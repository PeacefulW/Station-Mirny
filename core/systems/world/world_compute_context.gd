class_name WorldComputeContext
extends RefCounted

const WorldNoiseUtilsScript = preload("res://core/systems/world/world_noise_utils.gd")

var balance: WorldGenBalance = null
var world_seed: int = 0
var spawn_tile: Vector2i = Vector2i.ZERO
var current_biome: BiomeData = null

var _default_biome: BiomeData = null
var _planet_sampler: PlanetSampler = null
var _biome_resolver: BiomeResolver = null
var _local_variation_resolver: LocalVariationResolver = null
var _surface_terrain_resolver: RefCounted = null
var _world_pre_pass: RefCounted = null
var _biome_by_id: Dictionary = {}
var _palette_index_by_id: Dictionary = {}
var _default_palette_index: int = 0
var _feature_hook_snapshot: Array[Resource] = []

func configure(
	balance_resource: WorldGenBalance,
	world_seed_value: int,
	spawn_tile_value: Vector2i,
	current_biome_value: BiomeData,
	default_biome: BiomeData,
	planet_sampler: PlanetSampler,
	biome_resolver: BiomeResolver,
	local_variation_resolver: LocalVariationResolver,
	biome_by_id: Dictionary,
	palette_index_by_id: Dictionary,
	feature_hook_snapshot: Array[Resource],
	world_pre_pass: RefCounted
) -> WorldComputeContext:
	assert(world_pre_pass != null, "WorldComputeContext requires WorldPrePass for authoritative GDScript structure sampling")
	balance = balance_resource
	world_seed = world_seed_value
	spawn_tile = spawn_tile_value
	current_biome = current_biome_value
	_default_biome = default_biome
	_planet_sampler = planet_sampler
	_biome_resolver = biome_resolver
	_local_variation_resolver = local_variation_resolver
	_world_pre_pass = world_pre_pass
	_biome_by_id = biome_by_id.duplicate()
	_palette_index_by_id = palette_index_by_id.duplicate()
	_default_palette_index = int(_palette_index_by_id.get(default_biome.id if default_biome else &"", 0))
	_feature_hook_snapshot = feature_hook_snapshot.duplicate()
	return self

func set_surface_terrain_resolver(surface_terrain_resolver: RefCounted) -> WorldComputeContext:
	_surface_terrain_resolver = surface_terrain_resolver
	return self

func sample_world_channels(world_pos: Vector2i) -> WorldChannels:
	if _planet_sampler == null:
		return WorldChannels.new()
	return _planet_sampler.sample_world_channels(world_pos)

func sample_structure_context(world_pos: Vector2i, channels: WorldChannels = null) -> WorldStructureContext:
	var sampled := WorldStructureContext.new()
	sampled.world_pos = world_pos
	sampled.canonical_world_pos = canonicalize_tile(world_pos)
	if _world_pre_pass == null or not _world_pre_pass.has_method("sample"):
		push_error("WorldComputeContext.sample_structure_context() requires a published WorldPrePass snapshot")
		assert(false, "WorldComputeContext.sample_structure_context() requires WorldPrePass as the only authoritative structure source")
		return sampled.clamp_fields()
	sampled.ridge_strength = _sample_prepass_value(WorldPrePass.RIDGE_STRENGTH_CHANNEL, sampled.canonical_world_pos)
	sampled.mountain_mass = _sample_prepass_value(WorldPrePass.MOUNTAIN_MASS_CHANNEL, sampled.canonical_world_pos)
	sampled.floodplain_strength = _sample_prepass_value(WorldPrePass.FLOODPLAIN_STRENGTH_CHANNEL, sampled.canonical_world_pos)
	sampled.river_distance = _sample_prepass_value(WorldPrePass.RIVER_DISTANCE_CHANNEL, sampled.canonical_world_pos)
	sampled.river_width = _sample_prepass_value(WorldPrePass.RIVER_WIDTH_CHANNEL, sampled.canonical_world_pos)
	sampled.river_strength = _derive_river_strength_from_prepass(sampled.river_width, sampled.river_distance)
	return sampled.clamp_fields()

