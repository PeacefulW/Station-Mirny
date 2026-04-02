class_name MountainRoofSystem
extends Node

## Координирует player-local mountain shell reveal state.
## R1: canonical exterior shell is `cover_layer`; legacy roof cache is no longer reveal authority.

const INVALID_MOUNTAIN_KEY: Vector2i = Vector2i(999999, 999999)
const _CARDINAL_ZONE_OFFSETS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]
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
const _COVER_APPLY_TIME_BUDGET_USEC: int = 1200
const _COVER_APPLY_MAX_CHUNKS_PER_FRAME: int = 1

var _chunk_manager: ChunkManager = null
var _player: Player = null
var _last_tile: Vector2i = INVALID_MOUNTAIN_KEY
var _is_player_on_mined_floor: bool = false
var _needs_zone_refresh: bool = false
var _active_local_zone_seed: Vector2i = INVALID_MOUNTAIN_KEY
var _active_local_zone_kind: StringName = &""
var _active_local_zone_tiles: Dictionary = {}
var _active_local_cover_tiles_by_chunk: Dictionary = {}
var _active_local_reveal_chunk_coords: Dictionary = {}
var _active_local_zone_truncated: bool = false
var _cached_zone_seed: Vector2i = INVALID_MOUNTAIN_KEY
var _cached_zone_kind: StringName = &""
var _cached_zone_tiles: Dictionary = {}
var _cached_cover_tiles_by_chunk: Dictionary = {}
var _cached_zone_truncated: bool = false
var _cached_zone_valid: bool = false
var _pending_incremental_mined_tile: Vector2i = INVALID_MOUNTAIN_KEY
var _pending_incremental_affected_chunks: Array[Vector2i] = []
var _pending_cover_apply_coords: Array[Vector2i] = []
var _pending_cover_apply_lookup: Dictionary = {}

func _ready() -> void:
	EventBus.mountain_tile_mined.connect(_on_mountain_tile_mined)
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	call_deferred("_resolve_dependencies")

func _exit_tree() -> void:
	if EventBus.mountain_tile_mined.is_connected(_on_mountain_tile_mined):
		EventBus.mountain_tile_mined.disconnect(_on_mountain_tile_mined)
	if EventBus.chunk_loaded.is_connected(_on_chunk_loaded):
		EventBus.chunk_loaded.disconnect(_on_chunk_loaded)
	if EventBus.chunk_unloaded.is_connected(_on_chunk_unloaded):
		EventBus.chunk_unloaded.disconnect(_on_chunk_unloaded)
	_pending_cover_apply_coords.clear()
	_pending_cover_apply_lookup.clear()
	_chunk_manager = null
	_player = null

func _process(_delta: float) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	if _needs_zone_refresh:
		_needs_zone_refresh = false
		_request_refresh(true)
	_check_player_mountain_state()
	_drain_cover_apply_queue()

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
	var previous_cover_tiles_by_chunk: Dictionary = _active_local_cover_tiles_by_chunk
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var start_tile: Vector2i = _find_reveal_start(player_tile)
	if start_tile == INVALID_MOUNTAIN_KEY:
		_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
		_pending_incremental_affected_chunks = []
		_clear_active_local_zone()
	else:
		if not _try_apply_incremental_zone_refresh(start_tile) and not _try_restore_cached_zone(start_tile):
			_refresh_active_local_zone(start_tile)
	WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)
	var affected_chunks: Array[Vector2i] = _pending_incremental_affected_chunks
	if affected_chunks.is_empty():
		var diff_usec: int = WorldPerfProbe.begin()
		affected_chunks = _collect_affected_chunk_coords(previous_cover_tiles_by_chunk)
		WorldPerfProbe.end("MountainRoofSystem._collect_affected_chunk_coords", diff_usec)
	_pending_incremental_affected_chunks = []
	if affected_chunks.is_empty():
		return
	_queue_reveal_state_apply(affected_chunks)

func _queue_reveal_state_apply(affected_chunks: Array[Vector2i]) -> void:
	for coord: Vector2i in affected_chunks:
		_enqueue_cover_apply_coord(coord)

