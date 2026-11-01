class_name FallState
extends HeroState
## Обычное падение. Физику ведёт airborne.


func enter() -> void:
	ctx.pose = &"fall"
