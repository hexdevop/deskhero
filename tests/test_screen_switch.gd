extends GutTest
## T-009: Overlay.screen_at_point / point_in_any. Переезд во время drag: Hero через _input и EventBus (T-114).

var _office: Array[Rect2i] = [Rect2i(0, 2160, 2940, 1912), Rect2i(2940, 0, 3840, 2160)]
var _two_hd: Array[Rect2i] = [Rect2i(1920, 0, 1920, 1080), Rect2i(0, 0, 1920, 1080)]


func test_office_inside_each() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(100, 3000), _office), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(4000, 500), _office), 1)


func test_office_edges_half_open() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(0, 2160), _office), 0, "левый верхний угол входит")
	assert_eq(Overlay.screen_at_point(Vector2i(2939, 4071), _office), 0, "последний пиксель входит")
	assert_eq(Overlay.screen_at_point(Vector2i(2940, 4071), _office), -1, "x = правая граница: вне")
	assert_eq(Overlay.screen_at_point(Vector2i(2939, 4072), _office), -1, "y = нижняя граница: вне")
	assert_eq(Overlay.screen_at_point(Vector2i(2940, 0), _office), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(2940, 2159), _office), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(2940, 2160), _office), -1, "угол стыка: y = нижняя граница экрана 1, x = правая граница экрана 0")


func test_office_outside_returns_minus_one() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(-1, 0), _office), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(100, 100), _office), -1, "над экраном 0, левее экрана 1")
	assert_eq(Overlay.screen_at_point(Vector2i(6780, 0), _office), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(0, 0), _office), -1, "(0,0), который отдаёт mouse_get_position вне экранов")


func test_office_margin_shrinks_both_sides() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(2935, 3000), _office, 8), -1, "5 px от правого края экрана 0 при margin 8")
	assert_eq(Overlay.screen_at_point(Vector2i(2931, 3000), _office, 8), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(2931, 3000), _office, 0), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(7, 3000), _office, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(8, 2168), _office, 8), 0, "ровно на внутренней границе")
	assert_eq(Overlay.screen_at_point(Vector2i(2945, 100), _office, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(2948, 8), _office, 8), 1)


func test_office_gap_between_screens_with_margin() -> void:
	# курсор в 3 px по обе стороны границы: ни один экран не выигрывает, остаёмся где были
	assert_eq(Overlay.screen_at_point(Vector2i(2937, 2200), _office, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(2943, 2100), _office, 8), -1)


func test_two_hd_primary_right() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(2000, 500), _two_hd), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(500, 500), _two_hd), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(1919, 0), _two_hd), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(1920, 0), _two_hd), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(-1, 500), _two_hd), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(3840, 500), _two_hd), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(500, 1080), _two_hd), -1)


func test_two_hd_margin_at_shared_border() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(1915, 500), _two_hd, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(1925, 500), _two_hd, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(1911, 500), _two_hd, 8), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(1912, 500), _two_hd, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(1928, 500), _two_hd, 8), 0)


func test_menu_bar_excluded_in_usable_rect() -> void:
	var usable: Array[Rect2i] = [Rect2i(0, 25, 1920, 1055), Rect2i(1920, 0, 1920, 1080)]
	assert_eq(Overlay.screen_at_point(Vector2i(500, 10), usable), -1, "меню-бар не принадлежит экрану")
	assert_eq(Overlay.screen_at_point(Vector2i(500, 25), usable), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(500, 30), usable, 8), -1, "margin считается от рабочей области")
	assert_eq(Overlay.screen_at_point(Vector2i(500, 33), usable, 8), 0)


func test_single_screen() -> void:
	var one: Array[Rect2i] = [Rect2i(0, 0, 1440, 900)]
	assert_eq(Overlay.screen_at_point(Vector2i(10, 10), one), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(1440, 10), one), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(10, 10), one, 20), -1)


func test_empty_list() -> void:
	var none: Array[Rect2i] = []
	assert_eq(Overlay.screen_at_point(Vector2i(10, 10), none), -1)
	assert_false(Overlay.point_in_any(Vector2i.ZERO, none))


func test_margin_degenerate() -> void:
	var one: Array[Rect2i] = [Rect2i(0, 0, 100, 100)]
	assert_eq(Overlay.screen_at_point(Vector2i(50, 50), one, 50), -1, "margin съедает область целиком")
	assert_eq(Overlay.screen_at_point(Vector2i(50, 50), one, 1000), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(0, 0), one, -5), 0, "отрицательный margin = 0")
	assert_eq(Overlay.screen_at_point(Vector2i(100, 100), one, -5), -1, "отрицательный margin не расширяет область")


func test_zero_size_rect_skipped() -> void:
	var rects: Array[Rect2i] = [Rect2i(0, 0, 0, 0), Rect2i(0, 0, 100, 100)]
	assert_eq(Overlay.screen_at_point(Vector2i(0, 0), rects), 1)


