class_name ChunkManager
extends Node2D

## Менеджер чанков мира.
## Загружает чанки, рендерит землю/горы и выполняет mining горной породы.

var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(99999, 99999)
var _player: Node2D = null
var _chunk_container: Node2D = null
var _load_queue: Array[Vector2i] = []
var _redrawing_chunks: Array[Chunk] = []
var _saved_chunk_data: Dictionary = {}
var _terrain_tileset: TileSet = null
var _overlay_tileset: TileSet = null
var _initialized: bool = false
var _active_z: int = 0
var _z_containers: Dictionary = {}
var _z_chunks: Dictionary = {}
var _active_mountain_key: Vector2i = Vector2i(999999, 999999)
var _active_mountain_chunk_coords: Dictionary = {}
var _mountain_key_by_tile: Dictionary = {}
var _mountain_tiles_by_key: Dictionary = {}
var _mountain_open_tiles_by_key: Dictionary = {}
var _mountain_tiles_by_key_by_chunk: Dictionary = {}
var _mountain_open_tiles_by_key_by_chunk: Dictionary = {}
var _is_topology_dirty: bool = false
var _native_topology_builder: RefCounted = null
var _native_topology_active: bool = false
var _native_topology_dirty: bool = false
var _is_topology_build_in_progress: bool = false
var _is_boot_in_progress: bool = false
var _staged_chunk: Chunk = null
var _staged_coord: Vector2i = Vector2i(999999, 999999)
var _staged_data: Dictionary = {}  ## Native data между фазами
## --- Async generation (runtime only) ---
var _gen_task_id: int = -1  ## WorkerThreadPool task ID, -1 = нет активной задачи
var _gen_coord: Vector2i = Vector2i(999999, 999999)  ## Координата в процессе генерации
var _gen_result: Dictionary = {}  ## Результат от worker thread
var _gen_mutex: Mutex = Mutex.new()
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
var _topology_component_queue: Array[Vector2i] = []
var _topology_component_queue_index: int = 0
var _topology_component_tiles: Dictionary = {}
var _topology_component_open_tiles: Dictionary = {}
var _topology_component_tiles_by_chunk: Dictionary = {}
var _topology_component_open_tiles_by_chunk: Dictionary = {}
var _topology_component_key: Vector2i = Vector2i(999999, 999999)

func _ready() -> void:
	add_to_group("chunk_manager")
	_chunk_container = Node2D.new()
	_chunk_container.name = "Chunks"
	add_child(_chunk_container)
	_setup_z_containers()
	call_deferred("_deferred_init")

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
			coords.append(Vector2i(center.x + dx, center.y + dy))
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absi(a.x - center.x) + absi(a.y - center.y) < absi(b.x - center.x) + absi(b.y - center.y)
	)
	var total: int = coords.size()
	for i: int in range(total):
		var coord: Vector2i = coords[i]
		if not _loaded_chunks.has(coord):
			_load_chunk(coord)
			var chunk: Chunk = _loaded_chunks.get(coord)
			if chunk and not chunk.is_redraw_complete():
				chunk.continue_redraw(64)
			var redraw_idx: int = _redrawing_chunks.find(chunk)
			if redraw_idx >= 0:
				_redrawing_chunks.remove_at(redraw_idx)
		var pct: float = float(i + 1) / float(total) * 80.0
		progress_callback.call(pct, "Генерация местности... (%d/%d)" % [i + 1, total])
		await get_tree().process_frame
	progress_callback.call(85.0, "Построение карты гор...")
	await get_tree().process_frame
	if _is_native_topology_enabled():
		_native_topology_builder.call("ensure_built")
		_native_topology_dirty = false
	else:
		_ensure_topology_current()
	progress_callback.call(95.0, "Высадка...")
	await get_tree().process_frame
	_is_boot_in_progress = false

func set_saved_data(data: Dictionary) -> void:
	_saved_chunk_data = data

func get_save_data() -> Dictionary:
	var result: Dictionary = _saved_chunk_data.duplicate()
	for coord: Vector2i in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[coord]
		if chunk.is_dirty:
			result[coord] = chunk.get_modifications()
	return result

