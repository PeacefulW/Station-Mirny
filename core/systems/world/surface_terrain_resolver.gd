class_name SurfaceTerrainResolver
extends RefCounted

var _world_context: RefCounted = null
var _balance: WorldGenBalance = null
var _safe_radius: float = 0.0
var _safe_radius_sq: float = 0.0
var _land_guarantee_radius: float = 0.0
var _land_guarantee_radius_sq: float = 0.0
var _mountain_threshold_value: float = 0.0
var _ridge_backbone_weight: float = 0.76
var _massif_fill_weight: float = 0.30
var _core_bonus_weight: float = 0.16
var _current_biome_palette_index: int = 0

const _POLAR_KIND_ICE: StringName = &"polar_ice"
const _POLAR_KIND_SCORCHED: StringName = &"polar_scorched"
const _POLAR_KIND_SALT_FLAT: StringName = &"polar_salt_flat"
const _POLAR_KIND_DRY_RIVERBED: StringName = &"polar_dry_riverbed"

func initialize(balance_resource: WorldGenBalance, world_context: RefCounted) -> SurfaceTerrainResolver:
	_balance = balance_resource
	_world_context = world_context
	if _balance:
		_safe_radius = float(_balance.safe_zone_radius)
		_safe_radius_sq = _safe_radius * _safe_radius
		_land_guarantee_radius = float(_balance.land_guarantee_radius)
		_land_guarantee_radius_sq = _land_guarantee_radius * _land_guarantee_radius
		_mountain_threshold_value = clampf(
			_balance.mountain_base_threshold - _balance.mountain_density,
			_balance.mountain_threshold_min,
			_balance.mountain_threshold_max
		)
		var chaininess: float = clampf(_balance.mountain_chaininess, 0.0, 1.0)
		_ridge_backbone_weight = lerpf(0.76, 0.92, chaininess)
		_massif_fill_weight = lerpf(0.30, 0.38, chaininess)
		_core_bonus_weight = lerpf(0.16, 0.28, chaininess)
	if _world_context and _world_context.current_biome:
		_current_biome_palette_index = _world_context.get_biome_palette_index(_world_context.current_biome.id)
	return self

func build_tile_data(tile_pos: Vector2i) -> TileGenData:
	var data := TileGenData.new()
	populate_tile_data(tile_pos, data)
	return data

func populate_tile_data(tile_pos: Vector2i, data: TileGenData) -> void:
	if data == null:
		return
	_reset_tile_data(data)
	if _world_context == null:
		return
	var canonical_tile: Vector2i = _world_context.canonicalize_tile(tile_pos)
	var spawn_tile: Vector2i = _resolve_spawn_tile()
	_populate_tile_data(data, canonical_tile, spawn_tile)

func populate_canonical_tile_data(
	canonical_tile: Vector2i,
	spawn_tile: Vector2i,
	_safe_radius_ignored: float,
	data: TileGenData
) -> void:
	if data == null:
		return
	_reset_tile_data(data)
	if _world_context == null:
		return
	_populate_tile_data(data, canonical_tile, spawn_tile)

func populate_chunk_build_data(canonical_tile: Vector2i, spawn_tile: Vector2i, data: TileGenData) -> void:
	if data == null:
		return
	_reset_chunk_build_data(data)
	if _world_context == null:
		return
	var channels: WorldChannels = _world_context.sample_world_channels(canonical_tile)
	var prepass_channels: WorldPrePassChannels = _sample_prepass_channels(canonical_tile)
	var structure_context: WorldStructureContext = _world_context.sample_structure_context(canonical_tile, channels)
	var biome_result: BiomeResult = _world_context.get_biome_result_at_tile(canonical_tile, channels, structure_context)
	var local_variation: LocalVariationContext = _world_context.sample_local_variation(
		canonical_tile,
		biome_result,
		channels,
		structure_context
	)
	var distance_from_spawn_sq: float = _distance_from_spawn_sq(canonical_tile, spawn_tile)
	data.height = channels.height
	data.flora_density = channels.flora_density
	data.terrain = _resolve_surface_terrain_sq(
		distance_from_spawn_sq,
		channels,
		structure_context,
		prepass_channels,
		local_variation
	)
	if biome_result:
		var resolved_biome: BiomeData = biome_result.biome as BiomeData
		if resolved_biome:
			data.biome_palette_index = _world_context.get_biome_palette_index(resolved_biome.id)
	elif _current_biome_palette_index > 0:
		data.biome_palette_index = _current_biome_palette_index
	if data.terrain == TileGenData.TerrainType.GROUND and local_variation:
		data.local_variation_id = LocalVariationContext.kind_to_variation_id(local_variation.variation_kind)
		data.flora_modulation = local_variation.flora_modulation
	_apply_polar_surface_modifiers(data, channels, structure_context, prepass_channels)

