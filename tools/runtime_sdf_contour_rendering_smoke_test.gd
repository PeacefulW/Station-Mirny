extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const DIFF_REVISION: int = 17
const OUTPUT_SIZE_PX: int = 1024

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	_assert_contour_visual_coverage_metadata()
	if _failed:
		quit(1)
		return

	var chunk_view := ChunkView.new()
	root.add_child(chunk_view)
	chunk_view.configure(Vector2i.ZERO)
	chunk_view.set_contour_rendering_enabled(true)
	chunk_view.begin_apply(_build_packet_with_ground_and_two_mountains())
	while chunk_view.apply_next_batch(64):
		pass

	var stale_results: Dictionary = {
		WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE: _build_contour_result(
			WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE,
			DIFF_REVISION - 1
		),
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: _build_contour_result(
			WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
			DIFF_REVISION - 1
		),
	}
	chunk_view.apply_contour_results(stale_results, DIFF_REVISION)
	var stale_state: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(not bool(stale_state.get("ready", true)), "Stale contour revisions must keep the chunk hidden.")
	_assert(not chunk_view.visible, "A stale contour chunk must remain hidden.")

	var fresh_results: Dictionary = {
		WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE: _build_contour_result(
			WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE,
			DIFF_REVISION
		),
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: _build_contour_result(
			WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
			DIFF_REVISION
		),
	}
	chunk_view.apply_contour_results(fresh_results, DIFF_REVISION)
	var visible_mask := PackedByteArray()
	visible_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	chunk_view.apply_cover_visibility(visible_mask)

	var state: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(bool(state.get("ready", false)), "Fresh ground and mountain contour resources must make the chunk render-ready.")
	_assert(chunk_view.visible, "A fresh contour chunk must become visible.")
	_assert(int(state.get("ground_visual_count", 0)) == 1, "ChunkView must create one ground contour visual.")
	_assert(int(state.get("mountain_bucket_count", 0)) == 1, "ChunkView must create one SDF-shaped mountain contour visual per chunk.")
	_assert(int(state.get("target_tilemap_apply_count", -1)) == 0, "Ground and mountain terrain ids must not use TileMap apply path in contour mode.")
	_assert(int(state.get("target_tilemap_cell_count", -1)) == 0, "Ground and mountain TileMap cells must remain empty in contour mode.")

	var ground_state: Dictionary = state.get("ground", {}) as Dictionary
	_assert(bool(ground_state.get("has_mask_texture", false)), "Ground material must receive mask texture.")
	_assert(bool(ground_state.get("has_height_texture", false)), "Ground material must receive height texture.")
	_assert(bool(ground_state.get("has_normal_texture", false)), "Ground material must receive normal texture.")
	_assert(bool(ground_state.get("has_base_albedo", false)), "Ground material must receive exported base albedo texture.")
	_assert(bool(ground_state.get("has_chunk_origin", false)), "Ground material must receive chunk origin uniform.")
	_assert(bool(ground_state.get("has_tile_size", false)), "Ground material must receive tile size uniform.")

	var mountain_buckets: Array = state.get("mountain_buckets", []) as Array
	var seen_mountain_ids: Dictionary = {}
	for bucket_variant: Variant in mountain_buckets:
		var bucket: Dictionary = bucket_variant as Dictionary
		seen_mountain_ids[int(bucket.get("mountain_id", 0))] = true
		_assert(bool(bucket.get("has_mask_texture", false)), "Mountain material must receive mask texture.")
		_assert(bool(bucket.get("has_height_texture", false)), "Mountain material must receive height texture.")
		_assert(bool(bucket.get("has_normal_texture", false)), "Mountain material must receive normal texture.")
		_assert(bool(bucket.get("has_base_albedo", false)), "Mountain material must receive exported base albedo texture.")
		_assert(bool(bucket.get("has_cover_mask", false)), "Mountain material must receive cover mask.")
		_assert(bool(bucket.get("has_chunk_origin", false)), "Mountain material must receive chunk origin uniform.")
		_assert(bool(bucket.get("has_tile_size", false)), "Mountain material must receive tile size uniform.")
	_assert(seen_mountain_ids.has(ChunkView.FALLBACK_MOUNTAIN_CONTOUR_ID), "Mountain contour visual must use the chunk SDF bucket.")
	chunk_view.apply_runtime_contour_cell_state(Vector2i(4, 4), WorldRuntimeConstants.TERRAIN_PLAINS_DUG, true)
	var dirty_cell_state: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(bool(dirty_cell_state.get("visible", false)), "Dirty contour chunks must keep the previous visual visible until native refresh arrives.")
	_assert(bool(dirty_cell_state.get("ready", false)), "Logical cell updates must not fabricate a partial contour visual revision.")

	chunk_view.set_debug_overlays(true, true, true)
	var after_debug_state: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(
		int(after_debug_state.get("mask_texture_instance_id", 0)) == int(state.get("mask_texture_instance_id", 0)),
		"Debug overlay toggles must not mutate contour textures."
	)

	chunk_view.queue_free()
	await process_frame

	_assert_halo_only_mountain_facade_visual()
	await process_frame

	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_rendering_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	_assert(
		FileAccess.file_exists("res://assets/shaders/contour_ground_material.gdshader"),
		"Iteration 04 requires contour_ground_material.gdshader."
	)
	_assert(
		FileAccess.file_exists("res://assets/shaders/contour_mountain_material.gdshader"),
		"Iteration 04 requires contour_mountain_material.gdshader."
	)
	_assert_shader_has_alpha_only_mask_fallback(
		"res://assets/shaders/contour_ground_material.gdshader",
		"ground"
	)
	_assert_shader_has_alpha_only_mask_fallback(
		"res://assets/shaders/contour_mountain_material.gdshader",
		"mountain"
	)
	_assert_mountain_shader_has_bottom_outline_darkening()
	_assert_mountain_shader_uses_cover_mask()
	_assert_mountain_shader_darkens_bottom_contact()
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	_assert(
		chunk_view_source.contains("apply_contour_results"),
		"ChunkView must expose contour result apply for Iteration 04."
	)
	_assert(
		chunk_view_source.contains("get_contour_render_debug_state"),
		"ChunkView must expose contour rendering debug readback."
	)
	_assert(
		not chunk_view_source.contains("apply_contour_ground_placeholder"),
		"ChunkView must not expose a script-side ground placeholder apply path."
	)
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		not streamer_source.contains("_build_constant_contour_result") \
			and not streamer_source.contains("_build_immediate_ground_placeholder_result") \
			and not streamer_source.contains("_is_contour_solid_mask_empty") \
			and not streamer_source.contains("_is_contour_solid_mask_full"),
		"WorldStreamer must not fabricate contour visuals through GDScript constant or placeholder paths."
	)

