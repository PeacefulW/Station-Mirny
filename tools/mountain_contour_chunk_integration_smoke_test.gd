extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MountainContourCollisionCache = preload("res://core/systems/world/mountain_contour_collision_cache.gd")
const MountainContourStyleRegistry = preload("res://core/systems/world/mountain_contour_style_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_contour_chunk_integration_smoke_test"
const REPORT_PATH: String = "%s/report.json" % OUTPUT_DIR

var _failed: bool = false
var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	if _failed:
		_write_report()
		quit(1)
		return

	var registry := MountainContourStyleRegistry.new()
	_assert(registry.load_default_styles(), "Chunk integration smoke test must load the default mountain contour style.")
	var style = registry.require_style(&"mountain")
	_assert(style != null, "Default mountain contour style must resolve.")
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for chunk contour integration smoke test.")
	_assert(world_core != null and world_core.has_method("build_mountain_contour_runtime"), "WorldCore must expose build_mountain_contour_runtime().")
	if _failed:
		_write_report()
		quit(1)
		return

	_assert_chunk_can_apply_contour_runtime(style, world_core)
	_assert_missing_required_seam_blocks_cache(style)
	_assert_missing_required_seam_keeps_degraded_visual(style)
	_assert_loaded_seam_halo_restores_cache(style, world_core)
	_assert_no_save_contour_payload()

	if _failed:
		_write_report()
		quit(1)
		return
	_write_report()
	print("mountain_contour_chunk_integration_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	var world_streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(chunk_view_source.contains("MountainContourVisualLayer"), "ChunkView must own a MountainContourVisualLayer child for runtime contour data.")
	_assert(chunk_view_source.contains("apply_mountain_contour_runtime_data"), "ChunkView must expose apply_mountain_contour_runtime_data(...).")
	_assert(chunk_view_source.contains("get_mountain_contour_runtime_debug_snapshot"), "ChunkView must expose contour runtime debug stats.")
	_assert(world_streamer_source.contains("_build_mountain_contour_runtime_halo_state"), "WorldStreamer must build a production solid halo with readiness state.")
	_assert(world_streamer_source.contains("build_mountain_contour_runtime"), "WorldStreamer must call native build_mountain_contour_runtime().")
	_assert(world_streamer_source.contains("_mountain_contour_collision_caches"), "WorldStreamer must store contour collision caches per chunk.")
	_assert(world_streamer_source.contains("get_mountain_contour_runtime_debug_snapshot"), "WorldStreamer must expose contour runtime debug snapshot.")
	_assert(_function_body(world_streamer_source, "save_world_state").find("contour") == -1, "Task 6 must not add contour data to save_world_state().")

func _assert_chunk_can_apply_contour_runtime(style, world_core: Object) -> void:
	var runtime_result: Dictionary = _build_runtime_result(world_core, _build_halo(_interior_blob()), style)
	var cache := MountainContourCollisionCache.new()
	cache.configure(
		Vector2i.ZERO,
		runtime_result.get("collision_loops", []) as Array,
		runtime_result.get("collision_aabbs", []) as Array
	)
	var chunk_view: ChunkView = _build_loaded_chunk_view(Vector2i.ZERO, _build_packet(_interior_blob()))
	chunk_view.apply_mountain_contour_runtime_data(
		style,
		runtime_result,
		true,
		_halo_state(true, [], [], _interior_blob().size(), runtime_result),
		false
	)
	var snapshot: Dictionary = chunk_view.get_mountain_contour_runtime_debug_snapshot()
	_assert(bool(snapshot.get("ready", false)), "Interior mountain chunk contour runtime must be ready without seam neighbours.")
	_assert(bool(snapshot.get("visual_ready", false)), "ChunkView must apply visual runtime mesh data.")
	_assert(bool(snapshot.get("collision_ready", false)), "ChunkView debug stats must receive contour collision readiness.")
	_assert(int(snapshot.get("loop_count", 0)) > 0, "Contour collision loop count must be observable.")
	_assert(int(snapshot.get("total_vertex_count", 0)) > 0, "Contour visual vertex count must be observable.")
	_assert(not bool(snapshot.get("visual_layer_visible", true)), "Task 6 integration layer must default to hidden until cutover validation.")
	_assert(int(snapshot.get("visual_layer_z_index", -1)) > 1, "Contour visual layer must draw above ground/overlay layers.")
	_assert(int(snapshot.get("visual_layer_z_index", 99)) < 10, "Contour visual layer must draw below roof/cover layers.")
	chunk_view.free()

func _assert_missing_required_seam_blocks_cache(style) -> void:
	var cache := MountainContourCollisionCache.new()
	var chunk_view: ChunkView = _build_loaded_chunk_view(Vector2i.ZERO, _build_packet(_west_seam_blob()))
	chunk_view.apply_mountain_contour_runtime_data(
		style,
		{"ready": false},
		false,
		_halo_state(false, [], [Vector2i(-1, 0)], _west_seam_blob().size(), {}),
		false
	)
	var snapshot: Dictionary = chunk_view.get_mountain_contour_runtime_debug_snapshot()
	_assert(not bool(snapshot.get("ready", true)), "Missing required west seam halo must mark contour runtime not ready.")
	_assert(not bool(snapshot.get("collision_ready", true)), "Missing required seam cache must not be configured as ready.")
	_assert(cache.is_point_blocked(Vector2.ZERO), "Missing contour cache must block collision queries.")
	_assert((snapshot.get("missing_required_seam_neighbours", []) as Array).has(Vector2i(-1, 0)), "Missing required west seam neighbour must be reported.")
	chunk_view.free()

func _assert_missing_required_seam_keeps_degraded_visual(style) -> void:
	var chunk_coord := Vector2i.ZERO
	var packet: Dictionary = _build_packet(_west_seam_blob())
	var chunk_view: ChunkView = _build_loaded_chunk_view(chunk_coord, packet)
	var streamer := WorldStreamer.new()
	streamer._mountain_contour_style = style
	streamer._mountain_contour_runtime_visible = true
	streamer._chunk_packets[chunk_coord] = packet
	streamer._chunk_views[chunk_coord] = chunk_view
	var telemetry: Dictionary = streamer._rebuild_mountain_contour_runtime_for_chunk(chunk_coord)
	var snapshot: Dictionary = streamer.get_mountain_contour_runtime_debug_snapshot(chunk_coord)
	_assert(not telemetry.is_empty(), "Missing seam runtime rebuild must still produce telemetry.")
	_assert(not bool(snapshot.get("ready", true)), "Missing seam contour runtime must not become fully ready.")
	_assert(not bool(snapshot.get("collision_ready", true)), "Missing seam contour runtime must not configure collision cache as ready.")
	_assert(bool(snapshot.get("missing_cache_blocks", false)), "Missing seam contour cache must stay fail-closed for collision.")
	_assert(bool(snapshot.get("visual_ready", false)), "Missing seam contour runtime must still publish degraded visual geometry.")
	_assert(not bool(snapshot.get("visual_layer_visible", true)), "Missing seam contour visual layer must stay hidden while visual cutover is rejected.")
	_assert(not bool(snapshot.get("visual_cutover_accepted", true)), "Missing seam contour runtime must report rejected visual cutover.")
	_assert(int(snapshot.get("total_vertex_count", 0)) > 0, "Missing seam contour visual must contain vertices.")
	_assert(not (snapshot.get("missing_required_seam_neighbours", []) as Array).is_empty(), "Missing required seam neighbour must remain visible in debug state.")
	chunk_view.free()
	streamer.free()

func _assert_loaded_seam_halo_restores_cache(style, world_core: Object) -> void:
	var seam_blob: Array[Vector2i] = _west_seam_blob()
	seam_blob.append(Vector2i(-1, 7))
	seam_blob.append(Vector2i(-1, 8))
	var runtime_result: Dictionary = _build_runtime_result(world_core, _build_halo(seam_blob), style)
	var chunk_view: ChunkView = _build_loaded_chunk_view(Vector2i.ZERO, _build_packet(_west_seam_blob()))
	chunk_view.apply_mountain_contour_runtime_data(
		style,
		runtime_result,
		true,
		_halo_state(true, [Vector2i(-1, 0)], [], _west_seam_blob().size() + 2, runtime_result),
		false
	)
	var snapshot: Dictionary = chunk_view.get_mountain_contour_runtime_debug_snapshot()
	_assert(bool(snapshot.get("ready", false)), "Loaded west seam halo must restore contour runtime readiness.")
	_assert(bool(snapshot.get("collision_ready", false)), "Loaded west seam halo must configure collision cache.")
	_assert((snapshot.get("loaded_seam_neighbours", []) as Array).has(Vector2i(-1, 0)), "Loaded west seam neighbour must be visible in debug state.")
	_assert((snapshot.get("missing_required_seam_neighbours", []) as Array).is_empty(), "No required seam neighbour should be missing after west packet is loaded.")
	chunk_view.free()

func _assert_no_save_contour_payload() -> void:
	var world_streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(_function_body(world_streamer_source, "save_world_state").find("contour") == -1, "Contour runtime state must not enter world save payload.")

func _build_loaded_chunk_view(chunk_coord: Vector2i, packet: Dictionary) -> ChunkView:
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	chunk_view.begin_apply(packet)
	while chunk_view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE):
		pass
	chunk_view.visible = true
	return chunk_view

func _build_runtime_result(world_core: Object, solid_halo: PackedByteArray, style) -> Dictionary:
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_runtime",
		solid_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		style.to_runtime_geometry_params()
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

func _halo_state(
	ready: bool,
	loaded_seam_neighbours: Array[Vector2i],
	missing_required_seam_neighbours: Array[Vector2i],
	solid_sample_count: int,
	runtime_result: Dictionary
) -> Dictionary:
	return {
		"ready": ready,
		"halo_side": WorldRuntimeConstants.CHUNK_SIZE + 2,
		"solid_sample_count": solid_sample_count,
		"loaded_seam_neighbours": loaded_seam_neighbours,
		"missing_required_seam_neighbours": missing_required_seam_neighbours,
		"optional_missing_seam_neighbours": [],
		"loop_count": (runtime_result.get("collision_loops", []) as Array).size(),
		"aabb_count": (runtime_result.get("collision_aabbs", []) as Array).size(),
	}

func _build_packet(solid_locals: Array[Vector2i]) -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var terrain_atlas_indices := PackedInt32Array()
	var walkable_flags := PackedByteArray()
	var lake_flags := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		walkable_flags[index] = 1
	for local_coord: Vector2i in solid_locals:
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		walkable_flags[index] = 0
		mountain_ids[index] = 7
		mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	return {
		"chunk_coord": Vector2i.ZERO,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": terrain_atlas_indices.duplicate(),
	}

func _interior_blob() -> Array[Vector2i]:
	return [
		Vector2i(7, 7),
		Vector2i(8, 7),
		Vector2i(7, 8),
		Vector2i(8, 8),
	]

func _west_seam_blob() -> Array[Vector2i]:
	return [
		Vector2i(0, 7),
		Vector2i(0, 8),
		Vector2i(1, 7),
		Vector2i(1, 8),
	]

func _east_seam_blob() -> Array[Vector2i]:
	return [
		Vector2i(14, 7),
		Vector2i(14, 8),
		Vector2i(15, 7),
		Vector2i(15, 8),
	]

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
