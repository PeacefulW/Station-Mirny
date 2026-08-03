class_name WeatherRegimeProfile
extends Resource
## Авторский профиль одного погодного режима (environment runtime, ADR-0007).
## Режимы — данные: новый режим = новый ресурс + веса переходов, без кода
## в WeatherRuntime. Полосы (Vector2 = min/max) задают диапазон оси; владелец
## сэмплирует внутри полосы медленным шумом («дыхание» погоды).
## Контракты: docs/02_system_specs/world/weather_runtime.md и
## docs/02_system_specs/world/humidity_and_rain_runtime.md

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: StringName = &""

@export_group("Live axes")
## Облачность: 0 ясно .. 1 пасмурно.
@export var cloud_cover: Vector2 = Vector2(0.0, 0.2)
## Сила ветра 0..1, уходит в WindRuntime как цель.
@export var wind_strength: Vector2 = Vector2(0.2, 0.5)
@export var wind_gustiness: Vector2 = Vector2(0.2, 0.5)
## Амплитуда дрейфа направления ветра (град): погода решает поведение
## направления (буря мечется, ясно держит ровно).
@export var heading_drift_deg: float = 10.0

## В V1 активны NONE/RAIN; остальные значения зарезервированы для будущего
## temperature/season resolver и пока не проходят runtime-валидацию профиля.
@export_enum("None", "Rain", "Snow", "Ash", "Spore") var precipitation_kind: int = 0
@export var precipitation_intensity: Vector2 = Vector2.ZERO
@export var humidity: Vector2 = Vector2(0.5, 0.5)
@export_range(0.0, 1.0, 0.01) var precipitation_start_humidity: float = 1.0
@export_range(0.0, 1.0, 0.01) var precipitation_start_cloud_cover: float = 1.0

@export_group("Reserved temperature axis (no consumers)")
@export var temperature_c: Vector2 = Vector2(12.0, 12.0)

@export_group("Transitions")
## regime_id -> вес перехода. В V0 только соседние режимы.
@export var successor_weights: Dictionary = { }
@export var min_duration_hours: float = 6.0
@export var max_duration_hours: float = 12.0


func is_valid_regime() -> bool:
	if str(id).is_empty() or successor_weights.is_empty():
		return false
	if min_duration_hours <= 0.0 or max_duration_hours < min_duration_hours:
		return false
	if not _is_normalized_band(cloud_cover) \
			or not _is_normalized_band(wind_strength) \
			or not _is_normalized_band(wind_gustiness) \
			or not _is_normalized_band(humidity) \
			or not _is_normalized_band(precipitation_intensity):
		return false
	if temperature_c.x > temperature_c.y:
		return false
	if precipitation_kind == 0:
		return is_zero_approx(precipitation_intensity.x) \
				and is_zero_approx(precipitation_intensity.y)
	if precipitation_kind != 1:
		return false
	return precipitation_intensity.y > 0.0 \
			and precipitation_start_humidity >= 0.0 \
			and precipitation_start_humidity < 1.0 \
			and precipitation_start_cloud_cover >= 0.0 \
			and precipitation_start_cloud_cover < 1.0


static func _is_normalized_band(band: Vector2) -> bool:
	return band.x >= 0.0 and band.y <= 1.0 and band.x <= band.y
