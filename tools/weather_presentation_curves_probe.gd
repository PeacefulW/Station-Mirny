extends SceneTree

# Headless-проба чистых presentation-кривых Iteration 2b:
# - broken peaks in cloudy and fades by overcast;
# - deck/flatten rise toward overcast;
# - sun rays are a rare cloudy-only accent, not an overcast effect.
# Запуск:
#   Godot_v4.7-stable_win64_console.exe --headless --path . -s tools/weather_presentation_curves_probe.gd

const WeatherPresentationCurves = preload("res://core/systems/world/weather_presentation_curves.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var clear_cover: float = 0.08
	var cloudy_cover: float = 0.50
	var overcast_cover: float = 0.90

	var clear_broken: float = WeatherPresentationCurves.broken_cloud_strength(clear_cover)
	var cloudy_broken: float = WeatherPresentationCurves.broken_cloud_strength(cloudy_cover)
	var overcast_broken: float = WeatherPresentationCurves.broken_cloud_strength(overcast_cover)
	var cloudy_deck: float = WeatherPresentationCurves.deck_strength(cloudy_cover)
	var overcast_deck: float = WeatherPresentationCurves.deck_strength(overcast_cover)
	var cloudy_flatten: float = WeatherPresentationCurves.flatten_strength(cloudy_cover)
	var overcast_flatten: float = WeatherPresentationCurves.flatten_strength(overcast_cover)
	var cloudy_rays: float = WeatherPresentationCurves.sun_ray_strength(cloudy_cover)
	var overcast_edge_rays: float = WeatherPresentationCurves.sun_ray_strength(0.72)
	var overcast_rays: float = WeatherPresentationCurves.sun_ray_strength(overcast_cover)

	print(
		"weather_presentation_curves_probe: broken clear=%.3f cloudy=%.3f overcast=%.3f" % [
			clear_broken,
			cloudy_broken,
			overcast_broken,
		],
	)
	print(
		"weather_presentation_curves_probe: deck cloudy=%.3f overcast=%.3f flatten cloudy=%.3f overcast=%.3f rays cloudy=%.3f overcast_edge=%.3f overcast=%.3f" % [
			cloudy_deck,
			overcast_deck,
			cloudy_flatten,
			overcast_flatten,
			cloudy_rays,
			overcast_edge_rays,
			overcast_rays,
		],
	)

	_check(clear_broken < 0.05, "broken почти ноль при clear (%.3f)" % clear_broken)
	_check(cloudy_broken > 0.85, "broken пиковый при cloudy (%.3f)" % cloudy_broken)
	_check(overcast_broken < 0.06, "broken гаснет к overcast (%.3f)" % overcast_broken)
	_check(cloudy_deck < 0.35, "deck слабо тушит cloudy-просветы (%.3f)" % cloudy_deck)
	_check(overcast_deck > 0.85, "deck почти полный при overcast (%.3f)" % overcast_deck)
	_check(cloudy_flatten < 0.01, "flatten не работает в cloudy (%.3f)" % cloudy_flatten)
	_check(overcast_flatten > 0.75, "flatten сильный в overcast (%.3f)" % overcast_flatten)
	_check(cloudy_rays > 0.45, "sun rays разрешены в cloudy (%.3f)" % cloudy_rays)
	_check(overcast_edge_rays < 0.05, "sun rays гаснут уже на входе в overcast (%.3f)" % overcast_edge_rays)
	_check(overcast_rays < 0.05, "sun rays гаснут в overcast (%.3f)" % overcast_rays)

	if _failures.is_empty():
		print("weather_presentation_curves_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("weather_presentation_curves_probe: FAILED %s" % failure)
		quit(1)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("weather_presentation_curves_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("weather_presentation_curves_probe: FAIL %s" % description)
