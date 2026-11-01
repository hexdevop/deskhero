extends GutTest
## T-114: HeroBalance.is_valid / validation_errors и resources/hero_balance.tres.


func test_tres_loads_as_hero_balance() -> void:
	var res: Resource = load(HeroFixture.BALANCE_PATH)
	assert_not_null(res)
	assert_true(res is HeroBalance)


func test_tres_is_valid() -> void:
	var b: HeroBalance = HeroFixture.balance()
	assert_eq(b.validation_errors(), PackedStringArray(), "в .tres нет нарушений")
	assert_true(b.is_valid())


func test_class_defaults_are_valid() -> void:
	assert_true(HeroBalance.new().is_valid())


func test_tres_values_match_documented_start_numbers() -> void:
	# D-010: пауза 15..45 с, прогулка 40..200 px, жёсткая посадка с 1000.
	var b: HeroBalance = HeroFixture.balance()
	assert_eq(b.idle_pause_min_sec, 15.0)
	assert_eq(b.idle_pause_max_sec, 45.0)
	assert_eq(b.walk_distance_min_px, 40.0)
	assert_eq(b.walk_distance_max_px, 200.0)
	assert_eq(b.hard_landing_speed, 1000.0)
	assert_eq(b.dev_quit_hold_sec, 0.5)


func test_padding_less_than_step_is_error() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.contour_padding_px = b.contour_step_px - 0.1
	assert_false(b.is_valid())
	assert_has(Array(b.validation_errors()), "contour_padding_px < contour_step_px")


func test_padding_equal_to_step_is_valid() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.contour_padding_px = b.contour_step_px
	assert_true(b.is_valid())


func test_idle_pause_min_greater_than_max() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.idle_pause_min_sec = 50.0
	assert_has(Array(b.validation_errors()), "idle_pause_min_sec > idle_pause_max_sec")


func test_idle_pause_min_equal_max_is_valid() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.idle_pause_min_sec = b.idle_pause_max_sec
	assert_true(b.is_valid())


func test_walk_distance_min_greater_than_max() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.walk_distance_min_px = 300.0
	assert_has(Array(b.validation_errors()), "walk_distance_min_px > walk_distance_max_px")


func test_throw_speed_min_greater_than_max() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.throw_min_speed = 3000.0
	assert_has(Array(b.validation_errors()), "throw_min_speed > throw_max_speed")


func test_sulk_greater_than_max() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.sulk_sec = b.sulk_max_sec + 1.0
	assert_has(Array(b.validation_errors()), "sulk_sec > sulk_max_sec")


func test_max_fall_not_above_hard_landing() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.max_fall_speed = b.hard_landing_speed
	assert_has(Array(b.validation_errors()), "max_fall_speed <= hard_landing_speed", "жёсткую посадку нельзя получить")


func test_non_positive_body() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.body_size_px = Vector2(0.0, 80.0)
	assert_false(b.is_valid())
	b.body_size_px = Vector2(56.0, -1.0)
	assert_false(b.is_valid())


func test_non_positive_stride_step_window() -> void:
	for field: String in ["walk_stride_px", "max_step_sec", "throw_sample_window_sec"]:
		var b: HeroBalance = HeroFixture.balance()
		b.set(field, 0.0)
		assert_false(b.is_valid(), "%s = 0 недопустим" % field)
		b.set(field, -1.0)
		assert_false(b.is_valid(), "%s < 0 недопустим" % field)


func test_several_violations_all_reported() -> void:
	var b: HeroBalance = HeroFixture.balance()
	b.idle_pause_min_sec = 99.0
	b.walk_distance_min_px = 999.0
	b.throw_min_speed = 9999.0
	assert_eq(b.validation_errors().size(), 3)