func sample_terrain_type(tile_x: int, tile_y: int) -> TileGenData.TerrainType:
	var canonical_tile: Vector2i = _world_context.canonicalize_tile(Vector2i(tile_x, tile_y)) if _world_context else Vector2i(tile_x, tile_y)
	if _world_context == null:
		return TileGenData.TerrainType.GROUND
	var spawn_tile: Vector2i = _resolve_spawn_tile()
	var channels: WorldChannels = _world_context.sample_world_channels(canonical_tile)
	var prepass_channels: WorldPrePassChannels = _sample_prepass_channels(canonical_tile)
	var structure_context: WorldStructureContext = _world_context.sample_structure_context(canonical_tile, channels)
	var biome_result: BiomeResult = _world_context.get_biome_result_at_tile(canonical_tile, channels, structure_context)
	var local_variation: LocalVariationContext = _world_context.sample_local_variation(
		canonical_tile,
		biome_result,
		channels,
		structure_context
	)
	return _resolve_surface_terrain_sq(
		_distance_from_spawn_sq(canonical_tile, spawn_tile),
		channels,
		structure_context,
		prepass_channels,
		local_variation
	)

func resolve_surface_terrain_type_from_context(
	canonical_tile: Vector2i,
	channels: WorldChannels,
	structure_context: WorldStructureContext,
	local_variation: LocalVariationContext = null
) -> int:
	if _world_context == null:
		return TileGenData.TerrainType.GROUND
	var prepass_channels: WorldPrePassChannels = _sample_prepass_channels(canonical_tile)
	return _resolve_surface_terrain_sq(
		_distance_from_spawn_sq(canonical_tile, _resolve_spawn_tile()),
		channels,
		structure_context,
		prepass_channels,
		local_variation
	)

func canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	if _world_context == null:
		return chunk_coord
	return _world_context.canonicalize_chunk_coord(chunk_coord)

func chunk_to_tile_origin(chunk_coord: Vector2i) -> Vector2i:
	if _world_context == null:
		return Vector2i.ZERO
	return _world_context.chunk_to_tile_origin(chunk_coord)

func get_chunk_size() -> int:
	return _balance.chunk_size_tiles if _balance else 0

func _populate_tile_data(
	data: TileGenData,
	canonical_tile: Vector2i,
	spawn_tile: Vector2i
) -> void:
	data.canonical_world_pos = canonical_tile
	var channels: WorldChannels = _world_context.sample_world_channels(canonical_tile)
	var prepass_channels: WorldPrePassChannels = _sample_prepass_channels(canonical_tile)
	var structure_context: WorldStructureContext = _world_context.sample_structure_context(canonical_tile, channels)
	var biome_result: BiomeResult = _world_context.get_biome_result_at_tile(canonical_tile, channels, structure_context)
	var local_variation: LocalVariationContext = _world_context.sample_local_variation(
		canonical_tile,
		biome_result,
		channels,
		structure_context
	)
	var distance_from_spawn_sq: float = _distance_from_spawn_sq(canonical_tile, spawn_tile)
	var distance_from_spawn: float = sqrt(distance_from_spawn_sq)
	data.height = channels.height
	data.world_height = channels.height
	data.canonical_world_pos = channels.canonical_world_pos
	if structure_context:
		data.ridge_strength = structure_context.ridge_strength
		data.mountain_mass = structure_context.mountain_mass
		data.river_strength = structure_context.river_strength
		data.floodplain_strength = structure_context.floodplain_strength
	if biome_result:
		var resolved_biome: BiomeData = biome_result.biome as BiomeData
		if resolved_biome:
			data.biome_id = resolved_biome.id
		data.biome_score = float(biome_result.score)
	elif _world_context.current_biome:
		data.biome_id = _world_context.current_biome.id
	data.biome_palette_index = _world_context.get_biome_palette_index(data.biome_id)
	data.temperature = channels.temperature
	data.moisture = channels.moisture
	data.ruggedness = channels.ruggedness
	data.flora_density = channels.flora_density
	data.latitude = channels.latitude
	data.distance_from_spawn = distance_from_spawn
	data.terrain = _resolve_surface_terrain_sq(
		distance_from_spawn_sq,
		channels,
		structure_context,
		prepass_channels,
		local_variation
	)
	if data.terrain == TileGenData.TerrainType.GROUND and local_variation:
		data.local_variation_kind = local_variation.variation_kind
		data.local_variation_id = LocalVariationContext.kind_to_variation_id(local_variation.variation_kind)
		data.local_variation_score = local_variation.variation_score
		data.flora_modulation = local_variation.flora_modulation
		data.wetness_modulation = local_variation.wetness_modulation
		data.rockiness_modulation = local_variation.rockiness_modulation
		data.openness_modulation = local_variation.openness_modulation
	_apply_polar_surface_modifiers(data, channels, structure_context, prepass_channels)

