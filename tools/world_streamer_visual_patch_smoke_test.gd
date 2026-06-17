extends SceneTree

const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MountainPlateau2DRasterLayer = preload("res://core/systems/world/mountain_plateau_2d_raster_layer.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

const GRASS_INSTANCE_STRIDE: int = 12
const GRASS_MOUNTAIN_CLEARANCE_PX: float = 64.0

var _failed: bool = false

func _init() -> void:
	var source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		source.contains("func _is_loaded_mountain_geometry_surface(sample: Dictionary) -> bool:"),
		"world streamer must keep a dedicated runtime mountain surface helper"
	)
	_assert(
		source.contains("return _uses_mountain_surface_presentation("),
		"runtime mountain surface helper must resolve from current terrain_id"
	)
	_assert(
		not source.contains("func _is_loaded_mountain_geometry_surface(sample: Dictionary) -> bool:\n\tvar mountain_flags"),
		"runtime mountain surface helper must not treat stale mountain_flags as current surface"
	)

	var dug_surface_sample: Dictionary = {
		"terrain_id": WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		"mountain_id": 1,
		"mountain_flags": WorldRuntimeConstants.MOUNTAIN_FLAG_WALL,
	}
	_assert(
		not _is_runtime_mountain_surface(dug_surface_sample),
		"dug tile must not count as mountain surface for runtime autotile adjacency"
	)

	var wall_surface_sample: Dictionary = {
		"terrain_id": WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
		"mountain_id": 1,
		"mountain_flags": WorldRuntimeConstants.MOUNTAIN_FLAG_WALL,
	}
	_assert(
		_is_runtime_mountain_surface(wall_surface_sample),
		"wall tile must count as mountain surface for runtime autotile adjacency"
	)

	var north_wall_tile := Vector2i(2, 1)
	var world_seed: int = 240518
	var variant_index: int = Autotile47.pick_variant(north_wall_tile, world_seed)
	var solid_index: int = Autotile47.build_atlas_index(
		Autotile47.build_signature_code(true, true, true, true, true, true, true, true),
		variant_index
	)
	var open_south_index: int = Autotile47.build_atlas_index(
		Autotile47.build_signature_code(true, true, true, false, false, false, true, true),
		variant_index
	)
	_assert(open_south_index != solid_index, "open inner south edge must not collapse to solid atlas index")
	_assert_loaded_ground_edges_only_against_water()
	_assert_runtime_mountain_ground_patch_disabled()
	_assert_full_mountain_surface_keeps_ground_underlay()
	_assert_grass_scatter_keeps_mountain_clearance()

	if _failed:
		quit(1)
		return
	print("world_streamer_visual_patch_smoke_test: OK")
	quit(0)

func _is_runtime_mountain_surface(sample: Dictionary) -> bool:
	var terrain_id: int = int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	return terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _assert_loaded_ground_edges_only_against_water() -> void:
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("func _is_loaded_water_surface_terrain(terrain_id: int) -> bool:"),
		"WorldStreamer must keep a dedicated helper for water-only ground edge adjacency."
	)
	_assert(
		streamer_source.contains("func _resolve_loaded_ground_atlas_index(tile_coord: Vector2i) -> int:") and
				streamer_source.contains("_is_loaded_water_surface_terrain(") and
				streamer_source.contains("Autotile47.build_signature_code("),
		"Loaded plains ground atlas resolution must derive 47-tile edges from water neighbours."
	)
	_assert(
		not streamer_source.contains("# Ground uses solid atlas variants only"),
		"Loaded plains ground must no longer be forced to solid atlas variants."
	)

func _assert_runtime_mountain_ground_patch_disabled() -> void:
	var layer := MountainPlateau2DRasterLayer.new()
	_assert(
		not layer.is_ground_surface_enabled(),
		"Legacy MountainPlateau2DRasterLayer must not display its raster ground surface by default."
	)
	layer.free()
	var default_preset: Dictionary = MountainPlateau2DRasterLayer.default_preset()
	_assert(
		not bool(default_preset.get("runtime_ground_patch", true)),
		"Legacy mountain raster preset must default runtime_ground_patch to false."
	)
	var backend_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_chunk_packet_backend.gd")
	_assert(
		backend_source.contains("request_preset[\"runtime_ground_patch\"] = false"),
		"Runtime chunk-hit raster requests must force runtime_ground_patch off."
	)
	var layer_source: String = FileAccess.get_file_as_string("res://core/systems/world/mountain_plateau_2d_raster_layer.gd")
	_assert(
		not layer_source.contains("Color(0.36, 0.48, 0.28"),
		"Legacy GDScript mountain raster must not keep the old green detail tint."
	)
	var native_source: String = FileAccess.get_file_as_string("res://gdextension/src/mountain_plateau_raster.cpp")
	_assert(
		native_source.contains("preset_bool(p_preset, \"runtime_ground_patch\", false)"),
		"Native mountain raster must not emit runtime ground patches by default."
	)
	_assert(
		not native_source.contains("{ 0.36f, 0.48f, 0.28f"),
		"Native mountain raster must not keep the old green detail tint."
	)
	var shader_source: String = FileAccess.get_file_as_string("res://assets/shaders/mountain_top_mask_underlay.gdshader")
	_assert(
		shader_source.contains("shadow_cavity_enclosure") \
				and shader_source.contains("shadow_cavity_reject_strength"),
		"Mountain projected shadows must reject enclosed mined cavities instead of filling them flat."
	)
	_assert(
		shader_source.contains("projected_shadow_open_fill_strength") \
				and shader_source.contains("projected_shadow *= clamp(projected_shadow_open_fill_strength"),
		"Mountain underlay must keep shadow-only open-space fill disabled by data by default."
	)
	var material_source: String = FileAccess.get_file_as_string("res://data/terrain/material_sets/mountain_mask_underlay_material_set.tres")
	_assert(
		material_source.contains("\"projected_shadow_open_fill_strength\": 0.0"),
		"Mountain mask material set must explicitly disable shadow-only open-space fill."
	)

