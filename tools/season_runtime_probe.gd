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

## Потолок суточного изменения сезонного оффсета. Годовой размах 52 C за 60
## дней даёт 1.73 C/день при идеально равномерном распределении; допускаем
## умеренную неравномерность реального цикла, но не рывок.
const MAX_DAILY_OFFSET_STEP_C: float = 3.0

## Зазор выборки левой стороны фазового шва и аналитические множители допуска.
const HOUR_EPSILON: float = 0.001
const SEAM_SLOPE_BOUND: float = 1.5
const SEAM_SAFETY_FACTOR: float = 2.0

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
	_check_annual_minimum(time_manager)
	_check_gradual_year(time_manager)
	_check_display_and_calendar(time_manager)
	_check_time_scale(time_manager)
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
	# Кривая опирается на центр фазы: день 8 в полдень при 15-дневной фазе —
	# ровно середина WARM, где профиль читается точно.
	_set_time(time_manager, 12.0, 8, WARM)
	_check_close(_season_progress(time_manager), 0.5, "season progress выводится из day+hour")
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

	# Каждая фаза читает собственный профиль в своей середине.
	var authored_temperature: Array[float] = [6.0, -14.0, -46.0, -14.0]
	for season_kind: int in range(4):
		_set_time(time_manager, 12.0, 8 + season_kind * 15, season_kind)
		_check_close(
			_temperature_offset(time_manager),
			authored_temperature[season_kind],
			"фаза %d читает авторский профиль в своём центре" % season_kind,
		)

	# Стык фаз — точка сплайна, а не авторское значение и не простая середина
	# между двумя соседями: Catmull-Rom учитывает и внешние ключевые кадры.
	# Ожидаемые числа посчитаны вручную по формуле при t=0.5 на сегменте
	# STORM->WARM с опорами (COLD, STORM, WARM, SPORE), независимо от кода:
	#   температура 0.5*(-28 + 26 + 4 - 3.5)            = -0.75
	#   влажность   0.5*(0.24 - 0.025 - 0.255 + 0.08375) =  0.021875
	#   вес clear   0.5*(0.9 + 0.175 + 1.0625 - 0.35)    =  0.89375
	_set_time(time_manager, 0.0, 1, WARM)
	_check_close(_season_progress(time_manager), 0.0, "фаза начинается с progress=0")
	_check_close(
		_temperature_offset(time_manager),
		-0.75,
		"стык STORM->WARM берёт значение сплайна",
	)
	_check_close(
		_humidity_offset(time_manager),
		0.021875,
		"humidity на стыке берёт значение сплайна",
	)
	_check_close(
		_regime_multiplier(time_manager, &"core:clear"),
		0.89375,
		"regime weight на стыке берёт значение сплайна",
	)


func _check_annual_minimum(time_manager: Node) -> void:
	var minimum_offset: float = INF
	var minimum_day: int = -1
	for day: int in range(1, 61):
		var season: int = (day - 1) / 15
		for hour_step: int in range(4):
			_set_time(time_manager, float(hour_step) * 6.0, day, season)
			var offset: float = _temperature_offset(time_manager)
			if offset < minimum_offset:
				minimum_offset = offset
				minimum_day = day
	_check(
		minimum_day >= 31 and minimum_day <= 45,
		"годовой минимум лежит внутри COLD, а не SPORE (день %d)" % minimum_day,
	)
	_check_close(
		minimum_offset,
		-46.0,
		"годовой минимум достигает авторского COLD offset",
	)


## Регрессия: год не должен стоять на месте полфазы, а потом обваливаться.
## Проверяем и потолок суточного шага, и отсутствие мёртвых участков.
func _check_gradual_year(time_manager: Node) -> void:
	var offsets: Array[float] = []
	for day: int in range(1, 61):
		_set_time(time_manager, 12.0, day, (day - 1) / 15)
		offsets.append(_temperature_offset(time_manager))
	var max_step: float = 0.0
	var max_step_day: int = 0
	var flat_days: int = 0
	for index: int in range(offsets.size()):
		var step: float = absf(offsets[(index + 1) % offsets.size()] - offsets[index])
		if step > max_step:
			max_step = step
			max_step_day = index + 1
		if step < 0.2:
			flat_days += 1
	_check(
		max_step <= MAX_DAILY_OFFSET_STEP_C,
		"суточный шаг ограничен %.1f C (максимум %.2f на дне %d)" % [
			MAX_DAILY_OFFSET_STEP_C,
			max_step,
			max_step_day,
		],
	)
	_check(
		flat_days <= 6,
		"в году нет длинного мёртвого участка (%d почти неподвижных дней)" % flat_days,
	)


