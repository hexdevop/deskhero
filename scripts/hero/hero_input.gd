class_name HeroInput
extends RefCounted
## Значение ввода для машины состояний. Координаты в lpx, система окна.

enum Kind { PRESS, MOVE, RELEASE, CANCEL, RESYNC }

var kind: Kind = Kind.MOVE
var pos: Vector2 = Vector2.ZERO
var now_sec: float = 0.0


static func make(p_kind: Kind, p_pos: Vector2, p_now_sec: float) -> HeroInput:
	var input := HeroInput.new()
	input.kind = p_kind
	input.pos = p_pos
	input.now_sec = p_now_sec
	return input
