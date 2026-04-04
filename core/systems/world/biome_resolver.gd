class_name BiomeResolver
extends RefCounted

const _SCORE_EPSILON: float = 0.0001
const _LEGACY_SCORE_KEYS := ["height", "temperature", "moisture", "ruggedness", "flora_density", "latitude"]
const _STRUCTURE_SCORE_KEYS := ["ridge_strength", "river_strength", "floodplain_strength"]
const _CAUSAL_SCORE_KEYS := ["drainage", "slope", "rain_shadow", "continentalness"]
const _DEFAULT_CONTINENTAL_DRYING_FACTOR: float = 0.35
const _DEFAULT_DRAINAGE_MOISTURE_BONUS: float = 0.28

var _biomes: Array[BiomeData] = []

func configure(biomes: Array[BiomeData]) -> void:
	_biomes.clear()
	for biome: BiomeData in biomes:
		if biome == null:
			continue
		if str(biome.id).is_empty():
			continue
		_biomes.append(biome)
	_biomes.sort_custom(func(a: BiomeData, b: BiomeData) -> bool:
		if a.priority == b.priority:
			return String(a.id) < String(b.id)
		return a.priority > b.priority
	)

func get_biomes() -> Array[BiomeData]:
	return _biomes.duplicate()

func has_biomes() -> bool:
	return not _biomes.is_empty()

func resolve_biome(
	world_pos: Vector2i,
	channels: WorldChannels,
	structure_context: WorldStructureContext = null,
	prepass_channels: WorldPrePassChannels = null,
	balance: WorldGenBalance = null
) -> BiomeResult:
	var causal_context: Dictionary = _build_causal_context(channels, prepass_channels, balance)
	var best_valid: BiomeResult = null
	var second_valid: BiomeResult = null
	var best_fallback: BiomeResult = null
	var second_fallback: BiomeResult = null
	for biome: BiomeData in _biomes:
		var is_valid: bool = biome.matches_channels(channels, structure_context)
		if bool(causal_context.get("enabled", false)):
			is_valid = is_valid and _matches_causal_prepass(biome, causal_context)
		var channel_scores: Dictionary = _build_channel_scores(biome, channels, false, causal_context)
		var structure_scores: Dictionary = _build_structure_scores(biome, structure_context, false)
		if is_valid:
			var score: float = _compute_weighted_score(biome, channel_scores, structure_scores)
			var valid_candidate := BiomeResult.new().configure(
				world_pos,
				biome,
				score,
				true,
				channel_scores,
				false,
				structure_scores
			)
			var valid_ranked: Array = _insert_ranked_candidate(valid_candidate, best_valid, second_valid)
			best_valid = valid_ranked[0] as BiomeResult
			second_valid = valid_ranked[1] as BiomeResult
		var fallback_channel_scores: Dictionary = _build_channel_scores(biome, channels, true, causal_context)
		var fallback_structure_scores: Dictionary = _build_structure_scores(biome, structure_context, true)
		var fallback_score: float = _compute_weighted_score(biome, fallback_channel_scores, fallback_structure_scores)
		var fallback_candidate := BiomeResult.new().configure(
			world_pos,
			biome,
			fallback_score,
			is_valid,
			fallback_channel_scores,
			not is_valid,
			fallback_structure_scores
		)
		var fallback_ranked: Array = _insert_ranked_candidate(fallback_candidate, best_fallback, second_fallback)
		best_fallback = fallback_ranked[0] as BiomeResult
		second_fallback = fallback_ranked[1] as BiomeResult
	if best_valid != null:
		best_valid.set_secondary_candidate(
			_select_secondary_candidate(best_valid, second_valid, best_fallback, second_fallback)
		)
		return best_valid
	if best_fallback != null:
		best_fallback.set_secondary_candidate(
			_select_secondary_candidate(best_fallback, second_fallback)
		)
		return best_fallback
	return BiomeResult.new()

func _insert_ranked_candidate(candidate: BiomeResult, best: BiomeResult, second: BiomeResult) -> Array:
	if candidate == null or not candidate.has_biome():
		return [best, second]
	if _is_candidate_better(candidate, best):
		if best != null and best.has_biome() and best.biome_id != candidate.biome_id:
			second = best
		best = candidate
		return [best, second]
	if best != null and best.has_biome() and candidate.biome_id == best.biome_id:
		return [best, second]
	if _is_candidate_better(candidate, second):
		second = candidate
	return [best, second]

