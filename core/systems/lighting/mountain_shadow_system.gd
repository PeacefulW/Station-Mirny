class_name MountainShadowSystem
extends Node

## Система теней от гор. Строит shadow_mask по чанкам на основе
## внешней кромки горы и угла солнца. Рендер через Sprite2D + ImageTexture.
## Edge-тайлы кешируются при загрузке чанка. Rebuild бюджетирован.

const RuntimeWorkTypes = preload("res://core/runtime/runtime_work_types.gd")
const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")
const JOB_SHADOWS: StringName = &"mountain_shadow.visual_rebuild"
const NATIVE_SHADOW_KERNELS_CLASS: StringName = &"MountainShadowKernels"
const INVALID_COORD: Vector2i = Vector2i(999999, 999999)
const SHADOW_START_SCAN_LIMIT: int = 4
const RETIRED_SHADOW_BUILD_LIMIT: int = 2
const EDGE_NEIGHBOR_OFFSETS: Array[Vector2i] = [
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
var _shadow_sprites: Dictionary = {}
var _shadow_container: Node2D = null
var _last_built_angle: float = -999.0
var _edge_cache: Dictionary = {}
var _edge_cache_versions: Dictionary = {}
var _edge_cache_ready_versions: Dictionary = {}
var _dirty_queue: Array[Vector2i] = []
var _edge_build_queue: Array[Vector2i] = []
var _active_edge_cache_build: Dictionary = {}
var _edge_cache_compute_results: Dictionary = {}
var _edge_cache_compute_mutex: Mutex = Mutex.new()
var _shadow_build_versions: Dictionary = {}
var _active_build: Dictionary = {}  ## Detached shadow compute + main-thread finalize state
var _retired_shadow_builds: Array[Dictionary] = []
var _shadow_compute_results: Dictionary = {}
var _shadow_compute_mutex: Mutex = Mutex.new()
var _prefer_shadow_step: bool = true
var _pending_mined_tile_updates: Array[Vector2i] = []
var _pending_mined_tile_update_lookup: Dictionary = {}
var _current_z: int = 0
var _boot_shadow_work_started: bool = false
var _boot_shadow_work_drained: bool = false
var _boot_shadow_completion_emitted: bool = false
var _worker_task_serial: int = 0
var _native_shadow_kernels_checked: bool = false
var _native_shadow_kernels_available: bool = false
var _native_shadow_kernel_error_emitted: bool = false
var _sync_boot_shadow_runtime_warning_emitted: bool = false

signal boot_shadow_work_drained

func _ready() -> void:
	_shadow_container = Node2D.new()
	_shadow_container.name = "ShadowContainer"
	_shadow_container.z_index = -5
	add_child(_shadow_container)
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	EventBus.mountain_tile_mined.connect(_on_mountain_tile_mined)
	EventBus.z_level_changed.connect(_on_z_level_changed)
	_current_z = _resolve_current_z()
	_shadow_container.visible = _is_surface_context()
	call_deferred("_resolve_dependencies")

func _exit_tree() -> void:
	if FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(JOB_SHADOWS)
	_wait_for_active_compute_tasks()

func _process(_delta: float) -> void:
	if not _chunk_manager or not TimeManager or not WorldGenerator or not WorldGenerator.balance:
		return
	if not _is_surface_context():
		return
	var sun_angle: float = TimeManager.get_sun_angle()
	var threshold: float = WorldGenerator.balance.shadow_angle_threshold
	if absf(sun_angle - _last_built_angle) > threshold:
		_last_built_angle = sun_angle
		_mark_all_dirty()

func _resolve_dependencies() -> void:
	var chunks: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunks.is_empty():
		_chunk_manager = chunks[0] as ChunkManager
	_cache_native_shadow_kernels_support()
	FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_VISUAL,
		3.5,
		_tick_shadows,
		JOB_SHADOWS,
		RuntimeWorkTypes.CadenceKind.PRESENTATION,
		RuntimeWorkTypes.ThreadingRole.COMPUTE_THEN_APPLY,
		false,
		"Mountain shadows"
	)

func build_boot_shadows() -> void:
	_warn_if_sync_boot_shadow_after_handoff(&"build_boot_shadows")
	if not _chunk_manager:
		_resolve_dependencies()
	if not _is_surface_context() or not _chunk_manager:
		_suspend_surface_shadow_runtime(true)
		return
	_mark_boot_shadow_work_started()
	var player_chunk: Vector2i = _get_player_chunk_coord()
	var coords: Array[Vector2i] = []
	for coord: Vector2i in _chunk_manager.get_loaded_chunks():
		if _chunk_or_neighbors_have_mountain(coord):
			coords.append(coord)
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_priority_score(a, player_chunk) < _chunk_priority_score(b, player_chunk)
	)
	_suspend_surface_shadow_runtime(false)
	var live_coords: Dictionary = {}
	for coord: Vector2i in coords:
		live_coords[coord] = true
	for existing_coord: Vector2i in _shadow_sprites.keys():
		if live_coords.has(existing_coord):
			continue
		_remove_shadow(existing_coord)
	for coord: Vector2i in coords:
		_build_edge_cache_now(coord)
	for coord: Vector2i in coords:
		_rebuild_shadow_now(coord)
	_seed_current_sun_angle()
	_show_shadow_container()
	_refresh_boot_shadow_completion_state()

## Lightweight boot initialization: seeds sun angle, shows container, and ensures
## all loaded mountain chunks are in the dirty/edge queues for budgeted processing
## via _tick_shadows() (FrameBudgetDispatcher). No synchronous rebuild.
func schedule_boot_shadows() -> void:
	if not _chunk_manager:
		_resolve_dependencies()
	if not _is_surface_context() or not _chunk_manager:
		_suspend_surface_shadow_runtime(true)
		return
	_mark_boot_shadow_work_started()
	_suspend_surface_shadow_runtime(false)
	## Chunks already enqueued via EventBus.chunk_loaded → _on_chunk_loaded.
	## Ensure nothing was missed and re-mark all dirty for completeness.
	for coord: Vector2i in _chunk_manager.get_loaded_chunks():
		if _chunk_or_neighbors_have_mountain(coord):
			_enqueue_edge_cache_build(coord)
			_mark_dirty(coord)
	_seed_current_sun_angle()
	_show_shadow_container()
	_refresh_boot_shadow_completion_state()

func prepare_boot_shadows(progress_callback: Callable) -> void:
	_warn_if_sync_boot_shadow_after_handoff(&"prepare_boot_shadows")
	if not _chunk_manager:
		_resolve_dependencies()
	if not _is_surface_context() or not _chunk_manager:
		_suspend_surface_shadow_runtime(true)
		return
	_mark_boot_shadow_work_started()
	var player_chunk: Vector2i = _get_player_chunk_coord()
	var coords: Array[Vector2i] = []
	for coord: Vector2i in _chunk_manager.get_loaded_chunks():
		if _chunk_or_neighbors_have_mountain(coord):
			coords.append(coord)
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_priority_score(a, player_chunk) < _chunk_priority_score(b, player_chunk)
	)
	_suspend_surface_shadow_runtime(false)
	var live_coords: Dictionary = {}
	for coord: Vector2i in coords:
		live_coords[coord] = true
	for existing_coord: Vector2i in _shadow_sprites.keys():
		if live_coords.has(existing_coord):
			continue
		_remove_shadow(existing_coord)
	var total_steps: int = maxi(1, coords.size() * 2)
	var completed_steps: int = 0
	if progress_callback.is_valid():
		progress_callback.call(96.0, Localization.t("UI_LOADING_BUILDING_MOUNTAINS"))
	for coord: Vector2i in coords:
		_build_edge_cache_now(coord)
		completed_steps += 1
		_report_boot_shadow_progress(progress_callback, completed_steps, total_steps)
	for coord: Vector2i in coords:
		_rebuild_shadow_now(coord)
		completed_steps += 1
		_report_boot_shadow_progress(progress_callback, completed_steps, total_steps)
	_seed_current_sun_angle()
	_show_shadow_container()
	_refresh_boot_shadow_completion_state()

