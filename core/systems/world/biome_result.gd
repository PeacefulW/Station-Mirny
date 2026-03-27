class_name BiomeResult
extends RefCounted

var biome: BiomeData = null
var biome_id: StringName = &""
var world_pos: Vector2i = Vector2i.ZERO
var score: float = -1.0
var priority: int = 0
var is_valid: bool = false
var used_fallback: bool = false
var channel_scores: Dictionary = {}
var structure_scores: Dictionary = {}
var matched_tags: Array[StringName] = []

func has_biome() -> bool:
	return biome != null and not str(biome_id).is_empty()

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
	biome = p_biome
	biome_id = p_biome.id if p_biome else &""
	score = p_score
	priority = p_biome.priority if p_biome else 0
	is_valid = p_is_valid
	used_fallback = p_used_fallback
	channel_scores = p_channel_scores.duplicate(true)
	structure_scores = p_structure_scores.duplicate(true)
	matched_tags = p_biome.tags.duplicate() if p_biome else []
	return self

func get_debug_summary() -> Dictionary:
	return {
		"biome_id": biome_id,
		"score": score,
		"priority": priority,
		"is_valid": is_valid,
		"used_fallback": used_fallback,
		"channel_scores": channel_scores.duplicate(true),
		"structure_scores": structure_scores.duplicate(true),
		"matched_tags": matched_tags.duplicate(),
	}
