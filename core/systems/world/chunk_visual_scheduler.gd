class_name ChunkVisualScheduler
extends RefCounted

const BAND_TERRAIN_FAST: int = 0
const BAND_TERRAIN_URGENT: int = 1
const BAND_TERRAIN_NEAR: int = 2
const BAND_FULL_NEAR: int = 3
const BAND_BORDER_FIX_NEAR: int = 4
const BAND_BORDER_FIX_FAR: int = 5
const BAND_FULL_FAR: int = 6

var _owner: Node = null
var _hot_path_debug_system = null
var _hot_path_forensics_enabled: bool = false

var q_terrain_fast: Array[Dictionary] = []
var q_terrain_urgent: Array[Dictionary] = []
var q_terrain_near: Array[Dictionary] = []
var q_full_near: Array[Dictionary] = []
var q_border_fix_near: Array[Dictionary] = []
var q_border_fix_far: Array[Dictionary] = []
var q_full_far: Array[Dictionary] = []
var q_cosmetic: Array[Dictionary] = []
var task_versions: Dictionary = {}
var task_pending: Dictionary = {}
var task_enqueued_usec: Dictionary = {}
var apply_started_usec: Dictionary = {}
var convergence_started_usec: Dictionary = {}
var first_pass_ready_usec: Dictionary = {}
var full_ready_usec: Dictionary = {}
var apply_feedback: Dictionary = {}
var chunks_processed_this_tick: Dictionary = {}
var chunks_processed_frame: int = -1
var compute_active: Dictionary = {}  ## Vector4i task_key -> int task_id
var compute_waiting_tasks: Dictionary = {}  ## Vector4i task_key -> queued task payload
var compute_results: Dictionary = {}  ## Vector4i task_key -> prepared batch
var compute_mutex: Mutex = Mutex.new()
var budget_exhausted_count: int = 0
var visual_task_slice_count: int = 0
var visual_task_requeue_count: int = 0
var visual_task_requeue_due_budget_count: int = 0
var duplicate_requeue_rejected_count: int = 0
var max_single_task_apply_ms: float = 0.0
var starvation_incident_count: int = 0
var max_urgent_wait_ms: float = 0.0
var log_ticks: int = 0

func setup(owner: Node) -> void:
	_owner = owner
	_hot_path_debug_system = owner._chunk_debug_system if owner != null else null
	_hot_path_forensics_enabled = _hot_path_debug_system != null \
		and _hot_path_debug_system.is_hot_path_forensics_enabled()

func clear_runtime_state() -> void:
	for task_variant: Variant in compute_active.values():
		WorkerThreadPool.wait_for_task_completion(int(task_variant))
	q_terrain_fast.clear()
	q_terrain_urgent.clear()
	q_terrain_near.clear()
	q_full_near.clear()
	q_border_fix_near.clear()
	q_border_fix_far.clear()
	q_full_far.clear()
	q_cosmetic.clear()
	task_versions.clear()
	task_pending.clear()
	task_enqueued_usec.clear()
	apply_started_usec.clear()
	convergence_started_usec.clear()
	first_pass_ready_usec.clear()
	full_ready_usec.clear()
	compute_active.clear()
	compute_waiting_tasks.clear()
	compute_mutex.lock()
	compute_results.clear()
	compute_mutex.unlock()
	_reset_telemetry()

func begin_step() -> void:
	var frame_index: int = Engine.get_process_frames()
	if chunks_processed_frame != frame_index:
		chunks_processed_this_tick.clear()
		chunks_processed_frame = frame_index

func queue_depth() -> int:
	return q_terrain_fast.size() \
		+ q_terrain_urgent.size() \
		+ q_terrain_near.size() \
		+ q_full_near.size() \
		+ q_border_fix_near.size() \
		+ q_border_fix_far.size() \
		+ q_full_far.size() \
		+ q_cosmetic.size() \
		+ compute_active.size() \
		+ compute_waiting_tasks.size()

func queue_for_band(band: int) -> Array[Dictionary]:
	match band:
		BAND_TERRAIN_FAST:
			return q_terrain_fast
		BAND_TERRAIN_URGENT:
			return q_terrain_urgent
		BAND_TERRAIN_NEAR:
			return q_terrain_near
		BAND_FULL_NEAR:
			return q_full_near
		BAND_BORDER_FIX_NEAR:
			return q_border_fix_near
		BAND_BORDER_FIX_FAR:
			return q_border_fix_far
		BAND_FULL_FAR:
			return q_full_far
		_:
			return q_cosmetic

func ordered_queues() -> Array[Array]:
	return [
		q_terrain_fast,
		q_terrain_urgent,
		q_border_fix_near,
		q_terrain_near,
		q_full_near,
		q_border_fix_far,
		q_full_far,
		q_cosmetic,
	]

func has_pending_tasks() -> bool:
	return not q_terrain_fast.is_empty() \
		or not q_terrain_urgent.is_empty() \
		or not q_terrain_near.is_empty() \
		or not q_full_near.is_empty() \
		or not q_border_fix_near.is_empty() \
		or not q_border_fix_far.is_empty() \
		or not q_full_far.is_empty() \
		or not q_cosmetic.is_empty() \
		or not compute_active.is_empty() \
		or not compute_waiting_tasks.is_empty()

func tick_budget(max_usec: int) -> bool:
	if _owner == null:
		return false
	return _run(max_usec, false)

func tick_once(resolved_budget_usec: int) -> bool:
	if _owner == null:
		return false
	return _run(resolved_budget_usec, true)

func reset_runtime_telemetry() -> void:
	var now_usec: int = Time.get_ticks_usec()
	for task_key: Variant in task_pending.keys():
		task_enqueued_usec[task_key] = now_usec
	_reset_telemetry()

func resolve_scheduler_budget_ms() -> float:
	var budget_ms: float = 4.0
	if WorldGenerator and WorldGenerator.balance:
		budget_ms = WorldGenerator.balance.visual_scheduler_budget_ms
	return budget_ms

func mark_apply_started(coord: Vector2i, z_level: int) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	if not apply_started_usec.has(chunk_key):
		apply_started_usec[chunk_key] = Time.get_ticks_usec()
	mark_convergence_started(coord, z_level)

func mark_convergence_started(coord: Vector2i, z_level: int, force_reset: bool = false) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	if not force_reset and convergence_started_usec.has(chunk_key):
		return
	convergence_started_usec[chunk_key] = Time.get_ticks_usec()

func mark_first_pass_ready(coord: Vector2i, z_level: int) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	if first_pass_ready_usec.has(chunk_key):
		return
	var now_usec: int = Time.get_ticks_usec()
	first_pass_ready_usec[chunk_key] = now_usec
	if apply_started_usec.has(chunk_key):
		var latency_ms: float = float(now_usec - int(apply_started_usec[chunk_key])) / 1000.0
		WorldPerfProbe.record("stream.chunk_first_pass_ms %s@z%d" % [coord, z_level], latency_ms)

