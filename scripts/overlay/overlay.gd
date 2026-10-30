class_name Overlay
extends Node
## Прозрачное окно без рамки на рабочую область экрана + FPS-режимы.
## Флаги окна (прозрачность, без рамки, поверх всех) заданы в project.godot.
## Поверх этого T-004 добавит passthrough-полигон.

signal work_area_changed(rect: Rect2i)

@export var config: OverlayConfig

var _screen_index: int = 0
var _work_area: Rect2i = Rect2i()
var _active: bool = false
var _timer: Timer


func _ready() -> void:
	if config == null:
		config = OverlayConfig.new()
	_screen_index = resolve_screen(config.screen_index, DisplayServer.get_primary_screen(), DisplayServer.get_screen_count())
	var window: Window = get_window()
	window.transparent = true
	window.transparent_bg = true
	window.borderless = true
	window.always_on_top = true
	OS.low_processor_usage_mode = config.low_processor_mode
	OS.low_processor_usage_mode_sleep_usec = config.low_processor_sleep_usec
	_apply_fps()
	refresh_work_area()
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
	if rect == _work_area and get_window().size == rect.size:
		return
	_work_area = rect
	var window: Window = get_window()
	window.position = rect.position
	window.size = rect.size
	work_area_changed.emit(rect)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_DPI_CHANGE:
		refresh_work_area()


func _apply_fps() -> void:
	Engine.max_fps = config.active_fps if _active else config.idle_fps


## Чистая функция: индекс экрана или основной, если индекс -1 или вне диапазона.
static func resolve_screen(requested: int, primary: int, count: int) -> int:
	if requested < 0 or requested >= count:
		return primary
	return requested
