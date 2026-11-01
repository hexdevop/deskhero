class_name WebLine
extends Node2D
## Нить героя (D-011, D-012). Рисует то, что отдаёт WebRope.draw_points: логики нет. Вид оригинальный (NFR-6):
## две тонкие свитые жилки бледной мяты и бирюзы костюма героя над мягкой индиго-тенью (читается и на светлом
## фоне), в точке крепления янтарная бусина-зажим, такая же летит на кончике выстрела. Паутинного узора нет.
## Рисует в lpx окна (узел top_level, масштаб units_per_px задаёт Hero). Перерисовка только при изменении:
## в REST ни кадра.

## Шаг выборки вдоль нити, lpx: короче даёт гладкую свивку, длиннее экономит точки.
const SAMPLE_STEP: float = 5.0
## Потолок числа выборок: очень длинная нить рисуется грубее, а не дольше.
const MAX_SAMPLES: int = 180
## Длина витка свивки и размах жилок: туго натянутая нить свита плотнее и тоньше.
const TWIST_PERIOD: float = 26.0
const TWIST_AMP_SLACK: float = 1.7
const TWIST_AMP_TAUT: float = 0.8
## Толщина жилок и тени от натяжения (0..1).
const STRAND_W_SLACK: float = 0.9
const STRAND_W_TAUT: float = 1.5
const SHADOW_W_SLACK: float = 2.4
const SHADOW_W_TAUT: float = 3.6
const BEAD_RADIUS: float = 2.9

@export var strand_a: Color = Color(0.561, 0.961, 0.816)
@export var strand_b: Color = Color(0.200, 0.780, 0.730)
@export var shadow: Color = Color(0.290, 0.247, 0.549, 0.34)
@export var bead_fill: Color = Color(1.0, 0.710, 0.180)
@export var bead_edge: Color = Color(0.106, 0.102, 0.180)

var _points: PackedVector2Array = PackedVector2Array()
var _tension: float = 0.0


## Новая геометрия нити: перерисовка только при отличии от прошлой. Пустой список прячет узел.
func apply(points: PackedVector2Array, tension: float) -> void:
	if points.size() < 2:
		if visible or not _points.is_empty():
			_points = PackedVector2Array()
			visible = false
		return
	if visible and is_equal_approx(tension, _tension) and points == _points:
		return
	_points = points
	_tension = tension
	visible = true
	queue_redraw()


func is_drawn() -> bool:
	return visible and _points.size() >= 2


func _draw() -> void:
	if _points.size() < 2:
		return
	var t: float = clampf(_tension, 0.0, 1.0)
	var samples: PackedVector2Array = sample(_points, SAMPLE_STEP)
	draw_polyline(samples, shadow, lerpf(SHADOW_W_SLACK, SHADOW_W_TAUT, t), true)
	var amp: float = lerpf(TWIST_AMP_SLACK, TWIST_AMP_TAUT, t)
	var width: float = lerpf(STRAND_W_SLACK, STRAND_W_TAUT, t)
	draw_polyline(twist(samples, amp, TWIST_PERIOD, 0.0), strand_a, width, true)
	draw_polyline(twist(samples, amp, TWIST_PERIOD, PI), strand_b, width, true)
	var tip: Vector2 = _points[_points.size() - 1]
	draw_circle(tip, BEAD_RADIUS, bead_fill, true, -1.0, true)
	draw_arc(tip, BEAD_RADIUS, 0.0, TAU, 14, bead_edge, 1.0, true)


## Сглаженная выборка вдоль нити с шагом около step, от первой точки к последней. Две точки: прямая.
## Больше двух: сплайн Катмулла-Рома через заданные точки. Всегда содержит обе крайние точки.
static func sample(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var n: int = points.size()
	if n < 2:
		return points.duplicate()
	var total: float = 0.0
	for i: int in n - 1:
		total += points[i].distance_to(points[i + 1])
	var use_step: float = maxf(step, total / float(MAX_SAMPLES))
	var out := PackedVector2Array()
	out.append(points[0])
	for i: int in n - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, n - 1)]
		var count: int = maxi(int(ceil(p1.distance_to(p2) / use_step)), 1)
		for k: int in range(1, count + 1):
			var u: float = float(k) / float(count)
			out.append(_catmull(p0, p1, p2, p3, u))
	return out


## Свитая жилка: смещение поперёк нити синусом по длине. Фаза отсчитывается от последней точки (крепления),
## поэтому при размотке виток не бежит по креплению. Крайние точки остаются на оси.
static func twist(samples: PackedVector2Array, amp: float, period: float, phase: float) -> PackedVector2Array:
	var n: int = samples.size()
	var out := PackedVector2Array()
	out.resize(n)
	if n < 2:
		return samples.duplicate()
	var dist: float = 0.0
	var total: float = 0.0
	for i: int in n - 1:
		total += samples[i].distance_to(samples[i + 1])
	for i: int in n:
		if i > 0:
			dist += samples[i].distance_to(samples[i - 1])
		var a: Vector2 = samples[maxi(i - 1, 0)]
		var b: Vector2 = samples[mini(i + 1, n - 1)]
		var tangent: Vector2 = (b - a).normalized() if a != b else Vector2.DOWN
		var normal := Vector2(-tangent.y, tangent.x)
		var from_end: float = total - dist
		var edge: float = clampf(minf(dist, from_end) / period, 0.0, 1.0)  # к концам виток сходит на нет
		out[i] = samples[i] + normal * amp * edge * sin(from_end / period * TAU + phase)
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var u2: float = u * u
	var u3: float = u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)
