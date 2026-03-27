class_name ChunkManager
extends Node2D

## Менеджер чанков мира.
## Загружает чанки, рендерит землю/горы и выполняет mining горной породы.

const RuntimeWorkTypes = preload("res://core/runtime/runtime_work_types.gd")
const ChunkFloraBuilderScript = preload("res://core/systems/world/chunk_flora_builder.gd")
const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")
const JOB_STREAMING_LOAD: StringName = &"chunk_manager.streaming_load"
const JOB_STREAMING_REDRAW: StringName = &"chunk_manager.streaming_redraw"
const JOB_TOPOLOGY: StringName = &"chunk_manager.topology_rebuild"
const TOPOLOGY_COMMIT_NONE: int = -1
const TOPOLOGY_START_NONE: int = -1
const TOPOLOGY_START_RESET_SCAN_COORDS: int = 0
const TOPOLOGY_START_COLLECT_CHUNKS: int = 1
const TOPOLOGY_START_RESET_VISITED: int = 2
const TOPOLOGY_START_RESET_KEY_BY_TILE: int = 3
const TOPOLOGY_START_RESET_TILES_BY_KEY: int = 4
const TOPOLOGY_START_RESET_OPEN_TILES_BY_KEY: int = 5
const TOPOLOGY_START_RESET_TILES_BY_KEY_BY_CHUNK: int = 6
const TOPOLOGY_START_RESET_OPEN_TILES_BY_KEY_BY_CHUNK: int = 7
const TOPOLOGY_START_RESET_COMPONENT: int = 8
const TOPOLOGY_COMMIT_KEY_BY_TILE: int = 0
const TOPOLOGY_COMMIT_TILES_BY_KEY: int = 1
const TOPOLOGY_COMMIT_OPEN_TILES_BY_KEY: int = 2
const TOPOLOGY_COMMIT_TILES_BY_KEY_BY_CHUNK: int = 3
const TOPOLOGY_COMMIT_OPEN_TILES_BY_KEY_BY_CHUNK: int = 4
const _CARDINAL_DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const TOPOLOGY_START_CHUNKS_PER_STEP: int = 8
const TOPOLOGY_RETIRED_DICT_KEYS_PER_STEP: int = 512
const MAX_LOAD_REQUESTS_SCANNED_PER_TICK: int = 16
const MAX_RELEVANT_LOAD_QUEUE_OVERSCAN: int = 8
const SURFACE_PAYLOAD_CACHE_LIMIT: int = 48
const INVALID_CHUNK_STATE_KEY: Vector3i = Vector3i(999999, 999999, 999999)
const INVALID_Z_LEVEL: int = 999999

var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(99999, 99999)
var _player: Node2D = null
var _chunk_container: Node2D = null
var _load_queue: Array[Dictionary] = []
var _redrawing_chunks: Array[Chunk] = []
var _saved_chunk_data: Dictionary = {}
var _terrain_tileset: TileSet = null
var _overlay_tileset: TileSet = null
var _underground_terrain_tileset: TileSet = null
var _tileset_bundles_by_biome: Dictionary = {}
var _fog_tileset: TileSet = null
var _fog_state: UndergroundFogState = UndergroundFogState.new()
var _fog_job_id: StringName = &""
var _initialized: bool = false
var _active_z: int = 0
var _z_containers: Dictionary = {}
var _z_chunks: Dictionary = {}
var _mountain_key_by_tile: Dictionary = {}
var _mountain_tiles_by_key: Dictionary = {}
var _mountain_open_tiles_by_key: Dictionary = {}
var _mountain_tiles_by_key_by_chunk: Dictionary = {}
var _mountain_open_tiles_by_key_by_chunk: Dictionary = {}
var _is_topology_dirty: bool = false
var _native_topology_builder: RefCounted = null
var _native_topology_active: bool = false
var _native_topology_dirty: bool = false
var _flora_builder: ChunkFloraBuilderScript = null
var _is_topology_build_in_progress: bool = false
var _is_boot_in_progress: bool = false
var _staged_chunk: Chunk = null
var _staged_coord: Vector2i = Vector2i(999999, 999999)
var _staged_z: int = 0
var _staged_data: Dictionary = {}  ## Native data между фазами
var _staged_flora_result: ChunkFloraResultScript = null
## --- Async generation (runtime only) ---
var _gen_task_id: int = -1  ## WorkerThreadPool task ID, -1 = нет активной задачи
var _gen_coord: Vector2i = Vector2i(999999, 999999)  ## Координата в процессе генерации
var _gen_z: int = 0
var _gen_result: Dictionary = {}  ## Результат от worker thread
var _gen_mutex: Mutex = Mutex.new()
var _worker_chunk_builder: RefCounted = null
var _shutdown_in_progress: bool = false
var _surface_payload_cache: Dictionary = {}
var _surface_payload_cache_lru: Array[Vector3i] = []
var _topology_scan_chunk_coords: Array[Vector2i] = []
var _topology_scan_chunk_index: int = 0
var _topology_scan_local_x: int = 0
var _topology_scan_local_y: int = 0
var _topology_build_visited: Dictionary = {}
var _topology_build_key_by_tile: Dictionary = {}
var _topology_build_tiles_by_key: Dictionary = {}
var _topology_build_open_tiles_by_key: Dictionary = {}
var _topology_build_tiles_by_key_by_chunk: Dictionary = {}
var _topology_build_open_tiles_by_key_by_chunk: Dictionary = {}
var _topology_build_start_phase: int = TOPOLOGY_START_NONE
var _topology_start_chunk_keys: Array[Vector2i] = []
var _topology_start_chunk_index: int = 0
var _topology_component_queue: Array[Vector2i] = []
var _topology_component_queue_index: int = 0
var _topology_component_tiles: Dictionary = {}
var _topology_component_open_tiles: Dictionary = {}
var _topology_component_tiles_by_chunk: Dictionary = {}
var _topology_component_open_tiles_by_chunk: Dictionary = {}
var _topology_component_key: Vector2i = Vector2i(999999, 999999)
var _topology_component_tiles_list: Array[Vector2i] = []
var _topology_component_finalize_index: int = 0
var _topology_build_commit_phase: int = TOPOLOGY_COMMIT_NONE
var _topology_retired_dicts: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("chunk_manager")
	_chunk_container = Node2D.new()
	_chunk_container.name = "Chunks"
	add_child(_chunk_container)
	_setup_z_containers()
	call_deferred("_deferred_init")

func _exit_tree() -> void:
	_shutdown_in_progress = true
	_load_queue.clear()
	_redrawing_chunks.clear()
	if _staged_chunk != null:
		_staged_chunk = null
	_staged_data = {}
	_staged_flora_result = null
	if _gen_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_gen_task_id)
		_gen_task_id = -1
	_gen_coord = Vector2i(999999, 999999)
	_gen_z = 0
	_gen_mutex.lock()
	_gen_result = {}
	_gen_mutex.unlock()
	_worker_chunk_builder = null
	_surface_payload_cache.clear()
	_surface_payload_cache_lru.clear()
	if FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(JOB_STREAMING_LOAD)
		FrameBudgetDispatcher.unregister_job(JOB_STREAMING_REDRAW)
		FrameBudgetDispatcher.unregister_job(JOB_TOPOLOGY)
		if _fog_job_id:
			FrameBudgetDispatcher.unregister_job(_fog_job_id)

func _process(_delta: float) -> void:
	if not _initialized or not _player or _is_boot_in_progress:
		return
	_check_player_chunk()

## Boot-time загрузка стартового пузыря. Вызывается из GameWorld под loading screen.
## progress_callback: func(percent: float, text: String) -> void
func boot_load_initial_chunks(progress_callback: Callable) -> void:
	if not _initialized or not _player:
		return
	_is_boot_in_progress = true
	var center: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	_player_chunk = center
	var load_radius: int = WorldGenerator.balance.load_radius
	var coords: Array[Vector2i] = []
	for dx: int in range(-load_radius, load_radius + 1):
		for dy: int in range(-load_radius, load_radius + 1):
			coords.append(_offset_chunk_coord(center, Vector2i(dx, dy)))
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_manhattan_distance(a, center) < _chunk_manhattan_distance(b, center)
	)
	var total: int = coords.size()
	for i: int in range(total):
		var coord: Vector2i = coords[i]
		if not _loaded_chunks.has(coord):
			_load_chunk(coord)
			var chunk: Chunk = _loaded_chunks.get(coord)
			if chunk and not chunk.is_redraw_complete():
				chunk.complete_redraw_now()
			var redraw_idx: int = _redrawing_chunks.find(chunk)
			if redraw_idx >= 0:
				_redrawing_chunks.remove_at(redraw_idx)
		var pct: float = float(i + 1) / float(total) * 80.0
		progress_callback.call(pct, Localization.t("UI_LOADING_GENERATING_TERRAIN", {"current": i + 1, "total": total}))
		await get_tree().process_frame
	progress_callback.call(85.0, Localization.t("UI_LOADING_BUILDING_MOUNTAINS"))
	await get_tree().process_frame
	if _is_native_topology_enabled():
		_native_topology_builder.call("ensure_built")
		_native_topology_dirty = false
	else:
		_ensure_topology_current()
	progress_callback.call(95.0, Localization.t("UI_LOADING_LANDING"))
	await get_tree().process_frame
	_sync_loaded_chunk_display_positions(center)
	_is_boot_in_progress = false

func set_saved_data(data: Dictionary) -> void:
	var normalized: Dictionary = {}
	for key: Variant in data:
		var normalized_key: Vector3i = _normalize_saved_chunk_key(key)
		if normalized_key == INVALID_CHUNK_STATE_KEY:
			continue
		normalized[normalized_key] = data[key]
	_saved_chunk_data = normalized

func get_save_data() -> Dictionary:
	var result: Dictionary = _saved_chunk_data.duplicate()
	for z_value: int in _z_chunks:
		var z_loaded_chunks: Dictionary = _z_chunks[z_value] as Dictionary
		for coord: Vector2i in z_loaded_chunks:
			var chunk: Chunk = z_loaded_chunks[coord]
			if chunk.is_dirty:
				result[_make_chunk_state_key(z_value, coord)] = chunk.get_modifications()
	return result

func is_tile_loaded(gt: Vector2i) -> bool:
	return _loaded_chunks.has(WorldGenerator.tile_to_chunk(_canonical_tile(gt)))

func get_chunk_at_tile(gt: Vector2i) -> Chunk:
	return _loaded_chunks.get(WorldGenerator.tile_to_chunk(_canonical_tile(gt)))

func get_chunk(cc: Vector2i) -> Chunk:
	return _loaded_chunks.get(_canonical_chunk_coord(cc))

func get_terrain_type_at_global(tile_pos: Vector2i) -> int:
	var canonical_tile: Vector2i = _canonical_tile(tile_pos)
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(canonical_tile)
	var loaded_chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if loaded_chunk:
		return loaded_chunk.get_terrain_type_at(loaded_chunk.global_to_local(canonical_tile))
	var saved_chunk_state: Dictionary = _get_saved_chunk_modifications(_active_z, chunk_coord)
	var local_tile: Vector2i = _tile_to_local(canonical_tile, chunk_coord, WorldGenerator.balance.chunk_size_tiles)
	var tile_state: Dictionary = saved_chunk_state.get(local_tile, {}) as Dictionary
	if tile_state.has("terrain"):
		return int(tile_state["terrain"])
	# Underground: unloaded tiles are solid rock, not surface terrain
	if _active_z != 0:
		return TileGenData.TerrainType.ROCK
	if WorldGenerator and WorldGenerator._is_initialized:
		return WorldGenerator.get_terrain_type_fast(canonical_tile)
	return TileGenData.TerrainType.GROUND

func get_loaded_chunks() -> Dictionary:
	return _loaded_chunks

