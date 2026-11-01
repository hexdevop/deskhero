extends GutTest
## T-215: Overlay: cursor_is_valid, опрос курсора только по запросу героя, is_fast и motion_fps.
## Overlay создаётся в дереве теста; глобальные настройки движка и окна, которые он меняет, возвращаются в after_each.

var _saved_max_fps: int = 0
var _saved_low_proc: bool = false
var _saved_sleep: int = 0
var _saved_win_pos: Vector2i = Vector2i.ZERO
var _saved_win_size: Vector2i = Vector2i.ZERO
var _saved_polygon: PackedVector2Array = PackedVector2Array()


func before_each() -> void:
	_saved_max_fps = Engine.max_fps
	_saved_low_proc = OS.low_processor_usage_mode
	_saved_sleep = OS.low_processor_usage_mode_sleep_usec
	var w: Window = get_window()
	_saved_win_pos = w.position
	_saved_win_size = w.size
	_saved_polygon = w.mouse_passthrough_polygon


func after_each() -> void:
	Engine.max_fps = _saved_max_fps
	OS.low_processor_usage_mode = _saved_low_proc
	OS.low_processor_usage_mode_sleep_usec = _saved_sleep
	var w: Window = get_window()
	w.position = _saved_win_pos
	w.size = _saved_win_size
	w.mouse_passthrough_polygon = _saved_polygon


func _overlay() -> Overlay:
	var o := Overlay.new()
	o.config = load("res://resources/overlay_config.tres") as OverlayConfig
	add_child_autofree(o)
	return o


# --- cursor_is_valid

func test_origin_probe_is_invalid_even_inside_window() -> void:
	assert_false(Overlay.cursor_is_valid(Vector2i(0, 0), Rect2i(0, 0, 1920, 1080)), "(0, 0) — ответ «вне экранов» (D-009)")
	assert_false(Overlay.cursor_is_valid(Vector2i(0, 0), Rect2i(-100, -100, 500, 500)))


func test_probe_inside_window_is_valid() -> void:
	assert_true(Overlay.cursor_is_valid(Vector2i(10, 10), Rect2i(0, 0, 1920, 1080)))
	assert_true(Overlay.cursor_is_valid(Vector2i(1, 0), Rect2i(0, 0, 1920, 1080)))
	assert_true(Overlay.cursor_is_valid(Vector2i(0, 1), Rect2i(0, 0, 1920, 1080)))
	assert_true(Overlay.cursor_is_valid(Vector2i(1919, 1079), Rect2i(0, 0, 1920, 1080)))


func test_probe_outside_window_is_invalid() -> void:
	var win := Rect2i(100, 50, 800, 600)
	assert_false(Overlay.cursor_is_valid(Vector2i(99, 100), win))
	assert_false(Overlay.cursor_is_valid(Vector2i(100, 49), win))
	assert_false(Overlay.cursor_is_valid(Vector2i(900, 100), win), "правый край исключён")
	assert_false(Overlay.cursor_is_valid(Vector2i(200, 650), win), "нижний край исключён")
	assert_false(Overlay.cursor_is_valid(Vector2i(5000, 5000), win))
	assert_false(Overlay.cursor_is_valid(Vector2i(-5, -5), win))


func test_probe_on_second_monitor_window_origin_is_valid() -> void:
	var win := Rect2i(1920, 0, 1920, 1080)
	assert_true(Overlay.cursor_is_valid(Vector2i(1920, 0), win), "левый верхний угол второго монитора — не (0, 0)")
	assert_false(Overlay.cursor_is_valid(Vector2i(0, 0), win))
	assert_true(Overlay.cursor_is_valid(Vector2i(3839, 1079), win))


func test_probe_with_negative_monitor_coordinates() -> void:
	var win := Rect2i(-1920, -200, 1920, 1080)
	assert_true(Overlay.cursor_is_valid(Vector2i(-1000, 500), win))
	assert_true(Overlay.cursor_is_valid(Vector2i(-1920, -200), win))
	assert_false(Overlay.cursor_is_valid(Vector2i(0, 0), win), "(0, 0) вне окна и ещё и недействителен")
	assert_false(Overlay.cursor_is_valid(Vector2i(-1921, 0), win))


func test_probe_with_empty_window_rect_is_invalid() -> void:
	assert_false(Overlay.cursor_is_valid(Vector2i(5, 5), Rect2i(0, 0, 0, 0)))
	assert_false(Overlay.cursor_is_valid(Vector2i(5, 5), Rect2i(0, 0, 0, 100)))


# --- опрос по запросу

func test_cursor_timer_does_not_run_without_request() -> void:
	var o: Overlay = _overlay()
	assert_false(o.is_polling_cursor(), "после _ready опроса нет")


