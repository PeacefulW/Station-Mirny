extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MountainCavityCache = preload("res://core/systems/world/mountain_cavity_cache.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _tiles: Dictionary = {}
var _failed: bool = false

func _init() -> void:
	_seed_base_ground(Rect2i(-2, -2, 18, 8))
	_seed_mountain_one()
	_seed_mountain_two()
	var cache := MountainCavityCache.new()
	var candidate_tiles: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(2, 0),
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
	var wide_opening: Dictionary = cache.get_sample(Vector2i(2, 0), Callable(self, "_sample_tile"))
	var first_floor: Dictionary = cache.get_sample(Vector2i(1, 1), Callable(self, "_sample_tile"))
	var second_opening: Dictionary = cache.get_sample(Vector2i(5, 0), Callable(self, "_sample_tile"))
	var other_mountain_opening: Dictionary = cache.get_sample(Vector2i(11, 0), Callable(self, "_sample_tile"))

	_assert(bool(first_opening.get("is_opening", false)), "first mouth should be opening")
	_assert(bool(wide_opening.get("is_opening", false)), "wide mouth neighbour should be a real opening")
	_assert(int(first_opening.get("component_id", 0)) > 0, "first mouth should belong to a component")
	_assert(int(wide_opening.get("component_id", 0)) == int(first_opening.get("component_id", 0)), "wide mouth tiles should share the real cavity component")
	_assert(int(first_floor.get("component_id", 0)) == int(first_opening.get("component_id", 0)), "first cavity floor should share component")
	_assert(int(second_opening.get("component_id", 0)) > 0, "second mouth should belong to a component")
	_assert(int(second_opening.get("component_id", 0)) != int(first_opening.get("component_id", 0)), "separate cavity should stay isolated")
	_assert(int(other_mountain_opening.get("mountain_id", 0)) == 2, "second mountain should keep independent ownership")
	_assert(int(other_mountain_opening.get("component_id", 0)) > 0, "foot-band mouth should still become a component")
	_assert(bool(other_mountain_opening.get("is_opening", false)), "foot-band mouth should still count as opening")

	var outside_mask: PackedByteArray = cache.build_chunk_visibility_mask(Vector2i.ZERO, 0)
	_assert(_mask_has_tile(outside_mask, Vector2i(1, 0)), "outside should show first opening")
	_assert(_mask_has_tile(outside_mask, Vector2i(2, 0)), "outside should show the full multi-tile mouth")
	_assert(_mask_has_tile(outside_mask, Vector2i(5, 0)), "outside should show second opening")
	_assert(_mask_has_tile(outside_mask, Vector2i(11, 0)), "outside should show other mountain opening")
	_assert(not _mask_has_tile(outside_mask, Vector2i(0, 0)), "outside must not synthesize a side arch around the mouth")
	_assert(not _mask_has_tile(outside_mask, Vector2i(0, 1)), "outside must not synthesize a deeper opening shell")
	_assert(not _mask_has_tile(outside_mask, Vector2i(1, 1)), "outside should hide cavity interior")

	var inside_first_mask: PackedByteArray = cache.build_chunk_visibility_mask(
		Vector2i.ZERO,
		int(first_opening.get("component_id", 0))
	)
	_assert(_mask_has_tile(inside_first_mask, Vector2i(1, 0)), "inside should show current opening tile")
	_assert(_mask_has_tile(inside_first_mask, Vector2i(2, 0)), "inside should keep the full real mouth visible")
	_assert(_mask_has_tile(inside_first_mask, Vector2i(1, 1)), "inside should show current cavity floor")
	_assert(not _mask_has_tile(inside_first_mask, Vector2i(0, 1)), "inside must not reveal an unmined shell tile")
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
	_assert_runtime_roof_ownership()
	_assert_native_excavation_cutout()

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
	for floor_tile: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(5, 0), Vector2i(5, 1)]:
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

