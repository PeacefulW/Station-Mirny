extends SceneTree

const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const BACKEND_SOURCE_PATH: String = "res://core/systems/world/world_chunk_packet_backend.gd"

class FakeGrassWorldCore:
	extends RefCounted

	var derived_halo: PackedByteArray = PackedByteArray([1, 0, 1, 1, 0])
	var halo_call_count: int = 0
	var scatter_call_count: int = 0
	var last_packets: Array = []


	func build_chunk_halo_fields(packets: Array, _radius: int) -> Dictionary:
		halo_call_count += 1
		last_packets = packets
		return {
			"success": true,
			"remaining_halo": derived_halo,
		}


	func build_grass_scatter_buffer(
			_seed: int,
			_coord: Vector2i,
			_terrain_ids: PackedInt32Array,
			_lake_flags: PackedByteArray,
			mountain_halo: PackedByteArray,
			halo_radius: int,
			_params: PackedFloat32Array,
	) -> Dictionary:
		scatter_call_count += 1
		return {
			"instance_count": mountain_halo.size(),
			"observed_mountain_halo": mountain_halo,
			"observed_halo_radius": halo_radius,
		}


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_packet_coalescing_replaces_generation_snapshot()
	_test_object_request_uses_immutable_packed_handles()
	_test_grass_worker_derives_halo_from_immutable_packet_window()
	_test_grass_worker_halo_rejects_malformed_envelopes_once()
	_test_packet_batch_is_exact_and_fairness_bounded()
	_test_incompatible_tie_closes_packet_batch_frontier()
	_test_quota_overflow_preserves_logical_fifo()
	_test_result_queue_partial_drain_compaction_and_append_order()
	_test_backend_source_guards()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	print("world_chunk_packet_backend_contract_test: PASS")
	quit(0)


func _test_packet_coalescing_replaces_generation_snapshot() -> void:
	var backend := WorldChunkPacketBackend.new()
	var coord := Vector2i(4, -7)
	backend.queue_packet_request(
		coord,
		11,
		3,
		PackedFloat32Array([1.0, 2.0]),
		9,
		17,
		WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING,
	)
	var original_turn: int = int(backend._pending_requests[0].get("enqueued_turn", -1))
	var original_sequence: int = int(
		backend._pending_requests[0].get("enqueue_sequence", -1)
	)
	backend.queue_packet_request(
		coord,
		99,
		8,
		PackedFloat32Array([8.0, 13.0, 21.0]),
		9,
		2,
		WorldChunkPacketBackend.PRIORITY_CLASS_REVEAL,
	)
	_expect(backend._pending_requests.size() == 1, "packet replacement must keep one queue entry")
	var queued: Dictionary = backend._pending_requests[0] as Dictionary
	_expect(int(queued.get("seed", -1)) == 99, "packet replacement must refresh seed")
	_expect(int(queued.get("world_version", -1)) == 8, "packet replacement must refresh version")
	_expect(
		(queued.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array) \
				== PackedFloat32Array([8.0, 13.0, 21.0]),
		"packet replacement must refresh the complete settings payload",
	)
	_expect(int(queued.get("priority", -1)) == 2, "packet replacement must refresh priority")
	_expect(
		int(queued.get("priority_class", -1)) == WorldChunkPacketBackend.PRIORITY_CLASS_REVEAL,
		"packet replacement must refresh priority class",
	)
	_expect(
		int(queued.get("enqueued_turn", -2)) == original_turn,
		"packet replacement must preserve starvation age",
	)
	_expect(
		int(queued.get("enqueue_sequence", -2)) == original_sequence,
		"packet replacement must preserve stable FIFO sequence",
	)
	_expect(backend._request_semaphore.try_wait(), "coalesced packet must retain one permit")
	_expect(not backend._request_semaphore.try_wait(), "coalesced packet must not post a second permit")


