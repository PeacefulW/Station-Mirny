class_name ChunkContentBuilder
extends RefCounted

const WorldFeatureHookResolverScript = preload("res://core/systems/world/world_feature_hook_resolver.gd")
const WorldPoiResolverScript = preload("res://core/systems/world/world_poi_resolver.gd")

const FEATURE_AND_POI_PAYLOAD_KEY: String = "feature_and_poi_payload"
const PLACEMENTS_KEY: String = "placements"
const FEATURE_KIND: StringName = &"feature"
const POI_KIND: StringName = &"poi"
const CHUNK_GEN_SLOW_LOG_THRESHOLD_MS: float = 80.0

var _world_context: RefCounted = null
var _terrain_resolver: RefCounted = null
var _balance: WorldGenBalance = null
var _feature_and_poi_payload_cache: RefCounted = null
var _all_pois_snapshot: Array[Resource] = []
var _native_generator: RefCounted = null

func initialize(
	balance_resource: WorldGenBalance,
	world_context: RefCounted,
	terrain_resolver: RefCounted,
	feature_and_poi_payload_cache: RefCounted = null,
	all_pois: Array[Resource] = []
) -> void:
	_balance = balance_resource
	_world_context = world_context
	_terrain_resolver = terrain_resolver
	_feature_and_poi_payload_cache = feature_and_poi_payload_cache
	_all_pois_snapshot = all_pois
	if not _balance:
		return
	if WorldGenerator and WorldGenerator.has_method("get_native_chunk_generator"):
		_native_generator = WorldGenerator.get_native_chunk_generator()

func build_chunk(chunk_coord: Vector2i) -> ChunkBuildResult:
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	var base_tile: Vector2i = _chunk_to_tile_origin(canonical_chunk)
	var result: ChunkBuildResult = ChunkBuildResult.new().initialize(canonical_chunk, _chunk_size(), base_tile)
	if not result.is_valid():
		return result
	var chunk_size: int = result.chunk_size
	var feature_and_poi_payload: Dictionary = _build_feature_and_poi_payload(canonical_chunk, base_tile, chunk_size)
	_publish_feature_and_poi_payload(canonical_chunk, feature_and_poi_payload)
	var spawn_tile: Vector2i = _world_context.spawn_tile if _world_context else Vector2i.ZERO
	var tile_data: TileGenData = TileGenData.new()
	var canonical_tile: Vector2i = base_tile
	var row_index: int = 0
	for local_y: int in range(chunk_size):
		canonical_tile.x = base_tile.x
		canonical_tile.y = base_tile.y + local_y
		for local_x: int in range(chunk_size):
			var index: int = row_index + local_x
			_terrain_resolver.populate_chunk_build_data(canonical_tile, spawn_tile, tile_data)
			result.set_tile(
				index,
				tile_data.terrain,
				tile_data.height,
				tile_data.local_variation_id,
				tile_data.biome_palette_index,
				tile_data.flora_density,
				tile_data.flora_modulation,
				tile_data.secondary_biome_palette_index,
				tile_data.ecotone_factor
			)
			canonical_tile.x += 1
		row_index += chunk_size
	result.feature_and_poi_payload = feature_and_poi_payload
	return result

