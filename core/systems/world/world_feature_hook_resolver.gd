class_name WorldFeatureHookResolver
extends RefCounted

const STRUCTURE_TAG_SURFACE: StringName = &"surface"
const STRUCTURE_TAG_RIDGE: StringName = &"ridge"
const STRUCTURE_TAG_MOUNTAIN: StringName = &"mountain"
const STRUCTURE_TAG_RIVER: StringName = &"river"
const STRUCTURE_TAG_FLOODPLAIN: StringName = &"floodplain"

static func resolve_for_origin(candidate_origin: Vector2i, ctx: WorldComputeContext) -> Array[Dictionary]:
	var ordered_decisions: Array[Dictionary] = []
	if ctx == null:
		return ordered_decisions
	var canonical_origin: Vector2i = ctx.canonicalize_tile(candidate_origin)
	var channels: WorldChannels = ctx.sample_world_channels(canonical_origin)
	var structure_context: WorldStructureContext = ctx.sample_structure_context(canonical_origin, channels)
	var biome_result: BiomeResult = ctx.get_biome_result_at_tile(canonical_origin, channels, structure_context)
	var local_variation: LocalVariationContext = ctx.sample_local_variation(
		canonical_origin,
		biome_result,
		channels,
		structure_context
	)
	var terrain_type: int = ctx.get_surface_terrain_type(canonical_origin)
	var structure_tags: Array[StringName] = _collect_structure_tags(structure_context)
	for feature_hook_resource: Resource in ctx.get_feature_hook_snapshot():
		if feature_hook_resource == null:
			continue
		if not _is_feature_hook_eligible(feature_hook_resource, biome_result, terrain_type, structure_tags):
			continue
		var decision: Dictionary = {
			"candidate_origin": canonical_origin,
			"hook_id": _get_hook_id(feature_hook_resource),
			"score": _compute_score(
				feature_hook_resource,
				ctx,
				canonical_origin,
				channels,
				structure_context,
				biome_result,
				local_variation
			),
			"debug_marker_kind": _get_hook_debug_marker_kind(feature_hook_resource),
		}
		_insert_ordered_decision(ordered_decisions, decision)
	return ordered_decisions

static func _insert_ordered_decision(ordered_decisions: Array[Dictionary], decision: Dictionary) -> void:
	for index: int in range(ordered_decisions.size()):
		if _is_decision_before(decision, ordered_decisions[index]):
			ordered_decisions.insert(index, decision)
			return
	ordered_decisions.append(decision)

static func _is_decision_before(left: Dictionary, right: Dictionary) -> bool:
	var left_score: float = float(left.get("score", 0.0))
	var right_score: float = float(right.get("score", 0.0))
	if not is_equal_approx(left_score, right_score):
		return left_score > right_score
	return str(left.get("hook_id", &"")) < str(right.get("hook_id", &""))

static func _is_feature_hook_eligible(
	feature_hook: Resource,
	biome_result: BiomeResult,
	terrain_type: int,
	structure_tags: Array[StringName]
) -> bool:
	var hook_id: StringName = _get_hook_id(feature_hook)
	if hook_id == &"":
		return false
	var hook_weight: float = _get_hook_weight(feature_hook)
	if hook_weight <= 0.0:
		return false
	var allowed_biome_ids: Array[StringName] = _get_hook_string_name_array(feature_hook, "allowed_biome_ids")
	if not allowed_biome_ids.is_empty():
		if biome_result == null or not allowed_biome_ids.has(biome_result.biome_id):
			return false
	var allowed_terrain_types: Array[int] = _get_hook_int_array(feature_hook, "allowed_terrain_types")
	if not allowed_terrain_types.is_empty() and not allowed_terrain_types.has(terrain_type):
		return false
	for required_tag: StringName in _get_hook_string_name_array(feature_hook, "required_structure_tags"):
		if not structure_tags.has(required_tag):
			return false
	return true

static func _collect_structure_tags(structure_context: WorldStructureContext) -> Array[StringName]:
	var structure_tags: Array[StringName] = [STRUCTURE_TAG_SURFACE]
	if structure_context == null:
		return structure_tags
	if structure_context.is_ridge_core():
		structure_tags.append(STRUCTURE_TAG_RIDGE)
	if structure_context.mountain_mass >= 0.5:
		structure_tags.append(STRUCTURE_TAG_MOUNTAIN)
	if structure_context.is_river_core():
		structure_tags.append(STRUCTURE_TAG_RIVER)
	if structure_context.has_floodplain():
		structure_tags.append(STRUCTURE_TAG_FLOODPLAIN)
	return structure_tags

