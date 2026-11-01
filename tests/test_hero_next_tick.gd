extends GutTest
## T-114: next_tick_sec: сон цикла и пробуждение.

var _ctx: HeroContext
var _m: HeroStateMachine


func before_each() -> void:
	_ctx = HeroFixture.context(5)
	_m = HeroFixture.grounded_machine(_ctx)


func test_idle_sleeps_until_pause_end() -> void:
	var idle := _m.get_state(HeroState.IDLE) as IdleState
	assert_gt(_m.next_tick_sec(), 0.0, "в покое можно спать")
	assert_eq(_m.next_tick_sec(), idle.remaining_sec)
	assert_between(_m.next_tick_sec(), 15.0, 45.0)


func test_idle_next_tick_shrinks_with_time() -> void:
	var before: float = _m.next_tick_sec()
	_m.update(2.0)
	assert_almost_eq(_m.next_tick_sec(), before - 2.0, 0.0001)


func test_waking_exactly_at_next_tick_leaves_idle() -> void:
	_m.update(_m.next_tick_sec())
	assert_eq(_m.current_id(), HeroState.WALK, "проснулся ровно в срок и пошёл")


func test_waking_slightly_before_stays_idle() -> void:
	_m.update(_m.next_tick_sec() - 0.001)
	assert_eq(_m.current_id(), HeroState.IDLE)
	assert_between(_m.next_tick_sec(), 0.0, 0.0011)
	assert_gt(_m.next_tick_sec(), 0.0)


func test_next_tick_never_negative() -> void:
	(_m.get_state(HeroState.IDLE) as IdleState).remaining_sec = -3.0
	assert_eq(_m.next_tick_sec(), 0.0)


func test_active_states_demand_every_frame() -> void:
	_m.transition(HeroState.WALK)
	assert_eq(_m.next_tick_sec(), 0.0)
	_m.transition(HeroState.FALL)
	assert_eq(_m.next_tick_sec(), 0.0)
	_m.transition(HeroState.THROWN)
	assert_eq(_m.next_tick_sec(), 0.0)
	_m.transition(HeroState.CARRIED)
	assert_eq(_m.next_tick_sec(), 0.0)
	_ctx.last_impact_speed = 0.0
	_m.transition(HeroState.LAND)
	assert_eq(_m.next_tick_sec(), 0.0)


func test_groups_alone_are_infinite() -> void:
	assert_eq(_m.get_state(HeroState.ROOT).next_tick_sec(), INF)
	assert_eq(_m.get_state(HeroState.GROUNDED).next_tick_sec(), INF)


func test_idle_with_happy_wakes_for_emotion_end() -> void:
	_ctx.emotions.show_for(HeroEmotions.Emotion.HAPPY, 1.5)
	assert_eq(_m.next_tick_sec(), 1.5, "эмоция кончается раньше паузы")


func test_idle_sulking_sleeps_until_sulk_end() -> void:
	_ctx.emotions.offend()
	(_m.get_state(HeroState.IDLE) as IdleState).remaining_sec = 1.0
	assert_eq(_m.next_tick_sec(), _ctx.balance.sulk_sec, "пауза кончилась бы раньше, но обида не даёт гулять")


func test_idle_sulking_wake_goes_to_walk_only_after_sulk() -> void:
	_ctx.emotions.offend()
	(_m.get_state(HeroState.IDLE) as IdleState).remaining_sec = 1.0
	_m.update(_m.next_tick_sec() - 0.01)
	assert_eq(_m.current_id(), HeroState.IDLE)
	_m.update(0.01)
	assert_eq(_m.current_id(), HeroState.WALK)


func test_sleep_loop_reaches_walk_in_few_wakes() -> void:
	# Имитируем Hero: спим next_tick_sec и тикаем ровно на него.
	var wakes: int = 0
	var slept: float = 0.0
	while _m.current_id() == HeroState.IDLE and wakes < 20:
		var dt: float = _m.next_tick_sec()
		assert_gt(dt, 0.0)
		slept += dt
		_m.update(dt)
		wakes += 1
	assert_eq(_m.current_id(), HeroState.WALK)
	assert_lte(wakes, 2, "никакой busy-loop в покое")
	assert_between(slept, 15.0, 45.0)


func test_sleep_infinite_when_only_sulk_forever_not_possible() -> void:
	# INF для idle допустим только пока есть обида, а обида конечна: цикл не засыпает навсегда.
	_ctx.emotions.offend()
	assert_ne(_m.next_tick_sec(), INF)


func test_scared_infinite_does_not_block_sleep_calc() -> void:
	_ctx.emotions.show_for(HeroEmotions.Emotion.SCARED, INF)
	assert_eq(_m.next_tick_sec(), (_m.get_state(HeroState.IDLE) as IdleState).remaining_sec)


func test_before_start_next_tick_infinite() -> void:
	var m := HeroStateMachine.new(HeroFixture.context())
	assert_eq(m.next_tick_sec(), INF)
