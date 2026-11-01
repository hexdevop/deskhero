extends GutTest
## HeroPose.solve: чистый расчёт позы. Детерминизм, все позы, границы вытяжения и наклона.

const POSES: Array[StringName] = [&"idle", &"walk", &"fall", &"thrown", &"carried", &"land", &"unknown"]
const NEUTRAL := HeroEmotions.Emotion.NEUTRAL


func _solve(pose: StringName, facing: int = 1, motion: Vector2 = Vector2.ZERO, phase: float = 0.0,
		emo: HeroEmotions.Emotion = NEUTRAL, land_t: float = 0.0, impact: float = 0.0,
		breath: float = 0.0, clock: float = 0.0) -> HeroPose:
	var p := HeroPose.new()
	p.solve(pose, facing, phase, emo, motion, land_t, impact, breath, false, clock)
	return p


func _finite(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


func _assert_sane(p: HeroPose, label: String) -> void:
	assert_true(_finite(p.scale) and p.scale.x > 0.0 and p.scale.y > 0.0, "%s: scale %s" % [label, p.scale])
	assert_true(is_finite(p.lean) and is_finite(p.bob), "%s: lean/bob" % label)
	for v: Vector2 in [p.pivot, p.foot_near, p.foot_far, p.hand_near, p.hand_far, p.cape_dir, p.tuft_shift]:
		assert_true(_finite(v), "%s: not finite %s" % [label, v])
	assert_true(is_finite(p.cape_length) and p.cape_length > 0.0, "%s: cape_length %s" % [label, p.cape_length])
	assert_true(is_finite(p.cape_bend), "%s: cape_bend" % label)
	assert_almost_eq(p.cape_dir.length(), 1.0, 0.001, "%s: cape_dir normalized" % label)


func _same(a: HeroPose, b: HeroPose) -> bool:
	return a.scale == b.scale and a.lean == b.lean and a.pivot == b.pivot and a.bob == b.bob \
		and a.foot_near == b.foot_near and a.foot_far == b.foot_far \
		and a.hand_near == b.hand_near and a.hand_far == b.hand_far \
		and a.arms_crossed == b.arms_crossed and a.cape_dir == b.cape_dir \
		and a.cape_length == b.cape_length and a.cape_bend == b.cape_bend \
		and a.emotion == b.emotion and a.blink == b.blink and a.tuft_shift == b.tuft_shift


func test_deterministic_same_inputs_same_pose() -> void:
	for pose: StringName in POSES:
		var a: HeroPose = _solve(pose, -1, Vector2(-640.0, 310.0), 0.37, HeroEmotions.Emotion.SCARED, 0.4, 0.8, 0.5, 1.23)
		var b: HeroPose = _solve(pose, -1, Vector2(-640.0, 310.0), 0.37, HeroEmotions.Emotion.SCARED, 0.4, 0.8, 0.5, 1.23)
		assert_true(_same(a, b), "поза %s различается" % pose)


func test_reused_instance_has_no_leftover_state() -> void:
	# одна и та же поза после другой, на том же объекте, равна свежей
	var reused := HeroPose.new()
	reused.solve(&"thrown", 1, 0.0, NEUTRAL, Vector2(1200.0, -800.0), 0.0, 0.0, 0.0, false, 0.3)
	reused.solve(&"idle", 1, 0.0, NEUTRAL, Vector2.ZERO, 0.0, 0.0, 0.5, false, 0.0)
	assert_true(_same(reused, _solve(&"idle", 1, Vector2.ZERO, 0.0, NEUTRAL, 0.0, 0.0, 0.5)))


func test_all_poses_finite_and_sane() -> void:
	for pose: StringName in POSES:
		_assert_sane(_solve(pose, 1, Vector2(300.0, -200.0), 0.25, NEUTRAL, 0.5, 0.5, 0.5, 2.0), String(pose))
		_assert_sane(_solve(pose), String(pose) + " zero")


func test_all_poses_all_emotions() -> void:
	for pose: StringName in POSES:
		for emo: HeroEmotions.Emotion in [HeroEmotions.Emotion.NEUTRAL, HeroEmotions.Emotion.HAPPY,
				HeroEmotions.Emotion.SCARED, HeroEmotions.Emotion.OFFENDED]:
			var p: HeroPose = _solve(pose, 1, Vector2(100.0, 100.0), 0.1, emo)
			assert_eq(p.emotion, emo)
			_assert_sane(p, "%s/%d" % [pose, emo])


func test_offended_crosses_arms_only_idle_and_land() -> void:
	for pose: StringName in POSES:
		var p: HeroPose = _solve(pose, 1, Vector2.ZERO, 0.0, HeroEmotions.Emotion.OFFENDED)
		var expect: bool = pose == &"idle" or pose == &"land"
		assert_eq(p.arms_crossed, expect, String(pose))
	assert_false(_solve(&"idle").arms_crossed)


func test_blink_passthrough() -> void:
	var p := HeroPose.new()
	p.solve(&"idle", 1, 0.0, NEUTRAL, Vector2.ZERO, 0.0, 0.0, 0.0, true, 0.0)
	assert_true(p.blink)


func test_zero_motion_in_air_does_not_produce_nan() -> void:
	# v.normalized() от нуля в плаще не должен давать NaN
	for pose: StringName in [&"fall", &"thrown", &"carried"]:
		_assert_sane(_solve(pose, 1, Vector2.ZERO), String(pose))


func test_stretch_bounded_at_extreme_speed() -> void:
	var max_y: float = 1.0 + HeroLook.STRETCH_MAX
	for speed: float in [0.0, 100.0, HeroLook.STRETCH_REF_SPEED, 5000.0, 1.0e6, 1.0e9]:
		for pose: StringName in [&"fall", &"thrown"]:
			var p: HeroPose = _solve(pose, 1, Vector2(speed * 0.6, speed * 0.8))
			assert_true(p.scale.y <= max_y + 0.0001, "%s speed %s: scale.y %s" % [pose, speed, p.scale.y])
			assert_true(p.scale.y >= 1.0 - 0.0001, "%s: scale.y %s < 1" % [pose, p.scale.y])
			assert_true(p.scale.x > 0.0 and p.scale.x <= 1.0 + 0.0001, "%s: scale.x %s" % [pose, p.scale.x])


func test_stretch_monotonic_with_speed() -> void:
	var prev: float = 0.0
	for speed: float in [0.0, 200.0, 500.0, 900.0, 1400.0]:
		var p: HeroPose = _solve(&"thrown", 1, Vector2(0.0, speed))
		assert_true(p.scale.y >= prev - 0.00001, "вытяжение убывает на %s" % speed)
		prev = p.scale.y
	assert_almost_eq(prev, 1.0 + HeroLook.STRETCH_MAX, 0.0001, "на STRETCH_REF_SPEED полное вытяжение")


func test_lean_bounded_and_signed() -> void:
	var limits: Dictionary = {&"fall": HeroLook.LEAN_MAX_FALL, &"thrown": HeroLook.LEAN_MAX_THROWN,
		&"carried": HeroLook.LEAN_MAX_CARRIED}
	for pose: StringName in limits:
		var lim: float = limits[pose]
		for vx: float in [-1.0e9, -5000.0, -450.0, 0.0, 450.0, 5000.0, 1.0e9]:
			var p: HeroPose = _solve(pose, 1, Vector2(vx, 0.0))
			assert_true(absf(p.lean) <= lim + 0.0001, "%s vx %s: lean %s > %s" % [pose, vx, p.lean, lim])
			if vx > 0.0:
				assert_true(p.lean > 0.0, "%s: знак наклона" % pose)
			elif vx < 0.0:
				assert_true(p.lean < 0.0, "%s: знак наклона" % pose)
		assert_almost_eq(_solve(pose, 1, Vector2(1.0e9, 0.0)).lean, lim, 0.0001, "%s: насыщение" % pose)


func test_facing_mirrors_lean() -> void:
	# движение вперёд по facing даёт один и тот же наклон в осях рисунка
	for pose: StringName in [&"fall", &"thrown", &"carried"]:
		var right: HeroPose = _solve(pose, 1, Vector2(600.0, 100.0))
		var left: HeroPose = _solve(pose, -1, Vector2(-600.0, 100.0))
		assert_true(_same(right, left), "%s: зеркало по facing" % pose)


func test_walk_phase_wraps() -> void:
	var a: HeroPose = _solve(&"walk", 1, Vector2(100.0, 0.0), 0.3)
	var b: HeroPose = _solve(&"walk", 1, Vector2(100.0, 0.0), 1.3)
	assert_almost_eq(a.foot_near.x, b.foot_near.x, 0.001)
	assert_almost_eq(a.foot_far.y, b.foot_far.y, 0.001)
	assert_almost_eq(a.bob, b.bob, 0.001)


func test_walk_feet_within_stride_and_lift() -> void:
	for i: int in 41:
		var p: HeroPose = _solve(&"walk", 1, Vector2.ZERO, float(i) / 40.0)
		assert_true(absf(p.foot_near.x - (HeroLook.HIP_X + 1.0)) <= HeroLook.WALK_STRIDE + 0.001)
		assert_true(p.foot_near.y <= 0.0 and p.foot_near.y >= -HeroLook.WALK_LIFT - 0.001)
		assert_true(p.foot_far.y <= 0.0 and p.foot_far.y >= -HeroLook.WALK_LIFT - 0.001)
		assert_true(p.bob <= 0.0 and p.bob >= -HeroLook.WALK_BOB - 0.001)


func test_land_scale_bounded_for_any_input() -> void:
	var amp_max: float = HeroLook.SQUASH_HARD
	for t: float in [-5.0, 0.0, 0.1, 0.5, 0.99, 1.0, 7.0]:
		for impact: float in [-1.0, 0.0, 0.2, 0.35, 1.0, 5.0]:
			var p: HeroPose = _solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, t, impact)
			_assert_sane(p, "land t=%s i=%s" % [t, impact])
			assert_true(p.scale.y >= 1.0 - amp_max - 0.0001 and p.scale.y <= 1.0 + amp_max + 0.0001,
				"land t=%s i=%s scale.y %s" % [t, impact, p.scale.y])


