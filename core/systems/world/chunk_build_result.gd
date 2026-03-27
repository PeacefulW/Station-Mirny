class_name ChunkBuildResult
extends RefCounted

var chunk_coord: Vector2i = Vector2i.ZERO
var canonical_chunk_coord: Vector2i = Vector2i.ZERO
var chunk_size: int = 0
var base_tile: Vector2i = Vector2i.ZERO
var terrain: PackedByteArray = PackedByteArray()
var height: PackedFloat32Array = PackedFloat32Array()
var variation: PackedByteArray = PackedByteArray()
var biome: PackedByteArray = PackedByteArray()
var flora_density_values: PackedFloat32Array = PackedFloat32Array()
var flora_modulation_values: PackedFloat32Array = PackedFloat32Array()

func initialize(coord: Vector2i, size: int, chunk_base_tile: Vector2i = Vector2i.ZERO) -> ChunkBuildResult:
	chunk_coord = coord
	canonical_chunk_coord = coord
	chunk_size = maxi(0, size)
	base_tile = chunk_base_tile
	var tile_count: int = chunk_size * chunk_size
	terrain.resize(tile_count)
	height.resize(tile_count)
	variation.resize(tile_count)
	biome.resize(tile_count)
	flora_density_values.resize(tile_count)
	flora_modulation_values.resize(tile_count)
	if tile_count > 0:
		variation.fill(0)
		biome.fill(0)
	return self

func set_tile(index: int, terrain_type: int, height_value: float, variation_id: int = 0, biome_id: int = 0, p_flora_density: float = 0.5, p_flora_mod: float = 0.0) -> void:
	if index < 0 or index >= terrain.size():
		return
	terrain[index] = terrain_type
	height[index] = height_value
	variation[index] = variation_id
	biome[index] = biome_id
	flora_density_values[index] = p_flora_density
	flora_modulation_values[index] = p_flora_mod

func is_valid() -> bool:
	var tile_count: int = chunk_size * chunk_size
	return chunk_size > 0 \
		and terrain.size() == tile_count \
		and height.size() == tile_count \
		and variation.size() == tile_count \
		and biome.size() == tile_count

func to_native_data() -> Dictionary:
	return {
		"chunk_size": chunk_size,
		"terrain": terrain.duplicate(),
		"height": height.duplicate(),
		"variation": variation.duplicate(),
		"biome": biome.duplicate(),
	}
