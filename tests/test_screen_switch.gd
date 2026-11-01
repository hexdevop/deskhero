extends GutTest
## T-009: Overlay.screen_at_point / point_in_any и PlaceholderSquare.drag_to (без окна и без событий ОС).

var _office: Array[Rect2i] = [Rect2i(0, 2160, 2940, 1912), Rect2i(2940, 0, 3840, 2160)]
var _two_hd: Array[Rect2i] = [Rect2i(1920, 0, 1920, 1080), Rect2i(0, 0, 1920, 1080)]


func test_office_inside_each() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(100, 3000), _office), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(4000, 500), _office), 1)


func test_office_edges_half_open() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(0, 2160), _office), 0, "левый верхний угол входит")
	assert_eq(Overlay.screen_at_point(Vector2i(2939, 4071), _office), 0, "последний пиксель входит")
	assert_eq(Overlay.screen_at_point(Vector2i(2940, 4071), _office), -1, "x = правая граница: вне")
	assert_eq(Overlay.screen_at_point(Vector2i(2939, 4072), _office), -1, "y = нижняя граница: вне")
	assert_eq(Overlay.screen_at_point(Vector2i(2940, 0), _office), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(2940, 2159), _office), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(2940, 2160), _office), -1, "угол стыка: y = нижняя граница экрана 1, x = правая граница экрана 0")


func test_office_outside_returns_minus_one() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(-1, 0), _office), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(100, 100), _office), -1, "над экраном 0, левее экрана 1")
	assert_eq(Overlay.screen_at_point(Vector2i(6780, 0), _office), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(0, 0), _office), -1, "(0,0), который отдаёт mouse_get_position вне экранов")


func test_office_margin_shrinks_both_sides() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(2935, 3000), _office, 8), -1, "5 px от правого края экрана 0 при margin 8")
	assert_eq(Overlay.screen_at_point(Vector2i(2931, 3000), _office, 8), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(2931, 3000), _office, 0), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(7, 3000), _office, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(8, 2168), _office, 8), 0, "ровно на внутренней границе")
	assert_eq(Overlay.screen_at_point(Vector2i(2945, 100), _office, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(2948, 8), _office, 8), 1)


func test_office_gap_between_screens_with_margin() -> void:
	# курсор в 3 px по обе стороны границы: ни один экран не выигрывает, остаёмся где были
	assert_eq(Overlay.screen_at_point(Vector2i(2937, 2200), _office, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(2943, 2100), _office, 8), -1)


func test_two_hd_primary_right() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(2000, 500), _two_hd), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(500, 500), _two_hd), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(1919, 0), _two_hd), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(1920, 0), _two_hd), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(-1, 500), _two_hd), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(3840, 500), _two_hd), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(500, 1080), _two_hd), -1)


func test_two_hd_margin_at_shared_border() -> void:
	assert_eq(Overlay.screen_at_point(Vector2i(1915, 500), _two_hd, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(1925, 500), _two_hd, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(1911, 500), _two_hd, 8), 1)
	assert_eq(Overlay.screen_at_point(Vector2i(1912, 500), _two_hd, 8), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(1928, 500), _two_hd, 8), 0)


func test_menu_bar_excluded_in_usable_rect() -> void:
	var usable: Array[Rect2i] = [Rect2i(0, 25, 1920, 1055), Rect2i(1920, 0, 1920, 1080)]
	assert_eq(Overlay.screen_at_point(Vector2i(500, 10), usable), -1, "меню-бар не принадлежит экрану")
	assert_eq(Overlay.screen_at_point(Vector2i(500, 25), usable), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(500, 30), usable, 8), -1, "margin считается от рабочей области")
	assert_eq(Overlay.screen_at_point(Vector2i(500, 33), usable, 8), 0)


func test_single_screen() -> void:
	var one: Array[Rect2i] = [Rect2i(0, 0, 1440, 900)]
	assert_eq(Overlay.screen_at_point(Vector2i(10, 10), one), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(1440, 10), one), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(10, 10), one, 20), -1)


func test_empty_list() -> void:
	var none: Array[Rect2i] = []
	assert_eq(Overlay.screen_at_point(Vector2i(10, 10), none), -1)
	assert_false(Overlay.point_in_any(Vector2i.ZERO, none))