func mark_full_ready(coord: Vector2i, z_level: int) -> void:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	if full_ready_usec.has(chunk_key):
		return
	var now_usec: int = Time.get_ticks_usec()
	full_ready_usec[chunk_key] = now_usec
	if convergence_started_usec.has(chunk_key):
		var convergence_latency_ms: float = float(now_usec - int(convergence_started_usec[chunk_key])) / 1000.0
		WorldPerfProbe.record("stream.chunk_full_redraw_ms %s@z%d" % [coord, z_level], convergence_latency_ms)
	elif apply_started_usec.has(chunk_key):
		var apply_latency_ms: float = float(now_usec - int(apply_started_usec[chunk_key])) / 1000.0
		WorldPerfProbe.record("stream.chunk_full_redraw_ms %s@z%d" % [coord, z_level], apply_latency_ms)

func clear_full_ready(coord: Vector2i, z_level: int) -> void:
	full_ready_usec.erase(_make_visual_chunk_key(coord, z_level))

func ensure_task(chunk: Chunk, z_level: int, kind: int, invalidate: bool = false) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	var key: Vector4i = _make_visual_task_key(chunk.chunk_coord, z_level, kind)
	if task_pending.has(key) and not invalidate:
		return
	var version: int = int(task_versions.get(key, 0)) + 1
	task_versions[key] = version
	task_pending[key] = version
	task_enqueued_usec[key] = Time.get_ticks_usec()
	var task: Dictionary = _owner._build_visual_task(chunk.chunk_coord, z_level, kind, version)
	_owner._debug_upsert_visual_task_meta(task)
	if push_task(task):
		_owner._debug_note_visual_task_event(
			task,
			"visual_task_enqueued",
			{
				"reason_human": _owner._debug_visual_reason_human(
					kind,
					int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))
				),
			}
		)

func retag_task(task: Dictionary) -> void:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	var old_band: int = int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))
	var new_band: int = _owner._resolve_visual_band(coord, z_level, kind)
	task["priority_band"] = new_band
	task["camera_score"] = float(_owner._chunk_chebyshev_distance(coord, _owner._player_chunk))
	task["movement_score"] = float(_owner._player_chunk_motion.length_squared())
	if (new_band == _owner.VisualPriorityBand.TERRAIN_FAST or new_band == _owner.VisualPriorityBand.TERRAIN_URGENT) \
		and old_band != new_band:
		var key: Vector4i = _make_visual_task_key(coord, z_level, kind)
		task_enqueued_usec[key] = Time.get_ticks_usec()
		task["wait_recorded"] = false
	var task_key: Vector4i = _make_visual_task_key(coord, z_level, kind)
	_owner._debug_update_visual_task_meta_band(task_key, new_band)

func push_task(task: Dictionary) -> bool:
	if not _try_accept_live_task(task, "queue_back"):
		return false
	var band: int = int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	if band == _owner.VisualPriorityBand.TERRAIN_URGENT \
		and kind == _owner.VisualTaskKind.TASK_FIRST_PASS \
		and q_terrain_urgent.size() >= _resolve_visual_urgent_queue_cap():
		band = _owner.VisualPriorityBand.TERRAIN_NEAR
		task["priority_band"] = band
		var task_key: Vector4i = _make_visual_task_key(
			task.get("chunk_coord", Vector2i.ZERO) as Vector2i,
			int(task.get("z", _active_z())),
			kind
		)
		_owner._debug_update_visual_task_meta_band(task_key, band)
	var queue: Array[Dictionary] = queue_for_band(band)
	queue.append(task)
	if kind == _owner.VisualTaskKind.TASK_FIRST_PASS:
		_enforce_visual_urgent_queue_cap()
	return true

func push_task_front(task: Dictionary) -> bool:
	if not _try_accept_live_task(task, "queue_front"):
		return false
	var band: int = int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))
	var queue: Array[Dictionary] = queue_for_band(band)
	queue.insert(0, task)
	return true

func promote_existing_task_to_front(coord: Vector2i, z_level: int, kind: int) -> bool:
	var task_key: Vector4i = _make_visual_task_key(coord, z_level, kind)
	for queue: Array[Dictionary] in ordered_queues():
		for index: int in range(queue.size()):
			var queued_task: Dictionary = queue[index]
			var queued_coord: Vector2i = queued_task.get("chunk_coord", Vector2i.ZERO) as Vector2i
			var queued_z: int = int(queued_task.get("z", _active_z()))
			var queued_kind: int = int(queued_task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
			if _make_visual_task_key(queued_coord, queued_z, queued_kind) != task_key:
				continue
			var promoted_task: Dictionary = queue[index]
			queue.remove_at(index)
			retag_task(promoted_task)
			push_task_front(promoted_task)
			return true
	return false

func refresh_task_priorities() -> void:
	var all_tasks: Array[Dictionary] = []
	for queue: Array[Dictionary] in ordered_queues():
		while not queue.is_empty():
			var task: Dictionary = queue.pop_front()
			retag_task(task)
			all_tasks.append(task)
	for task: Dictionary in all_tasks:
		push_task(task)

func clear_task(task: Dictionary) -> void:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	var key: Vector4i = _make_visual_task_key(coord, z_level, kind)
	_owner._debug_note_visual_task_event(task, "visual_task_cleared")
	task_pending.erase(key)
	task_enqueued_usec.erase(key)
	_owner._debug_drop_visual_task_meta(task)

func _try_accept_live_task(task: Dictionary, route: String) -> bool:
	if _has_duplicate_live_task(task):
		_record_duplicate_requeue_rejected(task, route)
		return false
	return true

func _has_duplicate_live_task(task: Dictionary) -> bool:
	var task_key: Vector4i = _task_key_from_payload(task)
	var version: int = int(task.get("invalidation_version", -1))
	if version < 0:
		return false
	for queue: Array[Dictionary] in ordered_queues():
		for queued_task: Dictionary in queue:
			if _task_payload_matches_key_version(queued_task, task_key, version):
				return true
	var waiting_task: Dictionary = compute_waiting_tasks.get(task_key, {}) as Dictionary
	if not waiting_task.is_empty():
		return _task_payload_matches_key_version(waiting_task, task_key, version)
	return compute_active.has(task_key) and int(task_pending.get(task_key, -1)) == version

func _append_existing_task_to_queue(queue: Array[Dictionary], task: Dictionary, route: String) -> bool:
	if not _try_accept_live_task(task, route):
		return false
	queue.append(task)
	return true

func _task_key_from_payload(task: Dictionary) -> Vector4i:
	return _make_visual_task_key(
		task.get("chunk_coord", Vector2i.ZERO) as Vector2i,
		int(task.get("z", _active_z())),
		int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	)

func _task_payload_matches_key_version(task: Dictionary, task_key: Vector4i, version: int) -> bool:
	return _task_key_from_payload(task) == task_key \
		and int(task.get("invalidation_version", -1)) == version

func _record_duplicate_requeue_rejected(task: Dictionary, route: String) -> void:
	duplicate_requeue_rejected_count += 1
	WorldPerfProbe.record_counter("scheduler.duplicate_requeue_rejected_total", 1.0)
	_owner._debug_note_visual_task_event(
		task,
		"visual_task_duplicate_requeue_rejected",
		{
			"route": route,
			"version": int(task.get("invalidation_version", -1)),
		},
		"duplicate_live_task",
		"dedup_rejected"
	)

func process_border_fix_task(chunk: Chunk, _tile_budget: int, _deadline_usec: int) -> bool:
	if chunk == null or not is_instance_valid(chunk) or not chunk.has_pending_border_dirty():
		return false
	WorldPerfProbe.record("scheduler.border_fix_sync_apply_blocked_count", 1.0)
	return chunk.has_pending_border_dirty()

func is_far_visual_band(band: int) -> bool:
	return band == _owner.VisualPriorityBand.FULL_FAR \
		or band == _owner.VisualPriorityBand.BORDER_FIX_FAR \
		or band == _owner.VisualPriorityBand.COSMETIC

func process_one_task(deadline_usec: int, processed_by_kind: Dictionary) -> int:
	if _owner == null:
		return -1
	begin_step()
	return _process_one_task(deadline_usec, processed_by_kind)

func _active_z() -> int:
	return _owner.get_active_z_level()

func _player_chunk_coord() -> Vector2i:
	return _owner._get_player_chunk_coord()

func _get_visual_task_chunk(task: Dictionary) -> Chunk:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z()))
	var loaded_for_z: Dictionary = _owner._z_chunks.get(z_level, {})
	return loaded_for_z.get(coord) as Chunk

