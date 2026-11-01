extends GutTest
## T-215: HeroBalance.validation_errors: каждое правило паутины ловит нарушение, а исходный баланс корректен.

const POSITIVE: Array[String] = [
	"rope_substep_sec", "rope_rest_speed", "rope_rest_stretch_px", "web_max_length_px", "web_min_height_px",
	"web_shot_speed", "swing_reel_speed", "swing_anchor_dx_min_px", "swing_anchor_dx_max_px", "swing_min_room_px",
	"swing_max_sec", "thread_stiffness", "thread_ascend_speed", "thread_descend_speed", "thread_max_stretch_px",
	"thread_grab_zone_px", "hang_rest_min_sec", "hang_rest_max_sec", "web_trip_min_interval_sec", "weave_step_sec",
	"weave_walk_max_px", "corner_web_radius_px", "web_fall_sec", "sweep_min_speed", "sweep_hit_px",
	"web_release_fade_sec", "weave_idle_sec", "swing_release_angle_max_rad", "rope_grip_height_ratio", "swing_safe_impact_ratio",
	"web_stage_timeout_sec", "swing_safe_height_margin", "swing_release_start_ratio",
]
const NON_NEGATIVE: Array[String] = [
	"web_shoot_windup_sec", "swing_damping", "swing_floor_clearance_px", "swing_release_angle_min_rad",
	"swing_lean_max_rad", "thread_damping", "thread_sway_damping", "thread_snap_extra_px", "hang_top_gap_px",
	"descent_anchor_jitter_px",
]
const FRACTIONS: Array[String] = [
	"web_trip_chance", "web_wall_anchor_chance", "sweep_clear_ratio", "hang_rest_ratio_min", "hang_rest_ratio_max", "web_descent_chance",
	"web_wall_anchor_zone_ratio", "swing_safe_height_margin", "swing_release_start_ratio", "hang_default_rest_ratio",
	"rope_grip_height_ratio", "swing_safe_impact_ratio",
]


func _has(errors: PackedStringArray, key: String) -> bool:
	for e: String in errors:
		if e.contains(key):
			return true
	return false


func test_shipped_balance_valid_and_calm_balance_valid() -> void:
	assert_true(HeroFixture.balance().is_valid(), str(HeroFixture.balance().validation_errors()))
	assert_true(HeroFixture.calm_balance().is_valid())


func test_each_positive_field_rejects_zero_and_negative() -> void:
	for key: String in POSITIVE:
		for bad: float in [0.0, -1.0]:
			var b: HeroBalance = HeroFixture.balance()
			b.set(key, bad)
			assert_true(_has(b.validation_errors(), key), "%s = %s должно быть ошибкой" % [key, bad])


func test_each_non_negative_field_rejects_negative_and_accepts_zero() -> void:
	for key: String in NON_NEGATIVE:
		var b: HeroBalance = HeroFixture.balance()
		b.set(key, -0.001)
		assert_true(_has(b.validation_errors(), key), "%s < 0 ошибка" % key)
		b.set(key, 0.0)
		assert_false(_has(b.validation_errors(), "%s must not be negative" % key), "%s = 0 допустим" % key)


func test_each_fraction_rejects_outside_unit_range() -> void:
	for key: String in FRACTIONS:
		for bad: float in [-0.01, 1.01]:
			var b: HeroBalance = HeroFixture.balance()
			b.set(key, bad)
			assert_true(_has(b.validation_errors(), key), "%s = %s вне 0..1" % [key, bad])
		var ok: HeroBalance = HeroFixture.balance()
		ok.set(key, 1.0)
		assert_false(_has(ok.validation_errors(), "%s must be in 0..1" % key), "%s = 1 допустимо" % key)


func test_ordering_rules() -> void:
	var cases: Array[Array] = [
		["swing_anchor_dx_min_px", 600.0, "swing_anchor_dx_min_px > swing_anchor_dx_max_px"],
		["swing_release_angle_min_rad", 0.9, "swing_release_angle_min_rad > swing_release_angle_max_rad"],
		["hang_rest_ratio_min", 0.8, "hang_rest_ratio_min > hang_rest_ratio_max"],
		["hang_rest_min_sec", 30.0, "hang_rest_min_sec > hang_rest_max_sec"],
		["rope_substep_sec", 0.06, "rope_substep_sec > max_step_sec"],
	]
	for c: Array in cases:
		var b: HeroBalance = HeroFixture.balance()
		b.set(c[0], c[1])
		assert_true(_has(b.validation_errors(), c[2]), c[2])
		var ok: HeroBalance = HeroFixture.balance()
		assert_false(_has(ok.validation_errors(), c[2]))


func test_stability_rules() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.thread_stiffness = 0.5 * 0.5 / (b.rope_substep_sec * b.rope_substep_sec) * 1.01
	assert_true(_has(b.validation_errors(), "thread_stiffness"), "пружина слишком жёсткая для подшага")
	b = HeroFixture.balance()
	b.swing_damping = 1.0 / b.rope_substep_sec
	assert_true(_has(b.validation_errors(), "damping"), "затухание swing съедает скорость за подшаг")
	b = HeroFixture.balance()
	b.thread_sway_damping = 2.0 / b.rope_substep_sec
	assert_true(_has(b.validation_errors(), "damping"))


func test_counts_rules() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.weave_steps = 0
	assert_true(_has(b.validation_errors(), "weave_steps"))
	b = HeroFixture.balance()
	b.weave_steps = 1
	assert_false(_has(b.validation_errors(), "weave_steps"))
	b = HeroFixture.balance()
	b.web_sag_points = 1
	assert_true(_has(b.validation_errors(), "web_sag_points"))
	b = HeroFixture.balance()
	b.web_sag_points = 2
	assert_false(_has(b.validation_errors(), "web_sag_points"))


func test_hard_landing_speed_must_be_positive() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.hard_landing_speed = 0.0
	assert_true(_has(b.validation_errors(), "hard_landing_speed"))


func test_invalid_balance_does_not_crash_planner() -> void:
	# мусорный баланс не должен вешать планировщик (проверка защит делением и пустых диапазонов)
	var ctx: HeroContext = HeroFixture.web_context()
	ctx.balance.web_trip_chance = 1.0
	ctx.balance.swing_anchor_dx_min_px = 600.0
	ctx.balance.swing_anchor_dx_max_px = 100.0
	for i: int in 20:
		ctx.web_cooldown_sec = 0.0
		ctx.planner.decide(ctx)
	assert_false(ctx.balance.is_valid())


func test_nan_fraction_rejected() -> void:
	for key: String in ["web_descent_chance", "hang_default_rest_ratio", "web_wall_anchor_zone_ratio"]:
		var b: HeroBalance = HeroFixture.balance()
		b.set(key, NAN)
		assert_true(_has(b.validation_errors(), key), "%s = NaN ошибка" % key)


func test_substep_lower_bound() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.rope_substep_sec = HeroBalance.MIN_ROPE_SUBSTEP_SEC * 0.5
	assert_true(_has(b.validation_errors(), "rope_substep_sec must be >="), "слишком мелкий подшаг")
	b.rope_substep_sec = HeroBalance.MIN_ROPE_SUBSTEP_SEC
	assert_false(_has(b.validation_errors(), "rope_substep_sec must be >="), "ровно на границе допустим")
