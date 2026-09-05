extends SceneTree

# Windowed live-runtime perf probe for torch shadow-field movement hitches.
#
# Loads the real world scene, places the player by a generated mountain edge,
# enables the torch, moves the player across snapped shadow-field windows, and
# prints frame times plus WorldStreamer shadow-mask CPU timings.
#
# Run:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/mountain_torch_shadow_field_live_perf_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const TARGET_VIEWPORT_SIZE: Vector2i = Vector2i(1920, 1080)
const MAX_SETTLE_FRAMES: int = 900
const MEASURE_FRAMES: int = 420
const PROBE_NIGHT: Color = Color(0.025, 0.028, 0.038)
const TARGET_CAMERA_ZOOM: float = 0.2
const MAX_FRAME_P95_MS: float = 1000.0 / 60.0
const MAX_SINGLE_FRAME_MS: float = 20.0
const MAX_SHADOW_CPU_P95_MS: float = 2.0
const MAX_SHADOW_CPU_MS: float = 3.0
const MIN_COMPOSE_COUNT: int = 4

var _streamer: Node = null
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_torch_shadow_field_live_perf_probe: must run windowed")
		quit(1)
		return
	DisplayServer.window_set_size(TARGET_VIEWPORT_SIZE)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = TARGET_VIEWPORT_SIZE
	root.content_scale_size = TARGET_VIEWPORT_SIZE

	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame

	_streamer = scene.get_node_or_null("WorldStreamer")
	var daylight: CanvasModulate = scene.get_node_or_null("Daylight") as CanvasModulate
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var torch: PointLight2D = player.get_node_or_null("Torch") as PointLight2D if player != null else null
	var field: Node2D = scene.get_node_or_null("MountainTorchShadowField") as Node2D
	_assert(_streamer != null, "WorldStreamer exists")
	_assert(player != null, "Player exists")
	_assert(camera != null, "Camera exists")
	_assert(torch != null, "Torch exists")
	_assert(field != null, "MountainTorchShadowField exists")
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
	player.set_process(false)
	player.set_physics_process(false)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	camera.zoom = Vector2(TARGET_CAMERA_ZOOM, TARGET_CAMERA_ZOOM)
	camera.set("_target_zoom", TARGET_CAMERA_ZOOM)
	torch.enabled = true

	await _stream_until_stable()
	var home: Vector2 = player.global_position
	var mountain_offset: Vector2 = _find_mountain_offset(home)
	_assert(mountain_offset != Vector2.INF, "real mountain edge target found")
	if mountain_offset == Vector2.INF:
		scene.queue_free()
		quit(1)
		return
	var anchor: Vector2 = home + mountain_offset
	player.global_position = anchor
	camera.force_update_scroll()
	_streamer._update_player_chunk_coord()
	await _stream_until_stable()
	for _i: int in range(40):
		_streamer._streaming_tick()
		await process_frame

	print("live_perf anchor_tile=%s anchor_chunk=%s field_visible=%s" % [
		str(WorldRuntimeConstants.world_to_tile(anchor)),
		str(WorldRuntimeConstants.tile_to_chunk(WorldRuntimeConstants.world_to_tile(anchor))),
		str(field.visible),
	])

	var frame_samples: Array[float] = []
	var shadow_cpu_samples: Array[float] = []
	var compose_count: int = 0
	var cache_hit_count: int = 0
	var pending_count: int = 0
	var max_shadow_cpu_ms: float = 0.0
	var max_shadow_debug: Dictionary = {}

	frame_samples.resize(MEASURE_FRAMES)
	var previous_usec: int = Time.get_ticks_usec()
	for index: int in range(MEASURE_FRAMES):
		var phase: float = fmod(float(index) / 180.0, 2.0)
		var t: float = phase if phase <= 1.0 else 2.0 - phase
		player.global_position = anchor + Vector2(lerpf(-640.0, 640.0, t), 0.0)
		camera.force_update_scroll()
		_streamer._update_player_chunk_coord()
		_streamer._streaming_tick()
		await RenderingServer.frame_post_draw
		var now_usec: int = Time.get_ticks_usec()
		frame_samples[index] = float(now_usec - previous_usec) / 1000.0
		previous_usec = now_usec

		var debug: Dictionary = _streamer.call("get_mountain_torch_shadow_field_debug_state") as Dictionary
		var shadow_ms: float = float(debug.get("elapsed_ms_last", 0.0))
		shadow_cpu_samples.append(shadow_ms)
		if bool(debug.get("composed", false)):
			compose_count += 1
		if bool(debug.get("cache_hit", false)):
			cache_hit_count += 1
		if bool(debug.get("pending", false)):
			pending_count += 1
		if shadow_ms > max_shadow_cpu_ms:
			max_shadow_cpu_ms = shadow_ms
			max_shadow_debug = debug.duplicate()

	var frame_stats: Dictionary = _stats(frame_samples)
	var shadow_stats: Dictionary = _stats(shadow_cpu_samples)
	var final_debug: Dictionary = \
			_streamer.call("get_mountain_torch_shadow_field_debug_state") as Dictionary
	_assert(torch.enabled, "real player torch must remain enabled for the whole measurement")
	_assert(field.visible, "real mountain torch shadow overlay must be visible")
	_assert(
		int(final_debug.get("solid_sample_count", 0)) > 0,
		"stitched real-world mask must contain mountain pixels",
	)
	_assert(
		compose_count >= MIN_COMPOSE_COUNT,
		"movement must cross enough snapped mask windows; got %d" % compose_count,
	)
	_assert(
		float(frame_stats.get("p95_ms", INF)) <= MAX_FRAME_P95_MS,
		"torch-on real-world frame P95 exceeded 60 FPS budget: %s" % str(frame_stats),
	)
	_assert(
		float(frame_stats.get("max_ms", INF)) <= MAX_SINGLE_FRAME_MS,
		"torch-on movement produced a hitch: %s" % str(frame_stats),
	)
	_assert(
		float(shadow_stats.get("p95_ms", INF)) <= MAX_SHADOW_CPU_P95_MS,
		"torch mask P95 regressed: %s" % str(shadow_stats),
	)
	_assert(
		float(shadow_stats.get("max_ms", INF)) <= MAX_SHADOW_CPU_MS,
		"torch mask produced a main-thread spike: %s" % str(shadow_stats),
	)
	print("mountain_torch_shadow_field_live_perf_probe results:")
	print("frames avg_ms=%.3f p95_ms=%.3f max_ms=%.3f fps_avg=%.1f" % [
		float(frame_stats.get("avg_ms", 0.0)),
		float(frame_stats.get("p95_ms", 0.0)),
		float(frame_stats.get("max_ms", 0.0)),
		1000.0 / maxf(float(frame_stats.get("avg_ms", 1000.0)), 0.001),
	])
	print("shadow_cpu avg_ms=%.3f p95_ms=%.3f max_ms=%.3f compose_count=%d cache_hit_count=%d pending_count=%d max_debug=%s" % [
		float(shadow_stats.get("avg_ms", 0.0)),
		float(shadow_stats.get("p95_ms", 0.0)),
		float(shadow_stats.get("max_ms", 0.0)),
		compose_count,
		cache_hit_count,
		pending_count,
		str(max_shadow_debug),
	])

	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"avg_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var sum: float = 0.0
	for value: float in sorted:
		sum += value
	return {
		"avg_ms": sum / float(sorted.size()),
		"p95_ms": sorted[mini(sorted.size() - 1, int(floorf(float(sorted.size()) * 0.95)))],
		"max_ms": sorted[sorted.size() - 1],
	}


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
			if solids < 70 or solids > 220:
				continue
			var south_tile: Vector2i = _find_south_mountain_edge_tile(packet)
			if south_tile == Vector2i(-1, -1):
				continue
			var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
			var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + south_tile + Vector2i(0, 4)
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


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
