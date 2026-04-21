extends SceneTree

const HarvestQuery = preload("res://core/systems/world/harvest_query.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _tiles: Dictionary = {}
var _failed: bool = false

func _init() -> void:
	_seed_default_walkable(Rect2i(-1, -1, 8, 8))

	_set_tile(Vector2i(3, 3), false, true)
	for sealed_neighbor: Vector2i in [Vector2i(3, 2), Vector2i(4, 3), Vector2i(3, 4), Vector2i(2, 3)]:
		_set_tile(sealed_neighbor, false, false)
	_assert(
		not HarvestQuery.is_tile_orthogonally_exposed(Vector2i(3, 3), Callable(self, "_sample_tile")),
		"sealed rock tile should not be harvestable through diagonal-only contact"
	)

	_set_tile(Vector2i(5, 3), false, true)
	_set_tile(Vector2i(5, 2), true, false)
	_assert(
		HarvestQuery.is_tile_orthogonally_exposed(Vector2i(5, 3), Callable(self, "_sample_tile")),
		"rock tile with one orthogonal walkable face should stay harvestable"
	)

	_set_tile(Vector2i(1, 0), false, true)
	_set_tile(Vector2i(2, 0), false, true)
	var nearest_target: Vector2 = HarvestQuery.find_target_on_ray(
		WorldRuntimeConstants.tile_to_world_center(Vector2i.ZERO),
		WorldRuntimeConstants.tile_to_world_center(Vector2i(3, 0)),
		Callable(self, "_has_resource_at_world"),
		Callable(self, "_is_walkable_at_world")
	)
	_assert(
		nearest_target == WorldRuntimeConstants.tile_to_world_center(Vector2i(1, 0)),
		"harvest ray should stop on the nearest diggable tile"
	)

	_set_tile(Vector2i(1, 0), false, false)
	_set_tile(Vector2i(0, 1), false, false)
	_set_tile(Vector2i(1, 1), false, true)
	_set_tile(Vector2i(2, 1), true, false)
	var blocked_corner_target: Vector2 = HarvestQuery.find_target_on_ray(
		WorldRuntimeConstants.tile_to_world_center(Vector2i.ZERO),
		WorldRuntimeConstants.tile_to_world_center(Vector2i(1, 1)),
		Callable(self, "_has_resource_at_world"),
		Callable(self, "_is_walkable_at_world")
	)
	_assert(
		blocked_corner_target == Vector2.INF,
		"harvest ray should not dig through a blocking corner tile"
	)

	if _failed:
		quit(1)
		return
	print("harvest_gate_smoke_test: OK")
	quit(0)

func _seed_default_walkable(rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			_tiles[Vector2i(x, y)] = _make_tile(true, false)

func _set_tile(world_tile: Vector2i, walkable: bool, resource: bool) -> void:
	_tiles[world_tile] = _make_tile(walkable, resource)

func _make_tile(walkable: bool, resource: bool) -> Dictionary:
	return {
		"ready": true,
		"walkable": walkable,
		"resource": resource,
	}

func _sample_tile(world_tile: Vector2i) -> Dictionary:
	return (_tiles.get(world_tile, _make_tile(true, false)) as Dictionary).duplicate(true)

func _has_resource_at_world(world_pos: Vector2) -> bool:
	var world_tile: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	var tile_data: Dictionary = _sample_tile(world_tile)
	return bool(tile_data.get("resource", false)) \
		and HarvestQuery.is_tile_orthogonally_exposed(world_tile, Callable(self, "_sample_tile"))

func _is_walkable_at_world(world_pos: Vector2) -> bool:
	var world_tile: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	return bool(_sample_tile(world_tile).get("walkable", false))

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
