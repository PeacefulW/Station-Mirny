class_name BiomeResult
extends RefCounted

var biome: BiomeData = null
var biome_id: StringName = &""
var world_pos: Vector2i = Vector2i.ZERO
var score: float = -1.0
var primary_biome: BiomeData = null
var primary_biome_id: StringName = &""
var primary_score: float = -1.0
var secondary_biome: BiomeData = null
var secondary_biome_id: StringName = &""
var secondary_score: float = 0.0
var dominance: float = 0.0
var ecotone_factor: float = 0.0
var priority: int = 0
var is_valid: bool = false
var used_fallback: bool = false
var channel_scores: Dictionary = {}
var structure_scores: Dictionary = {}
var matched_tags: Array[StringName] = []

func has_biome() -> bool:
	return primary_biome != null and not str(primary_biome_id).is_empty()

func has_secondary_biome() -> bool:
	return secondary_biome != null and not str(secondary_biome_id).is_empty()

func configure(
	p_world_pos: Vector2i,
	p_biome: BiomeData,
	p_score: float,
	p_is_valid: bool,
	p_channel_scores: Dictionary,
	p_used_fallback: bool = false,
	p_structure_scores: Dictionary = {}
) -> BiomeResult:
	world_pos = p_world_pos
	primary_biome = p_biome
	primary_biome_id = p_biome.id if p_biome else &""
	primary_score = p_score
	biome = primary_biome
	biome_id = primary_biome_id
	score = primary_score
	priority = p_biome.priority if p_biome else 0
	is_valid = p_is_valid
	used_fallback = p_used_fallback
	channel_scores = p_channel_scores.duplicate(true)
	structure_scores = p_structure_scores.duplicate(true)
	matched_tags = p_biome.tags.duplicate() if p_biome else []
	secondary_biome = null
	secondary_biome_id = &""
	secondary_score = 0.0
	_refresh_transition_metrics()
	return self

func set_secondary_candidate(candidate: BiomeResult = null) -> BiomeResult:
	if candidate != null and candidate.has_biome():
		secondary_biome = candidate.primary_biome if candidate.primary_biome != null else candidate.biome
		secondary_biome_id = candidate.primary_biome_id if candidate.primary_biome_id != &"" else candidate.biome_id
		secondary_score = candidate.primary_score if candidate.primary_biome != null else candidate.score
	else:
		secondary_biome = null
		secondary_biome_id = &""
		secondary_score = 0.0
	_refresh_transition_metrics()
	return self

func get_debug_summary() -> Dictionary:
	return {
		"biome_id": biome_id,
		"score": score,
		"primary_biome_id": primary_biome_id,
		"primary_score": primary_score,
		"secondary_biome_id": secondary_biome_id,
		"secondary_score": secondary_score,
		"dominance": dominance,
		"ecotone_factor": ecotone_factor,
		"priority": priority,
		"is_valid": is_valid,
		"used_fallback": used_fallback,
		"channel_scores": channel_scores.duplicate(true),
		"structure_scores": structure_scores.duplicate(true),
		"matched_tags": matched_tags.duplicate(),
	}

func _refresh_transition_metrics() -> void:
	if not has_biome():
		dominance = 0.0
		ecotone_factor = 0.0
		return
	if not has_secondary_biome():
		dominance = 1.0
		ecotone_factor = 0.0
		return
	var score_gap: float = clampf(primary_score - secondary_score, 0.0, 1.0)
	dominance = score_gap
	ecotone_factor = clampf(1.0 - score_gap, 0.0, 1.0)
