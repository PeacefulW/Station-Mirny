class_name ChunkManager
extends Node2D

## Менеджер чанков. Отслеживает позицию игрока и
## загружает/выгружает чанки вокруг него.
## Мост между WorldGenerator (данные) и видимым миром.
##
## Не знает о строительстве, фауне, UI — только о тайлах
## и ресурсных нодах. Общается через EventBus.

# --- Приватные ---
## Загруженные чанки: Vector2i (coord) -> Chunk.
var _loaded_chunks: Dictionary = {}
## Текущий чанк игрока (для отслеживания перехода).
var _player_chunk: Vector2i = Vector2i(99999, 99999)
## Ссылка на игрока (находим через группу).
var _player: Node2D = null
## Контейнер для чанков.
var _chunk_container: Node2D = null
## Очередь чанков на загрузку (для порционной загрузки).
var _load_queue: Array[Vector2i] = []
## Определения ресурсных нод: DepositType (int) или "tree" -> ResourceNodeData.
var _resource_defs: Dictionary = {}
## Сохранённые изменения чанков: Vector2i (chunk coord) -> Dictionary.
var _saved_chunk_data: Dictionary = {}
## Сколько тайлов рисуем за один кадр (порционная загрузка).
var _tiles_per_frame: int = 512

func _ready() -> void:
	_chunk_container = Node2D.new()
	_chunk_container.name = "Chunks"
	add_child(_chunk_container)
	_load_resource_definitions()
	# Ищем игрока с задержкой (он может ещё не быть в дереве)
	call_deferred("_find_player")

func _process(_delta: float) -> void:
	if not _player or not WorldGenerator.balance:
		return
	_check_player_chunk()
	_process_load_queue()

# --- Публичные методы ---

## Принудительно загрузить чанки вокруг позиции.
## Используется при старте мира или телепортации.
func force_load_around(world_pos: Vector2) -> void:
	var center: Vector2i = WorldGenerator.world_to_chunk(world_pos)
	_player_chunk = center
	_update_chunks(center)
	# Немедленно загрузить все чанки из очереди
	while not _load_queue.is_empty():
		var coord: Vector2i = _load_queue.pop_front()
		_load_chunk_immediate(coord)

## Задать сохранённые данные чанков (при загрузке игры).
func set_saved_data(data: Dictionary) -> void:
	_saved_chunk_data = data

## Получить все данные чанков для сохранения.
func get_save_data() -> Dictionary:
	var result: Dictionary = _saved_chunk_data.duplicate()
	# Обновляем данные из загруженных грязных чанков
	for coord: Vector2i in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[coord]
		if chunk.is_dirty:
			result[coord] = chunk.get_modifications()
	return result

## Проверить, загружен ли чанк по глобальным координатам тайла.
func is_tile_loaded(global_tile: Vector2i) -> bool:
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	return _loaded_chunks.has(chunk_coord)

## Получить чанк по глобальным координатам тайла (или null).
func get_chunk_at_tile(global_tile: Vector2i) -> Chunk:
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	return _loaded_chunks.get(chunk_coord)

## Получить чанк по координатам чанка (или null).
func get_chunk(chunk_coord: Vector2i) -> Chunk:
	return _loaded_chunks.get(chunk_coord)

# --- Приватные методы ---

func _find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node2D
		# Первая загрузка чанков вокруг игрока
		if WorldGenerator and WorldGenerator._is_initialized:
			force_load_around(_player.global_position)

## Проверить, перешёл ли игрок в другой чанк.
func _check_player_chunk() -> void:
	var current_chunk: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	if current_chunk != _player_chunk:
		_player_chunk = current_chunk
		_update_chunks(current_chunk)

## Обновить список загруженных чанков: загрузить новые, выгрузить далёкие.
func _update_chunks(center: Vector2i) -> void:
	var load_r: int = WorldGenerator.balance.load_radius
	var unload_r: int = WorldGenerator.balance.unload_radius
	# Определяем, какие чанки нужны
	var needed: Dictionary = {}
	for dx: int in range(-load_r, load_r + 1):
		for dy: int in range(-load_r, load_r + 1):
			var coord := Vector2i(center.x + dx, center.y + dy)
			needed[coord] = true
	# Выгрузить далёкие чанки
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks:
		var dist_x: int = absi(coord.x - center.x)
		var dist_y: int = absi(coord.y - center.y)
		if dist_x > unload_r or dist_y > unload_r:
			to_unload.append(coord)
	for coord: Vector2i in to_unload:
		_unload_chunk(coord)
	# Добавить в очередь загрузки новые чанки
	# Сортируем по расстоянию от центра (ближние первыми)
	var to_load: Array[Vector2i] = []
	for coord: Vector2i in needed:
		if not _loaded_chunks.has(coord) and not _load_queue.has(coord):
			to_load.append(coord)
	to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var dist_a: int = absi(a.x - center.x) + absi(a.y - center.y)
		var dist_b: int = absi(b.x - center.x) + absi(b.y - center.y)
		return dist_a < dist_b
	)
	_load_queue.append_array(to_load)

## Обработать очередь загрузки (порционно — 1 чанк за кадр).
func _process_load_queue() -> void:
	if _load_queue.is_empty():
		return
	var coord: Vector2i = _load_queue.pop_front()
	# Проверяем, не стал ли чанк ненужным пока был в очереди
	var load_r: int = WorldGenerator.balance.load_radius
	var dist_x: int = absi(coord.x - _player_chunk.x)
	var dist_y: int = absi(coord.y - _player_chunk.y)
	if dist_x > load_r or dist_y > load_r:
		return
	_load_chunk_immediate(coord)

## Загрузить один чанк немедленно.
func _load_chunk_immediate(coord: Vector2i) -> void:
	if _loaded_chunks.has(coord):
		return
	# Получаем данные генерации от WorldGenerator
	var gen_data: Dictionary = WorldGenerator.get_chunk_data(coord)
	# Создаём чанк
	var chunk := Chunk.new()
	chunk.setup(
		coord,
		WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		WorldGenerator.current_biome
	)
	# Получаем сохранённые изменения если есть
	var saved_mods: Dictionary = _saved_chunk_data.get(coord, {})
	# Заполняем
	chunk.populate(gen_data, saved_mods, _resource_defs)
	_chunk_container.add_child(chunk)
	_loaded_chunks[coord] = chunk
	EventBus.chunk_loaded.emit(coord)

## Выгрузить чанк.
func _unload_chunk(coord: Vector2i) -> void:
	if not _loaded_chunks.has(coord):
		return
	var chunk: Chunk = _loaded_chunks[coord]
	# Сохраняем изменения перед выгрузкой
	if chunk.is_dirty:
		_saved_chunk_data[coord] = chunk.get_modifications()
	chunk.cleanup()
	chunk.queue_free()
	_loaded_chunks.erase(coord)
	EventBus.chunk_unloaded.emit(coord)

## Загрузить определения ресурсных нод.
## Маппинг DepositType -> ResourceNodeData.
func _load_resource_definitions() -> void:
	# Железная руда
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
	# Медная руда
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
	# Камень
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
	# Водный источник
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
	# Дерево
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
