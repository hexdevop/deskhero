class_name CornerWebField
extends RefCounted
## Паутина в четырёх углах рабочей области (D-012, п. 5, 6). Без сцены: сплетение шагами, смахивание, падающие нити.
## Нить угла хранится локально: начало в углу, x и y растут внутрь области. В глобальные координаты (lpx окна)
## её переводит draw_data(), поэтому set_bounds не пересчитывает геометрию. Рисует CornerWebsView.

enum Corner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }
enum Kind { SPOKE, RING }

const CORNER_COUNT: int = 4
## Устройство узора (вид, не поведение): число лучей и верхний предел колец.
const SPOKES_MIN: int = 4
const SPOKES_MAX: int = 5
const RINGS_MAX: int = 8
## Лучи у самых стен, рад от стены.
const EDGE_ANGLE_MIN: float = 0.03
const EDGE_ANGLE_JITTER: float = 0.1
## Длина луча относительно радиуса паутины.
const SPOKE_LENGTH_MIN: float = 0.86
## Внешнее кольцо и разброс радиуса кольца относительно шага.
const RING_OUTER: float = 0.84
const RING_INNER: float = 0.2
const RING_JITTER: float = 0.07
## Провис кольца между лучами: точка хорды тянется к углу.
const RING_SAG: float = 0.07
## Падение смахнутой нити: ускорение как доля gravity и снос по x, lpx/с.
const FALL_ACCEL_RATIO: float = 0.2
const FALL_DRIFT: float = 26.0

signal woven(corner: int)
signal swept(corner: int)


## Отрезок для вида: точки в глобальных lpx окна, прозрачность и толщина.
class Line:
	var points: PackedVector2Array = PackedVector2Array()
	var alpha: float = 1.0
	var width: float = 1.0
	var kind: Kind = Kind.SPOKE


class Stroke:
	var points: PackedVector2Array = PackedVector2Array()
	var kind: Kind = Kind.SPOKE
	var order: int = 1
	var alive: bool = true


class Falling:
	var points: PackedVector2Array = PackedVector2Array()
	var kind: Kind = Kind.SPOKE
	var age: float = 0.0
	var drift: float = 0.0


class CornerState:
	var strokes: Array[Stroke] = []
	var step: int = 0
	var weaving: bool = false


## Растёт при любом видимом изменении: вид перерисовывается только по нему.
var revision: int = 0

var _balance: HeroBalance
var _rng: RandomNumberGenerator
var _bounds: Rect2 = Rect2(0.0, 0.0, 800.0, 600.0)
var _states: Array[CornerState] = []
var _falling: Array[Falling] = []


func _init(p_balance: HeroBalance, p_rng: RandomNumberGenerator) -> void:
	_balance = p_balance
	_rng = p_rng
	for i: int in CORNER_COUNT:
		_states.append(CornerState.new())


static func is_top(corner: int) -> bool:
	return corner == Corner.TOP_LEFT or corner == Corner.TOP_RIGHT


static func is_left(corner: int) -> bool:
	return corner == Corner.TOP_LEFT or corner == Corner.BOTTOM_LEFT


## Начала углов считаются от bounds, нити локальны.
func set_bounds(bounds: Rect2) -> void:
	if bounds == _bounds:
		return
	_bounds = bounds
	if has_webs() or not _falling.is_empty():
		revision += 1


func get_bounds() -> Rect2:
	return _bounds


## Угол не занят: ни готовой паутины, ни плетения.
func is_free(corner: int) -> bool:
	if corner < 0 or corner >= CORNER_COUNT:
		return false
	var st: CornerState = _states[corner]
	return st.strokes.is_empty() and not st.weaving


func is_weaving(corner: int) -> bool:
	return corner >= 0 and corner < CORNER_COUNT and _states[corner].weaving


func free_corners() -> Array[int]:
	var out: Array[int] = []
	for i: int in CORNER_COUNT:
		if is_free(i):
			out.append(i)
	return out


## Есть хоть одна видимая живая нить: тогда Overlay опрашивает курсор.
func has_webs() -> bool:
	for i: int in CORNER_COUNT:
		if _alive_count(_states[i]) > 0:
			return true
	return false


## Сколько нитей угла видно сейчас (для тестов и вида).
func visible_count(corner: int) -> int:
	return _alive_count(_states[corner])


## Сколько нитей угла уже показано за всё время (живых и смахнутых).
func shown_count(corner: int) -> int:
	var n: int = 0
	for s: Stroke in _states[corner].strokes:
		if s.order <= _states[corner].step:
			n += 1
	return n


func step_of(corner: int) -> int:
	return _states[corner].step


## Занимает угол и задумывает узор. false, если угол занят.
func begin_weave(corner: int) -> bool:
	if not is_free(corner):
		return false
	var st: CornerState = _states[corner]
	st.strokes = _generate()
	st.step = 0
	st.weaving = true
	return true


