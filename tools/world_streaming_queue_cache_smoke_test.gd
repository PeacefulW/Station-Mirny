extends SceneTree
## Queue/cache regression for the current global RenderWorld contract.
##
## Chunk object results remain immutable CPU/cache truth and retain collision
## records. Visual records are consumed by one background snapshot request and
## published with explicit epoch/generation tokens. No per-chunk visual pool or
## freed SceneTree object participates in this test.

const WorldChunkPacketBackend = preload(
	"res://core/systems/world/world_chunk_packet_backend.gd"
)
const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)
const WorldRenderClassRegistry = preload(
	"res://core/systems/world/world_render_class_registry.gd"
)

const TEST_EPOCH: int = 41

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_packet_queue_coalescing_and_pruning()
	_test_grass_queue_revision_replacement()
	_test_object_queue_revision_replacement()
	_test_shared_compute_priority_contract()
	_test_render_request_coalescing_keeps_latest_token()
	_test_result_drain_never_loses_publication_token()
	_test_collision_payload_is_owned_outside_render_snapshot()
	_test_object_failure_retries_current_revision()
	_test_warm_base_packet_cache_reapplies_current_diff()
	_test_stalled_reveal_guard_recovers_warm_object_presentation()
	await _test_terminal_failure_does_not_poison_render_queue()
	await _test_backend_start_stop_restart()
	await process_frame
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("world_streaming_queue_cache_smoke_test: %s" % failure)
		quit(1)
		return
	print("world_streaming_queue_cache_smoke_test: PASS")
	quit(0)


func _test_packet_queue_coalescing_and_pruning() -> void:
	var backend := WorldChunkPacketBackend.new()
	var kept_coord := Vector2i(2, 3)
	var stale_coord := Vector2i(9, 9)
	backend.queue_packet_request(
		kept_coord, 7, WorldRuntimeConstants.WORLD_VERSION,
		PackedFloat32Array(), TEST_EPOCH, 12,
	)
	backend.queue_packet_request(
		kept_coord, 7, WorldRuntimeConstants.WORLD_VERSION,
		PackedFloat32Array(), TEST_EPOCH, 1,
	)
	backend.queue_packet_request(
		stale_coord, 7, WorldRuntimeConstants.WORLD_VERSION,
		PackedFloat32Array(), TEST_EPOCH, 30,
	)
	_expect(backend._pending_requests.size() == 2, "duplicate packet demand coalesces")
	var removed: Array[Vector2i] = backend.sync_packet_requests(
		TEST_EPOCH,
		{kept_coord: 0},
	)
	_expect(removed == [stale_coord], "stale packet demand is pruned")
	_expect(backend._pending_requests.size() == 1, "one current packet token remains")
	_expect(
		int(backend._pending_requests[0].get("priority", -1)) == 0,
		"retained packet priority refreshes",
	)
	_expect(
		backend._request_semaphore.try_wait(),
		"coalesced packet owns exactly one worker permit",
	)
	_expect(
		not backend._request_semaphore.try_wait(),
		"pruned packet leaves no phantom worker permit",
	)
	backend.clear_queued_work()


func _test_render_request_coalescing_keeps_latest_token() -> void:
	var backend := WorldChunkPacketBackend.new()
	_queue_empty_render_request(backend, TEST_EPOCH, 70, true)
	_queue_empty_render_request(backend, TEST_EPOCH, 71, true)
	_expect(
		backend._pending_requests.size() == 1,
		"one epoch has one coalesced immutable render request",
	)
	var retained: Dictionary = backend._pending_requests[0] as Dictionary
	_expect(
		int(retained.get("request_generation", -1)) == 71,
		"coalescing retains the newest publication generation",
	)
	_expect(
		int(retained.get("epoch", -1)) == TEST_EPOCH,
		"coalescing retains the explicit world epoch",
	)
	_expect(
		backend._request_semaphore.try_wait() \
				and not backend._request_semaphore.try_wait(),
		"replacement neither duplicates nor loses its worker permit",
	)
	backend.clear_queued_work()


