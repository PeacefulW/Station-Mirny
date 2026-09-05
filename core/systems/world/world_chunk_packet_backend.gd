class_name WorldChunkPacketBackend
extends RefCounted

const DEFAULT_MAX_BATCH_SIZE: int = 64
const MOUNTAIN_SKYLIGHT_REACH_TILES: int = 1
const PRIORITY_CLASS_INTERACTIVE: int = 0
const PRIORITY_CLASS_REVEAL: int = 1
const PRIORITY_CLASS_STREAMING: int = 2
const PRIORITY_CLASS_BACKGROUND: int = 3
# Shared-pool weighted fairness. With the normal six-worker cap, five reveal
# dispatches followed by one streaming slot approximates one worker of sustained
# source-prefetch throughput without giving up deadline-first scheduling.
const MAX_REVEAL_DISPATCH_BURST: int = 5
const MAX_NON_BACKGROUND_DISPATCH_BURST: int = 31
const RESULT_QUEUE_COMPACT_MIN_HEAD: int = 64

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
var _completed_grass_scatter_buffers: Array[Dictionary] = []
var _completed_object_presentation_buffers: Array[Dictionary] = []
var _completed_world_render_snapshots: Array[Dictionary] = []
var _completed_result_head_by_queue: Dictionary = {}
var _worker_should_exit: bool = false
var _max_batch_size: int = DEFAULT_MAX_BATCH_SIZE
var _worker_count: int = 1
var _request_dispatch_turn: int = 0
var _next_request_enqueue_sequence: int = 0
var _reveal_dispatch_burst: int = 0
var _non_background_dispatch_burst: int = 0


func start(worker_count: int = 1) -> void:
	if not _worker_threads.is_empty():
		return
	var probe_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(probe_world_core != null, "WorldCore required - build GDExtension first")
	_request_mutex.lock()
	_worker_should_exit = false
	_request_mutex.unlock()
	_worker_count = maxi(1, worker_count)
	for worker_index: int in range(_worker_count):
		var worker_thread := Thread.new()
		var start_error: Error = worker_thread.start(_worker_loop)
		if start_error != OK:
			_request_mutex.lock()
			_worker_should_exit = true
			_request_mutex.unlock()
			for started_worker_index: int in range(_worker_threads.size()):
				_request_semaphore.post()
			for started_worker: Thread in _worker_threads:
				started_worker.wait_to_finish()
			_worker_threads.clear()
			push_error(
				"Failed to start world chunk packet worker thread: %s" % error_string(start_error)
			)
			assert(false, "Failed to start world chunk packet worker thread")
			return
		_worker_threads.append(worker_thread)


func stop() -> void:
	if _worker_threads.is_empty():
		return
	_request_mutex.lock()
	_worker_should_exit = true
	_request_mutex.unlock()
	for worker_index: int in range(_worker_threads.size()):
		_request_semaphore.post()
	for worker_thread: Thread in _worker_threads:
		worker_thread.wait_to_finish()
	_worker_threads.clear()
	_request_mutex.lock()
	_reveal_dispatch_burst = 0
	_non_background_dispatch_burst = 0
	_request_mutex.unlock()


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
		epoch: int,
		priority: int = 0,
		priority_class: int = PRIORITY_CLASS_STREAMING,
) -> void:
	var request := {
		"kind": "packet",
		"coord": chunk_coord,
		"seed": seed,
		"world_version": world_version,
		"settings_packed": settings_packed.duplicate(),
		"epoch": epoch,
		"priority": priority,
		"priority_class": priority_class,
	}
	_request_mutex.lock()
	for request_index: int in range(_pending_requests.size()):
		var queued_request: Dictionary = _pending_requests[request_index] as Dictionary
		if str(queued_request.get("kind", "")) != "packet" \
				or int(queued_request.get("epoch", -1)) != epoch \
				or (queued_request.get("coord", Vector2i.ZERO) as Vector2i) != chunk_coord:
			continue
		# Coalescing replaces generation truth as one atomic snapshot. Epoch is a
		# normal caller invariant, not permission to retain an older seed/version
		# or settings payload for the same coordinate.
		request["enqueued_turn"] = int(
			queued_request.get("enqueued_turn", _request_dispatch_turn)
		)
		request["enqueue_sequence"] = int(
			queued_request.get("enqueue_sequence", _next_request_enqueue_sequence)
		)
		_pending_requests[request_index] = request
		_reset_fairness_debt_without_waiters_locked()
		_request_mutex.unlock()
		return
	request["enqueued_turn"] = _request_dispatch_turn
	request["enqueue_sequence"] = _claim_request_enqueue_sequence_locked()
	_pending_requests.append(request)
	_request_semaphore.post()
	_request_mutex.unlock()


## Keeps queued packet work aligned with the current source bubble. Requests
## already executing cannot be cancelled; their epoch-tagged results remain
## safe to reject or cache on the main thread.
func sync_packet_requests(epoch: int, priority_by_coord: Dictionary) -> Array[Vector2i]:
	var removed_coords: Array[Vector2i] = []
	_request_mutex.lock()
	var retained: Array[Dictionary] = []
	for request: Dictionary in _pending_requests:
		if str(request.get("kind", "")) != "packet" or int(request.get("epoch", -1)) != epoch:
			retained.append(request)
			continue
		var coord: Vector2i = request.get("coord", Vector2i.ZERO) as Vector2i
		if not priority_by_coord.has(coord):
			removed_coords.append(coord)
			continue
		request["priority"] = int(priority_by_coord.get(coord, 0))
		retained.append(request)
	_pending_requests = retained
	_reset_fairness_debt_without_waiters_locked()
	_consume_cancelled_request_permits_locked(removed_coords.size())
	_request_mutex.unlock()
	return removed_coords


func queue_grass_scatter_request(
		chunk_coord: Vector2i,
		seed: int,
		terrain_ids: PackedInt32Array,
		lake_flags: PackedByteArray,
		mountain_solid_halo: PackedByteArray,
		mountain_solid_halo_radius_tiles: int,
		grass_params: PackedFloat32Array,
		epoch: int,
		revision: int,
		priority: int = 0,
		priority_class: int = PRIORITY_CLASS_STREAMING,
) -> void:
	var request := {
		"kind": "grass_scatter",
		"coord": chunk_coord,
		"seed": seed,
		"terrain_ids": terrain_ids.duplicate(),
		"lake_flags": lake_flags.duplicate(),
		"mountain_solid_halo": mountain_solid_halo.duplicate(),
		"mountain_solid_halo_radius_tiles": maxi(0, mountain_solid_halo_radius_tiles),
		"grass_params": grass_params.duplicate(),
		"epoch": epoch,
		"revision": revision,
		"priority": priority,
		"priority_class": priority_class,
		"queued_msec": Time.get_ticks_msec(),
	}
	_request_mutex.lock()
	for request_index: int in range(_pending_requests.size()):
		var queued_request: Dictionary = _pending_requests[request_index] as Dictionary
		if str(queued_request.get("kind", "")) != "grass_scatter" \
				or int(queued_request.get("epoch", -1)) != epoch \
				or (queued_request.get("coord", Vector2i.ZERO) as Vector2i) != chunk_coord:
			continue
		request["enqueued_turn"] = int(queued_request.get("enqueued_turn", _request_dispatch_turn))
		request["enqueue_sequence"] = int(
			queued_request.get("enqueue_sequence", _next_request_enqueue_sequence)
		)
		_pending_requests[request_index] = request
		_reset_fairness_debt_without_waiters_locked()
		_request_mutex.unlock()
		return
	request["enqueued_turn"] = _request_dispatch_turn
	request["enqueue_sequence"] = _claim_request_enqueue_sequence_locked()
	_pending_requests.append(request)
	_request_semaphore.post()
	_request_mutex.unlock()