func is_tile_loaded(gt: Vector2i) -> bool:
	return _loaded_chunks.has(WorldGenerator.tile_to_chunk(gt))

func get_chunk_at_tile(gt: Vector2i) -> Chunk:
	return _loaded_chunks.get(WorldGenerator.tile_to_chunk(gt))

func get_chunk(cc: Vector2i) -> Chunk:
	return _loaded_chunks.get(cc)

func get_terrain_type_at_global(tile_pos: Vector2i) -> int:
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(tile_pos)
	var loaded_chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if loaded_chunk:
		return loaded_chunk.get_terrain_type_at(loaded_chunk.global_to_local(tile_pos))
	var saved_chunk_state: Dictionary = _saved_chunk_data.get(chunk_coord, {}) as Dictionary
	var local_tile: Vector2i = Vector2i(
		tile_pos.x - chunk_coord.x * WorldGenerator.balance.chunk_size_tiles,
		tile_pos.y - chunk_coord.y * WorldGenerator.balance.chunk_size_tiles
	)
	var tile_state: Dictionary = saved_chunk_state.get(local_tile, {}) as Dictionary
	if tile_state.has("terrain"):
		return int(tile_state["terrain"])
	if WorldGenerator and WorldGenerator._is_initialized:
		return WorldGenerator.get_tile_data(tile_pos.x, tile_pos.y).terrain
	return TileGenData.TerrainType.GROUND

func get_loaded_chunks() -> Dictionary:
	return _loaded_chunks

func is_topology_ready() -> bool:
	if _is_native_topology_enabled():
		return not _native_topology_dirty
	return not _is_topology_dirty and not _is_topology_build_in_progress

func get_mountain_key_at_tile(tile_pos: Vector2i) -> Vector2i:
	if _is_native_topology_enabled():
		return _native_topology_builder.call("get_mountain_key_at_tile", tile_pos) as Vector2i
	return _mountain_key_by_tile.get(tile_pos, Vector2i(999999, 999999))

func get_mountain_tiles(mountain_key: Vector2i) -> Dictionary:
	if _is_native_topology_enabled():
		return _native_topology_builder.call("get_mountain_tiles", mountain_key) as Dictionary
	return _mountain_tiles_by_key.get(mountain_key, {}) as Dictionary

func get_mountain_open_tiles(mountain_key: Vector2i) -> Dictionary:
	if _is_native_topology_enabled():
		return _native_topology_builder.call("get_mountain_open_tiles", mountain_key) as Dictionary
	return _mountain_open_tiles_by_key.get(mountain_key, {}) as Dictionary

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
	_on_mountain_tile_changed(tile_pos, int(result["old_type"]), int(result["new_type"]))
	EventBus.mountain_tile_mined.emit(tile_pos, int(result["old_type"]), int(result["new_type"]))
	WorldPerfProbe.end("ChunkManager.try_harvest_at_world", started_usec)
	return {
		"item_id": str(WorldGenerator.balance.rock_drop_item_id),
		"amount": WorldGenerator.balance.rock_drop_amount,
	}

func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var chunk: Chunk = get_chunk_at_tile(tile_pos)
	if not chunk:
		return false
	return chunk.get_terrain_type_at(chunk.global_to_local(tile_pos)) == TileGenData.TerrainType.ROCK

func is_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var chunk: Chunk = get_chunk_at_tile(tile_pos)
	if not chunk:
		return WorldGenerator.is_walkable_at(world_pos)
	return chunk.get_terrain_type_at(chunk.global_to_local(tile_pos)) != TileGenData.TerrainType.ROCK

