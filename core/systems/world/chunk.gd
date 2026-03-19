class_name Chunk
extends Node2D

## Один чанк мира (64×64 тайла). Создаётся ChunkManager.
## Содержит визуальное представление земли и ресурсные ноды.
## Не знает о других чанках — только о своих координатах.

# --- Публичные ---
## Координаты этого чанка (не тайла!).
var chunk_coord: Vector2i = Vector2i.ZERO
## Загружен ли чанк полностью.
var is_loaded: bool = false
## Были ли в этом чанке изменения игрока (для сохранения).
var is_dirty: bool = false

# --- Приватные ---
var _terrain_container: Node2D = null
var _resource_container: Node2D = null
var _tile_size: int = 32
var _chunk_size: int = 64
## Ресурсные ноды в этом чанке: Vector2i (тайл) -> ResourceNode.
var _resource_nodes: Dictionary = {}
## Тайлы, которые игрок изменил (добыл ресурс, срубил дерево).
var _modified_tiles: Dictionary = {}
## Данные генерации (кэш на время загрузки).
var _gen_data: Dictionary = {}
## Текущий биом.
var _biome: BiomeData = null

## Инициализировать чанк. Вызывается ChunkManager.
func setup(
	p_coord: Vector2i,
	p_tile_size: int,
	p_chunk_size: int,
	p_biome: BiomeData
) -> void:
	chunk_coord = p_coord
	_tile_size = p_tile_size
	_chunk_size = p_chunk_size
	_biome = p_biome
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	# Позиция чанка в мировых координатах
	var chunk_pixels: int = _chunk_size * _tile_size
	position = Vector2(chunk_coord.x * chunk_pixels, chunk_coord.y * chunk_pixels)
	# Контейнеры
	_terrain_container = Node2D.new()
	_terrain_container.name = "Terrain"
	_terrain_container.z_index = -10
	add_child(_terrain_container)
	_resource_container = Node2D.new()
	_resource_container.name = "Resources"
	_resource_container.z_index = -5
	add_child(_resource_container)

## Заполнить чанк данными генерации. Вызывается ChunkManager.
## [param gen_data] — словарь Vector2i -> TileGenData от WorldGenerator.
## [param saved_modifications] — изменения игрока (из сохранения).
## [param resource_defs] — словарь int (DepositType) -> ResourceNodeData.
func populate(
	gen_data: Dictionary,
	saved_modifications: Dictionary,
	resource_defs: Dictionary
) -> void:
	_gen_data = gen_data
	_modified_tiles = saved_modifications.duplicate()
	_render_terrain()
	_spawn_resources(resource_defs)
	is_loaded = true

## Получить список изменений для сохранения.
func get_modifications() -> Dictionary:
	var mods: Dictionary = _modified_tiles.duplicate()
	# Добавляем состояние ресурсных нод
	for tile_pos: Vector2i in _resource_nodes:
		var node: ResourceNode = _resource_nodes[tile_pos]
		if is_instance_valid(node):
			mods[tile_pos] = node.save_state()
	return mods

## Пометить тайл как изменённый (ресурс добыт, дерево срублено).
func mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void:
	_modified_tiles[tile_pos] = state
	is_dirty = true

## Преобразовать глобальный тайл в локальную позицию внутри чанка.
func global_to_local_tile(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

## Преобразовать локальный тайл в мировую позицию (пиксели, относительно чанка).
func local_tile_to_position(local_tile: Vector2i) -> Vector2:
	return Vector2(
		local_tile.x * _tile_size + _tile_size * 0.5,
		local_tile.y * _tile_size + _tile_size * 0.5
	)

## Очистить чанк перед выгрузкой.
func cleanup() -> void:
	is_loaded = false
	_gen_data.clear()
	# Ноды удалятся через queue_free() родителя

# --- Приватные методы ---

## Нарисовать землю (цветные прямоугольники-заглушки).
func _render_terrain() -> void:
	if not _biome:
		return
	for global_tile: Vector2i in _gen_data:
		var tile_data: TileGenData = _gen_data[global_tile]
		var local_tile: Vector2i = global_to_local_tile(global_tile)
		var color: Color = _get_terrain_color(tile_data)
		var rect := ColorRect.new()
		rect.size = Vector2(_tile_size, _tile_size)
		rect.position = Vector2(local_tile.x * _tile_size, local_tile.y * _tile_size)
		rect.color = color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_terrain_container.add_child(rect)

## Заспавнить ресурсные ноды (руда, деревья, камни).
func _spawn_resources(resource_defs: Dictionary) -> void:
	for global_tile: Vector2i in _gen_data:
		var tile_data: TileGenData = _gen_data[global_tile]
		# Проверяем, не был ли этот тайл уже изменён игроком
		if _modified_tiles.has(global_tile):
			var mod: Dictionary = _modified_tiles[global_tile]
			if mod.get("depleted", false):
				continue
		# Ресурсная залежь
		if tile_data.deposit != TileGenData.DepositType.NONE:
			var def: ResourceNodeData = resource_defs.get(tile_data.deposit)
			if def:
				_create_resource_node(def, global_tile, tile_data)
		# Деревья
		elif tile_data.has_tree:
			var tree_def: ResourceNodeData = resource_defs.get("tree")
			if tree_def:
				_create_resource_node(tree_def, global_tile, tile_data)

## Создать одну ресурсную ноду.
func _create_resource_node(
	def: ResourceNodeData,
	global_tile: Vector2i,
	_tile_data: TileGenData
) -> void:
	var node := ResourceNode.new()
	var local_tile: Vector2i = global_to_local_tile(global_tile)
	var local_pos: Vector2 = local_tile_to_position(local_tile)
	node.setup(def, global_tile, local_pos)
	# Восстанавливаем состояние из сохранения если есть
	if _modified_tiles.has(global_tile):
		node.load_state(_modified_tiles[global_tile])
	node.depleted.connect(_on_resource_depleted.bind(global_tile))
	_resource_container.add_child(node)
	_resource_nodes[global_tile] = node

## Получить цвет тайла по данным генерации.
func _get_terrain_color(tile_data: TileGenData) -> Color:
	if not _biome:
		return Color(0.2, 0.2, 0.2)
	var base_color: Color
	match tile_data.terrain:
		TileGenData.TerrainType.WATER:
			base_color = _biome.water_color
		TileGenData.TerrainType.SAND:
			base_color = _biome.sand_color
		TileGenData.TerrainType.ROCK:
			base_color = _biome.rock_color
		TileGenData.TerrainType.GRASS:
			base_color = _biome.grass_color
		_:
			base_color = _biome.ground_color
	# Лёгкая вариация яркости по высоте для естественности
	var height_variation: float = (tile_data.height - 0.5) * 0.15
	base_color = base_color.lightened(height_variation)
	# Лёгкий оттенок спор (чем гуще — тем зеленовато-мутнее)
	if tile_data.spore_density > 0.4:
		var spore_tint: float = (tile_data.spore_density - 0.4) * 0.2
		base_color = base_color.lerp(Color(0.3, 0.35, 0.2), spore_tint)
	return base_color

func _on_resource_depleted(global_tile: Vector2i) -> void:
	mark_tile_modified(global_tile, {"depleted": true})
