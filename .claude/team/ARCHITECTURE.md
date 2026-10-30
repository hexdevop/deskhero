# DeskHero — архитектура

Целевая структура и принципы заданы в [docs/SPEC.md](../../docs/SPEC.md) §4–5. Здесь — то, что нужно команде для работы. Решения с вариантами фиксируются в `docs/DECISIONS.md`.

## Стек

| Что | Версия | Заметка |
|---|---|---|
| Godot | 4.7.2 | `brew install --cask godot`, CLI `godot` |
| GDScript | движка | Статическая типизация везде |
| GUT | 9.7.1 (тег v9.7.1, коммит aeb5d4f3f7f0) | В `addons/gut/`, только для тестов. Плагин не включать: он сам ходит в сеть. Флаг `-gcheck_update` запрещён. В экспорт не попадает |
| GDExtension | этап 5 | C++ (godot-cpp) или Rust (godot-rust), выбрать на этапе 5 |
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
  web/
  platform/                  # обёртки над GDExtension и fallback через OS.execute
native/                      # GDExtension, с этапа 5
assets/                      # sprites, sounds, fonts
tests/                       # GUT
tools/build.fish
.github/workflows/release.yml
```

## Модули

| Модуль | Ответственность |
|---|---|
| `main.tscn` | Оверлей: окно, рабочая область, обновление passthrough-полигона, FPS-режимы |
| `EventBus` | Глобальные типизированные сигналы, единственный канал между модулями |
| `GameState` | Потребности, прогресс, характер; чистая логика без сцены |
| `SaveManager` | JSON в `user://`, `schema_version`, миграции, атомарная запись |
| `Settings` | Настройки пользователя |
| `SystemProbe` | Время, idle, батарея, CPU, окна через сменные бэкенды |
| `scripts/hero/` | Иерархическая машина состояний: по файлу на состояние с `enter()/exit()/update()/handle_input()` |
| `scripts/web/` | Паутина: выстрел, верёвка, нитки в углах |
| `scripts/platform/` | Единственное место с платформенными ветвлениями; заглушки для неподдерживаемых ОС |

Правила зависимостей: модули общаются через `EventBus`; логика, которую надо тестировать, не зависит от дерева сцены; числа баланса — только в ресурсе `.tres`.

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

Сети нет. Системные API: `CGWindowListCopyWindowInfo` (macOS), `EnumWindows` + `DwmGetWindowAttribute` (Windows), `_NET_CLIENT_LIST` (X11), `StatusIndicator` для трея, `OS.move_to_trash()`.

## Конфигурация и секреты

Секретов у приложения нет. Настройки — в `user://`. Если для CI появятся секреты, они живут только в GitHub Secrets. Ключевые настройки окна — в `project.godot` (прозрачность, без рамки, always on top); `LSUIElement` — через настройки экспорта macOS.

## Запуск, тесты, линт

```fish
godot --path . --editor                                              # редактор
godot --path .                                                       # запуск оверлея
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit   # тесты
godot --headless --path . --check-only --script <файл.gd>            # проверка синтаксиса
```

Команды тестов уточняются в T-002 и после этого обновляются в `CLAUDE.md`. Отдельного линтера нет; статическая типизация включается предупреждениями проекта (`untyped_declaration` как ошибка).