func _assert_full_mountain_surface_keeps_ground_underlay() -> void:
	var view := ChunkView.new()
	get_root().add_child(view)
	view.configure(Vector2i.ZERO)
	view.set_mountain_tile_visuals_enabled(false)
	var packet: Dictionary = _build_full_mountain_surface_packet()
	view.begin_apply(packet)
	while view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE):
		pass
	var base_layer := view.get_node("TerrainBaseLayer") as TileMapLayer
	_assert(base_layer != null, "ChunkView must keep a TerrainBaseLayer for mountain underlay.")
	if base_layer != null:
		var source_id: int = base_layer.get_cell_source_id(Vector2i.ZERO)
		_assert(
			source_id == WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
			"Suppressed full-mountain surface chunks must paint plains ground under the organic mountain mask."
		)
	view.queue_free()

func _build_full_mountain_surface_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var terrain_atlas_indices := PackedInt32Array()
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_atlas_indices := PackedInt32Array()
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		walkable_flags[index] = 0
		mountain_ids[index] = 77
		mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	return {
		"chunk_coord": Vector2i.ZERO,
		"world_seed": 77,
		"world_version": WorldRuntimeConstants.WORLD_VERSION,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _assert_grass_scatter_keeps_mountain_clearance() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for grass mountain-clearance checks.")
	if world_core == null:
		return
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			var index: int = WorldRuntimeConstants.local_to_index(Vector2i(x, y))
			terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for x: int in range(7, 9):
			var mountain_index: int = WorldRuntimeConstants.local_to_index(Vector2i(x, y))
			terrain_ids[mountain_index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	var result: Dictionary = world_core.call(
		"build_grass_scatter_buffer",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		Vector2i.ZERO,
		terrain_ids,
		lake_flags,
		_build_dense_grass_params()
	) as Dictionary
	_assert(not result.has("error"), "Grass mountain-clearance buffer build must not return an error.")
	var instance_count: int = int(result.get("instance_count", 0))
	_assert(instance_count > 0, "Grass mountain-clearance check must generate grass instances.")
	var checked_count: int = 0
	var bucket_buffers: Array = result.get("bucket_buffers", []) as Array
	for bucket_variant: Variant in bucket_buffers:
		var bucket: PackedFloat32Array = bucket_variant as PackedFloat32Array
		var offset: int = 0
		while offset + GRASS_INSTANCE_STRIDE <= bucket.size():
			var local_x: float = float(bucket[offset + 3])
			var local_y: float = float(bucket[offset + 7])
			checked_count += 1
			_assert(
				_grass_origin_has_mountain_clearance(terrain_ids, local_x, local_y, GRASS_MOUNTAIN_CLEARANCE_PX),
				"Grass scatter placed a tuft inside mountain clearance at local=(%.1f, %.1f)." % [local_x, local_y]
			)
			offset += GRASS_INSTANCE_STRIDE
	_assert(checked_count == instance_count, "Grass bucket buffers must align with instance_count.")

func _build_dense_grass_params() -> PackedFloat32Array:
	return PackedFloat32Array([
		float(WorldRuntimeConstants.CHUNK_SIZE),
		float(WorldRuntimeConstants.TILE_SIZE_PX),
		float(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
		64.0,
		4096.0,
		1050.0,
		1.0,
		820.0,
		0.0,
		1900.0,
		0.0,
		34.0,
		58.0,
		30.0,
		52.0,
		0.7,
		8.0,
		0.0,
		16.0,
		0.8,
		1.16,
		0.18,
		0.82,
		0.97,
		16.0,
		16.0,
		0.12,
		0.45,
	])

func _grass_origin_has_mountain_clearance(terrain_ids: PackedInt32Array, local_x: float, local_y: float, clearance_px: float) -> bool:
	var diagonal_clearance: float = clearance_px * 0.72
	for offset: Vector2 in [
		Vector2.ZERO,
		Vector2(clearance_px, 0.0),
		Vector2(-clearance_px, 0.0),
		Vector2(0.0, clearance_px),
		Vector2(0.0, -clearance_px),
		Vector2(diagonal_clearance, diagonal_clearance),
		Vector2(-diagonal_clearance, diagonal_clearance),
		Vector2(diagonal_clearance, -diagonal_clearance),
		Vector2(-diagonal_clearance, -diagonal_clearance),
	]:
		if _grass_sample_hits_mountain(terrain_ids, local_x + offset.x, local_y + offset.y):
			return false
	return true

func _grass_sample_hits_mountain(terrain_ids: PackedInt32Array, local_x: float, local_y: float) -> bool:
	if local_x < 0.0 \
			or local_y < 0.0 \
			or local_x >= float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX) \
			or local_y >= float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX):
		return false
	var local_coord := Vector2i(
		floori(local_x / float(WorldRuntimeConstants.TILE_SIZE_PX)),
		floori(local_y / float(WorldRuntimeConstants.TILE_SIZE_PX)),
	)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index < 0 or index >= terrain_ids.size():
		return true
	var terrain_id: int = int(terrain_ids[index])
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
