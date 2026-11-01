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
  autoload/                  # event_bus (этап 1); game_state, save_manager, settings, system_probe позже
  hero/                      # см. «Этап 1: герой»
  overlay/                   # overlay.gd, overlay_config.gd, passthrough_shape.gd (этап 1); placeholder_square.gd удаляется в T-113
  web/
  platform/                  # macos_window.gd, display_units.gd (этап 1); обёртки над GDExtension и fallback через OS.execute
resources/                   # overlay_config.tres, hero_balance.tres
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
| `main.tscn`, `scripts/overlay/` | Оверлей: окно, рабочая область, переезд между мониторами, passthrough-полигон, FPS-режимы. Про героя знает только через `EventBus` |
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

Исключение этапа 0: `Overlay` и `PlaceholderSquare` связаны прямыми сигналами, `EventBus` ещё нет. Оно заканчивается в T-110 (D-004, D-010).

## Этап 1: герой

Решения и причины — в D-010. Здесь контракт для исполнителей. Единицы логики и баланса — `lpx` (логические пиксели, на macOS точки). Координаты `pos` — точка между ступнями.

### Дерево

```
scenes/main.tscn             # Main (Overlay) → Hero (экземпляр hero.tscn)
scenes/hero/hero.tscn        # Hero (Node2D) → View (HeroView), WakeTimer (Timer, one_shot)
scripts/autoload/event_bus.gd        # без class_name: имя занято autoload
scripts/hero/
  hero.gd                    # Hero: единственный мост логика ↔ Godot
  hero_view.gd               # HeroView: рисует примитивами, логики нет
  hero_balance.gd            # HeroBalance (Resource)
  hero_input.gd              # HeroInput: значение ввода
  hero_context.gd            # HeroContext: данные героя и мира
  hero_emotions.gd           # HeroEmotions
  throw_tracker.gd           # ThrowTracker: скорость броска
  state_machine.gd           # HeroStateMachine
  states/
    hero_state.gd            # HeroState (база, RefCounted)
    root_state.gd  grounded_state.gd  airborne_state.gd     # суперсостояния
    idle_state.gd  walk_state.gd  land_state.gd             # внутри grounded
    fall_state.gd  thrown_state.gd                          # внутри airborne
    carried_state.gd                                        # внутри root
scripts/overlay/passthrough_shape.gd # static rect_polygon, window_scale (из PlaceholderSquare)
scripts/platform/display_units.gd    # DisplayUnits.units_per_px() -> float
resources/hero_balance.tres
```

### Логика (без сцены)

```gdscript
class_name HeroState extends RefCounted
var ctx: HeroContext
var parent: HeroState                         # null у root
func enter() -> void
func exit() -> void
func update(delta: float) -> StringName       # id следующего состояния или &""
func handle_input(input: HeroInput) -> StringName
func next_tick_sec() -> float                 # 0: каждый кадр; >0: сон; INF: до внешнего события

class_name HeroStateMachine extends RefCounted
signal state_changed(from: StringName, to: StringName)
func _init(context: HeroContext) -> void
func start(initial: StringName) -> void
func update(delta: float) -> void
func handle_input(input: HeroInput) -> void
func next_tick_sec() -> float                 # минимум по цепочке листа и по ctx.emotions
func current_id() -> StringName

class_name HeroContext extends RefCounted
signal hard_landed(speed: float)
var balance: HeroBalance
var rng: RandomNumberGenerator                # seed задаётся снаружи, в тестах фиксирован
var emotions: HeroEmotions
var throw_tracker: ThrowTracker
var bounds: Rect2                             # lpx
var pos: Vector2
var velocity: Vector2
var facing: int                               # -1 или 1
var pose: StringName                          # для HeroView
var walk_phase: float
var grab_offset: Vector2
func body_rect() -> Rect2
func contour_rect() -> Rect2                  # последний опубликованный: тело + padding
func update_contour(force: bool) -> bool      # true, если сдвиг >= contour_step_px или force
func floor_y() -> float
func set_bounds(new_bounds: Rect2) -> void    # втягивает x внутрь, y не трогает, если над полом

class_name HeroInput extends RefCounted
enum Kind { PRESS, MOVE, RELEASE, CANCEL, RESYNC }
var kind: Kind
var pos: Vector2                              # lpx, координаты окна
var now_sec: float

class_name ThrowTracker extends RefCounted
func reset() -> void
func add_sample(pos: Vector2, now_sec: float) -> void
func velocity(now_sec: float) -> Vector2      # по окну throw_sample_window_sec; меньше двух разных моментов: ноль
```

