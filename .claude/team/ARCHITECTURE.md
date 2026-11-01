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
| `scripts/web/` | Паутина: логика верёвки, планировщик, углы, виды. Подключается к миру только через `Hero`, см. «Этап 2: паутина» |
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

## Этап 2: паутина

Решения и причины — в D-011 (верёвка) и D-012 (поведение, контур, смахивание). Единицы — `lpx`, как на этапе 1. Логика без сцены, ограничения T-111 (`Node`, `EventBus`, `DisplayServer`, `InputEvent`, `Time`) действуют и на `scripts/web/` кроме `*_view.gd` и `web_line.gd`. `_physics_process`, `PinJoint2D`, `Area2D` запрещены.

Базис T-117 учитывается по факту: `motion_fps` в `Overlay`, новый вид `HeroView`. Перед T-211 сверить этот раздел с итогом T-117.

### Файлы

```
scripts/web/
  web_rope.gd                # WebRope: связь, подшаг, рисуемая геометрия
  web_plan.gd                # WebPlan: значение, что герой задумал
  web_planner.gd             # WebPlanner: выбор действия и цели
  corner_web_field.gd        # CornerWebField: паутина в углах, смахивание
  web_line.gd                # WebLine (Node2D): рисует нить
  corner_webs_view.gd        # CornerWebsView (Node2D): рисует углы
scripts/hero/states/
  web_state.gd               # группа web
  shoot_web_state.gd  swing_state.gd  hang_state.gd  stretched_state.gd  weave_state.gd
scenes/web/web_line.tscn     # top_level, потомок Hero
scenes/web/corner_webs.tscn  # top_level, потомок Hero
```

Дерево `hero.tscn`: `Hero` → `CornerWebs`, `WebLine`, `View`, `WakeTimer`. Порядок задаёт отрисовку: нить под героем. `top_level = true`, потому что `Hero` двигается, `scale` = `units_per_px`, в `_refresh_units` обновляется вместе с `View`.

### Логика

```gdscript
class_name WebRope extends RefCounted
enum Phase { OFF, SHOOTING, ATTACHED, RELEASED }
enum Mode { HARD, SPRING }
var phase: Phase
var mode: Mode
var anchor: Vector2
var length: float
var target_length: float
var reel_speed: float
var touched_floor: bool                       # сброс в начале advance
var touched_wall: bool
func _init(p_balance: HeroBalance) -> void
func shoot(target: Vector2) -> void           # SHOOTING, кончик идёт от руки к target
func attach(ctx: HeroContext, mode: Mode) -> void   # ATTACHED, length = текущее расстояние
func advance(ctx: HeroContext, delta: float) -> void  # подшаги; delta уже зажата вызывающим
func release() -> void                        # RELEASED, кончик уходит к якорю за web_release_fade_sec
func snap() -> void                           # разрыв: как release, скорость ctx не трогает
func is_taut(ctx: HeroContext) -> bool
func stretch(ctx: HeroContext) -> float       # max(r - length, 0)
func is_settled(ctx: HeroContext) -> bool     # скорость < rope_rest_speed и отклонение от равновесия < rope_rest_stretch_px
func settle(ctx: HeroContext) -> void         # точная установка в равновесие, скорость 0
func anchor_valid(bounds: Rect2) -> bool
func tick_visual(delta: float, hand: Vector2) -> void   # SHOOTING, RELEASED
func wake_sec() -> float                      # 0 в SHOOTING и RELEASED, иначе INF
func draw_points(hand: Vector2) -> PackedVector2Array   # 2 точки натянутой, web_sag_points при провисе; пусто в OFF

class_name WebPlan extends RefCounted
enum Kind { SWING, DESCENT, WEAVE_TOP, WEAVE_BOTTOM }
var kind: Kind
var anchor: Vector2
var walk_to_x: float                          # NAN: идти не надо
var corner: int                               # CornerWebField.Corner или -1
var swing_length: float
var rest_length: float                        # DESCENT: где остановиться
var release_angle: float

class_name WebPlanner extends RefCounted
func decide(ctx: HeroContext) -> StringName   # WALK, SHOOT_WEB или WEAVE; пишет ctx.plan
func swing_plan(ctx: HeroContext) -> WebPlan  # null, если нет места
func descent_plan(ctx: HeroContext) -> WebPlan
func weave_plan(ctx: HeroContext) -> WebPlan
static func predicted_impact(pos: Vector2, velocity: Vector2, floor_y: float, gravity: float, max_fall: float) -> float

class_name CornerWebField extends RefCounted
enum Corner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }
signal woven(corner: int)
signal swept(corner: int)
var revision: int                             # растёт при любом видимом изменении
func _init(p_balance: HeroBalance, p_rng: RandomNumberGenerator) -> void
func set_bounds(bounds: Rect2) -> void        # начала углов считаются от bounds, координаты нитей локальны
func weave_step(corner: int) -> bool          # true: готово
func sweep(from: Vector2, to: Vector2, dt: float) -> bool   # true: что-то изменилось
func tick(delta: float) -> void               # падающие нити
func wake_sec() -> float                      # 0, пока нити падают
func has_webs() -> bool
func free_corners() -> Array[int]
func draw_data() -> Array                     # типизированные структуры для вида: отрезки, альфа
```

