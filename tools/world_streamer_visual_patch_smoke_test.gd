extends SceneTree

const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MountainPlateau2DRasterLayer = preload("res://core/systems/world/mountain_plateau_2d_raster_layer.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

const GRASS_INSTANCE_STRIDE: int = 12
const GRASS_MOUNTAIN_CLEARANCE_PX: float = 128.0
const GRASS_MOUNTAIN_HALO_RADIUS_TILES: int = 8

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
	_assert_grass_scatter_sees_cross_chunk_mountain_halo()

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
		shader_source.contains("projected_shadow_color = vec3(0.030, 0.026, 0.018)"),
		"Mountain projected shadows must keep the dark pre-regression shadow color."
	)
	_assert(
		not shader_source.contains("projected_shadow_open_fill_strength") \
				and not shader_source.contains("projected_shadow *= clamp(projected_shadow_open_fill_strength"),
		"Mountain projected shadows must not be globally disabled on exterior open ground."
	)
	_assert(
		not shader_source.contains("shadow_cavity_enclosure") \
				and not shader_source.contains("shadow_cavity_reject_strength"),
		"Mountain projected shadows must not be cut by the local cavity-reject probe."
	)
	var material_source: String = FileAccess.get_file_as_string("res://data/terrain/material_sets/mountain_mask_underlay_material_set.tres")
	_assert(
		not material_source.contains("\"projected_shadow_open_fill_strength\"") \
				and not material_source.contains("\"shadow_cavity_reject_strength\""),
		"Mountain mask material set must not zero or locally reject exterior projected shadows."
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
		var atlas_coords: Vector2i = base_layer.get_cell_atlas_coords(Vector2i.ZERO)
		_assert(
			source_id == WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
			"Suppressed full-mountain surface chunks must paint organic ground under the mountain mask."
		)
		_assert(
			atlas_coords == WorldTileSetFactory.get_atlas_coords(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, 0),
			"Suppressed full-mountain surface chunks must use the organic ground material, not a square dug/foothill tile."
		)
		view.apply_runtime_cell(Vector2i.ZERO, WorldRuntimeConstants.TERRAIN_PLAINS_DUG, 0, true)
		_assert(
			base_layer.get_cell_source_id(Vector2i.ZERO) == WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
			"Mined mountain PLAINS_DUG tiles must keep the organic ground visual under the mountain mask."
		)
		_assert(
			base_layer.get_cell_atlas_coords(Vector2i.ZERO) == WorldTileSetFactory.get_atlas_coords(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, 0),
			"Mined mountain PLAINS_DUG tiles must not display the square dug tile atlas."
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
	var halo: PackedByteArray = _build_solid_halo_from_terrain_ids(terrain_ids, GRASS_MOUNTAIN_HALO_RADIUS_TILES)
	var result: Dictionary = world_core.call(
		"build_grass_scatter_buffer",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		Vector2i.ZERO,
		terrain_ids,
		lake_flags,
		halo,
		GRASS_MOUNTAIN_HALO_RADIUS_TILES,
		_build_dense_grass_params()
	) as Dictionary
	_assert(
		not result.has("error"),
		"Grass mountain-clearance buffer build must not return an error: %s" % str(result.get("error", ""))
	)
	var instance_count: int = int(result.get("instance_count", 0))
	_assert(instance_count > 0, "Grass mountain-clearance check must generate grass instances.")
	_assert_grass_directional_shadow_buffer_contract(result)
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


func _assert_grass_directional_shadow_buffer_contract(result: Dictionary) -> void:
	var instance_count: int = int(result.get("instance_count", 0))
	var directional: PackedFloat32Array = result.get(
		"directional_shadow_buffer",
		PackedFloat32Array(),
	) as PackedFloat32Array
	_assert(directional.size() == instance_count * GRASS_INSTANCE_STRIDE,
		"Native directional-shadow buffer must contain every tuft exactly once.")
	var bucket_buffers: Array = result.get("bucket_buffers", []) as Array
	var flat_offset: int = 0
	var bucket_float_count: int = 0
	var non_empty_bucket_count: int = 0
	for bucket_variant: Variant in bucket_buffers:
		var bucket: PackedFloat32Array = bucket_variant as PackedFloat32Array
		bucket_float_count += bucket.size()
		if not bucket.is_empty():
			non_empty_bucket_count += 1
		for value: float in bucket:
			_assert(flat_offset < directional.size() \
					and is_equal_approx(directional[flat_offset], value),
				"Directional-shadow flattening must preserve finalized bucket order.")
			flat_offset += 1
	_assert(flat_offset == directional.size(),
		"Directional-shadow flattening must not append or omit transforms.")
	var contact_shadow: PackedFloat32Array = result.get(
		"shadow_buffer",
		PackedFloat32Array(),
	) as PackedFloat32Array
	var spores: PackedFloat32Array = result.get(
		"spore_buffer",
		PackedFloat32Array(),
	) as PackedFloat32Array
	var expected_float_count: int = bucket_float_count \
			+ directional.size() \
			+ contact_shadow.size() \
			+ spores.size()
	_assert(int(result.get("buffer_float_count", -1)) == expected_float_count,
		"Grass producer metadata must include the flat directional-shadow payload.")
	_assert(int(result.get("payload_bytes", -1)) == expected_float_count * 4,
		"Grass warm-cache byte metadata must remain exact and O(1).")
	_assert(int(result.get("non_empty_bucket_count", -1)) == non_empty_bucket_count,
		"Grass non-empty stripe metadata must remain exact after flattening.")

## Regression for the 2026-07-04 grass-in-mountain bug: a mountain sitting in a
## NEIGHBOURING chunk must still clear grass near the shared seam. The target
## chunk here is pure plains (no mountain tile of its own); only the halo
## (representing the neighbour chunk) carries solid cells near one edge.
func _assert_grass_scatter_sees_cross_chunk_mountain_halo() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for cross-chunk grass clearance checks.")
	if world_core == null:
		return
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var halo_radius: int = GRASS_MOUNTAIN_HALO_RADIUS_TILES
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius * 2
	var halo := PackedByteArray()
	halo.resize(halo_side * halo_side)
	# Neighbour chunk to the west (tx < 0 in halo space) is solid mountain along
	# the whole shared seam.
	for ty: int in range(halo_side):
		for tx: int in range(halo_radius):
			halo[ty * halo_side + tx] = 1
	var result: Dictionary = world_core.call(
		"build_grass_scatter_buffer",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		Vector2i.ZERO,
		terrain_ids,
		lake_flags,
		halo,
		halo_radius,
		_build_dense_grass_params()
	) as Dictionary
	_assert(
		not result.has("error"),
		"Cross-chunk grass halo buffer build must not return an error: %s" % str(result.get("error", ""))
	)
	var bucket_buffers: Array = result.get("bucket_buffers", []) as Array
	var checked_count: int = 0
	for bucket_variant: Variant in bucket_buffers:
		var bucket: PackedFloat32Array = bucket_variant as PackedFloat32Array
		var offset: int = 0
		while offset + GRASS_INSTANCE_STRIDE <= bucket.size():
			var local_x: float = float(bucket[offset + 3])
			checked_count += 1
			_assert(
				local_x >= GRASS_MOUNTAIN_CLEARANCE_PX * 0.99,
				"Grass scatter ignored a mountain halo cell from the neighbouring chunk at local_x=%.1f." % local_x
			)
			offset += GRASS_INSTANCE_STRIDE
	_assert(checked_count > 0, "Cross-chunk grass halo check must generate grass instances to verify.")

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
		0.9,
		0.28,
		0.4,
		0.28,
		0.07,
		7.0,
		7000.0,
		0.34,
		2600.0,
		0.06,
		700.0,
		0.85,
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

## Mirrors WorldStreamer._build_mountain_solid_halo's layout for a synthetic
## single-chunk test: the chunk's own tiles land at halo offset
## (halo_radius_tiles, halo_radius_tiles); there is no real neighbour data, so
## the padding ring stays zero (not-mountain), matching a chunk with no
## adjacent mountains.
func _build_solid_halo_from_terrain_ids(terrain_ids: PackedInt32Array, halo_radius_tiles: int) -> PackedByteArray:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius_tiles * 2
	var halo := PackedByteArray()
	halo.resize(halo_side * halo_side)
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			var index: int = WorldRuntimeConstants.local_to_index(Vector2i(x, y))
			var terrain_id: int = int(terrain_ids[index])
			if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
				var halo_row: int = (y + halo_radius_tiles) * halo_side
				halo[halo_row + x + halo_radius_tiles] = 1
	return halo

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
