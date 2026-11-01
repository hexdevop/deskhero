class_name WeaveState
extends HeroState
## Плетение паутины в углу (D-012, п. 6). Верхний угол: герой висит на нитке у верхнего края (WEAVE_TOP),
## нижний: стоит у стены (WEAVE_BOTTOM). Шаг раз в weave_step_sec; поза меняется только на шагах,
## между ними герой спит: next_tick_sec равен остатку шага. Пока висящий герой ещё качается, кадры идут как в hang.

var _step_left: float = 0.0
var _hanging: bool = false
var _aborted: bool = false
var _phase_flip: bool = false


func enter() -> void:
	var plan: WebPlan = ctx.plan
	_aborted = plan == null
	_step_left = ctx.balance.weave_step_sec
	_phase_flip = false
	ctx.emotions.clear_temporary()
	ctx.walk_phase = 0.0
	if plan == null:
		ctx.pose = &"weave"
		return
	_hanging = plan.kind == WebPlan.Kind.WEAVE_TOP
	ctx.facing = -1 if CornerWebField.is_left(plan.corner) else 1
	if _hanging:
		ctx.pose = HeroContext.POSE_WEAVE_HANG
		ctx.contour_top_extra_px = ctx.balance.thread_grab_zone_px
		plan.stage = WebPlan.Stage.WEAVE
		plan.settled = false
		ctx.rope.target_length = ctx.rope.length  # подмотка закончена: нить держит длину
	else:
		ctx.pose = &"weave"
		ctx.velocity = Vector2.ZERO
	if not plan.weave_started:
		plan.weave_started = true
		if not ctx.corners.begin_weave(plan.corner):
			_aborted = true  # угол успел занять кто-то другой


func update(delta: float) -> StringName:
	var b: HeroBalance = ctx.balance
	var plan: WebPlan = ctx.plan
	if _aborted or plan == null:
		return _finish(false)
	if _hanging:
		var rope: WebRope = ctx.rope
		if plan.settled and ctx.pos.distance_to(rope.rest_pos(ctx)) > b.rope_rest_stretch_px:
			plan.settled = false  # границы сдвинули героя: снова считаем физику
		if not plan.settled:
			rope.advance(ctx, minf(delta, b.max_step_sec))
			ctx.lean = clampf(-rope.angle(ctx), -b.swing_lean_max_rad, b.swing_lean_max_rad)
			if rope.touched_floor:
				ctx.last_impact_speed = maxf(ctx.velocity.y, 0.0)
				ctx.velocity.y = 0.0
				return LAND
			if rope.is_settled(ctx):
				rope.settle(ctx)
				ctx.lean = clampf(-rope.angle(ctx), -b.swing_lean_max_rad, b.swing_lean_max_rad)
				plan.settled = true
	_step_left -= delta
	while _step_left <= 0.0:
		_step_left += b.weave_step_sec
		_phase_flip = not _phase_flip
		ctx.walk_phase = 0.5 if _phase_flip else 0.0
		if ctx.corners.weave_step(plan.corner):
			return _finish(true)
	return NONE


func handle_input(input: HeroInput) -> StringName:
	if not _hanging or input.kind != HeroInput.Kind.PRESS or ctx.carrying:
		return NONE  # на полу захват берёт root
	if not ctx.contour_rect().has_point(input.pos):
		return NONE
	ctx.grab_offset = ctx.pos - input.pos
	ctx.throw_tracker.reset()
	ctx.throw_tracker.add_sample(input.pos, input.now_sec)
	return STRETCHED


## Идёт шаг или нужны кадры физики: 0 только пока висящий герой не замер.
func next_tick_sec() -> float:
	var plan: WebPlan = ctx.plan
	if _hanging and plan != null and not plan.settled:
		return 0.0
	return maxf(_step_left, 0.0)


## Верхний угол: герой спускается на пол. Нижний: стоит. Время без помех сбрасывается, следующее плетение не скоро.
func _finish(woven: bool) -> StringName:
	var plan: WebPlan = ctx.plan
	if woven:
		ctx.calm_sec = 0.0
	if _hanging and plan != null and ctx.rope.phase == WebRope.Phase.ATTACHED:
		plan.stage = WebPlan.Stage.DESCEND
		plan.settled = false
		plan.stage_sec = 0.0
		return HANG
	if _hanging:
		return FALL
	return IDLE
