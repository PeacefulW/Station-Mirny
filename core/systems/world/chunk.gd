class_name Chunk
extends Node2D

## Один чанк мира.
## Хранит terrain-данные, exterior shell cover и локальные модификации.

const REDRAW_PHASE_TERRAIN: int = 0
const REDRAW_PHASE_COVER: int = 1
const REDRAW_PHASE_CLIFF: int = 2
const REDRAW_PHASE_DEBUG_INTERIOR: int = 3
const REDRAW_PHASE_DEBUG_COLLISION: int = 4
const REDRAW_PHASE_DONE: int = 5
const _COVER_REVEAL_DIRS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1),
]

var chunk_coord: Vector2i = Vector2i.ZERO
var is_loaded: bool = false
var is_dirty: bool = false

var _terrain_layer: TileMapLayer = null
var _cover_layer: TileMapLayer = null
var _cliff_layer: TileMapLayer = null
var _fog_layer: TileMapLayer = null
var _debug_root: Node2D = null
var _tile_size: int = 64
var _chunk_size: int = 64
var _terrain_tileset: TileSet = null
var _overlay_tileset: TileSet = null
var _chunk_manager: ChunkManager = null
var _modified_tiles: Dictionary = {}
var _biome: BiomeData = null
var _terrain_bytes: PackedByteArray = PackedByteArray()
var _height_bytes: PackedFloat32Array = PackedFloat32Array()
var _variation_bytes: PackedByteArray = PackedByteArray()
var _has_mountain: bool = false
var _redraw_phase: int = REDRAW_PHASE_DONE
var _redraw_tile_index: int = 0
var _revealed_local_cover_tiles: Dictionary = {}
var _is_underground: bool = false

func setup(
	p_coord: Vector2i,
	p_tile_size: int,
	p_chunk_size: int,
	p_biome: BiomeData,
	p_terrain_tileset: TileSet,
	p_overlay_tileset: TileSet,
	p_chunk_manager: ChunkManager
) -> void:
	chunk_coord = WorldGenerator.canonicalize_chunk_coord(p_coord) if WorldGenerator else p_coord
	_tile_size = p_tile_size
	_chunk_size = p_chunk_size
	_biome = p_biome
	_terrain_tileset = p_terrain_tileset
	_overlay_tileset = p_overlay_tileset
	_chunk_manager = p_chunk_manager
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
	_variation_bytes = native_data.get("variation", PackedByteArray()).duplicate()
	if _variation_bytes.size() != _terrain_bytes.size():
		_variation_bytes = PackedByteArray()
	_apply_saved_modifications()
	_cache_has_mountain()
	_reset_cover_visual_state()
	if instant:
		_redraw_all()
	else:
		_begin_progressive_redraw()
	is_loaded = true

func complete_redraw_now() -> void:
	_redraw_all()