`HeroStateMachine` строит таблицу id → состояние. `update` и `handle_input` идут от листа к корню до первого непустого id. Переход выполняет `exit` от листа до общего предка, затем `enter` вниз. Переход в текущий лист не перезапускает его. За один `update` выполняется не больше одного перехода.

| Состояние | Родитель | Делает | Переходы |
|---|---|---|---|
| `root` | — | — | `PRESS` в контуре → `carried` |
| `grounded` | `root` | Держит ноги на полу, если пол поднялся | Пол опустился → `fall` |
| `idle` | `grounded` | Стоит, считает паузу | Пауза кончилась и нет обиды → `walk` |
| `walk` | `grounded` | Идёт к цели, у стены разворачивается | Цель достигнута → `idle` |
| `land` | `grounded` | Гасит скорость `land_friction`, длится `land_soft_sec` или `land_hard_sec` | Время вышло → `idle` |
| `airborne` | `root` | Гравитация, `max_fall_speed`, стены и потолок с `wall_restitution` | Касание пола → `land` |
| `fall` | `airborne` | Обычное падение | Через родителя |
| `thrown` | `airborne` | Добавляет `air_drag` | Через родителя |
| `carried` | `root` | `pos` за курсором с `grab_offset`, зажат в `bounds`; на `RESYNC` сброс `ThrowTracker` и новая проба | `RELEASE`: скорость >= `throw_min_speed` → `thrown`, иначе `fall`; `CANCEL` → `fall` с нулевой скоростью |

Старт: `fall` из центра рабочей области. `airborne` запоминает скорость удара для `land`. Удар >= `hard_landing_speed` → `land` с `land_hard_sec`, `emotions.offend()`, сигнал `hard_landed`.

`next_tick_sec`: `idle` возвращает остаток паузы или, при обиде, `INF`. Всё остальное возвращает 0. Машина берёт минимум с `emotions.next_change_sec()`, поэтому герой проснётся к концу эмоции и обиды.

### Эмоции

```gdscript
class_name HeroEmotions extends RefCounted
enum Emotion { NEUTRAL, HAPPY, SCARED, OFFENDED }
signal changed(emotion: Emotion)
func show_for(emotion: Emotion, sec: float) -> void   # INF: пока не снимут
func clear_temporary() -> void
func offend() -> void
func is_sulking() -> bool
func tick(delta: float) -> void                       # зовёт машина в каждом update
func next_change_sec() -> float
```

| Событие | Эмоция |
|---|---|
| `carried.enter`, `thrown.enter` | `SCARED`, держится до посадки |
| Мягкая посадка | `HAPPY` на `happy_sec` |
| Жёсткая посадка | `OFFENDED`, обида на `sulk_sec` |
| Повторная жёсткая посадка при обиде | Обида растёт на `sulk_sec`, максимум `sulk_max_sec` |
| Обида кончилась | `NEUTRAL` |

Обида важнее остальных: пока она идёт, видна `OFFENDED`, а `show_for` не перекрывает её. Обида — это таймер, а не седьмое состояние: герой не гуляет, но его можно таскать и бросать. Отдельное состояние понадобится только для другого поведения.

### Баланс

Все числа — в `resources/hero_balance.tres`, значения стартовые, настраиваются руками. `HeroBalance.is_valid()` проверяет: `contour_padding_px >= contour_step_px`, минимум <= максимум, `max_fall_speed > hard_landing_speed`.

| Поле | Значение | Поле | Значение |
|---|---|---|---|
| `body_size_px` | (56, 80) | `throw_min_speed` | 150 |
| `gravity` | 1400 | `throw_max_speed` | 2400 |
| `max_fall_speed` | 1400 | `throw_sample_window_sec` | 0.1 |
| `air_drag` | 0.4 | `hard_landing_speed` | 1000 |
| `wall_restitution` | 0.4 | `land_soft_sec` | 0.15 |
| `land_friction` | 6.0 | `land_hard_sec` | 0.6 |
| `walk_speed` | 50 | `happy_sec` | 2.0 |
| `idle_pause_min_sec` | 15 | `sulk_sec` | 12 |
| `idle_pause_max_sec` | 45 | `sulk_max_sec` | 30 |
| `walk_distance_min_px` | 40 | `contour_step_px` | 6 |
| `walk_distance_max_px` | 200 | `contour_padding_px` | 6 |
| `max_step_sec` | 0.05 | `dev_quit_hold_sec` | 0.5 |

