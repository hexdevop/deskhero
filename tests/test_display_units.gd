extends GutTest
## T-114: DisplayUnits.sanitize / units_per_px.


func test_sanitize_valid_values_unchanged() -> void:
	assert_eq(DisplayUnits.sanitize(1.0), 1.0)
	assert_eq(DisplayUnits.sanitize(2.0), 2.0)
	assert_eq(DisplayUnits.sanitize(1.5), 1.5)
	assert_eq(DisplayUnits.sanitize(0.0001), 0.0001)


func test_sanitize_zero_and_negative_give_one() -> void:
	assert_eq(DisplayUnits.sanitize(0.0), 1.0)
	assert_eq(DisplayUnits.sanitize(-0.0), 1.0)
	assert_eq(DisplayUnits.sanitize(-2.0), 1.0)


func test_sanitize_nan_and_inf_give_one() -> void:
	assert_eq(DisplayUnits.sanitize(NAN), 1.0)
	assert_eq(DisplayUnits.sanitize(INF), 1.0)
	assert_eq(DisplayUnits.sanitize(-INF), 1.0)


func test_units_per_px_is_positive_and_finite() -> void:
	var u: float = DisplayUnits.units_per_px()
	assert_gt(u, 0.0)
	assert_false(is_inf(u) or is_nan(u))
