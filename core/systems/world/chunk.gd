class_name Chunk
extends Node2D

const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")

## Один чанк мира.
## Хранит terrain-данные, exterior shell cover и локальные модификации.

const REDRAW_PHASE_TERRAIN: int = 0
const REDRAW_PHASE_COVER: int = 1
const REDRAW_PHASE_CLIFF: int = 2
const REDRAW_PHASE_FLORA: int = 3
const REDRAW_PHASE_DEBUG_INTERIOR: int = 4
const REDRAW_PHASE_DEBUG_COLLISION: int = 5
const REDRAW_PHASE_DONE: int = 6
const REDRAW_TIME_BUDGET_USEC: int = 1500
const _CARDINAL_DIRS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]
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
var _ground_face_layer: TileMapLayer = null
var _rock_layer: TileMapLayer = null
var _cover_layer: TileMapLayer = null
var _cliff_layer: TileMapLayer = null
var _gf_debug_printed: bool = false
var _fog_layer: TileMapLayer = null
var _flora_container: Node2D = null
var _flora_result: ChunkFloraResultScript = null
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
var _biome_bytes: PackedByteArray = PackedByteArray()
var _has_mountain: bool = false
var _redraw_phase: int = REDRAW_PHASE_DONE
var _redraw_tile_index: int = 0
var _revealed_local_cover_tiles: Dictionary = {}
var _is_underground: bool = false
var _use_operation_global_terrain_cache: bool = false
var _operation_global_terrain_cache: Dictionary = {}
var _mining_write_authorized: bool = false

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
	sync_display_position(chunk_coord)
	_terrain_layer = _create_layer("Terrain", _terrain_tileset, -12)
	_ground_face_layer = _create_layer("GroundFaces", _terrain_tileset, -11)
	_ground_face_layer.modulate = p_biome.ground_color if p_biome else Color.WHITE
	_rock_layer = _create_layer("Rock", _terrain_tileset, -10)
	_cliff_layer = _create_layer("Cliffs", _overlay_tileset, -9)
	_cover_layer = _create_layer("MountainCover", _terrain_tileset, 6)
	_flora_container = Node2D.new()
	_flora_container.name = "Flora"
	_flora_container.y_sort_enabled = true
	_flora_container.z_index = -5
	add_child(_flora_container)
	_debug_root = Node2D.new()
	_debug_root.name = "DebugRoot"
	_debug_root.z_index = 50
	add_child(_debug_root)

func sync_display_position(reference_chunk: Vector2i) -> void:
	var display_chunk: Vector2i = chunk_coord
	if WorldGenerator and WorldGenerator._is_initialized:
		display_chunk = WorldGenerator.get_display_chunk_coord(chunk_coord, reference_chunk)
	var chunk_pixels: int = _chunk_size * _tile_size
	position = Vector2(display_chunk.x * chunk_pixels, display_chunk.y * chunk_pixels)

func populate_native(native_data: Dictionary, saved_modifications: Dictionary, instant: bool = false) -> void:
	_modified_tiles = saved_modifications.duplicate()
	_terrain_bytes = native_data.get("terrain", PackedByteArray())
	_height_bytes = native_data.get("height", PackedFloat32Array())
	_variation_bytes = native_data.get("variation", PackedByteArray())
	_biome_bytes = native_data.get("biome", PackedByteArray())
	if _variation_bytes.size() != _terrain_bytes.size():
		push_error("Chunk.populate_native(): variation array size mismatch for %s" % [chunk_coord])
		assert(false, "variation array size must match terrain array size")
		_variation_bytes.resize(_terrain_bytes.size())
		_variation_bytes.fill(ChunkTilesetFactory.SURFACE_VARIATION_NONE)
	if _biome_bytes.size() != _terrain_bytes.size():
		push_error("Chunk.populate_native(): biome array size mismatch for %s" % [chunk_coord])
		assert(false, "biome array size must match terrain array size")
		_biome_bytes.resize(_terrain_bytes.size())
		_biome_bytes.fill(0)
	_apply_saved_modifications()
	_cache_has_mountain()
	_reset_cover_visual_state()
	if instant:
		_redraw_all()
	else:
		_begin_progressive_redraw()
	is_loaded = true

