extends GutTest
## T-215: состояния паутины shoot_web, swing, hang, stretched: переходы, захват, границы, большие delta.

const DT: float = 1.0 / 30.0
const TALL: Rect2 = Rect2(0.0, 0.0, 1200.0, 1400.0)

## Разрешённые переходы (откуда -> куда). Всё остальное в симуляциях считается ошибкой.
const ALLOWED: Dictionary = {
	&"idle": [&"walk", &"shoot_web", &"carried"],
	&"walk": [&"idle", &"carried"],
	&"land": [&"idle", &"carried"],
	&"fall": [&"land", &"carried"],
	&"thrown": [&"land", &"carried"],
	&"carried": [&"fall", &"thrown"],
	&"shoot_web": [&"swing", &"hang", &"idle", &"fall", &"carried"],
	&"swing": [&"land", &"fall", &"carried"],
	&"hang": [&"land", &"fall", &"stretched"],
	&"stretched": [&"hang", &"carried"],
}

var _hard: Array[float] = []
var _pairs: Dictionary = {}


func before_each() -> void:
	_hard.clear()
	_pairs.clear()


func _watch(m: HeroStateMachine, ctx: HeroContext) -> void:
	ctx.hard_landed.connect(func(s: float) -> void: _hard.append(s))
	m.state_changed.connect(func(from: StringName, to: StringName) -> void:
		if from != HeroState.NONE:
			_pairs["%s>%s" % [from, to]] = true)


func _swing_trip(swing: bool = true) -> Array:
	var found: Array = HeroFixture.find_plan(swing)
	var ctx: HeroContext = found[0]
	var plan: WebPlan = found[1]
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	_watch(m, ctx)
	return [ctx, plan, m]


func _press_body(ctx: HeroContext) -> HeroInput:
	return HeroInput.make(HeroInput.Kind.PRESS, ctx.pos + Vector2(0.0, -10.0), 0.0)


func _press_above_head(ctx: HeroContext) -> HeroInput:
	return HeroInput.make(HeroInput.Kind.PRESS, ctx.pos + Vector2(0.0, -ctx.balance.body_size_px.y - 20.0), 0.0)


func _inside(ctx: HeroContext) -> bool:
	return ctx.bounds.grow(0.01).encloses(ctx.body_rect()) and is_finite(ctx.pos.x) and is_finite(ctx.pos.y)


func _in_state(m: HeroStateMachine, id: StringName) -> Callable:
	return func() -> bool: return m.current_id() == id


# --- shoot_web

func test_shoot_enter_state() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var plan: WebPlan = t[1]
	var m: HeroStateMachine = t[2]
	ctx.facing = -1 if plan.anchor.x > ctx.pos.x else 1
	ctx.velocity = Vector2(50, 0)
	HeroFixture.launch(m, ctx, plan)
	assert_eq(m.current_id(), HeroState.SHOOT_WEB)
	assert_eq(ctx.pose, &"shoot_web")
	assert_eq(ctx.velocity, Vector2.ZERO)
	assert_eq(ctx.facing, 1 if plan.anchor.x > ctx.pos.x else -1, "лицом к якорю")


func test_shoot_windup_then_flight() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	m.update(0.1)
	assert_eq(ctx.rope.phase, WebRope.Phase.OFF, "замах ещё идёт")
	m.update(0.11)
	assert_eq(ctx.rope.phase, WebRope.Phase.SHOOTING, "замах 0.2 с кончился: выстрел")
	assert_eq(ctx.rope.anchor, (t[1] as WebPlan).anchor)


func test_shoot_swing_attaches_hard_rope_without_dropping_it() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var plan: WebPlan = t[1]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, plan)
	var elapsed: float = HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	assert_gte(elapsed, 0.0, "дошло до swing")
	var expected: float = ctx.balance.web_shoot_windup_sec + ctx.hand_pos().distance_to(plan.anchor) / ctx.balance.web_shot_speed
	assert_between(elapsed, expected - 0.01, expected + 3.0 * DT, "замах + путь / скорость")
	assert_eq(ctx.rope.phase, WebRope.Phase.ATTACHED, "shoot_web -> swing не трогает нить")
	assert_eq(ctx.rope.mode, WebRope.Mode.HARD)
	assert_almost_eq(ctx.rope.length, ctx.hand_pos().distance_to(plan.anchor), 0.01)
	assert_same(ctx.plan, plan, "план не сброшен при переходе внутри группы")


func test_shoot_descent_attaches_spring_and_goes_hang() -> void:
	var t: Array = _swing_trip(false)
	var ctx: HeroContext = t[0]
	var plan: WebPlan = t[1]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, plan)
	assert_gte(HeroFixture.run_until(m, _in_state(m, HeroState.HANG), 5.0), 0.0)
	assert_eq(ctx.rope.phase, WebRope.Phase.ATTACHED)
	assert_eq(ctx.rope.mode, WebRope.Mode.SPRING)
	assert_same(ctx.plan, plan)
	assert_eq(plan.stage, WebPlan.Stage.ASCEND, "подвес начинается с подъёма")


func test_shoot_without_plan_returns_idle() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.plan = null
	m.transition(HeroState.SHOOT_WEB)
	m.update(DT)
	assert_eq(m.current_id(), HeroState.IDLE)


func test_shoot_anchor_invalid_on_arrival_goes_idle() -> void:
	var t: Array = _swing_trip(false)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	m.update(0.25)  # выстрелил
	assert_eq(ctx.rope.phase, WebRope.Phase.SHOOTING)
	ctx.set_bounds(Rect2(0.0, 100.0, 1200.0, 600.0))  # верхний край ушёл ниже якоря
	HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 5.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_true(ctx.rope.phase == WebRope.Phase.RELEASED or ctx.rope.phase == WebRope.Phase.OFF, "нить отпущена")
	assert_null(ctx.plan)


func test_shoot_in_air_falls() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	ctx.pos.y -= 100.0
	HeroFixture.launch(m, ctx, t[1])
	m.update(DT)
	assert_eq(m.current_id(), HeroState.FALL, "вылазка без опоры не удерживает героя")
	assert_null(ctx.plan)


