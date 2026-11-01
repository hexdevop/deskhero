class_name WebState
extends HeroState
## Группа: герой на нити. Выход из группы рвёт нить, поэтому shoot_web -> swing её не трогает.


func next_tick_sec() -> float:
	return INF


func exit() -> void:
	var plan: WebPlan = ctx.plan
	if plan != null and plan.corner >= 0 and ctx.corners.is_weaving(plan.corner):
		ctx.corners.cancel_weave(plan.corner)  # выход из группы: плетение прервано, угол снова доступен
		ctx.weave_cooldown_sec = ctx.balance.weave_retry_sec
	ctx.rope.sync_hand(ctx.hand_pos())  # оборванная нить уходит от руки этого кадра
	ctx.rope.release()  # безопасно, если нить уже оборвана или не выстрелена
	ctx.plan = null
	ctx.lean = 0.0
	ctx.contour_top_extra_px = 0.0


func update(_delta: float) -> StringName:
	var rope: WebRope = ctx.rope
	if rope.phase == WebRope.Phase.ATTACHED:
		if not rope.anchor_valid(ctx.bounds):
			return FALL
	elif ctx.pos.y < ctx.floor_y() - HeroContext.FLOOR_EPSILON:
		return FALL
	return NONE
