class_name WorldPoiResolver
extends RefCounted

static func resolve_for_origin(candidate_origin: Vector2i, hook_decisions: Array[Dictionary], ctx: WorldComputeContext) -> Array[Dictionary]:
	var placements_by_anchor: Dictionary = {}
	if ctx == null:
		return []
	var canonical_origin: Vector2i = ctx.canonicalize_tile(candidate_origin)
	var resolved_hook_ids: Array[StringName] = _collect_resolved_hook_ids(hook_decisions)
	for poi_resource: Resource in WorldFeatureRegistry.get_all_pois():
		if poi_resource == null:
			continue
		if not _matches_required_feature_hooks(poi_resource, resolved_hook_ids):
			continue
		var candidate: Dictionary = _build_candidate(canonical_origin, poi_resource, ctx)
		if candidate.is_empty():
			continue
		var anchor_tile: Vector2i = candidate.get("anchor_tile", Vector2i.ZERO) as Vector2i
		var existing_candidate: Dictionary = placements_by_anchor.get(anchor_tile, {})
		if existing_candidate.is_empty() or _is_candidate_better(candidate, existing_candidate):
			placements_by_anchor[anchor_tile] = candidate
	return _sorted_placements(placements_by_anchor)

static func _build_candidate(candidate_origin: Vector2i, poi_resource: Resource, ctx: WorldComputeContext) -> Dictionary:
	var anchor_offset: Vector2i = _get_anchor_offset(poi_resource)
	var anchor_tile: Vector2i = ctx.canonicalize_tile(candidate_origin + anchor_offset)
	var owner_chunk: Vector2i = _tile_to_chunk(ctx, anchor_tile)
	var footprint_tiles: Array[Vector2i] = _resolve_footprint_tiles(candidate_origin, poi_resource, ctx)
	if footprint_tiles.is_empty():
		return {}
	if not _footprint_satisfies_constraints(footprint_tiles, poi_resource, ctx):
		return {}
	return {
		"id": _get_poi_id(poi_resource),
		"candidate_origin": candidate_origin,
		"anchor_tile": anchor_tile,
		"owner_chunk": owner_chunk,
		"footprint_tiles": footprint_tiles,
		"debug_marker_kind": _get_debug_marker_kind(poi_resource),
		"priority": _get_priority(poi_resource),
		"tie_break_hash": _hash_for_anchor(ctx.get_world_seed(), anchor_tile, _get_poi_id(poi_resource)),
	}

static func _matches_required_feature_hooks(poi_resource: Resource, resolved_hook_ids: Array[StringName]) -> bool:
	for required_hook_id: StringName in _get_string_name_array(poi_resource, "required_feature_hook_ids"):
		if not resolved_hook_ids.has(required_hook_id):
			return false
	return true

static func _resolve_footprint_tiles(candidate_origin: Vector2i, poi_resource: Resource, ctx: WorldComputeContext) -> Array[Vector2i]:
	var world_tiles: Array[Vector2i] = []
	var seen_tiles: Dictionary = {}
	for footprint_offset: Vector2i in _get_effective_footprint_offsets(poi_resource):
		var footprint_tile: Vector2i = ctx.canonicalize_tile(candidate_origin + footprint_offset)
		if seen_tiles.has(footprint_tile):
			continue
		seen_tiles[footprint_tile] = true
		world_tiles.append(footprint_tile)
	world_tiles.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		if left.y != right.y:
			return left.y < right.y
		return left.x < right.x
	)
	return world_tiles

static func _footprint_satisfies_constraints(footprint_tiles: Array[Vector2i], poi_resource: Resource, ctx: WorldComputeContext) -> bool:
	for footprint_tile: Vector2i in footprint_tiles:
		if not _tile_satisfies_constraints(footprint_tile, poi_resource, ctx):
			return false
	return true

static func _tile_satisfies_constraints(tile_pos: Vector2i, poi_resource: Resource, ctx: WorldComputeContext) -> bool:
	var allowed_biome_ids: Array[StringName] = _get_string_name_array(poi_resource, "allowed_biome_ids")
	if not allowed_biome_ids.is_empty():
		var biome_result: BiomeResult = ctx.get_biome_result_at_tile(tile_pos)
		if biome_result == null or not allowed_biome_ids.has(biome_result.biome_id):
			return false
	var required_structure_tags: Array[StringName] = _get_string_name_array(poi_resource, "required_structure_tags")
	if not required_structure_tags.is_empty():
		var channels: WorldChannels = ctx.sample_world_channels(tile_pos)
		var structure_context: WorldStructureContext = ctx.sample_structure_context(tile_pos, channels)
		var structure_tags: Array[StringName] = _collect_structure_tags(structure_context)
		for required_tag: StringName in required_structure_tags:
			if not structure_tags.has(required_tag):
				return false
	var allowed_terrain_types: Array[int] = _get_int_array(poi_resource, "allowed_terrain_types")
	if not allowed_terrain_types.is_empty():
		if not allowed_terrain_types.has(ctx.get_surface_terrain_type(tile_pos)):
			return false
	return true

