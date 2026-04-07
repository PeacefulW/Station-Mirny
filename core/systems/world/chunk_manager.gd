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
const SURFACE_PAYLOAD_CACHE_LIMIT: int = 192
const INVALID_CHUNK_STATE_KEY: Vector3i = Vector3i(999999, 999999, 999999)
const INVALID_Z_LEVEL: int = 999999

enum VisualTaskKind {
	TASK_FIRST_PASS,
	TASK_FULL_REDRAW,
	TASK_BORDER_FIX,
	TASK_COSMETIC,
}

enum VisualPriorityBand {
	TERRAIN_FAST,
	TERRAIN_URGENT,
	TERRAIN_NEAR,
	FULL_NEAR,
	BORDER_FIX_NEAR,
	BORDER_FIX_FAR,
	FULL_FAR,
	COSMETIC,
}

enum VisualTaskRunState {
	DROPPED,
	REQUEUE,
	COMPLETED,
}

const BORDER_FIX_REDRAW_MICRO_BATCH_TILES: int = 16
const PLAYER_CHUNK_DIAG_LOG_INTERVAL_MSEC: int = 2000
const PLAYER_CHUNK_DIAG_BLOCKED_AGE_MS: float = 250.0
const PLAYER_CHUNK_DIAG_SPIKE_MS: float = 12.0
const VISUAL_ADAPTIVE_APPLY_MIN_MS: float = 0.75
const VISUAL_ADAPTIVE_APPLY_MAX_MS: float = 4.0
const VISUAL_ADAPTIVE_FEEDBACK_BLEND: float = 0.55
const VISUAL_ADAPTIVE_MIN_TILES: int = 8
const VISUAL_ADAPTIVE_MIN_BORDER_TILES: int = 4
const VISUAL_ADAPTIVE_FAST_SAFETY: float = 0.55
const VISUAL_ADAPTIVE_URGENT_SAFETY: float = 0.65
const VISUAL_ADAPTIVE_NEAR_SAFETY: float = 0.72
const VISUAL_ADAPTIVE_FAR_SAFETY: float = 0.82
const VISUAL_FAST_PHASE_TILE_CAP_TERRAIN: int = 96
const VISUAL_FAST_PHASE_TILE_CAP_COVER: int = 48
const VISUAL_FAST_PHASE_TILE_CAP_CLIFF: int = 96
const VISUAL_URGENT_PHASE_TILE_CAP_TERRAIN: int = 128
const VISUAL_URGENT_PHASE_TILE_CAP_COVER: int = 80
const VISUAL_URGENT_PHASE_TILE_CAP_CLIFF: int = 128

var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(99999, 99999)
var _last_player_chunk_for_priority: Vector2i = Vector2i(99999, 99999)
var _player_chunk_motion: Vector2i = Vector2i.ZERO
var _player: Node2D = null
var _chunk_container: Node2D = null
var _load_queue: Array[Dictionary] = []
var _redrawing_chunks: Array[Chunk] = []
var _visual_q_terrain_fast: Array[Dictionary] = []
var _visual_q_terrain_urgent: Array[Dictionary] = []
var _visual_q_terrain_near: Array[Dictionary] = []
var _visual_q_full_near: Array[Dictionary] = []
var _visual_q_border_fix_near: Array[Dictionary] = []
var _visual_q_border_fix_far: Array[Dictionary] = []
var _visual_q_full_far: Array[Dictionary] = []
var _visual_q_cosmetic: Array[Dictionary] = []
var _visual_task_versions: Dictionary = {}
var _visual_task_pending: Dictionary = {}
var _visual_task_enqueued_usec: Dictionary = {}
var _visual_apply_started_usec: Dictionary = {}
var _visual_convergence_started_usec: Dictionary = {}
var _visual_first_pass_ready_usec: Dictionary = {}
var _visual_full_ready_usec: Dictionary = {}
var _visual_scheduler_budget_exhausted_count: int = 0
var _visual_scheduler_starvation_incident_count: int = 0
var _visual_scheduler_max_urgent_wait_ms: float = 0.0
var _visual_scheduler_log_ticks: int = 0
var _visual_apply_feedback: Dictionary = {}
var _visual_chunks_processed_this_tick: Dictionary = {}
var _visual_chunks_processed_frame: int = -1
var _player_chunk_diag_last_usec: int = 0
var _player_chunk_diag_last_signature: String = ""
var _visual_compute_active: Dictionary = {}  ## String task_key -> int task_id
var _visual_compute_waiting_tasks: Dictionary = {}  ## String task_key -> queued task payload
var _visual_compute_results: Dictionary = {}  ## String task_key -> prepared batch
var _visual_compute_mutex: Mutex = Mutex.new()
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

## --- Boot readiness state (boot_chunk_readiness_spec) ---
enum BootChunkState {
	QUEUED_COMPUTE,
	COMPUTED,
	QUEUED_APPLY,
	APPLIED,
	VISUAL_COMPLETE,
}
## Ring 0 (player) + ring 1 (immediate neighbors) = first-playable gate.
## Outer rings are required for boot_complete only.
const BOOT_FIRST_PLAYABLE_MAX_RING: int = 1
var _boot_chunk_states: Dictionary = {}  ## Vector2i -> BootChunkState
var _boot_center: Vector2i = Vector2i.ZERO
var _boot_load_radius: int = 0
var _boot_first_playable: bool = false
var _boot_complete_flag: bool = false
## Topology is part of boot_complete but NOT part of first_playable.
var _boot_topology_ready: bool = false
var _boot_started_usec: int = 0
## --- Boot performance instrumentation (boot_performance_instrumentation_spec) ---
var _boot_metric_compute_ms: float = 0.0
var _boot_metric_apply_ms: float = 0.0
var _boot_metric_terrain_redraw_ms: float = 0.0
var _boot_metric_chunks_computed: int = 0
var _boot_metric_chunks_applied: int = 0

## --- Boot compute pipeline (boot_chunk_compute_pipeline_spec) ---
const BOOT_MAX_CONCURRENT_COMPUTE: int = 3
## --- Boot apply budget (boot_chunk_apply_budget_spec) ---
const BOOT_MAX_PREPARE_PER_STEP: int = 2
const BOOT_MAX_APPLY_PER_STEP: int = 1
const BOOT_APPLY_WARNING_MS: float = 8.0
const RUNTIME_MAX_CONCURRENT_COMPUTE: int = 4
var _boot_compute_pending: Array[Vector2i] = []
var _boot_compute_active: Dictionary = {}  ## Vector2i -> int (WorkerThreadPool task_id)
var _boot_compute_builders: Dictionary = {}  ## Vector2i -> ChunkContentBuilder (detached, per-task)
var _boot_compute_results: Dictionary = {}  ## Vector2i -> Dictionary (native_data)
var _boot_compute_mutex: Mutex = Mutex.new()
var _boot_compute_z: int = 0
var _boot_applied_count: int = 0
var _boot_total_count: int = 0
var _boot_compute_generation: int = 0  ## Incremented on each boot start; stale results carry old generation
var _boot_failed_coords: Array[Vector2i] = []
var _boot_runtime_handoff_started: bool = false
var _boot_compute_requested_usec: Dictionary = {}  ## Vector2i -> int
var _boot_compute_started_usec: Dictionary = {}  ## Vector2i -> int
var _boot_metric_queue_wait_ms: float = 0.0

## --- Boot apply queue (boot_chunk_apply_budget_spec) ---
var _boot_prepare_queue: Array[Dictionary] = []  ## [{coord: Vector2i, native_data: Dictionary, flora_payload: Dictionary}], sorted by distance
var _boot_apply_queue: Array[Dictionary] = []  ## [{coord: Vector2i, native_data: Dictionary, flora_payload: Dictionary, install_entry: Dictionary}], sorted by distance
var _boot_has_remaining_chunks: bool = false  ## True while boot background work is not fully complete
var _boot_pipeline_drained: bool = false  ## True once compute/apply pipeline is fully drained
var _staged_chunk: Chunk = null
var _staged_coord: Vector2i = Vector2i(999999, 999999)
var _staged_z: int = 0
var _staged_data: Dictionary = {}  ## Native data между фазами
var _staged_flora_result: ChunkFloraResultScript = null
var _staged_flora_payload: Dictionary = {}
var _staged_install_entry: Dictionary = {}
## --- Async generation (runtime only) ---
var _gen_task_id: int = -1  ## WorkerThreadPool task ID, -1 = нет активной задачи
var _gen_coord: Vector2i = Vector2i(999999, 999999)  ## Координата в процессе генерации
var _gen_z: int = 0
var _gen_result: Dictionary = {}  ## Vector2i -> {native_data, flora_payload}
var _gen_mutex: Mutex = Mutex.new()
var _worker_chunk_builder: RefCounted = null
var _gen_active_tasks: Dictionary = {}  ## Vector2i -> int task_id
var _gen_active_z_levels: Dictionary = {}  ## Vector2i -> int z_level
var _gen_builders: Dictionary = {}  ## Vector2i -> ChunkContentBuilder
var _gen_ready_queue: Array[Dictionary] = []  ## [{coord, z, native_data, flora_payload}]
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
var _topology_task_id: int = -1
var _topology_task_generation: int = -1
var _topology_build_generation: int = 0
var _topology_result_mutex: Mutex = Mutex.new()
var _topology_result: Dictionary = {}

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
	_clear_visual_task_state()
	if _staged_chunk != null:
		_staged_chunk = null
	_staged_data = {}
	_staged_flora_result = null
	_staged_flora_payload = {}
	for task_variant: Variant in _gen_active_tasks.values():
		WorkerThreadPool.wait_for_task_completion(int(task_variant))
	_gen_active_tasks.clear()
	_gen_active_z_levels.clear()
	_gen_builders.clear()
	_gen_ready_queue.clear()
	_gen_mutex.lock()
	_gen_result = {}
	_gen_mutex.unlock()
	_sync_runtime_generation_status()
	_worker_chunk_builder = null
	if _topology_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_topology_task_id)
	_topology_task_id = -1
	_topology_task_generation = -1
	_topology_result_mutex.lock()
	_topology_result = {}
	_topology_result_mutex.unlock()
	_surface_payload_cache.clear()
	_surface_payload_cache_lru.clear()
	_boot_wait_all_compute()
	_boot_cleanup_compute_pipeline()
	_boot_chunk_states.clear()
	_boot_started_usec = 0
	if FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(JOB_STREAMING_LOAD)
		FrameBudgetDispatcher.unregister_job(JOB_STREAMING_REDRAW)
		FrameBudgetDispatcher.unregister_job(JOB_TOPOLOGY)
		if _fog_job_id:
			FrameBudgetDispatcher.unregister_job(_fog_job_id)

func _process(_delta: float) -> void:
	if not _initialized or not _player:
		return
	if _boot_has_remaining_chunks:
		_tick_boot_remaining()
	if _is_boot_in_progress:
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
	_boot_init_readiness(center, load_radius)
	var coords: Array[Vector2i] = []
	for dx: int in range(-load_radius, load_radius + 1):
		for dy: int in range(-load_radius, load_radius + 1):
			coords.append(_offset_chunk_coord(center, Vector2i(dx, dy)))
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_priority_less(a, b, center)
	)
	var total: int = coords.size()
	_boot_compute_z = _active_z
	_boot_applied_count = 0
	_boot_total_count = total
	for coord: Vector2i in coords:
		_boot_set_chunk_state(coord, BootChunkState.QUEUED_COMPUTE)
		if _loaded_chunks.has(coord):
			var loaded_chunk: Chunk = _loaded_chunks.get(coord) as Chunk
			_sync_chunk_visibility_for_publication(loaded_chunk)
			_boot_on_chunk_applied(coord, loaded_chunk)
		else:
			_boot_compute_pending.append(coord)
			_boot_compute_requested_usec[coord] = Time.get_ticks_usec()
	var _loop_iter: int = 0
	while not _boot_first_playable:
		var _iter_start: int = Time.get_ticks_usec()
		_boot_submit_pending_tasks()
		_boot_collect_completed()
		_boot_drain_computed_to_apply_queue()
		_boot_prepare_apply_entries()
		_boot_apply_from_queue()
		_boot_process_redraw_budget(2500)
		_boot_promote_redrawn_chunks()
		if _boot_compute_active.is_empty() \
			and _boot_compute_pending.is_empty() \
			and _boot_prepare_queue.is_empty() \
			and _boot_apply_queue.is_empty() \
			and _boot_compute_results.is_empty():
			_boot_pipeline_drained = true
		_boot_update_gates()
		var applied_count: int = _boot_count_applied_chunks()
		var pct: float = float(applied_count) / float(total) * 80.0 if total > 0 else 80.0
		progress_callback.call(
			pct,
			Localization.t("UI_LOADING_GENERATING_TERRAIN", {"current": applied_count, "total": total})
		)
		var _iter_ms: float = float(Time.get_ticks_usec() - _iter_start) / 1000.0
		_loop_iter += 1
		if _iter_ms > 10.0:
			WorldPerfProbe.record("Boot.loop_step_ms", _iter_ms)
		if _boot_first_playable:
			break
		await get_tree().process_frame
	_boot_has_remaining_chunks = not _boot_complete_flag
	if _boot_has_remaining_chunks:
		if not _boot_pipeline_drained and _boot_has_pending_runtime_handoff_work():
			_boot_start_runtime_handoff()
		progress_callback.call(85.0, Localization.t("UI_LOADING_LANDING"))
		await get_tree().process_frame
	progress_callback.call(95.0, Localization.t("UI_LOADING_LANDING"))
	await get_tree().process_frame
	_sync_loaded_chunk_display_positions(center)
	_is_boot_in_progress = false
	_reset_visual_runtime_telemetry()

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

func _chunk_chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(_chunk_axis_distance(a.x, b.x), absi(a.y - b.y))

func _chunk_priority_less(a: Vector2i, b: Vector2i, center: Vector2i) -> bool:
	var ring_a: int = _chunk_chebyshev_distance(a, center)
	var ring_b: int = _chunk_chebyshev_distance(b, center)
	if ring_a != ring_b:
		return ring_a < ring_b
	var dist_a: int = _chunk_manhattan_distance(a, center)
	var dist_b: int = _chunk_manhattan_distance(b, center)
	if dist_a != dist_b:
		return dist_a < dist_b
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y

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
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	return _gen_active_tasks.has(canonical_coord) and int(_gen_active_z_levels.get(canonical_coord, INVALID_Z_LEVEL)) == z_level

func _clear_staged_request() -> void:
	if _staged_chunk != null:
		_staged_chunk.queue_free()
	_staged_chunk = null
	_staged_coord = Vector2i(999999, 999999)
	_staged_z = 0
	_staged_data = {}
	_staged_flora_result = null
	_staged_flora_payload = {}
	_staged_install_entry = {}

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
	chunk.set_mining_write_authorized(true)
	var result: Dictionary = chunk.try_mine_at(local_tile)
	chunk.set_mining_write_authorized(false)
	if result.is_empty():
		return {}
	# Same-chunk neighbor re-normalization (MINED_FLOOR <-> MOUNTAIN_ENTRANCE)
	chunk._refresh_open_neighbors(local_tile)
	chunk.redraw_mining_patch(local_tile)
	_ensure_chunk_border_fix_task(chunk, _active_z, true)
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

## Redraw border tiles of loaded neighbor chunks after a new chunk is loaded.
## Fixes cross-chunk wall form mismatches when neighbors were drawn before this chunk existed.
func _redraw_neighbor_borders(coord: Vector2i) -> void:
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor_coord: Vector2i = _offset_chunk_coord(coord, dir)
		var neighbor_chunk: Chunk = _loaded_chunks.get(neighbor_coord) as Chunk
		if not neighbor_chunk:
			continue
		var dirty: Dictionary = {}
		if dir == Vector2i.LEFT:
			for y: int in range(chunk_size):
				dirty[Vector2i(chunk_size - 1, y)] = true
		elif dir == Vector2i.RIGHT:
			for y: int in range(chunk_size):
				dirty[Vector2i(0, y)] = true
		elif dir == Vector2i.UP:
			for x: int in range(chunk_size):
				dirty[Vector2i(x, chunk_size - 1)] = true
		elif dir == Vector2i.DOWN:
			for x: int in range(chunk_size):
				dirty[Vector2i(x, 0)] = true
		neighbor_chunk._redraw_dirty_tiles(dirty)

## Instead of synchronously redrawing all border tiles of 4 neighbors (256
## tiles, 20-49ms), mark dirty tiles and add neighbors to the progressive
## redraw queue. Border tiles will be processed by _tick_redraws() over
## the next 1-2 frames. Used only in streaming finalize path.
## (boot_fast_first_playable_spec Iteration 3, change 3A)
func _enqueue_neighbor_border_redraws(coord: Vector2i) -> void:
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor_coord: Vector2i = _offset_chunk_coord(coord, dir)
		var neighbor_chunk: Chunk = _loaded_chunks.get(neighbor_coord) as Chunk
		if not neighbor_chunk:
			continue
		if not neighbor_chunk.is_first_pass_ready():
			continue  # Neighbor hasn't drawn terrain yet, border will be drawn naturally
		var dirty: Dictionary = {}
		if dir == Vector2i.LEFT:
			for y: int in range(chunk_size):
				dirty[Vector2i(chunk_size - 1, y)] = true
		elif dir == Vector2i.RIGHT:
			for y: int in range(chunk_size):
				dirty[Vector2i(0, y)] = true
		elif dir == Vector2i.UP:
			for x: int in range(chunk_size):
				dirty[Vector2i(x, chunk_size - 1)] = true
		elif dir == Vector2i.DOWN:
			for x: int in range(chunk_size):
				dirty[Vector2i(x, 0)] = true
		neighbor_chunk.enqueue_dirty_border_redraw(dirty)
		_ensure_chunk_border_fix_task(neighbor_chunk, _active_z, true)

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
			neighbor_chunk.enqueue_dirty_border_redraw(cross_dirty)
			_ensure_chunk_border_fix_task(neighbor_chunk, _active_z, true)

func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	return get_terrain_type_at_global(tile_pos) == TileGenData.TerrainType.ROCK

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

func _resolve_flora_tile_size() -> int:
	return WorldGenerator.balance.tile_size if WorldGenerator and WorldGenerator.balance else 0

