class_name Chunk
extends Node2D

## Один чанк мира.
## Хранит terrain-данные, roof-оверлей и локальные модификации.

var chunk_coord: Vector2i = Vector2i.ZERO
var is_loaded: bool = false
var is_dirty: bool = false

var _terrain_layer: TileMapLayer = null
var _cover_layer: TileMapLayer = null
var _cliff_layer: TileMapLayer = null
var _debug_root: Node2D = null
var _tile_size: int = 64
var _chunk_size: int = 64
var _terrain_tileset: TileSet = null
var _overlay_tileset: TileSet = null
var _modified_tiles: Dictionary = {}
var _biome: BiomeData = null
var _terrain_bytes: PackedByteArray = PackedByteArray()
var _height_bytes: PackedFloat32Array = PackedFloat32Array()
var _active_mountain_key: Vector2i = Vector2i(999999, 999999)
var _is_mountain_overlay_active: bool = false
var _has_mountain: bool = false
var _redraw_row: int = -1

func setup(
	p_coord: Vector2i,
	p_tile_size: int,
	p_chunk_size: int,
	p_biome: BiomeData,
	p_terrain_tileset: TileSet,
	p_overlay_tileset: TileSet
) -> void:
	chunk_coord = p_coord
	_tile_size = p_tile_size
	_chunk_size = p_chunk_size
	_biome = p_biome
	_terrain_tileset = p_terrain_tileset
	_overlay_tileset = p_overlay_tileset
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	var chunk_pixels: int = _chunk_size * _tile_size
	position = Vector2(chunk_coord.x * chunk_pixels, chunk_coord.y * chunk_pixels)
	_terrain_layer = _create_layer("Terrain", _terrain_tileset, -10)
	_cliff_layer = _create_layer("Cliffs", _overlay_tileset, -9)
	_cover_layer = _create_layer("MountainCover", _terrain_tileset, 6)
	_debug_root = Node2D.new()
	_debug_root.name = "DebugRoot"
	_debug_root.z_index = 50
	add_child(_debug_root)

func populate_native(native_data: Dictionary, saved_modifications: Dictionary, instant: bool = false) -> void:
	_modified_tiles = saved_modifications.duplicate()
	_terrain_bytes = native_data.get("terrain", PackedByteArray()).duplicate()
	_height_bytes = native_data.get("height", PackedFloat32Array()).duplicate()
	_apply_saved_modifications()
	_cache_has_mountain()
	if instant:
		_redraw_all()
	else:
		_begin_progressive_redraw()
	is_loaded = true

func global_to_local(global_tile: Vector2i) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

func has_any_mountain() -> bool:
	return _has_mountain

func get_chunk_size() -> int:
	return _chunk_size

func get_terrain_bytes() -> PackedByteArray:
	return _terrain_bytes

func get_modifications() -> Dictionary:
	return _modified_tiles.duplicate()

func get_terrain_type_at(local: Vector2i) -> int:
	var idx: int = local.y * _chunk_size + local.x
	if idx < 0 or idx >= _terrain_bytes.size():
		return TileGenData.TerrainType.GROUND
	return _terrain_bytes[idx]

func mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void:
	_modified_tiles[tile_pos] = state
	is_dirty = true

