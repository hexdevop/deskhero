class_name HeroView
extends Node2D
## Процедурный герой из полигонов и дуг (плейсхолдер до этапа 9). Логики нет: получает данные, считает позу
## через HeroPose и рисует. Рисует в lpx относительно ступней (0, 0); масштаб в единицы Godot задаёт родитель.
## Края сглаживаются: каждая форма обводится замкнутой полилинией с antialiased = true.
## Перерисовка: каждый кадр, пока герой в движении (walk, fall, thrown, carried, land, swing, hang, stretched); в покое только по изменению
## и по редкому таймеру (шаг дыхания, моргание), так что цикл сна не ломается.
## Оригинальный герой: индиго-капюшон с кисточкой, бирюзовый костюм, янтарный плащ, открытое лицо. Без символов на груди.

const DYNAMIC_POSES: Array[StringName] = [&"walk", &"fall", &"thrown", &"carried", &"land", &"swing", &"hang", &"stretched"]
const ICON_GAP: float = 10.0
const MSEC_PER_SEC: float = 1000.0

var _size: Vector2 = Vector2(56.0, 80.0)
var _pose: StringName = &"idle"
var _facing: int = 1
var _emotion: HeroEmotions.Emotion = HeroEmotions.Emotion.NEUTRAL
var _walk_phase: float = 0.0
var _motion: Vector2 = Vector2.ZERO
var _land_t: float = 0.0
var _impact: float = 0.0
var _breath: float = 0.0
var _breath_step: int = 0
var _blink: bool = false
var _blink_at_sec: float = -1.0
var _clock_override: float = -1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _data: HeroPose = HeroPose.new()
var _anim_timer: Timer


func _ready() -> void:
	_rng.randomize()
	_anim_timer = Timer.new()
	_anim_timer.one_shot = true
	_anim_timer.timeout.connect(_on_anim_timeout)
	add_child(_anim_timer)
	_sync_idle_anim()


func configure(body_size: Vector2) -> void:
	_size = body_size
	queue_redraw()


## Фиксирует часы анимации (для листа поз и тестов); отрицательное значение возвращает реальные часы.
func set_clock(sec: float) -> void:
	_clock_override = sec


## Задаёт дыхание и моргание вручную (лист поз). Таймер покоя при этом не меняет их, пока поза не динамическая.
func set_idle_phase(breath_step: int, blink_closed: bool) -> void:
	_breath_step = posmod(breath_step, HeroLook.BREATH_STEPS)
	_breath = _breath_value(_breath_step)
	_blink = blink_closed
	queue_redraw()


## motion: скорость в lpx/с; land_t: 0..1 по посадке; impact: ударная скорость как доля hard_landing_speed.
func apply(pose: StringName, facing: int, walk_phase: float, emotion: HeroEmotions.Emotion,
		motion: Vector2 = Vector2.ZERO, land_t: float = 0.0, impact: float = 0.0) -> void:
	var dynamic: bool = DYNAMIC_POSES.has(pose)
	var changed: bool = pose != _pose or facing != _facing or emotion != _emotion
	_pose = pose
	_facing = facing
	_emotion = emotion
	_walk_phase = walk_phase
	_motion = motion
	_land_t = land_t
	_impact = impact
	if changed:
		_sync_idle_anim()
	if dynamic or changed:
		queue_redraw()


func _draw() -> void:
	_data.solve(_pose, _facing, _walk_phase, _emotion, _motion, _land_t, _impact, _breath, _blink, _clock())
	var s: float = _size.y / HeroLook.DESIGN_HEIGHT
	var squash := Transform2D(Vector2(_data.scale.x, 0.0), Vector2(0.0, _data.scale.y), Vector2.ZERO)
	var lean := Transform2D(0.0, _data.pivot) * Transform2D(_data.lean, Vector2.ZERO) * Transform2D(0.0, -_data.pivot)
	var flip := Transform2D(Vector2(s * float(_facing), 0.0), Vector2(0.0, s), Vector2.ZERO)
	draw_set_transform_matrix(flip * lean * squash)
	_draw_cape()
	_draw_leg(_data.foot_far, -HeroLook.HIP_X, HeroLook.SUIT_SHADE)
	_draw_leg(_data.foot_near, HeroLook.HIP_X, HeroLook.SUIT)
	_draw_torso()
	_draw_collar()
	_draw_head()
	_draw_arm(_data.hand_far, -HeroLook.SHOULDER_X, HeroLook.SUIT_SHADE, false)
	_draw_arm(_data.hand_near, HeroLook.SHOULDER_X, HeroLook.SUIT, true)
	draw_set_transform_matrix(Transform2D(0.0, Vector2.ZERO))
	_draw_icon(-HeroLook.DESIGN_HEIGHT * s * _data.scale.y - ICON_GAP * s)


