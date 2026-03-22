class_name Chunk
extends Node2D

## Один чанк мира (64×64 тайла). v8: горы = RockLayer (TileMapLayer).
## Terrain = только GROUND. Скалы = отдельный слой с коллизией.

var chunk_coord: Vector2i = Vector2i.ZERO
var is_loaded: bool = false
var is_dirty: bool = false

var _terrain_layer: TileMapLayer = null
var _rock_layer: TileMapLayer = null
var _roof_layer: TileMapLayer = null
var _tile_size: int = 64
var _chunk_size: int = 64
var _tileset: TileSet = null
var _rock_tileset: TileSet = null
var _modified_tiles: Dictionary = {}
var _biome: BiomeData = null
var _terrain_bytes: PackedByteArray = PackedByteArray()
var _mined_rocks: Array[Vector2i] = []

func setup(
	p_coord: Vector2i, p_tile_size: int, p_chunk_size: int,
	p_biome: BiomeData, p_tileset: TileSet, p_rock_tileset: TileSet
) -> void:
	chunk_coord = p_coord
	_tile_size = p_tile_size
	_chunk_size = p_chunk_size
	_biome = p_biome
	_tileset = p_tileset
	_rock_tileset = p_rock_tileset
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	var cp: int = _chunk_size * _tile_size
	position = Vector2(chunk_coord.x * cp, chunk_coord.y * cp)

	# Земля (GROUND)
	_terrain_layer = TileMapLayer.new()
	_terrain_layer.name = "Terrain"
	_terrain_layer.tile_set = _tileset
	_terrain_layer.z_index = -10
	add_child(_terrain_layer)

	# Скалы (ROCK) — отдельный слой с коллизией
	if _rock_tileset:
		_rock_layer = TileMapLayer.new()
		_rock_layer.name = "RockLayer"
		_rock_layer.tile_set = _rock_tileset
		_rock_layer.z_index = -5
		add_child(_rock_layer)

		# Крыша горы — тот же тайлсет, поверх всего
		_roof_layer = TileMapLayer.new()
		_roof_layer.name = "RoofLayer"
		_roof_layer.tile_set = _rock_tileset
		_roof_layer.z_index = 5
		add_child(_roof_layer)

## Заполнить из C++ данных.
func populate_native(
	native_data: Dictionary,
	saved_modifications: Dictionary
) -> void:
	_modified_tiles = saved_modifications.duplicate()
	var cs: int = native_data.get("chunk_size", _chunk_size)
	var terrain: PackedByteArray = native_data.get("terrain", PackedByteArray())
	var height: PackedFloat32Array = native_data.get("height", PackedFloat32Array())
	var is_mountain: PackedByteArray = native_data.get("is_mountain", PackedByteArray())

	_terrain_bytes = terrain.duplicate()

	# Загрузить ранее выкопанные тайлы
	var saved_mined: Array = _modified_tiles.get("mined_rocks", [])
	for pos_data: Variant in saved_mined:
		if pos_data is Vector2i:
			_mined_rocks.append(pos_data as Vector2i)

	# Определить горные ячейки
	var rock_set: Dictionary = {}  # Vector2i -> true
	for ly: int in range(cs):
		for lx: int in range(cs):
			var idx: int = ly * cs + lx
			var is_rock: bool = false
			if not is_mountain.is_empty() and idx < is_mountain.size():
				is_rock = is_mountain[idx] == 1
			elif idx < _terrain_bytes.size():
				is_rock = _terrain_bytes[idx] == 1
			if is_rock:
				var local := Vector2i(lx, ly)
				# Пропустить выкопанные
				if local not in _mined_rocks:
					rock_set[local] = true

	# Terrain: всё GROUND (горы рисуются RockLayer)
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

	# RockLayer: ручной автотайлинг (быстрее чем set_cells_terrain_connect)
	if _rock_layer:
		for cell: Vector2i in rock_set:
			var atlas_coord: Vector2i = _get_rock_atlas_coord(cell, rock_set)
			_rock_layer.set_cell(cell, 0, atlas_coord)

	# RoofLayer: только ВНУТРЕННИЕ горные ячейки (все 4 соседа = rock)
	# Краевые тайлы НЕ покрываются крышей — их автотайлинг виден
	if _roof_layer:
		for cell: Vector2i in rock_set:
			var all_sides_rock: bool = true
			for off: Vector2i in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
				if not rock_set.has(cell + off):
					all_sides_rock = false
					break
			if all_sides_rock:
				_roof_layer.set_cell(cell, 0, Vector2i(11, 3))

	is_loaded = true

## Есть ли скала в локальном тайле.
func has_rock_at(local: Vector2i) -> bool:
	if not _rock_layer:
		return false
	return _rock_layer.get_cell_source_id(local) != -1

