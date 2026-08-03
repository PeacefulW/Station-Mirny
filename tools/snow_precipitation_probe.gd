extends SceneTree

# Headless contract probe for temperature-resolved snow: authoritative kind
# resolution, presentation cross-fade, bounded snow layer, and the shared
# open-sky gate. Pixel style still requires a windowed render check.
# Run:
#   Godot_v4.7-stable_win64_console.exe --headless --path . \
#     -s tools/snow_precipitation_probe.gd

const SNOW_SCRIPT_PATH: String = "res://core/systems/world/snow_overlay.gd"
const SNOW_SHADER_PATH: String = "res://assets/shaders/snow_overlay.gdshader"
const RAIN_SCRIPT_PATH: String = "res://core/systems/world/rain_overlay.gd"
const EXPOSURE_RESOLVER_SCRIPT_PATH: String = (
	"res://core/systems/world/environment_exposure_resolver.gd"
)
const GROUND_WETNESS_SCRIPT_PATH: String = (
	"res://core/systems/world/ground_wetness_presenter.gd"
)
const GROUND_WETNESS_PROFILE_PATH: String = "res://data/balance/ground_wetness_profile.tres"
const BALANCE_PATH: String = "res://data/balance/weather_balance.tres"
const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const MOUNTAIN_FLAG_INTERIOR: int = 1
const KIND_NONE: int = 0
const KIND_RAIN: int = 1
const KIND_SNOW: int = 2
const WARM: int = 0
const COLD: int = 2
const STORM: int = 3
const BREATH_SAMPLES: int = 400
const BREATH_STEP_HOURS: float = 0.37

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
	print("snow_precipitation_probe: START")
	call_deferred("_run")


func _run() -> void:
	var snow_script: Script = ResourceLoader.load(SNOW_SCRIPT_PATH) as Script
	var snow_shader: Shader = ResourceLoader.load(SNOW_SHADER_PATH) as Shader
	var resolver_script: Script = ResourceLoader.load(EXPOSURE_RESOLVER_SCRIPT_PATH) as Script
	var world_scene: PackedScene = ResourceLoader.load(WORLD_SCENE_PATH) as PackedScene
	var balance: Resource = ResourceLoader.load(BALANCE_PATH)
	_check(snow_script != null, "SnowOverlay script loads")
	_check(snow_shader != null, "snow shader loads")
	_check(world_scene != null, "world runtime scene loads with snow wiring")
	_check(balance != null, "WeatherBalance resource loads")
	if snow_script == null or snow_shader == null or world_scene == null or balance == null:
		_finish()
		return
	_check(bool(balance.call("is_valid_balance")), "WeatherBalance passes validation")
	_check(snow_script.can_instantiate(), "SnowOverlay script compiles")
	if not snow_script.can_instantiate() or not resolver_script.can_instantiate():
		_finish()
		return

	var time_manager: Node = root.get_node_or_null("TimeManager")
	var weather: Node = root.get_node_or_null("WeatherRuntime")
	_check(time_manager != null and weather != null, "TimeManager/WeatherRuntime autoloads present")
	if time_manager == null or weather == null:
		_finish()
		return

	_check_kind_resolution(time_manager, weather, float(balance.get("freeze_temperature_c")))
	_check_crossfade(time_manager, weather, balance)
	_check_ground_response()
	await _check_presentation(snow_script, resolver_script, time_manager, weather)
	_assert_static_contracts()

	weather.call("clear_debug_humidity")
	weather.call("clear_debug_cloud_cover")
	weather.call("clear_debug_regime")
	time_manager.call("clear_debug_season")
	_finish()


## Авторитетное разрешение вида: тот же потенциал осадков, температура решает
## дождь это или снег.
func _check_kind_resolution(time_manager: Node, weather: Node, freeze: float) -> void:
	weather.call("set_debug_regime", &"core:overcast")
	weather.call("set_debug_cloud_cover", 1.0)
	weather.call("set_debug_humidity", 0.85)

	time_manager.call("set_debug_season", WARM)
	var warm_temperature: float = float(weather.call("get_temperature_c"))
	var warm_kind: int = int(weather.call("get_precipitation_kind"))
	var warm_intensity: float = float(weather.call("get_precipitation_intensity"))
	_check(
		warm_temperature > freeze,
		"WARM overcast stays above freezing (%.1f C)" % warm_temperature,
	)
	_check(warm_kind == KIND_RAIN, "above freezing publishes RAIN")

	time_manager.call("set_debug_season", COLD)
	var cold_temperature: float = float(weather.call("get_temperature_c"))
	var cold_kind: int = int(weather.call("get_precipitation_kind"))
	var cold_intensity: float = float(weather.call("get_precipitation_intensity"))
	_check(cold_temperature < freeze, "COLD overcast is below freezing (%.1f C)" % cold_temperature)
	_check(cold_kind == KIND_SNOW, "below freezing publishes SNOW")
	_check(
		absf(warm_intensity - cold_intensity) <= 0.0001,
		"kind resolution does not change intensity (%.4f vs %.4f)" % [
			warm_intensity,
			cold_intensity,
		],
	)
	_check(cold_intensity > 0.0, "freezing wet overcast still produces precipitation")

	# Statelessness: два одинаковых чтения подряд дают одинаковый результат.
	_check(
		int(weather.call("get_precipitation_kind")) == cold_kind
		and int(weather.call("get_precipitation_kind")) == cold_kind,
		"kind resolution is stateless across repeated reads",
	)

	# Сухой режим остаётся сухим на морозе — заморозка не выдумывает осадки.
	weather.call("set_debug_regime", &"core:clear")
	weather.call("set_debug_humidity", 0.0)
	weather.call("set_debug_cloud_cover", 0.0)
	_check(
		int(weather.call("get_precipitation_kind")) == KIND_NONE,
		"dry clear regime stays NONE at -40 C",
	)


