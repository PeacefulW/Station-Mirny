class_name ChunkBootPipeline
extends RefCounted

var _owner: Node = null

var chunk_states: Dictionary = {}
var center: Vector2i = Vector2i.ZERO
var load_radius: int = 0
var first_playable: bool = false
var complete_flag: bool = false
var topology_ready: bool = false
var started_usec: int = 0
var metric_compute_ms: float = 0.0
var metric_apply_ms: float = 0.0
var metric_terrain_redraw_ms: float = 0.0
var metric_chunks_computed: int = 0
var metric_chunks_applied: int = 0
var metric_queue_wait_ms: float = 0.0

var compute_pending: Array[Vector2i] = []
var compute_active: Dictionary = {}
var compute_builders: Dictionary = {}
var compute_results: Dictionary = {}
var compute_mutex: Mutex = Mutex.new()
var compute_z: int = 0
var applied_count: int = 0
var total_count: int = 0
var compute_generation: int = 0
var failed_coords: Array[Vector2i] = []
var runtime_handoff_started: bool = false
var compute_requested_usec: Dictionary = {}
var compute_started_usec: Dictionary = {}

var prepare_queue: Array[Dictionary] = []
var apply_queue: Array[Dictionary] = []
var has_remaining_chunks_flag: bool = false
var pipeline_drained: bool = false

func setup(owner: Node) -> void:
	_owner = owner

func has_remaining_chunks() -> bool:
	return has_remaining_chunks_flag

func is_first_playable() -> bool:
	return first_playable

func is_complete() -> bool:
	return complete_flag

func is_tracking_chunk(coord: Vector2i) -> bool:
	return chunk_states.has(coord)

func get_compute_z() -> int:
	return compute_z

func get_center() -> Vector2i:
	return center

func clear_runtime_state() -> void:
	wait_all_compute()
	cleanup_compute_pipeline()
	chunk_states.clear()
	started_usec = 0
	first_playable = false
	complete_flag = false
	topology_ready = false
	has_remaining_chunks_flag = false
	pipeline_drained = false

func boot_load_initial_chunks(progress_callback: Callable) -> void:
	if not _owner._initialized or not _owner._player:
		return
	var boot_center: Vector2i = WorldGenerator.world_to_chunk(_owner._player.global_position)
	_owner._player_chunk = boot_center
	var boot_load_radius: int = WorldGenerator.balance.load_radius
	init_readiness(boot_center, boot_load_radius)
	var coords: Array[Vector2i] = []
	for dx: int in range(-boot_load_radius, boot_load_radius + 1):
		for dy: int in range(-boot_load_radius, boot_load_radius + 1):
			coords.append(_offset_chunk_coord(boot_center, Vector2i(dx, dy)))
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_priority_less(a, b, boot_center)
	)
	var total: int = coords.size()
	compute_z = _active_z()
	applied_count = 0
	total_count = total
	for coord: Vector2i in coords:
		set_chunk_state(coord, _owner.BootChunkState.QUEUED_COMPUTE)
		var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(compute_z)
		if loaded_chunks_for_z.has(coord):
			var loaded_chunk: Chunk = loaded_chunks_for_z.get(coord) as Chunk
			_sync_chunk_visibility_for_publication(loaded_chunk)
			on_chunk_applied(coord, loaded_chunk)
		else:
			compute_pending.append(coord)
			compute_requested_usec[coord] = Time.get_ticks_usec()
	var loop_iter: int = 0
	while not first_playable:
		var iter_start: int = Time.get_ticks_usec()
		submit_pending_tasks()
		collect_completed()
		drain_computed_to_apply_queue()
		prepare_apply_entries()
		apply_from_queue()
		process_redraw_budget(2500)
		promote_redrawn_chunks()
		if compute_active.is_empty() \
			and compute_pending.is_empty() \
			and prepare_queue.is_empty() \
			and apply_queue.is_empty() \
			and compute_results.is_empty():
			pipeline_drained = true
		update_gates()
		var current_applied_count: int = count_applied_chunks()
		var pct: float = float(current_applied_count) / float(total) * 80.0 if total > 0 else 80.0
		progress_callback.call(
			pct,
			Localization.t("UI_LOADING_GENERATING_TERRAIN", {"current": current_applied_count, "total": total})
		)
		var iter_ms: float = float(Time.get_ticks_usec() - iter_start) / 1000.0
		loop_iter += 1
		if iter_ms > 10.0:
			WorldPerfProbe.record("Boot.loop_step_ms", iter_ms)
		if first_playable:
			break
		await _owner.get_tree().process_frame
	has_remaining_chunks_flag = not complete_flag
	if has_remaining_chunks_flag:
		if not pipeline_drained and has_pending_runtime_handoff_work():
			start_runtime_handoff()
		progress_callback.call(85.0, Localization.t("UI_LOADING_LANDING"))
		await _owner.get_tree().process_frame
	progress_callback.call(95.0, Localization.t("UI_LOADING_LANDING"))
	await _owner.get_tree().process_frame
	_sync_loaded_chunk_display_positions(boot_center)
	_reset_visual_runtime_telemetry()