func complete_redraw_now(include_flora: bool = false) -> void:
	_redraw_all(include_flora)

## Draws terrain layer immediately for all tiles, then leaves cover/cliff/flora
## for progressive redraw. Used by boot apply for ring 1 chunks so the player
## never sees green placeholder zones near spawn.
func complete_terrain_phase_now() -> void:
	if _redraw_phase != REDRAW_PHASE_TERRAIN:
		return
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			_redraw_terrain_tile(Vector2i(local_x, local_y))
	_redraw_phase = REDRAW_PHASE_COVER
	_redraw_tile_index = 0

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
	if not _is_inside(local):
		push_error("Chunk.get_terrain_type_at(): local tile %s is outside chunk %s" % [local, chunk_coord])
		assert(false, "local terrain read must stay inside chunk bounds")
		return TileGenData.TerrainType.ROCK
	var idx: int = local.y * _chunk_size + local.x
	if idx < 0 or idx >= _terrain_bytes.size():
		push_error("Chunk.get_terrain_type_at(): terrain array index %d is invalid for chunk %s" % [idx, chunk_coord])
		assert(false, "terrain byte array must match chunk bounds")
		return TileGenData.TerrainType.ROCK
	return _terrain_bytes[idx]

func mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void:
	_modified_tiles[tile_pos] = state
	is_dirty = true

func set_revealed_local_cover_tiles(cover_tiles: Dictionary) -> void:
	_apply_local_zone_cover_state(cover_tiles)

func set_mining_write_authorized(value: bool) -> void:
	_mining_write_authorized = value

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
	if not _mining_write_authorized:
		push_error("Chunk.try_mine_at(): unauthorized direct call for chunk %s" % [chunk_coord])
		assert(false, "ChunkManager.try_harvest_at_world() is the safe mining orchestration point")
		return {}
	if not _is_inside(local):
		return {}
	var old_type: int = get_terrain_type_at(local)
	if old_type != TileGenData.TerrainType.ROCK:
		return {}
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	var new_type: int = _resolve_open_tile_type(local)
	_set_terrain_type(local, new_type)
	var dirty_tiles: Dictionary = _collect_mining_dirty_tiles(local)
	_redraw_dirty_tiles(dirty_tiles)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache
	WorldPerfProbe.end("Chunk.try_mine_at %s" % [chunk_coord], started_usec)
	return {"old_type": old_type, "new_type": new_type}

func cleanup() -> void:
	is_loaded = false
	_terrain_bytes = PackedByteArray()
	_height_bytes = PackedFloat32Array()
	_variation_bytes = PackedByteArray()
	_biome_bytes = PackedByteArray()
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
	_normalize_saved_open_tiles_after_load()

func _normalize_saved_open_tiles_after_load() -> void:
	if _modified_tiles.is_empty():
		return
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	var tiles_to_refresh: Dictionary = {}
	for tile_pos: Vector2i in _modified_tiles:
		if not _is_inside(tile_pos):
			continue
		tiles_to_refresh[tile_pos] = true
		for dir: Vector2i in _CARDINAL_DIRS:
			var neighbor_tile: Vector2i = tile_pos + dir
			if _is_inside(neighbor_tile):
				tiles_to_refresh[neighbor_tile] = true
	for tile_pos: Vector2i in tiles_to_refresh:
		_refresh_open_tile(tile_pos)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache

func _redraw_all(include_flora: bool = false) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	_terrain_layer.clear()
	_ground_face_layer.clear()
	_rock_layer.clear()
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
	if include_flora:
		for tile_index: int in range(_chunk_size * _chunk_size):
			_redraw_flora_tile(tile_index)
		_redraw_phase = REDRAW_PHASE_DONE
	else:
		## Flora is deferred to progressive redraw. Set phase to FLORA so
		## progressive path can draw flora without re-doing terrain/cover/cliff.
		_redraw_phase = REDRAW_PHASE_FLORA
	_redraw_tile_index = 0
	WorldPerfProbe.end("Chunk._redraw_all %s" % [chunk_coord], started_usec)

