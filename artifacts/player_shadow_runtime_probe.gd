extends SceneTree

# Рендер-проба тени игрока в РЕАЛЬНОМ мире (на зелёном биополе), а не в изоляции.
# Инстансим world_runtime_v0, стримим до стабильности, ставим дневные часы,
# наводим камеру на игрока, снимаем PNG. Windowed (захват требует GPU):
#   godot --path . -s artifacts/player_shadow_runtime_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/player_shadow_runtime_probe"
const MAX_SETTLE_FRAMES: int = 600
const CAPTURES: Array[Dictionary] = [
	{ "name": "morning_08", "hour": 8.0 },
	{ "name": "midday_12", "hour": 12.0 },
	{ "name": "afternoon_16", "hour": 16.0 },
]

var _streamer: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("player_shadow_runtime_probe: must run windowed")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(820, 760))
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var daylight: CanvasModulate = scene.get_node_or_null("Daylight") as CanvasModulate
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	if _streamer == null or daylight == null or time_manager == null or camera == null:
		push_error("runtime probe: missing nodes streamer=%s daylight=%s tm=%s cam=%s" % [
			_streamer, daylight, time_manager, camera,
		])
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
	time_manager.call("set_paused", true)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	camera.zoom = Vector2(3.0, 3.0)
	camera.set("_target_zoom", 3.0)
	DirAccess.open("res://").make_dir_recursive("artifacts/player_shadow_runtime_probe")
	await _stream_until_stable()
	camera.force_update_scroll()

	for capture: Dictionary in CAPTURES:
		var capture_name: String = str(capture["name"])
		time_manager.call("set_paused", true)
		time_manager.call("restore_persisted_state", float(capture["hour"]), 1, 0)
		time_manager.call("set_paused", true)
		daylight._sync_from_current_context(true)
		_streamer._sync_sun_lighting_from_time(true)
		await _wait_frames(10)
		camera.force_update_scroll()
		var img: Image = await _capture()
		img.save_png("%s/%s.png" % [OUTPUT_DIR, capture_name])
		print("player_shadow_runtime_probe: %s hour=%.1f saved" % [capture_name, float(capture["hour"])])

	scene.queue_free()
	await process_frame
	print("player_shadow_runtime_probe: DONE -> %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


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
