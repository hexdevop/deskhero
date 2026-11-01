extends GutTest
## Чистые функции: Overlay.resolve_screen, HeroContext.clamp_pos, PassthroughShape.rect_polygon / hit_polygon / window_scale.


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


func _ctx_with(bounds: Rect2) -> HeroContext:
	return HeroFixture.context(1, bounds)  # тело 56x80 lpx


func test_clamp_inside_unchanged() -> void:
	var c: HeroContext = _ctx_with(Rect2(0, 0, 1000, 800))
	assert_eq(c.clamp_pos(Vector2(100, 200)), Vector2(100, 200))


func test_clamp_negative_and_overflow() -> void:
	var c: HeroContext = _ctx_with(Rect2(0, 0, 1000, 800))
	assert_eq(c.clamp_pos(Vector2(-50, -1)), Vector2(28, 80), "pos между ступнями: x от половины ширины, y от высоты тела")
	assert_eq(c.clamp_pos(Vector2(5000, 5000)), Vector2(972, 800))


func test_clamp_nonzero_origin() -> void:
	var c: HeroContext = _ctx_with(Rect2(0, 25, 1000, 775))
	assert_eq(c.clamp_pos(Vector2(10, 0)), Vector2(28, 105))
	assert_eq(c.clamp_pos(Vector2(2000, 2000)), Vector2(972, 800))


func test_clamp_bounds_narrower_than_body() -> void:
	var c: HeroContext = _ctx_with(Rect2(10, 10, 50, 50))
	assert_eq(c.clamp_pos(Vector2(100, 100)), Vector2(35, 60), "x по центру области, y на полу")
	assert_eq(c.clamp_pos(Vector2(-100, -100)), Vector2(35, 60))


func test_clamp_zero_bounds() -> void:
	var c: HeroContext = _ctx_with(Rect2())
	assert_eq(c.clamp_pos(Vector2(5, 5)), Vector2.ZERO)


func test_rect_polygon_scale_one() -> void:
	var p: PackedVector2Array = PassthroughShape.rect_polygon(Rect2(10, 20, 30, 40))
	assert_eq(p, PackedVector2Array([Vector2(10, 20), Vector2(40, 20), Vector2(40, 60), Vector2(10, 60)]))


func test_rect_polygon_scale_two() -> void:
	var p: PackedVector2Array = PassthroughShape.rect_polygon(Rect2(10, 20, 30, 40), Vector2(2, 2))
	assert_eq(p, PackedVector2Array([Vector2(20, 40), Vector2(80, 40), Vector2(80, 120), Vector2(20, 120)]))


func test_rect_polygon_zero_rect_degenerate() -> void:
	var p: PackedVector2Array = PassthroughShape.rect_polygon(Rect2(5, 5, 0, 0))
	assert_eq(p.size(), 4)
	assert_eq(p[0], p[2])


func test_hit_polygon_normal_equals_rect_polygon() -> void:
	var r: Rect2 = Rect2(10, 20, 30, 40)
	assert_eq(PassthroughShape.hit_polygon(r, Vector2(2, 2)), PassthroughShape.rect_polygon(r, Vector2(2, 2)))


func test_hit_polygon_empty_rect_gives_tiny_nondegenerate_polygon_outside_window() -> void:
	var p: PackedVector2Array = PassthroughShape.hit_polygon(Rect2(), Vector2(2, 2))
	assert_eq(p.size(), 4, "пустой полигон Godot значит «ловить всё»: нужен непустой")
	assert_ne(p[0], p[2], "невырожденный")
	assert_eq(p[0], Vector2(PassthroughShape.FALLBACK_OFFSET_PX, PassthroughShape.FALLBACK_OFFSET_PX))
	assert_lt(p[2].x, 0.0, "запасной полигон целиком за окном: не съедает пиксель")
	assert_lt(p[2].y, 0.0)


func test_hit_polygon_zero_width_or_height_or_negative() -> void:
	for r: Rect2 in [Rect2(5, 5, 0, 10), Rect2(5, 5, 10, 0), Rect2(5, 5, -3, 10), Rect2(5, 5, 10, -3)]:
		var p: PackedVector2Array = PassthroughShape.hit_polygon(r)
		assert_ne(p[0], p[2], "запасной полигон для %s" % r)
		assert_lt(p[2].x, 0.0)


func test_hit_polygon_collapsed_by_zero_scale_gives_fallback() -> void:
	var p: PackedVector2Array = PassthroughShape.hit_polygon(Rect2(10, 10, 30, 30), Vector2.ZERO)
	assert_ne(p[0], p[2], "масштаб 0 схлопывает полигон: запасной")
	assert_lt(p[2].x, 0.0)


func test_window_scale_equal_is_one() -> void:
	assert_eq(PassthroughShape.window_scale(Vector2(1440, 900), Vector2(1440, 900)), Vector2.ONE)


func test_window_scale_retina_2x() -> void:
	assert_eq(PassthroughShape.window_scale(Vector2(2880, 1800), Vector2(1440, 900)), Vector2(2, 2))


func test_window_scale_zero_viewport_is_one() -> void:
	assert_eq(PassthroughShape.window_scale(Vector2(100, 100), Vector2.ZERO), Vector2.ONE)
	assert_eq(PassthroughShape.window_scale(Vector2(100, 100), Vector2(0, 50)), Vector2.ONE)


func test_window_scale_zero_window() -> void:
	assert_eq(PassthroughShape.window_scale(Vector2.ZERO, Vector2(100, 100)), Vector2.ZERO)
