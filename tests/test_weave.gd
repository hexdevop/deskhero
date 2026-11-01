extends GutTest
## T-215: плетение в углах: WebPlanner.weave_plan/decide, WalkState с walk_to_x, WeaveState, сброс плана,
## calm_sec, HeroContext.visual_rect, sync_web_hand, WebRope.tension. Без сцены.

const DT: float = 1.0 / 30.0
const B: Rect2 = Rect2(0.0, 0.0, 1200.0, 700.0)
const TL: int = CornerWebField.Corner.TOP_LEFT
const TR: int = CornerWebField.Corner.TOP_RIGHT
const BL: int = CornerWebField.Corner.BOTTOM_LEFT
const BR: int = CornerWebField.Corner.BOTTOM_RIGHT

var _woven: Array[int] = []
var _swept: Array[int] = []
var _hard: Array[float] = []
var _states: Array[StringName] = []


func before_each() -> void:
	_woven.clear()
	_swept.clear()
	_hard.clear()
	_states.clear()


## Контекст с включённым плетением: простой уже достаточен.
func _weave_ctx(seed_value: int = 1, bounds: Rect2 = B, x: float = NAN) -> HeroContext:
	var ctx: HeroContext = HeroFixture.web_context(seed_value, bounds)
	ctx.balance.weave_idle_sec = 10.0
	ctx.calm_sec = 10.0
	if not is_nan(x):
		ctx.pos.x = x
	_watch_ctx(ctx)
	return ctx


func _watch_ctx(ctx: HeroContext) -> void:
	ctx.corners.woven.connect(func(c: int) -> void: _woven.append(c))
	ctx.corners.swept.connect(func(c: int) -> void: _swept.append(c))
	ctx.hard_landed.connect(func(s: float) -> void: _hard.append(s))


func _machine(ctx: HeroContext) -> HeroStateMachine:
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	m.state_changed.connect(func(_from: StringName, to: StringName) -> void: _states.append(to))
	return m


func _floor_x(ctx: HeroContext, left: bool) -> float:
	var half: float = ctx.balance.body_size_px.x * 0.5
	return ctx.bounds.position.x + half if left else ctx.bounds.end.x - half


func _plan(kind: WebPlan.Kind, corner: int, ctx: HeroContext, walk_to: float = NAN) -> WebPlan:
	var p := WebPlan.new()
	p.kind = kind
	p.corner = corner
	p.walk_to_x = walk_to
	if kind == WebPlan.Kind.WEAVE_TOP:
		p.anchor = Vector2(_floor_x(ctx, CornerWebField.is_left(corner)), ctx.bounds.position.y)
	return p


# --- WebPlanner.weave_plan / decide

func test_decide_without_calm_does_not_weave() -> void:
	var ctx: HeroContext = _weave_ctx()
	ctx.calm_sec = ctx.balance.weave_idle_sec - 0.1
	assert_eq(ctx.planner.decide(ctx), HeroState.WALK)
	assert_null(ctx.plan)


func test_decide_weaves_when_calm_reaches_idle_sec_exactly() -> void:
	var ctx: HeroContext = _weave_ctx()
	ctx.calm_sec = ctx.balance.weave_idle_sec
	var decision: StringName = ctx.planner.decide(ctx)
	assert_not_null(ctx.plan, "порог включительно")
	assert_true(ctx.plan.kind == WebPlan.Kind.WEAVE_TOP or ctx.plan.kind == WebPlan.Kind.WEAVE_BOTTOM)
	assert_true(decision == HeroState.WALK or decision == HeroState.SHOOT_WEB or decision == HeroState.WEAVE)


func test_decide_far_from_wall_walks_to_it_first() -> void:
	var ctx: HeroContext = _weave_ctx(1, B, 600.0)
	var decision: StringName = ctx.planner.decide(ctx)
	assert_eq(decision, HeroState.WALK)
	assert_true(ctx.plan.needs_walk())
	var wall_x: float = _floor_x(ctx, CornerWebField.is_left(ctx.plan.corner))
	assert_eq(ctx.plan.walk_to_x, wall_x, "цель ходьбы стоит у стены своего угла")
	assert_eq(ctx.web_cooldown_sec, 0.0, "плетение не расходует перезарядку вылазок")


func test_decide_at_wall_returns_state_by_kind_without_walk() -> void:
	var seen: Dictionary = {}
	for sd: int in 60:
		var ctx: HeroContext = _weave_ctx(sd, B, _floor_x(HeroFixture.web_context(1, B), true))
		var decision: StringName = ctx.planner.decide(ctx)
		var plan: WebPlan = ctx.plan
		assert_not_null(plan)
		assert_false(plan.needs_walk(), "уже у стены")
		assert_true(CornerWebField.is_left(plan.corner), "у левой стены только левые углы")
		if plan.kind == WebPlan.Kind.WEAVE_TOP:
			assert_eq(decision, HeroState.SHOOT_WEB)
			assert_true(CornerWebField.is_top(plan.corner))
			assert_eq(plan.anchor, Vector2(_floor_x(ctx, true), B.position.y))
		else:
			assert_eq(decision, HeroState.WEAVE)
			assert_false(CornerWebField.is_top(plan.corner))
		seen[plan.kind] = true
	assert_eq(seen.size(), 2, "оба вида углов выбираются")


