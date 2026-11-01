class_name AirborneState
extends HeroState
## Группа: полёт. Гравитация, стены, потолок, пол. Лист (fall, thrown) вызывается раньше.


func enter() -> void:
	ctx.last_impact_speed = 0.0


func update(delta: float) -> StringName:
	var b: HeroBalance = ctx.balance
	ctx.velocity.y = minf(ctx.velocity.y + b.gravity * delta, b.max_fall_speed)
	ctx.pos += ctx.velocity * delta
	var half_w: float = b.body_size_px.x * 0.5
	var min_x: float = ctx.bounds.position.x + half_w
	var max_x: float = ctx.bounds.end.x - half_w
	if min_x > max_x:
		ctx.pos.x = (min_x + max_x) * 0.5
		ctx.velocity.x = 0.0
	elif ctx.pos.x < min_x:
		ctx.pos.x = min_x
		ctx.velocity.x = absf(ctx.velocity.x) * b.wall_restitution
	elif ctx.pos.x > max_x:
		ctx.pos.x = max_x
		ctx.velocity.x = -absf(ctx.velocity.x) * b.wall_restitution
	var min_y: float = ctx.bounds.position.y + b.body_size_px.y
	if ctx.pos.y < min_y:
		ctx.pos.y = min_y
		ctx.velocity.y = absf(ctx.velocity.y) * b.wall_restitution
	if ctx.pos.y >= ctx.floor_y():
		ctx.pos.y = ctx.floor_y()
		ctx.last_impact_speed = maxf(ctx.velocity.y, 0.0)
		ctx.velocity.y = 0.0
		return LAND
	return NONE
