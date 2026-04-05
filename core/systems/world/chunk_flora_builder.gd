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
	flora_modulation_values: PackedFloat32Array,
	secondary_biome_bytes: PackedByteArray = PackedByteArray(),
	ecotone_values: PackedFloat32Array = PackedFloat32Array()
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
	var has_secondary_biomes: bool = secondary_biome_bytes.size() == tile_count
	var has_ecotone_values: bool = ecotone_values.size() == tile_count
	var flora_sets_by_biome_index: Dictionary = {}
	var decor_sets_by_biome_index: Dictionary = {}
	var flora_sets_by_zone_key: Dictionary = {}
	var decor_sets_by_zone_key: Dictionary = {}
	var decor_densities_by_zone_key: Dictionary = {}
	var mixed_flora_candidates_by_zone_key: Dictionary = {}
	var mixed_decor_candidates_by_zone_key: Dictionary = {}
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
			var secondary_biome_idx: int = int(secondary_biome_bytes[index]) if has_secondary_biomes else biome_idx
			var ecotone_bucket: int = _resolve_ecotone_bucket(
				float(ecotone_values[index]) if has_ecotone_values else 0.0,
				biome_idx,
				secondary_biome_idx
			)
			if not flora_sets_by_biome_index.has(biome_idx):
				flora_sets_by_biome_index[biome_idx] = FloraDecorRegistry.get_flora_sets_for_ids(biome.flora_set_ids)
				decor_sets_by_biome_index[biome_idx] = FloraDecorRegistry.get_decor_sets_for_ids(biome.decor_set_ids)
			var world_x: int = base_x + local_x
			var hash1: float = _tile_hash_xy(world_x, world_y, 0)
			var hash2: float = _tile_hash_xy(world_x, world_y, 1)
			var hash3: float = _tile_hash_xy(world_x, world_y, 2)
			var placed: bool = false
			if ecotone_bucket > 0:
				var secondary_biome: BiomeData = biome_palette[secondary_biome_idx] if secondary_biome_idx >= 0 and secondary_biome_idx < biome_palette.size() else null
				if secondary_biome != null and not flora_sets_by_biome_index.has(secondary_biome_idx):
					flora_sets_by_biome_index[secondary_biome_idx] = FloraDecorRegistry.get_flora_sets_for_ids(secondary_biome.flora_set_ids)
					decor_sets_by_biome_index[secondary_biome_idx] = FloraDecorRegistry.get_decor_sets_for_ids(secondary_biome.decor_set_ids)
				var mixed_zone_key: String = _build_mixed_zone_key(biome_idx, secondary_biome_idx, variation_id, ecotone_bucket)
				if not mixed_flora_candidates_by_zone_key.has(mixed_zone_key):
					var blend_weights: Vector2 = _resolve_blend_weights(ecotone_bucket)
					mixed_flora_candidates_by_zone_key[mixed_zone_key] = _build_mixed_flora_candidates(
						flora_sets_by_biome_index.get(biome_idx, []),
						flora_sets_by_biome_index.get(secondary_biome_idx, []),
						subzone_kind,
						blend_weights.x,
						blend_weights.y
					)
					mixed_decor_candidates_by_zone_key[mixed_zone_key] = _build_mixed_decor_candidates(
						decor_sets_by_biome_index.get(biome_idx, []),
						decor_sets_by_biome_index.get(secondary_biome_idx, []),
						subzone_kind,
						blend_weights.x,
						blend_weights.y
					)
				placed = _try_place_mixed_flora(
					result,
					local_x,
					local_y,
					mixed_flora_candidates_by_zone_key.get(mixed_zone_key, []),
					flora_density_values[index],
					flora_modulation_values[index],
					hash1,
					_remap_hash(hash2, 0.38196601125),
					_remap_hash(hash2, 0.61803398875)
				)
				if not placed:
					_try_place_mixed_decor(
						result,
						local_x,
						local_y,
						mixed_decor_candidates_by_zone_key.get(mixed_zone_key, []),
						hash1,
						_remap_hash(hash3, 0.41421356237),
						_remap_hash(hash3, 0.73205080757)
					)
				continue
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
			placed = _try_place_flora(
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
	result.finalize_render_groups()
	return result

func _resolve_ecotone_bucket(ecotone_factor: float, biome_idx: int, secondary_biome_idx: int) -> int:
	if biome_idx < 0 or secondary_biome_idx < 0 or secondary_biome_idx == biome_idx:
		return 0
	var clamped: float = clampf(ecotone_factor, 0.0, 1.0)
	if clamped < 0.12:
		return 0
	return clampi(int(round(clamped * 8.0)), 1, 8)

func _build_mixed_zone_key(primary_biome_idx: int, secondary_biome_idx: int, variation_id: int, ecotone_bucket: int) -> String:
	return "%d|%d|%d|%d" % [primary_biome_idx, secondary_biome_idx, variation_id, ecotone_bucket]

func _resolve_blend_weights(ecotone_bucket: int) -> Vector2:
	if ecotone_bucket <= 0:
		return Vector2(1.0, 0.0)
	var transition: float = clampf(float(ecotone_bucket) / 8.0, 0.0, 1.0)
	var secondary_share: float = clampf(transition * 0.5, 0.0, 0.5)
	return Vector2(1.0 - secondary_share, secondary_share)

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

func _try_place_mixed_flora(
	result: ChunkFloraResultScript,
	local_x: int,
	local_y: int,
	flora_candidates: Array,
	flora_density: float,
	flora_mod: float,
	hash_density: float,
	hash_pick: float,
	hash_entry: float
) -> bool:
	var eligible_candidates: Array = []
	var total_weight: float = 0.0
	for candidate_data: Variant in flora_candidates:
		var candidate: Dictionary = candidate_data as Dictionary
		var flora_set: FloraSetDataScript = candidate.get("set", null) as FloraSetDataScript
		var share: float = float(candidate.get("share", 0.0))
		if flora_set == null or share <= 0.0:
			continue
		var effective_density: float = flora_set.base_density
		effective_density *= (1.0 + flora_density * flora_set.flora_channel_weight)
		effective_density *= (1.0 + flora_mod * flora_set.flora_modulation_weight)
		effective_density = clampf(effective_density * share, 0.0, 0.6)
		if hash_density >= effective_density:
			continue
		eligible_candidates.append({
			"set": flora_set,
			"weight": effective_density,
		})
		total_weight += effective_density
	var picked_candidate: Dictionary = _pick_weighted_candidate(eligible_candidates, total_weight, hash_pick)
	if picked_candidate.is_empty():
		return false
	var picked_set: FloraSetDataScript = picked_candidate.get("set", null) as FloraSetDataScript
	if picked_set == null:
		return false
	var entry: FloraEntryScript = picked_set.pick_entry(hash_entry, flora_density)
	if entry == null:
		return false
	result.add_placement(
		Vector2i(local_x, local_y),
		entry.id,
		true,
		entry.placeholder_color,
		entry.placeholder_size,
		entry.z_index_offset
	)
	return true

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

func _try_place_mixed_decor(
	result: ChunkFloraResultScript,
	local_x: int,
	local_y: int,
	decor_candidates: Array,
	hash_density: float,
	hash_pick: float,
	hash_entry: float
) -> void:
	var eligible_candidates: Array = []
	var total_weight: float = 0.0
	for candidate_data: Variant in decor_candidates:
		var candidate: Dictionary = candidate_data as Dictionary
		var decor_set: DecorSetDataScript = candidate.get("set", null) as DecorSetDataScript
		var density: float = float(candidate.get("density", 0.0))
		if decor_set == null or density <= 0.0 or hash_density >= density:
			continue
		eligible_candidates.append({
			"set": decor_set,
			"weight": density,
		})
		total_weight += density
	var picked_candidate: Dictionary = _pick_weighted_candidate(eligible_candidates, total_weight, hash_pick)
	if picked_candidate.is_empty():
		return
	var picked_set: DecorSetDataScript = picked_candidate.get("set", null) as DecorSetDataScript
	if picked_set == null:
		return
	var entry: DecorEntryScript = picked_set.pick_entry(hash_entry)
	if entry == null:
		return
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

func _build_mixed_flora_candidates(
	primary_flora_sets: Array,
	secondary_flora_sets: Array,
	subzone_kind: StringName,
	primary_share: float,
	secondary_share: float
) -> Array:
	var candidate_map: Dictionary = {}
	_append_flora_candidate_shares(
		candidate_map,
		_build_flora_sets_for_zone(primary_flora_sets, subzone_kind),
		primary_share
	)
	_append_flora_candidate_shares(
		candidate_map,
		_build_flora_sets_for_zone(secondary_flora_sets, subzone_kind),
		secondary_share
	)
	return _candidate_records_from_map(candidate_map)

func _build_mixed_decor_candidates(
	primary_decor_sets: Array,
	secondary_decor_sets: Array,
	subzone_kind: StringName,
	primary_share: float,
	secondary_share: float
) -> Array:
	var candidate_map: Dictionary = {}
	var primary_decor_cache: Array = _build_decor_sets_for_zone(primary_decor_sets, subzone_kind)
	var secondary_decor_cache: Array = _build_decor_sets_for_zone(secondary_decor_sets, subzone_kind)
	_append_decor_candidate_densities(
		candidate_map,
		primary_decor_cache[0],
		primary_decor_cache[1],
		primary_share
	)
	_append_decor_candidate_densities(
		candidate_map,
		secondary_decor_cache[0],
		secondary_decor_cache[1],
		secondary_share
	)
	return _candidate_records_from_map(candidate_map)

func _append_flora_candidate_shares(candidate_map: Dictionary, flora_sets: Array, share: float) -> void:
	if share <= 0.0:
		return
	for flora_set_resource: Resource in flora_sets:
		var flora_set: FloraSetDataScript = flora_set_resource as FloraSetDataScript
		if flora_set == null:
			continue
		var candidate_key: String = str(flora_set.id)
		var candidate: Dictionary = candidate_map.get(candidate_key, {
			"key": candidate_key,
			"set": flora_set,
			"share": 0.0,
		})
		candidate["share"] = float(candidate.get("share", 0.0)) + share
		candidate_map[candidate_key] = candidate

func _append_decor_candidate_densities(
	candidate_map: Dictionary,
	decor_sets: Array,
	decor_densities: PackedFloat32Array,
	share: float
) -> void:
	if share <= 0.0:
		return
	for index: int in range(decor_sets.size()):
		var decor_set: DecorSetDataScript = decor_sets[index] as DecorSetDataScript
		if decor_set == null:
			continue
		var density: float = (decor_densities[index] if index < decor_densities.size() else 0.0) * share
		if density <= 0.0:
			continue
		var candidate_key: String = str(decor_set.id)
		var candidate: Dictionary = candidate_map.get(candidate_key, {
			"key": candidate_key,
			"set": decor_set,
			"density": 0.0,
		})
		candidate["density"] = float(candidate.get("density", 0.0)) + density
		candidate_map[candidate_key] = candidate

func _candidate_records_from_map(candidate_map: Dictionary) -> Array:
	var keys: Array = candidate_map.keys()
	keys.sort()
	var candidates: Array = []
	for candidate_key: Variant in keys:
		candidates.append(candidate_map.get(candidate_key, {}))
	return candidates

func _pick_weighted_candidate(candidates: Array, total_weight: float, hash_value: float) -> Dictionary:
	if candidates.is_empty() or total_weight <= 0.0:
		return {}
	var target: float = clampf(hash_value, 0.0, 0.999999) * total_weight
	var accumulated: float = 0.0
	for candidate_data: Variant in candidates:
		var candidate: Dictionary = candidate_data as Dictionary
		accumulated += float(candidate.get("weight", 0.0))
		if target <= accumulated:
			return candidate
	return candidates.back() as Dictionary

func _remap_hash(hash_value: float, salt: float) -> float:
	return fposmod(hash_value + salt, 1.0)

func _tile_hash_xy(world_x: int, world_y: int, channel: int) -> float:
	var h: int = _world_seed * 374761393
	h = h + world_x * 668265263
	h = h + world_y * 2147483647
	h = h + channel * 1013904223
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h % 100000)) * 0.00001
