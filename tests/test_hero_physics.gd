extends GutTest
## T-114: физика airborne/walk/land: большие delta, границы, инварианты.


func _inside(ctx: HeroContext) -> bool:
	var r: Rect2 = ctx.body_rect()
	var b: Rect2 = ctx.bounds
	var eps: float = 0.001
	return r.position.x >= b.position.x - eps and r.end.x <= b.end.x + eps \
		and r.position.y >= b.position.y - eps and r.end.y <= b.end.y + eps


func _falling(ctx: HeroContext) -> HeroStateMachine:
	var m := HeroStateMachine.new(ctx)
	m.start(HeroState.FALL)
	return m


func test_free_fall_integrates_gravity() -> void:
	var ctx: HeroContext = HeroFixture.context(1, Rect2(0, 0, 800, 5000))
	ctx.pos = Vector2(400, 100)
	var m: HeroStateMachine = _falling(ctx)
	m.update(0.1)
	assert_almost_eq(ctx.velocity.y, 140.0, 0.001)
	assert_almost_eq(ctx.pos.y, 100.0 + 14.0, 0.001)


func test_fall_speed_capped() -> void:
	var ctx: HeroContext = HeroFixture.context(1, Rect2(0, 0, 800, 100000))
	ctx.pos = Vector2(400, 100)
	var m: HeroStateMachine = _falling(ctx)
	HeroFixture.run(m, 5.0)
	assert_eq(ctx.velocity.y, ctx.balance.max_fall_speed)


func test_huge_delta_lands_on_floor_not_below() -> void:
	var ctx: HeroContext = HeroFixture.context()
	ctx.pos = Vector2(400, 100)
	var m: HeroStateMachine = _falling(ctx)
	m.update(1000.0)
	assert_eq(m.current_id(), HeroState.LAND)
	assert_eq(ctx.pos.y, ctx.floor_y())
	assert_true(_inside(ctx))


func test_huge_delta_with_horizontal_speed_stays_in_bounds() -> void:
	var ctx: HeroContext = HeroFixture.context()
	ctx.pos = Vector2(400, 300)
	ctx.velocity = Vector2(2400.0, -2400.0)
	var m: HeroStateMachine = _falling(ctx)
	m.transition(HeroState.THROWN)
	ctx.velocity = Vector2(2400.0, -2400.0)
	m.update(500.0)
	assert_true(_inside(ctx), "pos=%s" % ctx.pos)
	assert_true(is_finite(ctx.pos.x) and is_finite(ctx.pos.y))


func test_wall_bounce_left_and_right() -> void:
	var ctx: HeroContext = HeroFixture.context()
	ctx.pos = Vector2(100, 300)
	ctx.velocity = Vector2(-1000.0, 0.0)
	var m: HeroStateMachine = _falling(ctx)
	m.update(0.2)
	assert_eq(ctx.pos.x, 28.0, "прижат к левой стене")
	assert_almost_eq(ctx.velocity.x, 400.0, 0.001, "отскок с wall_restitution = 0.4")
	ctx.pos = Vector2(700, 300)
	ctx.velocity = Vector2(1000.0, 0.0)
	m.update(0.2)
	assert_eq(ctx.pos.x, 772.0)
	assert_lt(ctx.velocity.x, 0.0)


func test_ceiling_bounce() -> void:
	var ctx: HeroContext = HeroFixture.context()
	ctx.pos = Vector2(400, 90)
	ctx.velocity = Vector2(0.0, -1000.0)
	var m: HeroStateMachine = _falling(ctx)
	m.update(0.1)
	assert_eq(ctx.pos.y, 80.0, "голова у потолка")
	assert_gt(ctx.velocity.y, 0.0, "отскок вниз")


func test_hard_landing_from_height() -> void:
	var ctx: HeroContext = HeroFixture.context(1, Rect2(0, 0, 800, 2000))
	ctx.pos = Vector2(400, 80)
	var m: HeroStateMachine = _falling(ctx)
	var hard: Array[float] = []
	ctx.hard_landed.connect(func(s: float) -> void: hard.append(s))
	HeroFixture.run(m, 5.0)
	assert_eq(hard.size(), 1)
	assert_gte(hard[0], ctx.balance.hard_landing_speed)
	assert_lte(hard[0], ctx.balance.max_fall_speed)