static func _compute_score(
	feature_hook: Resource,
	ctx: WorldComputeContext,
	canonical_origin: Vector2i,
	channels: WorldChannels,
	structure_context: WorldStructureContext,
	biome_result: BiomeResult,
	local_variation: LocalVariationContext
) -> float:
	var biome_factor: float = clampf(biome_result.score if biome_result else 0.0, 0.0, 1.0)
	var flora_factor: float = clampf(channels.flora_density if channels else 0.0, 0.0, 1.0)
	var variation_factor: float = clampf(local_variation.variation_score if local_variation else 0.0, 0.0, 1.0)
	var required_structure_tags: Array[StringName] = _get_hook_string_name_array(feature_hook, "required_structure_tags")
	var structure_factor: float = _compute_structure_factor(required_structure_tags, structure_context)
	var hash_factor: float = _hash_to_unit_interval(ctx.get_world_seed(), canonical_origin, _get_hook_id(feature_hook))
	var weighted_score: float = maxf(0.0, _get_hook_weight(feature_hook)) * (
		1.0
		+ biome_factor * 0.35
		+ structure_factor * 0.25
		+ variation_factor * 0.20
		+ flora_factor * 0.20
	)
	return snappedf(weighted_score + hash_factor * 0.000001, 0.000001)

static func _compute_structure_factor(required_structure_tags: Array[StringName], structure_context: WorldStructureContext) -> float:
	if required_structure_tags.is_empty():
		return 0.0
	var total: float = 0.0
	for required_tag: StringName in required_structure_tags:
		total += _resolve_structure_tag_strength(required_tag, structure_context)
	return clampf(total / float(required_structure_tags.size()), 0.0, 1.0)

static func _resolve_structure_tag_strength(required_tag: StringName, structure_context: WorldStructureContext) -> float:
	if required_tag == STRUCTURE_TAG_SURFACE:
		return 1.0
	if structure_context == null:
		return 0.0
	match required_tag:
		STRUCTURE_TAG_RIDGE:
			return clampf(structure_context.ridge_strength, 0.0, 1.0)
		STRUCTURE_TAG_MOUNTAIN:
			return clampf(structure_context.mountain_mass, 0.0, 1.0)
		STRUCTURE_TAG_RIVER:
			return clampf(structure_context.river_strength, 0.0, 1.0)
		STRUCTURE_TAG_FLOODPLAIN:
			return clampf(structure_context.floodplain_strength, 0.0, 1.0)
		_:
			return 0.0

static func _hash_to_unit_interval(world_seed: int, canonical_origin: Vector2i, hook_id: StringName) -> float:
	var hash_key: String = "%d|%d|%d|%s" % [world_seed, canonical_origin.x, canonical_origin.y, str(hook_id)]
	var hash_value: int = abs(hash(hash_key))
	return float(hash_value % 1000000) / 1000000.0

static func _get_hook_id(feature_hook: Resource) -> StringName:
	if feature_hook == null:
		return &""
	return feature_hook.get("id") as StringName

static func _get_hook_weight(feature_hook: Resource) -> float:
	if feature_hook == null:
		return 0.0
	return float(feature_hook.get("weight"))

static func _get_hook_debug_marker_kind(feature_hook: Resource) -> StringName:
	if feature_hook == null:
		return &""
	return feature_hook.get("debug_marker_kind") as StringName

static func _get_hook_string_name_array(feature_hook: Resource, property_name: String) -> Array[StringName]:
	var result: Array[StringName] = []
	if feature_hook == null:
		return result
	var values: Array = feature_hook.get(property_name) as Array
	for value: Variant in values:
		if value is StringName:
			result.append(value)
	return result

static func _get_hook_int_array(feature_hook: Resource, property_name: String) -> Array[int]:
	var result: Array[int] = []
	if feature_hook == null:
		return result
	var values: Array = feature_hook.get(property_name) as Array
	for value: Variant in values:
		result.append(int(value))
	return result