func count_applied_chunks() -> int:
	var counted_applied: int = 0
	for coord: Vector2i in chunk_states:
		if int(chunk_states[coord]) >= _owner.BootChunkState.APPLIED:
			counted_applied += 1
	return counted_applied

func on_chunk_applied(coord: Vector2i, chunk: Chunk) -> void:
	if not chunk_states.has(coord):
		return
	if int(chunk_states[coord]) < _owner.BootChunkState.APPLIED:
		set_chunk_state(coord, _owner.BootChunkState.APPLIED)
	on_chunk_redraw_progress(chunk)

func on_chunk_redraw_progress(chunk: Chunk) -> void:
	if chunk == null or not chunk_states.has(chunk.chunk_coord):
		return
	_sync_chunk_visibility_for_publication(chunk)
	if chunk.is_first_pass_ready():
		if _owner._chunk_visual_scheduler != null:
			_owner._chunk_visual_scheduler.mark_first_pass_ready(chunk.chunk_coord, _active_z())
	if chunk.is_full_redraw_ready():
		if _owner._chunk_visual_scheduler != null:
			_owner._chunk_visual_scheduler.mark_full_ready(chunk.chunk_coord, _active_z())
		set_chunk_state(chunk.chunk_coord, _owner.BootChunkState.VISUAL_COMPLETE)

func invalidate_visual_complete(coord: Vector2i, z_level: int) -> void:
	if complete_flag or z_level != compute_z:
		return
	if not chunk_states.has(coord):
		return
	if int(chunk_states[coord]) >= _owner.BootChunkState.VISUAL_COMPLETE:
		set_chunk_state(coord, _owner.BootChunkState.APPLIED)

func is_first_playable_slice_ready() -> bool:
	if chunk_states.is_empty():
		return false
	for coord: Vector2i in chunk_states:
		var ring: int = get_chunk_ring(coord)
		if ring > _owner.BOOT_FIRST_PLAYABLE_MAX_RING:
			continue
		var state: int = int(chunk_states[coord])
		if state < _owner.BootChunkState.APPLIED:
			return false
		var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(compute_z)
		var chunk: Chunk = loaded_chunks_for_z.get(coord) as Chunk
		if chunk == null:
			return false
		if not chunk.is_full_redraw_ready():
			return false
	return true

func has_pending_near_ring_work() -> bool:
	if chunk_states.is_empty():
		return false
	for coord: Vector2i in chunk_states:
		var ring: int = get_chunk_ring(coord)
		if ring > _owner.BOOT_FIRST_PLAYABLE_MAX_RING:
			continue
		var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(compute_z)
		var chunk: Chunk = loaded_chunks_for_z.get(coord) as Chunk
		var state: int = int(chunk_states[coord])
		if state < _owner.BootChunkState.APPLIED or chunk == null:
			return true
		if not chunk.is_full_redraw_ready():
			return true
	return false

func enqueue_runtime_load(coord: Vector2i) -> void:
	coord = _canonical_chunk_coord(coord)
	var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(compute_z)
	if loaded_chunks_for_z.has(coord) \
		or _has_load_request(coord, compute_z) \
		or _is_staged_request(coord, compute_z) \
		or _is_generating_request(coord, compute_z):
		return
	if _owner._chunk_streaming_service != null:
		_owner._chunk_streaming_service.enqueue_load_request(coord, compute_z)
		_owner._chunk_streaming_service.sort_load_queue_by_priority(center)

