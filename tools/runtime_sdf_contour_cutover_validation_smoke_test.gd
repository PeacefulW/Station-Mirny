extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

const CONTOUR_SMOKE_DIFF_REVISION: int = 31
const CONTOUR_SMOKE_OUTPUT_SIZE_PX: int = 64
const CUTOVER_TERRAIN_IDS: Array[int] = [
	WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
	WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED,
	WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
	WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
	WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
]

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	if _failed:
		quit(1)
		return

	_assert_contour_recipes_use_exported_assets()
	_assert_cutover_ids_have_no_active_tilemap_sources()
	_assert_active_worker_request_skips_water_surface_result()
	await _assert_legacy_blocked_participates_in_mountain_contour_halo()
	await _assert_chunk_view_never_renders_cutover_tilemap_cells()
	await _assert_legacy_blocked_creates_mountain_contour_bucket()

	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_cutover_validation_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var registry_source: String = FileAccess.get_file_as_string("res://core/systems/world/terrain_presentation_registry.gd")
	_assert(
		registry_source.contains("CONTOUR_CUTOVER_TERRAIN_IDS"),
		"TerrainPresentationRegistry must own the contour cutover terrain id set."
	)
	_assert(
		registry_source.contains("func is_contour_cutover_terrain"),
		"TerrainPresentationRegistry must expose contour cutover terrain classification."
	)
	_assert(
		registry_source.contains("func get_tilemap_terrain_ids_for_layer"),
		"TerrainPresentationRegistry must expose TileMap-only terrain ids excluding contour cutover ids."
	)

	var tile_set_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_tile_set_factory.gd")
	_assert(
		tile_set_source.contains("get_tilemap_terrain_ids_for_layer"),
		"WorldTileSetFactory must build TileSet sources only from TileMap-eligible terrain ids."
	)
	_assert(
		tile_set_source.contains("func has_tilemap_source_for_terrain"),
		"WorldTileSetFactory must expose debug readback for active TileMap source ownership."
	)

	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	_assert(
		chunk_view_source.contains("TerrainPresentationRegistry.is_contour_cutover_terrain"),
		"ChunkView must use the registry-owned contour cutover terrain id set."
	)
	_assert(
		chunk_view_source.contains("Cutover terrain ids are never allowed to fall back to TileMap rendering."),
		"ChunkView must document the no-fallback cutover guard in its active cell apply path."
	)
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("_build_constant_contour_result") \
			and streamer_source.contains("_is_contour_solid_mask_empty") \
			and streamer_source.contains("_is_contour_solid_mask_full"),
		"WorldStreamer contour worker must fast-path empty/full masks instead of sending trivial chunks through native SDF sampling."
	)
	_assert(
		streamer_source.contains("CONTOUR_WORKER_THREAD_COUNT") \
			and streamer_source.contains("_contour_worker_threads") \
			and streamer_source.contains("_has_contour_worker_threads_running"),
		"WorldStreamer contour scheduling must use a bounded worker pool instead of a single serialized contour worker."
	)
	var contour_field_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_contour_field.cpp")
	_assert(
		contour_field_source.contains("mask_rgba8.ptrw()") \
			and contour_field_source.contains("height_r16.ptrw()") \
			and contour_field_source.contains("normal_rgba8.ptrw()") \
			and contour_field_source.contains("collision_sdf_f32.ptrw()"),
		"Runtime contour field output buffers must use direct PackedArray writes instead of per-pixel Variant set() calls."
	)

