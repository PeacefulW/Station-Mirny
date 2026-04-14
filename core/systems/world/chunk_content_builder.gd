class_name ChunkContentBuilder
extends RefCounted

const ChunkScript = preload("res://core/systems/world/chunk.gd")
const ChunkFinalPacketScript = preload("res://core/systems/world/chunk_final_packet.gd")

const FEATURE_AND_POI_PAYLOAD_KEY: String = "feature_and_poi_payload"
const CHUNK_GEN_SLOW_LOG_THRESHOLD_MS: float = 80.0
const NATIVE_VISUAL_KERNELS_CLASS: StringName = &"ChunkVisualKernels"
const NATIVE_CHUNK_GENERATION_REQUEST_KIND: StringName = &"native_chunk_generation_request_v1"

var _world_context: RefCounted = null
var _terrain_resolver: RefCounted = null
var _balance: WorldGenBalance = null
var _feature_and_poi_payload_cache: RefCounted = null
var _native_generator: RefCounted = null
var _native_visual_kernels: RefCounted = null

func initialize(
	balance_resource: WorldGenBalance,
	world_context: RefCounted,
	terrain_resolver: RefCounted,
	feature_and_poi_payload_cache: RefCounted = null
) -> void:
	_balance = balance_resource
	_world_context = world_context
	_terrain_resolver = terrain_resolver
	_feature_and_poi_payload_cache = feature_and_poi_payload_cache
	if not _balance:
		return
	if WorldGenerator and WorldGenerator.has_method("get_native_chunk_generator"):
		_native_generator = WorldGenerator.get_native_chunk_generator()

func build_chunk(chunk_coord: Vector2i) -> ChunkBuildResult:
	var native_packet: Dictionary = build_chunk_native_data(chunk_coord)
	if native_packet.is_empty():
		return ChunkBuildResult.new()
	return ChunkBuildResult.new().populate_from_surface_packet(native_packet)

func build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary:
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	var base_tile: Vector2i = _chunk_to_tile_origin(canonical_chunk)
	var chunk_size: int = _chunk_size()
	if chunk_size <= 0:
		return {}
	var spawn_tile: Vector2i = _world_context.spawn_tile if _world_context else Vector2i.ZERO
	# Player-reachable surface packets must be self-contained before install.
	if _native_generator != null and _native_generator.has_method("generate_chunk"):
		var native_total_start_usec: int = Time.get_ticks_usec()
		var request_start_usec: int = Time.get_ticks_usec()
		var native_request: Dictionary = _build_native_chunk_generation_request(canonical_chunk, base_tile, chunk_size)
		var request_ms: float = float(Time.get_ticks_usec() - request_start_usec) / 1000.0
		var native_call_start_usec: int = Time.get_ticks_usec()
		var native_result: Dictionary = _native_generator.generate_chunk(canonical_chunk, spawn_tile, native_request)
		var native_call_ms: float = float(Time.get_ticks_usec() - native_call_start_usec) / 1000.0
		if not native_result.is_empty():
			var validate_start_usec: int = Time.get_ticks_usec()
			var native_payload_valid: bool = _validate_native_chunk_payload(native_result, canonical_chunk, chunk_size)
			var validate_ms: float = float(Time.get_ticks_usec() - validate_start_usec) / 1000.0
			if native_payload_valid:
				var feature_and_poi_payload: Dictionary = native_result.get(
					FEATURE_AND_POI_PAYLOAD_KEY,
					ChunkFinalPacketScript.empty_feature_and_poi_payload()
				) as Dictionary
				_publish_feature_and_poi_payload(canonical_chunk, feature_and_poi_payload)
				var prebaked_start_usec: int = Time.get_ticks_usec()
				var prebaked_visual_payload: Dictionary = _build_native_prebaked_visual_payload(
					native_result,
					canonical_chunk,
					base_tile,
					chunk_size
				)
				var prebaked_ms: float = float(Time.get_ticks_usec() - prebaked_start_usec) / 1000.0
				if prebaked_visual_payload.is_empty():
					return _block_legacy_surface_generation_fallback(
						canonical_chunk,
						"missing_native_prebaked_visual_payload"
					)
				native_result.merge(prebaked_visual_payload, true)
				ChunkFinalPacketScript.stamp_surface_packet_metadata(native_result, &"native_chunk_generator")
				if not ChunkFinalPacketScript.validate_surface_packet(
					native_result,
					"ChunkContentBuilder.build_chunk_native_data(%s)" % [canonical_chunk]
				):
					return _block_legacy_surface_generation_fallback(
						canonical_chunk,
						"invalid_surface_final_packet_contract"
					)
				var native_total_ms: float = float(Time.get_ticks_usec() - native_total_start_usec) / 1000.0
				_record_native_chunk_generation_metrics(canonical_chunk, request_ms, native_call_ms, validate_ms, prebaked_ms, native_total_ms)
				if native_total_ms >= CHUNK_GEN_SLOW_LOG_THRESHOLD_MS:
					print("[ChunkGen] slow native generate_chunk %s: %.1f ms (request=%.1f native=%.1f validate=%.1f prebaked=%.1f)" % [
						canonical_chunk,
						native_total_ms,
						request_ms,
						native_call_ms,
						validate_ms,
						prebaked_ms,
					])
				return native_result
	# Legacy GDScript fallback is forbidden in R1; missing native output is a hard failure.
	return _block_legacy_surface_generation_fallback(
		canonical_chunk,
		"missing_or_invalid_native_chunk_generator"
	)

