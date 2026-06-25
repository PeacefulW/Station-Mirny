extends SceneTree

# Render acceptance probe for Cloud Occlusion Iteration 3.
# It captures the live world scene and verifies that the shader cloud-shadow
# layer changes actual pixels. Static "node enabled" probes are not enough.
# Windowed:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/cloud_occlusion_render_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const OUTPUT_DIR: String = "res://artifacts/cloud_occlusion_render_probe"
const CLOUDY_FIELD_DIFF_MIN: float = 0.012
const SANCTUARY_FIELD_DIFF_MAX: float = 0.004

class MockIndoorBuildingSystem:
	extends Node

	func world_to_grid(_world_pos: Vector2) -> Vector2i:
		return Vector2i.ZERO

	func is_cell_indoor(_grid_pos: Vector2i) -> bool:
		return true


var _streamer: Node = null
var _failures: Array[String] = []


func _init() -> void:
	print("cloud_occlusion_render_probe: START")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("cloud_occlusion_render_probe must run windowed")
		_finish(null)
		return

	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	scene.get_node("HudLayer").visible = false
	_streamer = scene.get_node("WorldStreamer")
	var tm: Node = root.get_node("TimeManager")
	var weather: Node = root.get_node("WeatherRuntime")
	var wind: Node = root.get_node_or_null("WindRuntime")
	var field: Node2D = scene.get_node_or_null("CloudOccluderField") as Node2D
	var daylight: Node = scene.get_node_or_null("Daylight")
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
	cam.zoom = Vector2(0.5, 0.5)
	cam.set("_target_zoom", 0.5)
	DirAccess.open("res://").make_dir_recursive("artifacts/cloud_occlusion_render_probe")
	await _settle()
	cam.force_update_scroll()

	_check(field != null, "CloudOccluderField exists in live scene")
	if field == null:
		_finish(scene)
		return

	print("cloud_occlusion_render_probe: field_present=true renderer=world_space_shader children=%d" % field.get_child_count())

	var clear_luma: float = await _capture_regime(weather, "clear", "core:clear")
	var cloudy_luma: float = await _capture_regime(weather, "cloudy", "core:cloudy")
	var overcast_luma: float = await _capture_regime(weather, "overcast", "core:overcast")
	_check(overcast_luma < clear_luma * 0.92, "overcast is darker than clear")

	# Freeze wind before the A/B isolation. Otherwise grass/wind animation can
	# dominate the diff and hide the layer contribution.
	if wind != null:
		wind.call("set_debug_strength_override", 0.0)
		wind.set_process(false)
	# Видимость мерим на ЗАВЕДОМО облачном уровне (не на краю режима): порог
	# редкости mix(A, B, ...) — авторская настройка вкуса, и проба не должна от
	# неё падать. 0.65 даёт явные тучи при любом разумном A.
	weather.call("set_debug_cloud_cover", 0.65)
	if field.has_method("set_active_z_level"):
		field.call("set_active_z_level", 0)
	print("cloud_occlusion_render_probe: cloudy_cover=%.3f cloudy_occlusion=%.3f field_z=%d" % [
		float(weather.call("get_cloud_cover")),
		float(weather.call("get_cloud_occlusion")),
		field.z_index,
	])
	field.set_process(true)
	field.visible = true
	await _wait(12)
	var with_field: Image = await _capture()
	with_field.save_png("%s/cloudy_with_field.png" % OUTPUT_DIR)

	field.set_process(false)
	field.visible = false
	await _wait(3)
	var without_field: Image = await _capture()
	without_field.save_png("%s/cloudy_without_field.png" % OUTPUT_DIR)
	var field_diff: float = _mean_abs_diff(with_field, without_field)
	_save_amplified(with_field, without_field, 8.0, "%s/cloudy_shader_diff_x8.png" % OUTPUT_DIR)
	print("cloud_occlusion_render_probe: cloudy_shader_diff=%.5f threshold=%.5f" % [
		field_diff, CLOUDY_FIELD_DIFF_MIN,
	])
	if field_diff <= CLOUDY_FIELD_DIFF_MIN:
		_fail("cloudy shader layer changes rendered pixels")
		_finish(scene)
		return
	_check(true, "cloudy shader layer changes rendered pixels")

	# Sanctuary z-gate: the same cloudy frame with field processing active must
	# match the no-field baseline when the field is told it is not on surface.
	field.set_process(true)
	field.call("set_active_z_level", -1)
	await _wait(1)
	var z_gate: Image = await _capture()
	z_gate.save_png("%s/cloudy_z_gate.png" % OUTPUT_DIR)
	field.set_process(false)
	field.visible = false
	await _wait(1)
	var z_gate_without: Image = await _capture()
	z_gate_without.save_png("%s/cloudy_z_gate_without_field.png" % OUTPUT_DIR)
	var z_gate_diff: float = _mean_abs_diff(z_gate, z_gate_without)
	print("cloud_occlusion_render_probe: z_gate_diff=%.5f max=%.5f" % [
		z_gate_diff, SANCTUARY_FIELD_DIFF_MAX,
	])
	if z_gate_diff >= SANCTUARY_FIELD_DIFF_MAX:
		_fail("non-surface z gate disables cloud-shadow layer")
		_finish(scene)
		return
	_check(true, "non-surface z gate disables cloud-shadow layer")

	# Sanctuary roof gate: compare two close frames while a mock indoor building
	# system is active; Daylight is frozen so only the field gate is under test.
	if daylight != null:
		daylight.set_process(false)
	var mock_indoor := MockIndoorBuildingSystem.new()
	mock_indoor.name = "MockIndoorBuildingSystem"
	scene.add_child(mock_indoor)
	mock_indoor.add_to_group("building_system")
	field.call("set_active_z_level", 0)
	field.set("_building_system", null)
	field.set_process(true)
	await _wait(1)
	var roof_gate: Image = await _capture()
	roof_gate.save_png("%s/cloudy_roof_gate.png" % OUTPUT_DIR)
	field.set_process(false)
	field.visible = false
	await _wait(1)
	var roof_without: Image = await _capture()
	roof_without.save_png("%s/cloudy_roof_without_field.png" % OUTPUT_DIR)
	var roof_gate_diff: float = _mean_abs_diff(roof_gate, roof_without)
	print("cloud_occlusion_render_probe: roof_gate_diff=%.5f max=%.5f" % [
		roof_gate_diff, SANCTUARY_FIELD_DIFF_MAX,
	])
	if roof_gate_diff >= SANCTUARY_FIELD_DIFF_MAX:
		_fail("roof/indoor gate disables cloud-shadow layer")
		_finish(scene)
		return
	_check(true, "roof/indoor gate disables cloud-shadow layer")
	mock_indoor.queue_free()

	if wind != null:
		wind.set_process(true)
		wind.call("clear_debug_wind_override")
	weather.call("clear_debug_cloud_cover")
	weather.call("clear_debug_regime")
	print("cloud_occlusion_render_probe: luma clear=%.3f cloudy=%.3f overcast=%.3f" % [
		clear_luma, cloudy_luma, overcast_luma,
	])
	print("cloud_occlusion_render_probe: z_gate_diff=%.5f roof_gate_diff=%.5f max=%.5f" % [
		z_gate_diff, roof_gate_diff, SANCTUARY_FIELD_DIFF_MAX,
	])
	_finish(scene)