func _create_detached_flora_builder() -> ChunkFloraBuilderScript:
	if WorldGenerator == null or not WorldGenerator._is_initialized:
		return null
	var flora_builder := ChunkFloraBuilderScript.new()
	flora_builder.initialize(WorldGenerator.world_seed)
	return flora_builder

func _compute_flora_for_chunk(chunk: Chunk, build_result: ChunkBuildResult) -> ChunkFloraResultScript:
	if _flora_builder == null or build_result == null or not build_result.is_valid():
		return null
	var flora_result: ChunkFloraResultScript = _compute_flora_result(
		_flora_builder,
		build_result.canonical_chunk_coord,
		build_result.chunk_size,
		build_result.base_tile,
		build_result.biome,
		build_result.variation,
		build_result.terrain,
		build_result.flora_density_values,
		build_result.flora_modulation_values,
		build_result.secondary_biome,
		build_result.ecotone_values
	)
	if flora_result != null:
		chunk.set_flora_result(flora_result)
	return flora_result

func _build_flora_result_for_native_data(
	chunk_coord: Vector2i,
	native_data: Dictionary,
	flora_builder: ChunkFloraBuilderScript = null
) -> ChunkFloraResultScript:
	var active_flora_builder: ChunkFloraBuilderScript = flora_builder if flora_builder != null else _flora_builder
	if active_flora_builder == null or native_data.is_empty():
		return null
	var chunk_size: int = int(native_data.get("chunk_size", 0))
	var base_tile: Vector2i = native_data.get(
		"base_tile",
		WorldGenerator.chunk_to_tile_origin(chunk_coord) if WorldGenerator else Vector2i.ZERO
	) as Vector2i
	return _compute_flora_result(
		active_flora_builder,
		chunk_coord,
		chunk_size,
		base_tile,
		native_data.get("biome", PackedByteArray()) as PackedByteArray,
		native_data.get("variation", PackedByteArray()) as PackedByteArray,
		native_data.get("terrain", PackedByteArray()) as PackedByteArray,
		native_data.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array,
		native_data.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array,
		native_data.get("secondary_biome", PackedByteArray()) as PackedByteArray,
		native_data.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array
	)

func _build_flora_payload_for_native_data(
	chunk_coord: Vector2i,
	native_data: Dictionary,
	flora_builder: ChunkFloraBuilderScript = null
) -> Dictionary:
	var active_flora_builder: ChunkFloraBuilderScript = flora_builder if flora_builder != null else _flora_builder
	if active_flora_builder == null or native_data.is_empty():
		return {}
	var chunk_size: int = int(native_data.get("chunk_size", 0))
	var base_tile: Vector2i = native_data.get(
		"base_tile",
		WorldGenerator.chunk_to_tile_origin(chunk_coord) if WorldGenerator else Vector2i.ZERO
	) as Vector2i
	return _compute_flora_payload(
		active_flora_builder,
		chunk_coord,
		chunk_size,
		base_tile,
		native_data.get("biome", PackedByteArray()) as PackedByteArray,
		native_data.get("variation", PackedByteArray()) as PackedByteArray,
		native_data.get("terrain", PackedByteArray()) as PackedByteArray,
		native_data.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array,
		native_data.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array,
		native_data.get("secondary_biome", PackedByteArray()) as PackedByteArray,
		native_data.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array
	)

func _flora_result_from_payload(flora_payload: Dictionary) -> ChunkFloraResultScript:
	if flora_payload.is_empty():
		return null
	return ChunkFloraResultScript.from_serialized_payload(flora_payload)

func _build_native_flora_payload_from_placements(chunk_coord: Vector2i, native_data: Dictionary) -> Dictionary:
	if native_data.is_empty():
		return {}
	var placements: Array = native_data.get("flora_placements", []) as Array
	if placements.is_empty():
		return {}
	return ChunkFloraResultScript.build_serialized_payload_from_placements(
		chunk_coord,
		int(native_data.get("chunk_size", 0)),
		placements,
		_resolve_flora_tile_size()
	)

func _compute_flora_for_native_data(chunk: Chunk, chunk_coord: Vector2i, native_data: Dictionary) -> ChunkFloraResultScript:
	if _flora_builder == null or chunk == null or native_data.is_empty():
		return null
	var flora_result: ChunkFloraResultScript = _build_flora_result_for_native_data(chunk_coord, native_data)
	if flora_result != null:
		chunk.set_flora_result(flora_result)
	return flora_result

func _compute_flora_result(
	flora_builder: ChunkFloraBuilderScript,
	chunk_coord: Vector2i,
	chunk_size: int,
	base_tile: Vector2i,
	biome_bytes: PackedByteArray,
	variation_bytes: PackedByteArray,
	terrain_bytes: PackedByteArray,
	flora_density_values: PackedFloat32Array,
	flora_modulation_values: PackedFloat32Array,
	secondary_biome_bytes: PackedByteArray = PackedByteArray(),
	ecotone_values: PackedFloat32Array = PackedFloat32Array()
) -> ChunkFloraResultScript:
	if flora_builder == null or WorldGenerator == null or chunk_size <= 0:
		return null
	var tile_count: int = chunk_size * chunk_size
	var secondary_biome_ok: bool = secondary_biome_bytes.is_empty() or secondary_biome_bytes.size() == tile_count
	var ecotone_values_ok: bool = ecotone_values.is_empty() or ecotone_values.size() == tile_count
	if terrain_bytes.size() != tile_count \
		or biome_bytes.size() != tile_count \
		or variation_bytes.size() != tile_count \
		or flora_density_values.size() != tile_count \
		or flora_modulation_values.size() != tile_count \
		or not secondary_biome_ok \
		or not ecotone_values_ok:
		return null
	var biome_palette: Array[BiomeData] = WorldGenerator.get_registered_biomes()
	return flora_builder.compute_placements(
		chunk_coord,
		chunk_size,
		base_tile,
		terrain_bytes,
		biome_palette,
		biome_bytes,
		variation_bytes,
		flora_density_values,
		flora_modulation_values,
		secondary_biome_bytes,
		ecotone_values
	)

func _compute_flora_payload(
	flora_builder: ChunkFloraBuilderScript,
	chunk_coord: Vector2i,
	chunk_size: int,
	base_tile: Vector2i,
	biome_bytes: PackedByteArray,
	variation_bytes: PackedByteArray,
	terrain_bytes: PackedByteArray,
	flora_density_values: PackedFloat32Array,
	flora_modulation_values: PackedFloat32Array,
	secondary_biome_bytes: PackedByteArray = PackedByteArray(),
	ecotone_values: PackedFloat32Array = PackedFloat32Array()
) -> Dictionary:
	if flora_builder == null or WorldGenerator == null or chunk_size <= 0:
		return {}
	var tile_count: int = chunk_size * chunk_size
	var secondary_biome_ok: bool = secondary_biome_bytes.is_empty() or secondary_biome_bytes.size() == tile_count
	var ecotone_values_ok: bool = ecotone_values.is_empty() or ecotone_values.size() == tile_count
	if terrain_bytes.size() != tile_count \
		or biome_bytes.size() != tile_count \
		or variation_bytes.size() != tile_count \
		or flora_density_values.size() != tile_count \
		or flora_modulation_values.size() != tile_count \
		or not secondary_biome_ok \
		or not ecotone_values_ok:
		return {}
	var biome_palette: Array[BiomeData] = WorldGenerator.get_registered_biomes()
	return flora_builder.compute_payload(
		chunk_coord,
		chunk_size,
		base_tile,
		terrain_bytes,
		biome_palette,
		biome_bytes,
		variation_bytes,
		flora_density_values,
		flora_modulation_values,
		_resolve_flora_tile_size(),
		secondary_biome_bytes,
		ecotone_values
	)

func _is_native_topology_enabled() -> bool:
	return _native_topology_active

func _clear_visual_task_state() -> void:
	for task_variant: Variant in _visual_compute_active.values():
		WorkerThreadPool.wait_for_task_completion(int(task_variant))
	_visual_q_terrain_fast.clear()
	_visual_q_terrain_urgent.clear()
	_visual_q_terrain_near.clear()
	_visual_q_full_near.clear()
	_visual_q_border_fix_near.clear()
	_visual_q_border_fix_far.clear()
	_visual_q_full_far.clear()
	_visual_q_cosmetic.clear()
	_visual_task_versions.clear()
	_visual_task_pending.clear()
	_visual_task_enqueued_usec.clear()
	_visual_apply_started_usec.clear()
	_visual_convergence_started_usec.clear()
	_visual_first_pass_ready_usec.clear()
	_visual_full_ready_usec.clear()
	_visual_compute_active.clear()
	_visual_compute_waiting_tasks.clear()
	_visual_compute_mutex.lock()
	_visual_compute_results.clear()
	_visual_compute_mutex.unlock()
	_visual_scheduler_budget_exhausted_count = 0
	_visual_scheduler_starvation_incident_count = 0
	_visual_scheduler_max_urgent_wait_ms = 0.0
	_visual_scheduler_log_ticks = 0
	_visual_apply_feedback.clear()
	_visual_chunks_processed_this_tick.clear()
	_visual_chunks_processed_frame = -1

func _begin_visual_scheduler_step() -> void:
	_collect_completed_visual_compute()
	var frame_index: int = Engine.get_process_frames()
	if _visual_chunks_processed_frame != frame_index:
		_visual_chunks_processed_this_tick.clear()
		_visual_chunks_processed_frame = frame_index

func _resolve_visual_scheduler_budget_ms() -> float:
	var budget_ms: float = 4.0
	if WorldGenerator and WorldGenerator.balance:
		budget_ms = WorldGenerator.balance.visual_scheduler_budget_ms
	if not _visual_q_terrain_fast.is_empty():
		return minf(12.0, budget_ms * 2.0 + 4.0)
	if not _visual_q_terrain_urgent.is_empty():
		return minf(8.0, budget_ms * 2.0)
	if not _visual_q_terrain_near.is_empty():
		return minf(6.0, budget_ms * 1.5)
	return budget_ms

func _resolve_visual_target_apply_ms(kind: int, band: int, scheduler_budget_ms: float) -> float:
	var share: float = 0.15
	match band:
		VisualPriorityBand.TERRAIN_FAST:
			share = 0.35
		VisualPriorityBand.TERRAIN_URGENT:
			share = 0.30
		VisualPriorityBand.TERRAIN_NEAR, VisualPriorityBand.FULL_NEAR, VisualPriorityBand.BORDER_FIX_NEAR:
			share = 0.25
		VisualPriorityBand.FULL_FAR, VisualPriorityBand.BORDER_FIX_FAR:
			share = 0.18
		_:
			share = 0.15
	if kind == VisualTaskKind.TASK_BORDER_FIX:
		share *= 0.8
	return clampf(
		scheduler_budget_ms * share,
		VISUAL_ADAPTIVE_APPLY_MIN_MS,
		VISUAL_ADAPTIVE_APPLY_MAX_MS
	)

func _make_visual_apply_feedback_key(kind: int, band: int, phase_name: StringName) -> String:
	return "%d:%d:%s" % [kind, band, String(phase_name)]

func _resolve_visual_apply_safety_factor(kind: int, band: int) -> float:
	match band:
		VisualPriorityBand.TERRAIN_FAST:
			return VISUAL_ADAPTIVE_FAST_SAFETY
		VisualPriorityBand.TERRAIN_URGENT:
			return VISUAL_ADAPTIVE_URGENT_SAFETY
		VisualPriorityBand.TERRAIN_NEAR, VisualPriorityBand.FULL_NEAR, VisualPriorityBand.BORDER_FIX_NEAR:
			return VISUAL_ADAPTIVE_NEAR_SAFETY
		VisualPriorityBand.FULL_FAR, VisualPriorityBand.BORDER_FIX_FAR:
			return VISUAL_ADAPTIVE_FAR_SAFETY
		_:
			return VISUAL_ADAPTIVE_NEAR_SAFETY if kind == VisualTaskKind.TASK_FIRST_PASS else VISUAL_ADAPTIVE_FAR_SAFETY

func _resolve_visual_apply_tile_cap(kind: int, band: int, phase_name: StringName, base_tile_budget: int) -> int:
	if kind != VisualTaskKind.TASK_FIRST_PASS:
		return maxi(1, base_tile_budget)
	if band == VisualPriorityBand.TERRAIN_FAST:
		match phase_name:
			&"terrain":
				return mini(base_tile_budget, VISUAL_FAST_PHASE_TILE_CAP_TERRAIN)
			&"cover":
				return mini(base_tile_budget, VISUAL_FAST_PHASE_TILE_CAP_COVER)
			&"cliff":
				return mini(base_tile_budget, VISUAL_FAST_PHASE_TILE_CAP_CLIFF)
			_:
				return mini(base_tile_budget, VISUAL_FAST_PHASE_TILE_CAP_COVER)
	if band == VisualPriorityBand.TERRAIN_URGENT:
		match phase_name:
			&"terrain":
				return mini(base_tile_budget, VISUAL_URGENT_PHASE_TILE_CAP_TERRAIN)
			&"cover":
				return mini(base_tile_budget, VISUAL_URGENT_PHASE_TILE_CAP_COVER)
			&"cliff":
				return mini(base_tile_budget, VISUAL_URGENT_PHASE_TILE_CAP_CLIFF)
			_:
				return mini(base_tile_budget, VISUAL_URGENT_PHASE_TILE_CAP_COVER)
	return maxi(1, base_tile_budget)

func _resolve_visual_apply_tile_budget(
	kind: int,
	band: int,
	phase_name: StringName,
	base_tile_budget: int
) -> int:
	var min_tiles: int = VISUAL_ADAPTIVE_MIN_BORDER_TILES if kind == VisualTaskKind.TASK_BORDER_FIX else VISUAL_ADAPTIVE_MIN_TILES
	var max_tiles: int = maxi(min_tiles, _resolve_visual_apply_tile_cap(kind, band, phase_name, base_tile_budget))
	var feedback_key: String = _make_visual_apply_feedback_key(kind, band, phase_name)
	var feedback: Dictionary = _visual_apply_feedback.get(feedback_key, {}) as Dictionary
	if feedback.is_empty():
		return max_tiles
	var ms_per_command: float = float(feedback.get("ms_per_command", 0.0))
	var commands_per_tile: float = float(feedback.get("commands_per_tile", 0.0))
	if ms_per_command <= 0.0 or commands_per_tile <= 0.0:
		return max_tiles
	var scheduler_budget_ms: float = _resolve_visual_scheduler_budget_ms()
	var target_apply_ms: float = _resolve_visual_target_apply_ms(kind, band, scheduler_budget_ms)
	var safety_factor: float = _resolve_visual_apply_safety_factor(kind, band)
	var command_budget: int = int(floor(
		target_apply_ms * safety_factor / ms_per_command
	))
	if command_budget <= 0:
		return min_tiles
	var adaptive_tiles: int = int(floor(float(command_budget) / commands_per_tile))
	if adaptive_tiles <= 0:
		adaptive_tiles = min_tiles
	var last_apply_ms: float = float(feedback.get("last_apply_ms", 0.0))
	var last_tile_count: int = int(feedback.get("last_tile_count", 0))
	if last_apply_ms > target_apply_ms and last_tile_count > 0 and target_apply_ms > 0.0:
		var recent_scale: float = clampf(target_apply_ms / last_apply_ms, 0.0, 1.0) * safety_factor
		var recent_tiles: int = int(floor(float(last_tile_count) * recent_scale))
		if recent_tiles <= 0:
			recent_tiles = min_tiles
		adaptive_tiles = mini(adaptive_tiles, recent_tiles)
	return clampi(adaptive_tiles, min_tiles, max_tiles)

func _record_visual_apply_feedback(
	kind: int,
	band: int,
	phase_name: StringName,
	command_count: int,
	tile_count: int,
	apply_ms: float,
	scheduler_budget_ms: float
) -> void:
	if command_count <= 0 or tile_count <= 0 or apply_ms <= 0.0:
		return
	var feedback_key: String = _make_visual_apply_feedback_key(kind, band, phase_name)
	var ms_per_command: float = apply_ms / float(command_count)
	var commands_per_tile: float = float(command_count) / float(tile_count)
	var target_apply_ms: float = _resolve_visual_target_apply_ms(kind, band, scheduler_budget_ms)
	var previous: Dictionary = _visual_apply_feedback.get(feedback_key, {}) as Dictionary
	if previous.is_empty():
		_visual_apply_feedback[feedback_key] = {
			"ms_per_command": ms_per_command,
			"commands_per_tile": commands_per_tile,
			"last_apply_ms": apply_ms,
			"last_command_count": command_count,
			"last_tile_count": tile_count,
			"last_budget_ms": scheduler_budget_ms,
			"target_apply_ms": target_apply_ms,
		}
		return
	_visual_apply_feedback[feedback_key] = {
		"ms_per_command": lerpf(float(previous.get("ms_per_command", ms_per_command)), ms_per_command, VISUAL_ADAPTIVE_FEEDBACK_BLEND),
		"commands_per_tile": lerpf(float(previous.get("commands_per_tile", commands_per_tile)), commands_per_tile, VISUAL_ADAPTIVE_FEEDBACK_BLEND),
		"last_apply_ms": apply_ms,
		"last_command_count": command_count,
		"last_tile_count": tile_count,
		"last_budget_ms": scheduler_budget_ms,
		"target_apply_ms": target_apply_ms,
	}

func _resolve_visual_tiles_per_step(kind: int, band: int = VisualPriorityBand.COSMETIC) -> int:
	if WorldGenerator and WorldGenerator.balance:
		match kind:
			VisualTaskKind.TASK_FIRST_PASS:
				var first_pass_tiles: int = WorldGenerator.balance.visual_first_pass_tiles_per_step
				if band == VisualPriorityBand.TERRAIN_FAST:
					var chunk_tiles: int = maxi(1, WorldGenerator.balance.chunk_size_tiles * WorldGenerator.balance.chunk_size_tiles)
					return mini(chunk_tiles, maxi(2048, first_pass_tiles * 16))
				if band == VisualPriorityBand.TERRAIN_URGENT:
					return maxi(16, first_pass_tiles / 4)
				if band == VisualPriorityBand.TERRAIN_NEAR:
					return maxi(16, first_pass_tiles / 2)
				return first_pass_tiles
			VisualTaskKind.TASK_FULL_REDRAW:
				var full_redraw_tiles: int = WorldGenerator.balance.visual_full_redraw_tiles_per_step
				if band == VisualPriorityBand.FULL_FAR:
					return maxi(16, full_redraw_tiles / 4)
				if band == VisualPriorityBand.FULL_NEAR:
					return maxi(16, full_redraw_tiles / 2)
				return full_redraw_tiles
			VisualTaskKind.TASK_BORDER_FIX:
				var border_fix_tiles: int = WorldGenerator.balance.visual_border_fix_tiles_per_step
				if band == VisualPriorityBand.BORDER_FIX_FAR:
					return maxi(8, border_fix_tiles / 2)
				return border_fix_tiles
			_:
				return WorldGenerator.balance.visual_cosmetic_tiles_per_step
	return 64

