class_name LandState
extends HeroState
## Посадка: гасит горизонтальную скорость, длится land_soft_sec или land_hard_sec.

var remaining_sec: float = 0.0
var hard: bool = false
var total_sec: float = 0.0


func enter() -> void:
	ctx.pose = &"land"
	var speed: float = ctx.last_impact_speed
	hard = speed >= ctx.balance.hard_landing_speed
	total_sec = ctx.balance.land_hard_sec if hard else ctx.balance.land_soft_sec
	remaining_sec = total_sec
	ctx.land_progress = 0.0
	ctx.emotions.clear_temporary()
	if hard:
		ctx.emotions.offend()
		ctx.hard_landed.emit(speed)
	else:
		ctx.emotions.show_for(HeroEmotions.Emotion.HAPPY, ctx.balance.happy_sec)
		ctx.soft_landed.emit()


func update(delta: float) -> StringName:
	ctx.velocity.x *= exp(-ctx.balance.land_friction * delta)  # экспонента: не зависит от длины кадра
	var half_w: float = ctx.balance.body_size_px.x * 0.5
	var min_x: float = ctx.bounds.position.x + half_w
	var max_x: float = ctx.bounds.end.x - half_w
	var nx: float = ctx.pos.x + ctx.velocity.x * delta
	if nx < min_x or nx > max_x:
		nx = clampf(nx, min_x, max_x)
		ctx.velocity.x = 0.0
	ctx.pos.x = nx
	remaining_sec -= delta
	ctx.land_progress = clampf(1.0 - remaining_sec / total_sec, 0.0, 1.0) if total_sec > 0.0 else 1.0
	if remaining_sec <= 0.0:
		return IDLE
	return NONE
