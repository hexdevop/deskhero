class_name WalkState
extends HeroState
## Идёт в случайную сторону на случайное расстояние, у стены разворачивается.
## Если у героя есть план с walk_to_x (плетение), идёт к этой точке и на месте возвращает следующее состояние плана.
## Не дошёл (захват, падение, таймаут, цель пропала): план сбрасывается, чтобы он не пережил прогулку (М4 ревью T-211).

## Уже этой ширины хода нет смысла гулять.
const MIN_WALK_SPAN_PX: float = 1.0
## Приход к цели, lpx.
const ARRIVE_PX: float = 0.5
## Страховка пути к цели: время в запасах от расчётного и добавка, сек.
const TARGET_TIMEOUT_RATIO: float = 2.0
const TARGET_TIMEOUT_EXTRA_SEC: float = 5.0

var remaining_px: float = 0.0
var _target_x: float = NAN
var _time_left: float = 0.0


func enter() -> void:
	ctx.pose = &"walk"
	ctx.velocity = Vector2.ZERO
	_target_x = NAN
	var plan: WebPlan = ctx.plan
	if plan != null and plan.needs_walk():
		_target_x = plan.walk_to_x
		var dx: float = _target_x - ctx.pos.x
		ctx.facing = 1 if dx >= 0.0 else -1
		remaining_px = absf(dx)
		_time_left = remaining_px / ctx.balance.walk_speed * TARGET_TIMEOUT_RATIO + TARGET_TIMEOUT_EXTRA_SEC
		return
	ctx.facing = 1 if ctx.rng.randi() % 2 == 0 else -1
	remaining_px = ctx.rng.randf_range(ctx.balance.walk_distance_min_px, ctx.balance.walk_distance_max_px)


func exit() -> void:
	var plan: WebPlan = ctx.plan
	if plan != null and plan.needs_walk():
		ctx.plan = null  # прогулка к цели прервана: плана больше нет
		if plan.corner >= 0:
			ctx.weave_cooldown_sec = ctx.balance.weave_retry_sec


func update(delta: float) -> StringName:
	if not is_nan(_target_x):
		return _update_to_target(delta)
	var b: HeroBalance = ctx.balance
	var half_w: float = b.body_size_px.x * 0.5
	var min_x: float = ctx.bounds.position.x + half_w
	var max_x: float = ctx.bounds.end.x - half_w
	if max_x - min_x < MIN_WALK_SPAN_PX:
		return IDLE
	var target_x: float = ctx.pos.x + float(ctx.facing) * b.walk_speed * delta
	var hit_wall: bool = target_x < min_x or target_x > max_x
	target_x = clampf(target_x, min_x, max_x)
	var moved: float = absf(target_x - ctx.pos.x)
	ctx.pos.x = target_x
	remaining_px -= moved
	ctx.walk_phase = fposmod(ctx.walk_phase + moved / b.walk_stride_px, 1.0)
	if remaining_px <= 0.0:
		return IDLE
	if hit_wall:
		ctx.facing = -ctx.facing
	return NONE


## Шаг к walk_to_x плана: цель зажимается в текущие границы, путь ограничен по времени.
func _update_to_target(delta: float) -> StringName:
	var b: HeroBalance = ctx.balance
	var plan: WebPlan = ctx.plan
	if plan == null:
		return IDLE
	var half_w: float = b.body_size_px.x * 0.5
	var min_x: float = ctx.bounds.position.x + half_w
	var max_x: float = ctx.bounds.end.x - half_w
	_time_left -= delta
	if max_x - min_x < MIN_WALK_SPAN_PX or _time_left <= 0.0:
		return IDLE  # exit сбросит план
	var goal: float = clampf(_target_x, min_x, max_x)
	var dx: float = goal - ctx.pos.x
	var moved: float = minf(absf(dx), b.walk_speed * maxf(delta, 0.0))
	if moved > 0.0:
		ctx.facing = 1 if dx > 0.0 else -1
		ctx.pos.x += signf(dx) * moved
		ctx.walk_phase = fposmod(ctx.walk_phase + moved / b.walk_stride_px, 1.0)
	if absf(goal - ctx.pos.x) > ARRIVE_PX:
		return NONE
	plan.walk_to_x = NAN
	_target_x = NAN
	if plan.corner >= 0 and not ctx.corners.is_free(plan.corner):
		ctx.plan = null  # угол занят или уже оплетён
		ctx.weave_cooldown_sec = ctx.balance.weave_retry_sec
		return IDLE
	if plan.kind == WebPlan.Kind.WEAVE_BOTTOM:
		return WEAVE
	return SHOOT_WEB