func all_tracked_chunks_visual_complete() -> bool:
	for coord: Vector2i in chunk_states:
		if int(chunk_states[coord]) < _owner.BootChunkState.VISUAL_COMPLETE:
			return false
	return true

func has_pending_runtime_handoff_work() -> bool:
	if not prepare_queue.is_empty() or not apply_queue.is_empty() or not compute_pending.is_empty():
		return true
	for coord: Vector2i in chunk_states:
		if int(chunk_states[coord]) < _owner.BootChunkState.APPLIED:
			return true
	return false

func process_redraw_budget(max_usec: int) -> void:
	_tick_visuals_budget(max_usec)

func start_runtime_handoff() -> void:
	if runtime_handoff_started:
		return
	runtime_handoff_started = true
	compute_generation += 1
	for entry_variant: Variant in prepare_queue:
		_cache_chunk_install_handoff_entry(entry_variant as Dictionary, compute_z)
	for entry_variant: Variant in apply_queue:
		_cache_chunk_install_handoff_entry(entry_variant as Dictionary, compute_z)
	for coord_variant: Variant in compute_pending:
		var pending_coord: Vector2i = coord_variant as Vector2i
		compute_requested_usec.erase(pending_coord)
		compute_started_usec.erase(pending_coord)
	prepare_queue.clear()
	apply_queue.clear()
	compute_pending.clear()
	for coord: Vector2i in chunk_states:
		if int(chunk_states[coord]) < _owner.BootChunkState.APPLIED:
			enqueue_runtime_load(coord)

func tick_remaining() -> void:
	if not has_remaining_chunks_flag:
		return
	if first_playable and not runtime_handoff_started and has_pending_runtime_handoff_work():
		start_runtime_handoff()
	if runtime_handoff_started:
		collect_completed()
		drain_computed_to_apply_queue()
		for entry_variant: Variant in prepare_queue:
			_cache_chunk_install_handoff_entry(entry_variant as Dictionary, compute_z)
		for entry_variant: Variant in apply_queue:
			_cache_chunk_install_handoff_entry(entry_variant as Dictionary, compute_z)
		prepare_queue.clear()
		apply_queue.clear()
		for coord: Vector2i in chunk_states:
			if int(chunk_states[coord]) < _owner.BootChunkState.APPLIED:
				enqueue_runtime_load(coord)
	else:
		submit_pending_tasks()
		collect_completed()
		drain_computed_to_apply_queue()
		prepare_apply_entries()
		apply_from_queue()
	pipeline_drained = compute_active.is_empty() \
		and compute_pending.is_empty() \
		and prepare_queue.is_empty() \
		and apply_queue.is_empty() \
		and compute_results.is_empty()
	promote_redrawn_chunks()
	if pipeline_drained and not topology_ready:
		var all_startup_applied: bool = true
		for coord: Vector2i in chunk_states:
			if int(chunk_states[coord]) < _owner.BootChunkState.APPLIED:
				all_startup_applied = false
				break
		if all_startup_applied and _owner.is_topology_ready():
			topology_ready = true
	update_gates()
	if complete_flag:
		cleanup_compute_pipeline()
		has_remaining_chunks_flag = false

func compute_chunk_native_data(coord: Vector2i, z_level: int) -> Dictionary:
	coord = _canonical_chunk_coord(coord)
	if z_level != 0:
		return _generate_solid_rock_chunk()
	var cached_data: Dictionary = {}
	if _try_get_surface_payload_cache_native_data(coord, z_level, cached_data):
		return cached_data
	var native_data: Dictionary = _build_surface_chunk_native_data(coord)
	_cache_surface_chunk_payload(coord, z_level, native_data)
	return native_data

