class_name ChunkStreamingService
extends RefCounted

const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")
const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")

var _owner: Node = null
var load_queue: Array[Dictionary] = []
var load_queue_set: Dictionary = {}
var staged_chunk: Chunk = null
var staged_coord: Vector2i = Vector2i(999999, 999999)
var staged_z: int = 0
var staged_data: Dictionary = {}
var staged_flora_result: ChunkFloraResultScript = null
var staged_flora_payload: Dictionary = {}
var staged_install_entry: Dictionary = {}
var gen_task_id: int = -1
var gen_coord: Vector2i = Vector2i(999999, 999999)
var gen_z: int = 0
var gen_result: Dictionary = {}
var gen_mutex: Mutex = Mutex.new()
var worker_chunk_builder: RefCounted = null
var gen_active_tasks: Dictionary = {}
var gen_active_z_levels: Dictionary = {}
var gen_builders: Dictionary = {}
var gen_ready_queue: Array[Dictionary] = []
var debug_generate_started_usec: Dictionary = {}
var _visual_scheduler_ref: ChunkVisualScheduler = null
var _surface_payload_cache: ChunkSurfacePayloadCache = null

func setup(owner: Node, visual_scheduler: ChunkVisualScheduler, surface_payload_cache: ChunkSurfacePayloadCache) -> void:
	_owner = owner
	_visual_scheduler_ref = visual_scheduler
	_surface_payload_cache = surface_payload_cache

func _invalid_z_level() -> int:
	return _owner.INVALID_Z_LEVEL

func _max_load_requests_scanned_per_tick() -> int:
	return _owner.MAX_LOAD_REQUESTS_SCANNED_PER_TICK

func _runtime_max_concurrent_compute() -> int:
	return _owner.RUNTIME_MAX_CONCURRENT_COMPUTE

func _max_relevant_load_queue_overscan() -> int:
	return _owner.MAX_RELEVANT_LOAD_QUEUE_OVERSCAN

func _canonical_chunk_coord(coord: Vector2i) -> Vector2i:
	return _owner._canonical_chunk_coord(coord)

func _make_load_request_key(coord: Vector2i, z_level: int) -> Vector3i:
	return _owner._make_load_request_key(coord, z_level)

func _offset_chunk_coord(coord: Vector2i, offset: Vector2i) -> Vector2i:
	return _owner._offset_chunk_coord(coord, offset)

func _is_chunk_within_radius(coord: Vector2i, center: Vector2i, radius: int) -> bool:
	return _owner._is_chunk_within_radius(coord, center, radius)

func _has_load_request(coord: Vector2i, z_level: int) -> bool:
	return load_queue_set.has(_make_load_request_key(coord, z_level))

func _is_staged_request(coord: Vector2i, z_level: int) -> bool:
	return staged_coord == _canonical_chunk_coord(coord) and staged_z == z_level

func _is_generating_request(coord: Vector2i, z_level: int) -> bool:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	return gen_active_tasks.has(canonical_coord) \
		and int(gen_active_z_levels.get(canonical_coord, _invalid_z_level())) == z_level

func _chunk_priority_less(a: Vector2i, b: Vector2i, center: Vector2i) -> bool:
	return _owner._chunk_priority_less(a, b, center)

func enqueue_load_request(coord: Vector2i, z_level: int) -> void:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	if _has_load_request(canonical_coord, z_level):
		return
	var now_usec: int = Time.get_ticks_usec()
	var request: Dictionary = {
		"coord": canonical_coord,
		"z": z_level,
		"requested_usec": now_usec,
		"requested_frame": Engine.get_process_frames(),
		"reason": _debug_reason_for_chunk(canonical_coord, _chunk_chebyshev_distance(canonical_coord, _player_chunk()), "requested"),
		"priority": _debug_priority_label(canonical_coord),
	}
	load_queue.append(request)
	load_queue_set[_make_load_request_key(canonical_coord, z_level)] = true
	_debug_emit_chunk_event(
		"chunk_requested",
		"запросила загрузку",
		canonical_coord,
		z_level,
		"игрок приблизился к фактической области загрузки",
		StringName(_debug_impact_for_chunk(_chunk_chebyshev_distance(canonical_coord, _player_chunk()), "requested")),
		"queued",
		"поставлен в очередь",
		"stream_load",
		{"queue_depth": load_queue.size()}
	)

func _sync_loaded_chunk_display_positions(center: Vector2i) -> void:
	_owner._sync_loaded_chunk_display_positions(center)

func _get_loaded_chunks_for_z(z_level: int) -> Dictionary:
	return _owner._get_loaded_chunks_for_z(z_level)

func _generate_solid_rock_chunk() -> Dictionary:
	return _owner._generate_solid_rock_chunk()

func _try_get_surface_payload_cache_native_data(coord: Vector2i, z_level: int, out_native_data: Dictionary) -> bool:
	return _surface_payload_cache != null and _surface_payload_cache.try_get_native_data(coord, z_level, out_native_data)