func test_shoot_huge_delta_does_not_break() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	m.update(3600.0)
	assert_eq(m.current_id(), HeroState.SHOOT_WEB)
	assert_eq(ctx.rope.phase, WebRope.Phase.SHOOTING, "замах кончился разом")
	m.update(3600.0)
	assert_true(m.current_id() == HeroState.SWING or m.current_id() == HeroState.IDLE)
	assert_true(_inside(ctx))


# --- swing

func test_swing_sweep_1000_trips_soft_and_inside() -> void:
	var trips: int = 0
	var released: int = 0
	var violations: int = 0
	var low: float = INF
	var widths: Array[float] = [800.0, 1200.0, 1600.0, 3000.0]
	var heights: Array[float] = [500.0, 700.0, 900.0, 1400.0]
	var all_pairs: Dictionary = {}
	for sd: int in 1000:
		var bounds := Rect2(0.0, 0.0, widths[sd % 4], heights[(sd / 4) % 4])
		var ctx: HeroContext = HeroFixture.web_context(sd + 1, bounds)
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)  # ставит героя по центру
		ctx.pos.x = ctx.rng.randf_range(bounds.position.x + 28.0, bounds.end.x - 28.0)
		var plan: WebPlan = ctx.planner.swing_plan(ctx)
		if plan == null:
			continue
		trips += 1
		var hard_before: int = _hard.size()
		_watch(m, ctx)
		ctx.plan = plan
		m.transition(HeroState.SHOOT_WEB)
		var t: float = 0.0
		var swing_time: float = 0.0
		var lifted: bool = false
		var saw_fall: bool = false
		while t < 40.0 and m.current_id() != HeroState.IDLE:
			m.update(DT)
			t += DT
			if not _inside(ctx):
				violations += 1
			if m.current_id() == HeroState.SWING:
				swing_time += DT
				if ctx.floor_y() - ctx.pos.y > 5.0:
					lifted = true
				# зазор меряем, когда подмотка кончилась: пока нить длиннее swing_length, дуга ниже расчётной
				if lifted and swing_time < ctx.balance.swing_max_sec and ctx.rope.length <= plan.swing_length + 0.5:
					low = minf(low, ctx.floor_y() - ctx.pos.y)
			saw_fall = saw_fall or m.current_id() == HeroState.FALL
		assert_eq(m.current_id(), HeroState.IDLE, "вылазка %d кончилась (seed %d)" % [trips, sd + 1])
		if saw_fall:
			released += 1
		for k: String in _pairs:
			all_pairs[k] = true
		_pairs.clear()
		assert_eq(_hard.size(), hard_before, "жёсткой посадки нет, seed %d" % (sd + 1))
		_hard.clear()
	assert_gt(trips, 500, "достаточно вылазок для вывода")
	assert_eq(violations, 0, "герой всегда внутри bounds")
	gut.p("вылазок %d, отпускание %d, минимум зазора до пола в раскачке %.1f" % [trips, released, low])
	assert_gte(low, HeroFixture.balance().swing_floor_clearance_px - 1.0, "низ дуги выше пола на swing_floor_clearance_px")
	assert_gt(float(released) / float(trips), 0.5, "большинство раскачек кончается отпусканием")
	for k: String in all_pairs:
		var parts: PackedStringArray = k.split(">")
		assert_true((ALLOWED[StringName(parts[0])] as Array).has(StringName(parts[1])), "разрешённый переход %s" % k)


func test_swing_transitions_seen() -> void:
	var seen: Dictionary = {}
	for sd: int in 60:
		var ctx: HeroContext = HeroFixture.web_context(sd + 1)
		var plan: WebPlan = ctx.planner.swing_plan(ctx)
		if plan == null:
			continue
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
		_watch(m, ctx)
		ctx.plan = plan
		m.transition(HeroState.SHOOT_WEB)
		HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 40.0)
		for k: String in _pairs:
			seen[k] = true
	for expected: String in ["shoot_web>swing", "swing>fall", "fall>land", "land>idle"]:
		assert_true(seen.has(expected), "переход %s встретился" % expected)


func test_swing_enter_sets_reel_target() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var plan: WebPlan = t[1]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, plan)
	HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	assert_eq(ctx.pose, &"swing")
	assert_eq(ctx.rope.target_length, plan.swing_length)
	assert_eq(ctx.rope.reel_speed, ctx.balance.swing_reel_speed)


func test_swing_reeling_lifts_off_floor_quickly() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	var lift_time: float = HeroFixture.run_until(m, func() -> bool: return ctx.floor_y() - ctx.pos.y > 5.0, 2.0)
	assert_gte(lift_time, 0.0, "подмотка оторвала от пола за 2 с")
	assert_lt(lift_time, 1.0)


func test_swing_never_released_lowers_after_max_sec_and_lands_softly() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var plan: WebPlan = t[1]
	var m: HeroStateMachine = t[2]
	plan.release_angle = 10.0  # никогда не отпускать
	HeroFixture.launch(m, ctx, plan)
	HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	var swing_t: float = 0.0
	while m.current_id() == HeroState.SWING and swing_t < 60.0:
		m.update(DT)
		swing_t += DT
	assert_eq(m.current_id(), HeroState.LAND, "по swing_max_sec нить стравливается до пола")
	assert_gte(swing_t, ctx.balance.swing_max_sec - DT, "не раньше swing_max_sec")
	assert_lt(swing_t, 40.0)
	assert_eq(_hard.size(), 0, "мягко")
	assert_true(_inside(ctx))


func test_swing_wall_contact_falls() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	HeroFixture.attach_rope(ctx, Vector2(150.0, 0.0), Vector2(550.0, 250.0), WebRope.Mode.HARD)
	ctx.plan = null
	m.transition(HeroState.SWING)
	var elapsed: float = HeroFixture.run_until(m, _in_state(m, HeroState.FALL), 5.0)
	assert_gte(elapsed, 0.0, "дуга ушла за стену: падение")
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED, "выход из группы отпустил нить")
	assert_null(ctx.plan)
	assert_eq(ctx.lean, 0.0)


