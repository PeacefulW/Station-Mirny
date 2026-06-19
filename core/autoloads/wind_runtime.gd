class_name WindRuntimeSingleton
extends Node
## Низкоуровневый движок ветра (environment runtime, ADR-0007 layer 3) и
## единственный писатель wind_* global shader uniforms. ЦЕЛЬ ветра (силу,
## направление, порывистость) задаёт WeatherRuntime — ветер стал производной
## погоды; WindRuntime лишь плавно тянется к цели, аккумулирует фазу и пишет
## глобалы. WorldVisualWindProfile задаёт только форму порывов (темп/скролл).
## Состояние не сохраняется (реконструируется). Автолоад паузится с деревом.
## Контракт: docs/02_system_specs/world/weather_runtime.md
##           docs/02_system_specs/world/wind_and_grass_scatter_presentation.md

const WorldVisualWindProfile = preload("res://core/systems/world/world_visual_wind_profile.gd")

const GLOBAL_WIND_TIME: StringName = &"wind_time"
const GLOBAL_WIND_DIRECTION: StringName = &"wind_direction"
const GLOBAL_WIND_STRENGTH: StringName = &"wind_strength"
const GLOBAL_WIND_GUST_SCROLL_PX: StringName = &"wind_gust_scroll_px"

const DEBUG_OVERRIDE_DISABLED: float = -1.0
## Скорость подтягивания к цели погоды: ветер не дёргается при смене режима.
const TARGET_SMOOTH_RATE: float = 0.6
const DEFAULT_HEADING_DEG: float = -13.0

var _wind_time: float = 0.0
## Интеграл direction * scroll_speed: фронты порывов едут плавно даже при
## дрейфе направления (прямое dir * t * speed рвёт фазу при повороте dir).
var _gust_scroll_px: Vector2 = Vector2.ZERO
var _smoothed_strength: float = 0.3
var _smoothed_heading_rad: float = deg_to_rad(DEFAULT_HEADING_DEG)
var _debug_strength_override: float = DEBUG_OVERRIDE_DISABLED
var _debug_direction_override_deg: float = NAN


func _ready() -> void:
	if WeatherRuntime != null:
		_smoothed_strength = WeatherRuntime.get_target_wind_strength()
		_smoothed_heading_rad = deg_to_rad(WeatherRuntime.get_target_wind_heading_deg())
	_publish_globals(_current_direction(), _current_strength())


func _process(delta: float) -> void:
	_track_weather_target(delta)
	var direction: Vector2 = _current_direction()
	var strength: float = _current_strength()
	# Сила ветра ускоряет ход wind_time (темп трепета) и бег фронтов.
	# Оба — аккумулированные величины: смена силы не рвёт фазу анимации.
	_wind_time += delta * WorldVisualWindProfile.anim_rate_for_strength(strength)
	_gust_scroll_px += direction \
			* WorldVisualWindProfile.scroll_speed_px_per_s_for_strength(strength) \
			* delta
	_publish_globals(direction, strength)


## Плавное подтягивание сглаженного ветра к цели, заданной погодой.
func _track_weather_target(delta: float) -> void:
	if WeatherRuntime == null:
		return
	var k: float = clampf(delta * TARGET_SMOOTH_RATE, 0.0, 1.0)
	_smoothed_strength = lerpf(_smoothed_strength, WeatherRuntime.get_target_wind_strength(), k)
	_smoothed_heading_rad = lerp_angle(
		_smoothed_heading_rad,
		deg_to_rad(WeatherRuntime.get_target_wind_heading_deg()),
		k,
	)

# --- Публичные чтения (presentation/dev surface) ---


func get_wind_time() -> float:
	return _wind_time


func get_wind_strength() -> float:
	return _current_strength()


func get_wind_direction() -> Vector2:
	return _current_direction()


func get_wind_direction_deg() -> float:
	return rad_to_deg(_current_direction().angle())


func has_debug_wind_override() -> bool:
	return _debug_strength_override >= 0.0 or not is_nan(_debug_direction_override_deg)

# --- Dev-only управление (пробы и dev-сцены, не gameplay-путь) ---


func set_debug_strength_override(strength: float) -> void:
	_debug_strength_override = clampf(strength, 0.0, 1.0)
	_publish_globals(_current_direction(), _current_strength())


func set_debug_direction_override_deg(direction_deg: float) -> void:
	_debug_direction_override_deg = direction_deg
	_publish_globals(_current_direction(), _current_strength())


func clear_debug_wind_override() -> void:
	_debug_strength_override = DEBUG_OVERRIDE_DISABLED
	_debug_direction_override_deg = NAN
	_publish_globals(_current_direction(), _current_strength())

# --- Приватные ---


func _current_strength() -> float:
	if _debug_strength_override >= 0.0:
		return _debug_strength_override
	return clampf(_smoothed_strength, 0.0, 1.0)


func _current_direction() -> Vector2:
	if not is_nan(_debug_direction_override_deg):
		return Vector2.from_angle(deg_to_rad(_debug_direction_override_deg))
	return Vector2.from_angle(_smoothed_heading_rad)


func _publish_globals(direction: Vector2, strength: float) -> void:
	RenderingServer.global_shader_parameter_set(GLOBAL_WIND_TIME, _wind_time)
	RenderingServer.global_shader_parameter_set(GLOBAL_WIND_DIRECTION, direction)
	RenderingServer.global_shader_parameter_set(GLOBAL_WIND_STRENGTH, strength)
	RenderingServer.global_shader_parameter_set(GLOBAL_WIND_GUST_SCROLL_PX, _gust_scroll_px)