func _begin_progressive_redraw() -> void:
	_terrain_layer.clear()
	_ground_face_layer.clear()
	_rock_layer.clear()
	_cover_layer.clear()
	_cliff_layer.clear()
	_reset_cover_visual_state()
	for child: Node in _debug_root.get_children():
		child.queue_free()
	_redraw_phase = REDRAW_PHASE_TERRAIN
	_redraw_tile_index = 0

func is_redraw_complete() -> bool:
	return _redraw_phase == REDRAW_PHASE_DONE

func is_terrain_phase_done() -> bool:
	return _redraw_phase > REDRAW_PHASE_TERRAIN

## True when terrain + cover + cliff are complete. Flora and debug phases
## are NOT required — they are cosmetic/debug and must not block boot gates.
func is_gameplay_redraw_complete() -> bool:
	return _redraw_phase >= REDRAW_PHASE_FLORA

func is_flora_phase_done() -> bool:
	return _redraw_phase > REDRAW_PHASE_FLORA

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
		_ground_face_layer.erase_cell(local_tile)
		_rock_layer.erase_cell(local_tile)
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
	var rock_atlas: Vector2i = Vector2i(-1, -1)
	var rock_alt_id: int = 0
	match terrain_type:
		TileGenData.TerrainType.ROCK:
			# Base terrain under mountain: biome ground tile (always visible through rock alpha)
			atlas = _resolve_surface_ground_atlas(local_tile)
			# Rock wall form goes to separate rock_layer (alpha-blended over terrain)
			var rock_visual: Vector2i = _resolve_visible_rock_visual_class(local_tile)
			var rock_variant: Array = _apply_variant_full(rock_visual, local_tile, true)
			rock_atlas = rock_variant[0]
			rock_alt_id = rock_variant[1]
		TileGenData.TerrainType.WATER:
			atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, _biome_palette_index_at(local_tile))
		TileGenData.TerrainType.SAND:
			atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, _biome_palette_index_at(local_tile))
		TileGenData.TerrainType.GRASS:
			atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, _biome_palette_index_at(local_tile))
		TileGenData.TerrainType.MINED_FLOOR:
			atlas = ChunkTilesetFactory.TILE_MINED_FLOOR
		TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			atlas = ChunkTilesetFactory.TILE_MOUNTAIN_ENTRANCE
		_:
			atlas = _resolve_surface_ground_atlas(local_tile)
	_terrain_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, atlas, alt_id)
	# Rock layer: set wall form if ROCK, erase otherwise
	if rock_atlas.x >= 0:
		_rock_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, rock_atlas, rock_alt_id)
	else:
		_rock_layer.erase_cell(local_tile)
	# Ground/Sand face layer: elevation edges adjacent to WATER
	var gf_visual: Vector2i = Vector2i(-1, -1)
	if terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.GRASS \
		or terrain_type == TileGenData.TerrainType.SAND:
		gf_visual = _ground_face_visual_class(local_tile)
		if gf_visual.x >= 0 and not _gf_debug_printed:
			print("[GF] tile=%s type=%d gf_visual=%s atlas=%s" % [local_tile, terrain_type, gf_visual, ChunkTilesetFactory.get_ground_face_coords(gf_visual)])
			_gf_debug_printed = true
	if gf_visual.x >= 0:
		var gf_atlas: Vector2i
		if terrain_type == TileGenData.TerrainType.SAND:
			gf_atlas = ChunkTilesetFactory.get_sand_face_coords(gf_visual)
		else:
			gf_atlas = ChunkTilesetFactory.get_ground_face_coords(gf_visual)
		if gf_atlas.x >= 0:
			_ground_face_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, gf_atlas, 0)
		else:
			_ground_face_layer.erase_cell(local_tile)
	else:
		_ground_face_layer.erase_cell(local_tile)