func _make_visual_chunk_key(coord: Vector2i, z_level: int) -> String:
	return _owner._make_visual_chunk_key(coord, z_level)

func _make_visual_task_key(coord: Vector2i, z_level: int, kind: int) -> Vector4i:
	return _owner._make_visual_task_key(coord, z_level, kind)

func _resolve_visual_scheduler_budget_usec(max_usec: int) -> int:
	var budget_usec: int = maxi(0, max_usec)
	if budget_usec <= 0:
		budget_usec = int(resolve_scheduler_budget_ms() * 1000.0)
	return budget_usec

func _resolve_visual_target_apply_ms(kind: int, band: int, scheduler_budget_ms: float) -> float:
	var share: float = 0.15
	match band:
		_owner.VisualPriorityBand.TERRAIN_FAST:
			share = 0.35
		_owner.VisualPriorityBand.TERRAIN_URGENT:
			share = 0.30
		_owner.VisualPriorityBand.TERRAIN_NEAR, _owner.VisualPriorityBand.FULL_NEAR, _owner.VisualPriorityBand.BORDER_FIX_NEAR:
			share = 0.25
		_owner.VisualPriorityBand.FULL_FAR, _owner.VisualPriorityBand.BORDER_FIX_FAR:
			share = 0.18
		_:
			share = 0.15
	if kind == _owner.VisualTaskKind.TASK_BORDER_FIX:
		share *= 0.8
	return clampf(
		scheduler_budget_ms * share,
		_owner.VISUAL_ADAPTIVE_APPLY_MIN_MS,
		_owner.VISUAL_ADAPTIVE_APPLY_MAX_MS
	)

func _make_visual_apply_feedback_key(kind: int, band: int, phase_name: StringName) -> String:
	return "%d:%d:%s" % [kind, band, String(phase_name)]

func _resolve_visual_apply_safety_factor(kind: int, band: int) -> float:
	match band:
		_owner.VisualPriorityBand.TERRAIN_FAST:
			return _owner.VISUAL_ADAPTIVE_FAST_SAFETY
		_owner.VisualPriorityBand.TERRAIN_URGENT:
			return _owner.VISUAL_ADAPTIVE_URGENT_SAFETY
		_owner.VisualPriorityBand.TERRAIN_NEAR, _owner.VisualPriorityBand.FULL_NEAR, _owner.VisualPriorityBand.BORDER_FIX_NEAR:
			return _owner.VISUAL_ADAPTIVE_NEAR_SAFETY
		_owner.VisualPriorityBand.FULL_FAR, _owner.VisualPriorityBand.BORDER_FIX_FAR:
			return _owner.VISUAL_ADAPTIVE_FAR_SAFETY
		_:
			return _owner.VISUAL_ADAPTIVE_NEAR_SAFETY if kind == _owner.VisualTaskKind.TASK_FIRST_PASS else _owner.VISUAL_ADAPTIVE_FAR_SAFETY

func _resolve_visual_bootstrap_tile_budget(kind: int, phase_name: StringName, max_tiles: int) -> int:
	if kind == _owner.VisualTaskKind.TASK_BORDER_FIX:
		return mini(max_tiles, _owner.VISUAL_BOOTSTRAP_BORDER_TILES)
	if kind != _owner.VisualTaskKind.TASK_FULL_REDRAW:
		return max_tiles
	match phase_name:
		&"terrain":
			return mini(max_tiles, _owner.VISUAL_BOOTSTRAP_FULL_TERRAIN_TILES)
		&"cover":
			return mini(max_tiles, _owner.VISUAL_BOOTSTRAP_FULL_COVER_TILES)
		&"cliff":
			return mini(max_tiles, _owner.VISUAL_BOOTSTRAP_FULL_CLIFF_TILES)
		_:
			return mini(max_tiles, _owner.VISUAL_BOOTSTRAP_FULL_COVER_TILES)

func _resolve_visual_apply_tile_cap(kind: int, band: int, phase_name: StringName, base_tile_budget: int) -> int:
	if kind != _owner.VisualTaskKind.TASK_FIRST_PASS:
		return maxi(1, base_tile_budget)
	if band == _owner.VisualPriorityBand.TERRAIN_FAST:
		match phase_name:
			&"terrain":
				return mini(base_tile_budget, _owner.VISUAL_FAST_PHASE_TILE_CAP_TERRAIN)
			&"cover":
				return mini(base_tile_budget, _owner.VISUAL_FAST_PHASE_TILE_CAP_COVER)
			&"cliff":
				return mini(base_tile_budget, _owner.VISUAL_FAST_PHASE_TILE_CAP_CLIFF)
			_:
				return mini(base_tile_budget, _owner.VISUAL_FAST_PHASE_TILE_CAP_COVER)
	if band == _owner.VisualPriorityBand.TERRAIN_URGENT:
		match phase_name:
			&"terrain":
				return mini(base_tile_budget, _owner.VISUAL_URGENT_PHASE_TILE_CAP_TERRAIN)
			&"cover":
				return mini(base_tile_budget, _owner.VISUAL_URGENT_PHASE_TILE_CAP_COVER)
			&"cliff":
				return mini(base_tile_budget, _owner.VISUAL_URGENT_PHASE_TILE_CAP_CLIFF)
			_:
				return mini(base_tile_budget, _owner.VISUAL_URGENT_PHASE_TILE_CAP_COVER)
	return maxi(1, base_tile_budget)

