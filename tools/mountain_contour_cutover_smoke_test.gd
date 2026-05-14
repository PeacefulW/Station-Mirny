extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MountainContourStyleRegistry = preload("res://core/systems/world/mountain_contour_style_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_contour_cutover_smoke_test"
const REPORT_PATH: String = "%s/report.json" % OUTPUT_DIR

var _failed: bool = false
var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run():
	_assert_static_contract()
	if _failed:
		_write_report()
		quit(1)
		return

	var registry := MountainContourStyleRegistry.new()
	_assert(registry.load_default_styles(), "Cutover smoke test must load default mountain contour style.")
	var style = registry.require_style(&"mountain")
	_assert(style != null, "Default mountain contour style must resolve.")
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for mountain cutover smoke test.")
	_assert(world_core != null and world_core.has_method("build_mountain_contour_runtime"), "WorldCore must expose build_mountain_contour_runtime().")
	if _failed:
		_write_report()
		quit(1)
		return

	_assert_mountain_cells_are_not_visible_tilemap_surface(style, world_core)
	await _assert_production_contour_renders_visible_pixels(style, world_core)
	_assert_mining_reveals_dug_ground_and_clears_roof_cell()
	_assert_non_mountain_ground_still_uses_tilemap_surface()

	if _failed:
		_write_report()
		quit(1)
		return
	_write_report()
	print("mountain_contour_cutover_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	var world_streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		chunk_view_source.contains("_is_mountain_contour_visual_cutover_enabled"),
		"ChunkView must gate mountain square TileMap rendering through a named cutover policy."
	)
	_assert(
		chunk_view_source.contains("_resolve_base_tilemap_terrain_id"),
		"ChunkView must resolve a non-mountain base TileMap terrain id under contour-owned mountains."
	)
	_assert(
		chunk_view_source.contains("_clear_all_roof_surface_cells"),
		"ChunkView must clear legacy roof TileMap cells when contour cutover owns mountain visuals."
	)
	_assert(
		world_streamer_source.contains("_mountain_contour_runtime_visible: bool = true"),
		"WorldStreamer must enable mountain contour runtime visuals for normal gameplay cutover."
	)
	_assert(
		_function_body(world_streamer_source, "_publish_next_batch").contains("_refresh_mountain_contour_runtime_around_chunk(_active_publish_chunk)"),
		"Publishing a newly loaded chunk must refresh nearby contour runtime caches so seam-neighbour readiness can recover visible mountains."
	)

func _assert_mountain_cells_are_not_visible_tilemap_surface(style, world_core: Object) -> void:
	var wall_local := Vector2i(7, 7)
	var foot_local := Vector2i(8, 7)
	var terrain_by_local: Dictionary = {}
	terrain_by_local[wall_local] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	terrain_by_local[foot_local] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	var view: ChunkView = _build_loaded_chunk_view(terrain_by_local)
	var runtime_result: Dictionary = _build_runtime_result(world_core, _build_halo([
		wall_local,
		foot_local,
	]), style)
	view.apply_mountain_contour_runtime_data(
		style,
		runtime_result,
		true,
		_halo_state(true, 2, runtime_result),
		true
	)

	var wall_index: int = WorldRuntimeConstants.local_to_index(wall_local)
	var foot_index: int = WorldRuntimeConstants.local_to_index(foot_local)
	_assert(int(view._pending_terrain_ids[wall_index]) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL, "Logical wall terrain id must remain in pending packet state.")
	_assert(int(view._pending_terrain_ids[foot_index]) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT, "Logical foot terrain id must remain in pending packet state.")
	_assert(int(view._pending_mountain_ids[wall_index]) == 31, "Logical mountain id must remain available for cover systems.")
	_assert(int(view._pending_mountain_flags[foot_index]) == WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT, "Logical mountain foot flags must remain available for cover systems.")

	var wall_base_source: int = view._base_layer.get_cell_source_id(wall_local)
	var foot_base_source: int = view._base_layer.get_cell_source_id(foot_local)
	_assert(wall_base_source != WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL), "Wall must not render as a square mountain base TileMap cell.")
	_assert(foot_base_source != WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT), "Foot must not render as a square mountain base TileMap cell.")
	_assert(wall_base_source == WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND), "Wall underlay must render as non-mountain ground below contour visual.")
	_assert(foot_base_source == WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND), "Foot underlay must render as non-mountain ground below contour visual.")

	var wall_cover_debug: Dictionary = view.get_cover_render_debug(wall_local, 31, 0)
	var foot_cover_debug: Dictionary = view.get_cover_render_debug(foot_local, 31, 0)
	_assert(int(wall_cover_debug.get("pending_mountain_id", 0)) == 31, "Cover debug must keep mountain id after visual cutover.")
	_assert(int(foot_cover_debug.get("pending_flags", 0)) == WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT, "Cover debug must keep mountain flags after visual cutover.")
	_assert(int(wall_cover_debug.get("roof_cell_source_id", 0)) < 0, "Wall must not render as a square roof TileMap cell after cutover.")
	_assert(int(foot_cover_debug.get("roof_cell_source_id", 0)) < 0, "Foot must not render as a square roof TileMap cell after cutover.")

	var snapshot: Dictionary = view.get_mountain_contour_runtime_debug_snapshot()
	_assert(bool(snapshot.get("visual_layer_visible", false)), "Contour visual layer must be visible after cutover when runtime data is ready.")
	_assert(int(snapshot.get("visual_layer_z_index", -1)) > 1, "Contour visual layer must draw above ground/overlay TileMap layers.")
	_assert(int(snapshot.get("total_vertex_count", 0)) > 0, "Contour visual layer must own mountain vertices after cutover.")
	view.free()