## Ground face wall form — same 47-type logic as rock, but "open" = WATER only.
## Returns WALL_* constant or Vector2i(-1,-1) if no water neighbor.
func _ground_face_visual_class(local_tile: Vector2i) -> Vector2i:
	var s: bool = _get_neighbor_terrain(local_tile + Vector2i.DOWN) == TileGenData.TerrainType.WATER
	var n: bool = _get_neighbor_terrain(local_tile + Vector2i.UP) == TileGenData.TerrainType.WATER
	var w: bool = _get_neighbor_terrain(local_tile + Vector2i.LEFT) == TileGenData.TerrainType.WATER
	var e: bool = _get_neighbor_terrain(local_tile + Vector2i.RIGHT) == TileGenData.TerrainType.WATER
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 0:
		# Check diagonals for notch corners
		var d_ne: bool = _get_neighbor_terrain(local_tile + Vector2i(1, -1)) == TileGenData.TerrainType.WATER
		var d_nw: bool = _get_neighbor_terrain(local_tile + Vector2i(-1, -1)) == TileGenData.TerrainType.WATER
		var d_se: bool = _get_neighbor_terrain(local_tile + Vector2i(1, 1)) == TileGenData.TerrainType.WATER
		var d_sw: bool = _get_neighbor_terrain(local_tile + Vector2i(-1, 1)) == TileGenData.TerrainType.WATER
		var d_count: int = int(d_ne) + int(d_nw) + int(d_se) + int(d_sw)
		if d_count == 0:
			return Vector2i(-1, -1)  # No water neighbors at all
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
		return ChunkTilesetFactory.WALL_NOTCH_NW
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		if not s: return ChunkTilesetFactory.WALL_PENINSULA_N
		if not n: return ChunkTilesetFactory.WALL_PENINSULA_S
		if not e: return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		if s and w:
			var c_ne: bool = _get_neighbor_terrain(local_tile + Vector2i(1, -1)) == TileGenData.TerrainType.WATER
			return ChunkTilesetFactory.WALL_CORNER_SW_T if c_ne else ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			var c_nw: bool = _get_neighbor_terrain(local_tile + Vector2i(-1, -1)) == TileGenData.TerrainType.WATER
			return ChunkTilesetFactory.WALL_CORNER_SE_T if c_nw else ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			var c_se: bool = _get_neighbor_terrain(local_tile + Vector2i(1, 1)) == TileGenData.TerrainType.WATER
			return ChunkTilesetFactory.WALL_CORNER_NW_T if c_se else ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			var c_sw: bool = _get_neighbor_terrain(local_tile + Vector2i(-1, 1)) == TileGenData.TerrainType.WATER
			return ChunkTilesetFactory.WALL_CORNER_NE_T if c_sw else ChunkTilesetFactory.WALL_CORNER_NE
		if w and e: return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	# count == 1: single edge + diagonal checks
	if s:
		var s_ne: bool = _get_neighbor_terrain(local_tile + Vector2i(1, -1)) == TileGenData.TerrainType.WATER
		var s_nw: bool = _get_neighbor_terrain(local_tile + Vector2i(-1, -1)) == TileGenData.TerrainType.WATER
		if s_ne and s_nw: return ChunkTilesetFactory.WALL_T_SOUTH
		if s_ne: return ChunkTilesetFactory.WALL_SOUTH_NE
		if s_nw: return ChunkTilesetFactory.WALL_SOUTH_NW
		return ChunkTilesetFactory.WALL_SOUTH
	if n:
		var n_se: bool = _get_neighbor_terrain(local_tile + Vector2i(1, 1)) == TileGenData.TerrainType.WATER
		var n_sw: bool = _get_neighbor_terrain(local_tile + Vector2i(-1, 1)) == TileGenData.TerrainType.WATER
		if n_se and n_sw: return ChunkTilesetFactory.WALL_T_NORTH
		if n_se: return ChunkTilesetFactory.WALL_NORTH_SE
		if n_sw: return ChunkTilesetFactory.WALL_NORTH_SW
		return ChunkTilesetFactory.WALL_NORTH
	if w:
		var w_ne: bool = _get_neighbor_terrain(local_tile + Vector2i(1, -1)) == TileGenData.TerrainType.WATER
		var w_se: bool = _get_neighbor_terrain(local_tile + Vector2i(1, 1)) == TileGenData.TerrainType.WATER
		if w_ne and w_se: return ChunkTilesetFactory.WALL_T_WEST
		if w_ne: return ChunkTilesetFactory.WALL_WEST_NE
		if w_se: return ChunkTilesetFactory.WALL_WEST_SE
		return ChunkTilesetFactory.WALL_WEST
	var e_nw: bool = _get_neighbor_terrain(local_tile + Vector2i(-1, -1)) == TileGenData.TerrainType.WATER
	var e_sw: bool = _get_neighbor_terrain(local_tile + Vector2i(-1, 1)) == TileGenData.TerrainType.WATER
	if e_nw and e_sw: return ChunkTilesetFactory.WALL_T_EAST
	if e_nw: return ChunkTilesetFactory.WALL_EAST_NW
	if e_sw: return ChunkTilesetFactory.WALL_EAST_SW
	return ChunkTilesetFactory.WALL_EAST