func worker_compute(
	coord: Vector2i,
	z_level: int,
	builder: ChunkContentBuilder,
	generation: int,
	requested_usec: int
) -> void:
	if _owner._shutdown_in_progress:
		return
	var started_usec_local: int = Time.get_ticks_usec()
	var result_entry: Dictionary = {
		"generation": generation,
		"queue_wait_ms": float(started_usec_local - requested_usec) / 1000.0,
	}
	var data: Dictionary
	if z_level != 0:
		data = _generate_solid_rock_chunk()
	else:
		data = builder.build_chunk_native_data(coord)
	if _owner._shutdown_in_progress:
		return
	result_entry["native_data"] = data
	result_entry["compute_ms"] = float(Time.get_ticks_usec() - started_usec_local) / 1000.0
	if z_level == 0 and not data.is_empty():
		if data.has("flora_placements") and not (data["flora_placements"] as Array).is_empty():
			result_entry["flora_payload"] = _build_native_flora_payload_from_placements(coord, data)
		else:
			var flora_builder: ChunkFloraBuilder = _create_detached_flora_builder()
			result_entry["flora_payload"] = _build_flora_payload_for_native_data(coord, data, flora_builder)
	compute_mutex.lock()
	compute_results[coord] = result_entry
	compute_mutex.unlock()

func submit_pending_tasks() -> void:
	while not compute_pending.is_empty() and compute_active.size() < _owner.BOOT_MAX_CONCURRENT_COMPUTE:
		if _owner._shutdown_in_progress:
			break
		var coord: Vector2i = compute_pending.pop_front()
		if compute_active.has(coord):
			continue
		var requested_usec: int = int(compute_requested_usec.get(coord, Time.get_ticks_usec()))
		var builder: ChunkContentBuilder = null
		if WorldGenerator and _owner._wg_has_create_detached_chunk_content_builder:
			builder = WorldGenerator.create_detached_chunk_content_builder()
		if builder == null:
			print("[Boot] WARN: builder is null for %s — using sync fallback" % [coord])
			var compute_usec: int = Time.get_ticks_usec()
			var native_data: Dictionary = compute_chunk_native_data(coord, compute_z)
			var compute_ms_local: float = float(Time.get_ticks_usec() - compute_usec) / 1000.0
			var result_entry: Dictionary = {
				"native_data": native_data,
				"generation": compute_generation,
				"queue_wait_ms": float(compute_usec - requested_usec) / 1000.0,
				"compute_ms": compute_ms_local,
			}
			if compute_z == 0 and not native_data.is_empty():
				if native_data.has("flora_placements") and not (native_data["flora_placements"] as Array).is_empty():
					result_entry["flora_payload"] = _build_native_flora_payload_from_placements(coord, native_data)
				else:
					result_entry["flora_payload"] = _build_flora_payload_for_native_data(coord, native_data)
			compute_mutex.lock()
			compute_results[coord] = result_entry
			compute_mutex.unlock()
			continue
		compute_started_usec[coord] = Time.get_ticks_usec()
		var task_id: int = WorkerThreadPool.add_task(
			worker_compute.bind(coord, compute_z, builder, compute_generation, requested_usec)
		)
		compute_active[coord] = task_id
		compute_builders[coord] = builder

func collect_completed() -> Array[Vector2i]:
	var completed: Array[Vector2i] = []
	for coord: Vector2i in compute_active.keys():
		var task_id: int = int(compute_active[coord])
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			completed.append(coord)
	for coord: Vector2i in completed:
		compute_active.erase(coord)
		compute_builders.erase(coord)
		compute_started_usec.erase(coord)
	return completed

func drain_computed_to_apply_queue() -> void:
	compute_mutex.lock()
	var ready_coords: Array[Vector2i] = []
	for coord: Vector2i in compute_results:
		ready_coords.append(coord)
	compute_mutex.unlock()
	for coord: Vector2i in ready_coords:
		compute_mutex.lock()
		var result_entry: Dictionary = compute_results.get(coord, {})
		compute_results.erase(coord)
		compute_mutex.unlock()
		var queue_wait_ms: float = float(result_entry.get("queue_wait_ms", 0.0))
		var compute_ms_local: float = float(result_entry.get("compute_ms", 0.0))
		metric_queue_wait_ms += queue_wait_ms
		metric_compute_ms += compute_ms_local
		if not result_entry.is_empty():
			metric_chunks_computed += 1
		var result_generation: int = int(result_entry.get("generation", -1))
		if result_generation != compute_generation:
			if int(chunk_states.get(coord, -1)) < _owner.BootChunkState.APPLIED:
				enqueue_runtime_load(coord)
			continue
		var native_data: Dictionary = result_entry.get("native_data", {}) as Dictionary
		if native_data.is_empty():
			push_warning("[Boot] compute failed for chunk %s — skipping" % [coord])
			if failed_coords.find(coord) < 0:
				failed_coords.append(coord)
			enqueue_runtime_load(coord)
			continue
		var flora_payload: Dictionary = result_entry.get("flora_payload", {}) as Dictionary
		set_chunk_state(coord, _owner.BootChunkState.COMPUTED)
		set_chunk_state(coord, _owner.BootChunkState.QUEUED_APPLY)
		prepare_queue.append({
			"coord": coord,
			"native_data": native_data,
			"flora_payload": flora_payload,
		})
	_sort_chunk_entry_queue_by_priority(prepare_queue, center)

