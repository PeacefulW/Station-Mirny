class_name DaylightSystem
extends CanvasModulate
## Система освещения дня и ночи. Подписывается на TimeManager
## и плавно меняет цвет CanvasModulate.
## Днём — полная яркость, ночью — тёмно-синий мрак.

# --- Константы ---
## Цвета фаз дня. Тонирование — presentation response (ADR-0007 layer 4):
## HUD живёт в CanvasLayer и не тонируется; подземный свет — геймплейная
## система (ADR-0005), поэтому underground остаётся нейтральным.
const WeatherPresentationCurves = preload("res://core/systems/world/weather_presentation_curves.gd")
## Эти цвета теперь — AMBIENT-ПОЛ (а не полная заливка): ключ даёт реальный
## DirectionalLight2D (солнце), поэтому день приглушён, ночь по-настоящему тёмная
## (свет=безопасность, тьма=давление, ADR-0005). См.
## docs/02_system_specs/world/world_dynamic_lighting_2d.md.
## День — привычно-светлый (ambient почти как раньше), солнце лишь мягкий ключ.
## Ночь — ПОЧТИ ЧЁРНАЯ: без источника света видимость ~ноль (свет=безопасность,
## тьма=давление, ADR-0005). Светлячки/споры (blend_add) и факел остаются видимы.
const COLOR_NIGHT := Color(0.03, 0.035, 0.05)
const COLOR_DAWN := Color(0.55, 0.48, 0.52)
const COLOR_DAY := Color(0.85, 0.85, 0.83)
const COLOR_DUSK := Color(0.66, 0.50, 0.40)
const COLOR_UNDERGROUND := Color(1.0, 1.0, 1.0)
## Солнце — МЯГКИЙ ключ (рельеф по нормали), не второй фонарь: иначе день
## пересвечивается. Угол — из WorldVisualLightingProfile по времени суток.
const SUN_DAY_ENERGY := 0.45
const SUN_COLOR_DAY := Color(1.0, 0.92, 0.74)
const SUN_COLOR_LOW := Color(1.0, 0.72, 0.46)
## Нормировка яркости ambient -> сила солнца (средние новых COLOR_*).
const AMBIENT_NIGHT_AVG := 0.038
const AMBIENT_DAY_AVG := 0.843
## Множитель пасмурности при cloud_cover = 1: холоднее (тёплый R гасится
## сильнее B) и темнее. Это outside-ambient тон-сдвиг (sanctuary-контракт):
## применяется только на поверхности; underground и свет источников не трогает.
const COLOR_OVERCAST_TINT := Color(0.66, 0.72, 0.84)

# --- Приватные ---
var _target_color: Color = COLOR_DAY
## Скорость перехода между цветами (за секунду).
var _transition_speed: float = 1.0
var _current_z: int = 0
## Реальное солнце-ключ (Iteration 1). Тени-окклюдеры — Iteration 2.
var _sun: DirectionalLight2D = null


func _ready() -> void:
	_sun = DirectionalLight2D.new()
	_sun.name = "SunLight2D"
	_sun.energy = SUN_DAY_ENERGY
	_sun.color = SUN_COLOR_DAY
	_sun.rotation = deg_to_rad(WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG)
	_sun.shadow_enabled = false
	add_child(_sun)
	EventBus.time_of_day_changed.connect(_on_time_of_day_changed)
	EventBus.time_tick.connect(_on_time_tick)
	EventBus.z_level_changed.connect(_on_z_level_changed)
	_current_z = _resolve_current_z()
	_sync_from_current_context(true)


func _process(delta: float) -> void:
	# Плавный переход к целевому цвету. Погодный тон-сдвиг подмешивается
	# только на поверхности (outside-ambient): underground остаётся
	# нейтральным, как и днём/ночью (sanctuary-контракт, ADR-0005).
	var effective_target: Color = _target_color
	if _is_surface_context():
		effective_target *= _weather_tint()
	color = color.lerp(effective_target, _transition_speed * delta)
	_update_sun(delta)


