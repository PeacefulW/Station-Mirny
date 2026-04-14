class_name ChunkFinalPacket
extends RefCounted

const PACKET_KIND_KEY: String = "packet_kind"
const PACKET_VERSION_KEY: String = "packet_version"
const GENERATOR_VERSION_KEY: String = "generator_version"
const GENERATION_SOURCE_KEY: String = "generation_source"
const Z_LEVEL_KEY: String = "z_level"
const FEATURE_AND_POI_PAYLOAD_KEY: String = "feature_and_poi_payload"
const FLORA_PLACEMENTS_KEY: String = "flora_placements"
const FLORA_PAYLOAD_KEY: String = "flora_payload"
const PLACEMENTS_KEY: String = "placements"
const RENDER_PACKET_KEY: String = "render_packet"

const SURFACE_PACKET_KIND: StringName = &"frontier_surface_final_packet"
const SURFACE_PACKET_VERSION: int = 1
const SURFACE_GENERATOR_VERSION: int = 1

const SURFACE_REQUIRED_SCALAR_KEYS: Array[String] = [
	"chunk_coord",
	"canonical_chunk_coord",
	"base_tile",
	"chunk_size",
	PACKET_KIND_KEY,
	PACKET_VERSION_KEY,
	GENERATOR_VERSION_KEY,
	GENERATION_SOURCE_KEY,
	Z_LEVEL_KEY,
]

const SURFACE_REQUIRED_TILED_KEYS: Array[String] = [
	"terrain",
	"height",
	"variation",
	"biome",
	"secondary_biome",
	"ecotone_values",
	"flora_density_values",
	"flora_modulation_values",
	"rock_visual_class",
	"ground_face_atlas",
	"cover_mask",
	"cliff_overlay",
	"variant_id",
	"alt_id",
]

static func empty_feature_and_poi_payload() -> Dictionary:
	return {
		PLACEMENTS_KEY: [],
	}