func sync_display_to_player() -> void:
	if not _initialized or not _player or not WorldGenerator:
		return
	var reference_chunk: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	var chunk_changed: bool = reference_chunk != _player_chunk
	_player_chunk = reference_chunk
	_sync_loaded_chunk_display_positions(reference_chunk)
	if chunk_changed and not _is_boot_in_progress:
		_update_chunks(reference_chunk)

func _make_chunk_state_key(z_level: int, coord: Vector2i) -> Vector3i:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	return Vector3i(canonical_coord.x, canonical_coord.y, z_level)

func _normalize_saved_chunk_key(key: Variant) -> Vector3i:
	if key is Vector3i:
		var coord3: Vector3i = key as Vector3i
		var canonical_coord: Vector2i = _canonical_chunk_coord(Vector2i(coord3.x, coord3.y))
		return Vector3i(canonical_coord.x, canonical_coord.y, coord3.z)
	if key is Vector2i:
		var coord2: Vector2i = key as Vector2i
		var canonical_coord: Vector2i = _canonical_chunk_coord(coord2)
		return Vector3i(canonical_coord.x, canonical_coord.y, 0)
	return INVALID_CHUNK_STATE_KEY

func _get_saved_chunk_modifications(z_level: int, coord: Vector2i) -> Dictionary:
	return _saved_chunk_data.get(_make_chunk_state_key(z_level, coord), {}) as Dictionary

