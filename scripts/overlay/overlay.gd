class_name Overlay
extends Node
## Прозрачное окно без рамки на рабочую область экрана + FPS-режимы.
## Флаги окна (прозрачность, без рамки, поверх всех) заданы только в project.godot.
## Управляет mouse_passthrough_polygon по контуру квадрата. EventBus пока нет: связь через сигналы.

signal work_area_changed(rect: Rect2i)

@export var config: OverlayConfig
@export var placeholder: PlaceholderSquare

var _screen_index: int = 0
var _work_area: Rect2i = Rect2i()
var _active: bool = false
var _timer: Timer
var _linger_timer: Timer
var _drag_timer: Timer
var _fit_attempts: int = 0
var _capturing: bool = false
var _last_polygon: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	if config == null:
		config = OverlayConfig.new()
	_screen_index = resolve_screen(config.screen_index, DisplayServer.get_primary_screen(), DisplayServer.get_screen_count())
	var window: Window = get_window()
	window.size_changed.connect(_on_window_resized)
	OS.low_processor_usage_mode = config.low_processor_mode
	OS.low_processor_usage_mode_sleep_usec = config.low_processor_sleep_usec
	_apply_fps()
	_linger_timer = Timer.new()
	_linger_timer.one_shot = true
	_linger_timer.wait_time = config.active_linger_sec
	_linger_timer.timeout.connect(_on_linger_timeout)
	add_child(_linger_timer)
	_drag_timer = Timer.new()
	_drag_timer.one_shot = true
	_drag_timer.wait_time = config.drag_timeout_sec
	_drag_timer.timeout.connect(_on_drag_timeout)
	add_child(_drag_timer)
	if placeholder != null:
		placeholder.rect_changed.connect(_on_square_rect_changed)
		placeholder.drag_started.connect(_on_drag_started)
		placeholder.drag_ended.connect(_on_drag_ended)
		placeholder.quit_requested.connect(_on_quit_requested)
	refresh_work_area()
	_on_window_resized()  # size_changed может не прийти: границы и полигон нужны сразу
	_timer = Timer.new()
	_timer.wait_time = config.screen_check_interval_sec
	_timer.timeout.connect(refresh_work_area)
	add_child(_timer)
	_timer.start()


## Активность: true, 30 FPS; false, FPS покоя.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	_apply_fps()


func is_active() -> bool:
	return _active


## Переключить экран (задел под мульти-мониторы).
func set_screen(index: int) -> void:
	_screen_index = resolve_screen(index, DisplayServer.get_primary_screen(), DisplayServer.get_screen_count())
	refresh_work_area()


func get_work_area() -> Rect2i:
	return _work_area


## Перечитать рабочую область и подогнать окно, только если она изменилась.
func refresh_work_area() -> void:
	if not is_inside_tree() or config == null:
		return
	_screen_index = resolve_screen(_screen_index, DisplayServer.get_primary_screen(), DisplayServer.get_screen_count())
	var rect: Rect2i = DisplayServer.screen_get_usable_rect(_screen_index)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var changed: bool = rect != _work_area
	if changed:
		_work_area = rect
		_fit_attempts = 0
	_fit_window()
	if changed:
		work_area_changed.emit(rect)


## Подгонка окна без эмита. Если ОС не дала точный размер, после fit_max_attempts больше не трогаем.
func _fit_window() -> void:
	var window: Window = get_window()
	if window.position == _work_area.position and window.size == _work_area.size:
		_fit_attempts = 0  # успешная подгонка лимит не тратит
		return
	if _fit_attempts >= config.fit_max_attempts:
		return
	_fit_attempts += 1
	window.position = _work_area.position
	window.size = _work_area.size


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_DPI_CHANGE:
		refresh_work_area()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_drag()
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		# при зажатой кнопке ОС продолжает слать drag в окно: тогда не прерываем
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_cancel_drag()


func _cancel_drag() -> void:
	if placeholder != null:
		placeholder.cancel_drag()


func _apply_fps() -> void:
	Engine.max_fps = clampi(config.active_fps if _active else config.idle_fps, OverlayConfig.MIN_FPS, OverlayConfig.MAX_FPS)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		set_active(true)
		if _capturing:
			_drag_timer.start()  # движение мыши продлевает страховку
		else:
			_linger_timer.start()


func _on_linger_timeout() -> void:
	if not _capturing:
		set_active(false)


func _on_window_resized() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if placeholder != null and size.x > 0.0 and size.y > 0.0:
		placeholder.set_bounds(Rect2(Vector2.ZERO, size))  # эмитит rect_changed, полигон обновится


func _on_square_rect_changed(_rect: Rect2) -> void:
	_update_passthrough()


func _on_drag_started() -> void:
	_capturing = true
	_linger_timer.stop()
	_drag_timer.start()
	set_active(true)
	_update_passthrough()  # на время drag окно ловит всю область: курсор не слетает


func _on_drag_ended() -> void:
	_capturing = false
	_drag_timer.stop()
	_linger_timer.start()
	_update_passthrough()


func _on_drag_timeout() -> void:
	_cancel_drag()


func _on_quit_requested() -> void:
	get_tree().quit()


## Обновляет полигон, только если он отличается от установленного.
func _update_passthrough() -> void:
	if placeholder == null:
		return
	var window: Window = get_window()
	var view: Vector2 = get_viewport().get_visible_rect().size
	var scale: Vector2 = PlaceholderSquare.window_scale(Vector2(window.size), view)
	var area: Rect2 = Rect2(Vector2.ZERO, view) if _capturing else placeholder.get_rect()
	var polygon: PackedVector2Array = PlaceholderSquare.rect_polygon(area, scale)
	if polygon == _last_polygon:
		return
	_last_polygon = polygon
	window.mouse_passthrough_polygon = polygon


## Чистая функция: индекс экрана или основной, если индекс -1 или вне диапазона.
static func resolve_screen(requested: int, primary: int, count: int) -> int:
	if requested < 0 or requested >= count:
		return primary
	return requested
