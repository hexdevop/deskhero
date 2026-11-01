extends GutTest
## T-215: CornerWebField: плетение шагами, смахивание, порог очистки, падающие нити, set_bounds, free_corners,
## segments_distance. Без сцены.

const BOUNDS: Rect2 = Rect2(0.0, 0.0, 800.0, 600.0)

var _woven: Array[int] = []
var _swept: Array[int] = []


func before_each() -> void:
	_woven.clear()
	_swept.clear()


func _field(seed_value: int = 1, bounds: Rect2 = BOUNDS, tweak: Callable = Callable()) -> CornerWebField:
	var b: HeroBalance = HeroFixture.balance()
	if tweak.is_valid():
		tweak.call(b)
	var f := CornerWebField.new(b, HeroFixture.rng(seed_value))
	f.set_bounds(bounds)
	f.woven.connect(func(c: int) -> void: _woven.append(c))
	f.swept.connect(func(c: int) -> void: _swept.append(c))
	return f


func _balance_of(f: CornerWebField) -> HeroBalance:
	return f._balance


func _weave_all(f: CornerWebField, corner: int) -> int:
	assert_true(f.begin_weave(corner))
	var steps: int = 0
	while not f.weave_step(corner):
		steps += 1
		assert_lt(steps, 100, "плетение не кончается")
		if steps >= 100:
			break
	return steps + 1


## Локальная точка угла (x, y растут внутрь области) в глобальные lpx.
func _g(f: CornerWebField, corner: int, local: Vector2) -> Vector2:
	var sx: float = 1.0 if CornerWebField.is_left(corner) else -1.0
	var sy: float = 1.0 if CornerWebField.is_top(corner) else -1.0
	return f.corner_origin(corner) + Vector2(local.x * sx, local.y * sy)


## Отрезок x + y = k в локальных координатах угла, оба конца за стенами (снаружи области).
func _cross(f: CornerWebField, corner: int, k: float) -> Array[Vector2]:
	return [_g(f, corner, Vector2(k + 20.0, -20.0)), _g(f, corner, Vector2(-20.0, k + 20.0))]


func _fast(f: CornerWebField, a: Vector2, b: Vector2) -> bool:
	return f.sweep(a, b, a.distance_to(b) / (_balance_of(f).sweep_min_speed * 4.0))


# --- плетение

func test_new_field_is_empty_and_all_free() -> void:
	var f: CornerWebField = _field()
	assert_eq(f.free_corners(), [0, 1, 2, 3] as Array[int])
	assert_false(f.has_webs())
	assert_eq(f.revision, 0)
	assert_eq(f.draw_data().size(), 0)
	assert_eq(f.wake_sec(), INF)
	for c: int in 4:
		assert_true(f.is_free(c))
		assert_false(f.is_weaving(c))


func test_invalid_corner_indices() -> void:
	var f: CornerWebField = _field()
	assert_false(f.is_free(-1))
	assert_false(f.is_free(4))
	assert_false(f.is_weaving(-1))
	assert_false(f.is_weaving(99))
	assert_true(f.weave_step(99), "несуществующий угол: плетение окончено, ничего не делаем")
	assert_true(f.weave_step(-1))
	assert_eq(f.revision, 0)


func test_begin_weave_occupies_corner_but_shows_nothing() -> void:
	var f: CornerWebField = _field()
	assert_true(f.begin_weave(CornerWebField.Corner.TOP_RIGHT))
	assert_false(f.is_free(CornerWebField.Corner.TOP_RIGHT))
	assert_true(f.is_weaving(CornerWebField.Corner.TOP_RIGHT))
	assert_false(f.begin_weave(CornerWebField.Corner.TOP_RIGHT), "занятый угол не берётся повторно")
	assert_eq(f.visible_count(CornerWebField.Corner.TOP_RIGHT), 0, "узор задуман, но ещё не показан")
	assert_false(f.has_webs(), "до первого шага курсор опрашивать не нужно")
	assert_eq(f.free_corners(), [0, 2, 3] as Array[int])


