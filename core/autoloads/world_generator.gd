class_name WorldGeneratorSingleton
extends Node

## Генератор мира v8. Упрощённый: только земля + горы.
## Делегирует генерацию в C++.

const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"
const BIOME_PATH: String = "res://data/biomes/plains_biome.tres"

var world_seed: int = 0
var balance: WorldGenBalance = null
var current_biome: BiomeData = null
var spawn_tile: Vector2i = Vector2i.ZERO
var _is_initialized: bool = false
var _native_generator: ChunkGenerator = null

func _ready() -> void:
	balance = load(BALANCE_PATH) as WorldGenBalance
	if not balance:
		push_error(Localization.t("SYSTEM_WORLD_BALANCE_LOAD_FAILED", {"path": BALANCE_PATH}))
		return
	current_biome = load(BIOME_PATH) as BiomeData

func initialize_world(seed_value: int) -> void:
	world_seed = seed_value
	_setup_native_generator()
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
	return get_chunk_data_native(chunk_coord)

func get_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	if not _is_initialized:
		return TileGenData.new()
	return TileGenData.new()

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
	if not _is_initialized or not balance:
		return true
	var tile_pos: Vector2i = world_to_tile(world_pos)
	var chunk_coord: Vector2i = tile_to_chunk(tile_pos)
	var chunk_data: Dictionary = get_chunk_data_native(chunk_coord)
	if chunk_data.is_empty():
		return true
	var chunk_size: int = int(chunk_data.get("chunk_size", balance.chunk_size_tiles))
	var local_x: int = posmod(tile_pos.x, chunk_size)
	var local_y: int = posmod(tile_pos.y, chunk_size)
	var index: int = local_y * chunk_size + local_x
	var terrain: PackedByteArray = chunk_data.get("terrain", PackedByteArray())
	if index < 0 or index >= terrain.size():
		return true
	return terrain[index] != 1  # 1 = ROCK = непроходим

func _setup_native_generator() -> void:
	_native_generator = ChunkGenerator.new()
	var params: Dictionary = {
		"chunk_size": balance.chunk_size_tiles,
		"rock_threshold": balance.rock_threshold,
		"warp_strength": balance.warp_strength,
		"ridge_weight": balance.ridge_weight,
		"continental_weight": balance.continental_weight,
		"safe_zone_radius": balance.safe_zone_radius,
		"land_guarantee_radius": balance.land_guarantee_radius,
		"height_frequency": balance.height_frequency,
		"height_octaves": balance.height_octaves,
		"warp_frequency": balance.warp_frequency,
		"ridge_frequency": balance.ridge_frequency,
		"continental_frequency": balance.continental_frequency,
		"mountain_size": balance.mountain_size,
	}
	_native_generator.initialize(world_seed, params)
