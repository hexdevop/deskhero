extends GutTest
## T-114: переходы, суперсостояния, порядок enter/exit, запрет перехода не в лист.

const IDS: Array[StringName] = [&"root", &"grounded", &"airborne", &"idle", &"walk", &"land", &"fall", &"thrown", &"carried"]

var _ctx: HeroContext
var _m: HeroStateMachine


class Spy:
	extends HeroState
	var log: Array[String]

	func enter() -> void:
		log.append("enter:" + String(id))

	func exit() -> void:
		log.append("exit:" + String(id))


func before_each() -> void:
	_ctx = HeroFixture.context(7)
	_m = HeroFixture.grounded_machine(_ctx)


## Подменяет состояния шпионами с общим журналом; иерархия та же. Вызывать до start.
func _spy_machine() -> Dictionary:
	var ctx: HeroContext = HeroFixture.context(3)
	var m := HeroStateMachine.new(ctx)
	var log: Array[String] = []
	var spies: Dictionary = {}
	for sid: StringName in IDS:
		var spy := Spy.new()
		spy.id = sid
		spy.ctx = ctx
		spy.log = log
		spies[sid] = spy
		m._states[sid] = spy
	for sid: StringName in IDS:
		var orig := HeroStateMachine.new(ctx).get_state(sid)
		if orig.parent != null:
			(spies[sid] as HeroState).parent = spies[orig.parent.id]
	return {"m": m, "log": log}


func _drop_to_land(hard: bool) -> void:
	_m.transition(HeroState.FALL)
	_ctx.last_impact_speed = 1500.0 if hard else 100.0
	_m.transition(HeroState.LAND)


# --- Старт и структура

func test_start_enters_idle() -> void:
	assert_eq(_m.current_id(), HeroState.IDLE)


func test_current_id_before_start_is_none() -> void:
	var m := HeroStateMachine.new(_ctx)
	assert_eq(m.current_id(), HeroState.NONE)
	m.update(0.1)
	m.handle_input(HeroFixture.press_on_body(_ctx))
	assert_eq(m.current_id(), HeroState.NONE, "без start ничего не происходит")


func test_start_twice_ignored() -> void:
	_m.start(HeroState.FALL)
	assert_eq(_m.current_id(), HeroState.IDLE)


func test_start_in_group_refused() -> void:
	var m := HeroStateMachine.new(_ctx)
	m.start(HeroState.GROUNDED)
	assert_eq(m.current_id(), HeroState.NONE)


func test_hierarchy() -> void:
	var expect: Dictionary = {
		&"root": &"", &"grounded": &"root", &"airborne": &"root", &"carried": &"root",
		&"idle": &"grounded", &"walk": &"grounded", &"land": &"grounded",
		&"fall": &"airborne", &"thrown": &"airborne",
	}
	for sid: StringName in expect:
		var s: HeroState = _m.get_state(sid)
		assert_not_null(s, str(sid))
		var parent_id: StringName = s.parent.id if s.parent != null else &""
		assert_eq(parent_id, expect[sid], "родитель " + str(sid))


func test_get_state_unknown_is_null() -> void:
	assert_null(_m.get_state(&"nope"))


# --- Запрет перехода не в лист

func test_transition_to_group_refused() -> void:
	for gid: StringName in [&"root", &"grounded", &"airborne"]:
		_m.transition(gid)
		assert_eq(_m.current_id(), HeroState.IDLE, "переход в группу %s запрещён" % gid)


func test_transition_to_unknown_refused() -> void:
	_m.transition(&"nope")
	_m.transition(&"")
	assert_eq(_m.current_id(), HeroState.IDLE)


func test_refused_transition_emits_nothing() -> void:
	var seen: Array[int] = [0]
	_m.state_changed.connect(func(_f: StringName, _t: StringName) -> void: seen[0] += 1)
	_m.transition(&"grounded")
	_m.transition(&"nope")
	assert_eq(seen[0], 0)


func test_transition_to_same_leaf_does_not_restart() -> void:
	var idle := _m.get_state(HeroState.IDLE) as IdleState
	idle.remaining_sec = 5.0
	_m.transition(HeroState.IDLE)
	assert_eq(idle.remaining_sec, 5.0, "enter не вызван повторно")


# --- Сигнал

