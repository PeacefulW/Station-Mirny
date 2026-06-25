extends SceneTree

# Dev validation probe for the REAL in-scene 2D lighting (Iteration 1). Loads the
# world scene (which now owns the DaylightSystem sun + player Torch), drives the
# DaylightSystem ambient to day/night and toggles the player's Torch, and captures:
#   01 day, torch off        -> the true daytime look (no torch wash)
#   02 night, torch off      -> pitch black (zero visibility = intended)
#   03 night, torch on       -> warm torch pool in the dark
# Windowed (needs a GPU). Main scene untouched.
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/ground_light_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/ground_light_probe"
const ZOOM: float = 0.45
const MAX_SETTLE_FRAMES: int = 600
# Local mirrors of DaylightSystem ambient floors (avoid a static class reference
# that drags the EventBus autoload into this -s tool's compile step).
const PROBE_DAY: Color = Color(0.85, 0.85, 0.83)
const PROBE_NIGHT: Color = Color(0.03, 0.035, 0.05)

var _streamer: Node = null
var _daylight: CanvasModulate = null
var _torch: PointLight2D = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ground_light_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	_daylight = scene.get_node_or_null("Daylight") as CanvasModulate
	_torch = player.get_node_or_null("Torch") as PointLight2D

	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	_streamer.initialize_new_world(WorldRuntimeConstants.DEFAULT_WORLD_SEED, mountain, bounds, foundation, lakes)
	if time_manager != null:
		time_manager.call("set_paused", true)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.set("_target_zoom", ZOOM)

	await _stream_until_stable()
	DirAccess.open("res://").make_dir_recursive("artifacts/ground_light_probe")

	await _set_phase(PROBE_DAY, false)
	await _capture(camera, "01_day_torch_off")

	await _set_phase(PROBE_NIGHT, false)
	await _capture(camera, "02_night_torch_off")

	await _set_phase(PROBE_NIGHT, true)
	await _capture(camera, "03_night_torch_on")

	scene.queue_free()
	await process_frame
	quit(0)


# Force the DaylightSystem ambient and the torch, then let its _process settle the
# sun (energy/angle derive from the ambient brightness).
func _set_phase(ambient: Color, torch_on: bool) -> void:
	if _daylight != null:
		_daylight.color = ambient
		_daylight.set("_target_color", ambient)
	if _torch != null:
		_torch.enabled = torch_on
	for _f: int in range(24):
		await process_frame


func _capture(camera: Camera2D, label: String) -> void:
	camera.force_update_scroll()
	for _f: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("ground_light_probe: capture FAILED %s" % label)
		return
	img.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	print("ground_light_probe: saved %s/%s.png" % [ProjectSettings.globalize_path(OUTPUT_DIR), label])


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
