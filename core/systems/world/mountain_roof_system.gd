class_name MountainRoofSystem
extends Node

## Координирует player-local mountain shell reveal state.
## R1: canonical exterior shell is `cover_layer`; legacy roof cache is no longer reveal authority.

const INVALID_MOUNTAIN_KEY: Vector2i = Vector2i(999999, 999999)
const _ZONE_REVEAL_TILE_OFFSETS := [
	Vector2i.ZERO,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1),
]

var _chunk_manager: ChunkManager = null
var _player: Player = null
var _last_tile: Vector2i = INVALID_MOUNTAIN_KEY
var _is_player_on_mined_floor: bool = false
var _needs_zone_refresh: bool = false
var _active_local_zone_seed: Vector2i = INVALID_MOUNTAIN_KEY
var _active_local_zone_kind: StringName = &""
var _active_local_zone_tiles: Dictionary = {}
var _active_local_zone_chunk_coords: Array[Vector2i] = []
var _active_local_cover_tiles_by_chunk: Dictionary = {}
var _active_local_reveal_chunk_coords: Array[Vector2i] = []
var _active_local_zone_truncated: bool = false

func _ready() -> void:
	EventBus.mountain_tile_mined.connect(_on_mountain_tile_mined)
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	call_deferred("_resolve_dependencies")

func _process(_delta: float) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	if _needs_zone_refresh:
		_needs_zone_refresh = false
		_request_refresh(true)
	_check_player_mountain_state()

func _resolve_dependencies() -> void:
	var chunks: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunks.is_empty():
		_chunk_manager = chunks[0] as ChunkManager
	_player = PlayerAuthority.get_local_player()
	_request_refresh()

func _check_player_mountain_state() -> void:
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	if player_tile == _last_tile:
		return
	_last_tile = player_tile
	var is_on_mined_floor: bool = _is_player_on_opened_mountain_tile(player_tile)
	if is_on_mined_floor == _is_player_on_mined_floor and (not is_on_mined_floor or _has_active_local_zone()):
		if is_on_mined_floor and not _active_local_zone_tiles.has(player_tile):
			_request_refresh(true)
		return
	_is_player_on_mined_floor = is_on_mined_floor
	_request_refresh()

func _request_refresh(force_refresh: bool = false) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	# Surface-only system. Skip underground (ADR-0006).
	if _chunk_manager.get_active_z_level() != 0:
		return
	var previous_cover_tiles_by_chunk: Dictionary = _duplicate_cover_tiles_by_chunk(_active_local_cover_tiles_by_chunk)
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var start_tile: Vector2i = _find_reveal_start(player_tile)
	if start_tile == INVALID_MOUNTAIN_KEY:
		_clear_active_local_zone()
	else:
		_refresh_active_local_zone(start_tile)
	var affected_chunks: Array[Vector2i] = _collect_affected_chunk_coords(previous_cover_tiles_by_chunk)
	if affected_chunks.is_empty():
		WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)
		return
	_apply_reveal_state(affected_chunks, force_refresh)
	WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)

func _apply_reveal_state(affected_chunks: Array[Vector2i], _animate: bool) -> void:
	for coord: Vector2i in affected_chunks:
		var chunk: Chunk = _chunk_manager.get_chunk(coord)
		if not chunk:
			continue
		var cover_step_usec: int = WorldPerfProbe.begin()
		chunk.set_revealed_local_cover_tiles(_active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary)
		WorldPerfProbe.end("MountainRoofSystem._process_cover_step %s" % [coord], cover_step_usec)

func _find_reveal_start(player_tile: Vector2i) -> Vector2i:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return INVALID_MOUNTAIN_KEY
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	if terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return player_tile
	return INVALID_MOUNTAIN_KEY

func _is_player_on_opened_mountain_tile(player_tile: Vector2i) -> bool:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return false
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	return terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _on_mountain_tile_mined(_tile_pos: Vector2i, _old_type: int, _new_type: int) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	if _is_player_on_opened_mountain_tile(player_tile):
		_needs_zone_refresh = true

func _on_chunk_loaded(coord: Vector2i) -> void:
	if coord == Vector2i(999999, 999999):
		return
	if _has_active_local_zone():
		if _active_local_reveal_chunk_coords.has(coord):
			var chunk: Chunk = _chunk_manager.get_chunk(coord)
			if chunk:
				chunk.set_revealed_local_cover_tiles(_active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary)
		_needs_zone_refresh = true

func _on_chunk_unloaded(coord: Vector2i) -> void:
	if coord == Vector2i(999999, 999999):
		return
	if _has_active_local_zone():
		_needs_zone_refresh = true

