class_name PowerValidationScenario
extends "res://core/debug/scenarios/validation_scenario.gd"

const POWER_SETTLE_FRAMES: int = 12
const POWER_WAIT_TIMEOUT_FRAMES: int = 180

var _power_validation_stage: int = -1
var _power_wait_frames_remaining: int = 0
var _power_wait_timeout_frames_remaining: int = -1
var _power_case: Dictionary = {}

func _init() -> void:
	super._init(&"power")

func start(context) -> void:
	super.start(context)
	if context.building_system == null or context.power_system == null or context.life_support == null or context.player == null:
		context.log_status("power validation skipped; required systems unavailable")
		_finish_skip("required_systems_unavailable")
		return
	context.collect_validation_scrap(64)
	var battery_tile: Vector2i = context.building_system.world_to_grid(context.player.global_position) + Vector2i(8, 4)
	_power_case = {
		"battery_tile": battery_tile,
		"baseline_source_count": context.power_system.get_registered_source_count(),
		"baseline_consumer_count": context.power_system.get_registered_consumer_count(),
		"baseline_supply": context.power_system.total_supply,
		"baseline_demand": context.power_system.total_demand,
		"baseline_powered": context.life_support.is_powered(),
	}
	_power_validation_stage = 0
	_set_result_state("running", {"battery_tile": battery_tile})
	context.log_status("power validation prepared at %s" % [battery_tile])

func update(context, _delta: float) -> void:
	if _process_power_wait_if_needed(context):
		return
	match _power_validation_stage:
		0:
			if int(_power_case.get("baseline_consumer_count", 0)) <= 0:
				_finish_failed("power validation found no registered consumers")
				return
			if not context.place_validation_building("ark_battery", _power_case.get("battery_tile", Vector2i.ZERO)):
				_finish_failed("failed to place validation battery")
				return
			context.log_status("placed validation battery %s" % [_power_case["battery_tile"]])
			_begin_power_wait()
		1:
			var baseline_sources: int = int(_power_case.get("baseline_source_count", 0))
			if context.power_system.get_registered_source_count() != baseline_sources + 1:
				_finish_failed("power registry did not add validation battery source")
				return
			if context.power_system.total_supply <= float(_power_case.get("baseline_supply", 0.0)):
				_finish_failed("power supply did not increase after validation battery placement")
				return
			if not context.life_support.is_powered():
				_finish_failed("life support did not become powered after validation battery placement")
				return
			if not context.remove_validation_building(_power_case.get("battery_tile", Vector2i.ZERO)):
				_finish_failed("failed to remove validation battery")
				return
			context.log_status("removed validation battery %s" % [_power_case["battery_tile"]])
			_begin_power_wait()
		2:
			if context.power_system.get_registered_source_count() != int(_power_case.get("baseline_source_count", 0)):
				_finish_failed("power registry did not remove validation battery source")
				return
			if not is_equal_approx(context.power_system.total_supply, float(_power_case.get("baseline_supply", 0.0))):
				_finish_failed("power supply did not return to baseline after validation battery removal")
				return
			if context.life_support.is_powered() != bool(_power_case.get("baseline_powered", false)):
				_finish_failed("life support power state did not return to baseline after battery removal")
				return
			context.log_status("power validation complete")
			_finish_pass()
		_:
			_finish_failed("power validation reached an invalid stage")

func _process_power_wait_if_needed(context) -> bool:
	if _power_wait_timeout_frames_remaining < 0:
		return false
	if context.power_system != null and context.power_system.has_pending_recompute():
		_power_wait_timeout_frames_remaining -= 1
		_power_wait_frames_remaining = POWER_SETTLE_FRAMES
		if _power_wait_timeout_frames_remaining <= 0:
			_finish_failed("power recompute did not settle within timeout")
		return true
	if _power_wait_frames_remaining > 0:
		_power_wait_frames_remaining -= 1
		return true
	_power_wait_timeout_frames_remaining = -1
	_power_validation_stage += 1
	return true

func _begin_power_wait() -> void:
	_power_wait_frames_remaining = POWER_SETTLE_FRAMES
	_power_wait_timeout_frames_remaining = POWER_WAIT_TIMEOUT_FRAMES
