extends SceneTree

# Windowed live-runtime probe for torch mountain occlusion.
# Loads world_runtime_v0, finds a real generated south mountain edge, places the
# player/torch just below it, captures no-occluder vs occluder frames, and prints
# near-chunk LightOccluder2D counts.
#
# Run:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/mountain_torch_live_occluder_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/mountain_torch_live_occluder_probe"
const MAX_SETTLE_FRAMES: int = 900
const PROBE_NIGHT: Color = Color(0.025, 0.028, 0.038)

var _streamer: Node = null
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_torch_live_occluder_probe: must run windowed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var daylight: CanvasModulate = scene.get_node_or_null("Daylight") as CanvasModulate
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var torch: PointLight2D = player.get_node_or_null("Torch") as PointLight2D
	_assert(_streamer != null, "WorldStreamer exists")
	_assert(player != null, "Player exists")
	_assert(camera != null, "Camera exists")
	_assert(torch != null, "Torch exists")
	if _failed:
		quit(1)
		return

	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		mountain,
		bounds,
		foundation,
		lakes,
	)
	if time_manager != null:
		time_manager.call("restore_persisted_state", 23.0, 1, 0)
		time_manager.call("set_paused", true)
	if daylight != null and daylight.has_method("_sync_from_current_context"):
		daylight.call("_sync_from_current_context", true)
	if _streamer.has_method("_sync_sun_lighting_from_time"):
		_streamer.call("_sync_sun_lighting_from_time", true)
	if daylight != null:
		daylight.color = PROBE_NIGHT
		daylight.set("_target_color", PROBE_NIGHT)
	if player.has_method("set_process"):
		player.set_process(false)
	if player.has_method("set_physics_process"):
		player.set_physics_process(false)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	camera.zoom = Vector2(1.25, 1.25)
	camera.set("_target_zoom", 1.25)
	torch.enabled = true

	await _stream_until_stable()
	var home: Vector2 = player.global_position
	var mountain_offset: Vector2 = _find_mountain_offset(home)
	_assert(mountain_offset != Vector2.INF, "real mountain edge target found")
	if mountain_offset == Vector2.INF:
		scene.queue_free()
		quit(1)
		return
	player.global_position = home + mountain_offset
	camera.force_update_scroll()
	_streamer._update_player_chunk_coord()
	await _stream_until_stable()
	_streamer._update_player_chunk_coord()
	for _i: int in range(16):
		_streamer._streaming_tick()
		await process_frame
	var target_tile: Vector2i = WorldRuntimeConstants.world_to_tile(player.global_position)
	print("live_probe player_tile=%s player_chunk=%s" % [
		str(target_tile),
		str(WorldRuntimeConstants.tile_to_chunk(target_tile)),
	])

	_set_near_occluders_enabled(false)
	await _wait(12)
	var no_occ: Image = await _capture("01_no_occluders")
	_set_near_occluders_enabled(true)
	_sync_near_occluders()
	await _wait(12)
	var with_occ: Image = await _capture("02_with_occluders")
	var summary: Dictionary = _summarize_near_occluders(target_tile)
	print("live_probe occluder_summary=%s" % str(summary))
	print("live_probe mean_abs_diff=%.5f" % _mean_abs_diff(no_occ, with_occ))

	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _set_near_occluders_enabled(enabled: bool) -> void:
	for chunk_variant: Variant in _streamer._chunk_views.keys():
		var view: Node = _streamer._chunk_views.get(chunk_variant)
		if view != null and view.has_method("set_mountain_light_occluders_enabled"):
			view.call("set_mountain_light_occluders_enabled", enabled)


func _sync_near_occluders() -> void:
	for chunk_variant: Variant in _streamer._chunk_views.keys():
		var view: Node = _streamer._chunk_views.get(chunk_variant)
		if view != null and view.has_method("sync_mountain_light_occluders"):
			view.call("sync_mountain_light_occluders")


