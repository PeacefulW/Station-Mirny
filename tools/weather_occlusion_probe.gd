extends SceneTree

# Проба Cloud Occlusion Iteration 1:
# - WeatherRuntime exposes get_cloud_occlusion()
# - occlusion is the documented smoothstep(0.10, 0.95, cloud_cover)
# - occlusion rises clear -> cloudy -> overcast and is near-zero in clear
# - save payload remains the same slow weather state (no new persisted field)
# Headless ok. Запуск:
#   Godot_v4.7-stable_win64_console.exe --headless --path . -s tools/weather_occlusion_probe.gd

const OCCLUSION_START: float = 0.10
const OCCLUSION_END: float = 0.95

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var weather: Node = root.get_node_or_null("WeatherRuntime")
	if weather == null:
		print("weather_occlusion_probe: WeatherRuntime autoload missing")
		quit(1)
		return
	_check(weather.has_method("get_cloud_occlusion"), "WeatherRuntime exposes get_cloud_occlusion()")

	var samples: Dictionary = {}
	for regime: StringName in [&"core:clear", &"core:cloudy", &"core:overcast"]:
		weather.call("set_debug_regime", regime)
		var cover: float = float(weather.call("get_cloud_cover"))
		var occlusion: float = float(weather.call("get_cloud_occlusion"))
		var expected: float = _smoothstep(OCCLUSION_START, OCCLUSION_END, cover)
		samples[String(regime)] = {
			"cover": cover,
			"occlusion": occlusion,
			"expected": expected,
		}
		_check(
			absf(occlusion - expected) <= 0.0001,
			"%s occlusion matches smoothstep curve (cover=%.3f occlusion=%.3f expected=%.3f)" % [
				String(regime),
				cover,
				occlusion,
				expected,
			],
		)
	weather.call("clear_debug_regime")

	var clear_occ: float = samples["core:clear"]["occlusion"]
	var cloudy_occ: float = samples["core:cloudy"]["occlusion"]
	var overcast_occ: float = samples["core:overcast"]["occlusion"]
	print(
		"weather_occlusion_probe: clear cover=%.3f occ=%.3f | cloudy cover=%.3f occ=%.3f | overcast cover=%.3f occ=%.3f" % [
			float(samples["core:clear"]["cover"]),
			clear_occ,
			float(samples["core:cloudy"]["cover"]),
			cloudy_occ,
			float(samples["core:overcast"]["cover"]),
			overcast_occ,
		],
	)
	_check(clear_occ <= 0.02, "clear regime occlusion is near zero (%.3f)" % clear_occ)
	_check(
		clear_occ < cloudy_occ and cloudy_occ < overcast_occ,
		"occlusion rises clear < cloudy < overcast",
	)
	_check(overcast_occ >= 0.80, "overcast occlusion is high (%.3f)" % overcast_occ)

	var save_data: Dictionary = weather.call("export_save_dict")
	_check(not save_data.has("cloud_occlusion"), "cloud occlusion is not persisted")
	_check(save_data.size() == 7, "weather save payload still has 7 slow-state fields")

	if _failures.is_empty():
		print("weather_occlusion_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("weather_occlusion_probe: FAILED %s" % failure)
		quit(1)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("weather_occlusion_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("weather_occlusion_probe: FAIL %s" % description)