func _canonical_tile(tile_pos: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("canonicalize_tile"):
		return WorldGenerator.canonicalize_tile(tile_pos)
	return tile_pos

func _canonical_chunk_coord(coord: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("canonicalize_chunk_coord"):
		return WorldGenerator.canonicalize_chunk_coord(coord)
	return coord

func _offset_tile(tile_pos: Vector2i, offset: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("offset_tile"):
		return WorldGenerator.offset_tile(tile_pos, offset)
	return tile_pos + offset

func _offset_chunk_coord(coord: Vector2i, offset: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("offset_chunk_coord"):
		return WorldGenerator.offset_chunk_coord(coord, offset)
	return coord + offset

func _tile_to_local(tile_pos: Vector2i, chunk_coord: Vector2i, chunk_size: int) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("tile_to_local_in_chunk"):
		return WorldGenerator.tile_to_local_in_chunk(tile_pos, chunk_coord)
	return Vector2i(
		tile_pos.x - chunk_coord.x * chunk_size,
		tile_pos.y - chunk_coord.y * chunk_size
	)

func _chunk_local_to_tile(chunk_coord: Vector2i, local_tile: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("chunk_local_to_tile"):
		return WorldGenerator.chunk_local_to_tile(chunk_coord, local_tile)
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles if WorldGenerator and WorldGenerator.balance else 1
	return Vector2i(
		chunk_coord.x * chunk_size + local_tile.x,
		chunk_coord.y * chunk_size + local_tile.y
	)

func _chunk_axis_distance(chunk_x: int, center_x: int) -> int:
	if WorldGenerator:
		return absi(WorldGenerator.chunk_wrap_delta_x(chunk_x, center_x))
	return absi(chunk_x - center_x)

func _chunk_manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return _chunk_axis_distance(a.x, b.x) + absi(a.y - b.y)

func _is_chunk_within_radius(coord: Vector2i, center: Vector2i, radius: int) -> bool:
	return _chunk_axis_distance(coord.x, center.x) <= radius and absi(coord.y - center.y) <= radius

func _resolve_display_reference_chunk(fallback_chunk: Vector2i) -> Vector2i:
	if _player and WorldGenerator:
		return WorldGenerator.world_to_chunk(_player.global_position)
	return _canonical_chunk_coord(fallback_chunk)

func _sync_chunk_display_position(chunk: Chunk, reference_chunk: Vector2i) -> void:
	if not is_instance_valid(chunk):
		return
	chunk.sync_display_position(_resolve_display_reference_chunk(reference_chunk))

func _sync_loaded_chunk_display_positions(reference_chunk: Vector2i) -> void:
	var canonical_reference: Vector2i = _resolve_display_reference_chunk(reference_chunk)
	for coord: Vector2i in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[coord]
		_sync_chunk_display_position(chunk, canonical_reference)

func _has_load_request(coord: Vector2i, z_level: int) -> bool:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	for request: Dictionary in _load_queue:
		if request.get("coord", Vector2i.ZERO) == canonical_coord and int(request.get("z", INVALID_Z_LEVEL)) == z_level:
			return true
	return false

func _enqueue_load_request(coord: Vector2i, z_level: int) -> void:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	if _has_load_request(canonical_coord, z_level):
		return
	_load_queue.append({
		"coord": canonical_coord,
		"z": z_level,
	})

func _is_staged_request(coord: Vector2i, z_level: int) -> bool:
	return _staged_coord == _canonical_chunk_coord(coord) and _staged_z == z_level

func _is_generating_request(coord: Vector2i, z_level: int) -> bool:
	return _gen_coord == _canonical_chunk_coord(coord) and _gen_z == z_level

func _clear_staged_request() -> void:
	if _staged_chunk != null:
		_staged_chunk.queue_free()
	_staged_chunk = null
	_staged_coord = Vector2i(999999, 999999)
	_staged_z = 0
	_staged_data = {}
	_staged_flora_result = null

func is_topology_ready() -> bool:
	if _is_native_topology_enabled():
		return not _native_topology_dirty
	return not _is_topology_dirty and not _is_topology_build_in_progress

func get_mountain_key_at_tile(tile_pos: Vector2i) -> Vector2i:
	if _active_z != 0:
		return Vector2i(999999, 999999)
	tile_pos = _canonical_tile(tile_pos)
	if _is_native_topology_enabled():
		return _native_topology_builder.call("get_mountain_key_at_tile", tile_pos) as Vector2i
	return _mountain_key_by_tile.get(tile_pos, Vector2i(999999, 999999))

func get_mountain_tiles(mountain_key: Vector2i) -> Dictionary:
	if _active_z != 0:
		return {}
	if _is_native_topology_enabled():
		return _native_topology_builder.call("get_mountain_tiles", mountain_key) as Dictionary
	return _mountain_tiles_by_key.get(mountain_key, {}) as Dictionary

func get_mountain_open_tiles(mountain_key: Vector2i) -> Dictionary:
	if _active_z != 0:
		return {}
	if _is_native_topology_enabled():
		return _native_topology_builder.call("get_mountain_open_tiles", mountain_key) as Dictionary
	return _mountain_open_tiles_by_key.get(mountain_key, {}) as Dictionary

## Возвращает player-local derived product для loaded underground pocket.
## Не использует `mountain_key` как reveal-domain и не является shared world truth.
func query_local_underground_zone(seed_tile: Vector2i) -> Dictionary:
	var started_usec: int = WorldPerfProbe.begin()
	seed_tile = _canonical_tile(seed_tile)
	if not is_tile_loaded(seed_tile):
		return {}
	var seed_chunk: Chunk = get_chunk_at_tile(seed_tile)
	if not seed_chunk:
		return {}
	var seed_local: Vector2i = seed_chunk.global_to_local(seed_tile)
	if not _is_local_underground_zone_open_tile(seed_chunk.get_terrain_type_at(seed_local)):
		return {}
	var visited: Dictionary = {seed_tile: true}
	var queue: Array[Vector2i] = [seed_tile]
	var queue_index: int = 0
	var tiles: Dictionary = {}
	var chunk_coords: Dictionary = {}
	var truncated: bool = false
	while queue_index < queue.size():
		var current: Vector2i = queue[queue_index]
		queue_index += 1
		tiles[current] = true
		var current_chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(current)
		chunk_coords[current_chunk_coord] = true
		var current_chunk: Chunk = _loaded_chunks.get(current_chunk_coord)
		if not current_chunk:
			truncated = true
			continue
		var chunk_size: int = current_chunk.get_chunk_size()
		var current_local: Vector2i = _tile_to_local(current, current_chunk_coord, chunk_size)
		for dir: Vector2i in _CARDINAL_DIRS:
			var next_tile: Vector2i = _offset_tile(current, dir)
			if visited.has(next_tile):
				continue
			var next_chunk_coord: Vector2i = current_chunk_coord
			var next_local: Vector2i = current_local + dir
			var next_chunk: Chunk = current_chunk
			if next_local.x < 0:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.LEFT)
				next_local.x += chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.x >= chunk_size:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.RIGHT)
				next_local.x -= chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.y < 0:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.UP)
				next_local.y += chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.y >= chunk_size:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.DOWN)
				next_local.y -= chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			if not next_chunk:
				truncated = true
				continue
			if not _is_local_underground_zone_open_tile(next_chunk.get_terrain_type_at(next_local)):
				continue
			visited[next_tile] = true
			queue.append(next_tile)
	var chunk_coord_list: Array[Vector2i] = []
	for coord: Vector2i in chunk_coords:
		chunk_coord_list.append(coord)
	WorldPerfProbe.end("ChunkManager.query_local_underground_zone", started_usec)
	return {
		"zone_kind": &"loaded_open_pocket",
		"seed_tile": seed_tile,
		"tiles": tiles,
		"chunk_coords": chunk_coord_list,
		"truncated": truncated,
	}

func try_harvest_at_world(world_pos: Vector2) -> Dictionary:
	var started_usec: int = WorldPerfProbe.begin()
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var chunk: Chunk = get_chunk_at_tile(tile_pos)
	if not chunk:
		return {}
	var local_tile: Vector2i = chunk.global_to_local(tile_pos)
	var result: Dictionary = chunk.try_mine_at(local_tile)
	if result.is_empty():
		return {}
	# Same-chunk neighbor re-normalization (MINED_FLOOR <-> MOUNTAIN_ENTRANCE)
	chunk._refresh_open_neighbors(local_tile)
	var same_chunk_norm_dirty: Dictionary = {}
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor_local: Vector2i = local_tile + dir
		if chunk._is_inside(neighbor_local):
			same_chunk_norm_dirty[neighbor_local] = true
	if not same_chunk_norm_dirty.is_empty():
		chunk._redraw_dirty_tiles(same_chunk_norm_dirty)
	# Cross-chunk seam: normalize + redraw affected neighbor chunks
	_seam_normalize_and_redraw(tile_pos, local_tile, chunk)
	_on_mountain_tile_changed(tile_pos, int(result["old_type"]), int(result["new_type"]))
	EventBus.mountain_tile_mined.emit(tile_pos, int(result["old_type"]), int(result["new_type"]))
	# Underground fog: reveal newly mined tile + neighbors
	if _active_z != 0:
		var reveal_tiles: Array = [tile_pos]
		for offset: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
				Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			reveal_tiles.append(_offset_tile(tile_pos, offset))
		_fog_state.force_reveal(reveal_tiles)
		var visible_tiles: Dictionary = {}
		for t: Variant in reveal_tiles:
			var rv_tile: Vector2i = t as Vector2i
			visible_tiles[rv_tile] = true
		_apply_underground_fog_visible_tiles(visible_tiles)
	WorldPerfProbe.end("ChunkManager.try_harvest_at_world", started_usec)
	return {
		"item_id": str(WorldGenerator.balance.rock_drop_item_id),
		"amount": WorldGenerator.balance.rock_drop_amount,
	}

func _seam_normalize_and_redraw(tile_pos: Vector2i, local_tile: Vector2i, source_chunk: Chunk) -> void:
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles
	var on_left: bool = local_tile.x == 0
	var on_right: bool = local_tile.x == chunk_size - 1
	var on_top: bool = local_tile.y == 0
	var on_bottom: bool = local_tile.y == chunk_size - 1
	if not (on_left or on_right or on_top or on_bottom):
		return
	# Cardinal neighbor directions that cross into another chunk
	var cross_dirs: Array[Vector2i] = []
	if on_left:
		cross_dirs.append(Vector2i.LEFT)
	if on_right:
		cross_dirs.append(Vector2i.RIGHT)
	if on_top:
		cross_dirs.append(Vector2i.UP)
	if on_bottom:
		cross_dirs.append(Vector2i.DOWN)
	for dir: Vector2i in cross_dirs:
		var neighbor_global: Vector2i = _offset_tile(tile_pos, dir)
		var neighbor_chunk: Chunk = get_chunk_at_tile(neighbor_global)
		if not neighbor_chunk or neighbor_chunk == source_chunk:
			continue
		var n_local: Vector2i = neighbor_chunk.global_to_local(neighbor_global)
		# Re-normalize the direct cardinal neighbor (MINED_FLOOR <-> MOUNTAIN_ENTRANCE)
		neighbor_chunk._refresh_open_tile(n_local)
		neighbor_chunk.is_dirty = true
		# Redraw a border strip: the neighbor tile + tiles along the seam edge
		# (covers cardinal + diagonal visual dependencies)
		var perp: Vector2i = Vector2i(abs(dir.y), abs(dir.x))
		var cross_dirty: Dictionary = {}
		for p_offset: int in range(-1, 2):
			var t: Vector2i = n_local + perp * p_offset
			if neighbor_chunk._is_inside(t):
				cross_dirty[t] = true
		if not cross_dirty.is_empty():
			neighbor_chunk._redraw_dirty_tiles(cross_dirty)

func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var chunk: Chunk = get_chunk_at_tile(tile_pos)
	if not chunk:
		return false
	return chunk.get_terrain_type_at(chunk.global_to_local(tile_pos)) == TileGenData.TerrainType.ROCK

func is_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	return _is_walkable_terrain(get_terrain_type_at_global(tile_pos))

## Устанавливает активный mountain key и возвращает список чанков,
## у которых должен обновиться local mountain shell reveal state.
func _deferred_init() -> void:
	_player = PlayerAuthority.get_local_player()
	_build_world_tilesets()
	_build_fog_tileset()
	_setup_native_topology_builder()
	_setup_flora_builder()
	_initialized = _terrain_tileset != null and _overlay_tileset != null
	if _initialized:
		_register_budget_jobs()
		_fog_job_id = FrameBudgetDispatcher.register_job(
			RuntimeWorkTypes.CATEGORY_TOPOLOGY,
			1.0,
			_fog_update_tick,
			&"underground.fog_update",
			RuntimeWorkTypes.CadenceKind.NEAR_PLAYER,
			RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
			false,
			"Underground fog update"
		)

func _build_world_tilesets() -> void:
	_tileset_bundles_by_biome.clear()
	if not WorldGenerator or not WorldGenerator.balance:
		return
	var registered_biomes: Array[BiomeData] = []
	if WorldGenerator.has_method("get_registered_biomes"):
		registered_biomes = WorldGenerator.get_registered_biomes()
	var biome: BiomeData = _get_default_biome()
	if not biome:
		return
	if registered_biomes.is_empty():
		registered_biomes.append(biome)
	_terrain_tileset = ChunkTilesetFactory.build_surface_tileset(WorldGenerator.balance, registered_biomes)
	_overlay_tileset = ChunkTilesetFactory.build_overlay_tileset(WorldGenerator.balance, biome)
	_underground_terrain_tileset = ChunkTilesetFactory.build_underground_terrain_tileset(WorldGenerator.balance, biome)
	for biome_candidate: BiomeData in registered_biomes:
		_get_or_build_tileset_bundle(biome_candidate)

func _get_default_biome() -> BiomeData:
	if WorldGenerator and WorldGenerator.current_biome:
		return WorldGenerator.current_biome
	if WorldGenerator and WorldGenerator.has_method("get_registered_biomes"):
		var registered_biomes: Array[BiomeData] = WorldGenerator.get_registered_biomes()
		if not registered_biomes.is_empty():
			return registered_biomes[0]
	for biome_key: Variant in _tileset_bundles_by_biome:
		var bundle: Dictionary = _tileset_bundles_by_biome.get(biome_key, {}) as Dictionary
		var cached_biome: BiomeData = bundle.get("biome") as BiomeData
		if cached_biome:
			return cached_biome
	return null

func _get_biome_cache_key(biome: BiomeData) -> StringName:
	if not biome:
		return &""
	if not biome.id.is_empty():
		return biome.id
	if not biome.resource_path.is_empty():
		return StringName(biome.resource_path)
	return StringName("%s:%d" % [biome.get_class(), biome.get_instance_id()])

func _get_or_build_tileset_bundle(biome: BiomeData) -> Dictionary:
	if not biome or not WorldGenerator or not WorldGenerator.balance:
		return {}
	var biome_key: StringName = _get_biome_cache_key(biome)
	var cached: Dictionary = _tileset_bundles_by_biome.get(biome_key, {}) as Dictionary
	if not cached.is_empty():
		return cached
	var bundle := {
		"biome": biome,
		"terrain": _terrain_tileset,
		"overlay": _overlay_tileset,
		"underground_terrain": ChunkTilesetFactory.build_underground_terrain_tileset(WorldGenerator.balance, biome),
	}
	_tileset_bundles_by_biome[biome_key] = bundle
	return bundle

func _coerce_biome_candidate(candidate: Variant) -> BiomeData:
	if candidate is BiomeData:
		return candidate as BiomeData
	if candidate is Dictionary:
		var candidate_dict: Dictionary = candidate as Dictionary
		if candidate_dict.get("biome") is BiomeData:
			return candidate_dict.get("biome") as BiomeData
	if candidate != null and candidate is Object:
		var object_biome: Variant = (candidate as Object).get("biome")
		if object_biome is BiomeData:
			return object_biome as BiomeData
	return null

func _get_chunk_center_tile(chunk_coord: Vector2i) -> Vector2i:
	var origin: Vector2i = WorldGenerator.chunk_to_tile_origin(chunk_coord)
	var half_chunk: int = maxi(0, WorldGenerator.balance.chunk_size_tiles / 2)
	return WorldGenerator.offset_tile(origin, Vector2i(half_chunk, half_chunk))

func _resolve_chunk_biome(coord: Vector2i, z_level: int) -> BiomeData:
	if z_level != 0:
		return _get_default_biome()
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	var resolved_biome: BiomeData = _resolve_chunk_biome_from_world_generator(canonical_coord)
	if resolved_biome:
		return resolved_biome
	return _get_default_biome()

func _resolve_chunk_biome_from_world_generator(chunk_coord: Vector2i) -> BiomeData:
	if not WorldGenerator:
		return null
	for method_name: String in [
		"get_dominant_biome_for_chunk",
		"get_chunk_biome",
	]:
		if not WorldGenerator.has_method(method_name):
			continue
		var direct_candidate: Variant = WorldGenerator.call(method_name, chunk_coord)
		var direct_biome: BiomeData = _coerce_biome_candidate(direct_candidate)
		if direct_biome:
			return direct_biome
	var center_tile: Vector2i = _get_chunk_center_tile(chunk_coord)
	for method_name: String in [
		"get_tile_biome",
		"resolve_biome_at_tile",
		"get_biome_at_tile",
		"resolve_biome_for_tile",
	]:
		if not WorldGenerator.has_method(method_name):
			continue
		var tile_candidate: Variant = WorldGenerator.call(method_name, center_tile)
		var tile_biome: BiomeData = _coerce_biome_candidate(tile_candidate)
		if tile_biome:
			return tile_biome
	if WorldGenerator.has_method("resolve_biome") and WorldGenerator.has_method("sample_world_channels"):
		var channels = WorldGenerator.sample_world_channels(center_tile)
		var resolved_candidate: Variant = WorldGenerator.call("resolve_biome", center_tile, channels)
		var resolved_biome: BiomeData = _coerce_biome_candidate(resolved_candidate)
		if resolved_biome:
			return resolved_biome
	return null

func _build_fog_tileset() -> void:
	if not WorldGenerator or not WorldGenerator.balance:
		return
	_fog_tileset = ChunkTilesetFactory.create_fog_tileset(WorldGenerator.balance.tile_size)

func _is_walkable_terrain(terrain_type: int) -> bool:
	return terrain_type != TileGenData.TerrainType.ROCK \
		and terrain_type != TileGenData.TerrainType.WATER

func _fog_update_tick() -> bool:
	if _active_z == 0 or not _player:
		return false
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var delta: Dictionary = _fog_state.update(player_tile)
	var newly_visible: Dictionary = delta.get("newly_visible", {})
	var newly_discovered: Dictionary = delta.get("newly_discovered", {})
	if newly_visible.is_empty() and newly_discovered.is_empty():
		return false
	_apply_underground_fog_visible_tiles(newly_visible)
	_apply_underground_fog_discovered_tiles(newly_discovered)
	return false

func _apply_underground_fog_visible_tiles(global_tiles: Dictionary) -> void:
	var tiles_by_chunk: Dictionary = _collect_underground_revealable_tiles(global_tiles)
	for chunk_coord: Vector2i in tiles_by_chunk:
		var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
		if chunk:
			chunk.apply_fog_visible(tiles_by_chunk[chunk_coord] as Dictionary)

func _apply_underground_fog_discovered_tiles(global_tiles: Dictionary) -> void:
	var tiles_by_chunk: Dictionary = _collect_underground_revealable_tiles(global_tiles)
	for chunk_coord: Vector2i in tiles_by_chunk:
		var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
		if chunk:
			chunk.apply_fog_discovered(tiles_by_chunk[chunk_coord] as Dictionary)

func _collect_underground_revealable_tiles(global_tiles: Dictionary) -> Dictionary:
	var candidate_tiles: Dictionary = global_tiles.duplicate()
	for global_tile: Vector2i in global_tiles:
		_expand_underground_wall_halo(_canonical_tile(global_tile), candidate_tiles)
	var tiles_by_chunk: Dictionary = {}
	for global_tile: Vector2i in candidate_tiles:
		var canonical_tile: Vector2i = _canonical_tile(global_tile)
		var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(canonical_tile)
		var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
		if not chunk:
			continue
		var local: Vector2i = chunk.global_to_local(canonical_tile)
		if not chunk.is_fog_revealable(local):
			continue
		if not tiles_by_chunk.has(chunk_coord):
			tiles_by_chunk[chunk_coord] = {}
		(tiles_by_chunk[chunk_coord] as Dictionary)[local] = true
	return tiles_by_chunk

func _expand_underground_wall_halo(global_tile: Vector2i, candidate_tiles: Dictionary) -> void:
	global_tile = _canonical_tile(global_tile)
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
	if not chunk:
		return
	var local: Vector2i = chunk.global_to_local(global_tile)
	var terrain: int = chunk.get_terrain_type_at(local)
	if terrain != TileGenData.TerrainType.MINED_FLOOR \
		and terrain != TileGenData.TerrainType.MOUNTAIN_ENTRANCE \
		and terrain != TileGenData.TerrainType.GROUND:
		return
	for offset: Vector2i in [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
	]:
		candidate_tiles[_offset_tile(global_tile, offset)] = true

func _setup_native_topology_builder() -> void:
	_native_topology_active = false
	if not WorldGenerator or not WorldGenerator.balance or not WorldGenerator.balance.use_native_mountain_topology:
		_native_topology_builder = null
		return
	if ClassDB.class_exists("MountainTopologyBuilder"):
		_native_topology_builder = ClassDB.instantiate("MountainTopologyBuilder") as RefCounted
		if _native_topology_builder \
			and _native_topology_builder.has_method("set_chunk") \
			and _native_topology_builder.has_method("ensure_built") \
			and _native_topology_builder.has_method("get_mountain_chunk_coords"):
			_native_topology_active = true
		else:
			_native_topology_builder = null
	else:
		_native_topology_builder = null

func _setup_flora_builder() -> void:
	if WorldGenerator and WorldGenerator._is_initialized:
		_flora_builder = ChunkFloraBuilderScript.new()
		_flora_builder.initialize(WorldGenerator.world_seed)

func _compute_flora_for_chunk(chunk: Chunk, build_result: ChunkBuildResult) -> ChunkFloraResultScript:
	if _flora_builder == null or build_result == null or not build_result.is_valid():
		return null
	var flora_result: ChunkFloraResultScript = _compute_flora_result(
		build_result.canonical_chunk_coord,
		build_result.chunk_size,
		build_result.base_tile,
		build_result.biome,
		build_result.variation,
		build_result.terrain,
		build_result.flora_density_values,
		build_result.flora_modulation_values
	)
	if flora_result != null:
		chunk.set_flora_result(flora_result)
	return flora_result

func _compute_flora_for_native_data(chunk: Chunk, chunk_coord: Vector2i, native_data: Dictionary) -> ChunkFloraResultScript:
	if _flora_builder == null or chunk == null or native_data.is_empty():
		return null
	var chunk_size: int = int(native_data.get("chunk_size", 0))
	var base_tile: Vector2i = native_data.get(
		"base_tile",
		WorldGenerator.chunk_to_tile_origin(chunk_coord) if WorldGenerator else Vector2i.ZERO
	) as Vector2i
	var flora_result: ChunkFloraResultScript = _compute_flora_result(
		chunk_coord,
		chunk_size,
		base_tile,
		native_data.get("biome", PackedByteArray()) as PackedByteArray,
		native_data.get("variation", PackedByteArray()) as PackedByteArray,
		native_data.get("terrain", PackedByteArray()) as PackedByteArray,
		native_data.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array,
		native_data.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array
	)
	if flora_result != null:
		chunk.set_flora_result(flora_result)
	return flora_result

func _compute_flora_result(
	chunk_coord: Vector2i,
	chunk_size: int,
	base_tile: Vector2i,
	biome_bytes: PackedByteArray,
	variation_bytes: PackedByteArray,
	terrain_bytes: PackedByteArray,
	flora_density_values: PackedFloat32Array,
	flora_modulation_values: PackedFloat32Array
) -> ChunkFloraResultScript:
	if _flora_builder == null or WorldGenerator == null or chunk_size <= 0:
		return null
	var tile_count: int = chunk_size * chunk_size
	if terrain_bytes.size() != tile_count \
		or biome_bytes.size() != tile_count \
		or variation_bytes.size() != tile_count \
		or flora_density_values.size() != tile_count \
		or flora_modulation_values.size() != tile_count:
		return null
	var biome_palette: Array[BiomeData] = WorldGenerator.get_registered_biomes()
	return _flora_builder.compute_placements(
		chunk_coord,
		chunk_size,
		base_tile,
		terrain_bytes,
		biome_palette,
		biome_bytes,
		variation_bytes,
		flora_density_values,
		flora_modulation_values
	)

func _is_native_topology_enabled() -> bool:
	return _native_topology_active

func _check_player_chunk() -> void:
	var cur: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	if cur != _player_chunk:
		_player_chunk = cur
		_sync_loaded_chunk_display_positions(cur)
		_update_chunks(cur)

func _update_chunks(center: Vector2i) -> void:
	center = _canonical_chunk_coord(center)
	var load_radius: int = WorldGenerator.balance.load_radius
	var unload_radius: int = WorldGenerator.balance.unload_radius
	var needed: Dictionary = {}
	for dx: int in range(-load_radius, load_radius + 1):
		for dy: int in range(-load_radius, load_radius + 1):
			needed[_offset_chunk_coord(center, Vector2i(dx, dy))] = true
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks:
		if not _is_chunk_within_radius(coord, center, unload_radius):
			to_unload.append(coord)
	for coord: Vector2i in to_unload:
		_unload_chunk(coord)
	_prune_load_queue(center, _active_z, load_radius)
	var to_load: Array[Vector2i] = []
	for coord: Vector2i in needed:
		if not _loaded_chunks.has(coord) \
			and not _has_load_request(coord, _active_z) \
			and not _is_staged_request(coord, _active_z) \
			and not _is_generating_request(coord, _active_z):
			to_load.append(coord)
	to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_manhattan_distance(a, center) < _chunk_manhattan_distance(b, center)
	)
	for coord: Vector2i in to_load:
		_enqueue_load_request(coord, _active_z)
	_sync_loaded_chunk_display_positions(center)

