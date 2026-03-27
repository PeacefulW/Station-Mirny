class_name BiomeResolver
extends RefCounted

const _SCORE_EPSILON: float = 0.0001

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

func resolve_biome(world_pos: Vector2i, channels: WorldChannels, structure_context: WorldStructureContext = null) -> BiomeResult:
	var best_valid: BiomeResult = null
	var best_fallback: BiomeResult = null
	for biome: BiomeData in _biomes:
		var is_valid: bool = biome.matches_channels(channels, structure_context)
		if is_valid:
			var score: float = biome._compute_weighted_score(channels, false, structure_context)
			if _is_better_score(score, biome, best_valid):
				best_valid = BiomeResult.new()
				best_valid.configure(world_pos, biome, score, true, {}, false, {})
		if best_valid == null:
			var fallback_score: float = biome._compute_weighted_score(channels, true, structure_context)
			if _is_better_score(fallback_score, biome, best_fallback):
				best_fallback = BiomeResult.new()
				best_fallback.configure(world_pos, biome, fallback_score, is_valid, {}, not is_valid, {})
	if best_valid != null:
		return best_valid
	if best_fallback != null:
		return best_fallback
	return BiomeResult.new()

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
