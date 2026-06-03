extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const PROBE_SEED: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
const MOUNTAIN_DENSITY: float = 0.0
const SHORELINE_LAKE_DENSITY: float = 1.0
const DRY_GROUND_LAKE_DENSITY: float = 0.0
const MAX_SCAN_RADIUS_CHUNKS: int = 36
const MAX_SETTLE_FRAMES: int = 900
const OUTPUT_DIR: String = "res://artifacts/terrain_edge_native_mask_probe"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("terrain_edge_native_mask_probe: start")
	var target: Dictionary = _find_land_water_edge_target(SHORELINE_LAKE_DENSITY)
	_assert(not target.is_empty(), "Probe must find a generated land/water edge target.")
	if target.is_empty():
		_finish()
		return
	await _run_runtime_probe("shoreline", SHORELINE_LAKE_DENSITY, target)
	if _failed:
		_finish()
		return

	var dry_target: Dictionary = _find_dry_ground_target(DRY_GROUND_LAKE_DENSITY)
	_assert(not dry_target.is_empty(), "Probe must find a generated dry ground target.")
	if dry_target.is_empty():
		_finish()
		return
	await _run_runtime_probe("dry_ground", DRY_GROUND_LAKE_DENSITY, dry_target)

	_finish()

func _run_runtime_probe(label: String, lake_density: float, target: Dictionary) -> void:
	var packed_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "World runtime scene must load.")
	if packed_scene == null:
		return

	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame

	var streamer: Node = scene.get_node_or_null("WorldStreamer")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	_assert(streamer != null, "World runtime scene must contain WorldStreamer.")
	_assert(player != null, "World runtime scene must contain Player.")
	if streamer == null or player == null:
		_finish()
		return

	streamer.call(
		"initialize_new_world",
		PROBE_SEED,
		_build_mountain_settings(),
		WorldBoundsSettings.hard_coded_defaults(),
		FoundationGenSettings.for_bounds(WorldBoundsSettings.hard_coded_defaults()),
		_build_lake_settings(lake_density)
	)
	var target_tile: Vector2i = target.get("target_tile", Vector2i.ZERO) as Vector2i
	player.global_position = WorldRuntimeConstants.tile_to_world_center(target_tile)
	streamer.call("_update_player_chunk_coord")

	var settled: Dictionary = await _wait_until_settled(streamer)
	var debug: Dictionary = streamer.call("get_mountain_mask_runtime_debug_state") as Dictionary
	var screenshot_status: Dictionary = await _capture_viewport("%s/%s.png" % [OUTPUT_DIR, label])
	print("terrain_edge_native_mask_probe: %s settled=%s debug=%s target=%s" % [
		label,
		JSON.stringify(settled),
		JSON.stringify(_compact_debug(debug)),
		JSON.stringify(_compact_target(target)),
	])
	_assert(bool(settled.get("ready", false)), "Terrain edge streaming work must settle.")
	_assert(bool(debug.get("terrain_edge_mask_runtime_enabled", false)), "Terrain edge native mask runtime must be enabled.")
	var terrain_ground_visible_chunk_count: int = int(debug.get("terrain_ground_visible_chunk_count", 0))
	_assert(terrain_ground_visible_chunk_count > 0, "Probe must publish at least one chunk with dry terrain ground.")
	_assert(
		int(debug.get("terrain_ground_visible_without_mask_count", -1)) == 0,
		"No visible dry terrain chunk may fall back to square base terrain."
	)
	_assert(
		int(debug.get("terrain_ground_visible_without_visual_count", -1)) == 0,
		"No visible dry terrain chunk may be published before the terrain ground visual texture is ready."
	)
	_assert(int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) == 0, "Terrain edge visual upload queue must drain.")
	_assert(int(debug.get("terrain_edge_mask_visual_pending_count", 0)) == 0, "Terrain edge visual pending flags must drain.")
	_assert(int(debug.get("terrain_edge_mask_inflight_count", 0)) == 0, "Terrain edge worker requests must drain.")
	print("terrain_edge_native_mask_probe: %s screenshot=%s" % [label, JSON.stringify(screenshot_status)])

	scene.queue_free()
	await process_frame

func _wait_until_settled(streamer: Node) -> Dictionary:
	var last_debug: Dictionary = {}
	for frame: int in range(MAX_SETTLE_FRAMES):
		streamer.call("_streaming_tick")
		streamer.call("_mountain_native_mask_visual_apply_tick")
		await process_frame
		last_debug = streamer.call("get_mountain_mask_runtime_debug_state") as Dictionary
		if not bool(streamer.call("_has_pending_streaming_work")) \
				and int(last_debug.get("ready_terrain_edge_mask_chunk_count", 0)) > 0 \
				and int(last_debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) == 0 \
				and int(last_debug.get("terrain_edge_mask_visual_pending_count", 0)) == 0 \
				and int(last_debug.get("terrain_edge_mask_inflight_count", 0)) == 0:
			return {
				"ready": true,
				"frame": frame,
				"debug": _compact_debug(last_debug),
			}
	return {
		"ready": false,
		"frame": MAX_SETTLE_FRAMES,
		"debug": _compact_debug(last_debug),
	}