func prepare_apply_entries() -> int:
	var prepared_this_step: int = 0
	while not prepare_queue.is_empty() and prepared_this_step < _owner.BOOT_MAX_PREPARE_PER_STEP:
		if _owner._shutdown_in_progress:
			break
		var entry: Dictionary = prepare_queue.pop_front()
		var coord: Vector2i = entry.get("coord", Vector2i.ZERO) as Vector2i
		var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(compute_z)
		if loaded_chunks_for_z.has(coord):
			on_chunk_applied(coord, loaded_chunks_for_z.get(coord) as Chunk)
			continue
		var native_data: Dictionary = entry.get("native_data", {}) as Dictionary
		var prepared_flora_payload: Dictionary = {}
		if compute_z == 0:
			prepared_flora_payload = entry.get("flora_payload", {}) as Dictionary
		var install_entry: Dictionary = _owner._chunk_streaming_service.prepare_chunk_install_entry(
			coord,
			compute_z,
			native_data,
			null,
			prepared_flora_payload
		) if _owner._chunk_streaming_service != null else {}
		if install_entry.is_empty():
			continue
		entry["install_entry"] = install_entry
		apply_queue.append(entry)
		prepared_this_step += 1
	_sort_chunk_entry_queue_by_priority(apply_queue, center)
	return prepared_this_step

func apply_from_queue() -> int:
	var applied_this_step_local: int = 0
	while not apply_queue.is_empty() and applied_this_step_local < _owner.BOOT_MAX_APPLY_PER_STEP:
		if _owner._shutdown_in_progress:
			break
		var front_coord: Vector2i = apply_queue[0].get("coord", Vector2i.ZERO) as Vector2i
		if get_chunk_ring(front_coord) > _owner.BOOT_FIRST_PLAYABLE_MAX_RING:
			break
		var step_start_usec: int = Time.get_ticks_usec()
		var entry: Dictionary = apply_queue.pop_front()
		var coord: Vector2i = entry.get("coord", Vector2i.ZERO) as Vector2i
		var install_entry: Dictionary = entry.get("install_entry", {}) as Dictionary
		var apply_usec: int = Time.get_ticks_usec()
		apply_chunk_from_native_data(
			coord,
			compute_z,
			install_entry.get("native_data", {}) as Dictionary,
			entry.get("flora_payload", {}) as Dictionary,
			install_entry
		)
		var apply_ms_local: float = float(Time.get_ticks_usec() - apply_usec) / 1000.0
		metric_apply_ms += apply_ms_local
		metric_chunks_applied += 1
		WorldPerfProbe.record("Boot.apply_chunk %s" % [coord], apply_ms_local)
		applied_this_step_local += 1
		applied_count += 1
		var step_ms: float = float(Time.get_ticks_usec() - step_start_usec) / 1000.0
		if step_ms > _owner.BOOT_APPLY_WARNING_MS:
			WorldPerfProbe.record("Boot.apply_step_over_budget_ms", step_ms)
	return applied_this_step_local

func wait_all_compute() -> void:
	for coord: Vector2i in compute_active.keys():
		var task_id: int = int(compute_active[coord])
		WorkerThreadPool.wait_for_task_completion(task_id)
	compute_active.clear()
	compute_builders.clear()

func cleanup_compute_pipeline() -> void:
	compute_pending.clear()
	compute_active.clear()
	compute_builders.clear()
	runtime_handoff_started = false
	compute_requested_usec.clear()
	compute_started_usec.clear()
	compute_mutex.lock()
	compute_results.clear()
	compute_mutex.unlock()
	prepare_queue.clear()
	apply_queue.clear()
	applied_count = 0
	total_count = 0
	if not failed_coords.is_empty():
		print("[Boot] %d chunk(s) failed compute: %s" % [failed_coords.size(), str(failed_coords)])

