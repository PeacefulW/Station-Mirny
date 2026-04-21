class_name MountainResolver
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

var _last_mountain_id: int = 0
var _last_component_id: int = 0
var _debug_snapshot: Dictionary = {"ready": false}

func update_from_player_position(
	world_pos: Vector2,
	streamer: WorldStreamer
) -> void:
	if streamer == null:
		_debug_snapshot = {
			"ready": false,
			"reason": "missing_dependencies",
			"last_mountain_id": _last_mountain_id,
			"last_component_id": _last_component_id,
		}
		return
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	var current_sample: Dictionary = streamer.get_mountain_cover_sample(tile_coord)
	if not bool(current_sample.get("ready", false)):
		_debug_snapshot = {
			"ready": false,
			"reason": "sample_not_ready",
			"tile_coord": tile_coord,
			"last_mountain_id": _last_mountain_id,
			"last_component_id": _last_component_id,
		}
		return
	var current_component_id: int = int(current_sample.get("component_id", 0))
	var current_mountain_id: int = int(current_sample.get("mountain_id", 0)) if current_component_id > 0 else 0
	var last_mountain_id_before_update: int = _last_mountain_id
	var last_component_id_before_update: int = _last_component_id
	_debug_snapshot = {
		"ready": true,
		"tile_coord": tile_coord,
		"sample_mountain_id": int(current_sample.get("mountain_id", 0)),
		"sample_mountain_flags": int(current_sample.get("mountain_flags", 0)),
		"sample_component_id": current_component_id,
		"sample_is_opening": bool(current_sample.get("is_opening", false)),
		"resolved_mountain_id": current_mountain_id,
		"resolved_component_id": current_component_id,
		"last_mountain_id_before_update": last_mountain_id_before_update,
		"last_component_id_before_update": last_component_id_before_update,
	}
	if current_mountain_id == _last_mountain_id and current_component_id == _last_component_id:
		_debug_snapshot["last_mountain_id_after_update"] = _last_mountain_id
		_debug_snapshot["last_component_id_after_update"] = _last_component_id
		return
	streamer.set_active_mountain_component(current_mountain_id, current_component_id)
	_last_mountain_id = current_mountain_id
	_last_component_id = current_component_id
	_debug_snapshot["last_mountain_id_after_update"] = _last_mountain_id
	_debug_snapshot["last_component_id_after_update"] = _last_component_id

func get_debug_snapshot() -> Dictionary:
	return _debug_snapshot.duplicate(true)
