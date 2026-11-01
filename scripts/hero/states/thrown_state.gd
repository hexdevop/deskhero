class_name ThrownState
extends HeroState
## Бросок: к физике airborne добавляется сопротивление воздуха.


func enter() -> void:
	ctx.emotions.show_for(HeroEmotions.Emotion.SCARED, INF)
	ctx.pose = &"thrown"


func update(delta: float) -> StringName:
	ctx.velocity *= maxf(0.0, 1.0 - ctx.balance.air_drag * delta)
	return NONE