func _surface_rock_visual_class(local_tile: Vector2i) -> Vector2i:
	var s: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i.DOWN))
	var n: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i.UP))
	var w: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i.LEFT))
	var e: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i.RIGHT))
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		## Peninsula: 3 edges open, 1 closed.
		## Sprite Forge edge bits: eX=1 when neighbor X is OPEN.
		## pen_n (42): e=0b1011 → eN=1,eS=0,eE=1,eW=1 → S closed → not s
		## pen_s (43): e=0b0111 → eN=0,eS=1,eE=1,eW=1 → N closed → not n
		## pen_e (44): e=0b1101 → eN=1,eS=1,eE=0,eW=1 → E closed → not e
		## pen_w (45): e=0b1110 → eN=1,eS=1,eE=1,eW=0 → W closed → not w
		if not s:
			return ChunkTilesetFactory.WALL_PENINSULA_N
		if not n:
			return ChunkTilesetFactory.WALL_PENINSULA_S
		if not e:
			return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		## L-corners: check diagonal notch on the closed-side corner.
		## Sprite Forge: corner notch visible when both adjacent cardinals = rock AND diagonal = open.
		if s and w:
			## S+W open → N+E rock. Possible notch at NE diagonal.
			var c_ne: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
			if c_ne:
				return ChunkTilesetFactory.WALL_CORNER_SW_T
			return ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			## S+E open → N+W rock. Possible notch at NW diagonal.
			var c_nw: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
			if c_nw:
				return ChunkTilesetFactory.WALL_CORNER_SE_T
			return ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			## N+W open → S+E rock. Possible notch at SE diagonal.
			var c_se: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
			if c_se:
				return ChunkTilesetFactory.WALL_CORNER_NW_T
			return ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			## N+E open → S+W rock. Possible notch at SW diagonal.
			var c_sw: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
			if c_sw:
				return ChunkTilesetFactory.WALL_CORNER_NE_T
			return ChunkTilesetFactory.WALL_CORNER_NE
		if w and e:
			return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	if count == 1:
		if s:
			var s_ne: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
			var s_nw: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
			if s_ne and s_nw:
				return ChunkTilesetFactory.WALL_T_SOUTH
			if s_ne:
				return ChunkTilesetFactory.WALL_SOUTH_NE
			if s_nw:
				return ChunkTilesetFactory.WALL_SOUTH_NW
			return ChunkTilesetFactory.WALL_SOUTH
		if n:
			var n_se: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
			var n_sw: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
			if n_se and n_sw:
				return ChunkTilesetFactory.WALL_T_NORTH
			if n_se:
				return ChunkTilesetFactory.WALL_NORTH_SE
			if n_sw:
				return ChunkTilesetFactory.WALL_NORTH_SW
			return ChunkTilesetFactory.WALL_NORTH
		if w:
			var w_ne: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
			var w_se: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
			if w_ne and w_se:
				return ChunkTilesetFactory.WALL_T_WEST
			if w_ne:
				return ChunkTilesetFactory.WALL_WEST_NE
			if w_se:
				return ChunkTilesetFactory.WALL_WEST_SE
			return ChunkTilesetFactory.WALL_WEST
		var e_nw: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
		var e_sw: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
		if e_nw and e_sw:
			return ChunkTilesetFactory.WALL_T_EAST
		if e_nw:
			return ChunkTilesetFactory.WALL_EAST_NW
		if e_sw:
			return ChunkTilesetFactory.WALL_EAST_SW
		return ChunkTilesetFactory.WALL_EAST
	var d_sw: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
	var d_se: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
	var d_ne: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
	var d_nw: bool = _is_open_for_surface_rock_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
	var d_count: int = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw)
	if d_count == 4:
		return ChunkTilesetFactory.WALL_CROSS
	if d_count == 3:
		if not d_sw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SW
		if not d_se:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SE
		if not d_nw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_NW
		return ChunkTilesetFactory.WALL_DIAG3_NO_NE
	if d_count == 2:
		if d_sw and d_se:
			return ChunkTilesetFactory.WALL_EDGE_EW
		if d_ne and d_nw:
			return ChunkTilesetFactory.WALL_DIAG_NE_NW
		if d_ne and d_se:
			return ChunkTilesetFactory.WALL_DIAG_NE_SE
		if d_nw and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NW_SW
		if d_ne and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NE_SW
		return ChunkTilesetFactory.WALL_DIAG_NW_SE
	if d_sw:
		return ChunkTilesetFactory.WALL_NOTCH_SW
	if d_se:
		return ChunkTilesetFactory.WALL_NOTCH_SE
	if d_ne:
		return ChunkTilesetFactory.WALL_NOTCH_NE
	if d_nw:
		return ChunkTilesetFactory.WALL_NOTCH_NW
	return ChunkTilesetFactory.WALL_INTERIOR

