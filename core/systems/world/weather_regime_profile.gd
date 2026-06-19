class_name WeatherRegimeProfile
extends Resource
## Авторский профиль одного погодного режима (environment runtime, ADR-0007).
## Режимы — данные: новый режим = новый ресурс + веса переходов, без кода
## в WeatherRuntime. Полосы (Vector2 = min/max) задают диапазон оси; владелец
## сэмплирует внутри полосы медленным шумом («дыхание» погоды).
## Контракт: docs/02_system_specs/world/weather_runtime.md

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: StringName = &""

@export_group("Live axes (V0)")
## Облачность: 0 ясно .. 1 пасмурно.
@export var cloud_cover: Vector2 = Vector2(0.0, 0.2)
## Сила ветра 0..1, уходит в WindRuntime как цель.
@export var wind_strength: Vector2 = Vector2(0.2, 0.5)
@export var wind_gustiness: Vector2 = Vector2(0.2, 0.5)
## Амплитуда дрейфа направления ветра (град): погода решает поведение
## направления (буря мечется, ясно держит ровно).
@export var heading_drift_deg: float = 10.0

@export_group("Reserved axes (V0 neutral, no consumers)")
@export var precipitation_kind: int = 0
@export var precipitation_intensity: Vector2 = Vector2.ZERO
@export var temperature_c: Vector2 = Vector2(12.0, 12.0)
@export var humidity: Vector2 = Vector2(0.5, 0.5)

@export_group("Transitions")
## regime_id -> вес перехода. В V0 только соседние режимы.
@export var successor_weights: Dictionary = { }
@export var min_duration_hours: float = 6.0
@export var max_duration_hours: float = 12.0


func is_valid_regime() -> bool:
	return not str(id).is_empty() and not successor_weights.is_empty() \
			and min_duration_hours > 0.0 and max_duration_hours >= min_duration_hours
