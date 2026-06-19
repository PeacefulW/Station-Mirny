extends SceneTree

# Проба Weather Runtime V0: симулирует ход игрового времени (эмит time_tick),
# гоняет режимы и проверяет:
# - видны все три режима (clear/cloudy/overcast) с adjacent-only переходами
# - weather_changed эмитится на сменах
# - облачность растёт clear < cloudy < overcast (полосы режимов)
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
	for _step: int in range(4000):
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
	_check(_changes.size() >= 6 and int(bus.weather_changed.get_connections().size()) >= 1, "weather_changed эмитится")
	_check(_adjacent_only(), "переходы только соседние (нет clear<->overcast напрямую)")
	_check(
		float(cloud_by_regime.get("core:clear", 1.0)) < float(cloud_by_regime.get("core:cloudy", 0.0))
		and float(cloud_by_regime.get("core:cloudy", 1.0)) < float(cloud_by_regime.get("core:overcast", 0.0)),
		"облачность растёт clear < cloudy < overcast",
	)
	_check(
		float(wind_target_by_regime.get("core:clear", 1.0)) < float(wind_target_by_regime.get("core:overcast", 0.0)),
		"цель ветра растёт clear < overcast",
	)

	# WindRuntime тянется к цели погоды. В headless delta крошечный, поэтому
	# проверяем НАПРАВЛЕНИЕ движения: на overcast (высокая цель) ветер за
	# время приближается к цели, а не точное мгновенное совпадение.
	var wind_before: float = wind.get_wind_strength()
	var target_before: float = weather.get_target_wind_strength()
	for _i: int in range(900):
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


func _check(passed: bool, description: String) -> void:
	if passed:
		print("weather_runtime_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("weather_runtime_probe: FAIL %s" % description)
