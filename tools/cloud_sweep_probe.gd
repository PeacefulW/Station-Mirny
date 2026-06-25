extends SceneTree

# Визуальный sweep облачности на ИГРОВОМ зуме (1.0): снимает кадры при разных
# cloud_cover, чтобы тюнить вид тучек (редкие -> растут -> сливаются в пасмурно).
# Windowed:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/cloud_sweep_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const OUTPUT_DIR: String = "res://artifacts/cloud_sweep_probe"
const COVERS: Array = [0.22, 0.40, 0.60, 0.85]

var _streamer: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cloud_sweep_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node("WorldStreamer")
	var tm: Node = root.get_node("TimeManager")
	var weather: Node = root.get_node("WeatherRuntime")
	var cam: Camera2D = scene.get_node("Player/Camera2D")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
	)
	tm.call("set_paused", true)
	tm.call("restore_persisted_state", 12.0, 1, 0)
	tm.call("set_paused", true)
	cam.enabled = true
	cam.position_smoothing_enabled = false
	cam.set_process(false)
	cam.zoom = Vector2(1.0, 1.0)
	cam.set("_target_zoom", 1.0)
	DirAccess.open("res://").make_dir_recursive("artifacts/cloud_sweep_probe")
	await _settle()
	cam.force_update_scroll()

	for cover_variant: Variant in COVERS:
		var cover: float = float(cover_variant)
		weather.call("set_debug_cloud_cover", cover)
		await _wait(40)
		var img: Image = await _capture()
		img.save_png("%s/cover_%02d.png" % [OUTPUT_DIR, int(round(cover * 100.0))])
		print("cloud_sweep_probe: cover=%.2f luma=%.3f saved" % [cover, _frame_luma(img)])
	weather.call("clear_debug_cloud_cover")
	print("cloud_sweep_probe: DONE")
	scene.queue_free()
	await process_frame
	quit(0)


func _frame_luma(source: Image) -> float:
	var img: Image = source.duplicate() as Image
	img.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			total += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	return total / float(img.get_width() * img.get_height())


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _wait(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _settle() -> void:
	for _i: int in range(500):
		_streamer._streaming_tick()
		_streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		if _streamer._requested_chunks.is_empty() and not _streamer._has_pending_streaming_work():
			return
