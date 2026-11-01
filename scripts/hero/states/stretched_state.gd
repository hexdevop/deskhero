class_name StretchedState
extends HeroState
## Нитку тянут за героя. Герой следует за курсором до thread_max_stretch_px сверх длины, дальше упирается
## в предел по лучу от якоря. За пределом + thread_snap_extra_px нить рвётся, герой остаётся в руке (carried).
## Физику не ведёт: растяжение уже в геометрии, пружина отработает в hang.


func enter() -> void:
	ctx.emotions.show_for(HeroEmotions.Emotion.SCARED, INF)
	ctx.pose = &"stretched"
	ctx.carrying = true
	ctx.velocity = Vector2.ZERO


func exit() -> void:
	ctx.carrying = false
	ctx.emotions.clear_temporary()


func update(_delta: float) -> StringName:
	if not ctx.rope.anchor_valid(ctx.bounds):
		_snap()
		return CARRIED
	return NONE


func handle_input(input: HeroInput) -> StringName:
	var b: HeroBalance = ctx.balance
	var rope: WebRope = ctx.rope
	match input.kind:
		HeroInput.Kind.MOVE:
			var target: Vector2 = ctx.clamp_pos(input.pos + ctx.grab_offset)
			var offset: Vector2 = ctx.hand_offset()
			var d: Vector2 = target + offset - rope.anchor
			var r: float = d.length()
			var max_r: float = rope.length + b.thread_max_stretch_px
			if r > max_r + b.thread_snap_extra_px:
				ctx.pos = target
				ctx.throw_tracker.add_sample(input.pos, input.now_sec)
				_snap()
				return CARRIED
			if r > max_r and r > 0.0:
				target = ctx.clamp_pos(rope.anchor + d / r * max_r - offset)
			ctx.pos = target
			ctx.throw_tracker.add_sample(input.pos, input.now_sec)
		HeroInput.Kind.RESYNC:
			# якорь принадлежит прежней системе координат (смена монитора): рвём
			ctx.throw_tracker.reset()
			ctx.pos = ctx.clamp_pos(input.pos + ctx.grab_offset)
			ctx.throw_tracker.add_sample(input.pos, input.now_sec)
			_snap()
			return CARRIED
		HeroInput.Kind.RELEASE, HeroInput.Kind.CANCEL:
			ctx.velocity = Vector2.ZERO
			return HANG
	return NONE


func _snap() -> void:
	ctx.rope.hand = ctx.hand_pos()
	ctx.rope.snap()
