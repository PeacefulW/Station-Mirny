class_name WorldGeneratorSingleton
extends Node

## Генератор мира. Autoload-синглтон.
##
## Использует 5 техник для реалистичного ландшафта:
## 1. Domain Warping — органичные формы вместо круглых пятен
## 2. Ridged Noise — горные хребты с острыми пиками
## 3. Continental Noise — крупномасштабная суша/океан
## 4. River Simulation — реки текут по рельефу сверху вниз
## 5. Moisture Map — влажность определяет растительность
##
## Детерминированный: один seed → всегда один мир.

# --- Константы ---
const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"
const BIOME_PATH: String = "res://data/biomes/plains_biome.tres"

# --- Публичные ---
var world_seed: int = 0
var balance: WorldGenBalance = null
var current_biome: BiomeData = null
var spawn_tile: Vector2i = Vector2i.ZERO
var _is_initialized: bool = false

# --- Приватные: слои шума ---
var _noise_height: FastNoiseLite = null
var _noise_warp_x: FastNoiseLite = null
var _noise_warp_y: FastNoiseLite = null
var _noise_ridge: FastNoiseLite = null
var _noise_continental: FastNoiseLite = null
var _noise_moisture: FastNoiseLite = null
var _noise_spore: FastNoiseLite = null
var _noise_resource: FastNoiseLite = null

## Карта рек: хранит тайлы через которые проходит река.
## Dictionary[int] -> float (ключ = tile_hash, значение = ширина).
var _river_tiles: Dictionary = {}
## Границы сгенерированных рек (для порционной генерации).
var _river_generated_radius: int = 0

func _ready() -> void:
	balance = load(BALANCE_PATH) as WorldGenBalance
	if not balance:
		push_error("WorldGenerator: не удалось загрузить %s" % BALANCE_PATH)
		return
	current_biome = load(BIOME_PATH) as BiomeData
	if not current_biome:
		push_error("WorldGenerator: не удалось загрузить %s" % BIOME_PATH)

# --- Публичные методы ---

## Инициализировать мир с seed.
func initialize_world(seed_value: int) -> void:
	world_seed = seed_value
	_setup_noise_layers()
	_generate_rivers()
	_is_initialized = true
	EventBus.world_seed_set.emit(world_seed)

## Инициализировать со случайным seed.
func initialize_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	initialize_world(rng.randi())

## Получить данные одного тайла.
func get_tile_data(tile_x: int, tile_y: int) -> TileGenData:
	if not _is_initialized:
		push_error("WorldGenerator: не инициализирован!")
		return TileGenData.new()
	return _generate_tile(tile_x, tile_y)

## Получить данные целого чанка.
func get_chunk_data(chunk_coord: Vector2i) -> Dictionary:
	var cs: int = balance.chunk_size_tiles
	var result: Dictionary = {}
	for lx: int in range(cs):
		for ly: int in range(cs):
			var gx: int = chunk_coord.x * cs + lx
			var gy: int = chunk_coord.y * cs + ly
			result[Vector2i(gx, gy)] = _generate_tile(gx, gy)
	return result

## Мировая позиция (пиксели) → тайл.
func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / balance.tile_size),
		floori(world_pos.y / balance.tile_size)
	)

## Тайл → центр тайла (пиксели).
func tile_to_world(tile_pos: Vector2i) -> Vector2:
	var ts: float = float(balance.tile_size)
	return Vector2(tile_pos.x * ts + ts * 0.5, tile_pos.y * ts + ts * 0.5)

## Мировая позиция → координаты чанка.
func world_to_chunk(world_pos: Vector2) -> Vector2i:
	var cp: int = balance.get_chunk_size_pixels()
	return Vector2i(floori(world_pos.x / cp), floori(world_pos.y / cp))

## Тайл → чанк.
func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	var cs: int = balance.chunk_size_tiles
	return Vector2i(
		floori(float(tile_pos.x) / cs),
		floori(float(tile_pos.y) / cs)
	)

## Плотность спор в мировой точке.
func get_spore_density_at(world_pos: Vector2) -> float:
	if not _is_initialized:
		return 0.0
	var t: Vector2i = world_to_tile(world_pos)
	return _calc_spore_density(t.x, t.y)

## Проходим ли тайл в мировой точке?
func is_walkable_at(world_pos: Vector2) -> bool:
	if not _is_initialized:
		return true
	var t: Vector2i = world_to_tile(world_pos)
	var data: TileGenData = _generate_tile(t.x, t.y)
	return data.terrain != TileGenData.TerrainType.WATER \
		and data.terrain != TileGenData.TerrainType.ROCK

# --- Приватные: настройка шумов ---

