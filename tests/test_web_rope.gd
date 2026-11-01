extends GutTest
## T-215: WebRope без сцены: HARD, SPRING, подшаг, энергия, фазы нити.

const DT: float = 1.0 / 30.0
const ANCHOR: Vector2 = Vector2(600.0, 0.0)

var _ctx: HeroContext


func before_each() -> void:
	_ctx = HeroFixture.web_context()


func _energy(c: HeroContext) -> float:
	return 0.5 * c.velocity.length_squared() - c.balance.gravity * c.hand_pos().y


# --- HARD

func test_hard_length_holds_over_60s() -> void:
	_ctx.balance.swing_damping = 0.0
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	var length: float = _ctx.rope.length
	var worst: float = 0.0
	for i: int in 60 * 30:
		_ctx.rope.advance(_ctx, DT)
		worst = maxf(worst, _ctx.hand_pos().distance_to(ANCHOR) - length)
	assert_lt(worst, 0.01, "рука не уходит дальше длины нити")
	assert_eq(_ctx.rope.length, length, "длина не меняется без подмотки")


func test_hard_energy_does_not_grow_without_damping() -> void:
	_ctx.balance.swing_damping = 0.0
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	var e0: float = _energy(_ctx)
	var allowed: float = 0.01 * _ctx.balance.gravity * (_ctx.rope.length - 228.0)  # 1% потенциала размаха
	var growth: float = 0.0
	for i: int in 60 * 30:
		_ctx.rope.advance(_ctx, DT)
		growth = maxf(growth, _energy(_ctx) - e0)
	assert_lt(growth, allowed, "энергия не растёт: рост %.1f, допуск %.1f" % [growth, allowed])


func test_hard_hero_always_inside_bounds() -> void:
	# нить длиннее зазора до пола: дуга упирается в пол и стены
	for start: Vector2 in [Vector2(900.0, 100.0), Vector2(100.0, 300.0), Vector2(1100.0, 500.0)]:
		var c: HeroContext = HeroFixture.web_context()
		c.balance.swing_damping = 0.0
		HeroFixture.attach_rope(c, Vector2(300.0, 100.0), start, WebRope.Mode.HARD)
		for i: int in 20 * 30:
			c.rope.advance(c, DT)
			assert_true(c.bounds.grow(0.001).encloses(c.body_rect()), "тело внутри bounds, старт %s, pos %s" % [start, c.pos])
			if c.rope.touched_floor or c.rope.touched_wall:
				break


