extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MountainCavityCache = preload("res://core/systems/world/mountain_cavity_cache.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

var _tiles: Dictionary = {}
var _failed: bool = false

func _init() -> void:
	_seed_base_ground(Rect2i(-2, -2, 18, 8))
	_seed_mountain_one()
	_seed_mountain_two()
	var cache := MountainCavityCache.new()
	var candidate_tiles: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(5, 0),
		Vector2i(5, 1),
		Vector2i(11, 0),
	]
	var load_result: Dictionary = cache.on_chunk_loaded(
		Vector2i.ZERO,
		candidate_tiles,
		Callable(self, "_sample_tile")
	)
	_assert(not load_result.is_empty(), "chunk load should return affected chunks")

	var first_opening: Dictionary = cache.get_sample(Vector2i(1, 0), Callable(self, "_sample_tile"))
	var first_floor: Dictionary = cache.get_sample(Vector2i(1, 1), Callable(self, "_sample_tile"))
	var second_opening: Dictionary = cache.get_sample(Vector2i(5, 0), Callable(self, "_sample_tile"))
	var other_mountain_opening: Dictionary = cache.get_sample(Vector2i(11, 0), Callable(self, "_sample_tile"))

	_assert(bool(first_opening.get("is_opening", false)), "first mouth should be opening")
	_assert(int(first_opening.get("component_id", 0)) > 0, "first mouth should belong to a component")
	_assert(int(first_floor.get("component_id", 0)) == int(first_opening.get("component_id", 0)), "first cavity floor should share component")
	_assert(int(second_opening.get("component_id", 0)) > 0, "second mouth should belong to a component")
	_assert(int(second_opening.get("component_id", 0)) != int(first_opening.get("component_id", 0)), "separate cavity should stay isolated")
	_assert(int(other_mountain_opening.get("mountain_id", 0)) == 2, "second mountain should keep independent ownership")
	_assert(int(other_mountain_opening.get("component_id", 0)) > 0, "foot-band mouth should still become a component")
	_assert(bool(other_mountain_opening.get("is_opening", false)), "foot-band mouth should still count as opening")

	var outside_mask: PackedByteArray = cache.build_chunk_visibility_mask(Vector2i.ZERO, 0)
	_assert(_mask_has_tile(outside_mask, Vector2i(1, 0)), "outside should show first opening")
	_assert(_mask_has_tile(outside_mask, Vector2i(5, 0)), "outside should show second opening")
	_assert(_mask_has_tile(outside_mask, Vector2i(11, 0)), "outside should show other mountain opening")
	_assert(_mask_has_tile(outside_mask, Vector2i(0, 0)), "outside should show immediate opening shell")
	_assert(not _mask_has_tile(outside_mask, Vector2i(0, 1)), "outside should hide next-cell shell beyond the mouth")
	_assert(not _mask_has_tile(outside_mask, Vector2i(1, 1)), "outside should hide cavity interior")

	var inside_first_mask: PackedByteArray = cache.build_chunk_visibility_mask(
		Vector2i.ZERO,
		int(first_opening.get("component_id", 0))
	)
	_assert(_mask_has_tile(inside_first_mask, Vector2i(1, 0)), "inside should show current opening tile")
	_assert(_mask_has_tile(inside_first_mask, Vector2i(1, 1)), "inside should show current cavity floor")
	_assert(_mask_has_tile(inside_first_mask, Vector2i(0, 1)), "inside should show canonical shell near cavity")
	_assert(_mask_has_tile(inside_first_mask, Vector2i(5, 0)), "inside should keep foreign real mouth visible")
	_assert(_mask_has_tile(inside_first_mask, Vector2i(11, 0)), "inside should keep other mountain mouth visible")
	_assert(not _mask_has_tile(inside_first_mask, Vector2i(5, 1)), "inside should still hide foreign cavity floor")

	_set_floor(
		Vector2i(2, 2),
		1,
		WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR | WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	)
	cache.on_tile_dug(Vector2i(2, 2), Callable(self, "_sample_tile"))
	var diagonal_only: Dictionary = cache.get_sample(Vector2i(2, 2), Callable(self, "_sample_tile"))
	_assert(int(diagonal_only.get("component_id", 0)) > 0, "diagonal dig should create a component")
	_assert(int(diagonal_only.get("component_id", 0)) != int(first_opening.get("component_id", 0)), "diagonal-only contact must not connect cavities")

	for bridge_tile: Vector2i in [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]:
		_set_floor(
			bridge_tile,
			1,
			WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR | WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
		)
		cache.on_tile_dug(bridge_tile, Callable(self, "_sample_tile"))

	var merged_left: Dictionary = cache.get_sample(Vector2i(1, 1), Callable(self, "_sample_tile"))
	var merged_right: Dictionary = cache.get_sample(Vector2i(5, 1), Callable(self, "_sample_tile"))
	_assert(int(merged_left.get("component_id", 0)) == int(merged_right.get("component_id", 0)), "orthogonal bridge should merge cavities")

	var merged_mask: PackedByteArray = cache.build_chunk_visibility_mask(
		Vector2i.ZERO,
		int(merged_left.get("component_id", 0))
	)
	_assert(_mask_has_tile(merged_mask, Vector2i(5, 1)), "merged cavity should reveal right-side floor")
	_assert(_mask_has_tile(merged_mask, Vector2i(11, 0)), "merged cavity should still keep other mountain mouth visible")
	_assert_roof_tileset_mapping()

	if _failed:
		quit(1)
		return
	print("mountain_cover_cache_smoke_test: OK")
	quit(0)

