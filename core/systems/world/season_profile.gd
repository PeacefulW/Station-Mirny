class_name SeasonProfile
extends Resource
## Авторский профиль одной глобальной сезонной фазы (ADR-0007, slow world
## state). TimeManager читает эти ресурсы и остаётся единственным владельцем
## текущей фазы; сам профиль не содержит mutable runtime-состояния.

@export_group("Identity")
@export var id: StringName = &""
@export_range(0, 3, 1) var season_kind: int = 0

@export_group("Environment offsets")
@export var temperature_offset_c: float = 0.0
@export var humidity_offset: float = 0.0

@export_group("Weather regime weights")
## regime_id -> неотрицательный множитель. Отсутствующий id нейтрален (1.0),
## чтобы новый погодный режим не требовал правки каждого сезонного профиля.
@export var weather_regime_weight_multipliers: Dictionary = { }


func is_valid_profile(expected_season_count: int = 4) -> bool:
	var id_text: String = String(id)
	if id_text.is_empty() or not id_text.contains(":") or id_text.ends_with(":"):
		return false
	if season_kind < 0 or season_kind >= expected_season_count:
		return false
	if not is_finite(temperature_offset_c) or not is_finite(humidity_offset):
		return false
	for regime_id_variant: Variant in weather_regime_weight_multipliers:
		var regime_id: String = String(regime_id_variant)
		var multiplier_variant: Variant = weather_regime_weight_multipliers[regime_id_variant]
		if regime_id.is_empty() or not regime_id.contains(":"):
			return false
		if typeof(multiplier_variant) != TYPE_FLOAT and typeof(multiplier_variant) != TYPE_INT:
			return false
		var multiplier: float = float(multiplier_variant)
		if not is_finite(multiplier) or multiplier < 0.0:
			return false
	return true


func get_weather_regime_weight_multiplier(regime_id: StringName) -> float:
	return float(weather_regime_weight_multipliers.get(regime_id, 1.0))
