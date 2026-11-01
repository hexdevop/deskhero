extends GutTest
## T-215: Hero (мост) в сцене с паутиной: drag_started/ended без повторов при stretched -> carried,
## cursor_watch_requested только при смене, cursor_sampled (недействительная проба рвёт отрезок, пустая не будит),
## woven/swept в EventBus, WebLine и CornerWebsView не перерисовываются без изменений.
## События строятся в тесте и подаются прямым вызовом _input / через EventBus, ОС не трогаем.

const DT: float = 0.016
const TL: int = CornerWebField.Corner.TOP_LEFT
const BR: int = CornerWebField.Corner.BOTTOM_RIGHT

var _hero: Hero
var _draws: int = 0


func _spawn(units: float = 1.0, tweak: Callable = Callable()) -> Hero:
	var h: Hero = (load("res://scenes/hero/hero.tscn") as PackedScene).instantiate() as Hero
	h.rng_seed = 11
	h.balance = HeroFixture.calm_balance()
	if tweak.is_valid():
		tweak.call(h.balance)
	add_child_autofree(h)
	h.units_per_px = units
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 800 * units, 900 * units))
	return h


func _settle(h: Hero) -> void:
	var guard: int = 0
	while not h.is_sleeping() and guard < 2000:
		h._process(DT)
		guard += 1
	assert_true(h.is_sleeping(), "герой должен уснуть")


func _mouse(button: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = at
	return ev


func _motion(at: Vector2) -> InputEventMouseMotion:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = at
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	return ev


## Герой висит: спуск по плану, крутим кадры вручную, пока не замрёт в REST (тогда спит).
func _hang_asleep(h: Hero) -> WebPlan:
	_settle(h)
	var ctx: HeroContext = h.get_context()
	var plan: WebPlan = ctx.planner.descent_plan(ctx)
	assert_not_null(plan)
	ctx.plan = plan
	h.get_machine().transition(HeroState.SHOOT_WEB)
	var guard: int = 0
	while guard < 4000 and not (h.is_sleeping() and plan.stage == WebPlan.Stage.REST):
		h._process(DT)
		guard += 1
	assert_true(h.is_sleeping() and plan.stage == WebPlan.Stage.REST, "замер в REST")
	return plan


func _above_head(h: Hero) -> Vector2:
	var ctx: HeroContext = h.get_context()
	return (ctx.pos + Vector2(0.0, -ctx.balance.body_size_px.y - 20.0)) * h.units_per_px


func _count(_n: Variant = null) -> void:
	_draws += 1


func _frames(n: int = 3) -> void:
	for i: int in n:
		await get_tree().process_frame


## Курсор с интервалом dt_sec между пробами: подвинуть метку прошлой пробы назад.
func _sample_pair(h: Hero, a: Vector2, b: Vector2, dt_sec: float = 0.1) -> void:
	EventBus.cursor_sampled.emit(a, true)
	h._cursor_prev_usec -= int(dt_sec * 1000000.0)
	EventBus.cursor_sampled.emit(b, true)


# --- drag_started / drag_ended

func test_stretched_to_carried_gives_one_drag_started_and_one_drag_ended() -> void:
	_hero = _spawn()
	_hang_asleep(_hero)
	watch_signals(EventBus)
	var start: Vector2 = _above_head(_hero)
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, true, start))
	assert_eq(_hero.get_machine().current_id(), HeroState.STRETCHED)
	assert_signal_emit_count(EventBus, "hero_drag_started", 1)
	assert_signal_not_emitted(EventBus, "hero_drag_ended")
	var i: int = 0
	while _hero.get_machine().current_id() == HeroState.STRETCHED and i < 40:
		i += 1
		_hero._input(_motion(start + Vector2(0.0, 30.0 * float(i))))
	assert_eq(_hero.get_machine().current_id(), HeroState.CARRIED, "нить порвалась")
	assert_signal_emit_count(EventBus, "hero_drag_started", 1, "stretched -> carried не повторяет drag_started")
	assert_signal_not_emitted(EventBus, "hero_drag_ended", "и не завершает его")
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, false, start + Vector2(0.0, 30.0 * float(i))))
	assert_signal_emit_count(EventBus, "hero_drag_ended", 1)
	assert_signal_emit_count(EventBus, "hero_drag_started", 1)