func build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary:
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	var base_tile: Vector2i = _chunk_to_tile_origin(canonical_chunk)
	var chunk_size: int = _chunk_size()
	if chunk_size <= 0:
		return {}
	var spawn_tile: Vector2i = _world_context.spawn_tile if _world_context else Vector2i.ZERO
	# Try native C++ path — skip expensive feature/POI computation on worker threads.
	# Feature/POI payload is deferred to main-thread cache population.
	if _native_generator != null and _native_generator.has_method("generate_chunk"):
		var native_start_usec: int = Time.get_ticks_usec()
		var native_result: Dictionary = _native_generator.generate_chunk(canonical_chunk, spawn_tile)
		var native_ms: float = float(Time.get_ticks_usec() - native_start_usec) / 1000.0
		if not native_result.is_empty():
			native_result[FEATURE_AND_POI_PAYLOAD_KEY] = _empty_feature_and_poi_payload()
			if native_ms >= CHUNK_GEN_SLOW_LOG_THRESHOLD_MS:
				print("[ChunkGen] slow native generate_chunk %s: %.1f ms" % [canonical_chunk, native_ms])
			return native_result
	# GDScript fallback — compute feature/POI here
	var feature_and_poi_payload: Dictionary = _build_feature_and_poi_payload(canonical_chunk, base_tile, chunk_size)
	_publish_feature_and_poi_payload(canonical_chunk, feature_and_poi_payload)
	# GDScript fallback
	var tile_count: int = chunk_size * chunk_size
	var terrain := PackedByteArray()
	var height := PackedFloat32Array()
	var variation := PackedByteArray()
	var biome := PackedByteArray()
	var secondary_biome := PackedByteArray()
	var ecotone_values := PackedFloat32Array()
	var flora_density_values := PackedFloat32Array()
	var flora_modulation_values := PackedFloat32Array()
	terrain.resize(tile_count)
	height.resize(tile_count)
	variation.resize(tile_count)
	biome.resize(tile_count)
	secondary_biome.resize(tile_count)
	ecotone_values.resize(tile_count)
	flora_density_values.resize(tile_count)
	flora_modulation_values.resize(tile_count)
	var tile_data: TileGenData = TileGenData.new()
	var canonical_tile: Vector2i = base_tile
	var row_index: int = 0
	for local_y: int in range(chunk_size):
		canonical_tile.x = base_tile.x
		canonical_tile.y = base_tile.y + local_y
		for local_x: int in range(chunk_size):
			var index: int = row_index + local_x
			_terrain_resolver.populate_chunk_build_data(canonical_tile, spawn_tile, tile_data)
			terrain[index] = tile_data.terrain
			height[index] = tile_data.height
			variation[index] = tile_data.local_variation_id
			biome[index] = tile_data.biome_palette_index
			secondary_biome[index] = tile_data.secondary_biome_palette_index
			ecotone_values[index] = tile_data.ecotone_factor
			flora_density_values[index] = tile_data.flora_density
			flora_modulation_values[index] = tile_data.flora_modulation
			canonical_tile.x += 1
		row_index += chunk_size
	return {
		"chunk_coord": canonical_chunk,
		"canonical_chunk_coord": canonical_chunk,
		"base_tile": base_tile,
		"chunk_size": chunk_size,
		"terrain": terrain,
		"height": height,
		"variation": variation,
		"biome": biome,
		"secondary_biome": secondary_biome,
		"ecotone_values": ecotone_values,
		"flora_density_values": flora_density_values,
		"flora_modulation_values": flora_modulation_values,
		FEATURE_AND_POI_PAYLOAD_KEY: feature_and_poi_payload,
	}

func build_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	if _terrain_resolver == null:
		return TileGenData.new()
	return _terrain_resolver.build_tile_data(Vector2i(tile_x, tile_y))

func sample_terrain_type(tile_x: int, tile_y: int) -> TileGenData.TerrainType:
	if _terrain_resolver == null:
		return TileGenData.TerrainType.GROUND
	return _terrain_resolver.sample_terrain_type(tile_x, tile_y)

func _chunk_size() -> int:
	return _balance.chunk_size_tiles if _balance else 0

func _canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	if _terrain_resolver:
		return _terrain_resolver.canonicalize_chunk_coord(chunk_coord)
	return chunk_coord

func _chunk_to_tile_origin(chunk_coord: Vector2i) -> Vector2i:
	if _terrain_resolver:
		return _terrain_resolver.chunk_to_tile_origin(chunk_coord)
	return Vector2i.ZERO

func _build_feature_and_poi_payload(canonical_chunk: Vector2i, base_tile: Vector2i, chunk_size: int) -> Dictionary:
	if _world_context == null or chunk_size <= 0:
		return _empty_feature_and_poi_payload()
	if _feature_and_poi_payload_cache != null \
		and _feature_and_poi_payload_cache.has_method("has_payload") \
		and _feature_and_poi_payload_cache.call("has_payload", canonical_chunk):
		return _feature_and_poi_payload_cache.call("get_payload", canonical_chunk) as Dictionary
	var placements: Array[Dictionary] = []
	var hook_decisions_by_origin: Dictionary = {}
	var poi_placements_by_origin: Dictionary = {}
	var anchor_winner_cache: Dictionary = {}
	var hook_id_cache_by_origin: Dictionary = {}
	var candidate_cache: Dictionary = {}
	_append_feature_payload_records(placements, base_tile, chunk_size, hook_decisions_by_origin)
	_append_poi_payload_records(
		placements,
		canonical_chunk,
		base_tile,
		chunk_size,
		hook_decisions_by_origin,
		poi_placements_by_origin,
		anchor_winner_cache,
		hook_id_cache_by_origin,
		candidate_cache
	)
	_sort_payload_placements(placements)
	return {
		PLACEMENTS_KEY: placements,
	}

func _append_feature_payload_records(
	placements: Array[Dictionary],
	base_tile: Vector2i,
	chunk_size: int,
	hook_decisions_by_origin: Dictionary
) -> void:
	for local_y: int in range(chunk_size):
		for local_x: int in range(chunk_size):
			var candidate_origin: Vector2i = _world_context.canonicalize_tile(base_tile + Vector2i(local_x, local_y))
			var hook_decisions: Array[Dictionary] = _get_feature_hook_decisions(candidate_origin, hook_decisions_by_origin)
			for decision: Dictionary in hook_decisions:
				var serialized_decision: Dictionary = _serialize_feature_decision(decision)
				if serialized_decision.is_empty():
					continue
				placements.append(serialized_decision)

