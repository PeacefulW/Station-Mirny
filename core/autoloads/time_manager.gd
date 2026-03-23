class_name TimeManagerSingleton
extends Node

## Глобальный менеджер времени. Считает игровое время,
## определяет фазу дня (рассвет/день/закат/ночь) и сезон.
## Не знает о других системах — сообщает через EventBus.

# --- Перечисления ---
enum TimeOfDay { DAWN, DAY, DUSK, NIGHT }
enum Season { WARM, SPORE, COLD, STORM }

# --- Константы ---
## Путь к ресурсу баланса. Моды могут подменить файл по этому пути.
const BALANCE_PATH: String = "res://data/balance/time_balance.tres"

# --- Публичные ---
var balance: TimeBalance = null
## Текущий час (0.0 — 24.0, дробная часть = минуты).
var current_hour: float = 7.0
## Текущий игровой день (начинается с 1).
var current_day: int = 1
## Текущий сезон.
var current_season: Season = Season.WARM
## Текущая фаза дня.
var current_time_of_day: TimeOfDay = TimeOfDay.DAY
## Пауза времени.
var is_paused: bool = false
## Множитель скорости времени (1.0 = нормально).
var time_scale: float = 1.0

# --- Приватные ---
## Скорость: сколько игровых часов проходит за 1 реальную секунду.
var _hours_per_real_second: float = 0.0
var _previous_whole_hour: int = -1

func _ready() -> void:
	balance = load(BALANCE_PATH) as TimeBalance
	if not balance:
		push_error(Localization.t("SYSTEM_TIME_BALANCE_LOAD_FAILED", {"path": BALANCE_PATH}))
		return
	_calculate_speed()
	_previous_whole_hour = floori(current_hour)
	current_time_of_day = _get_time_of_day(floori(current_hour))
	_emit_initial_state()

func _process(delta: float) -> void:
	if not balance or is_paused:
		return
	_advance_time(delta)

# --- Публичные методы ---

## Получить текущий час как целое число (0–23).
func get_hour() -> int:
	return floori(current_hour) % balance.hours_per_day

## Получить прогресс текущего дня (0.0 — 1.0).
func get_day_progress() -> float:
	return current_hour / float(balance.hours_per_day)

## Получить нормализованное "положение солнца" (0.0 = полночь, 0.5 = полдень).
func get_sun_progress() -> float:
	return fmod(current_hour / float(balance.hours_per_day) + 0.5, 1.0)

## Угол солнца в радианах.
## Восход слева (запад), полдень сверху (север), закат справа (восток).
## Тени: утром → вправо, днём → вниз (юг), вечером → влево.
func get_sun_angle() -> float:
	var progress: float = get_sun_progress()
	var shadow_angle: float = fmod(progress - 0.75 + 1.0, 1.0) * TAU
	return shadow_angle - PI

## Коэффициент длины тени (1.0 = полдень, 6.0 = рассвет/закат/ночь).
func get_shadow_length_factor() -> float:
	var elevation: float = maxf(cos(get_sun_progress() * TAU), 0.0)
	if elevation < 0.05:
		return 6.0
	return clampf(1.0 / (elevation * 2.0), 1.0, 6.0)

# --- Приватные методы ---

func _calculate_speed() -> void:
	var real_seconds_per_day: float = balance.day_duration_minutes * 60.0
	_hours_per_real_second = float(balance.hours_per_day) / real_seconds_per_day

func _advance_time(delta: float) -> void:
	var advance: float = _hours_per_real_second * delta * time_scale
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
	var season_index: int = ((current_day - 1) / balance.season_length_days) % Season.size()
	var new_season: Season = season_index as Season
	if new_season != current_season:
		var old_season: Season = current_season
		current_season = new_season
		EventBus.season_changed.emit(new_season, old_season)

func _get_time_of_day(hour: int) -> TimeOfDay:
	if not balance:
		return TimeOfDay.DAY
	if hour >= balance.night_hour or hour < balance.dawn_hour:
		return TimeOfDay.NIGHT
	elif hour >= balance.dusk_hour:
		return TimeOfDay.DUSK
	elif hour >= balance.day_hour:
		return TimeOfDay.DAY
	else:
		return TimeOfDay.DAWN

func _emit_initial_state() -> void:
	EventBus.time_of_day_changed.emit(current_time_of_day, current_time_of_day)
	EventBus.hour_changed.emit(get_hour())
	EventBus.day_changed.emit(current_day)
	EventBus.season_changed.emit(current_season, current_season)