### EventBus

| Сигнал | Кто шлёт | Кто слушает |
|---|---|---|
| `world_bounds_changed(bounds: Rect2)` | `Overlay` | `Hero` |
| `drag_cursor_resync(cursor: Vector2)` | `Overlay` | `Hero` |
| `drag_cancel_requested()` | `Overlay` | `Hero` |
| `hero_contour_changed(rect: Rect2)` | `Hero` | `Overlay` |
| `hero_drag_started()` | `Hero` | `Overlay` |
| `hero_drag_ended()` | `Hero` | `Overlay` |
| `hero_activity_changed(active: bool)` | `Hero` | `Overlay` |
| `quit_requested()` | `Hero` | `Overlay` |
| `hero_state_changed(from: StringName, to: StringName)` | `Hero` | На этапе 1 только тесты, дальше потребности и характер |
| `hero_emotion_changed(emotion: HeroEmotions.Emotion)` | `Hero` | То же |
| `hero_hard_landed(speed: float)` | `Hero` | То же |

Координаты в сигналах — единицы viewport. В `lpx` их переводит только `Hero`. `work_area_changed` убирается, он заменён `world_bounds_changed`. Этот же контракт `Overlay` и квадрат используют в T-110, пока героя нет: шлёт `PlaceholderSquare`. `hero_activity_changed`, `hero_state_*`, `hero_emotion_*`, `hero_hard_landed` объявляются в T-113.

Порядок важен: `Hero` — потомок `Overlay`, поэтому `Hero._ready` и подключения к `EventBus` выполняются раньше `Overlay._ready`, а первый `world_bounds_changed` уже будет услышан. `Hero._input` выполняется раньше `Overlay._input`, поэтому логика `_track_drag` с уточнением позиции сохраняется. Сигналы синхронны: переезд шлёт сначала `world_bounds_changed`, затем `drag_cursor_resync`.

### Hero (мост)

Шаг: `_process(delta)` → `machine.update(minf(delta, max_step_sec))` → `_after_step()`. Пробуждение таймером передаёт реальное прошедшее время без ограничения.

`_after_step()`:
1. Записать `position` как `ctx.pos * units`, передать в `HeroView` позу, направление, фазу и эмоцию. `HeroView` вызывает `queue_redraw` только при изменении.
2. `ctx.update_contour(false)`; если `true`, послать `hero_contour_changed`.
3. `wait := machine.next_tick_sec()`. Если `wait >= 0.05`: `set_process(false)`, таймер на `wait` (при `INF` не заводить), `hero_activity_changed(false)`. Иначе: `set_process(true)`, таймер стоп, `hero_activity_changed(true)`. Сигнал — только при смене значения.

Ввод: `_input` переводит `InputEvent` в `HeroInput`, после него сразу `_after_step()`. Просыпается и спящий герой. Попадание считается по `contour_rect()`. `now_sec` берётся из `Time.get_ticks_usec()` здесь. Потерянное отпускание (`button_mask` пуст при движении) даёт `CANCEL`. Вход и выход из `carried` по `state_changed` шлют `hero_drag_started` и `hero_drag_ended`. При остановке героя контур публикуется с `force`, чтобы полигон совпал с телом.

Dev-выход: нажатие правой кнопки на контуре запоминает время, отпускание на контуре не раньше `dev_quit_hold_sec` шлёт `quit_requested`. Сохраняется до T-304. Запасной выход: `pkill -f DeskHero.app`.

Запрещено: `_physics_process`, `CharacterBody2D`, `Area2D`, обращение к `Overlay`, перерисовка в `idle`.

### Overlay (изменения T-110, T-113)