func test_hard_chunking_matches_to_one_substep() -> void:
	var results: Array[HeroContext] = []
	for pattern: Array in [[0.05], [0.01, 0.01, 0.01, 0.01, 0.01], [DT], [0.0123, 0.0377], [0.005, 0.045]]:
		var c: HeroContext = HeroFixture.web_context()
		c.balance.swing_damping = 0.0
		HeroFixture.attach_rope(c, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
		var total: float = 0.0
		while total < 5.0 - 0.0001:
			for d: float in pattern:
				c.rope.advance(c, d)
				total += d
		results.append(c)
	# разное число подшагов на конце не больше одного: допуск скорость * подшаг, с запасом на накопитель
	for i: int in range(1, results.size()):
		var tol: float = results[0].velocity.length() * results[0].balance.rope_substep_sec * 2.0 + 0.01
		assert_lt(results[0].pos.distance_to(results[i].pos), tol, "нарезка %d совпадает с нарезкой 0" % i)


func test_hard_same_time_one_step_equals_many() -> void:
	var a: HeroContext = HeroFixture.web_context()
	var b: HeroContext = HeroFixture.web_context()
	HeroFixture.attach_rope(a, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	HeroFixture.attach_rope(b, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	a.rope.advance(a, 0.05)
	for i: int in 5:
		b.rope.advance(b, 0.01)
	assert_lt(a.pos.distance_to(b.pos), 0.01)
	assert_lt(a.velocity.distance_to(b.velocity), 0.5)


func test_substep_accumulator_below_one_substep_does_nothing() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	var before: Vector2 = _ctx.pos
	_ctx.rope.advance(_ctx, _ctx.balance.rope_substep_sec * 0.5)
	assert_eq(_ctx.pos, before, "меньше подшага: пусто")
	_ctx.rope.advance(_ctx, _ctx.balance.rope_substep_sec * 0.6)
	assert_ne(_ctx.pos, before, "накопитель сложил два куска в один подшаг")


func test_negative_delta_ignored() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	var before: Vector2 = _ctx.pos
	_ctx.rope.advance(_ctx, -1.0)
	assert_eq(_ctx.pos, before)


func test_reel_lifts_hero_off_floor() -> void:
	_ctx.rope.anchor = Vector2(900.0, 0.0)
	_ctx.pos = Vector2(600.0, _ctx.floor_y())
	_ctx.rope.attach(_ctx, WebRope.Mode.HARD)
	_ctx.rope.target_length = 500.0
	_ctx.rope.reel_speed = _ctx.balance.swing_reel_speed
	var lifted_at: float = -1.0
	for i: int in 30:
		_ctx.rope.advance(_ctx, DT)
		if lifted_at < 0.0 and _ctx.floor_y() - _ctx.pos.y > 5.0:
			lifted_at = float(i + 1) * DT
	assert_gt(lifted_at, 0.0, "подмотка оторвала героя от пола")
	assert_lt(lifted_at, 0.8)
	assert_false(_ctx.rope.touched_floor, "отрыв не считается ударом")


func test_reel_never_overshoots_target() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	var start: float = _ctx.rope.length
	_ctx.rope.target_length = start - 100.0
	_ctx.rope.reel_speed = 420.0
	_ctx.rope.advance(_ctx, 0.1)
	assert_almost_eq(_ctx.rope.length, start - 42.0, 0.5, "420 lpx/с за 0.1 с")
	_ctx.rope.advance(_ctx, 5.0)
	assert_eq(_ctx.rope.length, start - 100.0, "ровно в цель, не дальше")


func test_reel_end_kills_radial_velocity() -> void:
	# подмотка закончилась: герой не должен уходить внутрь круга по инерции
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	_ctx.rope.target_length = _ctx.rope.length - 20.0
	_ctx.rope.reel_speed = 420.0
	for i: int in 60:
		_ctx.rope.advance(_ctx, DT)
	assert_almost_eq(_ctx.rope.length, _ctx.rope.target_length, 0.001)
	assert_lte(_ctx.hand_pos().distance_to(ANCHOR), _ctx.rope.length + 0.01)


func test_hard_floor_contact_reported_with_speed() -> void:
	# нить длиннее, чем до пола: маятник бьёт в пол на скорости
	HeroFixture.attach_rope(_ctx, Vector2(600.0, 300.0), Vector2(1000.0, 350.0), WebRope.Mode.HARD)
	_ctx.rope.target_length = _ctx.rope.length
	var hit: bool = false
	for i: int in 120:
		_ctx.rope.advance(_ctx, DT)
		if _ctx.rope.touched_floor:
			hit = true
			break
	assert_true(hit, "дуга достаёт до пола")
	assert_gt(_ctx.velocity.y, 30.0, "скорость удара сохранена для вызывающего")
	assert_almost_eq(_ctx.pos.y, _ctx.floor_y(), 0.001)


func test_hard_resting_on_floor_is_not_impact() -> void:
	# стоит на полу, нить слабо натянута: контакта удара нет
	_ctx.rope.anchor = Vector2(600.0, 0.0)
	_ctx.pos = Vector2(600.0, _ctx.floor_y())
	_ctx.rope.attach(_ctx, WebRope.Mode.HARD)
	for i: int in 30:
		_ctx.rope.advance(_ctx, DT)
		assert_false(_ctx.rope.touched_floor)
	assert_eq(_ctx.pos.y, _ctx.floor_y())


# --- SPRING

func _spring_hanging() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(600.0, 300.0), WebRope.Mode.SPRING)


func test_spring_converges_and_settles() -> void:
	_spring_hanging()
	assert_false(_ctx.rope.is_settled(_ctx), "на стартовой длине ещё не в равновесии (провисание)")
	var steps: int = 0
	while not _ctx.rope.is_settled(_ctx) and steps < 30 * 30:
		_ctx.rope.advance(_ctx, DT)
		steps += 1
	assert_true(_ctx.rope.is_settled(_ctx), "пружина сошлась за 30 с")
	assert_lt(float(steps) * DT, 20.0)


func test_spring_settle_does_not_jump() -> void:
	_spring_hanging()
	while not _ctx.rope.is_settled(_ctx):
		_ctx.rope.advance(_ctx, DT)
	var before: Vector2 = _ctx.pos
	_ctx.rope.settle(_ctx)
	assert_lt(before.distance_to(_ctx.pos), _ctx.balance.rope_rest_stretch_px, "settle меньше допуска покоя")
	assert_eq(_ctx.velocity, Vector2.ZERO)
	assert_true(_ctx.rope.is_settled(_ctx))
	assert_eq(_ctx.pos, _ctx.rope.rest_pos(_ctx))
	assert_almost_eq(_ctx.rope.stretch(_ctx), _ctx.balance.gravity / _ctx.balance.thread_stiffness, 0.001, "провисание g/k")


func test_spring_released_stretch_returns() -> void:
	_spring_hanging()
	while not _ctx.rope.is_settled(_ctx):
		_ctx.rope.advance(_ctx, DT)
	_ctx.rope.settle(_ctx)
	var rest: Vector2 = _ctx.pos
	_ctx.pos += Vector2(40.0, 100.0)  # потянули вниз и вбок, отпустили
	_ctx.velocity = Vector2.ZERO
	assert_false(_ctx.rope.is_settled(_ctx))
	var steps: int = 0
	while not _ctx.rope.is_settled(_ctx) and steps < 30 * 30:
		_ctx.rope.advance(_ctx, DT)
		steps += 1
	assert_true(_ctx.rope.is_settled(_ctx), "вернулась в равновесие")
	assert_lt(_ctx.pos.distance_to(rest), _ctx.balance.rope_rest_stretch_px + 0.001)


func test_spring_slack_has_no_force() -> void:
	# рука ближе длины: нить провисла, только гравитация
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(600.0, 300.0), WebRope.Mode.SPRING)
	_ctx.rope.length = 500.0
	_ctx.rope.target_length = 500.0
	var vy0: float = _ctx.velocity.y
	_ctx.rope.advance(_ctx, _ctx.balance.rope_substep_sec)
	assert_almost_eq(_ctx.velocity.y - vy0, _ctx.balance.gravity * _ctx.balance.rope_substep_sec * (1.0 - _ctx.balance.thread_sway_damping * _ctx.balance.rope_substep_sec), 0.001, "свободное падение с затуханием качания")


func test_spring_reel_speed_uses_thread_speed() -> void:
	_spring_hanging()
	assert_eq(_ctx.rope.reel_speed, _ctx.balance.thread_descend_speed)
	var start: float = _ctx.rope.length
	_ctx.rope.target_length = start + 75.0
	_ctx.rope.advance(_ctx, 0.5)
	assert_almost_eq(_ctx.rope.length, start + 75.0, 0.5, "150 lpx/с за 0.5 с")


func test_attach_sets_mode_speeds_and_length() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	assert_eq(_ctx.rope.phase, WebRope.Phase.ATTACHED)
	assert_almost_eq(_ctx.rope.length, Vector2(900.0, 228.0).distance_to(ANCHOR), 0.001)
	assert_eq(_ctx.rope.target_length, _ctx.rope.length)
	assert_eq(_ctx.rope.reel_speed, _ctx.balance.swing_reel_speed)
	assert_false(_ctx.rope.touched_floor or _ctx.rope.touched_wall)


# --- фазы, выстрел, исчезновение

func test_off_rope_is_inert() -> void:
	var before: Vector2 = _ctx.pos
	_ctx.rope.advance(_ctx, 1.0)
	assert_eq(_ctx.pos, before)
	assert_false(_ctx.rope.is_settled(_ctx))
	assert_eq(_ctx.rope.draw_points(_ctx.hand_pos()).size(), 0)
	assert_eq(_ctx.rope.wake_sec(), INF)
	assert_false(_ctx.rope.tip_arrived())


func test_shooting_tip_arrives_after_distance_over_speed() -> void:
	var target: Vector2 = Vector2(600.0, 0.0)
	var hand: Vector2 = Vector2(600.0, 600.0)
	_ctx.rope.shoot(target)
	assert_eq(_ctx.rope.phase, WebRope.Phase.SHOOTING)
	assert_eq(_ctx.rope.wake_sec(), 0.0, "кончик летит: нужны кадры")
	var t: float = 0.0
	while not _ctx.rope.tip_arrived() and t < 5.0:
		_ctx.rope.tick_visual(DT, hand)
		t += DT
	var expected: float = 600.0 / _ctx.balance.web_shot_speed
	assert_between(t, expected, expected + 2.0 * DT, "время полёта = путь / скорость")


func test_shooting_huge_delta_arrives_at_once() -> void:
	_ctx.rope.shoot(Vector2(600.0, 0.0))
	_ctx.rope.tick_visual(0.0, Vector2(600.0, 600.0))  # старт кончика
	assert_false(_ctx.rope.tip_arrived())
	_ctx.rope.tick_visual(3600.0, Vector2(600.0, 600.0))
	assert_true(_ctx.rope.tip_arrived())


func test_shooting_draw_points_tip_between_hand_and_anchor() -> void:
	_ctx.rope.shoot(Vector2(600.0, 0.0))
	var hand := Vector2(600.0, 600.0)
	assert_eq(_ctx.rope.draw_points(hand).size(), 0, "кончик ещё не стартовал")
	_ctx.rope.tick_visual(0.1, hand)
	var pts: PackedVector2Array = _ctx.rope.draw_points(hand)
	assert_eq(pts.size(), 2)
	assert_eq(pts[0], hand)
	assert_almost_eq(pts[1].y, 600.0 - _ctx.balance.web_shot_speed * 0.1, 0.01)


func test_release_fades_to_off() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	_ctx.rope.release()
	assert_eq(_ctx.rope.phase, WebRope.Phase.RELEASED)
	assert_eq(_ctx.rope.wake_sec(), 0.0, "тает: нужны кадры")
	var pts: PackedVector2Array = _ctx.rope.draw_points(_ctx.hand_pos())
	assert_eq(pts.size(), 2)
	assert_eq(pts[1], ANCHOR)
	_ctx.rope.tick_visual(_ctx.balance.web_release_fade_sec * 0.5, _ctx.hand_pos())
	assert_eq(_ctx.rope.phase, WebRope.Phase.RELEASED, "половина времени: ещё тает")
	_ctx.rope.tick_visual(_ctx.balance.web_release_fade_sec * 0.6, _ctx.hand_pos())
	assert_eq(_ctx.rope.phase, WebRope.Phase.OFF)
	assert_eq(_ctx.rope.wake_sec(), INF)


func test_release_huge_delta_finishes() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	_ctx.rope.snap()
	_ctx.rope.tick_visual(3600.0, _ctx.hand_pos())
	assert_eq(_ctx.rope.phase, WebRope.Phase.OFF)


func test_release_from_off_or_released_is_noop() -> void:
	_ctx.rope.release()
	assert_eq(_ctx.rope.phase, WebRope.Phase.OFF)
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	_ctx.rope.release()
	_ctx.rope.tick_visual(0.1, _ctx.hand_pos())
	var pts_before: PackedVector2Array = _ctx.rope.draw_points(_ctx.hand_pos())
	_ctx.rope.release()  # повторный release не перезапускает исчезновение
	assert_eq(_ctx.rope.draw_points(_ctx.hand_pos()), pts_before)


func test_release_of_shooting_rope_starts_from_tip() -> void:
	_ctx.rope.shoot(Vector2(600.0, 0.0))
	var hand := Vector2(600.0, 600.0)
	_ctx.rope.tick_visual(0.1, hand)
	var tip_y: float = _ctx.rope.draw_points(hand)[1].y
	_ctx.rope.release()
	assert_almost_eq(_ctx.rope.draw_points(hand)[0].y, tip_y, 0.01, "обрыв выстрела уходит от кончика")


func test_draw_points_taut_and_slack() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(600.0, 300.0), WebRope.Mode.SPRING)
	var hand: Vector2 = _ctx.hand_pos()
	assert_eq(_ctx.rope.draw_points(hand).size(), 2, "натянута: прямая")
	_ctx.rope.length = 400.0
	var pts: PackedVector2Array = _ctx.rope.draw_points(hand)
	assert_eq(pts.size(), _ctx.balance.web_sag_points, "провисла: ломаная")
	assert_eq(pts[0], hand)
	assert_almost_eq(pts[pts.size() - 1].distance_to(ANCHOR), 0.0, 0.001)


