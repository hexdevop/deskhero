# DeskHero — архитектура

Целевая структура и принципы заданы в [docs/SPEC.md](../../docs/SPEC.md) §4–5. Здесь — то, что нужно команде для работы. Решения с вариантами фиксируются в `docs/DECISIONS.md`.

## Стек

| Что | Версия | Заметка |
|---|---|---|
| Godot | 4.7.2 | `brew install --cask godot`, CLI `godot` |
| GDScript | движка | Статическая типизация везде |
| GUT | 9.7.1 (тег v9.7.1, коммит aeb5d4f3f7f0) | В `addons/gut/`, только для тестов. Плагин не включать: он сам ходит в сеть. Флаг `-gcheck_update` запрещён. В экспорт не попадает |
| GDExtension (этап 0) | Objective-C, без godot-cpp | Минимальный модуль macOS: `native/deskhero_native.m`, нужен только Apple clang (D-005) |
| GDExtension (этап 5) | не выбрано | C++ (godot-cpp) или Rust (godot-rust), выбрать на этапе 5 |
| GitHub Actions | этап 10 | Сборка по тегу `v*` |

## Целевое дерево

```
project.godot
addons/gut/                  # тестовый фреймворк
docs/                        # SPEC, DECISIONS, ART
scenes/
  main.tscn                  # оверлей-окно, корень
  hero/ web/ ui/ minigames/
scripts/
  autoload/                  # event_bus, game_state, save_manager, settings, system_probe
  hero/                      # hero.gd, state_machine.gd, states/
  overlay/                   # этап 0: overlay.gd, placeholder_square.gd, overlay_config.gd
  web/
  platform/                  # с этапа 0: macos_window.gd; обёртки над GDExtension и fallback через OS.execute
resources/                   # overlay_config.tres
native/                      # GDExtension с этапа 0: deskhero_native.m, deskhero.gdextension
  bin/                       # собранная dylib, не в git
assets/                      # sprites, sounds, fonts
tests/                       # GUT
tools/build_native.fish      # с этапа 0: сборка нативного модуля
tools/build.fish             # этап 10
export_presets.cfg           # пресет macOS
build/                       # результаты сборки, не в git
.github/workflows/release.yml
```

## Модули

| Модуль | Ответственность |
|---|---|
| `main.tscn`, `scripts/overlay/` | Оверлей: окно, рабочая область, обновление passthrough-полигона, FPS-режимы, квадрат-плейсхолдер |
| `EventBus` | Глобальные типизированные сигналы, единственный канал между модулями |
| `GameState` | Потребности, прогресс, характер; чистая логика без сцены |
| `SaveManager` | JSON в `user://`, `schema_version`, миграции, атомарная запись |
| `Settings` | Настройки пользователя |
| `SystemProbe` | Время, idle, батарея, CPU, окна через сменные бэкенды |
| `scripts/hero/` | Иерархическая машина состояний: по файлу на состояние с `enter()/exit()/update()/handle_input()` |
| `scripts/web/` | Паутина: выстрел, верёвка, нитки в углах |
| `scripts/platform/` | Единственное место с платформенными ветвлениями; заглушки для неподдерживаемых ОС. Сейчас `MacosWindow`: `apply_all_spaces()`, `get_collection_behavior()`, `hide_from_dock()`, `is_available()` |
| `native/` | Нативный код. Сейчас класс `MacosWindowNative`: `collectionBehavior` окна и политика активации Accessory (D-005, D-006) |

Правила зависимостей: модули общаются через `EventBus`; логика, которую надо тестировать, не зависит от дерева сцены; числа баланса — только в ресурсе `.tres`.

Исключение этапа 0: `Overlay` и `PlaceholderSquare` связаны прямыми сигналами, `EventBus` ещё нет. На этапе 1 связи переводятся на него (D-004).

## Модель данных (сохранение)

```json
{
  "schema_version": 1,
  "last_seen_unix": 0,
  "needs": { "hunger": 0.0, "mood": 0.0, "energy": 0.0 },
  "progress": { "level": 1, "xp": 0, "unlocked_tricks": [] },
  "character": { "affectionate": 0.0, "nervous": 0.0, "playful": 0.0 },
  "memory": [],
  "flags": { "trash_confirmed": false }
}
```

Модель уточняет `architect` к этапу 3. Запись: во временный файл, затем переименование. Сохранения читаются только как JSON — никаких `str_to_var`, `bytes_to_var` с объектами и `load()` файлов из `user://`.

## Внешние интеграции

Сети нет. Системные API: `NSWindow.collectionBehavior` и `NSApp setActivationPolicy:` (macOS, с этапа 0), `CGWindowListCopyWindowInfo` (macOS), `EnumWindows` + `DwmGetWindowAttribute` (Windows), `_NET_CLIENT_LIST` (X11), `StatusIndicator` для трея, `OS.move_to_trash()`.

## Конфигурация и секреты

Секретов у приложения нет. Настройки — в `user://`. Если для CI появятся секреты, они живут только в GitHub Secrets. Ключевые настройки окна — в `project.godot` (прозрачность, без рамки, always on top). `LSUIElement` задан в пресете экспорта macOS, но сам по себе не действует: Godot ставит Regular в `main()`, поэтому политику Accessory ставит модуль из `Overlay._ready` (D-006).

## Запуск, сборка, тесты, линт

Все команды — fish, из корня проекта.

```fish
godot --path . --editor                                              # редактор
godot --path .                                                       # запуск оверлея из исходников
godot --headless --path . --import                                   # один раз в свежем клоне
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit   # тесты
godot --headless --path . --check-only --script <файл.gd>            # проверка синтаксиса

fish tools/build_native.fish                                         # нативный модуль: universal, macOS 13+, ad-hoc
godot --headless --path . --export-release macOS build/DeskHero.app  # экспорт, только --export-release
open build/DeskHero.app                                              # запуск сборки
```

`tools/build_native.fish` нужны только Apple clang и `godot` в PATH, сети он не использует. Заголовок `gdextension_interface.h` берётся у установленного движка в `build/native/include` и кэшируется. Для экспорта нужны шаблоны 4.7.2, см. `README.md`. Настоящее поведение Dock и Cmd+Tab видно только на экспортированной сборке. `tools/build.fish` из ТЗ появится на этапе 10 и не заменён этим скриптом.

Отдельного линтера нет; статическая типизация включается предупреждениями проекта (`untyped_declaration` как ошибка).
