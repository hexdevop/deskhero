extends GutTest
## T-114: ThrowTracker.

var _b: HeroBalance
var _t: ThrowTracker


func before_each() -> void:
	_b = HeroFixture.balance()
	_t = ThrowTracker.new(_b)


func test_empty_is_zero() -> void:
	assert_eq(_t.velocity(1.0), Vector2.ZERO)
	assert_eq(_t.sample_count(), 0)


func test_single_sample_is_zero() -> void:
	_t.add_sample(Vector2(10, 10), 1.0)
	assert_eq(_t.velocity(1.0), Vector2.ZERO)


func test_two_samples_velocity() -> void:
	_t.add_sample(Vector2(0, 0), 1.00)
	_t.add_sample(Vector2(10, -5), 1.05)
	var v: Vector2 = _t.velocity(1.05)
	assert_almost_eq(v.x, 200.0, 0.01)
	assert_almost_eq(v.y, -100.0, 0.01)


func test_same_timestamp_is_zero() -> void:
	_t.add_sample(Vector2(0, 0), 1.0)
	_t.add_sample(Vector2(500, 0), 1.0)
	assert_eq(_t.velocity(1.0), Vector2.ZERO, "dt = 0 не делит на ноль")


func test_uses_first_and_last_in_window() -> void:
	# Окно 0.1 с: проба в 0.80 вне окна на момент 1.0.
	_t.add_sample(Vector2(0, 0), 0.80)
	_t.add_sample(Vector2(100, 0), 0.92)
	_t.add_sample(Vector2(110, 0), 1.00)
	var v: Vector2 = _t.velocity(1.0)
	assert_almost_eq(v.x, 10.0 / 0.08, 0.01)


func test_samples_outside_window_give_zero() -> void:
	_t.add_sample(Vector2(0, 0), 1.0)
	_t.add_sample(Vector2(100, 0), 1.05)
	assert_eq(_t.velocity(2.0), Vector2.ZERO, "курсор давно стоял: бросок нулевой")


func test_cursor_stopped_before_release() -> void:
	_t.add_sample(Vector2(0, 0), 1.00)
	_t.add_sample(Vector2(300, 0), 1.02)
	_t.add_sample(Vector2(300, 0), 1.10)
	_t.add_sample(Vector2(300, 0), 1.15)
	assert_lt(_t.velocity(1.15).length(), _b.throw_min_speed, "остановка перед отпусканием не даёт бросок")


func test_speed_is_capped() -> void:
	_t.add_sample(Vector2(0, 0), 1.0)
	_t.add_sample(Vector2(100000, 0), 1.01)
	assert_almost_eq(_t.velocity(1.01).length(), _b.throw_max_speed, 0.01)


func test_cap_keeps_direction() -> void:
	_t.add_sample(Vector2(0, 0), 1.0)
	_t.add_sample(Vector2(-30000, 30000), 1.01)
	var v: Vector2 = _t.velocity(1.01)
	assert_lt(v.x, 0.0)
	assert_gt(v.y, 0.0)
	assert_almost_eq(absf(v.x), absf(v.y), 0.01)


func test_reset_clears() -> void:
	_t.add_sample(Vector2(0, 0), 1.0)
	_t.add_sample(Vector2(10, 0), 1.05)
	_t.reset()
	assert_eq(_t.sample_count(), 0)
	assert_eq(_t.velocity(1.05), Vector2.ZERO)


func test_old_samples_pruned() -> void:
	for i in 100:
		_t.add_sample(Vector2(i, 0), i * 0.01)
	# Хранится не больше двух окон (0.2 с = ~21 проба при шаге 0.01).
	assert_lt(_t.sample_count(), 25)
	assert_gt(_t.sample_count(), 2)


func test_velocity_after_pruning_is_correct() -> void:
	for i in 100:
		_t.add_sample(Vector2(i * 2.0, 0), i * 0.01)
	assert_almost_eq(_t.velocity(0.99).x, 200.0, 0.5)


func test_sample_exactly_at_window_edge_counts() -> void:
	_t.add_sample(Vector2(0, 0), 0.9)
	_t.add_sample(Vector2(20, 0), 1.0)
	assert_almost_eq(_t.velocity(1.0).x, 200.0, 0.5)


func test_future_sample_ignored() -> void:
	_t.add_sample(Vector2(0, 0), 1.0)
	_t.add_sample(Vector2(50, 0), 1.05)
	assert_eq(_t.velocity(1.01), Vector2.ZERO, "проба после now не учитывается")