func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	if new_z == _current_z:
		_show_shadow_container()
		return
	_current_z = new_z
	if not _is_surface_context():
		_suspend_surface_shadow_runtime(true)
		return
	_show_shadow_container()
	_mark_all_dirty()

func set_active_z_level(new_z: int) -> void:
	_on_z_level_changed(new_z, _current_z)

func _on_chunk_loaded(coord: Vector2i) -> void:
	if not _is_surface_context():
		return
	coord = _canonical_chunk_coord(coord)
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	if chunk and chunk.has_any_mountain():
		_enqueue_edge_cache_build(coord)
	_mark_dirty(coord)
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		_mark_dirty(_offset_chunk_coord(coord, dir))
	_refresh_boot_shadow_completion_state()

func _on_chunk_unloaded(coord: Vector2i) -> void:
	coord = _canonical_chunk_coord(coord)
	var active_edge_coord: Vector2i = _active_edge_cache_build.get("coord", Vector2i(999999, 999999))
	if not _active_edge_cache_build.is_empty() \
		and active_edge_coord == coord:
		_active_edge_cache_build["cancelled"] = true
	_supersede_active_shadow_build(coord)
	_edge_cache.erase(coord)
	_edge_cache_ready_versions.erase(coord)
	_remove_shadow(coord)
	_refresh_boot_shadow_completion_state()

func _on_mountain_tile_mined(tile_pos: Vector2i, _old_type: int, _new_type: int) -> void:
	if not _is_surface_context():
		return
	tile_pos = WorldGenerator.canonicalize_tile(tile_pos)
	if not _pending_mined_tile_update_lookup.has(tile_pos):
		_pending_mined_tile_update_lookup[tile_pos] = true
		_pending_mined_tile_updates.append(tile_pos)
	_refresh_boot_shadow_completion_state()

func _mark_dirty(coord: Vector2i) -> void:
	coord = _canonical_chunk_coord(coord)
	_bump_chunk_version(_shadow_build_versions, coord)
	_supersede_active_shadow_build(coord)
	if coord not in _dirty_queue:
		_dirty_queue.append(coord)

func _mark_all_dirty() -> void:
	if not _chunk_manager:
		return
	for coord: Vector2i in _chunk_manager.get_loaded_chunks():
		if _chunk_or_neighbors_have_mountain(coord):
			_mark_dirty(coord)
	_refresh_boot_shadow_completion_state()

## Tick для FrameBudgetDispatcher. Edge build → progressive shadow build.
func _tick_shadows() -> bool:
	_drain_retired_shadow_builds()
	if not _is_surface_context():
		_tick_suspended_shadow_runtime()
		_refresh_boot_shadow_completion_state()
		return false
	if _try_mined_tile_update_step():
		_refresh_boot_shadow_completion_state()
		return false
	if _should_yield_to_chunk_visual_pressure():
		_refresh_boot_shadow_completion_state()
		return false
	if not _active_build.is_empty():
		var phase: String = str(_active_build.get("phase", "compute"))
		match phase:
			"compute":
				_advance_shadow_build()
			"finalize_texture":
				_finalize_shadow_texture()
			"finalize_apply":
				_finalize_shadow_apply()
			_:
				_active_build.clear()
		_refresh_boot_shadow_completion_state()
		return false
	var has_dirty: bool = not _dirty_queue.is_empty()
	var has_edge_work: bool = not _active_edge_cache_build.is_empty() or not _edge_build_queue.is_empty()
	if has_dirty and has_edge_work:
		if _prefer_shadow_step and _try_shadow_step():
			_prefer_shadow_step = false
			_refresh_boot_shadow_completion_state()
			return false
		if _try_edge_step():
			_prefer_shadow_step = true
			_refresh_boot_shadow_completion_state()
			return false
		if _try_shadow_step():
			_prefer_shadow_step = false
			_refresh_boot_shadow_completion_state()
			return false
		_refresh_boot_shadow_completion_state()
		return false
	if has_dirty:
		_try_shadow_step()
		_refresh_boot_shadow_completion_state()
		return false
	if has_edge_work:
		_try_edge_step()
		_refresh_boot_shadow_completion_state()
		return false
	_refresh_boot_shadow_completion_state()
	return false

func _should_yield_to_chunk_visual_pressure() -> bool:
	if _chunk_manager == null or not _chunk_manager.has_method("_has_player_visible_visual_pressure"):
		return false
	return bool(_chunk_manager._has_player_visible_visual_pressure())

func _try_mined_tile_update_step() -> bool:
	if _pending_mined_tile_updates.is_empty():
		return false
	var tile_pos: Vector2i = _pending_mined_tile_updates[0]
	_pending_mined_tile_updates.remove_at(0)
	_pending_mined_tile_update_lookup.erase(tile_pos)
	var update_payload: Dictionary = _collect_mined_tile_shadow_update_payload(tile_pos)
	var edge_dirty_coords: Array[Vector2i] = update_payload.get("edge_dirty_coords", []) as Array[Vector2i]
	var dirty_targets: Array[Vector2i] = update_payload.get("dirty_targets", []) as Array[Vector2i]
	for dirty_coord: Vector2i in dirty_targets:
		_mark_dirty(dirty_coord)
	if _should_emit_mined_shadow_refresh_diag(tile_pos, edge_dirty_coords, dirty_targets):
		_emit_shadow_refresh_diag(tile_pos, edge_dirty_coords, dirty_targets)
	return true

func _try_shadow_step() -> bool:
	var step_usec: int = WorldPerfProbe.begin()
	var deferred: Array[Vector2i] = []
	var remaining_checks: int = mini(SHADOW_START_SCAN_LIMIT, _dirty_queue.size())
	while remaining_checks > 0 and not _dirty_queue.is_empty():
		remaining_checks -= 1
		var coord: Vector2i = _pop_best_queue_coord(_dirty_queue)
		if not _chunk_manager or not _chunk_manager.get_chunk(coord):
			continue
		if not _shadow_inputs_ready(coord):
			deferred.append(coord)
			continue
		_start_shadow_build(coord)
		for deferred_coord: Vector2i in deferred:
			_requeue_dirty_coord(deferred_coord)
		WorldPerfProbe.end("Shadow.try_shadow_step start=%s deferred=%d" % [coord, deferred.size()], step_usec)
		return true
	for deferred_coord: Vector2i in deferred:
		_requeue_dirty_coord(deferred_coord)
	WorldPerfProbe.end("Shadow.try_shadow_step start=none deferred=%d" % [deferred.size()], step_usec)
	return false

func _try_edge_step() -> bool:
	if not _active_edge_cache_build.is_empty():
		_advance_edge_cache_build()
		return true
	if not _edge_build_queue.is_empty():
		var coord: Vector2i = _pop_best_queue_coord(_edge_build_queue)
		_start_edge_cache_build(coord)
		return true
	return false

func _collect_mined_tile_shadow_update_payload(tile_pos: Vector2i) -> Dictionary:
	return _update_edges_at(tile_pos)