## Устанавливает активный mountain key и возвращает список чанков,
## у которых должен обновиться cheap roof visual state.
func set_active_mountain_key(mountain_key: Vector2i = Vector2i(999999, 999999)) -> Array[Vector2i]:
	if mountain_key == _active_mountain_key:
		return []
	var previous_chunks: Dictionary = {}
	for coord: Vector2i in _active_mountain_chunk_coords:
		previous_chunks[coord] = true
	_active_mountain_key = mountain_key
	if _is_native_topology_enabled():
		_active_mountain_chunk_coords = _to_chunk_coord_set(
			_native_topology_builder.call("get_mountain_chunk_coords", _active_mountain_key) as Array
		)
	else:
		_active_mountain_chunk_coords = _to_chunk_coord_set(
			(_mountain_tiles_by_key_by_chunk.get(_active_mountain_key, {}) as Dictionary).keys()
		)
	var affected_chunks: Array[Vector2i] = []
	for coord: Vector2i in _active_mountain_chunk_coords:
		if not previous_chunks.has(coord):
			affected_chunks.append(coord)
	for coord: Vector2i in previous_chunks:
		affected_chunks.append(coord)
	return affected_chunks

func _deferred_init() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node2D
	_build_world_tilesets()
	_setup_native_topology_builder()
	_initialized = _terrain_tileset != null and _overlay_tileset != null
	if _initialized:
		_register_budget_jobs()

func _build_world_tilesets() -> void:
	if not WorldGenerator or not WorldGenerator.balance:
		return
	var biome: BiomeData = WorldGenerator.current_biome
	if not biome:
		return
	var tilesets: Dictionary = ChunkTilesetFactory.build_tilesets(WorldGenerator.balance, biome)
	_terrain_tileset = tilesets.get("terrain") as TileSet
	_overlay_tileset = tilesets.get("overlay") as TileSet

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

func _is_native_topology_enabled() -> bool:
	return _native_topology_active

func _check_player_chunk() -> void:
	var cur: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	if cur != _player_chunk:
		_player_chunk = cur
		_update_chunks(cur)

func _update_chunks(center: Vector2i) -> void:
	var load_radius: int = WorldGenerator.balance.load_radius
	var unload_radius: int = WorldGenerator.balance.unload_radius
	var needed: Dictionary = {}
	for dx: int in range(-load_radius, load_radius + 1):
		for dy: int in range(-load_radius, load_radius + 1):
			needed[Vector2i(center.x + dx, center.y + dy)] = true
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks:
		if absi(coord.x - center.x) > unload_radius or absi(coord.y - center.y) > unload_radius:
			to_unload.append(coord)
	for coord: Vector2i in to_unload:
		_unload_chunk(coord)
	var to_load: Array[Vector2i] = []
	for coord: Vector2i in needed:
		if not _loaded_chunks.has(coord) and coord not in _load_queue and coord != _staged_coord and coord != _gen_coord:
			to_load.append(coord)
	to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absi(a.x - center.x) + absi(a.y - center.y) < absi(b.x - center.x) + absi(b.y - center.y)
	)
	_load_queue.append_array(to_load)

func _process_load_queue() -> void:
	var loads_per_frame: int = 1
	if WorldGenerator and WorldGenerator.balance:
		loads_per_frame = WorldGenerator.balance.chunk_loads_per_frame
	var loaded_count: int = 0
	while not _load_queue.is_empty() and loaded_count < loads_per_frame:
		var coord: Vector2i = _load_queue.pop_front()
		var load_radius: int = WorldGenerator.balance.load_radius
		if absi(coord.x - _player_chunk.x) > load_radius or absi(coord.y - _player_chunk.y) > load_radius:
			continue
		_load_chunk(coord)
		loaded_count += 1

