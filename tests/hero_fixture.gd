class_name HeroFixture
extends RefCounted
## Общие заготовки для тестов логики героя. Без сцен, без EventBus.

const BALANCE_PATH: String = "res://resources/hero_balance.tres"


static func balance() -> HeroBalance:
	return (load(BALANCE_PATH) as HeroBalance).duplicate() as HeroBalance


static func rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


static func context(seed_value: int = 1, bounds: Rect2 = Rect2(0.0, 0.0, 800.0, 600.0)) -> HeroContext:
	var ctx := HeroContext.new(balance(), rng(seed_value))
	ctx.set_bounds(bounds)
	ctx.place_at_center()
	return ctx


## Машина, уже стоящая на полу в idle.
static func grounded_machine(ctx: HeroContext) -> HeroStateMachine:
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