func _build_surface_chunk_native_data(coord: Vector2i) -> Dictionary:
	return _owner._build_surface_chunk_native_data(coord)

func _cache_surface_chunk_payload(coord: Vector2i, z_level: int, native_data: Dictionary) -> void:
	if _surface_payload_cache != null:
		_surface_payload_cache.cache_native_payload(coord, z_level, native_data)

func _cache_surface_chunk_flora_payload(coord: Vector2i, z_level: int, flora_payload: Dictionary) -> void:
	if _surface_payload_cache != null:
		_surface_payload_cache.cache_flora_payload(coord, z_level, flora_payload)

func _cache_surface_chunk_flora_result(coord: Vector2i, z_level: int, flora_result: ChunkFloraResultScript) -> void:
	if _surface_payload_cache != null:
		_surface_payload_cache.cache_flora_result(coord, z_level, flora_result)

func prepare_chunk_install_entry(
	coord: Vector2i,
	z_level: int,
	native_data: Dictionary,
	prepared_flora_result: ChunkFloraResultScript = null,
	prepared_flora_payload: Dictionary = {}
) -> Dictionary:
	if native_data.is_empty():
		return {}
	coord = _canonical_chunk_coord(coord)
	var chunk_biome: BiomeData = _owner._resolve_chunk_biome(coord, z_level)
	var tileset_bundle: Dictionary = _owner._get_or_build_tileset_bundle(chunk_biome)
	var terrain_tileset: TileSet = null
	if z_level != 0:
		terrain_tileset = tileset_bundle.get("underground_terrain") as TileSet
	else:
		terrain_tileset = tileset_bundle.get("terrain") as TileSet
	var overlay_tileset: TileSet = tileset_bundle.get("overlay") as TileSet
	if terrain_tileset == null or overlay_tileset == null:
		return {}
	var saved_modifications: Dictionary = _get_saved_chunk_modifications(z_level, coord)
	var flora_result: ChunkFloraResultScript = null
	var flora_payload: Dictionary = {}
	if z_level == 0:
		if not _has_surface_chunk_cache(coord, z_level):
			_cache_surface_chunk_payload(coord, z_level, native_data)
		if saved_modifications.is_empty():
			flora_payload = _get_cached_surface_chunk_flora_payload(coord, z_level)
			if flora_payload.is_empty():
				flora_payload = prepared_flora_payload
			if flora_payload.is_empty() and prepared_flora_result != null:
				flora_payload = prepared_flora_result.to_serialized_payload(_owner._resolve_flora_tile_size())
				flora_result = prepared_flora_result
			if flora_payload.is_empty():
				flora_result = _owner._get_cached_surface_chunk_flora_result(coord, z_level)
				if flora_result == null:
					flora_result = prepared_flora_result
				if flora_result == null:
					flora_result = _owner._build_flora_result_for_native_data(coord, native_data)
				if flora_result != null:
					flora_payload = flora_result.to_serialized_payload(_owner._resolve_flora_tile_size())
			if not flora_payload.is_empty() and _get_cached_surface_chunk_flora_payload(coord, z_level).is_empty():
				_cache_surface_chunk_flora_payload(coord, z_level, flora_payload)
			if flora_result != null:
				_cache_surface_chunk_flora_result(coord, z_level, flora_result)
	return {
		"coord": coord,
		"z_level": z_level,
		"native_data": native_data,
		"saved_modifications": saved_modifications,
		"chunk_biome": chunk_biome,
		"terrain_tileset": terrain_tileset,
		"overlay_tileset": overlay_tileset,
		"flora_result": flora_result,
		"flora_payload": flora_payload,
		"underground": z_level != 0,
		"init_fog": z_level != 0 and _owner._fog_tileset != null,
	}

func create_chunk_from_install_entry(install_entry: Dictionary) -> Chunk:
	if install_entry.is_empty():
		return null
	var coord: Vector2i = install_entry.get("coord", Vector2i.ZERO) as Vector2i
	var native_data: Dictionary = install_entry.get("native_data", {}) as Dictionary
	var saved_modifications: Dictionary = install_entry.get("saved_modifications", {}) as Dictionary
	var chunk_biome: BiomeData = install_entry.get("chunk_biome", null) as BiomeData
	var terrain_tileset: TileSet = install_entry.get("terrain_tileset", null) as TileSet
	var overlay_tileset: TileSet = install_entry.get("overlay_tileset", null) as TileSet
	if native_data.is_empty() or terrain_tileset == null or overlay_tileset == null:
		return null
	var chunk := Chunk.new()
	chunk.setup(
		coord,
		WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		chunk_biome,
		terrain_tileset,
		overlay_tileset,
		_owner
	)
	_owner._sync_chunk_display_position(chunk, _owner._player_chunk)
	if install_entry.get("underground", false):
		chunk.set_underground(true)
	chunk.populate_native(native_data, saved_modifications, false)
	var flora_payload: Dictionary = install_entry.get("flora_payload", {}) as Dictionary
	if not flora_payload.is_empty():
		chunk.set_flora_payload(flora_payload)
	var flora_result: ChunkFloraResultScript = install_entry.get("flora_result", null) as ChunkFloraResultScript
	if flora_payload.is_empty() and flora_result != null:
		chunk.set_flora_result(flora_result)
	if install_entry.get("init_fog", false):
		chunk.init_fog_layer(_owner._fog_tileset)
	return chunk

