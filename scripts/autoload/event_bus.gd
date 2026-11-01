extends Node
## Глобальный канал между модулями (autoload EventBus). Только типизированные сигналы, логики нет.
## Без class_name: имя занято autoload. Контракт — в .claude/team/ARCHITECTURE.md, раздел «EventBus».
## Координаты в сигналах — единицы viewport.

## Overlay: границы мира героя (область окна) изменились.
@warning_ignore("unused_signal")
signal world_bounds_changed(bounds: Rect2)
## Overlay: окно переехало во время drag, позиция курсора в новых координатах окна.
@warning_ignore("unused_signal")
signal drag_cursor_resync(cursor: Vector2)
## Overlay: потеря фокуса или таймаут, drag надо прервать.
@warning_ignore("unused_signal")
signal drag_cancel_requested
## Герой: контур изменился (не каждый кадр).
@warning_ignore("unused_signal")
signal hero_contour_changed(rect: Rect2)
@warning_ignore("unused_signal")
signal hero_drag_started
@warning_ignore("unused_signal")
signal hero_drag_ended
## Dev-выход.
@warning_ignore("unused_signal")
signal quit_requested