func test_weave_steps_reveal_strokes_and_finish_on_last_step() -> void:
	var f: CornerWebField = _field(5)
	var corner: int = CornerWebField.Corner.BOTTOM_LEFT
	var steps: int = _balance_of(f).weave_steps
	f.begin_weave(corner)
	var last_visible: int = 0
	for i: int in steps:
		var rev: int = f.revision
		var done: bool = f.weave_step(corner)
		assert_gt(f.revision, rev, "каждый шаг видим")
		assert_eq(f.step_of(corner), i + 1)
		assert_gte(f.visible_count(corner), last_visible, "нити только прибавляются")
		last_visible = f.visible_count(corner)
		assert_eq(done, i == steps - 1, "окончено только на последнем шаге")
	assert_eq(_woven, [corner] as Array[int], "woven шлётся один раз")
	assert_false(f.is_weaving(corner))
	assert_false(f.is_free(corner), "оплетённый угол не свободен")
	assert_true(f.has_webs())
	assert_true(f.weave_step(corner), "лишний шаг ничего не делает")
	assert_eq(_woven.size(), 1)
	assert_eq(f.step_of(corner), steps)


func test_first_step_shows_spokes_and_last_shows_all_with_rings() -> void:
	var f: CornerWebField = _field(2)
	var corner: int = CornerWebField.Corner.TOP_LEFT
	f.begin_weave(corner)
	f.weave_step(corner)
	var first: Array[CornerWebField.Line] = f.draw_data()
	assert_gte(first.size(), CornerWebField.SPOKES_MIN)
	for line: CornerWebField.Line in first:
		assert_eq(line.kind, CornerWebField.Kind.SPOKE, "сначала только лучи")
	_weave_all_remaining(f, corner)
	var kinds: Dictionary = {}
	for line: CornerWebField.Line in f.draw_data():
		kinds[line.kind] = true
	assert_true(kinds.has(CornerWebField.Kind.RING), "в конце есть кольца")
	assert_gt(f.visible_count(corner), first.size())


func _weave_all_remaining(f: CornerWebField, corner: int) -> void:
	var guard: int = 0
	while not f.weave_step(corner) and guard < 100:
		guard += 1


func test_unfinished_weaving_keeps_corner_taken_and_partial() -> void:
	var f: CornerWebField = _field()
	var corner: int = CornerWebField.Corner.TOP_LEFT
	f.begin_weave(corner)
	f.weave_step(corner)
	f.weave_step(corner)
	assert_true(f.is_weaving(corner))
	assert_false(f.is_free(corner))
	assert_true(f.has_webs())
	assert_eq(_woven.size(), 0, "woven только по окончании")
	assert_false(f.begin_weave(corner))


func test_pattern_is_deterministic_for_seed_and_differs_between_seeds() -> void:
	var a: CornerWebField = _field(9)
	var b: CornerWebField = _field(9)
	var c: CornerWebField = _field(10)
	for f: CornerWebField in [a, b, c]:
		_weave_all(f, CornerWebField.Corner.TOP_LEFT)
	var da: Array[CornerWebField.Line] = a.draw_data()
	var db: Array[CornerWebField.Line] = b.draw_data()
	var dc: Array[CornerWebField.Line] = c.draw_data()
	assert_eq(da.size(), db.size())
	for i: int in da.size():
		assert_eq(da[i].points, db[i].points)
	var same: bool = da.size() == dc.size()
	if same:
		for i: int in da.size():
			if da[i].points != dc[i].points:
				same = false
				break
	assert_false(same, "другое зерно даёт другой узор")