func _test_result_drain_never_loses_publication_token() -> void:
	var backend := WorldChunkPacketBackend.new()
	backend._completed_world_render_snapshots.append({
		"success": true,
		"epoch": TEST_EPOCH,
		"request_generation": 80,
	})
	backend._completed_world_render_snapshots.append({
		"success": true,
		"epoch": TEST_EPOCH,
		"request_generation": 81,
	})
	var first: Array[Dictionary] = backend.drain_completed_world_render_snapshots(1)
	_expect(
		first.size() == 1 and int(first[0].get("request_generation", -1)) == 80,
		"bounded drain returns the oldest complete publication token",
	)
	_expect(
		backend.has_completed_world_render_snapshots(),
		"logical queue head preserves the unread publication token",
	)
	var second: Array[Dictionary] = backend.drain_completed_world_render_snapshots(1)
	_expect(
		second.size() == 1 and int(second[0].get("request_generation", -1)) == 81,
		"second bounded drain returns the retained publication token",
	)
	_expect(
		not backend.has_completed_world_render_snapshots(),
		"completed queue reports empty after both tokens are consumed",
	)
	backend.clear_queued_work()


func _test_collision_payload_is_owned_outside_render_snapshot() -> void:
	var world_core: Object = ClassDB.instantiate(&"WorldCore")
	_expect(world_core != null, "WorldCore is available for collision/render contract")
	if world_core == null:
		return
	var object_result_variant: Variant = world_core.call(
		"build_object_presentation_buffers",
		PackedByteArray([4]),
		PackedByteArray([40]),
		PackedByteArray([80]),
		PackedByteArray([180]),
		PackedByteArray([0]),
		PackedByteArray([0]),
		PackedByteArray([0]),
		PackedByteArray([255]),
		PackedByteArray([0]),
		_tree_metrics(),
		PackedFloat32Array(),
		PackedFloat32Array(),
		_presentation_params(),
	)
	_expect(object_result_variant is Dictionary, "object packet decode returns a Dictionary")
	if not object_result_variant is Dictionary:
		world_core = null
		return
	var object_result: Dictionary = object_result_variant as Dictionary
	var collision_records: PackedFloat32Array = object_result.get(
		"tree_collision_records",
		PackedFloat32Array(),
	) as PackedFloat32Array
	_expect(collision_records.size() == 4, "one tree emits one four-float collision record")
	var snapshot_variant: Variant = world_core.call(
		"build_world_render_snapshot",
		PackedVector2Array([Vector2.ZERO]),
		[object_result],
		[{}],
		_source_bindings(),
		1.0,
	)
	_expect(snapshot_variant is Dictionary, "render snapshot returns a Dictionary")
	if snapshot_variant is Dictionary:
		var snapshot: Dictionary = snapshot_variant as Dictionary
		_expect(bool(snapshot.get("success", false)), "tree visual record builds successfully")
		_expect(int(snapshot.get("instance_count", 0)) == 1, "renderer receives one tree body")
		_expect(
			not snapshot.has("tree_collision_records"),
			"RenderWorld snapshot does not duplicate collision ownership",
		)
		_expect(
			(object_result.get("tree_collision_records") as PackedFloat32Array) \
					== collision_records,
			"immutable chunk collision payload survives visual derivation",
		)
	world_core = null


func _test_terminal_failure_does_not_poison_render_queue() -> void:
	var backend := WorldChunkPacketBackend.new()
	backend.start(1)
	_queue_empty_render_request(backend, TEST_EPOCH, 90, false)
	var failed: Dictionary = await _await_render_result(backend, 3000)
	_expect(not failed.is_empty(), "terminal render failure returns a completion")
	_expect(not bool(failed.get("success", true)), "invalid render request fails explicitly")
	_expect(
		int(failed.get("epoch", -1)) == TEST_EPOCH \
				and int(failed.get("request_generation", -1)) == 90,
		"terminal failure preserves its publication token",
	)

	_queue_empty_render_request(backend, TEST_EPOCH, 91, true)
	var recovered: Dictionary = await _await_render_result(backend, 3000)
	_expect(not recovered.is_empty(), "new generation runs after a terminal failure")
	_expect(bool(recovered.get("success", false)), "new valid generation self-recovers")
	_expect(
		int(recovered.get("epoch", -1)) == TEST_EPOCH \
				and int(recovered.get("request_generation", -1)) == 91,
		"recovered result publishes only the new token",
	)
	backend.stop()
	backend.clear_queued_work()


