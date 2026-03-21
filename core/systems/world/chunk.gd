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
var _terrain_material: ShaderMaterial = null
var _roof_image: Image = null
var _roof_texture: ImageTexture = null
var _cliff_renderer: CliffRenderer = null
var _rock_collision: StaticBody2D = null

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
	_build_rock_collision()
	_build_cliff_sprites()

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

	# Roof map (ROCK тайлы = крыша)
	_roof_image = Image.create(_chunk_size, _chunk_size, false, Image.FORMAT_R8)
	for y2: int in range(_chunk_size):
		for x2: int in range(_chunk_size):
			var idx2: int = y2 * _chunk_size + x2
			var t: int = _terrain_bytes[idx2] if idx2 < _terrain_bytes.size() else 0
			# ROCK(1) и MINED_FLOOR(5) = под крышей, ENTRANCE(6) = нет
			var roof_val: float = 1.0 if (t == 1 or t == 5) else 0.0
			_roof_image.set_pixel(x2, y2, Color(roof_val, 0, 0, 1))
	_roof_texture = ImageTexture.create_from_image(_roof_image)

	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = shader
	_terrain_material.set_shader_parameter("terrain_map", data_tex)
	_terrain_material.set_shader_parameter("roof_map", _roof_texture)
	_terrain_material.set_shader_parameter("roof_opacity", 1.0)
	if textures.has("plains"):
		_terrain_material.set_shader_parameter("tex_plains", textures["plains"])
	if textures.has("rock"):
		_terrain_material.set_shader_parameter("tex_rock", textures["rock"])
	if textures.has("shore"):
		_terrain_material.set_shader_parameter("tex_shore", textures["shore"])
	_terrain_material.set_shader_parameter("chunk_world_size", Vector2(chunk_px, chunk_px))
	_terrain_material.set_shader_parameter("chunk_world_offset", Vector2(
		chunk_coord.x * chunk_px, chunk_coord.y * chunk_px
	))
	_terrain_material.set_shader_parameter("texture_scale", 6.0)

	_terrain_sprite.material = _terrain_material
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

## Построить StaticBody2D коллизию для краевых ROCK тайлов.
func _build_rock_collision() -> void:
	if _rock_collision:
		_rock_collision.queue_free()
	_rock_collision = StaticBody2D.new()
	_rock_collision.name = "RockCollision"
	_rock_collision.collision_layer = 2
	_rock_collision.collision_mask = 0
	add_child(_rock_collision)

	for ly: int in range(_chunk_size):
		for lx: int in range(_chunk_size):
			var idx: int = ly * _chunk_size + lx
			if idx >= _terrain_bytes.size() or _terrain_bytes[idx] != 1:
				continue
			if _is_interior_rock(lx, ly):
				continue
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(_tile_size, _tile_size)
			shape.shape = rect
			shape.position = Vector2(lx * _tile_size + _tile_size * 0.5, ly * _tile_size + _tile_size * 0.5)
			_rock_collision.add_child(shape)

## Тайл внутренний (все 4 соседа = ROCK).
func _is_interior_rock(lx: int, ly: int) -> bool:
	for off: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var nx: int = lx + off.x
		var ny: int = ly + off.y
		if nx < 0 or nx >= _chunk_size or ny < 0 or ny >= _chunk_size:
			continue
		var nidx: int = ny * _chunk_size + nx
		if nidx >= _terrain_bytes.size() or _terrain_bytes[nidx] != 1:
			return false
	return true

## Построить клиф-спрайты по краям горных формаций.
func _build_cliff_sprites() -> void:
	if _cliff_renderer:
		_cliff_renderer.queue_free()
	_cliff_renderer = CliffRenderer.new()
	_cliff_renderer.name = "CliffRenderer"
	add_child(_cliff_renderer)
	_cliff_renderer.build_cliffs(_terrain_bytes, _chunk_size, _tile_size, chunk_coord)

## Убрать коллизию с тайла (при копании).
func _remove_collision_at(local: Vector2i) -> void:
	if not _rock_collision:
		return
	var target_pos := Vector2(local.x * _tile_size + _tile_size * 0.5, local.y * _tile_size + _tile_size * 0.5)
	for child: Node in _rock_collision.get_children():
		var col: CollisionShape2D = child as CollisionShape2D
		if col and col.position.distance_to(target_pos) < 1.0:
			col.queue_free()
			break

## Задать roof_opacity для шейдера (0=скрыта, 1=видна).
func set_roof_opacity(value: float) -> void:
	if _terrain_material:
		_terrain_material.set_shader_parameter("roof_opacity", value)

## Изменить тип terrain в тайле (для копания).
func set_terrain_type_at(local: Vector2i, new_type: int) -> void:
	var idx: int = local.y * _chunk_size + local.x
	if idx < 0 or idx >= _terrain_bytes.size():
		return
	_terrain_bytes[idx] = new_type
	_update_terrain_textures_at(local, new_type)
	# Обновить коллизию и клифы при копании
	if new_type != 1:
		_remove_collision_at(local)
	_build_cliff_sprites()
	is_dirty = true

## Получить тип terrain в локальном тайле.
func get_terrain_type_at(local: Vector2i) -> int:
	var idx: int = local.y * _chunk_size + local.x
	if idx < 0 or idx >= _terrain_bytes.size():
		return 0
	return _terrain_bytes[idx]

## Обновить data-текстуры (terrain_map + roof_map) после изменения тайла.
func _update_terrain_textures_at(local: Vector2i, new_type: int) -> void:
	if not _terrain_material:
		return

	# Обновить terrain_map
	var terrain_value: float = 0.0
	match new_type:
		0: terrain_value = 0.0
		1: terrain_value = 0.25
		2: terrain_value = 0.5
		3: terrain_value = 0.75
		4: terrain_value = 1.0
		5: terrain_value = 0.0   # MINED_FLOOR → пол (как GROUND)
		6: terrain_value = 0.0   # ENTRANCE → пол
	var terrain_img: Image = (_terrain_material.get_shader_parameter("terrain_map") as ImageTexture).get_image()
	if terrain_img:
		terrain_img.set_pixel(local.x, local.y, Color(terrain_value, 0, 0, 1))
		(_terrain_material.get_shader_parameter("terrain_map") as ImageTexture).update(terrain_img)

	# Обновить roof_map
	if _roof_image:
		var roof_val: float = 1.0 if (new_type == 1 or new_type == 5) else 0.0
		_roof_image.set_pixel(local.x, local.y, Color(roof_val, 0, 0, 1))
		if _roof_texture:
			_roof_texture.update(_roof_image)

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