func _finalize_chunk_install(coord: Vector2i, z_level: int, chunk: Chunk) -> void:
	_owner._finalize_chunk_install(coord, z_level, chunk)

func _make_visual_task_key(coord: Vector2i, z_level: int, kind: int) -> Vector4i:
	return _owner._make_visual_task_key(coord, z_level, kind)

func _make_visual_chunk_key(coord: Vector2i, z_level: int) -> String:
	return _owner._make_visual_chunk_key(coord, z_level)

func _make_chunk_state_key(z_level: int, coord: Vector2i) -> Vector3i:
	return _owner._make_chunk_state_key(z_level, coord)

func _remove_native_loaded_open_pocket_query_chunk(coord: Vector2i, z_level: int) -> void:
	_owner._remove_native_loaded_open_pocket_query_chunk(coord, z_level)

func _should_track_surface_topology(z_level: int) -> bool:
	return _owner._should_track_surface_topology(z_level)

func _is_native_topology_enabled() -> bool:
	return _owner._is_native_topology_enabled()

func _debug_record_recent_lifecycle_event(
	event_key: String,
	coord: Vector2i,
	z_level: int,
	action_human: String,
	reason_human: String,
	duration_ms: float = -1.0
) -> void:
	_owner._debug_record_recent_lifecycle_event(event_key, coord, z_level, action_human, reason_human, duration_ms)

func _debug_emit_chunk_event(
	action: String,
	action_human: String,
	coord: Vector2i,
	z_level: int,
	reason: String,
	impact: StringName,
	state: String,
	state_human: String,
	code_term: String,
	detail_fields: Dictionary = {}
) -> void:
	_owner._debug_emit_chunk_event(action, action_human, coord, z_level, reason, impact, state, state_human, code_term, detail_fields)

func _worker_generate(coord: Vector2i, z_level: int, builder: ChunkContentBuilder = null) -> void:
	_owner._worker_generate(coord, z_level, builder)

func _debug_impact_for_chunk(distance: int, state: String) -> String:
	return _owner._debug_impact_for_chunk(distance, state)

func _chunk_chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return _owner._chunk_chebyshev_distance(a, b)

func _debug_age_ms(started_usec: int, now_usec: int) -> float:
	return _owner._debug_age_ms(started_usec, now_usec)

func _sort_load_request_entries_by_priority(queue: Array[Dictionary], center: Vector2i) -> void:
	if queue.size() <= 1:
		return
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var coord_a: Vector2i = _canonical_chunk_coord(a.get("coord", Vector2i.ZERO) as Vector2i)
		var coord_b: Vector2i = _canonical_chunk_coord(b.get("coord", Vector2i.ZERO) as Vector2i)
		return _chunk_priority_less(coord_a, coord_b, center)
	)

func _debug_priority_label(coord: Vector2i) -> String:
	return _owner._debug_priority_label(coord)

func _debug_reason_for_chunk(coord: Vector2i, distance: int, state: String) -> String:
	return _owner._debug_reason_for_chunk(coord, distance, state)

func _get_saved_chunk_modifications(z_level: int, coord: Vector2i) -> Dictionary:
	return _owner._get_saved_chunk_modifications(z_level, coord)

func _get_cached_surface_chunk_flora_payload(coord: Vector2i, z_level: int) -> Dictionary:
	return _surface_payload_cache.get_flora_payload(coord, z_level) if _surface_payload_cache != null else {}

func _has_surface_chunk_cache(coord: Vector2i, z_level: int) -> bool:
	return _surface_payload_cache.has_chunk(coord, z_level) if _surface_payload_cache != null else false

func _has_runtime_tilesets() -> bool:
	return _owner._terrain_tileset != null and _owner._overlay_tileset != null

func _is_shutdown_in_progress() -> bool:
	return _owner._shutdown_in_progress

func _is_boot_in_progress() -> bool:
	return _owner._is_boot_in_progress

func _can_create_detached_chunk_content_builder() -> bool:
	return _owner._wg_has_create_detached_chunk_content_builder

func _save_dirty_chunk_data(chunk: Chunk, coord: Vector2i, z_level: int) -> void:
	_owner._saved_chunk_data[_make_chunk_state_key(z_level, coord)] = chunk.get_modifications()

func _remove_surface_chunk_from_topology(coord: Vector2i) -> void:
	_owner._native_topology_builder.call("remove_chunk", coord)
	_owner._native_topology_dirty = true