func sync_grass_scatter_requests(epoch: int, revision_and_priority_by_coord: Dictionary) -> Array[Vector2i]:
	var removed_coords: Array[Vector2i] = []
	_request_mutex.lock()
	var retained: Array[Dictionary] = []
	for request: Dictionary in _pending_requests:
		if str(request.get("kind", "")) != "grass_scatter" or int(request.get("epoch", -1)) != epoch:
			retained.append(request)
			continue
		var coord: Vector2i = request.get("coord", Vector2i.ZERO) as Vector2i
		var current: Dictionary = revision_and_priority_by_coord.get(coord, {}) as Dictionary
		if current.is_empty() or int(current.get("revision", -1)) != int(request.get("revision", -2)):
			removed_coords.append(coord)
			continue
		request["priority"] = int(current.get("priority", 0))
		retained.append(request)
	_pending_requests = retained
	_reset_fairness_debt_without_waiters_locked()
	_consume_cancelled_request_permits_locked(removed_coords.size())
	_request_mutex.unlock()
	return removed_coords


func queue_world_render_snapshot_request(
		chunk_origins: PackedVector2Array,
		object_results: Array,
		grass_results: Array,
		source_bindings: Array,
		grass_lod_fraction: float,
		epoch: int,
		request_generation: int,
) -> void:
	var request := {
		"kind": "world_render_snapshot",
		"chunk_origins": chunk_origins.duplicate(),
		# Dictionaries and packed arrays are immutable worker results. Duplicate
		# only the Array shells; copying every 30+ MiB payload would defeat the
		# point of the background render-preparation stage.
		"object_results": object_results.duplicate(),
		"grass_results": grass_results.duplicate(),
		"source_bindings": source_bindings.duplicate(true),
		"grass_lod_fraction": grass_lod_fraction,
		"epoch": epoch,
		"request_generation": request_generation,
		"priority": -1000000,
		"priority_class": PRIORITY_CLASS_BACKGROUND,
		"queued_msec": Time.get_ticks_msec(),
	}
	_request_mutex.lock()
	for request_index: int in range(_pending_requests.size()):
		var queued: Dictionary = _pending_requests[request_index] as Dictionary
		if str(queued.get("kind", "")) != "world_render_snapshot" \
				or int(queued.get("epoch", -1)) != epoch:
			continue
		request["enqueued_turn"] = int(queued.get("enqueued_turn", _request_dispatch_turn))
		request["enqueue_sequence"] = int(
			queued.get("enqueue_sequence", _next_request_enqueue_sequence),
		)
		_pending_requests[request_index] = request
		_request_mutex.unlock()
		return
	request["enqueued_turn"] = _request_dispatch_turn
	request["enqueue_sequence"] = _claim_request_enqueue_sequence_locked()
	_pending_requests.append(request)
	_request_semaphore.post()
	_request_mutex.unlock()


## Queues pure object-packet decoding/bucketing for a worker-local WorldCore.
## Packet object channels and catalog parameter arrays have an immutable-owner
## contract: the request keeps their ref-counted PackedArray handles in O(1),
## and both producer and worker only read them until completion. Rebinding a
## producer value is safe; mutating a shared handle violates this contract. The
## 256-cell terrain packet never crosses this path.
func queue_object_presentation_request(
		chunk_coord: Vector2i,
		packet: Dictionary,
		tree_metrics: PackedFloat32Array,
		rock_metrics: PackedFloat32Array,
		bush_metrics: PackedFloat32Array,
		params: PackedFloat32Array,
		catalog_generation: int,
		epoch: int,
		revision: int,
		priority: int = 0,
		priority_class: int = PRIORITY_CLASS_REVEAL,
) -> void:
	var request := {
		"kind": "object_presentation",
		"coord": chunk_coord,
		"object_kind": packet.get("object_kind", PackedByteArray()) as PackedByteArray,
		"object_x": packet.get("object_local_x_px_q4", PackedByteArray()) as PackedByteArray,
		"object_y": packet.get("object_local_y_px_q4", PackedByteArray()) as PackedByteArray,
		"object_size": packet.get("object_size_px", PackedByteArray()) as PackedByteArray,
		"object_atlas": packet.get("object_atlas_index", PackedByteArray()) as PackedByteArray,
		"object_variant": packet.get("object_variant", PackedByteArray()) as PackedByteArray,
		"object_flags": packet.get("object_flags", PackedByteArray()) as PackedByteArray,
		"object_tint": packet.get("object_tint", PackedByteArray()) as PackedByteArray,
		"object_phase": packet.get("object_phase", PackedByteArray()) as PackedByteArray,
		"tree_metrics": tree_metrics,
		"rock_metrics": rock_metrics,
		"bush_metrics": bush_metrics,
		"params": params,
		"catalog_generation": catalog_generation,
		"epoch": epoch,
		"revision": revision,
		"priority": priority,
		"priority_class": priority_class,
		"queued_msec": Time.get_ticks_msec(),
	}
	_request_mutex.lock()
	for request_index: int in range(_pending_requests.size()):
		var queued_request: Dictionary = _pending_requests[request_index] as Dictionary
		if str(queued_request.get("kind", "")) != "object_presentation" \
				or int(queued_request.get("epoch", -1)) != epoch \
				or (queued_request.get("coord", Vector2i.ZERO) as Vector2i) != chunk_coord:
			continue
		request["enqueued_turn"] = int(queued_request.get("enqueued_turn", _request_dispatch_turn))
		request["enqueue_sequence"] = int(
			queued_request.get("enqueue_sequence", _next_request_enqueue_sequence)
		)
		_pending_requests[request_index] = request
		_reset_fairness_debt_without_waiters_locked()
		_request_mutex.unlock()
		return
	request["enqueued_turn"] = _request_dispatch_turn
	request["enqueue_sequence"] = _claim_request_enqueue_sequence_locked()
	_pending_requests.append(request)
	_request_semaphore.post()
	_request_mutex.unlock()


func sync_object_presentation_requests(
		epoch: int,
		revision_and_priority_by_coord: Dictionary,
) -> Array[Vector2i]:
	var removed_coords: Array[Vector2i] = []
	_request_mutex.lock()
	var retained: Array[Dictionary] = []
	for request: Dictionary in _pending_requests:
		if str(request.get("kind", "")) != "object_presentation" \
				or int(request.get("epoch", -1)) != epoch:
			retained.append(request)
			continue
		var coord: Vector2i = request.get("coord", Vector2i.ZERO) as Vector2i
		var current: Dictionary = revision_and_priority_by_coord.get(coord, {}) as Dictionary
		if current.is_empty() \
				or int(current.get("revision", -1)) != int(request.get("revision", -2)) \
				or int(current.get("catalog_generation", -1)) \
						!= int(request.get("catalog_generation", -2)):
			removed_coords.append(coord)
			continue
		request["priority"] = int(current.get("priority", 0))
		request["priority_class"] = int(
			current.get(
				"priority_class",
				request.get("priority_class", PRIORITY_CLASS_REVEAL),
			)
		)
		retained.append(request)
	_pending_requests = retained
	_reset_fairness_debt_without_waiters_locked()
	_consume_cancelled_request_permits_locked(removed_coords.size())
	_request_mutex.unlock()
	return removed_coords