## Инкрементальное обновление edge-кеша для 1 тайла и 8 соседей. O(9) вместо O(4096).
func _update_edges_at(tile_pos: Vector2i) -> Dictionary:
	if not _chunk_manager:
		return {
			"edge_dirty_coords": [],
			"dirty_targets": [],
		}
	var dirty_targets: Dictionary = {}
	var edge_dirty_coords: Dictionary = {}
	var boundary_reach: int = _resolve_shadow_cross_chunk_reach()
	var ready_changed_coords: Dictionary = {}
	var coords_needing_rebuild: Dictionary = {}
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var check_tile: Vector2i = WorldGenerator.offset_tile(tile_pos, Vector2i(offset_x, offset_y))
			var coord: Vector2i = _canonical_chunk_coord(WorldGenerator.tile_to_chunk(check_tile))
			var chunk: Chunk = _chunk_manager.get_chunk(coord)
			if not chunk:
				continue
			var chunk_size: int = chunk.get_chunk_size()
			var local_tile: Vector2i = chunk.global_to_local(check_tile)
			if local_tile.x < 0 or local_tile.y < 0 or local_tile.x >= chunk_size or local_tile.y >= chunk_size:
				continue
			var terrain_bytes: PackedByteArray = chunk.get_terrain_bytes()
			var local_index: int = local_tile.y * chunk_size + local_tile.x
			var is_edge: bool = terrain_bytes[local_index] == TileGenData.TerrainType.ROCK \
				and _is_external_edge_at(coord, terrain_bytes, local_tile.x, local_tile.y, chunk_size)
			var previous_version: int = int(_edge_cache_versions.get(coord, 0))
			var had_ready_cache: bool = _edge_cache.has(coord) \
				and int(_edge_cache_ready_versions.get(coord, -1)) == previous_version
			if not _edge_cache.has(coord):
				_edge_cache[coord] = [] as Array[Vector2i]
			var edges: Array = _edge_cache[coord] as Array
			var edge_idx: int = edges.find(check_tile)
			var had_edge: bool = edge_idx >= 0
			if is_edge == had_edge:
				continue
			if is_edge:
				edges.append(check_tile)
			else:
				edges.remove_at(edge_idx)
			edge_dirty_coords[coord] = true
			ready_changed_coords[coord] = had_ready_cache
			if not had_ready_cache:
				coords_needing_rebuild[coord] = true
			_maybe_mark_shadow_target(dirty_targets, coord)
			if local_tile.x < boundary_reach:
				_maybe_mark_shadow_target(dirty_targets, _offset_chunk_coord(coord, Vector2i.LEFT))
			if local_tile.x >= chunk_size - boundary_reach:
				_maybe_mark_shadow_target(dirty_targets, _offset_chunk_coord(coord, Vector2i.RIGHT))
			if local_tile.y < boundary_reach:
				_maybe_mark_shadow_target(dirty_targets, _offset_chunk_coord(coord, Vector2i.UP))
			if local_tile.y >= chunk_size - boundary_reach:
				_maybe_mark_shadow_target(dirty_targets, _offset_chunk_coord(coord, Vector2i.DOWN))
	for changed_coord_variant: Variant in edge_dirty_coords.keys():
		var changed_coord: Vector2i = changed_coord_variant as Vector2i
		var new_version: int = _bump_chunk_version(_edge_cache_versions, changed_coord)
		if bool(ready_changed_coords.get(changed_coord, false)):
			_edge_cache_ready_versions[changed_coord] = new_version
		else:
			_edge_cache_ready_versions.erase(changed_coord)
		if coords_needing_rebuild.has(changed_coord) and changed_coord not in _edge_build_queue:
			_edge_build_queue.append(changed_coord)
	var edge_coord_list: Array[Vector2i] = []
	for coord_variant: Variant in edge_dirty_coords.keys():
		edge_coord_list.append(coord_variant as Vector2i)
	var dirty_target_list: Array[Vector2i] = []
	for target_variant: Variant in dirty_targets.keys():
		dirty_target_list.append(target_variant as Vector2i)
	return {
		"edge_dirty_coords": edge_coord_list,
		"dirty_targets": dirty_target_list,
	}

func _should_emit_mined_shadow_refresh_diag(
	tile_pos: Vector2i,
	edge_dirty_coords: Array[Vector2i],
	dirty_targets: Array[Vector2i]
) -> bool:
	if edge_dirty_coords.is_empty() and dirty_targets.is_empty():
		return false
	if WorldGenerator == null:
		return false
	var source_chunk: Vector2i = _canonical_chunk_coord(WorldGenerator.tile_to_chunk(tile_pos))
	for edge_coord: Vector2i in edge_dirty_coords:
		if edge_coord != source_chunk:
			return true
	for dirty_coord: Vector2i in dirty_targets:
		if dirty_coord != source_chunk:
			return true
	return false

func _resolve_shadow_cross_chunk_reach() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.shadow_max_length)
	return 8

func _is_shadow_target_live(coord: Vector2i) -> bool:
	if _shadow_sprites.has(coord):
		return true
	return _chunk_manager != null and _chunk_manager.get_chunk(coord) != null

func _maybe_mark_shadow_target(targets: Dictionary, coord: Vector2i) -> void:
	coord = _canonical_chunk_coord(coord)
	if _is_shadow_target_live(coord):
		targets[coord] = true

static func _copy_edge_array(source: Array) -> Array[Vector2i]:
	var copy: Array[Vector2i] = []
	for edge_variant: Variant in source:
		copy.append(edge_variant as Vector2i)
	return copy

static func _edge_tile_key(edge: Vector2i) -> String:
	return "%d:%d" % [edge.x, edge.y]

static func _build_edge_lookup(edges: Array[Vector2i]) -> Dictionary:
	var lookup: Dictionary = {}
	for edge: Vector2i in edges:
		lookup[_edge_tile_key(edge)] = edge
	return lookup

static func _edge_lookup_differs(old_lookup: Dictionary, new_lookup: Dictionary) -> bool:
	if old_lookup.size() != new_lookup.size():
		return true
	for key_variant: Variant in old_lookup.keys():
		if not new_lookup.has(key_variant):
			return true
	return false

func _edge_touches_boundary(
	coord: Vector2i,
	edge: Vector2i,
	dir: Vector2i,
	chunk_size: int,
	boundary_reach: int
) -> bool:
	var origin: Vector2i = WorldGenerator.chunk_to_tile_origin(coord)
	var local_x: int = edge.x - origin.x
	var local_y: int = edge.y - origin.y
	match dir:
		Vector2i.LEFT:
			return local_x >= 0 and local_x < boundary_reach
		Vector2i.RIGHT:
			return local_x >= chunk_size - boundary_reach and local_x < chunk_size
		Vector2i.UP:
			return local_y >= 0 and local_y < boundary_reach
		Vector2i.DOWN:
			return local_y >= chunk_size - boundary_reach and local_y < chunk_size
		_:
			return false

func _edge_boundary_differs_one_way(
	coord: Vector2i,
	source_lookup: Dictionary,
	other_lookup: Dictionary,
	dir: Vector2i,
	chunk_size: int,
	boundary_reach: int
) -> bool:
	for edge_variant: Variant in source_lookup.values():
		var edge: Vector2i = edge_variant as Vector2i
		if not _edge_touches_boundary(coord, edge, dir, chunk_size, boundary_reach):
			continue
		if not other_lookup.has(_edge_tile_key(edge)):
			return true
	return false

func _edge_boundary_differs(
	coord: Vector2i,
	old_lookup: Dictionary,
	new_lookup: Dictionary,
	dir: Vector2i,
	chunk_size: int,
	boundary_reach: int
) -> bool:
	return _edge_boundary_differs_one_way(coord, old_lookup, new_lookup, dir, chunk_size, boundary_reach) \
		or _edge_boundary_differs_one_way(coord, new_lookup, old_lookup, dir, chunk_size, boundary_reach)

func _collect_shadow_targets_for_edge_delta(
	coord: Vector2i,
	old_edges: Array[Vector2i],
	new_edges: Array[Vector2i]
) -> Array[Vector2i]:
	var old_lookup: Dictionary = _build_edge_lookup(old_edges)
	var new_lookup: Dictionary = _build_edge_lookup(new_edges)
	var dirty_targets: Dictionary = {}
	if _edge_lookup_differs(old_lookup, new_lookup):
		_maybe_mark_shadow_target(dirty_targets, coord)
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	var chunk_size: int = chunk.get_chunk_size() if chunk != null else (WorldGenerator.balance.chunk_size_tiles if WorldGenerator and WorldGenerator.balance else 64)
	var boundary_reach: int = mini(chunk_size, _resolve_shadow_cross_chunk_reach())
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not _edge_boundary_differs(coord, old_lookup, new_lookup, dir, chunk_size, boundary_reach):
			continue
		_maybe_mark_shadow_target(dirty_targets, _offset_chunk_coord(coord, dir))
	var result: Array[Vector2i] = []
	for target_variant: Variant in dirty_targets.keys():
		result.append(target_variant as Vector2i)
	return result