func test_weave_plan_skips_walls_beyond_walk_max() -> void:
	var wide: Rect2 = Rect2(0.0, 0.0, 3000.0, 700.0)
	var ctx: HeroContext = _weave_ctx(1, wide, 1500.0)
	assert_null(ctx.planner.weave_plan(ctx), "обе стены дальше weave_walk_max_px")
	assert_eq(ctx.planner.decide(ctx), HeroState.WALK)
	assert_null(ctx.plan)


func test_weave_plan_picks_only_reachable_side() -> void:
	var wide: Rect2 = Rect2(0.0, 0.0, 3000.0, 700.0)
	for sd: int in 40:
		var ctx: HeroContext = _weave_ctx(sd, wide, 300.0)
		var plan: WebPlan = ctx.planner.weave_plan(ctx)
		assert_not_null(plan)
		assert_true(CornerWebField.is_left(plan.corner), "правая стена дальше 800 lpx")


func test_weave_plan_wall_distance_boundary() -> void:
	var wide: Rect2 = Rect2(0.0, 0.0, 3000.0, 700.0)
	var ctx: HeroContext = _weave_ctx(1, wide)
	var max_px: float = ctx.balance.weave_walk_max_px
	ctx.pos.x = _floor_x(ctx, true) + max_px
	assert_not_null(ctx.planner.weave_plan(ctx), "ровно weave_walk_max_px: ещё идёт")
	ctx.pos.x = _floor_x(ctx, true) + max_px + 1.0
	assert_null(ctx.planner.weave_plan(ctx), "на 1 lpx дальше: нет")


func test_weave_plan_short_area_only_bottom_corners() -> void:
	var low: Rect2 = Rect2(0.0, 0.0, 1200.0, 200.0)
	for sd: int in 30:
		var ctx: HeroContext = _weave_ctx(sd, low)
		var plan: WebPlan = ctx.planner.weave_plan(ctx)
		assert_not_null(plan)
		assert_eq(plan.kind, WebPlan.Kind.WEAVE_BOTTOM, "нет места для верхнего угла")
		assert_false(CornerWebField.is_top(plan.corner))


func test_weave_plan_tall_area_beyond_max_shot_only_bottom_corners() -> void:
	var tall: Rect2 = Rect2(0.0, 0.0, 1200.0, 2000.0)
	for sd: int in 30:
		var ctx: HeroContext = _weave_ctx(sd, tall)
		var plan: WebPlan = ctx.planner.weave_plan(ctx)
		assert_not_null(plan)
		assert_eq(plan.kind, WebPlan.Kind.WEAVE_BOTTOM, "выстрел длиннее web_max_length_px")


func test_weave_plan_no_free_corners_gives_null_and_decide_falls_back() -> void:
	var ctx: HeroContext = _weave_ctx()
	for c: int in 4:
		ctx.corners.begin_weave(c)
	assert_null(ctx.planner.weave_plan(ctx))
	assert_eq(ctx.planner.decide(ctx), HeroState.WALK)
	assert_null(ctx.plan)


func test_weave_plan_skips_taken_corners() -> void:
	for sd: int in 30:
		var ctx: HeroContext = _weave_ctx(sd)
		ctx.corners.begin_weave(TL)
		ctx.corners.begin_weave(BR)
		var plan: WebPlan = ctx.planner.weave_plan(ctx)
		assert_true(plan.corner == TR or plan.corner == BL, "занятые углы не выбираются, получили %d" % plan.corner)


func test_weave_wins_over_trip_but_trip_when_no_corner() -> void:
	var ctx: HeroContext = _weave_ctx()
	ctx.balance.web_trip_chance = 1.0
	ctx.planner.decide(ctx)
	assert_true(ctx.plan.kind == WebPlan.Kind.WEAVE_TOP or ctx.plan.kind == WebPlan.Kind.WEAVE_BOTTOM, "плетение раньше вылазки")
	var ctx2: HeroContext = _weave_ctx()
	ctx2.balance.web_trip_chance = 1.0
	for c: int in 4:
		ctx2.corners.begin_weave(c)
	ctx2.planner.decide(ctx2)
	assert_not_null(ctx2.plan)
	assert_true(ctx2.plan.kind == WebPlan.Kind.SWING or ctx2.plan.kind == WebPlan.Kind.DESCENT, "углов нет: обычная вылазка")


func test_weave_plan_narrow_area_is_null() -> void:
	var ctx: HeroContext = _weave_ctx(1, Rect2(0.0, 0.0, 40.0, 700.0))
	assert_null(ctx.planner.weave_plan(ctx))


