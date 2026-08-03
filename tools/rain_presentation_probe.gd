extends SceneTree

# Headless contract probe for the bounded rain presentation layer and its
# shared open-sky resolver. Pixel style still requires a windowed render check.
# Run:
#   Godot_v4.7-stable_win64_console.exe --headless --path . \
#     -s tools/rain_presentation_probe.gd

const RAIN_SCRIPT_PATH: String = "res://core/systems/world/rain_overlay.gd"
const RAIN_SHADER_PATH: String = "res://assets/shaders/rain_overlay.gdshader"
const EXPOSURE_RESOLVER_SCRIPT_PATH: String = (
	"res://core/systems/world/environment_exposure_resolver.gd"
)
const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const MOUNTAIN_FLAG_INTERIOR: int = 1

var _failures: Array[String] = []


class MockBuildingSystem:
	extends Node

	var indoor: bool = false


	func world_to_grid(_world_pos: Vector2) -> Vector2i:
		return Vector2i.ZERO


	func is_cell_indoor(_grid_pos: Vector2i) -> bool:
		return indoor


class MockWorldStreamer:
	extends Node

	var sample_ready: bool = true
	var mountain_flags: int = 0


	func get_mountain_cover_sample(_world_tile: Vector2i) -> Dictionary:
		return {
			"ready": sample_ready,
			"mountain_flags": mountain_flags,
		}


func _init() -> void:
	print("rain_presentation_probe: START")
	call_deferred("_run")


func _run() -> void:
	var rain_script: Script = ResourceLoader.load(RAIN_SCRIPT_PATH) as Script
	var rain_shader: Shader = ResourceLoader.load(RAIN_SHADER_PATH) as Shader
	var resolver_script: Script = ResourceLoader.load(
		EXPOSURE_RESOLVER_SCRIPT_PATH,
	) as Script
	var world_scene: PackedScene = ResourceLoader.load(WORLD_SCENE_PATH) as PackedScene
	_check(rain_script != null, "RainOverlay script loads")
	_check(rain_shader != null, "rain shader loads")
	_check(resolver_script != null, "EnvironmentExposureResolver script loads")
	_check(world_scene != null, "world runtime scene loads with rain wiring")
	if (
		rain_script == null
		or rain_shader == null
		or resolver_script == null
		or world_scene == null
	):
		_finish()
		return
	_check(rain_script.can_instantiate(), "RainOverlay script compiles")
	_check(
		resolver_script.can_instantiate(),
		"EnvironmentExposureResolver script compiles",
	)
	if not rain_script.can_instantiate() or not resolver_script.can_instantiate():
		_finish()
		return

	var world := Node2D.new()
	root.add_child(world)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(512.0, 512.0)
	camera.make_current()

	var building := MockBuildingSystem.new()
	world.add_child(building)
	building.add_to_group("building_system")
	var streamer := MockWorldStreamer.new()
	world.add_child(streamer)
	streamer.add_to_group("chunk_manager")

	var resolver: Node = resolver_script.new() as Node
	world.add_child(resolver)
	var rain: Node2D = rain_script.new() as Node2D
	world.add_child(rain)
	await process_frame
	await process_frame

	_check(
		rain.get("_exposure_resolver") == resolver,
		"RainOverlay resolves the scene-shared EnvironmentExposureResolver",
	)
	_check(
		bool(resolver.call("is_open_sky_at", Vector2.ZERO)),
		"resolver reports clear surface terrain as open sky",
	)

	var weather: Node = root.get_node_or_null("WeatherRuntime")
	_check(weather != null, "WeatherRuntime autoload available")
	if weather == null:
		world.queue_free()
		_finish()
		return

	weather.call("set_debug_regime", &"core:clear")
	weather.call("set_debug_cloud_cover", 0.0)
	weather.call("set_debug_humidity", 0.0)
	resolver.call("set_active_z_level", 0)
	rain.call("_process", 0.016)
	_check(not rain.visible, "dry clear weather hides rain under open sky")
	_check(
		_rain_uniform(rain) <= 0.0,
		"dry clear weather publishes zero visual intensity",
	)

	weather.call("set_debug_regime", &"core:overcast")
	weather.call("set_debug_cloud_cover", 1.0)
	weather.call("set_debug_humidity", 0.80)
	rain.call("_process", 0.016)
	_check(rain.visible, "80% humidity under dense overcast shows rain under open sky")
	_check(_rain_uniform(rain) > 0.0, "wet overcast publishes positive intensity")
	_check(rain is Sprite2D, "rain is one Sprite2D shader layer")
	_check(rain.get_child_count() == 0, "rain layer has no per-drop child nodes")
	_check(rain.z_index == 405, "rain renders above existing world atmosphere")

	resolver.call("set_active_z_level", -1)
	_check(
		not bool(resolver.call("is_open_sky_at", Vector2.ZERO)),
		"shared resolver closes open sky below the surface",
	)
	rain.call("_process", 0.016)
	_check(not rain.visible, "subsurface context hides rain through shared resolver")
	_check(
		_rain_uniform(rain) <= 0.0,
		"subsurface context publishes zero visual intensity",
	)

	resolver.call("set_active_z_level", 0)
	building.indoor = true
	_check(
		not bool(resolver.call("is_open_sky_at", Vector2.ZERO)),
		"shared resolver closes open sky inside a building",
	)
	rain.call("_process", 0.016)
	_check(not rain.visible, "building interior hides rain through shared resolver")

	building.indoor = false
	streamer.mountain_flags = MOUNTAIN_FLAG_INTERIOR
	_check(
		not bool(resolver.call("is_open_sky_at", Vector2.ZERO)),
		"shared resolver closes open sky inside a mountain",
	)
	rain.call("_process", 0.016)
	_check(not rain.visible, "mountain interior hides rain through shared resolver")

	streamer.mountain_flags = 0
	streamer.sample_ready = false
	_check(
		not bool(resolver.call("is_open_sky_at", Vector2.ZERO)),
		"unknown mountain cover fails closed in the shared resolver",
	)
	rain.call("_process", 0.016)
	_check(not rain.visible, "unknown mountain cover cannot leak visible rain")

	streamer.sample_ready = true
	_check(
		bool(resolver.call("is_open_sky_at", Vector2.ZERO)),
		"resolver reopens the surface after cover becomes authoritative",
	)
	rain.call("_process", 0.016)
	_check(rain.visible, "rain returns after the shared context becomes open")

	_assert_static_contracts()
	weather.call("clear_debug_humidity")
	weather.call("clear_debug_cloud_cover")
	weather.call("clear_debug_regime")
	world.queue_free()
	await process_frame
	_finish()