## Кросс-фейд: вес — чистая функция температуры, снаружи полосы ровно один слой,
## внутри — оба частично, и суммарно всегда единица.
func _check_crossfade(time_manager: Node, weather: Node, balance: Resource) -> void:
	weather.call("set_debug_regime", &"core:overcast")
	weather.call("set_debug_cloud_cover", 1.0)
	weather.call("set_debug_humidity", 0.85)
	var freeze: float = float(balance.get("freeze_temperature_c"))
	var half_band: float = float(balance.get("precipitation_crossfade_c"))

	time_manager.call("set_debug_season", COLD)
	_check_close(
		float(weather.call("get_snow_presentation_weight")),
		1.0,
		"deep cold is pure snow",
	)
	time_manager.call("set_debug_season", WARM)
	_check_close(
		float(weather.call("get_snow_presentation_weight")),
		0.0,
		"warm overcast is pure rain",
	)

	# Полосу кросс-фейда пересекает плечевой сезон в облачном режиме: overcast
	# в STORM лежит уже целиком ниже нуля, а cloudy даёт около -4..-1 C, то есть
	# ровно окрестность точки замерзания. Свипуем дыхание полосы и проверяем
	# свойство на каждом сэмпле, а не на одной удачной точке.
	time_manager.call("set_debug_season", STORM)
	var band_samples: int = 0
	var property_holds: bool = true
	for sample: int in range(BREATH_SAMPLES):
		weather.call(
			"restore_persisted_state",
			{
				"active_regime": "core:cloudy",
				"next_regime": "core:cloudy",
				"in_transition": false,
				"transition": 0.0,
				"remaining_hours": 999.0,
				"weather_time_hours": float(sample) * BREATH_STEP_HOURS,
				"transition_count": 0,
			},
		)
		weather.call("set_debug_regime", &"core:cloudy")
		weather.call("set_debug_cloud_cover", 1.0)
		weather.call("set_debug_humidity", 0.85)
		var temperature: float = float(weather.call("get_temperature_c"))
		var snow_weight: float = float(weather.call("get_snow_presentation_weight"))
		if snow_weight < 0.0 or snow_weight > 1.0:
			property_holds = false
		if temperature >= freeze + half_band and not is_zero_approx(snow_weight):
			property_holds = false
		if temperature <= freeze - half_band and not is_equal_approx(snow_weight, 1.0):
			property_holds = false
		if temperature > freeze - half_band and temperature < freeze + half_band:
			band_samples += 1
			if snow_weight <= 0.0 or snow_weight >= 1.0:
				property_holds = false
	_check(band_samples > 0, "sweep reaches the cross-fade band (%d samples)" % band_samples)
	_check(property_holds, "cross-fade weight is bounded and correct outside/inside the band")


## Снег не мочит землю: та же авторская функция, другой вид осадков.
func _check_ground_response() -> void:
	var ground_script: GDScript = ResourceLoader.load(GROUND_WETNESS_SCRIPT_PATH) as GDScript
	var profile: Resource = ResourceLoader.load(GROUND_WETNESS_PROFILE_PATH)
	_check(ground_script != null and profile != null, "ground wetness script/profile load")
	if ground_script == null or profile == null:
		return
	var after_rain: float = ground_script.calculate_next_amount(profile, 0.5, 1.0, KIND_RAIN, 1.0)
	var after_snow: float = ground_script.calculate_next_amount(profile, 0.5, 1.0, KIND_SNOW, 1.0)
	_check(after_rain > 0.5, "rain still wets the ground (%.3f)" % after_rain)
	_check(after_snow < 0.5, "snow dries the ground instead of wetting it (%.3f)" % after_snow)


