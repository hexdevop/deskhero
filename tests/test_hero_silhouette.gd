extends GutTest
## HeroContext.silhouette_rect и land_progress/торможение LandState; Overlay.target_fps отдельно в test_overlay_fps.gd.

const AIR_POSES: Array[StringName] = [HeroState.FALL, HeroState.THROWN, HeroState.CARRIED]
const GROUND_POSES: Array[StringName] = [HeroState.IDLE, HeroState.WALK, HeroState.LAND]


func test_body_inside_silhouette_for_every_pose() -> void:
	var c: HeroContext = HeroFixture.context()
	for pose: StringName in AIR_POSES + GROUND_POSES:
		c.pose = pose
		var s: Rect2 = c.silhouette_rect()
		assert_true(s.encloses(c.body_rect()), "тело вне силуэта в %s: %s vs %s" % [pose, c.body_rect(), s])


func test_ground_margin_only_above() -> void:
	var c: HeroContext = HeroFixture.context()
	c.pose = HeroState.IDLE
	var b: Rect2 = c.body_rect()
	var s: Rect2 = c.silhouette_rect()
	var e: Vector2 = c.balance.silhouette_ground_extra_px
	assert_eq(s.position, Vector2(b.position.x - e.x, b.position.y - e.y))
	assert_eq(s.size, Vector2(b.size.x + e.x * 2.0, b.size.y + e.y))
	assert_eq(s.end.y, b.end.y, "низ силуэта совпадает с низом тела (ступни)")


func test_air_margin_larger_than_ground() -> void:
	var c: HeroContext = HeroFixture.context()
	c.pose = HeroState.IDLE
	var ground: Rect2 = c.silhouette_rect()
	for pose: StringName in AIR_POSES:
		c.pose = pose
		var air: Rect2 = c.silhouette_rect()
		var e: Vector2 = c.balance.silhouette_air_extra_px
		assert_true(air.encloses(ground), "%s: силуэт в воздухе не шире земного" % pose)
		assert_eq(air.size.x, c.body_rect().size.x + e.x * 2.0, String(pose))
		assert_eq(air.size.y, c.body_rect().size.y + e.y, String(pose))
		assert_eq(air.end.y, c.body_rect().end.y, "%s: запаса снизу нет" % pose)


func test_silhouette_follows_pos() -> void:
	var c: HeroContext = HeroFixture.context()
	c.pose = HeroState.FALL
	c.pos = Vector2(123.0, 456.0)
	var a: Rect2 = c.silhouette_rect()
	c.pos += Vector2(10.0, -5.0)
	assert_eq(c.silhouette_rect().position, a.position + Vector2(10.0, -5.0))
	assert_eq(c.silhouette_rect().size, a.size)


func test_contour_encloses_silhouette_after_update() -> void:
	var c: HeroContext = HeroFixture.context()
	for pose: StringName in AIR_POSES + GROUND_POSES:
		c.pose = pose
		c.update_contour(false)
		assert_true(c.contour_rect().encloses(c.silhouette_rect()), "контур не покрывает силуэт в %s" % pose)


func test_contour_republished_when_pose_grows_silhouette() -> void:
	var c: HeroContext = HeroFixture.context()
	c.pose = HeroState.IDLE
	c.update_contour(true)
	c.pose = HeroState.THROWN  # позиция не менялась, но силуэт вырос
	c.update_contour(false)
	assert_true(c.contour_rect().encloses(c.silhouette_rect()))


# --- LandState ---

func _landed(impact: float = 100.0, vx: float = 300.0) -> Array:
	var c: HeroContext = HeroFixture.context(1, Rect2(0.0, 0.0, 4000.0, 600.0))
	var m: HeroStateMachine = HeroFixture.grounded_machine(c)
	c.last_impact_speed = impact
	c.velocity = Vector2(vx, 0.0)
	m.transition(HeroState.LAND)
	return [c, m, m.get_state(HeroState.LAND) as LandState]


func test_land_progress_zero_on_enter() -> void:
	var r: Array = _landed()
	assert_eq((r[0] as HeroContext).land_progress, 0.0)


func test_land_progress_monotonic_and_clamped() -> void:
	var r: Array = _landed()
	var c: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	var prev: float = 0.0
	for i: int in 5:
		m.update(0.02)
		assert_true(c.land_progress >= prev and c.land_progress <= 1.0, "progress %s" % c.land_progress)
		prev = c.land_progress
	assert_almost_eq(prev, 0.02 * 5 / c.balance.land_soft_sec, 0.001, "линейно по времени")