func _reset_tile_data(data: TileGenData) -> void:
	data.terrain = TileGenData.TerrainType.GROUND
	data.height = 0.5
	data.world_height = 0.5
	data.canonical_world_pos = Vector2i.ZERO
	data.temperature = 0.5
	data.moisture = 0.5
	data.ruggedness = 0.5
	data.flora_density = 0.5
	data.latitude = 0.0
	data.ridge_strength = 0.0
	data.mountain_mass = 0.0
	data.river_strength = 0.0
	data.floodplain_strength = 0.0
	data.biome_id = &""
	data.biome_palette_index = 0
	data.biome_score = -1.0
	data.local_variation_id = 0
	data.local_variation_kind = &"none"
	data.local_variation_score = 0.0
	data.flora_modulation = 0.0
	data.wetness_modulation = 0.0
	data.rockiness_modulation = 0.0
	data.openness_modulation = 0.0
	data.distance_from_spawn = 0.0

func _reset_chunk_build_data(data: TileGenData) -> void:
	data.terrain = TileGenData.TerrainType.GROUND
	data.height = 0.5
	data.local_variation_id = 0
	data.biome_palette_index = 0
	data.flora_density = 0.5
	data.flora_modulation = 0.0

func _apply_polar_surface_modifiers(
	data: TileGenData,
	channels: WorldChannels,
	structure_context: WorldStructureContext,
	prepass_channels: WorldPrePassChannels = null
) -> void:
	if data == null or channels == null or _balance == null:
		return
	if data.terrain == TileGenData.TerrainType.ROCK \
		or data.terrain == TileGenData.TerrainType.MINED_FLOOR \
		or data.terrain == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return
	var cold_factor: float = _resolve_cold_factor(channels.temperature)
	var hot_factor: float = _resolve_hot_factor(channels.temperature)
	if cold_factor <= 0.0 and hot_factor <= 0.0:
		return
	var overlay_id: int = data.local_variation_id
	var overlay_kind: StringName = data.local_variation_kind
	var overlay_score: float = data.local_variation_score
	var is_flat_surface: bool = _is_flat_polar_surface(channels, prepass_channels)
	if data.terrain == TileGenData.TerrainType.WATER:
		if channels.temperature < _balance.prepass_frozen_river_threshold and cold_factor > 0.0:
			overlay_id = ChunkTilesetFactory.SURFACE_VARIATION_ICE
			overlay_kind = _POLAR_KIND_ICE
			overlay_score = cold_factor
	elif is_flat_surface:
		if cold_factor > 0.0 and data.height < _balance.ice_cap_max_height:
			overlay_id = ChunkTilesetFactory.SURFACE_VARIATION_ICE
			overlay_kind = _POLAR_KIND_ICE
			overlay_score = cold_factor
			data.height = clampf(data.height + cold_factor * _balance.ice_cap_height_bonus, 0.0, 1.0)
			data.world_height = data.height
		elif hot_factor > 0.70 and data.terrain == TileGenData.TerrainType.SAND \
			and structure_context != null \
			and structure_context.floodplain_strength >= _balance.bank_min_floodplain:
			overlay_id = ChunkTilesetFactory.SURFACE_VARIATION_SALT_FLAT
			overlay_kind = _POLAR_KIND_SALT_FLAT
			overlay_score = hot_factor
		elif hot_factor > 0.0 and data.terrain != TileGenData.TerrainType.WATER:
			overlay_id = ChunkTilesetFactory.SURFACE_VARIATION_SCORCHED
			overlay_kind = _POLAR_KIND_SCORCHED
			overlay_score = hot_factor
	if overlay_id != data.local_variation_id:
		data.local_variation_id = overlay_id
		data.local_variation_kind = overlay_kind
		data.local_variation_score = overlay_score
	var cold_suppression: float = maxf(0.0, 1.0 - cold_factor * 0.9)
	var hot_suppression: float = maxf(0.0, 1.0 - hot_factor * 0.95)
	data.flora_density = clampf(data.flora_density * cold_suppression * hot_suppression, 0.0, 1.0)
	if data.local_variation_id == ChunkTilesetFactory.SURFACE_VARIATION_SALT_FLAT \
		or data.local_variation_id == ChunkTilesetFactory.SURFACE_VARIATION_DRY_RIVERBED:
		data.flora_density = minf(data.flora_density, 0.03)