func _resolve_visual_max_tasks_per_tick(kind: int, band: int = VisualPriorityBand.COSMETIC) -> int:
	if WorldGenerator and WorldGenerator.balance:
		match kind:
			VisualTaskKind.TASK_FIRST_PASS:
				var first_pass_max: int = maxi(1, WorldGenerator.balance.visual_first_pass_max_tasks_per_tick)
				if band == VisualPriorityBand.TERRAIN_FAST:
					return 1
				if band == VisualPriorityBand.TERRAIN_URGENT:
					return maxi(1, mini(2, first_pass_max))
				return first_pass_max
			VisualTaskKind.TASK_FULL_REDRAW:
				return maxi(1, WorldGenerator.balance.visual_full_redraw_max_tasks_per_tick)
			VisualTaskKind.TASK_BORDER_FIX:
				var border_fix_max: int = maxi(1, WorldGenerator.balance.visual_full_redraw_max_tasks_per_tick)
				if band == VisualPriorityBand.BORDER_FIX_FAR:
					return maxi(1, border_fix_max / 2)
				return border_fix_max
	return 999999

func _resolve_visual_urgent_queue_cap() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.visual_first_pass_max_tasks_per_tick)
	return 4

func _enforce_visual_urgent_queue_cap() -> void:
	while _visual_q_terrain_urgent.size() > _resolve_visual_urgent_queue_cap():
		var task: Dictionary = _visual_q_terrain_urgent.pop_back()
		task["priority_band"] = VisualPriorityBand.TERRAIN_NEAR
		_visual_q_terrain_near.append(task)

func _make_visual_task_key(coord: Vector2i, z_level: int, kind: int) -> String:
	return "%d:%d:%d:%d" % [coord.x, coord.y, z_level, kind]

func _make_visual_chunk_key(coord: Vector2i, z_level: int) -> String:
	return "%d:%d:%d" % [coord.x, coord.y, z_level]

func _is_forward_ring1_visual_chunk(coord: Vector2i) -> bool:
	if _player_chunk_motion == Vector2i.ZERO:
		return false
	var delta: Vector2i = coord - _player_chunk
	if max(abs(delta.x), abs(delta.y)) != 1:
		return false
	if delta.y == 0 and _player_chunk_motion.x != 0 and delta.x == signi(_player_chunk_motion.x):
		return true
	if delta.x == 0 and _player_chunk_motion.y != 0 and delta.y == signi(_player_chunk_motion.y):
		return true
	return false

func _is_protected_first_pass_chunk(coord: Vector2i, z_level: int) -> bool:
	if z_level != _active_z:
		return false
	if coord == _player_chunk:
		return true
	return _is_forward_ring1_visual_chunk(coord)

func _resolve_visual_band(coord: Vector2i, z_level: int, kind: int) -> int:
	if kind == VisualTaskKind.TASK_BORDER_FIX:
		if z_level != _active_z:
			return VisualPriorityBand.BORDER_FIX_FAR
		var border_ring: int = _chunk_chebyshev_distance(coord, _player_chunk)
		if border_ring <= 2:
			return VisualPriorityBand.BORDER_FIX_NEAR
		return VisualPriorityBand.BORDER_FIX_FAR
	if kind == VisualTaskKind.TASK_COSMETIC:
		return VisualPriorityBand.COSMETIC
	if z_level != _active_z:
		return VisualPriorityBand.FULL_FAR
	var ring: int = _chunk_chebyshev_distance(coord, _player_chunk)
	if kind == VisualTaskKind.TASK_FIRST_PASS:
		if _is_protected_first_pass_chunk(coord, z_level):
			return VisualPriorityBand.TERRAIN_FAST
		if ring == 1:
			return VisualPriorityBand.TERRAIN_NEAR
		if ring == 2:
			return VisualPriorityBand.TERRAIN_NEAR
		return VisualPriorityBand.FULL_FAR
	if ring <= 2:
		return VisualPriorityBand.FULL_NEAR
	return VisualPriorityBand.FULL_FAR

func _build_visual_task(coord: Vector2i, z_level: int, kind: int, version: int) -> Dictionary:
	return {
		"chunk_coord": coord,
		"z": z_level,
		"kind": kind,
		"priority_band": _resolve_visual_band(coord, z_level, kind),
		"camera_score": float(_chunk_chebyshev_distance(coord, _player_chunk)),
		"movement_score": float(_player_chunk_motion.length_squared()),
		"eta_score": 0.0,
		"invalidation_version": version,
		"wait_recorded": false,
	}

func _retag_visual_task(task: Dictionary) -> void:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z))
	var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
	var old_band: int = int(task.get("priority_band", VisualPriorityBand.COSMETIC))
	var new_band: int = _resolve_visual_band(coord, z_level, kind)
	task["priority_band"] = new_band
	task["camera_score"] = float(_chunk_chebyshev_distance(coord, _player_chunk))
	task["movement_score"] = float(_player_chunk_motion.length_squared())
	if (new_band == VisualPriorityBand.TERRAIN_FAST or new_band == VisualPriorityBand.TERRAIN_URGENT) \
		and old_band != new_band:
		var key: String = _make_visual_task_key(coord, z_level, kind)
		_visual_task_enqueued_usec[key] = Time.get_ticks_usec()
		task["wait_recorded"] = false

func _get_visual_queue_for_band(band: int) -> Array[Dictionary]:
	match band:
		VisualPriorityBand.TERRAIN_FAST:
			return _visual_q_terrain_fast
		VisualPriorityBand.TERRAIN_URGENT:
			return _visual_q_terrain_urgent
		VisualPriorityBand.TERRAIN_NEAR:
			return _visual_q_terrain_near
		VisualPriorityBand.FULL_NEAR:
			return _visual_q_full_near
		VisualPriorityBand.BORDER_FIX_NEAR:
			return _visual_q_border_fix_near
		VisualPriorityBand.BORDER_FIX_FAR:
			return _visual_q_border_fix_far
		VisualPriorityBand.FULL_FAR:
			return _visual_q_full_far
		_:
			return _visual_q_cosmetic

func _push_visual_task(task: Dictionary) -> void:
	var band: int = int(task.get("priority_band", VisualPriorityBand.COSMETIC))
	var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
	if band == VisualPriorityBand.TERRAIN_URGENT \
		and kind == VisualTaskKind.TASK_FIRST_PASS \
		and _visual_q_terrain_urgent.size() >= _resolve_visual_urgent_queue_cap():
		band = VisualPriorityBand.TERRAIN_NEAR
		task["priority_band"] = band
	var queue: Array[Dictionary] = _get_visual_queue_for_band(band)
	queue.append(task)
	if kind == VisualTaskKind.TASK_FIRST_PASS:
		_enforce_visual_urgent_queue_cap()

func _refresh_visual_task_priorities() -> void:
	var all_tasks: Array[Dictionary] = []
	for queue: Array[Dictionary] in [
		_visual_q_terrain_fast,
		_visual_q_terrain_urgent,
		_visual_q_terrain_near,
		_visual_q_full_near,
		_visual_q_border_fix_near,
		_visual_q_border_fix_far,
		_visual_q_full_far,
		_visual_q_cosmetic,
	]:
		while not queue.is_empty():
			var task: Dictionary = queue.pop_front()
			_retag_visual_task(task)
			all_tasks.append(task)
	for task: Dictionary in all_tasks:
		_push_visual_task(task)

func _mark_visual_apply_started(coord: Vector2i, z_level: int) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	if not _visual_apply_started_usec.has(chunk_key):
		_visual_apply_started_usec[chunk_key] = Time.get_ticks_usec()
	_mark_visual_convergence_started(coord, z_level)

func _mark_visual_convergence_started(coord: Vector2i, z_level: int, force_reset: bool = false) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	if not force_reset and _visual_convergence_started_usec.has(chunk_key):
		return
	_visual_convergence_started_usec[chunk_key] = Time.get_ticks_usec()

func _mark_visual_first_pass_ready(coord: Vector2i, z_level: int) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	if _visual_first_pass_ready_usec.has(chunk_key):
		return
	var now_usec: int = Time.get_ticks_usec()
	_visual_first_pass_ready_usec[chunk_key] = now_usec
	if _visual_apply_started_usec.has(chunk_key):
		var latency_ms: float = float(now_usec - int(_visual_apply_started_usec[chunk_key])) / 1000.0
		WorldPerfProbe.record("stream.chunk_first_pass_ms %s@z%d" % [coord, z_level], latency_ms)

func _mark_visual_full_ready(coord: Vector2i, z_level: int) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	if _visual_full_ready_usec.has(chunk_key):
		return
	var now_usec: int = Time.get_ticks_usec()
	_visual_full_ready_usec[chunk_key] = now_usec
	if _visual_convergence_started_usec.has(chunk_key):
		var latency_ms: float = float(now_usec - int(_visual_convergence_started_usec[chunk_key])) / 1000.0
		WorldPerfProbe.record("stream.chunk_full_redraw_ms %s@z%d" % [coord, z_level], latency_ms)
	elif _visual_apply_started_usec.has(chunk_key):
		var latency_ms: float = float(now_usec - int(_visual_apply_started_usec[chunk_key])) / 1000.0
		WorldPerfProbe.record("stream.chunk_full_redraw_ms %s@z%d" % [coord, z_level], latency_ms)

func _clear_visual_full_ready(coord: Vector2i, z_level: int) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	_visual_full_ready_usec.erase(chunk_key)

func _invalidate_boot_visual_complete(coord: Vector2i, z_level: int) -> void:
	if _boot_complete_flag or z_level != _boot_compute_z:
		return
	if not _boot_chunk_states.has(coord):
		return
	if int(_boot_chunk_states[coord]) >= BootChunkState.VISUAL_COMPLETE:
		_boot_set_chunk_state(coord, BootChunkState.APPLIED)

func _sync_chunk_visibility_for_publication(chunk: Chunk) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	chunk.visible = chunk._is_visibility_publication_ready()

func _try_finalize_chunk_visual_convergence(chunk: Chunk, z_level: int) -> bool:
	if chunk == null or not is_instance_valid(chunk):
		return false
	chunk._refresh_interior_macro_layer_if_dirty()
	_sync_chunk_visibility_for_publication(chunk)
	if chunk.is_first_pass_ready():
		_mark_visual_first_pass_ready(chunk.chunk_coord, z_level)
	if not chunk._can_publish_full_redraw_ready():
		return false
	chunk._mark_visual_full_redraw_ready()
	_sync_chunk_visibility_for_publication(chunk)
	_mark_visual_full_ready(chunk.chunk_coord, z_level)
	if not _boot_complete_flag and _boot_chunk_states.has(chunk.chunk_coord):
		_boot_on_chunk_redraw_progress(chunk)
	return true

func _invalidate_chunk_visual_convergence(chunk: Chunk, z_level: int) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	_mark_visual_convergence_started(chunk.chunk_coord, z_level, true)
	chunk._mark_visual_convergence_owed()
	_clear_visual_full_ready(chunk.chunk_coord, z_level)
	_invalidate_boot_visual_complete(chunk.chunk_coord, z_level)

func _ensure_chunk_full_redraw_task(chunk: Chunk, z_level: int, invalidate: bool = false) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	if invalidate:
		_invalidate_chunk_visual_convergence(chunk, z_level)
	if chunk.is_full_redraw_ready() and not invalidate:
		_mark_visual_full_ready(chunk.chunk_coord, z_level)
		return
	if not chunk.needs_full_redraw():
		_try_finalize_chunk_visual_convergence(chunk, z_level)
		return
	if chunk.is_redraw_complete():
		_try_finalize_chunk_visual_convergence(chunk, z_level)
		return
	chunk._mark_visual_full_redraw_pending()
	_ensure_visual_task(chunk, z_level, VisualTaskKind.TASK_FULL_REDRAW, invalidate)

func _ensure_chunk_border_fix_task(chunk: Chunk, z_level: int, invalidate: bool = false) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	if chunk._pending_border_dirty.is_empty():
		_try_finalize_chunk_visual_convergence(chunk, z_level)
		return
	if invalidate:
		_invalidate_chunk_visual_convergence(chunk, z_level)
	if chunk.needs_full_redraw() and not chunk.is_redraw_complete():
		_ensure_visual_task(chunk, z_level, VisualTaskKind.TASK_FULL_REDRAW, invalidate)
	var border_fix_key: String = _make_visual_task_key(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX)
	if _visual_task_pending.has(border_fix_key):
		return
	_ensure_visual_task(chunk, z_level, VisualTaskKind.TASK_BORDER_FIX)

func _ensure_visual_task(chunk: Chunk, z_level: int, kind: int, invalidate: bool = false) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	var key: String = _make_visual_task_key(chunk.chunk_coord, z_level, kind)
	if _visual_task_pending.has(key) and not invalidate:
		return
	var version: int = int(_visual_task_versions.get(key, 0)) + 1
	_visual_task_versions[key] = version
	_visual_task_pending[key] = version
	_visual_task_enqueued_usec[key] = Time.get_ticks_usec()
	_push_visual_task(_build_visual_task(chunk.chunk_coord, z_level, kind, version))

func _schedule_chunk_visual_work(chunk: Chunk, z_level: int) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	_mark_visual_apply_started(chunk.chunk_coord, z_level)
	if not chunk.is_first_pass_ready():
		_ensure_visual_task(chunk, z_level, VisualTaskKind.TASK_FIRST_PASS)
	else:
		_mark_visual_first_pass_ready(chunk.chunk_coord, z_level)
		_ensure_chunk_full_redraw_task(chunk, z_level)
	_sync_chunk_visibility_for_publication(chunk)
	if not chunk._pending_border_dirty.is_empty():
		_ensure_chunk_border_fix_task(chunk, z_level)
	else:
		_try_finalize_chunk_visual_convergence(chunk, z_level)

func _worker_prepare_visual_batch(task_key: String, request: Dictionary) -> void:
	if _shutdown_in_progress:
		return
	var started_usec: int = Time.get_ticks_usec()
	var batch: Dictionary = Chunk.compute_visual_batch(request)
	if _shutdown_in_progress:
		return
	batch["task_key"] = task_key
	batch["chunk_coord"] = request.get("chunk_coord", Vector2i.ZERO)
	batch["z"] = int(request.get("z", INVALID_Z_LEVEL))
	batch["invalidation_version"] = int(request.get("invalidation_version", -1))
	batch["tile_count"] = int(request.get("tile_count", batch.get("tile_count", 0)))
	batch["requested_tile_budget"] = int(request.get("requested_tile_budget", 0))
	batch["visual_budget_ms"] = float(request.get("requested_visual_budget_ms", 0.0))
	batch["target_apply_ms"] = float(request.get("requested_target_apply_ms", 0.0))
	batch["prepare_ms"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_visual_compute_mutex.lock()
	_visual_compute_results[task_key] = batch
	_visual_compute_mutex.unlock()

func _submit_visual_compute(task: Dictionary, chunk: Chunk, tile_budget: int) -> bool:
	if chunk == null or not is_instance_valid(chunk):
		return false
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z))
	var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
	var band: int = int(task.get("priority_band", VisualPriorityBand.COSMETIC))
	var key: String = _make_visual_task_key(coord, z_level, kind)
	if _visual_compute_active.has(key) or _visual_compute_waiting_tasks.has(key):
		return true
	var request: Dictionary = {}
	var requested_tile_budget: int = maxi(1, tile_budget)
	match kind:
		VisualTaskKind.TASK_FIRST_PASS, VisualTaskKind.TASK_FULL_REDRAW:
			if chunk.supports_worker_visual_phase():
				var phase_name: StringName = chunk.get_redraw_phase_name()
				requested_tile_budget = _resolve_visual_apply_tile_budget(kind, band, phase_name, tile_budget)
				request = chunk.build_visual_phase_batch(requested_tile_budget)
		VisualTaskKind.TASK_BORDER_FIX:
			var dirty_tile_budget: int = mini(tile_budget, BORDER_FIX_REDRAW_MICRO_BATCH_TILES)
			requested_tile_budget = _resolve_visual_apply_tile_budget(kind, band, &"dirty", dirty_tile_budget)
			request = chunk.build_visual_dirty_batch(chunk._pending_border_dirty, requested_tile_budget)
		_:
			return false
	if request.is_empty():
		return false
	var requested_visual_budget_ms: float = _resolve_visual_scheduler_budget_ms()
	request["tile_count"] = int((request.get("tiles", []) as Array).size())
	request["requested_tile_budget"] = requested_tile_budget
	request["requested_visual_budget_ms"] = requested_visual_budget_ms
	request["requested_target_apply_ms"] = _resolve_visual_target_apply_ms(kind, band, requested_visual_budget_ms)
	if bool(request.get("skip_worker_compute", false)):
		var immediate_task: Dictionary = task.duplicate(true)
		var prepared_batch: Dictionary = Chunk.compute_visual_batch(request)
		prepared_batch["tile_count"] = int(request.get("tile_count", prepared_batch.get("tile_count", 0)))
		prepared_batch["requested_tile_budget"] = requested_tile_budget
		prepared_batch["visual_budget_ms"] = requested_visual_budget_ms
		prepared_batch["target_apply_ms"] = float(request.get("requested_target_apply_ms", 0.0))
		immediate_task["prepared_batch"] = prepared_batch
		_push_visual_task(immediate_task)
		return true
	request["chunk_coord"] = coord
	request["z"] = z_level
	request["invalidation_version"] = int(task.get("invalidation_version", -1))
	var task_id: int = WorkerThreadPool.add_task(_worker_prepare_visual_batch.bind(key, request))
	_visual_compute_active[key] = task_id
	_visual_compute_waiting_tasks[key] = task
	return true