func _seed_base_ground(rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			_tiles[Vector2i(x, y)] = _make_tile(0, 0, true)

func _seed_mountain_one() -> void:
	for y: int in range(0, 3):
		for x: int in range(0, 7):
			_tiles[Vector2i(x, y)] = _make_tile(
				1,
				WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR | WorldRuntimeConstants.MOUNTAIN_FLAG_WALL,
				false
			)
	for floor_tile: Vector2i in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(5, 0), Vector2i(5, 1)]:
		_set_floor(
			floor_tile,
			1,
			WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR | WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
		)

func _seed_mountain_two() -> void:
	for y: int in range(0, 2):
		for x: int in range(10, 13):
			_tiles[Vector2i(x, y)] = _make_tile(2, WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT, false)
	_tiles[Vector2i(11, 0)] = _make_tile(2, WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT, true)

func _set_floor(world_tile: Vector2i, mountain_id: int, mountain_flags: int) -> void:
	_tiles[world_tile] = _make_tile(mountain_id, mountain_flags, true)

func _make_tile(mountain_id: int, mountain_flags: int, walkable: bool) -> Dictionary:
	return {
		"ready": true,
		"mountain_id": mountain_id,
		"mountain_flags": mountain_flags,
		"walkable": walkable,
	}

func _sample_tile(world_tile: Vector2i) -> Dictionary:
	return (_tiles.get(world_tile, _make_tile(0, 0, true)) as Dictionary).duplicate(true)

func _mask_has_tile(mask: PackedByteArray, world_tile: Vector2i) -> bool:
	var index: int = WorldRuntimeConstants.local_to_index(WorldRuntimeConstants.tile_to_local(world_tile))
	return index >= 0 and index < mask.size() and mask[index] != 0

func _assert_roof_tileset_mapping() -> void:
	var view := ChunkView.new()
	view.configure(Vector2i.ZERO)
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_atlas_indices := PackedInt32Array()
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var local_coord := Vector2i(1, 1)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	mountain_ids[index] = 1
	mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	mountain_atlas_indices[index] = 7
	view.begin_apply({
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": PackedInt32Array(),
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	})
	view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var render_debug: Dictionary = view.get_cover_render_debug(local_coord, 1, 0)
	_assert(int(render_debug.get("roof_terrain_id", -1)) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT, "roof layer should keep mountain foot terrain id")
	_assert(int(render_debug.get("roof_cell_source_id", -1)) == WorldTileSetFactory.get_roof_source_id(WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT), "roof layer should use dedicated mountain foot roof source id")
	_assert((render_debug.get("roof_cell_atlas_coords", Vector2i(-1, -1)) as Vector2i) == WorldTileSetFactory.get_atlas_coords(WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT, 7), "roof layer should preserve mountain foot atlas coords")
	view.free()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
