class_name IdleState
extends HeroState
## Стоит и считает паузу до прогулки. Обида запрещает прогулки.

var remaining_sec: float = 0.0


func enter() -> void:
	ctx.pose = &"idle"
	ctx.velocity = Vector2.ZERO
	remaining_sec = ctx.rng.randf_range(ctx.balance.idle_pause_min_sec, ctx.balance.idle_pause_max_sec)


func update(delta: float) -> StringName:
	remaining_sec -= delta
	if remaining_sec <= 0.0 and not ctx.is_sulking():
		return WALK
	return NONE


func next_tick_sec() -> float:
	if ctx.is_sulking():
		return INF
	return maxf(remaining_sec, 0.0)
