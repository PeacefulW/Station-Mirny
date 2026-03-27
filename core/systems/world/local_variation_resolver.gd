class_name LocalVariationResolver
extends RefCounted

const LOCAL_VARIATION_CONTEXT_SCRIPT := preload("res://core/systems/world/local_variation_context.gd")

const _DEFAULT_WRAP_WIDTH_TILES: int = 4096
const _SCORE_EPSILON: float = 0.00001

const _KIND_NONE: StringName = &"none"
const _KIND_SPARSE_FLORA: StringName = &"sparse_flora"
const _KIND_DENSE_FLORA: StringName = &"dense_flora"
const _KIND_CLEARING: StringName = &"clearing"
const _KIND_ROCKY_PATCH: StringName = &"rocky_patch"
const _KIND_WET_PATCH: StringName = &"wet_patch"

var _world_seed: int = 0
var _balance: WorldGenBalance = null
var _field_noise: FastNoiseLite = FastNoiseLite.new()
var _patch_noise: FastNoiseLite = FastNoiseLite.new()
var _detail_noise: FastNoiseLite = FastNoiseLite.new()

func initialize(seed_value: int, balance_resource: WorldGenBalance) -> void:
	_world_seed = seed_value
	_balance = balance_resource
	if not _balance:
		return
	var base_frequency: float = maxf(_balance.local_variation_frequency, 0.0001)
	var base_octaves: int = maxi(1, _balance.local_variation_octaves)
	_setup_noise_instance(_field_noise, _world_seed + 311, base_frequency, base_octaves)
	_setup_noise_instance(_patch_noise, _world_seed + 353, base_frequency * 1.85, maxi(1, base_octaves + 1))
	_setup_noise_instance(_detail_noise, _world_seed + 389, base_frequency * 3.2, maxi(1, min(base_octaves + 1, 6)))

func resolve_local_variation(world_pos: Vector2i, biome = null, channels = null, structure_context = null):
	var context = LOCAL_VARIATION_CONTEXT_SCRIPT.new()
	context.world_pos = world_pos
	context.canonical_world_pos = canonicalize_world_pos(world_pos)
	context.biome_id = _resolve_biome_id(biome)
	context.biome_tags = _resolve_biome_tags(biome)
	context.local_noise = _sample_periodic_noise01(_field_noise, context.canonical_world_pos)
	context.patch_noise = _sample_periodic_noise01(_patch_noise, context.canonical_world_pos)
	context.detail_noise = _sample_periodic_noise01(_detail_noise, context.canonical_world_pos)

	var candidate_scores: Dictionary = {
		_KIND_SPARSE_FLORA: _score_sparse_flora(context, channels, structure_context),
		_KIND_DENSE_FLORA: _score_dense_flora(context, channels, structure_context),
		_KIND_CLEARING: _score_clearing(context, channels, structure_context),
		_KIND_ROCKY_PATCH: _score_rocky_patch(context, channels, structure_context),
		_KIND_WET_PATCH: _score_wet_patch(context, channels, structure_context),
	}
	context.candidate_scores = candidate_scores.duplicate(true)

	var best_kind: StringName = _KIND_NONE
	var best_score: float = 0.0
	for kind: StringName in LOCAL_VARIATION_CONTEXT_SCRIPT.get_supported_kinds():
		var score: float = float(candidate_scores.get(kind, 0.0))
		if score > best_score + _SCORE_EPSILON:
			best_kind = kind
			best_score = score

	if best_score < _resolve_min_score():
		best_kind = _KIND_NONE
		best_score = 0.0

	context.variation_kind = best_kind
	context.variation_score = best_score
	_apply_modulations(context, channels, structure_context)
	return context.clamp_fields()

func canonicalize_world_pos(world_pos: Vector2i) -> Vector2i:
	return Vector2i(wrap_world_x(world_pos.x), world_pos.y)

func wrap_world_x(world_x: int) -> int:
	var width: int = _resolve_wrap_width_tiles()
	if width <= 0:
		return world_x
	return int(posmod(world_x, width))

func get_wrap_width_tiles() -> int:
	return _resolve_wrap_width_tiles()