func test_swing_floor_impact_goes_land_with_speed() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	_watch(m, ctx)
	HeroFixture.attach_rope(ctx, Vector2(600.0, 300.0), Vector2(1000.0, 350.0), WebRope.Mode.HARD)
	ctx.plan = null
	m.transition(HeroState.SWING)
	assert_gte(HeroFixture.run_until(m, _in_state(m, HeroState.LAND), 5.0), 0.0)
	assert_gt(ctx.last_impact_speed, 30.0)
	assert_eq(ctx.velocity.y, 0.0)
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)


func test_swing_lean_and_facing() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	HeroFixture.attach_rope(ctx, Vector2(600.0, 0.0), Vector2(1000.0, 250.0), WebRope.Mode.HARD)
	ctx.plan = null
	m.transition(HeroState.SWING)
	var lean_limit: float = ctx.balance.swing_lean_max_rad
	for i: int in 90:
		m.update(DT)
		if m.current_id() != HeroState.SWING:
			break
		assert_lte(absf(ctx.lean), lean_limit + 0.0001)
		if absf(ctx.velocity.x) > SwingState.FACING_MIN_SPEED:
			assert_eq(ctx.facing, 1 if ctx.velocity.x > 0.0 else -1)


func test_swing_without_plan_never_releases_by_angle() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	HeroFixture.attach_rope(ctx, Vector2(600.0, 0.0), Vector2(900.0, 250.0), WebRope.Mode.HARD)
	ctx.plan = null
	m.transition(HeroState.SWING)
	for i: int in 120:
		m.update(DT)
		assert_eq(m.current_id(), HeroState.SWING, "без плана отпускать нечего (первые 4 с)")


func test_swing_invalid_anchor_after_bounds_change_falls() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	m.update(DT)
	var anchor: Vector2 = ctx.rope.anchor
	ctx.set_bounds(Rect2(anchor.x + 10.0, 0.0, 500.0, 700.0))  # якорь остался слева от области
	m.update(DT)
	assert_eq(m.current_id(), HeroState.FALL)
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)


func test_swing_floor_changes_keep_hero_inside() -> void:
	for new_end: float in [900.0, 600.0, 520.0]:
		var t: Array = _swing_trip(true)
		var ctx: HeroContext = t[0]
		var m: HeroStateMachine = t[2]
		HeroFixture.launch(m, ctx, t[1])
		HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
		for i: int in 15:
			m.update(DT)
		ctx.set_bounds(Rect2(0.0, 0.0, 1200.0, new_end))
		var steps: int = 0
		while m.current_id() != HeroState.IDLE and steps < 30 * 40:
			m.update(DT)
			steps += 1
			assert_true(_inside(ctx), "пол %s: внутри области" % new_end)
		assert_eq(m.current_id(), HeroState.IDLE, "пол %s: вылазка кончилась" % new_end)


func test_swing_narrow_bounds_keep_hero_inside() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	for i: int in 10:
		m.update(DT)
	var anchor: Vector2 = ctx.rope.anchor
	ctx.set_bounds(Rect2(anchor.x - 120.0, 0.0, 240.0, 700.0))
	var steps: int = 0
	while m.current_id() != HeroState.IDLE and steps < 30 * 40:
		m.update(DT)
		steps += 1
		assert_true(_inside(ctx))
	assert_eq(m.current_id(), HeroState.IDLE)


func test_swing_huge_delta() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	for i: int in 10:
		m.update(DT)
	m.update(3600.0)
	assert_true(_inside(ctx))
	assert_true(m.current_id() != HeroState.NONE)
	HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 40.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(_hard.size(), 0)


# --- hang

func _descent_run(plan_edit: Callable = Callable()) -> Dictionary:
	var t: Array = _swing_trip(false)
	var ctx: HeroContext = t[0]
	var plan: WebPlan = t[1]
	var m: HeroStateMachine = t[2]
	if plan_edit.is_valid():
		plan_edit.call(plan, ctx)
	HeroFixture.launch(m, ctx, plan)
	var stages: Array[int] = []
	var top: float = INF
	var rest_len: float = -1.0
	var asleep_next: float = -1.0
	var next_when_unsettled: float = -1.0
	var elapsed: float = 0.0
	var rest_total: float = -1.0
	var rest_began: float = 0.0
	var asleep_after: float = -1.0
	while elapsed < 150.0 and m.current_id() != HeroState.IDLE:
		var wait: float = m.next_tick_sec()
		var step: float = DT
		if wait >= ctx.balance.max_step_sec:
			step = minf(wait, 5.0)
		m.update(step)
		elapsed += step
		if m.current_id() == HeroState.HANG:
			if stages.is_empty() or stages[stages.size() - 1] != plan.stage:
				stages.append(plan.stage)
				if plan.stage == WebPlan.Stage.REST:
					rest_len = ctx.rope.length
					rest_total = plan.rest_left_sec
					rest_began = elapsed
			top = minf(top, ctx.pos.y - ctx.balance.body_size_px.y - ctx.bounds.position.y)
			if plan.stage == WebPlan.Stage.REST and not plan.settled and next_when_unsettled < 0.0:
				next_when_unsettled = m.next_tick_sec()
			if plan.stage == WebPlan.Stage.REST and plan.settled and asleep_next < 0.0:
				asleep_next = m.next_tick_sec()
				asleep_after = elapsed - rest_began
	return {"ctx": ctx, "plan": plan, "m": m, "stages": stages, "top": top, "rest_len": rest_len,
			"asleep_next": asleep_next, "rest_total": rest_total, "asleep_after": asleep_after, "unsettled_next": next_when_unsettled, "elapsed": elapsed}


