class_name HeroBalance
extends Resource
## Все числа баланса героя. Значения лежат в resources/hero_balance.tres.
## Единицы: lpx (логические пиксели, на macOS точки), секунды, lpx/сек.

## Нижний предел подшага верёвки: меньше даст сотни подшагов за кадр.
const MIN_ROPE_SUBSTEP_SEC: float = 0.002


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
## Торможение по горизонтали при посадке: экспонента exp(-k*t). 20 за land_soft_sec оставляет около 5% скорости:
## герой не обрывает скольжение на полном ходу при переходе в idle.
@export var land_friction: float = 20.0
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
## Запас контура под силуэт сверх тела (x с каждой стороны, y сверху): плащ, наклон, вытяжение.
## На земле и в воздухе или в руках (там герой наклоняется и вытягивается).
@export var silhouette_ground_extra_px: Vector2 = Vector2(0.0, 8.0)
@export var silhouette_air_extra_px: Vector2 = Vector2(28.0, 22.0)
## Максимальный шаг логики за кадр.
@export var max_step_sec: float = 0.05
## Удержание правой кнопки для dev-выхода.
@export var dev_quit_hold_sec: float = 0.5

## --- Паутина (этап 2, D-011, D-012). Длины в lpx, скорости в lpx/с, время в секундах.
## Верёвка: фиксированный подшаг; доля высоты тела, на которой рука (точка крепления нити).
@export var rope_substep_sec: float = 0.00833
@export var rope_grip_height_ratio: float = 0.9
## Покой на нитке: скорость и отклонение от равновесия, ниже которых герой «замер».
@export var rope_rest_speed: float = 6.0
@export var rope_rest_stretch_px: float = 1.5
## Выстрел: предел длины, минимальная высота цели над полом, скорость кончика, замах, исчезновение нити.
@export var web_max_length_px: float = 1400.0
@export var web_min_height_px: float = 260.0
@export var web_shot_speed: float = 1800.0
@export var web_shoot_windup_sec: float = 0.2
@export var web_release_fade_sec: float = 0.25
## Число точек рисуемой провисшей нити.
@export var web_sag_points: int = 12
## Вылазки: шанс при конце паузы, минимальный интервал, шанс стены вместо верхнего края.
@export var web_trip_chance: float = 0.25
@export var web_trip_min_interval_sec: float = 180.0
@export var web_wall_anchor_chance: float = 0.2
## Раскачка: подмотка, затухание, смещение якоря по x, нужный простор, зазор до пола.
@export var swing_reel_speed: float = 420.0
@export var swing_damping: float = 0.15
@export var swing_anchor_dx_min_px: float = 180.0
@export var swing_anchor_dx_max_px: float = 520.0
@export var swing_min_room_px: float = 300.0
@export var swing_floor_clearance_px: float = 16.0
## Отпускание: угол нити за вертикалью (рад) и доля hard_landing_speed, ниже которой допустима посадка.
@export var swing_release_angle_min_rad: float = 0.25
@export var swing_release_angle_max_rad: float = 0.7
@export var swing_safe_impact_ratio: float = 0.8
@export var swing_max_sec: float = 6.0
@export var swing_lean_max_rad: float = 0.6
## Нитка-пружина (hang, stretched): жёсткость, демпфер по нити, затухание качания, скорости подъёма и спуска.
@export var thread_stiffness: float = 60.0
@export var thread_damping: float = 2.2
@export var thread_sway_damping: float = 0.8
@export var thread_ascend_speed: float = 480.0
@export var thread_descend_speed: float = 150.0
## Натяжение: предел растяжения, запас до разрыва, высота зоны хвата нити над головой.
@export var thread_max_stretch_px: float = 140.0
@export var thread_snap_extra_px: float = 40.0
@export var thread_grab_zone_px: float = 36.0
## Спуск: зазор под верхним краем, где герой подтягивается, доля пути для остановки, длительность паузы.
@export var hang_top_gap_px: float = 24.0
@export var hang_rest_ratio_min: float = 0.3
@export var hang_rest_ratio_max: float = 0.7
@export var hang_rest_min_sec: float = 8.0
@export var hang_rest_max_sec: float = 25.0
## Разброс якоря спуска по x вокруг героя (в обе стороны).
@export var descent_anchor_jitter_px: float = 60.0
## Доля вылазок, которые оказываются спуском (остальные раскачка).
@export var web_descent_chance: float = 0.3
## Верхняя доля высоты области, где выбирается якорь на стене.
@export var web_wall_anchor_zone_ratio: float = 0.333
## Запас допустимой высоты старта раскачки и доля стартового угла, не выше которой отпускается нить.
@export var swing_safe_height_margin: float = 0.85
@export var swing_release_start_ratio: float = 0.7
## Запасной план спуска (вход в hang без плана): доля доступной длины для остановки.
@export var hang_default_rest_ratio: float = 0.5
## Предел длительности одного этапа подъёма или спуска и стравливания нити: страховка от вечного бодрствования.
@export var web_stage_timeout_sec: float = 20.0
## Плетение и паутина в углах (T-213, T-214): поля заведены здесь, чтобы не трогать файл повторно.
@export var weave_idle_sec: float = 300.0
@export var weave_step_sec: float = 0.8
@export var weave_steps: int = 6
@export var weave_walk_max_px: float = 300.0
@export var corner_web_radius_px: float = 110.0
@export var web_fall_sec: float = 0.5
@export var sweep_min_speed: float = 500.0
@export var sweep_hit_px: float = 14.0
@export var sweep_clear_ratio: float = 0.35


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
	if silhouette_ground_extra_px.x < 0.0 or silhouette_ground_extra_px.y < 0.0 \
			or silhouette_air_extra_px.x < 0.0 or silhouette_air_extra_px.y < 0.0:
		errors.append("silhouette extra must not be negative")
	if gravity <= 0.0 or walk_speed <= 0.0:
		errors.append("gravity and walk_speed must be positive")
	if wall_restitution < 0.0 or wall_restitution > 1.0:
		errors.append("wall_restitution must be in 0..1")
	if sulk_sec < 0.0 or happy_sec < 0.0 or land_soft_sec < 0.0 or land_hard_sec < 0.0 or dev_quit_hold_sec < 0.0:
		errors.append("durations must not be negative")
	if hard_landing_speed <= 0.0:
		errors.append("hard_landing_speed must be positive")
	errors.append_array(_web_errors())
	return errors