func _score_sparse_flora(context, channels, structure_context) -> float:
	var flora_density: float = _channel_value(channels, "flora_density", 0.5)
	var moisture: float = _channel_value(channels, "moisture", 0.5)
	var ruggedness: float = _channel_value(channels, "ruggedness", 0.5)
	var river_strength: float = _structure_value(structure_context, "river_strength")
	var floodplain_strength: float = _structure_value(structure_context, "floodplain_strength")
	var mountain_mass: float = _structure_value(structure_context, "mountain_mass")
	var base_score: float = (
		(1.0 - flora_density) * 0.42
		+ (1.0 - moisture) * 0.18
		+ ruggedness * 0.12
		+ (1.0 - floodplain_strength) * 0.10
		+ (1.0 - river_strength) * 0.08
		+ mountain_mass * 0.10
	)
	var noise_score: float = _blend_noise_scores(
		_band_score(context.local_noise, 0.24, 0.24),
		_band_score(context.patch_noise, 0.34, 0.20),
		0.65
	)
	var tag_bias: float = _tag_bias(
		context.biome_tags,
		[&"dry", &"upland", &"mountain", &"cold"],
		[&"wet", &"lowland"]
	)
	return _normalize_score(base_score * 0.74 + noise_score * 0.18 + tag_bias)

func _score_dense_flora(context, channels, structure_context) -> float:
	var flora_density: float = _channel_value(channels, "flora_density", 0.5)
	var moisture: float = _channel_value(channels, "moisture", 0.5)
	var ruggedness: float = _channel_value(channels, "ruggedness", 0.5)
	var ridge_strength: float = _structure_value(structure_context, "ridge_strength")
	var floodplain_strength: float = _structure_value(structure_context, "floodplain_strength")
	var mountain_mass: float = _structure_value(structure_context, "mountain_mass")
	var base_score: float = (
		flora_density * 0.42
		+ moisture * 0.24
		+ floodplain_strength * 0.12
		+ (1.0 - ruggedness) * 0.08
		+ (1.0 - ridge_strength) * 0.08
		+ (1.0 - mountain_mass) * 0.06
	)
	var noise_score: float = _blend_noise_scores(
		_band_score(context.local_noise, 0.78, 0.22),
		_band_score(context.detail_noise, 0.62, 0.20),
		0.70
	)
	var tag_bias: float = _tag_bias(
		context.biome_tags,
		[&"wet", &"temperate", &"baseline", &"lowland"],
		[&"dry", &"mountain"]
	)
	return _normalize_score(base_score * 0.74 + noise_score * 0.18 + tag_bias)

func _score_clearing(context, channels, structure_context) -> float:
	var flora_density: float = _channel_value(channels, "flora_density", 0.5)
	var moisture: float = _channel_value(channels, "moisture", 0.5)
	var ruggedness: float = _channel_value(channels, "ruggedness", 0.5)
	var ridge_strength: float = _structure_value(structure_context, "ridge_strength")
	var river_strength: float = _structure_value(structure_context, "river_strength")
	var vegetated_gate: float = clampf(flora_density * 1.35 - 0.18, 0.0, 1.0)
	var base_score: float = (
		flora_density * 0.28
		+ moisture * 0.10
		+ (1.0 - ruggedness) * 0.18
		+ (1.0 - ridge_strength) * 0.08
		+ (1.0 - river_strength) * 0.06
	)
	var noise_score: float = _blend_noise_scores(
		_band_score(context.local_noise, 0.50, 0.16),
		_band_score(context.patch_noise, 0.48, 0.14),
		0.55
	)
	var tag_bias: float = _tag_bias(
		context.biome_tags,
		[&"temperate", &"baseline", &"wet"],
		[&"mountain", &"dry"]
	)
	return _normalize_score(vegetated_gate * (base_score * 0.72 + noise_score * 0.22 + tag_bias))

