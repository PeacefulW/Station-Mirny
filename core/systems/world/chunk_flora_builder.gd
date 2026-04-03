class_name ChunkFloraBuilder
extends RefCounted

## Compute-С„Р°Р·Р° СЂР°Р·РјРµС‰РµРЅРёСЏ С„Р»РѕСЂС‹ Рё РґРµРєРѕСЂР° РЅР° С‡Р°РЅРєРµ.
## Deterministic: РѕРґРёРЅ seed + РєРѕРѕСЂРґРёРЅР°С‚С‹ = РѕРґРёРЅР°РєРѕРІС‹Р№ СЂРµР·СѓР»СЊС‚Р°С‚.
## РќРµ РјСѓС‚РёСЂСѓРµС‚ scene tree вЂ” С‚РѕР»СЊРєРѕ СЃРѕР·РґР°С‘С‚ ChunkFloraResult.

const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")
const FloraSetDataScript = preload("res://data/flora/flora_set_data.gd")
const DecorSetDataScript = preload("res://data/decor/decor_set_data.gd")
const FloraEntryScript = preload("res://data/flora/flora_entry.gd")
const DecorEntryScript = preload("res://data/decor/decor_entry.gd")

const VARIATION_KIND_BY_ID: Array[StringName] = [
	&"none",
	&"sparse_flora",
	&"dense_flora",
	&"clearing",
	&"rocky_patch",
	&"wet_patch",
	&"polar_ice",
	&"polar_scorched",
	&"polar_salt_flat",
	&"polar_dry_riverbed",
]

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
) -> ChunkFloraResultScript:
	var result: ChunkFloraResultScript = ChunkFloraResultScript.new()
	result.chunk_coord = chunk_coord
	result.chunk_size = chunk_size
	var tile_count: int = chunk_size * chunk_size
	if terrain_bytes.size() != tile_count \
		or biome_bytes.size() != tile_count \
		or variation_bytes.size() != tile_count \
		or flora_density_values.size() != tile_count \
		or flora_modulation_values.size() != tile_count:
		return result
	var flora_sets_by_biome_index: Dictionary = {}
	var decor_sets_by_biome_index: Dictionary = {}
	var flora_sets_by_zone_key: Dictionary = {}
	var decor_sets_by_zone_key: Dictionary = {}
	var decor_densities_by_zone_key: Dictionary = {}
	var base_x: int = base_tile.x
	var base_y: int = base_tile.y
	for local_y: int in range(chunk_size):
		var world_y: int = base_y + local_y
		var row_index: int = local_y * chunk_size
		for local_x: int in range(chunk_size):
			var index: int = row_index + local_x
			if terrain_bytes[index] != TileGenData.TerrainType.GROUND:
				continue
			var variation_id: int = variation_bytes[index]
			var subzone_kind: StringName = VARIATION_KIND_BY_ID[variation_id] if variation_id >= 0 and variation_id < VARIATION_KIND_BY_ID.size() else &"none"
			var biome_idx: int = biome_bytes[index]
			var biome: BiomeData = biome_palette[biome_idx] if biome_idx < biome_palette.size() else null
			if biome == null:
				continue
			if not flora_sets_by_biome_index.has(biome_idx):
				flora_sets_by_biome_index[biome_idx] = FloraDecorRegistry.get_flora_sets_for_ids(biome.flora_set_ids)
				decor_sets_by_biome_index[biome_idx] = FloraDecorRegistry.get_decor_sets_for_ids(biome.decor_set_ids)
			var zone_key: int = biome_idx * 16 + variation_id
			if not flora_sets_by_zone_key.has(zone_key):
				flora_sets_by_zone_key[zone_key] = _build_flora_sets_for_zone(
					flora_sets_by_biome_index.get(biome_idx, []),
					subzone_kind
				)
				var decor_cache: Array = _build_decor_sets_for_zone(
					decor_sets_by_biome_index.get(biome_idx, []),
					subzone_kind
				)
				decor_sets_by_zone_key[zone_key] = decor_cache[0]
				decor_densities_by_zone_key[zone_key] = decor_cache[1]
			var world_x: int = base_x + local_x
			var hash1: float = _tile_hash_xy(world_x, world_y, 0)
			var hash2: float = _tile_hash_xy(world_x, world_y, 1)
			var hash3: float = _tile_hash_xy(world_x, world_y, 2)
			var placed: bool = _try_place_flora(
				result,
				local_x,
				local_y,
				flora_sets_by_zone_key.get(zone_key, []),
				flora_density_values[index],
				flora_modulation_values[index],
				hash1,
				hash2
			)
			if not placed:
				_try_place_decor(
					result,
					local_x,
					local_y,
					decor_sets_by_zone_key.get(zone_key, []),
					decor_densities_by_zone_key.get(zone_key, PackedFloat32Array()),
					hash1,
					hash3
				)
	return result

