class_name WebRope
extends RefCounted
## Нить с якорем: одна связь, герой (ctx.pos, ctx.velocity) двигается напрямую (D-011).
## Фиксированный подшаг rope_substep_sec с накопителем: результат не зависит от нарезки кадров.
## HARD: жёсткая длина, проекция на окружность, подмотка разгоняет героя. SPRING: пружина при растяжении.
## Рисуемая геометрия считается отсюда, но рисует её WebLine (T-212). Без сцены.

enum Phase { OFF, SHOOTING, ATTACHED, RELEASED }
enum Mode { HARD, SPRING }

## Касание считается контактом, если проникновение больше этого (lpx).
const CONTACT_EPSILON: float = 0.05
## Больше этого за один advance не считается (защита от сотен тысяч подшагов после долгого сна).
const MAX_ADVANCE_SEC: float = 1.0
## Контакт с полом считается ударом, если вертикальная скорость больше этого числа шагов гравитации за подшаг.
## Скорость покоя на полу равна gravity * подшаг, так что порог следует за балансом.
const FLOOR_CONTACT_STEPS: float = 2.5
## Натяжение для вида (tension): провисшая, натянутая, в полёте.
const SLACK_TENSION: float = 0.15
const TAUT_TENSION: float = 0.55
const TRANSIT_TENSION: float = 0.5
const ANCHOR_EPSILON: float = 0.5
const TAUT_EPSILON: float = 0.01

var phase: Phase = Phase.OFF
var mode: Mode = Mode.HARD
var anchor: Vector2 = Vector2.ZERO
var length: float = 0.0
var target_length: float = 0.0
var reel_speed: float = 0.0
var touched_floor: bool = false
var touched_wall: bool = false
## Рука в последний раз, когда её сообщали (tick_visual, advance, attach): откуда уходит оборванная нить.
var hand: Vector2 = Vector2.ZERO

var _balance: HeroBalance
var _acc: float = 0.0
var _drag: float = 0.0
var _tip: Vector2 = Vector2.ZERO
var _tip_started: bool = false
var _tip_arrived: bool = false
var _release_from: Vector2 = Vector2.ZERO
var _fade_left: float = 0.0


func _init(p_balance: HeroBalance) -> void:
	_balance = p_balance


## Начинает выстрел: кончик идёт от руки к target. Якорь известен сразу, но связи ещё нет.
func shoot(target: Vector2) -> void:
	phase = Phase.SHOOTING
	anchor = target
	_tip_started = false
	_tip_arrived = false


## Кончик долетел до якоря (читает shoot_web).
func tip_arrived() -> bool:
	return phase == Phase.SHOOTING and _tip_arrived


## Связь установлена: длина равна текущему расстоянию от руки до якоря.
func attach(ctx: HeroContext, p_mode: Mode) -> void:
	phase = Phase.ATTACHED
	mode = p_mode
	hand = ctx.hand_pos()
	length = hand.distance_to(anchor)
	target_length = length
	reel_speed = _balance.swing_reel_speed if p_mode == Mode.HARD else _balance.thread_descend_speed
	_drag = _balance.swing_damping if p_mode == Mode.HARD else _balance.thread_sway_damping
	_acc = 0.0
	touched_floor = false
	touched_wall = false


## delta уже зажата вызывающим (max_step_sec). Подшаги с накопителем.
func advance(ctx: HeroContext, delta: float) -> void:
	touched_floor = false
	touched_wall = false
	if phase != Phase.ATTACHED:
		return
	var h: float = _balance.rope_substep_sec
	_acc += clampf(delta, 0.0, MAX_ADVANCE_SEC)
	while _acc >= h:
		_acc -= h
		_substep(ctx, h)
		if touched_floor or touched_wall:
			_acc = 0.0  # состояние разберёт вызывающий; остаток времени не нужен
			break
	hand = ctx.hand_pos()


func release() -> void:
	if phase != Phase.ATTACHED and phase != Phase.SHOOTING:
		return
	if phase == Phase.SHOOTING and _tip_started:
		_release_from = _tip
	else:
		_release_from = hand
	phase = Phase.RELEASED
	_fade_left = _balance.web_release_fade_sec


