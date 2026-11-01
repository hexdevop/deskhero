class_name DisplayUnits
extends RefCounted
## Перевод логических пикселей (lpx, на macOS точки) в единицы Godot (D-010, пункт 6).
## Единица Godot = точка, умноженная на screen_get_max_scale(). На macOS значение не меняется за жизнь процесса.


## Единиц Godot в одном lpx; всегда положительное.
static func units_per_px() -> float:
	return sanitize(DisplayServer.screen_get_max_scale())


## Чистая функция: нулевой, отрицательный и нечисловой множитель заменяется единицей.
static func sanitize(value: float) -> float:
	if is_nan(value) or is_inf(value) or value <= 0.0:
		return 1.0
	return value
