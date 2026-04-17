class_name BiomeData
extends Resource

const _EPSILON: float = 0.00001

@export_group("Identity")
@export var id: StringName = &""
@export var display_name_key: String = ""
@export var display_name: String = ""
@export var tags: Array[StringName] = []
@export var priority: int = 0

@export_group("Resolver Ranges")
@export_range(0.0, 1.0, 0.001) var min_height: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_height: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_temperature: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_temperature: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_moisture: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_moisture: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_ruggedness: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_ruggedness: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_flora_density: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_flora_density: float = 1.0
@export_range(-1.0, 1.0, 0.001) var min_latitude: float = -1.0
@export_range(-1.0, 1.0, 0.001) var max_latitude: float = 1.0

@export_group("Causal Channel Ranges")
@export_range(0.0, 1.0, 0.001) var min_drainage: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_drainage: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_slope: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_slope: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_rain_shadow: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_rain_shadow: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_continentalness: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_continentalness: float = 1.0

@export_group("Structure Ranges")
@export_range(0.0, 1.0, 0.001) var min_ridge_strength: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_ridge_strength: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_river_strength: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_river_strength: float = 1.0
@export_range(0.0, 1.0, 0.001) var min_floodplain_strength: float = 0.0
@export_range(0.0, 1.0, 0.001) var max_floodplain_strength: float = 1.0

@export_group("Resolver Weights")
@export_range(0.0, 4.0, 0.01) var height_weight: float = 1.0
@export_range(0.0, 4.0, 0.01) var temperature_weight: float = 1.0
@export_range(0.0, 4.0, 0.01) var moisture_weight: float = 1.0
@export_range(0.0, 4.0, 0.01) var ruggedness_weight: float = 1.0
@export_range(0.0, 4.0, 0.01) var flora_density_weight: float = 0.6
@export_range(0.0, 4.0, 0.01) var latitude_weight: float = 0.6

@export_group("Causal Channel Weights")
@export_range(0.0, 4.0, 0.01) var drainage_weight: float = 0.0
@export_range(0.0, 4.0, 0.01) var slope_weight: float = 0.0
@export_range(0.0, 4.0, 0.01) var rain_shadow_weight: float = 0.0
@export_range(0.0, 4.0, 0.01) var continentalness_weight: float = 0.0

@export_group("Structure Weights")
@export_range(0.0, 4.0, 0.01) var ridge_strength_weight: float = 1.0
@export_range(0.0, 4.0, 0.01) var river_strength_weight: float = 1.0
@export_range(0.0, 4.0, 0.01) var floodplain_strength_weight: float = 1.0

@export_group("Sets")
@export var flora_set_ids: Array[StringName] = []
@export var decor_set_ids: Array[StringName] = []

@export_group("Placeholder Colors")
@export var ground_color: Color = Color(0.22, 0.18, 0.12)
@export var water_color: Color = Color(0.10, 0.15, 0.28)
@export var sand_color: Color = Color(0.45, 0.38, 0.25)
@export var grass_color: Color = Color(0.35, 0.28, 0.10)

@export_group("Gameplay Surface")
@export var base_temperature: float = -5.0
@export var spore_density_multiplier: float = 1.0
@export var enemy_frequency_multiplier: float = 1.0
@export var resource_density_multiplier: float = 1.0

@export_group("Flora")
@export var tree_types: Array[StringName] = [&"dead_tree"]
@export_range(0.0, 1.0, 0.01) var grass_coverage: float = 0.6

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)

func matches_channels(channels: Variant, structure_context: Variant = null) -> bool:
	return _is_in_range(_get_channel_value(channels, "height"), min_height, max_height) \
		and _is_in_range(_get_channel_value(channels, "temperature"), min_temperature, max_temperature) \
		and _is_in_range(_get_channel_value(channels, "moisture"), min_moisture, max_moisture) \
		and _is_in_range(_get_channel_value(channels, "ruggedness"), min_ruggedness, max_ruggedness) \
		and _is_in_range(_get_channel_value(channels, "flora_density"), min_flora_density, max_flora_density) \
		and _is_in_range(_get_channel_value(channels, "latitude"), min_latitude, max_latitude) \
		and _matches_structure_context(structure_context)

func compute_match_score(channels: Variant, structure_context: Variant = null) -> float:
	if not matches_channels(channels, structure_context):
		return -1.0
	return _compute_weighted_score(channels, false, structure_context)

func compute_fallback_score(channels: Variant, structure_context: Variant = null) -> float:
	return _compute_weighted_score(channels, true, structure_context)

func get_channel_scores(channels: Variant, soft: bool = false) -> Dictionary:
	return {
		"height": _score_range(_get_channel_value(channels, "height"), min_height, max_height, soft),
		"temperature": _score_range(_get_channel_value(channels, "temperature"), min_temperature, max_temperature, soft),
		"moisture": _score_range(_get_channel_value(channels, "moisture"), min_moisture, max_moisture, soft),
		"ruggedness": _score_range(_get_channel_value(channels, "ruggedness"), min_ruggedness, max_ruggedness, soft),
		"flora_density": _score_range(_get_channel_value(channels, "flora_density"), min_flora_density, max_flora_density, soft),
		"latitude": _score_range(_get_channel_value(channels, "latitude"), min_latitude, max_latitude, soft),
	}

