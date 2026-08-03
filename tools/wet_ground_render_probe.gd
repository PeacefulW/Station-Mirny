extends SceneTree
## Windowed visual proof for the shared wet-ground material. Captures the same
## spawn ground dry, fully wet at close zoom, and fully wet at wide/far zoom.

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIRECTORY: String = "res://artifacts/wet_ground_visual"
const MIN_SETTLE_FRAMES: int = 300
const MAX_SETTLE_FRAMES: int = 1800


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wet_ground_render_probe: windowed renderer required")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var packed_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame

	var streamer: Node = scene.get_node_or_null("WorldStreamer")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var presenter: Node = scene.get_node_or_null("GroundWetnessPresenter")
	var exposure_component: Node = scene.get_node_or_null("Player/ExposureComponent")
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var weather_runtime: Node = root.get_node_or_null("WeatherRuntime")
	if streamer == null or player == null or camera == null or presenter == null:
		push_error("wet_ground_render_probe: runtime scene wiring is incomplete")
		quit(1)
		return

	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	streamer.call(
		"initialize_new_world",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
	)
	if time_manager != null:
		time_manager.call("set_paused", true)
		time_manager.call("restore_persisted_state", 12.0, 1, 0)
		time_manager.call("set_paused", true)
	if weather_runtime != null:
		weather_runtime.call("set_debug_regime", &"core:clear")
		weather_runtime.call("set_debug_cloud_cover", 0.0)
		weather_runtime.call("set_debug_humidity", 0.0)

	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	var initial_envelope_ready: bool = false
	for frame_index: int in range(MAX_SETTLE_FRAMES):
		streamer.call("_streaming_tick")
		await process_frame
		if frame_index < MIN_SETTLE_FRAMES:
			continue
		var loading_state: Dictionary = streamer.call("get_initial_loading_state") as Dictionary
		if bool(loading_state.get("ready", false)):
			initial_envelope_ready = true
			break
	if not initial_envelope_ready:
		print(
			"wet_ground_render_probe: full initial envelope still streaming; "
			+ "capturing the populated local proof area",
		)
	var loading_surface: CanvasLayer = scene.get_node_or_null(
		"InitialLoadingScreen",
	) as CanvasLayer
	if loading_surface != null:
		loading_surface.visible = false

	var material: ShaderMaterial = WorldTileSetFactory.get_built_material_for_terrain(
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
	)
	if material == null:
		push_error("wet_ground_render_probe: shared plains material was not built")
		quit(1)
		return
	presenter.set_process(false)
	var directory: DirAccess = DirAccess.open("res://")
	if directory != null:
		directory.make_dir_recursive("artifacts/wet_ground_visual")

	material.set_shader_parameter("wet_ground_amount", 0.0)
	material.set_shader_parameter("wet_ground_rain_intensity", 0.0)
	await _capture(camera, 0.90, "%s/dry_close.png" % OUTPUT_DIRECTORY)

	material.set_shader_parameter("wet_ground_amount", 1.0)
	material.set_shader_parameter("wet_ground_rain_intensity", 1.0)
	if exposure_component != null and exposure_component.has_method("load_state"):
		exposure_component.call(
			"load_state",
			{
				"wetness": 0.72,
				"cold_load": 0.58,
			},
		)
	await _capture(camera, 0.90, "%s/wet_close.png" % OUTPUT_DIRECTORY)
	await _capture(camera, 0.45, "%s/wet_wide.png" % OUTPUT_DIRECTORY)
	await _capture(camera, 0.20, "%s/wet_far.png" % OUTPUT_DIRECTORY)

	material.set_shader_parameter("wet_ground_amount", 0.0)
	material.set_shader_parameter("wet_ground_rain_intensity", 0.0)
	if exposure_component != null and exposure_component.has_method("load_state"):
		exposure_component.call("load_state", { })
	if weather_runtime != null:
		weather_runtime.call("clear_debug_humidity")
		weather_runtime.call("clear_debug_cloud_cover")
		weather_runtime.call("clear_debug_regime")
	scene.queue_free()
	await process_frame
	print("wet_ground_render_probe: OK output=%s" % OUTPUT_DIRECTORY)
	quit(0)


func _capture(camera: Camera2D, zoom: float, path: String) -> void:
	camera.zoom = Vector2(zoom, zoom)
	camera.set("_target_zoom", zoom)
	camera.force_update_scroll()
	for frame_index: int in range(18):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("wet_ground_render_probe: capture failed for %s" % path)
		return
	image.save_png(path)
	print("wet_ground_render_probe: saved %s" % ProjectSettings.globalize_path(path))