func _block_legacy_surface_generation_fallback(canonical_chunk: Vector2i, reason: String) -> Dictionary:
	var message: String = "Zero-Tolerance Chunk Readiness R1 blocked legacy surface generation fallback for %s (%s). Player-reachable chunks must use native-only generation." % [
		canonical_chunk,
		reason,
	]
	push_error(message)
	assert(false, message)
	return {}

func _build_native_chunk_generation_request(canonical_chunk: Vector2i, base_tile: Vector2i, chunk_size: int) -> Dictionary:
	return {
		"snapshot_kind": NATIVE_CHUNK_GENERATION_REQUEST_KIND,
		"chunk_coord": canonical_chunk,
		"base_tile": base_tile,
		"chunk_size": chunk_size,
	}

func _record_native_chunk_generation_metrics(
	canonical_chunk: Vector2i,
	request_ms: float,
	native_call_ms: float,
	validate_ms: float,
	prebaked_ms: float,
	total_ms: float
) -> void:
	WorldPerfProbe.record("ChunkGen.native_request_ms %s" % [canonical_chunk], request_ms)
	WorldPerfProbe.record("ChunkGen.native_call_ms %s" % [canonical_chunk], native_call_ms)
	WorldPerfProbe.record("ChunkGen.native_validate_ms %s" % [canonical_chunk], validate_ms)
	WorldPerfProbe.record("ChunkGen.native_visual_payload_ms %s" % [canonical_chunk], prebaked_ms)
	WorldPerfProbe.record("ChunkGen.native_total_ms %s" % [canonical_chunk], total_ms)

func build_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	if _terrain_resolver == null:
		return TileGenData.new()
	return _terrain_resolver.build_tile_data(Vector2i(tile_x, tile_y))

func sample_terrain_type(tile_x: int, tile_y: int) -> TileGenData.TerrainType:
	if _terrain_resolver == null:
		return TileGenData.TerrainType.GROUND
	return _terrain_resolver.sample_terrain_type(tile_x, tile_y)

func _build_prebaked_visual_payload(
	native_data: Dictionary,
	canonical_chunk: Vector2i,
	base_tile: Vector2i,
	chunk_size: int
) -> Dictionary:
	var request: Dictionary = _build_prebaked_visual_request(native_data, canonical_chunk, base_tile, chunk_size)
	if request.is_empty():
		return {}
	var helper: RefCounted = _get_native_visual_kernels()
	if helper != null and helper.has_method("build_prebaked_visual_payload"):
		var native_payload: Dictionary = helper.call("build_prebaked_visual_payload", request) as Dictionary
		if not native_payload.is_empty():
			return native_payload
	return ChunkScript.build_prebaked_visual_payload(request)