func is_roofed_terrain(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.ROCK or terrain_type == TileGenData.TerrainType.MINED_FLOOR

func set_mountain_cover_hidden(is_hidden: bool, mountain_key: Vector2i = Vector2i(999999, 999999)) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	var topology_changed: bool = _is_mountain_overlay_active != is_hidden or _active_mountain_key != mountain_key
	_active_mountain_key = mountain_key
	_is_mountain_overlay_active = is_hidden
	if is_loaded and has_any_mountain() and topology_changed:
		_apply_overlay_visibility()
	WorldPerfProbe.end("Chunk.set_mountain_cover_hidden %s" % [chunk_coord], started_usec)

func try_mine_at(local: Vector2i) -> Dictionary:
	var started_usec: int = WorldPerfProbe.begin()
	if not _is_inside(local):
		return {}
	var old_type: int = get_terrain_type_at(local)
	if old_type != TileGenData.TerrainType.ROCK:
		return {}
	var new_type: int = _resolve_open_tile_type(local)
	_set_terrain_type(local, new_type)
	_refresh_open_neighbors(local)
	var dirty_tiles: Dictionary = _collect_mining_dirty_tiles(local)
	_redraw_dirty_tiles(dirty_tiles)
	WorldPerfProbe.end("Chunk.try_mine_at %s" % [chunk_coord], started_usec)
	return {"old_type": old_type, "new_type": new_type}

func cleanup() -> void:
	is_loaded = false
	_terrain_bytes = PackedByteArray()
	_height_bytes = PackedFloat32Array()

func _create_layer(layer_name: String, tileset: TileSet, z_index_value: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	layer.z_index = z_index_value
	add_child(layer)
	return layer

func _apply_saved_modifications() -> void:
	for tile_pos: Vector2i in _modified_tiles:
		var state: Dictionary = _modified_tiles[tile_pos]
		if state.has("terrain"):
			_set_terrain_type(tile_pos, int(state["terrain"]), false)

func _redraw_all() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	_terrain_layer.clear()
	_cover_layer.clear()
	_cliff_layer.clear()
	for child: Node in _debug_root.get_children():
		child.queue_free()
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var tile := Vector2i(local_x, local_y)
			_redraw_terrain_tile(tile)
			_redraw_cover_tile(tile)
			_redraw_cliff_tile(tile)
	_apply_overlay_visibility()
	_rebuild_debug_markers()
	WorldPerfProbe.end("Chunk._redraw_all %s" % [chunk_coord], started_usec)

func _begin_progressive_redraw() -> void:
	_terrain_layer.clear()
	_cover_layer.clear()
	_cliff_layer.clear()
	for child: Node in _debug_root.get_children():
		child.queue_free()
	_redraw_row = 0

func is_redraw_complete() -> bool:
	return _redraw_row < 0

func continue_redraw(max_rows: int) -> bool:
	if _redraw_row < 0:
		return true
	var end_row: int = mini(_redraw_row + max_rows, _chunk_size)
	for local_y: int in range(_redraw_row, end_row):
		for local_x: int in range(_chunk_size):
			var tile := Vector2i(local_x, local_y)
			_redraw_terrain_tile(tile)
			_redraw_cover_tile(tile)
			_redraw_cliff_tile(tile)
	_redraw_row = end_row
	if _redraw_row >= _chunk_size:
		_redraw_row = -1
		_apply_overlay_visibility()
		_rebuild_debug_markers()
		return true
	return false

func _redraw_dynamic_visibility(_dirty_tiles: Dictionary) -> void:
	_apply_overlay_visibility()
	if WorldGenerator and WorldGenerator.balance and WorldGenerator.balance.mountain_debug_visualization:
		for child: Node in _debug_root.get_children():
			child.queue_free()
		_rebuild_debug_markers()

func _redraw_dirty_tiles(dirty_tiles: Dictionary) -> void:
	for local_tile: Vector2i in dirty_tiles:
		if not _is_inside(local_tile):
			continue
		_terrain_layer.erase_cell(local_tile)
		_cover_layer.erase_cell(local_tile)
		_cliff_layer.erase_cell(local_tile)
		_redraw_terrain_tile(local_tile)
		_redraw_cover_tile(local_tile)
		_redraw_cliff_tile(local_tile)
	_apply_overlay_visibility()
	if WorldGenerator and WorldGenerator.balance and WorldGenerator.balance.mountain_debug_visualization:
		for child: Node in _debug_root.get_children():
			child.queue_free()
		_rebuild_debug_markers()

func _redraw_terrain_tile(local_tile: Vector2i) -> void:
	var terrain_type: int = get_terrain_type_at(local_tile)
	var atlas: Vector2i = ChunkTilesetFactory.TILE_GROUND
	var alt_id: int = 0
	match terrain_type:
		TileGenData.TerrainType.ROCK:
			var result: Array = _apply_variant_full(
				_rock_visual_class(local_tile), local_tile)
			atlas = result[0]
			alt_id = result[1]
		TileGenData.TerrainType.MINED_FLOOR:
			atlas = ChunkTilesetFactory.TILE_MINED_FLOOR
		TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			atlas = ChunkTilesetFactory.TILE_MOUNTAIN_ENTRANCE
		_:
			atlas = _ground_atlas_for_height(_height_at(local_tile))
	_terrain_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, atlas, alt_id)

func _ground_atlas_for_height(height_value: float) -> Vector2i:
	if height_value < 0.38:
		return ChunkTilesetFactory.TILE_GROUND_DARK
	if height_value > 0.62:
		return ChunkTilesetFactory.TILE_GROUND_LIGHT
	return ChunkTilesetFactory.TILE_GROUND

func _resolve_open_tile_type(local_tile: Vector2i) -> int:
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _is_open_exterior(_get_neighbor_terrain(local_tile + dir)):
			return TileGenData.TerrainType.MOUNTAIN_ENTRANCE
	return TileGenData.TerrainType.MINED_FLOOR

func _refresh_open_neighbors(local_tile: Vector2i) -> void:
	_refresh_open_tile(local_tile)
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		_refresh_open_tile(local_tile + dir)

func _refresh_open_tile(local_tile: Vector2i) -> void:
	if not _is_inside(local_tile):
		return
	var terrain_type: int = get_terrain_type_at(local_tile)
	if terrain_type != TileGenData.TerrainType.MINED_FLOOR and terrain_type != TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return
	_set_terrain_type(local_tile, _resolve_open_tile_type(local_tile), false)

func _set_terrain_type(local_tile: Vector2i, terrain_type: int, mark_modified: bool = true) -> void:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _terrain_bytes.size():
		return
	_terrain_bytes[idx] = terrain_type
	if not _has_mountain and _is_mountain_terrain(terrain_type):
		_has_mountain = true
	if mark_modified:
		mark_tile_modified(local_tile, {"terrain": terrain_type})
	else:
		_modified_tiles[local_tile] = {"terrain": terrain_type}

func _get_neighbor_terrain(local_tile: Vector2i) -> int:
	if _is_inside(local_tile):
		return get_terrain_type_at(local_tile)
	return TileGenData.TerrainType.GROUND

func _is_open_for_visual(terrain_type: int) -> bool:
	return terrain_type != TileGenData.TerrainType.ROCK

func _is_open_exterior(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.WATER \
		or terrain_type == TileGenData.TerrainType.SAND \
		or terrain_type == TileGenData.TerrainType.GRASS

func _is_rock_at(local_tile: Vector2i) -> bool:
	return _is_inside(local_tile) and get_terrain_type_at(local_tile) == TileGenData.TerrainType.ROCK

func _should_blacken_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var neighbor_type: int = _get_neighbor_terrain(local_tile + dir)
		if _is_open_exterior(neighbor_type):
			return false
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR \
		or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			return false
	return true

func _apply_overlay_visibility() -> void:
	if _cover_layer:
		_cover_layer.visible = not _is_mountain_overlay_active

func refresh_cliffs() -> void:
	if not _cliff_layer:
		return
	_cliff_layer.clear()
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			_redraw_cliff_tile(Vector2i(local_x, local_y))

func _get_sun_direction() -> Vector2:
	if not TimeManager:
		return Vector2(0.0, -1.0)
	var angle: float = TimeManager.get_sun_angle()
	return Vector2(cos(angle), sin(angle))

func _is_cliff_exposed_to_surface(local_tile: Vector2i) -> bool:
	return _is_open_exterior(_get_neighbor_terrain(local_tile))

func _redraw_cliff_tile(_local_tile: Vector2i) -> void:
	pass

func _redraw_cover_tile(local_tile: Vector2i) -> void:
	var terrain: int = get_terrain_type_at(local_tile)
	var need_cover: bool = terrain == TileGenData.TerrainType.MINED_FLOOR \
		or _is_cave_edge_rock(local_tile)
	if not need_cover:
		return
	# Use the same variant hash as terrain layer — mountain looks identical before/after mining
	var base: Vector2i = _cover_rock_atlas(local_tile)
	var result: Array = _apply_variant_full(base, local_tile)
	_cover_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, result[0], result[1])

## XOR-shift hash — no visible linear patterns.
static func _tile_hash(pos: Vector2i) -> int:
	var h: int = pos.x * 374761393 + pos.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)