func _collect_completed_visual_compute() -> void:
	if _visual_compute_active.is_empty():
		return
	var completed_keys: Array[String] = []
	for key_variant: Variant in _visual_compute_active.keys():
		var key: String = str(key_variant)
		var task_id: int = int(_visual_compute_active.get(key, -1))
		if task_id >= 0 and WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			completed_keys.append(key)
	for key: String in completed_keys:
		_visual_compute_active.erase(key)
		_visual_compute_mutex.lock()
		var batch: Dictionary = _visual_compute_results.get(key, {}) as Dictionary
		_visual_compute_results.erase(key)
		_visual_compute_mutex.unlock()
		var waiting_task: Dictionary = _visual_compute_waiting_tasks.get(key, {}) as Dictionary
		_visual_compute_waiting_tasks.erase(key)
		if batch.is_empty() or waiting_task.is_empty():
			continue
		if int(_visual_task_pending.get(key, -1)) != int(batch.get("invalidation_version", -1)):
			continue
		var prepare_ms: float = float(batch.get("prepare_ms", 0.0))
		if prepare_ms >= 2.0:
			WorldPerfProbe.record(
				"ChunkManager.streaming_redraw_prepare_step.%s" % [String(batch.get("phase_name", &"done"))],
				prepare_ms
			)
		waiting_task["prepared_batch"] = batch
		_push_visual_task(waiting_task)

func _has_pending_visual_tasks() -> bool:
	return not _visual_q_terrain_fast.is_empty() \
		or not _visual_q_terrain_urgent.is_empty() \
		or not _visual_q_terrain_near.is_empty() \
		or not _visual_q_full_near.is_empty() \
		or not _visual_q_border_fix_near.is_empty() \
		or not _visual_q_border_fix_far.is_empty() \
		or not _visual_q_full_far.is_empty() \
		or not _visual_q_cosmetic.is_empty() \
		or not _visual_compute_active.is_empty() \
		or not _visual_compute_waiting_tasks.is_empty()

func _pop_allowed_visual_task_from_queue(queue: Array[Dictionary], processed_by_kind: Dictionary) -> Dictionary:
	var queue_size: int = queue.size()
	for _i: int in range(queue_size):
		if queue.is_empty():
			break
		var task: Dictionary = queue.pop_front()
		var chunk_key: String = _make_visual_chunk_key(
			task.get("chunk_coord", Vector2i.ZERO) as Vector2i,
			int(task.get("z", _active_z))
		)
		if _visual_chunks_processed_this_tick.has(chunk_key):
			queue.append(task)
			continue
		var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
		var band: int = int(task.get("priority_band", VisualPriorityBand.COSMETIC))
		var processed_count: int = int(processed_by_kind.get(kind, 0))
		if processed_count < _resolve_visual_max_tasks_per_tick(kind, band):
			return task
		queue.append(task)
	return {}

func _pop_next_visual_task(processed_by_kind: Dictionary) -> Dictionary:
	for queue: Array[Dictionary] in [
		_visual_q_terrain_fast,
		_visual_q_terrain_urgent,
		_visual_q_terrain_near,
		_visual_q_full_near,
		_visual_q_border_fix_near,
		_visual_q_full_far,
		_visual_q_border_fix_far,
		_visual_q_cosmetic,
	]:
		var task: Dictionary = _pop_allowed_visual_task_from_queue(queue, processed_by_kind)
		if not task.is_empty():
			return task
	return {}

func _get_visual_task_chunk(task: Dictionary) -> Chunk:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z))
	var loaded_for_z: Dictionary = _z_chunks.get(z_level, {})
	return loaded_for_z.get(coord) as Chunk

func _requeue_visual_task(task: Dictionary) -> void:
	_retag_visual_task(task)
	_push_visual_task(task)

func _clear_visual_task(task: Dictionary) -> void:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z))
	var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
	var key: String = _make_visual_task_key(coord, z_level, kind)
	_visual_task_pending.erase(key)
	_visual_task_enqueued_usec.erase(key)

func _record_visual_task_wait(task: Dictionary) -> void:
	var band: int = int(task.get("priority_band", VisualPriorityBand.COSMETIC))
	if band != VisualPriorityBand.TERRAIN_FAST and band != VisualPriorityBand.TERRAIN_URGENT:
		return
	if bool(task.get("wait_recorded", false)):
		return
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z))
	var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
	var key: String = _make_visual_task_key(coord, z_level, kind)
	if not _visual_task_enqueued_usec.has(key):
		return
	if _is_boot_in_progress:
		# Boot redraws intentionally batch under a different gate. Reset the
		# baseline so runtime starvation telemetry starts after handoff.
		_visual_task_enqueued_usec[key] = Time.get_ticks_usec()
		return
	var wait_ms: float = float(Time.get_ticks_usec() - int(_visual_task_enqueued_usec[key])) / 1000.0
	task["wait_recorded"] = true
	_visual_scheduler_max_urgent_wait_ms = maxf(_visual_scheduler_max_urgent_wait_ms, wait_ms)
	if band == VisualPriorityBand.TERRAIN_FAST:
		WorldPerfProbe.record("Scheduler.fast_visual_wait_ms", wait_ms)
	WorldPerfProbe.record("Scheduler.urgent_visual_wait_ms", wait_ms)
	WorldPerfProbe.record("scheduler.max_urgent_wait_ms", wait_ms)
	if wait_ms > 100.0:
		_visual_scheduler_starvation_incident_count += 1
		WorldPerfProbe.record("scheduler.starvation_incident_count", 1.0)

func _run_chunk_redraw_compat(chunk: Chunk, desired_tiles: int, deadline_usec: int, stop_at_terrain_ready: bool) -> bool:
	if chunk == null or not is_instance_valid(chunk):
		return false
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles if WorldGenerator and WorldGenerator.balance else 64
	var legacy_tiles_per_call: int = WorldGenerator.balance.chunk_redraw_tiles_per_step if WorldGenerator and WorldGenerator.balance else chunk_size
	var rows_per_call: int = maxi(1, ceili(float(legacy_tiles_per_call) / float(chunk_size)))
	var compatibility_calls: int = maxi(1, ceili(float(maxi(1, desired_tiles)) / float(maxi(1, legacy_tiles_per_call))))
	var phase_name: StringName = chunk.get_redraw_phase_name()
	var step_started_usec: int = Time.get_ticks_usec()
	var is_complete: bool = false
	for _i: int in range(compatibility_calls):
		is_complete = chunk.continue_redraw(rows_per_call)
		_sync_chunk_visibility_for_publication(chunk)
		_boot_on_chunk_redraw_progress(chunk)
		if is_complete:
			break
		if stop_at_terrain_ready and chunk.is_first_pass_ready():
			break
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
			break
	var step_ms: float = float(Time.get_ticks_usec() - step_started_usec) / 1000.0
	if step_ms >= 2.0:
		WorldPerfProbe.record("ChunkManager.streaming_redraw_step.%s" % [String(phase_name)], step_ms)
	if stop_at_terrain_ready:
		return not chunk.is_first_pass_ready() and not is_complete
	return not is_complete

func _process_border_fix_task(chunk: Chunk, tile_budget: int, deadline_usec: int) -> bool:
	if chunk == null or not is_instance_valid(chunk) or chunk._pending_border_dirty.is_empty():
		return false
	var remaining_budget: int = maxi(1, tile_budget)
	while remaining_budget > 0 and not chunk._pending_border_dirty.is_empty():
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
			return true
		var dirty_batch: Dictionary = {}
		var processed_keys: Array[Vector2i] = []
		var micro_batch_limit: int = mini(remaining_budget, BORDER_FIX_REDRAW_MICRO_BATCH_TILES)
		for local_tile: Vector2i in chunk._pending_border_dirty.keys():
			if dirty_batch.size() >= micro_batch_limit:
				break
			dirty_batch[local_tile] = true
			processed_keys.append(local_tile)
		if dirty_batch.is_empty():
			return not chunk._pending_border_dirty.is_empty()
		chunk._redraw_dirty_tiles(dirty_batch)
		for local_tile: Vector2i in processed_keys:
			chunk._pending_border_dirty.erase(local_tile)
		remaining_budget -= dirty_batch.size()
	return not chunk._pending_border_dirty.is_empty()