`HeroContext` получает: `rope: WebRope`, `corners: CornerWebField`, `planner: WebPlanner`, `plan: WebPlan`, `lean: float`, `contour_top_extra_px: float`, `calm_sec: float` (время без взаимодействия), `web_cooldown_sec: float`, `hand_pos() -> Vector2`, `visual_rect() -> Rect2`, `tick_web(delta)`, `web_wake_sec()`. `update_contour` и запасной случай `contour_rect` берут `visual_rect()` и добавляют сверху `contour_top_extra_px`. `set_bounds` передаёт границы в `corners`.

`HeroStateMachine.update` рядом с `tick_emotions` вызывает `ctx.tick_web(delta)` с полной `delta`. `next_tick_sec` берёт минимум ещё и с `ctx.web_wake_sec()`. `calm_sec` растёт в `tick_web`, сбрасывается при входе в `carried` и `stretched`. `web_cooldown_sec` убывает там же.

### Состояния

`HeroState` получает константы `WEB`, `SHOOT_WEB`, `SWING`, `HANG`, `STRETCHED`, `WEAVE` и две статические проверки: `is_drag(id)` (`carried`, `stretched`) и `is_fast(id)` (`fall`, `thrown`, `carried`, `swing`, `stretched`).

| Состояние | Родитель | Делает | Переходы |
|---|---|---|---|
| `web` | `root` | `next_tick_sec` = `INF`. `exit`: `rope.release()`, если паутина прикреплена; `plan = null`, `lean = 0`, `contour_top_extra_px = 0`. Выход только при уходе из группы, поэтому `shoot_web` → `swing` нить не трогает | Якорь вне `bounds` → `fall`. Паутина не прикреплена и ноги выше пола → `fall` |
| `shoot_web` | `web` | Лицом к якорю, пауза `web_shoot_windup_sec`, полёт кончика `web_shot_speed`. Попал: `attach` | Попал: `swing` для `SWING`, иначе `hang` |
| `swing` | `web` | `HARD`, подмотка до `plan.swing_length` со `swing_reel_speed`, затухание `swing_damping`, `lean` по нити с ограничением `swing_lean_max_rad` | См. ниже |
| `hang` | `web` | `SPRING`, фазы `ASCEND`, `REST`, `DESCEND`; `contour_top_extra_px = thread_grab_zone_px` | `PRESS` в контуре → `stretched`. `ASCEND` закончен и задумано плетение → `weave`. Касание пола в `DESCEND` → `land` |
| `stretched` | `web` | `carrying = true`, `pos` за курсором; натяжение считает `rope.stretch` | `MOVE` за пределом → `rope.snap()`, `carried`. `RELEASE`, `CANCEL` → `hang`. `RESYNC` или неверный якорь → `snap`, `carried` |
| `weave` | `web` | `weave_step` раз в `weave_step_sec`, поза меняется только в этих точках. `next_tick_sec` = остаток шага | Готово: верхний угол → `hang`, фаза `DESCEND`; нижний → `idle` |

`stretched` на каждый `MOVE` сначала сравнивает расстояние до якоря с `length + thread_max_stretch_px + thread_snap_extra_px`. До `thread_max_stretch_px` `pos` следует за курсором, дальше упирается в предел по лучу от якоря и ждёт разрыва. `grab_offset` и `throw_tracker` заполняются как в `root` и остаются действительными в `carried`.

Переход из `stretched` по `RELEASE` не сбрасывает скорость: она ноль, а растяжение уже в геометрии. `hang` при входе снова ведёт `advance`, поэтому пружина отрабатывает сама и герой качается вбок, если тянули вбок.

