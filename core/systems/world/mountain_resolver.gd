class_name MountainResolver
extends RefCounted

const MountainRevealRegistry = preload("res://core/systems/world/mountain_reveal_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const _FOOTPRINT_SAMPLE_OFFSETS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(-12.0, 0.0),
	Vector2(12.0, 0.0),
	Vector2(0.0, -12.0),
	Vector2(0.0, 12.0),
]
const _MIN_INTERIOR_SAMPLE_COUNT: int = 2

var _last_mountain_id: int = 0

func update_from_player_position(
	world_pos: Vector2,
	streamer: WorldStreamer,
	registry: MountainRevealRegistry
) -> void:
	if streamer == null or registry == null:
		return
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	var current_sample: Dictionary = _sample_mountain_tile(tile_coord, streamer)
	if not bool(current_sample.get("ready", false)):
		return
	var current_mountain_id: int = _resolve_interior_footprint_mountain(world_pos, streamer)
	if current_mountain_id == 0 \
			and int(current_sample.get("mountain_id", 0)) == 0 \
			and _should_use_doorway_fallback(tile_coord, streamer):
		current_mountain_id = _fallback_interior_cross(tile_coord, streamer)
	if current_mountain_id == _last_mountain_id:
		return
	if _last_mountain_id > 0:
		registry.request_conceal(_last_mountain_id)
	if current_mountain_id > 0:
		registry.request_reveal(current_mountain_id)
	_last_mountain_id = current_mountain_id

func _resolve_interior_footprint_mountain(world_pos: Vector2, streamer: WorldStreamer) -> int:
	var interior_counts_by_mountain: Dictionary = {}
	for offset: Vector2 in _FOOTPRINT_SAMPLE_OFFSETS:
		var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos + offset)
		var sample: Dictionary = _sample_mountain_tile(tile_coord, streamer)
		if not bool(sample.get("ready", false)):
			continue
		var mountain_id: int = int(sample.get("mountain_id", 0))
		var mountain_flags: int = int(sample.get("mountain_flags", 0))
		if mountain_id <= 0 or (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) == 0:
			continue
		interior_counts_by_mountain[mountain_id] = int(interior_counts_by_mountain.get(mountain_id, 0)) + 1
	var dominant_mountain_id: int = 0
	var dominant_count: int = 0
	for mountain_id_variant: Variant in interior_counts_by_mountain.keys():
		var mountain_id: int = int(mountain_id_variant)
		var count: int = int(interior_counts_by_mountain.get(mountain_id, 0))
		if count > dominant_count:
			dominant_count = count
			dominant_mountain_id = mountain_id
	if dominant_count >= _MIN_INTERIOR_SAMPLE_COUNT:
		return dominant_mountain_id
	return 0

func _should_use_doorway_fallback(tile_coord: Vector2i, streamer: WorldStreamer) -> bool:
	var interior_count: int = 0
	var interior_mountain_ids: Dictionary = {}
	for offset: Vector2i in [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]:
		var sample: Dictionary = _sample_mountain_tile(tile_coord + offset, streamer)
		if not bool(sample.get("ready", false)):
			continue
		var mountain_id: int = int(sample.get("mountain_id", 0))
		var mountain_flags: int = int(sample.get("mountain_flags", 0))
		if mountain_id <= 0 or (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) == 0:
			continue
		interior_count += 1
		interior_mountain_ids[mountain_id] = true
	return interior_count >= 2 and interior_mountain_ids.size() == 1

func _fallback_interior_cross(tile_coord: Vector2i, streamer: WorldStreamer) -> int:
	for offset: Vector2i in [
		Vector2i.ZERO,
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
	]:
		var sample: Dictionary = _sample_mountain_tile(tile_coord + offset, streamer)
		if not bool(sample.get("ready", false)):
			continue
		var mountain_id: int = int(sample.get("mountain_id", 0))
		var mountain_flags: int = int(sample.get("mountain_flags", 0))
		if mountain_id > 0 and (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0:
			return mountain_id
	return 0

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