func _test_object_request_uses_immutable_packed_handles() -> void:
	var backend := WorldChunkPacketBackend.new()
	var kinds := PackedByteArray([4, 7])
	var xs := PackedByteArray([10, 20])
	var tree_metrics := PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var rock_metrics := PackedFloat32Array([6.0, 7.0, 8.0, 9.0, 10.0])
	var params := PackedFloat32Array([0.25, 16.0, 64.0])
	var packet := {
		"object_kind": kinds,
		"object_local_x_px_q4": xs,
		"object_local_y_px_q4": PackedByteArray([30, 40]),
		"object_size_px": PackedByteArray([180, 24]),
		"object_atlas_index": PackedByteArray([0, 0]),
		"object_variant": PackedByteArray([1, 2]),
		"object_flags": PackedByteArray([0, 0]),
		"object_tint": PackedByteArray([255, 128]),
		"object_phase": PackedByteArray([3, 4]),
	}
	backend.queue_object_presentation_request(
		Vector2i(3, 5),
		packet,
		tree_metrics,
		rock_metrics,
		params,
		12,
		7,
		4,
	)
	var queued: Dictionary = backend._pending_requests[0] as Dictionary
	# Queue ownership is ref-counted and survives source-variable rebinding. Direct
	# mutation of a shared PackedArray is deliberately outside the immutable-owner
	# contract; the source guard below proves enqueue does not hide a deep copy.
	packet.clear()
	kinds = PackedByteArray([2])
	xs = PackedByteArray([99])
	tree_metrics = PackedFloat32Array([42.0])
	rock_metrics = PackedFloat32Array([43.0])
	params = PackedFloat32Array([44.0])
	_expect(
		(queued.get("object_kind", PackedByteArray()) as PackedByteArray)[0] == 4,
		"queued object kinds must survive source-variable rebinding",
	)
	_expect(
		(queued.get("object_x", PackedByteArray()) as PackedByteArray)[0] == 10,
		"queued coordinates must survive source-variable rebinding",
	)
	_expect(
		(queued.get("object_y", PackedByteArray()) as PackedByteArray)[0] == 30,
		"queued object channels must survive source packet eviction",
	)
	_expect(
		is_equal_approx(
			(queued.get("tree_metrics", PackedFloat32Array()) as PackedFloat32Array)[0],
			1.0,
		),
		"queued tree metrics must survive source-variable rebinding",
	)
	_expect(
		is_equal_approx(
			(queued.get("rock_metrics", PackedFloat32Array()) as PackedFloat32Array)[0],
			6.0,
		),
		"queued rock metrics must survive source-variable rebinding",
	)
	_expect(
		is_equal_approx(
			(queued.get("params", PackedFloat32Array()) as PackedFloat32Array)[0],
			0.25,
		),
		"queued parameters must survive source-variable rebinding",
	)


