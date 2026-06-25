extends SceneTree

# Проба «тени облаков гаснут ночью»: при высокой облачности снимает день/ночь/
# рассвет и изолирует слой облаков (с полем и без). Тени должны быть днём,
# исчезать ночью, частично проявляться на рассвете. Облачность-состояние при
# этом сохраняется (cover не меняем).
# Windowed:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/cloud_night_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const OUTPUT_DIR: String = "res://artifacts/cloud_night_probe"

var _streamer: Node = null
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cloud_night_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node("WorldStreamer")
	var tm: Node = root.get_node("TimeManager")
	var weather: Node = root.get_node("WeatherRuntime")
	var daylight: CanvasModulate = scene.get_node("Daylight") as CanvasModulate
	var field: Node2D = scene.get_node("CloudOccluderField") as Node2D
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
	cam.enabled = true
	cam.position_smoothing_enabled = false
	cam.set_process(false)
	cam.zoom = Vector2(0.5, 0.5)
	cam.set("_target_zoom", 0.5)
	DirAccess.open("res://").make_dir_recursive("artifacts/cloud_night_probe")
	await _settle()
	cam.force_update_scroll()

	weather.call("set_debug_cloud_cover", 0.7)

	var day_diff: float = await _layer_diff_at_hour(tm, daylight, field, "day", 12.0)
	var night_diff: float = await _layer_diff_at_hour(tm, daylight, field, "night", 0.0)
	var dawn_diff: float = await _layer_diff_at_hour(tm, daylight, field, "dawn", 6.0)

	weather.call("clear_debug_cloud_cover")
	print(
		"cloud_night_probe: shadow layer diff  day=%.4f dawn=%.4f night=%.4f" % [
			day_diff,
			dawn_diff,
			night_diff,
		],
	)
	_check(day_diff > 0.010, "днём тени облаков видны (diff=%.4f)" % day_diff)
	_check(night_diff < 0.003, "ночью тени облаков погасли (diff=%.4f)" % night_diff)
	_check(dawn_diff < day_diff and dawn_diff > night_diff, "на рассвете тени проявляются частично (%.4f)" % dawn_diff)

	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("cloud_night_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for f: String in _failures:
			print("cloud_night_probe: FAILED %s" % f)
		quit(1)


func _layer_diff_at_hour(tm: Node, daylight: CanvasModulate, field: Node2D, label: String, hour: float) -> float:
	tm.call("restore_persisted_state", hour, 1, 0)
	tm.call("set_paused", true)
	daylight.call("_sync_from_current_context", true)
	await _wait(40)
	var sun_factor: float = float(daylight.call("get_sun_day_factor")) if daylight.has_method("get_sun_day_factor") else -1.0
	var with_field: Image = await _capture()
	with_field.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	field.set_process(false)
	field.visible = false
	await _wait(6)
	var without_field: Image = await _capture()
	field.visible = true
	field.set_process(true)
	print(
		"cloud_night_probe: %s hour=%.0f sun_factor=%.3f field_visible=%s" % [
			label,
			hour,
			sun_factor,
			str(field.visible),
		],
	)
	return _mean_abs_diff(with_field, without_field)


func _mean_abs_diff(a: Image, b: Image) -> float:
	var ai: Image = a.duplicate() as Image
	var bi: Image = b.duplicate() as Image
	ai.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	bi.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	for y: int in range(ai.get_height()):
		for x: int in range(ai.get_width()):
			var ca: Color = ai.get_pixel(x, y)
			var cb: Color = bi.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(ai.get_width() * ai.get_height() * 3)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("cloud_night_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("cloud_night_probe: FAIL %s" % description)


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