func _process_load_queue() -> void:
	var loads_per_frame: int = 1
	if WorldGenerator and WorldGenerator.balance:
		loads_per_frame = WorldGenerator.balance.chunk_loads_per_frame
	var loaded_count: int = 0
	while not _load_queue.is_empty() and loaded_count < loads_per_frame:
		var request: Dictionary = _load_queue.pop_front()
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var request_z: int = int(request.get("z", _active_z))
		if request_z != _active_z:
			continue
		var load_radius: int = WorldGenerator.balance.load_radius
		if not _is_chunk_within_radius(coord, _player_chunk, load_radius):
			continue
		_load_chunk_for_z(coord, request_z)
		loaded_count += 1

func _load_chunk(coord: Vector2i) -> void:
	_load_chunk_for_z(_canonical_chunk_coord(coord), _active_z)

func _load_chunk_for_z(coord: Vector2i, z_level: int) -> void:
	coord = _canonical_chunk_coord(coord)
	var started_usec: int = WorldPerfProbe.begin()
	var loaded_chunks_for_z: Dictionary = _z_chunks.get(z_level, {})
	if loaded_chunks_for_z.has(coord) or not _terrain_tileset or not _overlay_tileset:
		return
	var native_data: Dictionary
	var build_result: ChunkBuildResult = null
	if z_level != 0:
		native_data = _generate_solid_rock_chunk()
	else:
		if not _try_get_surface_payload_cache_native_data(coord, z_level, native_data):
			build_result = WorldGenerator.build_chunk_content(coord) if WorldGenerator else null
			native_data = build_result.to_native_data() if build_result and build_result.is_valid() else _build_surface_chunk_native_data(coord)
			_cache_surface_chunk_payload(coord, z_level, native_data)
	var chunk_biome: BiomeData = _resolve_chunk_biome(coord, z_level)
	var tileset_bundle: Dictionary = _get_or_build_tileset_bundle(chunk_biome)
	var ts_tileset: TileSet = null
	if z_level != 0:
		ts_tileset = tileset_bundle.get("underground_terrain") as TileSet
	else:
		ts_tileset = tileset_bundle.get("terrain") as TileSet
	var overlay_tileset: TileSet = tileset_bundle.get("overlay") as TileSet
	if not ts_tileset or not overlay_tileset:
		return
	var chunk := Chunk.new()
	chunk.setup(
		coord,
		WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		chunk_biome,
		ts_tileset,
		overlay_tileset,
		self
	)
	_sync_chunk_display_position(chunk, _player_chunk)
	var is_player_chunk: bool = (coord == _player_chunk)
	var saved_modifications: Dictionary = _get_saved_chunk_modifications(z_level, coord)
	if z_level != 0:
		chunk.set_underground(true)
	chunk.populate_native(native_data, saved_modifications, is_player_chunk)
	if z_level == 0:
		var flora_result: ChunkFloraResultScript = _get_cached_surface_chunk_flora_result(coord, z_level) if saved_modifications.is_empty() else null
		if flora_result != null:
			chunk.set_flora_result(flora_result)
		elif build_result != null:
			flora_result = _compute_flora_for_chunk(chunk, build_result)
		else:
			flora_result = _compute_flora_for_native_data(chunk, coord, native_data)
		if saved_modifications.is_empty() and flora_result != null:
			_cache_surface_chunk_flora_result(coord, z_level, flora_result)
	if z_level != 0 and _fog_tileset:
		chunk.init_fog_layer(_fog_tileset)
	var z_container: Node2D = _z_containers.get(z_level) as Node2D
	if z_container:
		z_container.add_child(chunk)
	else:
		_chunk_container.add_child(chunk)
	loaded_chunks_for_z[coord] = chunk
	if z_level == _active_z:
		_loaded_chunks = loaded_chunks_for_z
	if not is_player_chunk:
		_redrawing_chunks.append(chunk)
	if _should_track_surface_topology(z_level):
		if _is_native_topology_enabled():
			_native_topology_builder.call("set_chunk", coord, chunk.get_terrain_bytes(), WorldGenerator.balance.chunk_size_tiles)
			_native_topology_dirty = true
		else:
			_mark_topology_dirty()
	EventBus.chunk_loaded.emit(coord)
	WorldPerfProbe.end("ChunkManager._load_chunk %s" % [coord], started_usec)

func _unload_chunk(coord: Vector2i) -> void:
	coord = _canonical_chunk_coord(coord)
	if _is_staged_request(coord, _active_z):
		_clear_staged_request()
	if _is_generating_request(coord, _active_z):
		_gen_coord = Vector2i(999999, 999999)
		_gen_z = 0
	if not _loaded_chunks.has(coord):
		return
	var chunk: Chunk = _loaded_chunks[coord]
	var redraw_idx: int = _redrawing_chunks.find(chunk)
	if redraw_idx >= 0:
		_redrawing_chunks.remove_at(redraw_idx)
	if chunk.is_dirty:
		_saved_chunk_data[_make_chunk_state_key(_active_z, coord)] = chunk.get_modifications()
	chunk.cleanup()
	chunk.queue_free()
	_loaded_chunks.erase(coord)
	if _should_track_surface_topology(_active_z):
		if _is_native_topology_enabled():
			_native_topology_builder.call("remove_chunk", coord)
			_native_topology_dirty = true
		else:
			_mark_topology_dirty()
	EventBus.chunk_unloaded.emit(coord)

func _register_budget_jobs() -> void:
	FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		3.0,
		_tick_loading,
		JOB_STREAMING_LOAD,
		RuntimeWorkTypes.CadenceKind.BACKGROUND,
		RuntimeWorkTypes.ThreadingRole.COMPUTE_THEN_APPLY,
		false,
		"Chunk streaming load"
	)
	FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		2.0,
		_tick_redraws,
		JOB_STREAMING_REDRAW,
		RuntimeWorkTypes.CadenceKind.BACKGROUND,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"Chunk redraw"
	)
	FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_TOPOLOGY,
		2.0,
		_tick_topology,
		JOB_TOPOLOGY,
		RuntimeWorkTypes.CadenceKind.BACKGROUND,
		RuntimeWorkTypes.ThreadingRole.COMPUTE_THEN_APPLY,
		false,
		"Mountain topology rebuild"
	)

## Async staged chunk loading. Generation в WorkerThreadPool, create/finalize на main thread.
## Thread-safety: Strategy A — один worker, read-only access к WorldGenerator.
func _tick_loading() -> bool:
	if _shutdown_in_progress:
		return false
	if _is_boot_in_progress:
		return false
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	if _should_compact_load_queue(_player_chunk, _active_z, load_radius):
		_prune_load_queue(_player_chunk, _active_z, load_radius)
	if _staged_chunk != null:
		if _staged_z != _active_z or not _is_chunk_within_radius(_staged_coord, _player_chunk, load_radius):
			_clear_staged_request()
			return _has_streaming_work()
		_staged_loading_finalize()
		return _has_streaming_work()
	if not _staged_data.is_empty():
		if _staged_z != _active_z or not _is_chunk_within_radius(_staged_coord, _player_chunk, load_radius):
			_clear_staged_request()
			return _has_streaming_work()
		_staged_loading_create()
		return true
	if _gen_task_id >= 0:
		if WorkerThreadPool.is_task_completed(_gen_task_id):
			WorkerThreadPool.wait_for_task_completion(_gen_task_id)
			_gen_task_id = -1
			var coord: Vector2i = _gen_coord
			var request_z: int = _gen_z
			_gen_coord = Vector2i(999999, 999999)
			_gen_z = 0
			_gen_mutex.lock()
			var completed_data: Dictionary = _gen_result
			_gen_result = {}
			_gen_mutex.unlock()
			if not completed_data.is_empty():
				_cache_surface_chunk_payload(coord, request_z, completed_data)
			if request_z != _active_z \
				or (_z_chunks.get(request_z, {}) as Dictionary).has(coord) \
				or not _is_chunk_within_radius(coord, _player_chunk, load_radius):
				return _has_streaming_work()
			_staged_data = completed_data
			_staged_coord = coord
			_staged_z = request_z
			return true
		# Worker generation is already running on a background thread.
		# Returning true here would make FrameBudgetDispatcher spin on polling
		# and burn the full streaming budget without any new main-thread work.
		return false
	if _load_queue.is_empty():
		return false
	var scanned_requests: int = 0
	while not _load_queue.is_empty() and scanned_requests < MAX_LOAD_REQUESTS_SCANNED_PER_TICK:
		scanned_requests += 1
		var request: Dictionary = _load_queue.pop_front()
		if not _is_load_request_relevant(request, _player_chunk, _active_z, load_radius):
			continue
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var request_z: int = int(request.get("z", _active_z))
		if _try_stage_surface_chunk_from_cache(coord, request_z):
			return true
		_submit_async_generate(coord, request_z)
		# Background compute has been queued; wait until a later frame to poll completion.
		return false
	return _has_streaming_work()

