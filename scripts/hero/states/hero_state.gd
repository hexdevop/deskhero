class_name HeroState
extends RefCounted
## База состояний. Переход возвращается id следующего состояния, &"" значит остаться.

const NONE: StringName = &""
const ROOT: StringName = &"root"
const GROUNDED: StringName = &"grounded"
const AIRBORNE: StringName = &"airborne"
const IDLE: StringName = &"idle"
const WALK: StringName = &"walk"
const LAND: StringName = &"land"
const FALL: StringName = &"fall"
const THROWN: StringName = &"thrown"
const CARRIED: StringName = &"carried"
const WEB: StringName = &"web"
const SHOOT_WEB: StringName = &"shoot_web"
const SWING: StringName = &"swing"
const HANG: StringName = &"hang"
const STRETCHED: StringName = &"stretched"
const WEAVE: StringName = &"weave"


## Герой в руке курсора (carried) или на растянутой нити (stretched): drag_started и drag_ended.
static func is_drag(state_id: StringName) -> bool:
	return state_id == CARRIED or state_id == STRETCHED


## Быстрое движение: Overlay держит motion_fps (D-013).
static func is_fast(state_id: StringName) -> bool:
	return state_id == FALL or state_id == THROWN or state_id == CARRIED \
		or state_id == SWING or state_id == STRETCHED


var id: StringName = NONE
var ctx: HeroContext
var parent: HeroState


func enter() -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> StringName:
	return NONE


func handle_input(_input: HeroInput) -> StringName:
	return NONE


## 0: тикать каждый кадр; >0: до этого времени ничего не изменится; INF: до внешнего события.
func next_tick_sec() -> float:
	return 0.0
