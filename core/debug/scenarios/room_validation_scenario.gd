class_name RoomValidationScenario
extends "res://core/debug/scenarios/validation_scenario.gd"

const ROOM_SETTLE_FRAMES: int = 12
const ROOM_WAIT_TIMEOUT_FRAMES: int = 180

var _room_validation_stage: int = -1
var _room_wait_frames_remaining: int = 0
var _room_wait_timeout_frames_remaining: int = -1
var _room_case: Dictionary = {}

func _init() -> void:
	super._init(&"room")

func start(context) -> void:
	super.start(context)
	if context.building_system == null or context.player == null:
		context.log_status("room validation skipped; building system unavailable")
		_finish_skip("building_system_unavailable")
		return
	context.collect_validation_scrap(64)
	var origin: Vector2i = context.building_system.world_to_grid(context.player.global_position) + Vector2i(4, 4)
	_room_case = {
		"wall_tiles": [
			origin + Vector2i(0, 0),
			origin + Vector2i(1, 0),
			origin + Vector2i(2, 0),
			origin + Vector2i(0, 1),
			origin + Vector2i(2, 1),
			origin + Vector2i(0, 2),
			origin + Vector2i(1, 2),
			origin + Vector2i(2, 2),
		],
		"interior_tile": origin + Vector2i(1, 1),
		"removed_tile": origin + Vector2i(1, 0),
		"destroyed_tile": origin + Vector2i(0, 1),
	}
	_room_validation_stage = 0
	_set_result_state("running", {"origin": origin})
	context.log_status("room validation prepared at %s" % [origin])

func update(context, _delta: float) -> void:
	if _process_room_wait_if_needed(context):
		return
	match _room_validation_stage:
		0:
			if not _build_validation_room(context):
				_finish_failed("failed to place validation room walls")
				return
			context.log_status("built validation room")
			_begin_room_wait()
		1:
			if not context.building_system.is_cell_indoor(_room_case.get("interior_tile", Vector2i.ZERO)):
				_finish_failed("closed validation room did not become indoor")
				return
			if not context.remove_validation_building(_room_case.get("removed_tile", Vector2i.ZERO)):
				_finish_failed("failed to remove validation room wall")
				return
			context.log_status("removed validation room wall %s" % [_room_case["removed_tile"]])
			_begin_room_wait()
		2:
			if context.building_system.is_cell_indoor(_room_case.get("interior_tile", Vector2i.ZERO)):
				_finish_failed("breached validation room remained indoor")
				return
			if not context.place_validation_building("wall", _room_case.get("removed_tile", Vector2i.ZERO)):
				_finish_failed("failed to re-place validation room wall")
				return
			context.log_status("re-placed validation room wall %s" % [_room_case["removed_tile"]])
			_begin_room_wait()
		3:
			if not context.building_system.is_cell_indoor(_room_case.get("interior_tile", Vector2i.ZERO)):
				_finish_failed("reclosed validation room did not become indoor")
				return
			if not context.destroy_validation_building(_room_case.get("destroyed_tile", Vector2i.ZERO)):
				_finish_failed("failed to destroy validation room wall")
				return
			context.log_status("destroyed validation room wall %s" % [_room_case["destroyed_tile"]])
			_begin_room_wait()
		4:
			if context.building_system.is_cell_indoor(_room_case.get("interior_tile", Vector2i.ZERO)):
				_finish_failed("destroyed-wall validation room remained indoor")
				return
			context.log_status("room validation complete")
			_finish_pass()
		_:
			_finish_failed("room validation reached an invalid stage")

func _process_room_wait_if_needed(context) -> bool:
	if _room_wait_timeout_frames_remaining < 0:
		return false
	if context.building_system != null and context.building_system.has_pending_room_recompute():
		_room_wait_timeout_frames_remaining -= 1
		_room_wait_frames_remaining = ROOM_SETTLE_FRAMES
		if _room_wait_timeout_frames_remaining <= 0:
			_finish_failed("room recompute did not settle within timeout")
		return true
	if _room_wait_frames_remaining > 0:
		_room_wait_frames_remaining -= 1
		return true
	_room_wait_timeout_frames_remaining = -1
	_room_validation_stage += 1
	return true

func _begin_room_wait() -> void:
	_room_wait_frames_remaining = ROOM_SETTLE_FRAMES
	_room_wait_timeout_frames_remaining = ROOM_WAIT_TIMEOUT_FRAMES

func _build_validation_room(context) -> bool:
	for tile: Vector2i in _room_case.get("wall_tiles", []):
		if not context.place_validation_building("wall", tile):
			return false
	return true
