class_name Chunk
extends Node2D

## Один чанк мира (64×64 тайла). v5: шейдер земли + ресурсы тайлами.
##
## Земля: Sprite2D с шейдером (плавные текстуры) ИЛИ fallback TileMapLayer.
## Ресурсы: TileMapLayer поверх земли.

var chunk_coord: Vector2i = Vector2i.ZERO
var is_loaded: bool = false
var is_dirty: bool = false

var _terrain_layer: TileMapLayer = null
var _resource_layer: TileMapLayer = null
var _terrain_sprite: Sprite2D = null
var _tile_size: int = 12
var _chunk_size: int = 64
var _tileset: TileSet = null
var _resource_tileset: TileSet = null
var _modified_tiles: Dictionary = {}
var _biome: BiomeData = null
var _terrain_bytes: PackedByteArray = PackedByteArray()

## Данные ресурсов: Vector2i (local) -> Dictionary {deposit, remaining, depleted}
var _resource_data: Dictionary = {}

func setup(
	p_coord: Vector2i, p_tile_size: int, p_chunk_size: int,
	p_biome: BiomeData, p_tileset: TileSet, p_resource_tileset: TileSet
) -> void:
	chunk_coord = p_coord
	_tile_size = p_tile_size
	_chunk_size = p_chunk_size
	_biome = p_biome
	_tileset = p_tileset
	_resource_tileset = p_resource_tileset
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	var cp: int = _chunk_size * _tile_size
	position = Vector2(chunk_coord.x * cp, chunk_coord.y * cp)

	_terrain_layer = TileMapLayer.new()
	_terrain_layer.name = "Terrain"
	_terrain_layer.tile_set = _tileset
	_terrain_layer.z_index = -10
	add_child(_terrain_layer)

	_resource_layer = TileMapLayer.new()
	_resource_layer.name = "Resources"
	_resource_layer.tile_set = _resource_tileset
	_resource_layer.z_index = -5
	add_child(_resource_layer)

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
	_terrain_bytes = terrain

	for ly: int in range(cs):
		for lx: int in range(cs):
			var idx: int = ly * cs + lx
			var local: Vector2i = Vector2i(lx, ly)

			# Земля (TileMapLayer — fallback / коллизии)
			var atlas_x: int = terrain[idx]
			var h: float = height[idx]
			var atlas_y: int = 1
			if h < 0.38: atlas_y = 0
			elif h > 0.62: atlas_y = 2
			_terrain_layer.set_cell(local, 0, Vector2i(atlas_x, atlas_y))

			# Ресурсы
			var global_tile := Vector2i(start_x + lx, start_y + ly)
			if _modified_tiles.has(global_tile):
				if _modified_tiles[global_tile].get("depleted", false):
					continue

			var dep: int = deposit[idx]
			var tree: int = has_tree[idx]

			if dep > 0:
				var resource_data: ResourceNodeData = resource_defs.get(dep) as ResourceNodeData
				if not resource_data:
					continue
				_resource_layer.set_cell(local, 0, Vector2i(dep - 1, 0))
				_resource_data[local] = {
					"deposit": dep,
					"global": global_tile,
					"definition": resource_data,
					"remaining": resource_data.harvest_count,
					"depleted": false,
				}
			elif tree > 0:
				var tree_data: ResourceNodeData = resource_defs.get(-1) as ResourceNodeData
				if not tree_data:
					continue
				_resource_layer.set_cell(local, 0, Vector2i(4, 0))
				_resource_data[local] = {
					"deposit": -1,
					"global": global_tile,
					"definition": tree_data,
					"remaining": tree_data.harvest_count,
					"depleted": false,
				}
	is_loaded = true

## Настроить шейдер земли. Вызывается после populate_native.
func setup_terrain_shader(textures: Dictionary) -> void:
	var shader: Shader = textures.get("shader") as Shader
	if not shader or _terrain_bytes.is_empty():
		return

	# Data-текстура (chunk_size × chunk_size, R = тип земли)
	var data_img := Image.create(_chunk_size, _chunk_size, false, Image.FORMAT_R8)
	for y: int in range(_chunk_size):
		for x: int in range(_chunk_size):
			var idx: int = y * _chunk_size + x
			var terrain_type: int = _terrain_bytes[idx] if idx < _terrain_bytes.size() else 0
			var value: float = 0.0
			match terrain_type:
				0: value = 0.0    # GROUND
				1: value = 0.25   # ROCK
				2: value = 0.5    # WATER
				3: value = 0.75   # SAND/SHORE
				4: value = 1.0    # GRASS
			data_img.set_pixel(x, y, Color(value, 0, 0, 1))
	var data_tex := ImageTexture.create_from_image(data_img)

	# Sprite2D на весь чанк
	var chunk_px: int = _chunk_size * _tile_size
	var base_img := Image.create(chunk_px, chunk_px, false, Image.FORMAT_RGBA8)
	base_img.fill(Color.WHITE)

	_terrain_sprite = Sprite2D.new()
	_terrain_sprite.name = "TerrainSprite"
	_terrain_sprite.texture = ImageTexture.create_from_image(base_img)
	_terrain_sprite.centered = false
	_terrain_sprite.z_index = -10

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("terrain_map", data_tex)
	if textures.has("plains"):
		mat.set_shader_parameter("tex_plains", textures["plains"])
	if textures.has("rock"):
		mat.set_shader_parameter("tex_rock", textures["rock"])
	if textures.has("shore"):
		mat.set_shader_parameter("tex_shore", textures["shore"])
	mat.set_shader_parameter("chunk_world_size", Vector2(chunk_px, chunk_px))
	mat.set_shader_parameter("chunk_world_offset", Vector2(
		chunk_coord.x * chunk_px, chunk_coord.y * chunk_px
	))
	mat.set_shader_parameter("texture_scale", 6.0)

	_terrain_sprite.material = mat
	add_child(_terrain_sprite)

	# Скрыть TileMapLayer (шейдер рисует), оставить для коллизий
	_terrain_layer.visible = false

## Попытаться добыть ресурс в локальном тайле.
func try_harvest_at(local_tile: Vector2i) -> Dictionary:
	if not _resource_data.has(local_tile):
		return {}
	var rd: Dictionary = _resource_data[local_tile]
	if rd.get("depleted", false):
		return {}

	rd["remaining"] = rd["remaining"] - 1
	var dep: int = rd["deposit"]
	var definition: ResourceNodeData = rd.get("definition") as ResourceNodeData
	var result: Dictionary = _get_harvest_result(definition)

	if rd["remaining"] <= 0:
		rd["depleted"] = true
		_resource_layer.erase_cell(local_tile)
		var global: Vector2i = rd["global"]
		_modified_tiles[global] = {"depleted": true}
		is_dirty = true
		EventBus.resource_node_depleted.emit(global, dep)

	return result

func has_resource_at(local_tile: Vector2i) -> bool:
	if not _resource_data.has(local_tile):
		return false
	return not _resource_data[local_tile].get("depleted", false)

func global_to_local(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

func get_modifications() -> Dictionary:
	return _modified_tiles.duplicate()

func mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void:
	_modified_tiles[tile_pos] = state
	is_dirty = true

func cleanup() -> void:
	is_loaded = false
	_resource_data.clear()
	_terrain_bytes = PackedByteArray()

func _get_harvest_result(definition: ResourceNodeData) -> Dictionary:
	if not definition:
		return {}
	return {
		"item_id": definition.drop_item_id,
		"amount": randi_range(definition.drop_amount_min, definition.drop_amount_max),
	}