## Разрыв: как release; скорость героя не трогает (он уходит в carried или fall со своей).
func snap() -> void:
	release()


func is_taut(ctx: HeroContext) -> bool:
	return ctx.hand_pos().distance_to(anchor) >= length - TAUT_EPSILON


func stretch(ctx: HeroContext) -> float:
	return maxf(ctx.hand_pos().distance_to(anchor) - length, 0.0)


## Угол нити от вертикали вниз: 0 прямо под якорем, больше нуля, если рука правее якоря.
func angle(ctx: HeroContext) -> float:
	var d: Vector2 = ctx.hand_pos() - anchor
	return atan2(d.x, d.y)


## Положение ступней в равновесии под якорем.
func rest_pos(ctx: HeroContext) -> Vector2:
	var sag: float = _balance.gravity / _balance.thread_stiffness if mode == Mode.SPRING else 0.0
	return anchor + Vector2(0.0, length + sag) - ctx.hand_offset()


func is_settled(ctx: HeroContext) -> bool:
	if phase != Phase.ATTACHED:
		return false
	return ctx.velocity.length() < _balance.rope_rest_speed \
		and ctx.pos.distance_to(rest_pos(ctx)) < _balance.rope_rest_stretch_px


## Точная установка в равновесие без скачка (вызывать после is_settled): скорость 0.
func settle(ctx: HeroContext) -> void:
	ctx.pos = rest_pos(ctx)
	ctx.velocity = Vector2.ZERO
	hand = ctx.hand_pos()
	_acc = 0.0


## Якорь внутри области (с небольшим допуском: цели лежат на самом краю).
func anchor_valid(bounds: Rect2) -> bool:
	return anchor.x >= bounds.position.x - ANCHOR_EPSILON and anchor.x <= bounds.end.x + ANCHOR_EPSILON \
		and anchor.y >= bounds.position.y - ANCHOR_EPSILON and anchor.y <= bounds.end.y + ANCHOR_EPSILON


## Кончик в полёте (SHOOTING) и исчезновение (RELEASED). delta полная: большой кадр просто завершает анимацию.
func tick_visual(delta: float, p_hand: Vector2) -> void:
	hand = p_hand
	if phase == Phase.SHOOTING:
		if not _tip_started:
			_tip = p_hand
			_tip_started = true
		_tip = _tip.move_toward(anchor, _balance.web_shot_speed * maxf(delta, 0.0))
		if _tip.is_equal_approx(anchor):
			_tip_arrived = true
	elif phase == Phase.RELEASED:
		_fade_left -= maxf(delta, 0.0)
		if _fade_left <= 0.0:
			phase = Phase.OFF


## 0: нужны кадры (кончик летит, нить тает); INF: нить сама ничего не требует.
func wake_sec() -> float:
	if phase == Phase.SHOOTING or phase == Phase.RELEASED:
		return 0.0
	return INF


## Руку сообщают после обновления состояния (HeroContext.sync_web_hand): оборванная нить уходит от свежей руки,
## а не от положения прошлого кадра (М6 ревью T-211).
func sync_hand(p_hand: Vector2) -> void:
	hand = p_hand


## Натяжение для вида, 0..1: провисшая нить 0.15, натянутая 0.55, растянутая пружина до 1. Кончик и тающая нить 0.5.
func tension(p_hand: Vector2) -> float:
	match phase:
		Phase.ATTACHED:
			var chord: float = p_hand.distance_to(anchor)
			if chord < length - TAUT_EPSILON:
				return SLACK_TENSION
			var stretched: float = clampf((chord - length) / maxf(_balance.thread_max_stretch_px, 1.0), 0.0, 1.0)
			return lerpf(TAUT_TENSION, 1.0, stretched)
		Phase.SHOOTING, Phase.RELEASED:
			return TRANSIT_TENSION
	return 0.0