func test_anchor_valid_edges() -> void:
	var r: WebRope = _ctx.rope
	var b: Rect2 = _ctx.bounds
	r.anchor = Vector2(0.0, 0.0)
	assert_true(r.anchor_valid(b), "угол области: на краю")
	r.anchor = Vector2(b.end.x, b.end.y)
	assert_true(r.anchor_valid(b))
	r.anchor = Vector2(-0.4, 0.0)
	assert_true(r.anchor_valid(b), "допуск 0.5")
	r.anchor = Vector2(-0.6, 0.0)
	assert_false(r.anchor_valid(b))
	r.anchor = Vector2(600.0, -1.0)
	assert_false(r.anchor_valid(b))
	r.anchor = Vector2(b.end.x + 1.0, 100.0)
	assert_false(r.anchor_valid(b))
	r.anchor = Vector2(600.0, b.end.y + 1.0)
	assert_false(r.anchor_valid(b))


func test_angle_sign_and_taut() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	assert_gt(_ctx.rope.angle(_ctx), 0.0, "рука правее якоря: угол > 0")
	assert_true(_ctx.rope.is_taut(_ctx))
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(300.0, 228.0), WebRope.Mode.HARD)
	assert_lt(_ctx.rope.angle(_ctx), 0.0)
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(600.0, 300.0), WebRope.Mode.HARD)
	assert_almost_eq(_ctx.rope.angle(_ctx), 0.0, 0.0001)