func test_land_clamps_t_and_starts_squashed() -> void:
	assert_true(_same(_solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, -3.0, 0.5), _solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, 0.0, 0.5)))
	assert_true(_same(_solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, 9.0, 0.5), _solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, 1.0, 0.5)))
	var start: HeroPose = _solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, 0.0, 1.0)
	assert_true(start.scale.y < 1.0, "в начале посадки приседание")


func test_land_end_is_nearly_neutral() -> void:
	var end: HeroPose = _solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, 1.0, 1.0)
	assert_almost_eq(end.scale.y, 1.0, 0.02, "в конце посадки масштаб почти 1, нет скачка в idle")


func test_hard_squash_deeper_than_soft() -> void:
	var soft: HeroPose = _solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, 0.0, 0.0)
	var hard: HeroPose = _solve(&"land", 1, Vector2.ZERO, 0.0, NEUTRAL, 0.0, 1.0)
	assert_true(hard.scale.y < soft.scale.y)


func test_idle_breath_range() -> void:
	for b: float in [0.0, 0.5, 1.0]:
		var p: HeroPose = _solve(&"idle", 1, Vector2.ZERO, 0.0, NEUTRAL, 0.0, 0.0, b)
		assert_almost_eq(p.scale.y, 1.0 + HeroLook.BREATH_SCALE * b, 0.0001)
	assert_eq(_solve(&"idle").scale, Vector2.ONE)


func test_cape_length_grows_with_speed_but_bounded() -> void:
	var slow: HeroPose = _solve(&"fall", 1, Vector2(0.0, 10.0))
	var fast: HeroPose = _solve(&"fall", 1, Vector2(0.0, 1.0e9))
	assert_true(fast.cape_length >= slow.cape_length)
	assert_true(fast.cape_length <= HeroLook.CAPE_LENGTH + HeroLook.CAPE_WIND_LENGTH + 0.001)
	assert_eq(_solve(&"idle", 1, Vector2(900.0, 900.0)).cape_length, HeroLook.CAPE_LENGTH, "в idle ветра нет")