func test_state_changed_signal_args() -> void:
	var log: Array = []
	_m.state_changed.connect(func(f: StringName, t: StringName) -> void: log.append([f, t]))
	_m.transition(HeroState.WALK)
	_m.transition(HeroState.FALL)
	assert_eq(log, [[&"idle", &"walk"], [&"walk", &"fall"]])


func test_start_emits_from_none() -> void:
	var m := HeroStateMachine.new(_ctx)
	var log: Array = []
	m.state_changed.connect(func(f: StringName, t: StringName) -> void: log.append([f, t]))
	m.start(HeroState.FALL)
	assert_eq(log, [[HeroState.NONE, &"fall"]])


# --- Порядок enter/exit

func test_start_enter_order_root_first() -> void:
	var d: Dictionary = _spy_machine()
	(d["m"] as HeroStateMachine).start(HeroState.IDLE)
	assert_eq(d["log"], ["enter:root", "enter:grounded", "enter:idle"])


func test_sibling_transition_keeps_parent() -> void:
	var d: Dictionary = _spy_machine()
	var m: HeroStateMachine = d["m"]
	m.start(HeroState.IDLE)
	(d["log"] as Array).clear()
	m.transition(HeroState.WALK)
	assert_eq(d["log"], ["exit:idle", "enter:walk"], "общий предок grounded не трогается")


func test_cross_group_transition_order() -> void:
	var d: Dictionary = _spy_machine()
	var m: HeroStateMachine = d["m"]
	m.start(HeroState.IDLE)
	(d["log"] as Array).clear()
	m.transition(HeroState.FALL)
	assert_eq(d["log"], ["exit:idle", "exit:grounded", "enter:airborne", "enter:fall"], "root не трогается")


func test_transition_to_root_child_leaf() -> void:
	var d: Dictionary = _spy_machine()
	var m: HeroStateMachine = d["m"]
	m.start(HeroState.FALL)
	(d["log"] as Array).clear()
	m.transition(HeroState.CARRIED)
	assert_eq(d["log"], ["exit:fall", "exit:airborne", "enter:carried"])
	(d["log"] as Array).clear()
	m.transition(HeroState.LAND)
	assert_eq(d["log"], ["exit:carried", "enter:grounded", "enter:land"])


func test_airborne_siblings_keep_group() -> void:
	var d: Dictionary = _spy_machine()
	var m: HeroStateMachine = d["m"]
	m.start(HeroState.FALL)
	(d["log"] as Array).clear()
	m.transition(HeroState.THROWN)
	assert_eq(d["log"], ["exit:fall", "enter:thrown"])


# --- Переходы между листьями

func test_idle_to_walk_after_pause() -> void:
	var idle := _m.get_state(HeroState.IDLE) as IdleState
	assert_between(idle.remaining_sec, 15.0, 45.0)
	_m.update(idle.remaining_sec - 0.01)
	assert_eq(_m.current_id(), HeroState.IDLE)
	_m.update(0.02)
	assert_eq(_m.current_id(), HeroState.WALK)


func test_walk_to_idle_after_distance() -> void:
	_m.transition(HeroState.WALK)
	var walk := _m.get_state(HeroState.WALK) as WalkState
	assert_between(walk.remaining_px, 40.0, 200.0)
	HeroFixture.run(_m, 10.0)
	assert_eq(_m.current_id(), HeroState.IDLE, "200 px при 50 px/с кончаются за 4 с")


func test_walk_moves_in_facing_direction_and_advances_phase() -> void:
	_m.transition(HeroState.WALK)
	var x0: float = _ctx.pos.x
	var face: int = _ctx.facing
	_m.update(0.1)
	assert_almost_eq(_ctx.pos.x - x0, float(face) * 5.0, 0.001)
	assert_between(_ctx.walk_phase, 0.0, 1.0)
	assert_gt(_ctx.walk_phase, 0.0)


func test_walk_turns_at_wall() -> void:
	_ctx.pos.x = _ctx.bounds.end.x - 28.0 - 1.0
	_m.transition(HeroState.WALK)
	_ctx.facing = 1
	(_m.get_state(HeroState.WALK) as WalkState).remaining_px = 1000.0
	_m.update(0.1)
	assert_eq(_ctx.pos.x, _ctx.bounds.end.x - 28.0, "упёрся в стену")
	assert_eq(_ctx.facing, -1, "развернулся")