func test_extremely_narrow_bounds_do_not_nan() -> void:
	var c: HeroContext = HeroFixture.web_context(1, Rect2(0.0, 0.0, 40.0, 700.0))  # уже тела
	HeroFixture.attach_rope(c, Vector2(20.0, 0.0), Vector2(20.0, 300.0), WebRope.Mode.HARD)
	for i: int in 30:
		c.rope.advance(c, DT)
	assert_false(is_nan(c.pos.x) or is_nan(c.pos.y))
	assert_eq(c.pos.x, 20.0, "по центру узкой области")


func test_advance_clamps_huge_delta_to_max_advance() -> void:
	var a: HeroContext = HeroFixture.web_context()
	var b: HeroContext = HeroFixture.web_context()
	HeroFixture.attach_rope(a, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	HeroFixture.attach_rope(b, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	var started: int = Time.get_ticks_msec()
	a.rope.advance(a, 3600.0)
	var spent: int = Time.get_ticks_msec() - started
	b.rope.advance(b, WebRope.MAX_ADVANCE_SEC)
	assert_lt(spent, 500, "3600 с не крутят 430000 подшагов (%d мс)" % spent)
	assert_eq(a.pos, b.pos, "огромная delta равна MAX_ADVANCE_SEC")
	assert_eq(a.velocity, b.velocity)


func test_advance_clamp_boundary() -> void:
	var a: HeroContext = HeroFixture.web_context()
	var b: HeroContext = HeroFixture.web_context()
	HeroFixture.attach_rope(a, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	HeroFixture.attach_rope(b, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	a.rope.advance(a, WebRope.MAX_ADVANCE_SEC + 0.5)
	b.rope.advance(b, WebRope.MAX_ADVANCE_SEC)
	assert_eq(a.pos, b.pos, "сверх предела отбрасывается")
	var c: HeroContext = HeroFixture.web_context()
	HeroFixture.attach_rope(c, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	var before: Vector2 = c.pos
	c.rope.advance(c, WebRope.MAX_ADVANCE_SEC * 0.5)
	assert_ne(c.pos, before, "меньше предела считается полностью")


func test_advance_nan_delta_does_not_poison_state() -> void:
	HeroFixture.attach_rope(_ctx, ANCHOR, Vector2(900.0, 228.0), WebRope.Mode.HARD)
	_ctx.rope.advance(_ctx, NAN)
	_ctx.rope.advance(_ctx, DT)
	assert_false(is_nan(_ctx.pos.x) or is_nan(_ctx.pos.y), "NaN в delta не отравляет позицию")