`hang`: `update` зовёт `advance(minf(delta, max_step_sec))`. В `REST`, если `is_settled`, вызывается `settle`, дальше считается пауза и `next_tick_sec` равен её остатку. До `is_settled` возвращается 0. Выход из `REST` — `target_length` до пола со скоростью `thread_descend_speed`. Планы `WEAVE_TOP` и `DESCENT` начинаются с `ASCEND`: `target_length` до `hang_top_gap_px` под верхним краем, `thread_ascend_speed`.

`swing` заканчивается в этом порядке:
1. `rope.touched_floor` → `last_impact_speed` из вертикальной скорости, `land`.
2. `rope.touched_wall` → `fall`, скорость остаётся.
3. Герой идёт вперёд и вверх, угол нити за вертикалью >= `plan.release_angle`, ожидаемая посадка `predicted_impact` < `hard_landing_speed * swing_safe_impact_ratio`, точка посадки внутри `bounds` → `fall`.
4. Время >= `swing_max_sec` → `target_length` к полу, ждём п. 1.

`fall` наследует `ctx.velocity`. `web.exit` превращает нить в `RELEASED`. Захват в `swing` и `shoot_web` идёт через `root` → `carried`, выход из группы рвёт нить. Новых веток в `root` нет.

`idle.update`: вместо `return WALK` — `return ctx.planner.decide(ctx)`. `walk`: если `ctx.plan != null` и `walk_to_x` задан, идёт к нему, цель и направление не случайны, на месте возвращает `SHOOT_WEB` или `WEAVE`. Обычная прогулка не меняется.

### Планировщик

`decide`, по порядку:
1. Плетение: `calm_sec >= weave_idle_sec`, есть свободный угол, ближняя стена не дальше `weave_walk_max_px`. Верхний или нижний угол выбирается случайно, затем `walk` к стене. Для верхнего: `shoot_web` вверх → `ASCEND` → `weave`.
2. Вылазка: `web_cooldown_sec <= 0`, `rng.randf() < web_trip_chance`. Поровну раскачка и спуск. После выбора `web_cooldown_sec = web_trip_min_interval_sec`.
3. Иначе `WALK`.

Цели:
- Высота `H = floor_y - anchor.y`. Меньше `web_min_height_px` → нет цели.
- Раскачка: сторона с большим простором, `dx` случайно из `swing_anchor_dx_min_px…max_px`, простор меньше `swing_min_room_px` → нет цели. С шансом `web_wall_anchor_chance` вместо верхнего края — стена на этой стороне, `y` в верхней трети.
- Длина выстрела больше `web_max_length_px` → нет цели.
- `swing_length = H - grip - swing_floor_clearance_px`, где `grip` — высота руки над ступнями.
- Спуск: якорь над героем со случайным смещением, `rest_length` из `hang_rest_ratio_min…max`.

Нижний край не кандидат. Стена не кандидат для спуска. Окна этапа 5 добавляются новым источником кандидатов в `swing_plan`.

### Рисование

`WebLine.apply(points: PackedVector2Array, tension: float)`: сравнивает с прошлым значением, `queue_redraw` только при отличии, при пустом списке `visible = false`. `Hero._after_step` передаёт `rope.draw_points(hand_pos())`. Рисует `draw_polyline`.

Вид оригинальный (NFR-6): две тонкие свитые жилки бледно-бирюзового цвета, плотнее при натяжении, в точке крепления маленькая янтарная бусина-зажим. Пятна-липучки и «чёрточки» на конце нет. В углах — неровная асимметричная природная сеть, цвета `@export` в виде и подбираются к палитре T-117. Красно-синих сочетаний и узора на костюме нет.

`CornerWebsView.apply(field)`: сравнивает `field.revision`, рисует `draw_data()` только при изменении, пустой — `visible = false`. Падающие нити меняют `revision` каждый кадр, только пока падают.

### Контур

Прямоугольник, `hero_contour_changed` и `Overlay` не меняются (D-012, п. 4). `visual_rect()` — габарит тела, повёрнутого на `lean` вокруг руки; при `lean == 0` равен `body_rect()`. Инвариант этапа 1 становится таким: `visual_rect` внутри `contour_rect`. Быстрая раскачка обновляет полигон почти каждый кадр, на macOS это дёшево (D-010, п. 5). Паутина в углах в полигон не входит.

### EventBus и мост

