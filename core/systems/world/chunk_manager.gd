class_name ChunkManager
extends Node2D

## Менеджер чанков. Отслеживает позицию игрока и
## загружает/выгружает чанки вокруг него.
##
## Создаёт общий TileSet (один на все чанки) программно.
## Позже TileSet заменится на настоящий с реальными спрайтами.

# --- Приватные ---
## Загруженные чанки: Vector2i -> Chunk.
var _loaded_chunks: Dictionary = {}
## Текущий чанк игрока.
var _player_chunk: Vector2i = Vector2i(99999, 99999)
var _player: Node2D = null
var _chunk_container: Node2D = null
## Очередь загрузки (ближние первыми).
var _load_queue: Array[Vector2i] = []
## Определения ресурсов: DepositType (int) или "tree" -> ResourceNodeData.
var _resource_defs: Dictionary = {}
## Сохранённые изменения чанков: Vector2i -> Dictionary.
var _saved_chunk_data: Dictionary = {}
## Общий TileSet для всех чанков (создаётся один раз).
var _shared_tileset: TileSet = null

# --- Константы для атласа ---
## Порядок тайлов: столбец = тип поверхности.
## 0=Ground, 1=Rock, 2=Water, 3=Sand, 4=Grass
const TERRAIN_COUNT: int = 5
## Строки: 0=тёмный, 1=обычный, 2=светлый
const VARIANT_COUNT: int = 3

func _ready() -> void:
	_chunk_container = Node2D.new()
	_chunk_container.name = "Chunks"
	add_child(_chunk_container)
	_load_resource_definitions()
	call_deferred("_deferred_init")

func _process(_delta: float) -> void:
	if not _player or not WorldGenerator or not WorldGenerator.balance:
		return
	_check_player_chunk()
	_process_load_queue()

# --- Публичные методы ---

## Принудительно загрузить чанки вокруг позиции.
func force_load_around(world_pos: Vector2) -> void:
	var center: Vector2i = WorldGenerator.world_to_chunk(world_pos)
	_player_chunk = center
	_update_chunks(center)
	while not _load_queue.is_empty():
		var coord: Vector2i = _load_queue.pop_front()
		_load_chunk_immediate(coord)

## Задать сохранённые данные чанков (при загрузке игры).
func set_saved_data(data: Dictionary) -> void:
	_saved_chunk_data = data

## Получить все данные чанков для сохранения.
func get_save_data() -> Dictionary:
	var result: Dictionary = _saved_chunk_data.duplicate()
	for coord: Vector2i in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[coord]
		if chunk.is_dirty:
			result[coord] = chunk.get_modifications()
	return result

## Проверить, загружен ли чанк.
func is_tile_loaded(global_tile: Vector2i) -> bool:
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	return _loaded_chunks.has(chunk_coord)

## Получить чанк по координатам тайла.
func get_chunk_at_tile(global_tile: Vector2i) -> Chunk:
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	return _loaded_chunks.get(chunk_coord)

## Получить чанк по координатам чанка.
func get_chunk(chunk_coord: Vector2i) -> Chunk:
	return _loaded_chunks.get(chunk_coord)

# --- Инициализация ---

func _deferred_init() -> void:
	_find_player()
	_build_tileset()

func _find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node2D
		if WorldGenerator and WorldGenerator._is_initialized and _shared_tileset:
			force_load_around(_player.global_position)

