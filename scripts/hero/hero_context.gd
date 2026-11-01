class_name HeroContext
extends RefCounted
## Данные героя и мира. Без сцены; часы, rng и ввод приходят снаружи.
## Единицы: lpx. pos — точка между ступнями.

signal hard_landed(speed: float)
signal soft_landed()

const FLOOR_EPSILON: float = 0.01

var balance: HeroBalance
var rng: RandomNumberGenerator
var throw_tracker: ThrowTracker
var emotions: HeroEmotions
var bounds: Rect2 = Rect2(0.0, 0.0, 800.0, 600.0)
var pos: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing: int = 1
var pose: StringName = &"idle"
var walk_phase: float = 0.0
## Смещение от курсора до pos в момент захвата.
var grab_offset: Vector2 = Vector2.ZERO
## Скорость последнего удара о пол, читает land.
var last_impact_speed: float = 0.0
## Выставляется carried, чтобы root не перехватывал повторный PRESS.
var carrying: bool = false

var _contour: Rect2 = Rect2()
var _contour_anchor: Vector2 = Vector2.ZERO
var _contour_valid: bool = false


func _init(p_balance: HeroBalance, p_rng: RandomNumberGenerator) -> void:
	balance = p_balance
	rng = p_rng
	throw_tracker = ThrowTracker.new(p_balance)
	emotions = HeroEmotions.new(p_balance)


func body_rect() -> Rect2:
	var size: Vector2 = balance.body_size_px
	return Rect2(pos.x - size.x * 0.5, pos.y - size.y, size.x, size.y)


## Последний опубликованный контур: тело плюс запас. Если ещё не публиковался, считается по телу.
func contour_rect() -> Rect2:
	if _contour_valid:
		return _contour
	return body_rect().grow(balance.contour_padding_px)


## Публикует новый контур, если герой сдвинулся от прошлого на contour_step_px или force.
## Инвариант: после вызова тело внутри контура.
func update_contour(force: bool) -> bool:
	var moved: Vector2 = (pos - _contour_anchor).abs()
	var need: bool = force or not _contour_valid \
		or maxf(moved.x, moved.y) >= balance.contour_step_px \
		or not _contour.encloses(body_rect())
	if not need:
		return false
	_contour = body_rect().grow(balance.contour_padding_px)
	_contour_anchor = pos
	_contour_valid = true
	return true


func floor_y() -> float:
	return bounds.end.y


## Крайние допустимые pos для тела внутри bounds (если область уже тела, x по центру).
func clamp_pos(p: Vector2) -> Vector2:
	var half_w: float = balance.body_size_px.x * 0.5
	var min_x: float = bounds.position.x + half_w
	var max_x: float = bounds.end.x - half_w
	var x: float = (min_x + max_x) * 0.5 if min_x > max_x else clampf(p.x, min_x, max_x)
	var min_y: float = bounds.position.y + balance.body_size_px.y
	var y: float = floor_y() if min_y > floor_y() else clampf(p.y, min_y, floor_y())
	return Vector2(x, y)


## Новая рабочая область. x втягивается внутрь; y меняется, только если герой оказался ниже пола или выше потолка.
func set_bounds(new_bounds: Rect2) -> void:
	bounds = new_bounds
	var clamped: Vector2 = clamp_pos(pos)
	pos.x = clamped.x
	pos.y = clamped.y if pos.y > floor_y() or pos.y < bounds.position.y + balance.body_size_px.y else pos.y


## Ставит героя в центр области (старт падения).
func place_at_center() -> void:
	pos = clamp_pos(Vector2(bounds.get_center().x, bounds.get_center().y + balance.body_size_px.y * 0.5))
	velocity = Vector2.ZERO


func tick_emotions(delta: float) -> void:
	emotions.tick(delta)


func is_sulking() -> bool:
	return emotions.is_sulking()


func emotion_wake_sec() -> float:
	return emotions.next_change_sec()