func _enqueue_cover_apply_coord(coord: Vector2i) -> void:
	if coord == INVALID_MOUNTAIN_KEY or _pending_cover_apply_lookup.has(coord):
		return
	_pending_cover_apply_lookup[coord] = true
	_pending_cover_apply_coords.append(coord)

func _remove_pending_cover_apply_coord(coord: Vector2i) -> void:
	if not _pending_cover_apply_lookup.has(coord):
		return
	_pending_cover_apply_lookup.erase(coord)
	var idx: int = _pending_cover_apply_coords.find(coord)
	if idx != -1:
		_pending_cover_apply_coords.remove_at(idx)

func _drain_cover_apply_queue() -> void:
	if _pending_cover_apply_coords.is_empty() or _chunk_manager.get_active_z_level() != 0:
		return
	var started_usec: int = Time.get_ticks_usec()
	var processed_chunks: int = 0
	while processed_chunks < _COVER_APPLY_MAX_CHUNKS_PER_FRAME \
		and not _pending_cover_apply_coords.is_empty():
		if Time.get_ticks_usec() - started_usec >= _COVER_APPLY_TIME_BUDGET_USEC:
			return
		var coord: Vector2i = _pop_next_cover_apply_coord()
		if coord == INVALID_MOUNTAIN_KEY:
			return
		_apply_cover_state_to_chunk(coord)
		processed_chunks += 1

func _pop_next_cover_apply_coord() -> Vector2i:
	if _pending_cover_apply_coords.is_empty():
		return INVALID_MOUNTAIN_KEY
	var best_idx: int = 0
	var best_score: int = _cover_apply_priority_score(_pending_cover_apply_coords[0])
	for idx: int in range(1, _pending_cover_apply_coords.size()):
		var score: int = _cover_apply_priority_score(_pending_cover_apply_coords[idx])
		if score < best_score:
			best_idx = idx
			best_score = score
	var coord: Vector2i = _pending_cover_apply_coords[best_idx]
	_pending_cover_apply_coords.remove_at(best_idx)
	_pending_cover_apply_lookup.erase(coord)
	return coord

func _cover_apply_priority_score(coord: Vector2i) -> int:
	if not _player or not WorldGenerator:
		return 0
	var player_chunk: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	return absi(coord.x - player_chunk.x) + absi(coord.y - player_chunk.y)

func _apply_cover_state_to_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if not chunk:
		return
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

func _on_mountain_tile_mined(tile_pos: Vector2i, _old_type: int, new_type: int) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	_invalidate_cached_zone()
	if new_type == TileGenData.TerrainType.MINED_FLOOR \
		or new_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		_pending_incremental_mined_tile = WorldGenerator.canonicalize_tile(tile_pos)
	else:
		_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	if _is_player_on_opened_mountain_tile(player_tile):
		_needs_zone_refresh = true

func _on_chunk_loaded(coord: Vector2i) -> void:
	if coord == Vector2i(999999, 999999):
		return
	if _cached_zone_valid and _cached_zone_truncated:
		_invalidate_cached_zone()
	if _has_active_local_zone():
		if _active_local_reveal_chunk_coords.has(coord):
			_enqueue_cover_apply_coord(coord)
		if _active_local_zone_truncated:
			_needs_zone_refresh = true

func _on_chunk_unloaded(coord: Vector2i) -> void:
	if coord == Vector2i(999999, 999999):
		return
	_remove_pending_cover_apply_coord(coord)
	if _cached_zone_valid and _cached_cover_tiles_by_chunk.has(coord):
		_invalidate_cached_zone()
	if _has_active_local_zone():
		if _active_local_reveal_chunk_coords.has(coord) or _active_local_zone_truncated:
			_needs_zone_refresh = true