func _emit_visual_scheduler_tick_log(processed_count: int, budget_exhausted: bool) -> void:
	if processed_count <= 0 and not budget_exhausted and not _has_pending_visual_tasks():
		return
	WorldPerfProbe.record("scheduler.visual_tasks_processed", float(processed_count))
	WorldPerfProbe.record("scheduler.visual_queue_depth.terrain_fast", float(_visual_q_terrain_fast.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.terrain_urgent", float(_visual_q_terrain_urgent.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.terrain_near", float(_visual_q_terrain_near.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.full_near", float(_visual_q_full_near.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.border_fix_near", float(_visual_q_border_fix_near.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.border_fix_far", float(_visual_q_border_fix_far.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.full_far", float(_visual_q_full_far.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.cosmetic", float(_visual_q_cosmetic.size()))
	_visual_scheduler_log_ticks += 1

func _process_visual_task(task: Dictionary, deadline_usec: int) -> int:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z))
	var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
	var key: String = _make_visual_task_key(coord, z_level, kind)
	if int(_visual_task_pending.get(key, -1)) != int(task.get("invalidation_version", -1)):
		# Stale task from an older invalidation version. Leave the current
		# pending version intact and drop only this queue item.
		return VisualTaskRunState.DROPPED
	var chunk: Chunk = _get_visual_task_chunk(task)
	if chunk == null or not is_instance_valid(chunk):
		_clear_visual_task(task)
		return VisualTaskRunState.DROPPED
	_record_visual_task_wait(task)
	var band: int = int(task.get("priority_band", VisualPriorityBand.COSMETIC))
	var prepared_batch: Dictionary = task.get("prepared_batch", {}) as Dictionary
	match kind:
		VisualTaskKind.TASK_FIRST_PASS:
			if prepared_batch.is_empty() and _submit_visual_compute(task, chunk, _resolve_visual_tiles_per_step(kind, band)):
				return VisualTaskRunState.DROPPED
			var first_pass_did_apply: bool = false
			if not prepared_batch.is_empty():
				var apply_started_usec: int = Time.get_ticks_usec()
				if not chunk.apply_visual_phase_batch(prepared_batch):
					task.erase("prepared_batch")
					return VisualTaskRunState.REQUEUE
				first_pass_did_apply = true
				var apply_ms: float = float(Time.get_ticks_usec() - apply_started_usec) / 1000.0
				_record_visual_apply_feedback(
					kind,
					band,
					StringName(prepared_batch.get("phase_name", &"done")),
					int(prepared_batch.get("command_count", 0)),
					int(prepared_batch.get("tile_count", 0)),
					apply_ms,
					float(prepared_batch.get("visual_budget_ms", _resolve_visual_scheduler_budget_ms()))
				)
				if apply_ms >= 1.0:
					WorldPerfProbe.record(
						"ChunkManager.streaming_redraw_step.%s" % [String(prepared_batch.get("phase_name", &"done"))],
						apply_ms
				)
				_boot_on_chunk_redraw_progress(chunk)
			else:
				_run_chunk_redraw_compat(chunk, _resolve_visual_tiles_per_step(kind, band), deadline_usec, true)
				first_pass_did_apply = true
			if first_pass_did_apply:
				_visual_chunks_processed_this_tick[_make_visual_chunk_key(coord, z_level)] = true
			_sync_chunk_visibility_for_publication(chunk)
			if chunk.is_first_pass_ready():
				_mark_visual_first_pass_ready(coord, z_level)
				_clear_visual_task(task)
				_ensure_chunk_full_redraw_task(chunk, z_level)
				if not chunk._pending_border_dirty.is_empty():
					_ensure_chunk_border_fix_task(chunk, z_level)
				else:
					_try_finalize_chunk_visual_convergence(chunk, z_level)
				return VisualTaskRunState.COMPLETED
			task.erase("prepared_batch")
			return VisualTaskRunState.REQUEUE
		VisualTaskKind.TASK_FULL_REDRAW:
			chunk._mark_visual_full_redraw_pending()
			if prepared_batch.is_empty() and _submit_visual_compute(task, chunk, _resolve_visual_tiles_per_step(kind, band)):
				return VisualTaskRunState.DROPPED
			var full_has_more: bool = true
			var full_redraw_did_apply: bool = false
			if not prepared_batch.is_empty():
				var full_apply_started_usec: int = Time.get_ticks_usec()
				if not chunk.apply_visual_phase_batch(prepared_batch):
					task.erase("prepared_batch")
					return VisualTaskRunState.REQUEUE
				full_redraw_did_apply = true
				var full_apply_ms: float = float(Time.get_ticks_usec() - full_apply_started_usec) / 1000.0
				_record_visual_apply_feedback(
					kind,
					band,
					StringName(prepared_batch.get("phase_name", &"done")),
					int(prepared_batch.get("command_count", 0)),
					int(prepared_batch.get("tile_count", 0)),
					full_apply_ms,
					float(prepared_batch.get("visual_budget_ms", _resolve_visual_scheduler_budget_ms()))
				)
				if full_apply_ms >= 1.0:
					WorldPerfProbe.record(
						"ChunkManager.streaming_redraw_step.%s" % [String(prepared_batch.get("phase_name", &"done"))],
						full_apply_ms
				)
				full_has_more = not chunk.is_redraw_complete()
			else:
				full_has_more = _run_chunk_redraw_compat(chunk, _resolve_visual_tiles_per_step(kind, band), deadline_usec, false)
				full_redraw_did_apply = true
			if full_redraw_did_apply:
				_visual_chunks_processed_this_tick[_make_visual_chunk_key(coord, z_level)] = true
			_sync_chunk_visibility_for_publication(chunk)
			if not full_has_more or chunk.is_redraw_complete():
				_clear_visual_task(task)
				if not chunk._pending_border_dirty.is_empty():
					_ensure_chunk_border_fix_task(chunk, z_level)
				else:
					_try_finalize_chunk_visual_convergence(chunk, z_level)
				return VisualTaskRunState.COMPLETED
			task.erase("prepared_batch")
			return VisualTaskRunState.REQUEUE
		VisualTaskKind.TASK_BORDER_FIX:
			if prepared_batch.is_empty() and _submit_visual_compute(task, chunk, _resolve_visual_tiles_per_step(kind, band)):
				return VisualTaskRunState.DROPPED
			var border_has_more: bool = true
			var border_fix_did_apply: bool = false
			if not prepared_batch.is_empty():
				var border_apply_started_usec: int = Time.get_ticks_usec()
				if not chunk.apply_visual_dirty_batch(prepared_batch):
					task.erase("prepared_batch")
					return VisualTaskRunState.REQUEUE
				border_fix_did_apply = true
				for tile_variant: Variant in prepared_batch.get("tiles", []):
					chunk._pending_border_dirty.erase(tile_variant as Vector2i)
				var border_apply_ms: float = float(Time.get_ticks_usec() - border_apply_started_usec) / 1000.0
				_record_visual_apply_feedback(
					kind,
					band,
					StringName(prepared_batch.get("phase_name", &"dirty")),
					int(prepared_batch.get("command_count", 0)),
					int(prepared_batch.get("tile_count", 0)),
					border_apply_ms,
					float(prepared_batch.get("visual_budget_ms", _resolve_visual_scheduler_budget_ms()))
				)
				if border_apply_ms >= 1.0:
					WorldPerfProbe.record("ChunkManager.streaming_redraw_step.dirty", border_apply_ms)
				border_has_more = not chunk._pending_border_dirty.is_empty()
			else:
				border_has_more = _process_border_fix_task(chunk, _resolve_visual_tiles_per_step(kind, band), deadline_usec)
				border_fix_did_apply = true
			if border_fix_did_apply:
				_visual_chunks_processed_this_tick[_make_visual_chunk_key(coord, z_level)] = true
			if not border_has_more:
				if _visual_task_enqueued_usec.has(key):
					var latency_ms: float = float(Time.get_ticks_usec() - int(_visual_task_enqueued_usec[key])) / 1000.0
					WorldPerfProbe.record("stream.chunk_border_fix_ms %s@z%d" % [coord, z_level], latency_ms)
				_clear_visual_task(task)
				_try_finalize_chunk_visual_convergence(chunk, z_level)
				return VisualTaskRunState.COMPLETED
			task.erase("prepared_batch")
			return VisualTaskRunState.REQUEUE
		_:
			_clear_visual_task(task)
			return VisualTaskRunState.DROPPED

func _process_one_visual_task(deadline_usec: int, processed_by_kind: Dictionary) -> int:
	var task: Dictionary = _pop_next_visual_task(processed_by_kind)
	if task.is_empty():
		return -1
	var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
	var run_state: int = _process_visual_task(task, deadline_usec)
	match run_state:
		VisualTaskRunState.REQUEUE:
			processed_by_kind[kind] = int(processed_by_kind.get(kind, 0)) + 1
			_requeue_visual_task(task)
			return 1
		VisualTaskRunState.COMPLETED:
			processed_by_kind[kind] = int(processed_by_kind.get(kind, 0)) + 1
			return 1
		_:
			return 0

func _run_visual_scheduler(max_usec: int, stop_after_processed_task: bool) -> bool:
	var budget_usec: int = maxi(0, max_usec)
	if budget_usec <= 0:
		budget_usec = int(_resolve_visual_scheduler_budget_ms() * 1000.0)
	_begin_visual_scheduler_step()
	var started_usec: int = Time.get_ticks_usec()
	var deadline_usec: int = started_usec + budget_usec if budget_usec > 0 else 0
	var processed_by_kind: Dictionary = {}
	var processed_count: int = 0
	var budget_exhausted: bool = false
	while _has_pending_visual_tasks():
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
			budget_exhausted = true
			break
		var processed_delta: int = _process_one_visual_task(deadline_usec, processed_by_kind)
		if processed_delta < 0:
			break
		processed_count += processed_delta
		if stop_after_processed_task and processed_delta > 0:
			break
	var used_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	if budget_exhausted:
		_visual_scheduler_budget_exhausted_count += 1
		WorldPerfProbe.record("scheduler.visual_budget_exhausted_count", 1.0)
	_emit_visual_scheduler_tick_log(processed_count, budget_exhausted)
	_maybe_log_player_chunk_visual_status("scheduler", used_ms, budget_exhausted)
	return _has_pending_visual_tasks()

func _tick_visuals_budget(max_usec: int) -> bool:
	return _run_visual_scheduler(max_usec, false)

func _tick_visuals() -> bool:
	if _shutdown_in_progress:
		return false
	if _is_boot_in_progress:
		return false
	return _run_visual_scheduler(int(_resolve_visual_scheduler_budget_ms() * 1000.0), true)

func _reset_visual_runtime_telemetry() -> void:
	var now_usec: int = Time.get_ticks_usec()
	for task_key: Variant in _visual_task_pending.keys():
		_visual_task_enqueued_usec[str(task_key)] = now_usec
	_visual_scheduler_budget_exhausted_count = 0
	_visual_scheduler_starvation_incident_count = 0
	_visual_scheduler_max_urgent_wait_ms = 0.0
	_visual_scheduler_log_ticks = 0
	_visual_apply_feedback.clear()
	_visual_chunks_processed_this_tick.clear()
	_visual_chunks_processed_frame = -1
	_player_chunk_diag_last_usec = 0
	_player_chunk_diag_last_signature = ""

func _get_diag_age_ms(source: Dictionary, key: Variant) -> float:
	if not source.has(key):
		return -1.0
	return float(Time.get_ticks_usec() - int(source[key])) / 1000.0

func _get_visual_task_age_ms(coord: Vector2i, z_level: int, kind: int) -> float:
	var key: String = _make_visual_task_key(coord, z_level, kind)
	if not _visual_task_pending.has(key):
		return -1.0
	return _get_diag_age_ms(_visual_task_enqueued_usec, key)

func _describe_chunk_visual_state(chunk: Chunk) -> String:
	if chunk == null or not is_instance_valid(chunk):
		return "not_loaded"
	match int(chunk._visual_state):
		0:
			return "uninitialized"
		1:
			return "native_ready"
		2:
			return "proxy_ready"
		3:
			return "terrain_ready"
		4:
			return "full_pending"
		5:
			return "full_ready"
		_:
			return "unknown"

func _format_diag_age_ms(value_ms: float) -> String:
	if value_ms < 0.0:
		return "-"
	return "%.0f" % value_ms

func _maybe_log_player_chunk_visual_status(
	trigger: String,
	dispatcher_step_ms: float = 0.0,
	budget_exhausted: bool = false
) -> void:
	if not _initialized or not _player or _is_boot_in_progress:
		return
	var coord: Vector2i = _canonical_chunk_coord(_player_chunk)
	var z_level: int = _active_z
	var chunk: Chunk = get_chunk(coord)
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	var load_queued: bool = _has_load_request(coord, z_level)
	var staged: bool = _is_staged_request(coord, z_level)
	var generating: bool = _is_generating_request(coord, z_level)
	var first_pass_age_ms: float = _get_visual_task_age_ms(coord, z_level, VisualTaskKind.TASK_FIRST_PASS)
	var full_redraw_age_ms: float = _get_visual_task_age_ms(coord, z_level, VisualTaskKind.TASK_FULL_REDRAW)
	var border_fix_age_ms: float = _get_visual_task_age_ms(coord, z_level, VisualTaskKind.TASK_BORDER_FIX)
	var apply_age_ms: float = _get_diag_age_ms(_visual_apply_started_usec, chunk_key)
	var convergence_age_ms: float = _get_diag_age_ms(_visual_convergence_started_usec, chunk_key)
	var first_pass_ready: bool = chunk != null and chunk.is_first_pass_ready()
	var full_ready: bool = chunk != null and chunk.is_full_redraw_ready()
	var phase_name: String = String(chunk.get_redraw_phase_name()) if chunk != null and is_instance_valid(chunk) else "none"
	var state_name: String = _describe_chunk_visual_state(chunk)
	var issues: Array[String] = []
	if chunk == null or not is_instance_valid(chunk):
		issues.append("not_loaded")
	if load_queued:
		issues.append("load_queued")
	if staged:
		issues.append("staged_apply")
	if generating:
		issues.append("generating")
	if not first_pass_ready:
		issues.append("first_pass_not_ready")
	if first_pass_age_ms >= 0.0:
		issues.append("first_pass_pending")
	if full_redraw_age_ms >= 0.0:
		issues.append("full_redraw_pending")
	if border_fix_age_ms >= 0.0:
		issues.append("border_fix_pending")
	if chunk != null and is_instance_valid(chunk) and chunk.visible and not first_pass_ready:
		issues.append("visible_before_first_pass")
	var blocked_age_ms: float = maxf(
		first_pass_age_ms,
		maxf(full_redraw_age_ms, maxf(border_fix_age_ms, maxf(apply_age_ms, convergence_age_ms)))
	)
	var is_blocked: bool = not issues.is_empty()
	if trigger == "entered_chunk" and not is_blocked:
		return
	var issues_text: String = ",".join(issues)
	var signature: String = "%s|%d|%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(coord),
		z_level,
		state_name,
		phase_name,
		str(load_queued),
		str(staged),
		str(generating),
		str(first_pass_ready),
		str(full_ready),
		issues_text,
	]
	var now_usec: int = Time.get_ticks_usec()
	var should_log: bool = false
	if signature != _player_chunk_diag_last_signature:
		should_log = true
	elif is_blocked \
		and blocked_age_ms >= PLAYER_CHUNK_DIAG_BLOCKED_AGE_MS \
		and now_usec - _player_chunk_diag_last_usec >= PLAYER_CHUNK_DIAG_LOG_INTERVAL_MSEC * 1000:
		should_log = true
	elif dispatcher_step_ms >= PLAYER_CHUNK_DIAG_SPIKE_MS \
		and now_usec - _player_chunk_diag_last_usec >= PLAYER_CHUNK_DIAG_LOG_INTERVAL_MSEC * 1000:
		should_log = true
	elif budget_exhausted \
		and is_blocked \
		and now_usec - _player_chunk_diag_last_usec >= PLAYER_CHUNK_DIAG_LOG_INTERVAL_MSEC * 1000:
		should_log = true
	if not should_log:
		return
	_player_chunk_diag_last_signature = signature
	_player_chunk_diag_last_usec = now_usec
	print(
		"[WorldPerf] PlayerChunk coord=%s z=%d trigger=%s loaded=%s visible=%s state=%s phase=%s first_pass=%s full_ready=%s issues=%s ages(first=%sms full=%sms border=%sms apply=%sms converge=%sms) queues(fast=%d urgent=%d near=%d full_near=%d full_far=%d) requests(load=%s staged=%s generating=%s) scheduler(step=%.2fms exhausted=%s)"
		% [
			coord,
			z_level,
			trigger,
			str(chunk != null and is_instance_valid(chunk)),
			str(chunk != null and is_instance_valid(chunk) and chunk.visible),
			state_name,
			phase_name,
			str(first_pass_ready),
			str(full_ready),
			issues_text if issues_text != "" else "healthy",
			_format_diag_age_ms(first_pass_age_ms),
			_format_diag_age_ms(full_redraw_age_ms),
			_format_diag_age_ms(border_fix_age_ms),
			_format_diag_age_ms(apply_age_ms),
			_format_diag_age_ms(convergence_age_ms),
			_visual_q_terrain_fast.size(),
			_visual_q_terrain_urgent.size(),
			_visual_q_terrain_near.size(),
			_visual_q_full_near.size(),
			_visual_q_full_far.size(),
			str(load_queued),
			str(staged),
			str(generating),
			dispatcher_step_ms,
			str(budget_exhausted),
		]
	)

func _check_player_chunk() -> void:
	var cur: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	if cur != _player_chunk:
		_player_chunk_motion = cur - _player_chunk if _player_chunk.x != 99999 else Vector2i.ZERO
		_last_player_chunk_for_priority = _player_chunk
		_player_chunk = cur
		_refresh_visual_task_priorities()
		_sync_loaded_chunk_display_positions(cur)
		_update_chunks(cur)
		_maybe_log_player_chunk_visual_status("entered_chunk")

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
		return _chunk_priority_less(a, b, center)
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
		var flora_payload: Dictionary = _get_cached_surface_chunk_flora_payload(coord, z_level) if saved_modifications.is_empty() else {}
		var flora_result: ChunkFloraResultScript = null
		if saved_modifications.is_empty() and flora_payload.is_empty():
			flora_result = _get_cached_surface_chunk_flora_result(coord, z_level)
		if not flora_payload.is_empty():
			chunk.set_flora_payload(flora_payload)
		elif flora_result != null:
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
	if not chunk.is_redraw_complete():
		_schedule_chunk_visual_work(chunk, z_level)
	_sync_chunk_visibility_for_publication(chunk)
	_boot_on_chunk_applied(coord, chunk)
	if _should_track_surface_topology(z_level):
		if _is_native_topology_enabled():
			_native_topology_builder.call("set_chunk", coord, chunk.get_terrain_bytes(), WorldGenerator.balance.chunk_size_tiles)
			_native_topology_dirty = true
		else:
			_mark_topology_dirty()
	EventBus.chunk_loaded.emit(coord)
	_enqueue_neighbor_border_redraws(coord)
	WorldPerfProbe.end("ChunkManager._load_chunk %s" % [coord], started_usec)

func _unload_chunk(coord: Vector2i) -> void:
	coord = _canonical_chunk_coord(coord)
	if _is_staged_request(coord, _active_z):
		_clear_staged_request()
	if _is_generating_request(coord, _active_z):
		_sync_runtime_generation_status()
	if not _loaded_chunks.has(coord):
		return
	var chunk: Chunk = _loaded_chunks[coord]
	for kind: int in [
		VisualTaskKind.TASK_FIRST_PASS,
		VisualTaskKind.TASK_FULL_REDRAW,
		VisualTaskKind.TASK_BORDER_FIX,
		VisualTaskKind.TASK_COSMETIC,
	]:
		var task_key: String = _make_visual_task_key(coord, _active_z, kind)
		_visual_task_pending.erase(task_key)
		_visual_task_enqueued_usec.erase(task_key)
	var chunk_key: String = _make_visual_chunk_key(coord, _active_z)
	_visual_apply_started_usec.erase(chunk_key)
	_visual_convergence_started_usec.erase(chunk_key)
	_visual_first_pass_ready_usec.erase(chunk_key)
	_visual_full_ready_usec.erase(chunk_key)
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
		RuntimeWorkTypes.CATEGORY_VISUAL,
		_resolve_visual_scheduler_budget_ms(),
		_tick_visuals,
		JOB_STREAMING_REDRAW,
		RuntimeWorkTypes.CadenceKind.PRESENTATION,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"Chunk visual scheduler"
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
## Thread-safety: pure-data compute runs in detached builders; scene-tree apply remains serialized.
func _tick_loading() -> bool:
	if _shutdown_in_progress:
		return false
	if _is_boot_in_progress:
		return false
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	if _should_compact_load_queue(_player_chunk, _active_z, load_radius):
		_prune_load_queue(_player_chunk, _active_z, load_radius)
	_collect_completed_runtime_generates(load_radius)
	if _staged_chunk != null:
		if _staged_z != _active_z or not _is_chunk_within_radius(_staged_coord, _player_chunk, load_radius):
			_clear_staged_request()
			return _has_streaming_work()
		_staged_loading_finalize()
		return _has_streaming_work()
	if not _staged_install_entry.is_empty() or not _staged_data.is_empty():
		if _staged_z != _active_z or not _is_chunk_within_radius(_staged_coord, _player_chunk, load_radius):
			_clear_staged_request()
			return _has_streaming_work()
		_staged_loading_create()
		return true
	if _promote_runtime_ready_result_to_stage(load_radius):
		return true
	if _load_queue.is_empty():
		return _has_streaming_work()
	var scanned_requests: int = 0
	while not _load_queue.is_empty() \
		and scanned_requests < MAX_LOAD_REQUESTS_SCANNED_PER_TICK \
		and _gen_active_tasks.size() < RUNTIME_MAX_CONCURRENT_COMPUTE:
		scanned_requests += 1
		var request: Dictionary = _load_queue.pop_front()
		if not _is_load_request_relevant(request, _player_chunk, _active_z, load_radius):
			continue
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var request_z: int = int(request.get("z", _active_z))
		if _try_stage_surface_chunk_from_cache(coord, request_z):
			return true
		_submit_async_generate(coord, request_z)
	if _promote_runtime_ready_result_to_stage(load_radius):
		return true
	return _has_streaming_work()

func _has_streaming_work() -> bool:
	return not _load_queue.is_empty() \
		or _staged_chunk != null \
		or not _staged_data.is_empty() \
		or not _gen_ready_queue.is_empty() \
		or _has_relevant_runtime_generate_task()

func _is_streaming_generation_idle() -> bool:
	return _load_queue.is_empty() \
		and _staged_chunk == null \
		and _staged_data.is_empty() \
		and _gen_ready_queue.is_empty() \
		and not _has_relevant_runtime_generate_task()

## Отправляет генерацию чанка в WorkerThreadPool.
func _submit_async_generate(coord: Vector2i, z_level: int) -> void:
	if _shutdown_in_progress:
		return
	coord = _canonical_chunk_coord(coord)
	if _gen_active_tasks.has(coord):
		return
	var builder: ChunkContentBuilder = null
	if WorldGenerator and WorldGenerator.has_method("create_detached_chunk_content_builder"):
		builder = WorldGenerator.create_detached_chunk_content_builder()
	var task_id: int = WorkerThreadPool.add_task(_worker_generate.bind(coord, z_level, builder))
	_gen_active_tasks[coord] = task_id
	_gen_active_z_levels[coord] = z_level
	_gen_builders[coord] = builder
	_sync_runtime_generation_status()

## Выполняется в worker thread. Только чистые данные, никаких Node/scene tree.
func _worker_generate(coord: Vector2i, z_level: int, builder: ChunkContentBuilder = null) -> void:
	if _shutdown_in_progress:
		return
	var result_entry: Dictionary = {}
	var data: Dictionary
	if z_level != 0:
		data = _generate_solid_rock_chunk()
	else:
		data = _build_surface_chunk_native_data(coord, builder)
		## Use native flora_placements if available, else GDScript fallback
		if data.has("flora_placements") and not (data["flora_placements"] as Array).is_empty():
			result_entry["flora_payload"] = _build_native_flora_payload_from_placements(coord, data)
		else:
			var flora_builder: ChunkFloraBuilderScript = _create_detached_flora_builder()
			var flora_payload: Dictionary = _build_flora_payload_for_native_data(coord, data, flora_builder)
			result_entry["flora_payload"] = flora_payload
	if _shutdown_in_progress:
		return
	result_entry["native_data"] = data
	_gen_mutex.lock()
	_gen_result[coord] = result_entry
	_gen_mutex.unlock()

func _build_surface_chunk_native_data(coord: Vector2i, builder: ChunkContentBuilder = null) -> Dictionary:
	if builder != null:
		return builder.build_chunk_native_data(coord)
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

func _collect_completed_runtime_generates(load_radius: int) -> void:
	if _gen_active_tasks.is_empty():
		return
	var completed_coords: Array[Vector2i] = []
	for coord_variant: Variant in _gen_active_tasks.keys():
		var coord: Vector2i = coord_variant as Vector2i
		var task_id: int = int(_gen_active_tasks.get(coord, -1))
		if task_id >= 0 and WorkerThreadPool.is_task_completed(task_id):
			completed_coords.append(coord)
	if completed_coords.size() > 1:
		completed_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _chunk_priority_less(a, b, _player_chunk)
		)
	for coord: Vector2i in completed_coords:
		var task_id: int = int(_gen_active_tasks.get(coord, -1))
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
		_gen_active_tasks.erase(coord)
		var request_z: int = int(_gen_active_z_levels.get(coord, INVALID_Z_LEVEL))
		_gen_active_z_levels.erase(coord)
		_gen_builders.erase(coord)
		_gen_mutex.lock()
		var completed_entry: Dictionary = _gen_result.get(coord, {}) as Dictionary
		_gen_result.erase(coord)
		_gen_mutex.unlock()
		var completed_data: Dictionary = completed_entry.get("native_data", {}) as Dictionary
		var completed_flora_payload: Dictionary = completed_entry.get("flora_payload", {}) as Dictionary
		if not completed_data.is_empty():
			_cache_surface_chunk_payload(coord, request_z, completed_data)
			if request_z == 0 and not completed_flora_payload.is_empty():
				_cache_surface_chunk_flora_payload(coord, request_z, completed_flora_payload)
		if request_z != _active_z \
			or (_z_chunks.get(request_z, {}) as Dictionary).has(coord) \
			or not _is_chunk_within_radius(coord, _player_chunk, load_radius):
			continue
		_gen_ready_queue.append({
			"coord": coord,
			"z": request_z,
			"native_data": completed_data,
			"flora_payload": completed_flora_payload,
		})
	_sort_runtime_ready_queue()
	_sync_runtime_generation_status()

func _promote_runtime_ready_result_to_stage(load_radius: int) -> bool:
	while not _gen_ready_queue.is_empty():
		var ready_entry: Dictionary = _gen_ready_queue.pop_front()
		var coord: Vector2i = ready_entry.get("coord", Vector2i.ZERO) as Vector2i
		var request_z: int = int(ready_entry.get("z", INVALID_Z_LEVEL))
		var completed_data: Dictionary = ready_entry.get("native_data", {}) as Dictionary
		var completed_flora_payload: Dictionary = ready_entry.get("flora_payload", {}) as Dictionary
		if completed_data.is_empty():
			continue
		if request_z != _active_z \
			or (_z_chunks.get(request_z, {}) as Dictionary).has(coord) \
			or not _is_chunk_within_radius(coord, _player_chunk, load_radius):
			continue
		if _stage_prepared_chunk_install(coord, request_z, completed_data, null, completed_flora_payload):
			return true
	return false

func _sort_runtime_ready_queue() -> void:
	if _gen_ready_queue.size() <= 1:
		return
	_gen_ready_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _chunk_priority_less(
			a.get("coord", Vector2i.ZERO) as Vector2i,
			b.get("coord", Vector2i.ZERO) as Vector2i,
			_player_chunk
		)
	)