## Returns [atlas_coords, alternative_tile_id].
func _apply_variant_full(base: Vector2i, local_tile: Vector2i) -> Array:
	var gt: Vector2i = _to_global_tile(local_tile)
	var h: int = _tile_hash(gt)
	var vi: int = 0
	if ChunkTilesetFactory.wall_variant_count > 1:
		vi = h % ChunkTilesetFactory.wall_variant_count
	var atlas := Vector2i(base.x + vi * ChunkTilesetFactory.wall_base_count, 0)
	var def_index: int = base.x - 7
	var alt_id: int = 0
	if def_index >= 0 and def_index < ChunkTilesetFactory._WALL_FLIP_CLASS.size():
		var flip_class: int = ChunkTilesetFactory._WALL_FLIP_CLASS[def_index]
		if flip_class > 0:
			var alt_count: int = ChunkTilesetFactory.wall_flip_alt_count[flip_class]
			var flip_hash: int = _tile_hash(Vector2i(gt.x + 17, gt.y + 31))
			alt_id = flip_hash % alt_count
	return [atlas, alt_id]

func _apply_variant(base: Vector2i, local_tile: Vector2i) -> Vector2i:
	return _apply_variant_full(base, local_tile)[0]

func _rock_visual_class(local_tile: Vector2i) -> Vector2i:
	var s: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i.DOWN))
	var n: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i.UP))
	var w: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i.LEFT))
	var e: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i.RIGHT))
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		if not n: return ChunkTilesetFactory.WALL_PENINSULA_S
		if not s: return ChunkTilesetFactory.WALL_PENINSULA_N
		if not w: return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		if s and w:
			if _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1))):
				return ChunkTilesetFactory.WALL_CORNER_SW_T
			return ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			if _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1))):
				return ChunkTilesetFactory.WALL_CORNER_SE_T
			return ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			if _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1))):
				return ChunkTilesetFactory.WALL_CORNER_NW_T
			return ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			if _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1))):
				return ChunkTilesetFactory.WALL_CORNER_NE_T
			return ChunkTilesetFactory.WALL_CORNER_NE
		if e and w: return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	if count == 1:
		if s:
			var s_ne: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
			var s_nw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
			if s_ne and s_nw: return ChunkTilesetFactory.WALL_T_SOUTH
			if s_ne: return ChunkTilesetFactory.WALL_SOUTH_NE
			if s_nw: return ChunkTilesetFactory.WALL_SOUTH_NW
			return ChunkTilesetFactory.WALL_SOUTH
		if n:
			var n_se: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
			var n_sw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
			if n_se and n_sw: return ChunkTilesetFactory.WALL_T_NORTH
			if n_se: return ChunkTilesetFactory.WALL_NORTH_SE
			if n_sw: return ChunkTilesetFactory.WALL_NORTH_SW
			return ChunkTilesetFactory.WALL_NORTH
		if w:
			var w_ne: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
			var w_se: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
			if w_ne and w_se: return ChunkTilesetFactory.WALL_T_WEST
			if w_ne: return ChunkTilesetFactory.WALL_WEST_NE
			if w_se: return ChunkTilesetFactory.WALL_WEST_SE
			return ChunkTilesetFactory.WALL_WEST
		var e_nw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
		var e_sw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
		if e_nw and e_sw: return ChunkTilesetFactory.WALL_T_EAST
		if e_nw: return ChunkTilesetFactory.WALL_EAST_NW
		if e_sw: return ChunkTilesetFactory.WALL_EAST_SW
		return ChunkTilesetFactory.WALL_EAST
	var d_sw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
	var d_se: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
	var d_ne: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
	var d_nw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
	var d_count: int = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw)
	if d_count == 4:
		return ChunkTilesetFactory.WALL_CROSS
	if d_count == 3:
		if not d_sw: return ChunkTilesetFactory.WALL_DIAG3_NO_SW
		if not d_se: return ChunkTilesetFactory.WALL_DIAG3_NO_SE
		if not d_nw: return ChunkTilesetFactory.WALL_DIAG3_NO_NW
		return ChunkTilesetFactory.WALL_DIAG3_NO_NE
	if d_count == 2:
		if d_sw and d_se: return ChunkTilesetFactory.WALL_EDGE_EW
		if d_ne and d_nw: return ChunkTilesetFactory.WALL_DIAG_NE_NW
		if d_ne and d_se: return ChunkTilesetFactory.WALL_DIAG_NE_SE
		if d_nw and d_sw: return ChunkTilesetFactory.WALL_DIAG_NW_SW
		if d_ne and d_sw: return ChunkTilesetFactory.WALL_DIAG_NE_SW
		return ChunkTilesetFactory.WALL_DIAG_NW_SE
	if d_sw: return ChunkTilesetFactory.WALL_NOTCH_SW
	if d_se: return ChunkTilesetFactory.WALL_NOTCH_SE
	if d_ne: return ChunkTilesetFactory.WALL_NOTCH_NE
	if d_nw: return ChunkTilesetFactory.WALL_NOTCH_NW
	return ChunkTilesetFactory.WALL_INTERIOR