# --- Части тела (дизайн-единицы)

func _draw_cape() -> void:
	var by: float = _data.bob
	var anchor: Vector2 = HeroLook.CAPE_ANCHOR + Vector2(0.0, by)
	var dir: Vector2 = _data.cape_dir
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var end: Vector2 = anchor + dir * _data.cape_length
	var half_base: float = 8.0
	var half_end: float = 13.0
	var bend: Vector2 = side * _data.cape_bend
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(anchor - side * half_base)
	for i: int in range(1, 6):  # одна кромка
		var t: float = float(i) / 6.0
		pts.append(anchor.lerp(end, t) - side * lerpf(half_base, half_end, t) + bend * sin(t * PI))
	# зубчатый низ: три фестона
	var left_end: Vector2 = end - side * half_end
	var right_end: Vector2 = end + side * half_end
	for i: int in range(0, 13):
		var t: float = float(i) / 12.0
		var scallop: float = absf(sin(t * PI * 3.0)) * 3.2
		pts.append(left_end.lerp(right_end, t) + dir * (scallop - 1.0) + bend * 0.8)
	for i: int in range(5, 0, -1):
		var t: float = float(i) / 6.0
		pts.append(anchor.lerp(end, t) + side * lerpf(half_base, half_end, t) + bend * sin(t * PI))
	pts.append(anchor + side * half_base)
	_shape(pts, HeroLook.CAPE)
	var fold: PackedVector2Array = PackedVector2Array([anchor.lerp(end, 0.25), anchor.lerp(end, 0.65) + bend * 0.5, anchor.lerp(end, 0.95) + bend * 0.7])
	draw_polyline(fold, HeroLook.CAPE_SHADE, 1.5, true)


func _draw_leg(foot: Vector2, hip_x: float, color: Color) -> void:
	var hip: Vector2 = Vector2(hip_x, HeroLook.HIP_Y)
	var ankle: Vector2 = foot + Vector2(0.0, -5.0)
	_shape(HeroShapes.capsule(hip, ankle, 3.9), color)
	var boot: PackedVector2Array = HeroShapes.ellipse(foot + Vector2(2.2, -4.6), Vector2(6.4, 3.9), HeroLook.CIRCLE_POINTS)
	_shape(boot, HeroLook.BOOT)


func _draw_torso() -> void:
	var by: float = _data.bob
	var top: float = HeroLook.TORSO_TOP + by
	var rect := Rect2(-HeroLook.TORSO_HALF_W, top, HeroLook.TORSO_HALF_W * 2.0, HeroLook.TORSO_BOTTOM - top)
	_shape(HeroShapes.round_rect(rect, 5.5, 5), HeroLook.SUIT)
	var belt := Rect2(-HeroLook.TORSO_HALF_W + 0.4, -20.0 + by * 0.4, HeroLook.TORSO_HALF_W * 2.0 - 0.8, 3.4)
	_shape(HeroShapes.round_rect(belt, 0.8, 1), HeroLook.CAPE)
	draw_circle(Vector2(1.5, -18.3 + by * 0.4), 1.9, HeroLook.MINT, true, -1.0, true)
	draw_arc(Vector2(1.5, -18.3 + by * 0.4), 1.9, 0.0, TAU, 12, HeroLook.INK, 1.0, true)