func queue_spawn_request(
		seed: int,
		world_version: int,
		settings_packed: PackedFloat32Array,
		epoch: int,
) -> void:
	_request_mutex.lock()
	_pending_requests.append(
		{
			"kind": "spawn",
			"priority_class": PRIORITY_CLASS_INTERACTIVE,
			"enqueued_turn": _request_dispatch_turn,
			"enqueue_sequence": _claim_request_enqueue_sequence_locked(),
			"seed": seed,
			"world_version": world_version,
			"settings_packed": settings_packed.duplicate(),
			"epoch": epoch,
		},
	)
	_request_semaphore.post()
	_request_mutex.unlock()


func queue_overview_request(
		seed: int,
		world_version: int,
		settings_packed: PackedFloat32Array,
		epoch: int,
		layer_mask: int = 0,
		pixels_per_cell: int = 1,
) -> void:
	_request_mutex.lock()
	_pending_requests.append(
		{
			"kind": "overview",
			"priority_class": PRIORITY_CLASS_BACKGROUND,
			"enqueued_turn": _request_dispatch_turn,
			"enqueue_sequence": _claim_request_enqueue_sequence_locked(),
			"seed": seed,
			"world_version": world_version,
			"settings_packed": settings_packed.duplicate(),
			"epoch": epoch,
			"layer_mask": layer_mask,
			"pixels_per_cell": maxi(1, pixels_per_cell),
		},
	)
	_request_semaphore.post()
	_request_mutex.unlock()


func queue_mountain_raster_request(
		packets: Array,
		target_chunk: Vector2i,
		preset: Dictionary,
		top_image: Image,
		face_image: Image,
		epoch: int,
		revision: int,
		raster_purpose: StringName = &"chunk_hit",
) -> void:
	var source_chunks: Array[Vector2i] = []
	for packet_variant: Variant in packets:
		var packet: Dictionary = packet_variant as Dictionary
		source_chunks.append(packet.get("chunk_coord", Vector2i.ZERO) as Vector2i)
	var request_preset: Dictionary = preset.duplicate(true)
	if raster_purpose == &"chunk_hit":
		request_preset["runtime_ground_patch"] = false
	_request_mutex.lock()
	_pending_requests.append(
		{
			"kind": "mountain_raster",
			"priority_class": PRIORITY_CLASS_REVEAL,
			"enqueued_turn": _request_dispatch_turn,
			"enqueue_sequence": _claim_request_enqueue_sequence_locked(),
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
		},
	)
	_request_semaphore.post()
	_request_mutex.unlock()


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
		closed_halo: PackedByteArray = PackedByteArray(),
		dug_halo: PackedByteArray = PackedByteArray(),
		priority: int = 0,
		priority_class: int = PRIORITY_CLASS_REVEAL,
		band_field_params: Dictionary = { },
		noise_field_params: Dictionary = { },
) -> void:
	_request_mutex.lock()
	_pending_requests.append(
		{
			"kind": "mountain_halo_mask",
			"enqueued_turn": _request_dispatch_turn,
			"enqueue_sequence": _claim_request_enqueue_sequence_locked(),
			"solid_halo": solid_halo.duplicate(),
			"closed_halo": closed_halo.duplicate(),
			"dug_halo": dug_halo.duplicate(),
			"target_chunk": target_chunk,
			"mask_origin_world": mask_origin_world,
			"chunk_size_tiles": maxi(1, chunk_size_tiles),
			"tile_size_px": maxi(1, tile_size_px),
			"pixels_per_tile": maxi(1, pixels_per_tile),
			"epoch": epoch,
			"revision": revision,
			"reason": reason,
			"mask_purpose": mask_purpose,
			"priority": priority,
			"priority_class": priority_class,
			"band_field_params": band_field_params.duplicate(true),
			"noise_field_params": noise_field_params.duplicate(true),
			"queued_msec": Time.get_ticks_msec(),
		},
	)
	_request_semaphore.post()
	_request_mutex.unlock()


func drain_completed_packets(max_count: int) -> Array[Dictionary]:
	_result_mutex.lock()
	var drained: Array[Dictionary] = _drain_result_queue_locked(
		_completed_packets,
		&"packets",
		max_count,
	)
	_result_mutex.unlock()
	return drained


func drain_completed_spawn_results(max_count: int) -> Array[Dictionary]:
	_result_mutex.lock()
	var drained: Array[Dictionary] = _drain_result_queue_locked(
		_completed_spawn_results,
		&"spawn",
		max_count,
	)
	_result_mutex.unlock()
	return drained


func drain_completed_overviews(max_count: int) -> Array[Dictionary]:
	_result_mutex.lock()
	var drained: Array[Dictionary] = _drain_result_queue_locked(
		_completed_overviews,
		&"overviews",
		max_count,
	)
	_result_mutex.unlock()
	return drained


func drain_completed_mountain_rasters(max_count: int) -> Array[Dictionary]:
	_result_mutex.lock()
	var drained: Array[Dictionary] = _drain_result_queue_locked(
		_completed_mountain_rasters,
		&"mountain_rasters",
		max_count,
	)
	_result_mutex.unlock()
	return drained


func drain_completed_mountain_halo_masks(max_count: int) -> Array[Dictionary]:
	_result_mutex.lock()
	var drained: Array[Dictionary] = _drain_result_queue_locked(
		_completed_mountain_halo_masks,
		&"mountain_halo_masks",
		max_count,
	)
	_result_mutex.unlock()
	return drained


func drain_completed_grass_scatter_buffers(max_count: int) -> Array[Dictionary]:
	_result_mutex.lock()
	var drained: Array[Dictionary] = _drain_result_queue_locked(
		_completed_grass_scatter_buffers,
		&"grass_scatter",
		max_count,
	)
	_result_mutex.unlock()
	return drained


func drain_completed_object_presentation_buffers(max_count: int) -> Array[Dictionary]:
	_result_mutex.lock()
	var drained: Array[Dictionary] = _drain_result_queue_locked(
		_completed_object_presentation_buffers,
		&"object_presentation",
		max_count,
	)
	_result_mutex.unlock()
	return drained


func drain_completed_world_render_snapshots(max_count: int) -> Array[Dictionary]:
	_result_mutex.lock()
	var drained: Array[Dictionary] = _drain_result_queue_locked(
		_completed_world_render_snapshots,
		&"world_render_snapshot",
		max_count,
	)
	_result_mutex.unlock()
	return drained


func clear_queued_work() -> void:
	_request_mutex.lock()
	var cancelled_request_count: int = _pending_requests.size()
	_pending_requests.clear()
	_consume_cancelled_request_permits_locked(cancelled_request_count)
	_request_dispatch_turn = 0
	_next_request_enqueue_sequence = 0
	_reveal_dispatch_burst = 0
	_non_background_dispatch_burst = 0
	_request_mutex.unlock()
	_result_mutex.lock()
	_completed_packets.clear()
	_completed_spawn_results.clear()
	_completed_overviews.clear()
	_completed_mountain_rasters.clear()
	_completed_mountain_halo_masks.clear()
	_completed_grass_scatter_buffers.clear()
	_completed_object_presentation_buffers.clear()
	_completed_world_render_snapshots.clear()
	_completed_result_head_by_queue.clear()
	_result_mutex.unlock()


func has_pending_requests() -> bool:
	_request_mutex.lock()
	var has_pending: bool = not _pending_requests.is_empty()
	_request_mutex.unlock()
	return has_pending


