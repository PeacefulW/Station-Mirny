extends SceneTree

# Static/smoke probe for Cloud Occlusion Lighting Iteration 3 wiring.
# This does NOT prove visual shadow darkness; use cloud_occlusion_render_probe.gd
# for acceptance. It only guards the shader-layer contract.
# Запуск:
#   Godot_v4.7-stable_win64_console.exe --headless --path . -s tools/cloud_occluder_field_probe.gd

const FIELD_SCRIPT_PATH: String = "res://core/systems/world/cloud_occluder_field.gd"
const FIELD_SHADER_PATH: String = "res://assets/shaders/cloud_occluder_field.gdshader"
const DAYLIGHT_PATH: String = "res://core/systems/daylight/daylight_system.gd"
const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const SPEC_PATH: String = "res://docs/02_system_specs/world/cloud_occlusion_lighting.md"
const RESIZED_VIEWPORT: Vector2i = Vector2i(1792, 1008)
const VIEW_MARGIN: float = 1.06

var _failures: Array[String] = []


func _init() -> void:
	print("cloud_occluder_field_probe: START")
	call_deferred("_run")


func _run() -> void:
	var field_script: Script = ResourceLoader.load(FIELD_SCRIPT_PATH) as Script
	var field_shader: Shader = ResourceLoader.load(FIELD_SHADER_PATH) as Shader
	_check(field_script != null, "CloudOccluderField script loads")
	_check(field_shader != null, "cloud occluder shader loads")
	if field_script == null or field_shader == null:
		_finish()
		return

	var world := Node2D.new()
	root.add_child(world)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(512.0, 512.0)
	camera.zoom = Vector2(0.2, 0.2)
	camera.make_current()
	root.size = RESIZED_VIEWPORT
	await process_frame

	var field: Node2D = field_script.new() as Node2D
	world.add_child(field)
	await process_frame

	var weather: Node = root.get_node_or_null("WeatherRuntime")
	_check(weather != null, "WeatherRuntime autoload available")
	if weather == null:
		_finish()
		return

	weather.call("set_debug_regime", &"core:clear")
	field._process(0.016)
	_check(not field.visible, "clear cover hides cloud-shadow shader layer")

	weather.call("set_debug_regime", &"core:cloudy")
	field._process(0.016)
	_check(field.visible, "cloudy cover shows cloud-shadow shader layer")
	_check(field is Sprite2D, "cloud-shadow field is a Sprite2D overlay")
	_check(field.z_index == 395, "cloud-shadow field uses overlay z above world terrain")
	_check(field.get_child_count() == 0, "field has no Light2D blob children")
	_check(_no_light_children(field), "field does not use PointLight2D or LightOccluder2D")
	_check(field.material is ShaderMaterial, "field owns ShaderMaterial")
	var viewport: Viewport = field.get_viewport()
	var world_from_canvas: Transform2D = viewport.canvas_transform.affine_inverse()
	var expected_world_size: Vector2 = (
		world_from_canvas * Vector2(RESIZED_VIEWPORT)
		- world_from_canvas * Vector2.ZERO
	).abs()
	var expected_overlay_scale: Vector2 = expected_world_size * VIEW_MARGIN
	_check(
		field.scale.is_equal_approx(expected_overlay_scale),
		"weather overlay covers the resized viewport instead of authored 1280x720",
	)

	if field.has_method("set_active_z_level"):
		field.call("set_active_z_level", -1)
		field._process(0.016)
		_check(not field.visible, "non-surface z hides cloud-shadow shader layer")

	var scene_source: String = FileAccess.get_file_as_string(WORLD_SCENE_PATH)
	var daylight_source: String = FileAccess.get_file_as_string(DAYLIGHT_PATH)
	var field_source: String = FileAccess.get_file_as_string(FIELD_SCRIPT_PATH)
	var shader_source: String = FileAccess.get_file_as_string(FIELD_SHADER_PATH)
	var spec_source: String = FileAccess.get_file_as_string(SPEC_PATH)
	_check(scene_source.contains("CloudOccluderField"), "world_runtime_v0 wires CloudOccluderField")
	_check(scene_source.contains("[node name=\"CloudOccluderField\" type=\"Sprite2D\""), "world_runtime_v0 instantiates CloudOccluderField as Sprite2D")
	_check(daylight_source.contains("SUN_CLOUD_SHADOW_ITEM_CULL_MASK: int = 1 << 8"), "sun cloud shadow mask is non-default")
	_check(field_source.contains("extends WorldViewOverlay"), "CloudOccluderField is a world-space shader overlay")
	_check(not field_source.contains("BLEND_MODE_SUB"), "subtractive Light2D blob renderer removed")
	_check(shader_source.contains("shadow_color") and shader_source.contains("cloud_cover"), "shader has cold shadow and weather inputs")
	_check(shader_source.contains("wind_gust_scroll_px"), "shader drift uses integrated wind scroll")
	_check(not shader_source.contains("wind_time"), "shader drift does not reproject accumulated wind_time")
	_check(not shader_source.contains("cloud_scale_clear_px"), "cloud cover does not rescale the sampled field")
	_check(spec_source.contains("world-space shader") and spec_source.contains("subtractive `PointLight2D`"), "spec records shader fallback and rejected subtractive blobs")

	weather.call("clear_debug_regime")
	_finish()


func _no_light_children(field: Node) -> bool:
	for child: Node in field.get_children():
		if child is PointLight2D or child is LightOccluder2D:
			return false
	return true


func _finish() -> void:
	if _failures.is_empty():
		print("cloud_occluder_field_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("cloud_occluder_field_probe: FAILED %s" % failure)
		quit(1)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("cloud_occluder_field_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("cloud_occluder_field_probe: FAIL %s" % description)
