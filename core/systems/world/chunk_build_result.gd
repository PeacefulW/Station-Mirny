class_name ChunkBuildResult
extends RefCounted

const ChunkFinalPacketScript = preload("res://core/systems/world/chunk_final_packet.gd")
const FEATURE_AND_POI_PAYLOAD_KEY: String = "feature_and_poi_payload"
const PLACEMENTS_KEY: String = "placements"

var chunk_coord: Vector2i = Vector2i.ZERO
var canonical_chunk_coord: Vector2i = Vector2i.ZERO
var chunk_size: int = 0
var base_tile: Vector2i = Vector2i.ZERO
var terrain: PackedByteArray = PackedByteArray()
var height: PackedFloat32Array = PackedFloat32Array()
var variation: PackedByteArray = PackedByteArray()
var biome: PackedByteArray = PackedByteArray()
var secondary_biome: PackedByteArray = PackedByteArray()
var ecotone_values: PackedFloat32Array = PackedFloat32Array()
var flora_density_values: PackedFloat32Array = PackedFloat32Array()
var flora_modulation_values: PackedFloat32Array = PackedFloat32Array()
var rock_visual_class: PackedByteArray = PackedByteArray()
var ground_face_atlas: PackedInt32Array = PackedInt32Array()
var cover_mask: PackedInt32Array = PackedInt32Array()
var cliff_overlay: PackedByteArray = PackedByteArray()
var variant_id: PackedByteArray = PackedByteArray()
var alt_id: PackedInt32Array = PackedInt32Array()
var feature_and_poi_payload: Dictionary = _empty_feature_and_poi_payload()

func initialize(coord: Vector2i, size: int, chunk_base_tile: Vector2i = Vector2i.ZERO) -> ChunkBuildResult:
	chunk_coord = coord
	canonical_chunk_coord = coord
	chunk_size = maxi(0, size)
	base_tile = chunk_base_tile
	feature_and_poi_payload = _empty_feature_and_poi_payload()
	var tile_count: int = chunk_size * chunk_size
	terrain.resize(tile_count)
	height.resize(tile_count)
	variation.resize(tile_count)
	biome.resize(tile_count)
	secondary_biome.resize(tile_count)
	ecotone_values.resize(tile_count)
	flora_density_values.resize(tile_count)
	flora_modulation_values.resize(tile_count)
	if tile_count > 0:
		var default_palette_index: int = BiomeRegistry.get_default_palette_index() if BiomeRegistry else 0
		variation.fill(0)
		biome.fill(default_palette_index)
		secondary_biome.fill(default_palette_index)
	return self

func set_tile(
	index: int,
	terrain_type: int,
	height_value: float,
	variation_id: int = 0,
	biome_id: int = 0,
	p_flora_density: float = 0.5,
	p_flora_mod: float = 0.0,
	p_secondary_biome_id: int = 0,
	p_ecotone_factor: float = 0.0
) -> void:
	if index < 0 or index >= terrain.size():
		return
	terrain[index] = terrain_type
	height[index] = height_value
	variation[index] = variation_id
	biome[index] = biome_id
	secondary_biome[index] = p_secondary_biome_id
	ecotone_values[index] = p_ecotone_factor
	flora_density_values[index] = p_flora_density
	flora_modulation_values[index] = p_flora_mod

func is_valid() -> bool:
	var tile_count: int = chunk_size * chunk_size
	return chunk_size > 0 \
		and terrain.size() == tile_count \
		and height.size() == tile_count \
		and variation.size() == tile_count \
		and biome.size() == tile_count \
		and secondary_biome.size() == tile_count \
		and ecotone_values.size() == tile_count \
		and flora_density_values.size() == tile_count \
		and flora_modulation_values.size() == tile_count

func apply_prebaked_visual_payload(payload: Dictionary) -> void:
	rock_visual_class = payload.get("rock_visual_class", PackedByteArray()) as PackedByteArray
	ground_face_atlas = payload.get("ground_face_atlas", PackedInt32Array()) as PackedInt32Array
	cover_mask = payload.get("cover_mask", PackedInt32Array()) as PackedInt32Array
	cliff_overlay = payload.get("cliff_overlay", PackedByteArray()) as PackedByteArray
	variant_id = payload.get("variant_id", PackedByteArray()) as PackedByteArray
	alt_id = payload.get("alt_id", PackedInt32Array()) as PackedInt32Array

func populate_from_surface_packet(packet: Dictionary) -> ChunkBuildResult:
	if not ChunkFinalPacketScript.validate_surface_packet(packet, "ChunkBuildResult.populate_from_surface_packet"):
		return self
	chunk_coord = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	canonical_chunk_coord = packet.get("canonical_chunk_coord", chunk_coord) as Vector2i
	chunk_size = int(packet.get("chunk_size", 0))
	base_tile = packet.get("base_tile", Vector2i.ZERO) as Vector2i
	terrain = (packet.get("terrain", PackedByteArray()) as PackedByteArray).duplicate()
	height = (packet.get("height", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	variation = (packet.get("variation", PackedByteArray()) as PackedByteArray).duplicate()
	biome = (packet.get("biome", PackedByteArray()) as PackedByteArray).duplicate()
	secondary_biome = (packet.get("secondary_biome", PackedByteArray()) as PackedByteArray).duplicate()
	ecotone_values = (packet.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	flora_density_values = (packet.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	flora_modulation_values = (packet.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	feature_and_poi_payload = (packet.get(FEATURE_AND_POI_PAYLOAD_KEY, _empty_feature_and_poi_payload()) as Dictionary).duplicate(true)
	apply_prebaked_visual_payload(packet)
	return self

func to_native_data() -> Dictionary:
	return {
		"chunk_coord": chunk_coord,
		"canonical_chunk_coord": canonical_chunk_coord,
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
		"rock_visual_class": rock_visual_class,
		"ground_face_atlas": ground_face_atlas,
		"cover_mask": cover_mask,
		"cliff_overlay": cliff_overlay,
		"variant_id": variant_id,
		"alt_id": alt_id,
		FEATURE_AND_POI_PAYLOAD_KEY: _duplicate_feature_and_poi_payload(),
	}

func _empty_feature_and_poi_payload() -> Dictionary:
	return {
		PLACEMENTS_KEY: [],
	}

func _duplicate_feature_and_poi_payload() -> Dictionary:
	return feature_and_poi_payload.duplicate(true) if not feature_and_poi_payload.is_empty() else _empty_feature_and_poi_payload()