func _test_grass_worker_derives_halo_from_immutable_packet_window() -> void:
	var fake := FakeGrassWorldCore.new()
	var coord := Vector2i(-3, 8)
	var terrain_ids := PackedInt32Array([0, 0, 0, 0])
	var lake_flags := PackedByteArray([0, 0, 0, 0])
	var params := PackedFloat32Array([1.0, 2.0])
	var explicit_backend := WorldChunkPacketBackend.new()
	explicit_backend.queue_grass_scatter_request(
		coord,
		41,
		terrain_ids,
		lake_flags,
		fake.derived_halo,
		2,
		params,
		13,
		17,
	)
	var explicit_request: Dictionary = _take_only_queued_request(explicit_backend)
	explicit_backend._process_grass_scatter_request(fake, explicit_request)
	var explicit_result: Dictionary = \
			explicit_backend.drain_completed_grass_scatter_buffers(1)[0]

	var shared_channel := PackedByteArray([7, 9])
	var packets: Array = []
	for packet_index: int in range(9):
		packets.append(
			{ "halo_source_present": false } \
					if packet_index < 3 \
					else { "halo_source_present": true, "test_channel": shared_channel }
		)
	var derived_backend := WorldChunkPacketBackend.new()
	derived_backend.queue_grass_scatter_request(
		coord,
		41,
		terrain_ids,
		lake_flags,
		PackedByteArray(),
		2,
		params,
		13,
		17,
		0,
		WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING,
		packets,
	)
	var derived_request: Dictionary = _take_only_queued_request(derived_backend)
	var owned_packets: Array = derived_request.get("halo_packets_3x3", []) as Array
	packets[4].clear()
	packets.clear()
	shared_channel = PackedByteArray([99])
	_expect(owned_packets.size() == 9, "grass queue must own the fixed packet-window shell")
	_expect(
		(owned_packets[4] as Dictionary).has("test_channel"),
		"grass queue must shallow-copy packet dictionaries before caller mutation",
	)
	_expect(
		(owned_packets[4] as Dictionary).get("test_channel") == PackedByteArray([7, 9]),
		"grass queue must retain immutable PackedArray handles without deep copying",
	)
	derived_backend._process_grass_scatter_request(fake, derived_request)
	var derived_result: Dictionary = \
			derived_backend.drain_completed_grass_scatter_buffers(1)[0]

	_expect(fake.halo_call_count == 1, "empty explicit halo must derive exactly once on worker")
	_expect(fake.scatter_call_count == 2, "explicit and derived requests must each scatter once")
	_expect(
		fake.last_packets.size() == 9 \
				and not bool((fake.last_packets[0] as Dictionary).get("halo_source_present", true)),
		"worker derivation must preserve row-major void boundary envelopes",
	)
	_expect(
		derived_result.get("observed_mountain_halo") \
				== explicit_result.get("observed_mountain_halo"),
		"worker-derived and explicit halo paths must feed identical scatter bytes",
	)
	_expect(
		int(derived_result.get("instance_count", -1)) \
				== int(explicit_result.get("instance_count", -2)),
		"worker-derived and explicit halo paths must preserve scatter output metadata",
	)
	for metadata_key: String in ["epoch", "revision", "target_chunk"]:
		_expect(
			derived_result.get(metadata_key) == explicit_result.get(metadata_key),
			"worker-derived halo must preserve %s metadata" % metadata_key,
		)
	_expect(
		derived_result.get("mountain_halo_source") == &"worker_3x3" \
				and bool(derived_result.get("mountain_halo_derived", false)),
		"derived completion must report its worker halo source",
	)
	_expect(
		explicit_result.get("mountain_halo_source") == &"explicit" \
				and not bool(explicit_result.get("mountain_halo_derived", true)),
		"legacy explicit completion must retain explicit halo metadata",
	)


func _test_grass_worker_halo_rejects_malformed_envelopes_once() -> void:
	var fake := FakeGrassWorldCore.new()
	var backend := WorldChunkPacketBackend.new()
	var malformed_packets: Array = []
	for packet_index: int in range(8):
		malformed_packets.append({ "halo_source_present": false })
	backend.queue_grass_scatter_request(
		Vector2i(6, 4),
		2,
		PackedInt32Array(),
		PackedByteArray(),
		PackedByteArray(),
		2,
		PackedFloat32Array(),
		23,
		29,
		0,
		WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING,
		malformed_packets,
	)
	backend._process_grass_scatter_request(fake, _take_only_queued_request(backend))
	var results: Array[Dictionary] = backend.drain_completed_grass_scatter_buffers(8)
	_expect(results.size() == 1, "malformed halo input must produce one bounded completion")
	var result: Dictionary = results[0]
	_expect(not bool(result.get("success", true)), "malformed halo input must fail explicitly")
	_expect(
		str(result.get("message", "")).contains("exactly nine"),
		"malformed halo failure must identify the fixed-window contract",
	)
	_expect(
		int(result.get("epoch", -1)) == 23 \
				and int(result.get("revision", -1)) == 29 \
				and result.get("target_chunk") == Vector2i(6, 4),
		"malformed halo failure must retain stale-result rejection metadata",
	)
	_expect(
		result.get("mountain_halo_source") == &"worker_3x3" \
				and not bool(result.get("mountain_halo_derived", true)),
		"malformed halo failure must report an attempted worker derivation",
	)
	_expect(
		fake.halo_call_count == 0 and fake.scatter_call_count == 0,
		"invalid envelope count must fail before native halo or scatter calls",
	)
	malformed_packets.append(71)
	backend.queue_grass_scatter_request(
		Vector2i(6, 4),
		2,
		PackedInt32Array(),
		PackedByteArray(),
		PackedByteArray(),
		2,
		PackedFloat32Array(),
		23,
		30,
		0,
		WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING,
		malformed_packets,
	)
	backend._process_grass_scatter_request(fake, _take_only_queued_request(backend))
	var type_failure: Dictionary = backend.drain_completed_grass_scatter_buffers(1)[0]
	_expect(
		not bool(type_failure.get("success", true)) \
				and str(type_failure.get("message", "")).contains("packet 8"),
		"fixed worker window must reject non-dictionary packet envelopes",
	)
	_expect(
		fake.halo_call_count == 0 and fake.scatter_call_count == 0,
		"invalid envelope type must fail before native halo or scatter calls",
	)