func _assert_production_contour_renders_visible_pixels(style, world_core: Object):
	if DisplayServer.get_name() == "headless":
		return
	var wall_local := Vector2i(7, 7)
	var foot_local := Vector2i(8, 7)
	var terrain_by_local: Dictionary = {}
	terrain_by_local[wall_local] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	terrain_by_local[foot_local] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	var view: ChunkView = _build_loaded_chunk_view(terrain_by_local)
	var runtime_result: Dictionary = _build_runtime_result(world_core, _build_halo([
		wall_local,
		foot_local,
	]), style)
	view.apply_mountain_contour_runtime_data(
		style,
		runtime_result,
		true,
		_halo_state(true, 2, runtime_result),
		true
	)
	view._base_layer.visible = false
	view._overlay_layer.visible = false
	if view._water_layer != null:
		view._water_layer.visible = false

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 1024)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	get_root().add_child(viewport)
	viewport.add_child(view)
	await process_frame
	await process_frame
	var image: Image = viewport.get_texture().get_image()
	var visible_pixel_count: int = _count_visible_pixels(image)
	_assert(visible_pixel_count > 0, "Production contour visual layer must render visible pixels, not only debug/collision geometry.")
	viewport.remove_child(view)
	view.free()
	viewport.free()

func _assert_mining_reveals_dug_ground_and_clears_roof_cell() -> void:
	var local_coord := Vector2i(7, 7)
	var terrain_by_local: Dictionary = {}
	terrain_by_local[local_coord] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	var view: ChunkView = _build_loaded_chunk_view(terrain_by_local)
	view.apply_runtime_cell(
		local_coord,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		true
	)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	_assert(int(view._pending_terrain_ids[index]) == WorldRuntimeConstants.TERRAIN_PLAINS_DUG, "Mining runtime cell must update logical terrain to dug ground.")
	_assert(int(view._pending_mountain_ids[index]) == 0, "Mining runtime cell must clear mountain id for the dug tile.")
	_assert(int(view._pending_mountain_flags[index]) == 0, "Mining runtime cell must clear mountain flags for the dug tile.")
	_assert(view._base_layer.get_cell_source_id(local_coord) == WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_DUG), "Mined mountain tile must reveal dug ground in the base TileMap.")
	var cover_debug: Dictionary = view.get_cover_render_debug(local_coord, 31, 0)
	_assert(int(cover_debug.get("roof_cell_source_id", 0)) < 0, "Mined mountain tile must not leave a stale roof TileMap cell.")
	view.free()