func _has_relevant_runtime_generate_task() -> bool:
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	for coord_variant: Variant in _gen_active_tasks.keys():
		var coord: Vector2i = coord_variant as Vector2i
		var z_level: int = int(_gen_active_z_levels.get(coord, INVALID_Z_LEVEL))
		if z_level == _active_z and _is_chunk_within_radius(coord, _player_chunk, load_radius):
			return true
	return false

func _sync_runtime_generation_status() -> void:
	if _gen_active_tasks.is_empty():
		_gen_task_id = -1
		_gen_coord = Vector2i(999999, 999999)
		_gen_z = 0
		return
	var active_coords: Array[Vector2i] = []
	for coord_variant: Variant in _gen_active_tasks.keys():
		active_coords.append(coord_variant as Vector2i)
	active_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_priority_less(a, b, _player_chunk)
	)
	var selected_coord: Vector2i = active_coords[0]
	_gen_coord = selected_coord
	_gen_z = int(_gen_active_z_levels.get(selected_coord, _active_z))
	_gen_task_id = int(_gen_active_tasks.get(selected_coord, -1))

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
		return _chunk_priority_less(coord_a, coord_b, center)
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
	if not entry.has("flora_payload"):
		entry["flora_payload"] = flora_result.to_serialized_payload(_resolve_flora_tile_size())
	_surface_payload_cache[cache_key] = entry
	_touch_surface_payload_cache_key(cache_key)

func _cache_surface_chunk_flora_payload(coord: Vector2i, z_level: int, flora_payload: Dictionary) -> void:
	if z_level != 0 or flora_payload.is_empty():
		return
	var cache_key: Vector3i = _make_surface_payload_cache_key(coord, z_level)
	var entry: Dictionary = _surface_payload_cache.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return
	entry["flora_payload"] = flora_payload
	_surface_payload_cache[cache_key] = entry
	_touch_surface_payload_cache_key(cache_key)

func _get_cached_surface_chunk_flora_payload(coord: Vector2i, z_level: int) -> Dictionary:
	if z_level != 0:
		return {}
	var entry: Dictionary = _surface_payload_cache.get(_make_surface_payload_cache_key(coord, z_level), {}) as Dictionary
	if entry.is_empty():
		return {}
	return entry.get("flora_payload", {}) as Dictionary

