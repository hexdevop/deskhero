class_name CornerWebsView
extends Node2D
## Паутина в углах: рисует CornerWebField.draw_data(), логики нет. Неровная природная сеть, не копия чужого узора:
## бледные нити с мягкой индиго-тенью (видны и на светлом фоне). Рисует в lpx окна (узел top_level, масштаб задаёт Hero).
## Перерисовка только при смене field.revision; без паутины узел скрыт. Клики по ней не ловятся (в полигон не входит).

const SPOKE_W: float = 1.2
const RING_W: float = 0.9
const SHADOW_EXTRA: float = 2.2
const KNOT_RADIUS: float = 1.1
## Кольцо хранит по 2 точки на промежуток между лучами; узелок на каждой точке крепления к лучу.
const KNOT_EVERY: int = 2
## Гладкость колец: выборка сплайном с этим шагом, lpx.
const SAMPLE_STEP: float = 9.0

@export var thread: Color = Color(0.92, 0.98, 0.96, 0.95)
@export var shadow: Color = Color(0.200, 0.170, 0.430, 0.78)

var _revision: int = -1
var _lines: Array[CornerWebField.Line] = []


## Перерисовывается, только если revision изменился. Пустое поле прячет узел.
func apply(field: CornerWebField) -> void:
	if field.revision == _revision:
		return
	_revision = field.revision
	_lines = field.draw_data()
	visible = not _lines.is_empty()
	queue_redraw()


func line_count() -> int:
	return _lines.size()


func _draw() -> void:
	for line: CornerWebField.Line in _lines:
		if line.points.size() < 2:
			continue
		var pts: PackedVector2Array = WebLine.sample(line.points, SAMPLE_STEP) if line.kind == CornerWebField.Kind.RING else line.points
		var width: float = SPOKE_W if line.kind == CornerWebField.Kind.SPOKE else RING_W
		var shade: Color = shadow
		shade.a *= line.alpha
		var core: Color = thread
		core.a *= line.alpha
		draw_polyline(pts, shade, width + SHADOW_EXTRA, true)
		draw_polyline(pts, core, width, true)
		if line.kind == CornerWebField.Kind.SPOKE:
			continue
		# узелки на изломах кольца (точки прикрепления к лучам)
		for i: int in range(0, line.points.size(), KNOT_EVERY):
			draw_circle(line.points[i], KNOT_RADIUS, core, true, -1.0, true)
