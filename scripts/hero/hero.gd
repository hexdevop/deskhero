class_name Hero
extends Node2D
## Единственный мост между логикой героя (RefCounted, lpx) и Godot (узлы, EventBus, единицы viewport).
## Покой: если машина сообщает next_tick_sec() >= max_step_sec, _process выключается, заводится один Timer.
## Пробуждение (таймер, ввод, смена границ) передаёт машине реальное прошедшее время без зажима:
## idle и эмоции считают от него паузу и обиду.

const MICROS_PER_SEC: float = 1000000.0
## Нижний предел таймера сна: страховка от нулевого и отрицательного ожидания.
const MIN_TIMER_SEC: float = 0.01

@export var balance: HeroBalance
## 0: случайное зерно. Не ноль: детерминированная прогулка (для тестов).
@export var rng_seed: int = 0
## Единиц Godot в одном lpx. По умолчанию из DisplayUnits при _ready; тесты могут переопределить.
var units_per_px: float = 1.0

## Последнее значение DisplayUnits: переопределённый вручную units_per_px не затирается, пока система не изменилась.
var _system_units: float = 1.0
var _ctx: HeroContext
var _machine: HeroStateMachine
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _started: bool = false
var _sleeping: bool = false
var _sleep_since_usec: int = 0
var _activity: int = -1  # -1: ещё не сообщали
var _pending_drag_end: bool = false
var _right_down_usec: int = -1

@onready var _view: HeroView = $View
@onready var _timer: Timer = $WakeTimer


func _ready() -> void:
	set_process(false)
	if balance == null:
		balance = HeroBalance.new()
	var errors: PackedStringArray = balance.validation_errors()
	if not errors.is_empty():
		push_error("HeroBalance: %s; используются значения по умолчанию" % ", ".join(errors))
		balance = HeroBalance.new()
	_system_units = DisplayUnits.units_per_px()
	units_per_px = _system_units
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_ctx = HeroContext.new(balance, _rng)
	_machine = HeroStateMachine.new(_ctx)
	_ctx.hard_landed.connect(_on_hard_landed)
	_ctx.emotions.changed.connect(_on_emotion_changed)
	_machine.state_changed.connect(_on_state_changed)
	_view.configure(balance.body_size_px)
	_view.scale = Vector2(units_per_px, units_per_px)
	_timer.one_shot = true
	_timer.timeout.connect(_on_wake_timeout)
	EventBus.world_bounds_changed.connect(_on_world_bounds_changed)
	EventBus.drag_cursor_resync.connect(_on_drag_cursor_resync)
	EventBus.drag_cancel_requested.connect(_on_drag_cancel_requested)


func get_context() -> HeroContext:
	return _ctx


func get_machine() -> HeroStateMachine:
	return _machine


func is_sleeping() -> bool:
	return _sleeping


func _process(delta: float) -> void:
	_machine.update(minf(delta, balance.max_step_sec))
	_after_step(false)


func _input(event: InputEvent) -> void:
	if not _started:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				if not _ctx.carrying and _hits_contour(button.position):
					_feed(HeroInput.Kind.PRESS, button.position)
			elif _ctx.carrying:
				_feed(HeroInput.Kind.RELEASE, button.position)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_button(button)
	elif event is InputEventMouseMotion and _ctx.carrying:
		var motion: InputEventMouseMotion = event
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_feed(HeroInput.Kind.CANCEL, motion.position)  # отпускание потеряно (например, вне окна)
		else:
			_feed(HeroInput.Kind.MOVE, motion.position)


## Dev-выход (D-010, пункт 8): удержание правой кнопки на герое, выход при отпускании на контуре.
func _handle_right_button(button: InputEventMouseButton) -> void:
	var on_hero: bool = _hits_contour(button.position)
	if button.pressed:
		_right_down_usec = Time.get_ticks_usec() if on_hero else -1
		return
	var held_sec: float = float(Time.get_ticks_usec() - _right_down_usec) / MICROS_PER_SEC
	var armed: bool = _right_down_usec >= 0
	_right_down_usec = -1
	if armed and on_hero and held_sec >= balance.dev_quit_hold_sec:
		EventBus.quit_requested.emit()


func _hits_contour(window_pos: Vector2) -> bool:
	return _ctx.contour_rect().has_point(window_pos / units_per_px)