func _rock_atlas(local_tile: Vector2i) -> Vector2i:
	if _is_surface_rock(local_tile):
		return ChunkTilesetFactory.TILE_ROCK
	return ChunkTilesetFactory.TILE_ROCK_INTERIOR

func _cover_rock_atlas(local_tile: Vector2i) -> Vector2i:
	if _is_exterior_surface_rock(local_tile):
		return ChunkTilesetFactory.WALL_SOUTH
	return ChunkTilesetFactory.WALL_INTERIOR

func _is_cave_edge_rock(local_tile: Vector2i) -> bool:
	if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
		return false
	var has_open_neighbor: bool = false
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var neighbor_type: int = _get_neighbor_terrain(local_tile + dir)
		if _is_open_exterior(neighbor_type):
			return false
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			has_open_neighbor = true
	return has_open_neighbor

func _is_exterior_surface_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		if _is_open_exterior(_get_neighbor_terrain(local_tile + dir)):
			return true
	return false

func _is_surface_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var neighbor_type: int = _get_neighbor_terrain(local_tile + dir)
		if _is_open_exterior(neighbor_type):
			return true
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			return true
	return false

func _height_at(local_tile: Vector2i) -> float:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _height_bytes.size():
		return 0.5
	return _height_bytes[idx]

func _cache_has_mountain() -> void:
	_has_mountain = false
	for terrain_type: int in _terrain_bytes:
		if _is_mountain_terrain(terrain_type):
			_has_mountain = true
			return

