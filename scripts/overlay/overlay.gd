class_name Overlay
extends Node
## Прозрачное окно без рамки на рабочую область экрана + FPS-режимы.
## Флаги окна (прозрачность, без рамки, поверх всех) заданы только в project.godot.
## Управляет mouse_passthrough_polygon по контуру героя. Связь с героем только через EventBus.

@export var config: OverlayConfig

var _screen_index: int = 0
var _work_area: Rect2i = Rect2i()
## Эффективная активность: мышь, герой или захват. От неё зависит FPS.
var _active: bool = false
var _mouse_active: bool = false
var _hero_active: bool = false
## Герой в воздухе, в руках или брошен: кадры идут на motion_fps.
var _hero_moving_fast: bool = false
var _timer: Timer
var _linger_timer: Timer
var _drag_timer: Timer
var _fit_attempts: int = 0
var _capturing: bool = false
## Контур героя из hero_contour_changed, в единицах viewport.
var _hero_rect: Rect2 = Rect2()
var _last_polygon: PackedVector2Array = PackedVector2Array()
## Кэш на время drag: рабочие области и полные рамки экранов, в единицах Godot (см. D-009).
var _usable_rects: Array[Rect2i] = []
var _screen_rects: Array[Rect2i] = []
var _last_switch_msec: int = -1000000
var _last_drag_mouse: Vector2i = Vector2i.ZERO
var _screen_count: int = 0


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
	EventBus.hero_contour_changed.connect(_on_hero_contour_changed)
	EventBus.hero_activity_changed.connect(_on_hero_activity_changed)
	EventBus.hero_state_changed.connect(_on_hero_state_changed)
	EventBus.hero_drag_started.connect(_on_drag_started)
	EventBus.hero_drag_ended.connect(_on_drag_ended)
	EventBus.quit_requested.connect(_on_quit_requested)
	MacosWindow.hide_from_dock()  # macOS: без значка в Dock; без модуля ничего не делает
	MacosWindow.apply_all_spaces()  # macOS: окно на всех Spaces; без модуля или на другой ОС ничего не делает
	_update_passthrough()  # до первого контура героя: крошечный полигон, окно не ловит все клики
	refresh_work_area()
	_on_window_resized()  # size_changed может не прийти: границы и полигон нужны сразу
	_timer = Timer.new()
	_timer.wait_time = config.screen_check_interval_sec
	_timer.timeout.connect(refresh_work_area)
	add_child(_timer)
	_timer.start()


## Активность мыши (события над окном): true, 30 FPS; false, снимается таймером.
## Итоговый режим FPS зависит ещё от героя и захвата.
func set_active(active: bool) -> void:
	_mouse_active = active
	_refresh_active()


## Эффективная активность: мышь, герой или захват.
func is_active() -> bool:
	return _active


func _refresh_active() -> void:
	var wanted: bool = _mouse_active or _hero_active or _capturing
	if wanted == _active:
		return
	_active = wanted
	_apply_fps()


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
	var count: int = DisplayServer.get_screen_count()
	if count != _screen_count:
		# экраны добавились или пропали: индексы могли сдвинуться, идём на основной
		if _screen_count != 0:
			_screen_index = DisplayServer.get_primary_screen()
		_screen_count = count
	_screen_index = resolve_screen(_screen_index, DisplayServer.get_primary_screen(), count)
	if _capturing:
		_cache_screens()  # кэш не должен устаревать, даже если рабочая область не изменилась
	var rect: Rect2i = DisplayServer.screen_get_usable_rect(_screen_index)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var changed: bool = rect != _work_area
	if changed:
		_work_area = rect
		_fit_attempts = 0
	_fit_window()
	if changed:
		if not _capturing:  # во время drag границы ставит переезд, старый viewport зажал бы героя зря
			_on_window_resized()  # размер окна мог не измениться (экран исчез, новый такого же размера): зажать героя


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
	MacosWindow.apply_all_spaces()  # повторно: после смены окна поведение могло сброситься


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_DPI_CHANGE:
		MacosWindow.hide_from_dock()  # на случай, если политика сбросилась
		MacosWindow.apply_all_spaces()
		refresh_work_area()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_drag()
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		# при зажатой кнопке ОС продолжает слать drag в окно: тогда не прерываем
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_cancel_drag()


