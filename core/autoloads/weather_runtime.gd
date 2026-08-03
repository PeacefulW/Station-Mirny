class_name WeatherRuntimeSingleton
extends Node
## Единственный владелец погодного состояния (environment runtime,
## ADR-0007 layers 2 slow + 3 local). Эволюционирует активный режим по
## игровому времени (детерминированно от seed + дня), задаёт цель ветра для
## WindRuntime, эмитит weather_changed на смену режима. Плавные оси читаются
## геттерами (pull-модель), не событием в кадр. O(1) на тик.
## V2: влажность и дождь — живые авторитетные оси; сезон TimeManager смещает
## влажность, температуру и веса будущего режима, но не пишет погоду напрямую.
## Контракты: docs/02_system_specs/world/weather_runtime.md и
## docs/02_system_specs/world/humidity_and_rain_runtime.md и
## docs/02_system_specs/world/seasons_and_temperature_runtime.md

const WeatherRegimeProfile = preload("res://core/systems/world/weather_regime_profile.gd")
const WeatherBalance = preload("res://data/balance/weather_balance.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const REGIME_DIRECTORY: String = "res://data/weather"
## Глобальные пороги погодной физики (точка замерзания). Моды могут подменить
## файл по этому пути.
const BALANCE_PATH: String = "res://data/balance/weather_balance.tres"
const START_REGIME_ID: StringName = &"core:clear"
const TRANSITION_WINDOW_HOURS: float = 2.0
## Пинг-понг порядок плавной дев-смены погоды (соседние режимы).
const DEBUG_CYCLE_ORDER: Array[StringName] = [&"core:clear", &"core:cloudy", &"core:overcast"]
const DEBUG_TRANSITION_SECONDS: float = 3.5
## Базовое направление ветра (откуда дует), на которое режим накладывает дрейф.
const WIND_BASE_HEADING_DEG: float = -13.0
## Прямая солнечная окклюзия облаками: 0 = солнце открыто, 1 = прямой луч закрыт.
const CLOUD_OCCLUSION_COVER_START: float = 0.10
const CLOUD_OCCLUSION_COVER_END: float = 0.95

enum PrecipitationKind {
	NONE = 0,
	RAIN = 1,
	SNOW = 2,
	ASH = 3,
	SPORE = 4,
}

var _balance: WeatherBalance = null
var _regimes_by_id: Dictionary = { }
var _active_id: StringName = START_REGIME_ID
var _next_id: StringName = START_REGIME_ID
var _in_transition: bool = false
var _transition: float = 0.0
var _remaining_hours: float = 0.0
var _weather_time_hours: float = 0.0
var _transition_count: int = 0
var _last_hour: float = -1.0
var _world_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
## Dev-форс режима (пробы/дев-сцены, не gameplay): замораживает эволюцию и
## возвращает оси выбранного режима без перехода.
var _debug_regime_id: StringName = &""
## Дев-кнопка плавной смены погоды: переход идёт по реальному времени.
var _debug_cycle_dir: int = 1
var _debug_fast_transition: bool = false
## Прямой дев-override облачности (клавиши +/-): пинит cloud_cover в реалтайме,
## чтобы вживую смотреть как тучки растут/плывут/сливаются. -1 = выключен.
var _debug_cover_override: float = -1.0
## Dev-only override влажности для причинных проб дождя. -1 = выключен.
var _debug_humidity_override: float = -1.0


func _ready() -> void:
	_load_balance()
	_load_regimes()
	_active_id = START_REGIME_ID
	_next_id = START_REGIME_ID
	_remaining_hours = _roll_duration(_active_id, 0)
	EventBus.time_tick.connect(_on_time_tick)
	EventBus.world_initialized.connect(_on_world_initialized)
	EventBus.weather_changed.emit(_active_id, _active_id)


## Только дев-переход по реальному времени (плавная кнопка смены погоды).
## Обычная эволюция идёт по игровому времени (time_tick), не здесь.
func _process(delta: float) -> void:
	if not _debug_fast_transition:
		return
	_weather_time_hours += delta * 0.25
	_transition += delta / DEBUG_TRANSITION_SECONDS
	if _transition >= 1.0:
		_commit_transition()
		_debug_fast_transition = false

# --- Публичные чтения ---


func get_active_regime_id() -> StringName:
	if not _debug_regime_id.is_empty():
		return _debug_regime_id
	return _active_id


func get_active_display_name_key() -> StringName:
	var profile: WeatherRegimeProfile = (
		_regimes_by_id.get(get_active_regime_id()) as WeatherRegimeProfile
	)
	if profile == null:
		return &""
	return profile.display_name_key

# --- Dev-only управление (пробы и dev-сцены, не gameplay-путь) ---


func set_debug_regime(regime_id: StringName) -> void:
	assert(_regimes_by_id.has(regime_id), "Unknown weather regime: %s" % regime_id)
	_debug_regime_id = regime_id


func clear_debug_regime() -> void:
	_debug_regime_id = &""


## Плавная дев-смена погоды на следующий соседний режим (пинг-понг по
## DEBUG_CYCLE_ORDER), переход за DEBUG_TRANSITION_SECONDS реального времени.
func debug_cycle_regime() -> void:
	_debug_regime_id = &""
	if _in_transition:
		# Уже в переходе — мгновенно завершаем текущий, чтобы кнопка отзывалась.
		_commit_transition()
	var index: int = DEBUG_CYCLE_ORDER.find(_active_id)
	if index < 0:
		index = 0
	if index >= DEBUG_CYCLE_ORDER.size() - 1:
		_debug_cycle_dir = -1
	elif index <= 0:
		_debug_cycle_dir = 1
	var target_index: int = clampi(index + _debug_cycle_dir, 0, DEBUG_CYCLE_ORDER.size() - 1)
	_next_id = DEBUG_CYCLE_ORDER[target_index]
	_in_transition = true
	_transition = 0.0
	_debug_fast_transition = true


func get_cloud_cover() -> float:
	if _debug_cover_override >= 0.0:
		return _debug_cover_override
	return _blended_axis(func(p: WeatherRegimeProfile) -> Vector2: return p.cloud_cover, 0.31)


## Дев: плавно подкрутить облачность (+/-). Пинит cloud_cover, эволюция замирает
## по этой оси; occlusion и слой облаков следуют автоматически.
func nudge_debug_cloud_cover(delta: float) -> void:
	var base: float = _debug_cover_override if _debug_cover_override >= 0.0 else get_cloud_cover()
	_debug_cover_override = clampf(base + delta, 0.0, 1.0)


func set_debug_cloud_cover(value: float) -> void:
	_debug_cover_override = clampf(value, 0.0, 1.0)


func clear_debug_cloud_cover() -> void:
	_debug_cover_override = -1.0


func get_cloud_occlusion() -> float:
	var cover: float = clampf(get_cloud_cover(), 0.0, 1.0)
	return smoothstep(CLOUD_OCCLUSION_COVER_START, CLOUD_OCCLUSION_COVER_END, cover)


func get_target_wind_strength() -> float:
	return _blended_axis(func(p: WeatherRegimeProfile) -> Vector2: return p.wind_strength, 0.0)


func get_target_wind_gustiness() -> float:
	return _blended_axis(func(p: WeatherRegimeProfile) -> Vector2: return p.wind_gustiness, 0.53)


## Целевое направление ветра: базовое + дрейф амплитудой режима.
func get_target_wind_heading_deg() -> float:
	var active: WeatherRegimeProfile = (
		_regimes_by_id.get(get_active_regime_id()) as WeatherRegimeProfile
	)
	if active == null:
		return WIND_BASE_HEADING_DEG
	var drift_amp: float = active.heading_drift_deg
	if _in_transition and _debug_regime_id.is_empty():
		var nxt: WeatherRegimeProfile = _regimes_by_id.get(_next_id) as WeatherRegimeProfile
		if nxt != null:
			drift_amp = lerpf(
				drift_amp,
				nxt.heading_drift_deg,
				smoothstep(0.0, 1.0, _transition),
			)
	# Медленный апериодичный мендр (value-noise по времени погоды) вместо
	# предсказуемых синусов: ветер «поворачивает», а не качается с периодом.
	var drift: float = _heading_meander(_weather_time_hours)
	return WIND_BASE_HEADING_DEG + drift_amp * drift

# --- Живые влажность и осадки ---


## Вид осадков разрешается температурой поверх уже посчитанного потенциала.
## Чистая функция без гистерезиса: нет скрытого состояния, значит нечего
## сохранять и нечему разъехаться с восстановленными погодными часами.
## Осознанное следствие: у самого порога kind может медленно переключаться —
## это гасится кросс-фейдом презентации, а не спрятанным состоянием.
func get_precipitation_kind() -> int:
	if get_precipitation_intensity() <= 0.0:
		return PrecipitationKind.NONE
	if get_temperature_c() <= _balance.freeze_temperature_c:
		return PrecipitationKind.SNOW
	return PrecipitationKind.RAIN


## Презентационный вес снега в полосе вокруг точки замерзания: 1 = чистый снег,
## 0 = чистый дождь. Только для слоёв презентации — на авторитетный kind не
## влияет. Существует, чтобы пересечение порога не читалось как рывок.
func get_snow_presentation_weight() -> float:
	var freeze: float = _balance.freeze_temperature_c
	var half_band: float = maxf(_balance.precipitation_crossfade_c, 0.0)
	var temperature: float = get_temperature_c()
	if is_zero_approx(half_band):
		return 1.0 if temperature <= freeze else 0.0
	return smoothstep(freeze + half_band, freeze - half_band, temperature)


func get_precipitation_intensity() -> float:
	var active: WeatherRegimeProfile = (
		_regimes_by_id.get(get_active_regime_id()) as WeatherRegimeProfile
	)
	if active == null:
		return 0.0
	var humidity: float = get_humidity()
	var cloud_cover: float = get_cloud_cover()
	var intensity: float = _rain_intensity_for_profile(active, humidity, cloud_cover)
	if _in_transition and _debug_regime_id.is_empty():
		var nxt: WeatherRegimeProfile = _regimes_by_id.get(_next_id) as WeatherRegimeProfile
		if nxt != null:
			var next_intensity: float = _rain_intensity_for_profile(nxt, humidity, cloud_cover)
			intensity = lerpf(intensity, next_intensity, smoothstep(0.0, 1.0, _transition))
	return clampf(intensity, 0.0, 1.0)


func get_humidity() -> float:
	if _debug_humidity_override >= 0.0:
		return _debug_humidity_override
	return clampf(
		_blended_axis(func(p: WeatherRegimeProfile) -> Vector2: return p.humidity, 0.5)
		+ _season_humidity_offset(),
		0.0,
		1.0,
	)


## Dev-only: задаёт влажность без изменения режима, чтобы проверять причинную
## связь humidity -> rain. Не является gameplay mutation path.
func set_debug_humidity(value: float) -> void:
	_debug_humidity_override = clampf(value, 0.0, 1.0)


func clear_debug_humidity() -> void:
	_debug_humidity_override = -1.0

# --- Живая глобальная температура внешнего воздуха ---


func get_temperature_c() -> float:
	return (
		_blended_axis(func(p: WeatherRegimeProfile) -> Vector2: return p.temperature_c, 0.5)
		+ _season_temperature_offset_c()
	)

# --- Save / Persistence (ADR-0007: только медленное состояние) ---


## Медленное состояние погоды для сейва. Живые оси (cloud_cover, цели ветра,
## humidity, precipitation и temperature-read) НЕ сохраняются —
## реконструируются из режима + часов.
func export_save_dict() -> Dictionary:
	return {
		"active_regime": String(_active_id),
		"next_regime": String(_next_id),
		"in_transition": _in_transition,
		"transition": _transition,
		"remaining_hours": _remaining_hours,
		"weather_time_hours": _weather_time_hours,
		"transition_count": _transition_count,
	}


## Восстановление медленного состояния из сейва. Неизвестный режим (контент
## изменился) -> безопасный дефолт clear. _last_hour сбрасывается: следующий
## time_tick ресинкает дельту без скачка. weather_changed уведомляет слои.
func restore_persisted_state(data: Dictionary) -> void:
	var active: StringName = StringName(String(data.get("active_regime", String(START_REGIME_ID))))
	var nxt: StringName = StringName(String(data.get("next_regime", String(active))))
	if not _regimes_by_id.has(active):
		active = START_REGIME_ID
	if not _regimes_by_id.has(nxt):
		nxt = active
	_active_id = active
	_next_id = nxt
	_in_transition = bool(data.get("in_transition", false))
	_transition = clampf(float(data.get("transition", 0.0)), 0.0, 1.0)
	# remaining_hours может быть отрицательным транзиентом во время перехода —
	# сохраняем как есть (re-roll только для не-перехода с remaining <= 0 ниже).
	_remaining_hours = float(data.get("remaining_hours", 0.0))
	_weather_time_hours = maxf(float(data.get("weather_time_hours", 0.0)), 0.0)
	_transition_count = maxi(int(data.get("transition_count", 0)), 0)
	_debug_regime_id = &""
	_debug_cover_override = -1.0
	_debug_humidity_override = -1.0
	_debug_fast_transition = false
	_last_hour = -1.0
	if not _in_transition and _remaining_hours <= 0.0:
		_remaining_hours = _roll_duration(_active_id, _transition_count)
	EventBus.weather_changed.emit(_active_id, _active_id)

# --- Приватные ---


func _on_world_initialized(seed_value: int) -> void:
	_world_seed = seed_value


func _on_time_tick(current_hour: float, _day_progress: float) -> void:
	if not _debug_regime_id.is_empty():
		# Dev-форс: эволюция заморожена.
		return
	if _last_hour < 0.0:
		_last_hour = current_hour
		return
	var delta_hours: float = current_hour - _last_hour
	if delta_hours < 0.0:
		delta_hours += float(_hours_per_day())
	_last_hour = current_hour
	if delta_hours <= 0.0:
		return
	_advance(delta_hours)


func _advance(delta_hours: float) -> void:
	_weather_time_hours += delta_hours
	if _in_transition:
		_transition += delta_hours / TRANSITION_WINDOW_HOURS
		if _transition >= 1.0:
			_commit_transition()
	else:
		_remaining_hours -= delta_hours
		if _remaining_hours <= 0.0:
			_begin_transition()


func _begin_transition() -> void:
	_next_id = _select_next_regime(_active_id)
	if _next_id == _active_id:
		# Нет валидного преемника — продлеваем текущий режим.
		_remaining_hours = _roll_duration(_active_id, _transition_count)
		return
	_in_transition = true
	_transition = 0.0


func _commit_transition() -> void:
	var previous_id: StringName = _active_id
	_active_id = _next_id
	_in_transition = false
	_transition = 0.0
	_transition_count += 1
	_remaining_hours = _roll_duration(_active_id, _transition_count)
	EventBus.weather_changed.emit(_active_id, previous_id)


## Детерминированный взвешенный выбор преемника. Сезон только умножает
## authored-вес кандидата; roll/clock/transition остаются погодными.
func _select_next_regime(current_id: StringName) -> StringName:
	var profile: WeatherRegimeProfile = _regimes_by_id.get(current_id) as WeatherRegimeProfile
	if profile == null or profile.successor_weights.is_empty():
		return current_id
	var total: float = 0.0
	for successor_variant: Variant in profile.successor_weights.keys():
		var successor_id: StringName = successor_variant as StringName
		var authored_weight: float = maxf(
			float(profile.successor_weights[successor_variant]),
			0.0,
		)
		total += authored_weight * _season_regime_weight_multiplier(successor_id)
	if total <= 0.0:
		return current_id
	var roll: float = _hash_unit(
		_world_seed,
		_current_day(),
		_transition_count,
		int(_active_id.hash()),
	) * total
	var acc: float = 0.0
	for successor_variant: Variant in profile.successor_weights.keys():
		var successor_id: StringName = successor_variant as StringName
		var authored_weight: float = maxf(
			float(profile.successor_weights[successor_variant]),
			0.0,
		)
		acc += authored_weight * _season_regime_weight_multiplier(successor_id)
		if roll <= acc and _regimes_by_id.has(successor_id):
			return successor_id
	return current_id


func _roll_duration(regime_id: StringName, salt: int) -> float:
	var profile: WeatherRegimeProfile = _regimes_by_id.get(regime_id) as WeatherRegimeProfile
	if profile == null:
		return 8.0
	var unit: float = _hash_unit(_world_seed, _current_day(), salt, int(regime_id.hash()) ^ 0x5bd1)
	return lerpf(profile.min_duration_hours, profile.max_duration_hours, unit)


## Значение оси: полоса активного режима, сэмплированная медленным «дыханием»,
## смешанная с полосой следующего во время перехода. fallback — при пустом
## реестре (нейтральное значение для зарезервированных осей).
func _blended_axis(band_getter: Callable, fallback: float) -> float:
	var active: WeatherRegimeProfile = (
		_regimes_by_id.get(get_active_regime_id()) as WeatherRegimeProfile
	)
	if active == null:
		return fallback
	var value: float = _sample_band(band_getter.call(active) as Vector2)
	if _in_transition and _debug_regime_id.is_empty():
		var nxt: WeatherRegimeProfile = _regimes_by_id.get(_next_id) as WeatherRegimeProfile
		if nxt != null:
			var next_value: float = _sample_band(band_getter.call(nxt) as Vector2)
			value = lerpf(value, next_value, smoothstep(0.0, 1.0, _transition))
	return value


func _sample_band(band: Vector2) -> float:
	# Два несоизмеримых медленных синуса -> апериодичное дыхание внутри полосы.
	var breath: float = sin(_weather_time_hours * 0.9 + 0.4) * 0.6 \
			+ sin(_weather_time_hours * 0.31 + 2.1) * 0.4
	return lerpf(band.x, band.y, clampf(0.5 + 0.5 * breath, 0.0, 1.0))


## Rain-only V1: профиль задаёт способность режима к осадкам, а фактическая
## интенсивность причинно растёт только после порогов влажности и облачности.
func _rain_intensity_for_profile(
		profile: WeatherRegimeProfile,
		humidity: float,
		cloud_cover: float,
) -> float:
	if profile.precipitation_kind != PrecipitationKind.RAIN:
		return 0.0
	var humidity_pressure: float = smoothstep(
		profile.precipitation_start_humidity,
		1.0,
		clampf(humidity, 0.0, 1.0),
	)
	var cloud_pressure: float = smoothstep(
		profile.precipitation_start_cloud_cover,
		1.0,
		clampf(cloud_cover, 0.0, 1.0),
	)
	var rain_capacity: float = lerpf(
		profile.precipitation_intensity.x,
		profile.precipitation_intensity.y,
		humidity_pressure,
	)
	return clampf(rain_capacity * humidity_pressure * cloud_pressure, 0.0, 1.0)


## Сглаженный value-noise по времени погоды в [-1, 1]: медленный апериодичный
## мендр направления. Детерминирован от времени (воспроизводим при reload).
func _heading_meander(t_hours: float) -> float:
	var t: float = t_hours * 0.6
	var i: float = floor(t)
	var f: float = t - i
	var u: float = f * f * (3.0 - 2.0 * f)
	return lerpf(_heading_hash(i), _heading_hash(i + 1.0), u) * 2.0 - 1.0


func _heading_hash(n: float) -> float:
	var s: float = sin(n * 12.9898 + 7.13) * 43758.5453
	return s - floor(s)


func _load_balance() -> void:
	_balance = ResourceLoader.load(BALANCE_PATH) as WeatherBalance
	assert(_balance != null, "WeatherRuntime missing balance resource: %s" % BALANCE_PATH)
	assert(
		_balance != null and _balance.is_valid_balance(),
		"WeatherRuntime balance resource failed validation: %s" % BALANCE_PATH,
	)


func _load_regimes() -> void:
	var directory: DirAccess = DirAccess.open(REGIME_DIRECTORY)
	assert(directory != null, "WeatherRuntime missing regime directory: %s" % REGIME_DIRECTORY)
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if not entry.ends_with(".tres"):
			continue
		var profile: WeatherRegimeProfile = ResourceLoader.load(
			"%s/%s" % [REGIME_DIRECTORY, entry],
		) as WeatherRegimeProfile
		assert(profile != null and profile.is_valid_regime(), "Invalid weather regime: %s" % entry)
		_regimes_by_id[profile.id] = profile
	directory.list_dir_end()
	assert(
		_regimes_by_id.has(START_REGIME_ID),
		"WeatherRuntime requires the %s regime" % START_REGIME_ID,
	)


func _current_day() -> int:
	if TimeManager != null:
		return TimeManager.current_day
	return 1


func _hours_per_day() -> int:
	if TimeManager != null and TimeManager.balance != null:
		return TimeManager.balance.hours_per_day
	return 24


func _season_temperature_offset_c() -> float:
	if TimeManager != null and TimeManager.has_method("get_season_temperature_offset_c"):
		return float(TimeManager.get_season_temperature_offset_c())
	return 0.0


func _season_humidity_offset() -> float:
	if TimeManager != null and TimeManager.has_method("get_season_humidity_offset"):
		return float(TimeManager.get_season_humidity_offset())
	return 0.0


func _season_regime_weight_multiplier(regime_id: StringName) -> float:
	if TimeManager != null and TimeManager.has_method("get_weather_regime_weight_multiplier"):
		return maxf(float(TimeManager.get_weather_regime_weight_multiplier(regime_id)), 0.0)
	return 1.0


static func _hash_unit(a: int, b: int, c: int, d: int) -> float:
	var value: int = a * 73856093 ^ b * 19349663 ^ c * 83492791 ^ d * 2654435761
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xffff) / 65535.0