func _load_chunk(coord: Vector2i) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if _loaded_chunks.has(coord) or not _terrain_tileset or not _overlay_tileset:
		return
	var native_data: Dictionary = WorldGenerator.get_chunk_data(coord)
	var chunk := Chunk.new()
	chunk.setup(
		coord,
		WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		WorldGenerator.current_biome,
		_terrain_tileset,
		_overlay_tileset,
		self
	)
	var is_player_chunk: bool = (coord == _player_chunk)
	chunk.populate_native(native_data, _saved_chunk_data.get(coord, {}), is_player_chunk)
	chunk.set_revealed_mountain_key(_active_mountain_key, false)
	var z_container: Node2D = _z_containers.get(_active_z) as Node2D
	if z_container:
		z_container.add_child(chunk)
	else:
		_chunk_container.add_child(chunk)
	_loaded_chunks[coord] = chunk
	if not is_player_chunk:
		_redrawing_chunks.append(chunk)
	if _is_native_topology_enabled():
		_native_topology_builder.call("set_chunk", coord, chunk.get_terrain_bytes(), WorldGenerator.balance.chunk_size_tiles)
		_native_topology_dirty = true
	else:
		_mark_topology_dirty()
	EventBus.chunk_loaded.emit(coord)
	WorldPerfProbe.end("ChunkManager._load_chunk %s" % [coord], started_usec)

func _unload_chunk(coord: Vector2i) -> void:
	if coord == _staged_coord:
		if _staged_chunk != null:
			_staged_chunk.queue_free()
			_staged_chunk = null
		_staged_data = {}
		_staged_coord = Vector2i(999999, 999999)
	if coord == _gen_coord:
		_gen_coord = Vector2i(999999, 999999)
	if not _loaded_chunks.has(coord):
		return
	var chunk: Chunk = _loaded_chunks[coord]
	var redraw_idx: int = _redrawing_chunks.find(chunk)
	if redraw_idx >= 0:
		_redrawing_chunks.remove_at(redraw_idx)
	if chunk.is_dirty:
		_saved_chunk_data[coord] = chunk.get_modifications()
	chunk.cleanup()
	chunk.queue_free()
	_loaded_chunks.erase(coord)
	if _is_native_topology_enabled():
		_native_topology_builder.call("remove_chunk", coord)
		_native_topology_dirty = true
	else:
		_mark_topology_dirty()
	EventBus.chunk_unloaded.emit(coord)

func _register_budget_jobs() -> void:
	FrameBudgetDispatcher.register_job(&"streaming", 3.0, _tick_loading)
	FrameBudgetDispatcher.register_job(&"streaming", 2.0, _tick_redraws)
	FrameBudgetDispatcher.register_job(&"topology", 2.0, _tick_topology)

## Async staged chunk loading. Generation в WorkerThreadPool, create/finalize на main thread.
## Thread-safety: Strategy A — один worker, read-only access к WorldGenerator.
func _tick_loading() -> bool:
	if _is_boot_in_progress:
		return false
	if _staged_chunk != null:
		_staged_loading_finalize()
		return _has_streaming_work()
	if not _staged_data.is_empty():
		_staged_loading_create()
		return true
	if _gen_task_id >= 0:
		if WorkerThreadPool.is_task_completed(_gen_task_id):
			WorkerThreadPool.wait_for_task_completion(_gen_task_id)
			_gen_task_id = -1
			var coord: Vector2i = _gen_coord
			_gen_coord = Vector2i(999999, 999999)
			var load_radius: int = WorldGenerator.balance.load_radius
			if _loaded_chunks.has(coord) or absi(coord.x - _player_chunk.x) > load_radius or absi(coord.y - _player_chunk.y) > load_radius:
				_gen_mutex.lock()
				_gen_result.clear()
				_gen_mutex.unlock()
				return _has_streaming_work()
			_gen_mutex.lock()
			_staged_data = _gen_result.duplicate()
			_gen_result.clear()
			_gen_mutex.unlock()
			_staged_coord = coord
			return true
		return _has_streaming_work()
	if _load_queue.is_empty():
		return false
	var coord: Vector2i = _load_queue.pop_front()
	var load_radius: int = WorldGenerator.balance.load_radius
	if absi(coord.x - _player_chunk.x) > load_radius or absi(coord.y - _player_chunk.y) > load_radius:
		return _has_streaming_work()
	if _loaded_chunks.has(coord):
		return _has_streaming_work()
	_submit_async_generate(coord)
	return true

func _has_streaming_work() -> bool:
	return not _load_queue.is_empty() or _staged_chunk != null or not _staged_data.is_empty() or _gen_task_id >= 0

