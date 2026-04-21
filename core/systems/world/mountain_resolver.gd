class_name MountainResolver
extends RefCounted

const MountainRevealRegistry = preload("res://core/systems/world/mountain_reveal_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

var _last_mountain_id: int = 0
var _debug_snapshot: Dictionary = {"ready": false}

func update_from_player_position(
	world_pos: Vector2,
	streamer: WorldStreamer,
	registry: MountainRevealRegistry
) -> void:
	if streamer == null or registry == null:
		_debug_snapshot = {
			"ready": false,
			"reason": "missing_dependencies",
			"last_mountain_id": _last_mountain_id,
		}
		return
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	var current_sample: Dictionary = _sample_mountain_tile(tile_coord, streamer)
	if not bool(current_sample.get("ready", false)):
		_debug_snapshot = {
			"ready": false,
			"reason": "sample_not_ready",
			"tile_coord": tile_coord,
			"last_mountain_id": _last_mountain_id,
		}
		return
	var current_mountain_id: int = 0
	var current_component_id: int = 0
	var current_sample_mountain_id: int = int(current_sample.get("mountain_id", 0))
	var current_sample_mountain_flags: int = int(current_sample.get("mountain_flags", 0))
	var current_sample_component_id: int = int(current_sample.get("cavity_component_id", 0))
	var doorway_fallback_used: bool = false
	if current_sample_component_id > 0:
		current_mountain_id = current_sample_mountain_id
		current_component_id = current_sample_component_id
	if current_component_id == 0 \
			and _should_use_doorway_fallback(tile_coord, streamer):
		var fallback_sample: Dictionary = _fallback_interior_cross(tile_coord, streamer)
		current_mountain_id = int(fallback_sample.get("mountain_id", 0))
		current_component_id = int(fallback_sample.get("cavity_component_id", 0))
		doorway_fallback_used = current_component_id > 0
	var last_mountain_id_before_update: int = _last_mountain_id
	_debug_snapshot = {
		"ready": true,
		"tile_coord": tile_coord,
		"sample_mountain_id": current_sample_mountain_id,
		"sample_mountain_flags": current_sample_mountain_flags,
		"sample_cavity_component_id": current_sample_component_id,
		"resolved_mountain_id": current_mountain_id,
		"resolved_cavity_component_id": current_component_id,
		"last_mountain_id_before_update": last_mountain_id_before_update,
		"doorway_fallback_used": doorway_fallback_used,
	}
	streamer.update_active_mountain_component(current_mountain_id, current_component_id, tile_coord)
	if current_mountain_id == _last_mountain_id:
		_debug_snapshot["last_mountain_id_after_update"] = _last_mountain_id
		return
	if _last_mountain_id > 0:
		registry.request_conceal(_last_mountain_id)
	if current_mountain_id > 0:
		registry.request_reveal(current_mountain_id)
	_last_mountain_id = current_mountain_id
	_debug_snapshot["last_mountain_id_after_update"] = _last_mountain_id

func get_debug_snapshot() -> Dictionary:
	return _debug_snapshot.duplicate(true)

func _should_use_doorway_fallback(tile_coord: Vector2i, streamer: WorldStreamer) -> bool:
	var north: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.UP, streamer)
	var south: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.DOWN, streamer)
	if _paired_cavity_sample(north, south).get("cavity_component_id", 0) > 0:
		return true
	var east: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.RIGHT, streamer)
	var west: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.LEFT, streamer)
	return _paired_cavity_sample(east, west).get("cavity_component_id", 0) > 0

func _fallback_interior_cross(tile_coord: Vector2i, streamer: WorldStreamer) -> Dictionary:
	var north: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.UP, streamer)
	var south: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.DOWN, streamer)
	var ns_match: Dictionary = _paired_cavity_sample(north, south)
	if int(ns_match.get("cavity_component_id", 0)) > 0:
		return ns_match
	var east: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.RIGHT, streamer)
	var west: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.LEFT, streamer)
	var ew_match: Dictionary = _paired_cavity_sample(east, west)
	if int(ew_match.get("cavity_component_id", 0)) > 0:
		return ew_match
	return {}

func _paired_cavity_sample(sample_a: Dictionary, sample_b: Dictionary) -> Dictionary:
	if not bool(sample_a.get("ready", false)) or not bool(sample_b.get("ready", false)):
		return {}
	var component_id_a: int = int(sample_a.get("cavity_component_id", 0))
	var component_id_b: int = int(sample_b.get("cavity_component_id", 0))
	if component_id_a <= 0 or component_id_a != component_id_b:
		return {}
	return {
		"mountain_id": int(sample_a.get("mountain_id", 0)),
		"cavity_component_id": component_id_a,
	}

func _sample_mountain_tile(tile_coord: Vector2i, streamer: WorldStreamer) -> Dictionary:
	return streamer.get_mountain_visibility_sample(tile_coord)