func test_draw_data_inside_bounds_and_near_own_corner_for_every_corner() -> void:
	var f: CornerWebField = _field(3)
	var radius: float = _balance_of(f).corner_web_radius_px
	for corner: int in 4:
		_weave_all(f, corner)
		assert_false(f.is_free(corner))
	var spokes: Dictionary = {}
	for line: CornerWebField.Line in f.draw_data():
		for p: Vector2 in line.points:
			assert_true(BOUNDS.grow(0.01).has_point(p), "нить внутри области: %s" % p)
		if line.kind != CornerWebField.Kind.SPOKE:
			continue
		for corner: int in 4:
			if line.points[0].is_equal_approx(f.corner_origin(corner)):
				spokes[corner] = int(spokes.get(corner, 0)) + 1
				for p: Vector2 in line.points:
					assert_lte(p.distance_to(f.corner_origin(corner)), radius + 0.01)
	for corner: int in 4:
		assert_gte(int(spokes.get(corner, 0)), CornerWebField.SPOKES_MIN, "лучи угла %d растут из его начала" % corner)


func test_corner_origin_for_nonzero_bounds() -> void:
	var f: CornerWebField = _field(1, Rect2(100.0, 50.0, 400.0, 300.0))
	assert_eq(f.corner_origin(CornerWebField.Corner.TOP_LEFT), Vector2(100, 50))
	assert_eq(f.corner_origin(CornerWebField.Corner.TOP_RIGHT), Vector2(500, 50))
	assert_eq(f.corner_origin(CornerWebField.Corner.BOTTOM_LEFT), Vector2(100, 350))
	assert_eq(f.corner_origin(CornerWebField.Corner.BOTTOM_RIGHT), Vector2(500, 350))


# --- смахивание

func test_sweep_requires_speed() -> void:
	var f: CornerWebField = _field(4)
	var corner: int = CornerWebField.Corner.TOP_LEFT
	_weave_all(f, corner)
	var seg: Array[Vector2] = _cross(f, corner, 60.0)
	var len: float = seg[0].distance_to(seg[1])
	var min_speed: float = _balance_of(f).sweep_min_speed
	var rev: int = f.revision
	assert_false(f.sweep(seg[0], seg[1], len / (min_speed * 0.99)), "чуть медленнее порога: не смахивает")
	assert_eq(f.revision, rev)
	assert_false(f.sweep(seg[0], seg[1], 5.0), "медленное движение")
	assert_true(f.has_webs())
	assert_true(f.sweep(seg[0], seg[1], len / (min_speed * 2.0)), "вдвое быстрее порога смахивает")
	assert_gt(f.revision, rev)


func test_sweep_zero_or_negative_dt_is_ignored() -> void:
	var f: CornerWebField = _field(4)
	var corner: int = CornerWebField.Corner.TOP_LEFT
	_weave_all(f, corner)
	var seg: Array[Vector2] = _cross(f, corner, 60.0)
	var before: int = f.visible_count(corner)
	assert_false(f.sweep(seg[0], seg[1], 0.0))
	assert_false(f.sweep(seg[0], seg[1], -1.0))
	assert_eq(f.visible_count(corner), before)


func test_sweep_across_corner_with_endpoints_outside_hits() -> void:
	for corner: int in 4:
		var f: CornerWebField = _field(6 + corner)
		_weave_all(f, corner)
		var seg: Array[Vector2] = _cross(f, corner, 70.0)
		assert_false(BOUNDS.has_point(seg[0]) and BOUNDS.has_point(seg[1]), "оба конца снаружи или на стене")
		var before: int = f.visible_count(corner)
		assert_true(_fast(f, seg[0], seg[1]), "угол %d: поперечный взмах задел нити" % corner)
		assert_lt(f.visible_count(corner), before)


func test_sweep_far_from_webs_changes_nothing() -> void:
	var f: CornerWebField = _field(4)
	_weave_all(f, CornerWebField.Corner.TOP_LEFT)
	var rev: int = f.revision
	assert_false(_fast(f, Vector2(400, 300), Vector2(500, 350)), "середина экрана")
	assert_false(_fast(f, Vector2(700, 500), Vector2(790, 590)), "чужой угол без паутины")
	assert_eq(f.revision, rev)
	assert_eq(f.wake_sec(), INF)