func _test_backend_start_stop_restart() -> void:
	var backend := WorldChunkPacketBackend.new()
	backend.start(2)
	await process_frame
	backend.stop()
	_expect(backend._worker_threads.is_empty(), "stop joins every worker")
	backend.start(2)
	await process_frame
	backend.stop()
	_expect(backend._worker_threads.is_empty(), "backend restarts after synchronized stop")
	backend.clear_queued_work()


func _queue_empty_render_request(
		backend: WorldChunkPacketBackend,
		epoch: int,
		generation: int,
		valid: bool,
) -> void:
	backend.queue_world_render_snapshot_request(
		PackedVector2Array([Vector2.ZERO]) if valid else PackedVector2Array(),
		[{}] if valid else [],
		[{}] if valid else [],
		_source_bindings() if valid else [],
		1.0,
		epoch,
		generation,
	)


func _await_render_result(
		backend: WorldChunkPacketBackend,
		timeout_msec: int,
) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		var drained: Array[Dictionary] = backend.drain_completed_world_render_snapshots(1)
		if not drained.is_empty():
			return drained[0]
		await process_frame
	return { }


func _source_bindings() -> Array:
	var registry := WorldRenderClassRegistry.new()
	_expect(registry.configure(WorldRenderClassRegistry.DEFAULT_REGISTRY_PATH, false),
		"render-class source bindings configure")
	return registry.get_native_source_bindings()


func _tree_metrics() -> PackedFloat32Array:
	return PackedFloat32Array([
		768.0, 768.0, 384.0, 539.0, 0.64, 0.0, 36.0, 36.0,
	])


func _presentation_params() -> PackedFloat32Array:
	return PackedFloat32Array([
		4.0, 16.0, 64.0, 1.0, 1.0, 34.0,
		0.5, 1.0, 1.0, 1.0,
		0.8, 0.4, 0.1, 1.0, 1.0, 0.5, 4.0, 0.1,
		1.0, 1.0,
	])


func _test_grass_queue_revision_replacement() -> void:
	var backend := WorldChunkPacketBackend.new()
	var coord := Vector2i(-4, 6)
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	backend.queue_grass_scatter_request(
		coord, 11, terrain_ids, lake_flags, PackedByteArray(), 0,
		PackedFloat32Array(), 8, 1, 10,
	)
	backend.queue_grass_scatter_request(
		coord, 11, terrain_ids, lake_flags, PackedByteArray(), 0,
		PackedFloat32Array(), 8, 2, 1,
	)
	_expect(backend._pending_requests.size() == 1, "new grass revision must replace queued stale work")
	_expect(int(backend._pending_requests[0].get("revision", -1)) == 2, "latest grass revision must win")
	var removed: Array[Vector2i] = backend.sync_grass_scatter_requests(8, {})
	_expect(removed == [coord], "grass work outside current views must be pruned")
	_expect(
		not backend._request_semaphore.try_wait(),
		"pruned grass work must not leave an obsolete worker permit",
	)


