extends GutTest
## T-114: HeroEmotions, обида, потолок sulk_max_sec и связь с состояниями.

const E = HeroEmotions.Emotion

var _b: HeroBalance
var _e: HeroEmotions


func before_each() -> void:
	_b = HeroFixture.balance()
	_e = HeroEmotions.new(_b)


func test_starts_neutral() -> void:
	assert_eq(_e.current(), E.NEUTRAL)
	assert_false(_e.is_sulking())
	assert_eq(_e.next_change_sec(), INF)
	assert_eq(_e.sulk_remaining_sec(), 0.0)


func test_temporary_expires_by_timer() -> void:
	_e.show_for(E.HAPPY, 2.0)
	assert_eq(_e.current(), E.HAPPY)
	assert_eq(_e.next_change_sec(), 2.0)
	_e.tick(1.5)
	assert_eq(_e.current(), E.HAPPY)
	_e.tick(0.5)
	assert_eq(_e.current(), E.NEUTRAL)
	assert_eq(_e.next_change_sec(), INF)


func test_infinite_temporary_stays_until_cleared() -> void:
	_e.show_for(E.SCARED, INF)
	_e.tick(100000.0)
	assert_eq(_e.current(), E.SCARED)
	assert_eq(_e.next_change_sec(), INF)
	_e.clear_temporary()
	assert_eq(_e.current(), E.NEUTRAL)


func test_show_neutral_or_offended_or_nonpositive_clears() -> void:
	_e.show_for(E.HAPPY, 5.0)
	_e.show_for(E.NEUTRAL, 5.0)
	assert_eq(_e.current(), E.NEUTRAL)
	_e.show_for(E.HAPPY, 5.0)
	_e.show_for(E.OFFENDED, 5.0)
	assert_eq(_e.current(), E.NEUTRAL, "OFFENDED нельзя показать напрямую, только offend()")
	assert_false(_e.is_sulking())
	_e.show_for(E.HAPPY, 5.0)
	_e.show_for(E.SCARED, 0.0)
	assert_eq(_e.current(), E.NEUTRAL)
	_e.show_for(E.HAPPY, 5.0)
	_e.show_for(E.SCARED, -1.0)
	assert_eq(_e.current(), E.NEUTRAL)


func test_new_temporary_replaces_old() -> void:
	_e.show_for(E.HAPPY, 5.0)
	_e.show_for(E.SCARED, 1.0)
	assert_eq(_e.current(), E.SCARED)
	assert_eq(_e.next_change_sec(), 1.0)


func test_offend_sets_sulk_and_visible() -> void:
	_e.offend()
	assert_true(_e.is_sulking())
	assert_eq(_e.current(), E.OFFENDED)
	assert_eq(_e.sulk_remaining_sec(), _b.sulk_sec)
	assert_eq(_e.next_change_sec(), _b.sulk_sec)


func test_sulk_ends_exactly_after_sulk_sec() -> void:
	_e.offend()
	_e.tick(_b.sulk_sec - 0.25)
	assert_true(_e.is_sulking())
	_e.tick(0.25)
	assert_false(_e.is_sulking())
	assert_eq(_e.current(), E.NEUTRAL)


func test_sulk_accumulates() -> void:
	_e.offend()
	_e.offend()
	assert_eq(_e.sulk_remaining_sec(), 2.0 * _b.sulk_sec)


func test_sulk_capped_by_max() -> void:
	for i in 10:
		_e.offend()
		assert_lte(_e.sulk_remaining_sec(), _b.sulk_max_sec, "после %d обид" % (i + 1))
	assert_eq(_e.sulk_remaining_sec(), _b.sulk_max_sec)


func test_sulk_cap_applies_with_partially_elapsed_sulk() -> void:
	_e.offend()
	_e.offend()
	_e.tick(20.0)
	assert_eq(_e.sulk_remaining_sec(), 4.0)
	_e.offend()
	_e.offend()
	_e.offend()
	assert_eq(_e.sulk_remaining_sec(), _b.sulk_max_sec)


func test_sulk_cap_with_invalid_balance_still_clamps() -> void:
	# validation_errors запрещает sulk_sec > sulk_max_sec, но offend не должен полагаться на это.
	_b.sulk_sec = 50.0
	_b.sulk_max_sec = 30.0
	_e.offend()
	assert_eq(_e.sulk_remaining_sec(), 30.0)


func test_sulk_hides_temporary_then_reveals_it() -> void:
	_e.show_for(E.SCARED, INF)
	_e.offend()
	assert_eq(_e.current(), E.OFFENDED, "обида важнее")
	_e.tick(_b.sulk_sec)
	assert_eq(_e.current(), E.SCARED, "бесконечная временная проявилась")


func test_temporary_set_during_sulk_hidden_until_end() -> void:
	_e.offend()
	_e.show_for(E.HAPPY, 100.0)
	assert_eq(_e.current(), E.OFFENDED)
	_e.tick(_b.sulk_sec)
	assert_eq(_e.current(), E.HAPPY)


func test_temporary_expiring_under_sulk_does_not_reappear() -> void:
	_e.offend()
	_e.show_for(E.HAPPY, 2.0)
	_e.tick(_b.sulk_sec)
	assert_eq(_e.current(), E.NEUTRAL)


func test_next_change_is_min_of_timers() -> void:
	_e.offend()
	_e.show_for(E.HAPPY, 2.0)
	assert_eq(_e.next_change_sec(), 2.0)
	_e.show_for(E.HAPPY, 100.0)
	assert_eq(_e.next_change_sec(), _b.sulk_sec)