func test_stretched_release_back_to_hang_ends_drag_once() -> void:
	_hero = _spawn()
	_hang_asleep(_hero)
	watch_signals(EventBus)
	var start: Vector2 = _above_head(_hero)
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, true, start))
	_hero._input(_motion(start + Vector2(0.0, 20.0)))
	assert_eq(_hero.get_machine().current_id(), HeroState.STRETCHED)
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, false, start + Vector2(0.0, 20.0)))
	assert_eq(_hero.get_machine().current_id(), HeroState.HANG)
	assert_signal_emit_count(EventBus, "hero_drag_started", 1)
	assert_signal_emit_count(EventBus, "hero_drag_ended", 1)
	assert_false(_hero.get_context().carrying)


func test_drag_ended_comes_after_contour_publication() -> void:
	_hero = _spawn()
	_hang_asleep(_hero)
	var order: Array[String] = []
	var on_contour: Callable = func(_r: Rect2) -> void: order.append("contour")
	var on_end: Callable = func() -> void: order.append("end")
	EventBus.hero_contour_changed.connect(on_contour)
	EventBus.hero_drag_ended.connect(on_end)
	var start: Vector2 = _above_head(_hero)
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, true, start))
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, false, start))
	EventBus.hero_contour_changed.disconnect(on_contour)
	EventBus.hero_drag_ended.disconnect(on_end)
	assert_eq(order.back(), "end", "drag_ended — последнее действие кадра")


func test_grab_in_swing_gives_drag_started_once() -> void:
	_hero = _spawn()
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	var plan: WebPlan = ctx.planner.swing_plan(ctx)
	if plan == null:
		pending("seed не дал раскачку в этой области")
		return
	ctx.plan = plan
	_hero.get_machine().transition(HeroState.SHOOT_WEB)
	var guard: int = 0
	while _hero.get_machine().current_id() != HeroState.SWING and guard < 400:
		_hero._process(DT)
		guard += 1
	assert_eq(_hero.get_machine().current_id(), HeroState.SWING)
	watch_signals(EventBus)
	_hero._input(_mouse(MOUSE_BUTTON_LEFT, true, (ctx.pos + Vector2(0.0, -10.0)) * _hero.units_per_px))
	assert_eq(_hero.get_machine().current_id(), HeroState.CARRIED, "в раскачке нить рвётся сразу")
	assert_signal_emit_count(EventBus, "hero_drag_started", 1)


func test_is_drag_covers_only_carried_and_stretched() -> void:
	for id: StringName in [HeroState.CARRIED, HeroState.STRETCHED]:
		assert_true(HeroState.is_drag(id), str(id))
	for id: StringName in [HeroState.IDLE, HeroState.WALK, HeroState.LAND, HeroState.FALL, HeroState.THROWN,
			HeroState.SHOOT_WEB, HeroState.SWING, HeroState.HANG, HeroState.WEAVE, HeroState.WEB, HeroState.ROOT, HeroState.NONE]:
		assert_false(HeroState.is_drag(id), str(id))


# --- cursor_watch_requested

func test_watch_requested_only_on_change() -> void:
	_hero = _spawn()
	_settle(_hero)
	watch_signals(EventBus)
	var ctx: HeroContext = _hero.get_context()
	_hero._after_step(false)
	_hero._after_step(false)
	assert_signal_not_emitted(EventBus, "cursor_watch_requested", "паутины нет: запроса нет")
	ctx.corners.begin_weave(TL)
	ctx.corners.weave_step(TL)
	_hero._after_step(false)
	_hero._after_step(false)
	_hero._on_wake_timeout()
	assert_signal_emit_count(EventBus, "cursor_watch_requested", 1)
	assert_signal_emitted_with_parameters(EventBus, "cursor_watch_requested", [true])