func _try_place_flora(
	result: ChunkFloraResultScript,
	local_x: int,
	local_y: int,
	flora_sets: Array,
	flora_density: float,
	flora_mod: float,
	hash_density: float,
	hash_entry: float
) -> bool:
	for flora_set: FloraSetDataScript in flora_sets:
		var effective_density: float = flora_set.base_density
		effective_density *= (1.0 + flora_density * flora_set.flora_channel_weight)
		effective_density *= (1.0 + flora_mod * flora_set.flora_modulation_weight)
		effective_density = clampf(effective_density, 0.0, 0.6)
		if hash_density >= effective_density:
			continue
		var entry: FloraEntryScript = flora_set.pick_entry(hash_entry, flora_density)
		if entry == null:
			continue
		result.add_placement(
			Vector2i(local_x, local_y),
			entry.id,
			true,
			entry.placeholder_color,
			entry.placeholder_size,
			entry.z_index_offset
		)
		return true
	return false

func _try_place_decor(
	result: ChunkFloraResultScript,
	local_x: int,
	local_y: int,
	decor_sets: Array,
	decor_densities: PackedFloat32Array,
	hash_density: float,
	hash_entry: float
) -> void:
	for index: int in range(decor_sets.size()):
		var density: float = decor_densities[index] if index < decor_densities.size() else 0.0
		if hash_density >= density:
			continue
		var decor_set: DecorSetDataScript = decor_sets[index] as DecorSetDataScript
		if decor_set == null:
			continue
		var entry: DecorEntryScript = decor_set.pick_entry(hash_entry)
		if entry == null:
			continue
		result.add_placement(
			Vector2i(local_x, local_y),
			entry.id,
			false,
			entry.placeholder_color,
			entry.placeholder_size,
			entry.z_index_offset
		)
		return

func _build_flora_sets_for_zone(flora_sets: Array, subzone_kind: StringName) -> Array:
	var filtered: Array = []
	for flora_set_resource: Resource in flora_sets:
		var flora_set: FloraSetDataScript = flora_set_resource as FloraSetDataScript
		if flora_set == null:
			continue
		if not flora_set.is_allowed_in_subzone(subzone_kind):
			continue
		filtered.append(flora_set)
	return filtered

func _build_decor_sets_for_zone(decor_sets: Array, subzone_kind: StringName) -> Array:
	var filtered_sets: Array = []
	var filtered_densities: PackedFloat32Array = PackedFloat32Array()
	for decor_set_resource: Resource in decor_sets:
		var decor_set: DecorSetDataScript = decor_set_resource as DecorSetDataScript
		if decor_set == null:
			continue
		if not decor_set.is_allowed_on_terrain(TileGenData.TerrainType.GROUND):
			continue
		filtered_sets.append(decor_set)
		filtered_densities.append(decor_set.get_subzone_density(subzone_kind))
	return [filtered_sets, filtered_densities]

func _tile_hash_xy(world_x: int, world_y: int, channel: int) -> float:
	var h: int = _world_seed * 374761393
	h = h + world_x * 668265263
	h = h + world_y * 2147483647
	h = h + channel * 1013904223
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h % 100000)) * 0.00001
