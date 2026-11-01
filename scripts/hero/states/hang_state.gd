class_name HangState
extends HeroState
## Висит на нитке-пружине. Этапы (WebPlan.Stage): ASCEND (подтянуться к верхнему краю), LOWER (опуститься
## до plan.rest_length), REST (качание гаснет, герой замирает, пауза), DESCEND (вниз до пола, посадка).
## Этап лежит в плане: возврат из stretched продолжает с того же места.

## Допуск на достижение целевой длины (lpx).
const LENGTH_EPSILON: float = 0.5


func enter() -> void:
	ctx.pose = &"hang"
	ctx.contour_top_extra_px = ctx.balance.thread_grab_zone_px
	ctx.emotions.clear_temporary()
	var plan: WebPlan = _ensure_plan()
	if plan.stage == WebPlan.Stage.NONE:
		_begin(WebPlan.Stage.ASCEND)
	else:
		plan.settled = false  # после натяжения пружина отрабатывает заново
		_apply_targets(plan.stage)


func update(delta: float) -> StringName:
	var b: HeroBalance = ctx.balance
	var rope: WebRope = ctx.rope
	var plan: WebPlan = ctx.plan
	if plan == null:
		return NONE
	if plan.stage == WebPlan.Stage.WEAVE:
		return WEAVE  # возврат из stretched во время плетения: продолжаем с того же шага
	plan.stage_sec += delta
	if plan.stage == WebPlan.Stage.REST:
		plan.rest_left_sec -= delta  # пауза идёт всегда; settled разрешает только сон
		if plan.settled and ctx.pos.distance_to(rope.rest_pos(ctx)) > b.rope_rest_stretch_px:
			plan.settled = false  # границы сдвинули героя: снова считаем физику
		if plan.rest_left_sec <= 0.0:
			_begin(WebPlan.Stage.DESCEND)
			return NONE
		if plan.settled:
			return NONE
	elif plan.stage_sec > b.web_stage_timeout_sec:
		return FALL  # этап не кончается (например, область изменилась): нить рвётся
	if plan.stage == WebPlan.Stage.DESCEND:
		rope.target_length = _floor_length()  # пол мог сместиться
	rope.advance(ctx, minf(delta, b.max_step_sec))
	ctx.lean = clampf(-rope.angle(ctx), -b.swing_lean_max_rad, b.swing_lean_max_rad)
	if rope.touched_floor or (plan.stage == WebPlan.Stage.DESCEND and ctx.pos.y >= ctx.floor_y() - HeroContext.FLOOR_EPSILON):
		ctx.last_impact_speed = maxf(ctx.velocity.y, 0.0)
		ctx.velocity.y = 0.0
		return LAND
	match plan.stage:
		WebPlan.Stage.ASCEND:
			if rope.length <= rope.target_length + LENGTH_EPSILON:
				if plan.kind == WebPlan.Kind.WEAVE_TOP:
					plan.stage = WebPlan.Stage.WEAVE
					plan.settled = false
					plan.stage_sec = 0.0
					return WEAVE
				_begin(WebPlan.Stage.LOWER)
		WebPlan.Stage.LOWER:
			if absf(rope.length - rope.target_length) <= LENGTH_EPSILON:
				_begin(WebPlan.Stage.REST)
		WebPlan.Stage.REST:
			if rope.is_settled(ctx):
				rope.settle(ctx)
				ctx.lean = clampf(-rope.angle(ctx), -b.swing_lean_max_rad, b.swing_lean_max_rad)  # без скачка позы при замирании
				plan.settled = true
	return NONE


func handle_input(input: HeroInput) -> StringName:
	if input.kind != HeroInput.Kind.PRESS or ctx.carrying:
		return NONE
	if not ctx.contour_rect().has_point(input.pos):
		return NONE
	ctx.grab_offset = ctx.pos - input.pos
	ctx.throw_tracker.reset()
	ctx.throw_tracker.add_sample(input.pos, input.now_sec)
	return STRETCHED


## 0: тикать; в REST после замирания: остаток паузы.
func next_tick_sec() -> float:
	var plan: WebPlan = ctx.plan
	if plan != null and plan.stage == WebPlan.Stage.REST and plan.settled:
		return maxf(plan.rest_left_sec, 0.0)
	return 0.0


func _ensure_plan() -> WebPlan:
	if ctx.plan == null:
		# вход без плана (например, из теста): спуск до середины доступной длины
		var plan := WebPlan.new()
		plan.kind = WebPlan.Kind.DESCENT
		plan.anchor = ctx.rope.anchor
		var full: float = maxf(ctx.floor_y() - plan.anchor.y - ctx.hand_offset().length(), ctx.balance.hang_top_gap_px)
		plan.rest_length = full * ctx.balance.hang_default_rest_ratio
		ctx.plan = plan
	return ctx.plan


func _begin(stage: WebPlan.Stage) -> void:
	var plan: WebPlan = ctx.plan
	if stage == WebPlan.Stage.LOWER and plan.rest_length <= ctx.rope.length + LENGTH_EPSILON:
		stage = WebPlan.Stage.REST  # уже ниже точки остановки
	plan.stage = stage
	plan.settled = false
	plan.stage_sec = 0.0
	if stage == WebPlan.Stage.REST:
		plan.rest_left_sec = ctx.rng.randf_range(ctx.balance.hang_rest_min_sec, ctx.balance.hang_rest_max_sec)
	_apply_targets(stage)


func _apply_targets(stage: WebPlan.Stage) -> void:
	var b: HeroBalance = ctx.balance
	var rope: WebRope = ctx.rope
	match stage:
		WebPlan.Stage.ASCEND:
			rope.target_length = maxf(rope.anchor.y - ctx.bounds.position.y, 0.0) + b.hang_top_gap_px
			rope.reel_speed = b.thread_ascend_speed
		WebPlan.Stage.LOWER:
			rope.target_length = ctx.plan.rest_length
			rope.reel_speed = b.thread_descend_speed
		WebPlan.Stage.REST:
			rope.target_length = rope.length
		WebPlan.Stage.DESCEND:
			rope.target_length = _floor_length()
			rope.reel_speed = b.thread_descend_speed


## Длина нити, при которой ступни касаются пола.
func _floor_length() -> float:
	return maxf(ctx.floor_y() - ctx.rope.anchor.y - ctx.hand_offset().length(), 0.0)