## Построить TileSet программно из цветов биома.
## Создаёт атлас 5×3 тайлов (5 типов × 3 яркости).
## Коллизия на камне и воде (блокируют проход).
func _build_tileset() -> void:
	if not WorldGenerator or not WorldGenerator.balance or not WorldGenerator.current_biome:
		push_warning("ChunkManager: WorldGenerator не готов, TileSet не создан")
		return

	var ts: int = WorldGenerator.balance.tile_size
	var biome: BiomeData = WorldGenerator.current_biome

	# --- 1. Создаём атлас-изображение ---
	var img_w: int = TERRAIN_COUNT * ts
	var img_h: int = VARIANT_COUNT * ts
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)

	# Базовые цвета: [Ground, Rock, Water, Sand, Grass]
	var base_colors: Array[Color] = [
		biome.ground_color,
		biome.rock_color,
		biome.water_color,
		biome.sand_color,
		biome.grass_color,
	]

	# Заливаем каждый тайл в атласе
	for type_idx: int in range(TERRAIN_COUNT):
		for var_idx: int in range(VARIANT_COUNT):
			var color: Color = base_colors[type_idx]
			match var_idx:
				0: color = color.darkened(0.12)  # Тёмный
				# 1: без изменений — обычный
				2: color = color.lightened(0.10)  # Светлый

			# Заполняем прямоугольник ts×ts пикселей
			var start_x: int = type_idx * ts
			var start_y: int = var_idx * ts
			for px: int in range(ts):
				for py: int in range(ts):
					img.set_pixel(start_x + px, start_y + py, color)

	# --- 2. Создаём текстуру из изображения ---
	var texture := ImageTexture.create_from_image(img)

	# --- 3. Создаём TileSet ---
	_shared_tileset = TileSet.new()
	_shared_tileset.tile_size = Vector2i(ts, ts)

	# Физический слой для коллизий (камень, вода)
	_shared_tileset.add_physics_layer()
	_shared_tileset.set_physics_layer_collision_layer(0, 2)  # Слой 2 = стены
	_shared_tileset.set_physics_layer_collision_mask(0, 0)

	# --- 4. Создаём атлас-источник ---
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(ts, ts)

	# Регистрируем все тайлы
	for x: int in range(TERRAIN_COUNT):
		for y: int in range(VARIANT_COUNT):
			source.create_tile(Vector2i(x, y))

	# --- 5. Добавляем коллизию на камень (x=1) и воду (x=2) ---
	var half: float = ts * 0.5
	var collision_polygon := PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])

	for y: int in range(VARIANT_COUNT):
		for blocked_x: int in [1, 2]:  # Rock=1, Water=2
			var td: TileData = source.get_tile_data(Vector2i(blocked_x, y), 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, collision_polygon)

	# --- 6. Регистрируем источник ---
	_shared_tileset.add_source(source, 0)

	# Если игрок уже найден — загружаем чанки
	if _player and WorldGenerator._is_initialized:
		force_load_around(_player.global_position)

# --- Обновление ---

func _check_player_chunk() -> void:
	var current_chunk: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	if current_chunk != _player_chunk:
		_player_chunk = current_chunk
		_update_chunks(current_chunk)

func _update_chunks(center: Vector2i) -> void:
	var load_r: int = WorldGenerator.balance.load_radius
	var unload_r: int = WorldGenerator.balance.unload_radius

	var needed: Dictionary = {}
	for dx: int in range(-load_r, load_r + 1):
		for dy: int in range(-load_r, load_r + 1):
			needed[Vector2i(center.x + dx, center.y + dy)] = true

	# Выгрузить далёкие
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks:
		if absi(coord.x - center.x) > unload_r or absi(coord.y - center.y) > unload_r:
			to_unload.append(coord)
	for coord: Vector2i in to_unload:
		_unload_chunk(coord)

	# Загрузить новые (ближние первыми)
	var to_load: Array[Vector2i] = []
	for coord: Vector2i in needed:
		if not _loaded_chunks.has(coord) and not _load_queue.has(coord):
			to_load.append(coord)
	to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = absi(a.x - center.x) + absi(a.y - center.y)
		var db: int = absi(b.x - center.x) + absi(b.y - center.y)
		return da < db
	)
	_load_queue.append_array(to_load)

## Загружаем по 2 чанка за кадр (с TileMapLayer это быстро).
func _process_load_queue() -> void:
	var loaded_this_frame: int = 0
	while not _load_queue.is_empty() and loaded_this_frame < 2:
		var coord: Vector2i = _load_queue.pop_front()
		var load_r: int = WorldGenerator.balance.load_radius
		if absi(coord.x - _player_chunk.x) > load_r or \
		   absi(coord.y - _player_chunk.y) > load_r:
			continue
		_load_chunk_immediate(coord)
		loaded_this_frame += 1