func _select_secondary_candidate(
	primary_candidate: BiomeResult,
	preferred_secondary: BiomeResult,
	fallback_best: BiomeResult = null,
	fallback_second: BiomeResult = null
) -> BiomeResult:
	for candidate: BiomeResult in [preferred_secondary, fallback_best, fallback_second]:
		if candidate == null or not candidate.has_biome():
			continue
		if primary_candidate != null and primary_candidate.has_biome() and candidate.biome_id == primary_candidate.biome_id:
			continue
		return candidate
	return null

func _build_channel_scores(
	biome: BiomeData,
	channels: WorldChannels,
	soft: bool,
	causal_context: Dictionary
) -> Dictionary:
	var channel_scores: Dictionary = biome.get_channel_scores(channels, soft)
	if not bool(causal_context.get("enabled", false)):
		return channel_scores
	if _uses_causal_moisture(biome):
		channel_scores["moisture"] = biome._score_range(
			float(causal_context.get("effective_moisture", channels.moisture)),
			biome.min_moisture,
			biome.max_moisture,
			soft
		)
	channel_scores["drainage"] = biome._score_range(
		float(causal_context.get("drainage", 0.0)),
		biome.min_drainage,
		biome.max_drainage,
		soft
	)
	channel_scores["slope"] = biome._score_range(
		float(causal_context.get("slope", 0.0)),
		biome.min_slope,
		biome.max_slope,
		soft
	)
	channel_scores["rain_shadow"] = biome._score_range(
		float(causal_context.get("rain_shadow", 0.0)),
		biome.min_rain_shadow,
		biome.max_rain_shadow,
		soft
	)
	channel_scores["continentalness"] = biome._score_range(
		float(causal_context.get("continentalness", 0.0)),
		biome.min_continentalness,
		biome.max_continentalness,
		soft
	)
	channel_scores["base_moisture"] = float(causal_context.get("base_moisture", channels.moisture))
	channel_scores["effective_moisture"] = float(causal_context.get("effective_moisture", channels.moisture))
	channel_scores["drainage_input"] = float(causal_context.get("drainage", 0.0))
	channel_scores["slope_input"] = float(causal_context.get("slope", 0.0))
	channel_scores["rain_shadow_input"] = float(causal_context.get("rain_shadow", 0.0))
	channel_scores["continentalness_input"] = float(causal_context.get("continentalness", 0.0))
	channel_scores["moisture_retention"] = float(causal_context.get("moisture_retention", 1.0))
	channel_scores["continental_drying_factor"] = float(causal_context.get("continental_drying_factor", 0.0))
	channel_scores["drainage_moisture_bonus"] = float(causal_context.get("drainage_moisture_bonus", 0.0))
	return channel_scores

func _build_structure_scores(
	biome: BiomeData,
	structure_context: WorldStructureContext,
	soft: bool
) -> Dictionary:
	return biome.get_structure_scores(structure_context, soft)

func _compute_weighted_score(
	biome: BiomeData,
	channel_scores: Dictionary,
	structure_scores: Dictionary
) -> float:
	var total_weight: float = 0.0
	var total_score: float = 0.0
	for key: String in _LEGACY_SCORE_KEYS:
		var legacy_weight: float = biome._get_weight_for_key(key)
		if legacy_weight > 0.0:
			total_weight += legacy_weight
			total_score += float(channel_scores.get(key, 0.0)) * legacy_weight
	for key: String in _STRUCTURE_SCORE_KEYS:
		var structure_weight: float = biome._get_weight_for_key(key)
		if structure_weight > 0.0:
			total_weight += structure_weight
			total_score += float(structure_scores.get(key, 0.0)) * structure_weight
	for key: String in _CAUSAL_SCORE_KEYS:
		var causal_weight: float = _get_causal_weight_for_key(biome, key)
		if causal_weight > 0.0:
			total_weight += causal_weight
			total_score += float(channel_scores.get(key, 0.0)) * causal_weight
	if total_weight <= 0.0:
		return 0.0
	return total_score / total_weight