## Ввод: сначала досчитать сон, потом событие, потом пересчёт покоя.
func _feed(kind: HeroInput.Kind, window_pos: Vector2) -> void:
	_advance_sleep()
	_machine.handle_input(HeroInput.make(kind, window_pos / units_per_px, Time.get_ticks_usec() / MICROS_PER_SEC))
	_after_step(false)


## Если герой спал, передать машине реальное прошедшее время без зажима. Это же update(0) для проснувшегося.
func _advance_sleep() -> void:
	if not _sleeping:
		return
	_sleeping = false
	var elapsed: float = maxf(float(Time.get_ticks_usec() - _sleep_since_usec) / MICROS_PER_SEC, 0.0)
	_machine.update(elapsed)


func _on_wake_timeout() -> void:
	if not _started:
		return
	_advance_sleep()
	_after_step(false)


func _on_world_bounds_changed(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or units_per_px <= 0.0:
		return
	_advance_sleep()
	var rescaled: bool = _refresh_units()
	_ctx.set_bounds(Rect2(bounds.position / units_per_px, bounds.size / units_per_px))
	if not _started:
		_started = true
		_ctx.place_at_center()
		_machine.start(HeroState.FALL)
		_after_step(true)  # первый контур публикуется до первого полигона
		return
	_machine.update(0.0)  # grounded и idle спят: пол мог измениться
	_after_step(rescaled)  # при смене масштаба контур в единицах viewport публикуется заново


## Смена max_scale (подключили Retina, ушли с него): логический размер героя в lpx не меняется,
## меняются множитель, масштаб View и контур в единицах viewport. true, если масштаб сменился.
func _refresh_units() -> bool:
	var current: float = DisplayUnits.units_per_px()
	if is_equal_approx(current, _system_units):
		return false
	_system_units = current
	units_per_px = current
	_view.scale = Vector2(current, current)
	return true


func _on_drag_cursor_resync(cursor: Vector2) -> void:
	if _started and _ctx.carrying:
		_feed(HeroInput.Kind.RESYNC, cursor)


func _on_drag_cancel_requested() -> void:
	if _started and _ctx.carrying:
		_feed(HeroInput.Kind.CANCEL, Vector2.ZERO)


func _after_step(force_contour: bool) -> void:
	var target: Vector2 = _ctx.pos * units_per_px
	if position != target:
		position = target
	_view.apply(_ctx.pose, _ctx.facing, _ctx.walk_phase, _ctx.emotions.current())
	_publish_contour(force_contour)
	_schedule()
	if _pending_drag_end:
		_pending_drag_end = false
		EventBus.hero_drag_ended.emit()  # после контура: полигон Overlay не устарел. Последнее действие: сигнал может вызвать re-entry


func _publish_contour(force: bool) -> void:
	if not _ctx.update_contour(force):
		return
	var rect: Rect2 = _ctx.contour_rect()
	EventBus.hero_contour_changed.emit(Rect2(rect.position * units_per_px, rect.size * units_per_px))


## Сон или каждый кадр по next_tick_sec().
func _schedule() -> void:
	var wait: float = _machine.next_tick_sec()
	if wait >= balance.max_step_sec:
		if not _sleeping:
			_publish_contour(true)  # при остановке полигон совпадает с телом
			_sleeping = true
		_sleep_since_usec = Time.get_ticks_usec()
		set_process(false)
		if is_inf(wait):
			_timer.stop()
		else:
			_timer.start(maxf(wait, MIN_TIMER_SEC))
		_set_activity(false)
	else:
		_sleeping = false
		set_process(true)
		_timer.stop()
		_set_activity(true)


func _set_activity(active: bool) -> void:
	var value: int = 1 if active else 0
	if value == _activity:
		return
	_activity = value
	EventBus.hero_activity_changed.emit(active)


func _on_state_changed(from: StringName, to: StringName) -> void:
	EventBus.hero_state_changed.emit(from, to)
	if to == HeroState.CARRIED:
		EventBus.hero_drag_started.emit()
	elif from == HeroState.CARRIED:
		_pending_drag_end = true


func _on_emotion_changed(emotion: HeroEmotions.Emotion) -> void:
	EventBus.hero_emotion_changed.emit(emotion)


func _on_hard_landed(speed: float) -> void:
	EventBus.hero_hard_landed.emit(speed)
