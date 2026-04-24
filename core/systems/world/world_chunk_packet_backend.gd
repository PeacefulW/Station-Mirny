class_name WorldChunkPacketBackend
extends RefCounted

const DEFAULT_MAX_BATCH_SIZE: int = 64

var _worker_thread: Thread = Thread.new()
var _request_mutex: Mutex = Mutex.new()
var _result_mutex: Mutex = Mutex.new()
var _request_semaphore: Semaphore = Semaphore.new()
var _pending_requests: Array[Dictionary] = []
var _completed_packets: Array[Dictionary] = []
var _completed_spawn_results: Array[Dictionary] = []
var _worker_should_exit: bool = false
var _max_batch_size: int = DEFAULT_MAX_BATCH_SIZE

func start() -> void:
	if _worker_thread.is_started():
		return
	var probe_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(probe_world_core != null, "WorldCore required - build GDExtension first")
	_worker_should_exit = false
	var start_error: Error = _worker_thread.start(_worker_loop)
	assert(start_error == OK, "Failed to start world chunk packet worker thread")

func stop() -> void:
	if not _worker_thread.is_started():
		return
	_worker_should_exit = true
	_request_semaphore.post()
	_worker_thread.wait_to_finish()

func set_max_batch_size(max_batch_size: int) -> void:
	_request_mutex.lock()
	_max_batch_size = maxi(1, max_batch_size)
	_request_mutex.unlock()

func get_max_batch_size() -> int:
	_request_mutex.lock()
	var max_batch_size: int = _max_batch_size
	_request_mutex.unlock()
	return max_batch_size

func queue_packet_request(
	chunk_coord: Vector2i,
	seed: int,
	world_version: int,
	settings_packed: PackedFloat32Array,
	epoch: int
) -> void:
	_request_mutex.lock()
	_pending_requests.append({
		"kind": "packet",
		"coord": chunk_coord,
		"seed": seed,
		"world_version": world_version,
		"settings_packed": settings_packed.duplicate(),
		"epoch": epoch,
	})
	_request_mutex.unlock()
	_request_semaphore.post()

func queue_spawn_request(
	seed: int,
	world_version: int,
	settings_packed: PackedFloat32Array,
	epoch: int
) -> void:
	_request_mutex.lock()
	_pending_requests.append({
		"kind": "spawn",
		"seed": seed,
		"world_version": world_version,
		"settings_packed": settings_packed.duplicate(),
		"epoch": epoch,
	})
	_request_mutex.unlock()
	_request_semaphore.post()

func drain_completed_packets(max_count: int) -> Array[Dictionary]:
	var drained: Array[Dictionary] = []
	_result_mutex.lock()
	var drain_count: int = mini(max_count, _completed_packets.size())
	for _i: int in range(drain_count):
		drained.append(_completed_packets.pop_front() as Dictionary)
	_result_mutex.unlock()
	return drained

func drain_completed_spawn_results(max_count: int) -> Array[Dictionary]:
	var drained: Array[Dictionary] = []
	_result_mutex.lock()
	var drain_count: int = mini(max_count, _completed_spawn_results.size())
	for _i: int in range(drain_count):
		drained.append(_completed_spawn_results.pop_front() as Dictionary)
	_result_mutex.unlock()
	return drained

func clear_queued_work() -> void:
	_request_mutex.lock()
	_pending_requests.clear()
	_request_mutex.unlock()
	_result_mutex.lock()
	_completed_packets.clear()
	_completed_spawn_results.clear()
	_result_mutex.unlock()

func has_pending_requests() -> bool:
	_request_mutex.lock()
	var has_pending: bool = not _pending_requests.is_empty()
	_request_mutex.unlock()
	return has_pending

func has_completed_packets() -> bool:
	_result_mutex.lock()
	var has_completed: bool = not _completed_packets.is_empty()
	_result_mutex.unlock()
	return has_completed

func _requests_are_batch_compatible(base_request: Dictionary, candidate_request: Dictionary) -> bool:
	if str(candidate_request.get("kind", "packet")) != "packet":
		return false
	if str(base_request.get("kind", "packet")) != "packet":
		return false
	if int(candidate_request.get("seed", 0)) != int(base_request.get("seed", 0)):
		return false
	if int(candidate_request.get("world_version", 0)) != int(base_request.get("world_version", 0)):
		return false
	if int(candidate_request.get("epoch", -1)) != int(base_request.get("epoch", -1)):
		return false
	return _settings_packed_equal(
		candidate_request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array,
		base_request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array
	)

func _settings_packed_equal(lhs: PackedFloat32Array, rhs: PackedFloat32Array) -> bool:
	if lhs.size() != rhs.size():
		return false
	for index: int in range(lhs.size()):
		if lhs[index] != rhs[index]:
			return false
	return true