# --- WalkState с walk_to_x

func test_walk_to_x_arrives_and_picks_next_state_by_kind() -> void:
	for top: bool in [false, true]:
		var ctx: HeroContext = HeroFixture.web_context(1)
		var m: HeroStateMachine = _machine(ctx)
		var target: float = _floor_x(ctx, true)
		var plan: WebPlan = _plan(WebPlan.Kind.WEAVE_TOP if top else WebPlan.Kind.WEAVE_BOTTOM, TL if top else BL, ctx, target)
		ctx.plan = plan
		m.transition(HeroState.WALK)
		assert_eq(ctx.facing, -1, "идёт к левой стене")
		var t: float = HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 30.0)
		assert_gte(t, 0.0, "дошёл")
		assert_almost_eq(ctx.pos.x, target, 0.6)
		assert_eq(m.current_id(), HeroState.SHOOT_WEB if top else HeroState.WEAVE)
		assert_same(ctx.plan, plan, "план пережил приход")
		assert_false(plan.needs_walk(), "walk_to_x сброшен")
		var expected: float = (600.0 - target) / ctx.balance.walk_speed
		assert_almost_eq(t, expected, 0.2, "путь занял расчётное время")


func test_walk_to_x_target_is_clamped_into_bounds() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = _machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, -500.0)
	m.transition(HeroState.WALK)
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 30.0)
	assert_almost_eq(ctx.pos.x, _floor_x(ctx, true), 0.6, "ушёл только до границы")
	assert_eq(m.current_id(), HeroState.WEAVE)
	var ctx2: HeroContext = HeroFixture.web_context(1)
	var m2: HeroStateMachine = _machine(ctx2)
	ctx2.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BR, ctx2, 99999.0)
	m2.transition(HeroState.WALK)
	HeroFixture.run_until(m2, func() -> bool: return m2.current_id() != HeroState.WALK, 30.0)
	assert_almost_eq(ctx2.pos.x, _floor_x(ctx2, false), 0.6)


func test_walk_to_x_bounds_shrink_during_walk_clamps_goal() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = _machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BR, ctx, _floor_x(ctx, false))
	m.transition(HeroState.WALK)
	HeroFixture.run(m, 0.5)
	ctx.set_bounds(Rect2(0.0, 0.0, 900.0, 700.0))
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 30.0)
	assert_almost_eq(ctx.pos.x, 900.0 - 28.0, 0.6, "цель зажата в новые границы")
	assert_true(ctx.bounds.encloses(ctx.body_rect()))
	assert_eq(m.current_id(), HeroState.WEAVE)


func test_walk_to_x_timeout_drops_plan() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = _machine(ctx)
	var target: float = _floor_x(ctx, true)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, target)
	m.transition(HeroState.WALK)
	var planned: float = (ctx.pos.x - target) / ctx.balance.walk_speed
	ctx.balance.walk_speed = 0.01  # застрял: путь расчётный, скорость уже иная
	var t: float = HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 200.0)
	assert_gte(t, 0.0, "выход по таймауту")
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_null(ctx.plan, "план не пережил прогулку")
	assert_gte(t, planned * WalkState.TARGET_TIMEOUT_RATIO + WalkState.TARGET_TIMEOUT_EXTRA_SEC - DT * 2.0)
	assert_lte(t, planned * WalkState.TARGET_TIMEOUT_RATIO + WalkState.TARGET_TIMEOUT_EXTRA_SEC + DT * 2.0)
	assert_eq(_woven.size(), 0)


func test_walk_to_x_grab_drops_plan() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = _machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, _floor_x(ctx, true))
	m.transition(HeroState.WALK)
	HeroFixture.run(m, 0.5)
	m.handle_input(HeroFixture.press_on_body(ctx))
	assert_eq(m.current_id(), HeroState.CARRIED)
	assert_null(ctx.plan, "захват оборвал прогулку к углу")


func test_walk_to_x_fall_drops_plan() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = _machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, _floor_x(ctx, true))
	m.transition(HeroState.WALK)
	HeroFixture.run(m, 0.5)
	ctx.set_bounds(Rect2(0.0, 0.0, 1200.0, 900.0))  # пол ушёл вниз
	m.update(DT)
	assert_eq(m.current_id(), HeroState.FALL)
	assert_null(ctx.plan)


func test_walk_to_x_corner_taken_on_arrival_goes_idle_and_drops_plan() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = _machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, _floor_x(ctx, true))
	m.transition(HeroState.WALK)
	ctx.corners.begin_weave(BL)  # угол заняли, пока шёл
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 30.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_null(ctx.plan)


func test_walk_to_x_corner_already_woven_on_arrival_goes_idle() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = _machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_TOP, TR, ctx, _floor_x(ctx, false))
	m.transition(HeroState.WALK)
	ctx.corners.begin_weave(TR)
	while not ctx.corners.weave_step(TR):
		pass
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 30.0)
	assert_eq(m.current_id(), HeroState.IDLE, "в оплетённый угол не стреляем")
	assert_null(ctx.plan)