| Сигнал | Кто шлёт | Кто слушает |
|---|---|---|
| `cursor_watch_requested(active: bool)` | `Hero` | `Overlay` |
| `cursor_sampled(pos: Vector2, valid: bool)` | `Overlay` | `Hero` |
| `corner_web_woven(corner: int)` | `Hero` | На этапе 2 только тесты |
| `corner_web_swept(corner: int)` | `Hero` | На этапе 2 только тесты, дальше настроение |

`Overlay`:
- Таймер `cursor_poll_sec` (`overlay_config.tres`) работает только между `cursor_watch_requested(true)` и `(false)`.
- Проба: `mouse_get_position()`. `valid = false`, если она равна `Vector2i.ZERO` или лежит вне окна. Иначе `pos` — координаты окна в единицах viewport, как в `_track_drag`.
- `_on_hero_state_changed` использует `HeroState.is_fast`.

`Hero`:
- `cursor_sampled` → перевод в `lpx`. Недействительная проба сбрасывает прошлую точку. Иначе `ctx.corners.sweep(prev, pos, dt)`, `dt` из `Time`. Было изменение: `_advance_sleep()`, `_after_step(false)`. Иначе герой не просыпается.
- `cursor_watch_requested` шлётся при смене `ctx.corners.has_webs()`, только при смене значения.
- `_on_state_changed`: `was := HeroState.is_drag(from)`, `now := HeroState.is_drag(to)`; `drag_started` при `not was and now`, отложенный `drag_ended` при `was and not now`.
- `_after_step`: `WebLine.apply`, `CornerWebsView.apply`, `View.apply` с `lean`.
- `_on_world_bounds_changed` работает по старому пути: шаг `update(0)` даёт `web` проверить якорь.

Смахивание: нить теряется, если отрезок курсора прошёл ближе `sweep_hit_px` и скорость >= `sweep_min_speed`. Оставшихся нитей меньше доли `sweep_clear_ratio`: падает вся паутина, угол свободен, `swept`. Неоконченная паутина смахивается так же. Если плетение идёт в этот момент, `weave` ждёт следующего шага и заканчивается.

### Мониторы и смена области

- Якорь живёт в координатах окна. `set_bounds` не сдвигает его. `web.update` при неверном якоре даёт `fall`, `stretched` даёт `carried`.
- Вне drag окно не переезжает (D-010, п. 7), поэтому якорь меняется только при смене области. Пол поднялся или опустился: нить цела, `touched_floor` и зажим `advance` разберутся.
- Паутина в углах привязана к углу текущей области и переезжает вместе с окном: отдельного учёта мониторов на этапе 2 нет.

### Баланс

Все поля — в `HeroBalance` и `resources/hero_balance.tres`: SPEC §5 требует один ресурс. Значения стартовые, настраиваются руками. Цвета — `@export` видов.

| Поле | Значение | Поле | Значение |
|---|---|---|---|
| `rope_substep_sec` | 0.00833 | `thread_stiffness` | 60 |
| `rope_grip_height_ratio` | 0.9 | `thread_damping` | 2.2 |
| `rope_rest_speed` | 6 | `thread_sway_damping` | 0.8 |
| `rope_rest_stretch_px` | 1.5 | `thread_ascend_speed` | 480 |
| `web_max_length_px` | 1400 | `thread_descend_speed` | 150 |
| `web_min_height_px` | 260 | `thread_max_stretch_px` | 140 |
| `web_shot_speed` | 1800 | `thread_snap_extra_px` | 40 |
| `web_shoot_windup_sec` | 0.2 | `thread_grab_zone_px` | 36 |
| `web_release_fade_sec` | 0.25 | `hang_top_gap_px` | 24 |
| `web_sag_points` | 12 | `hang_rest_ratio_min` | 0.3 |
| `web_trip_chance` | 0.25 | `hang_rest_ratio_max` | 0.7 |
| `web_trip_min_interval_sec` | 180 | `hang_rest_min_sec` | 8 |
| `web_wall_anchor_chance` | 0.2 | `hang_rest_max_sec` | 25 |
| `swing_reel_speed` | 420 | `weave_idle_sec` | 300 |
| `swing_damping` | 0.15 | `weave_step_sec` | 0.8 |
| `swing_anchor_dx_min_px` | 180 | `weave_steps` | 6 |
| `swing_anchor_dx_max_px` | 520 | `weave_walk_max_px` | 300 |
| `swing_min_room_px` | 300 | `corner_web_radius_px` | 110 |
| `swing_floor_clearance_px` | 16 | `web_fall_sec` | 0.5 |
| `swing_release_angle_min_rad` | 0.25 | `sweep_min_speed` | 500 |
| `swing_release_angle_max_rad` | 0.7 | `sweep_hit_px` | 14 |
| `swing_safe_impact_ratio` | 0.8 | `sweep_clear_ratio` | 0.35 |
| `swing_max_sec` | 6 | `swing_lean_max_rad` | 0.6 |