func _resolve_surface_ground_atlas(local_tile: Vector2i) -> Vector2i:
	if _is_underground:
		return _ground_atlas_for_height(_height_at(local_tile))
	var biome_palette_index: int = _biome_palette_index_at(local_tile)
	var variation_tile: Vector2i = ChunkTilesetFactory.get_surface_variation_tile(_variation_at(local_tile), biome_palette_index)
	if variation_tile.x >= 0:
		return variation_tile
	return ChunkTilesetFactory.get_surface_ground_tile(biome_palette_index, _height_at(local_tile))

func _ground_atlas_for_height(height_value: float) -> Vector2i:
	if height_value < 0.38:
		return ChunkTilesetFactory.TILE_GROUND_DARK
	if height_value > 0.62:
		return ChunkTilesetFactory.TILE_GROUND_LIGHT
	return ChunkTilesetFactory.TILE_GROUND

func _resolve_open_tile_type(local_tile: Vector2i) -> int:
	for dir: Vector2i in _CARDINAL_DIRS:
		if _is_open_exterior(_get_neighbor_terrain(local_tile + dir)):
			return TileGenData.TerrainType.MOUNTAIN_ENTRANCE
	return TileGenData.TerrainType.MINED_FLOOR

func _refresh_open_neighbors(local_tile: Vector2i) -> void:
	_refresh_open_tile(local_tile)
	for dir: Vector2i in _CARDINAL_DIRS:
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
	if _use_operation_global_terrain_cache and _operation_global_terrain_cache.has(global_tile):
		return int(_operation_global_terrain_cache[global_tile])
	var terrain_type: int = TileGenData.TerrainType.GROUND
	if _chunk_manager:
		terrain_type = _chunk_manager.get_terrain_type_at_global(global_tile)
	elif WorldGenerator and WorldGenerator._is_initialized:
		terrain_type = WorldGenerator.get_tile_data(global_tile.x, global_tile.y).terrain
	if _use_operation_global_terrain_cache:
		_operation_global_terrain_cache[global_tile] = terrain_type
	return terrain_type

func _is_open_for_visual(terrain_type: int) -> bool:
	return terrain_type != TileGenData.TerrainType.ROCK

