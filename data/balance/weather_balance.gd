class_name WeatherBalance
extends Resource
## Глобальные пороги погодной физики мира. Это не тюнинг отдельного режима:
## точка замерзания одна на планету, поэтому ей не место в WeatherRegimeProfile.
## WeatherRuntime читает этот ресурс и остаётся единственным владельцем осей.
## Контракт: docs/02_system_specs/world/snow_precipitation_runtime.md

@export_group("Identity")
@export var id: StringName = &"core:weather"

@export_group("Precipitation kind")
## Температура, на которой и ниже которой осадки публикуются как снег.
## Авторитетно: определяет PrecipitationKind, который читают gameplay-системы.
@export var freeze_temperature_c: float = 0.0
## Полуширина полосы кросс-фейда презентации вокруг порога. ТОЛЬКО визуал:
## на публикуемый kind не влияет, иначе появился бы второй источник истины.
@export_range(0.0, 20.0, 0.5) var precipitation_crossfade_c: float = 2.0


func is_valid_balance() -> bool:
	var id_text: String = String(id)
	if id_text.is_empty() or not id_text.contains(":") or id_text.ends_with(":"):
		return false
	if not is_finite(freeze_temperature_c):
		return false
	if not is_finite(precipitation_crossfade_c) or precipitation_crossfade_c < 0.0:
		return false
	return true