func get_structure_scores(structure_context: Variant, soft: bool = false) -> Dictionary:
	if structure_context == null:
		return {}
	return {
		"ridge_strength": _score_range(_get_structure_value(structure_context, "ridge_strength"), min_ridge_strength, max_ridge_strength, soft),
		"river_strength": _score_range(_get_structure_value(structure_context, "river_strength"), min_river_strength, max_river_strength, soft),
		"floodplain_strength": _score_range(_get_structure_value(structure_context, "floodplain_strength"), min_floodplain_strength, max_floodplain_strength, soft),
	}

func get_resolver_scores(channels: Variant, structure_context: Variant = null, soft: bool = false) -> Dictionary:
	var scores: Dictionary = get_channel_scores(channels, soft)
	if structure_context != null:
		scores.merge(get_structure_scores(structure_context, soft), true)
	return scores

func _compute_weighted_score(channels: Variant, soft: bool, structure_context: Variant = null) -> float:
	var total_weight: float = 0.0
	var total_score: float = 0.0
	var channel_scores: Dictionary = get_resolver_scores(channels, structure_context, soft)
	var score_keys: Array[String] = ["height", "temperature", "moisture", "ruggedness", "flora_density", "latitude"]
	if structure_context != null:
		score_keys.append_array(["ridge_strength", "river_strength", "floodplain_strength"])
	for key: String in score_keys:
		var weight: float = _get_weight_for_key(key)
		if weight <= 0.0:
			continue
		total_weight += weight
		total_score += float(channel_scores.get(key, 0.0)) * weight
	if total_weight <= 0.0:
		return 0.0
	return total_score / total_weight

func _get_weight_for_key(key: String) -> float:
	match key:
		"height":
			return height_weight
		"temperature":
			return temperature_weight
		"moisture":
			return moisture_weight
		"ruggedness":
			return ruggedness_weight
		"flora_density":
			return flora_density_weight
		"latitude":
			return latitude_weight
		"ridge_strength":
			return ridge_strength_weight
		"river_strength":
			return river_strength_weight
		"floodplain_strength":
			return floodplain_strength_weight
	return 0.0

func _matches_structure_context(structure_context: Variant) -> bool:
	if structure_context == null:
		return true
	return _is_in_range(_get_structure_value(structure_context, "ridge_strength"), min_ridge_strength, max_ridge_strength) \
		and _is_in_range(_get_structure_value(structure_context, "river_strength"), min_river_strength, max_river_strength) \
		and _is_in_range(_get_structure_value(structure_context, "floodplain_strength"), min_floodplain_strength, max_floodplain_strength)

func _get_structure_value(structure_context: Variant, key: StringName, default_value: float = 0.0) -> float:
	if structure_context == null:
		return default_value
	var value: Variant = _read_context_value(structure_context, key, default_value)
	if value is float or value is int:
		return float(value)
	return default_value

func _get_channel_value(channels: Variant, key: StringName, default_value: float = 0.0) -> float:
	if channels == null:
		return default_value
	var value: Variant = _read_context_value(channels, key, default_value)
	if value is float or value is int:
		return float(value)
	return default_value

func _read_context_value(context: Variant, key: StringName, default_value: Variant = null) -> Variant:
	if context == null:
		return default_value
	if context is Dictionary:
		var dictionary: Dictionary = context
		if dictionary.has(key):
			return dictionary[key]
		var string_key: String = String(key)
		if dictionary.has(string_key):
			return dictionary[string_key]
		return default_value
	if context is Object:
		return context.get(key)
	return default_value

func _is_in_range(value: float, min_value: float, max_value: float) -> bool:
	var lower: float = _canonicalize_score_input(minf(min_value, max_value))
	var upper: float = _canonicalize_score_input(maxf(min_value, max_value))
	value = _canonicalize_score_input(value)
	return value >= lower - _EPSILON and value <= upper + _EPSILON

func _score_range(value: float, min_value: float, max_value: float, soft: bool) -> float:
	var lower: float = _canonicalize_score_input(minf(min_value, max_value))
	var upper: float = _canonicalize_score_input(maxf(min_value, max_value))
	value = _canonicalize_score_input(value)
	if is_equal_approx(lower, upper):
		if is_equal_approx(value, lower):
			return 1.0
		if not soft:
			return 0.0
		return 1.0 / (1.0 + absf(value - lower) * 8.0)
	if value < lower - _EPSILON:
		if not soft:
			return 0.0
		return 1.0 / (1.0 + ((lower - value) / maxf(upper - lower, _EPSILON)) * 4.0)
	if value > upper + _EPSILON:
		if not soft:
			return 0.0
		return 1.0 / (1.0 + ((value - upper) / maxf(upper - lower, _EPSILON)) * 4.0)
	var center: float = (lower + upper) * 0.5
	var half_span: float = maxf((upper - lower) * 0.5, _EPSILON)
	return clampf(1.0 - absf(value - center) / half_span, 0.0, 1.0)

func _canonicalize_score_input(value: float) -> float:
	var packed := PackedFloat32Array([value])
	return float(packed[0])
