class_name TimeManagerSingleton
extends Node

const WorldVisualLightingProfile = preload(
	"res://core/systems/world/world_visual_lighting_profile.gd"
)
const SeasonProfile = preload("res://core/systems/world/season_profile.gd")

## Глобальный менеджер времени. Считает игровое время,
## определяет фазу дня (рассвет/день/закат/ночь) и сезон.
## Не знает о других системах — сообщает через EventBus.

# --- Перечисления ---
enum TimeOfDay { DAWN, DAY, DUSK, NIGHT }
enum Season { WARM, SPORE, COLD, STORM }

# --- Константы ---
## Путь к ресурсу баланса. Моды могут подменить файл по этому пути.
const BALANCE_PATH: String = "res://data/balance/time_balance.tres"
const DEFAULT_START_HOUR: float = 7.0
const DEFAULT_START_DAY: int = 1
const DEFAULT_START_SEASON: Season = Season.WARM
const CORE_SEASON_IDS: Array[StringName] = [
	&"core:warm",
	&"core:spore",
	&"core:cold",
	&"core:storm",
]

# --- Публичные ---
var balance: TimeBalance = null
## Текущий час (0.0 — 24.0, дробная часть = минуты).
var current_hour: float = DEFAULT_START_HOUR
## Текущий игровой день (начинается с 1).
var current_day: int = DEFAULT_START_DAY
## Текущий сезон.
var current_season: Season = DEFAULT_START_SEASON
## Текущая фаза дня.
var current_time_of_day: TimeOfDay = TimeOfDay.DAY

# --- Приватные ---
## Скорость: сколько игровых часов проходит за 1 реальную секунду.
var _hours_per_real_second: float = 0.0
var _previous_whole_hour: int = -1
var _is_paused: bool = false
var _time_scale: float = 1.0
var _season_profiles_by_kind: Dictionary = { }
## Dev-only forcing для probes/visual inspection. Не сохраняется и не меняет
## авторитетный current_season; -1 означает natural state.
var _debug_season: int = -1


func _ready() -> void:
	balance = load(BALANCE_PATH) as TimeBalance
	assert(balance != null, "TimeManager missing balance resource: %s" % BALANCE_PATH)
	if balance == null:
		return
	assert(balance.season_length_days > 0, "TimeManager season_length_days must be positive")
	_load_season_profiles()
	_calculate_speed()
	_apply_authoritative_time_state(current_hour, current_day, current_season)


func _process(delta: float) -> void:
	if not balance or _is_paused:
		return
	_advance_time(delta)


## Dev-only visual inspection path. TimeManager handles its own season-cycle
## shortcut so player gameplay input and HUD remain free of season mutation.
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_J:
		return
	debug_cycle_season()
	get_viewport().set_input_as_handled()

# --- Публичные методы ---


## Получить текущий час как целое число (0–23).
func get_hour() -> int:
	return floori(current_hour) % balance.hours_per_day


## Получить прогресс текущего дня (0.0 — 1.0).
func get_day_progress() -> float:
	return current_hour / float(balance.hours_per_day)


## Эффективная сезонная фаза. Dev override не меняет authoritative
## current_season и никогда не попадает в save payload.
func get_effective_season() -> int:
	if _debug_season >= 0:
		return _debug_season
	return int(current_season)


## Нормализованный прогресс текущей сезонной фазы (pull-model, 0.0..1.0).
func get_season_progress() -> float:
	if balance == null or balance.season_length_days <= 0:
		return 0.0
	if _debug_season >= 0:
		return 0.0
	var day_in_phase: int = (current_day - 1) % balance.season_length_days
	return clampf(
		(float(day_in_phase) + get_day_progress()) / float(balance.season_length_days),
		0.0,
		1.0,
	)


func get_season_temperature_offset_c() -> float:
	var active: SeasonProfile = _get_season_profile(get_effective_season())
	var next: SeasonProfile = _get_next_season_profile()
	return lerpf(
		active.temperature_offset_c,
		next.temperature_offset_c,
		_get_season_blend(),
	)


func get_season_humidity_offset() -> float:
	var active: SeasonProfile = _get_season_profile(get_effective_season())
	var next: SeasonProfile = _get_next_season_profile()
	return lerpf(active.humidity_offset, next.humidity_offset, _get_season_blend())


func get_weather_regime_weight_multiplier(regime_id: StringName) -> float:
	var active: SeasonProfile = _get_season_profile(get_effective_season())
	var next: SeasonProfile = _get_next_season_profile()
	return lerpf(
		active.get_weather_regime_weight_multiplier(regime_id),
		next.get_weather_regime_weight_multiplier(regime_id),
		_get_season_blend(),
	)

# --- Dev-only управление (probes/visual inspection, не gameplay-путь) ---


func set_debug_season(season: int) -> void:
	assert(season >= 0 and season < Season.size(), "Unknown season kind: %d" % season)
	_debug_season = season


func clear_debug_season() -> void:
	_debug_season = -1


func debug_cycle_season() -> void:
	_debug_season = (get_effective_season() + 1) % Season.size()


## Нормализованная фаза высоты солнца (азимут при этом не меняется).
func get_sun_progress() -> float:
	return fmod(current_hour / float(balance.hours_per_day) + 0.5, 1.0)


## Художественный угол солнца в радианах.
## Азимут всегда зафиксирован на северо-западе; время суток меняет высоту
## (длину/видимость тени), но не вращает тени вокруг объектов.
func get_sun_angle() -> float:
	return deg_to_rad(WorldVisualLightingProfile.FIXED_LIGHT_ANGLE_DEG)