func test_sweep_only_touches_corner_it_crosses() -> void:
	var f: CornerWebField = _field(4)
	_weave_all(f, CornerWebField.Corner.TOP_LEFT)
	_weave_all(f, CornerWebField.Corner.BOTTOM_RIGHT)
	var br: int = f.visible_count(CornerWebField.Corner.BOTTOM_RIGHT)
	var seg: Array[Vector2] = _cross(f, CornerWebField.Corner.TOP_LEFT, 70.0)
	assert_true(_fast(f, seg[0], seg[1]))
	assert_eq(f.visible_count(CornerWebField.Corner.BOTTOM_RIGHT), br)


func test_sweep_does_not_hit_unrevealed_strokes() -> void:
	var f: CornerWebField = _field(4)
	var corner: int = CornerWebField.Corner.TOP_LEFT
	f.begin_weave(corner)
	var seg: Array[Vector2] = _cross(f, corner, 70.0)
	assert_false(_fast(f, seg[0], seg[1]), "узор ещё не показан")
	assert_true(f.is_weaving(corner))


func test_sweep_dropped_strokes_become_falling_and_wake() -> void:
	var f: CornerWebField = _field(4)
	var corner: int = CornerWebField.Corner.TOP_LEFT
	_weave_all(f, corner)
	var total: int = f.visible_count(corner)
	var seg: Array[Vector2] = _cross(f, corner, 70.0)
	assert_true(_fast(f, seg[0], seg[1]))
	var gone: int = total - f.visible_count(corner)
	assert_gt(gone, 0)
	assert_eq(f.wake_sec(), 0.0, "падающие нити требуют кадров")
	var lines: Array[CornerWebField.Line] = f.draw_data()
	assert_eq(lines.size(), total, "живые плюс падающие дают прежнее число")
	var falling: int = 0
	for line: CornerWebField.Line in lines:
		if line.alpha == 1.0:
			continue
		falling += 1
	assert_eq(falling, 0, "в момент смахивания alpha ещё 1")


func test_falling_threads_fade_move_and_vanish() -> void:
	var f: CornerWebField = _field(4)
	var corner: int = CornerWebField.Corner.TOP_LEFT
	_weave_all(f, corner)
	var seg: Array[Vector2] = _cross(f, corner, 70.0)
	_fast(f, seg[0], seg[1])
	var fall_sec: float = _balance_of(f).web_fall_sec
	var base: Dictionary = {}
	var drops: Array[CornerWebField.Line] = f.draw_data()
	# запоминаем точки падающих (те, что не среди живых): после смахивания все они на месте
	var alive_pts: int = f.visible_count(corner)
	var rev: int = f.revision
	f.tick(fall_sec * 0.5)
	assert_gt(f.revision, rev, "падение видно")
	var mid: Array[CornerWebField.Line] = f.draw_data()
	assert_eq(mid.size(), drops.size())
	var faded: int = 0
	for line: CornerWebField.Line in mid:
		if line.alpha < 1.0:
			faded += 1
			assert_almost_eq(line.alpha, 0.5, 0.001)
	assert_eq(faded, drops.size() - alive_pts)
	assert_eq(f.wake_sec(), 0.0)
	f.tick(fall_sec * 0.5)
	assert_eq(f.wake_sec(), INF, "все упали")
	assert_eq(f.draw_data().size(), alive_pts)
	base.clear()


func test_tick_without_falling_threads_is_free() -> void:
	var f: CornerWebField = _field(4)
	_weave_all(f, CornerWebField.Corner.TOP_LEFT)
	var rev: int = f.revision
	f.tick(1.0)
	assert_eq(f.revision, rev, "ни одной перерисовки без падающих нитей")


func test_tick_negative_delta_does_not_rewind() -> void:
	var f: CornerWebField = _field(4)
	var corner: int = CornerWebField.Corner.TOP_LEFT
	_weave_all(f, corner)
	var seg: Array[Vector2] = _cross(f, corner, 70.0)
	_fast(f, seg[0], seg[1])
	f.tick(-5.0)
	for line: CornerWebField.Line in f.draw_data():
		assert_lte(line.alpha, 1.0)
		assert_gte(line.alpha, 0.0)