func apply_chunk_from_native_data(
	coord: Vector2i,
	z_level: int,
	native_data: Dictionary,
	flora_payload: Dictionary = {},
	install_entry: Dictionary = {}
) -> void:
	coord = _canonical_chunk_coord(coord)
	var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(z_level)
	if loaded_chunks_for_z.has(coord):
		on_chunk_applied(coord, loaded_chunks_for_z.get(coord) as Chunk)
		return
	var effective_install_entry: Dictionary = install_entry
	if effective_install_entry.is_empty():
		var prepared_flora_payload: Dictionary = flora_payload if z_level == 0 else {}
		effective_install_entry = _owner._chunk_streaming_service.prepare_chunk_install_entry(
			coord,
			z_level,
			native_data,
			null,
			prepared_flora_payload
		) if _owner._chunk_streaming_service != null else {}
	if effective_install_entry.is_empty():
		return
	var chunk: Chunk = _owner._chunk_streaming_service.create_chunk_from_install_entry(effective_install_entry) if _owner._chunk_streaming_service != null else null
	if chunk == null:
		return
	_finalize_chunk_install(coord, z_level, chunk)

func init_readiness(boot_center: Vector2i, boot_load_radius: int) -> void:
	chunk_states.clear()
	center = boot_center
	load_radius = boot_load_radius
	first_playable = false
	complete_flag = false
	topology_ready = false
	has_remaining_chunks_flag = false
	pipeline_drained = false
	runtime_handoff_started = false
	started_usec = Time.get_ticks_usec()
	compute_generation += 1
	failed_coords.clear()
	compute_requested_usec.clear()
	compute_started_usec.clear()
	metric_compute_ms = 0.0
	metric_apply_ms = 0.0
	metric_terrain_redraw_ms = 0.0
	metric_queue_wait_ms = 0.0
	metric_chunks_computed = 0
	metric_chunks_applied = 0
	prepare_queue.clear()
	apply_queue.clear()

func set_chunk_state(coord: Vector2i, new_state: int) -> void:
	var current_state: int = int(chunk_states.get(coord, -1))
	assert(
		new_state != _owner.BootChunkState.VISUAL_COMPLETE or current_state >= _owner.BootChunkState.APPLIED,
		"boot: visual_complete must not precede applied for chunk %s" % [coord]
	)
	chunk_states[coord] = new_state

func get_chunk_ring(coord: Vector2i) -> int:
	return _chunk_chebyshev_distance(coord, center)

func update_gates() -> void:
	if chunk_states.is_empty():
		return
	var all_chunks_terminal: bool = all_tracked_chunks_visual_complete()
	var was_first_playable: bool = first_playable
	first_playable = is_first_playable_slice_ready()
	if first_playable and not was_first_playable:
		var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0 if started_usec > 0 else 0.0
		WorldPerfProbe.mark_milestone("Boot.first_playable")
		print("[Boot] first_playable reached (%.1f ms) | queue_wait=%.1fms compute=%.1fms (%d chunks) apply=%.1fms (%d chunks) redraw=%.1fms" % [
			elapsed_ms, metric_queue_wait_ms, metric_compute_ms, metric_chunks_computed,
			metric_apply_ms, metric_chunks_applied,
			metric_terrain_redraw_ms
		])
	var was_boot_complete: bool = complete_flag
	complete_flag = all_chunks_terminal and topology_ready
	if complete_flag and not was_boot_complete:
		var elapsed_complete_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0 if started_usec > 0 else 0.0
		WorldPerfProbe.mark_milestone("Boot.boot_complete")
		print("[Boot] boot_complete reached (%.1f ms) | queue_wait=%.1fms compute=%.1fms (%d chunks) apply=%.1fms (%d chunks) redraw=%.1fms" % [
			elapsed_complete_ms, metric_queue_wait_ms, metric_compute_ms, metric_chunks_computed,
			metric_apply_ms, metric_chunks_applied,
			metric_terrain_redraw_ms
		])

