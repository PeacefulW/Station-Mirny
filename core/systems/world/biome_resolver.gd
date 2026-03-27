class_name BiomeResolver
extends RefCounted

const BIOME_RESULT_SCRIPT := preload("res://core/systems/world/biome_result.gd")

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

func resolve_biome(world_pos: Vector2i, channels, structure_context = null):
	var best_valid = null
	var best_fallback = null
	for biome: BiomeData in _biomes:
		var is_valid: bool = biome.matches_channels(channels, structure_context)
		if is_valid:
			var valid_result = BIOME_RESULT_SCRIPT.new()
			valid_result.configure(
				world_pos,
				biome,
				biome.compute_match_score(channels, structure_context),
				true,
				biome.get_channel_scores(channels, false),
				false,
				biome.get_structure_scores(structure_context, false)
			)
			if _is_better_result(valid_result, best_valid):
				best_valid = valid_result
		var fallback_result = BIOME_RESULT_SCRIPT.new()
		fallback_result.configure(
			world_pos,
			biome,
			biome.compute_fallback_score(channels, structure_context),
			is_valid,
			biome.get_channel_scores(channels, true),
			not is_valid,
			biome.get_structure_scores(structure_context, true)
		)
		if _is_better_result(fallback_result, best_fallback):
			best_fallback = fallback_result
	if best_valid != null:
		return best_valid
	if best_fallback != null:
		return best_fallback
	return BIOME_RESULT_SCRIPT.new()

func _is_better_result(candidate, incumbent) -> bool:
	if candidate == null or not candidate.has_biome():
		return false
	if incumbent == null or not incumbent.has_biome():
		return true
	if not candidate.is_valid and incumbent.is_valid:
		return false
	if candidate.is_valid and not incumbent.is_valid:
		return true
	if candidate.score > incumbent.score + 0.0001:
		return true
	if candidate.score < incumbent.score - 0.0001:
		return false
	if candidate.priority != incumbent.priority:
		return candidate.priority > incumbent.priority
	return String(candidate.biome_id) < String(incumbent.biome_id)
