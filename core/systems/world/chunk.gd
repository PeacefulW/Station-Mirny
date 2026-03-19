class_name Chunk
extends Node2D

## Один чанк мира (64×64 тайла). v3: читает из packed arrays (C++).

var chunk_coord: Vector2i = Vector2i.ZERO
var is_loaded: bool = false
var is_dirty: bool = false

var _terrain_layer: TileMapLayer = null
var _resource_container: Node2D = null
var _tile_size: int = 32
var _chunk_size: int = 64
var _tileset: TileSet = null
var _resource_nodes: Dictionary = {}
var _modified_tiles: Dictionary = {}
var _biome: BiomeData = null

func setup(
	p_coord: Vector2i, p_tile_size: int, p_chunk_size: int,
	p_biome: BiomeData, p_tileset: TileSet
) -> void:
	chunk_coord = p_coord
	_tile_size = p_tile_size
	_chunk_size = p_chunk_size
	_biome = p_biome
	_tileset = p_tileset
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	var cp: int = _chunk_size * _tile_size
	position = Vector2(chunk_coord.x * cp, chunk_coord.y * cp)
	_terrain_layer = TileMapLayer.new()
	_terrain_layer.name = "Terrain"
	_terrain_layer.tile_set = _tileset
	_terrain_layer.z_index = -10
	add_child(_terrain_layer)
	_resource_container = Node2D.new()
	_resource_container.name = "Resources"
	_resource_container.z_index = -5
	add_child(_resource_container)

## Заполнить из C++ данных (packed arrays).
func populate_native(
	native_data: Dictionary,
	saved_modifications: Dictionary,
	resource_defs: Dictionary
) -> void:
	_modified_tiles = saved_modifications.duplicate()
	var cs: int = native_data.get("chunk_size", _chunk_size)
	var terrain: PackedByteArray = native_data.get("terrain", PackedByteArray())
	var height: PackedFloat32Array = native_data.get("height", PackedFloat32Array())
	var deposit: PackedByteArray = native_data.get("deposit", PackedByteArray())
	var has_tree: PackedByteArray = native_data.get("has_tree", PackedByteArray())
	var start_x: int = chunk_coord.x * cs
	var start_y: int = chunk_coord.y * cs

	# Заполняем TileMapLayer
	for ly: int in range(cs):
		for lx: int in range(cs):
			var idx: int = ly * cs + lx
			var atlas_x: int = terrain[idx]  # 0=ground,1=rock,2=water,3=sand,4=grass
			var h: float = height[idx]
			var atlas_y: int = 1  # обычный
			if h < 0.38:
				atlas_y = 0  # тёмный
			elif h > 0.62:
				atlas_y = 2  # светлый
			_terrain_layer.set_cell(Vector2i(lx, ly), 0, Vector2i(atlas_x, atlas_y))

	# Спавним ресурсы
	for ly: int in range(cs):
		for lx: int in range(cs):
			var idx: int = ly * cs + lx
			var gx: int = start_x + lx
			var gy: int = start_y + ly
			var global_tile := Vector2i(gx, gy)
			# Пропускаем если тайл уже изменён
			if _modified_tiles.has(global_tile):
				if _modified_tiles[global_tile].get("depleted", false):
					continue
			var dep: int = deposit[idx]
			var tree: int = has_tree[idx]
			if dep > 0:
				var def: ResourceNodeData = resource_defs.get(dep)
				if def:
					_create_resource_node(def, global_tile, Vector2i(lx, ly))
			elif tree > 0:
				var tree_def: ResourceNodeData = resource_defs.get("tree")
				if tree_def:
					_create_resource_node(tree_def, global_tile, Vector2i(lx, ly))
	is_loaded = true

## Старый формат (совместимость с не-C++ генератором).
func populate(
	gen_data: Dictionary,
	saved_modifications: Dictionary,
	resource_defs: Dictionary
) -> void:
	_modified_tiles = saved_modifications.duplicate()
	for global_tile: Vector2i in gen_data:
		var td: TileGenData = gen_data[global_tile]
		var local_tile: Vector2i = _global_to_local(global_tile)
		var atlas_x: int = td.terrain
		var atlas_y: int = 1
		if td.height < 0.38: atlas_y = 0
		elif td.height > 0.62: atlas_y = 2
		_terrain_layer.set_cell(local_tile, 0, Vector2i(atlas_x, atlas_y))
		if _modified_tiles.has(global_tile):
			if _modified_tiles[global_tile].get("depleted", false):
				continue
		if td.deposit != TileGenData.DepositType.NONE:
			var def: ResourceNodeData = resource_defs.get(td.deposit)
			if def:
				_create_resource_node(def, global_tile, local_tile)
		elif td.has_tree:
			var tree_def: ResourceNodeData = resource_defs.get("tree")
			if tree_def:
				_create_resource_node(tree_def, global_tile, local_tile)
	is_loaded = true

func get_modifications() -> Dictionary:
	var mods: Dictionary = _modified_tiles.duplicate()
	for tile_pos: Vector2i in _resource_nodes:
		var node: ResourceNode = _resource_nodes[tile_pos]
		if is_instance_valid(node):
			mods[tile_pos] = node.save_state()
	return mods

func mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void:
	_modified_tiles[tile_pos] = state
	is_dirty = true

func cleanup() -> void:
	is_loaded = false

func _global_to_local(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

func _create_resource_node(def: ResourceNodeData, global_tile: Vector2i, local_tile: Vector2i) -> void:
	var node := ResourceNode.new()
	var local_pos := Vector2(
		local_tile.x * _tile_size + _tile_size * 0.5,
		local_tile.y * _tile_size + _tile_size * 0.5
	)
	node.setup(def, global_tile, local_pos)
	if _modified_tiles.has(global_tile):
		node.load_state(_modified_tiles[global_tile])
	node.depleted.connect(_on_resource_depleted.bind(global_tile))
	_resource_container.add_child(node)
	_resource_nodes[global_tile] = node

func _on_resource_depleted(global_tile: Vector2i) -> void:
	mark_tile_modified(global_tile, {"depleted": true})
