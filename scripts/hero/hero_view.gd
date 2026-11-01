class_name HeroView
extends Node2D
## Плейсхолдер героя из примитивов. Логики нет: получает позу и перерисовывается только при изменении.
## Рисует в lpx относительно ступней (0, 0); масштаб в единицы Godot задаёт родитель через scale.
## Оригинальный силуэт: графитовый шлем с янтарным визором, бирюзовый костюм. Без символов на груди.

@export var graphite: Color = Color(0.16, 0.18, 0.21)
@export var turquoise: Color = Color(0.1, 0.7, 0.68)
@export var amber: Color = Color(1.0, 0.73, 0.2)

var _size: Vector2 = Vector2(56.0, 80.0)
var _pose: StringName = &"idle"
var _facing: int = 1
var _emotion: HeroEmotions.Emotion = HeroEmotions.Emotion.NEUTRAL
var _step: int = 0


func configure(body_size: Vector2) -> void:
	_size = body_size
	queue_redraw()


## Перерисовка только если что-то видимое изменилось. Фаза ходьбы округляется до двух шагов ног.
func apply(pose: StringName, facing: int, walk_phase: float, emotion: HeroEmotions.Emotion) -> void:
	var step: int = 1 if (pose == &"walk" and walk_phase >= 0.5) else 0
	if pose == _pose and facing == _facing and emotion == _emotion and step == _step:
		return
	_pose = pose
	_facing = facing
	_emotion = emotion
	_step = step
	queue_redraw()


func _draw() -> void:
	var w: float = _size.x
	var h: float = _size.y
	if _pose == &"land":
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.12, 0.85))
	var hip: float = -0.32 * h
	var shoulder: float = -0.62 * h
	var leg_w: float = 0.13 * w
	var arm_w: float = 0.1 * w
	# ноги
	var swing: float = 0.0
	if _pose == &"walk":
		swing = (0.2 if _step == 0 else -0.2) * w
	elif _pose == &"carried" or _pose == &"thrown" or _pose == &"fall":
		swing = 0.06 * w
	draw_line(Vector2(-0.12 * w, hip), Vector2(-0.12 * w + swing, 0.0), graphite, leg_w)
	draw_line(Vector2(0.12 * w, hip), Vector2(0.12 * w - swing, 0.0), graphite, leg_w)
	# руки
	var arm_end_l: Vector2 = Vector2(-0.34 * w, -0.38 * h)
	var arm_end_r: Vector2 = Vector2(0.34 * w, -0.38 * h)
	match _pose:
		&"carried":
			arm_end_l = Vector2(-0.38 * w, -0.94 * h)
			arm_end_r = Vector2(0.38 * w, -0.94 * h)
		&"fall", &"thrown":
			arm_end_l = Vector2(-0.48 * w, -0.8 * h)
			arm_end_r = Vector2(0.48 * w, -0.8 * h)
		&"walk":
			arm_end_l.x += swing * 0.5
			arm_end_r.x -= swing * 0.5
	draw_line(Vector2(-0.26 * w, shoulder), arm_end_l, graphite, arm_w)
	draw_line(Vector2(0.26 * w, shoulder), arm_end_r, graphite, arm_w)
	# торс: капсула
	var torso_r: float = 0.25 * w
	var torso_top: float = -0.66 * h + torso_r
	var torso_bottom: float = hip + 0.04 * h - torso_r
	draw_circle(Vector2(0.0, torso_top), torso_r, turquoise)
	draw_circle(Vector2(0.0, torso_bottom), torso_r, turquoise)
	draw_rect(Rect2(-torso_r, torso_top, torso_r * 2.0, torso_bottom - torso_top), turquoise)
	# пояс
	draw_rect(Rect2(-torso_r, torso_bottom - 0.03 * h, torso_r * 2.0, 0.05 * h), amber)
	# голова
	var head_r: float = 0.17 * h
	var head: Vector2 = Vector2(0.0, -h + head_r)
	draw_circle(head, head_r, graphite)
	_draw_visor(head, head_r)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_emotion_icon(-h - 14.0)


func _draw_visor(head: Vector2, head_r: float) -> void:
	var f: float = float(_facing)
	var centre: Vector2 = head + Vector2(f * head_r * 0.28, 0.0)
	var vw: float = head_r * 1.2
	var vh: float = head_r * 0.42
	var color: Color = amber
	if _emotion == HeroEmotions.Emotion.OFFENDED:
		color = amber.darkened(0.45)
		vh *= 0.6
	elif _emotion == HeroEmotions.Emotion.SCARED:
		vh *= 1.5
	draw_rect(Rect2(centre.x - vw * 0.5, centre.y - vh * 0.5, vw, vh), color)
	if _emotion == HeroEmotions.Emotion.HAPPY:
		draw_arc(centre + Vector2(0.0, vh * 0.7), vw * 0.3, 0.15 * PI, 0.85 * PI, 8, graphite, 1.5)
	elif _emotion == HeroEmotions.Emotion.OFFENDED:
		draw_line(centre + Vector2(-vw * 0.5, -vh * 0.9), centre + Vector2(vw * 0.5, -vh * 0.2), graphite, 1.5)
	else:
		draw_rect(Rect2(centre.x - vw * 0.2, centre.y - vh * 0.5, 2.0, vh), graphite)


## Значок над головой: радость, испуг, обида. Не входит в контур, шрифтов нет.
func _draw_emotion_icon(y: float) -> void:
	match _emotion:
		HeroEmotions.Emotion.HAPPY:
			draw_arc(Vector2(0.0, y - 2.0), 7.0, 0.1 * PI, 0.9 * PI, 10, amber, 2.5)
		HeroEmotions.Emotion.SCARED:
			draw_line(Vector2(0.0, y - 9.0), Vector2(0.0, y + 1.0), amber, 3.0)
			draw_circle(Vector2(0.0, y + 7.0), 2.0, amber)
		HeroEmotions.Emotion.OFFENDED:
			draw_circle(Vector2(-4.0, y), 5.0, graphite)
			draw_circle(Vector2(4.0, y - 2.0), 6.0, graphite)
			draw_circle(Vector2(10.0, y + 1.0), 4.0, graphite)
		_:
			pass