func test_hang_full_descent_stage_order_and_soft_landing() -> void:
	var r: Dictionary = _descent_run()
	var plan: WebPlan = r["plan"]
	var ctx: HeroContext = r["ctx"]
	assert_eq(r["stages"], [WebPlan.Stage.ASCEND, WebPlan.Stage.LOWER, WebPlan.Stage.REST, WebPlan.Stage.DESCEND])
	assert_eq((r["m"] as HeroStateMachine).current_id(), HeroState.IDLE, "спуск до пола и посадка")
	assert_eq(_hard.size(), 0, "мягкая посадка")
	assert_almost_eq(ctx.pos.y, ctx.floor_y(), 0.01)
	assert_gte(float(r["top"]), -0.01, "голова не выше верхнего края")
	assert_almost_eq(float(r["rest_len"]), plan.rest_length, 1.0, "остановка на rest_length")
	assert_lt(float(r["elapsed"]), 150.0)
	assert_null(ctx.plan)
	assert_eq(ctx.contour_top_extra_px, 0.0, "зона хвата убрана при выходе")
	assert_true(ctx.rope.phase == WebRope.Phase.RELEASED or ctx.rope.phase == WebRope.Phase.OFF)


func test_hang_sleeps_only_in_settled_rest() -> void:
	var r: Dictionary = _descent_run()
	var b: HeroBalance = (r["ctx"] as HeroContext).balance
	assert_eq(float(r["unsettled_next"]), 0.0, "REST, пока качается: тикать каждый кадр")
	assert_gt(float(r["asleep_next"]), 0.0, "замер до конца паузы: сон есть")
	assert_lte(float(r["asleep_next"]), b.hang_rest_max_sec, "сон не длиннее максимальной паузы")
	assert_between(float(r["rest_total"]), b.hang_rest_min_sec, b.hang_rest_max_sec)
	# пауза идёт и пока качается: сон = вся пауза минус время до замирания
	assert_almost_eq(float(r["asleep_next"]), float(r["rest_total"]) - float(r["asleep_after"]), 3.0 * DT, "сон равен остатку паузы")
	assert_lt(float(r["asleep_next"]), float(r["rest_total"]), "время замирания вычтено из паузы")


func test_hang_skips_lower_when_rest_is_at_top_gap() -> void:
	var r: Dictionary = _descent_run(func(p: WebPlan, c: HeroContext) -> void: p.rest_length = c.balance.hang_top_gap_px)
	assert_eq(r["stages"], [WebPlan.Stage.ASCEND, WebPlan.Stage.REST, WebPlan.Stage.DESCEND], "остановка уже наверху: LOWER пропущен")
	assert_eq(_hard.size(), 0)


func test_hang_stage_targets() -> void:
	var t: Array = _swing_trip(false)
	var ctx: HeroContext = t[0]
	var plan: WebPlan = t[1]
	var m: HeroStateMachine = t[2]
	var b: HeroBalance = ctx.balance
	HeroFixture.launch(m, ctx, plan)
	HeroFixture.run_until(m, _in_state(m, HeroState.HANG), 5.0)
	assert_eq(ctx.pose, &"hang")
	assert_eq(ctx.contour_top_extra_px, b.thread_grab_zone_px, "зона хвата сверху")
	assert_eq(plan.stage, WebPlan.Stage.ASCEND)
	assert_almost_eq(ctx.rope.target_length, ctx.rope.anchor.y - ctx.bounds.position.y + b.hang_top_gap_px, 0.001)
	assert_eq(ctx.rope.reel_speed, b.thread_ascend_speed)
	HeroFixture.run_until(m, func() -> bool: return plan.stage == WebPlan.Stage.LOWER, 20.0)
	assert_eq(ctx.rope.target_length, plan.rest_length)
	assert_eq(ctx.rope.reel_speed, b.thread_descend_speed)
	HeroFixture.run_until(m, func() -> bool: return plan.stage == WebPlan.Stage.DESCEND, 90.0)
	assert_almost_eq(ctx.rope.target_length, ctx.floor_y() - ctx.rope.anchor.y - ctx.hand_offset().length(), 0.001)
	assert_eq(ctx.rope.reel_speed, b.thread_descend_speed)


func test_hang_ascend_keeps_machine_awake() -> void:
	var t: Array = _swing_trip(false)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	HeroFixture.run_until(m, _in_state(m, HeroState.HANG), 5.0)
	assert_eq(m.next_tick_sec(), 0.0, "подъём: тикать каждый кадр")


func test_rest_pause_counted_fully_and_hero_not_moved() -> void:
	var r: Array = HeroFixture.hang_at_rest()
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	assert_eq(plan.stage, WebPlan.Stage.REST)
	assert_true(plan.settled)
	assert_between(plan.rest_left_sec, 0.0, ctx.balance.hang_rest_max_sec)
	assert_eq(m.next_tick_sec(), plan.rest_left_sec, "сон ровно до конца паузы")
	assert_gt(m.next_tick_sec(), 0.0)
	var pos: Vector2 = ctx.pos
	var left: float = plan.rest_left_sec
	m.update(0.5)
	assert_eq(ctx.pos, pos, "в покое герой не двигается")
	assert_almost_eq(plan.rest_left_sec, left - 0.5, 0.0001)
	m.update(plan.rest_left_sec - 1.0)
	assert_eq(plan.stage, WebPlan.Stage.REST)
	assert_almost_eq(plan.rest_left_sec, 1.0, 0.001)
	m.update(1.0)
	assert_eq(plan.stage, WebPlan.Stage.DESCEND, "пауза закончилась ровно в срок")
	assert_eq(ctx.pos, pos, "и в момент конца паузы герой стоит")
	assert_eq(m.next_tick_sec(), 0.0, "спуск: тикать каждый кадр")


func test_rest_update_3600_does_not_move_hero_and_ends_pause() -> void:
	var r: Array = HeroFixture.hang_at_rest()
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	var pos: Vector2 = ctx.pos
	m.update(3600.0)
	assert_eq(ctx.pos, pos)
	assert_eq(ctx.velocity, Vector2.ZERO)
	assert_eq(plan.stage, WebPlan.Stage.DESCEND)
	assert_eq(m.current_id(), HeroState.HANG)
	HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 60.0)
	assert_eq(m.current_id(), HeroState.IDLE)


func test_rest_sleep_emulation_wakes_into_descent() -> void:
	var r: Array = HeroFixture.hang_at_rest()
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	m.update(m.next_tick_sec())
	assert_eq(plan.stage, WebPlan.Stage.DESCEND, "проснулся в срок")


# --- сон и RELEASED