func _has_streaming_work() -> bool:
	return not _load_queue.is_empty() or _staged_chunk != null or not _staged_data.is_empty() or _gen_task_id >= 0

func _is_streaming_generation_idle() -> bool:
	return _load_queue.is_empty() and _staged_chunk == null and _staged_data.is_empty() and _gen_task_id < 0

## Отправляет генерацию чанка в WorkerThreadPool. Один worker за раз.
func _submit_async_generate(coord: Vector2i, z_level: int) -> void:
	if _shutdown_in_progress:
		return
	coord = _canonical_chunk_coord(coord)
	_ensure_worker_chunk_builder()
	_gen_coord = coord
	_gen_z = z_level
	_gen_task_id = WorkerThreadPool.add_task(_worker_generate.bind(coord, z_level))

## Выполняется в worker thread. Только чистые данные, никаких Node/scene tree.
## Thread-safety: Strategy A — read-only access к noise instances и balance.
## FastNoiseLite.get_noise_2d() — pure function, no mutable state.
func _worker_generate(coord: Vector2i, z_level: int) -> void:
	if _shutdown_in_progress:
		return
	var data: Dictionary
	if z_level != 0:
		data = _generate_solid_rock_chunk()
	else:
		data = _build_surface_chunk_native_data(coord)
	if _shutdown_in_progress:
		return
	_gen_mutex.lock()
	_gen_result = data
	_gen_mutex.unlock()

func _build_surface_chunk_native_data(coord: Vector2i) -> Dictionary:
	if _worker_chunk_builder != null:
		return _worker_chunk_builder.build_chunk_native_data(coord)
	if not WorldGenerator:
		return {}
	return WorldGenerator.build_chunk_native_data(coord)

func _ensure_worker_chunk_builder() -> void:
	if _worker_chunk_builder != null:
		return
	if WorldGenerator and WorldGenerator.has_method("create_detached_chunk_content_builder"):
		_worker_chunk_builder = WorldGenerator.create_detached_chunk_content_builder()

func _is_load_request_relevant(
	request: Dictionary,
	center: Vector2i,
	active_z_level: int,
	load_radius: int
) -> bool:
	var request_z: int = int(request.get("z", INVALID_Z_LEVEL))
	if request_z != active_z_level:
		return false
	var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
	if (_z_chunks.get(request_z, {}) as Dictionary).has(coord):
		return false
	return _is_chunk_within_radius(coord, center, load_radius)

func _prune_load_queue(center: Vector2i, active_z_level: int, load_radius: int) -> void:
	if _load_queue.is_empty():
		return
	var filtered_queue: Array[Dictionary] = []
	var seen_requests: Dictionary = {}
	for request: Dictionary in _load_queue:
		if not _is_load_request_relevant(request, center, active_z_level, load_radius):
			continue
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var request_z: int = int(request.get("z", INVALID_Z_LEVEL))
		var request_key: Vector3i = Vector3i(coord.x, coord.y, request_z)
		if seen_requests.has(request_key):
			continue
		seen_requests[request_key] = true
		filtered_queue.append({
			"coord": coord,
			"z": request_z,
		})
	filtered_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var coord_a: Vector2i = _canonical_chunk_coord(a.get("coord", Vector2i.ZERO) as Vector2i)
		var coord_b: Vector2i = _canonical_chunk_coord(b.get("coord", Vector2i.ZERO) as Vector2i)
		var dist_a: int = _chunk_manhattan_distance(coord_a, center)
		var dist_b: int = _chunk_manhattan_distance(coord_b, center)
		if dist_a == dist_b:
			if coord_a.y == coord_b.y:
				return coord_a.x < coord_b.x
			return coord_a.y < coord_b.y
		return dist_a < dist_b
	)
	_load_queue = filtered_queue

func _should_compact_load_queue(center: Vector2i, active_z_level: int, load_radius: int) -> bool:
	if _load_queue.is_empty():
		return false
	var max_relevant_requests: int = _resolve_max_relevant_load_queue_size(load_radius)
	if _load_queue.size() > max_relevant_requests + MAX_RELEVANT_LOAD_QUEUE_OVERSCAN:
		return true
	var front_request: Dictionary = _load_queue[0] as Dictionary
	if not _is_load_request_relevant(front_request, center, active_z_level, load_radius):
		return true
	var tail_request: Dictionary = _load_queue[_load_queue.size() - 1] as Dictionary
	if not _is_load_request_relevant(tail_request, center, active_z_level, load_radius):
		return true
	return false

func _resolve_max_relevant_load_queue_size(load_radius: int) -> int:
	var diameter: int = load_radius * 2 + 1
	return maxi(0, diameter * diameter)

func _make_surface_payload_cache_key(coord: Vector2i, z_level: int) -> Vector3i:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	return Vector3i(canonical_coord.x, canonical_coord.y, z_level)

func _has_surface_chunk_cache(coord: Vector2i, z_level: int) -> bool:
	if z_level != 0:
		return false
	return _surface_payload_cache.has(_make_surface_payload_cache_key(coord, z_level))

func _cache_surface_chunk_payload(coord: Vector2i, z_level: int, native_data: Dictionary) -> void:
	if z_level != 0 or native_data.is_empty():
		return
	var cache_key: Vector3i = _make_surface_payload_cache_key(coord, z_level)
	var entry: Dictionary = _surface_payload_cache.get(cache_key, {}) as Dictionary
	entry["native_data"] = _duplicate_native_data(native_data)
	_surface_payload_cache[cache_key] = entry
	_touch_surface_payload_cache_key(cache_key)
	_trim_surface_payload_cache()

func _cache_surface_chunk_flora_result(coord: Vector2i, z_level: int, flora_result: ChunkFloraResultScript) -> void:
	if z_level != 0 or flora_result == null:
		return
	var cache_key: Vector3i = _make_surface_payload_cache_key(coord, z_level)
	var entry: Dictionary = _surface_payload_cache.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return
	entry["flora_result"] = flora_result
	_surface_payload_cache[cache_key] = entry
	_touch_surface_payload_cache_key(cache_key)

func _get_cached_surface_chunk_flora_result(coord: Vector2i, z_level: int) -> ChunkFloraResultScript:
	if z_level != 0:
		return null
	var entry: Dictionary = _surface_payload_cache.get(_make_surface_payload_cache_key(coord, z_level), {}) as Dictionary
	if entry.is_empty():
		return null
	return entry.get("flora_result", null) as ChunkFloraResultScript

func _try_get_surface_payload_cache_native_data(coord: Vector2i, z_level: int, out_native_data: Dictionary) -> bool:
	if z_level != 0:
		return false
	var cache_key: Vector3i = _make_surface_payload_cache_key(coord, z_level)
	var entry: Dictionary = _surface_payload_cache.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return false
	var cached_native_data: Dictionary = entry.get("native_data", {}) as Dictionary
	if cached_native_data.is_empty():
		return false
	out_native_data.assign(_duplicate_native_data(cached_native_data))
	_touch_surface_payload_cache_key(cache_key)
	return true

func _try_stage_surface_chunk_from_cache(coord: Vector2i, z_level: int) -> bool:
	if z_level != 0:
		return false
	var staged_native_data: Dictionary = {}
	if not _try_get_surface_payload_cache_native_data(coord, z_level, staged_native_data):
		return false
	_staged_coord = _canonical_chunk_coord(coord)
	_staged_z = z_level
	_staged_data = staged_native_data
	var saved_modifications: Dictionary = _get_saved_chunk_modifications(z_level, coord)
	_staged_flora_result = _get_cached_surface_chunk_flora_result(coord, z_level) if saved_modifications.is_empty() else null
	return true

