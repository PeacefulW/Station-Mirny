class_name RouteValidationScenario
extends "res://core/debug/scenarios/validation_scenario.gd"

const SEGMENT_SETTLE_FRAMES: int = 30
const TAIL_SETTLE_FRAMES: int = 180
const TOPOLOGY_WAIT_TIMEOUT_FRAMES: int = 360
const CATCH_UP_STATUS_LOG_INTERVAL_FRAMES: int = 60
const ARRIVE_DISTANCE_PX: float = 16.0
const DEFAULT_MOVE_SPEED_PX_PER_SEC: float = 8192.0

var _route_preset_name: StringName = &"local_ring"
var _route_offsets: Array = []
var _move_speed_px_per_sec: float = DEFAULT_MOVE_SPEED_PX_PER_SEC
var _targets: Array[Vector2] = []
var _target_index: int = 0
var _segment_frames_remaining: int = 0
var _tail_frames_remaining: int = -1
var _topology_wait_frames_remaining: int = -1
var _catch_up_status_frames_remaining: int = -1
var _last_catch_up_signature: String = ""
var _unchanged_catch_up_status_count: int = 0
var _route_announced: bool = false

func _init() -> void:
	super._init(&"route")

func configure(
	scenario_name: StringName,
	route_preset_name: StringName,
	route_offsets: Array,
	move_speed_px_per_sec: float = DEFAULT_MOVE_SPEED_PX_PER_SEC
) -> RouteValidationScenario:
	_scenario_name = scenario_name
	_result["name"] = String(_scenario_name)
	_route_preset_name = route_preset_name
	_route_offsets = route_offsets.duplicate()
	_move_speed_px_per_sec = move_speed_px_per_sec
	return self

func start(context) -> void:
	super.start(context)
	_targets = context.build_route_targets(_route_offsets)
	_target_index = 0
	_segment_frames_remaining = 0
	_tail_frames_remaining = -1
	_topology_wait_frames_remaining = -1
	_catch_up_status_frames_remaining = -1
	_last_catch_up_signature = ""
	_unchanged_catch_up_status_count = 0
	_route_announced = false
	context.set_route_progress(_route_preset_name, _targets, _target_index)
	_set_result_state("running", {
		"route_preset": String(_route_preset_name),
		"waypoint_count": _targets.size(),
		"move_speed_px_per_sec": _move_speed_px_per_sec,
	})
	context.log_status("%s prepared: preset=%s waypoints=%d" % [
		String(_scenario_name),
		_route_preset_name,
		_targets.size(),
	])

func update(context, delta: float) -> void:
	if context.player == null:
		_finish_failed("validation player is unavailable")
		return
	if _segment_frames_remaining > 0:
		_segment_frames_remaining -= 1
		return
	if _tail_frames_remaining >= 0:
		_process_tail_settle(context)
		return
	if _target_index >= _targets.size():
		context.set_validation_player_velocity(Vector2.ZERO)
		_tail_frames_remaining = TAIL_SETTLE_FRAMES
		_topology_wait_frames_remaining = -1
		_catch_up_status_frames_remaining = -1
		_last_catch_up_signature = ""
		_unchanged_catch_up_status_count = 0
		context.log_status("%s complete: preset=%s reached=%d/%d draining_background_work=true" % [
			String(_scenario_name),
			_route_preset_name,
			_target_index,
			_targets.size(),
		])
		return
	if not _route_announced:
		_route_announced = true
		context.log_status("%s start: preset=%s waypoints=%d" % [
			String(_scenario_name),
			_route_preset_name,
			_targets.size(),
		])
	var target: Vector2 = _targets[_target_index]
	var display_target: Vector2 = context.resolve_route_display_target(target)
	var move_direction: Vector2 = context.player.global_position.direction_to(display_target)
	context.set_validation_player_velocity(move_direction * _move_speed_px_per_sec)
	context.player.global_position = context.player.global_position.move_toward(
		display_target,
		_move_speed_px_per_sec * delta
	)
	if context.player.global_position.distance_to(display_target) > ARRIVE_DISTANCE_PX:
		return
	context.player.global_position = context.canonicalize_world_position(target)
	context.set_validation_player_velocity(Vector2.ZERO)
	_target_index += 1
	context.set_route_progress(_route_preset_name, _targets, _target_index)
	context.log_status("%s reached waypoint %d/%d at %s" % [
		String(_scenario_name),
		_target_index,
		_targets.size(),
		target,
	])
	_segment_frames_remaining = SEGMENT_SETTLE_FRAMES

func _process_tail_settle(context) -> void:
	if _tail_frames_remaining > 0:
		_tail_frames_remaining -= 1
		return
	if context.is_runtime_caught_up():
		var outcome: String = "finished"
		var blocker: String = "none"
		if context.has_redraw_backlog():
			outcome = "not_converged"
			blocker = "redraw_only"
		_finish_route(context, outcome, blocker)
		return
	if _topology_wait_frames_remaining < 0:
		_topology_wait_frames_remaining = TOPOLOGY_WAIT_TIMEOUT_FRAMES
		_catch_up_status_frames_remaining = 0
		_last_catch_up_signature = ""
		_unchanged_catch_up_status_count = 0
		context.emit_route_wait_status(context.describe_catch_up_blocker())
	if _catch_up_status_frames_remaining <= 0:
		var catch_up_signature: String = context.build_catch_up_signature()
		if catch_up_signature == _last_catch_up_signature:
			_unchanged_catch_up_status_count += 1
		else:
			_last_catch_up_signature = catch_up_signature
			_unchanged_catch_up_status_count = 0
		context.emit_route_wait_status(
			context.describe_catch_up_blocker(),
			_unchanged_catch_up_status_count
		)
		_catch_up_status_frames_remaining = CATCH_UP_STATUS_LOG_INTERVAL_FRAMES
	if _topology_wait_frames_remaining > 0:
		_topology_wait_frames_remaining -= 1
		_catch_up_status_frames_remaining -= 1
		return
	_finish_route(context, "blocked", context.describe_catch_up_blocker())

func _finish_route(
	context,
	outcome: String,
	blocker: String,
	failure_message: String = ""
) -> void:
	context.set_route_progress(_route_preset_name, _targets, _target_index)
	context.emit_route_outcome(outcome, blocker, _unchanged_catch_up_status_count, failure_message)
	var extra: Dictionary = {
		"blocker": blocker,
		"message": failure_message,
		"reached_waypoints": "%d/%d" % [_target_index, _targets.size()],
		"route_preset": String(_route_preset_name),
		"move_speed_px_per_sec": _move_speed_px_per_sec,
	}
	if _scenario_name == &"speed_traverse":
		extra["readiness_outcome"] = outcome
	if outcome == "finished":
		_finish_finished(extra)
		return
	if outcome == "not_converged":
		_complete_with_state("not_converged", extra)
		return
	_finish_failed(failure_message, extra, "blocked", blocker)