func global_to_local(global_tile: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("tile_to_local_in_chunk"):
		return WorldGenerator.tile_to_local_in_chunk(global_tile, chunk_coord)
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

func set_revealed_local_zone(zone_tiles: Dictionary) -> void:
	set_revealed_local_cover_tiles(_build_revealed_local_cover_tiles(zone_tiles))

func set_revealed_local_cover_tiles(cover_tiles: Dictionary) -> void:
	_apply_local_zone_cover_state(cover_tiles)

# --- Underground Fog of War ---

## Mark this chunk as underground. Must be called BEFORE redraw.
func set_underground(value: bool) -> void:
	_is_underground = value

## Initialize fog layer for underground chunks. Fills all tiles with UNSEEN.
func init_fog_layer(fog_tileset: TileSet) -> void:
	if _fog_layer:
		return
	_fog_layer = TileMapLayer.new()
	_fog_layer.name = "FogLayer"
	_fog_layer.tile_set = fog_tileset
	_fog_layer.z_index = 7  # Above cover_layer(6), below debug(50)
	add_child(_fog_layer)
	# Fill with UNSEEN
	for y: int in range(_chunk_size):
		for x: int in range(_chunk_size):
			_fog_layer.set_cell(
				Vector2i(x, y),
				ChunkTilesetFactory.FOG_SOURCE_ID,
				ChunkTilesetFactory.TILE_FOG_UNSEEN
			)

## Erase fog for tiles that are currently visible (player nearby).
## Also redraws terrain to update wall variants with current neighbor data.
func apply_fog_visible(visible_locals: Dictionary) -> void:
	if not _fog_layer:
		return
	for local: Vector2i in visible_locals:
		if _is_inside(local):
			_fog_layer.erase_cell(local)
			_redraw_terrain_tile(local)

## Set DISCOVERED fog tile for tiles that were visible but player moved away.
func apply_fog_discovered(discovered_locals: Dictionary) -> void:
	if not _fog_layer:
		return
	for local: Vector2i in discovered_locals:
		if _is_inside(local):
			_fog_layer.set_cell(
				local,
				ChunkTilesetFactory.FOG_SOURCE_ID,
				ChunkTilesetFactory.TILE_FOG_DISCOVERED
			)

## Returns true if this tile should have fog removed when in reveal radius.
## - MINED_FLOOR / MOUNTAIN_ENTRANCE: always (open space)
## - GROUND: always (surface terrain, shouldn't normally appear underground)
## - ROCK: only if adjacent (8-dir) to open space — visible cave wall face
## - Deep rock with no open neighbors: stays hidden under fog (dark mass)
func is_fog_revealable(local_tile: Vector2i) -> bool:
	if not _is_inside(local_tile):
		return false
	var terrain: int = get_terrain_type_at(local_tile)
	if terrain == TileGenData.TerrainType.MINED_FLOOR \
		or terrain == TileGenData.TerrainType.MOUNTAIN_ENTRANCE \
		or terrain == TileGenData.TerrainType.GROUND:
		return true
	# Rock adjacent to open space (any of 8 directions) = visible wall
	if terrain == TileGenData.TerrainType.ROCK:
		return _is_cave_edge_rock(local_tile)
	return false

func is_revealable_cover_edge(local_tile: Vector2i) -> bool:
	if not _is_inside(local_tile):
		return false
	if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
		return false
	return _is_cave_edge_rock(local_tile)

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
	_variation_bytes = PackedByteArray()
	_revealed_local_cover_tiles = {}

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
	_reset_cover_visual_state()
	for child: Node in _debug_root.get_children():
		child.queue_free()
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var tile := Vector2i(local_x, local_y)
			_redraw_terrain_tile(tile)
			_redraw_cover_tile(tile)
			_redraw_cliff_tile(tile)
	_rebuild_debug_markers()
	_redraw_phase = REDRAW_PHASE_DONE
	_redraw_tile_index = 0
	WorldPerfProbe.end("Chunk._redraw_all %s" % [chunk_coord], started_usec)

func _begin_progressive_redraw() -> void:
	_terrain_layer.clear()
	_cover_layer.clear()
	_cliff_layer.clear()
	_reset_cover_visual_state()
	for child: Node in _debug_root.get_children():
		child.queue_free()
	_redraw_phase = REDRAW_PHASE_TERRAIN
	_redraw_tile_index = 0

func is_redraw_complete() -> bool:
	return _redraw_phase == REDRAW_PHASE_DONE

func continue_redraw(max_rows: int) -> bool:
	if _redraw_phase == REDRAW_PHASE_DONE:
		return true
	while _redraw_phase != REDRAW_PHASE_DONE:
		if _redraw_phase == REDRAW_PHASE_DEBUG_INTERIOR or _redraw_phase == REDRAW_PHASE_DEBUG_COLLISION:
			if not _should_build_debug_markers():
				_advance_redraw_phase()
				continue
		var processed_phase: int = _redraw_phase
		var phase_start_index: int = _redraw_tile_index
		var processed: int = _process_redraw_phase_tiles(_resolve_redraw_phase_tile_budget(max_rows))
		if processed <= 0:
			_advance_redraw_phase()
			continue
		if processed_phase == REDRAW_PHASE_COVER:
			_reapply_local_zone_cover_state_for_index_range(phase_start_index, _redraw_tile_index)
		if _redraw_tile_index >= _chunk_size * _chunk_size:
			_advance_redraw_phase()
		return _redraw_phase == REDRAW_PHASE_DONE
	return true

func _redraw_dynamic_visibility(_dirty_tiles: Dictionary) -> void:
	_rebuild_cover_layer()
	_reapply_local_zone_cover_state()
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
	_reapply_local_zone_cover_state_for_tiles(dirty_tiles)
	if WorldGenerator and WorldGenerator.balance and WorldGenerator.balance.mountain_debug_visualization:
		for child: Node in _debug_root.get_children():
			child.queue_free()
		_rebuild_debug_markers()

func _redraw_cover_tiles(dirty_tiles: Dictionary) -> void:
	for local_tile: Vector2i in dirty_tiles:
		if not _is_inside(local_tile):
			continue
		_cover_layer.erase_cell(local_tile)
		_redraw_cover_tile(local_tile)
	_reapply_local_zone_cover_state_for_tiles(dirty_tiles)

func _reset_cover_visual_state() -> void:
	if _cover_layer:
		_cover_layer.visible = true
	_reapply_local_zone_cover_state()

func _redraw_terrain_tile(local_tile: Vector2i) -> void:
	var terrain_type: int = get_terrain_type_at(local_tile)
	var atlas: Vector2i = ChunkTilesetFactory.TILE_GROUND
	var alt_id: int = 0
	match terrain_type:
		TileGenData.TerrainType.ROCK:
			# All rock uses wall face variants (47 types). Underground non-edge rock
			# is hidden by fog layer anyway — no need for special dark tile.
			var result: Array = _apply_variant_full(
				_rock_visual_class(local_tile), local_tile)
			atlas = result[0]
			alt_id = result[1]
		TileGenData.TerrainType.WATER:
			atlas = ChunkTilesetFactory.tile_water
		TileGenData.TerrainType.SAND:
			atlas = ChunkTilesetFactory.tile_sand
		TileGenData.TerrainType.GRASS:
			atlas = ChunkTilesetFactory.tile_grass
		TileGenData.TerrainType.MINED_FLOOR:
			atlas = ChunkTilesetFactory.TILE_MINED_FLOOR
		TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			atlas = ChunkTilesetFactory.TILE_MOUNTAIN_ENTRANCE
		_:
			atlas = _resolve_surface_ground_atlas(local_tile)
	_terrain_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, atlas, alt_id)