func _web_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var positive: Dictionary = {
		"rope_substep_sec": rope_substep_sec, "rope_rest_speed": rope_rest_speed,
		"rope_rest_stretch_px": rope_rest_stretch_px, "web_max_length_px": web_max_length_px,
		"web_min_height_px": web_min_height_px, "web_shot_speed": web_shot_speed,
		"swing_reel_speed": swing_reel_speed, "swing_anchor_dx_min_px": swing_anchor_dx_min_px,
		"swing_anchor_dx_max_px": swing_anchor_dx_max_px, "swing_min_room_px": swing_min_room_px,
		"swing_max_sec": swing_max_sec, "thread_stiffness": thread_stiffness,
		"thread_ascend_speed": thread_ascend_speed, "thread_descend_speed": thread_descend_speed,
		"thread_max_stretch_px": thread_max_stretch_px, "thread_grab_zone_px": thread_grab_zone_px,
		"hang_rest_min_sec": hang_rest_min_sec, "hang_rest_max_sec": hang_rest_max_sec,
		"web_trip_min_interval_sec": web_trip_min_interval_sec, "weave_step_sec": weave_step_sec,
		"weave_walk_max_px": weave_walk_max_px, "corner_web_radius_px": corner_web_radius_px,
		"web_fall_sec": web_fall_sec, "sweep_min_speed": sweep_min_speed, "sweep_hit_px": sweep_hit_px,
		"web_release_fade_sec": web_release_fade_sec, "weave_idle_sec": weave_idle_sec,
		"swing_release_angle_max_rad": swing_release_angle_max_rad, "web_stage_timeout_sec": web_stage_timeout_sec,
		"swing_safe_height_margin": swing_safe_height_margin, "swing_release_start_ratio": swing_release_start_ratio,
	}
	for key: String in positive:
		if not (float(positive[key]) > 0.0):
			errors.append("%s must be positive" % key)
	var non_negative: Dictionary = {
		"web_shoot_windup_sec": web_shoot_windup_sec, "swing_damping": swing_damping,
		"swing_floor_clearance_px": swing_floor_clearance_px, "swing_release_angle_min_rad": swing_release_angle_min_rad,
		"swing_lean_max_rad": swing_lean_max_rad, "thread_damping": thread_damping,
		"thread_sway_damping": thread_sway_damping, "thread_snap_extra_px": thread_snap_extra_px,
		"hang_top_gap_px": hang_top_gap_px, "descent_anchor_jitter_px": descent_anchor_jitter_px,
	}
	for key: String in non_negative:
		if float(non_negative[key]) < 0.0:
			errors.append("%s must not be negative" % key)
	if rope_substep_sec < MIN_ROPE_SUBSTEP_SEC:
		errors.append("rope_substep_sec must be >= %s" % MIN_ROPE_SUBSTEP_SEC)
	if rope_substep_sec > max_step_sec:
		errors.append("rope_substep_sec > max_step_sec")
	if thread_stiffness > 0.0 and sqrt(thread_stiffness) * rope_substep_sec >= 0.5:
		errors.append("sqrt(thread_stiffness) * rope_substep_sec must be < 0.5")
	if swing_damping * rope_substep_sec >= 1.0 or thread_sway_damping * rope_substep_sec >= 1.0:
		errors.append("damping * rope_substep_sec must be < 1")
	if swing_anchor_dx_min_px > swing_anchor_dx_max_px:
		errors.append("swing_anchor_dx_min_px > swing_anchor_dx_max_px")
	if swing_release_angle_min_rad > swing_release_angle_max_rad:
		errors.append("swing_release_angle_min_rad > swing_release_angle_max_rad")
	if hang_rest_ratio_min > hang_rest_ratio_max:
		errors.append("hang_rest_ratio_min > hang_rest_ratio_max")
	if hang_rest_min_sec > hang_rest_max_sec:
		errors.append("hang_rest_min_sec > hang_rest_max_sec")
	var fractions: Dictionary = {
		"web_trip_chance": web_trip_chance, "web_wall_anchor_chance": web_wall_anchor_chance,
		"sweep_clear_ratio": sweep_clear_ratio, "hang_rest_ratio_min": hang_rest_ratio_min,
		"hang_rest_ratio_max": hang_rest_ratio_max, "rope_grip_height_ratio": rope_grip_height_ratio,
		"swing_safe_impact_ratio": swing_safe_impact_ratio, "web_descent_chance": web_descent_chance,
		"web_wall_anchor_zone_ratio": web_wall_anchor_zone_ratio, "swing_safe_height_margin": swing_safe_height_margin,
		"swing_release_start_ratio": swing_release_start_ratio, "hang_default_rest_ratio": hang_default_rest_ratio,
	}
	for key: String in fractions:
		var value: float = fractions[key]
		if is_nan(value) or value < 0.0 or value > 1.0:
			errors.append("%s must be in 0..1" % key)
	if rope_grip_height_ratio <= 0.0:
		errors.append("rope_grip_height_ratio must be positive")
	if swing_safe_impact_ratio <= 0.0:
		errors.append("swing_safe_impact_ratio must be positive")
	if weave_steps < 1:
		errors.append("weave_steps must be >= 1")
	if web_sag_points < 2:
		errors.append("web_sag_points must be >= 2")
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