func test_ordinary_walk_unchanged_without_plan() -> void:
	var ctx: HeroContext = HeroFixture.web_context(3)
	var m: HeroStateMachine = _machine(ctx)
	m.transition(HeroState.WALK)
	var x0: float = ctx.pos.x
	var t: float = HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 60.0)
	assert_gte(t, 0.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_null(ctx.plan)
	var walked: float = absf(ctx.pos.x - x0)
	assert_lte(walked, ctx.balance.walk_distance_max_px + 1.0)
	assert_eq(ctx.corners.free_corners().size(), 4)


func test_ordinary_walk_keeps_unrelated_plan() -> void:
	var ctx: HeroContext = HeroFixture.web_context(3)
	var m: HeroStateMachine = _machine(ctx)
	var plan: WebPlan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx)  # walk_to_x = NAN: обычная прогулка
	ctx.plan = plan
	m.transition(HeroState.WALK)
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 60.0)
	assert_same(ctx.plan, plan, "план без walk_to_x прогулка не трогает")


# --- WeaveState: нижний угол

func _bottom_weave(seed_value: int = 1) -> Array:
	var ctx: HeroContext = HeroFixture.web_context(seed_value)
	_watch_ctx(ctx)
	var m: HeroStateMachine = _machine(ctx)
	ctx.pos.x = _floor_x(ctx, true)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx)
	m.transition(HeroState.WEAVE)
	return [ctx, m]


func test_bottom_weave_steps_follow_weave_step_sec() -> void:
	var r: Array = _bottom_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	var step: float = ctx.balance.weave_step_sec
	assert_eq(ctx.pose, &"weave")
	assert_eq(ctx.facing, -1, "лицом в угол слева")
	assert_true(ctx.corners.is_weaving(BL))
	assert_almost_eq(m.next_tick_sec(), step, 0.0001, "после входа до шага ровно weave_step_sec")
	m.update(step * 0.5)
	assert_eq(ctx.corners.step_of(BL), 0)
	assert_almost_eq(m.next_tick_sec(), step * 0.5, 0.0001)
	m.update(step * 0.6)
	assert_eq(ctx.corners.step_of(BL), 1, "шаг после weave_step_sec")
	assert_almost_eq(m.next_tick_sec(), step * 0.9, 0.0001, "остаток переходит в следующий шаг")


func test_bottom_weave_sleeps_between_steps_and_never_returns_zero() -> void:
	var r: Array = _bottom_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	var steps: int = ctx.balance.weave_steps
	var guard: int = 0
	while m.current_id() == HeroState.WEAVE and guard < 1000:
		var wait: float = m.next_tick_sec()
		assert_gt(wait, 0.0, "между шагами герой может спать")
		assert_lte(wait, ctx.balance.weave_step_sec + 0.0001)
		m.update(DT)
		guard += 1
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(ctx.corners.step_of(BL), steps)


func test_bottom_weave_total_time_and_result() -> void:
	var r: Array = _bottom_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	ctx.calm_sec = 50.0
	var x0: float = ctx.pos.x
	var t: float = HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.IDLE, 30.0)
	var expected: float = ctx.balance.weave_step_sec * float(ctx.balance.weave_steps)
	assert_gte(t, expected - 0.0001)
	assert_lte(t, expected + DT * 2.0)
	assert_eq(_woven, [BL] as Array[int])
	assert_false(ctx.corners.is_free(BL))
	assert_eq(ctx.pos.x, x0, "стоит у стены")
	assert_lt(ctx.calm_sec, ctx.balance.weave_step_sec + 2.0 * DT, "конец плетения сбросил calm_sec")
	assert_null(ctx.plan)
	assert_eq(ctx.pose, &"idle")
	assert_eq(_hard.size(), 0)


func test_bottom_weave_pose_flips_on_steps_only() -> void:
	var r: Array = _bottom_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	var phase0: float = ctx.walk_phase
	m.update(ctx.balance.weave_step_sec * 0.5)
	assert_eq(ctx.walk_phase, phase0, "между шагами поза не меняется")
	m.update(ctx.balance.weave_step_sec * 0.6)
	assert_ne(ctx.walk_phase, phase0, "шаг переключает позу")


func test_bottom_weave_huge_delta_finishes_once() -> void:
	var r: Array = _bottom_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	m.update(3600.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(_woven, [BL] as Array[int], "за один огромный кадр плетение кончается один раз")
	assert_eq(ctx.corners.step_of(BL), ctx.balance.weave_steps)


func test_bottom_weave_without_plan_goes_idle() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = _machine(ctx)
	m.transition(HeroState.WEAVE)
	m.update(DT)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(ctx.corners.free_corners().size(), 4)


func test_weave_in_taken_corner_aborts_without_woven() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	_watch_ctx(ctx)
	var m: HeroStateMachine = _machine(ctx)
	ctx.pos.x = _floor_x(ctx, true)
	ctx.corners.begin_weave(BL)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx)
	m.transition(HeroState.WEAVE)
	m.update(DT)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(_woven.size(), 0)


