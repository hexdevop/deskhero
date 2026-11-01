class_name RootState
extends HeroState
## Корень: захват курсором из любого состояния.


func next_tick_sec() -> float:
	return INF


func handle_input(input: HeroInput) -> StringName:
	if input.kind != HeroInput.Kind.PRESS or ctx.carrying:
		return NONE
	if not ctx.contour_rect().has_point(input.pos):
		return NONE
	ctx.grab_offset = ctx.pos - input.pos
	ctx.throw_tracker.reset()
	ctx.throw_tracker.add_sample(input.pos, input.now_sec)
	return CARRIED
