class_name ChunkContentBuilder
extends RefCounted

const CHUNK_BUILD_RESULT_SCRIPT := preload("res://core/systems/world/chunk_build_result.gd")
const LOCAL_VARIATION_CONTEXT_SCRIPT := preload("res://core/systems/world/local_variation_context.gd")

var _world_provider = null
var _world_seed: int = 0
var _balance: WorldGenBalance = null
var _mountain_blob_noise: FastNoiseLite = FastNoiseLite.new()
var _mountain_detail_noise: FastNoiseLite = FastNoiseLite.new()

func initialize(seed_value: int, balance_resource: WorldGenBalance, world_provider) -> void:
	_world_seed = seed_value
	_balance = balance_resource
	_world_provider = world_provider
	if not _balance:
		return
	_setup_noise_instance(_mountain_blob_noise, _world_seed + 29, _blob_frequency(), 3)
	_setup_noise_instance(_mountain_detail_noise, _world_seed + 71, _balance.mountain_detail_frequency, 2)

func build_chunk(chunk_coord: Vector2i):
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	var base_tile: Vector2i = _chunk_to_tile_origin(canonical_chunk)
	var result = CHUNK_BUILD_RESULT_SCRIPT.new().initialize(canonical_chunk, _chunk_size(), base_tile)
	if not result.is_valid():
		return result
	var safe_radius: float = float(_balance.safe_zone_radius) if _balance else 0.0
	var spawn_tile: Vector2i = _spawn_tile()
	for local_y: int in range(result.chunk_size):
		for local_x: int in range(result.chunk_size):
			var tile_pos: Vector2i = Vector2i(base_tile.x + local_x, base_tile.y + local_y)
			var tile_data: TileGenData = _build_tile_data(_canonicalize_tile(tile_pos), spawn_tile, safe_radius)
			var index: int = local_y * result.chunk_size + local_x
			result.set_tile(index, tile_data.terrain, tile_data.height, tile_data.local_variation_id)
	return result

func build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary:
	var build_result = build_chunk(chunk_coord)
	if not build_result or not build_result.is_valid():
		return {}
	return build_result.to_native_data()

func build_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	return _build_tile_data(
		_canonicalize_tile(Vector2i(tile_x, tile_y)),
		_spawn_tile(),
		float(_balance.safe_zone_radius) if _balance else 0.0
	)

func _build_tile_data(canonical_tile: Vector2i, spawn_tile: Vector2i, safe_radius: float) -> TileGenData:
	var data := TileGenData.new()
	data.canonical_world_pos = canonical_tile
	if _world_provider == null:
		return data
	var channels = _world_provider.sample_world_channels(canonical_tile)
	var structure_context = _world_provider.sample_structure_context(canonical_tile, channels)
	var biome_result = _world_provider.get_biome_result_at_tile(canonical_tile, channels, structure_context)
	var local_variation = _world_provider.sample_local_variation(canonical_tile, biome_result, channels, structure_context)
	var distance_from_spawn: float = Vector2(_tile_wrap_delta_x(canonical_tile.x, spawn_tile.x), canonical_tile.y - spawn_tile.y).length()
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
	elif _world_provider.current_biome:
		data.biome_id = _world_provider.current_biome.id
	data.temperature = channels.temperature
	data.moisture = channels.moisture
	data.ruggedness = channels.ruggedness
	data.flora_density = channels.flora_density
	data.latitude = channels.latitude
	data.distance_from_spawn = distance_from_spawn
	data.terrain = _resolve_surface_terrain(
		canonical_tile,
		distance_from_spawn,
		channels,
		structure_context,
		safe_radius
	)
	if data.terrain == TileGenData.TerrainType.GROUND and local_variation:
		data.local_variation_kind = local_variation.variation_kind
		data.local_variation_id = LOCAL_VARIATION_CONTEXT_SCRIPT.kind_to_variation_id(local_variation.variation_kind)
		data.local_variation_score = local_variation.variation_score
		data.flora_modulation = local_variation.flora_modulation
		data.wetness_modulation = local_variation.wetness_modulation
		data.rockiness_modulation = local_variation.rockiness_modulation
		data.openness_modulation = local_variation.openness_modulation
	return data