func _load_chunk_immediate(coord: Vector2i) -> void:
	if _loaded_chunks.has(coord) or not _shared_tileset:
		return
	var gen_data: Dictionary = WorldGenerator.get_chunk_data(coord)
	var chunk := Chunk.new()
	chunk.setup(
		coord,
		WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		WorldGenerator.current_biome,
		_shared_tileset
	)
	var saved_mods: Dictionary = _saved_chunk_data.get(coord, {})
	chunk.populate(gen_data, saved_mods, _resource_defs)
	_chunk_container.add_child(chunk)
	_loaded_chunks[coord] = chunk
	EventBus.chunk_loaded.emit(coord)

func _unload_chunk(coord: Vector2i) -> void:
	if not _loaded_chunks.has(coord):
		return
	var chunk: Chunk = _loaded_chunks[coord]
	if chunk.is_dirty:
		_saved_chunk_data[coord] = chunk.get_modifications()
	chunk.cleanup()
	chunk.queue_free()
	_loaded_chunks.erase(coord)
	EventBus.chunk_unloaded.emit(coord)

# --- Определения ресурсов ---

func _load_resource_definitions() -> void:
	var iron := ResourceNodeData.new()
	iron.id = &"iron_ore"
	iron.display_name = "Железная руда"
	iron.drop_item_id = &"iron_ore"
	iron.drop_amount_min = 1
	iron.drop_amount_max = 3
	iron.harvest_count = 8
	iron.harvest_time = 2.0
	iron.placeholder_color = Color(0.55, 0.35, 0.25)
	iron.placeholder_size = Vector2(28, 28)
	iron.deposit_type = TileGenData.DepositType.IRON_ORE
	_resource_defs[TileGenData.DepositType.IRON_ORE] = iron

	var copper := ResourceNodeData.new()
	copper.id = &"copper_ore"
	copper.display_name = "Медная руда"
	copper.drop_item_id = &"copper_ore"
	copper.drop_amount_min = 1
	copper.drop_amount_max = 2
	copper.harvest_count = 6
	copper.harvest_time = 2.5
	copper.placeholder_color = Color(0.65, 0.45, 0.20)
	copper.placeholder_size = Vector2(26, 26)
	copper.deposit_type = TileGenData.DepositType.COPPER_ORE
	_resource_defs[TileGenData.DepositType.COPPER_ORE] = copper

	var stone := ResourceNodeData.new()
	stone.id = &"stone"
	stone.display_name = "Камень"
	stone.drop_item_id = &"stone"
	stone.drop_amount_min = 2
	stone.drop_amount_max = 4
	stone.harvest_count = 10
	stone.harvest_time = 1.5
	stone.placeholder_color = Color(0.45, 0.43, 0.40)
	stone.placeholder_size = Vector2(30, 30)
	stone.deposit_type = TileGenData.DepositType.STONE
	_resource_defs[TileGenData.DepositType.STONE] = stone

	var water := ResourceNodeData.new()
	water.id = &"water_source"
	water.display_name = "Водный источник"
	water.drop_item_id = &"water_dirty"
	water.drop_amount_min = 1
	water.drop_amount_max = 1
	water.harvest_count = 0
	water.harvest_time = 3.0
	water.placeholder_color = Color(0.20, 0.35, 0.55)
	water.placeholder_size = Vector2(24, 24)
	water.is_solid = false
	water.regenerates = true
	water.regen_time = 60.0
	water.deposit_type = TileGenData.DepositType.WATER_SOURCE
	_resource_defs[TileGenData.DepositType.WATER_SOURCE] = water

	var tree := ResourceNodeData.new()
	tree.id = &"dead_tree"
	tree.display_name = "Мёртвое дерево"
	tree.drop_item_id = &"wood"
	tree.drop_amount_min = 2
	tree.drop_amount_max = 5
	tree.harvest_count = 3
	tree.harvest_time = 2.0
	tree.placeholder_color = Color(0.30, 0.22, 0.15)
	tree.placeholder_size = Vector2(20, 32)
	tree.collision_radius = 10.0
	_resource_defs["tree"] = tree
