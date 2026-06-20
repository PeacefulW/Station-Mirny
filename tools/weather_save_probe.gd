extends SceneTree

# Проба сохранения медленного состояния погоды (Iteration 3):
# - эволюционировавшее состояние переживает export -> reset -> restore бит-в-бит
# - живые оси (cloud_cover, режим) реконструируются из восстановленного режима
# - старый сейв без секции weather -> дефолт clear
# - неизвестный режим (контент изменился) -> безопасный дефолт clear
# - связка collect_weather / apply_weather round-trip'ит то же состояние.
# Headless-ok. Запуск:
#   Godot_v4.7-stable_win64_console.exe --headless --path . -s tools/weather_save_probe.gd

const SaveCollectors = preload("res://core/autoloads/save_collectors.gd")
const SaveAppliers = preload("res://core/autoloads/save_appliers.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var weather: Node = root.get_node("WeatherRuntime")

	# Эволюционируем погоду до нетривиального состояния (хотя бы один переход).
	for _i: int in range(8):
		weather.call("_advance", 5.0)
	var evolved: Dictionary = weather.call("export_save_dict")
	print("weather_save_probe: evolved=%s" % str(evolved))

	# Round-trip: reset -> restore -> export должен совпасть бит-в-бит.
	weather.call("restore_persisted_state", { })
	var after_reset: StringName = weather.call("get_active_regime_id")
	weather.call("restore_persisted_state", evolved)
	var restored: Dictionary = weather.call("export_save_dict")
	_check(
		String(after_reset) == "core:clear",
		"сброс пустым диктом -> clear (was %s)" % str(after_reset),
	)
	_check(_dicts_match(evolved, restored), "export->reset->restore->export бит-в-бит (%s)" % str(restored))

	# Crafted mid-transition: живые оси реконструируются (не залипают на clear).
	weather.call(
		"restore_persisted_state",
		{
			"active_regime": "core:cloudy",
			"next_regime": "core:overcast",
			"in_transition": true,
			"transition": 0.5,
			"remaining_hours": 0.0,
			"weather_time_hours": 40.0,
			"transition_count": 3,
		},
	)
	var mid_regime: StringName = weather.call("get_active_regime_id")
	var mid_cover: float = weather.call("get_cloud_cover")
	print("weather_save_probe: mid regime=%s cover=%.3f" % [str(mid_regime), mid_cover])
	_check(String(mid_regime) == "core:cloudy", "mid-transition активный режим = cloudy")
	_check(
		mid_cover > 0.35 and mid_cover <= 1.0,
		"живая облачность реконструирована из cloudy->overcast (cover=%.3f)" % mid_cover,
	)

	# Неизвестный режим -> безопасный дефолт clear.
	weather.call(
		"restore_persisted_state",
		{ "active_regime": "core:bogus", "next_regime": "core:bogus" },
	)
	_check(
		String(weather.call("get_active_regime_id")) == "core:clear",
		"неизвестный режим -> дефолт clear",
	)

	# Связка collect/apply round-trip'ит то же состояние.
	for _j: int in range(6):
		weather.call("_advance", 5.0)
	var collected: Dictionary = SaveCollectors.collect_weather()
	weather.call("restore_persisted_state", { })
	SaveAppliers.apply_weather(collected)
	var reapplied: Dictionary = weather.call("export_save_dict")
	_check(collected.size() == 7, "collect_weather отдаёт все 7 полей (got %d)" % collected.size())
	_check(_dicts_match(collected, reapplied), "collect_weather/apply_weather round-trip совпал")

	if _failures.is_empty():
		print("weather_save_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for f: String in _failures:
			print("weather_save_probe: FAILED %s" % f)
		quit(1)


func _dicts_match(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key_variant: Variant in a.keys():
		if not b.has(key_variant):
			return false
		var av: Variant = a[key_variant]
		var bv: Variant = b[key_variant]
		if av is float or bv is float:
			if absf(float(av) - float(bv)) > 0.0001:
				return false
		elif str(av) != str(bv):
			return false
	return true


func _check(passed: bool, description: String) -> void:
	if passed:
		print("weather_save_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("weather_save_probe: FAIL %s" % description)