func _has_relevant_runtime_generate_task() -> bool:
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	for coord_variant: Variant in gen_active_tasks.keys():
		var coord: Vector2i = coord_variant as Vector2i
		var z_level: int = int(gen_active_z_levels.get(coord, _invalid_z_level()))
		if z_level == _active_z() and _is_chunk_within_radius(coord, _player_chunk(), load_radius):
			return true
	return false

func _rebuild_load_queue_set() -> void:
	load_queue_set.clear()
	for request: Dictionary in load_queue:
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var request_z: int = int(request.get("z", _invalid_z_level()))
		load_queue_set[_make_load_request_key(coord, request_z)] = true

func _pop_load_request() -> Dictionary:
	if load_queue.is_empty():
		return {}
	var request: Dictionary = load_queue.pop_front()
	var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
	var request_z: int = int(request.get("z", _invalid_z_level()))
	load_queue_set.erase(_make_load_request_key(coord, request_z))
	return request

func _active_z() -> int:
	return _owner.get_active_z_level()

func _player_chunk() -> Vector2i:
	return _owner._get_player_chunk_coord()

func _loaded_chunks() -> Dictionary:
	return _owner.get_loaded_chunks()

func _visual_scheduler() -> ChunkVisualScheduler:
	return _visual_scheduler_ref

func clear_runtime_state() -> void:
	load_queue.clear()
	load_queue_set.clear()
	if staged_chunk != null:
		staged_chunk = null
	staged_coord = Vector2i(999999, 999999)
	staged_z = 0
	staged_data = {}
	staged_flora_result = null
	staged_flora_payload = {}
	staged_install_entry = {}
	for task_variant: Variant in gen_active_tasks.values():
		WorkerThreadPool.wait_for_task_completion(int(task_variant))
	gen_active_tasks.clear()
	gen_active_z_levels.clear()
	gen_builders.clear()
	gen_ready_queue.clear()
	gen_mutex.lock()
	gen_result = {}
	gen_mutex.unlock()
	sync_runtime_generation_status()
	worker_chunk_builder = null

func sort_load_queue_by_priority(center: Vector2i) -> void:
	_sort_load_request_entries_by_priority(load_queue, center)

func handle_active_z_changed(z_level: int) -> void:
	var filtered_queue: Array[Dictionary] = []
	for request: Dictionary in load_queue:
		if int(request.get("z", _invalid_z_level())) == z_level:
			filtered_queue.append(request)
	load_queue = filtered_queue
	_rebuild_load_queue_set()
	if staged_z != z_level:
		clear_staged_request()
	sync_runtime_generation_status()

func update_chunks(center: Vector2i) -> void:
	var canonical_center: Vector2i = _canonical_chunk_coord(center)
	var active_z: int = _active_z()
	var loaded_chunks: Dictionary = _loaded_chunks()
	var load_radius: int = WorldGenerator.balance.load_radius
	var unload_radius: int = WorldGenerator.balance.unload_radius
	var needed: Dictionary = {}
	for dx: int in range(-load_radius, load_radius + 1):
		for dy: int in range(-load_radius, load_radius + 1):
			needed[_offset_chunk_coord(canonical_center, Vector2i(dx, dy))] = true
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in loaded_chunks:
		if not _is_chunk_within_radius(coord, canonical_center, unload_radius):
			to_unload.append(coord)
	for coord: Vector2i in to_unload:
		unload_chunk(coord)
	prune_load_queue(canonical_center, active_z, load_radius)
	var to_load: Array[Vector2i] = []
	for coord: Vector2i in needed:
		if not loaded_chunks.has(coord) \
			and not _has_load_request(coord, active_z) \
			and not _is_staged_request(coord, active_z) \
			and not _is_generating_request(coord, active_z):
			to_load.append(coord)
	if to_load.size() > 1:
		to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _chunk_priority_less(a, b, canonical_center)
		)
	for coord: Vector2i in to_load:
		enqueue_load_request(coord, active_z)
	_sync_loaded_chunk_display_positions(canonical_center)

func process_load_queue() -> void:
	var active_z: int = _active_z()
	var loads_per_frame: int = 1
	if WorldGenerator and WorldGenerator.balance:
		loads_per_frame = WorldGenerator.balance.chunk_loads_per_frame
	var loaded_count: int = 0
	while not load_queue.is_empty() and loaded_count < loads_per_frame:
		var request: Dictionary = _pop_load_request()
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var request_z: int = int(request.get("z", active_z))
		if request_z != active_z:
			continue
		var load_radius: int = WorldGenerator.balance.load_radius
		if not _is_chunk_within_radius(coord, _player_chunk(), load_radius):
			continue
		load_chunk_for_z(coord, request_z)
		loaded_count += 1

func load_chunk(coord: Vector2i) -> void:
	load_chunk_for_z(_canonical_chunk_coord(coord), _active_z())