func _assert_contour_recipes_use_exported_assets() -> void:
	var ground_source: String = TerrainPresentationRegistry.get_contour_recipe_source_for_class(
		WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE
	)
	var mountain_source: String = TerrainPresentationRegistry.get_contour_recipe_source_for_class(
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	_assert(
		ground_source.begins_with("res://assets/textures/terrain/ground/"),
		"Ground contour recipe must use the exported ground recipe folder, not the generator reference fallback."
	)
	_assert(
		mountain_source.begins_with("res://assets/textures/terrain/mountains/"),
		"Mountain contour recipe must use the exported mountain recipe folder, not the generator reference fallback."
	)

func _assert_cutover_ids_have_no_active_tilemap_sources() -> void:
	var registry := TerrainPresentationRegistry.new()
	var tile_set_factory := WorldTileSetFactory.new()
	for terrain_id: int in CUTOVER_TERRAIN_IDS:
		_assert(
			bool(registry.call("is_contour_cutover_terrain", terrain_id)),
			"Terrain id %d must be classified as contour cutover terrain." % terrain_id
		)
		_assert(
			not bool(tile_set_factory.call("has_tilemap_source_for_terrain", terrain_id)),
			"Contour cutover terrain id %d must not own an active TileMap source." % terrain_id
		)
	_assert(
		WorldTileSetFactory.get_roof_source_id(WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL) < 0,
		"Mountain wall must not expose an active roof TileMap source after contour cutover."
	)
	_assert(
		WorldTileSetFactory.get_roof_source_id(WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT) < 0,
		"Mountain foot must not expose an active roof TileMap source after contour cutover."
	)

func _assert_active_worker_request_skips_water_surface_result() -> void:
	var streamer := WorldStreamer.new()
	streamer._chunk_packets[Vector2i.ZERO] = _build_single_legacy_blocked_packet()
	var request: Dictionary = streamer._build_contour_worker_request(Vector2i.ZERO)
	var contour_classes: Array = request.get("contour_classes", []) as Array
	_assert(
		contour_classes.has(WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE),
		"Active contour worker requests must compute ground_surface results."
	)
	_assert(
		contour_classes.has(WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS),
		"Active contour worker requests must compute mountain_mass results."
	)
	_assert(
		not contour_classes.has(WorldRuntimeConstants.CONTOUR_CLASS_WATER_SURFACE),
		"Iteration 07 must not block chunk readiness on an independent water_surface contour result."
	)
	streamer.free()

func _assert_legacy_blocked_participates_in_mountain_contour_halo() -> void:
	var streamer := WorldStreamer.new()
	root.add_child(streamer)
	await process_frame
	streamer.world_seed = 1001
	streamer._chunk_packets[Vector2i.ZERO] = _build_single_legacy_blocked_packet()
	var halo: Dictionary = streamer.get_contour_halo_debug_state(
		Vector2i.ZERO,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	_assert(bool(halo.get("ready", false)), "Mountain halo debug state must be ready for loaded legacy blocked packet data.")
	var side: int = int(halo.get("halo_side", 0))
	var local_coord := Vector2i(4, 4)
	var halo_index: int = (local_coord.y + WorldRuntimeConstants.CONTOUR_HALO_TILES) * side \
		+ local_coord.x + WorldRuntimeConstants.CONTOUR_HALO_TILES
	var solid_mask: PackedByteArray = halo.get("solid_mask_with_halo", PackedByteArray()) as PackedByteArray
	var class_mask: PackedByteArray = halo.get("contour_class_mask_with_halo", PackedByteArray()) as PackedByteArray
	_assert(
		halo_index >= 0 and halo_index < solid_mask.size(),
		"Legacy blocked halo sample index must stay inside the mountain solid mask."
	)
	if halo_index >= 0 and halo_index < solid_mask.size() and halo_index < class_mask.size():
		_assert(
			solid_mask[halo_index] == 1,
			"Legacy blocked terrain must be solid in the mountain_mass contour halo."
		)
		_assert(
			class_mask[halo_index] == WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_CODE,
			"Legacy blocked terrain must classify as mountain in the contour class mask."
		)
	streamer._stop_contour_worker()
	streamer._packet_backend.stop()
	streamer.queue_free()
	await process_frame

func _assert_chunk_view_never_renders_cutover_tilemap_cells() -> void:
	var chunk_view := ChunkView.new()
	root.add_child(chunk_view)
	chunk_view.configure(Vector2i.ZERO)
	chunk_view.begin_apply(_build_cutover_packet())
	while chunk_view.apply_next_batch(32):
		pass
	var state_without_contour: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(
		int(state_without_contour.get("target_tilemap_apply_count", -1)) == 0,
		"ChunkView must not apply target cutover terrain ids through TileMap when contour rendering is disabled."
	)
	_assert(
		int(state_without_contour.get("target_tilemap_cell_count", -1)) == 0,
		"ChunkView must not leave active TileMap cells for target cutover terrain ids."
	)

	chunk_view.set_contour_rendering_enabled(true)
	chunk_view.begin_apply(_build_cutover_packet())
	while chunk_view.apply_next_batch(32):
		pass
	var state_with_contour: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(
		int(state_with_contour.get("target_tilemap_apply_count", -1)) == 0,
		"Contour-enabled ChunkView must not apply target terrain ids through TileMap."
	)
	_assert(
		int(state_with_contour.get("target_tilemap_cell_count", -1)) == 0,
		"Contour-enabled ChunkView must not retain target terrain TileMap cells."
	)

	chunk_view.queue_free()
	await process_frame

func _assert_legacy_blocked_creates_mountain_contour_bucket() -> void:
	var chunk_view := ChunkView.new()
	root.add_child(chunk_view)
	chunk_view.configure(Vector2i.ZERO)
	chunk_view.set_contour_rendering_enabled(true)
	chunk_view.begin_apply(_build_single_legacy_blocked_packet())
	while chunk_view.apply_next_batch(32):
		pass
	var fresh_results: Dictionary = {
		WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE: _build_contour_result(
			WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE
		),
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: _build_contour_result(
			WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
		),
	}
	chunk_view.apply_contour_results(fresh_results, CONTOUR_SMOKE_DIFF_REVISION)
	var state: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(bool(state.get("ready", false)), "Fresh ground and mountain results must make legacy blocked chunk render-ready.")
	_assert(
		int(state.get("mountain_bucket_count", 0)) == 1,
		"Legacy blocked cutover terrain must create a mountain contour bucket instead of a black cutover hole."
	)
	var buckets: Array = state.get("mountain_buckets", []) as Array
	if not buckets.is_empty():
		var first_bucket: Dictionary = buckets[0] as Dictionary
		_assert(
			int(first_bucket.get("mountain_id", 0)) == -1,
			"Legacy blocked cutover terrain without native mountain ids must use the fallback mountain contour bucket."
		)
	chunk_view.queue_free()
	await process_frame

func _build_cutover_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var terrain_atlas_indices := PackedInt32Array()
	var walkable_flags := PackedByteArray()
	var lake_flags := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	var mountain_atlas_indices := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var terrain_id: int = CUTOVER_TERRAIN_IDS[index % CUTOVER_TERRAIN_IDS.size()]
		terrain_ids[index] = terrain_id
		terrain_atlas_indices[index] = index % 47
		walkable_flags[index] = 1 if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_GROUND \
			or terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG else 0
		if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
				or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
			mountain_ids[index] = 1
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT \
				if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
				else WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	return {
		"chunk_coord": Vector2i.ZERO,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _build_single_legacy_blocked_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var terrain_atlas_indices := PackedInt32Array()
	var walkable_flags := PackedByteArray()
	var lake_flags := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	var mountain_atlas_indices := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		walkable_flags[index] = 1
	var blocked_index: int = WorldRuntimeConstants.local_to_index(Vector2i(4, 4))
	terrain_ids[blocked_index] = WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED
	walkable_flags[blocked_index] = 0
	return {
		"chunk_coord": Vector2i.ZERO,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _build_contour_result(contour_class: StringName) -> Dictionary:
	return {
		"chunk_coord": Vector2i.ZERO,
		"contour_class": contour_class,
		"recipe_id": contour_class,
		"diff_revision": CONTOUR_SMOKE_DIFF_REVISION,
		"pixel_size": Vector2i(CONTOUR_SMOKE_OUTPUT_SIZE_PX, CONTOUR_SMOKE_OUTPUT_SIZE_PX),
		"mask_rgba8": _build_byte_buffer(CONTOUR_SMOKE_OUTPUT_SIZE_PX * CONTOUR_SMOKE_OUTPUT_SIZE_PX * 4, 255),
		"height_r16": _build_byte_buffer(CONTOUR_SMOKE_OUTPUT_SIZE_PX * CONTOUR_SMOKE_OUTPUT_SIZE_PX * 2, 127),
		"normal_rgba8": _build_byte_buffer(CONTOUR_SMOKE_OUTPUT_SIZE_PX * CONTOUR_SMOKE_OUTPUT_SIZE_PX * 4, 128),
		"collision_sdf_f32": PackedFloat32Array(),
		"collision_origin_world_px": Vector2i.ZERO,
		"collision_sample_px": 4,
		"collision_size": Vector2i(17, 17),
		"collision_blocks_inside": contour_class == WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
		"ready": true,
	}

func _build_byte_buffer(size: int, value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size)
	bytes.fill(value)
	return bytes

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
