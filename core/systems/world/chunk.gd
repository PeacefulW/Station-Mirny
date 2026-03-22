class_name Chunk
extends Node2D

## Один чанк мира. Рисует землю и хранит модификации чанка.

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
	_terrain_bytes = terrain.duplicate()

	# Terrain: всё GROUND
	for ly: int in range(cs):
		for lx: int in range(cs):
			var idx: int = ly * cs + lx
			if idx >= _terrain_bytes.size():
				continue
			var h: float = height[idx] if idx < height.size() else 0.5
			var atlas_y: int = 1
			if h < 0.38: atlas_y = 0
			elif h > 0.62: atlas_y = 2
			_terrain_layer.set_cell(Vector2i(lx, ly), 0, Vector2i(0, atlas_y))

	is_loaded = true

func global_to_local(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

func has_any_mountain() -> bool:
	return false

func get_chunk_size() -> int:
	return _chunk_size

func get_terrain_bytes() -> PackedByteArray:
	return _terrain_bytes

func get_modifications() -> Dictionary:
	return _modified_tiles.duplicate()

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
