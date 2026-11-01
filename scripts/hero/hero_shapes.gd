class_name HeroShapes
extends RefCounted
## Геометрия для рисунка героя: эллипсы, капсулы, скруглённые прямоугольники, кривые Безье. Чистые функции.


static func ellipse(center: Vector2, radius: Vector2, count: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in count:
		var a: float = float(i) / float(count) * TAU
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return pts


## Дуга эллипса как закрытая фигура-сегмент (хорда замыкает), углы в радианах. Для линий берите как полилинию.
static func ellipse_arc(center: Vector2, radius: Vector2, from_rad: float, to_rad: float, count: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in count + 1:
		var a: float = lerpf(from_rad, to_rad, float(i) / float(count))
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return pts


## Капсула вокруг отрезка a-b с радиусом r.
static func capsule(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
	var axis: Vector2 = b - a
	var base: float = axis.angle() if axis.length() > 0.001 else 0.0
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = 8
	for i: int in n + 1:
		var ang: float = base - PI * 0.5 + PI * float(i) / float(n)
		pts.append(b + Vector2(cos(ang), sin(ang)) * r)
	for i: int in n + 1:
		var ang2: float = base + PI * 0.5 + PI * float(i) / float(n)
		pts.append(a + Vector2(cos(ang2), sin(ang2)) * r)
	return pts


static func round_rect(rect: Rect2, radius: float, corner_steps: int) -> PackedVector2Array:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts: PackedVector2Array = PackedVector2Array()
	var corners: Array[Vector2] = [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r),
	]
	for k: int in 4:
		for i: int in corner_steps + 1:
			var a: float = -PI * 0.5 + (float(k) + float(i) / float(corner_steps)) * PI * 0.5
			pts.append(corners[k] + Vector2(cos(a), sin(a)) * r)
	return pts


static func bezier(p0: Vector2, p1: Vector2, p2: Vector2, count: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in count + 1:
		var t: float = float(i) / float(count)
		pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	return pts


## Контур толстой ломаной (рука с локтем): полоса радиуса r с круглыми концами. Точки в порядке пути, не меньше двух.
static func stroke(path: PackedVector2Array, r: float) -> PackedVector2Array:
	var n: int = path.size()
	if n < 2:
		return PackedVector2Array()
	var normals: Array[Vector2] = []
	var scales: Array[float] = []
	for i: int in n:
		var prev_dir: Vector2 = (path[i] - path[i - 1]).normalized() if i > 0 else (path[1] - path[0]).normalized()
		var next_dir: Vector2 = (path[i + 1] - path[i]).normalized() if i < n - 1 else prev_dir
		var nrm: Vector2 = Vector2(-prev_dir.y, prev_dir.x) + Vector2(-next_dir.y, next_dir.x)
		nrm = nrm.normalized() if nrm.length() > 0.001 else Vector2(-prev_dir.y, prev_dir.x)
		var cos_half: float = maxf(nrm.dot(Vector2(-prev_dir.y, prev_dir.x)), 0.5)
		normals.append(nrm)
		scales.append(r / cos_half)
	var pts := PackedVector2Array()
	for i: int in n:
		pts.append(path[i] + normals[i] * scales[i])
	var end_dir: Vector2 = (path[n - 1] - path[n - 2]).normalized()
	var end_base: float = end_dir.angle()
	for i: int in range(1, 8):
		var a: float = end_base + PI * 0.5 - PI * float(i) / 8.0
		pts.append(path[n - 1] + Vector2(cos(a), sin(a)) * r)
	for i: int in range(n - 1, -1, -1):
		pts.append(path[i] - normals[i] * scales[i])
	var start_dir: Vector2 = (path[1] - path[0]).normalized()
	var start_base: float = start_dir.angle()
	for i: int in range(1, 8):
		var a: float = start_base - PI * 0.5 - PI * float(i) / 8.0
		pts.append(path[0] + Vector2(cos(a), sin(a)) * r)
	return pts