func _build_native_prebaked_visual_payload(
	native_data: Dictionary,
	canonical_chunk: Vector2i,
	base_tile: Vector2i,
	chunk_size: int
) -> Dictionary:
	var request: Dictionary = _build_prebaked_visual_request(native_data, canonical_chunk, base_tile, chunk_size)
	if request.is_empty():
		return {}
	var helper: RefCounted = _get_native_visual_kernels()
	if helper == null or not helper.has_method("build_prebaked_visual_payload"):
		push_error("ChunkContentBuilder.build_chunk_native_data(): native visual packet builder is unavailable for %s" % [canonical_chunk])
		assert(false, "surface final packet visual payload must be built by native ChunkVisualKernels")
		return {}
	var native_payload: Dictionary = helper.call("build_prebaked_visual_payload", request) as Dictionary
	if native_payload.is_empty():
		push_error("ChunkContentBuilder.build_chunk_native_data(): native visual packet builder returned an empty payload for %s" % [canonical_chunk])
		assert(false, "surface final packet visual payload must be complete before validation")
	return native_payload

func _build_prebaked_visual_request(
	native_data: Dictionary,
	canonical_chunk: Vector2i,
	base_tile: Vector2i,
	chunk_size: int
) -> Dictionary:
	if native_data.is_empty() or chunk_size <= 0:
		return {}
	return {
		"chunk_coord": canonical_chunk,
		"chunk_size": chunk_size,
		"is_underground": false,
		"terrain_bytes": native_data.get("terrain", PackedByteArray()) as PackedByteArray,
		"height_bytes": native_data.get("height", PackedFloat32Array()) as PackedFloat32Array,
		"variation_bytes": native_data.get("variation", PackedByteArray()) as PackedByteArray,
		"biome_bytes": native_data.get("biome", PackedByteArray()) as PackedByteArray,
		"secondary_biome_bytes": native_data.get("secondary_biome", PackedByteArray()) as PackedByteArray,
		"ecotone_values": native_data.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array,
		"terrain_halo": _build_terrain_halo(native_data.get("terrain", PackedByteArray()) as PackedByteArray, base_tile, chunk_size),
		"native_visual_tables": ChunkScript.build_native_visual_tables(),
	}

func _build_terrain_halo(terrain_bytes: PackedByteArray, base_tile: Vector2i, chunk_size: int) -> PackedByteArray:
	var stride: int = chunk_size + 2
	var halo := PackedByteArray()
	halo.resize(stride * stride)
	if terrain_bytes.size() != chunk_size * chunk_size:
		return halo
	for local_y: int in range(-1, chunk_size + 1):
		for local_x: int in range(-1, chunk_size + 1):
			var halo_index: int = (local_y + 1) * stride + (local_x + 1)
			if local_x >= 0 and local_y >= 0 and local_x < chunk_size and local_y < chunk_size:
				halo[halo_index] = terrain_bytes[local_y * chunk_size + local_x]
				continue
			var world_tile: Vector2i = base_tile + Vector2i(local_x, local_y)
			if _world_context != null and _world_context.has_method("canonicalize_tile"):
				world_tile = _world_context.canonicalize_tile(world_tile)
			halo[halo_index] = sample_terrain_type(world_tile.x, world_tile.y)
	return halo

func _get_native_visual_kernels() -> RefCounted:
	if _native_visual_kernels != null:
		return _native_visual_kernels
	if not ClassDB.class_exists(NATIVE_VISUAL_KERNELS_CLASS):
		return null
	_native_visual_kernels = ClassDB.instantiate(NATIVE_VISUAL_KERNELS_CLASS) as RefCounted
	return _native_visual_kernels