func test_watch_off_when_last_web_is_swept() -> void:
	_hero = _spawn(1.0, func(b: HeroBalance) -> void: b.sweep_clear_ratio = 1.0)
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	ctx.corners.begin_weave(TL)
	while not ctx.corners.weave_step(TL):
		pass
	_hero._after_step(false)
	watch_signals(EventBus)
	var origin: Vector2 = ctx.corners.corner_origin(TL)
	_sample_pair(_hero, origin + Vector2(90.0, -20.0), origin + Vector2(-20.0, 90.0))
	assert_signal_emitted(EventBus, "corner_web_swept")
	# смахнутое падает 0.5 с, потом паутины нет
	var guard: int = 0
	while not _hero.is_sleeping() and guard < 400:
		_hero._process(DT)
		guard += 1
	assert_signal_emit_count(EventBus, "cursor_watch_requested", 1)
	assert_signal_emitted_with_parameters(EventBus, "cursor_watch_requested", [false])


func test_watch_requested_not_by_unstarted_hero_samples() -> void:
	var h: Hero = (load("res://scenes/hero/hero.tscn") as PackedScene).instantiate() as Hero
	add_child_autofree(h)
	watch_signals(EventBus)
	EventBus.cursor_sampled.emit(Vector2(5, 5), true)
	EventBus.cursor_sampled.emit(Vector2(900, 900), true)
	assert_signal_not_emitted(EventBus, "cursor_watch_requested")
	assert_eq(h.get_machine().current_id(), HeroState.NONE)


# --- cursor_sampled

func test_fast_sample_pair_sweeps_corner_and_wakes_hero() -> void:
	_hero = _spawn()
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	ctx.corners.begin_weave(BR)
	while not ctx.corners.weave_step(BR):
		pass
	_hero._after_step(false)
	_settle(_hero)
	assert_true(_hero.is_sleeping())
	watch_signals(EventBus)
	var before: int = ctx.corners.visible_count(BR)
	var origin: Vector2 = ctx.corners.corner_origin(BR)
	_sample_pair(_hero, origin + Vector2(-90.0, 20.0), origin + Vector2(20.0, -90.0))
	assert_lt(ctx.corners.visible_count(BR), before, "нити смахнуты")
	assert_false(_hero.is_sleeping(), "падающие нити просыпают героя")
	assert_true(_hero.is_processing())
	_settle(_hero)
	assert_eq(ctx.corners.wake_sec(), INF, "упали, снова спит")


func test_slow_sample_pair_does_not_sweep() -> void:
	_hero = _spawn()
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	ctx.corners.begin_weave(BR)
	while not ctx.corners.weave_step(BR):
		pass
	_hero._after_step(false)
	_settle(_hero)
	var before: int = ctx.corners.visible_count(BR)
	var origin: Vector2 = ctx.corners.corner_origin(BR)
	_sample_pair(_hero, origin + Vector2(-90.0, 20.0), origin + Vector2(20.0, -90.0), 5.0)
	assert_eq(ctx.corners.visible_count(BR), before, "медленное движение не смахивает")
	assert_true(_hero.is_sleeping())


