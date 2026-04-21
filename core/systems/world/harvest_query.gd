class_name HarvestQuery
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

static func is_tile_orthogonally_exposed(world_tile: Vector2i, sample_tile: Callable) -> bool:
	for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var neighbor_data: Dictionary = sample_tile.call(world_tile + offset) as Dictionary
		if not bool(neighbor_data.get("ready", false)):
			continue
		if bool(neighbor_data.get("walkable", false)):
			return true
	return false

static func find_target_on_ray(
	start_world: Vector2,
	end_world: Vector2,
	has_resource_at_world: Callable,
	is_walkable_at_world: Callable
) -> Vector2:
	var ray_tiles: Array[Vector2i] = build_ray_tiles(start_world, end_world)
	for index: int in range(ray_tiles.size()):
		var tile_center: Vector2 = WorldRuntimeConstants.tile_to_world_center(ray_tiles[index])
		if has_resource_at_world.call(tile_center):
			return tile_center
		if index > 0 and not is_walkable_at_world.call(tile_center):
			return Vector2.INF
	return Vector2.INF

static func build_ray_tiles(start_world: Vector2, end_world: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start_tile: Vector2i = WorldRuntimeConstants.world_to_tile(start_world)
	var end_tile: Vector2i = WorldRuntimeConstants.world_to_tile(end_world)
	_append_ray_tile(result, start_tile)
	if start_tile == end_tile:
		return result
	var delta: Vector2 = end_world - start_world
	var step_x: int = 1 if delta.x > 0.0 else (-1 if delta.x < 0.0 else 0)
	var step_y: int = 1 if delta.y > 0.0 else (-1 if delta.y < 0.0 else 0)
	var tile_size: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	var t_delta_x: float = INF if step_x == 0 else absf(tile_size / delta.x)
	var t_delta_y: float = INF if step_y == 0 else absf(tile_size / delta.y)
	var next_boundary_x: float = float(start_tile.x + (1 if step_x > 0 else 0)) * tile_size
	var next_boundary_y: float = float(start_tile.y + (1 if step_y > 0 else 0)) * tile_size
	var t_max_x: float = INF if step_x == 0 else (next_boundary_x - start_world.x) / delta.x
	var t_max_y: float = INF if step_y == 0 else (next_boundary_y - start_world.y) / delta.y
	var current_tile: Vector2i = start_tile
	var max_steps: int = absi(end_tile.x - start_tile.x) + absi(end_tile.y - start_tile.y) + 4
	for _step: int in range(max_steps):
		if current_tile == end_tile:
			break
		if step_x != 0 and step_y != 0 and is_equal_approx(t_max_x, t_max_y):
			_append_ray_tile(result, current_tile + Vector2i(step_x, 0))
			_append_ray_tile(result, current_tile + Vector2i(0, step_y))
			current_tile += Vector2i(step_x, step_y)
			t_max_x += t_delta_x
			t_max_y += t_delta_y
			_append_ray_tile(result, current_tile)
			continue
		if t_max_x < t_max_y:
			current_tile += Vector2i(step_x, 0)
			t_max_x += t_delta_x
		else:
			current_tile += Vector2i(0, step_y)
			t_max_y += t_delta_y
		_append_ray_tile(result, current_tile)
	return result

static func _append_ray_tile(result: Array[Vector2i], world_tile: Vector2i) -> void:
	if result.is_empty() or result[result.size() - 1] != world_tile:
		result.append(world_tile)