func _draw_collar() -> void:
	var c: Vector2 = Vector2(1.0, -29.5 + _data.bob)
	_shape(HeroShapes.ellipse(c, Vector2(12.5, 4.4), HeroLook.CIRCLE_POINTS), HeroLook.CAPE)


func _draw_head() -> void:
	var by: Vector2 = Vector2(0.0, _data.bob)
	var hc: Vector2 = HeroLook.HEAD_CENTER + by
	# кисточка капюшона: загибается назад и реагирует на ветер
	var tip: Vector2 = hc + Vector2(-21.0, -29.0) + _data.tuft_shift
	var tuft: PackedVector2Array = HeroShapes.bezier(hc + Vector2(2.0, -21.0), hc + Vector2(-12.0, -33.0), tip, 8)
	var inner: PackedVector2Array = HeroShapes.bezier(tip, hc + Vector2(-22.0, -20.0), hc + Vector2(-17.0, -10.0), 8)
	tuft.append_array(inner)
	_shape(tuft, HeroLook.HOOD)
	_shape(HeroShapes.ellipse(hc, HeroLook.HEAD_RADIUS, 40), HeroLook.HOOD)
	var rim: PackedVector2Array = HeroShapes.ellipse_arc(hc, HeroLook.HEAD_RADIUS - Vector2(2.2, 2.2), deg_to_rad(200.0), deg_to_rad(285.0), 12)
	draw_polyline(rim, HeroLook.HOOD_LIGHT, 2.4, true)
	var fc: Vector2 = HeroLook.FACE_CENTER + by
	_shape(HeroShapes.ellipse(fc, HeroLook.FACE_RADIUS, 36), HeroLook.SKIN, 1.3)
	var shade: PackedVector2Array = HeroShapes.ellipse_arc(fc, HeroLook.FACE_RADIUS - Vector2(1.8, 1.8), deg_to_rad(205.0), deg_to_rad(335.0), 12)
	draw_polyline(shade, Color(0.89, 0.66, 0.52), 2.6, true)
	_draw_face(fc)


func _draw_face(fc: Vector2) -> void:
	var left: Vector2 = fc + Vector2(-6.0, 0.5)
	var right: Vector2 = fc + Vector2(6.5, 0.5)
	var blush_k: float = 1.0
	match _emotion:
		HeroEmotions.Emotion.HAPPY:
			_eye_happy(left)
			_eye_happy(right)
			_mouth_open(fc + Vector2(0.0, 7.5))
			blush_k = 1.4
		HeroEmotions.Emotion.SCARED:
			_eye_wide(left)
			_eye_wide(right)
			_brow(left + Vector2(-3.6, -6.8), left + Vector2(3.0, -9.2))
			_brow(right + Vector2(3.6, -6.8), right + Vector2(-3.0, -9.2))
			_mouth_o(fc + Vector2(0.0, 9.0))
			_sweat_drop(fc + Vector2(14.5, -11.0))
			blush_k = 0.0
		HeroEmotions.Emotion.OFFENDED:
			_eye_lidded(left)
			_eye_lidded(right)
			_brow(left + Vector2(-3.6, -6.2), left + Vector2(3.2, -3.4))
			_brow(right + Vector2(3.6, -6.2), right + Vector2(-3.2, -3.4))
			draw_arc(fc + Vector2(0.0, 13.5), 4.6, deg_to_rad(222.0), deg_to_rad(318.0), 10, HeroLook.INK, 1.8, true)
			blush_k = 1.2
		_:
			if _blink:
				_eye_blink(left)
				_eye_blink(right)
			else:
				_eye_open(left)
				_eye_open(right)
			draw_arc(fc + Vector2(0.0, 5.2), 3.4, deg_to_rad(35.0), deg_to_rad(145.0), 8, HeroLook.INK, 1.7, true)
	if blush_k > 0.0:
		var cheek: Color = HeroLook.BLUSH
		cheek.a *= minf(blush_k, 1.0)
		_blush(fc + Vector2(-9.5, 6.5), Vector2(3.0, 1.9) * blush_k, cheek)
		_blush(fc + Vector2(10.5, 6.5), Vector2(3.0, 1.9) * blush_k, cheek)