func _validate_native_chunk_payload(native_result: Dictionary, canonical_chunk: Vector2i, chunk_size: int) -> bool:
	var tile_count: int = chunk_size * chunk_size
	var required_arrays: Dictionary = {
		"terrain": native_result.get("terrain", PackedByteArray()) as PackedByteArray,
		"height": native_result.get("height", PackedFloat32Array()) as PackedFloat32Array,
		"variation": native_result.get("variation", PackedByteArray()) as PackedByteArray,
		"biome": native_result.get("biome", PackedByteArray()) as PackedByteArray,
		"secondary_biome": native_result.get("secondary_biome", PackedByteArray()) as PackedByteArray,
		"ecotone_values": native_result.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array,
		"flora_density_values": native_result.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array,
		"flora_modulation_values": native_result.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array,
	}
	for key: String in required_arrays.keys():
		var packed: Variant = required_arrays[key]
		if packed.size() == tile_count:
			continue
		push_error(
			"ChunkContentBuilder.build_chunk_native_data(): native payload field `%s` size mismatch for %s (expected %d, got %d)" % [
				key,
				canonical_chunk,
				tile_count,
				packed.size(),
			]
		)
		assert(false, "native chunk payload must stay wire-compatible with the authoritative GDScript shape")
		return false
	return _validate_feature_and_poi_payload(
		native_result.get(FEATURE_AND_POI_PAYLOAD_KEY, {}) as Dictionary,
		canonical_chunk
	)

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

func _validate_feature_and_poi_payload(payload: Dictionary, canonical_chunk: Vector2i) -> bool:
	if payload.is_empty():
		push_error("ChunkContentBuilder.build_chunk_native_data(): `%s` is empty for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
		assert(false, "surface packets must carry explicit feature_and_poi_payload shape from native generation")
		return false
	if not payload.has("placements"):
		push_error("ChunkContentBuilder.build_chunk_native_data(): `%s` is missing `placements` for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
		assert(false, "surface packets must carry explicit feature_and_poi_payload shape from native generation")
		return false
	var placements: Variant = payload.get("placements", [])
	if not (placements is Array):
		push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.placements` must stay an Array for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
		assert(false, "surface packets must carry explicit feature_and_poi_payload shape from native generation")
		return false
	for placement_variant: Variant in placements:
		if not (placement_variant is Dictionary):
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.placements` must contain Dictionaries for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			assert(false, "surface packets must carry serializable feature_and_poi placement records")
			return false
		var placement: Dictionary = placement_variant as Dictionary
		for key: String in ["kind", "id", "candidate_origin", "anchor_tile", "owner_chunk", "footprint_tiles", "debug_marker_kind"]:
			if placement.has(key):
				continue
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.placements` record is missing `%s` for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, key, canonical_chunk])
			assert(false, "surface packets must carry serializable feature_and_poi placement records")
			return false
		if not (placement.get("kind", &"") is StringName):
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.kind` must stay StringName for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			return false
		if not (placement.get("id", &"") is StringName):
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.id` must stay StringName for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			return false
		if not (placement.get("candidate_origin", Vector2i.ZERO) is Vector2i):
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.candidate_origin` must stay Vector2i for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			return false
		if not (placement.get("anchor_tile", Vector2i.ZERO) is Vector2i):
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.anchor_tile` must stay Vector2i for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			return false
		if not (placement.get("owner_chunk", Vector2i.ZERO) is Vector2i):
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.owner_chunk` must stay Vector2i for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			return false
		if not (placement.get("footprint_tiles", []) is Array):
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.footprint_tiles` must stay an Array for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			return false
		for footprint_tile: Variant in placement.get("footprint_tiles", []):
			if footprint_tile is Vector2i:
				continue
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.footprint_tiles` must contain Vector2i values for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			return false
		if not (placement.get("debug_marker_kind", &"") is StringName):
			push_error("ChunkContentBuilder.build_chunk_native_data(): `%s.debug_marker_kind` must stay StringName for %s" % [FEATURE_AND_POI_PAYLOAD_KEY, canonical_chunk])
			return false
	return true

func _publish_feature_and_poi_payload(canonical_chunk: Vector2i, payload: Dictionary) -> void:
	if _feature_and_poi_payload_cache == null:
		return
	if not _feature_and_poi_payload_cache.has_method("store_payload"):
		return
	_feature_and_poi_payload_cache.call("store_payload", canonical_chunk, payload)
