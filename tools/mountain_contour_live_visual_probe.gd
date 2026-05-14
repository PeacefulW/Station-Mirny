extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultMountainGenSettings = preload("res://data/balance/mountain_gen_settings.tres")
const DefaultFoundationGenSettings = preload("res://data/balance/foundation_gen_settings.tres")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const SAVE_SLOT: String = "save_001"
const USE_SAVE_SLOT: bool = false
const TARGET_TILE: Vector2i = Vector2i(177, 1600)
const AUTO_FIND_MOUNTAIN_EDGE: bool = true
const SEARCH_SEED: int = 240505
const OUTPUT_DIR: String = "res://artifacts/mountain_contour_live_visual_probe"
const REPORT_PATH: String = "%s/report.json" % OUTPUT_DIR
const SCREENSHOT_PATH: String = "%s/screenshot.png" % OUTPUT_DIR

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var target_tile: Vector2i = TARGET_TILE
	if AUTO_FIND_MOUNTAIN_EDGE:
		target_tile = _find_mountain_edge_probe_tile()
	var world_scene: Node = (load(WORLD_SCENE_PATH) as PackedScene).instantiate()
	var save_manager: Node = get_root().get_node_or_null("SaveManager")
	if USE_SAVE_SLOT and save_manager == null:
		_write_report({"ok": false, "error": "save_manager_missing"})
		quit(1)
		return
	if USE_SAVE_SLOT:
		save_manager.call("request_load_after_scene_change", SAVE_SLOT)
	get_root().add_child(world_scene)
	current_scene = world_scene
	await process_frame
	await process_frame

	var streamer: WorldStreamer = world_scene.get_node_or_null("WorldStreamer") as WorldStreamer
	var player: Node2D = world_scene.get_node_or_null("Player") as Node2D
	if streamer == null or player == null:
		_write_report({"ok": false, "error": "scene_missing_streamer_or_player"})
		quit(1)
		return
	if AUTO_FIND_MOUNTAIN_EDGE and not USE_SAVE_SLOT:
		var search_settings: Dictionary = _build_search_world_settings()
		streamer.initialize_new_world(
			SEARCH_SEED,
			search_settings["mountains"] as MountainGenSettings,
			search_settings["world_bounds"] as WorldBoundsSettings,
			search_settings["foundation"] as FoundationGenSettings,
			search_settings["lakes"] as LakeGenSettings
		)
		await process_frame
		await process_frame

	var target_world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(target_tile)
	player.global_position = target_world_pos
	for index: int in range(420):
		player.global_position = target_world_pos
		streamer.call("_streaming_tick")
		await process_frame
	player.global_position = target_world_pos

	var target_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(target_tile)
	var target_local: Vector2i = WorldRuntimeConstants.tile_to_local(target_tile)
	var target_index: int = WorldRuntimeConstants.local_to_index(target_local)
	var target_packet: Dictionary = streamer.get_chunk_packet(target_chunk)
	var target_sample: Dictionary = _packet_sample(target_packet, target_index)
	var chunks: Array[Dictionary] = []
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var chunk_coord: Vector2i = target_chunk + Vector2i(offset_x, offset_y)
			var snapshot: Dictionary = streamer.get_mountain_contour_runtime_debug_snapshot(chunk_coord)
			var packet: Dictionary = streamer.get_chunk_packet(chunk_coord)
			chunks.append({
				"chunk_coord": chunk_coord,
				"packet_loaded": not packet.is_empty(),
				"runtime_ready": bool(snapshot.get("ready", false)),
				"visual_ready": bool(snapshot.get("visual_ready", false)),
				"visual_layer_visible": bool(snapshot.get("visual_layer_visible", false)),
				"material_ready": bool(snapshot.get("material_ready", false)),
				"total_vertex_count": int(snapshot.get("total_vertex_count", 0)),
				"top_vertex_count": int(snapshot.get("top_vertex_count", 0)),
				"face_vertex_count": int(snapshot.get("face_vertex_count", 0)),
				"rim_vertex_count": int(snapshot.get("rim_vertex_count", 0)),
				"outline_vertex_count": int(snapshot.get("outline_vertex_count", 0)),
				"collision_ready": bool(snapshot.get("collision_ready", false)),
				"missing_required_seam_neighbours": snapshot.get("missing_required_seam_neighbours", []),
				"loaded_seam_neighbours": snapshot.get("loaded_seam_neighbours", []),
			})
	var report: Dictionary = {
		"ok": true,
		"save_slot": SAVE_SLOT,
		"use_save_slot": USE_SAVE_SLOT,
		"target_tile": target_tile,
		"target_chunk": target_chunk,
		"target_local": target_local,
		"target_sample": target_sample,
		"chunks": chunks,
	}
	await _capture_screenshot()
	_write_report(report)
	print("mountain_contour_live_visual_probe: OK")
	quit(0)