func load_chunk_for_z(coord: Vector2i, z_level: int) -> void:
	coord = _canonical_chunk_coord(coord)
	var started_usec: int = WorldPerfProbe.begin()
	var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(z_level)
	if loaded_chunks_for_z.has(coord) or not _has_runtime_tilesets():
		return
	var native_data: Dictionary = {}
	if z_level != 0:
		native_data = _generate_solid_rock_chunk()
	else:
		if not _try_get_surface_payload_cache_native_data(coord, z_level, native_data):
			var build_result: ChunkBuildResult = WorldGenerator.build_chunk_content(coord) if WorldGenerator else null
			native_data = build_result.to_native_data() if build_result and build_result.is_valid() else _build_surface_chunk_native_data(coord)
			_cache_surface_chunk_payload(coord, z_level, native_data)
	var install_entry: Dictionary = prepare_chunk_install_entry(coord, z_level, native_data)
	if install_entry.is_empty():
		return
	var chunk: Chunk = create_chunk_from_install_entry(install_entry)
	if chunk == null:
		return
	_finalize_chunk_install(coord, z_level, chunk)
	WorldPerfProbe.end("ChunkManager._load_chunk %s" % [coord], started_usec)

func unload_chunk(coord: Vector2i) -> void:
	var active_z: int = _active_z()
	var loaded_chunks: Dictionary = _loaded_chunks()
	var scheduler: ChunkVisualScheduler = _visual_scheduler()
	coord = _canonical_chunk_coord(coord)
	if _is_staged_request(coord, active_z):
		clear_staged_request()
	if _is_generating_request(coord, active_z):
		sync_runtime_generation_status()
	if not loaded_chunks.has(coord):
		return
	var chunk: Chunk = loaded_chunks[coord]
	for kind: int in [
		_owner.VisualTaskKind.TASK_FIRST_PASS,
		_owner.VisualTaskKind.TASK_FULL_REDRAW,
		_owner.VisualTaskKind.TASK_BORDER_FIX,
		_owner.VisualTaskKind.TASK_COSMETIC,
	]:
		if scheduler != null:
			var task_key: Vector4i = _make_visual_task_key(coord, active_z, kind)
			scheduler.task_pending.erase(task_key)
			scheduler.task_enqueued_usec.erase(task_key)
	var chunk_key: String = _make_visual_chunk_key(coord, active_z)
	if scheduler != null:
		scheduler.apply_started_usec.erase(chunk_key)
		scheduler.convergence_started_usec.erase(chunk_key)
		scheduler.first_pass_ready_usec.erase(chunk_key)
		scheduler.full_ready_usec.erase(chunk_key)
	if chunk.is_dirty:
		_save_dirty_chunk_data(chunk, coord, active_z)
	chunk.cleanup()
	chunk.queue_free()
	loaded_chunks.erase(coord)
	_remove_native_loaded_open_pocket_query_chunk(coord, active_z)
	if _should_track_surface_topology(active_z):
		if _is_native_topology_enabled():
			_remove_surface_chunk_from_topology(coord)
		else:
			push_error("Chunk runtime requires active native topology before unloading surface chunk %s." % [coord])
	EventBus.chunk_unloaded.emit(coord)
	_debug_record_recent_lifecycle_event(
		"unloaded",
		coord,
		active_z,
		"Выгрузка чанка",
		"чанк вышел из области удержания",
		-1.0
	)
	_debug_emit_chunk_event(
		"chunk_unloaded",
		"выгрузила чанк",
		coord,
		active_z,
		"чанк вышел из фактической области удержания после движения игрока",
		WorldRuntimeDiagnosticLog.IMPACT_INFORMATIONAL,
		"completed",
		"завершено",
		"stream_unload",
		{"loaded_chunks": loaded_chunks.size()}
	)

func tick_loading() -> bool:
	if _is_shutdown_in_progress():
		return false
	if _is_boot_in_progress():
		return false
	var active_z: int = _active_z()
	var player_chunk: Vector2i = _player_chunk()
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	if should_compact_load_queue(player_chunk, active_z, load_radius):
		prune_load_queue(player_chunk, active_z, load_radius)
	collect_completed_runtime_generates(load_radius)
	if staged_chunk != null:
		if staged_z != active_z or not _is_chunk_within_radius(staged_coord, player_chunk, load_radius):
			clear_staged_request()
			return has_streaming_work()
		staged_loading_finalize()
		return has_streaming_work()
	if not staged_install_entry.is_empty() or not staged_data.is_empty():
		if staged_z != active_z or not _is_chunk_within_radius(staged_coord, player_chunk, load_radius):
			clear_staged_request()
			return has_streaming_work()
		staged_loading_create()
		return true
	if promote_runtime_ready_result_to_stage(load_radius):
		return true
	if load_queue.is_empty():
		return has_streaming_work()
	var scanned_requests: int = 0
	while not load_queue.is_empty() \
		and scanned_requests < _max_load_requests_scanned_per_tick() \
		and gen_active_tasks.size() < _runtime_max_concurrent_compute():
		scanned_requests += 1
		var request: Dictionary = _pop_load_request()
		if not is_load_request_relevant(request, player_chunk, active_z, load_radius):
			continue
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var request_z: int = int(request.get("z", active_z))
		if try_stage_surface_chunk_from_cache(coord, request_z):
			return true
		submit_async_generate(coord, request_z)
	if promote_runtime_ready_result_to_stage(load_radius):
		return true
	return has_streaming_work()

