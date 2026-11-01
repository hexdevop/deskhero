extends GutTest
## T-215 (правки по ревью T-212..T-214): отмена плетения, кулдаун weave_retry_sec, calm_sec на выходе из carried
## и stretched, валидация, сброс пробы курсора при смене границ, cursor_poll_sec.

const DT: float = 1.0 / 30.0
const B: Rect2 = Rect2(0.0, 0.0, 1200.0, 700.0)
const TL: int = CornerWebField.Corner.TOP_LEFT
const BL: int = CornerWebField.Corner.BOTTOM_LEFT
const TR: int = CornerWebField.Corner.TOP_RIGHT

var _woven: Array[int] = []


func before_each() -> void:
	_woven.clear()


func _wall(ctx: HeroContext, left: bool) -> float:
	var half: float = ctx.balance.body_size_px.x * 0.5
	return ctx.bounds.position.x + half if left else ctx.bounds.end.x - half


func _plan(kind: WebPlan.Kind, corner: int, ctx: HeroContext, walk_to: float = NAN) -> WebPlan:
	var p := WebPlan.new()
	p.kind = kind
	p.corner = corner
	p.walk_to_x = walk_to
	if kind == WebPlan.Kind.WEAVE_TOP:
		p.anchor = Vector2(_wall(ctx, CornerWebField.is_left(corner)), ctx.bounds.position.y)
	return p


## Нижнее плетение у левой стены; steps — сколько шагов уже сделано.
func _bottom(steps: int) -> Array:
	var ctx: HeroContext = HeroFixture.web_context(1)
	ctx.corners.woven.connect(func(c: int) -> void: _woven.append(c))
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.pos.x = _wall(ctx, true)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx)
	m.transition(HeroState.WEAVE)
	for i: int in steps:
		m.update(ctx.balance.weave_step_sec + 0.001)
	return [ctx, m]


func _top() -> Array:
	var ctx: HeroContext = HeroFixture.web_context(1)
	ctx.corners.woven.connect(func(c: int) -> void: _woven.append(c))
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.pos.x = _wall(ctx, true)
	var plan: WebPlan = _plan(WebPlan.Kind.WEAVE_TOP, TL, ctx)
	HeroFixture.launch(m, ctx, plan)
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.WEAVE, 30.0)
	return [ctx, plan, m]


func _above_head(ctx: HeroContext, now: float = 0.0) -> HeroInput:
	return HeroInput.make(HeroInput.Kind.PRESS, ctx.pos + Vector2(0.0, -ctx.balance.body_size_px.y - 20.0), now)


func _enable_weave(ctx: HeroContext) -> void:
	ctx.balance.weave_idle_sec = 10.0
	ctx.calm_sec = 10.0


# --- CornerWebField.cancel_weave

func test_cancel_at_zero_steps_erases_pattern_and_frees_corner() -> void:
	var f := CornerWebField.new(HeroFixture.balance(), HeroFixture.rng(3))
	f.begin_weave(TL)
	f.cancel_weave(TL)
	assert_true(f.is_free(TL))
	assert_false(f.is_weaving(TL))
	assert_eq(f.visible_count(TL), 0)
	assert_eq(f.draw_data().size(), 0)
	assert_eq(f.free_corners().size(), 4)
	assert_true(f.begin_weave(TL), "угол можно плести заново")


func test_cancel_after_steps_keeps_webs_and_they_can_be_swept() -> void:
	var b: HeroBalance = HeroFixture.balance()
	var f := CornerWebField.new(b, HeroFixture.rng(3))
	f.set_bounds(Rect2(0, 0, 800, 600))
	f.begin_weave(TL)
	f.weave_step(TL)
	f.weave_step(TL)
	var shown: int = f.visible_count(TL)
	f.cancel_weave(TL)
	assert_false(f.is_weaving(TL), "плетение не идёт")
	assert_eq(f.visible_count(TL), shown, "показанное остаётся")
	assert_true(f.has_webs(), "курсор по ним опрашивается")
	assert_false(f.is_free(TL), "пока паутина висит, угол занят")
	assert_false(f.begin_weave(TL))
	assert_true(f.weave_step(TL), "шагов больше нет")
	var cleared: bool = false
	var k: float = 15.0
	while not cleared and k < 140.0:
		f.sweep(Vector2(k + 20.0, -20.0), Vector2(-20.0, k + 20.0), 0.01)
		cleared = f.is_free(TL)
		k += 10.0
	assert_true(cleared, "смахивание освобождает угол")