func test_walk_in_too_narrow_area_returns_idle() -> void:
	_ctx.set_bounds(Rect2(0, 0, 40, 600))
	_m.transition(HeroState.WALK)
	_m.update(0.05)
	assert_eq(_m.current_id(), HeroState.IDLE)


func test_idle_fall_land_idle_cycle() -> void:
	_m.transition(HeroState.FALL)
	_ctx.pos.y = 100.0
	var seen: Array[StringName] = []
	_m.state_changed.connect(func(_f: StringName, t: StringName) -> void: seen.append(t))
	HeroFixture.run(_m, 5.0)
	assert_eq(seen.slice(0, 2), [&"land", &"idle"])
	assert_eq(_ctx.pos.y, _ctx.floor_y())


func test_soft_landing_short_and_not_hard() -> void:
	_drop_to_land(false)
	var land := _m.get_state(HeroState.LAND) as LandState
	assert_false(land.hard)
	assert_eq(land.remaining_sec, _ctx.balance.land_soft_sec)


func test_hard_landing_long() -> void:
	_drop_to_land(true)
	var land := _m.get_state(HeroState.LAND) as LandState
	assert_true(land.hard)
	assert_eq(land.remaining_sec, _ctx.balance.land_hard_sec)


func test_hard_landing_threshold_inclusive() -> void:
	_m.transition(HeroState.FALL)
	_ctx.last_impact_speed = _ctx.balance.hard_landing_speed
	_m.transition(HeroState.LAND)
	assert_true((_m.get_state(HeroState.LAND) as LandState).hard, "ровно порог: жёсткая")
	_m.transition(HeroState.FALL)
	_ctx.last_impact_speed = _ctx.balance.hard_landing_speed - 0.01
	_m.transition(HeroState.LAND)
	assert_false((_m.get_state(HeroState.LAND) as LandState).hard)


func test_land_signals() -> void:
	var hard: Array[float] = []
	var soft: Array[int] = [0]
	_ctx.hard_landed.connect(func(s: float) -> void: hard.append(s))
	_ctx.soft_landed.connect(func() -> void: soft[0] += 1)
	_drop_to_land(false)
	assert_eq(soft[0], 1)
	assert_eq(hard.size(), 0)
	_drop_to_land(true)
	assert_eq(hard, [1500.0])
	assert_eq(soft[0], 1)


func test_land_to_idle_after_duration() -> void:
	_drop_to_land(false)
	_m.update(0.1)
	assert_eq(_m.current_id(), HeroState.LAND)
	_m.update(0.06)
	assert_eq(_m.current_id(), HeroState.IDLE)


func test_land_friction_stops_horizontal_motion() -> void:
	_m.transition(HeroState.FALL)
	_ctx.last_impact_speed = 100.0
	_ctx.velocity = Vector2(500.0, 0.0)
	_m.transition(HeroState.LAND)
	_m.update(0.05)
	assert_lt(_ctx.velocity.x, 500.0)
	assert_gt(_ctx.velocity.x, 0.0)


func test_airborne_enter_resets_impact_speed() -> void:
	_ctx.last_impact_speed = 900.0
	_m.transition(HeroState.FALL)
	assert_eq(_ctx.last_impact_speed, 0.0)


# --- Захват курсором (корень)

func test_press_on_body_grabs_from_every_leaf() -> void:
	for sid: StringName in [&"idle", &"walk", &"land", &"fall", &"thrown"]:
		var ctx: HeroContext = HeroFixture.context(5)
		var m: HeroStateMachine = HeroFixture.grounded_machine(ctx)
		if sid == &"land":
			ctx.last_impact_speed = 1.0
		m.transition(sid)
		m.handle_input(HeroFixture.press_on_body(ctx))
		assert_eq(m.current_id(), HeroState.CARRIED, "из %s" % sid)
		assert_true(ctx.carrying)


func test_press_outside_contour_ignored() -> void:
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, _ctx.pos + Vector2(500, -10), 0.0))
	assert_eq(_m.current_id(), HeroState.IDLE)


func test_press_in_padding_grabs() -> void:
	var p: Vector2 = _ctx.pos + Vector2(28.0 + 5.0, -10.0)
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 0.0))
	assert_eq(_m.current_id(), HeroState.CARRIED, "запас контура входит в зону захвата")