## Коэффициент длины тени (1.0 = полдень, 6.0 = рассвет/закат/ночь).
func get_shadow_length_factor() -> float:
	var elevation: float = maxf(cos(get_sun_progress() * TAU), 0.0)
	if elevation < 0.05:
		return 6.0
	return clampf(1.0 / (elevation * 2.0), 1.0, 6.0)


func reset_for_new_game() -> void:
	set_paused(false)
	set_time_scale(1.0)
	clear_debug_season()
	_apply_authoritative_time_state(DEFAULT_START_HOUR, DEFAULT_START_DAY, DEFAULT_START_SEASON)


func restore_persisted_state(hour: float, day: int, season: int) -> void:
	set_paused(false)
	clear_debug_season()
	_apply_authoritative_time_state(hour, day, season)


func set_paused(paused: bool) -> void:
	_is_paused = paused


func is_time_paused() -> bool:
	return _is_paused


func set_time_scale(scale: float) -> void:
	_time_scale = maxf(scale, 0.0)


func get_time_scale() -> float:
	return _time_scale

# --- Приватные методы ---


func _calculate_speed() -> void:
	var real_seconds_per_day: float = balance.day_duration_minutes * 60.0
	_hours_per_real_second = float(balance.hours_per_day) / real_seconds_per_day


func _load_season_profiles() -> void:
	_season_profiles_by_kind.clear()
	var ids_seen: Dictionary = { }
	assert(
		balance.season_profiles.size() == Season.size(),
		"TimeManager requires exactly %d season profiles" % Season.size(),
	)
	for profile: SeasonProfile in balance.season_profiles:
		assert(
			profile != null and profile.is_valid_profile(Season.size()),
			"Invalid season profile",
		)
		assert(not ids_seen.has(profile.id), "Duplicate season profile id: %s" % profile.id)
		assert(
			not _season_profiles_by_kind.has(profile.season_kind),
			"Duplicate season kind: %d" % profile.season_kind,
		)
		assert(
			profile.id == CORE_SEASON_IDS[profile.season_kind],
			"Season kind %d requires stable id %s" % [
				profile.season_kind,
				CORE_SEASON_IDS[profile.season_kind],
			],
		)
		ids_seen[profile.id] = true
		_season_profiles_by_kind[profile.season_kind] = profile
	assert(
		_season_profiles_by_kind.size() == Season.size(),
		"TimeManager season profile set is incomplete",
	)


func _get_season_profile(season: int) -> SeasonProfile:
	assert(_season_profiles_by_kind.has(season), "Missing season profile kind: %d" % season)
	return _season_profiles_by_kind.get(season) as SeasonProfile


func _get_next_season_profile() -> SeasonProfile:
	var next_season: int = (get_effective_season() + 1) % Season.size()
	return _get_season_profile(next_season)


func _get_season_blend() -> float:
	return smoothstep(0.0, 1.0, get_season_progress())


func _apply_authoritative_time_state(hour: float, day: int, season: int) -> void:
	if not balance:
		return
	current_hour = fposmod(hour, float(balance.hours_per_day))
	current_day = maxi(day, 1)
	current_season = clampi(season, 0, Season.size() - 1) as Season
	_previous_whole_hour = floori(current_hour)
	current_time_of_day = _get_time_of_day(get_hour())
	_emit_initial_state()


func _advance_time(delta: float) -> void:
	var advance: float = _hours_per_real_second * delta * _time_scale
	current_hour += advance

	# Проверяем переход через целый час
	var new_whole_hour: int = floori(current_hour)
	if new_whole_hour != _previous_whole_hour:
		_on_hour_changed(new_whole_hour)
		_previous_whole_hour = new_whole_hour

	# Переход на новый день
	if current_hour >= float(balance.hours_per_day):
		current_hour -= float(balance.hours_per_day)
		_previous_whole_hour = floori(current_hour)
		_on_new_day()

	# Постоянный тик для плавных систем (освещение и т.д.)
	EventBus.time_tick.emit(current_hour, get_day_progress())


func _on_hour_changed(hour: int) -> void:
	var clamped_hour: int = hour % balance.hours_per_day
	EventBus.hour_changed.emit(clamped_hour)

	# Проверяем смену фазы дня
	var new_phase: TimeOfDay = _get_time_of_day(clamped_hour)
	if new_phase != current_time_of_day:
		var old_phase: TimeOfDay = current_time_of_day
		current_time_of_day = new_phase
		EventBus.time_of_day_changed.emit(new_phase, old_phase)


func _on_new_day() -> void:
	current_day += 1
	EventBus.day_changed.emit(current_day)

	# Проверяем смену сезона
	if (current_day - 1) % balance.season_length_days == 0:
		var old_season: Season = current_season
		current_season = ((int(current_season) + 1) % Season.size()) as Season
		EventBus.season_changed.emit(current_season, old_season)


func _get_time_of_day(hour: int) -> TimeOfDay:
	if not balance:
		return TimeOfDay.DAY
	if hour >= balance.night_hour or hour < balance.dawn_hour:
		return TimeOfDay.NIGHT
	if hour >= balance.dusk_hour:
		return TimeOfDay.DUSK
	if hour >= balance.day_hour:
		return TimeOfDay.DAY
	return TimeOfDay.DAWN


func _emit_initial_state() -> void:
	EventBus.time_of_day_changed.emit(current_time_of_day, current_time_of_day)
	EventBus.hour_changed.emit(get_hour())
	EventBus.day_changed.emit(current_day)
	var effective_season: int = get_effective_season()
	EventBus.season_changed.emit(effective_season, effective_season)
	EventBus.time_tick.emit(current_hour, get_day_progress())