func _resolve_cold_factor(temperature: float) -> float:
	if _balance == null:
		return 0.0
	return clampf(
		(_balance.cold_pole_temperature - temperature) / maxf(0.001, _balance.cold_pole_transition_width),
		0.0,
		1.0
	)

func _resolve_hot_factor(temperature: float) -> float:
	if _balance == null:
		return 0.0
	return clampf(
		(temperature - _balance.hot_pole_temperature) / maxf(0.001, _balance.hot_pole_transition_width),
		0.0,
		1.0
	)

func _is_flat_polar_surface(channels: WorldChannels, prepass_channels: WorldPrePassChannels = null) -> bool:
	return _resolve_slope_value(prepass_channels, channels) <= 0.15

func _resolve_spawn_tile() -> Vector2i:
	return _world_context.spawn_tile if _world_context else Vector2i.ZERO

func _resolve_safe_radius() -> float:
	return _safe_radius

func _sample_prepass_channels(canonical_tile: Vector2i) -> WorldPrePassChannels:
	if _world_context != null and _world_context.has_method("sample_prepass_channels"):
		return _world_context.sample_prepass_channels(canonical_tile)
	return WorldPrePassChannels.new()

func _resolve_slope_value(
	prepass_channels: WorldPrePassChannels = null,
	channels: WorldChannels = null
) -> float:
	var pre_pass: RefCounted = _world_context.get_world_pre_pass() if _world_context and _world_context.has_method("get_world_pre_pass") else null
	if pre_pass != null and prepass_channels != null:
		return clampf(prepass_channels.slope, 0.0, 1.0)
	if channels != null:
		return clampf(channels.ruggedness * 0.82 + channels.height * 0.18, 0.0, 1.0)
	return 0.0

func _resolve_river_core_radius_tiles(
	structure_context: WorldStructureContext,
	prepass_channels: WorldPrePassChannels = null,
	channels: WorldChannels = null
) -> float:
	if structure_context == null:
		return 0.0
	var river_width: float = maxf(0.0, structure_context.river_width)
	if river_width <= 0.0:
		return 0.0
	var slope_value: float = _resolve_slope_value(prepass_channels, channels)
	var width_scale: float = lerpf(0.62, 0.38, slope_value)
	return maxf(0.9, river_width * width_scale)

func _resolve_bank_outer_radius_tiles(
	structure_context: WorldStructureContext,
	prepass_channels: WorldPrePassChannels = null,
	channels: WorldChannels = null
) -> float:
	if structure_context == null:
		return 0.0
	var river_width: float = maxf(0.0, structure_context.river_width)
	var floodplain_strength: float = clampf(structure_context.floodplain_strength, 0.0, 1.0)
	if river_width <= 0.0 and floodplain_strength <= 0.0:
		return 0.0
	var slope_value: float = _resolve_slope_value(prepass_channels, channels)
	var river_core_radius: float = _resolve_river_core_radius_tiles(structure_context, prepass_channels, channels)
	var bank_reach: float = maxf(
		1.0,
		river_width * 0.55 + floodplain_strength * lerpf(3.4, 1.6, slope_value)
	)
	return river_core_radius + bank_reach

func _resolve_valley_carve_pressure(
	structure_context: WorldStructureContext,
	prepass_channels: WorldPrePassChannels = null,
	channels: WorldChannels = null
) -> float:
	if structure_context == null:
		return 0.0
	var river_width: float = maxf(0.0, structure_context.river_width)
	var distance_to_river: float = maxf(0.0, structure_context.river_distance)
	var floodplain_strength: float = clampf(structure_context.floodplain_strength, 0.0, 1.0)
	if river_width <= 0.0 and floodplain_strength <= 0.0:
		return 0.0
	var slope_value: float = _resolve_slope_value(prepass_channels, channels)
	var carve_radius: float = maxf(
		2.0,
		river_width * lerpf(1.0, 1.45, slope_value)
			+ floodplain_strength * lerpf(2.6, 1.8, slope_value)
	)
	var t: float = clampf(1.0 - distance_to_river / carve_radius, 0.0, 1.0)
	var proximity_pressure: float = t * t * (3.0 - 2.0 * t)
	return maxf(proximity_pressure, floodplain_strength * 0.85)

