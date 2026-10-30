class_name OverlayConfig
extends Resource
## Параметры оверлея: экран и FPS. Значения лежат в resources/overlay_config.tres.

## Индекс экрана; основной монитор. Для мульти-мониторов меняется здесь или через Overlay.set_screen().
@export var screen_index: int = -1
## FPS при активности (перетаскивание, движение героя).
@export_range(5, 120) var active_fps: int = 30
## FPS в покое и во сне.
@export_range(1, 30) var idle_fps: int = 8
## Включать low_processor_mode: кадры рисуются только по событиям или по таймеру.
@export var low_processor_mode: bool = true
## Пауза между итерациями главного цикла в low_processor_mode, мкс.
@export var low_processor_sleep_usec: int = 33333
## Период проверки смены геометрии экрана, сек. Одна проверка стоит микросекунды.
@export_range(0.5, 30.0) var screen_check_interval_sec: float = 2.0
