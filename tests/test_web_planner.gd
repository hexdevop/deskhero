extends GutTest
## T-215: WebPlanner: цели, обида, нет места, интервал вылазок, доля времени, чистые функции.

const DT: float = 1.0 / 30.0


func _trip_ctx(seed_value: int, bounds: Rect2 = HeroFixture.WEB_BOUNDS) -> HeroContext:
	var ctx: HeroContext = HeroFixture.web_context(seed_value, bounds)
	ctx.balance.web_trip_chance = 1.0
	return ctx


# --- decide

func test_chance_zero_always_walks_and_makes_no_plan() -> void:
	for sd: int in 50:
		var ctx: HeroContext = HeroFixture.web_context(sd)
		assert_eq(ctx.planner.decide(ctx), HeroState.WALK)
		assert_null(ctx.plan)
		assert_eq(ctx.web_cooldown_sec, 0.0)


func test_chance_one_gives_shoot_web_with_plan_and_cooldown() -> void:
	var shots: int = 0
	for sd: int in 100:
		var ctx: HeroContext = _trip_ctx(sd)
		var decision: StringName = ctx.planner.decide(ctx)
		if decision == HeroState.SHOOT_WEB:
			shots += 1
			assert_not_null(ctx.plan)
			assert_eq(ctx.web_cooldown_sec, ctx.balance.web_trip_min_interval_sec)
		else:
			assert_eq(decision, HeroState.WALK)
			assert_null(ctx.plan, "прогулка без плана")
	assert_gt(shots, 90, "в большой области почти всегда есть цель")


func test_same_seed_same_decisions() -> void:
	var a: HeroContext = _trip_ctx(77)
	var b: HeroContext = _trip_ctx(77)
	for i: int in 20:
		a.web_cooldown_sec = 0.0
		b.web_cooldown_sec = 0.0
		var da: StringName = a.planner.decide(a)
		var db: StringName = b.planner.decide(b)
		assert_eq(da, db)
		if a.plan != null:
			assert_eq(a.plan.kind, b.plan.kind)
			assert_eq(a.plan.anchor, b.plan.anchor)
			assert_eq(a.plan.swing_length, b.plan.swing_length)
			assert_eq(a.plan.rest_length, b.plan.rest_length)
		a.plan = null
		b.plan = null


func test_different_seeds_give_different_plans() -> void:
	var anchors: Dictionary = {}
	for sd: int in 30:
		var ctx: HeroContext = _trip_ctx(sd)
		ctx.planner.decide(ctx)
		if ctx.plan != null:
			anchors[ctx.plan.anchor] = true
	assert_gt(anchors.size(), 10)


func test_cooldown_blocks_trips_and_repeats_by_interval() -> void:
	var ctx: HeroContext = _trip_ctx(3)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.balance.web_trip_chance = 1.0  # grounded_machine гасит шанс: включаем после
	var first: StringName = ctx.planner.decide(ctx)
	assert_eq(first, HeroState.SHOOT_WEB)
	ctx.plan = null
	for i: int in 20:
		assert_eq(ctx.planner.decide(ctx), HeroState.WALK, "в кулдауне вылазок нет")
		assert_null(ctx.plan)
	ctx.tick_web(ctx.balance.web_trip_min_interval_sec - 1.0)
	assert_eq(ctx.planner.decide(ctx), HeroState.WALK, "за секунду до конца интервала всё ещё запрет")
	ctx.tick_web(1.0)
	assert_eq(ctx.web_cooldown_sec, 0.0)
	assert_eq(ctx.planner.decide(ctx), HeroState.SHOOT_WEB, "интервал прошёл: можно снова")
	assert_not_null(m)


func test_cooldown_not_consumed_when_no_target() -> void:
	var ctx: HeroContext = _trip_ctx(1, Rect2(0.0, 0.0, 1200.0, 200.0))  # ниже web_min_height_px
	assert_eq(ctx.planner.decide(ctx), HeroState.WALK)
	assert_null(ctx.plan)
	assert_eq(ctx.web_cooldown_sec, 0.0, "цели нет: интервал не тратится")