func _append_poi_payload_records(
	placements: Array[Dictionary],
	canonical_chunk: Vector2i,
	base_tile: Vector2i,
	chunk_size: int,
	hook_decisions_by_origin: Dictionary,
	poi_placements_by_origin: Dictionary,
	anchor_winner_cache: Dictionary,
	hook_id_cache_by_origin: Dictionary,
	candidate_cache: Dictionary
) -> void:
	var emitted_placement_keys: Dictionary = {}
	for candidate_origin: Vector2i in _collect_candidate_origins_for_chunk_anchors(base_tile, chunk_size):
		var hook_decisions: Array[Dictionary] = _get_feature_hook_decisions(candidate_origin, hook_decisions_by_origin)
		var poi_placements: Array[Dictionary] = _get_poi_placements(
			candidate_origin,
			hook_decisions,
			poi_placements_by_origin,
			anchor_winner_cache,
			hook_id_cache_by_origin,
			candidate_cache
		)
		for placement: Dictionary in poi_placements:
			var owner_chunk: Vector2i = placement.get("owner_chunk", Vector2i.ZERO) as Vector2i
			if owner_chunk != canonical_chunk:
				continue
			var serialized_placement: Dictionary = _serialize_poi_placement(placement)
			if serialized_placement.is_empty():
				continue
			var placement_key: String = _placement_key(serialized_placement)
			if emitted_placement_keys.has(placement_key):
				continue
			emitted_placement_keys[placement_key] = true
			placements.append(serialized_placement)

func _collect_candidate_origins_for_chunk_anchors(base_tile: Vector2i, chunk_size: int) -> Array[Vector2i]:
	var candidate_origins: Array[Vector2i] = []
	var seen_origins: Dictionary = {}
	var all_pois: Array[Resource] = _get_all_pois()
	if all_pois.is_empty():
		return candidate_origins
	var unique_anchor_offsets: Array[Vector2i] = _collect_unique_poi_anchor_offsets(all_pois)
	if unique_anchor_offsets.is_empty():
		return candidate_origins
	for local_y: int in range(chunk_size):
		for local_x: int in range(chunk_size):
			var anchor_tile: Vector2i = _world_context.canonicalize_tile(base_tile + Vector2i(local_x, local_y))
			for anchor_offset: Vector2i in unique_anchor_offsets:
				var candidate_origin: Vector2i = _world_context.canonicalize_tile(anchor_tile - anchor_offset)
				if seen_origins.has(candidate_origin):
					continue
				seen_origins[candidate_origin] = true
				candidate_origins.append(candidate_origin)
	candidate_origins.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		if left.y != right.y:
			return left.y < right.y
		return left.x < right.x
	)
	return candidate_origins

func _get_feature_hook_decisions(candidate_origin: Vector2i, hook_decisions_by_origin: Dictionary) -> Array[Dictionary]:
	var canonical_origin: Vector2i = _world_context.canonicalize_tile(candidate_origin)
	if hook_decisions_by_origin.has(canonical_origin):
		return hook_decisions_by_origin.get(canonical_origin, [])
	var hook_decisions: Array[Dictionary] = WorldFeatureHookResolverScript.resolve_for_origin(canonical_origin, _world_context)
	hook_decisions_by_origin[canonical_origin] = hook_decisions
	return hook_decisions

func _get_poi_placements(
	candidate_origin: Vector2i,
	hook_decisions: Array[Dictionary],
	poi_placements_by_origin: Dictionary,
	anchor_winner_cache: Dictionary,
	hook_id_cache_by_origin: Dictionary,
	candidate_cache: Dictionary
) -> Array[Dictionary]:
	var canonical_origin: Vector2i = _world_context.canonicalize_tile(candidate_origin)
	if poi_placements_by_origin.has(canonical_origin):
		return poi_placements_by_origin.get(canonical_origin, [])
	var poi_placements: Array[Dictionary] = WorldPoiResolverScript.resolve_for_origin(
		canonical_origin,
		hook_decisions,
		_world_context,
		_all_pois_snapshot,
		anchor_winner_cache,
		hook_id_cache_by_origin,
		candidate_cache
	)
	poi_placements_by_origin[canonical_origin] = poi_placements
	return poi_placements

func _collect_unique_poi_anchor_offsets(all_pois: Array[Resource]) -> Array[Vector2i]:
	var unique_offsets: Array[Vector2i] = []
	var seen_offsets: Dictionary = {}
	for poi_resource: Resource in all_pois:
		if poi_resource == null:
			continue
		var anchor_offset: Vector2i = _get_poi_anchor_offset(poi_resource)
		if seen_offsets.has(anchor_offset):
			continue
		seen_offsets[anchor_offset] = true
		unique_offsets.append(anchor_offset)
	return unique_offsets

