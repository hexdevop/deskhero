extends GutTest
## T-114: Hero (мост) в сцене scenes/hero/hero.tscn. События строятся в тесте и подаются прямым вызовом _input
## и через EventBus, ОС не трогаем. Прошедшее время сна имитируем сдвигом приватных меток времени.

const SLEEP_SHIFT_USEC: int = 100000000  # 100 с: дольше любой паузы idle (15..45 с)

var _hero: Hero


func _spawn(units: float = 1.0) -> Hero:
	var h: Hero = (load("res://scenes/hero/hero.tscn") as PackedScene).instantiate() as Hero
	h.rng_seed = 11
	h.balance = HeroFixture.calm_balance()
	add_child_autofree(h)
	h.units_per_px = units
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 800 * units, 600 * units))
	return h


## Прогоняет кадры вручную (узел сам не крутится: тест без await) до сна.
func _settle(h: Hero) -> void:
	var guard: int = 0
	while not h.is_sleeping() and guard < 1000:
		h._process(0.016)
		guard += 1
	assert_true(h.is_sleeping(), "герой должен уснуть в покое")


## Ждёт по часам движка, а не по дельтам кадров: wait_seconds в headless может отдать на ~0.1 с меньше.
func _wait_real(sec: float) -> void:
	var start: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) / 1000000.0 < sec:
		await get_tree().process_frame


func _mouse(button: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = at
	return ev


func _on_hero(h: Hero) -> Vector2:
	return (h.get_context().pos + Vector2(0, -10)) * h.units_per_px


func test_first_bounds_start_fall_and_publish_contour() -> void:
	watch_signals(EventBus)
	_hero = _spawn()
	assert_eq(_hero.get_machine().current_id(), HeroState.FALL)
	assert_signal_emitted(EventBus, "hero_contour_changed")
	assert_signal_emitted_with_parameters(EventBus, "hero_activity_changed", [true])


func test_hero_falls_lands_and_sleeps_with_activity_false() -> void:
	watch_signals(EventBus)
	_hero = _spawn()
	_settle(_hero)
	assert_eq(_hero.get_machine().current_id(), HeroState.IDLE)
	assert_eq(_hero.get_context().pos.y, _hero.get_context().floor_y())
	assert_signal_emitted_with_parameters(EventBus, "hero_activity_changed", [false])
	assert_false(_hero.is_processing(), "в покое _process выключен")
	assert_false(_hero.get_node("WakeTimer").is_stopped(), "заведён один таймер на конец паузы")


func test_contour_encloses_body_at_rest() -> void:
	_hero = _spawn()
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	assert_true(ctx.contour_rect().encloses(ctx.body_rect()))


func test_units_per_px_two_scales_position_and_contour() -> void:
	watch_signals(EventBus)
	_hero = _spawn(2.0)
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	assert_eq(ctx.bounds, Rect2(0, 0, 800, 600), "границы переведены в lpx")
	assert_eq(_hero.position, ctx.pos * 2.0)
	var params: Array = get_signal_parameters(EventBus, "hero_contour_changed", get_signal_emit_count(EventBus, "hero_contour_changed") - 1)
	var rect: Rect2 = params[0]
	assert_eq(rect, Rect2(ctx.contour_rect().position * 2.0, ctx.contour_rect().size * 2.0), "контур опубликован в единицах Godot")


func test_empty_bounds_ignored() -> void:
	_hero = _spawn()
	var before: Rect2 = _hero.get_context().bounds
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 0, 600))
	assert_eq(_hero.get_context().bounds, before)


func test_bounds_before_first_valid_do_not_start() -> void:
	var h: Hero = (load("res://scenes/hero/hero.tscn") as PackedScene).instantiate() as Hero
	add_child_autofree(h)
	EventBus.world_bounds_changed.emit(Rect2())
	assert_eq(h.get_machine().current_id(), HeroState.NONE)


func test_input_before_start_ignored() -> void:
	var h: Hero = (load("res://scenes/hero/hero.tscn") as PackedScene).instantiate() as Hero
	add_child_autofree(h)
	h._input(_mouse(MOUSE_BUTTON_LEFT, true, Vector2(100, 100)))
	assert_eq(h.get_machine().current_id(), HeroState.NONE)


# --- сон и пробуждение

func test_wake_timeout_after_sleep_leads_idle_into_walk() -> void:
	_hero = _spawn()
	_settle(_hero)
	_hero._sleep_since_usec -= SLEEP_SHIFT_USEC
	_hero._on_wake_timeout()
	assert_eq(_hero.get_machine().current_id(), HeroState.WALK, "пауза закончилась за время сна: update(remaining) даёт walk")
	assert_false(_hero.is_sleeping())
	assert_true(_hero.is_processing(), "ходьба тикает каждый кадр")


