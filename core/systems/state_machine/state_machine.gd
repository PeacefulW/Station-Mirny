class_name StateMachine
extends RefCounted

var _owner: Node = null
var _states: Dictionary = {}
var _current_state: EntityState = null
var _current_state_name: StringName = &""

func setup(state_owner: Node) -> StateMachine:
	_owner = state_owner
	return self

func add_state(name: StringName, state: EntityState) -> void:
	if not state:
		return
	_states[name] = state.setup(self, _owner, name)

func transition_to(name: StringName, data: Dictionary = {}) -> void:
	if _current_state_name == name:
		return
	var next_state: EntityState = _states.get(name)
	if not next_state:
		push_warning(Localization.t("SYSTEM_STATE_NOT_FOUND", {"state": name}))
		return
	if _current_state:
		_current_state.exit()
	_current_state = next_state
	_current_state_name = name
	_current_state.enter(data)

func get_current_state_name() -> StringName:
	return _current_state_name

func update(delta: float) -> void:
	if _current_state:
		_current_state.update(delta)

func physics_update(delta: float) -> void:
	if _current_state:
		_current_state.physics_update(delta)

func handle_input(event: InputEvent) -> void:
	if _current_state:
		_current_state.handle_input(event)