func _is_open_for_surface_rock_visual(terrain_type: int) -> bool:
	return _is_open_exterior(terrain_type) \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _is_open_exterior(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.WATER \
		or terrain_type == TileGenData.TerrainType.SAND \
		or terrain_type == TileGenData.TerrainType.GRASS

func _is_rock_at(local_tile: Vector2i) -> bool:
	return _is_inside(local_tile) and get_terrain_type_at(local_tile) == TileGenData.TerrainType.ROCK

func _should_blacken_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
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

func _redraw_cliff_tile(local_tile: Vector2i) -> void:
	if not _cliff_layer or _is_underground:
		return
	if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
		return
	var south_open: bool = _is_open_exterior(_get_neighbor_terrain(local_tile + _CARDINAL_DIRS[3]))
	var west_open: bool = _is_open_exterior(_get_neighbor_terrain(local_tile + _CARDINAL_DIRS[0]))
	var east_open: bool = _is_open_exterior(_get_neighbor_terrain(local_tile + _CARDINAL_DIRS[1]))
	var north_open: bool = _is_open_exterior(_get_neighbor_terrain(local_tile + _CARDINAL_DIRS[2]))
	var overlay: Vector2i = Vector2i(-1, -1)
	if south_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_SOUTH
	elif west_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_WEST
	elif east_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_EAST
	elif north_open:
		overlay = ChunkTilesetFactory.TILE_TOP_EDGE
	if overlay.x >= 0:
		_cliff_layer.set_cell(local_tile, ChunkTilesetFactory.OVERLAY_SOURCE_ID, overlay)

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
	# Cover should restore the same wall class + deterministic variation policy
	# as the visible mountain shell on the surface.
	var base: Vector2i = _cover_rock_visual_class(local_tile)
	var cover_variant: Array = _apply_variant_full(base, local_tile, true)
	_cover_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, cover_variant[0], cover_variant[1])

## XOR-shift hash — no visible linear patterns.
static func _tile_hash_xy(tile_x: int, tile_y: int) -> int:
	var h: int = tile_x * 374761393 + tile_y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)

static func _tile_hash(pos: Vector2i) -> int:
	return _tile_hash_xy(pos.x, pos.y)

## Returns [atlas_coords, alternative_tile_id].
func _apply_variant_full(base: Vector2i, local_tile: Vector2i, allow_flip: bool = true) -> Array:
	var gt: Vector2i = _to_global_tile(local_tile)
	var atlas: Vector2i = _resolve_variant_atlas(base, gt.x, gt.y)
	var alt_id: int = _resolve_variant_alt_id(base, gt.x, gt.y, allow_flip)
	return [atlas, alt_id]

func _apply_variant(base: Vector2i, local_tile: Vector2i) -> Vector2i:
	return _apply_variant_full(base, local_tile)[0]

func _resolve_variant_atlas(base: Vector2i, _global_x: int, _global_y: int) -> Vector2i:
	## Atlas variant selection disabled — always use variant 0.
	## Per-tile variant hashing creates visual "mess" instead of cohesive mountains.
	## If per-mountain or per-chunk variants are needed, implement that separately.
	return ChunkTilesetFactory.get_wall_variant_coords(base, 0)

func _resolve_variant_alt_id(_base: Vector2i, _global_x: int, _global_y: int, _allow_flip: bool) -> int:
	## Flip variants disabled — creates visible mirroring artifacts on mountain edges.
	return 0

func _resolve_visible_rock_visual_class(local_tile: Vector2i) -> Vector2i:
	if _is_underground:
		return _rock_visual_class(local_tile)
	return _surface_rock_visual_class(local_tile)

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

func _cover_rock_visual_class(local_tile: Vector2i) -> Vector2i:
	return _surface_rock_visual_class(local_tile)

func _is_cave_edge_rock(local_tile: Vector2i) -> bool:
	if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
		return false
	var has_open_neighbor: bool = false
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		var neighbor_type: int = _get_neighbor_terrain(local_tile + dir)
		if _is_open_exterior(neighbor_type):
			return false
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			has_open_neighbor = true
	return has_open_neighbor

func _is_surface_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
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