func _take_only_queued_request(backend: WorldChunkPacketBackend) -> Dictionary:
	_expect(backend._pending_requests.size() == 1, "test backend must contain one request")
	_expect(backend._request_semaphore.try_wait(), "test request must own one semaphore permit")
	return backend._pending_requests.pop_back() as Dictionary


func _test_packet_batch_is_exact_and_fairness_bounded() -> void:
	var backend := WorldChunkPacketBackend.new()
	backend.set_max_batch_size(12)
	var settings := PackedFloat32Array([1.0, 2.0, 3.0])
	for packet_index: int in range(5):
		backend.queue_packet_request(
			Vector2i(packet_index, 0),
			71,
			6,
			settings,
			4,
			0,
			WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING,
		)
	backend.queue_packet_request(
		Vector2i(99, 0),
		71,
		6,
		PackedFloat32Array([1.0, 2.0, 4.0]),
		4,
		0,
		WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING,
	)
	backend.queue_overview_request(71, 6, settings, 4)
	backend._non_background_dispatch_burst = \
			WorldChunkPacketBackend.MAX_NON_BACKGROUND_DISPATCH_BURST - 2

	# Simulate the worker permit consumed immediately before base selection.
	_expect(backend._request_semaphore.try_wait(), "base request must own a permit")
	var base: Dictionary = backend._take_highest_priority_request_locked()
	_expect(str(base.get("kind", "")) == "packet", "streaming packet must win normal priority")
	_expect(
		backend._non_background_dispatch_burst \
				== WorldChunkPacketBackend.MAX_NON_BACKGROUND_DISPATCH_BURST - 1,
		"base dispatch must accrue one background fairness unit",
	)
	var batch: Array[Dictionary] = backend._take_packet_batch_locked(base, false)
	_expect(
		batch.size() == 2,
		"batch must stop exactly at the remaining background fairness allowance",
	)
	_expect(
		backend._non_background_dispatch_burst \
				== WorldChunkPacketBackend.MAX_NON_BACKGROUND_DISPATCH_BURST,
		"every detached batch member must accrue fairness debt",
	)
	for request: Dictionary in batch:
		_expect(
			(request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array) \
					== settings,
			"batch compatibility must compare the complete settings payload",
		)
	var incompatible_retained: bool = false
	for request: Dictionary in backend._pending_requests:
		if (request.get("coord", Vector2i.ZERO) as Vector2i) == Vector2i(99, 0):
			incompatible_retained = true
			break
	_expect(incompatible_retained, "different settings must never join a packet batch")
	var fair_request: Dictionary = backend._take_highest_priority_request_locked()
	_expect(
		str(fair_request.get("kind", "")) == "overview" \
				and bool(fair_request.get("_fairness_slot", false)),
		"the request after a full non-background burst must be one background slot",
	)