func _is_mountain_terrain(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.ROCK \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _is_inside(local_tile: Vector2i) -> bool:
	return local_tile.x >= 0 and local_tile.y >= 0 and local_tile.x < _chunk_size and local_tile.y < _chunk_size

func _to_global_tile(local_tile: Vector2i) -> Vector2i:
	return Vector2i(
		chunk_coord.x * _chunk_size + local_tile.x,
		chunk_coord.y * _chunk_size + local_tile.y
	)

func _collect_mining_dirty_tiles(local_tile: Vector2i) -> Dictionary:
	var dirty_tiles: Dictionary = {}
	for offset_x: int in range(-1, 2):
		for offset_y: int in range(-1, 2):
			var tile: Vector2i = local_tile + Vector2i(offset_x, offset_y)
			if _is_inside(tile):
				dirty_tiles[tile] = true
	return dirty_tiles

func _blocks_from_surface(local_tile: Vector2i) -> bool:
	var neighbor_type: int = _get_neighbor_terrain(local_tile)
	return neighbor_type == TileGenData.TerrainType.GROUND \
		or neighbor_type == TileGenData.TerrainType.WATER \
		or neighbor_type == TileGenData.TerrainType.SAND \
		or neighbor_type == TileGenData.TerrainType.GRASS

func _rebuild_debug_markers() -> void:
	if not WorldGenerator or not WorldGenerator.balance or not WorldGenerator.balance.mountain_debug_visualization:
		return
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			var terrain_type: int = get_terrain_type_at(local_tile)
			if terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
				_add_debug_rect(local_tile, Vector2.ZERO, Vector2(_tile_size - 18, _tile_size - 18), WorldGenerator.balance.mountain_debug_entrance_color)
			elif terrain_type == TileGenData.TerrainType.MINED_FLOOR:
				_add_debug_rect(local_tile, Vector2.ZERO, Vector2(_tile_size - 24, _tile_size - 24), WorldGenerator.balance.mountain_debug_mined_color)
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
				continue
			if _blocks_from_surface(local_tile + Vector2i.UP):
				_add_debug_rect(local_tile, Vector2(0.0, -_tile_size * 0.45), Vector2(_tile_size - 6, 4), WorldGenerator.balance.mountain_debug_collision_color)
			if _blocks_from_surface(local_tile + Vector2i.DOWN):
				_add_debug_rect(local_tile, Vector2(0.0, _tile_size * 0.45), Vector2(_tile_size - 6, 4), WorldGenerator.balance.mountain_debug_collision_color)
			if _blocks_from_surface(local_tile + Vector2i.LEFT):
				_add_debug_rect(local_tile, Vector2(-_tile_size * 0.45, 0.0), Vector2(4, _tile_size - 6), WorldGenerator.balance.mountain_debug_collision_color)
			if _blocks_from_surface(local_tile + Vector2i.RIGHT):
				_add_debug_rect(local_tile, Vector2(_tile_size * 0.45, 0.0), Vector2(4, _tile_size - 6), WorldGenerator.balance.mountain_debug_collision_color)

func _add_debug_rect(local_tile: Vector2i, offset: Vector2, size: Vector2, color: Color) -> void:
	var center: Vector2 = Vector2(
		local_tile.x * _tile_size + _tile_size * 0.5,
		local_tile.y * _tile_size + _tile_size * 0.5
	) + offset
	_add_debug_world_rect(center, size, color)

func _add_debug_world_rect(center: Vector2, size: Vector2, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.color = color
	var half: Vector2 = size * 0.5
	poly.position = center
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	_debug_root.add_child(poly)
