class_name GroundedState
extends HeroState
## Группа: ноги на полу. Поднялся пол: подтянуть; опустился: падать.


func next_tick_sec() -> float:
	return INF


func update(_delta: float) -> StringName:
	var floor_y: float = ctx.floor_y()
	if ctx.pos.y > floor_y:
		ctx.pos.y = floor_y
	elif ctx.pos.y < floor_y - HeroContext.FLOOR_EPSILON:
		return FALL
	return NONE
