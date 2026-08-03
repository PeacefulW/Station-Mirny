extends SceneTree

# Проба сохранения медленного состояния погоды (Iteration 3):
# - эволюционировавшее состояние переживает export -> reset -> restore бит-в-бит
# - живые оси (cloud_cover, temperature, humidity, rain) реконструируются из
#   slow weather + existing TimeSaveData season state
# - старый сейв без секции weather -> дефолт clear
# - неизвестный режим (контент изменился) -> безопасный дефолт clear
# - связка collect_weather / apply_weather round-trip'ит то же состояние.
# Headless-ok. Запуск:
#   Godot_v4.7-stable_win64_console.exe --headless --path . -s tools/weather_save_probe.gd

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var weather: Node = root.get_node_or_null("WeatherRuntime")
	var tm: Node = root.get_node_or_null("TimeManager")
	if weather == null or tm == null:
		print("weather_save_probe: WeatherRuntime/TimeManager autoload missing")
		quit(1)
		return

	# Эволюционируем погоду до нетривиального состояния (хотя бы один переход).
	for evolution_step: int in range(8):
		weather.call("_advance", 5.0)
	var evolved: Dictionary = weather.call("export_save_dict")
	var evolved_humidity: float = float(weather.call("get_humidity"))
	var evolved_rain: float = float(weather.call("get_precipitation_intensity"))
	var evolved_kind: int = int(weather.call("get_precipitation_kind"))
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
	_check(
		_dicts_match(evolved, restored),
		"export->reset->restore->export бит-в-бит (%s)" % str(restored),
	)
	_check(
		absf(float(weather.call("get_humidity")) - evolved_humidity) <= 0.0001
		and absf(float(weather.call("get_precipitation_intensity")) - evolved_rain) <= 0.0001
		and int(weather.call("get_precipitation_kind")) == evolved_kind,
		"live humidity/rain детерминированно реконструированы",
	)

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
	var mid_humidity: float = float(weather.call("get_humidity"))
	var mid_rain: float = float(weather.call("get_precipitation_intensity"))
	var mid_kind: int = int(weather.call("get_precipitation_kind"))
	print(
		"weather_save_probe: mid regime=%s cover=%.3f humidity=%.3f rain=%.3f kind=%d" % [
			str(mid_regime),
			mid_cover,
			mid_humidity,
			mid_rain,
			mid_kind,
		],
	)
	_check(String(mid_regime) == "core:cloudy", "mid-transition активный режим = cloudy")
	_check(
		mid_cover > 0.35 and mid_cover <= 1.0,
		"живая облачность реконструирована из cloudy->overcast (cover=%.3f)" % mid_cover,
	)
	_check(
		mid_humidity >= 0.58 and mid_humidity <= 0.96,
		"живая humidity реконструирована из cloudy->overcast (humidity=%.3f)" % mid_humidity,
	)
	_check(
		mid_rain >= 0.0
		and mid_rain <= 1.0
		and ((mid_rain > 0.0 and mid_kind == 1) or (is_zero_approx(mid_rain) and mid_kind == 0)),
		"rain kind/intensity согласованы после crafted restore",
	)

	# TimeSaveData уже хранит current_day/current_season. При одинаковом slow
	# weather state оно обязано реконструировать сезонные live axes без полей в
	# weather.json.
	var seasonal_weather_state: Dictionary = weather.call("export_save_dict") as Dictionary
	tm.call("restore_persisted_state", 7.0, 46, 3)
	weather.call("restore_persisted_state", seasonal_weather_state)
	var storm_temperature: float = float(weather.call("get_temperature_c"))
	var storm_humidity: float = float(weather.call("get_humidity"))
	tm.call("restore_persisted_state", 7.0, 1, 0)
	weather.call("restore_persisted_state", seasonal_weather_state)
	var warm_temperature: float = float(weather.call("get_temperature_c"))
	var warm_humidity: float = float(weather.call("get_humidity"))
	_check(
		warm_temperature > storm_temperature and storm_humidity > warm_humidity,
		"season из TimeSaveData меняет reconstructed temperature/humidity "
		+ "(warm %.2f/%.3f storm %.2f/%.3f)"
		% [warm_temperature, warm_humidity, storm_temperature, storm_humidity],
	)
	tm.call("restore_persisted_state", 7.0, 46, 3)
	weather.call("restore_persisted_state", seasonal_weather_state)
	_check(
		absf(float(weather.call("get_temperature_c")) - storm_temperature) <= 0.0001
		and absf(float(weather.call("get_humidity")) - storm_humidity) <= 0.0001,
		"seasonal live axes детерминированно реконструированы после restore",
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

	# Повторный round-trip из другого эволюционировавшего состояния (стабильность).
	for second_evolution_step: int in range(6):
		weather.call("_advance", 5.0)
	var evolved2: Dictionary = weather.call("export_save_dict")
	_check(
		evolved2.size() == 7,
		"export_save_dict отдаёт все 7 полей (got %d)" % evolved2.size(),
	)
	_check(
		not evolved2.has("humidity") \
				and not evolved2.has("precipitation_kind") \
				and not evolved2.has("precipitation_intensity") \
				and not evolved2.has("temperature_c"),
		"live temperature/humidity/rain не попадают в weather save payload",
	)
	weather.call("restore_persisted_state", { })
	weather.call("restore_persisted_state", evolved2)
	_check(
		_dicts_match(evolved2, weather.call("export_save_dict")),
		"повторный export->reset->restore->export бит-в-бит",
	)

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
