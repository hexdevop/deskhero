class_name OverlayConfig
extends Resource
## Параметры оверлея: экран и FPS. Значения лежат в resources/overlay_config.tres.

## Страховочные границы FPS: 0 в Engine.max_fps значит "без лимита", а выше 240 смысла нет.
const MIN_FPS: int = 1
const MAX_FPS: int = 240

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
## Сколько раз подгонять окно под рабочую область, если ОС не даёт точный размер. Потом сдаёмся до смены области.
@export_range(1, 10) var fit_max_attempts: int = 3
## Сколько держать active_fps после последнего события мыши вне перетаскивания, сек.
@export_range(0.1, 5.0) var active_linger_sec: float = 0.5
## Сторона квадрата-плейсхолдера, px окна.
@export_range(16, 512) var square_size: int = 96
## Цвет квадрата.
@export var square_color: Color = Color(0.85, 0.2, 0.25, 1.0)
## Цвет квадрата во время перетаскивания.
@export var square_drag_color: Color = Color(1.0, 0.45, 0.3, 1.0)
## Страховка: сколько секунд без движения мыши держать перетаскивание, потом принудительно завершить.
@export_range(1.0, 60.0) var drag_timeout_sec: float = 10.0
