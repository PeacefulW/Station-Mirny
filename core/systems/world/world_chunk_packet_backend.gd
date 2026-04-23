class_name WorldChunkPacketBackend
extends RefCounted

const MAX_BATCH_SIZE: int = 32

var _worker_thread: Thread = Thread.new()
var _request_mutex: Mutex = Mutex.new()
var _result_mutex: Mutex = Mutex.new()
var _request_semaphore: Semaphore = Semaphore.new()
var _pending_requests: Array[Dictionary] = []
var _completed_packets: Array[Dictionary] = []
var _worker_should_exit: bool = false

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

func queue_packet_request(
	chunk_coord: Vector2i,
	seed: int,
	world_version: int,
	settings_packed: PackedFloat32Array,
	epoch: int
) -> void:
	_request_mutex.lock()
	_pending_requests.append({
		"coord": chunk_coord,
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

func clear_queued_work() -> void:
	_request_mutex.lock()
	_pending_requests.clear()
	_request_mutex.unlock()
	_result_mutex.lock()
	_completed_packets.clear()
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

func _worker_loop() -> void:
	var worker_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(worker_world_core != null, "WorldCore required inside worker thread")
	while true:
		_request_semaphore.wait()
		if _worker_should_exit:
			return
		var batch_requests: Array[Dictionary] = []
		_request_mutex.lock()
		if not _pending_requests.is_empty():
			var base_request: Dictionary = _pending_requests.pop_front() as Dictionary
			batch_requests.append(base_request)
			while batch_requests.size() < MAX_BATCH_SIZE and not _pending_requests.is_empty():
				var candidate_request: Dictionary = _pending_requests[0] as Dictionary
				if not _requests_are_batch_compatible(base_request, candidate_request):
					break
				batch_requests.append(_pending_requests.pop_front() as Dictionary)
		_request_mutex.unlock()
		if batch_requests.is_empty():
			continue
		var base_request: Dictionary = batch_requests[0]
		var coords: PackedVector2Array = PackedVector2Array()
		for index: int in range(batch_requests.size()):
			coords.append(batch_requests[index].get("coord", Vector2i.ZERO) as Vector2i)
		var packets: Array = worker_world_core.call(
			"generate_chunk_packets_batch",
			int(base_request.get("seed", 0)),
			coords,
			int(base_request.get("world_version", 0)),
			base_request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array
		) as Array
		_result_mutex.lock()
		for index: int in range(mini(batch_requests.size(), packets.size())):
			var packet: Dictionary = packets[index] as Dictionary
			packet["epoch"] = int(batch_requests[index].get("epoch", -1))
			_completed_packets.append(packet)
		_result_mutex.unlock()
