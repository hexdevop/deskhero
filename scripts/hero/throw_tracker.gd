class_name ThrowTracker
extends RefCounted
## Скорость курсора по последним пробам, для броска. Время приходит снаружи.

## Меньший интервал между пробами — дрожание, а не движение: скорость ноль.
const MIN_SAMPLE_DT_SEC: float = 0.005
## Пробы хранятся за это число окон.
const HISTORY_WINDOWS: float = 2.0

var _balance: HeroBalance
var _positions: Array[Vector2] = []
var _times: Array[float] = []


func _init(balance: HeroBalance) -> void:
	_balance = balance


func reset() -> void:
	_positions.clear()
	_times.clear()


func sample_count() -> int:
	return _times.size()


func add_sample(pos: Vector2, now_sec: float) -> void:
	_positions.append(pos)
	_times.append(now_sec)
	_prune(now_sec)


## Скорость по пробам в окне [now_sec - window, now_sec]. Меньше двух разных моментов: ноль.
func velocity(now_sec: float) -> Vector2:
	var from_time: float = now_sec - _balance.throw_sample_window_sec
	var first: int = -1
	var last: int = -1
	for i in _times.size():
		if _times[i] >= from_time and _times[i] <= now_sec:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return Vector2.ZERO
	# Единственная проба в окне (например, точка отпускания после паузы без MOVE):
	# курсор мог сместиться за паузу, берём прошлую пробу как начало (средняя скорость).
	if last == first and first > 0:
		first -= 1
	if last <= first:
		return Vector2.ZERO
	var dt: float = _times[last] - _times[first]
	if dt < MIN_SAMPLE_DT_SEC:
		return Vector2.ZERO
	var v: Vector2 = (_positions[last] - _positions[first]) / dt
	return v.limit_length(_balance.throw_max_speed)


func _prune(now_sec: float) -> void:
	# Пробы старше окна не нужны: храним с запасом в одно окно.
	var from_time: float = now_sec - _balance.throw_sample_window_sec * HISTORY_WINDOWS
	while not _times.is_empty() and _times[0] < from_time:
		_times.remove_at(0)
		_positions.remove_at(0)