func _matches_causal_prepass(biome: BiomeData, causal_context: Dictionary) -> bool:
	return _matches_weighted_range(
		biome,
		float(causal_context.get("drainage", 0.0)),
		biome.min_drainage,
		biome.max_drainage,
		biome.drainage_weight
	) and _matches_weighted_range(
		biome,
		float(causal_context.get("slope", 0.0)),
		biome.min_slope,
		biome.max_slope,
		biome.slope_weight
	) and _matches_weighted_range(
		biome,
		float(causal_context.get("rain_shadow", 0.0)),
		biome.min_rain_shadow,
		biome.max_rain_shadow,
		biome.rain_shadow_weight
	) and _matches_weighted_range(
		biome,
		float(causal_context.get("continentalness", 0.0)),
		biome.min_continentalness,
		biome.max_continentalness,
		biome.continentalness_weight
	)

func _matches_weighted_range(
	biome: BiomeData,
	value: float,
	min_value: float,
	max_value: float,
	weight: float
) -> bool:
	if weight <= 0.0:
		return true
	return biome._is_in_range(value, min_value, max_value)

func _uses_causal_moisture(biome: BiomeData) -> bool:
	return biome.drainage_weight > 0.0 or biome.rain_shadow_weight > 0.0 or biome.continentalness_weight > 0.0

func _build_causal_context(
	channels: WorldChannels,
	prepass_channels: WorldPrePassChannels,
	balance: WorldGenBalance
) -> Dictionary:
	if prepass_channels == null:
		return {
			"enabled": false,
			"base_moisture": channels.moisture,
			"effective_moisture": channels.moisture,
		}
	var base_moisture: float = clampf(channels.moisture, 0.0, 1.0)
	var drainage: float = clampf(prepass_channels.drainage, 0.0, 1.0)
	var slope: float = clampf(prepass_channels.slope, 0.0, 1.0)
	var rain_shadow: float = clampf(prepass_channels.rain_shadow, 0.0, 1.0)
	var continentalness: float = clampf(prepass_channels.continentalness, 0.0, 1.0)
	var continental_drying_factor: float = _get_balance_float(
		balance,
		"biome_continental_drying_factor",
		_DEFAULT_CONTINENTAL_DRYING_FACTOR
	)
	var drainage_moisture_bonus: float = _get_balance_float(
		balance,
		"biome_drainage_moisture_bonus",
		_DEFAULT_DRAINAGE_MOISTURE_BONUS
	)
	# The pre-pass channel stores rain-shadow pressure, so higher values mean less retained moisture.
	var moisture_retention: float = clampf(1.0 - rain_shadow, 0.0, 1.0)
	var continental_retention: float = clampf(1.0 - continentalness * continental_drying_factor, 0.0, 1.0)
	var effective_moisture: float = clampf(
		base_moisture * moisture_retention * continental_retention + drainage * drainage_moisture_bonus,
		0.0,
		1.0
	)
	return {
		"enabled": true,
		"base_moisture": base_moisture,
		"effective_moisture": effective_moisture,
		"drainage": drainage,
		"slope": slope,
		"rain_shadow": rain_shadow,
		"continentalness": continentalness,
		"moisture_retention": moisture_retention,
		"continental_drying_factor": continental_drying_factor,
		"drainage_moisture_bonus": drainage_moisture_bonus,
	}

func _get_causal_weight_for_key(biome: BiomeData, key: String) -> float:
	match key:
		"drainage":
			return biome.drainage_weight
		"slope":
			return biome.slope_weight
		"rain_shadow":
			return biome.rain_shadow_weight
		"continentalness":
			return biome.continentalness_weight
	return 0.0

func _get_balance_float(balance: WorldGenBalance, property_name: StringName, fallback: float) -> float:
	if balance == null:
		return fallback
	var value: Variant = balance.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback

func _is_candidate_better(candidate: BiomeResult, incumbent: BiomeResult) -> bool:
	if candidate == null or not candidate.has_biome():
		return false
	return _is_better_score(candidate.score, candidate.biome, incumbent)

func _is_better_score(score: float, biome: BiomeData, incumbent: BiomeResult) -> bool:
	if incumbent == null or not incumbent.has_biome():
		return true
	if score > incumbent.score + _SCORE_EPSILON:
		return true
	if score < incumbent.score - _SCORE_EPSILON:
		return false
	if biome.priority != incumbent.priority:
		return biome.priority > incumbent.priority
	return String(biome.id) < String(incumbent.biome_id)

