class_name WorldChunkPacketBackend
extends RefCounted

const DEFAULT_MAX_BATCH_SIZE: int = 64

var _worker_threads: Array[Thread] = []
var _request_mutex: Mutex = Mutex.new()
var _result_mutex: Mutex = Mutex.new()
var _request_semaphore: Semaphore = Semaphore.new()
var _pending_requests: Array[Dictionary] = []
var _completed_packets: Array[Dictionary] = []
var _completed_spawn_results: Array[Dictionary] = []
var _completed_overviews: Array[Dictionary] = []
var _completed_mountain_rasters: Array[Dictionary] = []
var _completed_mountain_halo_masks: Array[Dictionary] = []
var _worker_should_exit: bool = false
var _max_batch_size: int = DEFAULT_MAX_BATCH_SIZE
var _worker_count: int = 1

func start(worker_count: int = 1) -> void:
	if not _worker_threads.is_empty():
		return
	var probe_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(probe_world_core != null, "WorldCore required - build GDExtension first")
	_worker_should_exit = false
	_worker_count = maxi(1, worker_count)
	for worker_index: int in range(_worker_count):
		var worker_thread := Thread.new()
		var start_error: Error = worker_thread.start(_worker_loop)
		assert(start_error == OK, "Failed to start world chunk packet worker thread")
		_worker_threads.append(worker_thread)

func stop() -> void:
	if _worker_threads.is_empty():
		return
	_worker_should_exit = true
	for _worker_index: int in range(_worker_threads.size()):
		_request_semaphore.post()
	for worker_thread: Thread in _worker_threads:
		worker_thread.wait_to_finish()
	_worker_threads.clear()

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

func queue_overview_request(
	seed: int,
	world_version: int,
	settings_packed: PackedFloat32Array,
	epoch: int,
	layer_mask: int = 0,
	pixels_per_cell: int = 1
) -> void:
	_request_mutex.lock()
	_pending_requests.append({
		"kind": "overview",
		"seed": seed,
		"world_version": world_version,
		"settings_packed": settings_packed.duplicate(),
		"epoch": epoch,
		"layer_mask": layer_mask,
		"pixels_per_cell": maxi(1, pixels_per_cell),
	})
	_request_mutex.unlock()
	_request_semaphore.post()

func queue_mountain_raster_request(
	packets: Array,
	target_chunk: Vector2i,
	preset: Dictionary,
	top_image: Image,
	face_image: Image,
	epoch: int,
	revision: int,
	raster_purpose: StringName = &"chunk_hit"
) -> void:
	var source_chunks: Array[Vector2i] = []
	for packet_variant: Variant in packets:
		var packet: Dictionary = packet_variant as Dictionary
		source_chunks.append(packet.get("chunk_coord", Vector2i.ZERO) as Vector2i)
	var request_preset: Dictionary = preset.duplicate(true)
	if raster_purpose == &"chunk_hit":
		request_preset["runtime_ground_patch"] = false
	_request_mutex.lock()
	_pending_requests.append({
		"kind": "mountain_raster",
		"packets": packets.duplicate(true),
		"target_chunk": target_chunk,
		"preset": request_preset,
		"top_image": top_image.duplicate() if top_image != null else null,
		"face_image": face_image.duplicate() if face_image != null else null,
		"epoch": epoch,
		"revision": revision,
		"raster_purpose": raster_purpose,
		"source_chunks": source_chunks,
		"queued_msec": Time.get_ticks_msec(),
	})
	_request_mutex.unlock()
	_request_semaphore.post()