func _test_incompatible_tie_closes_packet_batch_frontier() -> void:
	var backend := WorldChunkPacketBackend.new()
	backend.set_max_batch_size(8)
	var settings_a := PackedFloat32Array([1.0, 2.0])
	var settings_b := PackedFloat32Array([1.0, 3.0])
	backend.queue_packet_request(Vector2i(0, 0), 5, 2, settings_a, 7, 0)
	backend.queue_packet_request(Vector2i(1, 0), 5, 2, settings_b, 7, 0)
	backend.queue_packet_request(Vector2i(2, 0), 5, 2, settings_a, 7, 0)
	_expect(backend._request_semaphore.try_wait(), "frontier base must own one permit")
	var base: Dictionary = backend._take_highest_priority_request_locked()
	_expect(
		(base.get("coord", Vector2i(-1, -1)) as Vector2i) == Vector2i(0, 0),
		"stable FIFO must select the earliest exact-priority base",
	)
	var batch: Array[Dictionary] = backend._take_packet_batch_locked(base, false)
	_expect(
		batch.size() == 1,
		"an incompatible exact-priority tie must close the packet batch frontier",
	)
	var next_request: Dictionary = backend._take_highest_priority_request_locked()
	_expect(
		(next_request.get("coord", Vector2i(-1, -1)) as Vector2i) == Vector2i(1, 0),
		"a later compatible packet must not jump over an incompatible FIFO tie",
	)


func _test_quota_overflow_preserves_logical_fifo() -> void:
	var backend := WorldChunkPacketBackend.new()
	backend.set_max_batch_size(8)
	var settings_a := PackedFloat32Array([4.0, 5.0])
	var settings_b := PackedFloat32Array([4.0, 6.0])
	backend.queue_packet_request(Vector2i(0, 1), 8, 3, settings_a, 11, 0)
	backend.queue_packet_request(Vector2i(1, 1), 8, 3, settings_a, 11, 0)
	backend.queue_packet_request(Vector2i(2, 1), 8, 3, settings_a, 11, 0)
	backend.queue_packet_request(Vector2i(3, 1), 8, 3, settings_b, 11, 0)
	backend.queue_packet_request(Vector2i(4, 1), 8, 3, settings_a, 11, 0)
	backend.queue_overview_request(8, 3, settings_a, 11)
	backend._non_background_dispatch_burst = \
			WorldChunkPacketBackend.MAX_NON_BACKGROUND_DISPATCH_BURST - 2
	_expect(backend._request_semaphore.try_wait(), "quota base must own one permit")
	var base: Dictionary = backend._take_highest_priority_request_locked()
	var batch: Array[Dictionary] = backend._take_packet_batch_locked(base, false)
	_expect(batch.size() == 2, "quota boundary must admit exactly one additional packet")
	_expect(
		(batch[1].get("coord", Vector2i(-1, -1)) as Vector2i) == Vector2i(1, 1),
		"quota-limited batch must take the earliest compatible tie",
	)
	var fair_request: Dictionary = backend._take_highest_priority_request_locked()
	_expect(
		str(fair_request.get("kind", "")) == "overview",
		"full quota debt must dispatch the waiting background slot first",
	)
	var first_overflow: Dictionary = backend._take_highest_priority_request_locked()
	var incompatible_tie: Dictionary = backend._take_highest_priority_request_locked()
	_expect(
		(first_overflow.get("coord", Vector2i(-1, -1)) as Vector2i) == Vector2i(2, 1),
		"quota overflow must keep its original logical FIFO position",
	)
	_expect(
		(incompatible_tie.get("coord", Vector2i(-1, -1)) as Vector2i) == Vector2i(3, 1),
		"mixed exact-priority ties must remain FIFO after quota partitioning",
	)