func _resolve_surface_terrain_sq(
	distance_from_spawn_sq: float,
	channels: WorldChannels,
	structure_context: WorldStructureContext,
	prepass_channels: WorldPrePassChannels = null,
	local_variation: LocalVariationContext = null
) -> int:
	if distance_from_spawn_sq <= _safe_radius_sq:
		return TileGenData.TerrainType.GROUND
	if _is_river_core_tile_sq(
		distance_from_spawn_sq,
		channels,
		structure_context,
		prepass_channels,
		local_variation
	):
		return TileGenData.TerrainType.WATER
	if _is_bank_floodplain_tile_sq(
		distance_from_spawn_sq,
		channels,
		structure_context,
		prepass_channels,
		local_variation
	):
		return TileGenData.TerrainType.SAND
	if _is_mountain_core_tile_sq(
		distance_from_spawn_sq,
		channels,
		structure_context,
		prepass_channels,
		local_variation
	):
		return TileGenData.TerrainType.ROCK
	if _is_foothill_tile_sq(
		distance_from_spawn_sq,
		channels,
		structure_context,
		prepass_channels,
		local_variation
	):
		return TileGenData.TerrainType.ROCK
	return TileGenData.TerrainType.GROUND

func _is_river_core_tile_sq(
	distance_from_spawn_sq: float,
	channels: WorldChannels,
	structure_context: WorldStructureContext,
	prepass_channels: WorldPrePassChannels = null,
	local_variation: LocalVariationContext = null
) -> bool:
	if structure_context == null:
		return false
	if distance_from_spawn_sq <= _land_guarantee_radius_sq:
		return false
	var river_width: float = maxf(0.0, structure_context.river_width)
	if river_width <= 0.0:
		return false
	var distance_to_river: float = maxf(0.0, structure_context.river_distance)
	var river_core_radius: float = _resolve_river_core_radius_tiles(structure_context, prepass_channels, channels)
	if river_core_radius <= 0.0 or distance_to_river > river_core_radius:
		return false
	var wetness_bonus: float = local_variation.wetness_modulation if local_variation != null else 0.0
	var rockiness_penalty: float = local_variation.rockiness_modulation if local_variation != null else 0.0
	var effective_river_strength: float = structure_context.river_strength + structure_context.floodplain_strength * 0.10
	effective_river_strength += wetness_bonus * 0.10 - rockiness_penalty * 0.04
	if effective_river_strength < _balance.river_min_strength * 0.75:
		return false
	if channels == null:
		return true
	var slope_value: float = _resolve_slope_value(prepass_channels, channels)
	var allowed_height: float = _balance.river_max_height + river_width * 0.08 + (1.0 - slope_value) * 0.08
	if channels.height > allowed_height:
		return false
	return true

func _is_bank_floodplain_tile_sq(
	distance_from_spawn_sq: float,
	channels: WorldChannels,
	structure_context: WorldStructureContext,
	prepass_channels: WorldPrePassChannels = null,
	local_variation: LocalVariationContext = null
) -> bool:
	if structure_context == null:
		return false
	if distance_from_spawn_sq <= _land_guarantee_radius_sq:
		return false
	if _is_river_core_tile_sq(
		distance_from_spawn_sq,
		channels,
		structure_context,
		prepass_channels,
		local_variation
	):
		return false
	var distance_to_river: float = maxf(0.0, structure_context.river_distance)
	var bank_outer_radius: float = _resolve_bank_outer_radius_tiles(structure_context, prepass_channels, channels)
	if bank_outer_radius <= 0.0 or distance_to_river > bank_outer_radius:
		return false
	var wetness_bonus: float = local_variation.wetness_modulation if local_variation != null else 0.0
	var rockiness_penalty: float = local_variation.rockiness_modulation if local_variation != null else 0.0
	var slope_value: float = _resolve_slope_value(prepass_channels, channels)
	var effective_floodplain: float = structure_context.floodplain_strength + wetness_bonus * 0.08 - rockiness_penalty * 0.02
	if effective_floodplain < _balance.bank_min_floodplain * 0.55:
		return false
	if structure_context.ridge_strength > (_balance.bank_ridge_exclusion + 0.16) and slope_value > 0.60:
		return false
	if channels == null:
		return true
	var allowed_height: float = _balance.bank_max_height + structure_context.river_width * 0.05 + (1.0 - slope_value) * 0.06
	if channels.height > allowed_height:
		return false
	var effective_river_strength: float = structure_context.river_strength + wetness_bonus * 0.08
	return effective_river_strength >= _balance.bank_min_river * 0.75 \
		or channels.moisture + wetness_bonus * 0.10 > _balance.bank_min_moisture * 0.90