func sample_prepass_channels(world_pos: Vector2i) -> WorldPrePassChannels:
	var sampled := WorldPrePassChannels.new()
	sampled.world_pos = world_pos
	sampled.canonical_world_pos = canonicalize_tile(world_pos)
	if _world_pre_pass == null or not _world_pre_pass.has_method("sample"):
		push_error("WorldComputeContext.sample_prepass_channels() requires a published WorldPrePass snapshot")
		assert(false, "WorldComputeContext.sample_prepass_channels() requires WorldPrePass as the only authoritative pre-pass source")
		return sampled
	sampled.drainage = _sample_prepass_value(WorldPrePass.DRAINAGE_CHANNEL, sampled.canonical_world_pos)
	sampled.slope = _sample_prepass_value(WorldPrePass.SLOPE_CHANNEL, sampled.canonical_world_pos)
	sampled.rain_shadow = _sample_prepass_value(WorldPrePass.RAIN_SHADOW_CHANNEL, sampled.canonical_world_pos)
	sampled.continentalness = _sample_prepass_value(WorldPrePass.CONTINENTALNESS_CHANNEL, sampled.canonical_world_pos)
	return sampled.clamp_fields()

func sample_local_variation(
	world_pos: Vector2i,
	biome: BiomeResult = null,
	channels: WorldChannels = null,
	structure_context: WorldStructureContext = null
) -> LocalVariationContext:
	var canonical_tile: Vector2i = canonicalize_tile(world_pos)
	var sampled_channels: WorldChannels = channels
	if sampled_channels == null:
		sampled_channels = sample_world_channels(canonical_tile)
	var sampled_structure_context: WorldStructureContext = structure_context
	if sampled_structure_context == null:
		sampled_structure_context = sample_structure_context(canonical_tile, sampled_channels)
	var resolved_biome: BiomeResult = biome
	if resolved_biome == null:
		resolved_biome = get_biome_result_at_tile(canonical_tile, sampled_channels, sampled_structure_context)
	if _local_variation_resolver:
		return _local_variation_resolver.resolve_local_variation(
			canonical_tile,
			resolved_biome,
			sampled_channels,
			sampled_structure_context
		)
	return LocalVariationContext.new()

func get_biome_result_at_tile(
	tile_pos: Vector2i,
	channels: WorldChannels = null,
	structure_context: WorldStructureContext = null
) -> BiomeResult:
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	var sampled_channels: WorldChannels = channels
	if sampled_channels == null:
		sampled_channels = sample_world_channels(canonical_tile)
	var sampled_structure_context: WorldStructureContext = structure_context
	if sampled_structure_context == null:
		sampled_structure_context = sample_structure_context(canonical_tile, sampled_channels)
	return resolve_biome(canonical_tile, sampled_channels, sampled_structure_context)

func resolve_biome(
	world_pos: Vector2i,
	channels: WorldChannels = null,
	structure_context: WorldStructureContext = null
) -> BiomeResult:
	var canonical_tile: Vector2i = canonicalize_tile(world_pos)
	var sampled_channels: WorldChannels = channels
	if sampled_channels == null:
		sampled_channels = sample_world_channels(canonical_tile)
	var sampled_structure_context: WorldStructureContext = structure_context
	if sampled_structure_context == null:
		sampled_structure_context = sample_structure_context(canonical_tile, sampled_channels)
	var sampled_prepass_channels: WorldPrePassChannels = sample_prepass_channels(canonical_tile)
	if _biome_resolver:
		return _biome_resolver.resolve_biome(
			canonical_tile,
			sampled_channels,
			sampled_structure_context,
			sampled_prepass_channels,
			balance
		)
	return null

func get_biome_at_tile(tile_pos: Vector2i) -> BiomeData:
	var result: BiomeResult = get_biome_result_at_tile(tile_pos)
	if result:
		var biome: BiomeData = result.biome as BiomeData
		if biome:
			return biome
	return _resolve_default_biome()

func get_biome_by_id(biome_id: StringName) -> BiomeData:
	if biome_id == &"":
		return null
	return _biome_by_id.get(biome_id, null) as BiomeData

func get_biome_palette_index(biome_id: StringName) -> int:
	if biome_id == &"":
		return _default_palette_index
	var idx: Variant = _palette_index_by_id.get(biome_id, null)
	if idx != null:
		return int(idx)
	return BiomeRegistry.get_palette_index(biome_id) if BiomeRegistry else _default_palette_index

func get_world_seed() -> int:
	return world_seed

func get_world_pre_pass() -> RefCounted:
	return _world_pre_pass

func get_feature_hook_snapshot() -> Array[Resource]:
	var result: Array[Resource] = []
	for feature_hook: Resource in _feature_hook_snapshot:
		result.append(feature_hook)
	return result

func get_surface_terrain_type(tile_pos: Vector2i) -> int:
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	if _surface_terrain_resolver == null:
		return TileGenData.TerrainType.GROUND
	return _surface_terrain_resolver.sample_terrain_type(canonical_tile.x, canonical_tile.y)

