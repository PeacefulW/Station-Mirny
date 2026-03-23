class_name WorldGeneratorSingleton
extends Node

## Генератор мира. Собирает ground/rock карту процедурно в GDScript.
## DLL остаётся доступной для будущих фаз, но горы сейчас строятся локально.

const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"
const BIOME_PATH: String = "res://data/biomes/plains_biome.tres"

var world_seed: int = 0
var balance: WorldGenBalance = null
var current_biome: BiomeData = null
var spawn_tile: Vector2i = Vector2i.ZERO
var _is_initialized: bool = false
var _native_generator: ChunkGenerator = null
var _height_noise: FastNoiseLite = FastNoiseLite.new()
var _mountain_blob_noise: FastNoiseLite = FastNoiseLite.new()
var _mountain_chain_noise: FastNoiseLite = FastNoiseLite.new()
var _mountain_detail_noise: FastNoiseLite = FastNoiseLite.new()

func _ready() -> void:
	balance = load(BALANCE_PATH) as WorldGenBalance
	if not balance:
		push_error(Localization.t("SYSTEM_WORLD_BALANCE_LOAD_FAILED", {"path": BALANCE_PATH}))
		return
	current_biome = load(BIOME_PATH) as BiomeData

func initialize_world(seed_value: int) -> void:
	world_seed = seed_value
	_setup_native_generator()
	_setup_noise()
	_is_initialized = true
	EventBus.world_seed_set.emit(world_seed)

func initialize_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	initialize_world(rng.randi())

func get_chunk_data_native(chunk_coord: Vector2i) -> Dictionary:
	if not _is_initialized or not _native_generator:
		return {}
	return _native_generator.generate_chunk(chunk_coord, spawn_tile)

func get_chunk_data(chunk_coord: Vector2i) -> Dictionary:
	var chunk_size: int = balance.chunk_size_tiles
	var terrain := PackedByteArray()
	var height := PackedFloat32Array()
	terrain.resize(chunk_size * chunk_size)
	height.resize(chunk_size * chunk_size)
	var base_x: int = chunk_coord.x * chunk_size
	var base_y: int = chunk_coord.y * chunk_size
	var safe_r: float = float(balance.safe_zone_radius)
	var spawn_x: int = spawn_tile.x
	var spawn_y: int = spawn_tile.y
	for local_y: int in range(chunk_size):
		var tile_y: int = base_y + local_y
		var dy: float = float(tile_y - spawn_y)
		for local_x: int in range(chunk_size):
			var tile_x: int = base_x + local_x
			var idx: int = local_y * chunk_size + local_x
			var h: float = _sample01(_height_noise.get_noise_2d(tile_x, tile_y))
			height[idx] = h
			var dx: float = float(tile_x - spawn_x)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= safe_r:
				terrain[idx] = TileGenData.TerrainType.GROUND
			elif _is_mountain_tile(tile_x, tile_y, dist):
				terrain[idx] = TileGenData.TerrainType.ROCK
			else:
				terrain[idx] = TileGenData.TerrainType.GROUND
	return {
		"chunk_size": chunk_size,
		"terrain": terrain,
		"height": height,
	}

func get_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	if not _is_initialized:
		return TileGenData.new()
	return _generate_tile_data(tile_x, tile_y)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / balance.tile_size),
		floori(world_pos.y / balance.tile_size)
	)

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	var ts: float = float(balance.tile_size)
	return Vector2(tile_pos.x * ts + ts * 0.5, tile_pos.y * ts + ts * 0.5)

func world_to_chunk(world_pos: Vector2) -> Vector2i:
	var cp: int = balance.get_chunk_size_pixels()
	return Vector2i(floori(world_pos.x / cp), floori(world_pos.y / cp))

func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	var cs: int = balance.chunk_size_tiles
	return Vector2i(
		floori(float(tile_pos.x) / cs),
		floori(float(tile_pos.y) / cs)
	)

func is_walkable_at(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = world_to_tile(world_pos)
	var tile_data: TileGenData = get_tile_data(tile_pos.x, tile_pos.y)
	return tile_data.terrain != TileGenData.TerrainType.ROCK

func _setup_native_generator() -> void:
	_native_generator = ChunkGenerator.new()
	var params: Dictionary = {
		"chunk_size": balance.chunk_size_tiles,
		"rock_threshold": 0.0,
		"warp_strength": 0.0,
		"ridge_weight": 0.0,
		"continental_weight": 0.0,
		"safe_zone_radius": balance.safe_zone_radius,
		"land_guarantee_radius": balance.land_guarantee_radius,
		"height_frequency": balance.height_frequency,
		"height_octaves": balance.height_octaves,
		"warp_frequency": 0.0,
		"ridge_frequency": 0.0,
		"continental_frequency": 0.0,
	}
	_native_generator.initialize(world_seed, params)

func _setup_noise() -> void:
	_setup_noise_instance(_height_noise, world_seed + 11, balance.height_frequency, balance.height_octaves)
	_setup_noise_instance(_mountain_blob_noise, world_seed + 29, _blob_frequency(), 3)
	_setup_noise_instance(_mountain_chain_noise, world_seed + 47, balance.mountain_chain_frequency, 3)
	_setup_noise_instance(_mountain_detail_noise, world_seed + 71, balance.mountain_detail_frequency, 2)

func _setup_noise_instance(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.55
	noise.fractal_lacunarity = 2.1
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

func _generate_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	var data := TileGenData.new()
	var distance_from_spawn: float = Vector2(tile_x - spawn_tile.x, tile_y - spawn_tile.y).length()
	data.height = _sample01(_height_noise.get_noise_2d(tile_x, tile_y))
	data.distance_from_spawn = distance_from_spawn
	data.terrain = TileGenData.TerrainType.GROUND
	if distance_from_spawn <= float(balance.safe_zone_radius):
		return data
	if _is_mountain_tile(tile_x, tile_y, distance_from_spawn):
		data.terrain = TileGenData.TerrainType.ROCK
	return data

func _is_mountain_tile(tile_x: int, tile_y: int, distance_from_spawn: float) -> bool:
	if distance_from_spawn <= float(balance.land_guarantee_radius):
		return false
	var blob: float = _sample01(_mountain_blob_noise.get_noise_2d(tile_x, tile_y))
	var chain_value: float = 1.0 - absf(_mountain_chain_noise.get_noise_2d(tile_x, tile_y))
	var detail: float = _sample01(_mountain_detail_noise.get_noise_2d(tile_x, tile_y))
	var combined: float = lerpf(blob, chain_value, balance.mountain_chaininess)
	combined = lerpf(combined, detail, 0.18)
	return combined >= _mountain_threshold()

func _mountain_threshold() -> float:
	return clampf(0.74 - balance.mountain_density, 0.32, 0.78)

func _blob_frequency() -> float:
	match balance.mountain_area:
		1:
			return balance.mountain_blob_frequency * 1.45
		2:
			return balance.mountain_blob_frequency
		3:
			return balance.mountain_blob_frequency * 0.65
	return balance.mountain_blob_frequency

func _sample01(value: float) -> float:
	return value * 0.5 + 0.5
