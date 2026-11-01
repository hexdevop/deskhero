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