## Точки нити от руки (или кончика) к якорю. Натянутая: 2 точки, провисшая: web_sag_points. Пусто в OFF.
func draw_points(p_hand: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	match phase:
		Phase.SHOOTING:
			if _tip_started:
				points.append(p_hand)
				points.append(_tip)
		Phase.ATTACHED:
			var chord: float = p_hand.distance_to(anchor)
			if chord >= length - TAUT_EPSILON or _balance.web_sag_points <= 2:
				points.append(p_hand)
				points.append(anchor)
			else:
				var depth: float = 0.5 * sqrt(maxf(length * length - chord * chord, 0.0))
				var control: Vector2 = (p_hand + anchor) * 0.5 + Vector2(0.0, 2.0 * depth)
				var count: int = _balance.web_sag_points
				for i: int in count:
					var t: float = float(i) / float(count - 1)
					points.append(p_hand.lerp(control, t).lerp(control.lerp(anchor, t), t))
		Phase.RELEASED:
			var total: float = _balance.web_release_fade_sec
			var t_fade: float = 1.0 if total <= 0.0 else clampf(1.0 - _fade_left / total, 0.0, 1.0)
			points.append(_release_from.lerp(anchor, t_fade))
			points.append(anchor)
	return points


func _substep(ctx: HeroContext, h: float) -> void:
	var b: HeroBalance = _balance
	var vel: Vector2 = ctx.velocity
	vel.y += b.gravity * h
	vel *= maxf(0.0, 1.0 - _drag * h)
	var reeling: bool = length != target_length
	if reeling:
		length = move_toward(length, target_length, reel_speed * h)
	var offset: Vector2 = ctx.hand_offset()
	var q: Vector2 = ctx.pos + offset
	if reeling and length == target_length and mode == Mode.HARD:
		# подмотка закончилась: нить ловит героя, радиальная скорость гасится (иначе он по инерции уходит внутрь круга)
		var radial: Vector2 = q - anchor
		if radial.length_squared() > 0.0:
			var axis: Vector2 = radial.normalized()
			vel -= axis * vel.dot(axis)
	if mode == Mode.SPRING:
		var d: Vector2 = q - anchor
		var r: float = d.length()
		if r > length and r > 0.0001:
			var n: Vector2 = d / r
			var tension: float = maxf(b.thread_stiffness * (r - length) + b.thread_damping * vel.dot(n), 0.0)
			vel -= n * tension * h
		q += vel * h
	else:
		var moved: Vector2 = q + vel * h
		var d2: Vector2 = moved - anchor
		var r2: float = d2.length()
		if r2 > length and r2 > 0.0001:
			moved = anchor + d2 * (length / r2)
		vel = (moved - q) / h
		q = moved
	var p: Vector2 = q - offset
	# Стены, потолок, пол: зажим; контакт помечается флагом, скорость для вызывающего сохраняется.
	var half_w: float = b.body_size_px.x * 0.5
	var min_x: float = ctx.bounds.position.x + half_w
	var max_x: float = ctx.bounds.end.x - half_w
	if min_x > max_x:
		p.x = (min_x + max_x) * 0.5
		vel.x = 0.0
	elif p.x < min_x:
		touched_wall = touched_wall or min_x - p.x > CONTACT_EPSILON
		p.x = min_x
		vel.x = maxf(vel.x, absf(vel.x) * b.wall_restitution)
	elif p.x > max_x:
		touched_wall = touched_wall or p.x - max_x > CONTACT_EPSILON
		p.x = max_x
		vel.x = minf(vel.x, -absf(vel.x) * b.wall_restitution)
	var min_y: float = ctx.bounds.position.y + b.body_size_px.y
	if p.y < min_y:
		p.y = min_y
		vel.y = absf(vel.y) * b.wall_restitution
	if p.y > ctx.floor_y():
		if vel.y > FLOOR_CONTACT_STEPS * b.gravity * h and p.y - ctx.floor_y() > CONTACT_EPSILON:
			touched_floor = true
		else:
			vel.y = minf(vel.y, 0.0)
		p.y = ctx.floor_y()
	ctx.pos = p
	ctx.velocity = vel