static func _is_candidate_better(left: Dictionary, right: Dictionary) -> bool:
	var left_priority: int = int(left.get("priority", 0))
	var right_priority: int = int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	var left_hash: int = int(left.get("tie_break_hash", 0))
	var right_hash: int = int(right.get("tie_break_hash", 0))
	if left_hash != right_hash:
		return left_hash > right_hash
	return str(left.get("id", &"")) < str(right.get("id", &""))

static func _sorted_placements(placements_by_anchor: Dictionary) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	for placement: Dictionary in placements_by_anchor.values():
		placements.append(placement)
	placements.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_anchor: Vector2i = left.get("anchor_tile", Vector2i.ZERO) as Vector2i
		var right_anchor: Vector2i = right.get("anchor_tile", Vector2i.ZERO) as Vector2i
		if left_anchor.y != right_anchor.y:
			return left_anchor.y < right_anchor.y
		if left_anchor.x != right_anchor.x:
			return left_anchor.x < right_anchor.x
		return str(left.get("id", &"")) < str(right.get("id", &""))
	)
	return placements

static func _collect_resolved_hook_ids(hook_decisions: Array[Dictionary]) -> Array[StringName]:
	var resolved_hook_ids: Array[StringName] = []
	for decision: Dictionary in hook_decisions:
		var hook_id: Variant = decision.get("hook_id", &"")
		if hook_id is StringName and not resolved_hook_ids.has(hook_id):
			resolved_hook_ids.append(hook_id)
	return resolved_hook_ids

static func _collect_structure_tags(structure_context: WorldStructureContext) -> Array[StringName]:
	var structure_tags: Array[StringName] = [&"surface"]
	if structure_context == null:
		return structure_tags
	if structure_context.is_ridge_core():
		structure_tags.append(&"ridge")
	if structure_context.mountain_mass >= 0.5:
		structure_tags.append(&"mountain")
	if structure_context.is_river_core():
		structure_tags.append(&"river")
	if structure_context.has_floodplain():
		structure_tags.append(&"floodplain")
	return structure_tags

static func _tile_to_chunk(ctx: WorldComputeContext, tile_pos: Vector2i) -> Vector2i:
	var canonical_tile: Vector2i = ctx.canonicalize_tile(tile_pos)
	var chunk_size: int = ctx.balance.chunk_size_tiles if ctx.balance else 64
	return ctx.canonicalize_chunk_coord(Vector2i(
		floori(float(canonical_tile.x) / float(chunk_size)),
		floori(float(canonical_tile.y) / float(chunk_size))
	))

static func _hash_for_anchor(world_seed: int, anchor_tile: Vector2i, poi_id: StringName) -> int:
	return abs(hash("%d|%d|%d|%s" % [world_seed, anchor_tile.x, anchor_tile.y, str(poi_id)]))

static func _get_effective_footprint_offsets(poi_resource: Resource) -> Array[Vector2i]:
	if poi_resource == null:
		return []
	var result: Array[Vector2i] = []
	if poi_resource.has_method("get_effective_footprint_offsets"):
		var values: Array = poi_resource.call("get_effective_footprint_offsets") as Array
		for value: Variant in values:
			if value is Vector2i:
				result.append(value)
		return result
	for value: Variant in poi_resource.get("footprint_tiles") as Array:
		if value is Vector2i:
			result.append(value)
	if result.is_empty():
		result.append(_get_anchor_offset(poi_resource))
	return result

static func _get_poi_id(poi_resource: Resource) -> StringName:
	if poi_resource == null:
		return &""
	return poi_resource.get("id") as StringName

static func _get_anchor_offset(poi_resource: Resource) -> Vector2i:
	if poi_resource == null:
		return Vector2i.ZERO
	return poi_resource.get("anchor_offset") as Vector2i

static func _get_priority(poi_resource: Resource) -> int:
	if poi_resource == null:
		return 0
	return int(poi_resource.get("priority"))

static func _get_debug_marker_kind(poi_resource: Resource) -> StringName:
	if poi_resource == null:
		return &""
	return poi_resource.get("debug_marker_kind") as StringName

static func _get_string_name_array(poi_resource: Resource, property_name: String) -> Array[StringName]:
	var result: Array[StringName] = []
	if poi_resource == null:
		return result
	for value: Variant in poi_resource.get(property_name) as Array:
		if value is StringName:
			result.append(value)
	return result

static func _get_int_array(poi_resource: Resource, property_name: String) -> Array[int]:
	var result: Array[int] = []
	if poi_resource == null:
		return result
	for value: Variant in poi_resource.get(property_name) as Array:
		result.append(int(value))
	return result
