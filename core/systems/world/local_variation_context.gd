class_name LocalVariationContext
extends RefCounted

const KIND_NONE: StringName = &"none"
const KIND_SPARSE_FLORA: StringName = &"sparse_flora"
const KIND_DENSE_FLORA: StringName = &"dense_flora"
const KIND_CLEARING: StringName = &"clearing"
const KIND_ROCKY_PATCH: StringName = &"rocky_patch"
const KIND_WET_PATCH: StringName = &"wet_patch"

const VARIATION_ID_NONE: int = 0
const VARIATION_ID_SPARSE_FLORA: int = 1
const VARIATION_ID_DENSE_FLORA: int = 2
const VARIATION_ID_CLEARING: int = 3
const VARIATION_ID_ROCKY_PATCH: int = 4
const VARIATION_ID_WET_PATCH: int = 5

var world_pos: Vector2i = Vector2i.ZERO
var canonical_world_pos: Vector2i = Vector2i.ZERO
var biome_id: StringName = &""
var biome_tags: Array[StringName] = []
var secondary_biome_id: StringName = &""
var secondary_biome_tags: Array[StringName] = []
var ecotone_factor: float = 0.0
var dominance: float = 1.0

var variation_kind: StringName = KIND_NONE
var variation_score: float = 0.0

var local_noise: float = 0.0
var patch_noise: float = 0.0
var detail_noise: float = 0.0

var flora_modulation: float = 0.0
var wetness_modulation: float = 0.0
var rockiness_modulation: float = 0.0
var openness_modulation: float = 0.0

var candidate_scores: Dictionary = {}

static func get_supported_kinds() -> Array[StringName]:
	return [
		KIND_SPARSE_FLORA,
		KIND_DENSE_FLORA,
		KIND_CLEARING,
		KIND_ROCKY_PATCH,
		KIND_WET_PATCH,
	]

static func kind_to_variation_id(kind: StringName) -> int:
	match kind:
		KIND_SPARSE_FLORA:
			return VARIATION_ID_SPARSE_FLORA
		KIND_DENSE_FLORA:
			return VARIATION_ID_DENSE_FLORA
		KIND_CLEARING:
			return VARIATION_ID_CLEARING
		KIND_ROCKY_PATCH:
			return VARIATION_ID_ROCKY_PATCH
		KIND_WET_PATCH:
			return VARIATION_ID_WET_PATCH
		_:
			return VARIATION_ID_NONE

func has_variation() -> bool:
	return variation_kind != KIND_NONE and variation_score > 0.0

func clamp_fields() -> LocalVariationContext:
	variation_score = clampf(variation_score, 0.0, 1.0)
	local_noise = clampf(local_noise, 0.0, 1.0)
	patch_noise = clampf(patch_noise, 0.0, 1.0)
	detail_noise = clampf(detail_noise, 0.0, 1.0)
	ecotone_factor = clampf(ecotone_factor, 0.0, 1.0)
	dominance = clampf(dominance, 0.0, 1.0)
	flora_modulation = clampf(flora_modulation, -1.0, 1.0)
	wetness_modulation = clampf(wetness_modulation, -1.0, 1.0)
	rockiness_modulation = clampf(rockiness_modulation, -1.0, 1.0)
	openness_modulation = clampf(openness_modulation, -1.0, 1.0)
	return self

func get_debug_summary() -> Dictionary:
	return {
		"world_pos": world_pos,
		"canonical_world_pos": canonical_world_pos,
		"biome_id": biome_id,
		"biome_tags": biome_tags.duplicate(),
		"secondary_biome_id": secondary_biome_id,
		"secondary_biome_tags": secondary_biome_tags.duplicate(),
		"ecotone_factor": ecotone_factor,
		"dominance": dominance,
		"variation_kind": variation_kind,
		"variation_score": variation_score,
		"local_noise": local_noise,
		"patch_noise": patch_noise,
		"detail_noise": detail_noise,
		"flora_modulation": flora_modulation,
		"wetness_modulation": wetness_modulation,
		"rockiness_modulation": rockiness_modulation,
		"openness_modulation": openness_modulation,
		"candidate_scores": candidate_scores.duplicate(true),
	}