func test_sweep_during_bottom_weave_ends_it_without_woven() -> void:
	var r: Array = _bottom_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	ctx.calm_sec = 50.0
	HeroFixture.run(m, ctx.balance.weave_step_sec * 2.5)
	assert_eq(m.current_id(), HeroState.WEAVE)
	assert_true(ctx.corners.is_weaving(BL))
	var origin: Vector2 = ctx.corners.corner_origin(BL)
	var k: float = 15.0
	while _swept.is_empty() and k < 140.0:
		var a := Vector2(origin.x + k + 20.0, origin.y + 20.0)
		var b := Vector2(origin.x - 20.0, origin.y - k - 20.0)
		ctx.corners.sweep(a, b, 0.01)
		k += 12.0
	assert_eq(_swept, [BL] as Array[int], "взмахи очистили угол")
	assert_true(ctx.corners.is_free(BL))
	var t: float = HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.IDLE, 5.0)
	assert_gte(t, 0.0)
	assert_lte(t, ctx.balance.weave_step_sec + DT * 2.0, "заканчивает на ближайшем шаге")
	assert_eq(_woven.size(), 0, "woven не шлётся")
	assert_lt(ctx.calm_sec, ctx.balance.weave_step_sec + 2.0 * DT, "calm_sec сброшен и в этом случае")


func test_grab_during_bottom_weave_drops_plan_and_resets_calm() -> void:
	var r: Array = _bottom_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	HeroFixture.run(m, ctx.balance.weave_step_sec * 1.5)
	ctx.calm_sec = 77.0
	m.handle_input(HeroFixture.press_on_body(ctx))
	assert_eq(m.current_id(), HeroState.CARRIED)
	assert_null(ctx.plan)
	assert_eq(ctx.calm_sec, 0.0)
	assert_eq(_woven.size(), 0)


# --- WeaveState: верхний угол

func _top_weave(seed_value: int = 1, bounds: Rect2 = B) -> Array:
	var ctx: HeroContext = HeroFixture.web_context(seed_value, bounds)
	_watch_ctx(ctx)
	var m: HeroStateMachine = _machine(ctx)
	ctx.pos.x = _floor_x(ctx, true)
	var plan: WebPlan = _plan(WebPlan.Kind.WEAVE_TOP, TL, ctx)
	HeroFixture.launch(m, ctx, plan)
	return [ctx, plan, m]


func test_top_weave_full_chain_states_and_soft_landing() -> void:
	var r: Array = _top_weave()
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	var seen_weave_stage: bool = false
	var seen_pose: bool = false
	var guard: int = 0
	while m.current_id() != HeroState.IDLE and guard < 3000:
		m.update(DT)
		guard += 1
		if m.current_id() == HeroState.WEAVE:
			seen_weave_stage = seen_weave_stage or plan.stage == WebPlan.Stage.WEAVE
			seen_pose = seen_pose or ctx.pose == HeroContext.POSE_WEAVE_HANG
			assert_lt(ctx.pos.y, ctx.floor_y() - 20.0, "висит у верхнего края")
			assert_gt(ctx.contour_top_extra_px, 0.0, "зона хвата нити включена")
	assert_eq(m.current_id(), HeroState.IDLE, "дошёл до пола")
	assert_true(seen_weave_stage, "plan.stage == WEAVE в плетении")
	assert_true(seen_pose, "поза weave_hang")
	var chain: Array[StringName] = [HeroState.SHOOT_WEB, HeroState.HANG, HeroState.WEAVE, HeroState.HANG, HeroState.LAND, HeroState.IDLE]
	assert_eq(_states.filter(func(s: StringName) -> bool: return s != HeroState.FALL), chain, "цепочка: выстрел, подъём, плетение, спуск, посадка")
	assert_eq(_woven, [TL] as Array[int])
	assert_eq(ctx.corners.step_of(TL), ctx.balance.weave_steps)
	assert_eq(_hard.size(), 0, "посадка мягкая")
	assert_null(ctx.plan)
	assert_ne(ctx.rope.phase, WebRope.Phase.ATTACHED, "нить отпущена")
	assert_eq(ctx.contour_top_extra_px, 0.0)
	assert_eq(ctx.lean, 0.0)
	assert_true(ctx.bounds.grow(0.01).encloses(ctx.body_rect()))
	assert_lt(ctx.calm_sec, 30.0, "calm_sec сброшен концом плетения")


func test_top_weave_descend_follows_last_step() -> void:
	var r: Array = _top_weave()
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.WEAVE, 30.0)
	assert_eq(m.current_id(), HeroState.WEAVE)
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WEAVE, 30.0)
	assert_eq(m.current_id(), HeroState.HANG)
	assert_eq(plan.stage, WebPlan.Stage.DESCEND)
	assert_eq(ctx.corners.step_of(TL), ctx.balance.weave_steps)