func _cancel_drag() -> void:
	EventBus.drag_cancel_requested.emit()


func _apply_fps() -> void:
	Engine.max_fps = clampi(target_fps(config, _active, _hero_moving_fast), OverlayConfig.MIN_FPS, OverlayConfig.MAX_FPS)


## Чистая функция: motion_fps для быстрого движения героя, иначе active_fps или idle_fps. motion_fps не ниже active_fps.
static func target_fps(cfg: OverlayConfig, active: bool, moving_fast: bool) -> int:
	if moving_fast:
		return maxi(cfg.motion_fps, cfg.active_fps)
	return cfg.active_fps if active else cfg.idle_fps


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		set_active(true)
		if _capturing:
			_drag_timer.start()  # движение мыши продлевает страховку
			if event is InputEventMouseMotion:
				var motion: InputEventMouseMotion = event
				_track_drag(motion.position)
		else:
			_linger_timer.start()


## Во время drag: экран под курсором и переезд окна. Вызывается из событий, _process не нужен:
## AppKit шлёт mouseDragged в окно, где нажали кнопку, и за его пределами (D-009).
## _input героя выполняется раньше (обратный порядок дерева), здесь позиция только уточняется.
func _track_drag(event_position: Vector2) -> void:
	var mouse: Vector2i = DisplayServer.mouse_get_position()
	_last_drag_mouse = mouse
	if not point_in_any(mouse, _screen_rects):
		return  # mouse_get_position вне экранов отдаёт (0, 0): не верим
	var now: int = Time.get_ticks_msec()
	var target: int = screen_at_point(mouse, _usable_rects, config.screen_switch_margin_px)
	if target >= 0 and target != _screen_index and now - _last_switch_msec >= config.screen_switch_cooldown_ms:
		_switch_screen_while_dragging(target, mouse)
		_last_switch_msec = now
		return
	if now - _last_switch_msec < config.screen_switch_cooldown_ms:
		var local: Vector2 = Vector2(mouse - get_window().position) / _window_scale()
		if (event_position - local).length() > float(config.drag_resync_px):
			EventBus.drag_cursor_resync.emit(local)  # событие пришло ещё в координатах старого окна


func _switch_screen_while_dragging(target: int, mouse: Vector2i) -> void:
	var window: Window = get_window()
	var scale: Vector2 = _window_scale()  # до переезда: viewport ещё не обновился
	var previous: int = _screen_index
	set_screen(target)  # окно на рабочую область нового экрана, MacosWindow.apply_all_spaces внутри _fit_window
	if _work_area != DisplayServer.screen_get_usable_rect(target) or window.position != _work_area.position:
		# пустая область или ОС не дала переехать: откат на прежний экран
		_screen_index = previous
		refresh_work_area()
		return
	# viewport обновится позже, поэтому границы считаем из рабочей области сами
	EventBus.world_bounds_changed.emit(Rect2(Vector2.ZERO, Vector2(_work_area.size) / scale))
	EventBus.drag_cursor_resync.emit(Vector2(mouse - _work_area.position) / scale)
	_update_passthrough()


## Масштаб окна к viewport, не ноль.
func _window_scale() -> Vector2:
	var scale: Vector2 = PassthroughShape.window_scale(Vector2(get_window().size), get_viewport().get_visible_rect().size)
	if scale.x <= 0.0 or scale.y <= 0.0:
		return Vector2.ONE
	return scale


