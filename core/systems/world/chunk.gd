class_name Chunk
extends Node2D

## Один чанк мира (64×64 тайла). v6: только земля + горы, без ресурсов.

var chunk_coord: Vector2i = Vector2i.ZERO
var is_loaded: bool = false
var is_dirty: bool = false

var _terrain_layer: TileMapLayer = null
var _tile_size: int = 64
var _chunk_size: int = 64
var _tileset: TileSet = null
var _modified_tiles: Dictionary = {}
var _biome: BiomeData = null
var _terrain_bytes: PackedByteArray = PackedByteArray()
var _rock_collision: StaticBody2D = null
# TODO: вернуть когда добавим шейдер обратно
#var _terrain_sprite: Sprite2D = null
#var _terrain_material: ShaderMaterial = null
#var _roof_image: Image = null
#var _roof_texture: ImageTexture = null

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

## Заполнить из C++ данных.
func populate_native(
	native_data: Dictionary,
	saved_modifications: Dictionary
) -> void:
	_modified_tiles = saved_modifications.duplicate()
	var cs: int = native_data.get("chunk_size", _chunk_size)
	var terrain: PackedByteArray = native_data.get("terrain", PackedByteArray())
	var height: PackedFloat32Array = native_data.get("height", PackedFloat32Array())
	_terrain_bytes = terrain

	for ly: int in range(cs):
		for lx: int in range(cs):
			var idx: int = ly * cs + lx
			if idx >= terrain.size():
				continue
			var local: Vector2i = Vector2i(lx, ly)

			# Terrain: 0=GROUND, 1=ROCK
			var atlas_x: int = terrain[idx]
			var h: float = height[idx] if idx < height.size() else 0.5
			var atlas_y: int = 1
			if h < 0.38: atlas_y = 0
			elif h > 0.62: atlas_y = 2
			_terrain_layer.set_cell(local, 0, Vector2i(atlas_x, atlas_y))

	is_loaded = true
	_build_rock_collision()

func global_to_local(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

func get_modifications() -> Dictionary:
	return _modified_tiles.duplicate()

## Построить коллизию для краевых ROCK тайлов.
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

func _remove_collision_at(local: Vector2i) -> void:
	if not _rock_collision:
		return
	var target_pos := Vector2(local.x * _tile_size + _tile_size * 0.5, local.y * _tile_size + _tile_size * 0.5)
	for child: Node in _rock_collision.get_children():
		var col: CollisionShape2D = child as CollisionShape2D
		if col and col.position.distance_to(target_pos) < 1.0:
			col.queue_free()
			break

## Изменить тип terrain (для копания).
func set_terrain_type_at(local: Vector2i, new_type: int) -> void:
	var idx: int = local.y * _chunk_size + local.x
	if idx < 0 or idx >= _terrain_bytes.size():
		return
	_terrain_bytes[idx] = new_type
	if new_type != 1:
		_remove_collision_at(local)
	# Обновить TileMapLayer
	_terrain_layer.set_cell(local, 0, Vector2i(new_type if new_type <= 1 else 0, 1))
	is_dirty = true

func get_terrain_type_at(local: Vector2i) -> int:
	var idx: int = local.y * _chunk_size + local.x
	if idx < 0 or idx >= _terrain_bytes.size():
		return 0
	return _terrain_bytes[idx]

func mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void:
	_modified_tiles[tile_pos] = state
	is_dirty = true

func cleanup() -> void:
	is_loaded = false
	_terrain_bytes = PackedByteArray()
