extends SceneTree

# Рендер-проба тонирования времени суток (DaylightSystem):
# кадры день/закат/ночь/рассвет + панель + авто-проверки:
# - ночь заметно темнее дня (средняя люма)
# - закат теплее дня (средний R/B)
# - рассвет по люме между ночью и днём.
# Windowed (захват вьюпорта требует GPU). Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --path . -s tools/day_night_tint_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/day_night_tint_probe"
const MAX_SETTLE_FRAMES: int = 600
const PANEL_DIVIDER_PX: int = 4
const CAPTURES: Array[Dictionary] = [
	{ "name": "day", "hour": 12.0 },
	{ "name": "dusk", "hour": 19.5 },
	{ "name": "night", "hour": 23.0 },
	{ "name": "dawn", "hour": 6.0 },
]

var _streamer: Node = null
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("day_night_tint_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var daylight: CanvasModulate = scene.get_node_or_null("Daylight") as CanvasModulate
	if daylight == null:
		push_error("day_night_tint_probe: Daylight node missing in world scene")
		quit(1)
		return
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
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
	camera.zoom = Vector2(0.45, 0.45)
	camera.set("_target_zoom", 0.45)
	DirAccess.open("res://").make_dir_recursive("artifacts/day_night_tint_probe")
	await _stream_until_stable()
	camera.force_update_scroll()

	var frames: Array[Image] = []
	var stats: Dictionary = { }
	for capture: Dictionary in CAPTURES:
		var capture_name: String = str(capture["name"])
		time_manager.call("set_paused", true)
		time_manager.call("restore_persisted_state", float(capture["hour"]), 1, 0)
		time_manager.call("set_paused", true)
		# Мгновенная синхронизация вместо ожидания плавного лерпа перехода.
		daylight._sync_from_current_context(true)
		_streamer._sync_sun_lighting_from_time(true)
		await _wait_frames(8)
		var img: Image = await _capture()
		img.save_png("%s/tint_%s.png" % [OUTPUT_DIR, capture_name])
		frames.append(img)
		stats[capture_name] = _frame_stats(img)
		print(
			"day_night_tint_probe: %s hour=%.1f stats=%s" % [
				capture_name,
				float(capture["hour"]),
				str(stats[capture_name]),
			],
		)
	_save_panel(frames, "%s/tint_panel.png" % OUTPUT_DIR)

	var day_luma: float = float((stats["day"] as Dictionary)["luma"])
	var dusk_warmth: float = float((stats["dusk"] as Dictionary)["warmth"])
	var day_warmth: float = float((stats["day"] as Dictionary)["warmth"])
	var night_luma: float = float((stats["night"] as Dictionary)["luma"])
	var dawn_luma: float = float((stats["dawn"] as Dictionary)["luma"])
	_check(night_luma < day_luma * 0.75, "ночь темнее дня (%.3f < %.3f)" % [night_luma, day_luma * 0.75])
	_check(dusk_warmth > day_warmth * 1.15, "закат теплее дня (%.3f > %.3f)" % [dusk_warmth, day_warmth * 1.15])
	_check(
		dawn_luma > night_luma and dawn_luma < day_luma,
		"рассвет между ночью и днём (%.3f..%.3f..%.3f)" % [night_luma, dawn_luma, day_luma],
	)

	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("day_night_tint_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("day_night_tint_probe: FAILED %s" % failure)
		quit(1)


func _frame_stats(source: Image) -> Dictionary:
	var img: Image = source.duplicate() as Image
	img.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var sum_r: float = 0.0
	var sum_g: float = 0.0
	var sum_b: float = 0.0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var pixel: Color = img.get_pixel(x, y)
			sum_r += pixel.r
			sum_g += pixel.g
			sum_b += pixel.b
	var count: float = float(img.get_width() * img.get_height())
	var avg_r: float = sum_r / count
	var avg_g: float = sum_g / count
	var avg_b: float = sum_b / count
	return {
		"luma": avg_r * 0.299 + avg_g * 0.587 + avg_b * 0.114,
		"warmth": avg_r / maxf(avg_b, 0.001),
	}


func _check(passed: bool, description: String) -> void:
	if passed:
		print("day_night_tint_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("day_night_tint_probe: FAIL %s" % description)


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


func _save_panel(frames: Array[Image], path: String) -> void:
	if frames.is_empty():
		return
	var frame_size: Vector2i = frames[0].get_size()
	var panel := Image.create(
		frame_size.x * frames.size() + PANEL_DIVIDER_PX * (frames.size() - 1),
		frame_size.y,
		false,
		frames[0].get_format(),
	)
	panel.fill(Color.BLACK)
	for index: int in range(frames.size()):
		panel.blit_rect(
			frames[index],
			Rect2i(Vector2i.ZERO, frame_size),
			Vector2i(index * (frame_size.x + PANEL_DIVIDER_PX), 0),
		)
	panel.save_png(path)
	print("day_night_tint_probe: panel saved %s" % ProjectSettings.globalize_path(path))