func _draw_arm(hand: Vector2, shoulder_x: float, color: Color, device: bool) -> void:
	var shoulder: Vector2 = Vector2(shoulder_x, HeroLook.SHOULDER_Y + _data.bob)
	_shape(HeroShapes.capsule(shoulder, hand, 3.3), color)
	if device:
		var wrist: Vector2 = shoulder.lerp(hand, 0.72)
		draw_circle(wrist, 2.1, HeroLook.MINT, true, -1.0, true)
		draw_arc(wrist, 2.1, 0.0, TAU, 12, HeroLook.INK, 1.0, true)
	_shape(HeroShapes.ellipse(hand, Vector2(3.7, 3.7), 16), HeroLook.CAPE, 1.4)


# --- Мимика

func _eye_open(c: Vector2) -> void:
	_shape(HeroShapes.ellipse(c, Vector2(3.0, 4.2), 18), HeroLook.INK, 0.0)
	draw_circle(c + Vector2(0.9, -1.5), 1.2, HeroLook.WHITE, true, -1.0, true)
	draw_circle(c + Vector2(-0.8, 1.6), 0.6, HeroLook.WHITE, true, -1.0, true)


func _eye_blink(c: Vector2) -> void:
	draw_arc(c + Vector2(0.0, -1.2), 3.2, deg_to_rad(30.0), deg_to_rad(150.0), 8, HeroLook.INK, 1.9, true)


func _eye_happy(c: Vector2) -> void:
	draw_arc(c + Vector2(0.0, 2.4), 3.4, deg_to_rad(205.0), deg_to_rad(335.0), 10, HeroLook.INK, 2.1, true)


func _eye_wide(c: Vector2) -> void:
	_shape(HeroShapes.ellipse(c, Vector2(3.7, 5.0), 20), HeroLook.WHITE, 1.4)
	draw_circle(c + Vector2(0.4, 0.4), 1.8, HeroLook.INK, true, -1.0, true)
	draw_circle(c + Vector2(0.9, -0.3), 0.6, HeroLook.WHITE, true, -1.0, true)


func _eye_lidded(c: Vector2) -> void:
	var pts: PackedVector2Array = HeroShapes.ellipse_arc(c + Vector2(0.0, -0.6), Vector2(3.2, 3.4), 0.0, PI, 10)
	_shape(pts, HeroLook.INK, 0.0)


func _brow(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, HeroLook.INK, 1.8, true)


func _mouth_open(c: Vector2) -> void:
	var pts: PackedVector2Array = HeroShapes.ellipse_arc(c, Vector2(4.4, 4.2), 0.0, PI, 10)
	_shape(pts, HeroLook.INK, 0.0)
	var tongue: PackedVector2Array = HeroShapes.ellipse_arc(c + Vector2(0.0, 2.2), Vector2(2.4, 1.6), 0.0, PI, 8)
	_shape(tongue, Color(0.94, 0.45, 0.47), 0.0)


func _mouth_o(c: Vector2) -> void:
	_shape(HeroShapes.ellipse(c, Vector2(2.2, 3.0), 14), HeroLook.INK, 0.0)


func _blush(c: Vector2, r: Vector2, color: Color) -> void:
	_shape(HeroShapes.ellipse(c, r, 14), color, 0.0)


func _sweat_drop(c: Vector2) -> void:
	var pts: PackedVector2Array = PackedVector2Array([c + Vector2(0.0, -5.5), c + Vector2(2.2, -1.5)])
	pts.append_array(HeroShapes.ellipse_arc(c + Vector2(0.0, 0.8), Vector2(2.7, 2.7), deg_to_rad(-20.0), deg_to_rad(200.0), 8))
	pts.append(c + Vector2(-2.2, -1.5))
	_shape(pts, HeroLook.SWEAT, 1.2)


