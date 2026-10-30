class_name MacosWindow
extends RefCounted
## Обёртка над нативным модулем (native/deskhero_native.m): окно на всех Spaces.
## Единственное место с проверкой ОС и наличия класса. Нет macOS или модуля: тихо ничего не делает.

const NATIVE_CLASS: StringName = &"MacosWindowNative"

## NSWindowCollectionBehavior: CanJoinAllSpaces | Stationary | IgnoresCycle | FullScreenAuxiliary.
const MASK_ALL_SPACES: int = (1 << 0) | (1 << 4) | (1 << 6) | (1 << 8)


## Есть ли смысл вызывать нативную часть (macOS и модуль загружен).
static func is_available() -> bool:
	return OS.get_name() == "macOS" and ClassDB.class_exists(NATIVE_CLASS)


## Выставить окну поведение «на всех Spaces». true, если после вызова все нужные биты стоят.
## Повторный вызов безопасен: нативный код трогает окно, только если маска отличается.
static func apply_all_spaces(window_id: int = DisplayServer.MAIN_WINDOW_ID) -> bool:
	var value: int = _call(&"apply_all_spaces", window_id)
	return value >= 0 and (value & MASK_ALL_SPACES) == MASK_ALL_SPACES


## Текущее значение collectionBehavior или -1, если недоступно.
static func get_collection_behavior(window_id: int = DisplayServer.MAIN_WINDOW_ID) -> int:
	return _call(&"get_collection_behavior", window_id)


## Убрать приложение из Dock и Cmd+Tab (политика Accessory). Godot при старте сам ставит Regular
## поверх LSUIElement, поэтому ставим повторно из кода. Не трогает редактор. true, если политика Accessory.
static func hide_from_dock() -> bool:
	if Engine.is_editor_hint() or not is_available():
		return false
	var result: Variant = ClassDB.class_call_static(NATIVE_CLASS, &"set_accessory_policy")
	return result is int and result == 1


static func _call(method: StringName, window_id: int) -> int:
	if not is_available():
		return -1
	var handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window_id)
	if handle == 0:
		return -1
	# Динамический вызов: класс может отсутствовать, статическая ссылка не скомпилировалась бы
	var result: Variant = ClassDB.class_call_static(NATIVE_CLASS, method, handle)
	return result if result is int else -1
