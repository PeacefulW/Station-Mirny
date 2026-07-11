extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainCavityCache = preload("res://core/systems/world/mountain_cavity_cache.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const FIXTURE_WRAP_WIDTH_TILES: int = WorldRuntimeConstants.CHUNK_SIZE * 2
const MOUNTAIN_ID: int = 91

var _tiles: Dictionary = {}
var _failed: bool = false


func _init() -> void:
	# Direct --script entrypoints are parsed before named autoload globals are
	# registered. Defer the WorldStreamer load by one turn for the real project
	# compilation context instead of accepting a false-positive compile abort.
	call_deferred("_run")


func _run() -> void:
	_assert_cache_connects_across_horizontal_wrap()
	_assert_y_and_unbounded_coordinates_do_not_alias()
	_assert_streamer_reads_wrapped_candidate_diffs()
	if _failed:
		quit(1)
		return
	print("mountain_cavity_wrap_smoke_test: OK")
	quit(0)


func _assert_cache_connects_across_horizontal_wrap() -> void:
	_tiles.clear()
	var cache := MountainCavityCache.new()
	cache.configure_horizontal_wrap(FIXTURE_WRAP_WIDTH_TILES)
	var west_floor := Vector2i(0, 4)
	var east_floor := Vector2i(FIXTURE_WRAP_WIDTH_TILES - 1, 4)
	_set_floor(west_floor)
	_set_floor(east_floor)
	cache.on_chunk_loaded(
		WorldRuntimeConstants.tile_to_chunk(east_floor),
		[east_floor],
		Callable(self, "_sample_tile"),
	)
	cache.on_chunk_loaded(
		WorldRuntimeConstants.tile_to_chunk(west_floor),
		[west_floor],
		Callable(self, "_sample_tile"),
	)

	var west: Dictionary = cache.get_sample(west_floor, Callable(self, "_sample_tile"))
	var east: Dictionary = cache.get_sample(east_floor, Callable(self, "_sample_tile"))
	var east_alias: Dictionary = cache.get_sample(Vector2i(-1, 4), Callable(self, "_sample_tile"))
	var component_id: int = int(west.get("component_id", 0))
	_assert(component_id > 0, "west seam floor must belong to a cavity component")
	_assert(int(east.get("component_id", 0)) == component_id, "x=0 and x=width-1 floors must be cardinal neighbors")
	_assert(int(east_alias.get("component_id", 0)) == component_id, "negative X lookup must resolve to the canonical seam tile")

	var chunks: Array[Vector2i] = cache.get_component_chunks(component_id)
	_assert(chunks.has(Vector2i(0, 0)), "wrapped component must retain the west chunk")
	_assert(chunks.has(Vector2i(1, 0)), "wrapped component must retain the east chunk")
	_assert(chunks.size() == 2, "wrapped component must report exactly its two canonical chunks")

	var west_mask: PackedByteArray = cache.build_chunk_component_floor_mask(Vector2i(2, 0), component_id)
	var east_mask: PackedByteArray = cache.build_chunk_component_floor_mask(Vector2i(-1, 0), component_id)
	_assert(_mask_has_local(west_mask, Vector2i(0, 4)), "chunk x=width alias must resolve to west floor membership")
	_assert(_mask_has_local(east_mask, Vector2i(15, 4)), "chunk x=-1 alias must resolve to east floor membership")


func _assert_y_and_unbounded_coordinates_do_not_alias() -> void:
	_tiles.clear()
	var wrapped_cache := MountainCavityCache.new()
	wrapped_cache.configure_horizontal_wrap(FIXTURE_WRAP_WIDTH_TILES)
	var north_floor := Vector2i(5, -1)
	var south_floor := Vector2i(5, 31)
	_set_floor(north_floor)
	_set_floor(south_floor)
	wrapped_cache.on_chunk_loaded(
		WorldRuntimeConstants.tile_to_chunk(north_floor),
		[north_floor],
		Callable(self, "_sample_tile"),
	)
	wrapped_cache.on_chunk_loaded(
		WorldRuntimeConstants.tile_to_chunk(south_floor),
		[south_floor],
		Callable(self, "_sample_tile"),
	)
	var north_id: int = int(wrapped_cache.get_sample(
		north_floor,
		Callable(self, "_sample_tile"),
	).get("component_id", 0))
	var south_id: int = int(wrapped_cache.get_sample(
		south_floor,
		Callable(self, "_sample_tile"),
	).get("component_id", 0))
	_assert(north_id > 0 and south_id > 0 and north_id != south_id, "horizontal wrapping must never alias Y")

	_tiles.clear()
	var unbounded_cache := MountainCavityCache.new()
	unbounded_cache.configure_horizontal_wrap(0)
	var negative_floor := Vector2i(-1, 7)
	var zero_floor := Vector2i(0, 7)
	_set_floor(negative_floor)
	_set_floor(zero_floor)
	unbounded_cache.on_chunk_loaded(
		WorldRuntimeConstants.tile_to_chunk(negative_floor),
		[negative_floor],
		Callable(self, "_sample_tile"),
	)
	unbounded_cache.on_chunk_loaded(
		WorldRuntimeConstants.tile_to_chunk(zero_floor),
		[zero_floor],
		Callable(self, "_sample_tile"),
	)
	var negative_id: int = int(unbounded_cache.get_sample(
		negative_floor,
		Callable(self, "_sample_tile"),
	).get("component_id", 0))
	var zero_id: int = int(unbounded_cache.get_sample(
		zero_floor,
		Callable(self, "_sample_tile"),
	).get("component_id", 0))
	_assert(negative_id > 0 and negative_id == zero_id, "width 0 must preserve ordinary negative-coordinate adjacency")


func _assert_streamer_reads_wrapped_candidate_diffs() -> void:
	var world_streamer_script: Script = load("res://core/systems/world/world_streamer.gd")
	_assert(world_streamer_script != null, "WorldStreamer script must compile under Godot 4.7")
	if world_streamer_script == null:
		return
	_assert(world_streamer_script.can_instantiate(), "WorldStreamer script must be valid and instantiable")
	if not world_streamer_script.can_instantiate():
		return
	var streamer: Node = world_streamer_script.new() as Node
	_assert(streamer != null, "WorldStreamer script must instantiate")
	if streamer == null:
		return
	var bounds := WorldBoundsSettings.hard_coded_defaults()
	streamer.world_version = WorldRuntimeConstants.WORLD_VERSION
	streamer._apply_worldgen_settings(
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
	)
	_assert(
		streamer._mountain_cavity_cache._horizontal_wrap_width_tiles == bounds.width_tiles,
		"WorldStreamer settings must configure the cavity graph with finite X width",
	)

	var last_chunk_x: int = bounds.get_width_chunks() - 1
	var east_local := Vector2i(WorldRuntimeConstants.CHUNK_SIZE - 1, 6)
	streamer._diff_store.set_tile_override(
		Vector2i(last_chunk_x, 0),
		east_local,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		true,
	)
	# Y remains unbounded in the candidate ring and must keep its raw chunk key.
	streamer._diff_store.set_tile_override(
		Vector2i(0, -1),
		Vector2i(2, WorldRuntimeConstants.CHUNK_SIZE - 1),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		true,
	)
	var candidates: Array[Vector2i] = streamer._collect_cover_candidate_tiles_for_chunk(Vector2i.ZERO)
	_assert(
		candidates.has(Vector2i(bounds.width_tiles - 1, east_local.y)),
		"published chunk x=0 must read DiffStore candidates from canonical last chunk",
	)
	_assert(candidates.has(Vector2i(2, -1)), "candidate lookup must not wrap or clamp Y")
	_assert(not candidates.has(Vector2i(-1, east_local.y)), "candidate list must expose canonical X tile keys only")
	streamer.free()


func _set_floor(world_tile: Vector2i) -> void:
	_tiles[world_tile] = {
		"ready": true,
		"mountain_id": MOUNTAIN_ID,
		"mountain_flags": WorldRuntimeConstants.MOUNTAIN_FLAG_WALL,
		"walkable": true,
	}


func _sample_tile(world_tile: Vector2i) -> Dictionary:
	return (_tiles.get(world_tile, {
		"ready": true,
		"mountain_id": 0,
		"mountain_flags": 0,
		"walkable": true,
	}) as Dictionary).duplicate(true)


func _mask_has_local(mask: PackedByteArray, local_coord: Vector2i) -> bool:
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	return index >= 0 and index < mask.size() and mask[index] != 0


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
