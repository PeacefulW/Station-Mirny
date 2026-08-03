extends SceneTree

const SeasonProfileScript = preload("res://core/systems/world/season_profile.gd")

const WARM: int = 0
const SPORE: int = 1
const COLD: int = 2
const STORM: int = 3
const CORE_PROFILE_PATHS: Array[String] = [
	"res://data/seasons/warm.tres",
	"res://data/seasons/spore.tres",
	"res://data/seasons/cold.tres",
	"res://data/seasons/storm.tres",
]

var _failures: Array[String] = []
var _season_changes: Array[Array] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var event_bus: Node = root.get_node_or_null("EventBus")
	if time_manager == null or event_bus == null:
		push_error("season_runtime_probe: TimeManager/EventBus autoload missing")
		quit(1)
		return

	event_bus.season_changed.connect(
		func(new_season: int, previous_season: int) -> void:
			_season_changes.append([new_season, previous_season])
	)

	_check_profile_resources(time_manager)
	_check_time_collector_contract()
	_check_authored_samples(time_manager)
	_check_modifier_continuity(time_manager)
	_check_debug_override(time_manager)
	_check_natural_cycle_and_events(time_manager)
	_check_save_restore(time_manager)
	time_manager.call("reset_for_new_game")

	if _failures.is_empty():
		print("season_runtime_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("season_runtime_probe: FAILED %s" % failure)
		quit(1)


func _check_profile_resources(time_manager: Node) -> void:
	var ids: Dictionary = { }
	var kinds: Dictionary = { }
	for profile_path: String in CORE_PROFILE_PATHS:
		var profile: SeasonProfileScript = ResourceLoader.load(profile_path) as SeasonProfileScript
		_check(profile != null, "%s загружается" % profile_path)
		if profile == null:
			continue
		_check(profile.is_valid_profile(4), "%s проходит validation" % profile.id)
		ids[profile.id] = true
		kinds[profile.season_kind] = true
	_check(ids.size() == 4, "stable profile ids уникальны (%s)" % str(ids.keys()))
	_check(kinds.size() == 4, "все четыре season_kind представлены (%s)" % str(kinds.keys()))

	var balance: Resource = time_manager.get("balance") as Resource
	_check(balance != null, "TimeBalance загружен")
	if balance != null:
		_check(int(balance.get("season_length_days")) == 15, "длительность фазы остаётся 15 дней")
		var registered_profiles: Array = balance.get("season_profiles") as Array
		_check(registered_profiles.size() == 4, "TimeBalance регистрирует четыре профиля")


func _check_time_collector_contract() -> void:
	var source: String = FileAccess.get_file_as_string("res://core/autoloads/save_collectors.gd")
	var section_start: int = source.find("static func collect_time()")
	var section_end: int = source.find("static func collect_weather()", section_start)
	var section: String = source.substr(section_start, section_end - section_start)
	_check(
		section_start >= 0
		and section_end > section_start
		and section.contains('"current_hour": TimeManager.current_hour')
		and section.contains('"current_day": TimeManager.current_day')
		and section.contains('"current_season": int(TimeManager.current_season)')
		and not section.contains("season_progress")
		and not section.contains("temperature_offset")
		and not section.contains("humidity_offset"),
		"SaveCollectors сохраняет только три authoritative time fields",
	)


func _check_authored_samples(time_manager: Node) -> void:
	_set_time(time_manager, 0.0, 1, WARM)
	_check_close(_temperature_offset(time_manager), 6.0, "WARM temperature offset = +6 C")
	_check_close(_humidity_offset(time_manager), -0.08, "WARM humidity offset = -0.08")
	_check_close(
		_regime_multiplier(time_manager, &"core:clear"),
		1.35,
		"WARM clear weight = 1.35",
	)
	_check_close(
		_regime_multiplier(time_manager, &"mod:new_regime"),
		1.0,
		"missing regime id нейтрален",
	)
	_check_close(_season_progress(time_manager), 0.0, "фаза начинается с progress=0")

	# День 8, полдень при 15-дневной фазе — ровно середина WARM -> SPORE.
	_set_time(time_manager, 12.0, 8, WARM)
	_check_close(_season_progress(time_manager), 0.5, "season progress выводится из day+hour")
	_check_close(
		_temperature_offset(time_manager),
		3.5,
		"temperature offset плавно интерполируется",
	)
	_check_close(
		_humidity_offset(time_manager),
		-0.02,
		"humidity offset плавно интерполируется",
	)
	_check_close(
		_regime_multiplier(time_manager, &"core:clear"),
		1.125,
		"regime weight плавно интерполируется",
	)


func _check_modifier_continuity(time_manager: Node) -> void:
	for active_season: int in range(4):
		var next_season: int = (active_season + 1) % 4
		_set_time(time_manager, 23.999, 15, active_season)
		var before: Array[float] = [
			_temperature_offset(time_manager),
			_humidity_offset(time_manager),
			_regime_multiplier(time_manager, &"core:overcast"),
		]
		_set_time(time_manager, 0.0, 16, next_season)
		var after: Array[float] = [
			_temperature_offset(time_manager),
			_humidity_offset(time_manager),
			_regime_multiplier(time_manager, &"core:overcast"),
		]
		_check(
			_max_delta(before, after) < 0.0001,
			"модификаторы непрерывны %d->%d (%s -> %s)" % [
				active_season,
				next_season,
				str(before),
				str(after),
			],
		)


func _check_debug_override(time_manager: Node) -> void:
	_set_time(time_manager, 0.0, 1, WARM)
	time_manager.call("set_debug_season", COLD)
	_check(int(time_manager.call("get_effective_season")) == COLD, "debug season форсится")
	_check(int(time_manager.get("current_season")) == WARM, "debug forcing не меняет owner state")
	_check_close(_season_progress(time_manager), 0.0, "debug forcing возвращает profile anchor")
	_check_close(_temperature_offset(time_manager), -5.0, "debug forcing читает exact profile")
	time_manager.call("debug_cycle_season")
	_check(
		int(time_manager.call("get_effective_season")) == STORM,
		"debug cycle следует fixed order",
	)
	time_manager.call("clear_debug_season")
	_check(
		int(time_manager.call("get_effective_season")) == WARM,
		"clear возвращает natural season",
	)

	time_manager.call("set_debug_season", STORM)
	time_manager.call("reset_for_new_game")
	_check(int(time_manager.call("get_effective_season")) == WARM, "reset очищает debug season")
	time_manager.call("set_debug_season", STORM)
	_set_time(time_manager, 4.0, 20, COLD)
	_check(int(time_manager.call("get_effective_season")) == COLD, "restore очищает debug season")


func _check_natural_cycle_and_events(time_manager: Node) -> void:
	_season_changes.clear()
	_set_time(time_manager, 0.0, 1, WARM)
	_check(
		_season_changes == [[WARM, WARM]],
		"restore публикует initial season_changed(new==previous)",
	)
	_season_changes.clear()
	for day_step: int in range(60):
		time_manager.call("_on_new_day")
	var expected: Array[Array] = [
		[SPORE, WARM],
		[COLD, SPORE],
		[STORM, COLD],
		[WARM, STORM],
	]
	_check(_season_changes == expected, "natural cycle WARM->SPORE->COLD->STORM->WARM")
	_check(int(time_manager.get("current_day")) == 61, "natural cycle сохраняет day owner")


func _check_save_restore(time_manager: Node) -> void:
	_set_time(time_manager, 12.0, 38, COLD)
	var expected_progress: float = _season_progress(time_manager)
	var expected_temperature: float = _temperature_offset(time_manager)
	var expected_humidity: float = _humidity_offset(time_manager)
	var save_data: Dictionary = {
		"current_hour": float(time_manager.get("current_hour")),
		"current_day": int(time_manager.get("current_day")),
		"current_season": int(time_manager.get("current_season")),
	}
	_check(
		save_data.size() == 3
		and save_data.has("current_hour")
		and save_data.has("current_day")
		and save_data.has("current_season"),
		"TimeSaveData остаётся exact 3 fields",
	)

	time_manager.call("set_debug_season", STORM)
	time_manager.call("reset_for_new_game")
	time_manager.call(
		"restore_persisted_state",
		float(save_data["current_hour"]),
		int(save_data["current_day"]),
		int(save_data["current_season"]),
	)
	_check(
		int(time_manager.call("get_effective_season")) == COLD,
		"restore возвращает phase identity",
	)
	_check_close(
		_season_progress(time_manager),
		expected_progress,
		"restore реконструирует progress",
	)
	_check_close(
		_temperature_offset(time_manager),
		expected_temperature,
		"restore реконструирует temperature offset",
	)
	_check_close(
		_humidity_offset(time_manager),
		expected_humidity,
		"restore реконструирует humidity offset",
	)


func _set_time(time_manager: Node, hour: float, day: int, season: int) -> void:
	time_manager.call("restore_persisted_state", hour, day, season)


func _season_progress(time_manager: Node) -> float:
	return float(time_manager.call("get_season_progress"))


func _temperature_offset(time_manager: Node) -> float:
	return float(time_manager.call("get_season_temperature_offset_c"))


func _humidity_offset(time_manager: Node) -> float:
	return float(time_manager.call("get_season_humidity_offset"))


func _regime_multiplier(time_manager: Node, regime_id: StringName) -> float:
	return float(time_manager.call("get_weather_regime_weight_multiplier", regime_id))


func _max_delta(a: Array[float], b: Array[float]) -> float:
	var maximum: float = 0.0
	for index: int in range(a.size()):
		maximum = maxf(maximum, absf(a[index] - b[index]))
	return maximum


func _check_close(actual: float, expected: float, description: String) -> void:
	_check(absf(actual - expected) <= 0.0001, "%s (%.5f)" % [description, actual])


func _check(passed: bool, description: String) -> void:
	if passed:
		print("season_runtime_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("season_runtime_probe: FAIL %s" % description)
