class_name SwingState
extends HeroState
## Маятник на жёсткой нити: подмотка до plan.swing_length, затухание, отпускание на выходе вперёд и вверх.
## Конец: пол, стена, подходящий момент отпускания или swing_max_sec (тогда спуск к полу).

## Скорость по x, ниже которой направление взгляда не меняется.
const FACING_MIN_SPEED: float = 30.0

var _elapsed_sec: float = 0.0
var _lowering: bool = false
var _lowering_sec: float = 0.0


func enter() -> void:
	ctx.pose = &"swing"
	_elapsed_sec = 0.0
	_lowering = false
	_lowering_sec = 0.0
	var rope: WebRope = ctx.rope
	if ctx.plan != null:
		rope.target_length = ctx.plan.swing_length
	rope.reel_speed = ctx.balance.swing_reel_speed
	ctx.emotions.clear_temporary()


func update(delta: float) -> StringName:
	var b: HeroBalance = ctx.balance
	var rope: WebRope = ctx.rope
	rope.advance(ctx, minf(delta, b.max_step_sec))
	_elapsed_sec += delta
	ctx.lean = clampf(-rope.angle(ctx), -b.swing_lean_max_rad, b.swing_lean_max_rad)
	if absf(ctx.velocity.x) > FACING_MIN_SPEED:
		ctx.facing = 1 if ctx.velocity.x > 0.0 else -1
	# после swing_max_sec нить стравливается до пола: касание без удара тоже посадка
	if rope.touched_floor or (_lowering and ctx.pos.y >= ctx.floor_y() - HeroContext.FLOOR_EPSILON):
		ctx.last_impact_speed = maxf(ctx.velocity.y, 0.0)
		ctx.velocity.y = 0.0
		return LAND
	if rope.touched_wall:
		return FALL
	if _can_release():
		return FALL
	if _elapsed_sec >= b.swing_max_sec:
		_lowering = true
	if _lowering:
		# нить стравливается до пола; пол мог сместиться, поэтому цель пересчитывается
		_lowering_sec += delta
		rope.target_length = maxf(ctx.floor_y() - rope.anchor.y - ctx.hand_offset().length(), 0.0)
		if _lowering_sec > b.web_stage_timeout_sec:
			return FALL
	return NONE


func _can_release() -> bool:
	if ctx.plan == null:
		return false
	var b: HeroBalance = ctx.balance
	var angle: float = ctx.rope.angle(ctx)
	var moving_away: bool = ctx.velocity.x * angle > 0.0 and ctx.velocity.y < 0.0
	if not moving_away or absf(angle) < ctx.plan.release_angle:
		return false
	var impact: float = WebPlanner.predicted_impact(ctx.pos, ctx.velocity, ctx.floor_y(), b.gravity, b.max_fall_speed)
	if impact >= b.hard_landing_speed * b.swing_safe_impact_ratio:
		return false
	var land_x: float = WebPlanner.predicted_land_x(ctx.pos, ctx.velocity, ctx.floor_y(), b.gravity)
	var half_w: float = b.body_size_px.x * 0.5
	return land_x >= ctx.bounds.position.x + half_w and land_x <= ctx.bounds.end.x - half_w