func test_cancel_is_noop_for_idle_woven_and_invalid_corners() -> void:
	var f := CornerWebField.new(HeroFixture.balance(), HeroFixture.rng(3))
	f.cancel_weave(TL)
	f.cancel_weave(-1)
	f.cancel_weave(99)
	assert_true(f.is_free(TL))
	f.begin_weave(TL)
	while not f.weave_step(TL):
		pass
	var n: int = f.visible_count(TL)
	f.cancel_weave(TL)
	assert_eq(f.visible_count(TL), n, "оплетённый угол не трогаем")
	assert_false(f.is_free(TL))


# --- отмена через состояния

func test_grab_at_step_zero_during_bottom_weave_frees_corner_for_planner() -> void:
	var r: Array = _bottom(0)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	assert_true(ctx.corners.is_weaving(BL))
	m.handle_input(HeroFixture.press_on_body(ctx))
	assert_eq(m.current_id(), HeroState.CARRIED)
	assert_true(ctx.corners.is_free(BL), "угол снова свободен")
	assert_true(ctx.corners.free_corners().has(BL))
	_enable_weave(ctx)
	ctx.weave_cooldown_sec = 0.0
	var found: bool = false
	for sd: int in 40:
		ctx.rng.seed = sd
		ctx.pos.x = _wall(ctx, true)
		var plan: WebPlan = ctx.planner.weave_plan(ctx)
		found = found or (plan != null and plan.corner == BL)
	assert_true(found, "weave_plan может выбрать этот угол")


func test_grab_after_steps_during_bottom_weave_leaves_sweepable_web() -> void:
	var r: Array = _bottom(2)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	var shown: int = ctx.corners.visible_count(BL)
	assert_gt(shown, 0)
	m.handle_input(HeroFixture.press_on_body(ctx))
	assert_eq(m.current_id(), HeroState.CARRIED)
	assert_false(ctx.corners.is_weaving(BL))
	assert_eq(ctx.corners.visible_count(BL), shown)
	assert_eq(_woven.size(), 0, "woven не шлётся")
	assert_true(ctx.corners.has_webs())


func test_rope_snap_in_top_weave_cancels_weaving() -> void:
	for steps_wait: float in [0.0, 2.0]:
		var r: Array = _top()
		var ctx: HeroContext = r[0]
		var m: HeroStateMachine = r[2]
		assert_eq(m.current_id(), HeroState.WEAVE)
		HeroFixture.run(m, steps_wait)
		var steps: int = ctx.corners.step_of(TL)
		ctx.update_contour(true)
		var start: Vector2 = ctx.pos + Vector2(0.0, -ctx.balance.body_size_px.y - 20.0)
		m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, start, 0.0))
		assert_eq(m.current_id(), HeroState.STRETCHED)
		assert_true(ctx.corners.is_weaving(TL), "stretched группу не покидает: плетение не отменено")
		for i: int in 40:
			if m.current_id() != HeroState.STRETCHED:
				break
			m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, start + Vector2(0.0, 30.0 * float(i + 1)), 0.01 * float(i + 1)))
		assert_eq(m.current_id(), HeroState.CARRIED, "нить порвалась")
		assert_false(ctx.corners.is_weaving(TL))
		assert_eq(ctx.corners.step_of(TL), steps)
		if steps == 0:
			assert_true(ctx.corners.is_free(TL), "без шагов угол свободен")
		else:
			assert_false(ctx.corners.is_free(TL))
			assert_true(ctx.corners.has_webs())
		assert_eq(ctx.weave_cooldown_sec, ctx.balance.weave_retry_sec)