func test_web_group_and_leaf_next_tick() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	assert_eq(m.get_state(HeroState.WEB).next_tick_sec(), INF, "группа сама не будит")
	assert_eq(m.get_state(HeroState.ROOT).next_tick_sec(), INF)
	var t: Array = _swing_trip(true)
	var c2: HeroContext = t[0]
	var m2: HeroStateMachine = t[2]
	HeroFixture.launch(m2, c2, t[1])
	assert_eq(m2.next_tick_sec(), 0.0, "shoot_web: кадры нужны")
	HeroFixture.run_until(m2, _in_state(m2, HeroState.SWING), 5.0)
	assert_eq(m2.next_tick_sec(), 0.0, "swing: кадры нужны")


func test_released_rope_keeps_machine_awake_until_faded() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	HeroFixture.attach_rope(ctx, Vector2(600.0, 0.0), Vector2(600.0, 500.0), WebRope.Mode.SPRING)
	ctx.pos.y = ctx.floor_y()
	ctx.rope.release()
	assert_gt((m.get_state(HeroState.IDLE) as IdleState).remaining_sec, 0.0)
	assert_eq(m.next_tick_sec(), 0.0, "нить тает: не засыпать")
	m.update(ctx.balance.web_release_fade_sec + 0.01)
	assert_eq(ctx.rope.phase, WebRope.Phase.OFF)
	assert_gt(m.next_tick_sec(), 0.0, "нить исчезла: можно спать")
	assert_eq(m.next_tick_sec(), (m.get_state(HeroState.IDLE) as IdleState).remaining_sec)


# --- stretched

var _cursor0: Vector2 = Vector2.ZERO


func _grab_above_head(r: Array) -> void:
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	ctx.update_contour(true)
	var press: HeroInput = _press_above_head(ctx)
	_cursor0 = press.pos
	m.handle_input(press)


## Курсор идёт от точки захвата на delta (абсолютно, не от положения героя: тот упирается в предел).
func _move_by(r: Array, delta: Vector2) -> void:
	var m: HeroStateMachine = r[2]
	var steps: int = 10
	for i: int in steps:
		if m.current_id() != HeroState.STRETCHED:
			return
		m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, _cursor0 + delta * (float(i + 1) / float(steps)), 0.01 * float(i + 1)))


func test_hang_press_above_head_stretches_and_press_far_ignored() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	ctx.update_contour(true)
	m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, ctx.pos + Vector2(400.0, -10.0), 0.0))
	assert_eq(m.current_id(), HeroState.HANG, "мимо контура")
	m.handle_input(_press_above_head(ctx))
	assert_eq(m.current_id(), HeroState.STRETCHED, "зона хвата над головой")
	assert_true(ctx.carrying)
	assert_eq(ctx.pose, &"stretched")
	assert_eq(ctx.velocity, Vector2.ZERO)


func test_stretched_follows_cursor_within_limit_and_spring_returns() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	var rest: Vector2 = ctx.pos
	_grab_above_head(r)
	_move_by(r, Vector2(0.0, 100.0))
	assert_eq(m.current_id(), HeroState.STRETCHED)
	assert_almost_eq(ctx.pos.y, rest.y + 100.0, 0.01, "герой идёт за курсором")
	assert_eq(ctx.rope.phase, WebRope.Phase.ATTACHED)
	assert_lte(ctx.rope.stretch(ctx), ctx.balance.thread_max_stretch_px + 0.01)
	m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, ctx.pos, 1.0))
	assert_eq(m.current_id(), HeroState.HANG, "отпустил до предела: вернулся в hang")
	assert_false(ctx.carrying)
	assert_eq(ctx.velocity, Vector2.ZERO)
	assert_eq(plan.stage, WebPlan.Stage.REST, "этап не потерян")
	assert_same(ctx.plan, plan)
	assert_eq(ctx.rope.phase, WebRope.Phase.ATTACHED, "stretched -> hang не рвёт нить")
	var back: float = HeroFixture.run_until(m, func() -> bool: return plan.settled, 40.0)
	assert_gte(back, 0.0, "пружина вернула героя в покой")
	assert_lt(ctx.pos.distance_to(rest), ctx.balance.rope_rest_stretch_px + 0.5)


func test_stretched_clamps_at_limit_and_snaps_just_beyond() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	var b: HeroBalance = ctx.balance
	var length: float = ctx.rope.length
	var r0: float = ctx.hand_pos().distance_to(ctx.rope.anchor)
	_grab_above_head(r)
	var to_limit: float = (length + b.thread_max_stretch_px) - r0
	var to_snap: float = (length + b.thread_max_stretch_px + b.thread_snap_extra_px) - r0
	_move_by(r, Vector2(0.0, to_limit - 1.0))
	assert_eq(m.current_id(), HeroState.STRETCHED)
	assert_almost_eq(ctx.hand_pos().distance_to(ctx.rope.anchor), length + b.thread_max_stretch_px - 1.0, 0.05, "до предела: герой точно под курсором")
	_move_by(r, Vector2(0.0, to_snap - 0.05))
	assert_eq(m.current_id(), HeroState.STRETCHED, "чуть меньше предела разрыва: держит")
	assert_almost_eq(ctx.hand_pos().distance_to(ctx.rope.anchor), length + b.thread_max_stretch_px, 0.05, "герой упирается в предел")
	_move_by(r, Vector2(0.0, to_snap + 0.05))
	assert_eq(m.current_id(), HeroState.CARRIED, "за пределом + snap_extra нить рвётся")
	assert_true(ctx.carrying, "герой остаётся в руке")
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)
	assert_null(ctx.plan)
	assert_almost_eq(ctx.pos.y, _cursor0.y + to_snap + 0.05 + ctx.grab_offset.y, 0.01, "позиция следует курсору, а не пределу")


func test_stretched_snap_by_full_pull() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	_grab_above_head(r)
	var jump: Vector2 = _cursor0 + Vector2(0.0, 300.0)
	m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, jump, 0.1))
	assert_eq(m.current_id(), HeroState.CARRIED, "рывок сразу за предел")
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)
	assert_almost_eq(ctx.pos.y, ctx.clamp_pos(jump + ctx.grab_offset).y, 0.01)