func _find_mountain_edge_probe_tile() -> Vector2i:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	if world_core == null:
		return TARGET_TILE
	var coords := PackedVector2Array()
	for y: int in range(20, 80):
		for x: int in range(-12, 13):
			coords.append(Vector2(x, y))
	var packets: Variant = world_core.call(
		"generate_chunk_packets_batch",
		SEARCH_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_search_settings_packed()
	)
	if packets is not Array:
		return TARGET_TILE
	for packet_variant: Variant in packets:
		var packet: Dictionary = packet_variant as Dictionary
		var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
		for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
			var terrain_id: int = int(terrain_ids[index])
			if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
				continue
			var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbour_local: Vector2i = local_coord + offset
				if not WorldRuntimeConstants.is_local_coord_valid(neighbour_local):
					continue
				var neighbour_index: int = WorldRuntimeConstants.local_to_index(neighbour_local)
				if neighbour_index < 0 or neighbour_index >= terrain_ids.size() or neighbour_index >= walkable_flags.size():
					continue
				var neighbour_terrain: int = int(terrain_ids[neighbour_index])
				if int(walkable_flags[neighbour_index]) != 0 \
						and neighbour_terrain != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
						and neighbour_terrain != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
					return chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + neighbour_local
	return TARGET_TILE

func _build_search_settings_packed() -> PackedFloat32Array:
	var settings: Dictionary = _build_search_world_settings()
	var packed: PackedFloat32Array = (settings["mountains"] as MountainGenSettings).flatten_to_packed()
	packed = (settings["foundation"] as FoundationGenSettings).write_to_settings_packed(
		packed,
		settings["world_bounds"] as WorldBoundsSettings
	)
	return (settings["lakes"] as LakeGenSettings).write_to_settings_packed(packed)

func _build_search_world_settings() -> Dictionary:
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var mountain_settings: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	mountain_settings.density = 0.60
	mountain_settings.scale = 256.0
	mountain_settings.foot_band = 0.30
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		world_bounds
	)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lake_settings.density = 0.0
	return {
		"mountains": mountain_settings,
		"world_bounds": world_bounds,
		"foundation": foundation_settings,
		"lakes": lake_settings,
	}

func _packet_sample(packet: Dictionary, index: int) -> Dictionary:
	if packet.is_empty() or index < 0:
		return {"ready": false}
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if index >= terrain_ids.size():
		return {"ready": false}
	return {
		"ready": true,
		"terrain_id": int(terrain_ids[index]),
		"walkable": index < walkable_flags.size() and int(walkable_flags[index]) != 0,
		"mountain_id": int(mountain_ids[index]) if index < mountain_ids.size() else 0,
		"mountain_flags": int(mountain_flags[index]) if index < mountain_flags.size() else 0,
	}

func _capture_screenshot() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	var image: Image = get_root().get_texture().get_image()
	if image == null or image.is_empty():
		return
	var absolute_path: String = ProjectSettings.globalize_path(SCREENSHOT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	image.save_png(absolute_path)

func _write_report(report: Dictionary) -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if file == null:
		push_error("Failed to write live visual probe report.")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
