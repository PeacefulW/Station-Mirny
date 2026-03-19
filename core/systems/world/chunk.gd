class_name Chunk
extends Node2D

## Один чанк мира (64×64 тайла). Создаётся ChunkManager.
##
## ПРОИЗВОДИТЕЛЬНОСТЬ: Земля рисуется через TileMapLayer —
## одна нода на все 4096 тайлов вместо 4096 ColorRect.
## Это в тысячи раз быстрее: GPU рисует весь чанк за 1 вызов.

# --- Публичные ---
## Координаты этого чанка (не тайла!).
var chunk_coord: Vector2i = Vector2i.ZERO
## Загружен ли чанк полностью.
var is_loaded: bool = false
## Были ли в этом чанке изменения игрока (для сохранения).
var is_dirty: bool = false

# --- Приватные ---
var _terrain_layer: TileMapLayer = null
var _resource_container: Node2D = null
var _tile_size: int = 32
var _chunk_size: int = 64
## Общий TileSet (создаётся ChunkManager, один на все чанки).
var _tileset: TileSet = null
## Ресурсные ноды в этом чанке: Vector2i (глоб. тайл) -> ResourceNode.
var _resource_nodes: Dictionary = {}
## Тайлы, которые игрок изменил.
var _modified_tiles: Dictionary = {}
## Данные генерации (кэш).
var _gen_data: Dictionary = {}
## Текущий биом.
var _biome: BiomeData = null

## Инициализировать чанк. Вызывается ChunkManager.
func setup(
	p_coord: Vector2i,
	p_tile_size: int,
	p_chunk_size: int,
	p_biome: BiomeData,
	p_tileset: TileSet
) -> void:
	chunk_coord = p_coord
	_tile_size = p_tile_size
	_chunk_size = p_chunk_size
	_biome = p_biome
	_tileset = p_tileset
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]

	var chunk_pixels: int = _chunk_size * _tile_size
	position = Vector2(chunk_coord.x * chunk_pixels, chunk_coord.y * chunk_pixels)

	# TileMapLayer для земли — ОДНА нода на 4096 тайлов
	_terrain_layer = TileMapLayer.new()
	_terrain_layer.name = "Terrain"
	_terrain_layer.tile_set = _tileset
	_terrain_layer.z_index = -10
	# Коллизия: слой 2 (стены), чтобы игрок/враги не проходили через воду/камни
	_terrain_layer.collision_enabled = true
	add_child(_terrain_layer)

	# Контейнер для ресурсов (руда, деревья — это отдельные ноды)
	_resource_container = Node2D.new()
	_resource_container.name = "Resources"
	_resource_container.z_index = -5
	add_child(_resource_container)

## Заполнить чанк данными генерации.
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

## Получить изменения для сохранения.
func get_modifications() -> Dictionary:
	var mods: Dictionary = _modified_tiles.duplicate()
	for tile_pos: Vector2i in _resource_nodes:
		var node: ResourceNode = _resource_nodes[tile_pos]
		if is_instance_valid(node):
			mods[tile_pos] = node.save_state()
	return mods

## Пометить тайл как изменённый.
func mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void:
	_modified_tiles[tile_pos] = state
	is_dirty = true

## Глобальный тайл → локальный тайл в этом чанке.
func global_to_local_tile(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

## Локальный тайл → позиция в пикселях (относительно чанка).
func local_tile_to_position(local_tile: Vector2i) -> Vector2:
	return Vector2(
		local_tile.x * _tile_size + _tile_size * 0.5,
		local_tile.y * _tile_size + _tile_size * 0.5
	)

## Очистить перед выгрузкой.
func cleanup() -> void:
	is_loaded = false
	_gen_data.clear()

# --- Приватные методы ---

## Заполнить TileMapLayer тайлами — мгновенно, без фризов.
func _render_terrain() -> void:
	if not _tileset:
		return
	for global_tile: Vector2i in _gen_data:
		var tile_data: TileGenData = _gen_data[global_tile]
		var local_tile: Vector2i = global_to_local_tile(global_tile)

		# Определяем atlas-координаты: X = тип, Y = яркость
		var atlas_x: int = _terrain_to_atlas_x(tile_data.terrain)
		var atlas_y: int = _height_to_variant(tile_data.height, tile_data.spore_density)

		# Одна строчка вместо создания ноды — set_cell() работает мгновенно
		_terrain_layer.set_cell(local_tile, 0, Vector2i(atlas_x, atlas_y))

## Тип поверхности → столбец в атласе.
func _terrain_to_atlas_x(terrain: TileGenData.TerrainType) -> int:
	match terrain:
		TileGenData.TerrainType.GROUND:
			return 0
		TileGenData.TerrainType.ROCK:
			return 1
		TileGenData.TerrainType.WATER:
			return 2
		TileGenData.TerrainType.SAND:
			return 3
		TileGenData.TerrainType.GRASS:
			return 4
	return 0

## Высота + споры → строка в атласе (0=тёмный, 1=обычный, 2=светлый).
## Даёт естественную вариацию без per-tile нод.
func _height_to_variant(height: float, spore_density: float) -> int:
	# Споровые зоны всегда тёмные
	if spore_density > 0.6:
		return 0
	# Низкие = тёмные, средние = обычные, высокие = светлые
	if height < 0.38:
		return 0
	elif height > 0.62:
		return 2
	return 1

## Заспавнить ресурсные ноды.
func _spawn_resources(resource_defs: Dictionary) -> void:
	for global_tile: Vector2i in _gen_data:
		var tile_data: TileGenData = _gen_data[global_tile]
		if _modified_tiles.has(global_tile):
			var mod: Dictionary = _modified_tiles[global_tile]
			if mod.get("depleted", false):
				continue
		if tile_data.deposit != TileGenData.DepositType.NONE:
			var def: ResourceNodeData = resource_defs.get(tile_data.deposit)
			if def:
				_create_resource_node(def, global_tile, tile_data)
		elif tile_data.has_tree:
			var tree_def: ResourceNodeData = resource_defs.get("tree")
			if tree_def:
				_create_resource_node(tree_def, global_tile, tile_data)

func _create_resource_node(
	def: ResourceNodeData,
	global_tile: Vector2i,
	_tile_data: TileGenData
) -> void:
	var node := ResourceNode.new()
	var local_tile: Vector2i = global_to_local_tile(global_tile)
	var local_pos: Vector2 = local_tile_to_position(local_tile)
	node.setup(def, global_tile, local_pos)
	if _modified_tiles.has(global_tile):
		node.load_state(_modified_tiles[global_tile])
	node.depleted.connect(_on_resource_depleted.bind(global_tile))
	_resource_container.add_child(node)
	_resource_nodes[global_tile] = node

func _on_resource_depleted(global_tile: Vector2i) -> void:
	mark_tile_modified(global_tile, {"depleted": true})