func test_invalid_sample_breaks_segment() -> void:
	_hero = _spawn()
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	ctx.corners.begin_weave(BR)
	while not ctx.corners.weave_step(BR):
		pass
	_hero._after_step(false)
	_settle(_hero)
	var before: int = ctx.corners.visible_count(BR)
	var origin: Vector2 = ctx.corners.corner_origin(BR)
	EventBus.cursor_sampled.emit(origin + Vector2(-90.0, 20.0), true)
	EventBus.cursor_sampled.emit(Vector2.ZERO, false)
	_hero._cursor_prev_usec -= 100000
	EventBus.cursor_sampled.emit(origin + Vector2(20.0, -90.0), true)
	assert_eq(ctx.corners.visible_count(BR), before, "недействительная проба между точками рвёт отрезок")
	assert_true(_hero._cursor_has_prev, "после действительной пробы отрезок начался заново")
	# контроль: без недействительной пробы тот же взмах смахивает
	_hero._cursor_has_prev = false
	_sample_pair(_hero, origin + Vector2(-90.0, 20.0), origin + Vector2(20.0, -90.0))
	assert_lt(ctx.corners.visible_count(BR), before)


func test_invalid_sample_alone_keeps_state_and_sleep() -> void:
	_hero = _spawn()
	_settle(_hero)
	watch_signals(EventBus)
	EventBus.cursor_sampled.emit(Vector2.ZERO, false)
	EventBus.cursor_sampled.emit(Vector2(400, 300), false)
	assert_true(_hero.is_sleeping())
	assert_signal_not_emitted(EventBus, "hero_activity_changed")
	assert_false(_hero._cursor_has_prev)


func test_empty_valid_probe_does_not_wake_sleeping_hero() -> void:
	_hero = _spawn()
	_settle(_hero)
	assert_true(_hero.is_sleeping())
	watch_signals(EventBus)
	var timer_left: float = (_hero.get_node("WakeTimer") as Timer).time_left
	for i: int in 20:
		EventBus.cursor_sampled.emit(Vector2(100 + 20 * i, 100 + 10 * i), true)
		_hero._cursor_prev_usec -= 100000
	assert_true(_hero.is_sleeping(), "паутины нет: проба героя не будит")
	assert_false(_hero.is_processing())
	assert_signal_not_emitted(EventBus, "hero_activity_changed")
	assert_signal_not_emitted(EventBus, "hero_contour_changed")
	assert_almost_eq((_hero.get_node("WakeTimer") as Timer).time_left, timer_left, 0.5, "таймер сна не переведён")


func test_probe_far_from_webs_does_not_wake_hero_with_webs() -> void:
	_hero = _spawn()
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	ctx.corners.begin_weave(BR)
	while not ctx.corners.weave_step(BR):
		pass
	_hero._after_step(false)
	_settle(_hero)
	_sample_pair(_hero, Vector2(100, 100), Vector2(300, 150))
	assert_true(_hero.is_sleeping(), "быстрый взмах мимо углов героя не будит")


func test_samples_are_scaled_by_units_per_px() -> void:
	_hero = _spawn(2.0)
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	ctx.corners.begin_weave(BR)
	while not ctx.corners.weave_step(BR):
		pass
	_hero._after_step(false)
	_settle(_hero)
	var before: int = ctx.corners.visible_count(BR)
	var origin: Vector2 = ctx.corners.corner_origin(BR) * 2.0  # единицы viewport
	_sample_pair(_hero, origin + Vector2(-180.0, 40.0), origin + Vector2(40.0, -180.0))
	assert_lt(ctx.corners.visible_count(BR), before, "пробы в единицах viewport переведены в lpx")


func test_woven_and_swept_go_to_event_bus() -> void:
	_hero = _spawn(1.0, func(b: HeroBalance) -> void: b.sweep_clear_ratio = 1.0)
	_settle(_hero)
	var ctx: HeroContext = _hero.get_context()
	watch_signals(EventBus)
	ctx.corners.begin_weave(TL)
	while not ctx.corners.weave_step(TL):
		pass
	assert_signal_emitted_with_parameters(EventBus, "corner_web_woven", [TL])
	assert_signal_emit_count(EventBus, "corner_web_woven", 1)
	_hero._after_step(false)
	var origin: Vector2 = ctx.corners.corner_origin(TL)
	_sample_pair(_hero, origin + Vector2(90.0, -20.0), origin + Vector2(-20.0, 90.0))
	assert_signal_emitted_with_parameters(EventBus, "corner_web_swept", [TL])
	assert_signal_emit_count(EventBus, "corner_web_swept", 1)