func _test_result_queue_partial_drain_compaction_and_append_order() -> void:
	var backend := WorldChunkPacketBackend.new()
	for result_index: int in range(150):
		backend._completed_packets.append({"index": result_index})
	_assert_result_range(backend.drain_completed_packets(20), 0, 20, "first partial drain")
	for result_index: int in range(150, 160):
		backend._completed_packets.append({"index": result_index})
	_assert_result_range(backend.drain_completed_packets(50), 20, 50, "second partial drain")
	_assert_result_range(backend.drain_completed_packets(20), 70, 20, "compacting drain")
	_expect(
		int(backend._completed_packets[0].get("index", -1)) == 90,
		"logical-head compaction must retain the first unread result",
	)
	backend._completed_packets.append({"index": 160})
	_assert_result_range(
		backend.drain_completed_packets(1000),
		90,
		71,
		"append after compaction",
	)
	_expect(not backend.has_completed_packets(), "fully drained packet queue must report empty")
	_expect(backend._completed_packets.is_empty(), "fully drained packet storage must release entries")

	backend._completed_object_presentation_buffers.append({"index": 700})
	var object_results: Array[Dictionary] = \
			backend.drain_completed_object_presentation_buffers(1)
	_expect(
		object_results.size() == 1 and int(object_results[0].get("index", -1)) == 700,
		"logical heads must remain independent for every result queue",
	)


func _test_backend_source_guards() -> void:
	var source: String = FileAccess.get_file_as_string(BACKEND_SOURCE_PATH)
	_expect(not source.is_empty(), "backend source must be readable for performance contract checks")
	_expect(
		not source.contains("pop_front()"),
		"backend result queues must not regress to repeated front erases",
	)
	var object_enqueue_body: String = _function_body(source, "queue_object_presentation_request")
	_expect(not object_enqueue_body.is_empty(), "object enqueue function must exist")
	_expect(
		not object_enqueue_body.contains(".duplicate("),
		"object enqueue must retain immutable handles without a hidden main-thread deep copy",
	)
	var grass_enqueue_body: String = _function_body(source, "queue_grass_scatter_request")
	_expect(not grass_enqueue_body.is_empty(), "grass enqueue function must exist")
	_expect(
		not grass_enqueue_body.contains("terrain_ids.duplicate") \
				and not grass_enqueue_body.contains("lake_flags.duplicate") \
				and not grass_enqueue_body.contains("mountain_solid_halo.duplicate") \
				and not grass_enqueue_body.contains("grass_params.duplicate"),
		"grass enqueue must retain immutable packed handles without deep copies",
	)
	_expect(
		grass_enqueue_body.contains("duplicate(false)"),
		"grass packet envelopes must own shallow dictionary snapshots",
	)
	var batch_body: String = _function_body(source, "_take_packet_batch_locked")
	_expect(not batch_body.is_empty(), "linear packet batch helper must exist")
	_expect(
		not batch_body.contains("while ") and not batch_body.contains("remove_at("),
		"packet batch detachment must remain one linear pass without repeated erases",
	)
	_expect(
		batch_body.contains("incompatible_frontier_sequence") \
				and batch_body.contains("enqueue_sequence"),
		"packet batch must preserve the exact-priority FIFO frontier",
	)
	var settings_body: String = _function_body(source, "_settings_packed_equal")
	_expect(
		settings_body.contains("return lhs == rhs") and not settings_body.contains("for "),
		"settings compatibility must stay in native PackedArray equality",
	)
	var priority_body: String = _function_body(source, "_take_highest_priority_request_locked")
	_expect(
		priority_body.count("for request_index: int in range(_pending_requests.size())") == 1 \
				and not priority_body.contains("_oldest_request_index_for_class_locked") \
				and priority_body.contains("candidate_enqueue_sequence"),
		"priority selection must collect best/fairness/waiter state in one queue pass",
	)


func _function_body(source: String, function_name: String) -> String:
	var start_marker: String = "func %s(" % function_name
	var start: int = source.find(start_marker)
	if start < 0:
		return ""
	var next_function: int = source.find("\nfunc ", start + start_marker.length())
	if next_function < 0:
		return source.substr(start)
	return source.substr(start, next_function - start)


func _assert_result_range(
		results: Array[Dictionary],
		first_index: int,
		expected_count: int,
		label: String,
) -> void:
	_expect(results.size() == expected_count, "%s must return the expected count" % label)
	for result_index: int in range(results.size()):
		_expect(
			int(results[result_index].get("index", -1)) == first_index + result_index,
			"%s must preserve FIFO order at offset %d" % [label, result_index],
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