func _test_object_queue_revision_replacement() -> void:
	var backend := WorldChunkPacketBackend.new()
	var coord := Vector2i(7, -3)
	var packet := {
		"object_kind": PackedByteArray([4]),
		"object_local_x_px_q4": PackedByteArray([10]),
		"object_local_y_px_q4": PackedByteArray([20]),
		"object_size_px": PackedByteArray([180]),
		"object_atlas_index": PackedByteArray([0]),
		"object_variant": PackedByteArray([0]),
		"object_flags": PackedByteArray([0]),
		"object_tint": PackedByteArray([255]),
		"object_phase": PackedByteArray([0]),
	}
	var tree_metrics := PackedFloat32Array(
		[768.0, 768.0, 384.0, 539.0, 0.64, 0.0, 36.0, 36.0],
	)
	var rock_metrics := PackedFloat32Array([768.0, 768.0, 384.0, 482.0, 440.0])
	var bush_metrics := PackedFloat32Array()
	var params := PackedFloat32Array([4.0, 16.0, 64.0, 1.0, 1.0, 34.0])
	backend.queue_object_presentation_request(
		coord, packet, tree_metrics, rock_metrics, bush_metrics, params, 1, 9, 1, 12,
	)
	backend.queue_object_presentation_request(
		coord, packet, tree_metrics, rock_metrics, bush_metrics, params, 1, 9, 2, 1,
	)
	_expect(backend._pending_requests.size() == 1, "new object revision must replace stale queued work")
	_expect(int(backend._pending_requests[0].get("revision", -1)) == 2, "latest object revision must win")
	var kept_demand := {
		coord: {
			"revision": 2,
			"catalog_generation": 1,
			"priority": 0,
		},
	}
	_expect(
		backend.sync_object_presentation_requests(9, kept_demand).is_empty(),
		"matching object demand must stay queued",
	)
	_expect(int(backend._pending_requests[0].get("priority", -1)) == 0, "object priority must refresh")
	var removed: Array[Vector2i] = backend.sync_object_presentation_requests(9, {})
	_expect(removed == [coord], "object work outside source demand must be pruned")
	_expect(
		not backend._request_semaphore.try_wait(),
		"pruned object work must not leave an obsolete worker permit",
	)