func _capture_regime(weather: Node, label: String, regime_id: StringName) -> float:
	weather.call("set_debug_regime", regime_id)
	await _wait(70)
	var img: Image = await _capture()
	img.save_png("%s/scene_%s.png" % [OUTPUT_DIR, label])
	return _frame_luma(img)


func _frame_luma(source: Image) -> float:
	var img: Image = source.duplicate() as Image
	img.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var total: float = 0.0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			total += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	return total / float(img.get_width() * img.get_height())


func _save_amplified(a: Image, b: Image, gain: float, path: String) -> void:
	var ai: Image = a.duplicate() as Image
	var bi: Image = b.duplicate() as Image
	var w: int = ai.get_width()
	var h: int = ai.get_height()
	bi.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
	for y: int in range(h):
		for x: int in range(w):
			var ca: Color = ai.get_pixel(x, y)
			var cb: Color = bi.get_pixel(x, y)
			var d: float = clampf((absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 * gain, 0.0, 1.0)
			out.set_pixel(x, y, Color(d, d, d))
	out.save_png(path)


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


func _check(passed: bool, description: String) -> void:
	if passed:
		print("cloud_occlusion_render_probe: PASS %s" % description)
	else:
		_fail(description)


func _fail(description: String) -> void:
	_failures.append(description)
	print("cloud_occlusion_render_probe: FAIL %s" % description)


func _finish(scene: Node) -> void:
	if scene != null:
		scene.queue_free()
	if _failures.is_empty():
		print("cloud_occlusion_render_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("cloud_occlusion_render_probe: FAILED %s" % failure)
		quit(1)