func _biome_palette_index_at(local_tile: Vector2i) -> int:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _biome_bytes.size():
		return 0
	return int(_biome_bytes[idx])

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
		REDRAW_PHASE_COVER, REDRAW_PHASE_FLORA, REDRAW_PHASE_DEBUG_INTERIOR, REDRAW_PHASE_DEBUG_COLLISION:
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
		REDRAW_PHASE_FLORA:
			return &"flora"
		REDRAW_PHASE_DEBUG_INTERIOR:
			return &"debug_interior"
		REDRAW_PHASE_DEBUG_COLLISION:
			return &"debug_collision"
		_:
			return &"done"

func _process_redraw_phase_tiles(tile_budget: int) -> int:
	var total_tiles: int = _chunk_size * _chunk_size
	var end_index: int = mini(_redraw_tile_index + tile_budget, total_tiles)
	var start_index: int = _redraw_tile_index
	var processed_end_index: int = start_index
	var started_usec: int = Time.get_ticks_usec()
	for tile_index: int in range(start_index, end_index):
		var local_tile: Vector2i = _tile_from_index(tile_index)
		match _redraw_phase:
			REDRAW_PHASE_TERRAIN:
				_redraw_terrain_tile(local_tile)
			REDRAW_PHASE_COVER:
				_redraw_cover_tile(local_tile)
			REDRAW_PHASE_CLIFF:
				_redraw_cliff_tile(local_tile)
			REDRAW_PHASE_FLORA:
				_redraw_flora_tile(tile_index)
			REDRAW_PHASE_DEBUG_INTERIOR:
				_process_debug_marker_tile(local_tile, false)
			REDRAW_PHASE_DEBUG_COLLISION:
				_process_debug_marker_tile(local_tile, true)
			_:
				break
		processed_end_index = tile_index + 1
		## Hard time guard: check every 4 tiles (terrain/cover/cliff) or every tile (flora/debug).
		## No end_index bypass — budget must be respected even if tile_budget allows more.
		var tiles_done: int = processed_end_index - start_index
		var check_interval: int = 1
		if tiles_done % check_interval == 0:
			if Time.get_ticks_usec() - started_usec >= REDRAW_TIME_BUDGET_USEC:
				break
	var processed: int = processed_end_index - start_index
	_redraw_tile_index = processed_end_index
	return processed

func set_flora_result(result: ChunkFloraResultScript) -> void:
	_flora_result = result

func _redraw_flora_tile(tile_index: int) -> void:
	if _flora_result == null or _flora_container == null:
		return
	if _redraw_tile_index == 0 and tile_index == 0:
		for child: Node in _flora_container.get_children():
			child.queue_free()
	if _flora_result.is_empty():
		return
	var local_x: int = tile_index % _chunk_size
	var local_y: int = tile_index / _chunk_size
	var local_pos: Vector2i = Vector2i(local_x, local_y)
	var placements_for_tile: Array = _flora_result.get_placements_for_local_pos(local_pos)
	if placements_for_tile.is_empty():
		return
	for placement: Dictionary in placements_for_tile:
		var color: Color = placement.get("color", Color.WHITE)
		var size: Vector2i = placement.get("size", Vector2i(8, 8))
		var z_off: int = int(placement.get("z_offset", 0))
		var rect: ColorRect = ColorRect.new()
		rect.color = color
		rect.size = Vector2(size.x, size.y)
		rect.position = Vector2(
			local_x * _tile_size + (_tile_size - size.x) * 0.5,
			local_y * _tile_size + (_tile_size - size.y)
		)
		rect.z_index = z_off
		_flora_container.add_child(rect)

func _advance_redraw_phase() -> void:
	match _redraw_phase:
		REDRAW_PHASE_TERRAIN:
			_redraw_phase = REDRAW_PHASE_COVER
		REDRAW_PHASE_COVER:
			_redraw_phase = REDRAW_PHASE_CLIFF
		REDRAW_PHASE_CLIFF:
			_redraw_phase = REDRAW_PHASE_FLORA
		REDRAW_PHASE_FLORA:
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