func _score_rocky_patch(context, channels, structure_context) -> float:
	var flora_density: float = _channel_value(channels, "flora_density", 0.5)
	var moisture: float = _channel_value(channels, "moisture", 0.5)
	var ruggedness: float = _channel_value(channels, "ruggedness", 0.5)
	var ridge_strength: float = _structure_value(structure_context, "ridge_strength")
	var mountain_mass: float = _structure_value(structure_context, "mountain_mass")
	var floodplain_strength: float = _structure_value(structure_context, "floodplain_strength")
	var base_score: float = (
		ruggedness * 0.38
		+ ridge_strength * 0.22
		+ mountain_mass * 0.18
		+ (1.0 - flora_density) * 0.10
		+ (1.0 - moisture) * 0.06
		+ (1.0 - floodplain_strength) * 0.06
	)
	var noise_score: float = _blend_noise_scores(
		_band_score(context.local_noise, 0.86, 0.18),
		_band_score(context.detail_noise, 0.82, 0.18),
		0.65
	)
	var tag_bias: float = _tag_bias(
		context.biome_tags,
		[&"mountain", &"highland", &"upland"],
		[&"wet", &"lowland"]
	)
	return _normalize_score(base_score * 0.76 + noise_score * 0.16 + tag_bias)

func _score_wet_patch(context, channels, structure_context) -> float:
	var flora_density: float = _channel_value(channels, "flora_density", 0.5)
	var moisture: float = _channel_value(channels, "moisture", 0.5)
	var ruggedness: float = _channel_value(channels, "ruggedness", 0.5)
	var river_strength: float = _structure_value(structure_context, "river_strength")
	var floodplain_strength: float = _structure_value(structure_context, "floodplain_strength")
	var mountain_mass: float = _structure_value(structure_context, "mountain_mass")
	var base_score: float = (
		moisture * 0.34
		+ floodplain_strength * 0.26
		+ river_strength * 0.18
		+ (1.0 - ruggedness) * 0.08
		+ flora_density * 0.06
		+ (1.0 - mountain_mass) * 0.04
	)
	var noise_score: float = _blend_noise_scores(
		_band_score(context.local_noise, 0.12, 0.18),
		_band_score(context.patch_noise, 0.70, 0.20),
		0.70
	)
	var tag_bias: float = _tag_bias(
		context.biome_tags,
		[&"wet", &"lowland", &"temperate"],
		[&"dry", &"mountain", &"highland"]
	)
	return _normalize_score(base_score * 0.76 + noise_score * 0.16 + tag_bias)

func _apply_modulations(context, channels, structure_context) -> void:
	if context.variation_kind == _KIND_NONE:
		return
	var intensity: float = context.variation_score
	var floodplain_strength: float = _structure_value(structure_context, "floodplain_strength")
	var river_strength: float = _structure_value(structure_context, "river_strength")
	var ridge_strength: float = _structure_value(structure_context, "ridge_strength")
	var ruggedness: float = _channel_value(channels, "ruggedness", 0.5)
	var moisture: float = _channel_value(channels, "moisture", 0.5)

	match context.variation_kind:
		_KIND_SPARSE_FLORA:
			context.flora_modulation = -(0.16 + intensity * 0.34)
			context.wetness_modulation = -(0.06 + intensity * 0.14) + (0.04 - moisture * 0.04)
			context.rockiness_modulation = 0.06 + intensity * 0.18 + ruggedness * 0.08
			context.openness_modulation = 0.16 + intensity * 0.34
		_KIND_DENSE_FLORA:
			context.flora_modulation = 0.18 + intensity * 0.38
			context.wetness_modulation = 0.06 + intensity * 0.16 + floodplain_strength * 0.08
			context.rockiness_modulation = -(0.04 + intensity * 0.16)
			context.openness_modulation = -(0.10 + intensity * 0.30)
		_KIND_CLEARING:
			context.flora_modulation = -(0.10 + intensity * 0.26)
			context.wetness_modulation = -(0.02 + intensity * 0.08)
			context.rockiness_modulation = -(0.04 + intensity * 0.08)
			context.openness_modulation = 0.18 + intensity * 0.40
		_KIND_ROCKY_PATCH:
			context.flora_modulation = -(0.08 + intensity * 0.22)
			context.wetness_modulation = -(0.04 + intensity * 0.14)
			context.rockiness_modulation = 0.18 + intensity * 0.42 + ridge_strength * 0.10 + ruggedness * 0.08
			context.openness_modulation = 0.06 + intensity * 0.16
		_KIND_WET_PATCH:
			context.flora_modulation = 0.04 + intensity * 0.16
			context.wetness_modulation = 0.18 + intensity * 0.40 + maxf(floodplain_strength, river_strength) * 0.10
			context.rockiness_modulation = -(0.06 + intensity * 0.12)
			context.openness_modulation = -(0.04 + intensity * 0.12)