static func _validate_feature_and_poi_payload(payload: Dictionary, context: String) -> bool:
	if payload.is_empty():
		push_error("%s: `%s` must keep the explicit placements shape" % [context, FEATURE_AND_POI_PAYLOAD_KEY])
		return false
	if not payload.has(PLACEMENTS_KEY):
		push_error("%s: `%s` is missing `%s`" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
		return false
	if not (payload.get(PLACEMENTS_KEY, []) is Array):
		push_error("%s: `%s.%s` must stay an Array" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
		return false
	for placement_variant: Variant in payload.get(PLACEMENTS_KEY, []):
		if not (placement_variant is Dictionary):
			push_error("%s: `%s.%s` must contain Dictionaries" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
		var placement: Dictionary = placement_variant as Dictionary
		for key: String in ["kind", "id", "candidate_origin", "anchor_tile", "owner_chunk", "footprint_tiles", "debug_marker_kind"]:
			if placement.has(key):
				continue
			push_error("%s: `%s.%s` record is missing `%s`" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY, key])
			return false
		if not (placement.get("kind", &"") is StringName):
			push_error("%s: `%s.%s.kind` must stay StringName" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
		if not (placement.get("id", &"") is StringName):
			push_error("%s: `%s.%s.id` must stay StringName" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
		if not (placement.get("candidate_origin", Vector2i.ZERO) is Vector2i):
			push_error("%s: `%s.%s.candidate_origin` must stay Vector2i" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
		if not (placement.get("anchor_tile", Vector2i.ZERO) is Vector2i):
			push_error("%s: `%s.%s.anchor_tile` must stay Vector2i" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
		if not (placement.get("owner_chunk", Vector2i.ZERO) is Vector2i):
			push_error("%s: `%s.%s.owner_chunk` must stay Vector2i" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
		if not (placement.get("footprint_tiles", []) is Array):
			push_error("%s: `%s.%s.footprint_tiles` must stay an Array" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
		for footprint_tile: Variant in placement.get("footprint_tiles", []):
			if footprint_tile is Vector2i:
				continue
			push_error("%s: `%s.%s.footprint_tiles` must contain Vector2i values" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
		if not (placement.get("debug_marker_kind", &"") is StringName):
			push_error("%s: `%s.%s.debug_marker_kind` must stay StringName" % [context, FEATURE_AND_POI_PAYLOAD_KEY, PLACEMENTS_KEY])
			return false
	return true

static func stamp_surface_packet_metadata(packet: Dictionary, generation_source: StringName) -> void:
	packet[PACKET_KIND_KEY] = SURFACE_PACKET_KIND
	packet[PACKET_VERSION_KEY] = SURFACE_PACKET_VERSION
	packet[GENERATOR_VERSION_KEY] = SURFACE_GENERATOR_VERSION
	packet[Z_LEVEL_KEY] = 0
	packet[GENERATION_SOURCE_KEY] = generation_source
	if not packet.has(FLORA_PLACEMENTS_KEY):
		packet[FLORA_PLACEMENTS_KEY] = []
	if not packet.has(FEATURE_AND_POI_PAYLOAD_KEY):
		packet[FEATURE_AND_POI_PAYLOAD_KEY] = empty_feature_and_poi_payload()

static func validate_surface_packet(packet: Dictionary, context: String = "ChunkFinalPacket.validate_surface_packet") -> bool:
	if packet.is_empty():
		push_error("%s: surface final packet is empty" % [context])
		return false
	for key: String in SURFACE_REQUIRED_SCALAR_KEYS:
		if packet.has(key):
			continue
		push_error("%s: missing required surface final packet field `%s`" % [context, key])
		return false
	if (packet.get(PACKET_KIND_KEY, &"") as StringName) != SURFACE_PACKET_KIND:
		push_error("%s: unexpected `%s` value `%s`" % [context, PACKET_KIND_KEY, str(packet.get(PACKET_KIND_KEY, &""))])
		return false
	if int(packet.get(PACKET_VERSION_KEY, -1)) != SURFACE_PACKET_VERSION:
		push_error("%s: unexpected `%s` value `%s`" % [context, PACKET_VERSION_KEY, str(packet.get(PACKET_VERSION_KEY, -1))])
		return false
	if int(packet.get(GENERATOR_VERSION_KEY, -1)) != SURFACE_GENERATOR_VERSION:
		push_error("%s: unexpected `%s` value `%s`" % [context, GENERATOR_VERSION_KEY, str(packet.get(GENERATOR_VERSION_KEY, -1))])
		return false
	if int(packet.get(Z_LEVEL_KEY, 999999)) != 0:
		push_error("%s: surface final packet must stay on z_level 0" % [context])
		return false
	if str(packet.get(GENERATION_SOURCE_KEY, "")).strip_edges().is_empty():
		push_error("%s: `%s` must stay non-empty for provenance" % [context, GENERATION_SOURCE_KEY])
		return false
	var chunk_size: int = int(packet.get("chunk_size", 0))
	if chunk_size <= 0:
		push_error("%s: invalid chunk_size `%s`" % [context, str(packet.get("chunk_size", 0))])
		return false
	var tile_count: int = chunk_size * chunk_size
	for key: String in SURFACE_REQUIRED_TILED_KEYS:
		if not packet.has(key):
			push_error("%s: missing required tiled surface final packet field `%s`" % [context, key])
			return false
		var packed: Variant = packet.get(key, null)
		var packed_size: int = packed.size() if packed != null else -1
		if packed == null or packed_size != tile_count:
			push_error(
				"%s: surface final packet field `%s` size mismatch (expected %d, got %d)" % [
					context,
					key,
					tile_count,
					packed_size,
				]
			)
			return false
	if not packet.has(FLORA_PLACEMENTS_KEY):
		push_error("%s: missing `%s`" % [context, FLORA_PLACEMENTS_KEY])
		return false
	if not (packet.get(FLORA_PLACEMENTS_KEY, []) is Array):
		push_error("%s: `%s` must stay an Array" % [context, FLORA_PLACEMENTS_KEY])
		return false
	var feature_and_poi_payload: Dictionary = packet.get(FEATURE_AND_POI_PAYLOAD_KEY, {}) as Dictionary
	if not _validate_feature_and_poi_payload(feature_and_poi_payload, context):
		return false
	return true

static func validate_terminal_surface_packet(packet: Dictionary, context: String = "ChunkFinalPacket.validate_terminal_surface_packet") -> bool:
	if not validate_surface_packet(packet, context):
		return false
	var flora_placements: Array = packet.get(FLORA_PLACEMENTS_KEY, []) as Array
	if flora_placements.is_empty():
		return true
	if not packet.has(FLORA_PAYLOAD_KEY):
		push_error("%s: `%s` is required when `%s` contains placements" % [context, FLORA_PAYLOAD_KEY, FLORA_PLACEMENTS_KEY])
		return false
	var flora_payload: Dictionary = packet.get(FLORA_PAYLOAD_KEY, {}) as Dictionary
	if flora_payload.is_empty():
		push_error("%s: `%s` must not be empty when `%s` contains placements" % [context, FLORA_PAYLOAD_KEY, FLORA_PLACEMENTS_KEY])
		return false
	if (flora_payload.get("chunk_coord", Vector2i.ZERO) as Vector2i) != (packet.get("canonical_chunk_coord", Vector2i.ZERO) as Vector2i):
		push_error("%s: `%s.chunk_coord` must match packet canonical chunk coord" % [context, FLORA_PAYLOAD_KEY])
		return false
	if int(flora_payload.get("chunk_size", 0)) != int(packet.get("chunk_size", 0)):
		push_error("%s: `%s.chunk_size` must match packet chunk_size" % [context, FLORA_PAYLOAD_KEY])
		return false
	var payload_placements: Array = flora_payload.get(PLACEMENTS_KEY, []) as Array
	if payload_placements.size() != flora_placements.size():
		push_error("%s: `%s.%s` size mismatch (expected %d, got %d)" % [
			context,
			FLORA_PAYLOAD_KEY,
			PLACEMENTS_KEY,
			flora_placements.size(),
			payload_placements.size(),
		])
		return false
	if not flora_payload.has(RENDER_PACKET_KEY) or (flora_payload.get(RENDER_PACKET_KEY, {}) as Dictionary).is_empty():
		push_error("%s: `%s.%s` must be prebuilt before terminal surface publication" % [context, FLORA_PAYLOAD_KEY, RENDER_PACKET_KEY])
		return false
	if int(flora_payload.get("render_packet_tile_size", 0)) <= 0:
		push_error("%s: `%s.render_packet_tile_size` must be positive" % [context, FLORA_PAYLOAD_KEY])
		return false
	return true

static func duplicate_surface_packet(packet: Dictionary) -> Dictionary:
	if packet.is_empty():
		return {}
	return {
		PACKET_KIND_KEY: packet.get(PACKET_KIND_KEY, SURFACE_PACKET_KIND) as StringName,
		PACKET_VERSION_KEY: int(packet.get(PACKET_VERSION_KEY, SURFACE_PACKET_VERSION)),
		GENERATOR_VERSION_KEY: int(packet.get(GENERATOR_VERSION_KEY, SURFACE_GENERATOR_VERSION)),
		GENERATION_SOURCE_KEY: packet.get(GENERATION_SOURCE_KEY, &"") as StringName,
		Z_LEVEL_KEY: int(packet.get(Z_LEVEL_KEY, 0)),
		"chunk_coord": packet.get("chunk_coord", Vector2i.ZERO) as Vector2i,
		"canonical_chunk_coord": packet.get("canonical_chunk_coord", Vector2i.ZERO) as Vector2i,
		"base_tile": packet.get("base_tile", Vector2i.ZERO) as Vector2i,
		"chunk_size": int(packet.get("chunk_size", 0)),
		"terrain": (packet.get("terrain", PackedByteArray()) as PackedByteArray).duplicate(),
		"height": (packet.get("height", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"variation": (packet.get("variation", PackedByteArray()) as PackedByteArray).duplicate(),
		"biome": (packet.get("biome", PackedByteArray()) as PackedByteArray).duplicate(),
		"secondary_biome": (packet.get("secondary_biome", PackedByteArray()) as PackedByteArray).duplicate(),
		"ecotone_values": (packet.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"flora_density_values": (packet.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"flora_modulation_values": (packet.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"rock_visual_class": (packet.get("rock_visual_class", PackedByteArray()) as PackedByteArray).duplicate(),
		"ground_face_atlas": (packet.get("ground_face_atlas", PackedInt32Array()) as PackedInt32Array).duplicate(),
		"cover_mask": (packet.get("cover_mask", PackedInt32Array()) as PackedInt32Array).duplicate(),
		"cliff_overlay": (packet.get("cliff_overlay", PackedByteArray()) as PackedByteArray).duplicate(),
		"variant_id": (packet.get("variant_id", PackedByteArray()) as PackedByteArray).duplicate(),
		"alt_id": (packet.get("alt_id", PackedInt32Array()) as PackedInt32Array).duplicate(),
		FLORA_PLACEMENTS_KEY: (packet.get(FLORA_PLACEMENTS_KEY, []) as Array).duplicate(true),
		FLORA_PAYLOAD_KEY: (packet.get(FLORA_PAYLOAD_KEY, {}) as Dictionary).duplicate(true),
		FEATURE_AND_POI_PAYLOAD_KEY: (packet.get(FEATURE_AND_POI_PAYLOAD_KEY, empty_feature_and_poi_payload()) as Dictionary).duplicate(true),
	}
