class_name PassthroughShape
extends RefCounted
## Чистые функции для mouse_passthrough_polygon. Без сцены и окна.

## Запасной полигон лежит за левым верхним углом окна и не перехватывает ни одного пикселя.
## macOS (display_server_macos.mm:1848, 3231): полигон хранится как есть, границы окна не проверяются,
## курсор в окне имеет неотрицательные координаты, поэтому в такой полигон он не попадает.
## Пустой полигон (size == 0) нельзя: ветка else отключает passthrough, и окно ловит все клики.
const FALLBACK_SIDE_PX: float = 2.0
const FALLBACK_OFFSET_PX: float = -4.0


## Контур прямоугольника (по часовой), масштаб из системы viewport в пиксели окна.
static func rect_polygon(rect: Rect2, scale: Vector2 = Vector2.ONE) -> PackedVector2Array:
	var a: Vector2 = rect.position * scale
	var b: Vector2 = rect.end * scale
	return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


## Как rect_polygon, но для пустого прямоугольника отдаёт крошечный невырожденный полигон за границей окна:
## иначе окно поймало бы все клики. Так бывает только до первого контура героя.
static func hit_polygon(rect: Rect2, scale: Vector2 = Vector2.ONE) -> PackedVector2Array:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return rect_polygon(Rect2(Vector2(FALLBACK_OFFSET_PX, FALLBACK_OFFSET_PX), Vector2(FALLBACK_SIDE_PX, FALLBACK_SIDE_PX)), Vector2.ONE)
	var polygon: PackedVector2Array = rect_polygon(rect, scale)
	if polygon[0] == polygon[2]:
		return hit_polygon(Rect2(), scale)
	return polygon


## Масштаб окна к viewport (Retina / content scale). При нуле в viewport — единица.
static func window_scale(window_size: Vector2, viewport_size: Vector2) -> Vector2:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ONE
	return window_size / viewport_size
