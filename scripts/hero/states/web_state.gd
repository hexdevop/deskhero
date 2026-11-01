class_name WebState
extends HeroState
## Группа: герой на нити. Выход из группы рвёт нить, поэтому shoot_web -> swing её не трогает.


func next_tick_sec() -> float:
	return INF


func exit() -> void:
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