func test_top_weave_sleeps_when_settled_between_steps() -> void:
	var r: Array = _top_weave()
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.WEAVE, 30.0)
	var slept: bool = false
	var guard: int = 0
	while m.current_id() == HeroState.WEAVE and guard < 600:
		if plan.settled:
			slept = true
			var wait: float = m.next_tick_sec()
			assert_gt(wait, 0.0)
			assert_lte(wait, ctx.balance.weave_step_sec + 0.0001)
		else:
			assert_eq(m.next_tick_sec(), 0.0, "пока качается, кадры идут")
		m.update(DT)
		guard += 1
	assert_true(slept)


func test_top_weave_stretch_and_release_resumes_same_weaving() -> void:
	var r: Array = _top_weave()
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.WEAVE and ctx.corners.step_of(TL) >= 2, 30.0)
	assert_eq(m.current_id(), HeroState.WEAVE)
	var step_before: int = ctx.corners.step_of(TL)
	var lines_before: Array[CornerWebField.Line] = ctx.corners.draw_data()
	ctx.update_contour(true)
	ctx.calm_sec = 40.0
	m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, ctx.pos + Vector2(0.0, -ctx.balance.body_size_px.y - 20.0), 0.0))
	assert_eq(m.current_id(), HeroState.STRETCHED, "нить плетущего героя тянется, как в hang")
	assert_eq(ctx.calm_sec, 0.0, "натяжение сбросило calm_sec")
	assert_true(plan.weave_started)
	assert_eq(plan.stage, WebPlan.Stage.WEAVE)
	HeroFixture.run(m, 3.0)
	assert_eq(ctx.corners.step_of(TL), step_before, "пока тянут, плетение стоит")
	m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, ctx.pos, 4.0))
	assert_eq(m.current_id(), HeroState.HANG)
	m.update(DT)
	assert_eq(m.current_id(), HeroState.WEAVE, "hang в Stage.WEAVE возвращает в weave")
	assert_same(ctx.plan, plan)
	var lines_now: Array[CornerWebField.Line] = ctx.corners.draw_data()
	assert_gte(lines_now.size(), lines_before.size())
	for i: int in lines_before.size():
		assert_eq(lines_now[i].points, lines_before[i].points, "узор прежний, плетение не началось заново")
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.IDLE, 60.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(_woven, [TL] as Array[int], "woven один раз")
	assert_eq(ctx.corners.step_of(TL), ctx.balance.weave_steps)
	assert_eq(_hard.size(), 0)


func test_top_weave_grab_far_pull_snaps_into_carried_and_corner_stays_consistent() -> void:
	var r: Array = _top_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.WEAVE and ctx.corners.step_of(TL) >= 1, 30.0)
	ctx.update_contour(true)
	var start: Vector2 = ctx.pos + Vector2(0.0, -ctx.balance.body_size_px.y - 20.0)
	m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, start, 0.0))
	assert_eq(m.current_id(), HeroState.STRETCHED)
	for i: int in 20:
		if m.current_id() != HeroState.STRETCHED:
			break
		m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, start + Vector2(0.0, 40.0 * float(i + 1)), 0.01 * float(i + 1)))
	assert_eq(m.current_id(), HeroState.CARRIED, "за пределом нить рвётся")
	assert_null(ctx.plan)
	assert_ne(ctx.rope.phase, WebRope.Phase.ATTACHED)
	# герой в руке: угол либо дозреет, либо останется неоконченным; главное, что состояние согласовано
	var weaving: bool = ctx.corners.is_weaving(TL)
	var free: bool = ctx.corners.is_free(TL)
	assert_false(weaving and free, "угол не может быть и свободным и занятым плетением")


func test_top_weave_sweep_during_hanging_weave_finishes_and_descends() -> void:
	var r: Array = _top_weave()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.WEAVE and ctx.corners.step_of(TL) >= 2, 30.0)
	var origin: Vector2 = ctx.corners.corner_origin(TL)
	var k: float = 15.0
	while _swept.is_empty() and k < 140.0:
		ctx.corners.sweep(Vector2(origin.x + k + 20.0, origin.y - 20.0), Vector2(origin.x - 20.0, origin.y + k + 20.0), 0.01)
		k += 12.0
	assert_eq(_swept, [TL] as Array[int])
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.IDLE, 60.0)
	assert_eq(m.current_id(), HeroState.IDLE, "спустился на пол")
	assert_eq(_woven.size(), 0)
	assert_eq(_hard.size(), 0)
	assert_true(ctx.corners.is_free(TL))


# --- календарь: простой -> плетение -> снова простой

