class_name WebPlan
extends RefCounted
## Что герой задумал: значение без логики. Заполняет WebPlanner, читают shoot_web, swing, hang.

enum Kind { SWING, DESCENT, WEAVE_TOP, WEAVE_BOTTOM }
## Этап подвеса (читает hang). Хранится в плане, чтобы переход hang -> stretched -> hang не терял место.
enum Stage { NONE, ASCEND, LOWER, REST, DESCEND, WEAVE }

var kind: Kind = Kind.SWING
var anchor: Vector2 = Vector2.ZERO
## NAN: идти не надо.
var walk_to_x: float = NAN
## CornerWebField.Corner или -1.
var corner: int = -1
var swing_length: float = 0.0
## DESCENT: длина нити, на которой герой останавливается.
var rest_length: float = 0.0
var release_angle: float = 0.0

## Ход выполнения подвеса.
var stage: Stage = Stage.NONE
var rest_left_sec: float = 0.0
var settled: bool = false
## Сколько секунд идёт текущий этап (страховка web_stage_timeout_sec).
var stage_sec: float = 0.0
## Плетение уже занято углом (begin_weave вызван): возврат из stretched не начинает его заново.
var weave_started: bool = false


func needs_walk() -> bool:
	return not is_nan(walk_to_x)