func test_press_just_outside_padding_ignored() -> void:
	var p: Vector2 = _ctx.pos + Vector2(28.0 + 6.5, -10.0)
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 0.0))
	assert_eq(_m.current_id(), HeroState.IDLE)


func test_non_press_inputs_do_not_grab() -> void:
	for k: HeroInput.Kind in [HeroInput.Kind.MOVE, HeroInput.Kind.RELEASE, HeroInput.Kind.CANCEL, HeroInput.Kind.RESYNC]:
		_m.handle_input(HeroInput.make(k, _ctx.pos + Vector2(0, -10), 0.0))
		assert_eq(_m.current_id(), HeroState.IDLE, "вид %d" % k)


func test_press_records_grab_offset() -> void:
	var p: Vector2 = _ctx.pos + Vector2(10.0, -20.0)
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 0.0))
	assert_eq(_ctx.grab_offset, _ctx.pos - p)


func test_second_press_while_carried_ignored() -> void:
	_m.handle_input(HeroFixture.press_on_body(_ctx, 0.0))
	var n: int = _ctx.throw_tracker.sample_count()
	_m.handle_input(HeroFixture.press_on_body(_ctx, 0.1))
	assert_eq(_m.current_id(), HeroState.CARRIED)
	assert_eq(_ctx.throw_tracker.sample_count(), n, "повторный PRESS не сбрасывает историю")


func test_carried_follows_cursor_with_offset() -> void:
	var p: Vector2 = _ctx.pos + Vector2(10.0, -20.0)
	var off: Vector2 = _ctx.pos - p
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 0.0))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, Vector2(300, 300), 0.01))
	assert_eq(_ctx.pos, Vector2(300, 300) + off)


func test_carried_position_clamped_to_bounds() -> void:
	_m.handle_input(HeroFixture.press_on_body(_ctx))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, Vector2(-5000, -5000), 0.01))
	assert_true(_ctx.bounds.encloses(_ctx.body_rect()))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, Vector2(9000, 9000), 0.02))
	assert_true(_ctx.bounds.encloses(_ctx.body_rect()))


func test_carried_ignores_update_gravity() -> void:
	_m.handle_input(HeroFixture.press_on_body(_ctx))
	var p: Vector2 = _ctx.pos
	HeroFixture.run(_m, 1.0)
	assert_eq(_ctx.pos, p)
	assert_eq(_m.current_id(), HeroState.CARRIED)


func test_carried_exit_clears_carrying() -> void:
	_m.handle_input(HeroFixture.press_on_body(_ctx))
	_m.handle_input(HeroInput.make(HeroInput.Kind.CANCEL, _ctx.pos, 0.1))
	assert_false(_ctx.carrying)


func test_release_slow_goes_fall() -> void:
	_m.handle_input(HeroFixture.press_on_body(_ctx, 0.0))
	_m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, _ctx.pos + Vector2(0, -10), 0.5))
	assert_eq(_m.current_id(), HeroState.FALL)
	assert_eq(_ctx.velocity, Vector2.ZERO)


func test_release_fast_goes_thrown_with_velocity() -> void:
	var p: Vector2 = _ctx.pos + Vector2(0, -10)
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 1.00))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, p + Vector2(20, 0), 1.05))
	_m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, p + Vector2(40, 0), 1.10))
	assert_eq(_m.current_id(), HeroState.THROWN)
	assert_almost_eq(_ctx.velocity.x, 400.0, 0.5)


func test_release_at_threshold_throws() -> void:
	var p: Vector2 = _ctx.pos + Vector2(0, -10)
	# dt = 0.0625 и 9.375 px точно представимы: ровно 150 px/с.
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 2.0))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, p + Vector2(9.375, 0), 2.0625))
	_m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, p + Vector2(9.375, 0), 2.0625))
	assert_eq(_m.current_id(), HeroState.THROWN, "150 px/с ровно: бросок")


func test_release_just_below_threshold_falls() -> void:
	var p: Vector2 = _ctx.pos + Vector2(0, -10)
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 2.0))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, p + Vector2(9.25, 0), 2.0625))
	_m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, p + Vector2(9.25, 0), 2.0625))
	assert_eq(_m.current_id(), HeroState.FALL)