func _test_shared_compute_priority_contract() -> void:
	var backend := WorldChunkPacketBackend.new()
	backend.queue_packet_request(
		Vector2i(1, 0), 7, 1, PackedFloat32Array(), 3, 0,
	)
	backend.queue_object_presentation_request(
		Vector2i(8, 0), {}, PackedFloat32Array(), PackedFloat32Array(),
		PackedFloat32Array(), PackedFloat32Array(), 1, 3, 1, 64,
	)
	var first: Dictionary = backend._take_highest_priority_request_locked()
	_expect(
		str(first.get("kind", "")) == "object_presentation",
		"reveal-class object work must beat streaming-class packets independent of distance",
	)
	backend.clear_queued_work()
	backend._request_dispatch_turn = 0
	backend.queue_packet_request(
		Vector2i(1, 0), 7, 1, PackedFloat32Array(), 3, 0,
	)
	backend._request_dispatch_turn = 100
	backend.queue_object_presentation_request(
		Vector2i(8, 0), {}, PackedFloat32Array(), PackedFloat32Array(),
		PackedFloat32Array(), PackedFloat32Array(), 1, 3, 1, 64,
	)
	var aged_class_first: Dictionary = backend._take_highest_priority_request_locked()
	_expect(
		str(aged_class_first.get("kind", "")) == "object_presentation",
		"aged streaming work must never invert a fresh reveal deadline",
	)
	backend.clear_queued_work()
	for dispatch_index: int in range(WorldChunkPacketBackend.MAX_REVEAL_DISPATCH_BURST + 2):
		backend.queue_object_presentation_request(
			Vector2i(dispatch_index, 9), {}, PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array(), PackedFloat32Array(), 1, 3,
			dispatch_index + 10, dispatch_index,
		)
		backend._take_highest_priority_request_locked()
	_expect(
		backend._reveal_dispatch_burst == 0,
		"reveal quota debt must not accrue while no streaming request is waiting",
	)
	backend.queue_packet_request(Vector2i(99, 9), 7, 1, PackedFloat32Array(), 3, 999)
	backend.queue_object_presentation_request(
		Vector2i(0, 10), {}, PackedFloat32Array(), PackedFloat32Array(),
		PackedFloat32Array(), PackedFloat32Array(), 1, 3, 99, 0,
	)
	_expect(
		str(backend._take_highest_priority_request_locked().get("kind", "")) \
				== "object_presentation",
		"new streaming work must not consume a stale historical fairness slot",
	)
	backend.clear_queued_work()
	backend.queue_packet_request(
		Vector2i(99, 0), 7, 1, PackedFloat32Array(), 3, 999,
	)
	var streaming_received_fair_slot: bool = false
	for dispatch_index: int in range(WorldChunkPacketBackend.MAX_REVEAL_DISPATCH_BURST + 1):
		backend.queue_object_presentation_request(
			Vector2i(dispatch_index, 1), {}, PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array(), PackedFloat32Array(), 1, 3,
			dispatch_index + 1, dispatch_index,
		)
		var fair_dispatch: Dictionary = backend._take_highest_priority_request_locked()
		if str(fair_dispatch.get("kind", "")) == "packet":
			streaming_received_fair_slot = true
			_expect(
				bool(fair_dispatch.get("_fairness_slot", false)),
				"streaming quota must mark a single-request non-batchable slot",
			)
			break
	_expect(
		streaming_received_fair_slot,
		"continuous reveal work must leave a bounded throughput slot for vehicle prefetch",
	)
	backend.clear_queued_work()
	backend.queue_packet_request(
		Vector2i(99, 3), 7, 1, PackedFloat32Array(), 3, 999,
	)
	for dispatch_index: int in range(WorldChunkPacketBackend.MAX_REVEAL_DISPATCH_BURST):
		backend.queue_object_presentation_request(
			Vector2i(dispatch_index, 3), {}, PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array(), PackedFloat32Array(), 1, 3,
			dispatch_index + 30, dispatch_index,
		)
		backend._take_highest_priority_request_locked()
	_expect(
		backend._reveal_dispatch_burst == WorldChunkPacketBackend.MAX_REVEAL_DISPATCH_BURST,
		"reveal quota must reach its limit while a streaming request waits",
	)
	backend.sync_packet_requests(3, {})
	backend.queue_packet_request(
		Vector2i(100, 3), 7, 1, PackedFloat32Array(), 3, 999,
	)
	backend.queue_object_presentation_request(
		Vector2i(0, 4), {}, PackedFloat32Array(), PackedFloat32Array(),
		PackedFloat32Array(), PackedFloat32Array(), 1, 3, 40, 0,
	)
	_expect(
		str(backend._take_highest_priority_request_locked().get("kind", "")) \
				== "object_presentation",
		"removing the last streaming waiter must clear stale reveal quota debt",
	)
	backend.clear_queued_work()
	backend.queue_overview_request(7, 1, PackedFloat32Array(), 3)
	var background_received_fair_slot: bool = false
	for dispatch_index: int in range(
		WorldChunkPacketBackend.MAX_NON_BACKGROUND_DISPATCH_BURST + 1
	):
		backend.queue_packet_request(
			Vector2i(dispatch_index, 2), 7, 1, PackedFloat32Array(), 3, dispatch_index,
		)
		var fair_dispatch: Dictionary = backend._take_highest_priority_request_locked()
		if str(fair_dispatch.get("kind", "")) == "overview":
			background_received_fair_slot = true
			_expect(
				bool(fair_dispatch.get("_fairness_slot", false)),
				"background quota must mark its bounded fairness slot",
			)
			break
	_expect(
		background_received_fair_slot,
		"continuous streaming work must leave a bounded throughput slot for background work",
	)
	backend.clear_queued_work()
	backend.queue_packet_request(
		Vector2i(99, 6), 7, 1, PackedFloat32Array(), 3, 999,
		WorldChunkPacketBackend.PRIORITY_CLASS_BACKGROUND,
	)
	for dispatch_index: int in range(
		WorldChunkPacketBackend.MAX_NON_BACKGROUND_DISPATCH_BURST
	):
		backend.queue_object_presentation_request(
			Vector2i(dispatch_index, 6), {}, PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array(), PackedFloat32Array(), 1, 3,
			dispatch_index + 50, dispatch_index,
		)
		backend._take_highest_priority_request_locked()
	_expect(
		backend._non_background_dispatch_burst \
				== WorldChunkPacketBackend.MAX_NON_BACKGROUND_DISPATCH_BURST,
		"background quota must reach its limit while background work waits",
	)
	backend.sync_packet_requests(3, {})
	backend.queue_packet_request(
		Vector2i(100, 6), 7, 1, PackedFloat32Array(), 3, 999,
		WorldChunkPacketBackend.PRIORITY_CLASS_BACKGROUND,
	)
	backend.queue_object_presentation_request(
		Vector2i(0, 7), {}, PackedFloat32Array(), PackedFloat32Array(),
		PackedFloat32Array(), PackedFloat32Array(), 1, 3, 90, 0,
	)
	_expect(
		str(backend._take_highest_priority_request_locked().get("kind", "")) \
				== "object_presentation",
		"removing the last background waiter must clear stale background quota debt",
	)
	_expect(
		not backend._requests_are_batch_compatible(
			{
				"kind": "packet", "seed": 1, "world_version": 1, "epoch": 1,
				"settings_packed": PackedFloat32Array(), "priority": 0,
				"priority_class": WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING,
			},
			{
				"kind": "packet", "seed": 1, "world_version": 1, "epoch": 1,
				"settings_packed": PackedFloat32Array(), "priority": 1,
				"priority_class": WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING,
			},
		),
		"one native packet batch must not cross a distance-priority frontier",
	)
	backend.clear_queued_work()

	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	_expect(
		streamer._packet_backend == streamer._mountain_mask_backend \
			and streamer._packet_backend == streamer._grass_scatter_backend \
			and streamer._packet_backend == streamer._object_presentation_backend,
		"world compute roles must share one CPU-capped priority pool",
	)
	var worker_count: int = streamer._resolve_world_compute_worker_count()
	_expect(
		worker_count >= 1 and worker_count <= streamer.WORLD_COMPUTE_MAX_WORKERS,
		"shared compute worker count must stay within its CPU cap",
	)
	streamer.free()