func _supersede_active_shadow_build(coord: Vector2i) -> void:
	if _active_build.is_empty():
		return
	var active_coord: Vector2i = _active_build.get("coord", INVALID_COORD)
	if active_coord != coord:
		return
	var phase: String = str(_active_build.get("phase", "compute"))
	if phase != "compute":
		_active_build.clear()
		WorldPerfProbe.record("Shadow.stale_superseded", 1.0)
		return
	_drain_retired_shadow_builds()
	if _retired_shadow_builds.size() >= RETIRED_SHADOW_BUILD_LIMIT:
		_active_build["cancelled"] = true
		return
	_retired_shadow_builds.append({
		"task_id": int(_active_build.get("task_id", -1)),
		"task_key": str(_active_build.get("task_key", "")),
	})
	_active_build.clear()
	WorldPerfProbe.record("Shadow.stale_superseded", 1.0)

func _drain_retired_shadow_builds(force_wait: bool = false) -> void:
	if _retired_shadow_builds.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for build: Dictionary in _retired_shadow_builds:
		var task_id: int = int(build.get("task_id", -1))
		var task_key: String = str(build.get("task_key", ""))
		if task_id >= 0 and not force_wait and not WorkerThreadPool.is_task_completed(task_id):
			remaining.append(build)
			continue
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
		_take_shadow_worker_result(task_key)
		WorldPerfProbe.record("Shadow.stale_discarded", 1.0)
	_retired_shadow_builds = remaining

func _enqueue_edge_cache_build(coord: Vector2i) -> void:
	coord = _canonical_chunk_coord(coord)
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	if not chunk or not chunk.has_any_mountain():
		return
	_bump_chunk_version(_edge_cache_versions, coord)
	_edge_cache_ready_versions.erase(coord)
	if coord not in _edge_build_queue:
		_edge_build_queue.append(coord)

func _pop_best_queue_coord(queue: Array[Vector2i]) -> Vector2i:
	if queue.is_empty():
		return INVALID_COORD
	var player_chunk: Vector2i = _get_player_chunk_coord()
	if player_chunk == INVALID_COORD:
		var first_coord: Vector2i = queue[0]
		queue.remove_at(0)
		return first_coord
	var best_idx: int = 0
	var best_score: int = _chunk_priority_score(queue[0], player_chunk)
	for i: int in range(1, queue.size()):
		var score: int = _chunk_priority_score(queue[i], player_chunk)
		if score < best_score:
			best_idx = i
			best_score = score
	var coord: Vector2i = queue[best_idx]
	queue.remove_at(best_idx)
	return coord

func _get_player_chunk_coord() -> Vector2i:
	if not WorldGenerator or not PlayerAuthority:
		return INVALID_COORD
	var player_pos: Vector2 = PlayerAuthority.get_local_player_position()
	var player_tile: Vector2i = WorldGenerator.world_to_tile(player_pos)
	return WorldGenerator.tile_to_chunk(player_tile)

