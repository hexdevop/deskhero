# DeskHero

Десктопный питомец: маленький оригинальный супергерой-паутинщик, который живёт поверх рабочего стола, раскачивается на паутине между окнами и реагирует на пользователя и систему. Приложение работает полностью офлайн.

Полное ТЗ: `docs/SPEC.md`, решения: `docs/DECISIONS.md`.

## Требования

- Godot 4.7.2
- macOS (основная платформа), терминал fish

## Запуск

```fish
brew install --cask godot       # установка
godot --path . --editor         # редактор
godot --path .                  # запуск оверлея
godot --headless --path . --quit   # проверка, что проект загружается
```

## Нативный модуль (macOS)

Минимальный GDExtension на Objective-C (`native/deskhero_native.m`): ставит окну поведение «на всех Spaces» (`collectionBehavior` = CanJoinAllSpaces, Stationary, FullScreenAuxiliary, IgnoresCycle). Обёртка: `scripts/platform/macos_window.gd`. Нужен только Apple clang (Command Line Tools). Без модуля или не на macOS приложение работает, функция тихо выключена; в логе будет сообщение движка о незагруженной библиотеке.

```fish
fish tools/build_native.fish        # universal arm64+x86_64, macOS 13+, ad-hoc подпись
                                    # результат: native/bin/libdeskhero_native.macos.dylib (в git не попадает)
```

Заголовок `gdextension_interface.h` скрипт берёт у установленного godot (`--dump-gdextension-interface`) в `build/native/include`.

## Экспорт macOS

Один раз положите шаблоны экспорта 4.7.2 в `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` (нужны `macos.zip` и `version.txt` из официального `Godot_v4.7.2-stable_export_templates.tpz`, либо через редактор: Проект, Экспорт, Управление шаблонами).

```fish
fish tools/build_native.fish
godot --headless --path . --export-release macOS build/DeskHero.app
```

Пресет `macOS` в `export_presets.cfg`: universal, `LSUIElement` (Godot при старте сам ставит обычную политику активации и перекрывает его, поэтому модуль дополнительно ставит политику Accessory из `Overlay._ready`; в редакторе не применяется), ad-hoc подпись, из пака исключены `addons/gut`, `tests`, `tools`, `build`. Только `--export-release`. Сборка не нотаризована: первый запуск на другом Mac через правый клик, Открыть.