func _find_land_water_edge_target(lake_density: float) -> Dictionary:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for terrain edge probe.")
	if world_core == null:
		return {}
	var settings_packed: PackedFloat32Array = _settings_packed(lake_density)
	var spawn: Dictionary = world_core.call(
		"resolve_world_foundation_spawn_tile",
		PROBE_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	) as Dictionary
	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(
		spawn.get("spawn_tile", Vector2i.ZERO) as Vector2i
	)
	for radius: int in range(MAX_SCAN_RADIUS_CHUNKS + 1):
		var coords := PackedVector2Array()
		for cy: int in range(center_chunk.y - radius, center_chunk.y + radius + 1):
			for cx: int in range(center_chunk.x - radius, center_chunk.x + radius + 1):
				if maxi(absi(cx - center_chunk.x), absi(cy - center_chunk.y)) == radius:
					coords.append(Vector2(cx, cy))
		if coords.is_empty():
			continue
		var packets: Array = world_core.call(
			"generate_chunk_packets_batch",
			PROBE_SEED,
			coords,
			WorldRuntimeConstants.WORLD_VERSION,
			settings_packed
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			var edge: Dictionary = _find_edge_tile_in_packet(packet)
			if not edge.is_empty():
				return edge
	return {}

func _find_dry_ground_target(lake_density: float) -> Dictionary:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for terrain ground probe.")
	if world_core == null:
		return {}
	var settings_packed: PackedFloat32Array = _settings_packed(lake_density)
	var spawn: Dictionary = world_core.call(
		"resolve_world_foundation_spawn_tile",
		PROBE_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	) as Dictionary
	var spawn_tile: Vector2i = spawn.get("spawn_tile", Vector2i.ZERO) as Vector2i
	return {
		"chunk": WorldRuntimeConstants.tile_to_chunk(spawn_tile),
		"local": WorldRuntimeConstants.tile_to_local(spawn_tile),
		"target_tile": spawn_tile,
		"water_neighbour_local": Vector2i(-1, -1),
	}

func _find_edge_tile_in_packet(packet: Dictionary) -> Dictionary:
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		if _is_water_surface_sample(int(terrain_ids[index]), lake_flags, index):
			continue
		var local: Vector2i = WorldRuntimeConstants.index_to_local(index)
		for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbour_local: Vector2i = local + offset
			if neighbour_local.x < 0 \
					or neighbour_local.y < 0 \
					or neighbour_local.x >= WorldRuntimeConstants.CHUNK_SIZE \
					or neighbour_local.y >= WorldRuntimeConstants.CHUNK_SIZE:
				continue
			var neighbour_index: int = WorldRuntimeConstants.local_to_index(neighbour_local)
			if _is_water_surface_sample(int(terrain_ids[neighbour_index]), lake_flags, neighbour_index):
				return {
					"chunk": chunk_coord,
					"local": local,
					"target_tile": chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local,
					"water_neighbour_local": neighbour_local,
				}
	return {}

func _is_water_surface_sample(terrain_id: int, lake_flags: PackedByteArray, index: int) -> bool:
	if index < 0 or index >= lake_flags.size():
		return false
	if (int(lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) == 0:
		return false
	return terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP

func _settings_packed(lake_density: float) -> PackedFloat32Array:
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var packed: PackedFloat32Array = _build_mountain_settings().flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	return _build_lake_settings(lake_density).write_to_settings_packed(packed)

func _build_mountain_settings() -> MountainGenSettings:
	var settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	settings.density = MOUNTAIN_DENSITY
	return settings

func _build_lake_settings(lake_density: float) -> LakeGenSettings:
	var settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	settings.density = lake_density
	return settings

func _compact_debug(debug: Dictionary) -> Dictionary:
	return {
		"ready_terrain_edge_mask_chunk_count": int(debug.get("ready_terrain_edge_mask_chunk_count", 0)),
		"terrain_edge_mask_cached_count": int(debug.get("terrain_edge_mask_cached_count", 0)),
		"terrain_edge_mask_inflight_count": int(debug.get("terrain_edge_mask_inflight_count", 0)),
		"terrain_edge_mask_visual_ready_count": int(debug.get("terrain_edge_mask_visual_ready_count", 0)),
		"terrain_edge_mask_visual_pending_count": int(debug.get("terrain_edge_mask_visual_pending_count", 0)),
		"terrain_edge_mask_visual_upload_queue_count": int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)),
		"terrain_ground_visible_chunk_count": int(debug.get("terrain_ground_visible_chunk_count", 0)),
		"terrain_ground_visible_without_mask_count": int(debug.get("terrain_ground_visible_without_mask_count", 0)),
		"terrain_ground_visible_without_visual_count": int(debug.get("terrain_ground_visible_without_visual_count", 0)),
		"visible_chunk_count": int(debug.get("visible_chunk_count", 0)),
		"packet_count": int(debug.get("packet_count", 0)),
	}

func _compact_target(target: Dictionary) -> Dictionary:
	return {
		"chunk": str(target.get("chunk", Vector2i.ZERO)),
		"local": str(target.get("local", Vector2i.ZERO)),
		"target_tile": str(target.get("target_tile", Vector2i.ZERO)),
		"water_neighbour_local": str(target.get("water_neighbour_local", Vector2i.ZERO)),
	}

func _capture_viewport(path: String) -> Dictionary:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var status: Dictionary = {
		"path": absolute_path,
		"saved": false,
	}
	if DisplayServer.get_name() == "headless":
		status["skipped"] = "headless"
		return status
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive(OUTPUT_DIR.trim_prefix("res://"))
	await process_frame
	await process_frame
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null:
		status["error"] = "viewport_image_null"
		return status
	status["image_size"] = Vector2i(image.get_width(), image.get_height())
	var png_bytes: PackedByteArray = image.save_png_to_buffer()
	status["png_bytes"] = png_bytes.size()
	if png_bytes.is_empty():
		status["error"] = "png_buffer_empty"
		return status
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status["error"] = "file_open_failed"
		return status
	file.store_buffer(png_bytes)
	file.close()
	status["saved"] = FileAccess.file_exists(path)
	return status

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true

func _finish() -> void:
	quit(1 if _failed else 0)