func _resolve_visual_apply_tile_budget(
	kind: int,
	band: int,
	phase_name: StringName,
	base_tile_budget: int
) -> int:
	var min_tiles: int = _owner.VISUAL_ADAPTIVE_MIN_BORDER_TILES if kind == _owner.VisualTaskKind.TASK_BORDER_FIX else _owner.VISUAL_ADAPTIVE_MIN_TILES
	var max_tiles: int = maxi(min_tiles, _resolve_visual_apply_tile_cap(kind, band, phase_name, base_tile_budget))
	var feedback_key: String = _make_visual_apply_feedback_key(kind, band, phase_name)
	var feedback: Dictionary = apply_feedback.get(feedback_key, {}) as Dictionary
	if feedback.is_empty():
		return clampi(_resolve_visual_bootstrap_tile_budget(kind, phase_name, max_tiles), min_tiles, max_tiles)
	var ms_per_command: float = float(feedback.get("ms_per_command", 0.0))
	var commands_per_tile: float = float(feedback.get("commands_per_tile", 0.0))
	if ms_per_command <= 0.0 or commands_per_tile <= 0.0:
		return clampi(_resolve_visual_bootstrap_tile_budget(kind, phase_name, max_tiles), min_tiles, max_tiles)
	var scheduler_budget_ms: float = resolve_scheduler_budget_ms()
	var target_apply_ms: float = _resolve_visual_target_apply_ms(kind, band, scheduler_budget_ms)
	var safety_factor: float = _resolve_visual_apply_safety_factor(kind, band)
	var command_budget: int = int(floor(target_apply_ms * safety_factor / ms_per_command))
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

func _resolve_visual_tiles_per_step(kind: int, band: int = BAND_FULL_FAR) -> int:
	if WorldGenerator and WorldGenerator.balance:
		match kind:
			_owner.VisualTaskKind.TASK_FIRST_PASS:
				var first_pass_tiles: int = WorldGenerator.balance.visual_first_pass_tiles_per_step
				if band == _owner.VisualPriorityBand.TERRAIN_FAST:
					var chunk_tiles: int = maxi(1, WorldGenerator.balance.chunk_size_tiles * WorldGenerator.balance.chunk_size_tiles)
					return mini(chunk_tiles, maxi(2048, first_pass_tiles * 16))
				if band == _owner.VisualPriorityBand.TERRAIN_URGENT:
					return maxi(16, first_pass_tiles / 4)
				if band == _owner.VisualPriorityBand.TERRAIN_NEAR:
					return maxi(16, first_pass_tiles / 2)
				return first_pass_tiles
			_owner.VisualTaskKind.TASK_FULL_REDRAW:
				var full_redraw_tiles: int = WorldGenerator.balance.visual_full_redraw_tiles_per_step
				if band == _owner.VisualPriorityBand.FULL_FAR:
					return maxi(16, full_redraw_tiles / 2)
				if band == _owner.VisualPriorityBand.FULL_NEAR:
					return maxi(32, full_redraw_tiles * 2)
				return full_redraw_tiles
			_owner.VisualTaskKind.TASK_BORDER_FIX:
				var border_fix_tiles: int = _resolve_configured_border_fix_tiles_per_step()
				if band == _owner.VisualPriorityBand.BORDER_FIX_FAR:
					return maxi(1, border_fix_tiles / 2)
				return border_fix_tiles
			_:
				return WorldGenerator.balance.visual_cosmetic_tiles_per_step
	return 64

func _resolve_configured_border_fix_tiles_per_step() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.visual_border_fix_tiles_per_step)
	return 1

func _resolve_visual_max_tasks_per_tick(kind: int, band: int) -> int:
	if WorldGenerator and WorldGenerator.balance:
		match kind:
			_owner.VisualTaskKind.TASK_FIRST_PASS:
				var first_pass_max: int = maxi(1, WorldGenerator.balance.visual_first_pass_max_tasks_per_tick)
				if band == _owner.VisualPriorityBand.TERRAIN_FAST:
					return 1
				if band == _owner.VisualPriorityBand.TERRAIN_URGENT:
					return maxi(1, mini(2, first_pass_max))
				return first_pass_max
			_owner.VisualTaskKind.TASK_FULL_REDRAW:
				var full_redraw_max: int = maxi(1, WorldGenerator.balance.visual_full_redraw_max_tasks_per_tick)
				if band == _owner.VisualPriorityBand.FULL_FAR:
					return 1
				return mini(2, full_redraw_max)
			_owner.VisualTaskKind.TASK_BORDER_FIX:
				var border_fix_max: int = maxi(1, WorldGenerator.balance.visual_full_redraw_max_tasks_per_tick)
				if band == _owner.VisualPriorityBand.BORDER_FIX_FAR:
					return 1
				return mini(2, border_fix_max)
			_:
				return 999999
	return 999999

func _resolve_visual_urgent_queue_cap() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.visual_first_pass_max_tasks_per_tick)
	return 4

func _enforce_visual_urgent_queue_cap() -> void:
	while q_terrain_urgent.size() > _resolve_visual_urgent_queue_cap():
		var task: Dictionary = q_terrain_urgent.pop_back()
		task["priority_band"] = _owner.VisualPriorityBand.TERRAIN_NEAR
		_append_existing_task_to_queue(q_terrain_near, task, "urgent_cap_demote")

func _resolve_visual_band_order(band: int) -> int:
	match band:
		_owner.VisualPriorityBand.TERRAIN_FAST:
			return 0
		_owner.VisualPriorityBand.TERRAIN_URGENT:
			return 1
		_owner.VisualPriorityBand.BORDER_FIX_NEAR:
			return 2
		_owner.VisualPriorityBand.TERRAIN_NEAR:
			return 3
		_owner.VisualPriorityBand.FULL_NEAR:
			return 4
		_owner.VisualPriorityBand.BORDER_FIX_FAR:
			return 5
		_owner.VisualPriorityBand.FULL_FAR:
			return 6
		_:
			return 7

func _count_far_active_visual_compute() -> int:
	var active_count: int = 0
	for task_variant: Variant in compute_waiting_tasks.values():
		var task: Dictionary = task_variant as Dictionary
		if is_far_visual_band(int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))):
			active_count += 1
	return active_count

func _can_submit_visual_compute_now(band: int) -> bool:
	if compute_active.size() >= _owner.VISUAL_MAX_CONCURRENT_COMPUTE:
		return false
	if is_far_visual_band(band):
		var far_active_count: int = _count_far_active_visual_compute()
		if far_active_count >= _owner.VISUAL_MAX_FAR_CONCURRENT_COMPUTE:
			return false
	return true

