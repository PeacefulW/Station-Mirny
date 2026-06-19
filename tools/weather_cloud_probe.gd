extends SceneTree

# Проба облаков (Iteration 2b): форсит режимы ясно/облачно/пасмурно и проверяет:
# - cloudy даёт пик больших отдельных теней
# - overcast темнее/холоднее clear, но отдельные тени в нём слабее, чем cloudy
# - overcast flatten снижает локальный контраст и насыщенность
# - sun rays существуют как редкий cloudy-акцент и уходят ниже noise floor в overcast
# - sanctuary: underground погодный тон-сдвиг/flatten НЕ применяются (нейтрально).
# Кадры сохраняются. Windowed. Запуск:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/weather_cloud_probe.gd

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
	var dust: Sprite2D = scene.get_node("DustWindOverlay") as Sprite2D
	var cloud: Sprite2D = scene.get_node("CloudShadowOverlay") as Sprite2D
	var flatten: Sprite2D = scene.get_node_or_null("OvercastFlattenOverlay") as Sprite2D
	var sun_rays: Sprite2D = scene.get_node_or_null("SunRayOverlay") as Sprite2D
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
	var cloudy_stats: Dictionary = await _capture_regime(weather, daylight, "cloudy", "core:cloudy")
	var overcast_stats: Dictionary = await _capture_regime(weather, daylight, "overcast", "core:overcast")

	# Изолируем вклад конкретных движущихся слоёв: иначе diff ловит drift
	# соседнего overlay или downstream-изменение screen-texture flatten pass.
	var clear_cloud_diff: float = await _layer_diff(weather, daylight, cloud, &"core:clear", [dust, flatten, sun_rays])
	var cloudy_cloud_diff: float = await _layer_diff(weather, daylight, cloud, &"core:cloudy", [dust, flatten, sun_rays])
	var overcast_cloud_diff: float = await _layer_diff(weather, daylight, cloud, &"core:overcast", [dust, flatten, sun_rays])
	var cloudy_ray_diff: float = await _layer_diff(weather, daylight, sun_rays, &"core:cloudy", [dust, cloud, flatten])
	var overcast_ray_diff: float = await _layer_diff(weather, daylight, sun_rays, &"core:overcast", [dust, cloud, flatten])

	# Sanctuary: underground при overcast НЕ темнеет от погоды.
	weather.call("set_debug_regime", &"core:overcast")
	daylight.set_active_z_level(1)
	if flatten != null and flatten.has_method("set_active_z_level"):
		flatten.call("set_active_z_level", 1)
	if cloud.has_method("set_active_z_level"):
		cloud.call("set_active_z_level", 1)
	daylight._sync_from_current_context(true)
	await _wait(80)
	var underground_color: Color = daylight.color
	var underground_cloud_cover: float = float(
		(cloud.material as ShaderMaterial).get_shader_parameter("cloud_cover"),
	)
	daylight.set_active_z_level(0)
	if flatten != null and flatten.has_method("set_active_z_level"):
		flatten.call("set_active_z_level", 0)
	if cloud.has_method("set_active_z_level"):
		cloud.call("set_active_z_level", 0)
	weather.call("clear_debug_regime")

	print(
		"weather_cloud_probe: clear luma=%.3f warmth=%.3f sat=%.3f contrast=%.3f | cloudy luma=%.3f warmth=%.3f sat=%.3f contrast=%.3f | overcast luma=%.3f warmth=%.3f sat=%.3f contrast=%.3f" % [
			clear_stats["luma"],
			clear_stats["warmth"],
			clear_stats["saturation"],
			clear_stats["local_contrast"],
			cloudy_stats["luma"],
			cloudy_stats["warmth"],
			cloudy_stats["saturation"],
			cloudy_stats["local_contrast"],
			overcast_stats["luma"],
			overcast_stats["warmth"],
			overcast_stats["saturation"],
			overcast_stats["local_contrast"],
		],
	)
	print(
		"weather_cloud_probe: clear_cloud_diff=%.4f cloudy_cloud_diff=%.4f overcast_cloud_diff=%.4f cloudy_ray_diff=%.4f overcast_ray_diff=%.4f underground_color=%s" % [
			clear_cloud_diff,
			cloudy_cloud_diff,
			overcast_cloud_diff,
			cloudy_ray_diff,
			overcast_ray_diff,
			str(underground_color),
		],
	)
	_check(flatten != null, "OvercastFlattenOverlay присутствует в сцене")
	_check(sun_rays != null, "SunRayOverlay присутствует в сцене")
	_check(
		float(overcast_stats["luma"]) < float(clear_stats["luma"]) * 0.9,
		"пасмурно темнее ясного (%.3f < %.3f)" % [overcast_stats["luma"], float(clear_stats["luma"]) * 0.9],
	)
	_check(
		float(overcast_stats["warmth"]) < float(clear_stats["warmth"]),
		"пасмурно холоднее ясного (%.3f < %.3f)" % [overcast_stats["warmth"], clear_stats["warmth"]],
	)
	_check(
		cloudy_cloud_diff > clear_cloud_diff * 2.5,
		"cloudy даёт заметные отдельные тени (%.4f > %.4f)" % [cloudy_cloud_diff, clear_cloud_diff * 2.5],
	)
	_check(
		overcast_cloud_diff < cloudy_cloud_diff * 0.60,
		"overcast гасит отдельные тени относительно cloudy (%.4f < %.4f)" % [
			overcast_cloud_diff,
			cloudy_cloud_diff * 0.60,
		],
	)
	_check(
		float(cloudy_stats["local_contrast"]) > float(overcast_stats["local_contrast"]) * 1.08,
		"cloudy контрастнее overcast (%.3f > %.3f)" % [
			cloudy_stats["local_contrast"],
			float(overcast_stats["local_contrast"]) * 1.08,
		],
	)
	_check(
		float(overcast_stats["saturation"]) < float(clear_stats["saturation"]) * 0.86,
		"overcast заметно десатурирован относительно clear (%.3f < %.3f)" % [
			overcast_stats["saturation"],
			float(clear_stats["saturation"]) * 0.86,
		],
	)
	_check(
		cloudy_ray_diff > 0.003
		and overcast_ray_diff < 0.003
		and cloudy_ray_diff > overcast_ray_diff * 1.25,
		"sun rays редкий cloudy-акцент, overcast ниже noise floor (cloudy=%.4f overcast=%.4f)" % [
			cloudy_ray_diff,
			overcast_ray_diff,
		],
	)
	_check(
		underground_color.r > 0.9 and underground_color.b > 0.9,
		"sanctuary: underground не затемнён погодой (color=%s)" % str(underground_color),
	)
	_check(
		underground_cloud_cover <= 0.001,
		"sanctuary: тени облаков выключены под землёй (cloud_cover=%.3f)" % underground_cloud_cover,
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
	var luma_values: Array[float] = []
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			sr += c.r
			sg += c.g
			sb += c.b
			luma_values.append(c.r * 0.299 + c.g * 0.587 + c.b * 0.114)
	var n: float = float(img.get_width() * img.get_height())
	var ar: float = sr / n
	var ag: float = sg / n
	var ab: float = sb / n
	var luma: float = ar * 0.299 + ag * 0.587 + ab * 0.114
	var saturation: float = 0.0
	var local_contrast: float = 0.0
	for i: int in range(luma_values.size()):
		local_contrast += absf(luma_values[i] - luma)
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var cmax: float = maxf(c.r, maxf(c.g, c.b))
			var cmin: float = minf(c.r, minf(c.g, c.b))
			saturation += cmax - cmin
	return {
		"luma": luma,
		"warmth": ar / maxf(ab, 0.001),
		"saturation": saturation / n,
		"local_contrast": local_contrast / n,
	}


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


func _layer_diff(
		weather: Node,
		daylight: CanvasModulate,
		layer: Sprite2D,
		regime_id: StringName,
		hidden_during_measure: Array,
) -> float:
	if layer == null:
		return 0.0
	var original_layer_visible: bool = layer.visible
	var original_layer_processing: bool = layer.is_processing()
	var hidden_originals: Dictionary = { }
	var hidden_processing_originals: Dictionary = { }
	for hidden_variant: Variant in hidden_during_measure:
		var hidden: CanvasItem = hidden_variant as CanvasItem
		if hidden == null or hidden == layer:
			continue
		hidden_originals[hidden] = hidden.visible
		hidden_processing_originals[hidden] = hidden.is_processing()
		hidden.set_process(false)
		hidden.visible = false
	weather.call("set_debug_regime", regime_id)
	daylight._sync_from_current_context(true)
	await _wait(60)
	layer.set_process(false)
	layer.visible = true
	var with_layer: Image = await _capture()
	layer.visible = false
	await _wait(4)
	var without_layer: Image = await _capture()
	layer.visible = original_layer_visible
	layer.set_process(original_layer_processing)
	for hidden_key: Variant in hidden_originals.keys():
		var hidden_layer: CanvasItem = hidden_key as CanvasItem
		if hidden_layer != null:
			hidden_layer.visible = bool(hidden_originals[hidden_key])
			hidden_layer.set_process(bool(hidden_processing_originals[hidden_key]))
	return _mean_abs_diff(with_layer, without_layer)


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
