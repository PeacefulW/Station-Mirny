class_name MountainEntrance
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

static func recompute_entrance_flag(world_tile: Vector2i, streamer: WorldStreamer) -> bool:
	var tile_state: Dictionary = streamer._get_entrance_tile_state(world_tile)
	if not bool(tile_state.get("ready", false)):
		return false
	var mountain_flags: int = int(tile_state.get("mountain_flags", 0))
	var mountain_id: int = int(tile_state.get("mountain_id", 0))
	if mountain_id <= 0:
		return false
	if not bool(tile_state.get("walkable", false)):
		return false

	for offset: Vector2i in [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]:
		var neighbor_state: Dictionary = streamer._get_entrance_tile_state(world_tile + offset)
		if not bool(neighbor_state.get("ready", false)):
			continue
		var neighbor_mountain_id: int = int(neighbor_state.get("mountain_id", 0))
		var neighbor_walkable: bool = bool(neighbor_state.get("walkable", false))
		if neighbor_walkable and neighbor_mountain_id == 0:
			return true
	return false

static func can_harvest_mountain_tile(world_tile: Vector2i, streamer: WorldStreamer) -> bool:
	var tile_state: Dictionary = streamer._get_entrance_tile_state(world_tile)
	if not bool(tile_state.get("ready", false)):
		return false
	if not streamer._is_diggable_surface_terrain(int(tile_state.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))):
		return false
	for offset: Vector2i in [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]:
		var neighbor_state: Dictionary = streamer._get_entrance_tile_state(world_tile + offset)
		if not bool(neighbor_state.get("ready", false)):
			continue
		if bool(neighbor_state.get("walkable", false)):
			return true
	return false