func _duplicate_native_data(native_data: Dictionary) -> Dictionary:
	if native_data.is_empty():
		return {}
	return {
		"chunk_coord": native_data.get("chunk_coord", Vector2i.ZERO),
		"canonical_chunk_coord": native_data.get("canonical_chunk_coord", Vector2i.ZERO),
		"base_tile": native_data.get("base_tile", Vector2i.ZERO),
		"chunk_size": int(native_data.get("chunk_size", 0)),
		"terrain": (native_data.get("terrain", PackedByteArray()) as PackedByteArray).duplicate(),
		"height": (native_data.get("height", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"variation": (native_data.get("variation", PackedByteArray()) as PackedByteArray).duplicate(),
		"biome": (native_data.get("biome", PackedByteArray()) as PackedByteArray).duplicate(),
		"flora_density_values": (native_data.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"flora_modulation_values": (native_data.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
	}

func _touch_surface_payload_cache_key(cache_key: Vector3i) -> void:
	var existing_index: int = _surface_payload_cache_lru.find(cache_key)
	if existing_index >= 0:
		_surface_payload_cache_lru.remove_at(existing_index)
	_surface_payload_cache_lru.append(cache_key)

func _trim_surface_payload_cache() -> void:
	while _surface_payload_cache_lru.size() > SURFACE_PAYLOAD_CACHE_LIMIT:
		var evicted_key: Vector3i = _surface_payload_cache_lru.pop_front()
		_surface_payload_cache.erase(evicted_key)

## Фаза 0: только генерация terrain данных. CPU-heavy. Используется ТОЛЬКО в boot.
func _staged_loading_generate(coord: Vector2i) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if _loaded_chunks.has(coord) or not _terrain_tileset or not _overlay_tileset:
		return
	if _active_z != 0:
		_staged_data = _generate_solid_rock_chunk()
	else:
		_staged_data = _build_surface_chunk_native_data(coord)
	_staged_coord = coord
	_staged_z = _active_z
	WorldPerfProbe.end("ChunkStreaming.phase0_generate %s" % [coord], started_usec)

## Фаза 1: создание Chunk node + populate bytes.
func _staged_loading_create() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	var coord: Vector2i = _staged_coord
	var z_level: int = _staged_z
	var native_data: Dictionary = _staged_data
	var staged_flora_result: ChunkFloraResultScript = _staged_flora_result
	_staged_data = {}
	_staged_flora_result = null
	if (_z_chunks.get(z_level, {}) as Dictionary).has(coord):
		_staged_coord = Vector2i(999999, 999999)
		_staged_z = 0
		return
	var chunk_biome: BiomeData = _resolve_chunk_biome(coord, z_level)
	var tileset_bundle: Dictionary = _get_or_build_tileset_bundle(chunk_biome)
	var ts_tileset2: TileSet = null
	if z_level != 0:
		ts_tileset2 = tileset_bundle.get("underground_terrain") as TileSet
	else:
		ts_tileset2 = tileset_bundle.get("terrain") as TileSet
	var overlay_tileset: TileSet = tileset_bundle.get("overlay") as TileSet
	if not ts_tileset2 or not overlay_tileset:
		_staged_coord = Vector2i(999999, 999999)
		_staged_z = 0
		return
	var chunk := Chunk.new()
	chunk.setup(
		coord,
		WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		chunk_biome,
		ts_tileset2,
		overlay_tileset,
		self
	)
	_sync_chunk_display_position(chunk, _player_chunk)
	var saved_modifications: Dictionary = _get_saved_chunk_modifications(z_level, coord)
	if z_level != 0:
		chunk.set_underground(true)
	if z_level == 0 and not _has_surface_chunk_cache(coord, z_level):
		_cache_surface_chunk_payload(coord, z_level, native_data)
	chunk.populate_native(native_data, saved_modifications, false)
	if z_level == 0:
		var flora_result: ChunkFloraResultScript = staged_flora_result if saved_modifications.is_empty() else null
		if flora_result != null:
			chunk.set_flora_result(flora_result)
		else:
			flora_result = _compute_flora_for_native_data(chunk, coord, native_data)
		if saved_modifications.is_empty() and flora_result != null:
			_cache_surface_chunk_flora_result(coord, z_level, flora_result)
	if z_level != 0 and _fog_tileset:
		chunk.init_fog_layer(_fog_tileset)
	_staged_chunk = chunk
	WorldPerfProbe.end("ChunkStreaming.phase1_create %s" % [coord], started_usec)

## Фаза 2: добавить в scene tree + topology + enqueue redraw.
func _staged_loading_finalize() -> void:
	var total_usec: int = WorldPerfProbe.begin()
	var chunk: Chunk = _staged_chunk
	var coord: Vector2i = _staged_coord
	var z_level: int = _staged_z
	_staged_chunk = null
	_staged_coord = Vector2i(999999, 999999)
	_staged_z = 0
	var loaded_chunks_for_z: Dictionary = _z_chunks.get(z_level, {})
	if loaded_chunks_for_z.has(coord):
		chunk.queue_free()
		return
	_sync_chunk_display_position(chunk, _player_chunk)
	var sub_usec: int = WorldPerfProbe.begin()
	var z_container: Node2D = _z_containers.get(z_level) as Node2D
	if z_container:
		z_container.add_child(chunk)
	else:
		_chunk_container.add_child(chunk)
	WorldPerfProbe.end("ChunkStreaming.finalize.add_child %s" % [coord], sub_usec)
	loaded_chunks_for_z[coord] = chunk
	if z_level == _active_z:
		_loaded_chunks = loaded_chunks_for_z
	_redrawing_chunks.append(chunk)
	sub_usec = WorldPerfProbe.begin()
	if _should_track_surface_topology(z_level):
		if _is_native_topology_enabled():
			_native_topology_builder.call("set_chunk", coord, chunk.get_terrain_bytes(), WorldGenerator.balance.chunk_size_tiles)
			_native_topology_dirty = true
		else:
			_mark_topology_dirty()
	WorldPerfProbe.end("ChunkStreaming.finalize.topology %s" % [coord], sub_usec)
	sub_usec = WorldPerfProbe.begin()
	EventBus.chunk_loaded.emit(coord)
	WorldPerfProbe.end("ChunkStreaming.finalize.emit %s" % [coord], sub_usec)
	WorldPerfProbe.end("ChunkStreaming.phase2_finalize %s" % [coord], total_usec)

## Progressive redraw одного шага. Возвращает true если есть ещё работа.
func _tick_redraws() -> bool:
	if _shutdown_in_progress:
		return false
	if _is_boot_in_progress:
		return false
	while not _redrawing_chunks.is_empty():
		var chunk: Chunk = _redrawing_chunks.pop_front()
		if not is_instance_valid(chunk):
			continue
		var rows_per_step: int = 8
		if WorldGenerator and WorldGenerator.balance:
			rows_per_step = WorldGenerator.balance.chunk_redraw_rows_per_frame
		var phase_name: StringName = chunk.get_redraw_phase_name()
		var step_started_usec: int = Time.get_ticks_usec()
		var is_complete: bool = chunk.continue_redraw(rows_per_step)
		var step_ms: float = float(Time.get_ticks_usec() - step_started_usec) / 1000.0
		if step_ms >= 2.0:
			WorldPerfProbe.record("ChunkManager.streaming_redraw_step.%s" % [String(phase_name)], step_ms)
		if not is_complete:
			_redrawing_chunks.append(chunk)
		return not _redrawing_chunks.is_empty()
	return false

## Topology build один шаг. Возвращает true если есть ещё работа.
func _tick_topology() -> bool:
	if _shutdown_in_progress:
		return false
	if _is_boot_in_progress:
		return false
	if _active_z != 0:
		return false
	if _is_native_topology_enabled():
		if _native_topology_dirty and _is_streaming_generation_idle():
			_native_topology_builder.call("ensure_built")
			_native_topology_dirty = false
		return false
	if _has_topology_retired_cleanup():
		if not _is_topology_dirty or not _is_topology_build_in_progress:
			var cleanup_usec: int = WorldPerfProbe.begin()
			var has_more_cleanup: bool = _process_topology_retired_cleanup_step()
			WorldPerfProbe.end("Topology.runtime.cleanup", cleanup_usec)
			if has_more_cleanup or not _is_topology_dirty:
				return has_more_cleanup
	if not _is_topology_dirty:
		return false
	if not _is_topology_build_in_progress:
		if _has_streaming_work():
			return false
		_start_topology_build()
	return _process_topology_build_step()

func _process_chunk_redraws() -> void:
	if _redrawing_chunks.is_empty():
		return
	var rows_per_frame: int = 8
	if WorldGenerator and WorldGenerator.balance:
		rows_per_frame = WorldGenerator.balance.chunk_redraw_rows_per_frame
	var chunk: Chunk = _redrawing_chunks.pop_front()
	if not is_instance_valid(chunk):
		return
	if not chunk.continue_redraw(rows_per_frame):
		_redrawing_chunks.append(chunk)

func _setup_z_containers() -> void:
	for z: int in [ZLevelManager.Z_MIN, 0, ZLevelManager.Z_MAX]:
		var container := Node2D.new()
		container.name = "ZLayer_%d" % z
		container.visible = (z == 0)
		_chunk_container.add_child(container)
		_z_containers[z] = container
		_z_chunks[z] = {}
	_loaded_chunks = _z_chunks[0]

func set_active_z_level(z: int) -> void:
	_active_z = z
	for layer_z: int in _z_containers:
		(_z_containers[layer_z] as Node2D).visible = (layer_z == z)
	_loaded_chunks = _z_chunks.get(z, {})
	var reference_chunk: Vector2i = _player_chunk
	if _player and WorldGenerator:
		reference_chunk = WorldGenerator.world_to_chunk(_player.global_position)
	_sync_loaded_chunk_display_positions(reference_chunk)
	var filtered_queue: Array[Dictionary] = []
	for request: Dictionary in _load_queue:
		if int(request.get("z", INVALID_Z_LEVEL)) == z:
			filtered_queue.append(request)
	_load_queue = filtered_queue
	if _staged_z != z:
		_clear_staged_request()
	_player_chunk = Vector2i(99999, 99999)
	# Force immediate fog update on z-level entry
	if z != 0 and _player:
		_fog_state.clear()
		var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
		var delta: Dictionary = _fog_state.update(player_tile)
		_apply_underground_fog_visible_tiles(delta.get("newly_visible", {}))

func get_active_z_level() -> int:
	return _active_z

## Generate a chunk filled entirely with ROCK (for underground z != 0).
func _generate_solid_rock_chunk() -> Dictionary:
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles
	var terrain := PackedByteArray()
	var height := PackedFloat32Array()
	var variation := PackedByteArray()
	var biome := PackedByteArray()
	terrain.resize(chunk_size * chunk_size)
	height.resize(chunk_size * chunk_size)
	variation.resize(chunk_size * chunk_size)
	biome.resize(chunk_size * chunk_size)
	terrain.fill(TileGenData.TerrainType.ROCK)
	height.fill(0.5)
	variation.fill(0)
	biome.fill(0)
	return {"chunk_size": chunk_size, "terrain": terrain, "height": height, "variation": variation, "biome": biome}

## Create a tiny underground pocket at z=-1. Ensures ALL needed chunks are loaded
## and sets specified tiles to MINED_FLOOR. Called from debug path only.
func ensure_underground_pocket(center_tile: Vector2i, pocket_tiles: Array) -> void:
	var prev_z: int = _active_z
	if _active_z != -1:
		set_active_z_level(-1)
	# Collect all chunk coords needed: pocket tiles + 1-tile wall ring around them
	var needed_coords: Dictionary = {}
	for tile_pos: Variant in pocket_tiles:
		var t: Vector2i = _canonical_tile(tile_pos as Vector2i)
		needed_coords[WorldGenerator.tile_to_chunk(t)] = true
		for offset: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
				Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			needed_coords[WorldGenerator.tile_to_chunk(_offset_tile(t, offset))] = true
	# Ensure all needed chunks are loaded
	for coord: Vector2i in needed_coords:
		if _loaded_chunks.has(coord):
			continue
		var data: Dictionary = _generate_solid_rock_chunk()
		var chunk_biome: BiomeData = _resolve_chunk_biome(coord, -1)
		var tileset_bundle: Dictionary = _get_or_build_tileset_bundle(chunk_biome)
		var ug_ts: TileSet = tileset_bundle.get("underground_terrain") as TileSet
		var overlay_tileset: TileSet = tileset_bundle.get("overlay") as TileSet
		if not ug_ts or not overlay_tileset:
			continue
		var chunk := Chunk.new()
		chunk.setup(coord, WorldGenerator.balance.tile_size, WorldGenerator.balance.chunk_size_tiles,
			chunk_biome, ug_ts, overlay_tileset, self)
		chunk.set_underground(true)
		chunk.populate_native(data, {}, false)
		if _fog_tileset:
			chunk.init_fog_layer(_fog_tileset)
		var z_container: Node2D = _z_containers.get(-1) as Node2D
		if z_container:
			z_container.add_child(chunk)
		_loaded_chunks[coord] = chunk
		chunk._begin_progressive_redraw()
	# Mine the pocket tiles — group by chunk for correct local coords
	var dirty_by_chunk: Dictionary = {}
	for tile_pos: Variant in pocket_tiles:
		var t: Vector2i = _canonical_tile(tile_pos as Vector2i)
		var cc: Vector2i = WorldGenerator.tile_to_chunk(t)
		var ch: Chunk = _loaded_chunks.get(cc) as Chunk
		if not ch:
			continue
		var local: Vector2i = ch.global_to_local(t)
		if ch.get_terrain_type_at(local) == TileGenData.TerrainType.ROCK:
			ch._set_terrain_type(local, TileGenData.TerrainType.MINED_FLOOR)
			if not dirty_by_chunk.has(cc):
				dirty_by_chunk[cc] = {}
			(dirty_by_chunk[cc] as Dictionary)[local] = true
			# Mark 8 neighbors dirty (may be in different chunks)
			for offset: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
					Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
				var n_global: Vector2i = _offset_tile(t, offset)
				var n_cc: Vector2i = WorldGenerator.tile_to_chunk(n_global)
				var n_ch: Chunk = _loaded_chunks.get(n_cc) as Chunk
				if n_ch:
					var n_local: Vector2i = n_ch.global_to_local(n_global)
					if n_ch._is_inside(n_local):
						if not dirty_by_chunk.has(n_cc):
							dirty_by_chunk[n_cc] = {}
						(dirty_by_chunk[n_cc] as Dictionary)[n_local] = true
	# Redraw dirty tiles per chunk
	for cc: Vector2i in dirty_by_chunk:
		var ch: Chunk = _loaded_chunks.get(cc) as Chunk
		if ch:
			ch._redraw_dirty_tiles(dirty_by_chunk[cc])
	# Restore original z
	if prev_z != -1:
		set_active_z_level(prev_z)

func _collect_chunk_coords_from_tiles(tile_map: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tile_pos: Vector2i in tile_map:
		result[WorldGenerator.tile_to_chunk(tile_pos)] = true
	return result

func _group_tiles_by_chunk(tile_map: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tile_pos: Vector2i in tile_map:
		var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(tile_pos)
		if not result.has(chunk_coord):
			result[chunk_coord] = {}
		(result[chunk_coord] as Dictionary)[tile_pos] = true
	return result

func _to_chunk_coord_set(chunk_coords: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in chunk_coords:
		if value is Vector2i:
			result[value] = true
	return result

func _mark_topology_dirty() -> void:
	_is_topology_dirty = true
	_topology_build_start_phase = TOPOLOGY_START_NONE
	_topology_start_chunk_keys = []
	_topology_start_chunk_index = 0
	_is_topology_build_in_progress = false

func _ensure_topology_current() -> void:
	if _active_z != 0:
		return
	if _is_native_topology_enabled():
		_native_topology_builder.call("ensure_built")
		return
	if not _is_topology_dirty:
		return
	_rebuild_loaded_mountain_topology()
	_is_topology_dirty = false
	_is_topology_build_in_progress = false

func _process_topology_build() -> void:
	if _is_native_topology_enabled():
		if _native_topology_dirty and _load_queue.is_empty() and _redrawing_chunks.is_empty():
			_native_topology_builder.call("ensure_built")
			_native_topology_dirty = false
		return
	if not _is_topology_dirty:
		return
	if not _is_topology_build_in_progress:
		_start_topology_build()
	var started_usec: int = Time.get_ticks_usec()
	var budget_ms: float = 2.0
	if WorldGenerator and WorldGenerator.balance:
		budget_ms = WorldGenerator.balance.mountain_topology_build_budget_ms
	while float(Time.get_ticks_usec() - started_usec) / 1000.0 < budget_ms:
		if not _process_topology_build_step():
			break

func _start_topology_build() -> void:
	_is_topology_build_in_progress = true
	_topology_start_chunk_keys = []
	for coord: Vector2i in _loaded_chunks:
		_topology_start_chunk_keys.append(coord)
	_topology_build_start_phase = TOPOLOGY_START_RESET_SCAN_COORDS
	_topology_start_chunk_index = 0
	_topology_scan_chunk_index = 0
	_topology_scan_local_x = 0
	_topology_scan_local_y = 0
	_topology_build_commit_phase = TOPOLOGY_COMMIT_NONE

func _advance_topology_build_start_step() -> void:
	match _topology_build_start_phase:
		TOPOLOGY_START_RESET_SCAN_COORDS:
			_topology_scan_chunk_coords = []
			_topology_build_start_phase = TOPOLOGY_START_COLLECT_CHUNKS
		TOPOLOGY_START_COLLECT_CHUNKS:
			var end_index: int = mini(
				_topology_start_chunk_index + TOPOLOGY_START_CHUNKS_PER_STEP,
				_topology_start_chunk_keys.size()
			)
			for chunk_index: int in range(_topology_start_chunk_index, end_index):
				_topology_scan_chunk_coords.append(_topology_start_chunk_keys[chunk_index])
			_topology_start_chunk_index = end_index
			if _topology_start_chunk_index >= _topology_start_chunk_keys.size():
				_topology_build_start_phase = TOPOLOGY_START_RESET_VISITED
		TOPOLOGY_START_RESET_VISITED:
			_queue_retired_topology_dictionary(_topology_build_visited)
			_topology_build_visited = {}
			_topology_build_start_phase = TOPOLOGY_START_RESET_KEY_BY_TILE
		TOPOLOGY_START_RESET_KEY_BY_TILE:
			_topology_build_key_by_tile = {}
			_topology_build_start_phase = TOPOLOGY_START_RESET_TILES_BY_KEY
		TOPOLOGY_START_RESET_TILES_BY_KEY:
			_topology_build_tiles_by_key = {}
			_topology_build_start_phase = TOPOLOGY_START_RESET_OPEN_TILES_BY_KEY
		TOPOLOGY_START_RESET_OPEN_TILES_BY_KEY:
			_topology_build_open_tiles_by_key = {}
			_topology_build_start_phase = TOPOLOGY_START_RESET_COMPONENT
		TOPOLOGY_START_RESET_COMPONENT:
			_clear_topology_component_state()
			_topology_start_chunk_keys = []
			_topology_start_chunk_index = 0
			_topology_build_start_phase = TOPOLOGY_START_NONE
		_:
			_topology_start_chunk_keys = []
			_topology_start_chunk_index = 0
			_topology_build_start_phase = TOPOLOGY_START_NONE

func _process_topology_build_step() -> bool:
	if _topology_build_start_phase != TOPOLOGY_START_NONE:
		var start_usec: int = WorldPerfProbe.begin()
		_advance_topology_build_start_step()
		WorldPerfProbe.end("Topology.runtime.start", start_usec)
		return true
	if _topology_component_finalize_index < _topology_component_tiles_list.size():
		var finalize_usec: int = WorldPerfProbe.begin()
		_finalize_topology_component_step()
		WorldPerfProbe.end("Topology.runtime.finalize", finalize_usec)
		return true
	if _topology_component_queue_index < _topology_component_queue.size():
		var expand_usec: int = WorldPerfProbe.begin()
		_process_topology_component_step()
		WorldPerfProbe.end("Topology.runtime.expand", expand_usec)
		return true
	if _topology_build_commit_phase != TOPOLOGY_COMMIT_NONE:
		var commit_usec: int = WorldPerfProbe.begin()
		var has_more_commit: bool = _process_topology_build_commit_step()
		WorldPerfProbe.end("Topology.runtime.commit", commit_usec)
		return has_more_commit
	var scan_usec: int = WorldPerfProbe.begin()
	var scan_result: Dictionary = _find_next_topology_seed()
	WorldPerfProbe.end("Topology.runtime.scan", scan_usec)
	var next_seed: Vector2i = scan_result.get("seed", Vector2i(999999, 999999))
	if next_seed != Vector2i(999999, 999999):
		_begin_topology_component(next_seed)
		return true
	if not bool(scan_result.get("complete", false)):
		return true
	_begin_topology_build_commit()
	return true

func _find_next_topology_seed() -> Dictionary:
	var scan_budget: int = _resolve_topology_scan_tile_budget()
	var scanned_tiles: int = 0
	while scanned_tiles < scan_budget and _topology_scan_chunk_index < _topology_scan_chunk_coords.size():
		var chunk_coord: Vector2i = _topology_scan_chunk_coords[_topology_scan_chunk_index]
		var chunk: Chunk = _loaded_chunks.get(chunk_coord)
		if not chunk:
			_topology_scan_chunk_index += 1
			_topology_scan_local_x = 0
			_topology_scan_local_y = 0
			continue
		var chunk_size: int = chunk.get_chunk_size()
		while _topology_scan_local_y < chunk_size:
			while _topology_scan_local_x < chunk_size:
				var local_tile: Vector2i = Vector2i(_topology_scan_local_x, _topology_scan_local_y)
				_topology_scan_local_x += 1
				scanned_tiles += 1
				var terrain_type: int = chunk.get_terrain_type_at(local_tile)
				if not _is_mountain_topology_tile(terrain_type):
					continue
				var global_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_tile)
				if _topology_build_visited.has(global_tile):
					continue
				return {"seed": global_tile, "complete": false}
			_topology_scan_local_x = 0
			_topology_scan_local_y += 1
		_topology_scan_chunk_index += 1
		_topology_scan_local_x = 0
		_topology_scan_local_y = 0
	return {
		"seed": Vector2i(999999, 999999),
		"complete": _topology_scan_chunk_index >= _topology_scan_chunk_coords.size(),
	}

func _begin_topology_component(start_tile: Vector2i) -> void:
	_clear_topology_component_state()
	_topology_component_queue = [start_tile]
	_topology_component_queue_index = 0
	_topology_component_key = start_tile
	_topology_build_visited[start_tile] = true

func _process_topology_component_step() -> void:
	var tile_budget: int = _resolve_topology_scan_tile_budget()
	var processed_tiles: int = 0
	while processed_tiles < tile_budget and _topology_component_queue_index < _topology_component_queue.size():
		var current: Vector2i = _topology_component_queue[_topology_component_queue_index]
		_topology_component_queue_index += 1
		processed_tiles += 1
		_topology_component_tiles[current] = true
		_topology_component_tiles_list.append(current)
		var current_chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(current)
		if current.y < _topology_component_key.y or (current.y == _topology_component_key.y and current.x < _topology_component_key.x):
			_topology_component_key = current
		var current_chunk: Chunk = _loaded_chunks.get(current_chunk_coord)
		if not current_chunk:
			continue
		var chunk_size: int = current_chunk.get_chunk_size()
		var current_local: Vector2i = _tile_to_local(current, current_chunk_coord, chunk_size)
		var current_type: int = current_chunk.get_terrain_type_at(current_local)
		if current_type == TileGenData.TerrainType.MINED_FLOOR or current_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			_topology_component_open_tiles[current] = true
		for dir: Vector2i in _CARDINAL_DIRS:
			var next_tile: Vector2i = _offset_tile(current, dir)
			if _topology_build_visited.has(next_tile):
				continue
			var next_chunk_coord: Vector2i = current_chunk_coord
			var next_local: Vector2i = current_local + dir
			var next_chunk: Chunk = current_chunk
			if next_local.x < 0:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.LEFT)
				next_local.x += chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.x >= chunk_size:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.RIGHT)
				next_local.x -= chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.y < 0:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.UP)
				next_local.y += chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.y >= chunk_size:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.DOWN)
				next_local.y -= chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			if not next_chunk:
				continue
			if not _is_mountain_topology_tile(next_chunk.get_terrain_type_at(next_local)):
				continue
			_topology_build_visited[next_tile] = true
			_topology_component_queue.append(next_tile)
	if _topology_component_queue_index >= _topology_component_queue.size():
		var finalize_prepare_usec: int = WorldPerfProbe.begin()
		_begin_topology_component_finalize()
		WorldPerfProbe.end("Topology.runtime.finalize_prepare", finalize_prepare_usec)

func _begin_topology_component_finalize() -> void:
	_topology_component_finalize_index = 0

func _finalize_topology_component_step() -> void:
	var tile_budget: int = _resolve_topology_finalize_tile_budget()
	var end_index: int = mini(
		_topology_component_finalize_index + tile_budget,
		_topology_component_tiles_list.size()
	)
	for tile_index: int in range(_topology_component_finalize_index, end_index):
		var tile_pos: Vector2i = _topology_component_tiles_list[tile_index]
		_topology_build_key_by_tile[tile_pos] = _topology_component_key
	_topology_component_finalize_index = end_index
	if _topology_component_finalize_index < _topology_component_tiles_list.size():
		return
	_topology_build_tiles_by_key[_topology_component_key] = _topology_component_tiles
	_topology_build_open_tiles_by_key[_topology_component_key] = _topology_component_open_tiles
	_clear_topology_component_state()

func _clear_topology_component_state() -> void:
	_topology_component_queue = []
	_topology_component_queue_index = 0
	_topology_component_tiles = {}
	_topology_component_open_tiles = {}
	_topology_component_tiles_by_chunk = {}
	_topology_component_open_tiles_by_chunk = {}
	_topology_component_key = Vector2i(999999, 999999)
	_topology_component_tiles_list = []
	_topology_component_finalize_index = 0

func _begin_topology_build_commit() -> void:
	_topology_build_commit_phase = TOPOLOGY_COMMIT_KEY_BY_TILE

func _process_topology_build_commit_step() -> bool:
	match _topology_build_commit_phase:
		TOPOLOGY_COMMIT_KEY_BY_TILE:
			_queue_retired_topology_dictionary(_mountain_key_by_tile)
			_mountain_key_by_tile = _topology_build_key_by_tile
			_topology_build_commit_phase = TOPOLOGY_COMMIT_TILES_BY_KEY
		TOPOLOGY_COMMIT_TILES_BY_KEY:
			_queue_retired_topology_dictionary(_mountain_tiles_by_key)
			_mountain_tiles_by_key = _topology_build_tiles_by_key
			_topology_build_commit_phase = TOPOLOGY_COMMIT_OPEN_TILES_BY_KEY
		TOPOLOGY_COMMIT_OPEN_TILES_BY_KEY:
			_queue_retired_topology_dictionary(_mountain_open_tiles_by_key)
			_mountain_open_tiles_by_key = _topology_build_open_tiles_by_key
			_topology_build_commit_phase = TOPOLOGY_COMMIT_NONE
			_finish_topology_build()
			return false
		_:
			_topology_build_commit_phase = TOPOLOGY_COMMIT_NONE
			_finish_topology_build()
			return false
	return true

func _resolve_topology_scan_tile_budget() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.mountain_topology_scan_tiles_per_step)
	return 128

func _resolve_topology_finalize_tile_budget() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.mountain_topology_finalize_tiles_per_step)
	return 128