func _resolve_surface_ground_atlas(local_tile: Vector2i) -> Vector2i:
	if _is_underground:
		return _ground_atlas_for_height(_height_at(local_tile))
	var variation_tile: Vector2i = ChunkTilesetFactory.get_surface_variation_tile(_variation_at(local_tile))
	if variation_tile.x >= 0:
		return variation_tile
	return _ground_atlas_for_height(_height_at(local_tile))

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
	return _get_global_terrain(_to_global_tile(local_tile))

func _get_global_terrain(global_tile: Vector2i) -> int:
	if _chunk_manager:
		return _chunk_manager.get_terrain_type_at_global(global_tile)
	if WorldGenerator and WorldGenerator._is_initialized:
		return WorldGenerator.get_tile_data(global_tile.x, global_tile.y).terrain
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

func _rebuild_cover_layer() -> void:
	if not _cover_layer:
		return
	_cover_layer.clear()
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			_redraw_cover_tile(Vector2i(local_x, local_y))
	_reapply_local_zone_cover_state()

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
	# Underground z-levels don't use roof/cover system (ADR-0006).
	# Visibility handled by fog layer instead.
	if _is_underground:
		return
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

func _variation_at(local_tile: Vector2i) -> int:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _variation_bytes.size():
		return ChunkTilesetFactory.SURFACE_VARIATION_NONE
	return _variation_bytes[idx]

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
	if WorldGenerator and WorldGenerator.has_method("chunk_local_to_tile"):
		return WorldGenerator.chunk_local_to_tile(chunk_coord, local_tile)
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

