extends GutTest
## Overlay.target_fps: все комбинации active / moving_fast и порядок motion_fps / active_fps.


func _cfg(idle: int = 8, active: int = 30, motion: int = 60) -> OverlayConfig:
	var c := OverlayConfig.new()
	c.idle_fps = idle
	c.active_fps = active
	c.motion_fps = motion
	return c


func test_rest() -> void:
	assert_eq(Overlay.target_fps(_cfg(), false, false), 8)


func test_mouse_or_walk_active() -> void:
	assert_eq(Overlay.target_fps(_cfg(), true, false), 30)


func test_fast_wins_without_activity() -> void:
	assert_eq(Overlay.target_fps(_cfg(), false, true), 60)


func test_fast_and_active() -> void:
	assert_eq(Overlay.target_fps(_cfg(), true, true), 60)


func test_motion_below_active_is_raised_to_active() -> void:
	assert_eq(Overlay.target_fps(_cfg(8, 30, 20), false, true), 30)
	assert_eq(Overlay.target_fps(_cfg(8, 30, 20), true, true), 30)


func test_motion_equal_active() -> void:
	assert_eq(Overlay.target_fps(_cfg(8, 30, 30), false, true), 30)


func test_truth_table_ordering() -> void:
	var c: OverlayConfig = _cfg()
	var rest: int = Overlay.target_fps(c, false, false)
	var act: int = Overlay.target_fps(c, true, false)
	var fast: int = Overlay.target_fps(c, false, true)
	var both: int = Overlay.target_fps(c, true, true)
	assert_true(rest < act and act < fast)
	assert_eq(fast, both)


func test_shipped_config_values() -> void:
	var c: OverlayConfig = load("res://resources/overlay_config.tres") as OverlayConfig
	assert_not_null(c)
	assert_eq(Overlay.target_fps(c, false, false), c.idle_fps)
	assert_eq(Overlay.target_fps(c, true, false), c.active_fps)
	assert_eq(Overlay.target_fps(c, false, true), c.motion_fps)
	assert_true(c.motion_fps > c.active_fps and c.active_fps > c.idle_fps)


func test_shipped_sleep_does_not_cap_motion_fps() -> void:
	# движок берёт максимум из паузы и 1/max_fps: пауза не должна запирать motion_fps
	var c: OverlayConfig = load("res://resources/overlay_config.tres") as OverlayConfig
	var sleep_fps: float = 1.0e6 / float(c.low_processor_sleep_usec)
	assert_true(sleep_fps >= float(c.motion_fps) - 0.5, "sleep %d мкс = %.1f FPS < motion_fps %d" % [c.low_processor_sleep_usec, sleep_fps, c.motion_fps])


func test_result_inside_engine_limits_for_shipped_config() -> void:
	var c: OverlayConfig = load("res://resources/overlay_config.tres") as OverlayConfig
	for a: bool in [false, true]:
		for f: bool in [false, true]:
			var v: int = Overlay.target_fps(c, a, f)
			assert_true(v >= OverlayConfig.MIN_FPS and v <= OverlayConfig.MAX_FPS)