func test_margin_degenerate() -> void:
	var one: Array[Rect2i] = [Rect2i(0, 0, 100, 100)]
	assert_eq(Overlay.screen_at_point(Vector2i(50, 50), one, 50), -1, "margin съедает область целиком")
	assert_eq(Overlay.screen_at_point(Vector2i(50, 50), one, 1000), -1)
	assert_eq(Overlay.screen_at_point(Vector2i(0, 0), one, -5), 0, "отрицательный margin = 0")
	assert_eq(Overlay.screen_at_point(Vector2i(100, 100), one, -5), -1, "отрицательный margin не расширяет область")


func test_zero_size_rect_skipped() -> void:
	var rects: Array[Rect2i] = [Rect2i(0, 0, 0, 0), Rect2i(0, 0, 100, 100)]
	assert_eq(Overlay.screen_at_point(Vector2i(0, 0), rects), 1)


func test_overlapping_first_wins() -> void:
	var rects: Array[Rect2i] = [Rect2i(0, 0, 100, 100), Rect2i(50, 50, 100, 100)]
	assert_eq(Overlay.screen_at_point(Vector2i(60, 60), rects), 0)
	assert_eq(Overlay.screen_at_point(Vector2i(120, 120), rects), 1)


func test_point_in_any() -> void:
	assert_true(Overlay.point_in_any(Vector2i(100, 3000), _office))
	assert_true(Overlay.point_in_any(Vector2i(4000, 500), _office))
	assert_false(Overlay.point_in_any(Vector2i(0, 0), _office))
	assert_false(Overlay.point_in_any(Vector2i(2940, 4072), _office))
	assert_true(Overlay.point_in_any(Vector2i(2940, 2159), _office))


# --- PlaceholderSquare.drag_to: узел без окна, drag запускается прямым вызовом _input ---

func _make_square() -> PlaceholderSquare:
	var sq: PlaceholderSquare = PlaceholderSquare.new()
	add_child_autofree(sq)  # _ready создаёт config по умолчанию, квадрат 96 px
	sq.set_bounds(Rect2(0, 0, 1000, 800))
	sq.position = Vector2(100, 100)
	return sq


func _press(sq: PlaceholderSquare, at: Vector2) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	sq._input(ev)


func test_drag_to_without_drag_does_nothing() -> void:
	var sq: PlaceholderSquare = _make_square()
	sq.drag_to(Vector2(500, 500))
	assert_eq(sq.position, Vector2(100, 100))


func test_drag_to_keeps_grab_offset() -> void:
	var sq: PlaceholderSquare = _make_square()
	_press(sq, Vector2(120, 130))  # захват со смещением (20, 30)
	assert_true(sq.is_dragging())
	sq.drag_to(Vector2(520, 430))
	assert_eq(sq.position, Vector2(500, 400))


func test_drag_to_clamps_to_new_bounds() -> void:
	var sq: PlaceholderSquare = _make_square()
	_press(sq, Vector2(120, 130))
	sq.set_bounds(Rect2(0, 0, 500, 300))  # окно переехало на меньший экран
	sq.drag_to(Vector2(5000, 5000))
	assert_eq(sq.position, Vector2(404, 204))
	sq.drag_to(Vector2(-5000, -5000))
	assert_eq(sq.position, Vector2.ZERO)


func test_drag_to_scale_change_does_not_jump() -> void:
	# курсор в точке P: квадрат остаётся на тех же относительных координатах под курсором при смене scale
	var sq: PlaceholderSquare = _make_square()
	_press(sq, Vector2(150, 150))  # offset (50, 50)
	var cursor_screen: Vector2 = Vector2(900, 700)
	var origin: Vector2 = Vector2(200, 100)
	for sc: float in [2.0, 1.0, 2.0]:
		sq.drag_to((cursor_screen - origin) / sc)
		assert_eq(sq.position + Vector2(50, 50), (cursor_screen - origin) / sc, "квадрат под курсором при scale %s" % sc)


func test_drag_to_no_redundant_signals() -> void:
	var sq: PlaceholderSquare = _make_square()
	_press(sq, Vector2(120, 130))
	sq.drag_to(Vector2(520, 430))
	var before: Vector2 = sq.position
	sq.drag_to(Vector2(520, 430))
	assert_eq(sq.position, before)


func test_drag_to_after_cancel_does_nothing() -> void:
	var sq: PlaceholderSquare = _make_square()
	_press(sq, Vector2(120, 130))
	sq.cancel_drag()
	sq.drag_to(Vector2(700, 700))
	assert_eq(sq.position, Vector2(100, 100))