func test_stretched_sideways_pull_limits_along_ray() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	var b: HeroBalance = ctx.balance
	_grab_above_head(r)
	_move_by(r, Vector2(120.0, 120.0))
	if m.current_id() == HeroState.STRETCHED:
		assert_lte(ctx.hand_pos().distance_to(ctx.rope.anchor), ctx.rope.length + b.thread_max_stretch_px + 0.05)
	else:
		assert_eq(m.current_id(), HeroState.CARRIED)


func test_stretched_cancel_returns_to_hang() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	_grab_above_head(r)
	_move_by(r, Vector2(0.0, 50.0))
	m.handle_input(HeroInput.make(HeroInput.Kind.CANCEL, ctx.pos, 1.0))
	assert_eq(m.current_id(), HeroState.HANG)
	assert_eq(ctx.velocity, Vector2.ZERO)
	assert_false(ctx.carrying)


func test_stretched_resync_snaps_into_carried() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	_grab_above_head(r)
	_move_by(r, Vector2(0.0, 30.0))
	var new_cursor := Vector2(300.0, 300.0)
	m.handle_input(HeroInput.make(HeroInput.Kind.RESYNC, new_cursor, 2.0))
	assert_eq(m.current_id(), HeroState.CARRIED, "смена системы координат рвёт нить")
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)
	assert_eq(ctx.pos, ctx.clamp_pos(new_cursor + ctx.grab_offset))
	assert_true(ctx.carrying)


func test_stretched_ignores_second_press() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	_grab_above_head(r)
	m.handle_input(_press_body(ctx))
	assert_eq(m.current_id(), HeroState.STRETCHED)


func test_stretched_invalid_anchor_snaps() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	_grab_above_head(r)
	_move_by(r, Vector2(0.0, 20.0))
	ctx.set_bounds(Rect2(ctx.rope.anchor.x + 50.0, 0.0, 400.0, 1400.0))
	m.update(DT)
	assert_eq(m.current_id(), HeroState.CARRIED)
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)
	assert_true(ctx.carrying)


func test_stretched_state_keeps_stage_for_each_stage() -> void:
	for stage: int in [WebPlan.Stage.ASCEND, WebPlan.Stage.LOWER, WebPlan.Stage.DESCEND]:
		var found: Array = HeroFixture.find_plan(false, TALL)
		var ctx: HeroContext = found[0]
		var plan: WebPlan = found[1]
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
		HeroFixture.launch(m, ctx, plan)
		var reached: float = HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.HANG and plan.stage == stage, 120.0)
		assert_gte(reached, 0.0, "достигнут этап %d" % stage)
		var r: Array = [ctx, plan, m]
		_grab_above_head(r)
		assert_eq(m.current_id(), HeroState.STRETCHED, "этап %d: хват" % stage)
		m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, ctx.pos, 1.0))
		assert_eq(m.current_id(), HeroState.HANG)
		assert_eq(plan.stage, stage, "этап %d сохранён" % stage)
		assert_false(plan.settled)
		HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 150.0)
		assert_eq(m.current_id(), HeroState.IDLE, "этап %d: вылазка дошла до пола" % stage)


# --- захват курсором в каждом состоянии

func _enter_state(id: StringName) -> Array:
	var found: Array = HeroFixture.find_plan(id != HeroState.HANG)
	var ctx: HeroContext = found[0]
	var plan: WebPlan = found[1]
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	match id:
		HeroState.IDLE:
			pass
		HeroState.WALK, HeroState.LAND:
			m.transition(id)
		HeroState.FALL, HeroState.THROWN:
			ctx.pos.y -= 150.0
			m.transition(id)
		HeroState.SHOOT_WEB:
			HeroFixture.launch(m, ctx, plan)
			m.update(0.3)
		HeroState.SWING:
			HeroFixture.launch(m, ctx, plan)
			HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
			m.update(0.1)
		HeroState.HANG:
			HeroFixture.launch(m, ctx, plan)
			HeroFixture.run_until(m, _in_state(m, HeroState.HANG), 5.0)
			m.update(0.1)
		HeroState.CARRIED:
			m.handle_input(_press_body(ctx))
	return [ctx, plan, m]


func test_grab_from_every_leaf() -> void:
	var expected: Dictionary = {
		HeroState.IDLE: HeroState.CARRIED, HeroState.WALK: HeroState.CARRIED, HeroState.LAND: HeroState.CARRIED,
		HeroState.FALL: HeroState.CARRIED, HeroState.THROWN: HeroState.CARRIED, HeroState.SHOOT_WEB: HeroState.CARRIED,
		HeroState.SWING: HeroState.CARRIED, HeroState.HANG: HeroState.STRETCHED, HeroState.CARRIED: HeroState.CARRIED,
	}
	for id: StringName in expected:
		var r: Array = _enter_state(id)
		var ctx: HeroContext = r[0]
		var m: HeroStateMachine = r[2]
		assert_eq(m.current_id(), id, "вошли в %s" % id)
		m.handle_input(_press_body(ctx))
		assert_eq(m.current_id(), expected[id], "захват из %s" % id)
		assert_true(ctx.carrying, "в руке после захвата из %s" % id)
		if id in [HeroState.SHOOT_WEB, HeroState.SWING]:
			assert_true(ctx.rope.phase == WebRope.Phase.RELEASED or ctx.rope.phase == WebRope.Phase.OFF, "нить отпущена при захвате из %s" % id)
			assert_null(ctx.plan, "план сброшен при захвате из %s" % id)
			assert_eq(ctx.lean, 0.0)
		if id == HeroState.HANG:
			assert_eq(ctx.rope.phase, WebRope.Phase.ATTACHED, "из hang нить остаётся (stretched)")


func test_grab_in_shoot_web_during_windup_and_flight() -> void:
	for wait: float in [0.0, 0.1, 0.25]:
		var t: Array = _swing_trip(true)
		var ctx: HeroContext = t[0]
		var m: HeroStateMachine = t[2]
		HeroFixture.launch(m, ctx, t[1])
		if wait > 0.0:
			m.update(wait)
		m.handle_input(_press_body(ctx))
		assert_eq(m.current_id(), HeroState.CARRIED, "захват на %s с" % wait)
		assert_null(ctx.plan)
		m.update(1.0)
		assert_eq(ctx.rope.phase, WebRope.Phase.OFF, "нить исчезла")