func test_wake_timeout_before_pause_end_stays_asleep() -> void:
	_hero = _spawn()
	_settle(_hero)
	_hero._on_wake_timeout()  # прошло ничтожное время
	assert_eq(_hero.get_machine().current_id(), HeroState.IDLE)
	assert_true(_hero.is_sleeping())


func test_input_wakes_sleeping_hero() -> void:
	_hero = _spawn()
	_settle(_hero)
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, true, _on_hero(_hero)))
	assert_false(_hero.is_sleeping())
	assert_eq(_hero.get_machine().current_id(), HeroState.CARRIED)
	assert_true(_hero.is_processing() or _hero.get_machine().next_tick_sec() > 0.0)


func test_input_after_long_sleep_hands_elapsed_time_to_machine() -> void:
	_hero = _spawn()
	_settle(_hero)
	_hero._sleep_since_usec -= SLEEP_SHIFT_USEC
	# нажатие мимо контура сон не будит, нажатие на героя будит и сначала досчитывает паузу
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, true, _on_hero(_hero)))
	assert_eq(_hero.get_machine().current_id(), HeroState.CARRIED, "захват важнее ушедшей в walk паузы")


func test_press_outside_contour_does_not_wake() -> void:
	_hero = _spawn()
	_settle(_hero)
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, true, Vector2(5, 5)))
	assert_true(_hero.is_sleeping())
	assert_eq(_hero.get_machine().current_id(), HeroState.IDLE)


func test_bounds_change_wakes_sleeping_hero_when_floor_drops() -> void:
	_hero = _spawn()
	_settle(_hero)
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 800, 900))  # пол ниже
	assert_false(_hero.is_sleeping())
	assert_eq(_hero.get_machine().current_id(), HeroState.FALL)


func test_bounds_change_after_long_sleep_advances_pause() -> void:
	_hero = _spawn()
	_settle(_hero)
	_hero._sleep_since_usec -= SLEEP_SHIFT_USEC
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 800, 600))  # те же границы
	assert_eq(_hero.get_machine().current_id(), HeroState.WALK, "смена границ досчитала сон")


func test_bounds_change_keeps_hero_on_floor_when_floor_rises() -> void:
	_hero = _spawn()
	_settle(_hero)
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 800, 500))  # Dock вырос
	var ctx: HeroContext = _hero.get_context()
	assert_eq(ctx.pos.y, 500.0)
	assert_eq(_hero.position, ctx.pos)


# --- dev-выход: правая кнопка

func test_short_right_click_does_not_quit() -> void:
	_hero = _spawn()
	_settle(_hero)
	watch_signals(EventBus)
	var p: Vector2 = _on_hero(_hero)
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, true, p))
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, false, p))
	assert_signal_not_emitted(EventBus, "quit_requested")


func test_long_right_hold_on_hero_quits() -> void:  # реальное ожидание: счётчик движка отсчитывается от запуска, сдвигать метку нельзя
	_hero = _spawn()
	_settle(_hero)
	watch_signals(EventBus)
	var p: Vector2 = _on_hero(_hero)
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, true, p))
	await _wait_real(0.6)  # порог 0.5 с
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, false, p))
	assert_signal_emitted(EventBus, "quit_requested")


func test_long_right_hold_outside_hero_does_not_quit() -> void:
	_hero = _spawn()
	_settle(_hero)
	watch_signals(EventBus)
	var far: Vector2 = Vector2(5, 5)
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, true, far))
	assert_eq(_hero._right_down_usec, -1, "вне контура удержание не взводится")
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, false, far))
	assert_signal_not_emitted(EventBus, "quit_requested")


func test_right_press_outside_release_on_hero_does_not_quit() -> void:
	_hero = _spawn()
	_settle(_hero)
	watch_signals(EventBus)
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, true, Vector2(5, 5)))
	await _wait_real(0.6)
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, false, _on_hero(_hero)))
	assert_signal_not_emitted(EventBus, "quit_requested")


func test_right_release_without_press_does_not_quit() -> void:
	_hero = _spawn()
	_settle(_hero)
	watch_signals(EventBus)
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, false, _on_hero(_hero)))
	assert_signal_not_emitted(EventBus, "quit_requested")


func test_right_button_does_not_start_drag() -> void:
	_hero = _spawn()
	_settle(_hero)
	_hero._input(_mouse(MOUSE_BUTTON_RIGHT, true, _on_hero(_hero)))
	assert_eq(_hero.get_machine().current_id(), HeroState.IDLE)
	assert_true(_hero.is_sleeping())


func test_mouse_move_without_drag_does_not_wake() -> void:
	_hero = _spawn()
	_settle(_hero)
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = _on_hero(_hero)
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	_hero._input(ev)
	assert_true(_hero.is_sleeping())
