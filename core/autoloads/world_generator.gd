class_name WorldGeneratorSingleton
extends Node

## Генератор мира. Autoload-синглтон.
## Использует слои FastNoiseLite для процедурной генерации.
##
## Не создаёт визуальных объектов — только отвечает на вопрос:
## «Что должно быть в точке (x, y)?»
## Визуальным заполнением занимается ChunkManager.
##
## Детерминированный: один seed → всегда один и тот же мир.
## Моды могут заменить balance для изменения параметров генерации.

# --- Сигналы ---
## (Через EventBus, не здесь — см. event_bus.gd)

# --- Константы ---
const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"
const BIOME_PATH: String = "res://data/biomes/plains_biome.tres"

# --- Публичные ---
## Текущий seed мира.
var world_seed: int = 0
## Ресурс баланса генерации.
var balance: WorldGenBalance = null
## Текущий биом (пока один, позже — выбор по координатам).
var current_biome: BiomeData = null
## Координаты точки старта игрока (в тайлах).
var spawn_tile: Vector2i = Vector2i.ZERO

# --- Приватные ---
var _noise_height: FastNoiseLite = null
var _noise_spore: FastNoiseLite = null
var _noise_resource: FastNoiseLite = null
var _noise_vegetation: FastNoiseLite = null
## Кэш для быстрого определения типа залежи по позиции.
var _deposit_rng: RandomNumberGenerator = null
var _is_initialized: bool = false

func _ready() -> void:
	balance = load(BALANCE_PATH) as WorldGenBalance
	if not balance:
		push_error("WorldGenerator: не удалось загрузить %s" % BALANCE_PATH)
		return
	current_biome = load(BIOME_PATH) as BiomeData
	if not current_biome:
		push_error("WorldGenerator: не удалось загрузить %s" % BIOME_PATH)
		return

# --- Публичные методы ---

## Инициализировать генератор с заданным seed.
## Вызывается при создании нового мира.
func initialize_world(seed_value: int) -> void:
	world_seed = seed_value
	_setup_noise_layers()
	_is_initialized = true
	EventBus.world_seed_set.emit(world_seed)

## Инициализировать со случайным seed.
func initialize_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	initialize_world(rng.randi())

## Получить данные генерации для одного тайла.
## [param tile_x] и [param tile_y] — глобальные координаты тайла.
func get_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	if not _is_initialized:
		push_error("WorldGenerator: не инициализирован. Вызови initialize_world().")
		return TileGenData.new()
	return _generate_tile(tile_x, tile_y)

## Получить данные для прямоугольной области тайлов.
## Возвращает словарь: Vector2i -> TileGenData.
## Эффективнее, чем вызывать get_tile_data по одному.
func get_area_data(start: Vector2i, size: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for x: int in range(start.x, start.x + size.x):
		for y: int in range(start.y, start.y + size.y):
			result[Vector2i(x, y)] = _generate_tile(x, y)
	return result

## Получить данные для целого чанка.
## [param chunk_coord] — координаты чанка (не тайла!).
func get_chunk_data(chunk_coord: Vector2i) -> Dictionary:
	var chunk_size: int = balance.chunk_size_tiles
	var start := Vector2i(
		chunk_coord.x * chunk_size,
		chunk_coord.y * chunk_size
	)
	return get_area_data(start, Vector2i(chunk_size, chunk_size))

## Преобразовать мировую позицию (пиксели) в координаты тайла.
func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / balance.tile_size),
		floori(world_pos.y / balance.tile_size)
	)

## Преобразовать координаты тайла в центр тайла (пиксели).
func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2(
		tile_pos.x * balance.tile_size + balance.tile_size * 0.5,
		tile_pos.y * balance.tile_size + balance.tile_size * 0.5
	)

## Преобразовать мировую позицию в координаты чанка.
func world_to_chunk(world_pos: Vector2) -> Vector2i:
	var chunk_pixels: int = balance.get_chunk_size_pixels()
	return Vector2i(
		floori(world_pos.x / chunk_pixels),
		floori(world_pos.y / chunk_pixels)
	)

## Преобразовать координаты тайла в координаты чанка.
func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile_pos.x) / balance.chunk_size_tiles),
		floori(float(tile_pos.y) / balance.chunk_size_tiles)
	)

## Получить плотность спор в мировой точке (для систем выживания).
func get_spore_density_at(world_pos: Vector2) -> float:
	if not _is_initialized:
		return 0.0
	var tile: Vector2i = world_to_tile(world_pos)
	var raw: float = _sample_noise_normalized(_noise_spore, tile.x, tile.y)
	var biome_mult: float = current_biome.spore_density_multiplier if current_biome else 1.0
	return clampf(raw * biome_mult + balance.spore_min_density, 0.0, 1.0)

## Проверить, является ли мировая точка проходимой.
func is_walkable_at(world_pos: Vector2) -> bool:
	if not _is_initialized:
		return true
	var tile: Vector2i = world_to_tile(world_pos)
	var data: TileGenData = _generate_tile(tile.x, tile.y)
	return data.terrain != TileGenData.TerrainType.WATER and \
		   data.terrain != TileGenData.TerrainType.ROCK

## Получить текущий seed.
func get_seed() -> int:
	return world_seed

# --- Приватные методы ---

## Настроить все слои шума из seed.
func _setup_noise_layers() -> void:
	_noise_height = _create_noise(
		world_seed,
		balance.height_frequency,
		balance.height_octaves
	)
	_noise_spore = _create_noise(
		world_seed + 1000,
		balance.spore_frequency,
		balance.spore_octaves
	)
	_noise_resource = _create_noise(
		world_seed + 2000,
		balance.resource_frequency,
		balance.resource_octaves
	)
	_noise_vegetation = _create_noise(
		world_seed + 3000,
		balance.vegetation_frequency,
		2
	)
	_deposit_rng = RandomNumberGenerator.new()
	_deposit_rng.seed = world_seed + 5000

