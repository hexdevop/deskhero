extends GutTest
## T-114: с одинаковым seed, часами и входом траектория совпадает бит в бит.


## Один прогон: возвращает журнал (состояние, pos, velocity, эмоция) и переходы.
func _simulate(seed_value: int, input_seed: int) -> Array:
	var ctx: HeroContext = HeroFixture.context(seed_value, Rect2(0, 0, 640, 480))
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	var transitions: Array = []
	m.state_changed.connect(func(f: StringName, t: StringName) -> void: transitions.append("%s>%s" % [f, t]))
	var inp := HeroFixture.rng(input_seed)
	var trace: Array = []
	var now: float = 0.0
	for i in 6000:
		now += 1.0 / 30.0
		if i % 40 == 0:
			(m.get_state(HeroState.IDLE) as IdleState).remaining_sec = minf((m.get_state(HeroState.IDLE) as IdleState).remaining_sec, 0.5)
		var r: int = inp.randi() % 60
		if r == 0:
			m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, ctx.pos + Vector2(0, -20), now))
		elif r < 6:
			m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, Vector2(inp.randf_range(0, 640), inp.randf_range(0, 480)), now))
		elif r == 7:
			m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, Vector2(inp.randf_range(0, 640), inp.randf_range(0, 480)), now))
		m.update(1.0 / 30.0)
		trace.append([m.current_id(), ctx.pos, ctx.velocity, ctx.emotions.current(), ctx.walk_phase, ctx.facing])
	return [trace, transitions]


func test_same_seed_same_trace() -> void:
	var a: Array = _simulate(42, 7)
	var b: Array = _simulate(42, 7)
	assert_eq((a[1] as Array).size(), (b[1] as Array).size())
	assert_eq(a[1], b[1], "переходы совпадают")
	assert_true(a[0] == b[0], "траектория совпадает")


func test_simulation_actually_exercises_states() -> void:
	var a: Array = _simulate(42, 7)
	var seen: Dictionary = {}
	for t: String in a[1]:
		seen[t.get_slice(">", 1)] = true
	for sid: String in ["walk", "carried", "fall", "land", "idle"]:
		assert_true(seen.has(sid), "прогон дошёл до " + sid)


func test_different_seed_different_trace() -> void:
	var a: Array = _simulate(42, 7)
	var b: Array = _simulate(43, 7)
	assert_false(a[0] == b[0], "другой seed даёт другую прогулку")


func test_idle_pause_and_walk_distribution_from_seed() -> void:
	var first: Array[float] = []
	for s in 2:
		var ctx: HeroContext = HeroFixture.context(1234)
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
		first.append((m.get_state(HeroState.IDLE) as IdleState).remaining_sec)
	assert_eq(first[0], first[1])


func test_idle_pause_always_within_balance_range() -> void:
	for seed_value in 200:
		var ctx: HeroContext = HeroFixture.context(seed_value)
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
		var r: float = (m.get_state(HeroState.IDLE) as IdleState).remaining_sec
		assert_between(r, 15.0, 45.0)
		m.transition(HeroState.WALK)
		assert_between((m.get_state(HeroState.WALK) as WalkState).remaining_px, 40.0, 200.0)
		assert_true(ctx.facing == 1 or ctx.facing == -1)


func test_walk_both_directions_occur() -> void:
	var dirs: Dictionary = {}
	for seed_value in 50:
		var ctx: HeroContext = HeroFixture.context(seed_value)
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
		m.transition(HeroState.WALK)
		dirs[ctx.facing] = true
	assert_eq(dirs.size(), 2)


func test_step_size_independence_of_walk_distance() -> void:
	# Одна и та же прогулка при шаге 1/30 и 1/120 проходит почти один путь.
	var dist: Array[float] = []
	for step: float in [1.0 / 30.0, 1.0 / 120.0]:
		var ctx: HeroContext = HeroFixture.context(8)
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
		m.transition(HeroState.WALK)
		var x0: float = ctx.pos.x
		var t: float = 0.0
		while m.current_id() == HeroState.WALK and t < 20.0:
			m.update(step)
			t += step
		dist.append(absf(ctx.pos.x - x0))
	assert_almost_eq(dist[0], dist[1], 50.0 / 30.0 + 0.01, "разница не больше одного кадра ходьбы")