func _resolve_redraw_tile_budget(max_rows: int) -> int:
	var row_budget: int = maxi(1, max_rows) * _chunk_size
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, mini(row_budget, WorldGenerator.balance.chunk_redraw_tiles_per_step))
	return row_budget

func _resolve_redraw_phase_tile_budget(max_rows: int) -> int:
	var base_budget: int = _resolve_redraw_tile_budget(max_rows)
	match _redraw_phase:
		REDRAW_PHASE_TERRAIN:
			return maxi(1, base_budget / 2)
		REDRAW_PHASE_COVER, REDRAW_PHASE_DEBUG_INTERIOR, REDRAW_PHASE_DEBUG_COLLISION:
			return maxi(1, base_budget / 2)
		_:
			return base_budget

func _build_revealed_local_cover_tiles(zone_tiles: Dictionary) -> Dictionary:
	var reveal_tiles: Dictionary = {}
	if zone_tiles.is_empty():
		return reveal_tiles
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			var global_tile: Vector2i = _to_global_tile(local_tile)
			if zone_tiles.has(global_tile):
				reveal_tiles[local_tile] = true
				continue
			if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
				continue
			if not _is_cave_edge_rock(local_tile):
				continue
			for dir: Vector2i in _COVER_REVEAL_DIRS:
				var neighbor_tile: Vector2i = WorldGenerator.offset_tile(global_tile, dir) if WorldGenerator else global_tile + dir
				if zone_tiles.has(neighbor_tile):
					reveal_tiles[local_tile] = true
					break
	return reveal_tiles

func _apply_local_zone_cover_state(next_cover_tiles: Dictionary) -> void:
	if not _cover_layer:
		_revealed_local_cover_tiles = next_cover_tiles
		return
	for local_tile: Vector2i in _revealed_local_cover_tiles:
		if next_cover_tiles.has(local_tile):
			continue
		_redraw_cover_tile(local_tile)
	for local_tile: Vector2i in next_cover_tiles:
		if _revealed_local_cover_tiles.has(local_tile):
			continue
		_cover_layer.erase_cell(local_tile)
	_revealed_local_cover_tiles = next_cover_tiles

func _reapply_local_zone_cover_state() -> void:
	if not _cover_layer or _revealed_local_cover_tiles.is_empty():
		return
	for local_tile: Vector2i in _revealed_local_cover_tiles:
		_cover_layer.erase_cell(local_tile)

func _reapply_local_zone_cover_state_for_tiles(tile_map: Dictionary) -> void:
	if not _cover_layer or _revealed_local_cover_tiles.is_empty() or tile_map.is_empty():
		return
	for local_tile: Vector2i in tile_map:
		if _revealed_local_cover_tiles.has(local_tile):
			_cover_layer.erase_cell(local_tile)

func _reapply_local_zone_cover_state_for_index_range(start_index: int, end_index: int) -> void:
	if not _cover_layer or _revealed_local_cover_tiles.is_empty():
		return
	for tile_index: int in range(start_index, end_index):
		var local_tile: Vector2i = _tile_from_index(tile_index)
		if _revealed_local_cover_tiles.has(local_tile):
			_cover_layer.erase_cell(local_tile)

func get_redraw_phase_name() -> StringName:
	match _redraw_phase:
		REDRAW_PHASE_TERRAIN:
			return &"terrain"
		REDRAW_PHASE_COVER:
			return &"cover"
		REDRAW_PHASE_CLIFF:
			return &"cliff"
		REDRAW_PHASE_DEBUG_INTERIOR:
			return &"debug_interior"
		REDRAW_PHASE_DEBUG_COLLISION:
			return &"debug_collision"
		_:
			return &"done"