func _resolve_surface_terrain(
	tile_pos: Vector2i,
	distance_from_spawn: float,
	channels,
	structure_context,
	safe_radius: float
) -> int:
	if distance_from_spawn <= safe_radius:
		return TileGenData.TerrainType.GROUND
	if _is_river_tile(distance_from_spawn, channels, structure_context):
		return TileGenData.TerrainType.WATER
	if _is_river_bank_tile(distance_from_spawn, channels, structure_context):
		return TileGenData.TerrainType.SAND
	if _is_mountain_tile(tile_pos.x, tile_pos.y, distance_from_spawn, channels, structure_context):
		return TileGenData.TerrainType.ROCK
	return TileGenData.TerrainType.GROUND

func _is_mountain_tile(tile_x: int, tile_y: int, distance_from_spawn: float, channels = null, structure_context = null) -> bool:
	if distance_from_spawn <= float(_balance.land_guarantee_radius):
		return false
	var ridge_strength: float = structure_context.ridge_strength if structure_context else 0.0
	var mountain_mass: float = structure_context.mountain_mass if structure_context else 0.0
	var blob: float = _sample01(_mountain_blob_noise.get_noise_2d(tile_x, tile_y))
	var detail: float = _sample01(_mountain_detail_noise.get_noise_2d(tile_x, tile_y))
	var terrain_gate: float = 1.0
	if channels != null:
		terrain_gate = clampf(channels.height * 0.45 + channels.ruggedness * 0.85 - 0.18, 0.20, 1.0)
	var combined: float = ridge_strength * 0.72 + mountain_mass * 0.20 + detail * 0.05 + blob * 0.03
	combined *= terrain_gate
	return combined >= _mountain_threshold()

func _is_river_tile(distance_from_spawn: float, channels, structure_context) -> bool:
	if structure_context == null:
		return false
	if distance_from_spawn <= float(_balance.land_guarantee_radius):
		return false
	if structure_context.river_strength < 0.60:
		return false
	if structure_context.ridge_strength > 0.48:
		return false
	if channels != null and channels.height > 0.62:
		return false
	return true

func _is_river_bank_tile(distance_from_spawn: float, channels, structure_context) -> bool:
	if structure_context == null:
		return false
	if distance_from_spawn <= float(_balance.land_guarantee_radius):
		return false
	if _is_river_tile(distance_from_spawn, channels, structure_context):
		return false
	if structure_context.floodplain_strength < 0.58:
		return false
	if structure_context.ridge_strength > 0.42:
		return false
	if structure_context.river_strength >= 0.28:
		return true
	return channels != null and channels.moisture > 0.65 and channels.height < 0.50

func _mountain_threshold() -> float:
	return clampf(0.74 - _balance.mountain_density, 0.32, 0.78)

func _blob_frequency() -> float:
	match _balance.mountain_area:
		1:
			return _balance.mountain_blob_frequency * 1.45
		2:
			return _balance.mountain_blob_frequency
		3:
			return _balance.mountain_blob_frequency * 0.65
	return _balance.mountain_blob_frequency

func _setup_noise_instance(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.55
	noise.fractal_lacunarity = 2.1
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

func _chunk_size() -> int:
	return _balance.chunk_size_tiles if _balance else 0

func _spawn_tile() -> Vector2i:
	if _world_provider:
		return _world_provider.spawn_tile
	return Vector2i.ZERO

func _canonicalize_tile(tile_pos: Vector2i) -> Vector2i:
	if _world_provider:
		return _world_provider.canonicalize_tile(tile_pos)
	return tile_pos

func _canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	if _world_provider:
		return _world_provider.canonicalize_chunk_coord(chunk_coord)
	return chunk_coord

func _chunk_to_tile_origin(chunk_coord: Vector2i) -> Vector2i:
	if _world_provider:
		return _world_provider.chunk_to_tile_origin(chunk_coord)
	return Vector2i.ZERO

func _tile_wrap_delta_x(tile_x: int, reference_x: int) -> int:
	if _world_provider:
		return _world_provider.tile_wrap_delta_x(tile_x, reference_x)
	return tile_x - reference_x

func _sample01(value: float) -> float:
	return value * 0.5 + 0.5