func _refresh_active_local_zone(seed_tile: Vector2i) -> void:
	if not _chunk_manager:
		_clear_active_local_zone()
		return
	var started_usec: int = WorldPerfProbe.begin()
	var zone: Dictionary = _chunk_manager.query_local_underground_zone(seed_tile)
	if zone.is_empty():
		_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
		_clear_active_local_zone()
		WorldPerfProbe.end("MountainRoofSystem._refresh_local_zone", started_usec)
		return
	_active_local_zone_seed = zone.get("seed_tile", INVALID_MOUNTAIN_KEY)
	_active_local_zone_kind = zone.get("zone_kind", &"") as StringName
	_active_local_zone_tiles = zone.get("tiles", {}) as Dictionary
	var cover_build_usec: int = WorldPerfProbe.begin()
	_active_local_cover_tiles_by_chunk = _build_local_cover_tiles_by_chunk(_active_local_zone_tiles)
	_active_local_reveal_chunk_coords = _active_local_cover_tiles_by_chunk
	WorldPerfProbe.end("MountainRoofSystem._build_cover_tiles_by_chunk", cover_build_usec)
	_active_local_zone_truncated = bool(zone.get("truncated", false))
	_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	_cache_active_zone_state()
	WorldPerfProbe.end("MountainRoofSystem._refresh_local_zone", started_usec)

func _clear_active_local_zone() -> void:
	_active_local_zone_seed = INVALID_MOUNTAIN_KEY
	_active_local_zone_kind = &""
	_active_local_zone_tiles = {}
	_active_local_cover_tiles_by_chunk = {}
	_active_local_reveal_chunk_coords = {}
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

func _collect_changed_chunk_coords(
	previous_cover_tiles_by_chunk: Dictionary,
	chunk_coords: Dictionary
) -> Array[Vector2i]:
	var affected_chunks: Array[Vector2i] = []
	for coord: Vector2i in chunk_coords:
		var previous_cover_tiles: Dictionary = previous_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		var next_cover_tiles: Dictionary = _active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		if previous_cover_tiles != next_cover_tiles:
			affected_chunks.append(coord)
	return affected_chunks

func _has_active_local_zone() -> bool:
	return _active_local_zone_seed != INVALID_MOUNTAIN_KEY and not _active_local_zone_tiles.is_empty()

func _try_apply_incremental_zone_refresh(start_tile: Vector2i) -> bool:
	if _pending_incremental_mined_tile == INVALID_MOUNTAIN_KEY:
		return false
	if not _has_active_local_zone() or _active_local_zone_truncated:
		return false
	if not _active_local_zone_tiles.has(start_tile):
		return false
	var mined_tile: Vector2i = _pending_incremental_mined_tile
	if not _can_incrementally_extend_active_zone(mined_tile):
		return false
	var previous_cover_tiles_by_chunk: Dictionary = _active_local_cover_tiles_by_chunk
	_active_local_zone_tiles[mined_tile] = true
	var incremental_result: Dictionary = _build_incremental_cover_tiles_by_chunk(
		previous_cover_tiles_by_chunk,
		mined_tile
	)
	_active_local_cover_tiles_by_chunk = incremental_result.get("cover_tiles_by_chunk", {}) as Dictionary
	_active_local_reveal_chunk_coords = _active_local_cover_tiles_by_chunk
	_pending_incremental_affected_chunks = _collect_changed_chunk_coords(
		previous_cover_tiles_by_chunk,
		incremental_result.get("touched_chunks", {}) as Dictionary
	)
	_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	_cache_active_zone_state()
	return true

func _try_restore_cached_zone(start_tile: Vector2i) -> bool:
	if not _cached_zone_valid or not _cached_zone_tiles.has(start_tile):
		return false
	_active_local_zone_seed = _cached_zone_seed
	_active_local_zone_kind = _cached_zone_kind
	_active_local_zone_tiles = _cached_zone_tiles
	_active_local_cover_tiles_by_chunk = _cached_cover_tiles_by_chunk
	_active_local_reveal_chunk_coords = _active_local_cover_tiles_by_chunk
	_active_local_zone_truncated = _cached_zone_truncated
	_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	return true

func _can_incrementally_extend_active_zone(tile_pos: Vector2i) -> bool:
	if _active_local_zone_tiles.has(tile_pos):
		return false
	if not _is_open_mountain_tile(tile_pos):
		return false
	var has_active_neighbor: bool = false
	for offset: Vector2i in _CARDINAL_ZONE_OFFSETS:
		var neighbor_tile: Vector2i = WorldGenerator.offset_tile(tile_pos, offset)
		if _active_local_zone_tiles.has(neighbor_tile):
			has_active_neighbor = true
			continue
		if _is_open_mountain_tile(neighbor_tile):
			return false
	return has_active_neighbor

