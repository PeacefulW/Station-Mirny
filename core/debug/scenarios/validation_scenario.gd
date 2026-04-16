class_name ValidationScenario
extends RefCounted

var _scenario_name: StringName = &"validation_scenario"
var _result: Dictionary = {}
var _complete: bool = false
var _abort_run: bool = false

func _init(scenario_name: StringName = &"validation_scenario") -> void:
	_scenario_name = scenario_name
	_result = {
		"name": String(_scenario_name),
		"state": "pending",
		"updated_frame": Engine.get_process_frames(),
	}

func get_name() -> StringName:
	return _scenario_name

func start(_context) -> void:
	_set_result_state("running")

func update(_context, _delta: float) -> void:
	pass

func is_complete() -> bool:
	return _complete

func should_abort_run() -> bool:
	return _abort_run

func get_result() -> Dictionary:
	return _result.duplicate(true)

func _set_result_state(state: String, extra: Dictionary = {}) -> void:
	_result["name"] = String(_scenario_name)
	_result["state"] = state
	_result["updated_frame"] = Engine.get_process_frames()
	for key_variant: Variant in extra.keys():
		_result[key_variant] = extra[key_variant]

func _complete_with_state(state: String, extra: Dictionary = {}, abort_run: bool = false) -> void:
	_set_result_state(state, extra)
	_complete = true
	_abort_run = abort_run

func _finish_pass(extra: Dictionary = {}) -> void:
	_complete_with_state("passed", extra)

func _finish_finished(extra: Dictionary = {}) -> void:
	_complete_with_state("finished", extra)

func _finish_skip(reason: String, extra: Dictionary = {}) -> void:
	var merged: Dictionary = extra.duplicate(true)
	merged["reason"] = reason
	_complete_with_state("skipped", merged)

func _finish_failed(
	message: String,
	extra: Dictionary = {},
	state: String = "failed",
	blocker: String = "validation_step_failed"
) -> void:
	var merged: Dictionary = extra.duplicate(true)
	merged["message"] = message
	merged["blocker"] = blocker
	_complete_with_state(state, merged, state == "failed" or state == "blocked")
