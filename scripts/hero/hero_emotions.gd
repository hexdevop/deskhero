class_name HeroEmotions
extends RefCounted
## Эмоции героя. Обида — таймер, а не состояние: пока она идёт, видна OFFENDED
## и запрещены прогулки. Время приходит снаружи через tick().

enum Emotion { NEUTRAL, HAPPY, SCARED, OFFENDED }

signal changed(emotion: Emotion)

var _balance: HeroBalance
var _temp: Emotion = Emotion.NEUTRAL
var _temp_remaining: float = 0.0
var _sulk_remaining: float = 0.0
var _visible: Emotion = Emotion.NEUTRAL


func _init(balance: HeroBalance) -> void:
	_balance = balance


## Видимая эмоция: обида важнее всех остальных.
func current() -> Emotion:
	return _visible


## Временная эмоция на sec секунд (INF: пока не снимут). Обиду не перекрывает: она станет видна после обиды.
func show_for(emotion: Emotion, sec: float) -> void:
	if emotion == Emotion.NEUTRAL or emotion == Emotion.OFFENDED or sec <= 0.0:
		clear_temporary()
		return
	_temp = emotion
	_temp_remaining = sec
	_refresh()


func clear_temporary() -> void:
	_temp = Emotion.NEUTRAL
	_temp_remaining = 0.0
	_refresh()


## Жёсткая посадка: обида растёт на sulk_sec, но не выше sulk_max_sec.
func offend() -> void:
	_sulk_remaining = minf(_sulk_remaining + _balance.sulk_sec, _balance.sulk_max_sec)
	_refresh()


func is_sulking() -> bool:
	return _sulk_remaining > 0.0


func sulk_remaining_sec() -> float:
	return _sulk_remaining


func tick(delta: float) -> void:
	if _sulk_remaining > 0.0:
		_sulk_remaining = maxf(_sulk_remaining - delta, 0.0)
	if _temp != Emotion.NEUTRAL and not is_inf(_temp_remaining):
		_temp_remaining -= delta
		if _temp_remaining <= 0.0:
			_temp = Emotion.NEUTRAL
			_temp_remaining = 0.0
	_refresh()


## Через сколько секунд эмоция сменится сама; INF, если таймеров нет.
func next_change_sec() -> float:
	var result: float = INF
	if _sulk_remaining > 0.0:
		result = _sulk_remaining
	if _temp != Emotion.NEUTRAL and not is_inf(_temp_remaining):
		result = minf(result, _temp_remaining)
	return result


func _refresh() -> void:
	var now: Emotion = Emotion.OFFENDED if is_sulking() else _temp
	if now != _visible:
		_visible = now
		changed.emit(now)