func _assert_contour_visual_coverage_metadata() -> void:
	var streamer := WorldStreamer.new()
	var covered := {
		"mask_rgba8": PackedByteArray([0, 0, 0, 0, 0, 0, 0, 1]),
	}
	streamer._annotate_contour_result_visual_coverage(covered)
	_assert(bool(covered.get("has_visual_coverage", false)), "Contour results with non-zero alpha must be annotated with visual coverage before main-thread apply.")

	var empty := {
		"mask_rgba8": PackedByteArray([0, 0, 0, 0]),
	}
	streamer._annotate_contour_result_visual_coverage(empty)
	_assert(not bool(empty.get("has_visual_coverage", true)), "Contour results with zero alpha must not request a visual bucket.")
	streamer.free()

func _assert_halo_only_mountain_facade_visual() -> void:
	var chunk_view := ChunkView.new()
	root.add_child(chunk_view)
	chunk_view.configure(Vector2i(0, 1))
	chunk_view.set_contour_rendering_enabled(true)
	chunk_view.begin_apply(_build_ground_only_packet())
	while chunk_view.apply_next_batch(64):
		pass
	var fresh_results: Dictionary = {
		WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE: _build_contour_result(
			WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE,
			DIFF_REVISION
		),
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: _build_contour_result(
			WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
			DIFF_REVISION,
			true
		),
	}
	chunk_view.apply_contour_results(fresh_results, DIFF_REVISION)
	var state: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(
		int(state.get("mountain_bucket_count", 0)) == 1,
		"Halo-projected south mountain facade must create a fallback visual bucket even when this chunk has no local mountain tiles."
	)
	chunk_view.queue_free()

