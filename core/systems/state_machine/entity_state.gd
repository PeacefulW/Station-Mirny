class_name EntityState
extends RefCounted

var machine: StateMachine = null
var owner: Node = null
var state_name: StringName = &""

func setup(state_machine: StateMachine, state_owner: Node, name: StringName) -> EntityState:
	machine = state_machine
	owner = state_owner
	state_name = name
	return self

func enter(_data: Dictionary = {}) -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func handle_input(_event: InputEvent) -> void:
	pass
