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
## Прогресс, который читается при dev-форсировании фазы. Сезонная кривая
## опирается на центр фазы, поэтому точный авторский профиль лежит на 0.5,
## а не на 0.0 (0.0 — это стык с предыдущей фазой).
const DEBUG_SEASON_PROGRESS_ANCHOR: float = 0.5
## Dev-лестница ускорения времени. Не сохраняется и не влияет на результат:
## масштабирование часов неотличимо от более долгой игры.
const DEBUG_TIME_SCALE_LADDER: Array[float] = [1.0, 10.0, 60.0, 300.0]

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
	match key_event.keycode:
		KEY_J:
			debug_cycle_season()
		KEY_L:
			debug_cycle_time_scale()
		_:
			return
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
		return DEBUG_SEASON_PROGRESS_ANCHOR
	var day_in_phase: int = (current_day - 1) % balance.season_length_days
	return clampf(
		(float(day_in_phase) + get_day_progress()) / float(balance.season_length_days),
		0.0,
		1.0,
	)


## Ключ локализации имени текущей эффективной фазы. HUD резолвит текст из
## ключа; готовых строк в данных и коде нет.
func get_season_display_name_key() -> StringName:
	return _get_season_profile(get_effective_season()).display_name_key


## Номер дня внутри текущей фазы, 1..season_length_days. Выводится из
## авторитетного дня — отдельного счётчика не заводится.
func get_day_in_season() -> int:
	if balance == null or balance.season_length_days <= 0:
		return 1
	return (current_day - 1) % balance.season_length_days + 1


func get_season_length_days() -> int:
	if balance == null:
		return 0
	return balance.season_length_days


func get_season_temperature_offset_c() -> float:
	return _sample_season_curve(
		func(profile: SeasonProfile) -> float: return profile.temperature_offset_c,
	)


func get_season_humidity_offset() -> float:
	return _sample_season_curve(
		func(profile: SeasonProfile) -> float: return profile.humidity_offset,
	)


func get_weather_regime_weight_multiplier(regime_id: StringName) -> float:
	# Catmull-Rom может слегка выйти за пределы опорных значений между кадрами.
	# Для температуры и влажности это допустимо (влажность зажимается ниже по
	# потоку), а вот отрицательный вес сломал бы отбор погодного режима, поэтому
	# контракт «вес неотрицателен» удерживается здесь.
	return maxf(
		_sample_season_curve(
			func(profile: SeasonProfile) -> float:
				return profile.get_weather_regime_weight_multiplier(regime_id),
		),
		0.0,
	)

# --- Dev-only управление (probes/visual inspection, не gameplay-путь) ---


func set_debug_season(season: int) -> void:
	assert(season >= 0 and season < Season.size(), "Unknown season kind: %d" % season)
	_debug_season = season


func clear_debug_season() -> void:
	_debug_season = -1


## Форсирование фазы теперь замкнуто в круг через естественный ход:
## natural -> следующая фаза -> ... -> последняя -> natural. Без выхода
## форсирование залипало навсегда: счётчик дней продолжал идти по
## авторитетному дню, а имя фазы стояло на замороженном значении, из-за чего
## сезон выглядел как «никогда не меняется».
func debug_cycle_season() -> void:
	var next_season: int = get_effective_season() + 1
	if _debug_season >= 0 and next_season >= Season.size():
		clear_debug_season()
		return
	_debug_season = next_season % Season.size()


## Активно ли dev-форсирование фазы. Нужно, чтобы HUD мог честно показать, что
## показанный сезон не совпадает с естественным ходом времени.
func is_debug_season_forced() -> bool:
	return _debug_season >= 0


## Следующая ступень dev-ускорения времени. Ускорение не меняет ни один
## авторитетный результат: сезоны, выбор погодного режима и содержимое сейва
## зависят от мирового времени, а не от того, как быстро оно шло.
func debug_cycle_time_scale() -> void:
	var index: int = DEBUG_TIME_SCALE_LADDER.find(_time_scale)
	set_time_scale(DEBUG_TIME_SCALE_LADDER[(index + 1) % DEBUG_TIME_SCALE_LADDER.size()])


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
	# Ускорение — dev-состояние и не сохраняется, поэтому загруженный сейв
	# никогда не должен стартовать разогнанным.
	set_time_scale(1.0)
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


func _get_adjacent_season_profile(offset: int) -> SeasonProfile:
	return _get_season_profile(posmod(get_effective_season() + offset, Season.size()))


## Сезонная кривая с опорой на центр фазы: авторское значение профиля читается
## ровно в середине своей фазы. Интерполяция — периодический Catmull-Rom по
## четырём ключевым кадрам года.
##
## Почему не smoothstep между соседями: у него нулевая производная в самих
## ключевых кадрах и максимальная на стыке фаз, то есть год «стоит» в центре
## каждой фазы и рывком проскакивает между ними. Catmull-Rom берёт касательную
## в каждом кадре как (следующий - предыдущий)/2, поэтому изменение
## размазывается по всей фазе и год читается как непрерывный цикл.
##
## Свойства: значение и производная непрерывны на стыке (обе стороны шва —
## один и тот же сегмент), RNG нет, стоимость O(1) — четыре чтения профиля и
## один полином. Кривая общая для temperature/humidity/regime, поэтому три
## публичных чтения не могут разъехаться по форме.
func _sample_season_curve(extract: Callable) -> float:
	var progress: float = get_season_progress()
	# progress < 0.5 — сегмент «предыдущая -> текущая», иначе «текущая -> следующая».
	var segment_start: int = -1 if progress < 0.5 else 0
	var t: float = progress + 0.5 if progress < 0.5 else progress - 0.5
	return _catmull_rom(
		float(extract.call(_get_adjacent_season_profile(segment_start - 1))),
		float(extract.call(_get_adjacent_season_profile(segment_start))),
		float(extract.call(_get_adjacent_season_profile(segment_start + 1))),
		float(extract.call(_get_adjacent_season_profile(segment_start + 2))),
		t,
	)


## Равномерный Catmull-Rom: при t=0 возвращает p1, при t=1 возвращает p2,
## поэтому авторские значения профилей достигаются точно.
static func _catmull_rom(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


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