func test_cursor_timer_follows_requests() -> void:
	var o: Overlay = _overlay()
	EventBus.cursor_watch_requested.emit(true)
	assert_true(o.is_polling_cursor())
	EventBus.cursor_watch_requested.emit(false)
	assert_false(o.is_polling_cursor())
	EventBus.cursor_watch_requested.emit(false)
	assert_false(o.is_polling_cursor(), "повторное выключение безопасно")


func test_cursor_timer_repeat_request_does_not_restart_it() -> void:
	var o: Overlay = _overlay()
	EventBus.cursor_watch_requested.emit(true)
	var timer: Timer = o._cursor_timer
	timer.start(5.0)
	EventBus.cursor_watch_requested.emit(true)
	assert_gt(timer.time_left, 1.0, "запущенный таймер не перезапускается повторным запросом")
	EventBus.cursor_watch_requested.emit(false)


func test_cursor_timer_period_comes_from_config() -> void:
	var o: Overlay = _overlay()
	assert_almost_eq(o._cursor_timer.wait_time, o.config.cursor_poll_sec, 0.0001)
	assert_false(o._cursor_timer.one_shot, "опрос периодический")


func test_cursor_timer_is_stopped_when_overlay_frees() -> void:
	var o := Overlay.new()
	o.config = load("res://resources/overlay_config.tres") as OverlayConfig
	add_child(o)
	EventBus.cursor_watch_requested.emit(true)
	assert_true(o.is_polling_cursor())
	o.free()
	EventBus.cursor_watch_requested.emit(false)  # отписка при удалении: ошибок нет
	pass_test("запрос после удаления Overlay не падает")


func test_poll_emits_sample_and_headless_is_invalid() -> void:
	var o: Overlay = _overlay()
	if DisplayServer.get_name() != "headless":
		pending("позиция курсора реальная: проверяется только в headless")
		return
	watch_signals(EventBus)
	o._on_cursor_poll()
	assert_signal_emit_count(EventBus, "cursor_sampled", 1)
	assert_signal_emitted_with_parameters(EventBus, "cursor_sampled", [Vector2.ZERO, false])


# --- is_fast и FPS

func test_hero_state_is_fast_table() -> void:
	for id: StringName in [HeroState.SWING, HeroState.STRETCHED, HeroState.FALL, HeroState.THROWN, HeroState.CARRIED]:
		assert_true(HeroState.is_fast(id), "%s быстрое" % id)
	for id: StringName in [HeroState.HANG, HeroState.SHOOT_WEB, HeroState.WEAVE, HeroState.IDLE, HeroState.WALK,
			HeroState.LAND, HeroState.WEB, HeroState.ROOT, HeroState.GROUNDED, HeroState.AIRBORNE, HeroState.NONE]:
		assert_false(HeroState.is_fast(id), "%s не быстрое" % id)


func test_overlay_switches_to_motion_fps_for_swing_and_stretched_and_back() -> void:
	var o: Overlay = _overlay()
	var cfg: OverlayConfig = o.config
	Engine.max_fps = cfg.idle_fps
	EventBus.hero_state_changed.emit(HeroState.IDLE, HeroState.SWING)
	assert_eq(Engine.max_fps, cfg.motion_fps, "swing: motion_fps")
	EventBus.hero_state_changed.emit(HeroState.SWING, HeroState.FALL)
	assert_eq(Engine.max_fps, cfg.motion_fps)
	EventBus.hero_state_changed.emit(HeroState.FALL, HeroState.LAND)
	assert_eq(Engine.max_fps, cfg.idle_fps, "посадка: обратно в покой")
	EventBus.hero_state_changed.emit(HeroState.LAND, HeroState.HANG)
	assert_eq(Engine.max_fps, cfg.idle_fps, "hang: не быстрое")
	EventBus.hero_state_changed.emit(HeroState.HANG, HeroState.STRETCHED)
	assert_eq(Engine.max_fps, cfg.motion_fps, "stretched: motion_fps")
	EventBus.hero_state_changed.emit(HeroState.STRETCHED, HeroState.HANG)
	assert_eq(Engine.max_fps, cfg.idle_fps)


func test_overlay_weave_and_shoot_web_do_not_raise_fps() -> void:
	var o: Overlay = _overlay()
	var cfg: OverlayConfig = o.config
	Engine.max_fps = cfg.idle_fps
	EventBus.hero_state_changed.emit(HeroState.IDLE, HeroState.SHOOT_WEB)
	assert_eq(Engine.max_fps, cfg.idle_fps)
	EventBus.hero_state_changed.emit(HeroState.SHOOT_WEB, HeroState.WEAVE)
	assert_eq(Engine.max_fps, cfg.idle_fps)
	EventBus.hero_activity_changed.emit(true)
	assert_eq(Engine.max_fps, cfg.active_fps, "активный герой без быстрого движения: active_fps")
	EventBus.hero_activity_changed.emit(false)
	assert_eq(Engine.max_fps, cfg.idle_fps)
