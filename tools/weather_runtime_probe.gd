extends SceneTree

# Проба Weather Runtime V1: симулирует ход игрового времени (эмит time_tick),
# гоняет режимы и проверяет:
# - видны все три режима (clear/cloudy/overcast) с adjacent-only переходами
# - weather_changed эмитится на сменах
# - облачность растёт clear < cloudy < overcast (полосы режимов)
# - влажность живая, нормализованная и растёт между authored regimes
# - сезон меняет температуру/влажность и bias будущего режима без второго RNG
# - дождь причинно и монотонно растёт от влажности при фиксированных облаках
# - цель ветра растёт clear < overcast, и WindRuntime тянется к ней.
# Headless ок. Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --headless --path . -s tools/weather_runtime_probe.gd

var _failures: Array[String] = []
var _changes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var weather: Node = root.get_node_or_null("WeatherRuntime")
	var wind: Node = root.get_node_or_null("WindRuntime")
	var tm: Node = root.get_node_or_null("TimeManager")
	var bus: Node = root.get_node_or_null("EventBus")
	if weather == null or wind == null or tm == null or bus == null:
		push_error("weather_runtime_probe: autoloads missing")
		quit(1)
		return
	bus.weather_changed.connect(
		func(r: StringName, p: StringName) -> void:
			_changes.append([str(p), str(r)])
	)

	var cloud_by_regime: Dictionary = { }
	var wind_target_by_regime: Dictionary = { }
	var seen: Dictionary = { }
	var hour: float = 6.0
	var day: int = 1
	for step_index: int in range(4000):
		hour += 0.5
		if hour >= 24.0:
			hour -= 24.0
			day += 1
			tm.current_day = day
		bus.time_tick.emit(hour, hour / 24.0)
		await process_frame
		var rid: String = str(weather.get_active_regime_id())
		seen[rid] = true
		cloud_by_regime[rid] = weather.get_cloud_cover()
		wind_target_by_regime[rid] = weather.get_target_wind_strength()
		if seen.size() >= 3 and _changes.size() >= 6:
			break

	print("weather_runtime_probe: seen=%s changes=%d" % [str(seen.keys()), _changes.size()])
	print(
		"weather_runtime_probe: cloud clear=%.2f cloudy=%.2f overcast=%.2f" % [
			float(cloud_by_regime.get("core:clear", -1.0)),
			float(cloud_by_regime.get("core:cloudy", -1.0)),
			float(cloud_by_regime.get("core:overcast", -1.0)),
		],
	)
	_check(
		seen.has("core:clear") and seen.has("core:cloudy") and seen.has("core:overcast"),
		"все три режима достигнуты",
	)
	_check(
		_changes.size() >= 6 and int(bus.weather_changed.get_connections().size()) >= 1,
		"weather_changed эмитится",
	)
	_check(_adjacent_only(), "переходы только соседние (нет clear<->overcast напрямую)")
	_check(
		float(cloud_by_regime.get("core:clear", 1.0))
		< float(cloud_by_regime.get("core:cloudy", 0.0))
		and float(cloud_by_regime.get("core:cloudy", 1.0))
		< float(cloud_by_regime.get("core:overcast", 0.0)),
		"облачность растёт clear < cloudy < overcast",
	)
	_check(
		float(wind_target_by_regime.get("core:clear", 1.0))
		< float(wind_target_by_regime.get("core:overcast", 0.0)),
		"цель ветра растёт clear < overcast",
	)

	var humidity_by_regime: Dictionary = { }
	for regime_id: StringName in [&"core:clear", &"core:cloudy", &"core:overcast"]:
		weather.call("set_debug_regime", regime_id)
		var humidity: float = float(weather.call("get_humidity"))
		humidity_by_regime[String(regime_id)] = humidity
		_check(
			humidity >= 0.0 and humidity <= 1.0,
			"%s humidity в 0..1 (%.3f)" % [regime_id, humidity],
		)
	weather.call("clear_debug_regime")
	_check(
		float(humidity_by_regime["core:clear"])
		< float(humidity_by_regime["core:cloudy"])
		and float(humidity_by_regime["core:cloudy"])
		< float(humidity_by_regime["core:overcast"]),
		"влажность растёт clear < cloudy < overcast (%s)" % str(humidity_by_regime),
	)

	# При фиксированном weather sample меняем только effective season. Итоговые
	# temperature/humidity остаются собственностью WeatherRuntime.
	weather.call("set_debug_regime", &"core:cloudy")
	var seasonal_temperatures: Array[float] = []
	var seasonal_humidity: Array[float] = []
	for season_kind: int in range(4):
		tm.call("set_debug_season", season_kind)
		seasonal_temperatures.append(float(weather.call("get_temperature_c")))
		seasonal_humidity.append(float(weather.call("get_humidity")))
	# Плечевые фазы (spore/storm) намеренно равны по температуре: симметричные
	# плечи дают равномерный годовой цикл без плоской половины и рывка. Их
	# различают влажность и веса режимов, что проверяется ниже.
	_check(
		seasonal_temperatures[0] > seasonal_temperatures[1]
		and is_equal_approx(seasonal_temperatures[1], seasonal_temperatures[3])
		and seasonal_temperatures[3] > seasonal_temperatures[2],
		"temperature следует offsets warm > spore == storm > cold (%s)"
		% str(seasonal_temperatures),
	)
	_check(
		seasonal_humidity[3] > seasonal_humidity[1]
		and seasonal_humidity[1] > seasonal_humidity[2]
		and seasonal_humidity[2] > seasonal_humidity[0]
		and _all_normalized(seasonal_humidity),
		"humidity следует offsets storm > spore > cold > warm (%s)"
		% str(seasonal_humidity),
	)

	# Одинаковый deterministic roll распределяется по разным effective weights:
	# storm должен заметно чаще выбирать overcast, чем warm.
	var before_weight_probe: Dictionary = weather.call("export_save_dict") as Dictionary
	weather.call(
		"restore_persisted_state",
		{
			"active_regime": "core:cloudy",
			"next_regime": "core:cloudy",
			"in_transition": false,
			"transition": 0.0,
			"remaining_hours": 4.0,
			"weather_time_hours": 20.0,
			"transition_count": 0,
		},
	)
	var overcast_choices: Array[int] = []
	for selection_season: int in [0, 3]:
		tm.call("set_debug_season", selection_season)
		var overcast_count: int = 0
		for salt: int in range(128):
			weather.set("_transition_count", salt)
			if String(weather.call("_select_next_regime", &"core:cloudy")) == "core:overcast":
				overcast_count += 1
		overcast_choices.append(overcast_count)
	_check(
		overcast_choices[1] > overcast_choices[0] + 24,
		"storm bias чаще выбирает overcast, чем warm (%s/128)" % str(overcast_choices),
	)
	weather.call("restore_persisted_state", before_weight_probe)
	tm.call("clear_debug_season")
	weather.call("clear_debug_regime")

	# Фиксируем overcast + полную облачность и меняем только humidity: rain
	# обязан быть монотонной производной, а не отдельной случайной осью.
	weather.call("set_debug_regime", &"core:overcast")
	weather.call("set_debug_cloud_cover", 1.0)
	var humidity_samples: Array[float] = [0.0, 0.72, 0.80, 0.90, 1.0]
	var rain_samples: Array[float] = []
	for humidity_sample: float in humidity_samples:
		weather.call("set_debug_humidity", humidity_sample)
		rain_samples.append(float(weather.call("get_precipitation_intensity")))
	_check(
		_is_non_decreasing(rain_samples),
		"rain монотонно растёт от humidity (%s)" % str(rain_samples),
	)
	_check(is_zero_approx(rain_samples[0]), "сухой воздух не даёт дождь")
	weather.call("set_debug_humidity", 0.80)
	_check(
		rain_samples[2] > 0.0 and int(weather.call("get_precipitation_kind")) == 1,
		"80%% humidity под плотным overcast публикует RAIN (%.3f)" % rain_samples[2],
	)
	weather.call("set_debug_cloud_cover", 0.40)
	_check(
		is_zero_approx(float(weather.call("get_precipitation_intensity"))),
		"80% humidity без достаточной облачности сама по себе не создаёт дождь",
	)
	weather.call("set_debug_humidity", 1.0)
	weather.call("set_debug_cloud_cover", 1.0)
	_check(
		int(weather.call("get_precipitation_kind")) == 1 and rain_samples[-1] > 0.9,
		"насыщенный overcast публикует RAIN высокой интенсивности",
	)
	var cloud_samples: Array[float] = [0.0, 0.65, 0.75, 0.90, 1.0]
	var cloud_rain_samples: Array[float] = []
	for cloud_sample: float in cloud_samples:
		weather.call("set_debug_cloud_cover", cloud_sample)
		cloud_rain_samples.append(float(weather.call("get_precipitation_intensity")))
	_check(
		_is_non_decreasing(cloud_rain_samples),
		"rain монотонно растёт от cloud cover (%s)" % str(cloud_rain_samples),
	)
	weather.call("set_debug_cloud_cover", 0.0)
	_check(
		is_zero_approx(float(weather.call("get_precipitation_intensity"))) \
				and int(weather.call("get_precipitation_kind")) == 0,
		"без облачности осадки выключены даже при humidity=1",
	)
	weather.call("set_debug_regime", &"core:clear")
	weather.call("set_debug_cloud_cover", 1.0)
	_check(
		is_zero_approx(float(weather.call("get_precipitation_intensity"))),
		"clear остаётся сухим даже при dev humidity/cloud override",
	)
	weather.call("clear_debug_humidity")
	weather.call("clear_debug_cloud_cover")
	weather.call("clear_debug_regime")

	var save_data: Dictionary = weather.call("export_save_dict") as Dictionary
	_check(
		not save_data.has("humidity") \
				and not save_data.has("precipitation_kind") \
				and not save_data.has("precipitation_intensity") \
				and not save_data.has("temperature_c") \
				and save_data.size() == 7,
		"live temperature/humidity/rain не дублируются в slow-state save",
	)

	var transition_humidity: Array[float] = []
	var transition_rain: Array[float] = []
	for transition_sample: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		weather.call(
			"restore_persisted_state",
			{
				"active_regime": "core:cloudy",
				"next_regime": "core:overcast",
				"in_transition": true,
				"transition": transition_sample,
				"remaining_hours": 0.0,
				"weather_time_hours": 40.0,
				"transition_count": 3,
			},
		)
		transition_humidity.append(float(weather.call("get_humidity")))
		transition_rain.append(float(weather.call("get_precipitation_intensity")))
	_check(
		_is_non_decreasing(transition_humidity) and _all_normalized(transition_humidity),
		"humidity плавно смешивается cloudy->overcast (%s)" % str(transition_humidity),
	)
	_check(
		_is_non_decreasing(transition_rain) \
				and _all_normalized(transition_rain) \
				and _max_adjacent_delta(transition_rain) < 0.5,
		"rain bounded/continuous на cloudy->overcast (%s)" % str(transition_rain),
	)
	weather.call("restore_persisted_state", save_data)

	# WindRuntime тянется к цели погоды. В headless delta крошечный, поэтому
	# проверяем НАПРАВЛЕНИЕ движения: на overcast (высокая цель) ветер за
	# время приближается к цели, а не точное мгновенное совпадение.
	var wind_before: float = wind.get_wind_strength()
	var target_before: float = weather.get_target_wind_strength()
	for wind_step: int in range(900):
		bus.time_tick.emit(hour, hour / 24.0)
		await process_frame
	var wind_after: float = wind.get_wind_strength()
	var target_after: float = weather.get_target_wind_strength()
	print(
		"weather_runtime_probe: wind %.3f->%.3f target~%.3f regime=%s" % [
			wind_before,
			wind_after,
			target_after,
			str(weather.get_active_regime_id()),
		],
	)
	_check(
		absf(wind_after - target_after) < absf(wind_before - target_before),
		"WindRuntime приближается к цели погоды (%.3f -> %.3f к цели ~%.2f)" % [
			absf(wind_before - target_before),
			absf(wind_after - target_after),
			target_after,
		],
	)

	if _failures.is_empty():
		print("weather_runtime_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for f: String in _failures:
			print("weather_runtime_probe: FAILED %s" % f)
		quit(1)


func _adjacent_only() -> bool:
	for change: Array in _changes:
		var from_id: String = str(change[0])
		var to_id: String = str(change[1])
		if (from_id == "core:clear" and to_id == "core:overcast") \
				or (from_id == "core:overcast" and to_id == "core:clear"):
			return false
	return true


func _is_non_decreasing(values: Array[float]) -> bool:
	for index: int in range(1, values.size()):
		if values[index] + 0.0001 < values[index - 1]:
			return false
	return true


func _all_normalized(values: Array[float]) -> bool:
	for value: float in values:
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return false
	return true


func _max_adjacent_delta(values: Array[float]) -> float:
	var maximum: float = 0.0
	for index: int in range(1, values.size()):
		maximum = maxf(maximum, absf(values[index] - values[index - 1]))
	return maximum


func _check(passed: bool, description: String) -> void:
	if passed:
		print("weather_runtime_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("weather_runtime_probe: FAIL %s" % description)