func _process_redraw_phase_tiles(tile_budget: int) -> int:
	var total_tiles: int = _chunk_size * _chunk_size
	var end_index: int = mini(_redraw_tile_index + tile_budget, total_tiles)
	for tile_index: int in range(_redraw_tile_index, end_index):
		var local_tile: Vector2i = _tile_from_index(tile_index)
		match _redraw_phase:
			REDRAW_PHASE_TERRAIN:
				_redraw_terrain_tile(local_tile)
			REDRAW_PHASE_COVER:
				_redraw_cover_tile(local_tile)
			REDRAW_PHASE_CLIFF:
				_redraw_cliff_tile(local_tile)
			REDRAW_PHASE_DEBUG_INTERIOR:
				_process_debug_marker_tile(local_tile, false)
			REDRAW_PHASE_DEBUG_COLLISION:
				_process_debug_marker_tile(local_tile, true)
			_:
				break
	var processed: int = end_index - _redraw_tile_index
	_redraw_tile_index = end_index
	return processed

func _advance_redraw_phase() -> void:
	match _redraw_phase:
		REDRAW_PHASE_TERRAIN:
			_redraw_phase = REDRAW_PHASE_COVER
		REDRAW_PHASE_COVER:
			_redraw_phase = REDRAW_PHASE_CLIFF
		REDRAW_PHASE_CLIFF:
			if _should_build_debug_markers():
				_redraw_phase = REDRAW_PHASE_DEBUG_INTERIOR
			else:
				_redraw_phase = REDRAW_PHASE_DONE
		REDRAW_PHASE_DEBUG_INTERIOR:
			_redraw_phase = REDRAW_PHASE_DEBUG_COLLISION
		REDRAW_PHASE_DEBUG_COLLISION:
			_redraw_phase = REDRAW_PHASE_DONE
		_:
			_redraw_phase = REDRAW_PHASE_DONE
	_redraw_tile_index = 0

func _should_build_debug_markers() -> bool:
	return WorldGenerator != null \
		and WorldGenerator.balance != null \
		and WorldGenerator.balance.mountain_debug_visualization

func _process_debug_marker_tile(local_tile: Vector2i, collision_only: bool) -> void:
	if collision_only:
		if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
			return
		if _blocks_from_surface(local_tile + Vector2i.UP):
			_add_debug_rect(local_tile, Vector2(0.0, -_tile_size * 0.45), Vector2(_tile_size - 6, 4), WorldGenerator.balance.mountain_debug_collision_color)
		if _blocks_from_surface(local_tile + Vector2i.DOWN):
			_add_debug_rect(local_tile, Vector2(0.0, _tile_size * 0.45), Vector2(_tile_size - 6, 4), WorldGenerator.balance.mountain_debug_collision_color)
		if _blocks_from_surface(local_tile + Vector2i.LEFT):
			_add_debug_rect(local_tile, Vector2(-_tile_size * 0.45, 0.0), Vector2(4, _tile_size - 6), WorldGenerator.balance.mountain_debug_collision_color)
		if _blocks_from_surface(local_tile + Vector2i.RIGHT):
			_add_debug_rect(local_tile, Vector2(_tile_size * 0.45, 0.0), Vector2(4, _tile_size - 6), WorldGenerator.balance.mountain_debug_collision_color)
		return
	var terrain_type: int = get_terrain_type_at(local_tile)
	if terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		_add_debug_rect(local_tile, Vector2.ZERO, Vector2(_tile_size - 18, _tile_size - 18), WorldGenerator.balance.mountain_debug_entrance_color)
	elif terrain_type == TileGenData.TerrainType.MINED_FLOOR:
		_add_debug_rect(local_tile, Vector2.ZERO, Vector2(_tile_size - 24, _tile_size - 24), WorldGenerator.balance.mountain_debug_mined_color)

func _tile_from_index(tile_index: int) -> Vector2i:
	return Vector2i(tile_index % _chunk_size, tile_index / _chunk_size)

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