func _has_topology_retired_cleanup() -> bool:
	return not _topology_retired_dicts.is_empty()

func _queue_retired_topology_dictionary(dict_value: Dictionary) -> void:
	if dict_value.is_empty():
		return
	_topology_retired_dicts.append({
		"target": dict_value,
		"keys": dict_value.keys(),
		"index": 0,
	})

func _process_topology_retired_cleanup_step() -> bool:
	while not _topology_retired_dicts.is_empty():
		var retired: Dictionary = _topology_retired_dicts[0] as Dictionary
		var target: Dictionary = retired.get("target", {}) as Dictionary
		var keys: Array = retired.get("keys", []) as Array
		var index: int = retired.get("index", 0) as int
		if target.is_empty() or index >= keys.size():
			target.clear()
			_topology_retired_dicts.remove_at(0)
			continue
		var end_index: int = mini(index + TOPOLOGY_RETIRED_DICT_KEYS_PER_STEP, keys.size())
		for key_index: int in range(index, end_index):
			target.erase(keys[key_index])
		retired["index"] = end_index
		_topology_retired_dicts[0] = retired
		if target.is_empty() or end_index >= keys.size():
			target.clear()
			_topology_retired_dicts.remove_at(0)
		return not _topology_retired_dicts.is_empty()
	return false