func test_idle_does_not_trip_while_sulking() -> void:
	var ctx: HeroContext = _trip_ctx(5)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.balance.web_trip_chance = 1.0
	ctx.emotions.offend()
	assert_true(ctx.is_sulking())
	var idle := m.get_state(HeroState.IDLE) as IdleState
	idle.remaining_sec = 0.0
	m.update(DT)
	assert_eq(m.current_id(), HeroState.IDLE, "обида запрещает и прогулку, и вылазку")
	assert_null(ctx.plan)
	assert_eq(m.next_tick_sec(), ctx.emotion_wake_sec(), "спит до конца обиды")


func test_after_sulk_ends_trip_possible_again() -> void:
	var ctx: HeroContext = _trip_ctx(5)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.balance.web_trip_chance = 1.0
	ctx.emotions.offend()
	(m.get_state(HeroState.IDLE) as IdleState).remaining_sec = 0.0
	m.update(ctx.balance.sulk_sec + 0.1)
	assert_false(ctx.is_sulking())
	m.update(DT)
	assert_ne(m.current_id(), HeroState.IDLE, "обида прошла: idle выбрал действие")


# --- нет цели

func test_no_target_when_window_too_low() -> void:
	for h: float in [100.0, 200.0, 259.0]:
		var ctx: HeroContext = _trip_ctx(1, Rect2(0.0, 0.0, 1200.0, h))
		assert_null(ctx.planner.swing_plan(ctx), "swing, высота %s" % h)
		assert_null(ctx.planner.descent_plan(ctx), "descent, высота %s" % h)
		assert_eq(ctx.planner.decide(ctx), HeroState.WALK)


func test_no_swing_when_room_too_small() -> void:
	var ctx: HeroContext = _trip_ctx(1, Rect2(0.0, 0.0, 400.0, 700.0))  # комнаты по бокам < swing_min_room_px
	assert_null(ctx.planner.swing_plan(ctx))
	# спуск в такой области возможен
	assert_not_null(ctx.planner.descent_plan(ctx))


func test_decide_in_narrow_area_never_swings() -> void:
	for sd: int in 100:
		var ctx: HeroContext = _trip_ctx(sd, Rect2(0.0, 0.0, 400.0, 700.0))
		ctx.planner.decide(ctx)
		if ctx.plan != null:
			assert_eq(ctx.plan.kind, WebPlan.Kind.DESCENT)


func test_descent_needs_room_above_top_gap() -> void:
	var b: Rect2 = Rect2(0.0, 0.0, 1200.0, 100.0)
	var ctx: HeroContext = _trip_ctx(1, b)
	assert_null(ctx.planner.descent_plan(ctx))


# --- границы планов

func test_swing_plans_inside_bounds_and_length_limit() -> void:
	var made: int = 0
	var sizes: Array[Rect2] = [Rect2(0, 0, 1200, 700), Rect2(0, 0, 800, 600), Rect2(100, 50, 1600, 900), Rect2(0, 0, 3000, 1400)]
	for bounds: Rect2 in sizes:
		for sd: int in 150:
			var ctx: HeroContext = _trip_ctx(sd, bounds)
			ctx.pos.x = ctx.rng.randf_range(bounds.position.x + 30.0, bounds.end.x - 30.0)
			var plan: WebPlan = ctx.planner.swing_plan(ctx)
			if plan == null:
				continue
			made += 1
			var b: HeroBalance = ctx.balance
			assert_true(bounds.grow(0.001).has_point(plan.anchor), "якорь внутри %s: %s" % [bounds, plan.anchor])
			assert_true(is_equal_approx(plan.anchor.y, bounds.position.y) or is_equal_approx(plan.anchor.x, bounds.position.x + 28.0) \
					or is_equal_approx(plan.anchor.x, bounds.end.x - 28.0) or plan.anchor.y > bounds.position.y, "якорь на верхнем или боковом краю или рядом")
			assert_lte(plan.anchor.distance_to(ctx.hand_pos()), b.web_max_length_px + 0.001, "длина выстрела в пределе")
			assert_gt(plan.swing_length, 0.0)
			assert_lt(plan.swing_length, ctx.floor_y() - plan.anchor.y, "нить короче высоты: зазор до пола")
			assert_lte(plan.release_angle, b.swing_release_angle_max_rad + 0.0001)
			assert_gt(plan.release_angle, 0.0)
			assert_eq(plan.kind, WebPlan.Kind.SWING)
			assert_eq(plan.stage, WebPlan.Stage.NONE)
			assert_false(plan.needs_walk())
	assert_gt(made, 100)