func promote_redrawn_chunks() -> void:
	for coord: Vector2i in chunk_states:
		var state: int = int(chunk_states[coord])
		if state < _owner.BootChunkState.APPLIED:
			continue
		var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(compute_z)
		var chunk: Chunk = loaded_chunks_for_z.get(coord) as Chunk
		if chunk == null:
			continue
		on_chunk_redraw_progress(chunk)

func get_chunk_state(coord: Vector2i) -> int:
	return int(chunk_states.get(coord, -1))

func get_chunk_states_snapshot() -> Dictionary:
	return chunk_states.duplicate()

func get_compute_active_count() -> int:
	return compute_active.size()

func get_compute_pending_count() -> int:
	return compute_pending.size()

func get_failed_coords() -> Array[Vector2i]:
	return failed_coords.duplicate()

func _active_z() -> int:
	return _owner.get_active_z_level()

func _canonical_chunk_coord(coord: Vector2i) -> Vector2i:
	return _owner._canonical_chunk_coord(coord)

func _offset_chunk_coord(coord: Vector2i, offset: Vector2i) -> Vector2i:
	return _owner._offset_chunk_coord(coord, offset)

func _chunk_priority_less(a: Vector2i, b: Vector2i, current_center: Vector2i) -> bool:
	return _owner._chunk_priority_less(a, b, current_center)

func _chunk_chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return _owner._chunk_chebyshev_distance(a, b)

func _get_loaded_chunks_for_z(z_level: int) -> Dictionary:
	return _owner._get_loaded_chunks_for_z(z_level)

func _sync_chunk_visibility_for_publication(chunk: Chunk) -> void:
	_owner._sync_chunk_visibility_for_publication(chunk)

func _tick_visuals_budget(max_usec: int) -> bool:
	return _owner._tick_visuals_budget(max_usec)

func _cache_chunk_install_handoff_entry(entry: Dictionary, z_level: int) -> void:
	_owner._cache_chunk_install_handoff_entry(entry, z_level)

func _build_surface_chunk_native_data(coord: Vector2i) -> Dictionary:
	return _owner._build_surface_chunk_native_data(coord)

func _try_get_surface_payload_cache_native_data(coord: Vector2i, z_level: int, out_native_data: Dictionary) -> bool:
	return _owner._try_get_surface_payload_cache_native_data(coord, z_level, out_native_data)

func _cache_surface_chunk_payload(coord: Vector2i, z_level: int, native_data: Dictionary) -> void:
	_owner._cache_surface_chunk_payload(coord, z_level, native_data)

func _create_detached_flora_builder() -> ChunkFloraBuilder:
	return _owner._create_detached_flora_builder()

func _build_flora_payload_for_native_data(
	chunk_coord: Vector2i,
	native_data: Dictionary,
	flora_builder: ChunkFloraBuilder = null
) -> Dictionary:
	return _owner._build_flora_payload_for_native_data(chunk_coord, native_data, flora_builder)

func _build_native_flora_payload_from_placements(chunk_coord: Vector2i, native_data: Dictionary) -> Dictionary:
	return _owner._build_native_flora_payload_from_placements(chunk_coord, native_data)

func _generate_solid_rock_chunk() -> Dictionary:
	return _owner._generate_solid_rock_chunk()

func _has_load_request(coord: Vector2i, z_level: int) -> bool:
	return _owner._has_load_request(coord, z_level)

func _is_staged_request(coord: Vector2i, z_level: int) -> bool:
	return _owner._is_staged_request(coord, z_level)

func _is_generating_request(coord: Vector2i, z_level: int) -> bool:
	return _owner._is_generating_request(coord, z_level)

func _sort_chunk_entry_queue_by_priority(queue: Array[Dictionary], current_center: Vector2i) -> void:
	_owner._sort_chunk_entry_queue_by_priority(queue, current_center)

func _finalize_chunk_install(coord: Vector2i, z_level: int, chunk: Chunk) -> void:
	_owner._finalize_chunk_install(coord, z_level, chunk)

func _sync_loaded_chunk_display_positions(current_center: Vector2i) -> void:
	_owner._sync_loaded_chunk_display_positions(current_center)

func _reset_visual_runtime_telemetry() -> void:
	_owner._reset_visual_runtime_telemetry()
