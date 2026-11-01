class_name HeroPose
extends RefCounted
## Поза героя в дизайн-единицах (HeroLook). Чистые данные и расчёт, без узлов: тестируется отдельно.
## Все x даны «вперёд = +x»: зеркало по facing делает HeroView.

## Масштаб относительно ступней (приседание, вытяжение).
var scale: Vector2 = Vector2.ONE
## Наклон корпуса, радианы, и точка, вокруг которой он вращается.
var lean: float = 0.0
var pivot: Vector2 = Vector2.ZERO
## Смещение головы и корпуса (дыхание, шаг), по y.
var bob: float = 0.0
## Ступни и кисти: ближняя к зрителю нога и рука (near), дальняя (far).
var foot_near: Vector2 = Vector2(HeroLook.HIP_X, 0.0)
var foot_far: Vector2 = Vector2(-HeroLook.HIP_X, 0.0)
var hand_near: Vector2 = Vector2(HeroLook.SHOULDER_X + 3.0, -14.0)
var hand_far: Vector2 = Vector2(-HeroLook.SHOULDER_X - 3.0, -14.0)
var arms_crossed: bool = false
## Плащ: направление от плеч, длина, изгиб края.
var cape_dir: Vector2 = HeroLook.CAPE_HANG.normalized()
var cape_length: float = HeroLook.CAPE_LENGTH
var cape_bend: float = 0.0
## Мимика.
var emotion: HeroEmotions.Emotion = HeroEmotions.Emotion.NEUTRAL
var blink: bool = false
## Смещение кончика кисточки капюшона (ветер).
var tuft_shift: Vector2 = Vector2.ZERO


## Считает позу. motion: скорость в lpx/с (мировые оси), land_t: 0..1 по посадке, impact: доля hard_landing_speed 0..1+.
## breath: 0..1 фаза дыхания (только покой), clock: секунды для колебаний, пока герой в движении.
func solve(pose: StringName, facing: int, walk_phase: float, emo: HeroEmotions.Emotion, motion: Vector2,
		land_t: float, impact: float, breath: float, blink_closed: bool, clock: float) -> void:
	_reset()
	emotion = emo
	blink = blink_closed
	var v: Vector2 = Vector2(motion.x * float(facing), motion.y)  # в осях рисунка
	match pose:
		&"walk":
			_solve_walk(walk_phase)
		&"fall":
			_solve_air(v, clock, HeroLook.LEAN_MAX_FALL, false)
		&"thrown":
			_solve_air(v, clock, HeroLook.LEAN_MAX_THROWN, true)
		&"carried", &"stretched":
			_solve_carried(v, clock, 1.0)
		&"swing":
			_solve_carried(v, clock, 0.5)
		&"hang":
			_solve_carried(v, clock, 0.25)
		&"shoot_web":
			_solve_shoot()
		&"land":
			_solve_land(land_t, impact)
		_:
			_solve_idle(breath)
	_solve_cape(v, clock, pose)
	if emo == HeroEmotions.Emotion.OFFENDED and (pose == &"idle" or pose == &"land"):
		arms_crossed = true
		hand_near = Vector2(-5.5, -19.0 + bob)
		hand_far = Vector2(5.5, -21.0 + bob)


func _reset() -> void:
	scale = Vector2.ONE
	lean = 0.0
	pivot = Vector2(0.0, HeroLook.HIP_Y)
	bob = 0.0
	foot_near = Vector2(HeroLook.HIP_X + 1.0, 0.0)
	foot_far = Vector2(-HeroLook.HIP_X - 1.0, 0.0)
	hand_near = Vector2(HeroLook.SHOULDER_X + 3.5, -14.5)
	hand_far = Vector2(-HeroLook.SHOULDER_X - 3.5, -14.5)
	arms_crossed = false
	tuft_shift = Vector2.ZERO


func _solve_idle(breath: float) -> void:
	scale = Vector2(1.0 - HeroLook.BREATH_SCALE * 0.5 * breath, 1.0 + HeroLook.BREATH_SCALE * breath)
	bob = 0.0
	hand_near.y -= breath * 0.6
	hand_far.y -= breath * 0.6


func _solve_walk(phase: float) -> void:
	var s: float = sin(phase * TAU)
	var c: float = cos(phase * TAU)
	foot_near = Vector2(HeroLook.HIP_X + 1.0 + s * HeroLook.WALK_STRIDE, -maxf(c, 0.0) * HeroLook.WALK_LIFT)
	foot_far = Vector2(-HeroLook.HIP_X - 1.0 - s * HeroLook.WALK_STRIDE, -maxf(-c, 0.0) * HeroLook.WALK_LIFT)
	hand_near.x -= s * HeroLook.WALK_ARM_SWING
	hand_far.x += s * HeroLook.WALK_ARM_SWING
	bob = -absf(s) * HeroLook.WALK_BOB
	lean = HeroLook.WALK_LEAN
	tuft_shift = Vector2(-2.0, 0.0)


