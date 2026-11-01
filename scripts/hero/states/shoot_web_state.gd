class_name ShootWebState
extends HeroState
## Замах, затем полёт кончика к якорю; попал: swing для SWING, иначе hang.

var _windup_left: float = 0.0
var _shot: bool = false


func enter() -> void:
	ctx.pose = &"shoot_web"
	ctx.velocity = Vector2.ZERO
	ctx.emotions.clear_temporary()
	_windup_left = ctx.balance.web_shoot_windup_sec
	_shot = false
	if ctx.plan != null:
		var dir: float = ctx.plan.anchor.x - ctx.pos.x
		if absf(dir) > 0.01:
			ctx.facing = 1 if dir > 0.0 else -1


func update(delta: float) -> StringName:
	var plan: WebPlan = ctx.plan
	if plan == null:
		return IDLE
	if not _shot:
		_windup_left -= delta
		if _windup_left <= 0.0:
			ctx.rope.shoot(plan.anchor)
			_shot = true
		return NONE
	if not ctx.rope.tip_arrived():
		return NONE
	if not ctx.rope.anchor_valid(ctx.bounds):
		return IDLE  # область сменилась за время полёта
	if plan.kind == WebPlan.Kind.SWING:
		ctx.rope.attach(ctx, WebRope.Mode.HARD)
		return SWING
	ctx.rope.attach(ctx, WebRope.Mode.SPRING)
	return HANG