func _serialize_feature_decision(decision: Dictionary) -> Dictionary:
	var feature_id: StringName = decision.get("hook_id", &"") as StringName
	if feature_id == &"":
		return {}
	var candidate_origin: Vector2i = decision.get("candidate_origin", Vector2i.ZERO) as Vector2i
	var anchor_tile: Vector2i = _world_context.canonicalize_tile(candidate_origin)
	var footprint_tiles: Array[Vector2i] = [anchor_tile]
	return {
		"kind": FEATURE_KIND,
		"id": feature_id,
		"candidate_origin": anchor_tile,
		"anchor_tile": anchor_tile,
		"owner_chunk": _tile_to_chunk(anchor_tile),
		"footprint_tiles": footprint_tiles,
		"debug_marker_kind": decision.get("debug_marker_kind", &"") as StringName,
	}

func _serialize_poi_placement(placement: Dictionary) -> Dictionary:
	var poi_id: StringName = placement.get("id", &"") as StringName
	if poi_id == &"":
		return {}
	var footprint_tiles: Array[Vector2i] = []
	for footprint_tile: Variant in placement.get("footprint_tiles", []):
		if footprint_tile is Vector2i:
			footprint_tiles.append(footprint_tile)
	return {
		"kind": POI_KIND,
		"id": poi_id,
		"candidate_origin": placement.get("candidate_origin", Vector2i.ZERO) as Vector2i,
		"anchor_tile": placement.get("anchor_tile", Vector2i.ZERO) as Vector2i,
		"owner_chunk": placement.get("owner_chunk", Vector2i.ZERO) as Vector2i,
		"footprint_tiles": footprint_tiles,
		"debug_marker_kind": placement.get("debug_marker_kind", &"") as StringName,
	}

func _sort_payload_placements(placements: Array[Dictionary]) -> void:
	placements.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_anchor: Vector2i = left.get("anchor_tile", Vector2i.ZERO) as Vector2i
		var right_anchor: Vector2i = right.get("anchor_tile", Vector2i.ZERO) as Vector2i
		if left_anchor.y != right_anchor.y:
			return left_anchor.y < right_anchor.y
		if left_anchor.x != right_anchor.x:
			return left_anchor.x < right_anchor.x
		var left_kind: String = str(left.get("kind", &""))
		var right_kind: String = str(right.get("kind", &""))
		if left_kind != right_kind:
			return left_kind < right_kind
		var left_id: String = str(left.get("id", &""))
		var right_id: String = str(right.get("id", &""))
		if left_id != right_id:
			return left_id < right_id
		var left_origin: Vector2i = left.get("candidate_origin", Vector2i.ZERO) as Vector2i
		var right_origin: Vector2i = right.get("candidate_origin", Vector2i.ZERO) as Vector2i
		if left_origin.y != right_origin.y:
			return left_origin.y < right_origin.y
		return left_origin.x < right_origin.x
	)

func _placement_key(placement: Dictionary) -> String:
	var anchor_tile: Vector2i = placement.get("anchor_tile", Vector2i.ZERO) as Vector2i
	var candidate_origin: Vector2i = placement.get("candidate_origin", Vector2i.ZERO) as Vector2i
	return "%s|%s|%d|%d|%d|%d" % [
		str(placement.get("kind", &"")),
		str(placement.get("id", &"")),
		anchor_tile.x,
		anchor_tile.y,
		candidate_origin.x,
		candidate_origin.y,
	]

func _tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	var canonical_tile: Vector2i = _world_context.canonicalize_tile(tile_pos)
	var chunk_size: int = _chunk_size()
	if chunk_size <= 0:
		return Vector2i.ZERO
	return _world_context.canonicalize_chunk_coord(Vector2i(
		floori(float(canonical_tile.x) / float(chunk_size)),
		floori(float(canonical_tile.y) / float(chunk_size))
	))

func _get_poi_anchor_offset(poi_resource: Resource) -> Vector2i:
	if poi_resource == null:
		return Vector2i.ZERO
	return poi_resource.get("anchor_offset") as Vector2i

func _get_all_pois() -> Array[Resource]:
	return _all_pois_snapshot

func _empty_feature_and_poi_payload() -> Dictionary:
	return {
		PLACEMENTS_KEY: [],
	}

func _publish_feature_and_poi_payload(canonical_chunk: Vector2i, payload: Dictionary) -> void:
	if _feature_and_poi_payload_cache == null:
		return
	if not _feature_and_poi_payload_cache.has_method("store_payload"):
		return
	_feature_and_poi_payload_cache.call("store_payload", canonical_chunk, payload)