func _is_mountain_core_tile_sq(
	distance_from_spawn_sq: float,
	channels: WorldChannels = null,
	structure_context: WorldStructureContext = null,
	prepass_channels: WorldPrePassChannels = null,
	local_variation: LocalVariationContext = null
) -> bool:
	if structure_context == null:
		return false
	if distance_from_spawn_sq <= _land_guarantee_radius_sq:
		return false
	var ridge_strength: float = structure_context.ridge_strength
	var mountain_mass: float = structure_context.mountain_mass
	if ridge_strength < 0.20 and mountain_mass < 0.18:
		return false
	var slope_value: float = _resolve_slope_value(prepass_channels, channels)
	var ruggedness_gate: float = slope_value
	var terrain_gate: float = 1.0
	if channels != null:
		ruggedness_gate = clampf(channels.ruggedness * 0.55 + slope_value * 0.45, 0.0, 1.0)
		terrain_gate = clampf(channels.height * 0.34 + ruggedness_gate * 0.42 + slope_value * 0.28, 0.18, 1.0)
	var valley_carve: float = _resolve_valley_carve_pressure(structure_context, prepass_channels, channels)
	var combined: float = ridge_strength * _ridge_backbone_weight
	combined += mountain_mass * (_massif_fill_weight + 0.12)
	combined += maxf(0.0, ridge_strength - 0.58) * _core_bonus_weight
	combined += maxf(0.0, slope_value - 0.34) * 0.18
	combined += ruggedness_gate * 0.10
	combined -= valley_carve * 0.30
	combined -= structure_context.floodplain_strength * 0.08
	if local_variation != null:
		combined += local_variation.rockiness_modulation * 0.08
		combined -= local_variation.wetness_modulation * 0.05
		combined -= local_variation.openness_modulation * 0.05
	combined *= terrain_gate
	return combined >= _mountain_threshold_value

func _is_foothill_tile_sq(
	distance_from_spawn_sq: float,
	channels: WorldChannels = null,
	structure_context: WorldStructureContext = null,
	prepass_channels: WorldPrePassChannels = null,
	local_variation: LocalVariationContext = null
) -> bool:
	if structure_context == null:
		return false
	if distance_from_spawn_sq <= _land_guarantee_radius_sq:
		return false
	var slope_value: float = _resolve_slope_value(prepass_channels, channels)
	var ridge_strength: float = structure_context.ridge_strength
	var mountain_mass: float = structure_context.mountain_mass
	if maxf(ridge_strength * 0.75, mountain_mass) < 0.18 and slope_value < 0.32:
		return false
	var ruggedness_gate: float = slope_value
	if channels != null:
		ruggedness_gate = clampf(channels.ruggedness * 0.60 + slope_value * 0.40, 0.0, 1.0)
	var combined: float = ridge_strength * 0.26
	combined += mountain_mass * 0.28
	combined += slope_value * 0.26
	combined += ruggedness_gate * 0.12
	if channels != null:
		combined += maxf(0.0, channels.height - 0.42) * 0.12
	combined -= _resolve_valley_carve_pressure(structure_context, prepass_channels, channels) * 0.38
	combined -= structure_context.floodplain_strength * 0.10
	if local_variation != null:
		combined += local_variation.rockiness_modulation * 0.06
		combined -= local_variation.wetness_modulation * 0.03
		combined -= local_variation.openness_modulation * 0.05
	return combined >= _mountain_threshold_value * 0.72

func _distance_from_spawn_sq(canonical_tile: Vector2i, spawn_tile: Vector2i) -> float:
	var dx: float = float(_world_context.tile_wrap_delta_x(canonical_tile.x, spawn_tile.x))
	var dy: float = float(canonical_tile.y - spawn_tile.y)
	return dx * dx + dy * dy