## Создать настроенный объект FastNoiseLite.
func _create_noise(seed_val: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise

## Сэмплировать шум и нормализовать в диапазон 0.0 — 1.0.
## FastNoiseLite возвращает -1.0 .. 1.0, нам нужно 0.0 .. 1.0.
func _sample_noise_normalized(noise: FastNoiseLite, x: int, y: int) -> float:
	return (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5

## Сгенерировать данные для одного тайла.
func _generate_tile(tile_x: int, tile_y: int) -> TileGenData:
	var data := TileGenData.new()

	# Расстояние от точки старта
	var dx: float = float(tile_x - spawn_tile.x)
	var dy: float = float(tile_y - spawn_tile.y)
	data.distance_from_spawn = sqrt(dx * dx + dy * dy)

	# --- Высота ---
	var height_raw: float = _sample_noise_normalized(_noise_height, tile_x, tile_y)

	# Безопасная зона: гарантируем сушу вокруг спавна
	if data.distance_from_spawn < balance.land_guarantee_radius:
		var safety_factor: float = 1.0 - (data.distance_from_spawn / float(balance.land_guarantee_radius))
		# Поднимаем высоту ближе к центру, чтобы не было воды
		height_raw = lerpf(height_raw, 0.55, safety_factor * 0.8)

	data.height = height_raw

	# --- Определение типа поверхности ---
	data.terrain = _height_to_terrain(height_raw, tile_x, tile_y)

	# --- Споры ---
	var spore_raw: float = _sample_noise_normalized(_noise_spore, tile_x, tile_y)
	var biome_mult: float = current_biome.spore_density_multiplier if current_biome else 1.0
	data.spore_density = clampf(spore_raw * biome_mult + balance.spore_min_density, 0.0, 1.0)

	# Безопасная зона: меньше спор у спавна
	if data.distance_from_spawn < balance.safe_zone_radius:
		var safety: float = 1.0 - (data.distance_from_spawn / float(balance.safe_zone_radius))
		data.spore_density *= (1.0 - safety * 0.7)

	# --- Ресурсы ---
	if data.terrain == TileGenData.TerrainType.GROUND or \
	   data.terrain == TileGenData.TerrainType.GRASS:
		var res_raw: float = _sample_noise_normalized(_noise_resource, tile_x, tile_y)
		if res_raw > balance.resource_deposit_threshold:
			data.deposit = _determine_deposit_type(tile_x, tile_y, data.height)

	# Каменистые зоны тоже могут иметь руду (более вероятно)
	if data.terrain == TileGenData.TerrainType.ROCK:
		var res_raw: float = _sample_noise_normalized(_noise_resource, tile_x, tile_y)
		if res_raw > balance.resource_deposit_threshold * 0.8:
			data.deposit = _determine_deposit_type(tile_x, tile_y, data.height)

	# --- Растительность ---
	if data.terrain == TileGenData.TerrainType.GROUND or \
	   data.terrain == TileGenData.TerrainType.GRASS:
		var veg_raw: float = _sample_noise_normalized(_noise_vegetation, tile_x, tile_y)
		if veg_raw > balance.grass_threshold:
			data.has_grass = true
			data.terrain = TileGenData.TerrainType.GRASS
		if veg_raw > balance.tree_threshold and data.deposit == TileGenData.DepositType.NONE:
			data.has_tree = true

	return data

## Преобразовать высоту в тип поверхности.
func _height_to_terrain(height: float, tile_x: int, tile_y: int) -> TileGenData.TerrainType:
	if height < balance.water_threshold:
		return TileGenData.TerrainType.WATER

	# Песок — переходная зона рядом с водой
	if height < balance.water_threshold + 0.05:
		return TileGenData.TerrainType.SAND

	if height > balance.rock_threshold:
		return TileGenData.TerrainType.ROCK

	return TileGenData.TerrainType.GROUND

## Определить тип ресурсной залежи.
## Тип зависит от высоты и псевдослучайного распределения.
func _determine_deposit_type(tile_x: int, tile_y: int, height: float) -> TileGenData.DepositType:
	# Используем хеш координат для детерминированного результата
	var hash_val: int = _tile_hash(tile_x, tile_y)
	var roll: float = float(hash_val % 1000) / 1000.0

	# Распределение зависит от высоты:
	# Низкие зоны — больше воды, меньше руды
	# Высокие зоны — больше камня и руды
	if height < 0.4:
		# Низина: 40% водный источник, 30% железо, 20% медь, 10% камень
		if roll < 0.4:
			return TileGenData.DepositType.WATER_SOURCE
		elif roll < 0.7:
			return TileGenData.DepositType.IRON_ORE
		elif roll < 0.9:
			return TileGenData.DepositType.COPPER_ORE
		else:
			return TileGenData.DepositType.STONE
	else:
		# Возвышенность: 10% вода, 35% железо, 30% медь, 25% камень
		if roll < 0.1:
			return TileGenData.DepositType.WATER_SOURCE
		elif roll < 0.45:
			return TileGenData.DepositType.IRON_ORE
		elif roll < 0.75:
			return TileGenData.DepositType.COPPER_ORE
		else:
			return TileGenData.DepositType.STONE

## Детерминированный хеш координат тайла.
## Один и тот же тайл всегда даёт одинаковый хеш.
func _tile_hash(x: int, y: int) -> int:
	# Простой хеш: seed XOR координаты с большими множителями
	var h: int = world_seed
	h = h ^ (x * 374761393)
	h = h ^ (y * 668265263)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h)