func test_cancel_goes_fall_without_throw() -> void:
	var p: Vector2 = _ctx.pos + Vector2(0, -10)
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 1.0))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, p + Vector2(500, 0), 1.01))
	_m.handle_input(HeroInput.make(HeroInput.Kind.CANCEL, p, 1.02))
	assert_eq(_m.current_id(), HeroState.FALL)
	assert_eq(_ctx.velocity, Vector2.ZERO)


func test_resync_drops_history_so_no_false_throw() -> void:
	var p: Vector2 = _ctx.pos + Vector2(0, -10)
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 1.00))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, p + Vector2(5, 0), 1.04))
	# Окно переехало на другой монитор: курсор в новой системе координат скачет на 2000.
	_m.handle_input(HeroInput.make(HeroInput.Kind.RESYNC, p + Vector2(2000, 0), 1.06))
	_m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, p + Vector2(2000, 0), 1.08))
	assert_eq(_m.current_id(), HeroState.FALL, "скачок координат не должен стать броском")


func test_resync_keeps_carried_and_updates_position() -> void:
	_m.handle_input(HeroFixture.press_on_body(_ctx))
	_m.handle_input(HeroInput.make(HeroInput.Kind.RESYNC, Vector2(200, 200), 0.1))
	assert_eq(_m.current_id(), HeroState.CARRIED)
	assert_eq(_ctx.pos, _ctx.clamp_pos(Vector2(200, 200) + _ctx.grab_offset))


func test_thrown_lands_and_returns_to_idle() -> void:
	var p: Vector2 = _ctx.pos + Vector2(0, -10)
	_m.handle_input(HeroInput.make(HeroInput.Kind.PRESS, p, 1.0))
	_m.handle_input(HeroInput.make(HeroInput.Kind.MOVE, p + Vector2(0, -200), 1.05))
	_m.handle_input(HeroInput.make(HeroInput.Kind.RELEASE, p + Vector2(60, -200), 1.10))
	assert_eq(_m.current_id(), HeroState.THROWN)
	HeroFixture.run(_m, 6.0)
	assert_eq(_m.current_id(), HeroState.IDLE)
	assert_eq(_ctx.pos.y, _ctx.floor_y())


func test_thrown_air_drag_slows_horizontal() -> void:
	_m.transition(HeroState.THROWN)
	_ctx.pos.y = 100.0
	_ctx.velocity = Vector2(1000.0, 0.0)
	_m.update(0.1)
	assert_almost_eq(_ctx.velocity.x, 1000.0 * (1.0 - 0.4 * 0.1), 0.01)


func test_fall_has_no_air_drag() -> void:
	_m.transition(HeroState.FALL)
	_ctx.pos.y = 100.0
	_ctx.velocity = Vector2(1000.0, 0.0)
	_m.update(0.1)
	assert_eq(_ctx.velocity.x, 1000.0)


# --- Группа grounded следит за полом

func test_floor_lowered_makes_hero_fall() -> void:
	_ctx.set_bounds(Rect2(0, 0, 800, 900))
	_m.update(0.01)
	assert_eq(_m.current_id(), HeroState.FALL)


func test_floor_raised_snaps_hero_up() -> void:
	_ctx.bounds = Rect2(0, 0, 800, 500)
	_m.update(0.01)
	assert_eq(_m.current_id(), HeroState.IDLE)
	assert_eq(_ctx.pos.y, 500.0)


func test_floor_epsilon_tolerance() -> void:
	_ctx.pos.y = _ctx.floor_y() - HeroContext.FLOOR_EPSILON * 0.5
	_m.update(0.001)
	assert_eq(_m.current_id(), HeroState.IDLE)


func test_leaf_update_has_priority_over_parent() -> void:
	# land возвращает IDLE раньше, чем grounded успеет проверить пол.
	_drop_to_land(false)
	_ctx.set_bounds(Rect2(0, 0, 800, 900))
	_m.update(0.2)
	assert_eq(_m.current_id(), HeroState.IDLE, "лист решает первым")
	_m.update(0.01)
	assert_eq(_m.current_id(), HeroState.FALL, "на следующем тике группа замечает пол")


func test_input_bubbles_to_root_from_deep_leaf() -> void:
	# У листьев нет своего handle_input для PRESS: решает root.
	_m.transition(HeroState.WALK)
	_m.handle_input(HeroFixture.press_on_body(_ctx))
	assert_eq(_m.current_id(), HeroState.CARRIED)