## Значок над головой (SPEC §6): искры, восклицание, тучка. Не входит в контур, шрифтов нет.
func _draw_icon(y: float) -> void:
	match _emotion:
		HeroEmotions.Emotion.HAPPY:
			_sparkle(Vector2(-8.0, y + 2.0), 4.5)
			_sparkle(Vector2(7.0, y - 3.0), 3.2)
		HeroEmotions.Emotion.SCARED:
			draw_line(Vector2(0.0, y - 9.0), Vector2(0.0, y - 1.0), HeroLook.INK, 5.0, true)
			draw_line(Vector2(0.0, y - 9.0), Vector2(0.0, y - 1.0), HeroLook.CAPE, 3.0, true)
			draw_circle(Vector2(0.0, y + 4.0), 2.6, HeroLook.INK, true, -1.0, true)
			draw_circle(Vector2(0.0, y + 4.0), 1.5, HeroLook.CAPE, true, -1.0, true)
		HeroEmotions.Emotion.OFFENDED:
			var cloud: Color = Color(0.46, 0.43, 0.62)
			for c: Vector3 in [Vector3(-5.5, y, 4.6), Vector3(0.5, y - 2.5, 5.8), Vector3(6.5, y, 4.4)]:
				draw_circle(Vector2(c.x, c.y), c.z, cloud, true, -1.0, true)
				draw_arc(Vector2(c.x, c.y), c.z, 0.0, TAU, 14, HeroLook.INK, 1.3, true)
			for c: Vector3 in [Vector3(-5.5, y, 3.4), Vector3(0.5, y - 2.5, 4.6), Vector3(6.5, y, 3.2)]:
				draw_circle(Vector2(c.x, c.y), c.z, cloud, true, -1.0, true)
		_:
			pass


func _sparkle(c: Vector2, r: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 8:
		var a: float = float(i) * PI * 0.25
		var rad: float = r if i % 2 == 0 else r * 0.35
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	_shape(pts, HeroLook.CAPE, 1.1)


# --- Рисование

## Заливка и сглаживающая обводка. width 0: без обводки, но с мягким краем цветом заливки.
func _shape(pts: PackedVector2Array, color: Color, width: float = HeroLook.OUTLINE_W) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, color)
	var ring: PackedVector2Array = pts.duplicate()
	ring.append(pts[0])
	if width > 0.0:
		draw_polyline(ring, HeroLook.INK, width, true)
	else:
		draw_polyline(ring, color, 1.0, true)


# --- Покой: дыхание и моргание по редкому таймеру

func _clock() -> float:
	if _clock_override >= 0.0:
		return _clock_override
	return float(Time.get_ticks_msec()) / MSEC_PER_SEC


func _breath_value(step: int) -> float:
	return (1.0 - cos(float(step) / float(HeroLook.BREATH_STEPS) * TAU)) * 0.5


## Включает таймер только в покое; в остальных позах дыхания и моргания нет.
func _sync_idle_anim() -> void:
	if _anim_timer == null:
		return
	if _pose != &"idle":
		_anim_timer.stop()
		_blink = false
		_breath = 0.0
		return
	_blink_at_sec = _clock() + _rng.randf_range(HeroLook.BLINK_MIN_SEC, HeroLook.BLINK_MAX_SEC)
	_on_anim_timeout()


func _on_anim_timeout() -> void:
	if _pose != &"idle" or _clock_override >= 0.0:
		return
	var now: float = _clock()
	var step: int = int(now / HeroLook.BREATH_STEP_SEC) % HeroLook.BREATH_STEPS
	var closed: bool = now >= _blink_at_sec and now < _blink_at_sec + HeroLook.BLINK_SEC
	if now >= _blink_at_sec + HeroLook.BLINK_SEC:
		_blink_at_sec = now + _rng.randf_range(HeroLook.BLINK_MIN_SEC, HeroLook.BLINK_MAX_SEC)
	var dirty: bool = step != _breath_step or closed != _blink
	_breath_step = step
	_breath = _breath_value(step)
	_blink = closed
	if dirty:
		queue_redraw()
	var next_step: float = HeroLook.BREATH_STEP_SEC - fmod(now, HeroLook.BREATH_STEP_SEC)
	var next_blink: float = (_blink_at_sec - now) if _blink_at_sec > now else (_blink_at_sec + HeroLook.BLINK_SEC - now)
	_anim_timer.start(maxf(minf(next_step, next_blink), 0.02))