func _is_open_mountain_tile(global_tile: Vector2i) -> bool:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(global_tile)
	if not chunk:
		return false
	var local_tile: Vector2i = chunk.global_to_local(global_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	return terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _cache_active_zone_state() -> void:
	_cached_zone_seed = _active_local_zone_seed
	_cached_zone_kind = _active_local_zone_kind
	_cached_zone_tiles = _active_local_zone_tiles
	_cached_cover_tiles_by_chunk = _active_local_cover_tiles_by_chunk
	_cached_zone_truncated = _active_local_zone_truncated
	_cached_zone_valid = _has_active_local_zone()

func _invalidate_cached_zone() -> void:
	_cached_zone_seed = INVALID_MOUNTAIN_KEY
	_cached_zone_kind = &""
	_cached_zone_tiles = {}
	_cached_cover_tiles_by_chunk = {}
	_cached_zone_truncated = false
	_cached_zone_valid = false

func _build_incremental_cover_tiles_by_chunk(
	previous_cover_tiles_by_chunk: Dictionary,
	mined_tile: Vector2i
) -> Dictionary:
	var next_cover_tiles_by_chunk: Dictionary = previous_cover_tiles_by_chunk.duplicate()
	var touched_chunks: Dictionary = {}
	_refresh_incremental_cover_tile(next_cover_tiles_by_chunk, touched_chunks, mined_tile)
	for offset: Vector2i in _ZONE_REVEAL_TILE_OFFSETS:
		if offset == Vector2i.ZERO:
			continue
		_refresh_incremental_cover_tile(
			next_cover_tiles_by_chunk,
			touched_chunks,
			WorldGenerator.offset_tile(mined_tile, offset)
		)
	for coord: Vector2i in touched_chunks:
		if not next_cover_tiles_by_chunk.has(coord):
			continue
		if (next_cover_tiles_by_chunk[coord] as Dictionary).is_empty():
			next_cover_tiles_by_chunk.erase(coord)
	return {
		"cover_tiles_by_chunk": next_cover_tiles_by_chunk,
		"touched_chunks": touched_chunks,
	}

func _refresh_incremental_cover_tile(
	cover_tiles_by_chunk: Dictionary,
	touched_chunks: Dictionary,
	global_tile: Vector2i
) -> void:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(global_tile)
	if not chunk:
		return
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	var local_tile: Vector2i = chunk.global_to_local(global_tile)
	var should_reveal: bool = _active_local_zone_tiles.has(global_tile)
	if not should_reveal and _has_active_zone_neighbor(global_tile):
		should_reveal = chunk.is_revealable_cover_edge(local_tile)
	if not should_reveal and not cover_tiles_by_chunk.has(chunk_coord):
		return
	var chunk_cover_tiles: Dictionary = _get_mutable_chunk_cover_tiles(
		cover_tiles_by_chunk,
		touched_chunks,
		chunk_coord
	)
	if should_reveal:
		chunk_cover_tiles[local_tile] = true
	else:
		chunk_cover_tiles.erase(local_tile)

func _get_mutable_chunk_cover_tiles(
	cover_tiles_by_chunk: Dictionary,
	touched_chunks: Dictionary,
	chunk_coord: Vector2i
) -> Dictionary:
	if touched_chunks.has(chunk_coord):
		return cover_tiles_by_chunk.get(chunk_coord, {}) as Dictionary
	var chunk_cover_tiles: Dictionary = {}
	if cover_tiles_by_chunk.has(chunk_coord):
		chunk_cover_tiles = (cover_tiles_by_chunk[chunk_coord] as Dictionary).duplicate()
	cover_tiles_by_chunk[chunk_coord] = chunk_cover_tiles
	touched_chunks[chunk_coord] = true
	return chunk_cover_tiles

func _has_active_zone_neighbor(global_tile: Vector2i) -> bool:
	for offset: Vector2i in _ZONE_REVEAL_TILE_OFFSETS:
		if offset == Vector2i.ZERO:
			continue
		if _active_local_zone_tiles.has(WorldGenerator.offset_tile(global_tile, offset)):
			return true
	return false

func _build_local_cover_tiles_by_chunk(zone_tiles: Dictionary) -> Dictionary:
	var cover_tiles_by_chunk: Dictionary = {}
	if zone_tiles.is_empty() or not _chunk_manager:
		return cover_tiles_by_chunk
	var candidate_cache: Dictionary = {}
	var chunk_cache: Dictionary = {}
	var chunk_size: int = 0
	for global_tile: Vector2i in zone_tiles:
		var zone_chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
		var zone_chunk: Chunk = _resolve_cached_chunk(zone_chunk_coord, chunk_cache)
		if zone_chunk == null:
			continue
		if chunk_size <= 0:
			chunk_size = zone_chunk.get_chunk_size()
		var zone_local: Vector2i = _chunk_local_from_global(global_tile, zone_chunk_coord, chunk_size)
		var zone_cover_tiles: Dictionary
		if cover_tiles_by_chunk.has(zone_chunk_coord):
			zone_cover_tiles = cover_tiles_by_chunk[zone_chunk_coord] as Dictionary
		else:
			zone_cover_tiles = {}
			cover_tiles_by_chunk[zone_chunk_coord] = zone_cover_tiles
		zone_cover_tiles[zone_local] = true
		for offset: Vector2i in _ZONE_REVEAL_TILE_OFFSETS:
			if offset == Vector2i.ZERO:
				continue
			var candidate_local: Vector2i = zone_local + offset
			var candidate_tile: Vector2i = global_tile + offset
			var candidate_chunk_coord: Vector2i = zone_chunk_coord
			var candidate_chunk: Chunk = zone_chunk
			if candidate_local.x < 0 \
				or candidate_local.y < 0 \
				or candidate_local.x >= chunk_size \
				or candidate_local.y >= chunk_size:
				candidate_tile = WorldGenerator.offset_tile(global_tile, offset)
				candidate_chunk_coord = WorldGenerator.tile_to_chunk(candidate_tile)
				candidate_chunk = _resolve_cached_chunk(candidate_chunk_coord, chunk_cache)
				if candidate_chunk != null:
					candidate_local = _chunk_local_from_global(candidate_tile, candidate_chunk_coord, chunk_size)
			if candidate_cache.has(candidate_tile):
				if bool(candidate_cache[candidate_tile]):
					var cached_cover_tiles: Dictionary
					if cover_tiles_by_chunk.has(candidate_chunk_coord):
						cached_cover_tiles = cover_tiles_by_chunk[candidate_chunk_coord] as Dictionary
					else:
						cached_cover_tiles = {}
						cover_tiles_by_chunk[candidate_chunk_coord] = cached_cover_tiles
					cached_cover_tiles[candidate_local] = true
				continue
			if not candidate_chunk:
				candidate_cache[candidate_tile] = false
				continue
			var should_reveal: bool = candidate_chunk.is_revealable_cover_edge(candidate_local)
			candidate_cache[candidate_tile] = should_reveal
			if should_reveal:
				var candidate_cover_tiles: Dictionary
				if cover_tiles_by_chunk.has(candidate_chunk_coord):
					candidate_cover_tiles = cover_tiles_by_chunk[candidate_chunk_coord] as Dictionary
				else:
					candidate_cover_tiles = {}
					cover_tiles_by_chunk[candidate_chunk_coord] = candidate_cover_tiles
				candidate_cover_tiles[candidate_local] = true
	return cover_tiles_by_chunk

func _resolve_cached_chunk(chunk_coord: Vector2i, chunk_cache: Dictionary) -> Chunk:
	if chunk_cache.has(chunk_coord):
		return chunk_cache[chunk_coord] as Chunk
	var chunk: Chunk = _chunk_manager.get_chunk(chunk_coord)
	chunk_cache[chunk_coord] = chunk
	return chunk

func _chunk_local_from_global(global_tile: Vector2i, chunk_coord: Vector2i, chunk_size: int) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * chunk_size,
		global_tile.y - chunk_coord.y * chunk_size
	)

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