## Убрать скалу (копание). Пересчитать визуал соседей.
func remove_rock_at(local: Vector2i) -> void:
	if _rock_layer:
		_rock_layer.erase_cell(local)
		# Собрать соседей которые ещё rock
		var rock_neighbors: Array[Vector2i] = []
		for off: Vector2i in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
			Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			var n: Vector2i = local + off
			if has_rock_at(n):
				rock_neighbors.append(n)
		# Обновить визуал: erase + set заново (обновляет и collision)
		for n: Vector2i in rock_neighbors:
			var atlas_coord: Vector2i = _get_rock_atlas_coord_live(n)
			_rock_layer.set_cell(n, 0, atlas_coord)
	if _roof_layer:
		_roof_layer.erase_cell(local)
		for off: Vector2i in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
			var n: Vector2i = local + off
			if has_rock_at(n) and not _is_interior(n):
				_roof_layer.erase_cell(n)
	_mined_rocks.append(local)
	is_dirty = true

# Blob47: bitmask → atlas index. N=1,NE=2,E=4,SE=8,S=16,SW=32,W=64,NW=128
const BLOB_MASKS: Array[int] = [
	0, 1, 4, 5, 7, 16, 17, 20, 21, 23, 28, 29,
	31, 64, 65, 68, 69, 71, 80, 81, 84, 85, 87, 92,
	93, 95, 112, 113, 116, 117, 119, 124, 125, 127, 192, 193,
	197, 199, 208, 209, 212, 213, 215, 240, 241, 245, 247, 255,
]
var _blob_lookup: Dictionary = {}  # bitmask → Vector2i(col, row)

func _init_blob_lookup() -> void:
	if not _blob_lookup.is_empty():
		return
	for i: int in range(BLOB_MASKS.size()):
		_blob_lookup[BLOB_MASKS[i]] = Vector2i(i % 12, i / 12)

## Получить atlas coord для rock ячейки по соседям (из Dictionary).
func _get_rock_atlas_coord(cell: Vector2i, rock_set: Dictionary) -> Vector2i:
	_init_blob_lookup()
	var mask: int = 0
	if rock_set.has(cell + Vector2i(0, -1)):  mask |= 1    # N
	if rock_set.has(cell + Vector2i(1, -1)):  mask |= 2    # NE
	if rock_set.has(cell + Vector2i(1, 0)):   mask |= 4    # E
	if rock_set.has(cell + Vector2i(1, 1)):   mask |= 8    # SE
	if rock_set.has(cell + Vector2i(0, 1)):   mask |= 16   # S
	if rock_set.has(cell + Vector2i(-1, 1)):  mask |= 32   # SW
	if rock_set.has(cell + Vector2i(-1, 0)):  mask |= 64   # W
	if rock_set.has(cell + Vector2i(-1, -1)): mask |= 128  # NW
	# Убрать диагональные биты если соответствующие кардинальные отсутствуют
	if not (mask & 1 and mask & 4):   mask &= ~2    # NE требует N+E
	if not (mask & 4 and mask & 16):  mask &= ~8    # SE требует E+S
	if not (mask & 16 and mask & 64): mask &= ~32   # SW требует S+W
	if not (mask & 64 and mask & 1):  mask &= ~128  # NW требует W+N
	if _blob_lookup.has(mask):
		return _blob_lookup[mask]
	return Vector2i(11, 3)  # fallback: interior

## Получить atlas coord для live TileMapLayer (уже размещённые тайлы).
func _get_rock_atlas_coord_live(cell: Vector2i) -> Vector2i:
	_init_blob_lookup()
	var mask: int = 0
	if has_rock_at(cell + Vector2i(0, -1)):  mask |= 1
	if has_rock_at(cell + Vector2i(1, -1)):  mask |= 2
	if has_rock_at(cell + Vector2i(1, 0)):   mask |= 4
	if has_rock_at(cell + Vector2i(1, 1)):   mask |= 8
	if has_rock_at(cell + Vector2i(0, 1)):   mask |= 16
	if has_rock_at(cell + Vector2i(-1, 1)):  mask |= 32
	if has_rock_at(cell + Vector2i(-1, 0)):  mask |= 64
	if has_rock_at(cell + Vector2i(-1, -1)): mask |= 128
	if not (mask & 1 and mask & 4):   mask &= ~2
	if not (mask & 4 and mask & 16):  mask &= ~8
	if not (mask & 16 and mask & 64): mask &= ~32
	if not (mask & 64 and mask & 1):  mask &= ~128
	if _blob_lookup.has(mask):
		return _blob_lookup[mask]
	return Vector2i(11, 3)

## Внутренний тайл (все 4 кардинальных соседа = скала).
func _is_interior(local: Vector2i) -> bool:
	for off: Vector2i in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		if not has_rock_at(local + off):
			return false
	return true

## Показать/скрыть крышу горы.
func set_roof_visible(visible: bool) -> void:
	if _roof_layer:
		_roof_layer.visible = visible

## Окружён ли тайл скалами (для определения "внутри горы").
func is_surrounded_by_rock(local: Vector2i) -> bool:
	var count: int = 0
	for off: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if has_rock_at(local + off):
			count += 1
	return count >= 3

func global_to_local(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

func get_modifications() -> Dictionary:
	var mods: Dictionary = _modified_tiles.duplicate()
	if not _mined_rocks.is_empty():
		mods["mined_rocks"] = _mined_rocks.duplicate()
	return mods

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
	_mined_rocks.clear()