func _is_completed_visual_compute_higher_priority(a: Dictionary, b: Dictionary) -> bool:
	var a_task: Dictionary = a.get("task", {}) as Dictionary
	var b_task: Dictionary = b.get("task", {}) as Dictionary
	var a_band_order: int = _resolve_visual_band_order(int(a_task.get("priority_band", _owner.VisualPriorityBand.COSMETIC)))
	var b_band_order: int = _resolve_visual_band_order(int(b_task.get("priority_band", _owner.VisualPriorityBand.COSMETIC)))
	if a_band_order != b_band_order:
		return a_band_order < b_band_order
	var a_camera_score: float = float(a_task.get("camera_score", 999999.0))
	var b_camera_score: float = float(b_task.get("camera_score", 999999.0))
	if not is_equal_approx(a_camera_score, b_camera_score):
		return a_camera_score < b_camera_score
	var a_key: Vector4i = a.get("key", Vector4i.ZERO) as Vector4i
	var b_key: Vector4i = b.get("key", Vector4i.ZERO) as Vector4i
	var a_enqueued_usec: int = int(task_enqueued_usec.get(a_key, 0))
	var b_enqueued_usec: int = int(task_enqueued_usec.get(b_key, 0))
	if a_enqueued_usec != b_enqueued_usec:
		return a_enqueued_usec < b_enqueued_usec
	return _owner._visual_task_key_less(a_key, b_key)

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
	var previous: Dictionary = apply_feedback.get(feedback_key, {}) as Dictionary
	if previous.is_empty():
		apply_feedback[feedback_key] = {
			"ms_per_command": ms_per_command,
			"commands_per_tile": commands_per_tile,
			"last_apply_ms": apply_ms,
			"last_command_count": command_count,
			"last_tile_count": tile_count,
			"last_budget_ms": scheduler_budget_ms,
			"target_apply_ms": target_apply_ms,
		}
		return
	apply_feedback[feedback_key] = {
		"ms_per_command": lerpf(float(previous.get("ms_per_command", ms_per_command)), ms_per_command, _owner.VISUAL_ADAPTIVE_FEEDBACK_BLEND),
		"commands_per_tile": lerpf(float(previous.get("commands_per_tile", commands_per_tile)), commands_per_tile, _owner.VISUAL_ADAPTIVE_FEEDBACK_BLEND),
		"last_apply_ms": apply_ms,
		"last_command_count": command_count,
		"last_tile_count": tile_count,
		"last_budget_ms": scheduler_budget_ms,
		"target_apply_ms": target_apply_ms,
	}

func _should_prepare_border_fix_inline(_task: Dictionary, _chunk: Chunk, _requested_tile_budget: int) -> bool:
	return false

func _worker_prepare_visual_batch(task_key: Vector4i, request: Dictionary) -> void:
	if _owner._shutdown_in_progress:
		return
	var started_usec: int = Time.get_ticks_usec()
	var batch: Dictionary = Chunk.compute_visual_batch(request)
	if _owner._shutdown_in_progress:
		return
	batch["task_key"] = task_key
	batch["chunk_coord"] = request.get("chunk_coord", Vector2i.ZERO)
	batch["z"] = int(request.get("z", _owner.INVALID_Z_LEVEL))
	batch["invalidation_version"] = int(request.get("invalidation_version", -1))
	batch["tile_count"] = int(request.get("tile_count", batch.get("tile_count", 0)))
	batch["requested_tile_budget"] = int(request.get("requested_tile_budget", 0))
	batch["visual_budget_ms"] = float(request.get("requested_visual_budget_ms", 0.0))
	batch["target_apply_ms"] = float(request.get("requested_target_apply_ms", 0.0))
	batch["prepare_ms"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
	compute_mutex.lock()
	compute_results[task_key] = batch
	compute_mutex.unlock()

func _submit_visual_compute(task: Dictionary, chunk: Chunk, tile_budget: int) -> int:
	if chunk == null or not is_instance_valid(chunk):
		return _owner.VisualComputeSubmitState.UNAVAILABLE
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	var band: int = int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))
	var key: Vector4i = _make_visual_task_key(coord, z_level, kind)
	var request: Dictionary = {}
	var requested_tile_budget: int = maxi(1, tile_budget)
	match kind:
		_owner.VisualTaskKind.TASK_FIRST_PASS, _owner.VisualTaskKind.TASK_FULL_REDRAW:
			if chunk.supports_worker_visual_phase():
				var phase_name: StringName = chunk.get_redraw_phase_name()
				requested_tile_budget = _resolve_visual_apply_tile_budget(kind, band, phase_name, tile_budget)
				request = chunk.build_visual_phase_batch(requested_tile_budget)
		_owner.VisualTaskKind.TASK_BORDER_FIX:
			var dirty_tile_budget: int = mini(
				mini(tile_budget, _owner.BORDER_FIX_REDRAW_MICRO_BATCH_TILES),
				_resolve_configured_border_fix_tiles_per_step()
			)
			requested_tile_budget = _resolve_visual_apply_tile_budget(kind, band, &"dirty", dirty_tile_budget)
			request = chunk.build_visual_dirty_batch_from_tiles(
				chunk.collect_pending_border_dirty_tiles(requested_tile_budget)
			)
		_:
			return _owner.VisualComputeSubmitState.UNAVAILABLE
	if request.is_empty():
		return _owner.VisualComputeSubmitState.UNAVAILABLE
	var requested_visual_budget_ms: float = resolve_scheduler_budget_ms()
	request["tile_count"] = int((request.get("tiles", []) as Array).size())
	request["requested_tile_budget"] = requested_tile_budget
	request["requested_visual_budget_ms"] = requested_visual_budget_ms
	request["requested_target_apply_ms"] = _resolve_visual_target_apply_ms(kind, band, requested_visual_budget_ms)
	var inline_border_fix: bool = _should_prepare_border_fix_inline(task, chunk, requested_tile_budget)
	if compute_active.has(key) or compute_waiting_tasks.has(key):
		return _owner.VisualComputeSubmitState.SUBMITTED
	var can_prepare_immediately: bool = bool(request.get("skip_worker_compute", false)) \
		and int(request.get("phase", ChunkVisualKernel.REDRAW_PHASE_DONE)) == ChunkVisualKernel.REDRAW_PHASE_FLORA
	if inline_border_fix:
		can_prepare_immediately = true
	if can_prepare_immediately:
		var immediate_task: Dictionary = task.duplicate(true)
		var prepared_batch: Dictionary = Chunk.compute_visual_batch(request)
		if prepared_batch.is_empty():
			return _owner.VisualComputeSubmitState.UNAVAILABLE
		prepared_batch["tile_count"] = int(request.get("tile_count", prepared_batch.get("tile_count", 0)))
		prepared_batch["requested_tile_budget"] = requested_tile_budget
		prepared_batch["visual_budget_ms"] = requested_visual_budget_ms
		prepared_batch["target_apply_ms"] = float(request.get("requested_target_apply_ms", 0.0))
		immediate_task["prepared_batch"] = prepared_batch
		immediate_task.erase("force_inline_prepare")
		if inline_border_fix:
			push_task_front(immediate_task)
		else:
			push_task(immediate_task)
		return _owner.VisualComputeSubmitState.SUBMITTED
	if not _can_submit_visual_compute_now(band):
		if kind == _owner.VisualTaskKind.TASK_BORDER_FIX \
			and band == _owner.VisualPriorityBand.BORDER_FIX_NEAR \
			and _owner._is_player_near_visual_chunk(coord, z_level):
			_owner._debug_note_visual_task_event(
				task,
				"visual_task_compute_blocked",
				{},
				"compute_cap",
				"worker_capacity_blocked"
			)
			return _owner.VisualComputeSubmitState.BLOCKED
		_owner._debug_note_visual_task_event(
			task,
			"visual_task_compute_blocked",
			{},
			"compute_cap",
			"worker_capacity"
		)
		return _owner.VisualComputeSubmitState.BLOCKED
	request["chunk_coord"] = coord
	request["z"] = z_level
	request["invalidation_version"] = int(task.get("invalidation_version", -1))
	var task_id: int = WorkerThreadPool.add_task(_worker_prepare_visual_batch.bind(key, request))
	compute_active[key] = task_id
	compute_waiting_tasks[key] = task
	return _owner.VisualComputeSubmitState.SUBMITTED

