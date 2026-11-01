class_name HeroStateMachine
extends RefCounted
## Иерархическая машина: root > grounded (idle, walk, land), airborne (fall, thrown), carried,
## web (shoot_web, swing, hang, stretched).
## update и handle_input идут от листа к корню до первого непустого id.

signal state_changed(from: StringName, to: StringName)

var _ctx: HeroContext
var _states: Dictionary = {}  # StringName -> HeroState
var _leaf: HeroState


func _init(context: HeroContext) -> void:
	_ctx = context
	var root := _add(RootState.new(), HeroState.ROOT, null)
	var grounded := _add(GroundedState.new(), HeroState.GROUNDED, root)
	var airborne := _add(AirborneState.new(), HeroState.AIRBORNE, root)
	_add(IdleState.new(), HeroState.IDLE, grounded)
	_add(WalkState.new(), HeroState.WALK, grounded)
	_add(LandState.new(), HeroState.LAND, grounded)
	_add(FallState.new(), HeroState.FALL, airborne)
	_add(ThrownState.new(), HeroState.THROWN, airborne)
	_add(CarriedState.new(), HeroState.CARRIED, root)
	var web := _add(WebState.new(), HeroState.WEB, root)
	_add(ShootWebState.new(), HeroState.SHOOT_WEB, web)
	_add(SwingState.new(), HeroState.SWING, web)
	_add(HangState.new(), HeroState.HANG, web)
	_add(StretchedState.new(), HeroState.STRETCHED, web)


## Входит в начальный лист (и его предков).
func start(initial: StringName) -> void:
	var target: HeroState = _leaf_state(initial)
	if target == null or _leaf != null:
		return
	_leaf = target
	for s in _chain_down(target, null):
		s.enter()
	state_changed.emit(HeroState.NONE, initial)


func update(delta: float) -> void:
	if _leaf == null:
		return
	_ctx.tick_emotions(delta)
	_ctx.tick_web(delta)
	var s: HeroState = _leaf
	while s != null:
		var next: StringName = s.update(delta)
		if next != HeroState.NONE:
			transition(next)
			return
		s = s.parent


func handle_input(input: HeroInput) -> void:
	if _leaf == null:
		return
	var s: HeroState = _leaf
	while s != null:
		var next: StringName = s.handle_input(input)
		if next != HeroState.NONE:
			transition(next)
			return
		s = s.parent


## Минимум по цепочке листа и по эмоциям.
func next_tick_sec() -> float:
	var result: float = minf(_ctx.emotion_wake_sec(), _ctx.web_wake_sec())
	var s: HeroState = _leaf
	while s != null:
		result = minf(result, s.next_tick_sec())
		s = s.parent
	return result


func current_id() -> StringName:
	return _leaf.id if _leaf != null else HeroState.NONE


## Состояние по id (для тестов и мостов); null, если нет.
func get_state(id: StringName) -> HeroState:
	return _states.get(id) as HeroState


## Переход в лист: exit от листа до общего предка, затем enter вниз. В текущий лист не перезапускает.
func transition(to: StringName) -> void:
	var target: HeroState = _leaf_state(to)
	if _leaf == null or target == null or target == _leaf:
		return
	var from_id: StringName = _leaf.id
	var from_chain: Array[HeroState] = _chain_up(_leaf)
	var to_chain: Array[HeroState] = _chain_up(target)
	var common: HeroState = null
	for s in from_chain:
		if to_chain.has(s):
			common = s
			break
	for s in from_chain:
		if s == common:
			break
		s.exit()
	_leaf = target
	for s in _chain_down(target, common):
		s.enter()
	state_changed.emit(from_id, to)


func _add(state: HeroState, id: StringName, parent: HeroState) -> HeroState:
	state.id = id
	state.ctx = _ctx
	state.parent = parent
	_states[id] = state
	return state


## Только листья: у них нет детей.
func _leaf_state(id: StringName) -> HeroState:
	var s: HeroState = _states.get(id) as HeroState
	if s == null:
		return null
	for other: HeroState in _states.values():
		if other.parent == s:
			return null
	return s


func _chain_up(s: HeroState) -> Array[HeroState]:
	var out: Array[HeroState] = []
	var cur: HeroState = s
	while cur != null:
		out.append(cur)
		cur = cur.parent
	return out


## От ребёнка common (исключая common) вниз до листа.
func _chain_down(leaf: HeroState, common: HeroState) -> Array[HeroState]:
	var up: Array[HeroState] = []
	var cur: HeroState = leaf
	while cur != null and cur != common:
		up.append(cur)
		cur = cur.parent
	up.reverse()
	return up