func test_overlapping_first_wins() -> void:
	var rects: Array[Rect2i] = [Rect2i(0, 0, 100, 100), Rect2i(50, 50, 100, 100)]
	assert_eq(Overlay.screen_at_point(Vector2i(60, 60), rects), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(120, 120), rects), 1)


func test_point_in_any() -> void:
	assert_true(Overlay.point_in_any(Vector2i(100, 3000), _office))
	assert_true(Overlay.point_in_any(Vector2i(4000, 500), _office))
	assert_false(Overlay.point_in_any(Vector2i(0, 0), _office))
	assert_false(Overlay.point_in_any(Vector2i(2940, 4072), _office))
	assert_true(Overlay.point_in_any(Vector2i(2940, 2159), _office))


# --- Hero: drag и переезд окна. События строятся в тесте и подаются прямым вызовом _input, ОС не трогаем.

var _hero: Hero


func _spawn_hero(units: float = 1.0) -> Hero:
	var h: Hero = (load("res://scenes/hero/hero.tscn") as PackedScene).instantiate() as Hero
	h.rng_seed = 5
	add_child_autofree(h)
	h.units_per_px = units
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 800 * units, 600 * units))
	return h


func _mouse(pressed: bool, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = at
	return ev


func _motion(at: Vector2, left_down: bool) -> InputEventMouseMotion:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = at
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if left_down else 0
	return ev


func _body_point(h: Hero) -> Vector2:
	return (h.get_context().pos + Vector2(0, -10)) * h.units_per_px


func _grab(h: Hero) -> void:
	h._input(_mouse(true, _body_point(h)))


func test_press_on_hero_starts_drag() -> void:
	_hero = _spawn_hero()
	watch_signals(EventBus)
	_grab(_hero)
	assert_eq(_hero.get_machine().current_id(), HeroState.CARRIED)
	assert_signal_emitted(EventBus, "hero_drag_started")


func test_resync_moves_hero_to_new_cursor_without_throw() -> void:
	_hero = _spawn_hero()
	_grab(_hero)
	_hero._input(_motion(_body_point(_hero) + Vector2(5, 0), true))
	EventBus.drag_cursor_resync.emit(Vector2(700, 300))  # окно переехало, курсор в новых координатах
	assert_eq(_hero.get_machine().current_id(), HeroState.CARRIED)
	var ctx: HeroContext = _hero.get_context()
	assert_eq(ctx.pos, ctx.clamp_pos(Vector2(700, 300) + ctx.grab_offset))
	_hero._input(_mouse(false, Vector2(700, 300)))
	assert_eq(_hero.get_machine().current_id(), HeroState.FALL, "скачок координат не стал броском")


func test_resync_with_scale_two_converts_to_lpx() -> void:
	_hero = _spawn_hero(2.0)
	_grab(_hero)
	EventBus.drag_cursor_resync.emit(Vector2(1000, 600))  # единицы Godot = 2 на lpx
	var ctx: HeroContext = _hero.get_context()
	assert_eq(ctx.pos, ctx.clamp_pos(Vector2(500, 300) + ctx.grab_offset))
	assert_eq(_hero.position, ctx.pos * 2.0)


func test_resync_without_drag_is_ignored() -> void:
	_hero = _spawn_hero()
	var before: Vector2 = _hero.get_context().pos
	EventBus.drag_cursor_resync.emit(Vector2(700, 300))
	assert_eq(_hero.get_context().pos, before)
	assert_ne(_hero.get_machine().current_id(), HeroState.CARRIED)


func test_cancel_request_drops_hero() -> void:
	_hero = _spawn_hero()
	watch_signals(EventBus)
	_grab(_hero)
	EventBus.drag_cancel_requested.emit()
	assert_eq(_hero.get_machine().current_id(), HeroState.FALL)
	assert_eq(_hero.get_context().velocity, Vector2.ZERO)
	assert_signal_emitted(EventBus, "hero_drag_ended")


func test_cancel_request_without_drag_is_ignored() -> void:
	_hero = _spawn_hero()
	var before: StringName = _hero.get_machine().current_id()
	EventBus.drag_cancel_requested.emit()
	assert_eq(_hero.get_machine().current_id(), before)


func test_drag_with_new_bounds_clamps_hero() -> void:
	_hero = _spawn_hero()
	_grab(_hero)
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 400, 300))  # меньший монитор
	_hero._input(_motion(Vector2(5000, 5000), true))
	var ctx: HeroContext = _hero.get_context()
	assert_eq(ctx.pos, Vector2(372, 300), "прижат к полу и правой стене нового монитора")


func test_motion_without_left_button_cancels_drag() -> void:
	_hero = _spawn_hero()
	_grab(_hero)
	_hero._input(_motion(Vector2(300, 300), false))  # отпускание потеряно
	assert_eq(_hero.get_machine().current_id(), HeroState.FALL)