## Отправляет генерацию чанка в WorkerThreadPool. Один worker за раз.
func _submit_async_generate(coord: Vector2i) -> void:
	_gen_coord = coord
	_gen_task_id = WorkerThreadPool.add_task(_worker_generate.bind(coord))

## Выполняется в worker thread. Только чистые данные, никаких Node/scene tree.
## Thread-safety: Strategy A — read-only access к noise instances и balance.
## FastNoiseLite.get_noise_2d() — pure function, no mutable state.
func _worker_generate(coord: Vector2i) -> void:
	var data: Dictionary = WorldGenerator.get_chunk_data(coord)
	_gen_mutex.lock()
	_gen_result = data
	_gen_mutex.unlock()

## Фаза 0: только генерация terrain данных. CPU-heavy. Используется ТОЛЬКО в boot.
func _staged_loading_generate(coord: Vector2i) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if _loaded_chunks.has(coord) or not _terrain_tileset or not _overlay_tileset:
		return
	_staged_data = WorldGenerator.get_chunk_data(coord)
	_staged_coord = coord
	WorldPerfProbe.end("ChunkStreaming.phase0_generate %s" % [coord], started_usec)

## Фаза 1: создание Chunk node + populate bytes.
func _staged_loading_create() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	var coord: Vector2i = _staged_coord
	var native_data: Dictionary = _staged_data
	_staged_data = {}
	if _loaded_chunks.has(coord):
		_staged_coord = Vector2i(999999, 999999)
		return
	var chunk := Chunk.new()
	chunk.setup(
		coord,
		WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		WorldGenerator.current_biome,
		_terrain_tileset,
		_overlay_tileset,
		self
	)
	chunk.populate_native(native_data, _saved_chunk_data.get(coord, {}), false)
	chunk.set_revealed_mountain_key(_active_mountain_key, false)
	_staged_chunk = chunk
	WorldPerfProbe.end("ChunkStreaming.phase1_create %s" % [coord], started_usec)

## Фаза 2: добавить в scene tree + topology + enqueue redraw.
func _staged_loading_finalize() -> void:
	var total_usec: int = WorldPerfProbe.begin()
	var chunk: Chunk = _staged_chunk
	var coord: Vector2i = _staged_coord
	_staged_chunk = null
	_staged_coord = Vector2i(999999, 999999)
	if _loaded_chunks.has(coord):
		chunk.queue_free()
		return
	var sub_usec: int = WorldPerfProbe.begin()
	var z_container: Node2D = _z_containers.get(_active_z) as Node2D
	if z_container:
		z_container.add_child(chunk)
	else:
		_chunk_container.add_child(chunk)
	WorldPerfProbe.end("ChunkStreaming.finalize.add_child %s" % [coord], sub_usec)
	_loaded_chunks[coord] = chunk
	_redrawing_chunks.append(chunk)
	sub_usec = WorldPerfProbe.begin()
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
	if _is_boot_in_progress:
		return false
	while not _redrawing_chunks.is_empty():
		var chunk: Chunk = _redrawing_chunks[0]
		if not is_instance_valid(chunk):
			_redrawing_chunks.remove_at(0)
			continue
		var rows_per_step: int = 8
		if WorldGenerator and WorldGenerator.balance:
			rows_per_step = WorldGenerator.balance.chunk_redraw_rows_per_frame
		if chunk.continue_redraw(rows_per_step):
			_redrawing_chunks.remove_at(0)
		return not _redrawing_chunks.is_empty()
	return false

## Topology build один шаг. Возвращает true если есть ещё работа.
func _tick_topology() -> bool:
	if _is_boot_in_progress:
		return false
	if _is_native_topology_enabled():
		if _native_topology_dirty and _load_queue.is_empty() and _redrawing_chunks.is_empty():
			_native_topology_builder.call("ensure_built")
			_native_topology_dirty = false
		return false
	if not _is_topology_dirty:
		return false
	if not _is_topology_build_in_progress:
		_start_topology_build()
	return _process_topology_build_step()

