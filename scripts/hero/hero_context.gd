class_name HeroContext
extends RefCounted
## Данные героя и мира. Без сцены; часы, rng и ввод приходят снаружи.
## Единицы: lpx. pos — точка между ступнями.

signal hard_landed(speed: float)
signal soft_landed()

const FLOOR_EPSILON: float = 0.01
## Поза плетения на нитке (в углу сверху); на полу поза просто weave.
const POSE_WEAVE_HANG: StringName = &"weave_hang"

var balance: HeroBalance
var rng: RandomNumberGenerator
var throw_tracker: ThrowTracker
var emotions: HeroEmotions
var rope: WebRope
var planner: WebPlanner
## Паутина в углах области (T-213).
var corners: CornerWebField
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
## Доля прошедшего времени посадки 0..1: читает вид (приседание).
var land_progress: float = 0.0
## Выставляется carried, чтобы root не перехватывал повторный PRESS.
var carrying: bool = false
## Что задумал герой (WebPlanner); null вне вылазки. Сбрасывается при выходе из группы web.
var plan: WebPlan = null
## Наклон тела в раскачке: радианы, как Node2D.rotation вокруг руки (0: висит прямо). Рисует HeroView.
var lean: float = 0.0
## Запас контура сверху: зона хвата нити в hang.
var contour_top_extra_px: float = 0.0
## Сколько секунд осталось до следующей вылазки (убывает в tick_web).
var web_cooldown_sec: float = 0.0
## Сколько секунд герой не брался в руки и не тянулся за нитку (растёт в tick_web). По нему решается плетение.
var calm_sec: float = 0.0
## Пауза после неудачной попытки плетения (прервано, не дошёл): убывает в tick_web.
var weave_cooldown_sec: float = 0.0

var _contour: Rect2 = Rect2()
var _contour_anchor: Vector2 = Vector2.ZERO
var _contour_valid: bool = false


func _init(p_balance: HeroBalance, p_rng: RandomNumberGenerator) -> void:
	balance = p_balance
	rng = p_rng
	throw_tracker = ThrowTracker.new(p_balance)
	emotions = HeroEmotions.new(p_balance)
	rope = WebRope.new(p_balance)
	planner = WebPlanner.new()
	corners = CornerWebField.new(p_balance, p_rng)
	corners.set_bounds(bounds)


func body_rect() -> Rect2:
	var size: Vector2 = balance.body_size_px
	return Rect2(pos.x - size.x * 0.5, pos.y - size.y, size.x, size.y)


## Силуэт: тело плюс запас на плащ, наклон и вытяжение. В воздухе и в руках запас больше.
func silhouette_rect() -> Rect2:
	var extra: Vector2 = balance.silhouette_ground_extra_px
	if pose == HeroState.FALL or pose == HeroState.THROWN or pose == HeroState.CARRIED \
			or pose == HeroState.SHOOT_WEB or pose == HeroState.SWING or pose == HeroState.HANG \
			or pose == HeroState.STRETCHED or pose == POSE_WEAVE_HANG:
		extra = balance.silhouette_air_extra_px
	var r: Rect2 = body_rect()
	return Rect2(r.position.x - extra.x, r.position.y - extra.y, r.size.x + extra.x * 2.0, r.size.y + extra.y)


## Габарит видимого героя: силуэт, повёрнутый на lean вокруг руки (точки крепления нити). При lean == 0 это силуэт.
func visual_rect() -> Rect2:
	var r: Rect2 = silhouette_rect()
	if is_zero_approx(lean):
		return r
	var pivot: Vector2 = hand_pos()
	var corners_in: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c: Vector2 in corners_in:
		var p: Vector2 = pivot + (c - pivot).rotated(lean)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


## Источник контура: видимый герой плюс зона хвата нити сверху. Неповёрнутый силуэт входит всегда:
## физическое тело остаётся в контуре, даже если вид наклонён.
func _contour_source() -> Rect2:
	var r: Rect2 = silhouette_rect().merge(visual_rect())
	return Rect2(r.position.x, r.position.y - contour_top_extra_px, r.size.x, r.size.y + contour_top_extra_px)


## Последний опубликованный контур: силуэт плюс запас. Если ещё не публиковался, считается по телу.
func contour_rect() -> Rect2:
	if _contour_valid:
		return _contour
	return _contour_source().grow(balance.contour_padding_px)


## Публикует новый контур, если герой сдвинулся от прошлого на contour_step_px или force.
## Инвариант: после вызова силуэт внутри контура.
func update_contour(force: bool) -> bool:
	var moved: Vector2 = (pos - _contour_anchor).abs()
	var need: bool = force or not _contour_valid \
		or maxf(moved.x, moved.y) >= balance.contour_step_px \
		or not _contour.encloses(_contour_source())
	if not need:
		return false
	_contour = _contour_source().grow(balance.contour_padding_px)
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
	corners.set_bounds(new_bounds)


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


## Смещение руки (точки крепления нити) от ступней: вверх на долю высоты тела.
func hand_offset() -> Vector2:
	return Vector2(0.0, -balance.body_size_px.y * balance.rope_grip_height_ratio)


func hand_pos() -> Vector2:
	return pos + hand_offset()


## Время паутины: кончик в полёте, исчезающая нить, перезарядка вылазки. delta полная, без зажима.
func tick_web(delta: float) -> void:
	web_cooldown_sec = maxf(web_cooldown_sec - delta, 0.0)
	calm_sec += maxf(delta, 0.0)
	weave_cooldown_sec = maxf(weave_cooldown_sec - delta, 0.0)
	rope.tick_visual(delta, hand_pos())
	corners.tick(delta)


## После обновления состояния: рука нити равна руке героя этого кадра (без отставания на кадр).
func sync_web_hand() -> void:
	rope.sync_hand(hand_pos())


## 0: паутина требует кадров (кончик летит, нить тает, смахнутые нити падают); INF: сама не будит.
func web_wake_sec() -> float:
	return minf(rope.wake_sec(), corners.wake_sec())