func test_changed_signal_only_on_visible_change() -> void:
	var seen: Array[int] = []
	_e.changed.connect(func(x: HeroEmotions.Emotion) -> void: seen.append(x))
	_e.show_for(E.HAPPY, 1.0)
	_e.show_for(E.HAPPY, 1.0)
	_e.tick(0.5)
	assert_eq(seen, [E.HAPPY])
	_e.tick(0.5)
	_e.offend()
	_e.offend()
	_e.show_for(E.SCARED, INF)
	assert_eq(seen, [E.HAPPY, E.NEUTRAL, E.OFFENDED], "скрытая под обидой эмоция сигнала не даёт")
	_e.tick(1000.0)
	assert_eq(seen, [E.HAPPY, E.NEUTRAL, E.OFFENDED, E.SCARED])


func test_large_tick_never_negative() -> void:
	_e.offend()
	_e.show_for(E.HAPPY, 1.0)
	_e.tick(1.0e9)
	assert_eq(_e.sulk_remaining_sec(), 0.0)
	assert_eq(_e.next_change_sec(), INF)


func test_zero_delta_changes_nothing() -> void:
	_e.offend()
	_e.show_for(E.HAPPY, 1.0)
	_e.tick(0.0)
	assert_eq(_e.sulk_remaining_sec(), _b.sulk_sec)


# --- Связь с состояниями (контекст + машина)

func _hard_landing(m: HeroStateMachine, ctx: HeroContext) -> void:
	m.transition(HeroState.FALL)
	ctx.last_impact_speed = 1500.0
	m.transition(HeroState.LAND)


func test_hard_landing_offends() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	_hard_landing(m, ctx)
	assert_true(ctx.is_sulking())
	assert_eq(ctx.emotions.current(), E.OFFENDED)


func test_soft_landing_makes_happy_for_happy_sec() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	m.transition(HeroState.FALL)
	ctx.last_impact_speed = 10.0
	m.transition(HeroState.LAND)
	assert_eq(ctx.emotions.current(), E.HAPPY)
	assert_false(ctx.is_sulking())
	m.update(ctx.balance.happy_sec - 0.1)
	assert_eq(ctx.emotions.current(), E.HAPPY)
	m.update(0.2)
	assert_eq(ctx.emotions.current(), E.NEUTRAL)


func test_three_hard_landings_capped_at_sulk_max() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	for i in 5:
		_hard_landing(m, ctx)
	assert_eq(ctx.emotions.sulk_remaining_sec(), ctx.balance.sulk_max_sec)


func test_carried_and_thrown_show_scared() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	m.handle_input(HeroFixture.press_on_body(ctx))
	assert_eq(ctx.emotions.current(), E.SCARED)
	m.transition(HeroState.THROWN)
	assert_eq(ctx.emotions.current(), E.SCARED)


func test_scared_persists_through_fall_until_landing() -> void:
	var ctx: HeroContext = HeroFixture.context(1, Rect2(0, 0, 800, 2000))
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.pos.y = 500.0
	m.handle_input(HeroFixture.press_on_body(ctx, 0.0))
	m.handle_input(HeroInput.make(HeroInput.Kind.CANCEL, ctx.pos, 0.1))
	assert_eq(m.current_id(), HeroState.FALL)
	m.update(0.1)
	assert_eq(ctx.emotions.current(), E.SCARED, "в падении всё ещё испуган")
	HeroFixture.run(m, 5.0)
	assert_ne(ctx.emotions.current(), E.SCARED, "после посадки страх снят")


func test_hard_landing_clears_scared_then_shows_offended() -> void:
	var ctx: HeroContext = HeroFixture.context()
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	ctx.emotions.show_for(E.SCARED, INF)
	_hard_landing(m, ctx)
	ctx.emotions.tick(ctx.balance.sulk_sec)
	assert_eq(ctx.emotions.current(), E.NEUTRAL, "страх не должен вернуться после обиды")


func test_idle_does_not_walk_while_sulking() -> void:
	var ctx: HeroContext = HeroFixture.context(4)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	_hard_landing(m, ctx)
	m.update(ctx.balance.land_hard_sec + 0.1)
	assert_eq(m.current_id(), HeroState.IDLE)
	(m.get_state(HeroState.IDLE) as IdleState).remaining_sec = 0.0
	var walked: bool = false
	for i in int((ctx.balance.sulk_sec - 1.0) * 30.0):
		m.update(1.0 / 30.0)
		if m.current_id() == HeroState.WALK:
			walked = true
	assert_false(walked, "в обиде прогулок нет")
	assert_true(ctx.is_sulking())


func test_idle_walks_right_after_sulk_ends_if_pause_over() -> void:
	var ctx: HeroContext = HeroFixture.context(4)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	_hard_landing(m, ctx)
	m.update(ctx.balance.land_hard_sec + 0.1)
	(m.get_state(HeroState.IDLE) as IdleState).remaining_sec = 0.0
	m.update(ctx.emotions.sulk_remaining_sec() + 0.01)
	assert_eq(m.current_id(), HeroState.WALK)
	assert_eq(ctx.emotions.current(), E.NEUTRAL)


func test_sulk_ceiling_in_real_flow_gives_walk_by_max() -> void:
	# Сколько ни роняй, гулять он начнёт не позже sulk_max_sec после последней посадки.
	var ctx: HeroContext = HeroFixture.context(4)
	var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
	for i in 6:
		_hard_landing(m, ctx)
	m.update(ctx.balance.land_hard_sec + 0.01)
	(m.get_state(HeroState.IDLE) as IdleState).remaining_sec = 0.0
	var t: float = 0.0
	while m.current_id() != HeroState.WALK and t < 100.0:
		m.update(0.1)
		t += 0.1
	assert_lte(t, ctx.balance.sulk_max_sec, "обида не длиннее потолка")