func _get_cached_surface_chunk_flora_result(coord: Vector2i, z_level: int) -> ChunkFloraResultScript:
	if z_level != 0:
		return null
	var cache_key: Vector3i = _make_surface_payload_cache_key(coord, z_level)
	var entry: Dictionary = _surface_payload_cache.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return null
	var flora_result: ChunkFloraResultScript = entry.get("flora_result", null) as ChunkFloraResultScript
	if flora_result != null:
		return flora_result
	var flora_payload: Dictionary = entry.get("flora_payload", {}) as Dictionary
	if flora_payload.is_empty():
		return null
	flora_result = _flora_result_from_payload(flora_payload)
	if flora_result == null:
		return null
	entry["flora_result"] = flora_result
	_surface_payload_cache[cache_key] = entry
	_touch_surface_payload_cache_key(cache_key)
	return flora_result

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
	var saved_modifications: Dictionary = _get_saved_chunk_modifications(z_level, coord)
	var staged_flora_payload: Dictionary = _get_cached_surface_chunk_flora_payload(coord, z_level) if saved_modifications.is_empty() else {}
	return _stage_prepared_chunk_install(coord, z_level, staged_native_data, null, staged_flora_payload)

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
		"secondary_biome": (native_data.get("secondary_biome", PackedByteArray()) as PackedByteArray).duplicate(),
		"ecotone_values": (native_data.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"flora_density_values": (native_data.get("flora_density_values", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"flora_modulation_values": (native_data.get("flora_modulation_values", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"feature_and_poi_payload": (native_data.get("feature_and_poi_payload", {"placements": []}) as Dictionary).duplicate(true),
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

func _sort_chunk_entry_queue_by_priority(queue: Array[Dictionary], center: Vector2i) -> void:
	if queue.size() <= 1:
		return
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _chunk_priority_less(
			a.get("coord", Vector2i.ZERO) as Vector2i,
			b.get("coord", Vector2i.ZERO) as Vector2i,
			center
		)
	)

func _prepare_chunk_install_entry(
	coord: Vector2i,
	z_level: int,
	native_data: Dictionary,
	prepared_flora_result: ChunkFloraResultScript = null,
	prepared_flora_payload: Dictionary = {}
) -> Dictionary:
	if native_data.is_empty():
		return {}
	coord = _canonical_chunk_coord(coord)
	var chunk_biome: BiomeData = _resolve_chunk_biome(coord, z_level)
	var tileset_bundle: Dictionary = _get_or_build_tileset_bundle(chunk_biome)
	var terrain_tileset: TileSet = null
	if z_level != 0:
		terrain_tileset = tileset_bundle.get("underground_terrain") as TileSet
	else:
		terrain_tileset = tileset_bundle.get("terrain") as TileSet
	var overlay_tileset: TileSet = tileset_bundle.get("overlay") as TileSet
	if not terrain_tileset or not overlay_tileset:
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
				flora_payload = prepared_flora_result.to_serialized_payload(_resolve_flora_tile_size())
				flora_result = prepared_flora_result
			if flora_payload.is_empty():
				flora_result = _get_cached_surface_chunk_flora_result(coord, z_level)
				if flora_result == null:
					flora_result = prepared_flora_result
				if flora_result == null:
					flora_result = _build_flora_result_for_native_data(coord, native_data)
				if flora_result != null:
					flora_payload = flora_result.to_serialized_payload(_resolve_flora_tile_size())
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
		"init_fog": z_level != 0 and _fog_tileset != null,
	}

func _create_chunk_from_install_entry(install_entry: Dictionary) -> Chunk:
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
		self
	)
	_sync_chunk_display_position(chunk, _player_chunk)
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
		chunk.init_fog_layer(_fog_tileset)
	return chunk

func _finalize_chunk_install(coord: Vector2i, z_level: int, chunk: Chunk) -> void:
	var loaded_chunks_for_z: Dictionary = _z_chunks.get(z_level, {})
	if loaded_chunks_for_z.has(coord):
		chunk.queue_free()
		return
	_sync_chunk_display_position(chunk, _player_chunk)
	var z_container: Node2D = _z_containers.get(z_level) as Node2D
	if z_container:
		z_container.add_child(chunk)
	else:
		_chunk_container.add_child(chunk)
	loaded_chunks_for_z[coord] = chunk
	if z_level == _active_z:
		_loaded_chunks = loaded_chunks_for_z
	if not chunk.is_redraw_complete():
		_schedule_chunk_visual_work(chunk, z_level)
	_sync_chunk_visibility_for_publication(chunk)
	_boot_on_chunk_applied(coord, chunk)
	if _should_track_surface_topology(z_level):
		if _is_native_topology_enabled():
			_native_topology_builder.call("set_chunk", coord, chunk.get_terrain_bytes(), WorldGenerator.balance.chunk_size_tiles)
			_native_topology_dirty = true
		else:
			_mark_topology_dirty()
	EventBus.chunk_loaded.emit(coord)
	_enqueue_neighbor_border_redraws(coord)

func _stage_prepared_chunk_install(
	coord: Vector2i,
	z_level: int,
	native_data: Dictionary,
	prepared_flora_result: ChunkFloraResultScript = null,
	prepared_flora_payload: Dictionary = {}
) -> bool:
	var install_entry: Dictionary = _prepare_chunk_install_entry(
		coord,
		z_level,
		native_data,
		prepared_flora_result,
		prepared_flora_payload
	)
	if install_entry.is_empty():
		_staged_flora_result = null
		_staged_flora_payload = {}
		_staged_install_entry = {}
		return false
	_staged_coord = install_entry.get("coord", Vector2i.ZERO) as Vector2i
	_staged_z = z_level
	_staged_data = native_data
	_staged_flora_result = install_entry.get("flora_result", prepared_flora_result) as ChunkFloraResultScript
	_staged_flora_payload = install_entry.get("flora_payload", prepared_flora_payload) as Dictionary
	_staged_install_entry = install_entry
	return true

func _cache_chunk_install_handoff_entry(entry: Dictionary, z_level: int) -> void:
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
	var staged_flora_payload: Dictionary = _staged_flora_payload
	_staged_data = {}
	_staged_flora_result = null
	_staged_flora_payload = {}
	if (_z_chunks.get(z_level, {}) as Dictionary).has(coord):
		_staged_coord = Vector2i(999999, 999999)
		_staged_z = 0
		_staged_install_entry = {}
		return
	var install_entry: Dictionary = _staged_install_entry
	if install_entry.is_empty():
		install_entry = _prepare_chunk_install_entry(coord, z_level, native_data, staged_flora_result, staged_flora_payload)
	if install_entry.is_empty():
		_staged_coord = Vector2i(999999, 999999)
		_staged_z = 0
		_staged_install_entry = {}
		return
	var chunk: Chunk = _create_chunk_from_install_entry(install_entry)
	if chunk == null:
		_staged_coord = Vector2i(999999, 999999)
		_staged_z = 0
		_staged_install_entry = {}
		return
	_staged_install_entry = {}
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
	_finalize_chunk_install(coord, z_level, chunk)
	WorldPerfProbe.end("ChunkStreaming.phase2_finalize %s" % [coord], total_usec)

## Progressive redraw одного шага. Возвращает true если есть ещё работа.
func _tick_redraws() -> bool:
	return _tick_visuals()

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
	return _process_topology_build_step()

func _process_chunk_redraws() -> void:
	_process_one_visual_task(0, {})

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
	# Carve the pocket through the production mining path so topology/reveal/visuals stay aligned.
	var tile_size: int = WorldGenerator.balance.tile_size if WorldGenerator and WorldGenerator.balance else 1
	for tile_pos: Variant in pocket_tiles:
		var t: Vector2i = _canonical_tile(tile_pos as Vector2i)
		var ch: Chunk = get_chunk_at_tile(t)
		if not ch:
			continue
		var local: Vector2i = ch.global_to_local(t)
		if ch.get_terrain_type_at(local) != TileGenData.TerrainType.ROCK:
			continue
		var world_pos := Vector2(
			t.x * tile_size + tile_size * 0.5,
			t.y * tile_size + tile_size * 0.5
		)
		try_harvest_at_world(world_pos)
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
	_topology_build_generation += 1
	_is_topology_dirty = true
	_topology_build_start_phase = TOPOLOGY_START_NONE
	_topology_start_chunk_keys = []
	_topology_start_chunk_index = 0
	_topology_build_commit_phase = TOPOLOGY_COMMIT_NONE
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
		if _native_topology_dirty and _load_queue.is_empty() and not _has_pending_visual_tasks():
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
	if _topology_task_id >= 0:
		return
	var snapshot_usec: int = WorldPerfProbe.begin()
	var snapshot: Dictionary = _capture_topology_build_snapshot()
	WorldPerfProbe.end("Topology.runtime.snapshot", snapshot_usec)
	_is_topology_build_in_progress = true
	_topology_build_commit_phase = TOPOLOGY_COMMIT_NONE
	_topology_build_start_phase = TOPOLOGY_START_NONE
	_topology_start_chunk_keys = []
	_topology_start_chunk_index = 0
	_topology_scan_chunk_coords = []
	_topology_scan_chunk_index = 0
	_topology_scan_local_x = 0
	_topology_scan_local_y = 0
	_clear_topology_component_state()
	_topology_task_generation = _topology_build_generation
	_topology_task_id = WorkerThreadPool.add_task(_worker_rebuild_topology.bind(snapshot, _topology_task_generation))

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
			_topology_build_start_phase = TOPOLOGY_START_RESET_TILES_BY_KEY_BY_CHUNK
		TOPOLOGY_START_RESET_TILES_BY_KEY_BY_CHUNK:
			_topology_build_tiles_by_key_by_chunk = {}
			_topology_build_start_phase = TOPOLOGY_START_RESET_OPEN_TILES_BY_KEY_BY_CHUNK
		TOPOLOGY_START_RESET_OPEN_TILES_BY_KEY_BY_CHUNK:
			_topology_build_open_tiles_by_key_by_chunk = {}
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
	if _topology_build_commit_phase != TOPOLOGY_COMMIT_NONE:
		var commit_usec: int = WorldPerfProbe.begin()
		_process_topology_build_commit_step()
		WorldPerfProbe.end("Topology.runtime.commit", commit_usec)
		return false
	_collect_completed_topology_build()
	if _topology_build_commit_phase != TOPOLOGY_COMMIT_NONE:
		var commit_ready_usec: int = WorldPerfProbe.begin()
		_process_topology_build_commit_step()
		WorldPerfProbe.end("Topology.runtime.commit", commit_ready_usec)
		return false
	if not _is_topology_dirty:
		return false
	if _topology_task_id >= 0:
		return false
	if _has_streaming_work():
		return false
	_start_topology_build()
	return false

func _capture_topology_build_snapshot() -> Dictionary:
	var chunk_coords: Array[Vector2i] = []
	for coord_variant: Variant in _loaded_chunks.keys():
		chunk_coords.append(coord_variant as Vector2i)
	if chunk_coords.size() > 1:
		chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
		)
	var chunks: Dictionary = {}
	for chunk_coord: Vector2i in chunk_coords:
		var chunk: Chunk = _loaded_chunks.get(chunk_coord)
		if not chunk:
			continue
		chunks[chunk_coord] = {
			"chunk_size": chunk.get_chunk_size(),
			"terrain_bytes": chunk.get_terrain_bytes().duplicate(),
			"neighbors": {
				Vector2i.LEFT: _offset_chunk_coord(chunk_coord, Vector2i.LEFT),
				Vector2i.RIGHT: _offset_chunk_coord(chunk_coord, Vector2i.RIGHT),
				Vector2i.UP: _offset_chunk_coord(chunk_coord, Vector2i.UP),
				Vector2i.DOWN: _offset_chunk_coord(chunk_coord, Vector2i.DOWN),
			},
		}
	return {
		"scan_chunk_coords": chunk_coords,
		"chunks": chunks,
	}

func _worker_rebuild_topology(snapshot: Dictionary, generation: int) -> void:
	if _shutdown_in_progress:
		return
	var started_usec: int = Time.get_ticks_usec()
	var built_snapshot: Dictionary = _worker_build_topology_snapshot(snapshot)
	if _shutdown_in_progress:
		return
	built_snapshot["generation"] = generation
	built_snapshot["compute_ms"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_topology_result_mutex.lock()
	_topology_result = built_snapshot
	_topology_result_mutex.unlock()

func _worker_build_topology_snapshot(snapshot: Dictionary) -> Dictionary:
	var state: Dictionary = {
		"scan_chunk_coords": snapshot.get("scan_chunk_coords", []) as Array,
		"scan_chunk_index": 0,
		"scan_local_x": 0,
		"scan_local_y": 0,
		"build_visited": {},
		"build_key_by_tile": {},
		"build_tiles_by_key": {},
		"build_open_tiles_by_key": {},
		"build_tiles_by_key_by_chunk": {},
		"build_open_tiles_by_key_by_chunk": {},
		"component_queue": [],
		"component_queue_index": 0,
		"component_tiles": {},
		"component_open_tiles": {},
		"component_tiles_by_chunk": {},
		"component_open_tiles_by_chunk": {},
		"component_key": Vector2i(999999, 999999),
		"component_tiles_list": [],
		"component_finalize_index": 0,
	}
	while true:
		if int(state.get("component_finalize_index", 0)) < (state.get("component_tiles_list", []) as Array).size():
			_worker_finalize_topology_component_step(state)
			continue
		if int(state.get("component_queue_index", 0)) < (state.get("component_queue", []) as Array).size():
			_worker_process_topology_component_step(snapshot, state)
			continue
		var scan_result: Dictionary = _worker_find_next_topology_seed(snapshot, state)
		var seed_tile: Vector2i = scan_result.get("seed_tile", Vector2i(999999, 999999)) as Vector2i
		if seed_tile != Vector2i(999999, 999999):
			_worker_begin_topology_component(state, scan_result)
			continue
		if not bool(scan_result.get("complete", false)):
			continue
		break
	return {
		"key_by_tile": state.get("build_key_by_tile", {}) as Dictionary,
		"tiles_by_key": state.get("build_tiles_by_key", {}) as Dictionary,
		"open_tiles_by_key": state.get("build_open_tiles_by_key", {}) as Dictionary,
		"tiles_by_key_by_chunk": state.get("build_tiles_by_key_by_chunk", {}) as Dictionary,
		"open_tiles_by_key_by_chunk": state.get("build_open_tiles_by_key_by_chunk", {}) as Dictionary,
	}

func _worker_find_next_topology_seed(snapshot: Dictionary, state: Dictionary) -> Dictionary:
	var scan_chunk_coords: Array = state.get("scan_chunk_coords", []) as Array
	var scan_chunk_index: int = int(state.get("scan_chunk_index", 0))
	var scan_local_x: int = int(state.get("scan_local_x", 0))
	var scan_local_y: int = int(state.get("scan_local_y", 0))
	var build_visited: Dictionary = state.get("build_visited", {}) as Dictionary
	var snapshot_chunks: Dictionary = snapshot.get("chunks", {}) as Dictionary
	while scan_chunk_index < scan_chunk_coords.size():
		var chunk_coord: Vector2i = scan_chunk_coords[scan_chunk_index] as Vector2i
		var chunk_entry: Dictionary = snapshot_chunks.get(chunk_coord, {}) as Dictionary
		if chunk_entry.is_empty():
			scan_chunk_index += 1
			scan_local_x = 0
			scan_local_y = 0
			continue
		var chunk_size: int = int(chunk_entry.get("chunk_size", 0))
		while scan_local_y < chunk_size:
			while scan_local_x < chunk_size:
				var local_tile: Vector2i = Vector2i(scan_local_x, scan_local_y)
				scan_local_x += 1
				var terrain_type: int = _topology_snapshot_get_terrain_type_at_local(chunk_entry, local_tile)
				if not _is_mountain_topology_tile(terrain_type):
					continue
				var global_tile: Vector2i = _topology_snapshot_tile_from_chunk(chunk_coord, local_tile, chunk_size)
				if build_visited.has(global_tile):
					continue
				state["scan_chunk_index"] = scan_chunk_index
				state["scan_local_x"] = scan_local_x
				state["scan_local_y"] = scan_local_y
				return {
					"seed_tile": global_tile,
					"chunk_coord": chunk_coord,
					"local_tile": local_tile,
					"complete": false,
				}
			scan_local_x = 0
			scan_local_y += 1
		scan_chunk_index += 1
		scan_local_x = 0
		scan_local_y = 0
	state["scan_chunk_index"] = scan_chunk_index
	state["scan_local_x"] = scan_local_x
	state["scan_local_y"] = scan_local_y
	return {
		"seed_tile": Vector2i(999999, 999999),
		"complete": scan_chunk_index >= scan_chunk_coords.size(),
	}

func _worker_begin_topology_component(state: Dictionary, seed_result: Dictionary) -> void:
	_worker_clear_topology_component_state(state)
	var seed_tile: Vector2i = seed_result.get("seed_tile", Vector2i(999999, 999999)) as Vector2i
	var queue: Array = state.get("component_queue", []) as Array
	queue.append({
		"tile": seed_tile,
		"chunk_coord": seed_result.get("chunk_coord", Vector2i(999999, 999999)) as Vector2i,
		"local_tile": seed_result.get("local_tile", Vector2i.ZERO) as Vector2i,
	})
	state["component_queue"] = queue
	state["component_queue_index"] = 0
	state["component_key"] = seed_tile
	var build_visited: Dictionary = state.get("build_visited", {}) as Dictionary
	build_visited[seed_tile] = true

func _worker_process_topology_component_step(snapshot: Dictionary, state: Dictionary) -> void:
	var queue: Array = state.get("component_queue", []) as Array
	var queue_index: int = int(state.get("component_queue_index", 0))
	var component_tiles: Dictionary = state.get("component_tiles", {}) as Dictionary
	var component_open_tiles: Dictionary = state.get("component_open_tiles", {}) as Dictionary
	var component_tiles_by_chunk: Dictionary = state.get("component_tiles_by_chunk", {}) as Dictionary
	var component_open_tiles_by_chunk: Dictionary = state.get("component_open_tiles_by_chunk", {}) as Dictionary
	var component_tiles_list: Array = state.get("component_tiles_list", []) as Array
	var component_key: Vector2i = state.get("component_key", Vector2i(999999, 999999)) as Vector2i
	var build_visited: Dictionary = state.get("build_visited", {}) as Dictionary
	var snapshot_chunks: Dictionary = snapshot.get("chunks", {}) as Dictionary
	while queue_index < queue.size():
		var current_entry: Dictionary = queue[queue_index] as Dictionary
		queue_index += 1
		var current: Vector2i = current_entry.get("tile", Vector2i(999999, 999999)) as Vector2i
		var current_chunk_coord: Vector2i = current_entry.get("chunk_coord", Vector2i(999999, 999999)) as Vector2i
		var current_local: Vector2i = current_entry.get("local_tile", Vector2i.ZERO) as Vector2i
		component_tiles[current] = true
		component_tiles_list.append(current)
		if not component_tiles_by_chunk.has(current_chunk_coord):
			component_tiles_by_chunk[current_chunk_coord] = {}
		(component_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
		if current.y < component_key.y or (current.y == component_key.y and current.x < component_key.x):
			component_key = current
			state["component_key"] = component_key
		var current_chunk_entry: Dictionary = snapshot_chunks.get(current_chunk_coord, {}) as Dictionary
		if current_chunk_entry.is_empty():
			continue
		var current_type: int = _topology_snapshot_get_terrain_type_at_local(current_chunk_entry, current_local)
		if current_type == TileGenData.TerrainType.MINED_FLOOR or current_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			component_open_tiles[current] = true
			if not component_open_tiles_by_chunk.has(current_chunk_coord):
				component_open_tiles_by_chunk[current_chunk_coord] = {}
			(component_open_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
		var current_chunk_size: int = int(current_chunk_entry.get("chunk_size", 0))
		var neighbors: Dictionary = current_chunk_entry.get("neighbors", {}) as Dictionary
		for dir: Vector2i in _CARDINAL_DIRS:
			var next_chunk_coord: Vector2i = current_chunk_coord
			var next_local: Vector2i = current_local + dir
			if next_local.x < 0:
				next_chunk_coord = neighbors.get(Vector2i.LEFT, Vector2i(999999, 999999)) as Vector2i
				next_local.x += current_chunk_size
			elif next_local.x >= current_chunk_size:
				next_chunk_coord = neighbors.get(Vector2i.RIGHT, Vector2i(999999, 999999)) as Vector2i
				next_local.x -= current_chunk_size
			elif next_local.y < 0:
				next_chunk_coord = neighbors.get(Vector2i.UP, Vector2i(999999, 999999)) as Vector2i
				next_local.y += current_chunk_size
			elif next_local.y >= current_chunk_size:
				next_chunk_coord = neighbors.get(Vector2i.DOWN, Vector2i(999999, 999999)) as Vector2i
				next_local.y -= current_chunk_size
			var next_chunk_entry: Dictionary = snapshot_chunks.get(next_chunk_coord, {}) as Dictionary
			if next_chunk_entry.is_empty():
				continue
			if not _is_mountain_topology_tile(_topology_snapshot_get_terrain_type_at_local(next_chunk_entry, next_local)):
				continue
			var next_chunk_size: int = int(next_chunk_entry.get("chunk_size", current_chunk_size))
			var next_tile: Vector2i = _topology_snapshot_tile_from_chunk(next_chunk_coord, next_local, next_chunk_size)
			if build_visited.has(next_tile):
				continue
			build_visited[next_tile] = true
			queue.append({
				"tile": next_tile,
				"chunk_coord": next_chunk_coord,
				"local_tile": next_local,
			})
	state["component_queue_index"] = queue_index
	state["component_finalize_index"] = 0

func _worker_finalize_topology_component_step(state: Dictionary) -> void:
	var component_key: Vector2i = state.get("component_key", Vector2i(999999, 999999)) as Vector2i
	var component_tiles_list: Array = state.get("component_tiles_list", []) as Array
	var build_key_by_tile: Dictionary = state.get("build_key_by_tile", {}) as Dictionary
	for tile_variant: Variant in component_tiles_list:
		build_key_by_tile[tile_variant as Vector2i] = component_key
	var build_tiles_by_key: Dictionary = state.get("build_tiles_by_key", {}) as Dictionary
	var build_open_tiles_by_key: Dictionary = state.get("build_open_tiles_by_key", {}) as Dictionary
	var build_tiles_by_key_by_chunk: Dictionary = state.get("build_tiles_by_key_by_chunk", {}) as Dictionary
	var build_open_tiles_by_key_by_chunk: Dictionary = state.get("build_open_tiles_by_key_by_chunk", {}) as Dictionary
	build_tiles_by_key[component_key] = state.get("component_tiles", {}) as Dictionary
	build_open_tiles_by_key[component_key] = state.get("component_open_tiles", {}) as Dictionary
	build_tiles_by_key_by_chunk[component_key] = state.get("component_tiles_by_chunk", {}) as Dictionary
	build_open_tiles_by_key_by_chunk[component_key] = state.get("component_open_tiles_by_chunk", {}) as Dictionary
	_worker_clear_topology_component_state(state)

func _worker_clear_topology_component_state(state: Dictionary) -> void:
	state["component_queue"] = []
	state["component_queue_index"] = 0
	state["component_tiles"] = {}
	state["component_open_tiles"] = {}
	state["component_tiles_by_chunk"] = {}
	state["component_open_tiles_by_chunk"] = {}
	state["component_key"] = Vector2i(999999, 999999)
	state["component_tiles_list"] = []
	state["component_finalize_index"] = 0

func _topology_snapshot_get_terrain_type_at_local(chunk_entry: Dictionary, local_tile: Vector2i) -> int:
	var chunk_size: int = int(chunk_entry.get("chunk_size", 0))
	var terrain_bytes: PackedByteArray = chunk_entry.get("terrain_bytes", PackedByteArray()) as PackedByteArray
	var index: int = local_tile.y * chunk_size + local_tile.x
	if index < 0 or index >= terrain_bytes.size():
		return TileGenData.TerrainType.ROCK
	return terrain_bytes[index]

func _topology_snapshot_tile_from_chunk(chunk_coord: Vector2i, local_tile: Vector2i, chunk_size: int) -> Vector2i:
	return Vector2i(
		chunk_coord.x * chunk_size + local_tile.x,
		chunk_coord.y * chunk_size + local_tile.y
	)

func _collect_completed_topology_build() -> void:
	if _topology_task_id < 0:
		return
	if not WorkerThreadPool.is_task_completed(_topology_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_topology_task_id)
	var completed_generation: int = _topology_task_generation
	_topology_task_id = -1
	_topology_task_generation = -1
	_topology_result_mutex.lock()
	var completed_entry: Dictionary = _topology_result
	_topology_result = {}
	_topology_result_mutex.unlock()
	if completed_entry.is_empty():
		_is_topology_build_in_progress = false
		return
	var compute_ms: float = float(completed_entry.get("compute_ms", 0.0))
	if compute_ms > 0.0:
		WorldPerfProbe.record("Topology.runtime.worker_compute", compute_ms)
	if completed_generation != _topology_build_generation or not _is_topology_dirty:
		_is_topology_build_in_progress = false
		return
	_topology_build_key_by_tile = completed_entry.get("key_by_tile", {}) as Dictionary
	_topology_build_tiles_by_key = completed_entry.get("tiles_by_key", {}) as Dictionary
	_topology_build_open_tiles_by_key = completed_entry.get("open_tiles_by_key", {}) as Dictionary
	_topology_build_tiles_by_key_by_chunk = completed_entry.get("tiles_by_key_by_chunk", {}) as Dictionary
	_topology_build_open_tiles_by_key_by_chunk = completed_entry.get("open_tiles_by_key_by_chunk", {}) as Dictionary
	_begin_topology_build_commit()

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
		if not _topology_component_tiles_by_chunk.has(current_chunk_coord):
			_topology_component_tiles_by_chunk[current_chunk_coord] = {}
		(_topology_component_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
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
			if not _topology_component_open_tiles_by_chunk.has(current_chunk_coord):
				_topology_component_open_tiles_by_chunk[current_chunk_coord] = {}
			(_topology_component_open_tiles_by_chunk[current_chunk_coord] as Dictionary)[current] = true
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
	_topology_component_tiles_list = []
	_topology_component_finalize_index = 0

func _begin_topology_build_commit() -> void:
	_topology_build_commit_phase = TOPOLOGY_COMMIT_KEY_BY_TILE

func _process_topology_build_commit_step() -> bool:
	if _topology_build_commit_phase == TOPOLOGY_COMMIT_NONE:
		return false
	_queue_retired_topology_dictionary(_mountain_key_by_tile)
	_queue_retired_topology_dictionary(_mountain_tiles_by_key)
	_queue_retired_topology_dictionary(_mountain_open_tiles_by_key)
	_queue_retired_topology_dictionary(_mountain_tiles_by_key_by_chunk)
	_queue_retired_topology_dictionary(_mountain_open_tiles_by_key_by_chunk)
	_mountain_key_by_tile = _topology_build_key_by_tile
	_mountain_tiles_by_key = _topology_build_tiles_by_key
	_mountain_open_tiles_by_key = _topology_build_open_tiles_by_key
	_mountain_tiles_by_key_by_chunk = _topology_build_tiles_by_key_by_chunk
	_mountain_open_tiles_by_key_by_chunk = _topology_build_open_tiles_by_key_by_chunk
	_finish_topology_build()
	return false

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
	var old_is_mountain: bool = _is_mountain_topology_tile(old_type)
	var new_is_mountain: bool = _is_mountain_topology_tile(new_type)
	if not (old_is_mountain or new_is_mountain):
		return
	var started_usec: int = WorldPerfProbe.begin()
	if _is_native_topology_enabled():
		_native_topology_builder.call("update_tile", tile_pos, new_type)
		WorldPerfProbe.end("ChunkManager._on_mountain_tile_changed", started_usec)
		return
	if old_is_mountain and new_is_mountain:
		_incremental_topology_patch(tile_pos, new_type)
		if _topology_task_id >= 0 or _topology_build_commit_phase != TOPOLOGY_COMMIT_NONE:
			_mark_topology_dirty()
	else:
		## Mark dirty for background rebuild via _tick_topology() (FrameBudgetDispatcher).
		## No synchronous _ensure_topology_current() — that caused 1000ms+ freezes on harvest.
		_mark_topology_dirty()
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
		_mark_topology_dirty()
		return
	var tile_chunk: Vector2i = WorldGenerator.tile_to_chunk(tile_pos)
	_ensure_key_structures(mountain_key, tile_chunk)
	_mountain_key_by_tile[tile_pos] = mountain_key
	(_mountain_tiles_by_key[mountain_key] as Dictionary)[tile_pos] = true
	((_mountain_tiles_by_key_by_chunk[mountain_key] as Dictionary)[tile_chunk] as Dictionary)[tile_pos] = true
	_update_tile_open_status(tile_pos, new_type, mountain_key, tile_chunk)
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
		var neighbor_chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(neighbor)
		_update_tile_open_status(neighbor, neighbor_type, neighbor_key, neighbor_chunk_coord)

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

func _boot_count_applied_chunks() -> int:
	var applied_count: int = 0
	for coord: Vector2i in _boot_chunk_states:
		if int(_boot_chunk_states[coord]) >= BootChunkState.APPLIED:
			applied_count += 1
	return applied_count

func _boot_on_chunk_applied(coord: Vector2i, chunk: Chunk) -> void:
	if not _boot_chunk_states.has(coord):
		return
	if int(_boot_chunk_states[coord]) < BootChunkState.APPLIED:
		_boot_set_chunk_state(coord, BootChunkState.APPLIED)
	_boot_on_chunk_redraw_progress(chunk)

func _boot_on_chunk_redraw_progress(chunk: Chunk) -> void:
	if chunk == null or not _boot_chunk_states.has(chunk.chunk_coord):
		return
	_sync_chunk_visibility_for_publication(chunk)
	if chunk.is_first_pass_ready():
		_mark_visual_first_pass_ready(chunk.chunk_coord, _active_z)
	if chunk.is_full_redraw_ready():
		_mark_visual_full_ready(chunk.chunk_coord, _active_z)
		_boot_set_chunk_state(chunk.chunk_coord, BootChunkState.VISUAL_COMPLETE)

func _boot_is_first_playable_slice_ready() -> bool:
	if _boot_chunk_states.is_empty():
		return false
	for coord: Vector2i in _boot_chunk_states:
		var ring: int = _boot_get_chunk_ring(coord)
		if ring > BOOT_FIRST_PLAYABLE_MAX_RING:
			continue
		var state: int = int(_boot_chunk_states[coord])
		if state < BootChunkState.APPLIED:
			return false
		## Ring 0-1: must be fully published before player handoff.
		var chunk: Chunk = _loaded_chunks.get(coord)
		if chunk == null:
			return false
		if not chunk.is_full_redraw_ready():
			return false
	return true

func _boot_has_pending_near_ring_work() -> bool:
	if _boot_chunk_states.is_empty():
		return false
	for coord: Vector2i in _boot_chunk_states:
		var ring: int = _boot_get_chunk_ring(coord)
		if ring > BOOT_FIRST_PLAYABLE_MAX_RING:
			continue
		var chunk: Chunk = _loaded_chunks.get(coord)
		var state: int = int(_boot_chunk_states[coord])
		if state < BootChunkState.APPLIED or chunk == null:
			return true
		if not chunk.is_full_redraw_ready():
			return true
	return false

func _boot_enqueue_runtime_load(coord: Vector2i) -> void:
	coord = _canonical_chunk_coord(coord)
	if _loaded_chunks.has(coord) \
		or _has_load_request(coord, _boot_compute_z) \
		or _is_staged_request(coord, _boot_compute_z) \
		or _is_generating_request(coord, _boot_compute_z):
		return
	_enqueue_load_request(coord, _boot_compute_z)
	_load_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var coord_a: Vector2i = a.get("coord", Vector2i.ZERO) as Vector2i
		var coord_b: Vector2i = b.get("coord", Vector2i.ZERO) as Vector2i
		return _chunk_priority_less(coord_a, coord_b, _boot_center)
	)

func _boot_all_tracked_chunks_visual_complete() -> bool:
	for coord: Vector2i in _boot_chunk_states:
		if int(_boot_chunk_states[coord]) < BootChunkState.VISUAL_COMPLETE:
			return false
	return true

func _boot_has_pending_runtime_handoff_work() -> bool:
	if not _boot_prepare_queue.is_empty() or not _boot_apply_queue.is_empty() or not _boot_compute_pending.is_empty():
		return true
	for coord: Vector2i in _boot_chunk_states:
		if int(_boot_chunk_states[coord]) < BootChunkState.APPLIED:
			return true
	return false

func _boot_process_redraw_budget(max_usec: int) -> void:
	_tick_visuals_budget(max_usec)

func _boot_start_runtime_handoff() -> void:
	if _boot_runtime_handoff_started:
		return
	_boot_runtime_handoff_started = true
	_boot_compute_generation += 1
	for entry_variant: Variant in _boot_prepare_queue:
		var entry: Dictionary = entry_variant as Dictionary
		_cache_chunk_install_handoff_entry(entry, _boot_compute_z)
	for entry_variant: Variant in _boot_apply_queue:
		var entry: Dictionary = entry_variant as Dictionary
		_cache_chunk_install_handoff_entry(entry, _boot_compute_z)
	for coord_variant: Variant in _boot_compute_pending:
		var pending_coord: Vector2i = coord_variant as Vector2i
		_boot_compute_requested_usec.erase(pending_coord)
		_boot_compute_started_usec.erase(pending_coord)
	_boot_prepare_queue.clear()
	_boot_apply_queue.clear()
	_boot_compute_pending.clear()
	for coord: Vector2i in _boot_chunk_states:
		if int(_boot_chunk_states[coord]) < BootChunkState.APPLIED:
			_boot_enqueue_runtime_load(coord)

## --- Boot remaining tick (post-first_playable background completion) ---

func _tick_boot_remaining() -> void:
	if not _boot_has_remaining_chunks:
		return
	if _boot_first_playable and not _boot_runtime_handoff_started and _boot_has_pending_runtime_handoff_work():
		_boot_start_runtime_handoff()
	if _boot_runtime_handoff_started:
		_boot_collect_completed()
		_boot_drain_computed_to_apply_queue()
		for entry_variant: Variant in _boot_prepare_queue:
			_cache_chunk_install_handoff_entry(entry_variant as Dictionary, _boot_compute_z)
		for entry_variant: Variant in _boot_apply_queue:
			_cache_chunk_install_handoff_entry(entry_variant as Dictionary, _boot_compute_z)
		_boot_prepare_queue.clear()
		_boot_apply_queue.clear()
		for coord: Vector2i in _boot_chunk_states:
			if int(_boot_chunk_states[coord]) < BootChunkState.APPLIED:
				_boot_enqueue_runtime_load(coord)
	else:
		_boot_submit_pending_tasks()
		_boot_collect_completed()
		_boot_drain_computed_to_apply_queue()
		_boot_prepare_apply_entries()
		_boot_apply_from_queue()
	_boot_pipeline_drained = _boot_compute_active.is_empty() \
		and _boot_compute_pending.is_empty() \
		and _boot_prepare_queue.is_empty() \
		and _boot_apply_queue.is_empty() \
		and _boot_compute_results.is_empty()
	_boot_promote_redrawn_chunks()
	if _boot_pipeline_drained and not _boot_topology_ready:
		var all_startup_applied: bool = true
		for coord: Vector2i in _boot_chunk_states:
			if int(_boot_chunk_states[coord]) < BootChunkState.APPLIED:
				all_startup_applied = false
				break
		if all_startup_applied and is_topology_ready():
			_boot_topology_ready = true
	_boot_update_gates()
	if _boot_complete_flag:
		_boot_cleanup_compute_pipeline()
		_boot_has_remaining_chunks = false

## --- Boot compute/apply helpers (boot_chunk_compute_pipeline_spec) ---

## Pure-data compute (sync fallback): generates native_data without scene tree.
func _boot_compute_chunk_native_data(coord: Vector2i, z_level: int) -> Dictionary:
	coord = _canonical_chunk_coord(coord)
	if z_level != 0:
		return _generate_solid_rock_chunk()
	var cached_data: Dictionary = {}
	if _try_get_surface_payload_cache_native_data(coord, z_level, cached_data):
		return cached_data
	var native_data: Dictionary = _build_surface_chunk_native_data(coord)
	_cache_surface_chunk_payload(coord, z_level, native_data)
	return native_data

## Worker function: runs in WorkerThreadPool, writes result through mutex.
func _boot_worker_compute(
	coord: Vector2i,
	z_level: int,
	builder: ChunkContentBuilder,
	generation: int,
	requested_usec: int
) -> void:
	if _shutdown_in_progress:
		return
	var started_usec: int = Time.get_ticks_usec()
	var result_entry: Dictionary = {
		"generation": generation,
		"queue_wait_ms": float(started_usec - requested_usec) / 1000.0,
	}
	var data: Dictionary
	if z_level != 0:
		data = _generate_solid_rock_chunk()
	else:
		data = builder.build_chunk_native_data(coord)
	if _shutdown_in_progress:
		return
	result_entry["native_data"] = data
	result_entry["compute_ms"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
	## If native generated flora_placements, use them directly.
	## Otherwise fall back to GDScript flora computation.
	if z_level == 0 and not data.is_empty():
		if data.has("flora_placements") and not (data["flora_placements"] as Array).is_empty():
			result_entry["flora_payload"] = _build_native_flora_payload_from_placements(coord, data)
		else:
			push_warning("[Boot] native flora empty for %s — GDScript flora fallback in worker" % [coord])
			var flora_builder: ChunkFloraBuilderScript = _create_detached_flora_builder()
			result_entry["flora_payload"] = _build_flora_payload_for_native_data(coord, data, flora_builder)
	_boot_compute_mutex.lock()
	_boot_compute_results[coord] = result_entry
	_boot_compute_mutex.unlock()

## Submit pending compute tasks up to BOOT_MAX_CONCURRENT_COMPUTE.
func _boot_submit_pending_tasks() -> void:
	while not _boot_compute_pending.is_empty() and _boot_compute_active.size() < BOOT_MAX_CONCURRENT_COMPUTE:
		if _shutdown_in_progress:
			break
		var coord: Vector2i = _boot_compute_pending.pop_front()
		if _boot_compute_active.has(coord):
			continue
		var requested_usec: int = int(_boot_compute_requested_usec.get(coord, Time.get_ticks_usec()))
		var builder: ChunkContentBuilder = null
		if WorldGenerator and WorldGenerator.has_method("create_detached_chunk_content_builder"):
			builder = WorldGenerator.create_detached_chunk_content_builder()
		if builder == null:
			print("[Boot] WARN: builder is null for %s — using sync fallback" % [coord])
			var compute_usec: int = Time.get_ticks_usec()
			var native_data: Dictionary = _boot_compute_chunk_native_data(coord, _boot_compute_z)
			var compute_ms: float = float(Time.get_ticks_usec() - compute_usec) / 1000.0
			var result_entry: Dictionary = {
				"native_data": native_data,
				"generation": _boot_compute_generation,
				"queue_wait_ms": float(compute_usec - requested_usec) / 1000.0,
				"compute_ms": compute_ms,
			}
			if _boot_compute_z == 0 and not native_data.is_empty():
				if native_data.has("flora_placements") and not (native_data["flora_placements"] as Array).is_empty():
					result_entry["flora_payload"] = _build_native_flora_payload_from_placements(coord, native_data)
				else:
					result_entry["flora_payload"] = _build_flora_payload_for_native_data(coord, native_data)
			_boot_compute_mutex.lock()
			_boot_compute_results[coord] = result_entry
			_boot_compute_mutex.unlock()
			continue
		_boot_compute_started_usec[coord] = Time.get_ticks_usec()
		var task_id: int = WorkerThreadPool.add_task(
			_boot_worker_compute.bind(coord, _boot_compute_z, builder, _boot_compute_generation, requested_usec)
		)
		_boot_compute_active[coord] = task_id
		_boot_compute_builders[coord] = builder

## Collect completed worker results. Returns coords that finished.
func _boot_collect_completed() -> Array[Vector2i]:
	var completed: Array[Vector2i] = []
	for coord: Vector2i in _boot_compute_active.keys():
		var task_id: int = int(_boot_compute_active[coord])
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			completed.append(coord)
	for coord: Vector2i in completed:
		_boot_compute_active.erase(coord)
		_boot_compute_builders.erase(coord)
		_boot_compute_started_usec.erase(coord)
	return completed

## Move computed results from worker output into the sorted prepare queue.
## Discards stale (wrong generation) and failed (empty native_data) results.
func _boot_drain_computed_to_apply_queue() -> void:
	_boot_compute_mutex.lock()
	var ready_coords: Array[Vector2i] = []
	for coord: Vector2i in _boot_compute_results:
		ready_coords.append(coord)
	_boot_compute_mutex.unlock()
	for coord: Vector2i in ready_coords:
		_boot_compute_mutex.lock()
		var result_entry: Dictionary = _boot_compute_results.get(coord, {})
		_boot_compute_results.erase(coord)
		_boot_compute_mutex.unlock()
		var queue_wait_ms: float = float(result_entry.get("queue_wait_ms", 0.0))
		var compute_ms: float = float(result_entry.get("compute_ms", 0.0))
		_boot_metric_queue_wait_ms += queue_wait_ms
		_boot_metric_compute_ms += compute_ms
		if not result_entry.is_empty():
			_boot_metric_chunks_computed += 1
		var result_generation: int = int(result_entry.get("generation", -1))
		if result_generation != _boot_compute_generation:
			if int(_boot_chunk_states.get(coord, -1)) < BootChunkState.APPLIED:
				_boot_enqueue_runtime_load(coord)
			continue
		var native_data: Dictionary = result_entry.get("native_data", {})
		if native_data.is_empty():
			push_warning("[Boot] compute failed for chunk %s — skipping" % [coord])
			if _boot_failed_coords.find(coord) < 0:
				_boot_failed_coords.append(coord)
			_boot_enqueue_runtime_load(coord)
			continue
		var flora_payload: Dictionary = result_entry.get("flora_payload", {}) as Dictionary
		_boot_set_chunk_state(coord, BootChunkState.COMPUTED)
		_boot_set_chunk_state(coord, BootChunkState.QUEUED_APPLY)
		_boot_prepare_queue.append({
			"coord": coord,
			"native_data": native_data,
			"flora_payload": flora_payload,
		})
	_sort_chunk_entry_queue_by_priority(_boot_prepare_queue, _boot_center)

func _boot_prepare_apply_entries() -> int:
	var prepared_this_step: int = 0
	while not _boot_prepare_queue.is_empty() and prepared_this_step < BOOT_MAX_PREPARE_PER_STEP:
		if _shutdown_in_progress:
			break
		var entry: Dictionary = _boot_prepare_queue.pop_front()
		var coord: Vector2i = entry.get("coord", Vector2i.ZERO) as Vector2i
		var loaded_chunks_for_z: Dictionary = _z_chunks.get(_boot_compute_z, {})
		if loaded_chunks_for_z.has(coord):
			_boot_on_chunk_applied(coord, loaded_chunks_for_z.get(coord) as Chunk)
			continue
		var native_data: Dictionary = entry.get("native_data", {}) as Dictionary
		var prepared_flora_payload: Dictionary = {}
		if _boot_compute_z == 0:
			prepared_flora_payload = entry.get("flora_payload", {}) as Dictionary
		var install_entry: Dictionary = _prepare_chunk_install_entry(
			coord,
			_boot_compute_z,
			native_data,
			null,
			prepared_flora_payload
		)
		if install_entry.is_empty():
			continue
		entry["install_entry"] = install_entry
		_boot_apply_queue.append(entry)
		prepared_this_step += 1
	_sort_chunk_entry_queue_by_priority(_boot_apply_queue, _boot_center)
	return prepared_this_step

## Apply up to BOOT_MAX_APPLY_PER_STEP chunks from the sorted apply queue.
## Startup chunks publish through the visual scheduler and stay hidden until
## first-pass readiness is reached.
func _boot_apply_from_queue() -> int:
	var applied_this_step: int = 0
	while not _boot_apply_queue.is_empty() and applied_this_step < BOOT_MAX_APPLY_PER_STEP:
		if _shutdown_in_progress:
			break
		var front_coord: Vector2i = _boot_apply_queue[0].get("coord", Vector2i.ZERO) as Vector2i
		if _boot_get_chunk_ring(front_coord) > BOOT_FIRST_PLAYABLE_MAX_RING:
			break  # Ring 2+ deferred to runtime streaming after first_playable (boot_fast_first_playable_spec 1C)
		var step_start_usec: int = Time.get_ticks_usec()
		var entry: Dictionary = _boot_apply_queue.pop_front()
		var coord: Vector2i = entry.get("coord", Vector2i.ZERO) as Vector2i
		var install_entry: Dictionary = entry.get("install_entry", {}) as Dictionary
		var apply_usec: int = Time.get_ticks_usec()
		_boot_apply_chunk_from_native_data(
			coord,
			_boot_compute_z,
			install_entry.get("native_data", {}) as Dictionary,
			entry.get("flora_payload", {}) as Dictionary,
			install_entry
		)
		var apply_ms: float = float(Time.get_ticks_usec() - apply_usec) / 1000.0
		_boot_metric_apply_ms += apply_ms
		_boot_metric_chunks_applied += 1
		WorldPerfProbe.record("Boot.apply_chunk %s" % [coord], apply_ms)
		applied_this_step += 1
		_boot_applied_count += 1
		var step_ms: float = float(Time.get_ticks_usec() - step_start_usec) / 1000.0
		if step_ms > BOOT_APPLY_WARNING_MS:
			WorldPerfProbe.record("Boot.apply_step_over_budget_ms", step_ms)
	return applied_this_step

## Wait for all active boot compute tasks and clean up.
func _boot_wait_all_compute() -> void:
	for coord: Vector2i in _boot_compute_active.keys():
		var task_id: int = int(_boot_compute_active[coord])
		WorkerThreadPool.wait_for_task_completion(task_id)
	_boot_compute_active.clear()
	_boot_compute_builders.clear()

func _boot_cleanup_compute_pipeline() -> void:
	_boot_compute_pending.clear()
	_boot_compute_active.clear()
	_boot_compute_builders.clear()
	_boot_runtime_handoff_started = false
	_boot_compute_requested_usec.clear()
	_boot_compute_started_usec.clear()
	_boot_compute_mutex.lock()
	_boot_compute_results.clear()
	_boot_compute_mutex.unlock()
	_boot_prepare_queue.clear()
	_boot_apply_queue.clear()
	_boot_applied_count = 0
	_boot_total_count = 0
	if not _boot_failed_coords.is_empty():
		print("[Boot] %d chunk(s) failed compute: %s" % [_boot_failed_coords.size(), str(_boot_failed_coords)])

## Main-thread apply: creates Chunk node, populates, attaches to tree.
func _boot_apply_chunk_from_native_data(
	coord: Vector2i,
	z_level: int,
	native_data: Dictionary,
	flora_payload: Dictionary = {},
	install_entry: Dictionary = {}
) -> void:
	coord = _canonical_chunk_coord(coord)
	var loaded_chunks_for_z: Dictionary = _z_chunks.get(z_level, {})
	if loaded_chunks_for_z.has(coord):
		_boot_on_chunk_applied(coord, loaded_chunks_for_z.get(coord) as Chunk)
		return
	var effective_install_entry: Dictionary = install_entry
	if effective_install_entry.is_empty():
		var prepared_flora_payload: Dictionary = flora_payload if z_level == 0 else {}
		effective_install_entry = _prepare_chunk_install_entry(
			coord,
			z_level,
			native_data,
			null,
			prepared_flora_payload
		)
	if effective_install_entry.is_empty():
		return
	var chunk: Chunk = _create_chunk_from_install_entry(effective_install_entry)
	if chunk == null:
		return
	_finalize_chunk_install(coord, z_level, chunk)

## --- Boot readiness helpers (boot_chunk_readiness_spec) ---

func _boot_init_readiness(center: Vector2i, load_radius: int) -> void:
	_boot_chunk_states.clear()
	_boot_center = center
	_boot_load_radius = load_radius
	_boot_first_playable = false
	_boot_complete_flag = false
	_boot_topology_ready = false
	_boot_has_remaining_chunks = false
	_boot_pipeline_drained = false
	_boot_runtime_handoff_started = false
	_boot_started_usec = Time.get_ticks_usec()
	_boot_compute_generation += 1
	_boot_failed_coords.clear()
	_boot_compute_requested_usec.clear()
	_boot_compute_started_usec.clear()
	_boot_metric_compute_ms = 0.0
	_boot_metric_apply_ms = 0.0
	_boot_metric_terrain_redraw_ms = 0.0
	_boot_metric_queue_wait_ms = 0.0
	_boot_metric_chunks_computed = 0
	_boot_metric_chunks_applied = 0
	_boot_prepare_queue.clear()
	_boot_apply_queue.clear()

func _boot_set_chunk_state(coord: Vector2i, new_state: BootChunkState) -> void:
	var current_state: int = int(_boot_chunk_states.get(coord, -1))
	assert(new_state != BootChunkState.VISUAL_COMPLETE or current_state >= BootChunkState.APPLIED,
		"boot: visual_complete must not precede applied for chunk %s" % [coord])
	_boot_chunk_states[coord] = new_state

func _boot_get_chunk_ring(coord: Vector2i) -> int:
	return _chunk_chebyshev_distance(coord, _boot_center)

func _boot_update_gates() -> void:
	if _boot_chunk_states.is_empty():
		return
	var all_chunks_terminal: bool = _boot_all_tracked_chunks_visual_complete()
	var was_first_playable: bool = _boot_first_playable
	_boot_first_playable = _boot_is_first_playable_slice_ready()
	if _boot_first_playable and not was_first_playable:
		var elapsed_ms: float = float(Time.get_ticks_usec() - _boot_started_usec) / 1000.0 if _boot_started_usec > 0 else 0.0
		WorldPerfProbe.mark_milestone("Boot.first_playable")
		print("[Boot] first_playable reached (%.1f ms) | queue_wait=%.1fms compute=%.1fms (%d chunks) apply=%.1fms (%d chunks) redraw=%.1fms" % [
			elapsed_ms, _boot_metric_queue_wait_ms, _boot_metric_compute_ms, _boot_metric_chunks_computed,
			_boot_metric_apply_ms, _boot_metric_chunks_applied,
			_boot_metric_terrain_redraw_ms])
	var was_boot_complete: bool = _boot_complete_flag
	_boot_complete_flag = all_chunks_terminal and _boot_topology_ready
	if _boot_complete_flag and not was_boot_complete:
		var elapsed_ms: float = float(Time.get_ticks_usec() - _boot_started_usec) / 1000.0 if _boot_started_usec > 0 else 0.0
		WorldPerfProbe.mark_milestone("Boot.boot_complete")
		print("[Boot] boot_complete reached (%.1f ms) | queue_wait=%.1fms compute=%.1fms (%d chunks) apply=%.1fms (%d chunks) redraw=%.1fms" % [
			elapsed_ms, _boot_metric_queue_wait_ms, _boot_metric_compute_ms, _boot_metric_chunks_computed,
			_boot_metric_apply_ms, _boot_metric_chunks_applied,
			_boot_metric_terrain_redraw_ms])

func _boot_promote_redrawn_chunks() -> void:
	for coord: Vector2i in _boot_chunk_states:
		var state: int = int(_boot_chunk_states[coord])
		if state < BootChunkState.APPLIED:
			continue
		var chunk: Chunk = _loaded_chunks.get(coord)
		if chunk == null:
			continue
		_boot_on_chunk_redraw_progress(chunk)

## Read-only boot readiness API.

func is_boot_first_playable() -> bool:
	return _boot_first_playable

func is_boot_complete() -> bool:
	return _boot_complete_flag

func get_boot_chunk_state(coord: Vector2i) -> int:
	return int(_boot_chunk_states.get(coord, -1))

func get_boot_chunk_states_snapshot() -> Dictionary:
	return _boot_chunk_states.duplicate()

func get_boot_compute_active_count() -> int:
	return _boot_compute_active.size()

func get_boot_compute_pending_count() -> int:
	return _boot_compute_pending.size()

func get_boot_failed_coords() -> Array[Vector2i]:
	return _boot_failed_coords.duplicate()
