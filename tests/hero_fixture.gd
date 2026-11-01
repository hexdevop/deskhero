class_name HeroFixture
extends RefCounted
## Общие заготовки для тестов логики героя. Без сцен, без EventBus.

const BALANCE_PATH: String = "res://resources/hero_balance.tres"


static func balance() -> HeroBalance:
	return (load(BALANCE_PATH) as HeroBalance).duplicate() as HeroBalance


## Баланс без вылазок: тесты этапа 1 не должны зависеть от seed. Тесты паутины включают вылазки явно.
static func calm_balance() -> HeroBalance:
	var b: HeroBalance = balance()
	b.web_trip_chance = 0.0
	return b


static func rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


static func context(seed_value: int = 1, bounds: Rect2 = Rect2(0.0, 0.0, 800.0, 600.0)) -> HeroContext:
	var ctx := HeroContext.new(calm_balance(), rng(seed_value))
	ctx.set_bounds(bounds)
	ctx.place_at_center()
	return ctx


## Машина, уже стоящая на полу в idle.
static func grounded_machine(ctx: HeroContext) -> HeroStateMachine:
	ctx.balance.web_trip_chance = 0.0
	ctx.pos = Vector2(ctx.bounds.get_center().x, ctx.floor_y())
	var m := HeroStateMachine.new(ctx)
	m.start(HeroState.IDLE)
	return m


## Прогоняет update шагами step до total секунд.
static func run(m: HeroStateMachine, total: float, step: float = 1.0 / 30.0) -> void:
	var t: float = 0.0
	while t < total:
		m.update(step)
		t += step


static func press_on_body(ctx: HeroContext, now: float = 0.0) -> HeroInput:
	return HeroInput.make(HeroInput.Kind.PRESS, ctx.pos + Vector2(0.0, -10.0), now)


## --- Паутина (T-215)

const WEB_BOUNDS: Rect2 = Rect2(0.0, 0.0, 1200.0, 700.0)


## Контекст без вылазок, герой стоит на полу по центру области.
static func web_context(seed_value: int = 1, bounds: Rect2 = WEB_BOUNDS) -> HeroContext:
	var ctx: HeroContext = context(seed_value, bounds)
	ctx.pos = Vector2(bounds.get_center().x, ctx.floor_y())
	return ctx


## Нить уже связана: рука в hand_at, якорь в anchor, пол ниже. Без машины.
static func attach_rope(ctx: HeroContext, anchor: Vector2, hand_at: Vector2, mode: WebRope.Mode) -> void:
	ctx.rope.anchor = anchor
	ctx.pos = hand_at - ctx.hand_offset()
	ctx.velocity = Vector2.ZERO
	ctx.rope.attach(ctx, mode)


## Первый план раскачки или спуска, найденный перебором seed (стартовая позиция героя та же).
static func find_plan(swing: bool, bounds: Rect2 = WEB_BOUNDS, x: float = NAN) -> Array:
	for sd: int in range(1, 400):
		var ctx: HeroContext = web_context(sd, bounds)
		if not is_nan(x):
			ctx.pos.x = x
		var plan: WebPlan = ctx.planner.swing_plan(ctx) if swing else ctx.planner.descent_plan(ctx)
		if plan != null:
			return [ctx, plan]
	return []


## Крутит машину шагами step, пока pred не вернёт true или не истечёт total. Возвращает прошедшее время или -1.
static func run_until(m: HeroStateMachine, pred: Callable, total: float, step: float = 1.0 / 30.0) -> float:
	var t: float = 0.0
	while t < total:
		if pred.call():
			return t
		m.update(step)
		t += step
	return t if pred.call() else -1.0


## Запуск вылазки: план в контексте, переход в shoot_web.
static func launch(m: HeroStateMachine, ctx: HeroContext, plan: WebPlan) -> void:
	ctx.plan = plan
	m.transition(HeroState.SHOOT_WEB)


## Висит в REST и замер (спуск по плану спуска).
static func hang_at_rest(bounds: Rect2 = WEB_BOUNDS) -> Array:
	var found: Array = find_plan(false, bounds)
	var ctx: HeroContext = found[0]
	var plan: WebPlan = found[1]
	var m: HeroStateMachine = grounded_machine(ctx)
	launch(m, ctx, plan)
	run_until(m, func() -> bool: return plan.stage == WebPlan.Stage.REST and plan.settled, 60.0)
	return [ctx, plan, m]