func _test_object_failure_retries_current_revision() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	var coord := Vector2i(3, 4)
	var revision: int = 27
	var packet := {
		"object_kind": PackedByteArray([4]),
		"object_local_x_px_q4": PackedByteArray([10]),
		"object_local_y_px_q4": PackedByteArray([20]),
		"object_size_px": PackedByteArray([180]),
		"object_atlas_index": PackedByteArray([0]),
		"object_variant": PackedByteArray([0]),
		"object_flags": PackedByteArray([0]),
		"object_tint": PackedByteArray([255]),
		"object_phase": PackedByteArray([0]),
	}
	streamer._generation_epoch = 12
	streamer._player_chunk_coord = coord
	streamer._chunk_packets[coord] = packet
	streamer._base_chunk_packets[coord] = packet
	streamer._object_presentation_revision_by_chunk[coord] = revision
	streamer._record_object_presentation_failure(coord, revision, "synthetic retry proof")
	var retry: Dictionary = streamer._object_presentation_retry_by_chunk.get(coord, { }) as Dictionary
	_expect(int(retry.get("attempts", 0)) == 1, "first object failure must be tracked")
	_expect(not bool(retry.get("terminal", true)), "first object failure must remain retryable")
	retry["next_retry_msec"] = 0
	streamer._object_presentation_retry_by_chunk[coord] = retry
	streamer._retry_failed_object_presentation_builds(1)
	_expect(
		int(streamer._object_presentation_inflight_chunks.get(coord, -1)) == revision,
		"retry must queue the current object revision",
	)
	_expect(
		streamer._object_presentation_backend._pending_requests.size() == 1,
		"retry must produce one bounded worker request",
	)
	streamer._object_presentation_backend.clear_queued_work()
	streamer.free()