func _check_presentation(
		snow_script: Script,
		resolver_script: Script,
		time_manager: Node,
		weather: Node,
) -> void:
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
	var snow: Node2D = snow_script.new() as Node2D
	world.add_child(snow)
	await process_frame
	await process_frame

	_check(
		snow.get("_exposure_resolver") == resolver,
		"SnowOverlay resolves the scene-shared EnvironmentExposureResolver",
	)

	weather.call("set_debug_regime", &"core:overcast")
	weather.call("set_debug_cloud_cover", 1.0)
	weather.call("set_debug_humidity", 0.85)
	time_manager.call("set_debug_season", COLD)
	resolver.call("set_active_z_level", 0)
	snow.call("_process", 0.016)
	_check(snow.visible, "freezing wet overcast shows snow under open sky")
	_check(_snow_uniform(snow) > 0.0, "freezing overcast publishes positive snow intensity")
	_check(snow is Sprite2D, "snow is one Sprite2D shader layer")
	_check(snow.get_child_count() == 0, "snow layer has no per-flake child nodes")

	time_manager.call("set_debug_season", WARM)
	snow.call("_process", 0.016)
	_check(not snow.visible, "warm overcast hides snow while rain owns the frame")
	_check(_snow_uniform(snow) <= 0.0, "warm overcast publishes zero snow intensity")

	time_manager.call("set_debug_season", COLD)
	resolver.call("set_active_z_level", -1)
	snow.call("_process", 0.016)
	_check(not snow.visible, "subsurface context hides snow through shared resolver")

	resolver.call("set_active_z_level", 0)
	building.indoor = true
	snow.call("_process", 0.016)
	_check(not snow.visible, "building interior hides snow through shared resolver")

	building.indoor = false
	streamer.mountain_flags = MOUNTAIN_FLAG_INTERIOR
	snow.call("_process", 0.016)
	_check(not snow.visible, "mountain interior hides snow through shared resolver")

	streamer.mountain_flags = 0
	streamer.sample_ready = false
	snow.call("_process", 0.016)
	_check(not snow.visible, "unknown mountain cover cannot leak visible snow")

	streamer.sample_ready = true
	snow.call("_process", 0.016)
	_check(snow.visible, "snow returns after the shared context becomes open")

	world.queue_free()
	await process_frame


func _snow_uniform(snow: Node2D) -> float:
	var shader_material: ShaderMaterial = snow.material as ShaderMaterial
	_check(shader_material != null, "snow owns one ShaderMaterial")
	if shader_material == null:
		return 0.0
	return float(shader_material.get_shader_parameter("snow_intensity"))


func _assert_static_contracts() -> void:
	var scene_source: String = FileAccess.get_file_as_string(WORLD_SCENE_PATH)
	var snow_source: String = FileAccess.get_file_as_string(SNOW_SCRIPT_PATH)
	var rain_source: String = FileAccess.get_file_as_string(RAIN_SCRIPT_PATH)
	var shader_source: String = FileAccess.get_file_as_string(SNOW_SHADER_PATH)
	var weather_source: String = FileAccess.get_file_as_string(
		"res://core/autoloads/weather_runtime.gd",
	)
	_check(
		scene_source.count("res://core/systems/world/snow_overlay.gd") == 1
		and scene_source.count("[node name=\"SnowOverlay\" type=\"Sprite2D\"") == 1,
		"world runtime wires exactly one SnowOverlay Sprite2D",
	)
	_check(
		snow_source.contains("extends WorldViewOverlay")
		and snow_source.contains("get_snow_presentation_weight")
		and snow_source.contains("is_open_sky_at"),
		"SnowOverlay pull-reads weather truth and the shared open-sky API",
	)
	_check(
		not snow_source.contains("is_cell_indoor")
		and not snow_source.contains("get_mountain_cover_sample")
		and not snow_source.contains("z_level_changed"),
		"SnowOverlay does not duplicate z, building, or mountain gates",
	)
	_check(
		not snow_source.contains("ResourceLoader.load")
		and not snow_source.contains("add_child("),
		"snow runtime performs no loads or per-flake scene mutation",
	)
	_check(
		rain_source.contains("get_snow_presentation_weight"),
		"RainOverlay yields to snow through the shared cross-fade weight",
	)
	_check(
		shader_source.contains("wrapped_world = mod(world_pos")
		and shader_source.contains("wrapped_wind = mod(wind_gust_scroll_px")
		and not shader_source.contains("hint_screen_texture"),
		"snow is one precision-bounded pass without a screen back-buffer copy",
	)
	_check(
		weather_source.contains("freeze_temperature_c")
		and not weather_source.contains("PrecipitationKind.SNOW if")
		and weather_source.contains("BALANCE_PATH"),
		"freezing threshold is authored data, not a script constant",
	)


func _finish() -> void:
	if _failures.is_empty():
		print("snow_precipitation_probe: ALL CHECKS PASSED")
		quit(0)
		return
	for failure: String in _failures:
		print("snow_precipitation_probe: FAILED %s" % failure)
	quit(1)


func _check_close(actual: float, expected: float, description: String) -> void:
	_check(absf(actual - expected) <= 0.0001, "%s (%.5f)" % [description, actual])


func _check(passed: bool, description: String) -> void:
	if passed:
		print("snow_precipitation_probe: PASS %s" % description)
		return
	_failures.append(description)
	print("snow_precipitation_probe: FAIL %s" % description)