func _summarize_near_occluders(player_tile: Vector2i) -> Dictionary:
	var player_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(player_tile)
	var total_count: int = 0
	var enabled_chunks: int = 0
	var chunks: Array[Dictionary] = []
	for chunk_variant: Variant in _streamer._chunk_views.keys():
		var chunk_coord: Vector2i = chunk_variant as Vector2i
		if maxi(absi(chunk_coord.x - player_chunk.x), absi(chunk_coord.y - player_chunk.y)) > 1:
			continue
		var view: Node = _streamer._chunk_views.get(chunk_variant)
		if view == null or not view.has_method("get_mountain_light_occluder_debug_state"):
			continue
		var debug: Dictionary = view.call("get_mountain_light_occluder_debug_state") as Dictionary
		var count: int = int(debug.get("occluder_count", 0))
		total_count += count
		if bool(debug.get("enabled", false)):
			enabled_chunks += 1
		chunks.append({
			"chunk": chunk_coord,
			"enabled": bool(debug.get("enabled", false)),
			"dirty": bool(debug.get("dirty", false)),
			"count": count,
			"closed": int(debug.get("closed_count", 0)),
			"max_verts": int(debug.get("max_verts", 0)),
		})
	return {
		"player_chunk": player_chunk,
		"enabled_chunks": enabled_chunks,
		"total_occluders": total_count,
		"chunks": chunks,
	}


func _capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		_assert(false, "capture failed %s" % label)
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	print("live_probe saved %s/%s.png" % [ProjectSettings.globalize_path(OUTPUT_DIR), label])
	return img


func _mean_abs_diff(a: Image, b: Image) -> float:
	var ai: Image = a.duplicate() as Image
	var bi: Image = b.duplicate() as Image
	ai.resize(180, 120, Image.INTERPOLATE_BILINEAR)
	bi.resize(180, 120, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	for y: int in range(ai.get_height()):
		for x: int in range(ai.get_width()):
			var ca: Color = ai.get_pixel(x, y)
			var cb: Color = bi.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(ai.get_width() * ai.get_height() * 3)


func _find_mountain_offset(home: Vector2) -> Vector2:
	var core: Object = ClassDB.instantiate("WorldCore")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	packed = lakes.write_to_settings_packed(packed)
	var home_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(WorldRuntimeConstants.world_to_tile(home))
	for radius: int in range(1, 25):
		var coords := PackedVector2Array()
		for cy: int in range(home_chunk.y - radius, home_chunk.y + radius + 1):
			for cx: int in range(home_chunk.x - radius, home_chunk.x + radius + 1):
				if maxi(absi(cx - home_chunk.x), absi(cy - home_chunk.y)) == radius:
					coords.append(Vector2(cx, cy))
		var packets: Array = core.call(
			"generate_chunk_packets_batch",
			WorldRuntimeConstants.DEFAULT_WORLD_SEED,
			coords,
			WorldRuntimeConstants.WORLD_VERSION,
			packed,
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			var solids: int = _mountain_solid_count(packet)
			if solids < 70 or solids > 200:
				continue
			var south_tile: Vector2i = _find_south_mountain_edge_tile(packet)
			if south_tile == Vector2i(-1, -1):
				continue
			var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
			var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + south_tile + Vector2i(0, 4)
			print("live_probe target chunk=%s south_tile=%s stand_tile=%s" % [
				str(chunk_coord),
				str(south_tile),
				str(world_tile),
			])
			return WorldRuntimeConstants.tile_to_world_center(world_tile) - home
	return Vector2.INF


func _find_south_mountain_edge_tile(packet: Dictionary) -> Vector2i:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	if terrain_ids.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return Vector2i(-1, -1)
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE - 6, 1, -1):
		for x: int in range(2, WorldRuntimeConstants.CHUNK_SIZE - 2):
			var terrain_id: int = int(terrain_ids[y * WorldRuntimeConstants.CHUNK_SIZE + x])
			var below_id: int = int(terrain_ids[(y + 1) * WorldRuntimeConstants.CHUNK_SIZE + x])
			var solid: bool = terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
			var below_open: bool = below_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					and below_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
			if solid and below_open:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _mountain_solid_count(packet: Dictionary) -> int:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var count: int = 0
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			count += 1
	return count


func _stream_until_stable() -> void:
	for _tick: int in range(MAX_SETTLE_FRAMES):
		_streamer._streaming_tick()
		if _streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			_streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
		if _streamer._requested_chunks.is_empty() \
				and int(debug.get("native_mask_inflight_count", 0)) == 0 \
				and int(debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_inflight_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("grass_scatter_visual_upload_queue_count", 0)) == 0 \
				and not _streamer._has_pending_streaming_work():
			return


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