func _assert_non_mountain_ground_still_uses_tilemap_surface() -> void:
	var ground_local := Vector2i(2, 2)
	var view: ChunkView = _build_loaded_chunk_view({})
	_assert(
		view._base_layer.get_cell_source_id(ground_local) == WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
		"Non-mountain ground must continue using normal TileMap presentation."
	)
	view.free()

func _build_loaded_chunk_view(terrain_by_local: Dictionary) -> ChunkView:
	var view := ChunkView.new()
	view.configure(Vector2i.ZERO)
	view.begin_apply(_build_packet(terrain_by_local))
	while view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE):
		pass
	view.visible = true
	return view

func _build_runtime_result(world_core: Object, solid_halo: PackedByteArray, style) -> Dictionary:
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_runtime",
		solid_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		{
			"south_height_px": style.south_height_px,
			"side_height_px": style.side_height_px,
			"corner_round_px": style.corner_round_px,
			"diagonal_smooth_px": style.diagonal_smooth_px,
			"contour_warp_px": style.contour_warp_px,
			"rim_width_px": style.rim_width_px,
			"mountain_outline_enabled": style.mountain_outline_enabled,
			"mountain_outline_width_px": style.mountain_outline_width_px,
		}
	)
	_assert(result_variant is Dictionary, "build_mountain_contour_runtime() must return Dictionary.")
	if result_variant is Dictionary:
		return result_variant as Dictionary
	return {"ready": false}

func _build_halo(solid_locals: Array[Vector2i]) -> PackedByteArray:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(halo_side * halo_side)
	for local_coord: Vector2i in solid_locals:
		var halo_coord: Vector2i = local_coord + Vector2i.ONE
		solid_halo[halo_coord.y * halo_side + halo_coord.x] = 1
	return solid_halo

func _halo_state(ready: bool, solid_sample_count: int, runtime_result: Dictionary) -> Dictionary:
	return {
		"ready": ready,
		"halo_side": WorldRuntimeConstants.CHUNK_SIZE + 2,
		"solid_sample_count": solid_sample_count,
		"loaded_seam_neighbours": [],
		"missing_required_seam_neighbours": [],
		"optional_missing_seam_neighbours": [],
		"loop_count": (runtime_result.get("collision_loops", []) as Array).size(),
		"aabb_count": (runtime_result.get("collision_aabbs", []) as Array).size(),
	}

func _build_packet(terrain_by_local: Dictionary) -> Dictionary:
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
	for local_variant: Variant in terrain_by_local.keys():
		var local_coord: Vector2i = local_variant as Vector2i
		var terrain_id: int = int(terrain_by_local[local_variant])
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = terrain_id
		if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL:
			walkable_flags[index] = 0
			mountain_ids[index] = 31
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
			mountain_atlas_indices[index] = 5
		elif terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			walkable_flags[index] = 0
			mountain_ids[index] = 31
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
			mountain_atlas_indices[index] = 7
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

func _count_visible_pixels(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var count: int = 0
	var step: int = 4
	for y: int in range(0, image.get_height(), step):
		for x: int in range(0, image.get_width(), step):
			if image.get_pixel(x, y).a > 0.05:
				count += 1
	return count

func _function_body(source: String, function_name: String) -> String:
	var start: int = source.find("func %s" % [function_name])
	if start < 0:
		return ""
	var next: int = source.find("\nfunc ", start + 1)
	if next < 0:
		return source.substr(start)
	return source.substr(start, next - start)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_errors.append(message)
	_failed = true

func _write_report() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR).replace("\\", "/")
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		push_error("Failed to create report directory %s: %d" % [absolute_dir, err])
		return
	var file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if file == null:
		push_error("Failed to open report %s: %d" % [REPORT_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({
		"ok": not _failed,
		"errors": _errors,
	}, "\t"))
	file.close()