func test_idle_weaves_only_after_calm_threshold() -> void:
	var ctx: HeroContext = HeroFixture.web_context(21)
	_watch_ctx(ctx)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.balance.weave_idle_sec = 100.0
	var t: float = 0.0
	while t < 99.0:
		m.update(DT)
		t += DT
		if ctx.corners.free_corners().size() < 4:
			fail_test("паутина появилась до порога (t=%.1f)" % t)
			return
	while t < 600.0 and _woven.is_empty():
		m.update(DT)
		t += DT
	assert_eq(_woven.size(), 1, "после порога герой оплёл угол")
	assert_gte(t, 100.0)


func test_long_life_weaves_all_four_corners_safely() -> void:
	var ctx: HeroContext = HeroFixture.web_context(33)
	_watch_ctx(ctx)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.balance.weave_idle_sec = 1.0
	m.state_changed.connect(func(_f: StringName, to: StringName) -> void: _states.append(to))
	var t: float = 0.0
	while t < 4000.0 and _woven.size() < 4:
		m.update(DT)
		t += DT
		if not ctx.bounds.grow(0.01).encloses(ctx.body_rect()):
			fail_test("герой вышел за границы: %s" % ctx.pos)
			return
	assert_eq(_woven.size(), 4, "все четыре угла оплетены за %.0f с" % t)
	var uniq: Dictionary = {}
	for c: int in _woven:
		uniq[c] = true
	assert_eq(uniq.size(), 4, "каждый угол по одному разу")
	assert_eq(_hard.size(), 0, "ни одной жёсткой посадки")
	HeroFixture.run(m, 300.0)
	assert_eq(_woven.size(), 4, "свободных углов нет: новое плетение не начинается")
	assert_eq(ctx.corners.free_corners().size(), 0)
	assert_true(ctx.bounds.grow(0.01).encloses(ctx.body_rect()))


# --- calm_sec

func test_calm_sec_grows_with_time() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.calm_sec = 0.0
	HeroFixture.run(m, 5.0)
	assert_almost_eq(ctx.calm_sec, 5.0, 0.05)
	m.update(100.0)
	assert_almost_eq(ctx.calm_sec, 105.0, 0.1, "сон считается целиком")
	m.update(-1.0)
	assert_almost_eq(ctx.calm_sec, 105.0, 0.1, "отрицательная delta не уменьшает")


func test_calm_sec_reset_by_grab_in_idle_and_in_hang() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.calm_sec = 90.0
	m.handle_input(HeroFixture.press_on_body(ctx))
	assert_eq(m.current_id(), HeroState.CARRIED)
	assert_eq(ctx.calm_sec, 0.0)
	var h: Array = HeroFixture.hang_at_rest(Rect2(0.0, 0.0, 1200.0, 1400.0))
	var hctx: HeroContext = h[0]
	var hm: HeroStateMachine = h[2]
	hctx.update_contour(true)
	hctx.calm_sec = 90.0
	hm.handle_input(HeroInput.make(HeroInput.Kind.PRESS, hctx.pos + Vector2(0.0, -hctx.balance.body_size_px.y - 20.0), 0.0))
	assert_eq(hm.current_id(), HeroState.STRETCHED)
	assert_eq(hctx.calm_sec, 0.0)


func test_calm_sec_not_reset_by_trips() -> void:
	var found: Array = HeroFixture.find_plan(true)
	var ctx: HeroContext = found[0]
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.calm_sec = 10.0
	HeroFixture.launch(m, ctx, found[1])
	HeroFixture.run(m, 3.0)
	assert_gte(ctx.calm_sec, 13.0 - 0.1, "обычная вылазка не считается вмешательством")


# --- visual_rect

func test_visual_rect_equals_silhouette_without_lean() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	ctx.lean = 0.0
	assert_eq(ctx.visual_rect(), ctx.silhouette_rect())


func test_visual_rect_half_turn_mirrors_through_hand() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	ctx.pose = HeroState.HANG
	var s: Rect2 = ctx.silhouette_rect()
	var hand: Vector2 = ctx.hand_pos()
	ctx.lean = PI
	var v: Rect2 = ctx.visual_rect()
	var expected := Rect2(2.0 * hand - s.end, s.size)
	assert_almost_eq(v.position, expected.position, Vector2(0.01, 0.01))
	assert_almost_eq(v.size, expected.size, Vector2(0.01, 0.01))


func test_visual_rect_quarter_turn_swaps_extents() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	ctx.pose = HeroState.HANG
	var s: Rect2 = ctx.silhouette_rect()
	var hand: Vector2 = ctx.hand_pos()
	ctx.lean = PI * 0.5
	var v: Rect2 = ctx.visual_rect()
	assert_almost_eq(v.size.x, s.size.y, 0.01)
	assert_almost_eq(v.size.y, s.size.x, 0.01)
	# поворот на +90 градусов (x, y) -> (-y, x) вокруг руки
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c: Vector2 in [s.position, Vector2(s.end.x, s.position.y), s.end, Vector2(s.position.x, s.end.y)]:
		var d: Vector2 = c - hand
		var p: Vector2 = hand + Vector2(-d.y, d.x)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	assert_almost_eq(v.position, lo, Vector2(0.01, 0.01))
	assert_almost_eq(v.end, hi, Vector2(0.01, 0.01))