func _canonical_chunk_coord(coord: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("canonicalize_chunk_coord"):
		return WorldGenerator.canonicalize_chunk_coord(coord)
	return coord

func _offset_chunk_coord(coord: Vector2i, offset: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("offset_chunk_coord"):
		return WorldGenerator.offset_chunk_coord(coord, offset)
	return coord + offset

func _chunk_priority_score(coord: Vector2i, player_chunk: Vector2i) -> int:
	var dx: int = WorldGenerator.chunk_wrap_delta_x(coord.x, player_chunk.x) if WorldGenerator and WorldGenerator.has_method("chunk_wrap_delta_x") else coord.x - player_chunk.x
	var dy: int = coord.y - player_chunk.y
	return dx * dx + dy * dy

func _resolve_shadow_diag_scope(coord: Vector2i) -> StringName:
	var player_chunk: Vector2i = _get_player_chunk_coord()
	if player_chunk == INVALID_COORD:
		return &"far_runtime_backlog"
	if coord == player_chunk:
		return &"player_chunk"
	var dx: int = coord.x - player_chunk.x
	if WorldGenerator and WorldGenerator.has_method("chunk_wrap_delta_x"):
		dx = WorldGenerator.chunk_wrap_delta_x(coord.x, player_chunk.x)
	var dy: int = coord.y - player_chunk.y
	if maxi(absi(dx), absi(dy)) <= 1:
		return &"adjacent_loaded_chunk"
	return &"far_runtime_backlog"

func _resolve_shadow_diag_impact(scope: StringName) -> StringName:
	if scope == &"far_runtime_backlog":
		return WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT
	return WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE

func _pick_shadow_diag_target_coord(coords: Array[Vector2i]) -> Vector2i:
	if coords.is_empty():
		return INVALID_COORD
	var player_chunk: Vector2i = _get_player_chunk_coord()
	if player_chunk == INVALID_COORD:
		return coords[0]
	var best_coord: Vector2i = coords[0]
	var best_score: int = _chunk_priority_score(best_coord, player_chunk)
	for coord: Vector2i in coords:
		var score: int = _chunk_priority_score(coord, player_chunk)
		if score < best_score:
			best_coord = coord
			best_score = score
	return best_coord

func _emit_shadow_refresh_diag(
	tile_pos: Vector2i,
	edge_dirty_coords: Array[Vector2i],
	dirty_targets: Array[Vector2i]
) -> void:
	var target_coord: Vector2i = _pick_shadow_diag_target_coord(
		dirty_targets if not dirty_targets.is_empty() else edge_dirty_coords
	)
	if target_coord == INVALID_COORD:
		return
	var scope: StringName = _resolve_shadow_diag_scope(target_coord)
	var impact_key: StringName = _resolve_shadow_diag_impact(scope)
	var record: Dictionary = {
		"actor": "shadow_refresh",
		"actor_human": "Обновление теней горы",
		"action": "queue_follow_up",
		"action_human": "поставило в очередь пересчёт теней",
		"target": String(scope),
		"target_human": WorldRuntimeDiagnosticLog.describe_chunk_scope(scope, target_coord),
		"reason": "queued_not_applied",
		"reason_human": "после изменения края горы нужно пересчитать кеш внешней кромки (edge cache) и теневую маску",
		"impact": String(impact_key),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact_key),
		"state": "queued",
		"state_human": "очередь ещё не применена",
		"severity": String(WorldRuntimeDiagnosticLog.SEVERITY_FOLLOW_UP),
		"severity_human": WorldRuntimeDiagnosticLog.humanize_severity(WorldRuntimeDiagnosticLog.SEVERITY_FOLLOW_UP),
		"code": "shadow_refresh",
	}
	var detail_fields: Dictionary = {
		"dirty_targets": WorldRuntimeDiagnosticLog.format_coord_list(dirty_targets),
		"dirty_targets_count": dirty_targets.size(),
		"edge_dirty_coords": WorldRuntimeDiagnosticLog.format_coord_list(edge_dirty_coords),
		"edge_dirty_count": edge_dirty_coords.size(),
		"source_tile": str(tile_pos),
		"target_chunk": str(target_coord),
		"target_scope": String(scope),
	}
	WorldRuntimeDiagnosticLog.emit_record(record, detail_fields)

func _chunk_or_neighbors_have_mountain(coord: Vector2i) -> bool:
	if not _chunk_manager:
		return false
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if chunk and chunk.has_any_mountain():
		return true
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Chunk = _chunk_manager.get_chunk(_offset_chunk_coord(coord, dir))
		if neighbor and neighbor.has_any_mountain():
			return true
	return false

func _start_edge_cache_build(coord: Vector2i) -> void:
	if not _chunk_manager:
		return
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if not chunk or not chunk.has_any_mountain():
		var empty_version: int = _ensure_chunk_version(_edge_cache_versions, coord)
		var old_edges: Array[Vector2i] = _copy_edge_array(_edge_cache.get(coord, []) as Array)
		var empty_edges: Array[Vector2i] = []
		_edge_cache[coord] = empty_edges
		_edge_cache_ready_versions[coord] = empty_version
		_complete_edge_cache_build(coord, old_edges, empty_edges)
		return
	var version: int = _ensure_chunk_version(_edge_cache_versions, coord)
	var request: Dictionary = _build_edge_cache_request(coord, chunk, version)
	var task_key: String = _make_worker_task_key("edge", coord, version)
	var kernels: RefCounted = _create_shadow_kernels()
	if kernels == null:
		return
	var task_id: int = WorkerThreadPool.add_task(_worker_build_edge_cache.bind(task_key, request, kernels))
	_active_edge_cache_build = {
		"coord": coord,
		"version": version,
		"task_key": task_key,
		"task_id": task_id,
		"cancelled": false,
	}

func _advance_edge_cache_build() -> void:
	var build: Dictionary = _active_edge_cache_build
	var task_id: int = int(build.get("task_id", -1))
	if task_id < 0 or not WorkerThreadPool.is_task_completed(task_id):
		return
	WorkerThreadPool.wait_for_task_completion(task_id)
	var task_key: String = str(build.get("task_key", ""))
	var coord: Vector2i = build.get("coord", INVALID_COORD)
	var version: int = int(build.get("version", -1))
	var cancelled: bool = bool(build.get("cancelled", false))
	var result: Dictionary = _take_edge_cache_worker_result(task_key)
	_active_edge_cache_build.clear()
	if result.is_empty():
		return
	var compute_ms: float = float(result.get("compute_ms", 0.0))
	if compute_ms > 0.0:
		WorldPerfProbe.record("Shadow.edge_cache_compute %s" % [coord], compute_ms)
	if cancelled or coord == INVALID_COORD:
		return
	if int(_edge_cache_versions.get(coord, -1)) != version:
		return
	var old_edges: Array[Vector2i] = _copy_edge_array(_edge_cache.get(coord, []) as Array)
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	if not chunk or not chunk.has_any_mountain():
		var empty_edges: Array[Vector2i] = []
		_edge_cache[coord] = empty_edges
		_edge_cache_ready_versions[coord] = version
		_complete_edge_cache_build(coord, old_edges, empty_edges)
		return
	var new_edges: Array[Vector2i] = _copy_edge_array(result.get("edges", []) as Array)
	_edge_cache[coord] = new_edges
	_edge_cache_ready_versions[coord] = version
	_complete_edge_cache_build(coord, old_edges, new_edges)

func _complete_edge_cache_build(
	coord: Vector2i,
	old_edges: Array[Vector2i],
	new_edges: Array[Vector2i]
) -> void:
	for dirty_coord: Vector2i in _collect_shadow_targets_for_edge_delta(coord, old_edges, new_edges):
		_mark_dirty(dirty_coord)

func _build_edge_cache_now(coord: Vector2i) -> void:
	if not _chunk_manager:
		return
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if not chunk or not chunk.has_any_mountain():
		var empty_version: int = _ensure_chunk_version(_edge_cache_versions, coord)
		_edge_cache[coord] = [] as Array[Vector2i]
		_edge_cache_ready_versions[coord] = empty_version
		return
	var version: int = _ensure_chunk_version(_edge_cache_versions, coord)
	var request: Dictionary = _build_edge_cache_request(coord, chunk, version)
	var result: Dictionary = _run_edge_cache_request_blocking(request)
	if result.is_empty():
		return
	if int(_edge_cache_versions.get(coord, -1)) != version:
		return
	_edge_cache[coord] = _copy_edge_array(result.get("edges", []) as Array)
	_edge_cache_ready_versions[coord] = version

## Подготавливает detached shadow build для чанка.
func _start_shadow_build(coord: Vector2i) -> void:
	var request: Dictionary = _build_shadow_request(coord)
	if request.is_empty():
		_remove_shadow(coord)
		return
	var version: int = int(request.get("version", -1))
	var task_key: String = _make_worker_task_key("shadow", coord, version)
	var kernels: RefCounted = _create_shadow_kernels()
	if kernels == null:
		return
	var task_id: int = WorkerThreadPool.add_task(_worker_build_shadow.bind(task_key, request, kernels))
	_active_build = {
		"phase": "compute",
		"coord": coord,
		"version": version,
		"tile_size": int(request.get("tile_size", 1)),
		"base_x": int(request.get("base_x", 0)),
		"base_y": int(request.get("base_y", 0)),
		"task_key": task_key,
		"task_id": task_id,
		"cancelled": false,
	}

## Polls detached shadow raster/compute and forwards completed payloads to finalize/apply.
func _advance_shadow_build() -> void:
	var b: Dictionary = _active_build
	var task_id: int = int(b.get("task_id", -1))
	if task_id < 0 or not WorkerThreadPool.is_task_completed(task_id):
		return
	WorkerThreadPool.wait_for_task_completion(task_id)
	var task_key: String = str(b.get("task_key", ""))
	var coord: Vector2i = b.get("coord", INVALID_COORD)
	var version: int = int(b.get("version", -1))
	var cancelled: bool = bool(b.get("cancelled", false))
	var result: Dictionary = _take_shadow_worker_result(task_key)
	if result.is_empty():
		_active_build.clear()
		return
	var compute_ms: float = float(result.get("compute_ms", 0.0))
	if compute_ms > 0.0:
		WorldPerfProbe.record("Shadow.compute %s" % [coord], compute_ms)
	if cancelled or coord == INVALID_COORD or not _is_surface_context():
		_active_build.clear()
		return
	if int(_shadow_build_versions.get(coord, -1)) != version:
		_active_build.clear()
		return
	if not _chunk_manager or not _chunk_manager.get_chunk(coord):
		_remove_shadow(coord)
		_active_build.clear()
		return
	b.erase("task_id")
	b.erase("task_key")
	b["img"] = result.get("img")
	b["has_pixels"] = bool(result.get("has_pixels", false))
	b["phase"] = "finalize_texture"

## Финализация apply разбита на texture build и sprite apply, чтобы не склеивать её с последним compute-step.
func _finalize_shadow_texture() -> void:
	var finalize_usec: int = WorldPerfProbe.begin()
	var b: Dictionary = _active_build
	var coord: Vector2i = b.get("coord", Vector2i(999999, 999999))
	var version: int = int(b.get("version", -1))
	if int(_shadow_build_versions.get(coord, -1)) != version:
		_active_build.clear()
		WorldPerfProbe.end("Shadow.finalize_texture %s" % [coord], finalize_usec)
		_refresh_boot_shadow_completion_state()
		return
	var has_pixels: bool = b["has_pixels"] as bool
	var img: Image = b["img"] as Image
	if not has_pixels:
		_active_build.clear()
		_remove_shadow(coord)
		WorldPerfProbe.end("Shadow.finalize_texture %s" % [coord], finalize_usec)
		_refresh_boot_shadow_completion_state()
		return
	var reusable_texture: ImageTexture = null
	if _shadow_sprites.has(coord):
		var existing_sprite: Sprite2D = _shadow_sprites[coord] as Sprite2D
		if existing_sprite != null:
			reusable_texture = existing_sprite.texture as ImageTexture
	if reusable_texture != null \
		and reusable_texture.get_width() == img.get_width() \
		and reusable_texture.get_height() == img.get_height():
		reusable_texture.update(img)
		b["texture"] = reusable_texture
	else:
		b["texture"] = ImageTexture.create_from_image(img)
	b["phase"] = "finalize_apply"
	WorldPerfProbe.end("Shadow.finalize_texture %s" % [coord], finalize_usec)

func _finalize_shadow_apply() -> void:
	var finalize_usec: int = WorldPerfProbe.begin()
	var b: Dictionary = _active_build
	var coord: Vector2i = b.get("coord", Vector2i(999999, 999999))
	var version: int = int(b.get("version", -1))
	if int(_shadow_build_versions.get(coord, -1)) != version:
		_active_build.clear()
		WorldPerfProbe.end("Shadow.finalize_apply %s" % [coord], finalize_usec)
		_refresh_boot_shadow_completion_state()
		return
	var tile_size: int = b["tile_size"] as int
	var base_x: int = b["base_x"] as int
	var base_y: int = b["base_y"] as int
	var tex: ImageTexture = b.get("texture") as ImageTexture
	if not _chunk_manager or not _chunk_manager.get_chunk(coord) or tex == null:
		_active_build.clear()
		_remove_shadow(coord)
		WorldPerfProbe.end("Shadow.finalize_apply %s" % [coord], finalize_usec)
		_refresh_boot_shadow_completion_state()
		return
	var sprite: Sprite2D
	if _shadow_sprites.has(coord):
		sprite = _shadow_sprites[coord]
	else:
		sprite = Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_shadow_container.add_child(sprite)
		_shadow_sprites[coord] = sprite
	sprite.texture = tex
	sprite.scale = Vector2(tile_size, tile_size)
	sprite.position = Vector2(base_x * tile_size, base_y * tile_size)
	_active_build.clear()
	WorldPerfProbe.end("Shadow.finalize_apply %s" % [coord], finalize_usec)
	_refresh_boot_shadow_completion_state()

func _rebuild_shadow_now(coord: Vector2i) -> void:
	var request: Dictionary = _build_shadow_request(coord)
	if request.is_empty():
		_remove_shadow(coord)
		return
	var version: int = int(request.get("version", -1))
	var result: Dictionary = _run_shadow_request_blocking(request)
	if result.is_empty():
		return
	if int(_shadow_build_versions.get(coord, -1)) != version:
		return
	_active_build = {
		"phase": "finalize_texture",
		"coord": coord,
		"version": version,
		"tile_size": int(request.get("tile_size", 1)),
		"base_x": int(request.get("base_x", 0)),
		"base_y": int(request.get("base_y", 0)),
		"img": result.get("img"),
		"has_pixels": bool(result.get("has_pixels", false)),
		"cancelled": false,
	}
	while not _active_build.is_empty():
		var phase: String = str(_active_build.get("phase", "compute"))
		match phase:
			"compute":
				_advance_shadow_build()
			"finalize_texture":
				_finalize_shadow_texture()
			"finalize_apply":
				_finalize_shadow_apply()
			_:
				_active_build.clear()

func _build_edge_cache_request(coord: Vector2i, chunk: Chunk, version: int) -> Dictionary:
	var request_usec: int = WorldPerfProbe.begin()
	var chunk_size: int = chunk.get_chunk_size()
	var base_tile: Vector2i = WorldGenerator.chunk_to_tile_origin(coord)
	var request: Dictionary = {
		"coord": coord,
		"version": version,
		"chunk_size": chunk_size,
		"base_x": base_tile.x,
		"base_y": base_tile.y,
		"terrain_snapshot": _build_edge_terrain_snapshot(coord, chunk),
	}
	WorldPerfProbe.end("Shadow.edge_cache_request %s" % [coord], request_usec)
	return request

func _build_edge_terrain_snapshot(coord: Vector2i, chunk: Chunk) -> PackedByteArray:
	var chunk_size: int = chunk.get_chunk_size()
	var stride: int = chunk_size + 2
	var snapshot: PackedByteArray = PackedByteArray()
	snapshot.resize(stride * stride)
	var terrain_bytes: PackedByteArray = chunk.get_terrain_bytes()
	if terrain_bytes.size() < chunk_size * chunk_size:
		return snapshot
	for local_y: int in range(chunk_size):
		for local_x: int in range(chunk_size):
			var src_idx: int = local_y * chunk_size + local_x
			var dst_idx: int = (local_y + 1) * stride + (local_x + 1)
			snapshot[dst_idx] = terrain_bytes[src_idx]
	var base_tile: Vector2i = WorldGenerator.chunk_to_tile_origin(coord)
	for local_x: int in range(chunk_size):
		var top_idx: int = local_x + 1
		var bottom_idx: int = (stride - 1) * stride + local_x + 1
		snapshot[top_idx] = _read_edge_snapshot_terrain(base_tile + Vector2i(local_x, -1), chunk, terrain_bytes)
		snapshot[bottom_idx] = _read_edge_snapshot_terrain(base_tile + Vector2i(local_x, chunk_size), chunk, terrain_bytes)
	for local_y: int in range(chunk_size):
		var left_idx: int = (local_y + 1) * stride
		var right_idx: int = (local_y + 1) * stride + (stride - 1)
		snapshot[left_idx] = _read_edge_snapshot_terrain(base_tile + Vector2i(-1, local_y), chunk, terrain_bytes)
		snapshot[right_idx] = _read_edge_snapshot_terrain(base_tile + Vector2i(chunk_size, local_y), chunk, terrain_bytes)
	snapshot[0] = _read_edge_snapshot_terrain(base_tile + Vector2i(-1, -1), chunk, terrain_bytes)
	snapshot[stride - 1] = _read_edge_snapshot_terrain(base_tile + Vector2i(chunk_size, -1), chunk, terrain_bytes)
	snapshot[(stride - 1) * stride] = _read_edge_snapshot_terrain(base_tile + Vector2i(-1, chunk_size), chunk, terrain_bytes)
	snapshot[(stride * stride) - 1] = _read_edge_snapshot_terrain(base_tile + Vector2i(chunk_size, chunk_size), chunk, terrain_bytes)
	return snapshot

func _read_edge_snapshot_terrain(
	world_tile: Vector2i,
	center_chunk: Chunk,
	center_bytes: PackedByteArray
) -> int:
	if WorldGenerator:
		world_tile = WorldGenerator.canonicalize_tile(world_tile)
	var chunk_size: int = center_chunk.get_chunk_size() if center_chunk else 0
	if center_chunk and center_bytes.size() >= chunk_size * chunk_size:
		var local_center_tile: Vector2i = center_chunk.global_to_local(world_tile)
		if local_center_tile.x >= 0 and local_center_tile.y >= 0 and local_center_tile.x < chunk_size and local_center_tile.y < chunk_size:
			return center_bytes[local_center_tile.y * chunk_size + local_center_tile.x]
	if WorldGenerator == null:
		return TileGenData.TerrainType.GROUND
	var source_coord: Vector2i = _canonical_chunk_coord(WorldGenerator.tile_to_chunk(world_tile))
	if _chunk_manager:
		var source_chunk: Chunk = _chunk_manager.get_chunk(source_coord)
		if source_chunk:
			var source_chunk_size: int = source_chunk.get_chunk_size()
			var source_bytes: PackedByteArray = source_chunk.get_terrain_bytes()
			var local_tile: Vector2i = source_chunk.global_to_local(world_tile)
			if source_bytes.size() >= source_chunk_size * source_chunk_size \
				and local_tile.x >= 0 and local_tile.y >= 0 \
				and local_tile.x < source_chunk_size and local_tile.y < source_chunk_size:
				return source_bytes[local_tile.y * source_chunk_size + local_tile.x]
	if WorldGenerator:
		return int(WorldGenerator.get_terrain_type_fast(world_tile))
	return TileGenData.TerrainType.GROUND

func _run_edge_cache_request_blocking(request: Dictionary) -> Dictionary:
	var coord: Vector2i = request.get("coord", INVALID_COORD)
	var version: int = int(request.get("version", -1))
	var task_key: String = _make_worker_task_key("edge_sync", coord, version)
	var kernels: RefCounted = _create_shadow_kernels()
	if kernels == null:
		return {}
	var task_id: int = WorkerThreadPool.add_task(_worker_build_edge_cache.bind(task_key, request, kernels))
	WorkerThreadPool.wait_for_task_completion(task_id)
	return _take_edge_cache_worker_result(task_key)

func _worker_build_edge_cache(
	task_key: String,
	request: Dictionary,
	kernels: RefCounted = null
) -> void:
	var result: Dictionary = _compute_edge_cache_request(request, kernels)
	_edge_cache_compute_mutex.lock()
	_edge_cache_compute_results[task_key] = result
	_edge_cache_compute_mutex.unlock()

func _compute_edge_cache_request(
	request: Dictionary,
	kernels: RefCounted = null
) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var coord: Vector2i = request.get("coord", INVALID_COORD)
	var version: int = int(request.get("version", -1))
	var chunk_size: int = int(request.get("chunk_size", 0))
	var base_x: int = int(request.get("base_x", 0))
	var base_y: int = int(request.get("base_y", 0))
	var snapshot: PackedByteArray = request.get("terrain_snapshot", PackedByteArray()) as PackedByteArray
	if snapshot.is_empty():
		return {}
	if kernels == null:
		return {}
	var native_edges_variant: Variant = kernels.call("compute_edge_cache", chunk_size, base_x, base_y, snapshot)
	if typeof(native_edges_variant) != TYPE_ARRAY:
		return {}
	return {
		"coord": coord,
		"version": version,
		"edges": native_edges_variant,
		"compute_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}

func _take_edge_cache_worker_result(task_key: String) -> Dictionary:
	_edge_cache_compute_mutex.lock()
	var result: Dictionary = _edge_cache_compute_results.get(task_key, {}) as Dictionary
	_edge_cache_compute_results.erase(task_key)
	_edge_cache_compute_mutex.unlock()
	return result

func _build_shadow_request(coord: Vector2i) -> Dictionary:
	var request_usec: int = WorldPerfProbe.begin()
	if not _chunk_manager or not WorldGenerator or not WorldGenerator.balance or not TimeManager:
		WorldPerfProbe.end("Shadow.request %s" % [coord], request_usec)
		return {}
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if not chunk:
		WorldPerfProbe.end("Shadow.request %s" % [coord], request_usec)
		return {}
	var balance: WorldGenBalance = WorldGenerator.balance
	var length_factor: float = TimeManager.get_shadow_length_factor()
	if length_factor <= 0.0:
		WorldPerfProbe.end("Shadow.request %s" % [coord], request_usec)
		return {}
	var chunk_size: int = chunk.get_chunk_size()
	var shadow_length: int = clampi(
		int(float(balance.shadow_mountain_height) * length_factor),
		1, balance.shadow_max_length
	)
	var sun_angle: float = TimeManager.get_sun_angle()
	var shadow_dir: Vector2 = Vector2(cos(sun_angle + PI), sin(sun_angle + PI))
	var all_edges: Array[Vector2i] = []
	var source_chunks: Array[Vector2i] = [coord]
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		source_chunks.append(_offset_chunk_coord(coord, dir))
	for source_coord: Vector2i in source_chunks:
		var source_edges: Array = _edge_cache.get(source_coord, []) as Array
		for edge_variant: Variant in source_edges:
			all_edges.append(edge_variant as Vector2i)
	if all_edges.is_empty():
		WorldPerfProbe.end("Shadow.request %s" % [coord], request_usec)
		return {}
	var shadow_points: Array[Vector2i] = _bresenham(
		0,
		0,
		roundi(shadow_dir.x * float(shadow_length)),
		roundi(shadow_dir.y * float(shadow_length))
	)
	if shadow_points.is_empty():
		WorldPerfProbe.end("Shadow.request %s" % [coord], request_usec)
		return {}
	var version: int = _ensure_chunk_version(_shadow_build_versions, coord)
	var request: Dictionary = {
		"coord": coord,
		"version": version,
		"chunk_size": chunk_size,
		"tile_size": balance.tile_size,
		"base_x": WorldGenerator.chunk_to_tile_origin(coord).x,
		"base_y": coord.y * chunk_size,
		"shadow_color": balance.shadow_color,
		"max_intensity": balance.shadow_intensity,
		"terrain_bytes": chunk.get_terrain_bytes().duplicate(),
		"edges": all_edges.duplicate(),
		"shadow_points": shadow_points.duplicate(),
	}
	WorldPerfProbe.end("Shadow.request %s" % [coord], request_usec)
	return request

func _run_shadow_request_blocking(request: Dictionary) -> Dictionary:
	var coord: Vector2i = request.get("coord", INVALID_COORD)
	var version: int = int(request.get("version", -1))
	var task_key: String = _make_worker_task_key("shadow_sync", coord, version)
	var kernels: RefCounted = _create_shadow_kernels()
	if kernels == null:
		return {}
	var task_id: int = WorkerThreadPool.add_task(_worker_build_shadow.bind(task_key, request, kernels))
	WorkerThreadPool.wait_for_task_completion(task_id)
	return _take_shadow_worker_result(task_key)

func _worker_build_shadow(task_key: String, request: Dictionary, kernels: RefCounted = null) -> void:
	var result: Dictionary = _compute_shadow_request(request, kernels)
	_shadow_compute_mutex.lock()
	_shadow_compute_results[task_key] = result
	_shadow_compute_mutex.unlock()

func _compute_shadow_request(request: Dictionary, kernels: RefCounted = null) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var coord: Vector2i = request.get("coord", INVALID_COORD)
	var version: int = int(request.get("version", -1))
	var chunk_size: int = int(request.get("chunk_size", 0))
	var base_x: int = int(request.get("base_x", 0))
	var base_y: int = int(request.get("base_y", 0))
	var shadow_color: Color = request.get("shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	var max_intensity: float = float(request.get("max_intensity", 0.0))
	var terrain_bytes: PackedByteArray = request.get("terrain_bytes", PackedByteArray())
	var edges: Array = request.get("edges", []) as Array
	var shadow_points: Array = request.get("shadow_points", []) as Array
	if kernels == null:
		return {}
	var native_result_variant: Variant = kernels.call(
		"rasterize_shadow_image",
		chunk_size,
		base_x,
		base_y,
		shadow_color,
		max_intensity,
		terrain_bytes,
		edges,
		shadow_points
	)
	if typeof(native_result_variant) != TYPE_DICTIONARY:
		return {}
	var native_result: Dictionary = native_result_variant as Dictionary
	return {
		"coord": coord,
		"version": version,
		"img": native_result.get("img"),
		"has_pixels": bool(native_result.get("has_pixels", false)),
		"compute_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}

func _take_shadow_worker_result(task_key: String) -> Dictionary:
	_shadow_compute_mutex.lock()
	var result: Dictionary = _shadow_compute_results.get(task_key, {}) as Dictionary
	_shadow_compute_results.erase(task_key)
	_shadow_compute_mutex.unlock()
	return result

func _is_external_edge(chunk: Chunk, local: Vector2i, chunk_size: int) -> bool:
	return _is_external_edge_at(chunk.chunk_coord, chunk.get_terrain_bytes(), local.x, local.y, chunk_size)

func _is_external_edge_at(
	chunk_coord: Vector2i,
	terrain_bytes: PackedByteArray,
	local_x: int,
	local_y: int,
	chunk_size: int
) -> bool:
	var global_tile: Vector2i = WorldGenerator.chunk_local_to_tile(chunk_coord, Vector2i(local_x, local_y))
	for dir: Vector2i in EDGE_NEIGHBOR_OFFSETS:
		var neighbor_x: int = local_x + dir.x
		var neighbor_y: int = local_y + dir.y
		var terrain: int = TileGenData.TerrainType.ROCK
		if neighbor_x >= 0 and neighbor_y >= 0 and neighbor_x < chunk_size and neighbor_y < chunk_size:
			terrain = terrain_bytes[neighbor_y * chunk_size + neighbor_x]
		elif _chunk_manager:
			terrain = _chunk_manager.get_terrain_type_at_global(WorldGenerator.offset_tile(global_tile, dir))
		if _is_shadow_open_terrain(terrain):
			return true
	return false

func _is_shadow_open_terrain(terrain: int) -> bool:
	return _is_shadow_open_terrain_value(terrain)

static func _is_shadow_open_terrain_value(terrain: int) -> bool:
	return terrain == TileGenData.TerrainType.GROUND \
		or terrain == TileGenData.TerrainType.WATER \
		or terrain == TileGenData.TerrainType.SAND \
		or terrain == TileGenData.TerrainType.GRASS

func _remove_shadow(coord: Vector2i) -> void:
	if _shadow_sprites.has(coord):
		(_shadow_sprites[coord] as Sprite2D).queue_free()
		_shadow_sprites.erase(coord)

func _suspend_surface_shadow_runtime(hide_container: bool) -> void:
	_dirty_queue.clear()
	_edge_build_queue.clear()
	_pending_mined_tile_updates.clear()
	_pending_mined_tile_update_lookup.clear()
	if not _active_edge_cache_build.is_empty():
		_active_edge_cache_build["cancelled"] = true
	if not _active_build.is_empty():
		var phase: String = str(_active_build.get("phase", "compute"))
		if phase == "compute":
			_active_build["cancelled"] = true
		else:
			_active_build.clear()
	_prefer_shadow_step = true
	if hide_container and _shadow_container:
		_shadow_container.visible = false
	_refresh_boot_shadow_completion_state()

func _tick_suspended_shadow_runtime() -> void:
	_drain_retired_shadow_builds()
	if _shadow_container:
		_shadow_container.visible = false
	if not _active_build.is_empty():
		var phase: String = str(_active_build.get("phase", "compute"))
		if phase == "compute":
			_advance_shadow_build()
		else:
			_active_build.clear()
	if not _active_edge_cache_build.is_empty():
		_advance_edge_cache_build()

func _show_shadow_container() -> void:
	if _shadow_container:
		_shadow_container.visible = _is_surface_context()

func _seed_current_sun_angle() -> void:
	if TimeManager:
		_last_built_angle = TimeManager.get_sun_angle()

func _mark_boot_shadow_work_started() -> void:
	_boot_shadow_work_started = true
	_boot_shadow_work_drained = false
	_boot_shadow_completion_emitted = false

func _has_shadow_work_pending() -> bool:
	return not _dirty_queue.is_empty() \
		or not _edge_build_queue.is_empty() \
		or not _active_edge_cache_build.is_empty() \
		or not _active_build.is_empty()

func _refresh_boot_shadow_completion_state() -> void:
	if not _boot_shadow_work_started:
		return
	var drained: bool = _is_surface_context() and not _has_shadow_work_pending()
	if not drained:
		_boot_shadow_work_drained = false
		_boot_shadow_completion_emitted = false
		return
	if not _boot_shadow_work_drained:
		_boot_shadow_work_drained = true
		if not _boot_shadow_completion_emitted:
			_boot_shadow_completion_emitted = true
			boot_shadow_work_drained.emit()

func is_boot_shadow_work_drained() -> bool:
	return _boot_shadow_work_started and _boot_shadow_work_drained

func _report_boot_shadow_progress(progress_callback: Callable, completed_steps: int, total_steps: int) -> void:
	if not progress_callback.is_valid():
		return
	var progress: float = 96.0 + (float(completed_steps) / float(total_steps)) * 3.0
	progress_callback.call(progress, Localization.t("UI_LOADING_BUILDING_MOUNTAINS"))

func _bresenham(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	var cx: int = x0
	var cy: int = y0
	while true:
		if cx != x0 or cy != y0:
			result.append(Vector2i(cx, cy))
		if cx == x1 and cy == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
	return result

func _shadow_inputs_ready(coord: Vector2i) -> bool:
	if not _chunk_manager:
		return false
	var active_edge_coord: Vector2i = _active_edge_cache_build.get("coord", INVALID_COORD)
	var active_edge_cancelled: bool = bool(_active_edge_cache_build.get("cancelled", false))
	var source_chunks: Array[Vector2i] = [coord]
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		source_chunks.append(_offset_chunk_coord(coord, dir))
	for source_coord: Vector2i in source_chunks:
		var source_chunk: Chunk = _chunk_manager.get_chunk(source_coord)
		if not source_chunk or not source_chunk.has_any_mountain():
			continue
		var current_version: int = int(_edge_cache_versions.get(source_coord, -1))
		var ready_version: int = int(_edge_cache_ready_versions.get(source_coord, -1))
		var has_ready_cache: bool = _edge_cache.has(source_coord) \
			and current_version >= 0 \
			and ready_version == current_version
		if has_ready_cache:
			continue
		if active_edge_coord == source_coord and not active_edge_cancelled:
			return false
		if source_coord in _edge_build_queue:
			return false
		_enqueue_edge_cache_build(source_coord)
		return false
	return true

func _requeue_dirty_coord(coord: Vector2i) -> void:
	if coord not in _dirty_queue:
		_dirty_queue.append(coord)

func _bump_chunk_version(store: Dictionary, coord: Vector2i) -> int:
	var next_version: int = int(store.get(coord, 0)) + 1
	store[coord] = next_version
	return next_version

func _ensure_chunk_version(store: Dictionary, coord: Vector2i) -> int:
	if not store.has(coord):
		store[coord] = 1
	return int(store.get(coord, 1))

func _make_worker_task_key(prefix: String, coord: Vector2i, version: int) -> String:
	_worker_task_serial += 1
	return "%s:%d:%d:v%d:%d" % [prefix, coord.x, coord.y, version, _worker_task_serial]

func _cache_native_shadow_kernels_support() -> void:
	if _native_shadow_kernels_checked:
		return
	_native_shadow_kernels_checked = true
	_native_shadow_kernels_available = ClassDB.class_exists(NATIVE_SHADOW_KERNELS_CLASS) \
		and ClassDB.can_instantiate(NATIVE_SHADOW_KERNELS_CLASS)
	if _native_shadow_kernels_available:
		WorldPerfProbe.mark("Shadow.native_kernels_available")
	else:
		WorldPerfProbe.mark("Shadow.native_kernels_unavailable")
	print("[Shadow] MountainShadowKernels available=%s" % [str(_native_shadow_kernels_available)])

func _create_shadow_kernels() -> RefCounted:
	_cache_native_shadow_kernels_support()
	if not _native_shadow_kernels_available:
		_report_native_shadow_kernel_failure(&"class_unavailable")
		return null
	var instance: Object = ClassDB.instantiate(NATIVE_SHADOW_KERNELS_CLASS)
	if instance == null:
		_report_native_shadow_kernel_failure(&"instantiate_failed")
		return null
	if not instance.has_method("compute_edge_cache") or not instance.has_method("rasterize_shadow_image"):
		_report_native_shadow_kernel_failure(&"missing_required_methods")
		return null
	var kernels: RefCounted = instance as RefCounted
	if kernels == null:
		_report_native_shadow_kernel_failure(&"not_ref_counted")
		return null
	return kernels

func _report_native_shadow_kernel_failure(reason: StringName) -> void:
	if _native_shadow_kernel_error_emitted:
		return
	_native_shadow_kernel_error_emitted = true
	WorldPerfProbe.mark("Shadow.native_kernels_required_missing.%s" % [String(reason)])
	push_error("[Shadow] MountainShadowKernels required; GDScript shadow compute is not allowed (%s)." % [String(reason)])

func _warn_if_sync_boot_shadow_after_handoff(api_name: StringName) -> void:
	if _sync_boot_shadow_runtime_warning_emitted:
		return
	if not WorldPerfProbe.has_milestone("Boot.first_playable"):
		return
	_sync_boot_shadow_runtime_warning_emitted = true
	WorldPerfProbe.mark("Shadow.sync_boot_after_first_playable")
	push_warning("[Shadow] synchronous %s() called after Boot.first_playable; use budgeted schedule_boot_shadows() outside boot." % [String(api_name)])

func _wait_for_active_compute_tasks() -> void:
	if not _active_edge_cache_build.is_empty():
		var edge_task_id: int = int(_active_edge_cache_build.get("task_id", -1))
		if edge_task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(edge_task_id)
		_active_edge_cache_build.clear()
	if not _active_build.is_empty():
		var phase: String = str(_active_build.get("phase", "compute"))
		if phase == "compute":
			var shadow_task_id: int = int(_active_build.get("task_id", -1))
			if shadow_task_id >= 0:
				WorkerThreadPool.wait_for_task_completion(shadow_task_id)
		_active_build.clear()
	_drain_retired_shadow_builds(true)
	_edge_cache_compute_mutex.lock()
	_edge_cache_compute_results.clear()
	_edge_cache_compute_mutex.unlock()
	_shadow_compute_mutex.lock()
	_shadow_compute_results.clear()
	_shadow_compute_mutex.unlock()

func _resolve_shadow_edge_cache_tile_budget() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.mountain_shadow_edge_cache_tiles_per_step)
	return 128

func _resolve_shadow_edges_per_step() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.mountain_shadow_edges_per_step)
	return 4

func _is_surface_context() -> bool:
	return _current_z == 0

func _resolve_current_z() -> int:
	var z_managers: Array[Node] = get_tree().get_nodes_in_group("z_level_manager")
	if z_managers.is_empty():
		return 0
	var z_manager: Node = z_managers[0]
	if z_manager.has_method("get_current_z"):
		return int(z_manager.get_current_z())
	return 0