func get_surface_terrain_type_from_context(
	tile_pos: Vector2i,
	channels: WorldChannels,
	structure_context: WorldStructureContext,
	local_variation: LocalVariationContext = null
) -> int:
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	if _surface_terrain_resolver == null:
		return TileGenData.TerrainType.GROUND
	if _surface_terrain_resolver.has_method("resolve_surface_terrain_type_from_context"):
		return int(_surface_terrain_resolver.call(
			"resolve_surface_terrain_type_from_context",
			canonical_tile,
			channels,
			structure_context,
			local_variation
		))
	return get_surface_terrain_type(canonical_tile)

func canonicalize_tile(tile_pos: Vector2i) -> Vector2i:
	if _planet_sampler == null:
		return tile_pos
	return _planet_sampler.canonicalize_world_pos(tile_pos)

func wrap_world_tile_x(tile_x: int) -> int:
	if _planet_sampler == null:
		return tile_x
	return _planet_sampler.wrap_world_x(tile_x)

func get_world_wrap_width_tiles() -> int:
	if _planet_sampler:
		return _planet_sampler.get_wrap_width_tiles()
	if balance == null:
		return 0
	return WorldNoiseUtilsScript.resolve_wrap_width_tiles(balance)

func get_world_wrap_chunk_count() -> int:
	if balance == null:
		return 0
	return maxi(1, int(get_world_wrap_width_tiles() / balance.chunk_size_tiles))

func wrap_chunk_x(chunk_x: int) -> int:
	var chunk_count: int = get_world_wrap_chunk_count()
	if chunk_count <= 0:
		return chunk_x
	return int(posmod(chunk_x, chunk_count))

func canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(wrap_chunk_x(chunk_coord.x), chunk_coord.y)

func tile_wrap_delta_x(tile_x: int, reference_x: int) -> int:
	var wrap_width: int = get_world_wrap_width_tiles()
	if wrap_width <= 0:
		return tile_x - reference_x
	var delta: int = wrap_world_tile_x(tile_x) - wrap_world_tile_x(reference_x)
	var half_width: int = wrap_width / 2
	if delta > half_width:
		delta -= wrap_width
	elif delta < -half_width:
		delta += wrap_width
	return delta

func chunk_wrap_delta_x(chunk_x: int, reference_chunk_x: int) -> int:
	var chunk_count: int = get_world_wrap_chunk_count()
	if chunk_count <= 0:
		return chunk_x - reference_chunk_x
	var delta: int = wrap_chunk_x(chunk_x) - wrap_chunk_x(reference_chunk_x)
	var half_width: int = chunk_count / 2
	if delta > half_width:
		delta -= chunk_count
	elif delta < -half_width:
		delta += chunk_count
	return delta

func chunk_to_tile_origin(chunk_coord: Vector2i) -> Vector2i:
	if balance == null:
		return Vector2i.ZERO
	var canonical_chunk: Vector2i = canonicalize_chunk_coord(chunk_coord)
	return Vector2i(
		canonical_chunk.x * balance.chunk_size_tiles,
		canonical_chunk.y * balance.chunk_size_tiles
	)

func tile_to_local_in_chunk(tile_pos: Vector2i, chunk_coord: Vector2i) -> Vector2i:
	var canonical_tile: Vector2i = canonicalize_tile(tile_pos)
	var chunk_origin: Vector2i = chunk_to_tile_origin(chunk_coord)
	return Vector2i(
		canonical_tile.x - chunk_origin.x,
		canonical_tile.y - chunk_origin.y
	)

func chunk_local_to_tile(chunk_coord: Vector2i, local_tile: Vector2i) -> Vector2i:
	return canonicalize_tile(chunk_to_tile_origin(chunk_coord) + local_tile)

func offset_tile(tile_pos: Vector2i, offset: Vector2i) -> Vector2i:
	return canonicalize_tile(tile_pos + offset)

func offset_chunk_coord(chunk_coord: Vector2i, offset: Vector2i) -> Vector2i:
	return canonicalize_chunk_coord(chunk_coord + offset)

func _resolve_default_biome() -> BiomeData:
	if current_biome:
		return current_biome
	return _default_biome

func _sample_prepass_value(channel: StringName, canonical_world_pos: Vector2i) -> float:
	if _world_pre_pass == null or not _world_pre_pass.has_method("sample"):
		return 0.0
	return float(_world_pre_pass.call("sample", channel, canonical_world_pos))

func _derive_river_strength_from_prepass(river_width: float, river_distance: float) -> float:
	var width_strength: float = clampf((maxf(0.0, river_width) + 1.0) / 6.0, 0.0, 1.0)
	if river_distance <= 0.001 and river_width > 0.0:
		return maxf(width_strength, 0.55)
	return width_strength

