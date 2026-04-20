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
	var current_sample_mountain_id: int = int(current_sample.get("mountain_id", 0))
	var current_sample_mountain_flags: int = int(current_sample.get("mountain_flags", 0))
	var doorway_fallback_used: bool = false
	if current_sample_mountain_id > 0 \
			and (current_sample_mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0:
		current_mountain_id = current_sample_mountain_id
	if current_mountain_id == 0 \
			and current_sample_mountain_id == 0 \
			and _should_use_doorway_fallback(tile_coord, streamer):
		current_mountain_id = _fallback_interior_cross(tile_coord, streamer)
		doorway_fallback_used = current_mountain_id > 0
	var last_mountain_id_before_update: int = _last_mountain_id
	_debug_snapshot = {
		"ready": true,
		"tile_coord": tile_coord,
		"sample_mountain_id": current_sample_mountain_id,
		"sample_mountain_flags": current_sample_mountain_flags,
		"resolved_mountain_id": current_mountain_id,
		"last_mountain_id_before_update": last_mountain_id_before_update,
		"doorway_fallback_used": doorway_fallback_used,
	}
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
	if _paired_interior_mountain_id(north, south) > 0:
		return true
	var east: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.RIGHT, streamer)
	var west: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.LEFT, streamer)
	return _paired_interior_mountain_id(east, west) > 0

func _fallback_interior_cross(tile_coord: Vector2i, streamer: WorldStreamer) -> int:
	var north: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.UP, streamer)
	var south: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.DOWN, streamer)
	var ns_match: int = _paired_interior_mountain_id(north, south)
	if ns_match > 0:
		return ns_match
	var east: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.RIGHT, streamer)
	var west: Dictionary = _sample_mountain_tile(tile_coord + Vector2i.LEFT, streamer)
	var ew_match: int = _paired_interior_mountain_id(east, west)
	if ew_match > 0:
		return ew_match
	return 0

func _paired_interior_mountain_id(sample_a: Dictionary, sample_b: Dictionary) -> int:
	if not bool(sample_a.get("ready", false)) or not bool(sample_b.get("ready", false)):
		return 0
	var mountain_id_a: int = int(sample_a.get("mountain_id", 0))
	var mountain_id_b: int = int(sample_b.get("mountain_id", 0))
	if mountain_id_a <= 0 or mountain_id_a != mountain_id_b:
		return 0
	var interior_bit: int = WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR
	var is_a_interior: bool = (int(sample_a.get("mountain_flags", 0)) & interior_bit) != 0
	var is_b_interior: bool = (int(sample_b.get("mountain_flags", 0)) & interior_bit) != 0
	if not is_a_interior or not is_b_interior:
		return 0
	return mountain_id_a

func _sample_mountain_tile(tile_coord: Vector2i, streamer: WorldStreamer) -> Dictionary:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var packet: Dictionary = streamer.get_chunk_packet(chunk_coord)
	if packet.is_empty():
		return {"ready": false}
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= mountain_ids.size() or index >= mountain_flags.size():
		return {"ready": false}
	return {
		"ready": true,
		"mountain_id": int(mountain_ids[index]),
		"mountain_flags": int(mountain_flags[index]),
	}