func test_swing_dx_within_configured_range_or_wall() -> void:
	for sd: int in 200:
		var ctx: HeroContext = _trip_ctx(sd)
		var plan: WebPlan = ctx.planner.swing_plan(ctx)
		if plan == null:
			continue
		var dx: float = absf(plan.anchor.x - ctx.pos.x)
		var on_wall: bool = plan.anchor.y > ctx.bounds.position.y + 0.001
		if not on_wall:
			assert_lte(dx, ctx.balance.swing_anchor_dx_max_px + 0.001)
			assert_gte(dx, ctx.balance.swing_anchor_dx_min_px - 0.001)


func test_swing_start_height_not_above_safe() -> void:
	for sd: int in 300:
		var ctx: HeroContext = _trip_ctx(sd)
		var plan: WebPlan = ctx.planner.swing_plan(ctx)
		if plan == null:
			continue
		var hand: Vector2 = ctx.hand_pos()
		var to_hand: Vector2 = hand - plan.anchor
		var start_hand: Vector2 = plan.anchor + to_hand.normalized() * minf(plan.swing_length, to_hand.length())
		var height: float = ctx.floor_y() - (start_hand.y + ctx.hand_offset().length())
		assert_lte(height, WebPlanner.safe_start_height(ctx.balance) + 0.5, "старт раскачки не выше безопасного, seed %d" % sd)


func test_descent_plans_inside_bounds() -> void:
	var made: int = 0
	for bounds: Rect2 in [Rect2(0, 0, 1200, 700), Rect2(0, 0, 300, 400), Rect2(40, 20, 900, 500)]:
		for sd: int in 100:
			var ctx: HeroContext = _trip_ctx(sd, bounds)
			ctx.pos.x = ctx.rng.randf_range(bounds.position.x + 28.0, bounds.end.x - 28.0)
			var plan: WebPlan = ctx.planner.descent_plan(ctx)
			if plan == null:
				continue
			made += 1
			var b: HeroBalance = ctx.balance
			assert_eq(plan.anchor.y, bounds.position.y, "якорь на верхнем краю")
			assert_gte(plan.anchor.x, bounds.position.x + 28.0 - 0.001)
			assert_lte(plan.anchor.x, bounds.end.x - 28.0 + 0.001)
			assert_lte(absf(plan.anchor.x - ctx.pos.x), b.descent_anchor_jitter_px + 0.001)
			var full: float = ctx.floor_y() - plan.anchor.y - ctx.hand_offset().length()
			assert_gte(plan.rest_length, b.hang_top_gap_px - 0.001)
			assert_lte(plan.rest_length, full + 0.001)
			assert_lte(plan.anchor.distance_to(ctx.hand_pos()), b.web_max_length_px + 0.001)
			assert_eq(plan.kind, WebPlan.Kind.DESCENT)
	assert_gt(made, 200)


func test_descent_too_far_for_max_length_returns_null() -> void:
	var ctx: HeroContext = _trip_ctx(1, Rect2(0.0, 0.0, 1200.0, 3000.0))
	assert_gt(ctx.floor_y() - ctx.hand_offset().length(), ctx.balance.web_max_length_px)
	assert_null(ctx.planner.descent_plan(ctx), "длиннее web_max_length_px: цели нет")


# --- чистые функции