func test_clear_threshold_frees_corner_and_emits_swept() -> void:
	var f: CornerWebField = _field(4)
	var corner: int = CornerWebField.Corner.TOP_LEFT
	_weave_all(f, corner)
	var shown: int = f.shown_count(corner)
	var ratio: float = _balance_of(f).sweep_clear_ratio
	var cleared_at: int = -1
	var k: float = 20.0
	var i: int = 0
	while cleared_at < 0 and k < 140.0:
		var seg: Array[Vector2] = _cross(f, corner, k)
		_fast(f, seg[0], seg[1])
		if _swept.size() > 0:
			cleared_at = i
		else:
			assert_gte(float(f.visible_count(corner)), ratio * float(shown), "без очистки живых не меньше порога")
			assert_false(f.is_free(corner), "пока порог не пройден, угол занят")
		k += 10.0
		i += 1
	assert_gte(cleared_at, 0, "взмахи по всему углу в итоге очищают его")
	assert_eq(_swept, [corner] as Array[int])
	assert_eq(f.visible_count(corner), 0)
	assert_true(f.is_free(corner))
	assert_false(f.is_weaving(corner))
	assert_eq(f.step_of(corner), 0)
	assert_false(f.has_webs() and f.visible_count(corner) > 0)
	assert_true(f.begin_weave(corner), "освобождённый угол можно плести заново")


func test_clear_ratio_one_clears_on_first_hit() -> void:
	var f: CornerWebField = _field(4, BOUNDS, func(b: HeroBalance) -> void: b.sweep_clear_ratio = 1.0)
	var corner: int = CornerWebField.Corner.BOTTOM_RIGHT
	_weave_all(f, corner)
	var seg: Array[Vector2] = _cross(f, corner, 70.0)
	assert_true(_fast(f, seg[0], seg[1]))
	assert_eq(_swept, [corner] as Array[int], "порог 1.0: достаточно одной смахнутой нити")
	assert_true(f.is_free(corner))
	assert_eq(f.visible_count(corner), 0)


func test_swept_clears_whole_corner_into_falling_strokes() -> void:
	var f: CornerWebField = _field(4, BOUNDS, func(b: HeroBalance) -> void: b.sweep_clear_ratio = 1.0)
	var corner: int = CornerWebField.Corner.TOP_RIGHT
	_weave_all(f, corner)
	var total: int = f.visible_count(corner)
	var seg: Array[Vector2] = _cross(f, corner, 70.0)
	_fast(f, seg[0], seg[1])
	assert_eq(f.draw_data().size(), total, "все нити угла стали падающими")
	f.tick(_balance_of(f).web_fall_sec)
	assert_eq(f.draw_data().size(), 0)
	assert_false(f.has_webs())


func test_sweep_during_weaving_frees_corner_and_weave_step_reports_done_without_woven() -> void:
	var f: CornerWebField = _field(4, BOUNDS, func(b: HeroBalance) -> void: b.sweep_clear_ratio = 1.0)
	var corner: int = CornerWebField.Corner.BOTTOM_LEFT
	f.begin_weave(corner)
	f.weave_step(corner)
	f.weave_step(corner)
	var seg: Array[Vector2] = _cross(f, corner, 60.0)
	assert_true(_fast(f, seg[0], seg[1]))
	assert_eq(_swept, [corner] as Array[int])
	assert_true(f.is_free(corner))
	assert_false(f.is_weaving(corner))
	assert_true(f.weave_step(corner), "плетение окончено смахиванием")
	assert_eq(_woven.size(), 0, "woven не шлётся для смахнутого угла")


# --- set_bounds и revision

func test_set_bounds_same_or_empty_field_keeps_revision() -> void:
	var f: CornerWebField = _field()
	var rev: int = f.revision
	f.set_bounds(BOUNDS)
	f.set_bounds(Rect2(0.0, 0.0, 1000.0, 700.0))
	assert_eq(f.revision, rev, "пустому полю перерисовка не нужна")
	assert_eq(f.get_bounds(), Rect2(0.0, 0.0, 1000.0, 700.0))


