class_name ChunkFloraBuilder
extends RefCounted

## Compute-фаза размещения флоры и декора на чанке.
## Deterministic: один seed + координаты = одинаковый результат.
## Не мутирует scene tree — только создаёт ChunkFloraResult.

var _world_seed: int = 0

func initialize(seed_value: int) -> void:
	_world_seed = seed_value

func compute_placements(
	chunk_coord: Vector2i,
	chunk_size: int,
	base_tile: Vector2i,
	terrain_bytes: PackedByteArray,
	biome_palette: Array[BiomeData],
	biome_bytes: PackedByteArray,
	variation_bytes: PackedByteArray,
	flora_density_values: PackedFloat32Array,
	flora_modulation_values: PackedFloat32Array
) -> ChunkFloraResult:
	var result: ChunkFloraResult = ChunkFloraResult.new()
	result.chunk_coord = chunk_coord
	result.chunk_size = chunk_size
	var tile_count: int = chunk_size * chunk_size
	if terrain_bytes.size() != tile_count:
		return result
	for index: int in range(tile_count):
		var terrain: int = terrain_bytes[index]
		if terrain != TileGenData.TerrainType.GROUND:
			continue
		var local_x: int = index % chunk_size
		var local_y: int = index / chunk_size
		var world_tile: Vector2i = Vector2i(base_tile.x + local_x, base_tile.y + local_y)
		var flora_density: float = flora_density_values[index] if index < flora_density_values.size() else 0.5
		var flora_mod: float = flora_modulation_values[index] if index < flora_modulation_values.size() else 0.0
		var variation_id: int = variation_bytes[index] if index < variation_bytes.size() else 0
		var subzone_kind: StringName = LocalVariationContext.get_supported_kinds()[variation_id - 1] if variation_id > 0 and variation_id <= 5 else &"none"
		var biome_idx: int = biome_bytes[index] if index < biome_bytes.size() else 0
		var biome: BiomeData = biome_palette[biome_idx] if biome_idx < biome_palette.size() else null
		if biome == null:
			continue
		var hash1: float = _tile_hash(world_tile, 0)
		var hash2: float = _tile_hash(world_tile, 1)
		var hash3: float = _tile_hash(world_tile, 2)
		var placed: bool = _try_place_flora(result, Vector2i(local_x, local_y), biome, subzone_kind, flora_density, flora_mod, hash1, hash2)
		if not placed:
			_try_place_decor(result, Vector2i(local_x, local_y), biome, subzone_kind, hash1, hash3)
	return result

func _try_place_flora(
	result: ChunkFloraResult,
	local_pos: Vector2i,
	biome: BiomeData,
	subzone_kind: StringName,
	flora_density: float,
	flora_mod: float,
	hash_density: float,
	hash_entry: float
) -> bool:
	var flora_sets: Array[FloraSetData] = FloraDecorRegistry.get_flora_sets_for_ids(biome.flora_set_ids)
	for flora_set: FloraSetData in flora_sets:
		if not flora_set.is_allowed_in_subzone(subzone_kind):
			continue
		var effective_density: float = flora_set.base_density
		effective_density *= (1.0 + flora_density * flora_set.flora_channel_weight)
		effective_density *= (1.0 + flora_mod * flora_set.flora_modulation_weight)
		effective_density = clampf(effective_density, 0.0, 0.6)
		if hash_density >= effective_density:
			continue
		var entry: FloraEntry = flora_set.pick_entry(hash_entry, flora_density)
		if entry == null:
			continue
		result.add_placement(
			local_pos,
			entry.id,
			true,
			entry.placeholder_color,
			entry.placeholder_size,
			entry.z_index_offset
		)
		return true
	return false

func _try_place_decor(
	result: ChunkFloraResult,
	local_pos: Vector2i,
	biome: BiomeData,
	subzone_kind: StringName,
	hash_density: float,
	hash_entry: float
) -> void:
	var decor_sets: Array[DecorSetData] = FloraDecorRegistry.get_decor_sets_for_ids(biome.decor_set_ids)
	for decor_set: DecorSetData in decor_sets:
		if not decor_set.is_allowed_on_terrain(TileGenData.TerrainType.GROUND):
			continue
		var density: float = decor_set.get_subzone_density(subzone_kind)
		if hash_density >= density:
			continue
		var entry: DecorEntry = decor_set.pick_entry(hash_entry)
		if entry == null:
			continue
		result.add_placement(
			local_pos,
			entry.id,
			false,
			entry.placeholder_color,
			entry.placeholder_size,
			entry.z_index_offset
		)
		return

func _tile_hash(world_pos: Vector2i, channel: int) -> float:
	var h: int = _world_seed * 374761393
	h = h + world_pos.x * 668265263
	h = h + world_pos.y * 2147483647
	h = h + channel * 1013904223
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absf(float(h % 100000) / 100000.0)