func queue_mountain_halo_mask_request(
	solid_halo: PackedByteArray,
	target_chunk: Vector2i,
	mask_origin_world: Vector2,
	chunk_size_tiles: int,
	tile_size_px: int,
	pixels_per_tile: int,
	epoch: int,
	revision: int,
	reason: StringName,
	mask_purpose: StringName = &"mountain",
	cutout_halo: PackedByteArray = PackedByteArray(),
) -> void:
	_request_mutex.lock()
	_pending_requests.append({
		"kind": "mountain_halo_mask",
		"solid_halo": solid_halo.duplicate(),
		"cutout_halo": cutout_halo.duplicate(),
		"target_chunk": target_chunk,
		"mask_origin_world": mask_origin_world,
		"chunk_size_tiles": maxi(1, chunk_size_tiles),
		"tile_size_px": maxi(1, tile_size_px),
		"pixels_per_tile": maxi(1, pixels_per_tile),
		"epoch": epoch,
		"revision": revision,
		"reason": reason,
		"mask_purpose": mask_purpose,
		"queued_msec": Time.get_ticks_msec(),
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

func drain_completed_overviews(max_count: int) -> Array[Dictionary]:
	var drained: Array[Dictionary] = []
	_result_mutex.lock()
	var drain_count: int = mini(max_count, _completed_overviews.size())
	for _i: int in range(drain_count):
		drained.append(_completed_overviews.pop_front() as Dictionary)
	_result_mutex.unlock()
	return drained

func drain_completed_mountain_rasters(max_count: int) -> Array[Dictionary]:
	var drained: Array[Dictionary] = []
	_result_mutex.lock()
	var drain_count: int = mini(max_count, _completed_mountain_rasters.size())
	for _i: int in range(drain_count):
		drained.append(_completed_mountain_rasters.pop_front() as Dictionary)
	_result_mutex.unlock()
	return drained

func drain_completed_mountain_halo_masks(max_count: int) -> Array[Dictionary]:
	var drained: Array[Dictionary] = []
	_result_mutex.lock()
	var drain_count: int = mini(max_count, _completed_mountain_halo_masks.size())
	for _i: int in range(drain_count):
		drained.append(_completed_mountain_halo_masks.pop_front() as Dictionary)
	_result_mutex.unlock()
	return drained

func clear_queued_work() -> void:
	_request_mutex.lock()
	_pending_requests.clear()
	_request_mutex.unlock()
	_result_mutex.lock()
	_completed_packets.clear()
	_completed_spawn_results.clear()
	_completed_overviews.clear()
	_completed_mountain_rasters.clear()
	_completed_mountain_halo_masks.clear()
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

func has_completed_mountain_rasters() -> bool:
	_result_mutex.lock()
	var has_completed: bool = not _completed_mountain_rasters.is_empty()
	_result_mutex.unlock()
	return has_completed

func has_completed_mountain_halo_masks() -> bool:
	_result_mutex.lock()
	var has_completed: bool = not _completed_mountain_halo_masks.is_empty()
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

func _call_get_world_foundation_overview_payload(worker_world_core: Object, request: Dictionary) -> Dictionary:
	if not worker_world_core.has_method("get_world_foundation_overview"):
		return {
			"success": false,
			"message": "Native foundation overview API is unavailable in this build.",
		}

	var spawn_probe: Dictionary = _call_resolve_world_foundation_spawn_tile(worker_world_core, request)
	if not bool(spawn_probe.get("success", false)):
		return spawn_probe

	var requested_pixels_per_cell: int = maxi(1, int(request.get("pixels_per_cell", 1)))
	var overview_arg_count: int = _get_method_argument_count(
		worker_world_core,
		&"get_world_foundation_overview"
	)
	var overview_variant: Variant
	if overview_arg_count >= 2:
		overview_variant = worker_world_core.call(
			"get_world_foundation_overview",
			int(request.get("layer_mask", 0)),
			requested_pixels_per_cell
		)
	else:
		overview_variant = worker_world_core.call(
			"get_world_foundation_overview",
			int(request.get("layer_mask", 0))
		)
	if overview_variant is Image:
		var overview_image: Image = overview_variant as Image
		if overview_image != null and not overview_image.is_empty():
			if overview_arg_count == 1 and requested_pixels_per_cell > 1:
				overview_image = overview_image.duplicate() as Image
				overview_image.resize(
					overview_image.get_width() * requested_pixels_per_cell,
					overview_image.get_height() * requested_pixels_per_cell,
					Image.INTERPOLATE_BILINEAR
				)
			return {
				"success": true,
				"image": overview_image,
				"grid_width": int(spawn_probe.get("grid_width", 0)),
				"grid_height": int(spawn_probe.get("grid_height", 0)),
				"image_width": overview_image.get_width(),
				"image_height": overview_image.get_height(),
				"layer_mask": int(request.get("layer_mask", 0)),
				"pixels_per_cell": requested_pixels_per_cell,
				"compute_time_ms": float(spawn_probe.get("compute_time_ms", 0.0)),
			}
	return {
		"success": false,
		"message": "Native foundation overview returned empty image.",
	}

func _get_method_argument_count(target: Object, method_name: StringName) -> int:
	for method: Dictionary in target.get_method_list():
		if StringName(str(method.get("name", ""))) == method_name:
			var args: Array = method.get("args", []) as Array
			return args.size()
	return -1

func _append_completed_packets(batch_requests: Array[Dictionary], packets: Array) -> void:
	_result_mutex.lock()
	for index: int in range(batch_requests.size()):
		var packet: Dictionary = packets[index] as Dictionary
		packet["request_chunk_coord"] = batch_requests[index].get("coord", Vector2i.ZERO) as Vector2i
		packet["epoch"] = int(batch_requests[index].get("epoch", -1))
		_completed_packets.append(packet)
	_result_mutex.unlock()

func _append_failed_packets(batch_requests: Array[Dictionary], message: String) -> void:
	_result_mutex.lock()
	for request: Dictionary in batch_requests:
		var chunk_coord: Vector2i = request.get("coord", Vector2i.ZERO) as Vector2i
		_completed_packets.append({
			"success": false,
			"chunk_coord": chunk_coord,
			"request_chunk_coord": chunk_coord,
			"epoch": int(request.get("epoch", -1)),
			"message": message,
		})
	_result_mutex.unlock()

func _process_packet_batch_strict(worker_world_core: Object, batch_requests: Array[Dictionary]) -> void:
	var packets: Array = _call_generate_chunk_packets_batch(worker_world_core, batch_requests)
	if packets.size() == batch_requests.size():
		_append_completed_packets(batch_requests, packets)
		return

	var message := "WorldChunkPacketBackend batch response mismatch: expected %d packet(s), got %d. Native batch contract is required; no single-request fallback is allowed." \
		% [batch_requests.size(), packets.size()]
	push_error(message)
	_append_failed_packets(batch_requests, message)

func _process_spawn_request(worker_world_core: Object, request: Dictionary) -> void:
	var spawn_result: Dictionary = _call_resolve_world_foundation_spawn_tile(worker_world_core, request)
	spawn_result["epoch"] = int(request.get("epoch", -1))
	_result_mutex.lock()
	_completed_spawn_results.append(spawn_result)
	_result_mutex.unlock()

func _process_overview_request(worker_world_core: Object, request: Dictionary) -> void:
	var overview_result: Dictionary = _call_get_world_foundation_overview_payload(worker_world_core, request)
	overview_result["epoch"] = int(request.get("epoch", -1))
	overview_result["layer_mask"] = int(request.get("layer_mask", 0))
	_result_mutex.lock()
	_completed_overviews.append(overview_result)
	_result_mutex.unlock()

func _process_mountain_raster_request(worker_world_core: Object, request: Dictionary) -> void:
	var result: Dictionary = {}
	var started_msec: int = Time.get_ticks_msec()
	if not worker_world_core.has_method("build_mountain_plateau_raster_image"):
		result = {
			"success": false,
			"message": "WorldCore.build_mountain_plateau_raster_image is unavailable in this build.",
		}
	else:
		var result_variant: Variant = worker_world_core.call(
			"build_mountain_plateau_raster_image",
			request.get("packets", []) as Array,
			request.get("target_chunk", Vector2i.ZERO) as Vector2i,
			request.get("preset", {}) as Dictionary,
			request.get("top_image", null) as Image,
			request.get("face_image", null) as Image
		)
		if result_variant is Dictionary:
			result = result_variant as Dictionary
			result["success"] = bool(result.get("ready", false))
		else:
			result = {
				"success": false,
				"message": "Native mountain raster builder returned non-dictionary result.",
			}
	result["epoch"] = int(request.get("epoch", -1))
	result["revision"] = int(request.get("revision", -1))
	result["raster_purpose"] = request.get("raster_purpose", &"chunk_hit") as StringName
	result["target_chunk"] = request.get("target_chunk", Vector2i.ZERO) as Vector2i
	result["source_chunks"] = request.get("source_chunks", []) as Array
	result["source_chunk_count"] = (request.get("source_chunks", []) as Array).size()
	result["queued_msec"] = int(request.get("queued_msec", started_msec))
	result["worker_started_msec"] = started_msec
	result["worker_elapsed_ms"] = Time.get_ticks_msec() - started_msec
	result["queue_wait_ms"] = started_msec - int(request.get("queued_msec", started_msec))
	result["request_to_complete_ms"] = Time.get_ticks_msec() - int(request.get("queued_msec", started_msec))
	_result_mutex.lock()
	_completed_mountain_rasters.append(result)
	_result_mutex.unlock()

func _process_mountain_halo_mask_request(worker_world_core: Object, request: Dictionary) -> void:
	var result: Dictionary = {}
	var started_msec: int = Time.get_ticks_msec()
	if not worker_world_core.has_method("build_mountain_halo_mask"):
		result = {
			"success": false,
			"message": "WorldCore.build_mountain_halo_mask is unavailable in this build.",
		}
	else:
		var mask_origin_world: Vector2 = request.get("mask_origin_world", Vector2.ZERO) as Vector2
		var result_variant: Variant = worker_world_core.call(
			"build_mountain_halo_mask",
			request.get("solid_halo", PackedByteArray()) as PackedByteArray,
			int(request.get("chunk_size_tiles", 1)),
			int(request.get("tile_size_px", 1)),
			int(request.get("pixels_per_tile", 1)),
			mask_origin_world.x,
			mask_origin_world.y,
			request.get("cutout_halo", PackedByteArray()) as PackedByteArray,
		)
		if result_variant is Dictionary:
			result = result_variant as Dictionary
			var mask: PackedByteArray = result.get("mask", PackedByteArray()) as PackedByteArray
			var mask_width: int = int(result.get("width", 0))
			var mask_height: int = int(result.get("height", 0))
			result["success"] = mask_width > 0 \
				and mask_height > 0 \
				and mask.size() == mask_width * mask_height
		else:
			result = {
				"success": false,
				"message": "Native mountain halo mask builder returned non-dictionary result.",
			}
	var completed_msec: int = Time.get_ticks_msec()
	result["epoch"] = int(request.get("epoch", -1))
	result["revision"] = int(request.get("revision", -1))
	result["reason"] = request.get("reason", &"worker") as StringName
	result["mask_purpose"] = request.get("mask_purpose", &"mountain") as StringName
	if result["mask_purpose"] == &"mountain":
		result["cutout_halo"] = (
			request.get("cutout_halo", PackedByteArray()) as PackedByteArray
		).duplicate()
	result["target_chunk"] = request.get("target_chunk", Vector2i.ZERO) as Vector2i
	result["mask_origin_world"] = request.get("mask_origin_world", Vector2.ZERO) as Vector2
	result["queued_msec"] = int(request.get("queued_msec", started_msec))
	result["worker_started_msec"] = started_msec
	result["worker_elapsed_ms"] = completed_msec - started_msec
	result["queue_wait_ms"] = started_msec - int(request.get("queued_msec", started_msec))
	result["request_to_complete_ms"] = completed_msec - int(request.get("queued_msec", started_msec))
	_result_mutex.lock()
	_completed_mountain_halo_masks.append(result)
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
		if str(base_request.get("kind", "packet")) == "overview":
			_process_overview_request(worker_world_core, base_request)
			continue
		if str(base_request.get("kind", "packet")) == "mountain_raster":
			_process_mountain_raster_request(worker_world_core, base_request)
			continue
		if str(base_request.get("kind", "packet")) == "mountain_halo_mask":
			_process_mountain_halo_mask_request(worker_world_core, base_request)
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
		_process_packet_batch_strict(worker_world_core, batch_requests)