func _solve_air(v: Vector2, clock: float, lean_max: float, thrown: bool) -> void:
	var speed: float = v.length()
	var k: float = clampf(speed / HeroLook.STRETCH_REF_SPEED, 0.0, 1.0)
	var stretch: float = HeroLook.STRETCH_MAX * k
	scale = Vector2(1.0 - stretch * 0.55, 1.0 + stretch)
	pivot = Vector2(0.0, -HeroLook.DESIGN_HEIGHT * 0.45)
	lean = clampf(v.x / HeroLook.LEAN_REF_SPEED, -1.0, 1.0) * lean_max
	var flap: float = sin(clock * HeroLook.FLAP_HZ * TAU) * HeroLook.FLAP_AMOUNT * (0.4 + 0.6 * k)
	if thrown:
		# руки откинуты назад, ноги тянутся следом
		hand_near = Vector2(-HeroLook.SHOULDER_X - 9.0, -38.0 + flap)
		hand_far = Vector2(-HeroLook.SHOULDER_X - 13.0, -30.0 - flap)
		foot_near = Vector2(-1.0, -2.0)
		foot_far = Vector2(-9.0, -1.0)
	else:
		hand_near = Vector2(HeroLook.SHOULDER_X + 13.0, -41.0 + flap)
		hand_far = Vector2(-HeroLook.SHOULDER_X - 13.0, -41.0 - flap)
		foot_near = Vector2(HeroLook.HIP_X + 2.5, -1.5)
		foot_far = Vector2(-HeroLook.HIP_X - 2.5, -3.0)
	tuft_shift = Vector2(-v.x, -v.y).limit_length(HeroLook.STRETCH_REF_SPEED) * 0.006


## kick: размах ног (1 в руках курсора, меньше на нити).
func _solve_carried(v: Vector2, clock: float, kick_scale: float) -> void:
	# висит за руки: вращение вокруг верха, ноги раскачиваются по скорости курсора
	pivot = Vector2(0.0, -HeroLook.DESIGN_HEIGHT + 4.0)
	lean = clampf(v.x / HeroLook.CARRIED_REF_SPEED, -1.0, 1.0) * HeroLook.LEAN_MAX_CARRIED
	var k: float = clampf(v.length() / HeroLook.CARRIED_REF_SPEED, 0.0, 1.0)
	scale = Vector2(1.0 - 0.03 * k, 1.0 + 0.06 + 0.06 * k)
	var kick: float = sin(clock * HeroLook.FLAP_HZ * 0.7 * TAU) * (1.0 + 2.0 * k) * kick_scale
	hand_near = Vector2(HeroLook.SHOULDER_X + 11.0, -42.0)
	hand_far = Vector2(-HeroLook.SHOULDER_X - 11.0, -42.0)
	foot_near = Vector2(HeroLook.HIP_X + 1.5 + kick, -2.0)
	foot_far = Vector2(-HeroLook.HIP_X - 1.5 + kick * 0.6, -1.0)
	tuft_shift = Vector2(-v.x, -v.y).limit_length(HeroLook.CARRIED_REF_SPEED) * 0.008


## Замах паутиной: стоит, ближняя рука поднята к цели.
func _solve_shoot() -> void:
	hand_near = Vector2(HeroLook.SHOULDER_X + 9.0, -40.0)
	tuft_shift = Vector2(-1.0, 0.0)


func _solve_land(t: float, impact: float) -> void:
	var tt: float = clampf(t, 0.0, 1.0)
	var power: float = clampf(impact, HeroLook.SQUASH_MIN_IMPACT, 1.0)
	var amp: float = lerpf(HeroLook.SQUASH_SOFT, HeroLook.SQUASH_HARD, power)
	# приседание, лёгкий перелёт и затухание: в конце позы масштаб почти 1
	var wave: float = exp(-HeroLook.SQUASH_DECAY * tt) * cos(tt * TAU)
	var sq: float = amp * wave
	scale = Vector2(1.0 + sq * 0.9, 1.0 - sq)
	foot_near = Vector2(HeroLook.HIP_X + 3.5 * wave, 0.0)
	foot_far = Vector2(-HeroLook.HIP_X - 3.5 * wave, 0.0)
	hand_near = Vector2(HeroLook.SHOULDER_X + 6.0, -22.0 - 5.0 * wave)
	hand_far = Vector2(-HeroLook.SHOULDER_X - 6.0, -22.0 - 5.0 * wave)
	tuft_shift = Vector2(0.0, 3.0 * wave)


func _solve_cape(v: Vector2, clock: float, pose: StringName) -> void:
	var hang: Vector2 = HeroLook.CAPE_HANG.normalized()
	var wind: float = clampf(v.length() / HeroLook.CAPE_WIND_REF_SPEED, 0.0, 1.0)
	if pose == &"land" or pose == &"idle":
		wind = 0.0
	var dir: Vector2 = hang
	if wind > 0.0:
		var against: Vector2 = -v.normalized()
		dir = hang.lerp(against, wind).normalized()
	cape_dir = dir
	cape_length = HeroLook.CAPE_LENGTH + HeroLook.CAPE_WIND_LENGTH * wind
	var flutter_amp: float = HeroLook.CAPE_FLUTTER * (0.3 + wind) if (wind > 0.0 or pose == &"walk") else 0.0
	cape_bend = sin(clock * HeroLook.CAPE_FLUTTER_HZ * TAU) * flutter_amp
	if pose == &"walk":
		cape_dir = Vector2(-0.62, 0.78).normalized()