# --- перерисовки

func test_web_line_is_not_redrawn_in_rest() -> void:
	_hero = _spawn()
	_hang_asleep(_hero)
	var line: WebLine = _hero.get_node("WebLine")
	assert_true(line.is_drawn(), "нить в REST видна")
	await _frames()
	_draws = 0
	line.draw.connect(_count)
	for i: int in 10:
		_hero._on_wake_timeout()  # досчитывает сон и вызывает _after_step
		_hero._after_step(false)
	await _frames(4)
	assert_eq(_draws, 0, "в REST нить не перерисовывается")
	line.draw.disconnect(_count)


func test_web_line_apply_same_data_does_not_redraw_and_changes_do() -> void:
	var line := WebLine.new()
	add_child_autofree(line)
	var pts: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(50, 200)])
	line.apply(pts, 0.3)
	await _frames()
	_draws = 0
	line.draw.connect(_count)
	line.apply(pts.duplicate(), 0.3)
	line.apply(pts.duplicate(), 0.3 + 0.0000001)
	await _frames()
	assert_eq(_draws, 0, "те же данные: без перерисовки")
	line.apply(PackedVector2Array([Vector2(0, 0), Vector2(51, 200)]), 0.3)
	await _frames()
	assert_eq(_draws, 1, "точки сдвинулись")
	line.apply(PackedVector2Array([Vector2(0, 0), Vector2(51, 200)]), 0.9)
	await _frames()
	assert_eq(_draws, 2, "изменилось натяжение")
	line.draw.disconnect(_count)


func test_web_line_empty_list_hides_and_stays_hidden_without_redraw() -> void:
	var line := WebLine.new()
	add_child_autofree(line)
	line.apply(PackedVector2Array([Vector2(0, 0), Vector2(0, 100)]), 0.2)
	assert_true(line.visible)
	assert_true(line.is_drawn())
	line.apply(PackedVector2Array(), 0.0)
	assert_false(line.visible)
	assert_false(line.is_drawn())
	await _frames()
	_draws = 0
	line.draw.connect(_count)
	line.apply(PackedVector2Array(), 0.0)
	line.apply(PackedVector2Array([Vector2(1, 1)]), 0.0)
	await _frames()
	assert_eq(_draws, 0)
	assert_false(line.visible)
	line.apply(PackedVector2Array([Vector2(0, 0), Vector2(0, 100)]), 0.2)
	assert_true(line.visible, "новая нить показывает узел")
	line.draw.disconnect(_count)


func test_web_line_sample_and_twist_statics() -> void:
	var two: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(0, 100)])
	var s: PackedVector2Array = WebLine.sample(two, 5.0)
	assert_eq(s[0], Vector2(0, 0))
	assert_eq(s[s.size() - 1], Vector2(0, 100))
	assert_eq(s.size(), 21, "100 lpx шагом 5: 20 отрезков")
	for p: Vector2 in s:
		assert_almost_eq(p.x, 0.0, 0.0001, "две точки: прямая")
	assert_eq(WebLine.sample(PackedVector2Array([Vector2(3, 4)]), 5.0), PackedVector2Array([Vector2(3, 4)]))
	assert_eq(WebLine.sample(PackedVector2Array(), 5.0).size(), 0)
	var curve: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(40, 100), Vector2(0, 200)])
	var sc: PackedVector2Array = WebLine.sample(curve, 5.0)
	assert_eq(sc[0], curve[0])
	assert_eq(sc[sc.size() - 1], curve[2])
	var through: bool = false
	for p: Vector2 in sc:
		through = through or p.distance_to(curve[1]) < 0.001
	assert_true(through, "сплайн проходит через заданную точку")
	var long: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(0, 100000)])
	assert_lte(WebLine.sample(long, 5.0).size(), WebLine.MAX_SAMPLES + 2, "потолок числа выборок")
	var tw_a: PackedVector2Array = WebLine.twist(s, 1.7, 26.0, 0.0)
	var tw_b: PackedVector2Array = WebLine.twist(s, 1.7, 26.0, PI)
	assert_eq(tw_a.size(), s.size())
	assert_eq(tw_a[0], s[0], "концы на оси")
	assert_eq(tw_a[s.size() - 1], s[s.size() - 1])
	var max_off: float = 0.0
	for i: int in s.size():
		max_off = maxf(max_off, absf(tw_a[i].x))
		assert_almost_eq(tw_a[i].x + tw_b[i].x, 0.0, 0.0001, "жилки в противофазе")
		assert_almost_eq(tw_a[i].y, s[i].y, 0.0001, "смещение только поперёк нити")
	assert_lte(max_off, 1.7 + 0.0001)
	assert_gt(max_off, 0.5, "свивка есть")
	assert_eq(WebLine.twist(PackedVector2Array([Vector2(1, 1)]), 1.0, 26.0, 0.0), PackedVector2Array([Vector2(1, 1)]))


