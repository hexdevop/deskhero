class_name WalkState
extends HeroState
## Идёт в случайную сторону на случайное расстояние, у стены разворачивается.

## Уже этой ширины хода нет смысла гулять.
const MIN_WALK_SPAN_PX: float = 1.0

var remaining_px: float = 0.0


func enter() -> void:
	ctx.pose = &"walk"
	ctx.velocity = Vector2.ZERO
	ctx.facing = 1 if ctx.rng.randi() % 2 == 0 else -1
	remaining_px = ctx.rng.randf_range(ctx.balance.walk_distance_min_px, ctx.balance.walk_distance_max_px)


func update(delta: float) -> StringName:
	var b: HeroBalance = ctx.balance
	var half_w: float = b.body_size_px.x * 0.5
	var min_x: float = ctx.bounds.position.x + half_w
	var max_x: float = ctx.bounds.end.x - half_w
	if max_x - min_x < MIN_WALK_SPAN_PX:
		return IDLE
	var target_x: float = ctx.pos.x + float(ctx.facing) * b.walk_speed * delta
	var hit_wall: bool = target_x < min_x or target_x > max_x
	target_x = clampf(target_x, min_x, max_x)
	var moved: float = absf(target_x - ctx.pos.x)
	ctx.pos.x = target_x
	remaining_px -= moved
	ctx.walk_phase = fposmod(ctx.walk_phase + moved / b.walk_stride_px, 1.0)
	if remaining_px <= 0.0:
		return IDLE
	if hit_wall:
		ctx.facing = -ctx.facing
	return NONE