func test_stretched_hang_weave_does_not_cancel() -> void:
	var r: Array = _top()
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[2]
	HeroFixture.run_until(m, func() -> bool: return ctx.corners.step_of(TL) >= 2, 10.0)
	ctx.update_contour(true)
	m.handle_input(_above_head(ctx))
	assert_eq(m.current_id(), HeroState.STRETCHED)
	m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, ctx.pos, 1.0))
	assert_eq(m.current_id(), HeroState.HANG)
	assert_true(ctx.corners.is_weaving(TL), "плетение живо")
	assert_eq(ctx.weave_cooldown_sec, 0.0, "кулдаун не включался")
	m.update(DT)
	assert_eq(m.current_id(), HeroState.WEAVE)
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.IDLE, 60.0)
	assert_eq(_woven, [TL] as Array[int])
	assert_eq(ctx.weave_cooldown_sec, 0.0, "успешное плетение кулдауна не даёт")


func test_successful_weave_sets_no_cooldown() -> void:
	var r: Array = _bottom(0)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	HeroFixture.run_until(m, func() -> bool: return m.current_id() == HeroState.IDLE, 20.0)
	assert_eq(_woven, [BL] as Array[int])
	assert_eq(ctx.weave_cooldown_sec, 0.0)


# --- weave_retry_sec / weave_cooldown_sec

func test_cooldown_set_on_bottom_interrupt_and_decays_with_time() -> void:
	var r: Array = _bottom(1)
	var ctx: HeroContext = r[0]
	var m: HeroStateMachine = r[1]
	m.handle_input(HeroFixture.press_on_body(ctx))
	var retry: float = ctx.balance.weave_retry_sec
	assert_eq(ctx.weave_cooldown_sec, retry)
	m.update(30.0)
	assert_almost_eq(ctx.weave_cooldown_sec, retry - 30.0, 0.01)
	m.update(retry)
	assert_eq(ctx.weave_cooldown_sec, 0.0, "не уходит в минус")


func test_decide_respects_cooldown() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	_enable_weave(ctx)
	ctx.weave_cooldown_sec = 50.0
	for i: int in 20:
		assert_eq(ctx.planner.decide(ctx), HeroState.WALK)
		assert_null(ctx.plan, "в кулдауне плетения нет")
	ctx.weave_cooldown_sec = 0.0
	ctx.planner.decide(ctx)
	assert_not_null(ctx.plan, "кулдаун кончился: плетение возможно")


func test_cooldown_does_not_block_trips() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	_enable_weave(ctx)
	ctx.weave_cooldown_sec = 50.0
	ctx.balance.web_trip_chance = 1.0
	ctx.planner.decide(ctx)
	assert_not_null(ctx.plan)
	assert_true(ctx.plan.kind == WebPlan.Kind.SWING or ctx.plan.kind == WebPlan.Kind.DESCENT, "вылазки живут независимо")


func test_walk_failures_set_cooldown() -> void:
	var cases: Dictionary = {}
	# таймаут
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, _wall(ctx, true))
	m.transition(HeroState.WALK)
	ctx.balance.walk_speed = 0.01
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 200.0)
	assert_gt(ctx.weave_cooldown_sec, 0.0, "таймаут прогулки")
	# захват
	ctx = HeroFixture.web_context(1)
	m = HeroFixture.grounded_machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, _wall(ctx, true))
	m.transition(HeroState.WALK)
	HeroFixture.run(m, 0.5)
	m.handle_input(HeroFixture.press_on_body(ctx))
	assert_eq(ctx.weave_cooldown_sec, ctx.balance.weave_retry_sec, "захват в пути")
	# падение
	ctx = HeroFixture.web_context(1)
	m = HeroFixture.grounded_machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, _wall(ctx, true))
	m.transition(HeroState.WALK)
	HeroFixture.run(m, 0.5)
	ctx.set_bounds(Rect2(0.0, 0.0, 1200.0, 900.0))
	m.update(DT)
	assert_eq(m.current_id(), HeroState.FALL)
	assert_gt(ctx.weave_cooldown_sec, 0.0, "падение в пути")
	# угол занят на месте
	ctx = HeroFixture.web_context(1)
	m = HeroFixture.grounded_machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, _wall(ctx, true))
	m.transition(HeroState.WALK)
	ctx.corners.begin_weave(BL)
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 30.0)
	assert_eq(m.current_id(), HeroState.IDLE)
	assert_eq(ctx.weave_cooldown_sec, ctx.balance.weave_retry_sec, "угол занят по приходе")
	assert_eq(cases.size(), 0)


