extends SceneTree

# Оконная проба ветрового движения травы (Iteration 4):
# - под сильным ветром трава движется (кадры во времени различаются)
# - в штиль (strength=0) движение замирает (gate глушит)
# - close-up при сильном ветре + высокой порывистости сохраняется для
#   визуальной проверки разнонаправленного наклона (синхронность сломана).
# Windowed:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/grass_wind_dir_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const OUTPUT_DIR: String = "res://artifacts/grass_wind_dir_probe"

var _streamer: Node = null
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("grass_wind_dir_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node("WorldStreamer")
	var tm: Node = root.get_node("TimeManager")
	var wind: Node = root.get_node("WindRuntime")
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
	cam.zoom = Vector2(1.3, 1.3)
	cam.set("_target_zoom", 1.3)
	DirAccess.open("res://").make_dir_recursive("artifacts/grass_wind_dir_probe")
	await _settle()
	cam.force_update_scroll()

	# Сильный ветер + высокая порывистость, фиксированное направление.
	wind.call("set_debug_direction_override_deg", 0.0)
	wind.call("set_debug_strength_override", 0.85)
	wind.call("set_debug_gustiness_override", 0.85)
	await _wait(24)
	var strong_a: Image = await _capture()
	strong_a.save_png("%s/strong_wind_closeup.png" % OUTPUT_DIR)
	await _wait(26)
	var strong_b: Image = await _capture()
	var motion_strong: float = _mean_abs_diff(strong_a, strong_b)

	# Штиль: сила 0 -> amplitude_gate 0 -> движение замирает.
	wind.call("set_debug_strength_override", 0.0)
	await _wait(24)
	var calm_a: Image = await _capture()
	await _wait(26)
	var calm_b: Image = await _capture()
	var motion_calm: float = _mean_abs_diff(calm_a, calm_b)

	wind.call("clear_debug_wind_override")

	print(
		"grass_wind_dir_probe: motion_strong=%.4f motion_calm=%.4f" % [motion_strong, motion_calm],
	)
	_check(motion_strong > 0.0015, "трава движется под сильным ветром (motion=%.4f)" % motion_strong)
	_check(
		motion_calm < motion_strong * 0.2,
		"в штиль движение замирает (calm=%.4f << strong=%.4f)" % [motion_calm, motion_strong],
	)

	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("grass_wind_dir_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for f: String in _failures:
			print("grass_wind_dir_probe: FAILED %s" % f)
		quit(1)


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
		print("grass_wind_dir_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("grass_wind_dir_probe: FAIL %s" % description)


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