## Плетение прервано (героя схватили, нить порвалась, область сменилась). Угол освобождается: без единого шага
## узор невидим и стирается, иначе остаётся недоплетённая паутина, которую можно смахнуть.
func cancel_weave(corner: int) -> void:
	if corner < 0 or corner >= CORNER_COUNT:
		return
	var st: CornerState = _states[corner]
	if not st.weaving:
		return
	st.weaving = false
	if st.step == 0:
		st.strokes = []


## Один шаг плетения. true: плетение окончено (или угол освобождён смахиванием, тогда woven не шлётся).
func weave_step(corner: int) -> bool:
	if corner < 0 or corner >= CORNER_COUNT:
		return true
	var st: CornerState = _states[corner]
	if not st.weaving:
		return true
	st.step += 1
	revision += 1
	if st.step >= _balance.weave_steps:
		st.weaving = false
		woven.emit(corner)
		return true
	return false


## Курсор прошёл отрезок from-to за dt секунд (глобальные lpx окна). true: что-то изменилось.
func sweep(from: Vector2, to: Vector2, dt: float) -> bool:
	if dt <= 0.0 or from.distance_to(to) / dt < _balance.sweep_min_speed:
		return false
	var changed: bool = false
	for corner: int in CORNER_COUNT:
		if _sweep_corner(corner, from, to):
			changed = true
	return changed


## Падающие нити. delta полная.
func tick(delta: float) -> void:
	if _falling.is_empty():
		return
	var fall_sec: float = _balance.web_fall_sec
	var i: int = _falling.size() - 1
	while i >= 0:
		_falling[i].age += maxf(delta, 0.0)
		if _falling[i].age >= fall_sec:
			_falling.remove_at(i)
		i -= 1
	revision += 1


## 0, пока нити падают; иначе INF.
func wake_sec() -> float:
	return 0.0 if not _falling.is_empty() else INF


## Все видимые нити в глобальных lpx окна: живые и падающие.
func draw_data() -> Array[Line]:
	var out: Array[Line] = []
	for corner: int in CORNER_COUNT:
		var st: CornerState = _states[corner]
		for s: Stroke in st.strokes:
			if not s.alive or s.order > st.step:
				continue
			var line := Line.new()
			line.points = _to_global(corner, s.points)
			line.kind = s.kind
			line.width = 1.0
			out.append(line)
	var accel: float = _balance.gravity * FALL_ACCEL_RATIO
	for f: Falling in _falling:
		var line := Line.new()
		var shift := Vector2(f.drift * f.age, 0.5 * accel * f.age * f.age)
		line.points = f.points.duplicate()
		for k: int in line.points.size():
			line.points[k] += shift
		line.kind = f.kind
		line.alpha = clampf(1.0 - f.age / _balance.web_fall_sec, 0.0, 1.0)
		out.append(line)
	return out


## Начало угла в глобальных lpx.
func corner_origin(corner: int) -> Vector2:
	var x: float = _bounds.position.x if is_left(corner) else _bounds.end.x
	var y: float = _bounds.position.y if is_top(corner) else _bounds.end.y
	return Vector2(x, y)


func _alive_count(st: CornerState) -> int:
	var n: int = 0
	for s: Stroke in st.strokes:
		if s.alive and s.order <= st.step:
			n += 1
	return n


func _sign_x(corner: int) -> float:
	return 1.0 if is_left(corner) else -1.0


func _sign_y(corner: int) -> float:
	return 1.0 if is_top(corner) else -1.0


func _to_global(corner: int, local: PackedVector2Array) -> PackedVector2Array:
	var origin: Vector2 = corner_origin(corner)
	var sx: float = _sign_x(corner)
	var sy: float = _sign_y(corner)
	var out := PackedVector2Array()
	out.resize(local.size())
	for i: int in local.size():
		out[i] = origin + Vector2(local[i].x * sx, local[i].y * sy)
	return out


func _to_local_point(corner: int, p: Vector2) -> Vector2:
	var d: Vector2 = p - corner_origin(corner)
	return Vector2(d.x * _sign_x(corner), d.y * _sign_y(corner))