func test_group_exit_releases_rope_and_resets() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	m.update(0.2)
	ctx.lean = 0.3
	ctx.contour_top_extra_px = 36.0
	m.transition(HeroState.FALL)
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)
	assert_null(ctx.plan)
	assert_eq(ctx.lean, 0.0)
	assert_eq(ctx.contour_top_extra_px, 0.0)


func test_web_state_falls_when_rope_not_attached_and_hero_in_air() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	HeroFixture.attach_rope(ctx, Vector2(600.0, 0.0), Vector2(600.0, 300.0), WebRope.Mode.SPRING)
	ctx.plan = null
	m.transition(HeroState.HANG)
	ctx.rope.release()
	ctx.rope.tick_visual(3600.0, ctx.hand_pos())  # нить исчезла, герой в воздухе
	m.update(DT)
	assert_eq(m.current_id(), HeroState.FALL)


# --- hang: смена границ

func test_hang_bounds_changes() -> void:
	# пол ниже, пол выше (герой окажется ниже), сужение вокруг якоря: всегда внутри области и вылазка кончается
	var variants: Dictionary = {"floor_lower": 1, "floor_higher": 2, "narrow": 3}
	for name: String in variants:
		var r: Array = HeroFixture.hang_at_rest(TALL)
		var ctx: HeroContext = r[0]
		var m: HeroStateMachine = r[2]
		_watch(m, ctx)
		var anchor: Vector2 = ctx.rope.anchor
		match variants[name]:
			1:
				ctx.set_bounds(Rect2(0.0, 0.0, 1200.0, 1600.0))
			2:
				ctx.set_bounds(Rect2(0.0, 0.0, 1200.0, ctx.pos.y - 50.0))
			3:
				ctx.set_bounds(Rect2(anchor.x - 100.0, 0.0, 200.0, 1400.0))
		var steps: int = 0
		while m.current_id() != HeroState.IDLE and steps < 30 * 150:
			var wait: float = m.next_tick_sec()
			m.update(DT if wait < ctx.balance.max_step_sec else minf(wait, 5.0))
			steps += 1
			assert_true(_inside(ctx), "%s: внутри области" % name)
		assert_eq(m.current_id(), HeroState.IDLE, "%s: дошёл до пола" % name)
		assert_eq(_hard.size(), 0, "%s: мягко" % name)


func test_hang_anchor_outside_after_bounds_change_falls() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	ctx.set_bounds(Rect2(ctx.rope.anchor.x + 20.0, 0.0, 400.0, 1400.0))
	m.update(DT)
	assert_eq(m.current_id(), HeroState.FALL)
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)
	assert_null(ctx.plan)


func test_hang_huge_delta_in_motion() -> void:
	var t: Array = _swing_trip(false)
	var ctx: HeroContext = t[0]
	var m: HeroStateMachine = t[2]
	HeroFixture.launch(m, ctx, t[1])
	HeroFixture.run_until(m, _in_state(m, HeroState.HANG), 5.0)
	m.update(3600.0)
	assert_true(_inside(ctx))
	HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 150.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(_hard.size(), 0)


func test_hang_without_plan_makes_default_plan() -> void:
	var ctx: HeroContext = HeroFixture.web_context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	HeroFixture.attach_rope(ctx, Vector2(600.0, 0.0), Vector2(600.0, 300.0), WebRope.Mode.SPRING)
	ctx.plan = null
	m.transition(HeroState.HANG)
	assert_not_null(ctx.plan, "вход без плана не падает")
	for i: int in 30 * 120:
		m.update(DT)
		if m.current_id() == HeroState.IDLE:
			break
	assert_eq(m.current_id(), HeroState.IDLE)


# --- правки по ревью: пауза во время замирания, пол при спуске, страховка этапа, сброс settled

func _hang_to_stage(stage: int, bounds: Rect2 = TALL, edit: Callable = Callable()) -> Array:
	var found: Array = HeroFixture.find_plan(false, bounds)
	var ctx: HeroContext = found[0]
	var plan: WebPlan = found[1]
	if edit.is_valid():
		edit.call(ctx, plan)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	_watch(m, ctx)
	HeroFixture.launch(m, ctx, plan)
	var reached: float = HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.HANG and plan.stage == stage, 60.0)
	assert_gte(reached, 0.0, "достигнут этап %d" % stage)
	return [ctx, plan, m]


func test_rest_left_decreases_before_settled() -> void:
	var r: Array = _hang_to_stage(WebPlan.Stage.REST)
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	assert_false(plan.settled, "только вошли в REST: качается")
	var left0: float = plan.rest_left_sec
	for i: int in 15:
		m.update(DT)
	assert_false(plan.settled, "за полсекунды ещё качается")
	assert_almost_eq(plan.rest_left_sec, left0 - 15.0 * DT, 0.0001, "пауза идёт и до замирания")


func test_rest_pause_may_end_before_settled_and_descend_starts() -> void:
	var r: Array = _hang_to_stage(WebPlan.Stage.REST)
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	plan.rest_left_sec = 0.05
	m.update(0.1)
	assert_eq(plan.stage, WebPlan.Stage.DESCEND, "пауза кончилась раньше замирания: спуск")
	assert_false(plan.settled)
	HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 60.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(_hard.size(), 0)


func test_descend_target_follows_floor_lowered() -> void:
	var r: Array = _hang_to_stage(WebPlan.Stage.DESCEND)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	ctx.set_bounds(Rect2(0.0, 0.0, 1200.0, 1700.0))
	m.update(DT)
	assert_almost_eq(ctx.rope.target_length, 1700.0 - ctx.rope.anchor.y - ctx.hand_offset().length(), 0.001, "цель по новому полу")
	HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 90.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_almost_eq(ctx.pos.y, 1700.0, 0.01, "сел на новый пол")
	assert_eq(_hard.size(), 0)