`cursor_poll_sec` = 0.1 — в `OverlayConfig`: это частота опроса окна, а не поведение героя.

`validation_errors` дополнительно: все длины, скорости и `rope_substep_sec` > 0; `rope_substep_sec <= max_step_sec`; `sqrt(thread_stiffness) * rope_substep_sec < 0.5`; минимум <= максимум у пар; вероятности и доли в 0..1; `swing_safe_impact_ratio <= 1`; `weave_steps >= 1`; `web_sag_points >= 2`.

### Тесты (T-215)

Логика без сцены, `machine.update(1.0 / 30.0)`, фиксированный seed. `HeroFixture` выставляет `web_trip_chance = 0` и `weave_idle_sec = INF` в `grounded_machine` и `context`, чтобы тесты этапа 1 не менялись; тесты паутины включают их явно.

- `WebRope`, `HARD`: длина держится, без затухания энергия за 60 с не растёт, герой ни разу не ниже `bounds`.
- `WebRope`: одинаковое время одним шагом и нарезкой даёт совпадение с точностью до подшага.
- Подмотка отрывает героя от пола. Низ дуги выше пола на `swing_floor_clearance_px`.
- `SPRING`: сходится к равновесию, `is_settled` становится истинным, `settle` не прыгает, отпущенное растяжение возвращается.
- Большая `delta`: `update(3600)` в `REST` не двигает героя, пауза считается полностью.
- `next_tick_sec` > 0 только в `REST` и `weave`; `web.next_tick_sec` равен `INF`; `RELEASED` не даёт уснуть до конца исчезновения.
- Таблица переходов, захват из каждого листа, разрыв при пределе, `RESYNC` в `stretched`, `exit` группы освобождает нить, `shoot_web` → `swing` её не трогает.
- Границы: якорь вне области, пол выше и ниже, сужение по x.
- Раскачка не даёт жёсткой посадки: 1000 вылазок по разным seed и размерам области, ни одного `hard_landed`, герой всегда внутри `bounds`.
- `WebPlanner`: цель в границах и длине, в окне меньше `web_min_height_px` даёт `WALK`, обида запрещает вылазки, запрет повторяется по `web_trip_min_interval_sec`.
- Доля времени на вылазки за час симуляции: не больше 3%, вместе с ходьбой — не больше 12%.
- `CornerWebField`: шаги плетения, `sweep` быстрым и медленным курсором, отрезок поперёк угла с концами снаружи, полное падение, `set_bounds`, `free_corners`.
- Инвариант: `visual_rect` внутри `contour_rect` на всей симуляции.
- `HeroBalance.is_valid`: каждое новое правило.
- `Hero` в дереве: `drag_started` и `drag_ended` без повторов при `stretched` → `carried`, недействительная проба рвёт отрезок, `cursor_watch_requested` только при смене, спящий герой не просыпается от пустой пробы, `WebLine` не перерисовывается в `REST`.
- `Overlay`: таймер опроса только при запросе, чистая функция классификации пробы, `is_fast` для `swing`, `stretched`.

### Ручная проверка (T-216, основа чек-листа)

На `.app`, команды в fish.

- Выстрел: кончик летит к верхнему краю и к стене, нить под героем, вид не похож на чужих персонажей.
- Раскачка: дуга не задевает пол, отпускание выглядит живо, посадка мягкая, обиды нет.
- Спуск: подъём к верхнему краю, остановка, покачивание гаснет и полностью замирает, спуск до пола.
- Натяжение: потянуть вниз и вбок, пружина, разрыв за пределом, герой остаётся в руке.
- Клики сквозь: через нитку, рядом с героем в `hang`, в углах с паутиной, включая кнопки развёрнутых окон.
- Захват в раскачке и в выстреле, нить исчезает.
- Плетение: для быстрой проверки уменьшить `weave_idle_sec` в `.tres`, шаг за шагом в углу.
- Смахивание: быстрый взмах убирает, медленное движение нет, кнопка мыши не нужна.
- Смена области: размер Dock во время `hang`, отключение монитора во время `hang`.
- Покой: CPU при герое в `REST` и при паутине в углах, сценарий «жизнь» 10 минут.

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