func test_soft_landing_from_center_of_default_area() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = _falling(ctx)
	var soft: Array[int] = [0]
	var hard: Array[int] = [0]
	ctx.soft_landed.connect(func() -> void: soft[0] += 1)
	ctx.hard_landed.connect(func(_s: float) -> void: hard[0] += 1)
	HeroFixture.run(m, 3.0)
	assert_eq([soft[0], hard[0]], [1, 0], "падение с ~260 px: sqrt(2*1400*260) ~ 853 < 1000")


func test_narrow_area_centers_hero() -> void:
	var ctx: HeroContext = HeroFixture.context(1, Rect2(100, 0, 40, 600))
	ctx.pos = Vector2(100, 300)
	ctx.velocity = Vector2(800, 0)
	var m: HeroStateMachine = _falling(ctx)
	m.update(0.1)
	assert_eq(ctx.pos.x, 120.0)
	assert_eq(ctx.velocity.x, 0.0)


func test_area_shorter_than_hero_does_not_explode() -> void:
	var ctx: HeroContext = HeroFixture.context(1, Rect2(0, 0, 800, 50))
	var m: HeroStateMachine = _falling(ctx)
	HeroFixture.run(m, 2.0)
	assert_true(is_finite(ctx.pos.y))
	assert_eq(ctx.pos.y, ctx.floor_y())


func test_clamp_pos_inside_stays() -> void:
	var ctx: HeroContext = HeroFixture.context()
	assert_eq(ctx.clamp_pos(Vector2(400, 400)), Vector2(400, 400))
	assert_eq(ctx.clamp_pos(Vector2(-10, 9999)), Vector2(28, 600))
	assert_eq(ctx.clamp_pos(Vector2(9999, -9999)), Vector2(772, 80))


func test_set_bounds_pulls_x_inside_and_keeps_y() -> void:
	var ctx: HeroContext = HeroFixture.context()
	ctx.pos = Vector2(700, 300)
	ctx.set_bounds(Rect2(0, 0, 400, 600))
	assert_eq(ctx.pos.x, 372.0)
	assert_eq(ctx.pos.y, 300.0, "y выше пола не трогается")


func test_set_bounds_floor_raised_pulls_y() -> void:
	var ctx: HeroContext = HeroFixture.context()
	ctx.pos = Vector2(400, 600)
	ctx.set_bounds(Rect2(0, 0, 800, 400))
	assert_eq(ctx.pos.y, 400.0)


func test_set_bounds_shifted_origin_second_monitor() -> void:
	var ctx: HeroContext = HeroFixture.context()
	ctx.set_bounds(Rect2(1920, 25, 1920, 1000))
	assert_eq(ctx.pos.x, 1948.0)
	assert_eq(ctx.pos.x, 1920.0 + 28.0, "втянут к левой стене нового монитора")


func test_place_at_center_inside_bounds() -> void:
	for r: Rect2 in [Rect2(0, 0, 800, 600), Rect2(-1920, 100, 1920, 1000), Rect2(0, 0, 30, 30)]:
		var ctx := HeroContext.new(HeroFixture.balance(), HeroFixture.rng())
		ctx.set_bounds(r)
		ctx.place_at_center()
		assert_true(is_finite(ctx.pos.x) and is_finite(ctx.pos.y))
		if r.size.x >= 56.0 and r.size.y >= 80.0:
			assert_true(_inside(ctx), str(r))


func test_land_horizontal_slide_stops_at_wall() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.pos.x = 770.0
	m.transition(HeroState.FALL)
	ctx.last_impact_speed = 10.0
	ctx.velocity = Vector2(2000.0, 0.0)
	m.transition(HeroState.LAND)
	m.update(0.05)
	assert_lte(ctx.pos.x, 772.0)
	assert_true(_inside(ctx))


func test_land_large_delta_friction_not_negative() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	m.transition(HeroState.FALL)
	ctx.last_impact_speed = 10.0
	ctx.velocity = Vector2(100.0, 0.0)
	m.transition(HeroState.LAND)
	m.update(10.0)
	assert_gte(ctx.velocity.x, 0.0, "1 - friction*dt при большом dt не меняет знак скорости")


func test_walk_large_delta_stays_inside() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	m.transition(HeroState.WALK)
	(m.get_state(HeroState.WALK) as WalkState).remaining_px = 1.0e9
	for i in 20:
		m.update(100.0)
		assert_true(_inside(ctx), "шаг %d pos=%s" % [i, ctx.pos])
		if m.current_id() != HeroState.WALK:
			break