## Солнце ведётся от текущей ambient-яркости (плавно вместе с CanvasModulate):
## энергия = доля дня, угол = время суток. Под землёй солнце выключено
## (подземный свет — отдельная геймплейная система, ADR-0005).
func _update_sun(delta: float) -> void:
	if _sun == null:
		return
	var surface: bool = _is_surface_context()
	_sun.enabled = surface
	if not surface:
		return
	var ambient_avg: float = (color.r + color.g + color.b) / 3.0
	var strength: float = clampf(
		(ambient_avg - AMBIENT_NIGHT_AVG) / maxf(AMBIENT_DAY_AVG - AMBIENT_NIGHT_AVG, 0.001),
		0.0, 1.0,
	)
	var weight: float = clampf(_transition_speed * delta, 0.0, 1.0)
	_sun.energy = lerpf(_sun.energy, SUN_DAY_ENERGY * strength, weight)
	_sun.color = SUN_COLOR_LOW.lerp(SUN_COLOR_DAY, strength)
	if TimeManager:
		_sun.rotation = deg_to_rad(WorldVisualLightingProfile.light_angle_deg_for_hour(TimeManager.current_hour))


## Множитель пасмурности по облачности WeatherRuntime (white при ясной).
func _weather_tint() -> Color:
	if WeatherRuntime == null:
		return Color.WHITE
	var cloud_cover: float = clampf(WeatherRuntime.get_cloud_cover(), 0.0, 1.0)
	return Color.WHITE.lerp(COLOR_OVERCAST_TINT, WeatherPresentationCurves.deck_strength(cloud_cover))

# --- Приватные методы ---


func _on_time_of_day_changed(new_phase: int, _old_phase: int) -> void:
	if not _is_surface_context():
		return
	match new_phase:
		TimeManagerSingleton.TimeOfDay.DAWN:
			_target_color = COLOR_DAWN
		TimeManagerSingleton.TimeOfDay.DAY:
			_target_color = COLOR_DAY
		TimeManagerSingleton.TimeOfDay.DUSK:
			_target_color = COLOR_DUSK
		TimeManagerSingleton.TimeOfDay.NIGHT:
			_target_color = COLOR_NIGHT


func _on_time_tick(current_hour: float, _day_progress: float) -> void:
	if not _is_surface_context():
		return
	if not TimeManager or not TimeManager.balance:
		return
	_target_color = _resolve_surface_color_for_hour(current_hour)


func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	set_active_z_level(new_z)


func set_active_z_level(new_z: int) -> void:
	if new_z == _current_z:
		return
	_current_z = new_z
	_sync_from_current_context(true)


func _sync_from_current_context(force_immediate: bool) -> void:
	_target_color = _resolve_context_color()
	if force_immediate:
		color = _target_color


func _resolve_context_color() -> Color:
	if not _is_surface_context():
		return COLOR_UNDERGROUND
	if not TimeManager or not TimeManager.balance:
		return COLOR_DAY
	return _resolve_surface_color_for_hour(TimeManager.current_hour)


func _resolve_surface_color_for_hour(current_hour: float) -> Color:
	var balance: TimeBalance = TimeManager.balance
	if not balance:
		return COLOR_DAY
	if current_hour >= float(balance.dawn_hour) and current_hour < float(balance.day_hour):
		var dawn_progress: float = (current_hour - float(balance.dawn_hour)) / float(balance.day_hour - balance.dawn_hour)
		return _blend_phase_color(COLOR_NIGHT, COLOR_DAWN, COLOR_DAY, dawn_progress)
	if current_hour >= float(balance.dusk_hour) and current_hour < float(balance.night_hour):
		var dusk_progress: float = (current_hour - float(balance.dusk_hour)) / float(balance.night_hour - balance.dusk_hour)
		return _blend_phase_color(COLOR_DAY, COLOR_DUSK, COLOR_NIGHT, dusk_progress)
	if current_hour >= float(balance.night_hour) or current_hour < float(balance.dawn_hour):
		return COLOR_NIGHT
	return COLOR_DAY


## Переходная фаза проходит через свой пиковый цвет (янтарь заката, розовый
## рассвета), а не лерпит день<->ночь напрямую мимо него.
func _blend_phase_color(from_color: Color, peak_color: Color, to_color: Color, progress: float) -> Color:
	if progress < 0.5:
		return from_color.lerp(peak_color, progress * 2.0)
	return peak_color.lerp(to_color, (progress - 0.5) * 2.0)


func _is_surface_context() -> bool:
	return _current_z == 0


func _resolve_current_z() -> int:
	var z_managers: Array[Node] = get_tree().get_nodes_in_group("z_level_manager")
	if z_managers.is_empty():
		return 0
	var z_manager: Node = z_managers[0]
	if z_manager.has_method("get_current_z"):
		return int(z_manager.get_current_z())
	return 0