func _assert_runtime_roof_ownership() -> void:
	var view := ChunkView.new()
	view.configure(Vector2i.ZERO)
	view.set_mountain_tile_visuals_enabled(false)
	get_root().add_child(view)
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var local_coord := Vector2i(1, 1)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	mountain_ids[index] = 1
	mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	view.begin_apply({
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": PackedInt32Array(),
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": PackedInt32Array(),
	})
	view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	view.apply_runtime_cell(local_coord, WorldRuntimeConstants.TERRAIN_PLAINS_DUG, 0, true)
	var visible_mask := PackedByteArray()
	visible_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	visible_mask[index] = 1
	view.apply_cover_visibility(visible_mask)
	var render_debug: Dictionary = view.get_cover_render_debug(local_coord, 1, 1)
	_assert(int(render_debug.get("pending_mountain_id", 0)) == 1, "dug terrain must retain immutable mountain roof ownership")
	_assert(not bool(render_debug.get("has_roof_layer", true)), "runtime organic roof must not create square TileMap roof cells")
	_assert(float(render_debug.get("mask_value", 1.0)) < 0.01, "real dug opening should select the excavated native mask")
	var closed_mask := PackedByteArray()
	closed_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	view.apply_cover_visibility(closed_mask)
	var closed_debug: Dictionary = view.get_cover_render_debug(local_coord, 1, 0)
	_assert(float(closed_debug.get("mask_value", 0.0)) > 0.99, "outside state should select the closed native roof mask")
	view.free()

func _assert_native_excavation_cutout() -> void:
	var core: Object = ClassDB.instantiate("WorldCore")
	_assert(core != null, "WorldCore must be available for the native cutout smoke test")
	if core == null:
		return
	var halo_radius: int = 1
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius * 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(halo_side * halo_side)
	solid_halo.fill(1)
	var cutout_halo := PackedByteArray()
	cutout_halo.resize(halo_side * halo_side)
	var cutout_tile := Vector2i(halo_radius + 4, halo_radius + 4)
	for tile_y: int in range(cutout_tile.y - 2, cutout_tile.y + 3):
		for tile_x: int in range(cutout_tile.x - 2, cutout_tile.x + 3):
			var cutout_index: int = tile_y * halo_side + tile_x
			solid_halo[cutout_index] = 0
			cutout_halo[cutout_index] = 1
	var pixels_per_tile: int = 8
	var result: Dictionary = core.call(
		"build_mountain_halo_mask",
		solid_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		pixels_per_tile,
		0.0,
		0.0,
		cutout_halo,
	) as Dictionary
	var mask: PackedByteArray = result.get("mask", PackedByteArray()) as PackedByteArray
	var roof_mask: PackedByteArray = result.get("roof_mask", PackedByteArray()) as PackedByteArray
	var width: int = int(result.get("width", 0))
	var center_x: int = cutout_tile.x * pixels_per_tile + pixels_per_tile / 2
	var center_y: int = cutout_tile.y * pixels_per_tile + pixels_per_tile / 2
	var center_index: int = center_y * width + center_x
	_assert(
		center_index >= 0 and center_index < mask.size(),
		"native cutout center must be inside the returned mask",
	)
	if center_index >= 0 and center_index < mask.size():
		_assert(int(mask[center_index]) == 0, "native contour smoothing must not refill a dug tile center")
		_assert(int(roof_mask[center_index]) > 200, "closed native roof must preserve the pre-excavation surface")
	_assert(int(result.get("cutout_sample_count", 0)) == 25, "native mask must report the full excavated room")
	var closed_visibility := PackedByteArray()
	closed_visibility.resize(halo_side * halo_side)
	var closed_composed: PackedByteArray = core.call(
		"compose_mountain_cover_mask",
		mask,
		roof_mask,
		closed_visibility,
		pixels_per_tile,
	) as PackedByteArray
	var open_composed: PackedByteArray = core.call(
		"compose_mountain_cover_mask",
		mask,
		roof_mask,
		cutout_halo,
		pixels_per_tile,
	) as PackedByteArray
	if center_index >= 0 and center_index < closed_composed.size() and center_index < open_composed.size():
		_assert(int(closed_composed[center_index]) > 200, "outside composition must close the excavated center")
		_assert(int(open_composed[center_index]) == 0, "inside composition must reveal the excavated center")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