func _process_chunk_redraws() -> void:
	if _redrawing_chunks.is_empty():
		return
	var rows_per_frame: int = 8
	if WorldGenerator and WorldGenerator.balance:
		rows_per_frame = WorldGenerator.balance.chunk_redraw_rows_per_frame
	var chunk: Chunk = _redrawing_chunks[0]
	if chunk.continue_redraw(rows_per_frame):
		_redrawing_chunks.remove_at(0)

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
	_player_chunk = Vector2i(99999, 99999)

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
	_is_topology_build_in_progress = false

func _ensure_topology_current() -> void:
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
	_topology_scan_chunk_coords = []
	for coord: Vector2i in _loaded_chunks:
		_topology_scan_chunk_coords.append(coord)
	_topology_scan_chunk_index = 0
	_topology_scan_local_x = 0
	_topology_scan_local_y = 0
	_topology_build_visited = {}
	_topology_build_key_by_tile = {}
	_topology_build_tiles_by_key = {}
	_topology_build_open_tiles_by_key = {}
	_topology_build_tiles_by_key_by_chunk = {}
	_topology_build_open_tiles_by_key_by_chunk = {}
	_clear_topology_component_state()

func _process_topology_build_step() -> bool:
	if _topology_component_queue_index < _topology_component_queue.size():
		_process_topology_component_step()
		return true
	var next_seed: Vector2i = _find_next_topology_seed()
	if next_seed != Vector2i(999999, 999999):
		_begin_topology_component(next_seed)
		return true
	_finish_topology_build()
	return false

func _find_next_topology_seed() -> Vector2i:
	while _topology_scan_chunk_index < _topology_scan_chunk_coords.size():
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
				var terrain_type: int = chunk.get_terrain_type_at(local_tile)
				if not _is_mountain_topology_tile(terrain_type):
					continue
				var global_tile: Vector2i = Vector2i(
					chunk_coord.x * chunk_size + local_tile.x,
					chunk_coord.y * chunk_size + local_tile.y
				)
				if _topology_build_visited.has(global_tile):
					continue
				return global_tile
			_topology_scan_local_x = 0
			_topology_scan_local_y += 1
		_topology_scan_chunk_index += 1
		_topology_scan_local_x = 0
		_topology_scan_local_y = 0
	return Vector2i(999999, 999999)

func _begin_topology_component(start_tile: Vector2i) -> void:
	_clear_topology_component_state()
	_topology_component_queue = [start_tile]
	_topology_component_queue_index = 0
	_topology_component_key = start_tile
	_topology_build_visited[start_tile] = true