func test_land_progress_hard_uses_hard_duration() -> void:
	var r: Array = _landed(5000.0)
	var c: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	m.update(0.15)
	assert_almost_eq(c.land_progress, 0.15 / c.balance.land_hard_sec, 0.001)
	assert_eq(m.current_id(), HeroState.LAND)


func test_land_progress_clamped_with_huge_delta_and_exits() -> void:
	var r: Array = _landed()
	var c: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	m.update(10.0)
	assert_eq(c.land_progress, 1.0)
	assert_eq(m.current_id(), HeroState.IDLE)


func test_land_progress_zero_duration_no_division_by_zero() -> void:
	var c: HeroContext = HeroFixture.context(1, Rect2(0.0, 0.0, 4000.0, 600.0))
	c.balance.land_soft_sec = 0.0
	var m: HeroStateMachine = HeroFixture.grounded_machine(c)
	c.last_impact_speed = 10.0
	m.transition(HeroState.LAND)
	m.update(0.016)
	assert_true(is_finite(c.land_progress))
	assert_eq(c.land_progress, 1.0)


func test_land_friction_stable_for_large_delta() -> void:
	var v0: float = 800.0
	var k: float = HeroFixture.balance().land_friction
	for dt: float in [1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0, 0.1, 0.25, 0.5, 1.0, 5.0]:
		var r: Array = _landed(100.0, v0)
		var c: HeroContext = r[0]
		var start_x: float = c.pos.x
		(r[2] as LandState).update(dt)
		assert_true(is_finite(c.velocity.x) and is_finite(c.pos.x), "dt %s: NaN/inf" % dt)
		assert_true(c.velocity.x >= 0.0 and c.velocity.x <= v0, "dt %s: скорость %s вне 0..v0" % [dt, c.velocity.x])
		var moved: float = c.pos.x - start_x
		assert_true(moved >= 0.0 and moved <= v0 / k + 0.001, "dt %s: сдвиг %s (макс. v0/k)" % [dt, moved])


func test_land_friction_matches_exponential() -> void:
	var r: Array = _landed(100.0, 600.0)
	var c: HeroContext = r[0]
	(r[2] as LandState).update(0.05)
	assert_almost_eq(c.velocity.x, 600.0 * exp(-c.balance.land_friction * 0.05), 0.001)


func test_land_friction_independent_of_frame_length() -> void:
	# скорость через 0.1 с не должна зависеть от разбивки на кадры
	var finals: Array[float] = []
	for steps: int in [1, 2, 5, 10]:
		var r: Array = _landed(100.0, 800.0)
		var c: HeroContext = r[0]
		for i: int in steps:
			(r[2] as LandState).update(0.1 / float(steps))
		finals.append(c.velocity.x)
	for f: float in finals:
		assert_almost_eq(f, finals[0], 0.01)


func test_land_negative_velocity_does_not_flip() -> void:
	var r: Array = _landed(100.0, -800.0)
	var c: HeroContext = r[0]
	(r[2] as LandState).update(1.0)
	assert_true(c.velocity.x <= 0.0 and c.velocity.x >= -800.0)


func test_land_decay_sets_velocity_to_zero_on_wall_and_stays_in_bounds() -> void:
	var c: HeroContext = HeroFixture.context(1, Rect2(0.0, 0.0, 400.0, 600.0))
	var m: HeroStateMachine = HeroFixture.grounded_machine(c)
	c.pos.x = c.bounds.end.x - c.balance.body_size_px.x * 0.5 - 1.0
	c.last_impact_speed = 10.0
	c.velocity = Vector2(5000.0, 0.0)
	m.transition(HeroState.LAND)
	m.update(1.0)
	assert_true(c.pos.x <= c.bounds.end.x - c.balance.body_size_px.x * 0.5 + 0.001)
	assert_eq(c.velocity.x, 0.0)


func test_land_enter_to_idle_has_small_velocity_jump() -> void:
	# баг T-117: скорость обрывалась с ~180 lpx/с до нуля. К моменту выхода остаток должен быть мал.
	var r: Array = _landed(100.0, 600.0)
	var c: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	var guard: int = 0
	while m.current_id() == HeroState.LAND and guard < 100:
		m.update(1.0 / 60.0)
		guard += 1
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_true(absf(c.velocity.x) < 600.0 * 0.06, "остаток скорости при выходе в idle: %s" % c.velocity.x)