func has_pending_request_kind(kind: StringName) -> bool:
	_request_mutex.lock()
	var has_pending: bool = false
	for request: Dictionary in _pending_requests:
		if StringName(str(request.get("kind", "packet"))) == kind:
			has_pending = true
			break
	_request_mutex.unlock()
	return has_pending


func has_completed_packets() -> bool:
	_result_mutex.lock()
	var has_completed: bool = _result_queue_has_unread_locked(_completed_packets, &"packets")
	_result_mutex.unlock()
	return has_completed


func has_completed_mountain_rasters() -> bool:
	_result_mutex.lock()
	var has_completed: bool = _result_queue_has_unread_locked(
		_completed_mountain_rasters,
		&"mountain_rasters",
	)
	_result_mutex.unlock()
	return has_completed


func has_completed_mountain_halo_masks() -> bool:
	_result_mutex.lock()
	var has_completed: bool = _result_queue_has_unread_locked(
		_completed_mountain_halo_masks,
		&"mountain_halo_masks",
	)
	_result_mutex.unlock()
	return has_completed


func has_completed_grass_scatter_buffers() -> bool:
	_result_mutex.lock()
	var has_completed: bool = _result_queue_has_unread_locked(
		_completed_grass_scatter_buffers,
		&"grass_scatter",
	)
	_result_mutex.unlock()
	return has_completed


func has_completed_object_presentation_buffers() -> bool:
	_result_mutex.lock()
	var has_completed: bool = _result_queue_has_unread_locked(
		_completed_object_presentation_buffers,
		&"object_presentation",
	)
	_result_mutex.unlock()
	return has_completed


func has_completed_world_render_snapshots() -> bool:
	_result_mutex.lock()
	var has_completed: bool = _result_queue_has_unread_locked(
		_completed_world_render_snapshots,
		&"world_render_snapshot",
	)
	_result_mutex.unlock()
	return has_completed


## Result publication is append-only. Draining advances a logical head and only
## compacts occasionally, so a frame never performs repeated O(n) front erases
## while worker publication is waiting on the same mutex.
func _drain_result_queue_locked(
		queue: Array[Dictionary],
		queue_id: StringName,
		max_count: int,
) -> Array[Dictionary]:
	var head: int = clampi(
		int(_completed_result_head_by_queue.get(queue_id, 0)),
		0,
		queue.size(),
	)
	var drain_count: int = mini(maxi(0, max_count), queue.size() - head)
	var drained: Array[Dictionary] = []
	drained.resize(drain_count)
	for drain_index: int in range(drain_count):
		drained[drain_index] = queue[head + drain_index]
	var next_head: int = head + drain_count
	if next_head >= queue.size():
		queue.clear()
		_completed_result_head_by_queue.erase(queue_id)
	elif next_head >= RESULT_QUEUE_COMPACT_MIN_HEAD \
			and next_head * 2 >= queue.size():
		var remaining_count: int = queue.size() - next_head
		for remaining_index: int in range(remaining_count):
			queue[remaining_index] = queue[next_head + remaining_index]
		queue.resize(remaining_count)
		_completed_result_head_by_queue.erase(queue_id)
	else:
		_completed_result_head_by_queue[queue_id] = next_head
	return drained


func _result_queue_has_unread_locked(
		queue: Array[Dictionary],
		queue_id: StringName,
) -> bool:
	var head: int = clampi(
		int(_completed_result_head_by_queue.get(queue_id, 0)),
		0,
		queue.size(),
	)
	return head < queue.size()


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
	# A packet batch is one native call and cannot be preempted after dispatch.
	# Keep it on one priority frontier so a far/background packet never rides
	# along ahead of a newly urgent reveal/presentation request.
	if int(candidate_request.get("priority_class", PRIORITY_CLASS_STREAMING)) \
			!= int(base_request.get("priority_class", PRIORITY_CLASS_STREAMING)):
		return false
	if int(candidate_request.get("priority", 0)) != int(base_request.get("priority", 0)):
		return false
	return _settings_packed_equal(
		candidate_request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array,
		base_request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array,
	)


func _settings_packed_equal(lhs: PackedFloat32Array, rhs: PackedFloat32Array) -> bool:
	# PackedArray equality is implemented by the engine. It compares the complete
	# immutable payload, so batching cannot rely on a collision-prone hash while
	# GDScript also avoids walking every settings float under the queue mutex.
	return lhs == rhs


func _call_generate_chunk_packets_batch(
		worker_world_core: Object,
		batch_requests: Array[Dictionary],
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
		base_request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array,
	)
	if packets_variant is Array:
		return packets_variant as Array
	push_error(
		"WorldChunkPacketBackend.generate_chunk_packets_batch returned non-array result for %d request(s)." % batch_requests.size(),
	)
	return []


