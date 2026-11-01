class_name PlaceholderSquare
extends Node2D
## Квадрат-плейсхолдер героя: таскается левой кнопкой, правый клик завершает приложение (dev-выход).
## Координаты — в системе окна (viewport). Не знает про Overlay: общается через EventBus.

@export var config: OverlayConfig

var _bounds: Rect2 = Rect2()
var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _side: float = 96.0


func _ready() -> void:
	if config == null:
		config = OverlayConfig.new()
	_side = float(config.square_size)
	EventBus.world_bounds_changed.connect(set_bounds)
	EventBus.drag_cursor_resync.connect(drag_to)
	EventBus.drag_cancel_requested.connect(cancel_drag)


func get_rect() -> Rect2:
	return Rect2(position, Vector2(_side, _side))


func is_dragging() -> bool:
	return _dragging


## Принудительно завершить перетаскивание (потеря фокуса, таймаут). Без drag ничего не делает.
func cancel_drag() -> void:
	if _dragging:
		_end_drag()


## Поставить квадрат под курсор во время drag с сохранённой точкой захвата.
## cursor — в координатах окна. Нужен, когда окно переехало и позиция из события устарела.
func drag_to(cursor: Vector2) -> void:
	if not _dragging:
		return
	var target: Vector2 = clamp_position(cursor - _grab_offset, Vector2(_side, _side), _bounds)
	if target != position:
		position = target
		queue_redraw()


## Границы (область окна). Квадрат втягивается внутрь. Первый вызов ставит его в центр.
func set_bounds(bounds: Rect2) -> void:
	var first: bool = _bounds.size == Vector2.ZERO
	_bounds = bounds
	var target: Vector2 = position
	if first:
		target = bounds.position + (bounds.size - Vector2(_side, _side)) * 0.5
	var clamped: Vector2 = clamp_position(target, Vector2(_side, _side), bounds)
	if first or clamped != position:
		position = clamped
		queue_redraw()
	EventBus.hero_contour_changed.emit(get_rect())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed and not _dragging and get_rect().has_point(button.position):
				_start_drag(button.position)
			elif not button.pressed and _dragging:
				_end_drag()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			if get_rect().has_point(button.position):
				EventBus.quit_requested.emit()
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_end_drag()  # отпускание потеряно (например, вне окна)
			return
		var target: Vector2 = clamp_position(motion.position - _grab_offset, Vector2(_side, _side), _bounds)
		if target != position:
			position = target
			queue_redraw()


func _start_drag(mouse: Vector2) -> void:
	_dragging = true
	_grab_offset = mouse - position
	queue_redraw()
	EventBus.hero_drag_started.emit()


func _end_drag() -> void:
	_dragging = false
	queue_redraw()
	EventBus.hero_drag_ended.emit()
	EventBus.hero_contour_changed.emit(get_rect())


func _draw() -> void:
	var color: Color = config.square_drag_color if _dragging else config.square_color
	draw_rect(Rect2(Vector2.ZERO, Vector2(_side, _side)), color)


## Чистая функция: позиция левого верхнего угла, не выходящая за bounds.
static func clamp_position(pos: Vector2, size: Vector2, bounds: Rect2) -> Vector2:
	var max_pos: Vector2 = (bounds.position + bounds.size - size).max(bounds.position)
	return pos.clamp(bounds.position, max_pos)


## Чистая функция: контур прямоугольника (по часовой), масштаб из системы viewport в пиксели окна.
static func rect_polygon(rect: Rect2, scale: Vector2 = Vector2.ONE) -> PackedVector2Array:
	var a: Vector2 = rect.position * scale
	var b: Vector2 = rect.end * scale
	return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


## Чистая функция: масштаб окна к viewport (Retina / content scale). При нуле — единица.
static func window_scale(window_size: Vector2, viewport_size: Vector2) -> Vector2:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ONE
	return window_size / viewport_size
