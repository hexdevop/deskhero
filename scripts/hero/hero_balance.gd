class_name HeroBalance
extends Resource
## Все числа баланса героя. Значения лежат в resources/hero_balance.tres.
## Единицы: lpx (логические пиксели, на macOS точки), секунды, lpx/сек.

## Размер тела (ширина, высота).
@export var body_size_px: Vector2 = Vector2(56.0, 80.0)
## Ускорение падения.
@export var gravity: float = 1400.0
## Предел скорости падения вниз.
@export var max_fall_speed: float = 1400.0
## Торможение в полёте после броска: доля скорости в секунду.
@export var air_drag: float = 0.4
## Доля скорости, остающаяся после удара о стену или потолок.
@export var wall_restitution: float = 0.4
## Торможение по горизонтали при посадке: доля скорости в секунду.
@export var land_friction: float = 6.0
## Скорость ходьбы.
@export var walk_speed: float = 50.0
## Пауза между прогулками, минимум и максимум.
@export var idle_pause_min_sec: float = 15.0
@export var idle_pause_max_sec: float = 45.0
## Длина прогулки, минимум и максимум.
@export var walk_distance_min_px: float = 40.0
@export var walk_distance_max_px: float = 200.0
## Длина одного цикла ходьбы (фаза ног проходит 0..1 за этот путь).
@export var walk_stride_px: float = 24.0
## Минимальная скорость отпускания, с которой начинается бросок.
@export var throw_min_speed: float = 150.0
## Потолок скорости броска.
@export var throw_max_speed: float = 2400.0
## Окно, по которому считается скорость броска.
@export var throw_sample_window_sec: float = 0.1
## Скорость удара, с которой посадка жёсткая.
@export var hard_landing_speed: float = 1000.0
## Длительность посадки.
@export var land_soft_sec: float = 0.15
@export var land_hard_sec: float = 0.6
## Эмоции: радость после мягкой посадки, обида, потолок обиды (используются в T-112).
@export var happy_sec: float = 2.0
@export var sulk_sec: float = 12.0
@export var sulk_max_sec: float = 30.0
## Контур для passthrough: шаг пересчёта и запас вокруг тела.
@export var contour_step_px: float = 6.0
@export var contour_padding_px: float = 6.0
## Максимальный шаг логики за кадр.
@export var max_step_sec: float = 0.05
## Удержание правой кнопки для dev-выхода.
@export var dev_quit_hold_sec: float = 0.5


## Список нарушений инвариантов; пустой, если баланс корректен.
func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if contour_padding_px < contour_step_px:
		errors.append("contour_padding_px < contour_step_px")
	if idle_pause_min_sec > idle_pause_max_sec:
		errors.append("idle_pause_min_sec > idle_pause_max_sec")
	if walk_distance_min_px > walk_distance_max_px:
		errors.append("walk_distance_min_px > walk_distance_max_px")
	if throw_min_speed > throw_max_speed:
		errors.append("throw_min_speed > throw_max_speed")
	if sulk_sec > sulk_max_sec:
		errors.append("sulk_sec > sulk_max_sec")
	if max_fall_speed <= hard_landing_speed:
		errors.append("max_fall_speed <= hard_landing_speed")
	if body_size_px.x <= 0.0 or body_size_px.y <= 0.0:
		errors.append("body_size_px must be positive")
	if walk_stride_px <= 0.0 or max_step_sec <= 0.0 or throw_sample_window_sec <= 0.0:
		errors.append("walk_stride_px, max_step_sec, throw_sample_window_sec must be positive")
	if contour_step_px <= 0.0:
		errors.append("contour_step_px must be positive")
	if gravity <= 0.0 or walk_speed <= 0.0:
		errors.append("gravity and walk_speed must be positive")
	if wall_restitution < 0.0 or wall_restitution > 1.0:
		errors.append("wall_restitution must be in 0..1")
	if sulk_sec < 0.0 or happy_sec < 0.0 or land_soft_sec < 0.0 or land_hard_sec < 0.0 or dev_quit_hold_sec < 0.0:
		errors.append("durations must not be negative")
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