func test_visual_rect_always_contains_hand_and_sits_inside_contour_for_all_leans() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	ctx.pose = HeroState.SWING
	var limit: float = ctx.balance.swing_lean_max_rad
	var lean: float = -limit
	while lean <= limit + 0.0001:
		ctx.lean = lean
		ctx.update_contour(true)
		var v: Rect2 = ctx.visual_rect()
		assert_true(v.has_point(ctx.hand_pos()), "рука — центр поворота, остаётся внутри")
		assert_true(ctx.contour_rect().encloses(v), "visual_rect внутри contour_rect при lean %.2f" % lean)
		assert_true(ctx.contour_rect().encloses(ctx.silhouette_rect()), "физический силуэт тоже")
		lean += 0.05


func test_contour_encloses_visual_rect_over_simulated_trips() -> void:
	var checked: int = 0
	for swing: bool in [true, false]:
		for sd: int in range(1, 25):
			var ctx: HeroContext = HeroFixture.web_context(sd)
			var plan: WebPlan = ctx.planner.swing_plan(ctx) if swing else ctx.planner.descent_plan(ctx)
			if plan == null:
				continue
			var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
			HeroFixture.launch(m, ctx, plan)
			var t: float = 0.0
			while t < 40.0 and m.current_id() != HeroState.IDLE:
				m.update(DT)
				t += DT
				ctx.update_contour(false)  # так делает Hero после каждого шага
				var c: Rect2 = ctx.contour_rect()
				if not (c.encloses(ctx.visual_rect()) and c.encloses(ctx.silhouette_rect())):
					fail_test("seed %d swing=%s t=%.2f: контур %s не содержит visual %s / silhouette %s" % [sd, swing, t, c, ctx.visual_rect(), ctx.silhouette_rect()])
					return
				checked += 1
	assert_gt(checked, 1000, "проверено достаточно кадров")


# --- sync_web_hand и WebRope.tension

func test_rope_hand_equals_hero_hand_after_every_update_and_input() -> void:
	var r: Array = HeroFixture.hang_at_rest(Rect2(0.0, 0.0, 1200.0, 1400.0))
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	ctx.update_contour(true)
	for i: int in 30:
		m.update(DT)
		assert_eq(ctx.rope.hand, ctx.hand_pos(), "после update рука нити там же, где рука героя")
	var start: Vector2 = ctx.pos + Vector2(0.0, -ctx.balance.body_size_px.y - 20.0)
	m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, start, 0.0))
	for i: int in 8:
		m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, start + Vector2(5.0 * float(i + 1), 12.0 * float(i + 1)), 0.01 * float(i + 1)))
		assert_eq(ctx.rope.hand, ctx.hand_pos(), "после handle_input тоже")


func test_rope_hand_synced_on_snap_and_exit() -> void:
	var found: Array = HeroFixture.find_plan(true)
	var ctx: HeroContext = found[0]
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	HeroFixture.launch(m, ctx, found[1])
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.SWING, 10.0)
	HeroFixture.run(m, 0.5)
	m.handle_input(HeroFixture.press_on_body(ctx))
	assert_eq(m.current_id(), HeroState.CARRIED)
	assert_eq(ctx.rope.hand, ctx.hand_pos(), "оборванная нить уходит от свежей руки")


func test_rope_tension_by_phase_and_stretch() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var hand: Vector2 = ctx.hand_pos()
	assert_eq(ctx.rope.tension(hand), 0.0, "нити нет")
	HeroFixture.attach_rope(ctx, hand + Vector2(0.0, -300.0), hand, WebRope.Mode.SPRING)
	hand = ctx.hand_pos()
	ctx.rope.length = 400.0  # провисшая
	var slack: float = ctx.rope.tension(hand)
	assert_eq(slack, WebRope.SLACK_TENSION)
	ctx.rope.length = 300.0  # натянутая ровно
	var taut: float = ctx.rope.tension(hand)
	assert_eq(taut, WebRope.TAUT_TENSION)
	ctx.rope.length = 300.0 - ctx.balance.thread_max_stretch_px * 0.5
	var half: float = ctx.rope.tension(hand)
	assert_gt(half, taut)
	assert_lt(half, 1.0)
	ctx.rope.length = 300.0 - ctx.balance.thread_max_stretch_px * 3.0
	assert_eq(ctx.rope.tension(hand), 1.0, "растяжение выше предела упирается в 1")
	assert_lt(slack, taut)
	ctx.rope.release()
	assert_eq(ctx.rope.tension(hand), WebRope.TRANSIT_TENSION, "тающая нить")
	ctx.rope.shoot(hand + Vector2(0.0, -300.0))
	assert_eq(ctx.rope.tension(hand), WebRope.TRANSIT_TENSION, "кончик в полёте")