func test_walk_success_and_ordinary_walk_set_no_cooldown() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.plan = _plan(WebPlan.Kind.WEAVE_BOTTOM, BL, ctx, _wall(ctx, true))
	m.transition(HeroState.WALK)
	HeroFixture.run_until(m, func() -> bool: return m.current_id() != HeroState.WALK, 30.0)
	assert_eq(m.current_id(), HeroState.WEAVE)
	assert_eq(ctx.weave_cooldown_sec, 0.0, "дошёл: кулдауна нет")
	var ctx2: HeroContext = HeroFixture.web_context(2)
	var m2: HeroStateMachine = HeroFixture.grounded_machine(ctx2)
	m2.transition(HeroState.WALK)
	m2.handle_input(HeroFixture.press_on_body(ctx2))
	assert_eq(ctx2.weave_cooldown_sec, 0.0, "обычная прогулка кулдауна не даёт")


func test_interrupted_walk_then_no_immediate_retry_in_full_life() -> void:
	var ctx: HeroContext = HeroFixture.web_context(4)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	_enable_weave(ctx)
	ctx.balance.idle_pause_min_sec = 2.0
	ctx.balance.idle_pause_max_sec = 3.0
	ctx.weave_cooldown_sec = 60.0
	HeroFixture.run(m, 50.0)
	assert_eq(ctx.corners.free_corners().size(), 4, "в кулдауне плетения нет")
	HeroFixture.run(m, 200.0)
	assert_lt(ctx.corners.free_corners().size(), 4, "после кулдауна герой снова плетёт")


# --- валидация

## BUG (см. report T-214): по handoff weave_retry_sec должен быть строго > 0, в коде он в non_negative.
func test_validation_weave_retry_must_be_positive() -> void:
	var b: HeroBalance = HeroFixture.balance()
	assert_true(b.is_valid())
	b.weave_retry_sec = 0.0
	assert_false(b.is_valid(), "weave_retry_sec = 0 недопустимо")
	b.weave_retry_sec = -1.0
	assert_false(b.is_valid(), "отрицательное недопустимо")
	b.weave_retry_sec = 0.5
	assert_true(b.is_valid())


func test_validation_sweep_clear_ratio_strictly_positive() -> void:
	var b: HeroBalance = HeroFixture.balance()
	assert_true(b.is_valid())
	b.sweep_clear_ratio = 0.0
	assert_false(b.is_valid(), "sweep_clear_ratio = 0 недопустимо")
	b.sweep_clear_ratio = 0.01
	assert_true(b.is_valid())
	b.sweep_clear_ratio = 1.0
	assert_true(b.is_valid())
	b.sweep_clear_ratio = 1.01
	assert_false(b.is_valid())


# --- calm_sec на выходе