func _call_generate_chunk_packets_batch(
	worker_world_core: Object,
	batch_requests: Array[Dictionary]
) -> Array:
	if batch_requests.is_empty():
		return []
	var base_request: Dictionary = batch_requests[0]
	var coords: PackedVector2Array = PackedVector2Array()
	for index: int in range(batch_requests.size()):
		coords.append(batch_requests[index].get("coord", Vector2i.ZERO) as Vector2i)
	var packets_variant: Variant = worker_world_core.call(
		"generate_chunk_packets_batch",
		int(base_request.get("seed", 0)),
		coords,
		int(base_request.get("world_version", 0)),
		base_request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array
	)
	if packets_variant is Array:
		return packets_variant as Array
	push_error(
		"WorldChunkPacketBackend.generate_chunk_packets_batch returned non-array result for %d request(s)." % batch_requests.size()
	)
	return []

func _call_resolve_world_foundation_spawn_tile(worker_world_core: Object, request: Dictionary) -> Dictionary:
	var result_variant: Variant = worker_world_core.call(
		"resolve_world_foundation_spawn_tile",
		int(request.get("seed", 0)),
		int(request.get("world_version", 0)),
		request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array
	)
	if result_variant is Dictionary:
		return result_variant as Dictionary
	push_error("WorldChunkPacketBackend.resolve_world_foundation_spawn_tile returned non-dictionary result.")
	return {
		"success": false,
		"message": "Native spawn resolver returned non-dictionary result.",
	}

func _append_completed_packets(batch_requests: Array[Dictionary], packets: Array) -> void:
	_result_mutex.lock()
	for index: int in range(batch_requests.size()):
		var packet: Dictionary = packets[index] as Dictionary
		packet["epoch"] = int(batch_requests[index].get("epoch", -1))
		_completed_packets.append(packet)
	_result_mutex.unlock()

func _requeue_requests_front(requests: Array[Dictionary]) -> void:
	if requests.is_empty():
		return
	_request_mutex.lock()
	for index: int in range(requests.size() - 1, -1, -1):
		_pending_requests.push_front(requests[index])
	_request_mutex.unlock()
	_request_semaphore.post()

func _process_batch_with_fallback(worker_world_core: Object, batch_requests: Array[Dictionary]) -> void:
	var packets: Array = _call_generate_chunk_packets_batch(worker_world_core, batch_requests)
	if packets.size() == batch_requests.size():
		_append_completed_packets(batch_requests, packets)
		return

	push_error(
		"WorldChunkPacketBackend batch response mismatch: expected %d packet(s), got %d. Falling back to single-request generation."
		% [batch_requests.size(), packets.size()]
	)
	var recovered_packets: Array[Dictionary] = []
	var recovered_requests: Array[Dictionary] = []
	var failed_requests: Array[Dictionary] = []
	for request: Dictionary in batch_requests:
		var single_request: Array[Dictionary] = [request]
		var single_packets: Array = _call_generate_chunk_packets_batch(worker_world_core, single_request)
		if single_packets.size() != 1:
			var chunk_coord: Vector2i = request.get("coord", Vector2i.ZERO) as Vector2i
			push_error(
				"WorldChunkPacketBackend single-request fallback failed for chunk %s: expected 1 packet, got %d. Re-queueing request."
				% [str(chunk_coord), single_packets.size()]
			)
			failed_requests.append(request)
			continue
		recovered_requests.append(request)
		recovered_packets.append(single_packets[0] as Dictionary)
	if not recovered_requests.is_empty():
		_append_completed_packets(recovered_requests, recovered_packets)
	if not failed_requests.is_empty():
		_requeue_requests_front(failed_requests)

func _process_spawn_request(worker_world_core: Object, request: Dictionary) -> void:
	var spawn_result: Dictionary = _call_resolve_world_foundation_spawn_tile(worker_world_core, request)
	spawn_result["epoch"] = int(request.get("epoch", -1))
	_result_mutex.lock()
	_completed_spawn_results.append(spawn_result)
	_result_mutex.unlock()

func _worker_loop() -> void:
	var worker_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(worker_world_core != null, "WorldCore required inside worker thread")
	while true:
		_request_semaphore.wait()
		if _worker_should_exit:
			return
		var base_request: Dictionary = {}
		_request_mutex.lock()
		if not _pending_requests.is_empty():
			base_request = _pending_requests.pop_front() as Dictionary
		_request_mutex.unlock()
		if base_request.is_empty():
			continue
		if str(base_request.get("kind", "packet")) == "spawn":
			_process_spawn_request(worker_world_core, base_request)
			continue
		var batch_requests: Array[Dictionary] = [base_request]
		_request_mutex.lock()
		if not _pending_requests.is_empty():
			var max_batch_size: int = _max_batch_size
			while batch_requests.size() < max_batch_size and not _pending_requests.is_empty():
				var candidate_request: Dictionary = _pending_requests[0] as Dictionary
				if not _requests_are_batch_compatible(base_request, candidate_request):
					break
				batch_requests.append(_pending_requests.pop_front() as Dictionary)
		_request_mutex.unlock()
		_process_batch_with_fallback(worker_world_core, batch_requests)