func _resolve_biome_id(biome) -> StringName:
	var value: Variant = null
	if biome is Dictionary:
		var biome_dict: Dictionary = biome
		value = biome_dict.get("biome_id", biome_dict.get("id", &""))
	elif biome != null and biome is Object:
		var biome_object: Object = biome
		value = biome_object.get(&"biome_id")
		if value == null:
			value = biome_object.get(&"id")
	if value is StringName:
		return value
	if value is String and not String(value).is_empty():
		return StringName(String(value))
	return &""

func _resolve_biome_tags(biome) -> Array[StringName]:
	var raw_tags: Variant = []
	if biome is Dictionary:
		var biome_dict: Dictionary = biome
		raw_tags = biome_dict.get("matched_tags", biome_dict.get("tags", []))
	elif biome != null and biome is Object:
		var biome_object: Object = biome
		raw_tags = biome_object.get(&"matched_tags")
		if raw_tags == null:
			raw_tags = biome_object.get(&"tags")
	var tags: Array[StringName] = []
	if raw_tags is Array:
		for tag: Variant in raw_tags:
			if tag is StringName:
				tags.append(tag)
			elif tag is String and not String(tag).is_empty():
				tags.append(StringName(String(tag)))
	return tags

func _tag_bias(tags: Array[StringName], positive_tags: Array[StringName], negative_tags: Array[StringName]) -> float:
	var bias: float = 0.0
	for tag: StringName in positive_tags:
		if tags.has(tag):
			bias += 0.035
	for tag: StringName in negative_tags:
		if tags.has(tag):
			bias -= 0.04
	return clampf(bias, -0.12, 0.12)

func _channel_value(channels, property_name: String, fallback_value: float) -> float:
	if channels == null:
		return fallback_value
	var value: Variant = channels.get(property_name) if channels is Object else fallback_value
	if value is float or value is int:
		return float(value)
	return fallback_value

func _structure_value(structure_context, property_name: String, fallback_value: float = 0.0) -> float:
	if structure_context == null:
		return fallback_value
	var value: Variant = fallback_value
	if structure_context is Dictionary:
		value = (structure_context as Dictionary).get(property_name, fallback_value)
	elif structure_context is Object:
		value = (structure_context as Object).get(StringName(property_name))
	if value is float or value is int:
		return float(value)
	return fallback_value

func _band_score(value: float, center: float, half_width: float) -> float:
	if half_width <= _SCORE_EPSILON:
		return 0.0
	return clampf(1.0 - absf(value - center) / half_width, 0.0, 1.0)

func _blend_noise_scores(primary_score: float, secondary_score: float, primary_weight: float) -> float:
	var clamped_weight: float = clampf(primary_weight, 0.0, 1.0)
	return primary_score * clamped_weight + secondary_score * (1.0 - clamped_weight)

func _normalize_score(raw_score: float) -> float:
	return clampf(raw_score - 0.18, 0.0, 1.0)

func _resolve_min_score() -> float:
	if not _balance:
		return 0.22
	return clampf(_balance.local_variation_min_score, 0.0, 1.0)

func _sample_periodic_noise01(noise: FastNoiseLite, world_pos: Vector2i) -> float:
	var width: int = _resolve_wrap_width_tiles()
	if width <= 0:
		return _sample01(noise.get_noise_2d(world_pos.x, world_pos.y))
	var wrapped_x: int = wrap_world_x(world_pos.x)
	var angle: float = TAU * float(wrapped_x) / float(width)
	var ring_radius: float = float(width) / TAU
	var sample_x: float = cos(angle) * ring_radius
	var sample_y: float = float(world_pos.y)
	var sample_z: float = sin(angle) * ring_radius
	return _sample01(noise.get_noise_3d(sample_x, sample_y, sample_z))

func _setup_noise_instance(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.55
	noise.fractal_lacunarity = 2.05
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

func _resolve_wrap_width_tiles() -> int:
	if not _balance:
		return _DEFAULT_WRAP_WIDTH_TILES
	var tile_width: int = maxi(256, _balance.world_wrap_width_tiles)
	var chunk_size: int = maxi(1, _balance.chunk_size_tiles)
	var chunk_count: int = maxi(1, int(ceili(float(tile_width) / float(chunk_size))))
	return chunk_count * chunk_size

func _sample01(value: float) -> float:
	return value * 0.5 + 0.5
