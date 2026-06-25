extends SceneTree

# Static headless probe for Cloud Occlusion Lighting Iteration 2.
# This intentionally does not instantiate world_runtime_v0.tscn: Godot --script
# compiles loaded scenes before autoload global identifiers are available.
# Запуск:
#   Godot_v4.7-stable_win64_console.exe --headless --path . -s tools/cloud_occlusion_light_probe.gd

const DAYLIGHT_PATH: String = "res://core/systems/daylight/daylight_system.gd"
const PLAYER_SHADOW_PATH: String = "res://core/entities/player/player_sun_shadow.gd"
const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const WORLD_LIGHTING_SPEC_PATH: String = "res://docs/02_system_specs/world/world_dynamic_lighting_2d.md"

var _failures: Array[String] = []


func _init() -> void:
	print("cloud_occlusion_light_probe: START")
	call_deferred("_run")


func _run() -> void:
	var daylight_source: String = FileAccess.get_file_as_string(DAYLIGHT_PATH)
	var player_shadow_source: String = FileAccess.get_file_as_string(PLAYER_SHADOW_PATH)
	var scene_source: String = FileAccess.get_file_as_string(WORLD_SCENE_PATH)
	var lighting_spec: String = FileAccess.get_file_as_string(WORLD_LIGHTING_SPEC_PATH)

	_check(not daylight_source.is_empty(), "DaylightSystem source readable")
	_check(not player_shadow_source.is_empty(), "PlayerSunShadow source readable")
	_check(not scene_source.is_empty(), "world_runtime_v0 scene source readable")

	_check(daylight_source.contains("get_cloud_occlusion"), "DaylightSystem reads WeatherRuntime.get_cloud_occlusion()")
	_check(daylight_source.contains("SUN_OVERCAST_DIRECT_FACTOR"), "DaylightSystem has explicit direct-sun cloud multiplier")
	_check(daylight_source.contains("COLOR_OVERCAST_TINT"), "DaylightSystem keeps ambient cool-shift")
	_check(daylight_source.contains("_cloud_occlusion_for_context"), "DaylightSystem gates cloud occlusion through context")
	_check(daylight_source.contains("_has_open_sky_context"), "DaylightSystem has open-sky context gate")
	_check(daylight_source.contains("DirectionalLight2D.new()"), "DaylightSystem owns real DirectionalLight2D sun")
	_check(not daylight_source.contains("WeatherPresentationCurves"), "DaylightSystem no longer uses old weather curves")

	_check(player_shadow_source.contains("get_cloud_occlusion"), "PlayerSunShadow uses cloud occlusion for direct-sun attenuation")
	_check(not player_shadow_source.contains("get_cloud_cover"), "PlayerSunShadow no longer attenuates from raw cloud_cover")

	_check(not scene_source.contains("CloudShadowOverlay"), "CloudShadowOverlay node removed from live scene")
	_check(not scene_source.contains("OvercastFlattenOverlay"), "OvercastFlattenOverlay node removed from live scene")
	_check(not scene_source.contains("SunRayOverlay"), "SunRayOverlay node removed from live scene")
	_check(not scene_source.contains("cloud_shadow_overlay.gd"), "cloud shadow overlay script not referenced by live scene")
	_check(not scene_source.contains("overcast_flatten_overlay.gd"), "overcast flatten overlay script not referenced by live scene")
	_check(not scene_source.contains("sun_ray_overlay.gd"), "sun ray overlay script not referenced by live scene")

	_check(not FileAccess.file_exists("res://core/systems/world/cloud_shadow_overlay.gd"), "CloudShadowOverlay script removed")
	_check(not FileAccess.file_exists("res://core/systems/world/overcast_flatten_overlay.gd"), "OvercastFlattenOverlay script removed")
	_check(not FileAccess.file_exists("res://core/systems/world/sun_ray_overlay.gd"), "SunRayOverlay script removed")
	_check(not FileAccess.file_exists("res://core/systems/world/weather_presentation_curves.gd"), "WeatherPresentationCurves removed")
	_check(not FileAccess.file_exists("res://assets/shaders/cloud_shadow_overlay.gdshader"), "cloud shadow screen shader removed")
	_check(not FileAccess.file_exists("res://assets/shaders/overcast_flatten_overlay.gdshader"), "overcast flatten screen shader removed")
	_check(not FileAccess.file_exists("res://assets/shaders/sun_ray_overlay.gdshader"), "sun-ray screen shader removed")

	_check(lighting_spec.contains("Cloud Occlusion Boundary"), "world_dynamic_lighting_2d documents cloud occlusion boundary")
	_check(lighting_spec.contains("does **not** make `Light2D` nodes a"), "world lighting spec preserves ADR-0005 gameplay authority boundary")

	if _failures.is_empty():
		print("cloud_occlusion_light_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("cloud_occlusion_light_probe: FAILED %s" % failure)
		quit(1)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("cloud_occlusion_light_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("cloud_occlusion_light_probe: FAIL %s" % description)