func has_streaming_work() -> bool:
	return not load_queue.is_empty() \
		or staged_chunk != null \
		or not staged_data.is_empty() \
		or not gen_ready_queue.is_empty() \
		or _has_relevant_runtime_generate_task()

func is_streaming_generation_idle() -> bool:
	return load_queue.is_empty() \
		and staged_chunk == null \
		and staged_data.is_empty() \
		and gen_ready_queue.is_empty() \
		and not _has_relevant_runtime_generate_task()

func submit_async_generate(coord: Vector2i, z_level: int) -> void:
	if _is_shutdown_in_progress():
		return
	coord = _canonical_chunk_coord(coord)
	if gen_active_tasks.has(coord):
		return
	var builder: ChunkContentBuilder = null
	if WorldGenerator and _can_create_detached_chunk_content_builder():
		builder = WorldGenerator.create_detached_chunk_content_builder()
	var task_id: int = WorkerThreadPool.add_task(_worker_generate.bind(coord, z_level, builder))
	gen_active_tasks[coord] = task_id
	gen_active_z_levels[coord] = z_level
	gen_builders[coord] = builder
	debug_generate_started_usec[_make_chunk_state_key(z_level, coord)] = Time.get_ticks_usec()
	_debug_emit_chunk_event(
		"chunk_generation_started",
		"начала генерацию данных",
		coord,
		z_level,
		"запрос чанка взят из очереди потоковой догрузки",
		StringName(_debug_impact_for_chunk(_chunk_chebyshev_distance(coord, _player_chunk()), "generating")),
		"running",
		"выполняется",
		"stream_load",
		{"active_generators": gen_active_tasks.size()}
	)
	sync_runtime_generation_status()

func collect_completed_runtime_generates(load_radius: int) -> void:
	if gen_active_tasks.is_empty():
		return
	var completed_coords: Array[Vector2i] = []
	for coord_variant: Variant in gen_active_tasks.keys():
		var coord: Vector2i = coord_variant as Vector2i
		var task_id: int = int(gen_active_tasks.get(coord, -1))
		if task_id >= 0 and WorkerThreadPool.is_task_completed(task_id):
			completed_coords.append(coord)
	if completed_coords.size() > 1:
		completed_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _chunk_priority_less(a, b, _player_chunk())
		)
	for coord: Vector2i in completed_coords:
		var task_id: int = int(gen_active_tasks.get(coord, -1))
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
		gen_active_tasks.erase(coord)
		var request_z: int = int(gen_active_z_levels.get(coord, _invalid_z_level()))
		gen_active_z_levels.erase(coord)
		gen_builders.erase(coord)
		var debug_key: Vector3i = _make_chunk_state_key(request_z, coord)
		var generation_ms: float = _debug_age_ms(debug_generate_started_usec.get(debug_key, 0), Time.get_ticks_usec())
		debug_generate_started_usec.erase(debug_key)
		gen_mutex.lock()
		var completed_entry: Dictionary = gen_result.get(coord, {}) as Dictionary
		gen_result.erase(coord)
		gen_mutex.unlock()
		var completed_data: Dictionary = completed_entry.get("native_data", {}) as Dictionary
		var completed_flora_payload: Dictionary = completed_entry.get("flora_payload", {}) as Dictionary
		if not completed_data.is_empty():
			_cache_surface_chunk_payload(coord, request_z, completed_data)
			if request_z == 0 and not completed_flora_payload.is_empty():
				_cache_surface_chunk_flora_payload(coord, request_z, completed_flora_payload)
		if request_z != _active_z() \
			or _get_loaded_chunks_for_z(request_z).has(coord) \
			or not _is_chunk_within_radius(coord, _player_chunk(), load_radius):
			continue
		gen_ready_queue.append({
			"coord": coord,
			"z": request_z,
			"native_data": completed_data,
			"flora_payload": completed_flora_payload,
			"ready_usec": Time.get_ticks_usec(),
		})
		_debug_record_recent_lifecycle_event(
			"generated",
			coord,
			request_z,
			"Генерация данных чанка",
			"данные готовы и ждут применения",
			generation_ms
		)
		_debug_emit_chunk_event(
			"chunk_generation_completed",
			"завершила генерацию данных",
			coord,
			request_z,
			"данные чанка готовы и будут применены на основном потоке",
			StringName(_debug_impact_for_chunk(_chunk_chebyshev_distance(coord, _player_chunk()), "data_ready")),
			"ready",
			"данные готовы",
			"queued_not_applied",
			{"duration_ms": generation_ms, "ready_queue_depth": gen_ready_queue.size()}
		)
	sort_runtime_ready_queue()
	sync_runtime_generation_status()