func _refresh_active_local_zone(seed_tile: Vector2i) -> void:
	if not _chunk_manager:
		_clear_active_local_zone()
		return
	var started_usec: int = WorldPerfProbe.begin()
	var zone: Dictionary = _chunk_manager.query_local_underground_zone(seed_tile)
	if zone.is_empty():
		_clear_active_local_zone()
		WorldPerfProbe.end("MountainRoofSystem._refresh_local_zone", started_usec)
		return
	_active_local_zone_seed = zone.get("seed_tile", INVALID_MOUNTAIN_KEY)
	_active_local_zone_kind = zone.get("zone_kind", &"") as StringName
	_active_local_zone_tiles = zone.get("tiles", {}) as Dictionary
	_active_local_zone_chunk_coords = []
	for coord: Vector2i in zone.get("chunk_coords", []):
		_active_local_zone_chunk_coords.append(coord)
	var cover_build_usec: int = WorldPerfProbe.begin()
	_active_local_cover_tiles_by_chunk = _build_local_cover_tiles_by_chunk(_active_local_zone_tiles)
	_active_local_reveal_chunk_coords = _extract_cover_chunk_coords(_active_local_cover_tiles_by_chunk)
	WorldPerfProbe.end("MountainRoofSystem._build_cover_tiles_by_chunk", cover_build_usec)
	_active_local_zone_truncated = bool(zone.get("truncated", false))
	WorldPerfProbe.end("MountainRoofSystem._refresh_local_zone", started_usec)

func _clear_active_local_zone() -> void:
	_active_local_zone_seed = INVALID_MOUNTAIN_KEY
	_active_local_zone_kind = &""
	_active_local_zone_tiles = {}
	_active_local_zone_chunk_coords = []
	_active_local_cover_tiles_by_chunk = {}
	_active_local_reveal_chunk_coords = []
	_active_local_zone_truncated = false

func _collect_affected_chunk_coords(previous_cover_tiles_by_chunk: Dictionary) -> Array[Vector2i]:
	var affected_chunks: Array[Vector2i] = []
	var seen_coords: Dictionary = {}
	for coord: Vector2i in previous_cover_tiles_by_chunk:
		seen_coords[coord] = true
	for coord: Vector2i in _active_local_cover_tiles_by_chunk:
		seen_coords[coord] = true
	for coord: Vector2i in seen_coords:
		var previous_cover_tiles: Dictionary = previous_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		var next_cover_tiles: Dictionary = _active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		if previous_cover_tiles != next_cover_tiles:
			affected_chunks.append(coord)
	return affected_chunks

func _has_active_local_zone() -> bool:
	return _active_local_zone_seed != INVALID_MOUNTAIN_KEY and not _active_local_zone_tiles.is_empty()

func _build_local_cover_tiles_by_chunk(zone_tiles: Dictionary) -> Dictionary:
	var cover_tiles_by_chunk: Dictionary = {}
	if zone_tiles.is_empty() or not _chunk_manager:
		return cover_tiles_by_chunk
	var candidate_cache: Dictionary = {}
	for global_tile: Vector2i in zone_tiles:
		_append_global_cover_tile(cover_tiles_by_chunk, global_tile)
		for offset: Vector2i in _ZONE_REVEAL_TILE_OFFSETS:
			if offset == Vector2i.ZERO:
				continue
			var candidate_tile: Vector2i = WorldGenerator.offset_tile(global_tile, offset)
			if candidate_cache.has(candidate_tile):
				if bool(candidate_cache[candidate_tile]):
					_append_global_cover_tile(cover_tiles_by_chunk, candidate_tile)
				continue
			var candidate_chunk: Chunk = _chunk_manager.get_chunk_at_tile(candidate_tile)
			if not candidate_chunk:
				candidate_cache[candidate_tile] = false
				continue
			var candidate_local: Vector2i = candidate_chunk.global_to_local(candidate_tile)
			var should_reveal: bool = candidate_chunk.is_revealable_cover_edge(candidate_local)
			candidate_cache[candidate_tile] = should_reveal
			if should_reveal:
				_append_local_cover_tile(
					cover_tiles_by_chunk,
					WorldGenerator.tile_to_chunk(candidate_tile),
					candidate_local
				)
	return cover_tiles_by_chunk

func _append_global_cover_tile(cover_tiles_by_chunk: Dictionary, global_tile: Vector2i) -> void:
	global_tile = WorldGenerator.canonicalize_tile(global_tile)
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	var chunk: Chunk = _chunk_manager.get_chunk(chunk_coord)
	if not chunk:
		return
	_append_local_cover_tile(cover_tiles_by_chunk, chunk_coord, chunk.global_to_local(global_tile))

func _append_local_cover_tile(cover_tiles_by_chunk: Dictionary, chunk_coord: Vector2i, local_tile: Vector2i) -> void:
	if not cover_tiles_by_chunk.has(chunk_coord):
		cover_tiles_by_chunk[chunk_coord] = {}
	(cover_tiles_by_chunk[chunk_coord] as Dictionary)[local_tile] = true

func _extract_cover_chunk_coords(cover_tiles_by_chunk: Dictionary) -> Array[Vector2i]:
	var chunk_coords: Array[Vector2i] = []
	for coord: Vector2i in cover_tiles_by_chunk:
		chunk_coords.append(coord)
	return chunk_coords

func _duplicate_cover_tiles_by_chunk(cover_tiles_by_chunk: Dictionary) -> Dictionary:
	var duplicate_map: Dictionary = {}
	for coord: Vector2i in cover_tiles_by_chunk:
		duplicate_map[coord] = (cover_tiles_by_chunk[coord] as Dictionary).duplicate()
	return duplicate_map

func has_active_local_zone() -> bool:
	return _has_active_local_zone()

func get_active_local_zone_tile_count() -> int:
	return _active_local_zone_tiles.size()

func is_active_local_zone_truncated() -> bool:
	return _active_local_zone_truncated