func _process_topology_component_step() -> void:
	var current: Vector2i = _topology_component_queue[_topology_component_queue_index]
	_topology_component_queue_index += 1
	_topology_component_tiles[current] = true
	var current_chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(current)
	if not _topology_component_tiles_by_chunk.has(current_chunk_coord):
		_topology_component_tiles_by_chunk[current_chunk_coord] = {}
	(_topology_component_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
	if current.y < _topology_component_key.y or (current.y == _topology_component_key.y and current.x < _topology_component_key.x):
		_topology_component_key = current
	var current_chunk: Chunk = get_chunk_at_tile(current)
	if current_chunk:
		var current_local: Vector2i = current_chunk.global_to_local(current)
		var current_type: int = current_chunk.get_terrain_type_at(current_local)
		if current_type == TileGenData.TerrainType.MINED_FLOOR or current_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			_topology_component_open_tiles[current] = true
			if not _topology_component_open_tiles_by_chunk.has(current_chunk_coord):
				_topology_component_open_tiles_by_chunk[current_chunk_coord] = {}
			(_topology_component_open_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next_tile: Vector2i = current + dir
		if _topology_build_visited.has(next_tile):
			continue
		var next_chunk: Chunk = get_chunk_at_tile(next_tile)
		if not next_chunk:
			continue
		var next_local: Vector2i = next_chunk.global_to_local(next_tile)
		if not _is_mountain_topology_tile(next_chunk.get_terrain_type_at(next_local)):
			continue
		_topology_build_visited[next_tile] = true
		_topology_component_queue.append(next_tile)
	if _topology_component_queue_index >= _topology_component_queue.size():
		_finish_topology_component()

func _finish_topology_component() -> void:
	for tile_pos: Vector2i in _topology_component_tiles:
		_topology_build_key_by_tile[tile_pos] = _topology_component_key
	_topology_build_tiles_by_key[_topology_component_key] = _topology_component_tiles
	_topology_build_open_tiles_by_key[_topology_component_key] = _topology_component_open_tiles
	_topology_build_tiles_by_key_by_chunk[_topology_component_key] = _topology_component_tiles_by_chunk
	_topology_build_open_tiles_by_key_by_chunk[_topology_component_key] = _topology_component_open_tiles_by_chunk
	_clear_topology_component_state()

func _clear_topology_component_state() -> void:
	_topology_component_queue = []
	_topology_component_queue_index = 0
	_topology_component_tiles = {}
	_topology_component_open_tiles = {}
	_topology_component_tiles_by_chunk = {}
	_topology_component_open_tiles_by_chunk = {}
	_topology_component_key = Vector2i(999999, 999999)

func _finish_topology_build() -> void:
	_mountain_key_by_tile = _topology_build_key_by_tile
	_mountain_tiles_by_key = _topology_build_tiles_by_key
	_mountain_open_tiles_by_key = _topology_build_open_tiles_by_key
	_mountain_tiles_by_key_by_chunk = _topology_build_tiles_by_key_by_chunk
	_mountain_open_tiles_by_key_by_chunk = _topology_build_open_tiles_by_key_by_chunk
	_is_topology_dirty = false
	_is_topology_build_in_progress = false

func _rebuild_loaded_mountain_topology() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if _is_native_topology_enabled():
		_native_topology_builder.call("ensure_built")
		WorldPerfProbe.end("ChunkManager._rebuild_loaded_mountain_topology", started_usec)
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
				var global_tile: Vector2i = Vector2i(
					chunk_coord.x * chunk_size + local_x,
					chunk_coord.y * chunk_size + local_y
				)
				if visited.has(global_tile):
					continue
				_build_mountain_component(global_tile, visited)
	WorldPerfProbe.end("ChunkManager._rebuild_loaded_mountain_topology", started_usec)

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
		var current_chunk: Chunk = get_chunk_at_tile(current)
		if current_chunk:
			var current_local: Vector2i = current_chunk.global_to_local(current)
			var current_type: int = current_chunk.get_terrain_type_at(current_local)
			if current_type == TileGenData.TerrainType.MINED_FLOOR or current_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
				component_open_tiles[current] = true
				if not component_open_tiles_by_chunk.has(current_chunk_coord):
					component_open_tiles_by_chunk[current_chunk_coord] = {}
				(component_open_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next_tile: Vector2i = current + dir
			if visited.has(next_tile):
				continue
			var next_chunk: Chunk = get_chunk_at_tile(next_tile)
			if not next_chunk:
				continue
			var next_local: Vector2i = next_chunk.global_to_local(next_tile)
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
	if not (_is_mountain_topology_tile(old_type) or _is_mountain_topology_tile(new_type)):
		return
	var started_usec: int = WorldPerfProbe.begin()
	if _is_native_topology_enabled():
		_native_topology_builder.call("update_tile", tile_pos, new_type)
		WorldPerfProbe.end("ChunkManager._on_mountain_tile_changed", started_usec)
		return
	_incremental_topology_patch(tile_pos, new_type)
	WorldPerfProbe.end("ChunkManager._on_mountain_tile_changed", started_usec)

## Инкрементальный патч топологии для 1 тайла. O(9) вместо full BFS.
## При подозрении на split компонента — ставит dirty для background rebuild.
func _incremental_topology_patch(tile_pos: Vector2i, new_type: int) -> void:
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
		var neighbor: Vector2i = tile_pos + dir
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
		var key: Vector2i = _mountain_key_by_tile.get(tile_pos + dir, Vector2i(999999, 999999))
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