func test_calm_sec_reset_on_carried_exit_and_stretched_exit() -> void:
	var ctx: HeroContext = HeroFixture.web_context(1)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	m.handle_input(HeroFixture.press_on_body(ctx))
	m.update(40.0)  # держали долго
	assert_gt(ctx.calm_sec, 30.0, "в руке время тикает")
	m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, ctx.pos, 5.0))
	assert_ne(m.current_id(), HeroState.CARRIED)
	assert_eq(ctx.calm_sec, 0.0, "покой считается с отпускания")
	var h: Array = HeroFixture.hang_at_rest(Rect2(0.0, 0.0, 1200.0, 1400.0))
	var hctx: HeroContext = h[0]
	var hm: HeroStateMachine = h[2]
	hctx.update_contour(true)
	hm.handle_input(_above_head(hctx))
	assert_eq(hm.current_id(), HeroState.STRETCHED)
	hm.update(40.0)
	assert_gt(hctx.calm_sec, 30.0)
	hm.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, hctx.pos, 5.0))
	assert_eq(hm.current_id(), HeroState.HANG)
	assert_eq(hctx.calm_sec, 0.0)


func test_calm_sec_reset_when_stretched_snaps_into_carried_then_released() -> void:
	var h: Array = HeroFixture.hang_at_rest(Rect2(0.0, 0.0, 1200.0, 1400.0))
	var ctx: HeroContext = h[0]
	var m: HeroStateMachine = h[2]
	ctx.update_contour(true)
	var start: Vector2 = ctx.pos + Vector2(0.0, -ctx.balance.body_size_px.y - 20.0)
	m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, start, 0.0))
	for i: int in 40:
		if m.current_id() != HeroState.STRETCHED:
			break
		m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, start + Vector2(0.0, 30.0 * float(i + 1)), 0.01 * float(i + 1)))
	assert_eq(m.current_id(), HeroState.CARRIED)
	m.update(25.0)
	m.handle_input(HeroInput.make(HeroInput.Kind.CANCEL, Vector2.ZERO, 9.0))
	assert_eq(ctx.calm_sec, 0.0)


# --- мост: смена границ и cursor_poll_sec

func _spawn() -> Hero:
	var h: Hero = (load("res://scenes/hero/hero.tscn") as PackedScene).instantiate() as Hero
	h.rng_seed = 11
	h.balance = HeroFixture.calm_balance()
	add_child_autofree(h)
	h.units_per_px = 1.0
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 800, 900))
	var guard: int = 0
	while not h.is_sleeping() and guard < 2000:
		h._process(0.016)
		guard += 1
	return h


func test_bounds_change_resets_cursor_probe() -> void:
	var h: Hero = _spawn()
	var ctx: HeroContext = h.get_context()
	ctx.corners.begin_weave(TR)
	while not ctx.corners.weave_step(TR):
		pass
	h._after_step(false)
	var origin: Vector2 = ctx.corners.corner_origin(TR)
	EventBus.cursor_sampled.emit(origin + Vector2(-90.0, 20.0), true)
	assert_true(h._cursor_has_prev)
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 800, 900))
	assert_false(h._cursor_has_prev, "проба в старой системе координат сброшена")
	var before: int = ctx.corners.visible_count(TR)
	h._cursor_prev_usec -= 100000
	EventBus.cursor_sampled.emit(origin + Vector2(20.0, -90.0), true)
	assert_eq(ctx.corners.visible_count(TR), before, "фиктивного отрезка через смену границ нет")
	assert_true(h._cursor_has_prev, "новая проба начала отрезок")


func test_bounds_change_with_scale_change_resets_probe_too() -> void:
	var h: Hero = _spawn()
	h._cursor_has_prev = true
	h.units_per_px = 2.0
	h._system_units = 2.0  # имитация прежнего масштаба; _refresh_units сравнит с DisplayUnits
	EventBus.world_bounds_changed.emit(Rect2(0, 0, 1600, 1800))
	assert_false(h._cursor_has_prev)


func test_cursor_poll_default_is_0_2() -> void:
	assert_almost_eq(OverlayConfig.new().cursor_poll_sec, 0.2, 0.0001)
	assert_almost_eq((load("res://resources/overlay_config.tres") as OverlayConfig).cursor_poll_sec, 0.2, 0.0001)