func _cache_screens() -> void:
	_usable_rects.clear()
	_screen_rects.clear()
	for i: int in DisplayServer.get_screen_count():
		_usable_rects.append(DisplayServer.screen_get_usable_rect(i))
		_screen_rects.append(Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)))


func _on_linger_timeout() -> void:
	# снимает только активность мыши: идущий герой остаётся на active_fps
	_mouse_active = false
	_refresh_active()


func _on_hero_activity_changed(active: bool) -> void:
	_hero_active = active
	_refresh_active()


func _on_hero_state_changed(_from: StringName, to: StringName) -> void:
	var fast: bool = to == HeroState.FALL or to == HeroState.THROWN or to == HeroState.CARRIED
	if fast == _hero_moving_fast:
		return
	_hero_moving_fast = fast
	_apply_fps()


func _on_window_resized() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.x > 0.0 and size.y > 0.0:
		EventBus.world_bounds_changed.emit(Rect2(Vector2.ZERO, size))  # герой ответит hero_contour_changed, полигон обновится


func _on_hero_contour_changed(rect: Rect2) -> void:
	_hero_rect = rect
	_update_passthrough()


func _on_drag_started() -> void:
	_capturing = true
	_cache_screens()
	_last_drag_mouse = DisplayServer.mouse_get_position()
	_linger_timer.stop()
	_drag_timer.start()
	_refresh_active()
	_update_passthrough()  # на время drag окно ловит всю область: курсор не слетает


func _on_drag_ended() -> void:
	_capturing = false
	_drag_timer.stop()
	_linger_timer.start()
	_refresh_active()
	_on_window_resized()  # границы могли устареть за время drag (экран пропал)
	_update_passthrough()


func _on_drag_timeout() -> void:
	# курсор двигается без событий (например, над чужим экраном): это не зависание
	# продлеваем, только пока ОС сообщает зажатую левую кнопку (курсор может стоять): иначе потерянное отпускание (D-003) оставило бы полный полигон
	var pressed: bool = (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) != 0
	if _capturing and pressed:
		# кнопка зажата: держим, даже если курсор стоит. Незажатая кнопка (потерянное отпускание) идёт в cancel ниже
		if DisplayServer.mouse_get_position() != _last_drag_mouse:
			_track_drag(Vector2.ZERO)
		_drag_timer.start()
		return
	_cancel_drag()


func _on_quit_requested() -> void:
	get_tree().quit()


## Обновляет полигон, только если он отличается от установленного.
func _update_passthrough() -> void:
	var window: Window = get_window()
	var view: Vector2 = get_viewport().get_visible_rect().size
	var scale: Vector2 = PassthroughShape.window_scale(Vector2(window.size), view)
	var area: Rect2 = Rect2(Vector2.ZERO, view) if _capturing else _hero_rect
	var polygon: PackedVector2Array = PassthroughShape.hit_polygon(area, scale)
	if polygon == _last_polygon:
		return
	_last_polygon = polygon
	window.mouse_passthrough_polygon = polygon


## Чистая функция: индекс экрана или основной, если индекс -1 или вне диапазона.
static func resolve_screen(requested: int, primary: int, count: int) -> int:
	if requested < 0 or requested >= count:
		return primary
	return requested


## Чистая функция: индекс первой области, содержащей точку (область сужена на margin со всех сторон),
## или -1, если точка вне всех (зазор между экранами, меню-бар, Dock). Тогда остаёмся на текущем экране.
static func screen_at_point(point: Vector2i, rects: Array[Rect2i], margin: int = 0) -> int:
	for i: int in rects.size():
		var inner: Rect2i = rects[i].grow(-maxi(margin, 0))
		if inner.size.x > 0 and inner.size.y > 0 and inner.has_point(point):
			return i
	return -1


## Чистая функция: лежит ли точка хотя бы в одной области.
static func point_in_any(point: Vector2i, rects: Array[Rect2i]) -> bool:
	return screen_at_point(point, rects, 0) >= 0
