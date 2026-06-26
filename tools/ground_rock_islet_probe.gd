extends SceneTree

# Captures the real in-game plains ground (full ground_hybrid shader) day-lit at
# a wide composition zoom and a normal play zoom, to judge the bare-ground rock
# islet density before/after a shader tweak. Modeled on tools/ground_light_probe.gd.
# Windowed (needs a GPU).
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/ground_rock_islet_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/rock_islet"
const MAX_SETTLE_FRAMES: int = 600
const PROBE_DAY: Color = Color(0.85, 0.85, 0.83)

var _streamer: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ground_rock_islet_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var daylight: CanvasModulate = scene.get_node_or_null("Daylight") as CanvasModulate
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var torch: PointLight2D = player.get_node_or_null("Torch") as PointLight2D

	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	_streamer.initialize_new_world(WorldRuntimeConstants.DEFAULT_WORLD_SEED, mountain, bounds, foundation, lakes)
	if time_manager != null:
		time_manager.call("set_paused", true)
	if torch != null:
		torch.enabled = false
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	if daylight != null:
		daylight.color = PROBE_DAY
		daylight.set("_target_color", PROBE_DAY)

	await _stream_until_stable()
	for _f: int in range(24):
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	await _capture(camera, 0.45, "wide")
	await _capture(camera, 1.0, "play")

	scene.queue_free()
	await process_frame
	print("ground_rock_islet_probe: done -> %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _capture(camera: Camera2D, zoom: float, label: String) -> void:
	camera.zoom = Vector2(zoom, zoom)
	camera.set("_target_zoom", zoom)
	camera.force_update_scroll()
	for _f: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("ground_rock_islet_probe: capture FAILED %s" % label)
		return
	var path := "%s/%s.png" % [OUTPUT_DIR, label]
	img.save_png(path)
	print("ground_rock_islet_probe: saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])


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
				and not _streamer._has_pending_streaming_work():
			return