func _collect_completed_visual_compute(deadline_usec: int) -> void:
	if compute_active.is_empty() or _owner.VISUAL_COMPLETED_COMPUTE_MAX_INTAKE_PER_STEP <= 0:
		return
	var completed_entries: Array[Dictionary] = []
	for key_variant: Variant in compute_active.keys():
		var key: Vector4i = key_variant as Vector4i
		var task_id: int = int(compute_active.get(key, -1))
		if task_id < 0 or not WorkerThreadPool.is_task_completed(task_id):
			continue
		var waiting_task: Dictionary = compute_waiting_tasks.get(key, {}) as Dictionary
		if not waiting_task.is_empty():
			retag_task(waiting_task)
		completed_entries.append({
			"key": key,
			"task_id": task_id,
			"task": waiting_task,
		})
	if completed_entries.is_empty():
		return
	completed_entries.sort_custom(_is_completed_visual_compute_higher_priority)
	var collected_count: int = 0
	for entry: Dictionary in completed_entries:
		if collected_count >= _owner.VISUAL_COMPLETED_COMPUTE_MAX_INTAKE_PER_STEP:
			break
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
			break
		var key: Vector4i = entry.get("key", Vector4i.ZERO) as Vector4i
		var task_id: int = int(entry.get("task_id", -1))
		if task_id < 0:
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		compute_active.erase(key)
		compute_mutex.lock()
		var batch: Dictionary = compute_results.get(key, {}) as Dictionary
		compute_results.erase(key)
		compute_mutex.unlock()
		var waiting_task: Dictionary = compute_waiting_tasks.get(key, {}) as Dictionary
		compute_waiting_tasks.erase(key)
		if batch.is_empty() or waiting_task.is_empty():
			collected_count += 1
			continue
		if int(task_pending.get(key, -1)) != int(batch.get("invalidation_version", -1)):
			collected_count += 1
			continue
		var prepare_ms: float = float(batch.get("prepare_ms", 0.0))
		if prepare_ms >= 2.0:
			WorldPerfProbe.record(
				"ChunkManager.streaming_redraw_prepare_step.%s" % [String(batch.get("phase_name", &"done"))],
				prepare_ms
			)
		waiting_task["prepared_batch"] = batch
		if int(waiting_task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC)) == _owner.VisualTaskKind.TASK_BORDER_FIX \
			and _owner._is_player_near_visual_chunk(
				waiting_task.get("chunk_coord", Vector2i.ZERO) as Vector2i,
				int(waiting_task.get("z", _active_z()))
			):
			push_task_front(waiting_task)
		else:
			push_task(waiting_task)
		collected_count += 1

func _reset_telemetry() -> void:
	budget_exhausted_count = 0
	visual_task_slice_count = 0
	visual_task_requeue_count = 0
	visual_task_requeue_due_budget_count = 0
	duplicate_requeue_rejected_count = 0
	max_single_task_apply_ms = 0.0
	starvation_incident_count = 0
	max_urgent_wait_ms = 0.0
	log_ticks = 0
	apply_feedback.clear()
	chunks_processed_this_tick.clear()
	chunks_processed_frame = -1

func _pop_allowed_task_from_queue(queue: Array[Dictionary], processed_by_kind: Dictionary) -> Dictionary:
	var queue_size: int = queue.size()
	for _i: int in range(queue_size):
		if queue.is_empty():
			break
		var task: Dictionary = queue.pop_front()
		var chunk_key: String = _make_visual_chunk_key(
			task.get("chunk_coord", Vector2i.ZERO) as Vector2i,
			int(task.get("z", _active_z()))
		)
		if chunks_processed_this_tick.has(chunk_key):
			_append_existing_task_to_queue(queue, task, "processed_this_tick_rotation")
			continue
		var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
		var band: int = int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))
		var processed_count: int = int(processed_by_kind.get(kind, 0))
		if processed_count < _resolve_visual_max_tasks_per_tick(kind, band):
			return task
		if _hot_path_forensics_enabled and _hot_path_debug_system != null:
			_hot_path_debug_system.note_visual_task_event(
				task,
				"visual_task_skipped_kind_cap",
				{},
				"kind_cap"
			)
		_append_existing_task_to_queue(queue, task, "kind_cap_rotation")
	return {}

func _pop_next_task(processed_by_kind: Dictionary) -> Dictionary:
	for queue: Array[Dictionary] in ordered_queues():
		var task: Dictionary = _pop_allowed_task_from_queue(queue, processed_by_kind)
		if not task.is_empty():
			return task
	return {}

func _process_one_task(deadline_usec: int, processed_by_kind: Dictionary) -> int:
	var task: Dictionary = _pop_next_task(processed_by_kind)
	if task.is_empty():
		return -1
	if _hot_path_forensics_enabled and _hot_path_debug_system != null:
		_hot_path_debug_system.note_visual_task_event(task, "visual_task_selected")
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	var run_state: int = _process_visual_task(task, deadline_usec)
	if run_state == _owner.VisualTaskRunState.REQUEUE:
		processed_by_kind[kind] = int(processed_by_kind.get(kind, 0)) + 1
		_requeue_visual_task(task)
		return 1
	if run_state == _owner.VisualTaskRunState.COMPLETED:
		processed_by_kind[kind] = int(processed_by_kind.get(kind, 0)) + 1
		return 1
	return 0

func _requeue_visual_task(task: Dictionary) -> void:
	retag_task(task)
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	var accepted: bool = false
	if kind == _owner.VisualTaskKind.TASK_BORDER_FIX:
		accepted = push_task_front(task)
	else:
		accepted = push_task(task)
	if not accepted:
		return
	visual_task_requeue_count += 1
	var requeue_reason: String = String(task.get("last_requeue_reason", "resumable_slice"))
	if requeue_reason == "budget_exhausted":
		visual_task_requeue_due_budget_count += 1
	_owner._debug_note_visual_task_event(
		task,
		"visual_task_requeued",
		{
			"requeue_reason": requeue_reason,
			"phase": String(task.get("phase", &"unknown")),
			"cursor": int(task.get("cursor", -1)),
			"slice_count": int(task.get("slice_count", 0)),
			"last_slice_apply_ms": float(task.get("last_slice_apply_ms", 0.0)),
		}
	)

