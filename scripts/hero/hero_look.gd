class_name HeroLook
extends RefCounted
## Палитра и числа анимации процедурного героя (до этапа 9, где его заменит Skeleton2D).
## Единицы рисунка: «дизайн-единицы», герой 80 в высоту, ступни в (0, 0), вперёд +x, вверх -y.
## HeroView масштабирует рисунок под body_size_px.y / DESIGN_HEIGHT.

const DESIGN_HEIGHT: float = 80.0

# Палитра: индиго (капюшон), бирюза (костюм), янтарь (плащ, перчатки), тёплая кожа, мята (прибор на запястье), чернила.
const INK: Color = Color(0.106, 0.102, 0.180)
const HOOD: Color = Color(0.290, 0.247, 0.549)
const HOOD_LIGHT: Color = Color(0.416, 0.365, 0.690)
const SUIT: Color = Color(0.122, 0.639, 0.604)
const SUIT_SHADE: Color = Color(0.082, 0.502, 0.498)
const CAPE: Color = Color(1.0, 0.710, 0.180)
const CAPE_SHADE: Color = Color(0.910, 0.537, 0.102)
const SKIN: Color = Color(0.965, 0.812, 0.659)
const BLUSH: Color = Color(0.941, 0.561, 0.525, 0.75)
const MINT: Color = Color(0.561, 0.961, 0.816)
const BOOT: Color = Color(0.26, 0.22, 0.45)
const WHITE: Color = Color(1.0, 1.0, 1.0)
const SWEAT: Color = Color(0.678, 0.906, 1.0)

const OUTLINE_W: float = 1.7
const CIRCLE_POINTS: int = 28

# Пропорции.
const HEAD_CENTER: Vector2 = Vector2(0.0, -50.0)
const HEAD_RADIUS: Vector2 = Vector2(25.0, 22.5)
const FACE_CENTER: Vector2 = Vector2(5.0, -48.0)
const FACE_RADIUS: Vector2 = Vector2(17.0, 14.5)
const TORSO_TOP: float = -31.0
const TORSO_BOTTOM: float = -11.0
const TORSO_HALF_W: float = 10.5
const SHOULDER_Y: float = -27.0
const SHOULDER_X: float = 9.5
const HIP_Y: float = -12.0
const HIP_X: float = 5.5
const CAPE_ANCHOR: Vector2 = Vector2(-4.0, -28.0)

# Покой: каждая перерисовка кадра на Retina стоит около +0.7 п.п. CPU на 1 перерисовку/с (замер T-117),
# поэтому дыхание двумя шагами и моргание по редкому таймеру: около 0.7 перерисовки/с, а не 8 кадров/с.
const BREATH_STEPS: int = 2
const BREATH_STEP_SEC: float = 2.4
const BREATH_SCALE: float = 0.02
const BLINK_MIN_SEC: float = 4.0
const BLINK_MAX_SEC: float = 9.0
const BLINK_SEC: float = 0.14

# Ходьба.
const WALK_STRIDE: float = 7.0
const WALK_LIFT: float = 3.0
const WALK_BOB: float = 1.6
const WALK_LEAN: float = 0.06
const WALK_ARM_SWING: float = 7.0

# Воздух: вытяжение по скорости, наклон по горизонтальной скорости.
const STRETCH_REF_SPEED: float = 1400.0
const STRETCH_MAX: float = 0.18
const LEAN_REF_SPEED: float = 900.0
const LEAN_MAX_THROWN: float = 0.42
const LEAN_MAX_FALL: float = 0.18
const LEAN_MAX_CARRIED: float = 0.32
const CARRIED_REF_SPEED: float = 1200.0
const FLAP_HZ: float = 5.0
const FLAP_AMOUNT: float = 3.0

# Посадка: приседание затухающей волной.
const SQUASH_SOFT: float = 0.14
const SQUASH_HARD: float = 0.28
const SQUASH_MIN_IMPACT: float = 0.35
const SQUASH_DECAY: float = 3.2

# Плащ.
const CAPE_LENGTH: float = 25.0
const CAPE_WIND_LENGTH: float = 15.0
const CAPE_WIND_REF_SPEED: float = 700.0
const CAPE_FLUTTER_HZ: float = 3.0
const CAPE_FLUTTER: float = 2.2
const CAPE_HANG: Vector2 = Vector2(-0.45, 0.89)