func test_predicted_impact_free_fall() -> void:
	var b: HeroBalance = HeroFixture.balance()
	assert_almost_eq(WebPlanner.predicted_impact(Vector2(0, 500), Vector2.ZERO, 600.0, b.gravity, b.max_fall_speed),
			sqrt(2.0 * b.gravity * 100.0), 0.01)
	assert_almost_eq(WebPlanner.predicted_impact(Vector2(0, 600), Vector2(0, 300), 600.0, b.gravity, b.max_fall_speed), 300.0, 0.01, "у пола: текущая вертикальная скорость")
	assert_almost_eq(WebPlanner.predicted_impact(Vector2(0, 500), Vector2(900, -200), 600.0, b.gravity, b.max_fall_speed),
			sqrt(200.0 * 200.0 + 2.0 * b.gravity * 100.0), 0.01, "горизонталь не влияет, вверх считается")
	assert_eq(WebPlanner.predicted_impact(Vector2(0, 0), Vector2.ZERO, 100000.0, b.gravity, b.max_fall_speed), b.max_fall_speed, "потолок max_fall_speed")
	assert_almost_eq(WebPlanner.predicted_impact(Vector2(0, 700), Vector2(0, 100), 600.0, b.gravity, b.max_fall_speed), 100.0, 0.01, "ниже пола: падение 0")


func test_predicted_impact_matches_simulated_fall() -> void:
	for v: Vector2 in [Vector2(0, 0), Vector2(120, -300), Vector2(-80, 200)]:
		var ctx: HeroContext = HeroFixture.web_context(1)
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
		ctx.pos = Vector2(600.0, 200.0)
		ctx.velocity = v
		var predicted: float = WebPlanner.predicted_impact(ctx.pos, ctx.velocity, ctx.floor_y(), ctx.balance.gravity, ctx.balance.max_fall_speed)
		var land_x: float = WebPlanner.predicted_land_x(ctx.pos, ctx.velocity, ctx.floor_y(), ctx.balance.gravity)
		m.transition(HeroState.FALL)
		HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.LAND, 5.0, 0.001)
		assert_eq(m.current_id(), HeroState.LAND)
		assert_almost_eq(ctx.last_impact_speed, predicted, 12.0, "скорость удара, v=%s" % v)
		assert_almost_eq(ctx.pos.x, land_x, 6.0, "x посадки, v=%s" % v)


func test_safe_start_height_formula() -> void:
	var b: HeroBalance = HeroFixture.balance()
	var speed: float = b.hard_landing_speed * b.swing_safe_impact_ratio
	assert_almost_eq(WebPlanner.safe_start_height(b), speed * speed / (2.0 * b.gravity) * WebPlanner.SAFE_HEIGHT_MARGIN, 0.001)
	# падение с этой высоты ниже порога жёсткой посадки
	assert_lt(sqrt(2.0 * b.gravity * WebPlanner.safe_start_height(b)), b.hard_landing_speed)


# --- доля времени

func test_trip_time_share_over_an_hour() -> void:
	for sd: int in [2024, 1, 2, 3, 4]:
		_check_hour_share(sd)


func _check_hour_share(seed_value: int) -> void:
	var ctx: HeroContext = HeroFixture.web_context(seed_value)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.balance.web_trip_chance = HeroFixture.balance().web_trip_chance  # реальный баланс
	var t: float = 0.0
	var trip: float = 0.0
	var walk: float = 0.0
	var trips: int = 0
	var was_web: bool = false
	while t < 3600.0:
		var wait: float = m.next_tick_sec()
		var step: float = DT
		if wait >= ctx.balance.max_step_sec:
			step = minf(wait, 3600.0 - t)  # спящий цикл: один большой шаг, как будит Hero
		var id: StringName = m.current_id()
		var is_web: bool = id in [HeroState.SHOOT_WEB, HeroState.SWING, HeroState.HANG, HeroState.STRETCHED]
		if is_web:
			trip += step
		elif id == HeroState.WALK:
			walk += step
		if is_web and not was_web:
			trips += 1
		was_web = is_web
		m.update(minf(step, 3600.0))
		t += step
	var trip_share: float = trip / 3600.0
	var walk_share: float = walk / 3600.0
	gut.p("seed %d, за час: вылазок %d, вылазки %.2f%%, прогулки %.2f%%" % [seed_value, trips, trip_share * 100.0, walk_share * 100.0])
	assert_gt(trips, 0, "seed %d: за час хоть одна вылазка" % seed_value)
	assert_lte(trip_share, 0.03, "seed %d: вылазки не больше 3%% времени, получилось %.2f%%" % [seed_value, trip_share * 100.0])
	assert_lte(trip_share + walk_share, 0.12, "seed %d: вылазки + прогулки не больше 12%%, получилось %.2f%%" % [seed_value, (trip_share + walk_share) * 100.0])