func test_descend_target_follows_floor_raised() -> void:
	var r: Array = _hang_to_stage(WebPlan.Stage.DESCEND)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	var new_floor: float = ctx.pos.y + 150.0
	ctx.set_bounds(Rect2(0.0, 0.0, 1200.0, new_floor))
	m.update(DT)
	assert_almost_eq(ctx.rope.target_length, new_floor - ctx.rope.anchor.y - ctx.hand_offset().length(), 0.001)
	HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 90.0)
	assert_almost_eq(ctx.pos.y, new_floor, 0.01)
	assert_eq(_hard.size(), 0)


func test_stage_timeout_ascend_falls() -> void:
	var r: Array = _hang_to_stage(WebPlan.Stage.ASCEND, TALL, func(c: HeroContext, _p: WebPlan) -> void: c.balance.thread_ascend_speed = 0.01)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	var limit: float = ctx.balance.web_stage_timeout_sec
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.HANG, limit - 1.0)
	assert_eq(m.current_id(), HeroState.HANG, "до таймаута этап ещё жив")
	var t: float = HeroFixture.run_until(m, _in_state(m, HeroState.FALL), 3.0)
	assert_gte(t, 0.0, "после web_stage_timeout_sec нить рвётся и герой падает")
	assert_eq(ctx.rope.phase, WebRope.Phase.RELEASED)
	assert_null(ctx.plan)


func test_stage_timeout_descend_falls() -> void:
	var r: Array = _hang_to_stage(WebPlan.Stage.DESCEND)
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	ctx.rope.reel_speed = 0.0
	ctx.balance.thread_descend_speed = 0.0  # нить не стравливается: этап не кончится
	plan.stage_sec = ctx.balance.web_stage_timeout_sec - 0.05
	m.update(0.04)
	assert_eq(m.current_id(), HeroState.HANG)
	m.update(0.02)
	assert_eq(m.current_id(), HeroState.FALL, "таймаут этапа DESCEND")


func test_stage_timer_resets_on_stage_change_and_rest_is_exempt() -> void:
	var r: Array = _hang_to_stage(WebPlan.Stage.LOWER)
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	HeroFixture.run_until(m, func() -> bool: return plan.stage == WebPlan.Stage.REST, 30.0)
	assert_lt(plan.stage_sec, 0.2, "таймер этапа обнулён при входе в REST")
	plan.stage_sec = ctx.balance.web_stage_timeout_sec * 10.0
	m.update(DT)
	assert_eq(m.current_id(), HeroState.HANG, "REST ограничен паузой, а не таймаутом этапа")


func test_stretched_time_does_not_count_for_timeout() -> void:
	# stage_sec копится только в update hang; пока тянут, update hang не идёт
	var r: Array = _hang_to_stage(WebPlan.Stage.REST)
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	var before: float = plan.stage_sec
	_grab_above_head(r)
	assert_eq(m.current_id(), HeroState.STRETCHED)
	assert_eq(plan.stage_sec, before)


func test_swing_lowering_timeout_falls() -> void:
	var t: Array = _swing_trip(true)
	var ctx: HeroContext = t[0]
	var plan: WebPlan = t[1]
	var m: HeroStateMachine = t[2]
	plan.release_angle = 10.0  # не отпускать
	ctx.balance.swing_max_sec = 3.0
	HeroFixture.launch(m, ctx, plan)
	HeroFixture.run_until(m, _in_state(m, HeroState.SWING), 5.0)
	var swing_t: float = 0.0
	while m.current_id() == HeroState.SWING and swing_t < 60.0:
		if swing_t > 1.5:
			ctx.rope.reel_speed = 0.0  # подмотка кончилась; стравливание потом не двигает нить
		m.update(DT)
		swing_t += DT
	gut.p("swing: вышел в %s через %.2f с" % [m.current_id(), swing_t])
	assert_eq(m.current_id(), HeroState.FALL, "стравливание не вечное: по таймауту нить рвётся")
	var limit: float = ctx.balance.swing_max_sec + ctx.balance.web_stage_timeout_sec
	assert_between(swing_t, limit - 0.1, limit + 2.0 * DT, "через swing_max_sec + web_stage_timeout_sec")


func test_settled_resets_when_bounds_move_hero() -> void:
	# пол поднялся и прижал героя
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	assert_true(plan.settled)
	assert_gt(m.next_tick_sec(), 0.0)
	ctx.set_bounds(Rect2(0.0, 0.0, 1200.0, ctx.pos.y - 40.0))
	assert_gt(ctx.pos.distance_to(ctx.rope.rest_pos(ctx)), ctx.balance.rope_rest_stretch_px, "границы сдвинули героя")
	m.update(DT)
	assert_false(plan.settled, "физика снова считается")
	assert_eq(m.next_tick_sec(), 0.0, "тикать каждый кадр")
	# сузили область: герой сдвинут по x
	r = HeroFixture.hang_at_rest(TALL)
	ctx = r[0]
	plan = r[1]
	m = r[2]
	ctx.set_bounds(Rect2(ctx.rope.anchor.x - 10.0, 0.0, 300.0, 1400.0))
	assert_gt(ctx.pos.distance_to(ctx.rope.rest_pos(ctx)), ctx.balance.rope_rest_stretch_px)
	m.update(DT)
	assert_false(plan.settled)
	assert_eq(m.next_tick_sec(), 0.0)
	# и через некоторое время замирает снова или пауза кончается
	HeroFixture.run_until(m, _in_state(m, HeroState.IDLE), 90.0)
	assert_eq(m.current_id(), HeroState.IDLE)


func test_settled_kept_when_bounds_change_does_not_move_hero() -> void:
	var r: Array = HeroFixture.hang_at_rest(TALL)
	var ctx: HeroContext = r[0]
	var plan: WebPlan = r[1]
	var m: HeroStateMachine = r[2]
	var pos: Vector2 = ctx.pos
	ctx.set_bounds(Rect2(0.0, 0.0, 1300.0, 1500.0))  # шире и ниже: героя не трогает
	m.update(DT)
	assert_eq(ctx.pos, pos)
	assert_true(plan.settled, "герой не сдвинулся: сон сохраняется")