- Убрать `placeholder`, подключения к квадрату, `_cancel_drag` через прямой вызов (теперь `drag_cancel_requested`), `drag_to` и `set_bounds` (теперь `drag_cursor_resync`, `world_bounds_changed`).
- Контур хранить из `hero_contour_changed`. `_update_passthrough` по-прежнему ставит полигон только при изменении. Границы и переезд из T-009 сохраняются.
- FPS: `_apply_fps` выбирает активный, если `_mouse_active or _hero_active or _capturing`. Ловушка: `_on_linger_timeout` сейчас снимает активность напрямую и замедлил бы идущего героя. Он должен снимать только `_mouse_active`.
- При переезде нет потери герою: в `carried` он следует за курсором. Вне `carried` окно не переезжает.

Смена рабочей области: `world_bounds_changed` → `ctx.set_bounds` → шаг с `delta = 0`. Пол опустился: `fall`. Поднялся: ноги на полу. Спящий герой просыпается этим же путём. Экран пропал: окно на основном, тот же путь.

### Плейсхолдер

`HeroView` рисует только `draw_*`: капсула тела, круглая голова, визор, руки и ноги линиями, эмоция значком над головой без шрифтов. Значок не входит в контур. Палитра: графит, бирюза, янтарь. Запрещены красно-синяя схема, паутинный узор на костюме и символ на груди: NFR-6. Цвета — `@export` в `HeroView`, это не баланс. Поза `carried` — руки вверх, `land` — приседание, `walk` — две фазы ног. Моргания в покое нет: оно добавляется позже через `next_tick_sec`, без постоянной перерисовки.

### Тесты (T-114)

Симуляция — цикл `machine.update(1.0 / 30.0)` с фиксированным seed, без сцены.

- Переходы всей таблицы, порядок `enter`/`exit` через общего предка, всплытие, запрет двух переходов за шаг.
- Падение приземляется на `floor_y`, скорость не выше `max_fall_speed`, большой шаг не проваливает пол.
- Отскок от стен и потолка, герой всегда внутри `bounds`.
- Прогулка в границах, разворот, доля времени ходьбы за 1 час симуляции около 7% (проверка бюджета D-010).
- `ThrowTracker`: равномерное движение, остановка перед отпусканием даёт ноль, одна проба даёт ноль, `reset`, ограничение `throw_max_speed`.
- `RELEASE` с быстрой и медленной скоростью, `CANCEL`, `RESYNC` не даёт ложного броска.
- Порог `hard_landing_speed`, накопление и потолок обиды, запрет прогулок и их возобновление.
- `next_tick_sec`: больше 0 только в `idle`, учитывает конец эмоции; разбиение паузы на сон и пробуждение даёт тот же момент перехода.
- Инвариант: на всей симуляции `body_rect` внутри `contour_rect` после каждого шага.
- `set_bounds`: пол выше, пол ниже, сужение по x.
- `HeroBalance.is_valid` и загрузка `.tres`.
- `Hero` в дереве через вызов `_input`: `PRESS`, перевод единиц, удержание dev-выхода, короткий правый клик не выходит.
- Перенос старых тестов `clamp_position`, `rect_polygon`, `window_scale`, `drag_to`.

### Ручная проверка (T-116, основа чек-листа)

На `.app`, команды в fish.

- Старт: герой падает из центра на нижний край и стоит над Dock.
- Ходьба: редкие прогулки, не выходит за края, поза меняется.
- Клики сквозь: рядом с идущим героем клики проходят, клик по идущему хватает его с первого раза, снаружи контура плюс 5 px уходит сквозь.
- Бросок: рывок даёт полёт с инерцией, отскок от стен; медленное отпускание даёт простое падение; остановка перед отпусканием не бросает.
- Посадка: мягкая даёт радость, жёсткая — обиду и паузу в прогулках; поймать героя в полёте можно.
- Два монитора: перенос в `carried` работает, после отпускания на другом мониторе нет случайного броска, герой падает на пол нового монитора; бросок упирается в край монитора.
- Рабочая область: смена размера Dock и автоскрытие, герой остаётся на полу.
- Прерывания: Cmd+Tab посреди drag, потерянное отпускание, клики не зависают.
- Выход: короткий правый клик не закрывает, удержание закрывает.
- Работа рядом: 10 минут обычной работы, записать случайные перехваты и потерю фокуса.
- Покой: CPU по `top`, как в чек-листе этапа 0, плюс сценарий «жизнь» и drag.
- Оригинальность: силуэт и палитра не похожи на чужих персонажей.

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