func promote_runtime_ready_result_to_stage(load_radius: int) -> bool:
	while not gen_ready_queue.is_empty():
		var ready_entry: Dictionary = gen_ready_queue.pop_front()
		var coord: Vector2i = ready_entry.get("coord", Vector2i.ZERO) as Vector2i
		var request_z: int = int(ready_entry.get("z", _invalid_z_level()))
		var completed_data: Dictionary = ready_entry.get("native_data", {}) as Dictionary
		var completed_flora_payload: Dictionary = ready_entry.get("flora_payload", {}) as Dictionary
		if completed_data.is_empty():
			continue
		if request_z != _active_z() \
			or _get_loaded_chunks_for_z(request_z).has(coord) \
			or not _is_chunk_within_radius(coord, _player_chunk(), load_radius):
			continue
		if stage_prepared_chunk_install(coord, request_z, completed_data, null, completed_flora_payload):
			return true
	return false

func sort_runtime_ready_queue() -> void:
	if gen_ready_queue.size() <= 1:
		return
	gen_ready_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _chunk_priority_less(
			a.get("coord", Vector2i.ZERO) as Vector2i,
			b.get("coord", Vector2i.ZERO) as Vector2i,
			_player_chunk()
		)
	)

func sync_runtime_generation_status() -> void:
	if gen_active_tasks.is_empty():
		gen_task_id = -1
		gen_coord = Vector2i(999999, 999999)
		gen_z = 0
		return
	var active_coords: Array[Vector2i] = []
	for coord_variant: Variant in gen_active_tasks.keys():
		active_coords.append(coord_variant as Vector2i)
	active_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_priority_less(a, b, _player_chunk())
	)
	var selected_coord: Vector2i = active_coords[0]
	gen_coord = selected_coord
	gen_z = int(gen_active_z_levels.get(selected_coord, _active_z()))
	gen_task_id = int(gen_active_tasks.get(selected_coord, -1))

func is_load_request_relevant(
	request: Dictionary,
	center: Vector2i,
	active_z_level: int,
	load_radius: int
) -> bool:
	var request_z: int = int(request.get("z", _invalid_z_level()))
	if request_z != active_z_level:
		return false
	var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
	if _get_loaded_chunks_for_z(request_z).has(coord):
		return false
	return _is_chunk_within_radius(coord, center, load_radius)

func prune_load_queue(center: Vector2i, active_z_level: int, load_radius: int) -> void:
	if load_queue.is_empty():
		return
	var filtered_queue: Array[Dictionary] = []
	var seen_requests: Dictionary = {}
	for request: Dictionary in load_queue:
		if not is_load_request_relevant(request, center, active_z_level, load_radius):
			continue
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var request_z: int = int(request.get("z", _invalid_z_level()))
		var request_key: Vector3i = _make_load_request_key(coord, request_z)
		if seen_requests.has(request_key):
			continue
		seen_requests[request_key] = true
		var filtered_request: Dictionary = request.duplicate()
		filtered_request["coord"] = coord
		filtered_request["z"] = request_z
		if not filtered_request.has("requested_usec"):
			filtered_request["requested_usec"] = Time.get_ticks_usec()
		if not filtered_request.has("requested_frame"):
			filtered_request["requested_frame"] = Engine.get_process_frames()
		if not filtered_request.has("priority"):
			filtered_request["priority"] = _debug_priority_label(coord)
		if not filtered_request.has("reason"):
			filtered_request["reason"] = _debug_reason_for_chunk(coord, _chunk_chebyshev_distance(coord, center), "queued")
		filtered_queue.append(filtered_request)
	_sort_load_request_entries_by_priority(filtered_queue, center)
	load_queue = filtered_queue
	_rebuild_load_queue_set()

func should_compact_load_queue(center: Vector2i, active_z_level: int, load_radius: int) -> bool:
	if load_queue.is_empty():
		return false
	var max_relevant_requests: int = resolve_max_relevant_load_queue_size(load_radius)
	if load_queue.size() > max_relevant_requests + _max_relevant_load_queue_overscan():
		return true
	var front_request: Dictionary = load_queue[0] as Dictionary
	if not is_load_request_relevant(front_request, center, active_z_level, load_radius):
		return true
	var tail_request: Dictionary = load_queue[load_queue.size() - 1] as Dictionary
	if not is_load_request_relevant(tail_request, center, active_z_level, load_radius):
		return true
	return false

func resolve_max_relevant_load_queue_size(load_radius: int) -> int:
	var diameter: int = load_radius * 2 + 1
	return maxi(0, diameter * diameter)

