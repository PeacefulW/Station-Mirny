extends SceneTree

# Проба облаков (Iteration 2): форсит режимы ясно/пасмурно и проверяет:
# - пасмурно темнее ясного (тон-сдвиг + тени облаков)
# - пасмурно холоднее ясного (R/B падает)
# - ясное небо почти без облачных теней (слой near-empty)
# - sanctuary: на underground погодный тон-сдвиг НЕ применяется (нейтрально).
# Кадры сохраняются. Windowed. Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --path . -s tools/weather_cloud_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const OUTPUT_DIR: String = "res://artifacts/weather_cloud_probe"

var _streamer: Node = null
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("weather_cloud_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node("WorldStreamer")
	var tm: Node = root.get_node("TimeManager")
	var weather: Node = root.get_node("WeatherRuntime")
	var daylight: CanvasModulate = scene.get_node("Daylight") as CanvasModulate
	var cloud: Sprite2D = scene.get_node("CloudShadowOverlay") as Sprite2D
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
	cam.zoom = Vector2(0.4, 0.4)
	cam.set("_target_zoom", 0.4)
	DirAccess.open("res://").make_dir_recursive("artifacts/weather_cloud_probe")
	await _settle()
	cam.force_update_scroll()

	var clear_stats: Dictionary = await _capture_regime(weather, daylight, "clear", "core:clear")
	var overcast_stats: Dictionary = await _capture_regime(weather, daylight, "overcast", "core:overcast")

	# Облачные тени при ясном небе: слой near-empty (diff со скрытым слоём мал).
	weather.call("set_debug_regime", &"core:clear")
	daylight._sync_from_current_context(true)
	await _wait(60)
	var clear_with: Image = await _capture()
	cloud.visible = false
	await _wait(4)
	var clear_without: Image = await _capture()
	cloud.visible = true
	var clear_cloud_diff: float = _mean_abs_diff(clear_with, clear_without)

	# Облачные тени при пасмурном небе: слой заметно вкладывается в кадр.
	weather.call("set_debug_regime", &"core:overcast")
	daylight._sync_from_current_context(true)
	await _wait(60)
	var overcast_with: Image = await _capture()
	cloud.visible = false
	await _wait(4)
	var overcast_without: Image = await _capture()
	cloud.visible = true
	var overcast_cloud_diff: float = _mean_abs_diff(overcast_with, overcast_without)

	# Sanctuary: underground при overcast НЕ темнеет от погоды.
	weather.call("set_debug_regime", &"core:overcast")
	daylight.set_active_z_level(1)
	daylight._sync_from_current_context(true)
	await _wait(80)
	var underground_color: Color = daylight.color
	daylight.set_active_z_level(0)
	weather.call("clear_debug_regime")

	print(
		"weather_cloud_probe: clear luma=%.3f warmth=%.3f | overcast luma=%.3f warmth=%.3f" % [
			clear_stats["luma"],
			clear_stats["warmth"],
			overcast_stats["luma"],
			overcast_stats["warmth"],
		],
	)
	print(
		"weather_cloud_probe: clear_cloud_diff=%.4f overcast_cloud_diff=%.4f underground_color=%s" % [
			clear_cloud_diff,
			overcast_cloud_diff,
			str(underground_color),
		],
	)
	_check(
		float(overcast_stats["luma"]) < float(clear_stats["luma"]) * 0.9,
		"пасмурно темнее ясного (%.3f < %.3f)" % [overcast_stats["luma"], float(clear_stats["luma"]) * 0.9],
	)
	_check(
		float(overcast_stats["warmth"]) < float(clear_stats["warmth"]),
		"пасмурно холоднее ясного (%.3f < %.3f)" % [overcast_stats["warmth"], clear_stats["warmth"]],
	)
	# Облачный слой лежит ПОД Daylight-модуляцией: при пасмурном тон-сдвиг
	# затемняет весь кадр, и тёмные тени поверх уже тёмного дают малую
	# абсолютную дельту (dark-on-dark). Поэтому абсолютный порог скромный, а
	# главное доказательство присутствия — относительная проверка ниже.
	_check(overcast_cloud_diff > 0.0025, "облачные тени присутствуют при пасмурно (diff=%.4f)" % overcast_cloud_diff)
	_check(
		overcast_cloud_diff > clear_cloud_diff * 2.0,
		"теней при пасмурно заметно больше чем при ясно (%.4f > %.4f)" % [overcast_cloud_diff, clear_cloud_diff * 2.0],
	)
	_check(
		underground_color.r > 0.9 and underground_color.b > 0.9,
		"sanctuary: underground не затемнён погодой (color=%s)" % str(underground_color),
	)

	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("weather_cloud_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for f: String in _failures:
			print("weather_cloud_probe: FAILED %s" % f)
		quit(1)


func _capture_regime(weather: Node, daylight: CanvasModulate, label: String, regime_id: StringName) -> Dictionary:
	weather.call("set_debug_regime", regime_id)
	daylight._sync_from_current_context(true)
	await _wait(80)
	var img: Image = await _capture()
	img.save_png("%s/cloud_%s.png" % [OUTPUT_DIR, label])
	return _frame_stats(img)


func _frame_stats(source: Image) -> Dictionary:
	var img: Image = source.duplicate() as Image
	img.resize(200, 112, Image.INTERPOLATE_BILINEAR)
	var sr: float = 0.0
	var sg: float = 0.0
	var sb: float = 0.0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			sr += c.r
			sg += c.g
			sb += c.b
	var n: float = float(img.get_width() * img.get_height())
	var ar: float = sr / n
	var ag: float = sg / n
	var ab: float = sb / n
	return { "luma": ar * 0.299 + ag * 0.587 + ab * 0.114, "warmth": ar / maxf(ab, 0.001) }


func _mean_abs_diff(a: Image, b: Image) -> float:
	var ai: Image = a.duplicate() as Image
	var bi: Image = b.duplicate() as Image
	ai.resize(200, 112, Image.INTERPOLATE_BILINEAR)
	bi.resize(200, 112, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	for y: int in range(ai.get_height()):
		for x: int in range(ai.get_width()):
			var ca: Color = ai.get_pixel(x, y)
			var cb: Color = bi.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(ai.get_width() * ai.get_height() * 3)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("weather_cloud_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("weather_cloud_probe: FAIL %s" % description)


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
