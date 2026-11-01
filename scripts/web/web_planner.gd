class_name WebPlanner
extends RefCounted
## Выбор действия и цели паутины в момент конца паузы idle (D-012, п. 1). Работает на ctx.rng: детерминирован.
## Цели лежат на верхнем и боковых краях области; нижний край не кандидат. Плетение добавляет T-213.

## Значение по умолчанию поля swing_safe_height_margin (для сверки в тестах); в игре берётся из баланса.
const SAFE_HEIGHT_MARGIN: float = 0.85


## WALK или SHOOT_WEB; при выстреле план лежит в ctx.plan. Обида запрещает вылазки (проверяет idle).
func decide(ctx: HeroContext) -> StringName:
	var b: HeroBalance = ctx.balance
	if ctx.web_cooldown_sec > 0.0 or ctx.rng.randf() >= b.web_trip_chance:
		return HeroState.WALK
	var first_swing: bool = ctx.rng.randf() >= b.web_descent_chance
	var plan: WebPlan = swing_plan(ctx) if first_swing else descent_plan(ctx)
	if plan == null:
		return HeroState.WALK  # цели нет (мало места): обычная прогулка, тихо
	ctx.plan = plan
	ctx.web_cooldown_sec = b.web_trip_min_interval_sec
	return HeroState.SHOOT_WEB if not plan.needs_walk() else HeroState.WALK


## Раскачка со стартом на полу. null, если нет места или старт слишком высок для мягкой посадки.
func swing_plan(ctx: HeroContext) -> WebPlan:
	var b: HeroBalance = ctx.balance
	var half_w: float = b.body_size_px.x * 0.5
	var min_x: float = ctx.bounds.position.x + half_w
	var max_x: float = ctx.bounds.end.x - half_w
	var room_left: float = ctx.pos.x - min_x
	var room_right: float = max_x - ctx.pos.x
	var side: float = 1.0 if room_right >= room_left else -1.0
	var room: float = maxf(room_left, room_right)
	if room < b.swing_min_room_px:
		return null
	var wall: bool = ctx.rng.randf() < b.web_wall_anchor_chance
	var anchor_y: float = ctx.bounds.position.y
	var dx: float
	if wall:
		anchor_y += ctx.rng.randf() * ctx.bounds.size.y * b.web_wall_anchor_zone_ratio
		dx = room
	else:
		dx = minf(ctx.rng.randf_range(b.swing_anchor_dx_min_px, b.swing_anchor_dx_max_px), room)
	var height: float = ctx.floor_y() - anchor_y
	if height < b.web_min_height_px:
		return null
	var grip: float = ctx.hand_offset().length()
	var swing_length: float = height - grip - b.swing_floor_clearance_px
	if swing_length <= 0.0:
		return null
	# Герой поднимается по лучу к якорю, пока нить не станет swing_length: высота старта над полом.
	var reach: float = height - grip
	var safe: float = safe_start_height(b)
	if not wall and safe < reach:
		var dist_max: float = swing_length / (1.0 - safe / reach)
		dx = minf(dx, sqrt(maxf(dist_max * dist_max - reach * reach, 0.0)))
	if not wall and dx < b.swing_anchor_dx_min_px:
		return null
	var start_dist: float = sqrt(dx * dx + reach * reach)
	if reach * (1.0 - swing_length / start_dist) > safe:
		return null
	var plan := WebPlan.new()
	plan.kind = WebPlan.Kind.SWING
	plan.anchor = Vector2(ctx.pos.x + side * dx, anchor_y)
	if wall:
		plan.anchor.x = max_x if side > 0.0 else min_x
	plan.swing_length = swing_length
	var start_angle: float = atan2(dx, reach)
	plan.release_angle = minf(ctx.rng.randf_range(b.swing_release_angle_min_rad, b.swing_release_angle_max_rad),
			start_angle * b.swing_release_start_ratio)
	if (plan.anchor - (ctx.pos - Vector2(0.0, grip))).length() > b.web_max_length_px:
		return null
	return plan


## Спуск с верхнего края: якорь над героем со случайным смещением.
func descent_plan(ctx: HeroContext) -> WebPlan:
	var b: HeroBalance = ctx.balance
	var half_w: float = b.body_size_px.x * 0.5
	var min_x: float = ctx.bounds.position.x + half_w
	var max_x: float = ctx.bounds.end.x - half_w
	var anchor_y: float = ctx.bounds.position.y
	var height: float = ctx.floor_y() - anchor_y
	if height < b.web_min_height_px:
		return null
	var grip: float = ctx.hand_offset().length()
	var jitter: float = ctx.rng.randf_range(-b.descent_anchor_jitter_px, b.descent_anchor_jitter_px)
	var anchor_x: float = clampf(ctx.pos.x + jitter, minf(min_x, max_x), maxf(min_x, max_x))
	var full: float = height - grip
	if full <= b.hang_top_gap_px:
		return null
	var plan := WebPlan.new()
	plan.kind = WebPlan.Kind.DESCENT
	plan.anchor = Vector2(anchor_x, anchor_y)
	var ratio: float = ctx.rng.randf_range(b.hang_rest_ratio_min, b.hang_rest_ratio_max)
	plan.rest_length = clampf(full * ratio, b.hang_top_gap_px, full)
	if (plan.anchor - (ctx.pos - Vector2(0.0, grip))).length() > b.web_max_length_px:
		return null
	return plan


## Наибольшая высота старта раскачки над полом, с которой падение в любой точке дуги остаётся мягким.
static func safe_start_height(b: HeroBalance) -> float:
	var speed: float = b.hard_landing_speed * b.swing_safe_impact_ratio
	return speed * speed / (2.0 * b.gravity) * b.swing_safe_height_margin


## Скорость удара о пол при свободном падении из pos (ступни) со скоростью velocity.
static func predicted_impact(pos: Vector2, velocity: Vector2, floor_y: float, gravity: float, max_fall: float) -> float:
	var drop: float = maxf(floor_y - pos.y, 0.0)
	return minf(sqrt(velocity.y * velocity.y + 2.0 * gravity * drop), max_fall)


## x посадки при свободном падении (без сопротивления воздуха).
static func predicted_land_x(pos: Vector2, velocity: Vector2, floor_y: float, gravity: float) -> float:
	var drop: float = maxf(floor_y - pos.y, 0.0)
	var v_end: float = sqrt(velocity.y * velocity.y + 2.0 * gravity * drop)
	return pos.x + velocity.x * (v_end - velocity.y) / gravity