func test_set_bounds_with_webs_bumps_revision_and_moves_lines() -> void:
	var f: CornerWebField = _field(3)
	var corner: int = CornerWebField.Corner.BOTTOM_RIGHT
	_weave_all(f, corner)
	var before: Array[CornerWebField.Line] = f.draw_data()
	var rev: int = f.revision
	f.set_bounds(Rect2(0.0, 0.0, 1000.0, 700.0))
	assert_gt(f.revision, rev)
	var after: Array[CornerWebField.Line] = f.draw_data()
	assert_eq(after.size(), before.size())
	for i: int in before.size():
		for k: int in before[i].points.size():
			assert_eq(after[i].points[k], before[i].points[k] + Vector2(200.0, 100.0), "паутина уехала вместе с углом")


func test_set_bounds_does_not_move_falling_threads() -> void:
	var f: CornerWebField = _field(3, BOUNDS, func(b: HeroBalance) -> void: b.sweep_clear_ratio = 1.0)
	var corner: int = CornerWebField.Corner.BOTTOM_RIGHT
	_weave_all(f, corner)
	var seg: Array[Vector2] = _cross(f, corner, 70.0)
	_fast(f, seg[0], seg[1])
	var before: Array[CornerWebField.Line] = f.draw_data()
	var rev: int = f.revision
	f.set_bounds(Rect2(0.0, 0.0, 1000.0, 700.0))
	assert_gt(f.revision, rev, "падающие нити перерисовываются при смене границ")
	var after: Array[CornerWebField.Line] = f.draw_data()
	for i: int in before.size():
		assert_eq(after[i].points, before[i].points)


# --- segments_distance

func test_segments_distance_crossing_is_zero() -> void:
	assert_eq(CornerWebField.segments_distance(Vector2(0, 0), Vector2(10, 10), Vector2(0, 10), Vector2(10, 0)), 0.0)


func test_segments_distance_parallel() -> void:
	assert_almost_eq(CornerWebField.segments_distance(Vector2(0, 0), Vector2(10, 0), Vector2(0, 5), Vector2(10, 5)), 5.0, 0.0001)


func test_segments_distance_end_to_side() -> void:
	assert_almost_eq(CornerWebField.segments_distance(Vector2(0, 0), Vector2(10, 0), Vector2(5, 3), Vector2(5, 20)), 3.0, 0.0001)


func test_segments_distance_end_to_end() -> void:
	assert_almost_eq(CornerWebField.segments_distance(Vector2(0, 0), Vector2(3, 0), Vector2(6, 4), Vector2(9, 4)), 5.0, 0.0001)


func test_segments_distance_collinear_disjoint_and_overlapping() -> void:
	assert_almost_eq(CornerWebField.segments_distance(Vector2(0, 0), Vector2(1, 0), Vector2(4, 0), Vector2(6, 0)), 3.0, 0.0001)
	assert_almost_eq(CornerWebField.segments_distance(Vector2(0, 0), Vector2(5, 0), Vector2(3, 0), Vector2(8, 0)), 0.0, 0.0001)


func test_segments_distance_degenerate_point_segments() -> void:
	assert_almost_eq(CornerWebField.segments_distance(Vector2(0, 0), Vector2(0, 0), Vector2(3, 4), Vector2(3, 4)), 5.0, 0.0001)
	assert_almost_eq(CornerWebField.segments_distance(Vector2(5, 0), Vector2(5, 0), Vector2(0, 0), Vector2(10, 0)), 0.0, 0.0001)


func test_segments_distance_is_symmetric() -> void:
	var a := Vector2(1, 2)
	var b := Vector2(7, 3)
	var c := Vector2(-4, 9)
	var d := Vector2(2, 15)
	assert_almost_eq(CornerWebField.segments_distance(a, b, c, d), CornerWebField.segments_distance(c, d, a, b), 0.0001)
	assert_almost_eq(CornerWebField.segments_distance(a, b, c, d), CornerWebField.segments_distance(b, a, d, c), 0.0001)