## Шов фаз — это «день 15, час 24» == «день 16, час 0». Ровно час 24 задать
## нельзя (он нормализуется в 0), поэтому левая сторона берётся за HOUR_EPSILON
## до шва. Допуск выводится из этого зазора аналитически, а не подбирается под
## результат: максимальная производная smoothstep равна 1.5, поэтому расхождение
## не может превышать gap * 1.5 * размах пары профилей по данной оси. Реальный
## разрыв кривой такой оценке не подчиняется и тест уронит.
## Имена фаз — ключи локализации в данных, с покрытием в обеих локалях.
## День внутри фазы выводится из авторитетного дня, без отдельного счётчика.
func _check_display_and_calendar(time_manager: Node) -> void:
	var expected_keys: Array[StringName] = [
		&"SEASON_WARM",
		&"SEASON_SPORE",
		&"SEASON_COLD",
		&"SEASON_STORM",
	]
	var ru_source: String = FileAccess.get_file_as_string("res://locale/ru/messages.po")
	var en_source: String = FileAccess.get_file_as_string("res://locale/en/messages.po")
	for season_kind: int in range(4):
		time_manager.call("set_debug_season", season_kind)
		var key: StringName = time_manager.call("get_season_display_name_key")
		_check(
			key == expected_keys[season_kind],
			"фаза %d отдаёт ключ %s" % [season_kind, key],
		)
		_check(
			ru_source.contains('msgid "%s"' % key) and en_source.contains('msgid "%s"' % key),
			"%s переведён в обеих локалях" % key,
		)
	time_manager.call("clear_debug_season")

	_check(int(time_manager.call("get_season_length_days")) == 15, "длина фазы читается публично")
	for day_case: Array in [[1, 1], [15, 15], [16, 1], [38, 8], [60, 15]]:
		_set_time(time_manager, 12.0, int(day_case[0]), (int(day_case[0]) - 1) / 15)
		_check(
			int(time_manager.call("get_day_in_season")) == int(day_case[1]),
			"день %d = %d-й день фазы" % [int(day_case[0]), int(day_case[1])],
		)


## Ускорение — dev-состояние: лестница цикличная, в сейв не попадает, и ни
## reset, ни restore не оставляют мир разогнанным.
func _check_time_scale(time_manager: Node) -> void:
	time_manager.call("set_time_scale", 1.0)
	var ladder: Array[float] = [10.0, 60.0, 300.0, 1.0]
	for expected: float in ladder:
		time_manager.call("debug_cycle_time_scale")
		_check_close(
			float(time_manager.call("get_time_scale")),
			expected,
			"лестница ускорения переходит к x%d" % int(expected),
		)

	time_manager.call("set_time_scale", 300.0)
	time_manager.call("reset_for_new_game")
	_check_close(float(time_manager.call("get_time_scale")), 1.0, "new game сбрасывает ускорение")

	time_manager.call("set_time_scale", 300.0)
	time_manager.call("restore_persisted_state", 8.0, 20, 1)
	_check_close(
		float(time_manager.call("get_time_scale")),
		1.0,
		"загруженный сейв не стартует разогнанным",
	)

	var collector_source: String = FileAccess.get_file_as_string(
		"res://core/autoloads/save_collectors.gd",
	)
	_check(
		not collector_source.contains("time_scale"),
		"ускорение не попадает в save payload",
	)


func _check_modifier_continuity(time_manager: Node) -> void:
	var profiles: Array[SeasonProfileScript] = []
	for profile_path: String in CORE_PROFILE_PATHS:
		profiles.append(ResourceLoader.load(profile_path) as SeasonProfileScript)
	var seam_scale: float = (HOUR_EPSILON / 24.0) / 15.0 * SEAM_SLOPE_BOUND * SEAM_SAFETY_FACTOR
	var axis_names: Array[String] = ["temperature", "humidity", "overcast weight"]
	for active_season: int in range(4):
		var next_season: int = (active_season + 1) % 4
		var active_profile: SeasonProfileScript = profiles[active_season]
		var next_profile: SeasonProfileScript = profiles[next_season]
		var spans: Array[float] = [
			absf(next_profile.temperature_offset_c - active_profile.temperature_offset_c),
			absf(next_profile.humidity_offset - active_profile.humidity_offset),
			absf(
				next_profile.get_weather_regime_weight_multiplier(&"core:overcast")
				- active_profile.get_weather_regime_weight_multiplier(&"core:overcast"),
			),
		]
		_set_time(time_manager, 24.0 - HOUR_EPSILON, 15, active_season)
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
		for axis: int in range(before.size()):
			var delta: float = absf(before[axis] - after[axis])
			var bound: float = maxf(spans[axis] * seam_scale, 1e-9)
			_check(
				delta <= bound,
				"%s непрерывна %d->%d (delta %.9f <= bound %.9f)" % [
					axis_names[axis],
					active_season,
					next_season,
					delta,
					bound,
				],
			)


func _check_debug_override(time_manager: Node) -> void:
	_set_time(time_manager, 0.0, 1, WARM)
	time_manager.call("set_debug_season", COLD)
	_check(int(time_manager.call("get_effective_season")) == COLD, "debug season форсится")
	_check(int(time_manager.get("current_season")) == WARM, "debug forcing не меняет owner state")
	_check_close(_season_progress(time_manager), 0.5, "debug forcing возвращает profile anchor")
	_check_close(_temperature_offset(time_manager), -46.0, "debug forcing читает exact profile")
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

	# Регрессия: форсирование обязано быть выходимым. Раньше одно нажатие J
	# замораживало показанную фазу навсегда, и сезон выглядел как «не меняется».
	_set_time(time_manager, 0.0, 1, WARM)
	_check(not bool(time_manager.call("is_debug_season_forced")), "старт не форсирован")
	var forced_path: Array[int] = []
	for press: int in range(4):
		time_manager.call("debug_cycle_season")
		forced_path.append(int(time_manager.call("get_effective_season")))
	var expected_path: Array[int] = [SPORE, COLD, STORM, WARM]
	_check(
		forced_path == expected_path,
		"цикл J проходит все фазы и возвращается (%s)" % str(forced_path),
	)
	_check(
		not bool(time_manager.call("is_debug_season_forced")),
		"полный круг J возвращает естественный ход",
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