func _sweep_corner(corner: int, from: Vector2, to: Vector2) -> bool:
	var st: CornerState = _states[corner]
	if st.strokes.is_empty():
		return false
	var hit: float = _balance.sweep_hit_px
	var reach: float = _balance.corner_web_radius_px + hit
	var lf: Vector2 = _to_local_point(corner, from)
	var lt: Vector2 = _to_local_point(corner, to)
	# отрезок целиком вне квадрата угла: нитей там нет
	if (lf.x > reach and lt.x > reach) or (lf.y > reach and lt.y > reach) \
			or (lf.x < -hit and lt.x < -hit) or (lf.y < -hit and lt.y < -hit):
		return false
	var changed: bool = false
	for s: Stroke in st.strokes:
		if not s.alive or s.order > st.step:
			continue
		if _polyline_hit(s.points, lf, lt, hit):
			s.alive = false
			_drop(corner, s)
			changed = true
	if not changed:
		return false
	revision += 1
	var shown: int = shown_count(corner)
	if shown > 0 and float(_alive_count(st)) < _balance.sweep_clear_ratio * float(shown):
		for s: Stroke in st.strokes:
			if s.alive and s.order <= st.step:
				s.alive = false
				_drop(corner, s)
		st.strokes = []
		st.step = 0
		st.weaving = false
		swept.emit(corner)
	return true


## Нить уходит в падающие: точки уже глобальные, поэтому set_bounds её не трогает.
func _drop(corner: int, s: Stroke) -> void:
	var f := Falling.new()
	f.points = _to_global(corner, s.points)
	f.kind = s.kind
	f.drift = (_rng.randf() * 2.0 - 1.0) * FALL_DRIFT
	_falling.append(f)


static func _polyline_hit(points: PackedVector2Array, a: Vector2, b: Vector2, radius: float) -> bool:
	for i: int in points.size() - 1:
		if segments_distance(points[i], points[i + 1], a, b) <= radius:
			return true
	return false


## Наименьшее расстояние между двумя отрезками.
static func segments_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	var best: float = INF
	best = minf(best, a.distance_to(Geometry2D.get_closest_point_to_segment(a, c, d)))
	best = minf(best, b.distance_to(Geometry2D.get_closest_point_to_segment(b, c, d)))
	best = minf(best, c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)))
	best = minf(best, d.distance_to(Geometry2D.get_closest_point_to_segment(d, a, b)))
	return best


## Асимметричный узор: лучи от угла, кольца разной протяжённости с провисом. Локальные координаты.
func _generate() -> Array[Stroke]:
	var radius: float = _balance.corner_web_radius_px
	var spokes: int = _rng.randi_range(SPOKES_MIN, SPOKES_MAX)
	var angles: Array[float] = []
	var first: float = EDGE_ANGLE_MIN + _rng.randf() * EDGE_ANGLE_JITTER
	var last: float = PI * 0.5 - EDGE_ANGLE_MIN - _rng.randf() * EDGE_ANGLE_JITTER
	for i: int in spokes:
		var t: float = float(i) / float(spokes - 1)
		var a: float = lerpf(first, last, t)
		if i > 0 and i < spokes - 1:
			a += (_rng.randf() - 0.5) * 0.6 * (last - first) / float(spokes - 1)
		angles.append(a)
	var lengths: Array[float] = []
	var out: Array[Stroke] = []
	for i: int in spokes:
		var length: float = radius * lerpf(SPOKE_LENGTH_MIN, 1.0, _rng.randf())
		lengths.append(length)
		var dir := Vector2(cos(angles[i]), sin(angles[i]))
		var side := Vector2(-dir.y, dir.x)
		var bow: float = (_rng.randf() - 0.5) * 5.0
		var s := Stroke.new()
		s.kind = Kind.SPOKE
		s.order = 1
		s.points = PackedVector2Array([Vector2.ZERO, dir * length * 0.5 + side * bow, dir * length])
		out.append(s)
	var rings: int = clampi(_balance.weave_steps - 1, 1, RINGS_MAX)
	var max_order: int = maxi(_balance.weave_steps, 1)
	var outer: float = radius * RING_OUTER
	for k: int in rings:
		var f: float = float(k + 1) / float(rings)
		var ring_r: float = outer * (RING_INNER + (1.0 - RING_INNER) * pow(f, 1.15))
		ring_r *= 1.0 + (_rng.randf() * 2.0 - 1.0) * RING_JITTER
		var from_spoke: int = 0 if _rng.randf() < 0.7 else 1
		var to_spoke: int = spokes - 1 if _rng.randf() < 0.7 else spokes - 2
		var ring := Stroke.new()
		ring.kind = Kind.RING
		ring.order = mini(k + 2, max_order)
		var pts := PackedVector2Array()
		for i: int in range(from_spoke, to_spoke + 1):
			var r_here: float = minf(ring_r * (1.0 + (_rng.randf() - 0.5) * 0.05), lengths[i] * 0.97)
			var p := Vector2(cos(angles[i]), sin(angles[i])) * r_here
			if i > from_spoke:
				var prev: Vector2 = pts[pts.size() - 1]
				var mid: Vector2 = (prev + p) * 0.5 * (1.0 - RING_SAG * (0.6 + 0.8 * _rng.randf()))
				pts.append(mid)
			pts.append(p)
		ring.points = pts
		out.append(ring)
	return out