func _store_resumable_slice_state(
	task: Dictionary,
	chunk: Chunk,
	phase_name: StringName,
	cursor: int,
	tile_count: int,
	apply_ms: float,
	deadline_usec: int
) -> void:
	visual_task_slice_count += 1
	max_single_task_apply_ms = maxf(max_single_task_apply_ms, apply_ms)
	task["phase"] = phase_name
	task["cursor"] = cursor
	task["slice_version"] = int(task.get("invalidation_version", -1))
	task["slice_count"] = int(task.get("slice_count", 0)) + 1
	task["last_slice_tile_count"] = tile_count
	task["last_slice_apply_ms"] = apply_ms
	if chunk != null and is_instance_valid(chunk):
		task["pending_border_dirty_count"] = chunk.get_pending_border_dirty_count()
	if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
		task["last_requeue_reason"] = "budget_exhausted"
	else:
		task["last_requeue_reason"] = "resumable_slice"
	WorldPerfProbe.record("scheduler.visual_task_slice_count", 1.0)
	WorldPerfProbe.record("scheduler.visual_task_slice_ms.%s" % [String(phase_name)], apply_ms)

func _record_visual_task_wait(task: Dictionary) -> void:
	var band: int = int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))
	if band != _owner.VisualPriorityBand.TERRAIN_FAST and band != _owner.VisualPriorityBand.TERRAIN_URGENT:
		return
	if bool(task.get("wait_recorded", false)):
		return
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	var key: Vector4i = _make_visual_task_key(coord, z_level, kind)
	if not task_enqueued_usec.has(key):
		return
	if _owner._is_boot_in_progress:
		task_enqueued_usec[key] = Time.get_ticks_usec()
		return
	var wait_ms: float = float(Time.get_ticks_usec() - int(task_enqueued_usec[key])) / 1000.0
	task["wait_recorded"] = true
	max_urgent_wait_ms = maxf(max_urgent_wait_ms, wait_ms)
	if band == _owner.VisualPriorityBand.TERRAIN_FAST:
		WorldPerfProbe.record("Scheduler.fast_visual_wait_ms", wait_ms)
	WorldPerfProbe.record("Scheduler.urgent_visual_wait_ms", wait_ms)
	WorldPerfProbe.record("scheduler.max_urgent_wait_ms", wait_ms)
	if wait_ms > 100.0:
		starvation_incident_count += 1
		WorldPerfProbe.record("scheduler.starvation_incident_count", 1.0)

func _drop_legacy_visual_fallback_task(task: Dictionary, reason: String) -> int:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	clear_task(task)
	_owner._report_zero_tolerance_contract_breach(
		"legacy_visual_fallback_blocked",
		coord,
		z_level,
		"Заблокировала legacy visual fallback",
		"critical visual task `%s` попытался уйти в запрещённый compatibility/sync fallback (%s)" % [
			_owner._debug_visual_kind_name(kind),
			reason,
		],
		"legacy_visual_fallback",
		{
			"task_kind": _owner._debug_visual_kind_name(kind),
			"priority_band": int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC)),
		}
	)
	return _owner.VisualTaskRunState.DROPPED