func _call_resolve_world_foundation_spawn_tile(worker_world_core: Object, request: Dictionary) -> Dictionary:
	var result_variant: Variant = worker_world_core.call(
		"resolve_world_foundation_spawn_tile",
		int(request.get("seed", 0)),
		int(request.get("world_version", 0)),
		request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array,
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
		&"get_world_foundation_overview",
	)
	var overview_variant: Variant
	if overview_arg_count >= 2:
		overview_variant = worker_world_core.call(
			"get_world_foundation_overview",
			int(request.get("layer_mask", 0)),
			requested_pixels_per_cell,
		)
	else:
		overview_variant = worker_world_core.call(
			"get_world_foundation_overview",
			int(request.get("layer_mask", 0)),
		)
	if overview_variant is Image:
		var overview_image: Image = overview_variant as Image
		if overview_image != null and not overview_image.is_empty():
			if overview_arg_count == 1 and requested_pixels_per_cell > 1:
				overview_image = overview_image.duplicate() as Image
				overview_image.resize(
					overview_image.get_width() * requested_pixels_per_cell,
					overview_image.get_height() * requested_pixels_per_cell,
					Image.INTERPOLATE_BILINEAR,
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
		_completed_packets.append(
			{
				"success": false,
				"chunk_coord": chunk_coord,
				"request_chunk_coord": chunk_coord,
				"epoch": int(request.get("epoch", -1)),
				"message": message,
			},
		)
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
	var result: Dictionary = { }
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
			request.get("preset", { }) as Dictionary,
			request.get("top_image", null) as Image,
			request.get("face_image", null) as Image,
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
	var result: Dictionary = { }
	var started_msec: int = Time.get_ticks_msec()
	var mask_purpose: StringName = request.get("mask_purpose", &"mountain") as StringName
	var solid_halo: PackedByteArray = request.get("solid_halo", PackedByteArray()) as PackedByteArray
	var closed_halo: PackedByteArray = request.get("closed_halo", PackedByteArray()) as PackedByteArray
	var dug_halo: PackedByteArray = request.get("dug_halo", PackedByteArray()) as PackedByteArray
	var band_field_params: Dictionary = request.get("band_field_params", { }) as Dictionary
	var noise_field_params: Dictionary = request.get("noise_field_params", { }) as Dictionary
	# The construction roof C is requested only for excavated mountain chunks.
	# It reuses the exact same native contour recipe over the ownership halo, so
	# the roof stays byte-identical to the pre-dig silhouette without any C++
	# surface change.
	var construction_roof_requested: bool = mask_purpose == &"mountain" and not closed_halo.is_empty()
	if construction_roof_requested \
			and (closed_halo.size() != solid_halo.size() or dug_halo.size() != solid_halo.size()):
		result = {
			"success": false,
			"message": "Mountain closed/dug halos must match the remaining solid halo shape.",
		}
	elif not worker_world_core.has_method("build_mountain_halo_mask"):
		result = {
			"success": false,
			"message": "WorldCore.build_mountain_halo_mask is unavailable in this build.",
		}
	elif construction_roof_requested \
			and not worker_world_core.has_method("build_mountain_skylight_exposure"):
		result = {
			"success": false,
			"message": "WorldCore.build_mountain_skylight_exposure is unavailable in this build.",
		}
	elif not band_field_params.is_empty() \
			and not worker_world_core.has_method("build_mountain_band_field"):
		result = {
			"success": false,
			"message": "WorldCore.build_mountain_band_field is unavailable in this build.",
		}
	elif not noise_field_params.is_empty() \
			and not worker_world_core.has_method("build_mountain_noise_field"):
		result = {
			"success": false,
			"message": "WorldCore.build_mountain_noise_field is unavailable in this build.",
		}
	else:
		var mask_origin_world: Vector2 = request.get("mask_origin_world", Vector2.ZERO) as Vector2
		var result_variant: Variant = worker_world_core.call(
			"build_mountain_halo_mask",
			solid_halo,
			int(request.get("chunk_size_tiles", 1)),
			int(request.get("tile_size_px", 1)),
			int(request.get("pixels_per_tile", 1)),
			mask_origin_world.x,
			mask_origin_world.y,
		)
		if result_variant is Dictionary:
			result = result_variant as Dictionary
			var mask: PackedByteArray = result.get("mask", PackedByteArray()) as PackedByteArray
			var mask_width: int = int(result.get("width", 0))
			var mask_height: int = int(result.get("height", 0))
			var output_valid: bool = mask_width > 0 \
					and mask_height > 0 \
					and mask.size() == mask_width * mask_height
			if output_valid and not band_field_params.is_empty():
				output_valid = _append_mountain_band_fields(
					worker_world_core,
					result,
					mask,
					mask_width,
					mask_height,
					float(result.get("step_px", 0.0)),
					mask_origin_world,
					band_field_params,
				)
				if not output_valid:
					result["message"] = "Native mountain band-field output is malformed."
			if output_valid and not noise_field_params.is_empty():
				output_valid = _append_mountain_noise_fields(
					worker_world_core,
					result,
					mask_width,
					mask_height,
					float(result.get("step_px", 0.0)),
					mask_origin_world,
					noise_field_params,
				)
				if not output_valid:
					result["message"] = "Native mountain noise-field output is malformed."
			if output_valid and construction_roof_requested:
				var closed_variant: Variant = worker_world_core.call(
					"build_mountain_halo_mask",
					closed_halo,
					int(request.get("chunk_size_tiles", 1)),
					int(request.get("tile_size_px", 1)),
					int(request.get("pixels_per_tile", 1)),
					mask_origin_world.x,
					mask_origin_world.y,
				)
				var closed_result: Dictionary = { }
				var closed_mask: PackedByteArray = PackedByteArray()
				if closed_variant is Dictionary:
					closed_result = closed_variant as Dictionary
					closed_mask = closed_result.get(
						"mask",
						PackedByteArray(),
					) as PackedByteArray
				var closed_width: int = int(closed_result.get("width", 0))
				var closed_height: int = int(closed_result.get("height", 0))
				var closed_output_valid: bool = closed_width == mask_width \
						and closed_height == mask_height \
						and closed_mask.size() == closed_width * closed_height \
						and is_equal_approx(
							float(closed_result.get("step_px", 0.0)),
							float(result.get("step_px", 0.0)),
						) \
						and int(closed_result.get("halo_side", 0)) \
								== int(result.get("halo_side", 0))
				if closed_output_valid:
					if not band_field_params.is_empty():
						closed_output_valid = _append_mountain_band_fields(
							worker_world_core,
							result,
							closed_mask,
							closed_width,
							closed_height,
							float(closed_result.get("step_px", 0.0)),
							mask_origin_world,
							band_field_params,
						)
					if not closed_output_valid:
						output_valid = false
						result["message"] = "Native closed-mountain band-field output is malformed."
				if closed_output_valid:
					var reach_samples: int = MOUNTAIN_SKYLIGHT_REACH_TILES * int(
						request.get("pixels_per_tile", 1),
					)
					var skylight_started_usec: int = Time.get_ticks_usec()
					var exposure_variant: Variant = worker_world_core.call(
						"build_mountain_skylight_exposure",
						closed_mask,
						mask,
						mask_width,
						mask_height,
						float(result.get("step_px", 0.0)),
						reach_samples,
					)
					var skylight_elapsed_ms: float = float(
						Time.get_ticks_usec() - skylight_started_usec,
					) / 1000.0
					var exposure_result: Dictionary = { }
					if exposure_variant is Dictionary:
						exposure_result = exposure_variant as Dictionary
					var exposure_mask: PackedByteArray = exposure_result.get(
						"sky_exposure_mask",
						PackedByteArray(),
					) as PackedByteArray
					var exposure_output_valid: bool = exposure_mask.size() == mask_width * mask_height \
							and int(exposure_result.get("width", 0)) == mask_width \
							and int(exposure_result.get("height", 0)) == mask_height \
							and is_equal_approx(
								float(exposure_result.get("step_px", 0.0)),
								float(result.get("step_px", 0.0)),
							) \
							and int(exposure_result.get("reach_samples", 0)) == reach_samples
					if exposure_output_valid:
						result["closed_roof_mask"] = closed_mask
						result["dug_halo"] = dug_halo.duplicate()
						result["sky_exposure_mask"] = exposure_mask
						result["sky_exposure_reach_samples"] = reach_samples
						result["sky_exposure_source_sample_count"] = int(
							exposure_result.get("source_sample_count", 0),
						)
						result["sky_exposure_worker_elapsed_ms"] = skylight_elapsed_ms
					else:
						output_valid = false
						result["message"] = "Native mountain skylight exposure output is malformed."
				else:
					output_valid = false
					result["message"] = "Native mountain closed-roof mask output is malformed."
			result["success"] = output_valid
		else:
			result = {
				"success": false,
				"message": "Native mountain halo mask builder returned non-dictionary result.",
			}
	var completed_msec: int = Time.get_ticks_msec()
	result["epoch"] = int(request.get("epoch", -1))
	result["revision"] = int(request.get("revision", -1))
	result["reason"] = request.get("reason", &"worker") as StringName
	result["mask_purpose"] = mask_purpose
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


func _append_mountain_band_fields(
		worker_world_core: Object,
		result: Dictionary,
		mask: PackedByteArray,
		width: int,
		height: int,
		step_px: float,
		origin_world: Vector2,
		field_params: Dictionary,
) -> bool:
	for field_name_variant: Variant in field_params.keys():
		var field_name: StringName = field_name_variant as StringName
		var params: PackedFloat32Array = field_params.get(
			field_name,
			PackedFloat32Array(),
		) as PackedFloat32Array
		if params.size() < 4:
			return false
		var field_variant: Variant = worker_world_core.call(
			"build_mountain_band_field",
			mask,
			width,
			height,
			step_px,
			origin_world.x,
			origin_world.y,
			params,
		)
		if not field_variant is PackedByteArray:
			return false
		var field: PackedByteArray = field_variant as PackedByteArray
		if field.size() != width * height * 4:
			return false
		result[field_name] = field
	return true


func _append_mountain_noise_fields(
		worker_world_core: Object,
		result: Dictionary,
		width: int,
		height: int,
		step_px: float,
		origin_world: Vector2,
		field_params: Dictionary,
) -> bool:
	for field_name_variant: Variant in field_params.keys():
		var field_name: StringName = field_name_variant as StringName
		var params: PackedFloat32Array = field_params.get(
			field_name,
			PackedFloat32Array(),
		) as PackedFloat32Array
		if params.size() < 12:
			return false
		var field_variant: Variant = worker_world_core.call(
			"build_mountain_noise_field",
			width,
			height,
			step_px,
			origin_world.x,
			origin_world.y,
			params,
		)
		if not field_variant is PackedByteArray:
			return false
		var field: PackedByteArray = field_variant as PackedByteArray
		if field.size() != width * height * 4:
			return false
		result[field_name] = field
	return true


func _process_grass_scatter_request(worker_world_core: Object, request: Dictionary) -> void:
	var started_msec: int = Time.get_ticks_msec()
	var result: Dictionary = { }
	if not worker_world_core.has_method("build_grass_scatter_buffer"):
		result = {
			"success": false,
			"message": "WorldCore.build_grass_scatter_buffer is unavailable in this build.",
		}
	else:
		var result_variant: Variant = worker_world_core.call(
			"build_grass_scatter_buffer",
			int(request.get("seed", 0)),
			request.get("coord", Vector2i.ZERO) as Vector2i,
			request.get("terrain_ids", PackedInt32Array()) as PackedInt32Array,
			request.get("lake_flags", PackedByteArray()) as PackedByteArray,
			request.get("mountain_solid_halo", PackedByteArray()) as PackedByteArray,
			int(request.get("mountain_solid_halo_radius_tiles", 0)),
			request.get("grass_params", PackedFloat32Array()) as PackedFloat32Array,
		)
		if result_variant is Dictionary:
			result = result_variant as Dictionary
			result["success"] = not result.has("error")
			if result.has("error"):
				result["message"] = str(result.get("error", "Native grass scatter build failed."))
		else:
			result = {
				"success": false,
				"message": "Native grass scatter builder returned non-dictionary result.",
			}
	var completed_msec: int = Time.get_ticks_msec()
	result["epoch"] = int(request.get("epoch", -1))
	result["revision"] = int(request.get("revision", -1))
	result["target_chunk"] = request.get("coord", Vector2i.ZERO) as Vector2i
	result["queued_msec"] = int(request.get("queued_msec", started_msec))
	result["worker_started_msec"] = started_msec
	result["worker_elapsed_ms"] = completed_msec - started_msec
	result["queue_wait_ms"] = started_msec - int(request.get("queued_msec", started_msec))
	result["request_to_complete_ms"] = completed_msec - int(request.get("queued_msec", started_msec))
	_result_mutex.lock()
	_completed_grass_scatter_buffers.append(result)
	_result_mutex.unlock()


func _process_object_presentation_request(worker_world_core: Object, request: Dictionary) -> void:
	var started_msec: int = Time.get_ticks_msec()
	var result: Dictionary = { }
	if not worker_world_core.has_method("build_object_presentation_buffers"):
		result = {
			"success": false,
			"message": "WorldCore.build_object_presentation_buffers is unavailable in this build.",
		}
	else:
		var result_variant: Variant = worker_world_core.call(
			"build_object_presentation_buffers",
			request.get("object_kind", PackedByteArray()) as PackedByteArray,
			request.get("object_x", PackedByteArray()) as PackedByteArray,
			request.get("object_y", PackedByteArray()) as PackedByteArray,
			request.get("object_size", PackedByteArray()) as PackedByteArray,
			request.get("object_atlas", PackedByteArray()) as PackedByteArray,
			request.get("object_variant", PackedByteArray()) as PackedByteArray,
			request.get("object_flags", PackedByteArray()) as PackedByteArray,
			request.get("object_tint", PackedByteArray()) as PackedByteArray,
			request.get("object_phase", PackedByteArray()) as PackedByteArray,
			request.get("tree_metrics", PackedFloat32Array()) as PackedFloat32Array,
			request.get("rock_metrics", PackedFloat32Array()) as PackedFloat32Array,
			request.get("bush_metrics", PackedFloat32Array()) as PackedFloat32Array,
			request.get("params", PackedFloat32Array()) as PackedFloat32Array,
		)
		if result_variant is Dictionary:
			result = result_variant as Dictionary
			result["success"] = not result.has("error")
			if result.has("error"):
				result["message"] = str(result.get("error", "Native object presentation build failed."))
		else:
			result = {
				"success": false,
				"message": "Native object presentation builder returned non-dictionary result.",
			}
	var completed_msec: int = Time.get_ticks_msec()
	result["epoch"] = int(request.get("epoch", -1))
	result["revision"] = int(request.get("revision", -1))
	result["catalog_generation"] = int(request.get("catalog_generation", -1))
	result["target_chunk"] = request.get("coord", Vector2i.ZERO) as Vector2i
	result["queued_msec"] = int(request.get("queued_msec", started_msec))
	result["worker_started_msec"] = started_msec
	result["worker_elapsed_ms"] = completed_msec - started_msec
	result["queue_wait_ms"] = started_msec - int(request.get("queued_msec", started_msec))
	result["request_to_complete_ms"] = completed_msec - int(request.get("queued_msec", started_msec))
	_result_mutex.lock()
	_completed_object_presentation_buffers.append(result)
	_result_mutex.unlock()


func _process_world_render_snapshot_request(worker_world_core: Object, request: Dictionary) -> void:
	var started_msec: int = Time.get_ticks_msec()
	var result: Dictionary = { }
	if not worker_world_core.has_method("build_world_render_snapshot"):
		result = {
			"success": false,
			"error": "WorldCore.build_world_render_snapshot is unavailable in this build.",
		}
	else:
		var result_variant: Variant = worker_world_core.call(
			"build_world_render_snapshot",
			request.get("chunk_origins", PackedVector2Array()) as PackedVector2Array,
			request.get("object_results", []) as Array,
			request.get("grass_results", []) as Array,
			request.get("source_bindings", []) as Array,
			float(request.get("grass_lod_fraction", 1.0)),
		)
		if result_variant is Dictionary:
			result = result_variant as Dictionary
		else:
			result = {
				"success": false,
				"error": "Native world render snapshot builder returned non-Dictionary.",
			}
	var completed_msec: int = Time.get_ticks_msec()
	result["epoch"] = int(request.get("epoch", -1))
	result["request_generation"] = int(request.get("request_generation", -1))
	result["chunk_count"] = (request.get("chunk_origins", PackedVector2Array()) as PackedVector2Array).size()
	result["grass_lod_fraction"] = float(request.get("grass_lod_fraction", 1.0))
	result["worker_elapsed_ms"] = completed_msec - started_msec
	result["request_to_complete_ms"] = completed_msec - int(
		request.get("queued_msec", started_msec),
	)
	_result_mutex.lock()
	_completed_world_render_snapshots.append(result)
	_result_mutex.unlock()


func _take_highest_priority_request_locked() -> Dictionary:
	if _pending_requests.is_empty():
		return { }
	var best_index: int = -1
	var best_priority: int = 0
	var best_priority_class: int = PRIORITY_CLASS_STREAMING
	var best_enqueued_turn: int = _request_dispatch_turn
	var best_enqueue_sequence: int = 0
	var best_is_aged: bool = false
	var oldest_streaming_index: int = -1
	var oldest_streaming_turn: int = 1 << 60
	var oldest_streaming_priority: int = 2147483647
	var oldest_streaming_sequence: int = 1 << 60
	var streaming_count: int = 0
	var oldest_background_index: int = -1
	var oldest_background_turn: int = 1 << 60
	var oldest_background_priority: int = 2147483647
	var oldest_background_sequence: int = 1 << 60
	var background_count: int = 0
	var aging_turns: int = maxi(_pending_requests.size(), 1)
	# One queue walk collects normal priority, both fairness candidates, and the
	# waiter counts needed after removal. Dispatch must never turn one O(n)
	# selection into several serialized O(n) scans under the shared mutex.
	for request_index: int in range(_pending_requests.size()):
		var candidate: Dictionary = _pending_requests[request_index] as Dictionary
		var candidate_priority: int = int(candidate.get("priority", 0))
		var candidate_priority_class: int = int(
			candidate.get("priority_class", PRIORITY_CLASS_STREAMING)
		)
		var candidate_enqueued_turn: int = int(
			candidate.get("enqueued_turn", _request_dispatch_turn)
		)
		var candidate_enqueue_sequence: int = int(
			candidate.get("enqueue_sequence", request_index)
		)
		var candidate_is_aged: bool = \
				_request_dispatch_turn - candidate_enqueued_turn >= aging_turns
		if candidate_priority_class == PRIORITY_CLASS_STREAMING:
			streaming_count += 1
			if oldest_streaming_index < 0 \
					or candidate_enqueued_turn < oldest_streaming_turn \
					or (candidate_enqueued_turn == oldest_streaming_turn \
							and (candidate_priority < oldest_streaming_priority \
									or (candidate_priority == oldest_streaming_priority \
											and candidate_enqueue_sequence \
													< oldest_streaming_sequence))):
				oldest_streaming_index = request_index
				oldest_streaming_turn = candidate_enqueued_turn
				oldest_streaming_priority = candidate_priority
				oldest_streaming_sequence = candidate_enqueue_sequence
		elif candidate_priority_class == PRIORITY_CLASS_BACKGROUND:
			background_count += 1
			if oldest_background_index < 0 \
					or candidate_enqueued_turn < oldest_background_turn \
					or (candidate_enqueued_turn == oldest_background_turn \
							and (candidate_priority < oldest_background_priority \
									or (candidate_priority == oldest_background_priority \
											and candidate_enqueue_sequence \
													< oldest_background_sequence))):
				oldest_background_index = request_index
				oldest_background_turn = candidate_enqueued_turn
				oldest_background_priority = candidate_priority
				oldest_background_sequence = candidate_enqueue_sequence
		# Class is the normal hard ordering boundary. Aging prevents starvation
		# inside one class; bounded weighted-fair slots are applied once below,
		# independently of age, so an old background request cannot form a burst.
		if best_index < 0 \
				or candidate_priority_class < best_priority_class \
				or (candidate_priority_class == best_priority_class \
						and candidate_is_aged and not best_is_aged) \
				or (candidate_priority_class == best_priority_class \
						and candidate_is_aged == best_is_aged and candidate_is_aged \
						and (candidate_enqueued_turn < best_enqueued_turn \
								or (candidate_enqueued_turn == best_enqueued_turn \
										and candidate_enqueue_sequence < best_enqueue_sequence))) \
				or (candidate_priority_class == best_priority_class \
						and candidate_is_aged == best_is_aged and not candidate_is_aged \
						and candidate_priority < best_priority) \
				or (candidate_priority_class == best_priority_class \
						and candidate_is_aged == best_is_aged and not candidate_is_aged \
						and candidate_priority == best_priority \
						and (candidate_enqueued_turn < best_enqueued_turn \
								or (candidate_enqueued_turn == best_enqueued_turn \
										and candidate_enqueue_sequence < best_enqueue_sequence))):
			best_index = request_index
			best_priority = candidate_priority
			best_priority_class = candidate_priority_class
			best_enqueued_turn = candidate_enqueued_turn
			best_enqueue_sequence = candidate_enqueue_sequence
			best_is_aged = candidate_is_aged
	# Interactive work is never quota-delayed. Under a sustained reveal flood,
	# admit exactly one oldest streaming request after a bounded burst so vehicle
	# prefetch keeps making progress. Background gets a much smaller bounded share.
	var selected_by_fairness: bool = false
	if best_priority_class > PRIORITY_CLASS_INTERACTIVE:
		var fair_index: int = -1
		if _non_background_dispatch_burst >= MAX_NON_BACKGROUND_DISPATCH_BURST:
			fair_index = oldest_background_index
		if fair_index < 0 and _reveal_dispatch_burst >= MAX_REVEAL_DISPATCH_BURST:
			fair_index = oldest_streaming_index
		if fair_index >= 0:
			selected_by_fairness = true
			best_index = fair_index
			best_priority_class = int(
				_pending_requests[best_index].get(
					"priority_class",
					PRIORITY_CLASS_STREAMING,
				)
			)
	var request: Dictionary = _pending_requests[best_index] as Dictionary
	var selected_priority_class: int = int(
		request.get("priority_class", PRIORITY_CLASS_STREAMING)
	)
	_pending_requests.remove_at(best_index)
	if selected_by_fairness:
		# A fair slot is exactly one request, never a gateway to a packet batch.
		request["_fairness_slot"] = true
	_request_dispatch_turn += 1
	var streaming_is_waiting: bool = streaming_count \
			- (1 if selected_priority_class == PRIORITY_CLASS_STREAMING else 0) > 0
	if not streaming_is_waiting or selected_priority_class > PRIORITY_CLASS_REVEAL:
		_reveal_dispatch_burst = 0
	elif selected_priority_class == PRIORITY_CLASS_REVEAL:
		_reveal_dispatch_burst = mini(
			_reveal_dispatch_burst + 1,
			MAX_REVEAL_DISPATCH_BURST,
		)
	# Interactive dispatches neither accrue nor erase existing reveal debt while
	# a streaming request is genuinely waiting.
	var background_is_waiting: bool = background_count \
			- (1 if selected_priority_class == PRIORITY_CLASS_BACKGROUND else 0) > 0
	if not background_is_waiting or selected_priority_class >= PRIORITY_CLASS_BACKGROUND:
		_non_background_dispatch_burst = 0
	else:
		_non_background_dispatch_burst = mini(
			_non_background_dispatch_burst + 1,
			MAX_NON_BACKGROUND_DISPATCH_BURST,
		)
	return request


func _reset_fairness_debt_without_waiters_locked() -> void:
	var streaming_is_waiting: bool = false
	var background_is_waiting: bool = false
	for request: Dictionary in _pending_requests:
		var priority_class: int = int(
			request.get("priority_class", PRIORITY_CLASS_STREAMING)
		)
		streaming_is_waiting = streaming_is_waiting \
				or priority_class == PRIORITY_CLASS_STREAMING
		background_is_waiting = background_is_waiting \
				or priority_class == PRIORITY_CLASS_BACKGROUND
		if streaming_is_waiting and background_is_waiting:
			break
	if not streaming_is_waiting:
		_reveal_dispatch_burst = 0
	if not background_is_waiting:
		_non_background_dispatch_burst = 0


func _claim_request_enqueue_sequence_locked() -> int:
	var sequence: int = _next_request_enqueue_sequence
	_next_request_enqueue_sequence += 1
	return sequence


## Queue insertion posts while holding the same mutex, so every still-available
## permit corresponds to an entry visible here. A worker may already own a
## permit; try_wait then fails and that worker harmlessly observes the pruned
## queue. Never blocking here keeps cancellation independent of worker progress.
func _consume_cancelled_request_permits_locked(cancelled_count: int) -> void:
	for cancelled_index: int in range(cancelled_count):
		if not _request_semaphore.try_wait():
			break


func _worker_loop() -> void:
	var worker_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(worker_world_core != null, "WorldCore required inside worker thread")
	while true:
		_request_semaphore.wait()
		var base_request: Dictionary = { }
		_request_mutex.lock()
		if _worker_should_exit:
			_request_mutex.unlock()
			return
		if not _pending_requests.is_empty():
			base_request = _take_highest_priority_request_locked()
		_request_mutex.unlock()
		if base_request.is_empty():
			continue
		var is_fairness_slot: bool = bool(base_request.get("_fairness_slot", false))
		base_request.erase("_fairness_slot")
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
		if str(base_request.get("kind", "packet")) == "grass_scatter":
			_process_grass_scatter_request(worker_world_core, base_request)
			continue
		if str(base_request.get("kind", "packet")) == "object_presentation":
			_process_object_presentation_request(worker_world_core, base_request)
			continue
		if str(base_request.get("kind", "packet")) == "world_render_snapshot":
			_process_world_render_snapshot_request(worker_world_core, base_request)
			continue
		_request_mutex.lock()
		var batch_requests: Array[Dictionary] = _take_packet_batch_locked(
			base_request,
			is_fairness_slot,
		)
		_request_mutex.unlock()
		_process_packet_batch_strict(worker_world_core, batch_requests)


## Detaches a packet batch with one linear pass and no front/index erases. The
## queue remains untouched if a more urgent request appeared after base
## selection. Compatibility uses the complete native PackedArray equality
## above, never a hash-only key.
func _take_packet_batch_locked(
		base_request: Dictionary,
		is_fairness_slot: bool,
) -> Array[Dictionary]:
	var batch_requests: Array[Dictionary] = [base_request]
	if is_fairness_slot or _pending_requests.is_empty() or _max_batch_size <= 1:
		return batch_requests

	var compatible_candidates: Array[Dictionary] = []
	var retained_requests: Array[Dictionary] = []
	var has_request_ahead: bool = false
	var streaming_is_waiting: bool = false
	var background_is_waiting: bool = false
	var max_additional: int = _max_batch_size - 1
	var base_class: int = int(
		base_request.get("priority_class", PRIORITY_CLASS_STREAMING)
	)
	var base_priority: int = int(base_request.get("priority", 0))
	var incompatible_frontier_sequence: int = 1 << 60
	for request_index: int in range(_pending_requests.size()):
		var request: Dictionary = _pending_requests[request_index] as Dictionary
		var request_class: int = int(
			request.get("priority_class", PRIORITY_CLASS_STREAMING)
		)
		var request_priority: int = int(request.get("priority", 0))
		var request_sequence: int = int(
			request.get("enqueue_sequence", request_index)
		)
		streaming_is_waiting = streaming_is_waiting \
				or request_class == PRIORITY_CLASS_STREAMING
		background_is_waiting = background_is_waiting \
				or request_class == PRIORITY_CLASS_BACKGROUND
		has_request_ahead = has_request_ahead \
				or _request_is_ahead_of(base_request, request)
		var is_compatible: bool = _requests_are_batch_compatible(base_request, request)
		if request_class == base_class and request_priority == base_priority \
				and not is_compatible:
			incompatible_frontier_sequence = mini(
				incompatible_frontier_sequence,
				request_sequence,
			)
		if not is_compatible:
			retained_requests.append(request)
			continue
		# Physical queue order is deliberately not scheduling truth. Keep only the
		# earliest bounded compatible handles by monotonic enqueue sequence; this
		# remains one O(n) queue pass with O(batch_max) insertion work.
		var insertion_index: int = compatible_candidates.size()
		for candidate_index: int in range(compatible_candidates.size()):
			var candidate_sequence: int = int(
				compatible_candidates[candidate_index].get(
					"enqueue_sequence",
					candidate_index,
				)
			)
			if request_sequence < candidate_sequence:
				insertion_index = candidate_index
				break
		if insertion_index >= max_additional:
			retained_requests.append(request)
			continue
		compatible_candidates.insert(insertion_index, request)
		if compatible_candidates.size() > max_additional:
			retained_requests.append(compatible_candidates.pop_back() as Dictionary)

	if has_request_ahead or compatible_candidates.is_empty():
		return batch_requests

	# An exact-priority incompatible request is a stable FIFO barrier. A later
	# compatible packet may not jump across it merely because native batching
	# would accept its generation payload.
	var frontier_candidate_count: int = 0
	for candidate: Dictionary in compatible_candidates:
		if int(candidate.get("enqueue_sequence", frontier_candidate_count)) \
				>= incompatible_frontier_sequence:
			break
		frontier_candidate_count += 1
	if frontier_candidate_count <= 0:
		return batch_requests
	var allowed_additional: int = frontier_candidate_count
	if background_is_waiting and base_class < PRIORITY_CLASS_BACKGROUND:
		allowed_additional = mini(
			allowed_additional,
			maxi(0, MAX_NON_BACKGROUND_DISPATCH_BURST - _non_background_dispatch_burst),
		)
	if streaming_is_waiting and base_class == PRIORITY_CLASS_REVEAL:
		allowed_additional = mini(
			allowed_additional,
			maxi(0, MAX_REVEAL_DISPATCH_BURST - _reveal_dispatch_burst),
		)
	if allowed_additional <= 0:
		return batch_requests

	# Compatible overflow keeps both age and sequence. Even if the compact backing
	# array changes position, stable FIFO is defined by enqueue_sequence.
	for candidate_index: int in range(compatible_candidates.size()):
		var candidate: Dictionary = compatible_candidates[candidate_index]
		if candidate_index < allowed_additional:
			batch_requests.append(candidate)
		else:
			retained_requests.append(candidate)
	_pending_requests = retained_requests
	_record_additional_batch_dispatches_locked(
		base_class,
		allowed_additional,
		streaming_is_waiting,
		background_is_waiting,
	)
	_consume_cancelled_request_permits_locked(allowed_additional)
	return batch_requests


func _record_additional_batch_dispatches_locked(
		priority_class: int,
		dispatch_count: int,
		streaming_is_waiting: bool,
		background_is_waiting: bool,
) -> void:
	if dispatch_count <= 0:
		return
	_request_dispatch_turn += dispatch_count
	if not streaming_is_waiting or priority_class > PRIORITY_CLASS_REVEAL:
		_reveal_dispatch_burst = 0
	elif priority_class == PRIORITY_CLASS_REVEAL:
		_reveal_dispatch_burst = mini(
			_reveal_dispatch_burst + dispatch_count,
			MAX_REVEAL_DISPATCH_BURST,
		)
	if not background_is_waiting or priority_class >= PRIORITY_CLASS_BACKGROUND:
		_non_background_dispatch_burst = 0
	else:
		_non_background_dispatch_burst = mini(
			_non_background_dispatch_burst + dispatch_count,
			MAX_NON_BACKGROUND_DISPATCH_BURST,
		)


func _request_is_ahead_of(reference: Dictionary, candidate: Dictionary) -> bool:
	var reference_class: int = int(
		reference.get("priority_class", PRIORITY_CLASS_STREAMING)
	)
	var reference_priority: int = int(reference.get("priority", 0))
	var candidate_class: int = int(
		candidate.get("priority_class", PRIORITY_CLASS_STREAMING)
	)
	var candidate_priority: int = int(candidate.get("priority", 0))
	return candidate_class < reference_class \
			or (candidate_class == reference_class and candidate_priority < reference_priority)