func test_walk_phase_stays_in_unit_interval() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	m.transition(HeroState.WALK)
	(m.get_state(HeroState.WALK) as WalkState).remaining_px = 1.0e9
	for i in 500:
		m.update(0.033)
		assert_between(ctx.walk_phase, 0.0, 1.0)


func test_walk_never_leaves_area_over_long_run() -> void:
	var ctx: HeroContext = HeroFixture.context(11, Rect2(0, 0, 300, 200))
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	var bad: int = 0
	var walked: float = 0.0
	for i in 40000:
		var before: float = ctx.pos.x
		m.update(1.0 / 30.0)
		if not _inside(ctx):
			bad += 1
		walked += absf(ctx.pos.x - before)
		# Ускоряем жизнь: не ждём 15..45 с паузы.
		if m.current_id() == HeroState.IDLE and i % 30 == 0:
			(m.get_state(HeroState.IDLE) as IdleState).remaining_sec = 0.0
	assert_eq(bad, 0, "выходов за границы")
	assert_gt(walked, 1000.0, "герой реально ходил")


func test_random_inputs_fuzz_keeps_hero_in_bounds_and_contour() -> void:
	var ctx: HeroContext = HeroFixture.context(21, Rect2(0, 0, 640, 480))
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	var fuzz := HeroFixture.rng(99)
	var now: float = 0.0
	var outside: int = 0
	var no_contour: int = 0
	var nonfinite: int = 0
	for i in 20000:
		var dt: float = fuzz.randf_range(0.001, 0.05)
		now += dt
		match fuzz.randi() % 12:
			0:
				m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, ctx.pos + Vector2(fuzz.randf_range(-40, 40), fuzz.randf_range(-90, 10)), now))
			1, 2, 3:
				m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, Vector2(fuzz.randf_range(-300, 900), fuzz.randf_range(-300, 800)), now))
			4:
				m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, Vector2(fuzz.randf_range(-300, 900), fuzz.randf_range(-300, 800)), now))
			5:
				if fuzz.randf() < 0.3:
					m.handle_input(HeroInput.make(HeroInput.Kind.CANCEL, Vector2.ZERO, now))
			6:
				if fuzz.randf() < 0.1:
					m.handle_input(HeroInput.make(HeroInput.Kind.RESYNC, Vector2(fuzz.randf_range(-3000, 3000), fuzz.randf_range(-3000, 3000)), now))
			_:
				pass
		# max_step_sec ограничивает delta в Hero; здесь иногда даём и больше.
		m.update(dt if fuzz.randf() > 0.01 else 3.0)
		ctx.update_contour(false)
		if not is_finite(ctx.pos.x) or not is_finite(ctx.pos.y) or not is_finite(ctx.velocity.x) or not is_finite(ctx.velocity.y):
			nonfinite += 1
		var r: Rect2 = ctx.body_rect()
		if r.position.x < -0.001 or r.end.x > 640.001 or r.position.y < -0.001 or r.end.y > 480.001:
			outside += 1
		if not ctx.contour_rect().encloses(r):
			no_contour += 1
	assert_eq(nonfinite, 0)
	assert_eq(outside, 0, "тело вышло за границы")
	assert_eq(no_contour, 0, "тело вышло из контура после update_contour")


func test_contour_encloses_body_and_throttles() -> void:
	var ctx: HeroContext = HeroFixture.context()
	assert_true(ctx.update_contour(false), "первая публикация")
	assert_true(ctx.contour_rect().encloses(ctx.body_rect()))
	ctx.pos.x += 3.0
	assert_false(ctx.update_contour(false), "сдвиг 3 < шаг 6")
	assert_true(ctx.contour_rect().encloses(ctx.body_rect()), "запас 6 покрывает сдвиг 3")
	ctx.pos.x += 3.0
	assert_true(ctx.update_contour(false), "сдвиг 6 = шагу: пересчёт")
	assert_true(ctx.update_contour(true), "force всегда пересчитывает")


func test_contour_republished_when_body_escapes_it() -> void:
	var ctx: HeroContext = HeroFixture.context()
	ctx.update_contour(true)
	ctx.pos.y -= 5.9
	ctx.pos.x += 5.9
	assert_false(ctx.update_contour(false))
	assert_true(ctx.contour_rect().encloses(ctx.body_rect()))