func _assert_shader_has_alpha_only_mask_fallback(path: String, label: String) -> void:
	var shader_source: String = FileAccess.get_file_as_string(path)
	_assert(
		shader_source.contains("alpha_coverage_fallback"),
		"%s contour shader must turn alpha-only occupancy masks into visible material coverage." % label
	)

func _assert_mountain_shader_has_bottom_outline_darkening() -> void:
	var shader_source: String = FileAccess.get_file_as_string("res://assets/shaders/contour_mountain_material.gdshader")
	_assert(
		shader_source.contains("bottom_outline_strength")
			and shader_source.contains("outline_only_face")
			and shader_source.contains("bottom_outline_color"),
		"Mountain contour shader must darken native outline-only face coverage so generator bottom outline remains visible in runtime."
	)

func _assert_mountain_shader_uses_cover_mask() -> void:
	var shader_source: String = FileAccess.get_file_as_string("res://assets/shaders/contour_mountain_material.gdshader")
	_assert(
		shader_source.contains("texture(cover_mask")
			and shader_source.contains("local_pos_px")
			and shader_source.contains("mask_uv")
			and shader_source.contains("shape_mask.a * cover"),
		"Mountain contour shader must sample cover_mask so runtime mountain coverage matches the preview mask instead of drawing stale face pixels."
	)

func _assert_mountain_shader_darkens_bottom_contact() -> void:
	var shader_source: String = FileAccess.get_file_as_string("res://assets/shaders/contour_mountain_material.gdshader")
	_assert(
		shader_source.contains("bottom_face_contact")
			and shader_source.contains("TEXTURE_PIXEL_SIZE")
			and shader_source.contains("below_shape_mask"),
		"Mountain contour shader must darken the bottom face contact, not only the generator's transparent outline pixels."
	)

func _build_packet_with_ground_and_two_mountains() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var atlas_indices := PackedInt32Array()
	var walkable_flags := PackedByteArray()
	var lake_flags := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	var mountain_atlas_indices := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		walkable_flags[index] = 1
	for y: int in range(4, 12):
		for x: int in range(4, 12):
			var index: int = WorldRuntimeConstants.local_to_index(Vector2i(x, y))
			terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
			walkable_flags[index] = 0
			mountain_ids[index] = 1 if x < 8 else 2
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	return {
		"chunk_coord": Vector2i.ZERO,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _build_ground_only_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var atlas_indices := PackedInt32Array()
	var walkable_flags := PackedByteArray()
	var lake_flags := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	var mountain_atlas_indices := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		walkable_flags[index] = 1
	return {
		"chunk_coord": Vector2i(0, 1),
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _build_contour_result(
	contour_class: StringName,
	diff_revision: int,
	has_visual_coverage: bool = true
) -> Dictionary:
	return {
		"chunk_coord": Vector2i.ZERO,
		"contour_class": contour_class,
		"recipe_id": contour_class,
		"diff_revision": diff_revision,
		"pixel_size": Vector2i(OUTPUT_SIZE_PX, OUTPUT_SIZE_PX),
		"mask_rgba8": _build_byte_buffer(OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 4, 255),
		"height_r16": _build_byte_buffer(OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 2, 127),
		"normal_rgba8": _build_byte_buffer(OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 4, 128),
		"collision_sdf_f32": PackedFloat32Array(),
		"collision_origin_world_px": Vector2i.ZERO,
		"collision_sample_px": 4,
		"collision_size": Vector2i(257, 257),
		"collision_blocks_inside": contour_class == WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
		"has_visual_coverage": has_visual_coverage,
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
