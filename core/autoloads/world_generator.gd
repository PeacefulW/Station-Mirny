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
	var native_data: Dictionary = get_chunk_data_native(chunk_coord)
	if native_data.is_empty():
		return native_data
	var terrain: PackedByteArray = native_data.get("terrain", PackedByteArray())
	for idx: int in range(terrain.size()):
		terrain[idx] = 0
	native_data["terrain"] = terrain
	native_data.erase("is_mountain")
	native_data.erase("cluster_id")
	native_data.erase("has_roof")
	native_data.erase("is_edge")
	return native_data

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
	return true

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
	}
	_native_generator.initialize(world_seed, params)