func _process_visual_task(task: Dictionary, deadline_usec: int) -> int:
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", _owner.VisualTaskKind.TASK_COSMETIC))
	var key: Vector4i = _make_visual_task_key(coord, z_level, kind)
	if int(task_pending.get(key, -1)) != int(task.get("invalidation_version", -1)):
		return _owner.VisualTaskRunState.DROPPED
	var chunk: Chunk = _get_visual_task_chunk(task)
	if chunk == null or not is_instance_valid(chunk):
		clear_task(task)
		return _owner.VisualTaskRunState.DROPPED
	_record_visual_task_wait(task)
	var band: int = int(task.get("priority_band", _owner.VisualPriorityBand.COSMETIC))
	var prepared_batch: Dictionary = task.get("prepared_batch", {}) as Dictionary
	match kind:
		_owner.VisualTaskKind.TASK_FIRST_PASS:
			if prepared_batch.is_empty():
				var first_pass_submit_state: int = _submit_visual_compute(task, chunk, _resolve_visual_tiles_per_step(kind, band))
				if first_pass_submit_state == _owner.VisualComputeSubmitState.SUBMITTED:
					return _owner.VisualTaskRunState.DROPPED
				if first_pass_submit_state == _owner.VisualComputeSubmitState.BLOCKED:
					return _owner.VisualTaskRunState.REQUEUE
			var first_pass_did_apply: bool = false
			if not prepared_batch.is_empty():
				var apply_started_usec_now: int = Time.get_ticks_usec()
				if not chunk.apply_visual_phase_batch(prepared_batch):
					task.erase("prepared_batch")
					return _owner.VisualTaskRunState.REQUEUE
				first_pass_did_apply = true
				var apply_ms: float = float(Time.get_ticks_usec() - apply_started_usec_now) / 1000.0
				_store_resumable_slice_state(
					task,
					chunk,
					StringName(prepared_batch.get("phase_name", &"done")),
					int(prepared_batch.get("end_index", -1)),
					int(prepared_batch.get("tile_count", 0)),
					apply_ms,
					deadline_usec
				)
				_record_visual_apply_feedback(
					kind,
					band,
					StringName(prepared_batch.get("phase_name", &"done")),
					int(prepared_batch.get("command_count", 0)),
					int(prepared_batch.get("tile_count", 0)),
					apply_ms,
					float(prepared_batch.get("visual_budget_ms", resolve_scheduler_budget_ms()))
				)
				if apply_ms >= 1.0:
					WorldPerfProbe.record(
						"ChunkManager.streaming_redraw_step.%s" % [String(prepared_batch.get("phase_name", &"done"))],
						apply_ms
					)
				_owner._boot_on_chunk_redraw_progress(chunk)
			else:
				return _drop_legacy_visual_fallback_task(task, "first_pass_sync_compat_executor")
			if first_pass_did_apply:
				chunks_processed_this_tick[_make_visual_chunk_key(coord, z_level)] = true
			_owner._sync_chunk_visibility_for_publication(chunk)
			if chunk.is_first_pass_ready():
				mark_first_pass_ready(coord, z_level)
				clear_task(task)
				_owner._ensure_chunk_full_redraw_task(chunk, z_level)
				if chunk.has_pending_border_dirty():
					_owner._ensure_chunk_border_fix_task(chunk, z_level)
				else:
					_owner._try_finalize_chunk_visual_convergence(chunk, z_level)
				return _owner.VisualTaskRunState.COMPLETED
			task.erase("prepared_batch")
			return _owner.VisualTaskRunState.REQUEUE
		_owner.VisualTaskKind.TASK_FULL_REDRAW:
			chunk._mark_visual_full_redraw_pending()
			if prepared_batch.is_empty():
				var full_submit_state: int = _submit_visual_compute(task, chunk, _resolve_visual_tiles_per_step(kind, band))
				if full_submit_state == _owner.VisualComputeSubmitState.SUBMITTED:
					return _owner.VisualTaskRunState.DROPPED
				if full_submit_state == _owner.VisualComputeSubmitState.BLOCKED:
					return _owner.VisualTaskRunState.REQUEUE
			var full_has_more: bool = true
			var full_redraw_did_apply: bool = false
			if not prepared_batch.is_empty():
				var full_apply_started_usec: int = Time.get_ticks_usec()
				if not chunk.apply_visual_phase_batch(prepared_batch):
					task.erase("prepared_batch")
					return _owner.VisualTaskRunState.REQUEUE
				full_redraw_did_apply = true
				var full_apply_ms: float = float(Time.get_ticks_usec() - full_apply_started_usec) / 1000.0
				_store_resumable_slice_state(
					task,
					chunk,
					StringName(prepared_batch.get("phase_name", &"done")),
					int(prepared_batch.get("end_index", -1)),
					int(prepared_batch.get("tile_count", 0)),
					full_apply_ms,
					deadline_usec
				)
				_record_visual_apply_feedback(
					kind,
					band,
					StringName(prepared_batch.get("phase_name", &"done")),
					int(prepared_batch.get("command_count", 0)),
					int(prepared_batch.get("tile_count", 0)),
					full_apply_ms,
					float(prepared_batch.get("visual_budget_ms", resolve_scheduler_budget_ms()))
				)
				if full_apply_ms >= 1.0:
					WorldPerfProbe.record(
						"ChunkManager.streaming_redraw_step.%s" % [String(prepared_batch.get("phase_name", &"done"))],
						full_apply_ms
					)
				full_has_more = not chunk.is_redraw_complete()
			else:
				return _drop_legacy_visual_fallback_task(task, "full_redraw_sync_compat_executor")
			if full_redraw_did_apply:
				chunks_processed_this_tick[_make_visual_chunk_key(coord, z_level)] = true
			_owner._sync_chunk_visibility_for_publication(chunk)
			if not full_has_more or chunk.is_redraw_complete():
				clear_task(task)
				if chunk.has_pending_border_dirty():
					_owner._ensure_chunk_border_fix_task(chunk, z_level)
				else:
					_owner._try_finalize_chunk_visual_convergence(chunk, z_level)
				return _owner.VisualTaskRunState.COMPLETED
			task.erase("prepared_batch")
			return _owner.VisualTaskRunState.REQUEUE
		_owner.VisualTaskKind.TASK_BORDER_FIX:
			if not chunk.has_pending_border_dirty():
				chunk._mark_border_fix_reasons_applied()
				clear_task(task)
				_owner._try_finalize_chunk_visual_convergence(chunk, z_level)
				return _owner.VisualTaskRunState.COMPLETED
			if prepared_batch.is_empty():
				var border_submit_state: int = _submit_visual_compute(task, chunk, _resolve_visual_tiles_per_step(kind, band))
				if border_submit_state == _owner.VisualComputeSubmitState.SUBMITTED:
					return _owner.VisualTaskRunState.DROPPED
				if border_submit_state == _owner.VisualComputeSubmitState.BLOCKED:
					return _owner.VisualTaskRunState.REQUEUE
			var border_has_more: bool = true
			var border_fix_did_apply: bool = false
			if not prepared_batch.is_empty():
				var border_apply_started_usec: int = Time.get_ticks_usec()
				if not chunk.apply_visual_dirty_batch(prepared_batch):
					task.erase("prepared_batch")
					return _owner.VisualTaskRunState.REQUEUE
				border_fix_did_apply = true
				chunk.discard_pending_border_dirty_tiles(prepared_batch.get("tiles", []) as Array)
				var border_apply_ms: float = float(Time.get_ticks_usec() - border_apply_started_usec) / 1000.0
				_store_resumable_slice_state(
					task,
					chunk,
					StringName(prepared_batch.get("phase_name", &"dirty")),
					chunk.get_pending_border_dirty_count(),
					int(prepared_batch.get("tile_count", 0)),
					border_apply_ms,
					deadline_usec
				)
				_record_visual_apply_feedback(
					kind,
					band,
					StringName(prepared_batch.get("phase_name", &"dirty")),
					int(prepared_batch.get("command_count", 0)),
					int(prepared_batch.get("tile_count", 0)),
					border_apply_ms,
					float(prepared_batch.get("visual_budget_ms", resolve_scheduler_budget_ms()))
				)
				if border_apply_ms >= 1.0:
					WorldPerfProbe.record("ChunkManager.streaming_redraw_step.dirty", border_apply_ms)
				border_has_more = chunk.has_pending_border_dirty()
			else:
				return _drop_legacy_visual_fallback_task(task, "border_fix_sync_dirty_executor")
			if border_fix_did_apply:
				chunks_processed_this_tick[_make_visual_chunk_key(coord, z_level)] = true
			if not border_has_more:
				if task_enqueued_usec.has(key):
					var latency_ms: float = float(Time.get_ticks_usec() - int(task_enqueued_usec[key])) / 1000.0
					WorldPerfProbe.record("stream.chunk_border_fix_ms %s@z%d" % [coord, z_level], latency_ms)
				chunk._mark_border_fix_reasons_applied()
				clear_task(task)
				_owner._try_finalize_chunk_visual_convergence(chunk, z_level)
				return _owner.VisualTaskRunState.COMPLETED
			task.erase("prepared_batch")
			return _owner.VisualTaskRunState.REQUEUE
		_:
			clear_task(task)
			return _owner.VisualTaskRunState.DROPPED

func _run(max_usec: int, stop_after_processed_task: bool) -> bool:
	var budget_usec: int = _resolve_visual_scheduler_budget_usec(max_usec)
	begin_step()
	var started_usec: int = Time.get_ticks_usec()
	var deadline_usec: int = started_usec + budget_usec if budget_usec > 0 else 0
	_collect_completed_visual_compute(deadline_usec)
	var processed_by_kind: Dictionary = {}
	var processed_count: int = 0
	var budget_exhausted: bool = false
	while has_pending_tasks():
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
			budget_exhausted = true
			break
		var processed_delta: int = _process_one_task(deadline_usec, processed_by_kind)
		if processed_delta < 0:
			break
		processed_count += processed_delta
		if stop_after_processed_task and processed_delta > 0:
			break
	var used_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	if budget_exhausted:
		budget_exhausted_count += 1
		visual_task_requeue_due_budget_count += 1
		WorldPerfProbe.record("scheduler.visual_budget_exhausted_count", 1.0)
		WorldPerfProbe.record("scheduler.visual_task_requeue_due_budget_count", 1.0)
		_owner._debug_note_budget_exhausted_trace_task()
	_owner._emit_visual_scheduler_tick_log(processed_count, budget_exhausted)
	_owner._maybe_log_player_chunk_visual_status("scheduler", used_ms, budget_exhausted)
	return has_pending_tasks()
