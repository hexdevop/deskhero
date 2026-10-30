extends GutTest
## Чистые функции T-004: Overlay.resolve_screen, PlaceholderSquare.clamp_position / rect_polygon / window_scale.


func test_resolve_screen_minus_one_gives_primary() -> void:
	assert_eq(Overlay.resolve_screen(-1, 1, 3), 1)


func test_resolve_screen_out_of_range_gives_primary() -> void:
	assert_eq(Overlay.resolve_screen(3, 0, 3), 0)
	assert_eq(Overlay.resolve_screen(99, 2, 3), 2)
	assert_eq(Overlay.resolve_screen(-5, 2, 3), 2)


func test_resolve_screen_valid() -> void:
	assert_eq(Overlay.resolve_screen(0, 1, 3), 0)
	assert_eq(Overlay.resolve_screen(2, 1, 3), 2)


func test_resolve_screen_zero_count_gives_primary() -> void:
	assert_eq(Overlay.resolve_screen(0, 0, 0), 0)
	assert_eq(Overlay.resolve_screen(2, 5, 0), 5)


func test_clamp_inside_unchanged() -> void:
	var b: Rect2 = Rect2(0, 0, 1000, 800)
	assert_eq(PlaceholderSquare.clamp_position(Vector2(100, 200), Vector2(96, 96), b), Vector2(100, 200))


func test_clamp_negative_and_overflow() -> void:
	var b: Rect2 = Rect2(0, 0, 1000, 800)
	var s: Vector2 = Vector2(96, 96)
	assert_eq(PlaceholderSquare.clamp_position(Vector2(-50, -1), s, b), Vector2(0, 0))
	assert_eq(PlaceholderSquare.clamp_position(Vector2(5000, 5000), s, b), Vector2(904, 704))


func test_clamp_nonzero_origin() -> void:
	var b: Rect2 = Rect2(0, 25, 1000, 775)
	var s: Vector2 = Vector2(96, 96)
	assert_eq(PlaceholderSquare.clamp_position(Vector2(10, 0), s, b), Vector2(10, 25))
	assert_eq(PlaceholderSquare.clamp_position(Vector2(2000, 2000), s, b), Vector2(904, 704))


func test_clamp_bounds_smaller_than_square() -> void:
	var b: Rect2 = Rect2(10, 10, 50, 50)
	assert_eq(PlaceholderSquare.clamp_position(Vector2(100, 100), Vector2(96, 96), b), Vector2(10, 10))
	assert_eq(PlaceholderSquare.clamp_position(Vector2(-100, -100), Vector2(96, 96), b), Vector2(10, 10))


func test_clamp_zero_bounds() -> void:
	assert_eq(PlaceholderSquare.clamp_position(Vector2(5, 5), Vector2(96, 96), Rect2()), Vector2.ZERO)


func test_rect_polygon_scale_one() -> void:
	var p: PackedVector2Array = PlaceholderSquare.rect_polygon(Rect2(10, 20, 30, 40))
	assert_eq(p, PackedVector2Array([Vector2(10, 20), Vector2(40, 20), Vector2(40, 60), Vector2(10, 60)]))


func test_rect_polygon_scale_two() -> void:
	var p: PackedVector2Array = PlaceholderSquare.rect_polygon(Rect2(10, 20, 30, 40), Vector2(2, 2))
	assert_eq(p, PackedVector2Array([Vector2(20, 40), Vector2(80, 40), Vector2(80, 120), Vector2(20, 120)]))


func test_rect_polygon_zero_rect_degenerate() -> void:
	var p: PackedVector2Array = PlaceholderSquare.rect_polygon(Rect2(5, 5, 0, 0))
	assert_eq(p.size(), 4)
	assert_eq(p[0], p[2])


func test_window_scale_equal_is_one() -> void:
	assert_eq(PlaceholderSquare.window_scale(Vector2(1440, 900), Vector2(1440, 900)), Vector2.ONE)


func test_window_scale_retina_2x() -> void:
	assert_eq(PlaceholderSquare.window_scale(Vector2(2880, 1800), Vector2(1440, 900)), Vector2(2, 2))


func test_window_scale_zero_viewport_is_one() -> void:
	assert_eq(PlaceholderSquare.window_scale(Vector2(100, 100), Vector2.ZERO), Vector2.ONE)
	assert_eq(PlaceholderSquare.window_scale(Vector2(100, 100), Vector2(0, 50)), Vector2.ONE)


func test_window_scale_zero_window() -> void:
	assert_eq(PlaceholderSquare.window_scale(Vector2.ZERO, Vector2(100, 100)), Vector2.ZERO)
