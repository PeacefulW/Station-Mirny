extends SceneTree

const ChunkDebugVisualLayer = preload("res://core/systems/world/chunk_debug_visual_layer.gd")
const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failed: bool = false

func _init() -> void:
	_assert_static_contract()
	_assert_native_contour_helper()
	_assert_chunk_debug_layer_draws_contract()

	if _failed:
		quit(1)
		return
	print("mountain_contour_l1_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var scene_source: String = FileAccess.get_file_as_string("res://scenes/world/world_runtime_v0_scene.gd")
	_assert(scene_source.contains("KEY_F6"), "F6 must toggle the 64 px tile grid debug overlay.")
	_assert(scene_source.contains("KEY_F7"), "F7 must toggle the mountain solid mask debug overlay.")
	_assert(scene_source.contains("KEY_F10"), "F10 must toggle the mountain contour mesh debug overlay.")
	_assert(not scene_source.contains("KEY_F8"), "F8 must not be bound by mountain contour L1 debug controls.")

	var world_core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		world_core_source.contains("build_mountain_contour_debug"),
		"WorldCore must expose a native debug contour helper; GDScript must not solve marching squares."
	)
	_assert(
		world_core_source.contains("mountain_contour"),
		"WorldCore contour helper must delegate to native mountain_contour code."
	)

	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	_assert(
		chunk_view_source.contains("chunk_debug_visual_layer.gd"),
		"ChunkView must use the dedicated chunk debug visual layer."
	)
	_assert(
		chunk_view_source.contains("set_debug_overlays"),
		"ChunkView must expose set_debug_overlays() for streamer-owned key toggles."
	)

	var constants_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_runtime_constants.gd")
	_assert(
		constants_source.contains("const WORLD_VERSION: int = 44"),
		"WORLD_VERSION must remain unchanged for visual/debug-only L1 contour work."
	)

	var save_schema_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/packet_schemas.md")
	_assert(
		not save_schema_source.contains("mountain_contour_vertices"),
		"L1 implementation must not document packet contour arrays unless it actually adds packet fields."
	)
	_assert(
		save_schema_source.contains("MountainContourDebugResult"),
		"packet_schemas.md must document the debug-only native contour result shape."
	)

func _assert_native_contour_helper() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native contour checks.")
	if world_core == null:
		return
	_assert(
		world_core.has_method("build_mountain_contour_debug"),
		"WorldCore must bind build_mountain_contour_debug()."
	)
	if not world_core.has_method("build_mountain_contour_debug"):
		return
	var solid_halo: PackedByteArray = _build_single_solid_halo()
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_debug",
		solid_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	_assert(result_variant is Dictionary, "Native contour helper must return a Dictionary.")
	if result_variant is not Dictionary:
		return
	var result: Dictionary = result_variant as Dictionary
	_assert(result.has("vertices"), "Contour result must include vertices.")
	_assert(result.has("indices"), "Contour result must include triangle indices.")
	var vertices: PackedVector2Array = result.get("vertices", PackedVector2Array()) as PackedVector2Array
	var indices: PackedInt32Array = result.get("indices", PackedInt32Array()) as PackedInt32Array
	_assert(vertices.size() >= 4, "Single solid-tile contour must produce visible vertices.")
	_assert(indices.size() >= 3 and indices.size() % 3 == 0, "Contour indices must describe triangles.")

func _assert_chunk_debug_layer_draws_contract() -> void:
	var layer := ChunkDebugVisualLayer.new()
	get_root().add_child(layer)
	layer.configure(Vector2i.ZERO)
	layer.set_debug_visibility(true, true, true)
	layer.set_debug_data(_build_local_solid_mask(), _build_simple_contour_vertices(), PackedInt32Array([0, 1, 2]))
	var layer_debug: Dictionary = layer.get_debug_state()
	_assert(bool(layer_debug.get("grid_visible", false)), "Debug layer must report grid visibility.")
	_assert(bool(layer_debug.get("solid_mask_visible", false)), "Debug layer must report solid mask visibility.")
	_assert(bool(layer_debug.get("contour_visible", false)), "Debug layer must report contour visibility.")
	_assert(int(layer_debug.get("solid_tile_count", 0)) == 1, "Debug layer must count one solid mask tile.")
	_assert(int(layer_debug.get("contour_triangle_count", 0)) == 1, "Debug layer must count one contour triangle.")
	layer.queue_free()

	var view := ChunkView.new()
	get_root().add_child(view)
	view.configure(Vector2i.ZERO)
	view.begin_apply(_build_packet_with_single_mountain_tile())
	while view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	_assert(view.has_method("set_debug_overlays"), "ChunkView must expose debug overlay toggles.")
	_assert(view.has_method("apply_contour_debug_data"), "ChunkView must accept native contour debug data.")
	if view.has_method("set_debug_overlays"):
		view.call("set_debug_overlays", true, true, true)
	if view.has_method("apply_contour_debug_data"):
		view.call("apply_contour_debug_data", _build_local_solid_mask(), _build_simple_contour_vertices(), PackedInt32Array([0, 1, 2]))
	if view.has_method("get_mountain_contour_debug_state"):
		var view_debug: Dictionary = view.call("get_mountain_contour_debug_state") as Dictionary
		_assert(bool(view_debug.get("grid_visible", false)), "ChunkView debug state must expose grid visibility.")
		_assert(int(view_debug.get("solid_tile_count", 0)) == 1, "ChunkView debug state must expose the solid mask.")
		_assert(int(view_debug.get("contour_triangle_count", 0)) == 1, "ChunkView debug state must expose contour triangles.")
	else:
		_assert(false, "ChunkView must expose get_mountain_contour_debug_state().")
	view.queue_free()

func _build_single_solid_halo() -> PackedByteArray:
	var side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(side * side)
	var center_x: int = 1 + 4
	var center_y: int = 1 + 4
	solid_halo[center_y * side + center_x] = 1
	return solid_halo

func _build_local_solid_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mask[WorldRuntimeConstants.local_to_index(Vector2i(4, 4))] = 1
	return mask

func _build_simple_contour_vertices() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(256.0, 256.0),
		Vector2(320.0, 256.0),
		Vector2(256.0, 320.0),
	])

func _build_packet_with_single_mountain_tile() -> Dictionary:
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
	var mountain_index: int = WorldRuntimeConstants.local_to_index(Vector2i(4, 4))
	terrain_ids[mountain_index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	walkable_flags[mountain_index] = 0
	mountain_ids[mountain_index] = 77
	mountain_flags[mountain_index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
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

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
