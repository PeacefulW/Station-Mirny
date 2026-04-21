class_name MountainEntrance
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

static func recompute_entrance_flag(world_tile: Vector2i, streamer: WorldStreamer) -> bool:
	var tile_state: Dictionary = streamer._get_entrance_tile_state(world_tile)
	if not bool(tile_state.get("ready", false)):
		return false
	var mountain_flags: int = int(tile_state.get("mountain_flags", 0))
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) == 0:
		return false
	var mountain_id: int = int(tile_state.get("mountain_id", 0))
	if mountain_id <= 0:
		return false
	if not bool(tile_state.get("walkable", false)):
		return false

	for offset: Vector2i in [
		Vector2i.ZERO,
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]:
		if offset == Vector2i.ZERO:
			continue
		var neighbor_state: Dictionary = streamer._get_entrance_tile_state(world_tile + offset)
		if not bool(neighbor_state.get("ready", false)):
			continue
		var neighbor_mountain_id: int = int(neighbor_state.get("mountain_id", 0))
		var neighbor_flags: int = int(neighbor_state.get("mountain_flags", 0))
		var neighbor_walkable: bool = bool(neighbor_state.get("walkable", false))
		var neighbor_is_interior: bool = (neighbor_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0
		if neighbor_walkable and (
				neighbor_mountain_id != mountain_id
				or not neighbor_is_interior
		):
			return true
	return false