func _setup_noise_layers() -> void:
	_noise_height = _create_noise(world_seed, balance.height_frequency, balance.height_octaves)
	_noise_warp_x = _create_noise(world_seed + 500, balance.warp_frequency, 2)
	_noise_warp_y = _create_noise(world_seed + 800, balance.warp_frequency, 2)
	_noise_ridge = _create_noise(world_seed + 3000, balance.ridge_frequency, 4)
	_noise_continental = _create_noise(world_seed + 7000, balance.continental_frequency, 2)
	_noise_moisture = _create_noise(world_seed + 4000, balance.moisture_frequency, 3)
	_noise_spore = _create_noise(world_seed + 6000, balance.spore_frequency, balance.spore_octaves)
	_noise_resource = _create_noise(world_seed + 9000, balance.resource_frequency, 2)

func _create_noise(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n

## Шум → диапазон 0.0–1.0.
func _sample(noise: FastNoiseLite, x: float, y: float) -> float:
	return (noise.get_noise_2d(x, y) + 1.0) * 0.5

## Ridged noise: острые хребты вместо плавных холмов.
func _sample_ridged(x: float, y: float) -> float:
	var v: float = 0.0
	var amp: float = 1.0
	var freq: float = balance.ridge_frequency
	var total: float = 0.0
	for i: int in range(4):
		var n: float = _noise_ridge.get_noise_2d(x * freq / balance.ridge_frequency, y * freq / balance.ridge_frequency)
		n = 1.0 - absf(n)  # Переворачиваем: впадины → пики
		n *= n              # Обостряем пики
		v += n * amp
		total += amp
		amp *= 0.45
		freq *= 2.1
	return v / total

# --- Приватные: генерация рек ---

func _generate_rivers() -> void:
	_river_tiles.clear()
	var radius: int = balance.land_guarantee_radius * 6
	for i: int in range(balance.river_count):
		_trace_river(i, radius)
	_river_generated_radius = radius

func _trace_river(index: int, area_radius: int) -> void:
	# Стартовая позиция: случайная, в верхней части карты, на возвышенности
	var rng_x: float = _tile_hashf(index * 3, index * 7, world_seed + 9000)
	var rng_y: float = _tile_hashf(index * 5, index * 2, world_seed + 9500)
	var rx: float = spawn_tile.x + (rng_x - 0.5) * area_radius * 1.6
	var ry: float = spawn_tile.y - area_radius * 0.3 + rng_y * area_radius * 0.4
	var max_steps: int = area_radius * 3

	for step: int in range(max_steps):
		var ix: int = floori(rx)
		var iy: int = floori(ry)
		if absf(rx - spawn_tile.x) > area_radius or absf(ry - spawn_tile.y) > area_radius:
			break

		# Ширина реки: растёт к устью
		var t: float = float(step) / float(max_steps)
		var width: float = lerpf(balance.river_width_start, balance.river_width_end, t)
		var iw: int = ceili(width)

		# Отмечаем тайлы реки
		for dy: int in range(-iw, iw + 1):
			for dx: int in range(-iw, iw + 1):
				if dx * dx + dy * dy <= iw * iw:
					var key: int = _tile_key(ix + dx, iy + dy)
					_river_tiles[key] = width

		# Ищем самого низкого соседа (река течёт вниз)
		var best_h: float = 999.0
		var best_dir: int = 0
		for d: int in range(8):
			var angle: float = d * PI / 4.0
			var nx: float = rx + cos(angle) * 2.0
			var ny: float = ry + sin(angle) * 2.0 + 0.5  # Смещение вниз
			var nh: float = _calc_raw_height(floori(nx), floori(ny))
			if nh < best_h:
				best_h = nh
				best_dir = d

		var angle: float = best_dir * PI / 4.0
		rx += cos(angle) * 1.2
		ry += sin(angle) * 1.2 + 0.4  # Общий drift вниз

		# Если достигли воды — река впала
		if _calc_raw_height(floori(rx), floori(ry)) < balance.water_threshold:
			break

## Хеш координат для проверки is_river.
func _tile_key(x: int, y: int) -> int:
	return (x + 100000) * 200001 + (y + 100000)

func _is_river(x: int, y: int) -> bool:
	return _river_tiles.has(_tile_key(x, y))

# --- Приватные: генерация тайла ---

func _generate_tile(tx: int, ty: int) -> TileGenData:
	var data := TileGenData.new()

	# Расстояние от спавна
	var dx: float = float(tx - spawn_tile.x)
	var dy: float = float(ty - spawn_tile.y)
	data.distance_from_spawn = sqrt(dx * dx + dy * dy)

	# Высота (комбинация 3 шумов)
	var height: float = _calc_height_with_safety(tx, ty, data.distance_from_spawn)
	data.height = height

	# Река?
	var is_river: bool = _is_river(tx, ty)

	# Тип поверхности
	if is_river and height >= balance.water_threshold:
		data.terrain = TileGenData.TerrainType.WATER
	elif height < balance.water_threshold:
		data.terrain = TileGenData.TerrainType.WATER
	elif height < balance.water_threshold + 0.04:
		data.terrain = TileGenData.TerrainType.SAND
	elif height > balance.rock_threshold + 0.10:
		data.terrain = TileGenData.TerrainType.ROCK
	elif height > balance.rock_threshold:
		data.terrain = TileGenData.TerrainType.ROCK
	else:
		# Влажность определяет: земля или трава
		var moisture: float = _sample(_noise_moisture, float(tx), float(ty))
		if moisture > balance.grass_threshold:
			data.terrain = TileGenData.TerrainType.GRASS
		else:
			data.terrain = TileGenData.TerrainType.GROUND

	# Споры
	data.spore_density = _calc_spore_density(tx, ty)
	if data.distance_from_spawn < balance.safe_zone_radius:
		var safety: float = 1.0 - (data.distance_from_spawn / float(balance.safe_zone_radius))
		data.spore_density *= (1.0 - safety * 0.7)

	# Ресурсы (только на проходимой земле)
	if data.terrain == TileGenData.TerrainType.GROUND or \
	   data.terrain == TileGenData.TerrainType.GRASS:
		var res_val: float = _sample(_noise_resource, float(tx), float(ty))
		if res_val > balance.resource_deposit_threshold:
			data.deposit = _determine_deposit_type(tx, ty, height)

	# Руда в горах (повышенная вероятность)
	if data.terrain == TileGenData.TerrainType.ROCK:
		var res_val: float = _sample(_noise_resource, float(tx), float(ty))
		if res_val > balance.resource_deposit_threshold * 0.8:
			data.deposit = _determine_deposit_type(tx, ty, height)

	# Деревья (только на траве, не на ресурсах)
	if data.terrain == TileGenData.TerrainType.GRASS and \
	   data.deposit == TileGenData.DepositType.NONE:
		var moisture: float = _sample(_noise_moisture, float(tx), float(ty))
		if moisture > balance.tree_threshold:
			data.has_tree = true

	# Декоративная трава
	if data.terrain == TileGenData.TerrainType.GRASS:
		data.has_grass = true

	return data

## Высота с учётом всех 3 техник + безопасная зона.
func _calc_height_with_safety(tx: int, ty: int, dist: float) -> float:
	var h: float = _calc_raw_height(tx, ty)
	# Безопасная зона: поднимаем к 0.5 (гарантированная суша)
	if dist < balance.land_guarantee_radius:
		var factor: float = 1.0 - (dist / float(balance.land_guarantee_radius))
		h = lerpf(h, 0.50, factor * 0.7)
	return h

## Сырая высота: base + ridged + continental, с domain warping.
func _calc_raw_height(tx: int, ty: int) -> float:
	var fx: float = float(tx)
	var fy: float = float(ty)

	# 1. Domain Warping — сдвигаем координаты для органичных форм
	var warp_x: float = _sample(_noise_warp_x, fx, fy) * balance.warp_strength
	var warp_y: float = _sample(_noise_warp_y, fx, fy) * balance.warp_strength
	var warped_x: float = fx + warp_x
	var warped_y: float = fy + warp_y

	# 2. Базовый шум высот (с warping)
	var base: float = _sample(_noise_height, warped_x, warped_y)

	# 3. Ridged Noise — горные хребты
	var ridged: float = _sample_ridged(fx, fy)

	# 4. Continental — крупный масштаб
	var continental: float = _sample(_noise_continental, fx * 0.4, fy * 0.4)

	# Комбинация: веса из баланса
	var base_weight: float = 1.0 - balance.ridge_weight - balance.continental_weight
	return base * base_weight + ridged * balance.ridge_weight + continental * balance.continental_weight

func _calc_spore_density(tx: int, ty: int) -> float:
	var raw: float = _sample(_noise_spore, float(tx), float(ty))
	var mult: float = current_biome.spore_density_multiplier if current_biome else 1.0
	return clampf(raw * mult + balance.spore_min_density, 0.0, 1.0)

func _determine_deposit_type(tx: int, ty: int, height: float) -> TileGenData.DepositType:
	var roll: float = _tile_hashf(tx, ty, world_seed + 5000)
	if height < 0.4:
		if roll < 0.4: return TileGenData.DepositType.WATER_SOURCE
		elif roll < 0.7: return TileGenData.DepositType.IRON_ORE
		elif roll < 0.9: return TileGenData.DepositType.COPPER_ORE
		else: return TileGenData.DepositType.STONE
	else:
		if roll < 0.1: return TileGenData.DepositType.WATER_SOURCE
		elif roll < 0.45: return TileGenData.DepositType.IRON_ORE
		elif roll < 0.75: return TileGenData.DepositType.COPPER_ORE
		else: return TileGenData.DepositType.STONE

## Детерминированный float-хеш координат (0.0–1.0).
func _tile_hashf(x: int, y: int, s: int) -> float:
	var h: int = s
	h = h ^ (x * 374761393)
	h = h ^ (y * 668265263)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 10000) / 10000.0