func _test_warm_base_packet_cache_reapplies_current_diff() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	_expect(streamer_script != null, "WorldStreamer script must load")
	var streamer: Node = streamer_script.new() as Node
	_expect(streamer != null, "WorldStreamer must instantiate")
	var coord := Vector2i(5, 2)
	var local_coord := Vector2i(1, 1)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_ids.fill(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.fill(1)
	var base_packet := {
		"chunk_coord": coord,
		"terrain_ids": terrain_ids,
		"walkable_flags": walkable_flags,
	}
	var prepared_result := {
		"payload_bytes": 48,
		"tree_atlas_bucket_buffers": [],
		"rock_atlas_bucket_buffers": [],
		"tree_collision_records": PackedFloat32Array(),
	}
	streamer._object_presentation_revision_by_chunk[coord] = 17
	streamer._object_presentation_results_by_chunk[coord] = prepared_result
	streamer._player_chunk_coord = coord
	streamer._rebuild_desired_chunk_cache()
	streamer._diff_store.set_tile_override(
		coord,
		local_coord,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		false,
	)
	streamer._store_warm_chunk_packet(coord, base_packet)
	_expect(streamer._warm_object_presentation_cache.has(coord), "prepared object result must move with base")
	_expect(streamer._warm_object_presentation_cache_bytes == 48, "warm object bytes must be O(1) payload accounting")
	_expect(streamer._restore_warm_chunk_packet(coord), "warm packet must restore")
	_expect(streamer._object_presentation_results_by_chunk.has(coord), "prepared object result must restore without rebuild")
	_expect(streamer._object_presentation_cache_hit_count_total == 1, "warm object hit must be counted")
	_expect(int(streamer._object_presentation_revision_by_chunk.get(coord, -1)) == 17, "warm restore keeps revision")
	_expect(
		streamer._pending_hot_object_prestage_set.has(coord),
		"a warm CPU result restored without a view must re-enter bounded GPU prestage",
	)
	var restored: Dictionary = streamer._chunk_packets.get(coord, {}) as Dictionary
	var restored_terrain: PackedInt32Array = restored.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var restored_walkable: PackedByteArray = restored.get("walkable_flags", PackedByteArray()) as PackedByteArray
	_expect(restored_terrain[index] == WorldRuntimeConstants.TERRAIN_PLAINS_DUG, "current terrain diff must apply")
	_expect(restored_walkable[index] == 0, "current walkability diff must apply")
	var pristine: Dictionary = streamer._base_chunk_packets.get(coord, {}) as Dictionary
	var pristine_terrain: PackedInt32Array = pristine.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	_expect(pristine_terrain[index] == WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, "warm base must stay immutable")

	var warm_cache_capacity: int = int(streamer.WARM_PACKET_CACHE_MAX_CHUNKS)
	for cache_index: int in range(warm_cache_capacity + 2):
		var cache_coord := Vector2i(cache_index, 100)
		streamer._store_warm_chunk_packet(cache_coord, {"chunk_coord": cache_coord})
	_expect(
		streamer._warm_base_chunk_packet_cache.size() == warm_cache_capacity,
		"warm packet cache must remain bounded",
	)
	var oversized_coord := Vector2i(777, 100)
	streamer._object_presentation_revision_by_chunk[oversized_coord] = 99
	streamer._object_presentation_results_by_chunk[oversized_coord] = {
		"payload_bytes": int(streamer.WARM_OBJECT_PRESENTATION_CACHE_MAX_BYTES) + 1,
	}
	streamer._store_warm_chunk_packet(oversized_coord, {"chunk_coord": oversized_coord})
	_expect(
		not streamer._warm_base_chunk_packet_cache.has(oversized_coord) \
				and not streamer._warm_object_presentation_cache.has(oversized_coord),
		"object byte-cap eviction must evict the coupled warm base/result",
	)
	_expect(
		not streamer._object_presentation_revision_by_chunk.has(oversized_coord),
		"final warm eviction must invalidate object revision",
	)
	streamer.free()


## Regression for the recorded stall: a desired-visible chunk held its reveal
## guard while its CPU object result sat in the warm cache and every queue read
## zero, so no repair cursor could see it and the chunk stayed black until player
## movement happened to re-request the coordinate.
func _test_stalled_reveal_guard_recovers_warm_object_presentation() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	_expect(streamer_script != null, "WorldStreamer script must load")
	var streamer: Node = streamer_script.new() as Node
	var coord := Vector2i(6, 3)
	var prepared_result := {
		"payload_bytes": 64,
		"tree_atlas_bucket_buffers": [],
		"rock_atlas_bucket_buffers": [],
		"tree_collision_records": PackedFloat32Array(),
	}
	streamer._player_chunk_coord = coord
	streamer._rebuild_desired_chunk_cache()
	streamer._base_chunk_packets[coord] = {"chunk_coord": coord}
	streamer._chunk_packets[coord] = {"chunk_coord": coord}
	streamer._object_presentation_revision_by_chunk[coord] = 5
	streamer._object_presentation_results_by_chunk[coord] = prepared_result

	# Demote exactly the way the warm-cache path does.
	streamer._store_warm_chunk_packet(coord, {"chunk_coord": coord})
	_expect(
		not streamer._object_presentation_results_by_chunk.has(coord),
		"warm demotion removes the live object presentation result",
	)
	_expect(
		streamer._warm_object_presentation_cache.has(coord),
		"demoted object presentation result stays in the warm cache",
	)

	# The recorded stall state: reveal guard active, every queue empty.
	streamer._pending_hot_object_prestage_set.clear()
	streamer._pending_hot_object_prestage_chunks.clear()
	streamer._pending_object_packet_visual_upload_set.clear()
	streamer._object_presentation_inflight_chunks.clear()
	streamer._pending_chunk_visibility_after_mountain_visual[coord] = true

	# Negative control: the pre-fix repair could not observe this state at all,
	# because it requires a live CPU result before it does anything.
	_expect(
		not streamer._queue_object_presentation_for_live_view(coord),
		"the live-view repair alone cannot recover a warm-parked result",
	)
	_expect(
		not streamer._object_presentation_results_by_chunk.has(coord),
		"the live-view repair alone leaves the chunk without live truth",
	)
	_expect(
		streamer._pending_hot_object_prestage_chunks.is_empty(),
		"the stalled state really does report every queue at zero",
	)

	streamer._repair_stalled_object_presentation_guard(coord)
	_expect(
		streamer._object_presentation_results_by_chunk.has(coord),
		"a stalled reveal guard promotes the warm object result back to live truth",
	)
	_expect(
		not streamer._warm_object_presentation_cache.has(coord),
		"promoting the warm result clears its warm copy",
	)

	# A second guard tick must not manufacture a duplicate transaction.
	var live_after_first: Variant = streamer._object_presentation_results_by_chunk.get(coord)
	var prestage_after_first: int = streamer._pending_hot_object_prestage_chunks.size()
	streamer._repair_stalled_object_presentation_guard(coord)
	_expect(
		streamer._pending_hot_object_prestage_chunks.size() == prestage_after_first,
		"repeated guard ticks do not duplicate the presentation token",
	)
	_expect(
		streamer._object_presentation_results_by_chunk.get(coord) == live_after_first,
		"repeated guard ticks do not replace the restored live result",
	)

	# An inflight revision already owns the coordinate: the guard must not touch it.
	streamer._object_presentation_results_by_chunk.erase(coord)
	streamer._store_warm_object_presentation(coord, prepared_result)
	streamer._warm_base_chunk_packet_cache[coord] = {"chunk_coord": coord}
	streamer._store_warm_object_presentation(coord, prepared_result)
	streamer._object_presentation_inflight_chunks[coord] = 5
	streamer._repair_stalled_object_presentation_guard(coord)
	_expect(
		not streamer._object_presentation_results_by_chunk.has(coord),
		"an inflight revision keeps the guard from promoting a second result",
	)
	streamer._object_presentation_inflight_chunks.clear()
	streamer.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