func _finish_topology_build() -> void:
	_topology_build_commit_phase = TOPOLOGY_COMMIT_NONE
	_topology_build_start_phase = TOPOLOGY_START_NONE
	_topology_start_chunk_keys = []
	_topology_start_chunk_index = 0
	_is_topology_dirty = false
	_is_topology_build_in_progress = false

func _rebuild_loaded_mountain_topology() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	var perf_label: String = "ChunkManager._rebuild_loaded_mountain_topology.runtime"
	if _is_boot_in_progress:
		perf_label = "ChunkManager._rebuild_loaded_mountain_topology.boot"
	if _is_native_topology_enabled():
		_native_topology_builder.call("ensure_built")
		WorldPerfProbe.end(perf_label, started_usec)
		return
	_mountain_key_by_tile.clear()
	_mountain_tiles_by_key.clear()
	_mountain_open_tiles_by_key.clear()
	_mountain_tiles_by_key_by_chunk.clear()
	_mountain_open_tiles_by_key_by_chunk.clear()
	var visited: Dictionary = {}
	for chunk_coord: Vector2i in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[chunk_coord]
		var chunk_size: int = chunk.get_chunk_size()
		for local_y: int in range(chunk_size):
			for local_x: int in range(chunk_size):
				var local_tile: Vector2i = Vector2i(local_x, local_y)
				var terrain_type: int = chunk.get_terrain_type_at(local_tile)
				if not _is_mountain_topology_tile(terrain_type):
					continue
				var global_tile: Vector2i = _chunk_local_to_tile(chunk_coord, Vector2i(local_x, local_y))
				if visited.has(global_tile):
					continue
				_build_mountain_component(global_tile, visited)
	WorldPerfProbe.end(perf_label, started_usec)

func _build_mountain_component(start_tile: Vector2i, visited: Dictionary) -> void:
	var queue: Array[Vector2i] = [start_tile]
	var queue_index: int = 0
	var component_tiles: Dictionary = {}
	var component_open_tiles: Dictionary = {}
	var component_tiles_by_chunk: Dictionary = {}
	var component_open_tiles_by_chunk: Dictionary = {}
	var component_key: Vector2i = start_tile
	visited[start_tile] = true
	while queue_index < queue.size():
		var current: Vector2i = queue[queue_index]
		queue_index += 1
		component_tiles[current] = true
		var current_chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(current)
		if not component_tiles_by_chunk.has(current_chunk_coord):
			component_tiles_by_chunk[current_chunk_coord] = {}
		(component_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
		if current.y < component_key.y or (current.y == component_key.y and current.x < component_key.x):
			component_key = current
		var current_chunk: Chunk = _loaded_chunks.get(current_chunk_coord)
		if not current_chunk:
			continue
		var chunk_size: int = current_chunk.get_chunk_size()
		var current_local: Vector2i = _tile_to_local(current, current_chunk_coord, chunk_size)
		var current_type: int = current_chunk.get_terrain_type_at(current_local)
		if current_type == TileGenData.TerrainType.MINED_FLOOR or current_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			component_open_tiles[current] = true
			if not component_open_tiles_by_chunk.has(current_chunk_coord):
				component_open_tiles_by_chunk[current_chunk_coord] = {}
			(component_open_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
		for dir: Vector2i in _CARDINAL_DIRS:
			var next_tile: Vector2i = _offset_tile(current, dir)
			if visited.has(next_tile):
				continue
			var next_chunk_coord: Vector2i = current_chunk_coord
			var next_local: Vector2i = current_local + dir
			var next_chunk: Chunk = current_chunk
			if next_local.x < 0:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.LEFT)
				next_local.x += chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.x >= chunk_size:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.RIGHT)
				next_local.x -= chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.y < 0:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.UP)
				next_local.y += chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			elif next_local.y >= chunk_size:
				next_chunk_coord = _offset_chunk_coord(current_chunk_coord, Vector2i.DOWN)
				next_local.y -= chunk_size
				next_chunk = _loaded_chunks.get(next_chunk_coord)
			if not next_chunk:
				continue
			if not _is_mountain_topology_tile(next_chunk.get_terrain_type_at(next_local)):
				continue
			visited[next_tile] = true
			queue.append(next_tile)
	for tile_pos: Vector2i in component_tiles:
		_mountain_key_by_tile[tile_pos] = component_key
	_mountain_tiles_by_key[component_key] = component_tiles
	_mountain_open_tiles_by_key[component_key] = component_open_tiles
	_mountain_tiles_by_key_by_chunk[component_key] = component_tiles_by_chunk
	_mountain_open_tiles_by_key_by_chunk[component_key] = component_open_tiles_by_chunk

func _on_mountain_tile_changed(tile_pos: Vector2i, old_type: int, new_type: int) -> void:
	if _active_z != 0:
		return
	tile_pos = _canonical_tile(tile_pos)
	if not (_is_mountain_topology_tile(old_type) or _is_mountain_topology_tile(new_type)):
		return
	var started_usec: int = WorldPerfProbe.begin()
	if _is_native_topology_enabled():
		_native_topology_builder.call("update_tile", tile_pos, new_type)
		WorldPerfProbe.end("ChunkManager._on_mountain_tile_changed", started_usec)
		return
	_incremental_topology_patch(tile_pos, new_type)
	WorldPerfProbe.end("ChunkManager._on_mountain_tile_changed", started_usec)

func _should_track_surface_topology(z_level: int) -> bool:
	return z_level == 0

## Инкрементальный патч топологии для 1 тайла. O(9) вместо full BFS.
## При подозрении на split компонента — ставит dirty для background rebuild.
func _incremental_topology_patch(tile_pos: Vector2i, new_type: int) -> void:
	tile_pos = _canonical_tile(tile_pos)
	var mountain_key: Vector2i = _mountain_key_by_tile.get(tile_pos, Vector2i(999999, 999999))
	if mountain_key == Vector2i(999999, 999999):
		mountain_key = _find_neighbor_key(tile_pos)
	if mountain_key == Vector2i(999999, 999999):
		return
	var tile_chunk: Vector2i = WorldGenerator.tile_to_chunk(tile_pos)
	_ensure_key_structures(mountain_key, tile_chunk)
	_mountain_key_by_tile[tile_pos] = mountain_key
	(_mountain_tiles_by_key[mountain_key] as Dictionary)[tile_pos] = true
	((_mountain_tiles_by_key_by_chunk[mountain_key] as Dictionary)[tile_chunk] as Dictionary)[tile_pos] = true
	_update_tile_open_status(tile_pos, new_type, mountain_key, tile_chunk)
	var rock_neighbor_count: int = 0
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var neighbor: Vector2i = _offset_tile(tile_pos, dir)
		var neighbor_key: Vector2i = _mountain_key_by_tile.get(neighbor, Vector2i(999999, 999999))
		if neighbor_key == Vector2i(999999, 999999):
			continue
		var neighbor_chunk: Chunk = get_chunk_at_tile(neighbor)
		if not neighbor_chunk:
			continue
		var neighbor_local: Vector2i = neighbor_chunk.global_to_local(neighbor)
		var neighbor_type: int = neighbor_chunk.get_terrain_type_at(neighbor_local)
		if neighbor_type == TileGenData.TerrainType.ROCK:
			rock_neighbor_count += 1
		var neighbor_chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(neighbor)
		_update_tile_open_status(neighbor, neighbor_type, neighbor_key, neighbor_chunk_coord)
	if new_type != TileGenData.TerrainType.ROCK and rock_neighbor_count >= 2:
		_mark_topology_dirty()

## Ищет mountain_key среди 4 кардинальных соседей. O(4).
func _find_neighbor_key(tile_pos: Vector2i) -> Vector2i:
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var key: Vector2i = _mountain_key_by_tile.get(_offset_tile(tile_pos, dir), Vector2i(999999, 999999))
		if key != Vector2i(999999, 999999):
			return key
	return Vector2i(999999, 999999)

## Гарантирует наличие структур для ключа и чанка.
func _ensure_key_structures(mountain_key: Vector2i, tile_chunk: Vector2i) -> void:
	if not _mountain_tiles_by_key.has(mountain_key):
		_mountain_tiles_by_key[mountain_key] = {}
	if not _mountain_tiles_by_key_by_chunk.has(mountain_key):
		_mountain_tiles_by_key_by_chunk[mountain_key] = {}
	if not (_mountain_tiles_by_key_by_chunk[mountain_key] as Dictionary).has(tile_chunk):
		(_mountain_tiles_by_key_by_chunk[mountain_key] as Dictionary)[tile_chunk] = {}
	if not _mountain_open_tiles_by_key.has(mountain_key):
		_mountain_open_tiles_by_key[mountain_key] = {}
	if not _mountain_open_tiles_by_key_by_chunk.has(mountain_key):
		_mountain_open_tiles_by_key_by_chunk[mountain_key] = {}
	if not (_mountain_open_tiles_by_key_by_chunk[mountain_key] as Dictionary).has(tile_chunk):
		(_mountain_open_tiles_by_key_by_chunk[mountain_key] as Dictionary)[tile_chunk] = {}

## Обновляет open/closed статус одного тайла в топологии.
func _update_tile_open_status(tile_pos: Vector2i, terrain_type: int, mountain_key: Vector2i, tile_chunk: Vector2i) -> void:
	_ensure_key_structures(mountain_key, tile_chunk)
	var open_tiles: Dictionary = _mountain_open_tiles_by_key[mountain_key] as Dictionary
	var chunk_open: Dictionary = (_mountain_open_tiles_by_key_by_chunk[mountain_key] as Dictionary)[tile_chunk] as Dictionary
	if terrain_type == TileGenData.TerrainType.MINED_FLOOR or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		open_tiles[tile_pos] = true
		chunk_open[tile_pos] = true
	else:
		open_tiles.erase(tile_pos)
		chunk_open.erase(tile_pos)

func _is_mountain_topology_tile(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.ROCK \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _is_local_underground_zone_open_tile(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE
