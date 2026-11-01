class_name CarriedState
extends HeroState
## Герой в руке курсора. Позицию задаёт ввод, а не update.


func enter() -> void:
	ctx.emotions.show_for(HeroEmotions.Emotion.SCARED, INF)
	ctx.pose = &"carried"
	ctx.carrying = true
	ctx.velocity = Vector2.ZERO


func exit() -> void:
	ctx.carrying = false


func handle_input(input: HeroInput) -> StringName:
	match input.kind:
		HeroInput.Kind.MOVE:
			ctx.pos = ctx.clamp_pos(input.pos + ctx.grab_offset)
			ctx.throw_tracker.add_sample(input.pos, input.now_sec)
		HeroInput.Kind.RESYNC:
			# Курсор пересчитан в другую систему координат: история скоростей недействительна.
			ctx.throw_tracker.reset()
			ctx.pos = ctx.clamp_pos(input.pos + ctx.grab_offset)
			ctx.throw_tracker.add_sample(input.pos, input.now_sec)
		HeroInput.Kind.RELEASE:
			ctx.pos = ctx.clamp_pos(input.pos + ctx.grab_offset)
			# Точка отпускания тоже проба: остановка перед отпусканием гасит скорость.
			ctx.throw_tracker.add_sample(input.pos, input.now_sec)
			var v: Vector2 = ctx.throw_tracker.velocity(input.now_sec)
			if v.length() >= ctx.balance.throw_min_speed:
				ctx.velocity = v
				return THROWN
			ctx.velocity = Vector2.ZERO
			return FALL
		HeroInput.Kind.CANCEL:
			ctx.velocity = Vector2.ZERO
			return FALL
	return NONE