func test_corner_webs_view_redraws_only_on_revision() -> void:
	var view: CornerWebsView = (load("res://scenes/web/corner_webs.tscn") as PackedScene).instantiate() as CornerWebsView
	add_child_autofree(view)
	var field := CornerWebField.new(HeroFixture.balance(), HeroFixture.rng(5))
	field.set_bounds(Rect2(0, 0, 800, 600))
	view.apply(field)
	assert_false(view.visible, "пустое поле: узел скрыт")
	assert_eq(view.line_count(), 0)
	field.begin_weave(BR)
	field.weave_step(BR)
	view.apply(field)
	assert_true(view.visible)
	assert_eq(view.line_count(), field.draw_data().size())
	await _frames()
	_draws = 0
	view.draw.connect(_count)
	for i: int in 5:
		view.apply(field)
	await _frames()
	assert_eq(_draws, 0, "revision тот же: без перерисовки")
	field.weave_step(BR)
	view.apply(field)
	await _frames()
	assert_eq(_draws, 1, "шаг плетения перерисовал один раз")
	assert_eq(view.line_count(), field.draw_data().size())
	field.set_bounds(Rect2(0, 0, 1000, 700))
	view.apply(field)
	await _frames()
	assert_eq(_draws, 2, "смена границ перерисовала")
	view.draw.disconnect(_count)


func test_corner_webs_view_hides_after_threads_fell() -> void:
	var view: CornerWebsView = (load("res://scenes/web/corner_webs.tscn") as PackedScene).instantiate() as CornerWebsView
	add_child_autofree(view)
	var b: HeroBalance = HeroFixture.balance()
	b.sweep_clear_ratio = 1.0
	var field := CornerWebField.new(b, HeroFixture.rng(5))
	field.set_bounds(Rect2(0, 0, 800, 600))
	field.begin_weave(TL)
	while not field.weave_step(TL):
		pass
	view.apply(field)
	assert_true(view.visible)
	field.sweep(Vector2(90, -20), Vector2(-20, 90), 0.05)
	view.apply(field)
	assert_true(view.visible, "нити падают, их ещё видно")
	field.tick(b.web_fall_sec + 0.1)
	view.apply(field)
	assert_false(view.visible)
	assert_eq(view.line_count(), 0)


func test_hero_scale_applies_to_line_and_corner_views() -> void:
	_hero = _spawn(2.0)
	_hero._apply_view_scale()  # units_per_px переопределён после _ready, как в остальных тестах моста
	assert_eq(_hero.get_node("WebLine").scale, Vector2(2, 2))
	assert_eq(_hero.get_node("CornerWebs").scale, Vector2(2, 2))
	assert_eq(_hero.get_node("View").scale, Vector2(2, 2))