func try_stage_surface_chunk_from_cache(coord: Vector2i, z_level: int) -> bool:
	if z_level != 0:
		return false
	var staged_native_data: Dictionary = {}
	if not _try_get_surface_payload_cache_native_data(coord, z_level, staged_native_data):
		return false
	var saved_modifications: Dictionary = _get_saved_chunk_modifications(z_level, coord)
	var staged_flora_payload: Dictionary = _get_cached_surface_chunk_flora_payload(coord, z_level) if saved_modifications.is_empty() else {}
	return stage_prepared_chunk_install(coord, z_level, staged_native_data, null, staged_flora_payload)

func stage_prepared_chunk_install(
	coord: Vector2i,
	z_level: int,
	native_data: Dictionary,
	prepared_flora_result: ChunkFloraResultScript = null,
	prepared_flora_payload: Dictionary = {}
) -> bool:
	var install_entry: Dictionary = prepare_chunk_install_entry(
		coord,
		z_level,
		native_data,
		prepared_flora_result,
		prepared_flora_payload
	)
	if install_entry.is_empty():
		staged_flora_result = null
		staged_flora_payload = {}
		staged_install_entry = {}
		return false
	staged_coord = install_entry.get("coord", Vector2i.ZERO) as Vector2i
	staged_z = z_level
	staged_data = native_data
	staged_flora_result = install_entry.get("flora_result", prepared_flora_result) as ChunkFloraResultScript
	staged_flora_payload = install_entry.get("flora_payload", prepared_flora_payload) as Dictionary
	install_entry["staged_usec"] = Time.get_ticks_usec()
	staged_install_entry = install_entry
	_debug_emit_chunk_event(
		"chunk_apply_waiting",
		"подготовила чанк к применению",
		staged_coord,
		z_level,
		"данные готовы, следующий шаг - bounded main-thread установка",
		StringName(_debug_impact_for_chunk(_chunk_chebyshev_distance(staged_coord, _player_chunk()), "data_ready")),
		"waiting_apply",
		"ожидает применения",
		"queued_not_applied",
		{"ready_queue_depth": gen_ready_queue.size()}
	)
	return true

func cache_chunk_install_handoff_entry(entry: Dictionary, z_level: int) -> void:
	var coord: Vector2i = entry.get("coord", Vector2i.ZERO) as Vector2i
	var install_entry: Dictionary = entry.get("install_entry", {}) as Dictionary
	var native_data: Dictionary = install_entry.get("native_data", entry.get("native_data", {})) as Dictionary
	if z_level == 0 and not native_data.is_empty() and not _has_surface_chunk_cache(coord, z_level):
		_cache_surface_chunk_payload(coord, z_level, native_data)
	if z_level != 0:
		return
	var flora_payload: Dictionary = install_entry.get("flora_payload", entry.get("flora_payload", {})) as Dictionary
	if not flora_payload.is_empty():
		_cache_surface_chunk_flora_payload(coord, z_level, flora_payload)
	var flora_result: ChunkFloraResultScript = install_entry.get("flora_result", null) as ChunkFloraResultScript
	if flora_result != null:
		_cache_surface_chunk_flora_result(coord, z_level, flora_result)

func staged_loading_create() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	var coord: Vector2i = staged_coord
	var z_level: int = staged_z
	var native_data: Dictionary = staged_data
	var prepared_flora_result: ChunkFloraResultScript = staged_flora_result
	var prepared_flora_payload: Dictionary = staged_flora_payload
	staged_data = {}
	staged_flora_result = null
	staged_flora_payload = {}
	if _get_loaded_chunks_for_z(z_level).has(coord):
		staged_coord = Vector2i(999999, 999999)
		staged_z = 0
		staged_install_entry = {}
		return
	var install_entry: Dictionary = staged_install_entry
	if install_entry.is_empty():
		install_entry = prepare_chunk_install_entry(coord, z_level, native_data, prepared_flora_result, prepared_flora_payload)
	if install_entry.is_empty():
		staged_coord = Vector2i(999999, 999999)
		staged_z = 0
		staged_install_entry = {}
		return
	var chunk: Chunk = create_chunk_from_install_entry(install_entry)
	if chunk == null:
		staged_coord = Vector2i(999999, 999999)
		staged_z = 0
		staged_install_entry = {}
		return
	staged_install_entry = {}
	staged_chunk = chunk
	WorldPerfProbe.end("ChunkStreaming.phase1_create %s" % [coord], started_usec)

func staged_loading_finalize() -> void:
	var total_usec: int = WorldPerfProbe.begin()
	var chunk: Chunk = staged_chunk
	var coord: Vector2i = staged_coord
	var z_level: int = staged_z
	staged_chunk = null
	staged_coord = Vector2i(999999, 999999)
	staged_z = 0
	_finalize_chunk_install(coord, z_level, chunk)
	WorldPerfProbe.end("ChunkStreaming.phase2_finalize %s" % [coord], total_usec)

func clear_staged_request() -> void:
	if staged_chunk != null:
		staged_chunk.queue_free()
	staged_chunk = null
	staged_coord = Vector2i(999999, 999999)
	staged_z = 0
	staged_data = {}
	staged_flora_result = null
	staged_flora_payload = {}
	staged_install_entry = {}