func _rain_uniform(rain: Node2D) -> float:
	var shader_material: ShaderMaterial = rain.material as ShaderMaterial
	_check(shader_material != null, "rain owns one ShaderMaterial")
	if shader_material == null:
		return 0.0
	return float(shader_material.get_shader_parameter("rain_intensity"))


func _assert_static_contracts() -> void:
	var scene_source: String = FileAccess.get_file_as_string(WORLD_SCENE_PATH)
	var rain_source: String = FileAccess.get_file_as_string(RAIN_SCRIPT_PATH)
	var resolver_source: String = FileAccess.get_file_as_string(
		EXPOSURE_RESOLVER_SCRIPT_PATH,
	)
	var shader_source: String = FileAccess.get_file_as_string(RAIN_SHADER_PATH)
	_check(
		scene_source.count("res://core/systems/world/rain_overlay.gd") == 1
		and scene_source.count(
			"[node name=\"RainOverlay\" type=\"Sprite2D\"",
		) == 1,
		"world runtime wires exactly one RainOverlay Sprite2D",
	)
	_check(
		scene_source.count(EXPOSURE_RESOLVER_SCRIPT_PATH.trim_prefix("res://")) == 1
		and scene_source.count(
			"[node name=\"EnvironmentExposureResolver\" type=\"Node\"",
		) == 1,
		"world runtime wires exactly one shared exposure resolver",
	)
	_check(
		rain_source.contains("extends WorldViewOverlay")
		and rain_source.contains("get_precipitation_kind")
		and rain_source.contains("get_precipitation_intensity"),
		"RainOverlay pull-reads WeatherRuntime through WorldViewOverlay",
	)
	_check(
		rain_source.contains("EnvironmentExposureResolver")
		and rain_source.contains("environment_exposure_resolver")
		and rain_source.contains("is_open_sky_at"),
		"RainOverlay delegates visibility to the shared open-sky API",
	)
	_check(
		not rain_source.contains("is_cell_indoor")
		and not rain_source.contains("get_mountain_cover_sample")
		and not rain_source.contains("MOUNTAIN_FLAG_INTERIOR")
		and not rain_source.contains("z_level_changed")
		and not rain_source.contains("_current_z"),
		"RainOverlay does not duplicate z, building, or mountain gates",
	)
	_check(
		resolver_source.contains("z_level != 0")
		and resolver_source.contains("is_building_indoor_at")
		and resolver_source.contains("is_cell_indoor")
		and resolver_source.contains("get_mountain_cover_sample")
		and resolver_source.contains("MOUNTAIN_FLAG_INTERIOR")
		and resolver_source.contains("ready"),
		"EnvironmentExposureResolver owns the complete fail-closed sky gate",
	)
	_check(
		shader_source.contains("global uniform float wind_strength")
		and shader_source.contains("global uniform vec2 wind_direction")
		and shader_source.contains("global uniform vec2 wind_gust_scroll_px"),
		"rain shader reads existing wind globals",
	)
	_check(
		shader_source.contains("uniform float rain_intensity")
		and shader_source.contains("wrapped_world = mod(world_pos")
		and shader_source.contains("wrapped_wind = mod(wind_gust_scroll_px")
		and not shader_source.contains("hint_screen_texture"),
		"rain is one precision-bounded pass without a screen back-buffer copy",
	)
	_check(
		not rain_source.contains("ResourceLoader.load")
		and not rain_source.contains("PackedScene.instantiate")
		and not rain_source.contains("add_child("),
		"rain runtime performs no loads or per-drop scene mutation",
	)


func _finish() -> void:
	if _failures.is_empty():
		print("rain_presentation_probe: ALL CHECKS PASSED")
		quit(0)
		return
	for failure: String in _failures:
		print("rain_presentation_probe: FAILED %s" % failure)
	quit(1)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("rain_presentation_probe: PASS %s" % description)
		return
	_failures.append(description)
	print("rain_presentation_probe: FAIL %s" % description)
