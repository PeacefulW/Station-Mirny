class_name TerrainVisualPacketBackend
extends RefCounted

var _worker_thread: Thread = Thread.new()
var _request_mutex: Mutex = Mutex.new()
var _result_mutex: Mutex = Mutex.new()
var _request_semaphore: Semaphore = Semaphore.new()
var _pending_requests: Array[Dictionary] = []
var _completed_results: Dictionary = { }
var _cancelled_request_ids: Dictionary = { }
var _worker_should_exit: bool = false
var _next_request_id: int = 1
var _active_request_id: int = 0


func start() -> void:
	if _worker_thread.is_started():
		return
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		push_error("TerrainVisualSolver native class is required for TerrainVisualPacketBackend.")
		return
	_worker_should_exit = false
	var start_error: Error = _worker_thread.start(_worker_loop)
	assert(start_error == OK, "Failed to start terrain visual packet worker thread")


func stop() -> void:
	if not _worker_thread.is_started():
		return
	_worker_should_exit = true
	_request_semaphore.post()
	_worker_thread.wait_to_finish()
	_active_request_id = 0


func queue_chunk_visual_packet_request(
		solid_mask: PackedByteArray,
		width_tiles: int,
		height_tiles: int,
		recipe_payload: Dictionary,
		input_world_origin_tile: Vector2i,
		chunk_coord: Vector2i,
		seed: int,
		uses_halo: bool,
		output_rect_tiles: Rect2i,
) -> int:
	if not _worker_thread.is_started():
		push_error("TerrainVisualPacketBackend must be started before queueing solve work.")
		return 0
	_request_mutex.lock()
	var request_id := _next_request_id
	_next_request_id += 1
	_pending_requests.append(
		{
			"request_id": request_id,
			"solid_mask": solid_mask.duplicate(),
			"width_tiles": width_tiles,
			"height_tiles": height_tiles,
			"recipe_payload": recipe_payload.duplicate(true),
			"input_world_origin_tile": input_world_origin_tile,
			"chunk_coord": chunk_coord,
			"seed": seed,
			"uses_halo": uses_halo,
			"output_rect_tiles": output_rect_tiles,
		},
	)
	_request_mutex.unlock()
	_request_semaphore.post()
	return request_id


func take_completed_request(request_id: int) -> Dictionary:
	if request_id <= 0:
		return { }
	_result_mutex.lock()
	var result: Dictionary = _completed_results.get(request_id, { }) as Dictionary
	if not result.is_empty():
		_completed_results.erase(request_id)
		_cancelled_request_ids.erase(request_id)
	_result_mutex.unlock()
	return result


func cancel_request(request_id: int) -> void:
	if request_id <= 0:
		return
	_request_mutex.lock()
	for index: int in range(_pending_requests.size() - 1, -1, -1):
		var request: Dictionary = _pending_requests[index] as Dictionary
		if int(request.get("request_id", 0)) == request_id:
			_pending_requests.remove_at(index)
	_request_mutex.unlock()
	_result_mutex.lock()
	_completed_results.erase(request_id)
	_cancelled_request_ids[request_id] = true
	_result_mutex.unlock()


func clear_queued_work() -> void:
	var cancelled_request_ids: Array[int] = []
	_request_mutex.lock()
	for request: Dictionary in _pending_requests:
		cancelled_request_ids.append(int(request.get("request_id", 0)))
	_pending_requests.clear()
	_request_mutex.unlock()
	_result_mutex.lock()
	for request_id: int in cancelled_request_ids:
		_cancelled_request_ids[request_id] = true
	if _active_request_id > 0:
		_cancelled_request_ids[_active_request_id] = true
	_completed_results.clear()
	_result_mutex.unlock()


func has_pending_requests() -> bool:
	_request_mutex.lock()
	var has_pending := not _pending_requests.is_empty()
	_request_mutex.unlock()
	_result_mutex.lock()
	has_pending = has_pending or _active_request_id > 0
	_result_mutex.unlock()
	return has_pending


func _worker_loop() -> void:
	var worker_solver: Object = ClassDB.instantiate(&"TerrainVisualSolver")
	assert(worker_solver != null, "TerrainVisualSolver required inside visual packet worker")
	while true:
		_request_semaphore.wait()
		if _worker_should_exit:
			break
		var request: Dictionary = { }
		_request_mutex.lock()
		if not _pending_requests.is_empty():
			request = _pending_requests.pop_front() as Dictionary
		_request_mutex.unlock()
		if request.is_empty():
			continue
		_set_active_request_id(int(request.get("request_id", 0)))
		var result := _solve_request(worker_solver, request)
		_store_result(result)
		_set_active_request_id(0)
	if worker_solver != null:
		worker_solver.free()


func _set_active_request_id(request_id: int) -> void:
	_result_mutex.lock()
	_active_request_id = request_id
	_result_mutex.unlock()


func _store_result(result: Dictionary) -> void:
	var request_id := int(result.get("request_id", 0))
	if request_id <= 0:
		return
	_result_mutex.lock()
	if _cancelled_request_ids.has(request_id):
		_cancelled_request_ids.erase(request_id)
	else:
		_completed_results[request_id] = result
	_result_mutex.unlock()


func _solve_request(worker_solver: Object, request: Dictionary) -> Dictionary:
	var request_id := int(request.get("request_id", 0))
	var uses_halo := bool(request.get("uses_halo", false))
	var solver_method := (
		&"build_chunk_visual_packet_with_halo" if uses_halo else &"build_chunk_visual_packet"
	)
	var started_usec := Time.get_ticks_usec()
	var packet_variant: Variant
	if uses_halo:
		packet_variant = worker_solver.call(
			"build_chunk_visual_packet_with_halo",
			request.get("solid_mask", PackedByteArray()) as PackedByteArray,
			int(request.get("width_tiles", 0)),
			int(request.get("height_tiles", 0)),
			request.get("recipe_payload", { }) as Dictionary,
			request.get("input_world_origin_tile", Vector2i.ZERO) as Vector2i,
			request.get("chunk_coord", Vector2i.ZERO) as Vector2i,
			int(request.get("seed", 0)),
			request.get("output_rect_tiles", Rect2i(Vector2i.ZERO, Vector2i.ZERO)) as Rect2i,
		)
	else:
		packet_variant = worker_solver.call(
			"build_chunk_visual_packet",
			request.get("solid_mask", PackedByteArray()) as PackedByteArray,
			int(request.get("width_tiles", 0)),
			int(request.get("height_tiles", 0)),
			request.get("recipe_payload", { }) as Dictionary,
			request.get("input_world_origin_tile", Vector2i.ZERO) as Vector2i,
			request.get("chunk_coord", Vector2i.ZERO) as Vector2i,
			int(request.get("seed", 0)),
		)
	var solve_usec := Time.get_ticks_usec() - started_usec
	if packet_variant is Dictionary:
		var packet := packet_variant as Dictionary
		if not packet.is_empty():
			return {
				"success": true,
				"request_id": request_id,
				"chunk_coord": request.get("chunk_coord", Vector2i.ZERO) as Vector2i,
				"solver_method": solver_method,
				"solve_usec": solve_usec,
				"packet": packet,
			}
	return {
		"success": false,
		"request_id": request_id,
		"chunk_coord": request.get("chunk_coord", Vector2i.ZERO) as Vector2i,
		"solver_method": solver_method,
		"solve_usec": solve_usec,
		"message": "TerrainVisualSolver returned an empty or invalid packet.",
	}
