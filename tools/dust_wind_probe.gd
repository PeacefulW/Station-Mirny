extends SceneTree

# Проба летящей пыли: при фиксированном направлении снимает кадры на силе
# ветра 0.0 / 0.5 / 1.0 и проверяет, что количество пыли (отличие от штиля)
# растёт с силой — пыль работает как визуальный спидометр ветра.
# Windowed. Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --path . -s tools/dust_wind_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const OUTPUT_DIR: String = "res://artifacts/dust_wind_probe"

var _streamer: Node = null
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("dust_wind_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node("WorldStreamer")
	var tm: Node = root.get_node("TimeManager")
	var cam: Camera2D = scene.get_node("Player/Camera2D")
	var wind: Node = root.get_node("WindRuntime")
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
	cam.zoom = Vector2(0.7, 0.7)
	cam.set("_target_zoom", 0.7)
	wind.call("set_debug_direction_override_deg", 0.0)
	DirAccess.open("res://").make_dir_recursive("artifacts/dust_wind_probe")
	await _settle()
	cam.force_update_scroll()

	var calm: Image = await _capture_at_strength(wind, 0.0, "calm")
	var mid: Image = await _capture_at_strength(wind, 0.5, "mid")
	var storm: Image = await _capture_at_strength(wind, 1.0, "storm")
	var mid_diff: float = _mean_abs_diff(calm, mid)
	var storm_diff: float = _mean_abs_diff(calm, storm)
	print("dust_wind_probe: calm->mid diff=%.4f calm->storm diff=%.4f" % [mid_diff, storm_diff])
	_check(mid_diff > 0.001, "пыль появляется при среднем ветре (diff=%.4f)" % mid_diff)
	_check(storm_diff > mid_diff * 1.3, "пыль усиливается с силой (%.4f > %.4f)" % [storm_diff, mid_diff * 1.3])

	wind.call("clear_debug_wind_override")
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("dust_wind_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for f: String in _failures:
			print("dust_wind_probe: FAILED %s" % f)
		quit(1)


func _capture_at_strength(wind: Node, strength: float, label: String) -> Image:
	wind.call("set_debug_strength_override", strength)
	for _i: int in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/dust_%s.png" % [OUTPUT_DIR, label])
	return img


func _mean_abs_diff(a: Image, b: Image) -> float:
	var ai: Image = a.duplicate() as Image
	var bi: Image = b.duplicate() as Image
	ai.resize(240, 135, Image.INTERPOLATE_BILINEAR)
	bi.resize(240, 135, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	for y: int in range(ai.get_height()):
		for x: int in range(ai.get_width()):
			var ca: Color = ai.get_pixel(x, y)
			var cb: Color = bi.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(ai.get_width() * ai.get_height() * 3)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("dust_wind_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("dust_wind_probe: FAIL %s" % description)


func _settle() -> void:
	for _i: int in range(500):
		_streamer._streaming_tick()
		_streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		if _streamer._requested_chunks.is_empty() and not _streamer._has_pending_streaming_work():
			return
