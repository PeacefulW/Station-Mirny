extends SceneTree

const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")
const FrameBudgetDispatcherNode = preload("res://core/autoloads/frame_budget_dispatcher.gd")
const RuntimeWorkTypes = preload("res://core/runtime/runtime_work_types.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_packet_queue_coalescing_and_pruning()
	_test_grass_queue_revision_replacement()
	_test_object_queue_revision_replacement()
	_test_shared_compute_priority_contract()
	await _test_backend_start_stop_restart()
	_test_object_visual_queue_completion_priority()
	_test_object_visual_lane_budgeted_continuation()
	_test_object_visual_queue_cap_and_live_tick_preemption()
	_test_object_result_drain_is_cpu_only()
	_test_terminal_failure_is_dispatcher_only()
	_test_stale_hidden_hot_work_is_pruned()
	_test_live_hot_budget_pressure_does_not_restage_recursively()
	_test_incremental_cold_envelope_revision_and_accounting()
	_test_retire_dispatcher_and_hidden_admission_backpressure()
	_test_multi_victim_retirement_drains_autonomously()
	_test_clean_retire_pool_decision_tracks_violated_dimension()
	_test_object_failure_retries_current_revision()
	_test_warm_base_packet_cache_reapplies_current_diff()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	print("world_streaming_queue_cache_smoke_test: PASS")
	quit(0)


func _test_packet_queue_coalescing_and_pruning() -> void:
	var backend := WorldChunkPacketBackend.new()
	var settings := PackedFloat32Array([1.0, 2.0])
	var near_coord := Vector2i(2, 3)
	var stale_coord := Vector2i(9, 9)
	backend.queue_packet_request(near_coord, 7, 1, settings, 4, 12)
	backend.queue_packet_request(near_coord, 7, 1, settings, 4, 1)
	backend.queue_packet_request(stale_coord, 7, 1, settings, 4, 30)
	_expect(backend._pending_requests.size() == 2, "duplicate packet requests must coalesce")
	var removed: Array[Vector2i] = backend.sync_packet_requests(4, {near_coord: 0})
	_expect(removed == [stale_coord], "stale packet request must be removed")
	_expect(backend._pending_requests.size() == 1, "only current packet request may remain")
	_expect(int(backend._pending_requests[0].get("priority", -1)) == 0, "priority must refresh")
	_expect(
		backend._request_semaphore.try_wait(),
		"retained packet work must keep exactly one worker permit",
	)
	_expect(
		not backend._request_semaphore.try_wait(),
		"pruned packet work must not leave an obsolete worker permit",
	)


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


func _test_backend_start_stop_restart() -> void:
	var backend := WorldChunkPacketBackend.new()
	backend.start(2)
	await process_frame
	backend.stop()
	_expect(backend._worker_threads.is_empty(), "backend stop must join every worker")
	backend.start(2)
	await process_frame
	backend.stop()
	_expect(
		backend._worker_threads.is_empty(),
		"backend must restart cleanly after a synchronized stop",
	)


func _test_object_visual_queue_completion_priority() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	var live_far_coord := Vector2i(4, 0)
	var hidden_near_coord := Vector2i(1, 0)
	streamer._player_chunk_coord = Vector2i.ZERO
	var live_far_view: ChunkView = ChunkView.new()
	live_far_view.visible = false
	streamer.add_child(live_far_view)
	streamer._chunk_views[live_far_coord] = live_far_view
	streamer._queue_object_packet_visual_upload(hidden_near_coord)
	streamer._queue_object_packet_visual_upload(live_far_coord)
	_expect(
		streamer._take_next_object_packet_visual_upload() == live_far_coord,
		"a reveal-frontier view must beat a closer hidden prestage",
	)
	_expect(
		streamer._take_next_object_packet_visual_upload() == live_far_coord,
		"the selected atomic transaction must retain the lane until completion",
	)
	var urgent_coord := Vector2i(2, 0)
	var urgent_view: ChunkView = ChunkView.new()
	urgent_view.visible = false
	streamer.add_child(urgent_view)
	streamer._chunk_views[urgent_coord] = urgent_view
	streamer._queue_object_packet_visual_upload(urgent_coord)
	_expect(
		streamer._take_next_object_packet_visual_upload() == urgent_coord,
		"a closer reveal deadline may preempt the focused transaction",
	)
	streamer._drop_object_packet_visual_upload(urgent_coord)
	streamer._drop_object_packet_visual_upload(live_far_coord)
	_expect(
		streamer._take_next_object_packet_visual_upload() == hidden_near_coord,
		"hidden prestage runs after the live frontier drains",
	)
	streamer.free()


func _test_object_visual_lane_budgeted_continuation() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	streamer._player_chunk_coord = Vector2i.ZERO
	# More than one bounded scan slice proves the real dispatcher callback can
	# stay active without crossing into the selected envelope phase.
	for index: int in range(
		streamer.OBJECT_PRESENTATION_PRIORITY_SCAN_MAX_ITEMS_PER_PHASE * 3,
	):
		streamer._queue_object_packet_visual_upload(Vector2i(index + 20, 80))
	var dispatcher: FrameBudgetDispatcherNode = FrameBudgetDispatcherNode.new()
	root.add_child(dispatcher)
	dispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		streamer.OBJECT_PRESENTATION_VISUAL_UPLOAD_BUDGET_MS,
		Callable(streamer, "_object_presentation_visual_apply_tick"),
		&"test.object_visual_budgeted_continuation",
	)
	dispatcher._process(0.0)
	var callback_count: int = streamer._object_presentation_visual_lane_callback_count
	_expect(
		callback_count > 1,
		"FrameBudgetDispatcher consumes more than one safe object callback per frame",
	)
	_expect(
		callback_count <= streamer.OBJECT_PRESENTATION_MAX_DISPATCH_CALLBACKS_PER_FRAME,
		"object visual lane callback count stays hard-bounded",
	)
	_expect(
		streamer._object_packet_visual_selection_phase_prepared \
				and streamer._hot_object_presentation_layers.is_empty(),
		"priority completion yields before envelope or GPU work",
	)
	dispatcher.free()
	streamer.free()

	var guarded_streamer: Node = streamer_script.new() as Node
	guarded_streamer._player_chunk_coord = Vector2i.ZERO
	for index: int in range(
		guarded_streamer.OBJECT_PRESENTATION_PRIORITY_SCAN_MAX_ITEMS_PER_PHASE * 2,
	):
		guarded_streamer._queue_object_packet_visual_upload(Vector2i(index + 20, 90))
	guarded_streamer._object_presentation_visual_lane_frame = int(Engine.get_process_frames())
	guarded_streamer._object_presentation_visual_lane_started_usec = \
			Time.get_ticks_usec() \
			- guarded_streamer.OBJECT_PRESENTATION_VISUAL_UPLOAD_BUDGET_USEC \
			+ 1
	guarded_streamer._object_presentation_visual_lane_callback_count = 0
	_expect(
		not guarded_streamer._object_presentation_visual_apply_tick() \
				and guarded_streamer._object_packet_visual_priority_scan_active,
		"lane lookahead refuses another callback when the per-frame budget is exhausted",
	)
	guarded_streamer.free()

	var allocation_streamer: Node = streamer_script.new() as Node
	var family: StringName = \
			WorldObjectPacketLayer.PRESENTATION_PHASE_TREE_SLOT_ALLOCATION
	allocation_streamer._record_object_presentation_allocation_measurement(family, 80)
	_expect(
		allocation_streamer._object_presentation_allocation_lookahead_fits_lane(400, family),
		"measured family high-water plus safety margin may use the 0.65 ms allocation lane",
	)
	allocation_streamer._record_object_presentation_allocation_measurement(family, 520)
	_expect(
		not allocation_streamer._object_presentation_allocation_lookahead_fits_lane(0, family),
		"one allocation outlier raises the monotonic high-water and stops continuation",
	)
	var allocation_coord := Vector2i.ZERO
	allocation_streamer._player_chunk_coord = allocation_coord
	allocation_streamer._queue_object_packet_visual_upload(allocation_coord)
	allocation_streamer._focused_object_packet_visual_upload_chunk = allocation_coord
	allocation_streamer._object_packet_visual_priority_dirty = false
	allocation_streamer._object_presentation_visual_lane_started_usec = Time.get_ticks_usec()
	allocation_streamer._object_presentation_allocation_high_water_usec_by_family[family] = 40
	allocation_streamer._object_presentation_allocation_callback_count = 1
	_expect(
		allocation_streamer._can_continue_object_presentation_allocation_lane(
			Time.get_ticks_usec(),
			family,
			allocation_coord,
		),
		"one measured allocation may request the second allocation-only callback",
	)
	allocation_streamer._object_presentation_allocation_callback_count = \
			allocation_streamer.OBJECT_PRESENTATION_MAX_ALLOCATION_CALLBACKS_PER_FRAME
	_expect(
		not allocation_streamer._can_continue_object_presentation_allocation_lane(
			Time.get_ticks_usec(),
			family,
			allocation_coord,
		),
		"allocation-only continuation stops at two callbacks per process frame",
	)
	allocation_streamer.free()


func _test_object_visual_queue_cap_and_live_tick_preemption() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var capped_streamer: Node = streamer_script.new() as Node
	var queue_cap: int = int(capped_streamer.OBJECT_PRESENTATION_VISUAL_QUEUE_MAX_TOKENS)
	for index: int in range(queue_cap + 12):
		capped_streamer._queue_object_packet_visual_upload(Vector2i(index + 10, 40))
	_expect(
		capped_streamer._pending_object_packet_visual_upload_set.size() == queue_cap \
				and capped_streamer._pending_object_packet_visual_upload_chunks.size() == queue_cap \
				and capped_streamer._pending_object_packet_visual_upload_index_by_chunk.size() \
						== queue_cap,
		"priority snapshot source is hard-capped and index-consistent",
	)
	var urgent_coord := Vector2i.ZERO
	var urgent_view: ChunkView = ChunkView.new()
	urgent_view.visible = false
	capped_streamer.add_child(urgent_view)
	capped_streamer._chunk_views[urgent_coord] = urgent_view
	capped_streamer._queue_object_packet_visual_upload(urgent_coord)
	_expect(
		capped_streamer._pending_object_packet_visual_upload_set.size() == queue_cap \
				and capped_streamer._pending_object_packet_visual_upload_set.has(urgent_coord),
		"live admission replaces one lower-class token without exceeding the hard cap",
	)
	capped_streamer.free()

	var repair_streamer: Node = streamer_script.new() as Node
	repair_streamer._player_chunk_coord = Vector2i.ZERO
	for index: int in range(queue_cap):
		repair_streamer._queue_hot_object_prestage(Vector2i(index + 20, 60))
	var queued_before_live: Dictionary = \
			repair_streamer._pending_object_packet_visual_upload_set.duplicate()
	var repair_live_coord := Vector2i.ZERO
	var repair_live_view: ChunkView = ChunkView.new()
	repair_live_view.visible = false
	repair_streamer.add_child(repair_live_view)
	repair_streamer._chunk_views[repair_live_coord] = repair_live_view
	repair_streamer._queue_hot_object_prestage(repair_live_coord)
	var evicted_hidden_coord: Vector2i = repair_streamer.INVALID_CHUNK_COORD
	for queued_variant: Variant in queued_before_live.keys():
		var queued_coord: Vector2i = queued_variant as Vector2i
		if not repair_streamer._pending_object_packet_visual_upload_set.has(queued_coord):
			evicted_hidden_coord = queued_coord
			break
	_expect(
		evicted_hidden_coord != repair_streamer.INVALID_CHUNK_COORD \
				and repair_streamer._pending_hot_object_prestage_set.has(evicted_hidden_coord) \
				and repair_streamer._object_packet_visual_queue_repair_needed,
		"live cap admission retains its evicted hidden token for autonomous repair",
	)
	# Mutate an index before a partially advanced repair cursor, then open one
	# queue slot. Repair must restart rather than skipping the retained victim.
	var removed_before_cursor: Vector2i = repair_streamer \
			._pending_hot_object_prestage_chunks[0]
	repair_streamer._object_packet_visual_queue_repair_cursor = 5
	repair_streamer._drop_hot_object_prestage(removed_before_cursor)
	_expect(
		repair_streamer._object_packet_visual_queue_repair_cursor == 0,
		"prestage filtering resets the live repair cursor",
	)
	repair_streamer._drop_object_packet_visual_upload(removed_before_cursor)
	var repair_guard: int = queue_cap
	while not repair_streamer._pending_object_packet_visual_upload_set.has(
			evicted_hidden_coord,
		) and repair_guard > 0:
		repair_streamer._repair_one_object_packet_visual_queue_token()
		repair_guard -= 1
	_expect(
		repair_guard > 0 \
				and repair_streamer._pending_object_packet_visual_upload_set.has(
					evicted_hidden_coord,
				),
		"live-evicted hidden token is eventually reinserted after capacity opens",
	)
	repair_streamer.free()

	var streamer: Node = streamer_script.new() as Node
	streamer._generation_epoch = 91
	streamer._player_chunk_coord = Vector2i.ZERO
	var hidden_coord := Vector2i(1, 0)
	var hidden_revision: int = 601
	streamer._object_presentation_revision_by_chunk[hidden_coord] = hidden_revision
	streamer._object_presentation_results_by_chunk[hidden_coord] = \
			_make_live_object_completion(streamer, hidden_coord, hidden_revision)
	streamer._queue_hot_object_prestage(hidden_coord)
	streamer._object_presentation_visual_apply_tick()
	_expect(
		streamer._object_packet_visual_selection_phase_prepared \
				and streamer._focused_object_packet_visual_upload_chunk == hidden_coord,
		"hidden selection is prepared without running its envelope phase",
	)

	var live_coord := Vector2i.ZERO
	var live_revision: int = 602
	var live_view: ChunkView = ChunkView.new()
	live_view.visible = false
	streamer.add_child(live_view)
	streamer._chunk_views[live_coord] = live_view
	streamer._object_presentation_revision_by_chunk[live_coord] = live_revision
	streamer._object_presentation_results_by_chunk[live_coord] = \
			_make_live_object_completion(streamer, live_coord, live_revision)
	streamer._queue_hot_object_prestage(live_coord)
	_expect(
		streamer._object_packet_visual_urgent_priority_dirty,
		"O(1) enqueue class comparison marks genuine live preemption",
	)
	streamer._object_presentation_visual_apply_tick()
	_expect(
		streamer._object_packet_visual_selection_phase_prepared \
				and streamer._focused_object_packet_visual_upload_chunk == live_coord \
				and not streamer._hot_object_presentation_layers.has(hidden_coord),
		"live token invalidates prepared hidden work in the dispatcher tick",
	)
	streamer._object_presentation_visual_apply_tick()
	_expect(
		streamer._hot_object_presentation_layers.has(live_coord) \
				and not streamer._hot_object_presentation_layers.has(hidden_coord),
		"class-0 reveal runs before any hidden heavy phase",
	)
	streamer.free()

	var deadline_streamer: Node = streamer_script.new() as Node
	deadline_streamer._player_chunk_coord = Vector2i.ZERO
	var far_live_coord := Vector2i(4, 0)
	var near_live_coord := Vector2i(1, 0)
	var far_live_view: ChunkView = ChunkView.new()
	far_live_view.visible = false
	deadline_streamer.add_child(far_live_view)
	deadline_streamer._chunk_views[far_live_coord] = far_live_view
	deadline_streamer._queue_object_packet_visual_upload(far_live_coord)
	deadline_streamer._object_presentation_visual_apply_tick()
	_expect(
		deadline_streamer._object_packet_visual_selection_phase_prepared \
				and deadline_streamer._focused_object_packet_visual_upload_chunk \
						== far_live_coord,
		"far class-0 deadline is prepared without heavy work",
	)
	var near_live_view: ChunkView = ChunkView.new()
	near_live_view.visible = false
	deadline_streamer.add_child(near_live_view)
	deadline_streamer._chunk_views[near_live_coord] = near_live_view
	deadline_streamer._queue_object_packet_visual_upload(near_live_coord)
	_expect(
		deadline_streamer._object_packet_visual_urgent_priority_dirty,
		"O(1) enqueue comparison recognizes a closer same-class deadline",
	)
	deadline_streamer._object_presentation_visual_apply_tick()
	_expect(
		deadline_streamer._object_packet_visual_selection_phase_prepared \
				and deadline_streamer._focused_object_packet_visual_upload_chunk \
						== near_live_coord,
		"closer class-0 token gets a priority slice before far heavy work",
	)
	deadline_streamer.free()


func _test_object_result_drain_is_cpu_only() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	var coord := Vector2i(6, 0)
	var hidden_coord := Vector2i(1, 0)
	var revision: int = 41
	streamer._generation_epoch = 19
	streamer._player_chunk_coord = Vector2i.ZERO
	streamer._base_chunk_packets[coord] = {"chunk_coord": coord}
	streamer._chunk_packets[coord] = {"chunk_coord": coord}
	streamer._object_presentation_revision_by_chunk[coord] = revision
	streamer._object_presentation_inflight_chunks[coord] = revision
	var live_view: ChunkView = ChunkView.new()
	live_view.visible = false
	streamer.add_child(live_view)
	streamer._chunk_views[coord] = live_view

	# Prove that a newly completed live envelope can preempt already-focused
	# hidden work without constructing its graph in result drain.
	streamer._queue_object_packet_visual_upload(hidden_coord)
	_expect(
		streamer._take_next_object_packet_visual_upload() == hidden_coord,
		"hidden work is focused before the live completion arrives",
	)
	var streamer_child_count: int = streamer.get_child_count()
	var view_child_count: int = live_view.get_child_count()
	var pool_count: int = streamer._object_presentation_layer_pool.size()
	var hot_count: int = streamer._hot_object_presentation_layers.size()
	var result: Dictionary = _make_live_object_completion(
		streamer,
		coord,
		revision,
	)
	streamer._object_presentation_backend._completed_object_presentation_buffers.append(result)
	streamer._drain_completed_object_presentation_buffers(1)

	_expect(
		streamer._object_presentation_results_by_chunk.has(coord),
		"object drain stores immutable CPU truth",
	)
	_expect(
		not streamer._object_presentation_inflight_chunks.has(coord),
		"object drain releases inflight ownership",
	)
	_expect(
		streamer._pending_hot_object_prestage_set.has(coord) \
				and streamer._pending_object_packet_visual_upload_set.has(coord),
		"object drain enqueues one lightweight priority envelope",
	)
	_expect(
		streamer.get_child_count() == streamer_child_count \
				and live_view.get_child_count() == view_child_count \
				and streamer._object_presentation_layer_pool.size() == pool_count \
				and streamer._hot_object_presentation_layers.size() == hot_count \
				and streamer._hot_object_presentation_root == null \
				and live_view._object_packet_layer == null,
		"drain performs no Node, pool, hot-layer or RenderingServer envelope mutation",
	)
	_expect(
		streamer._take_next_object_packet_visual_upload() == coord,
		"a live completion token preempts the focused hidden envelope",
	)
	streamer._object_presentation_visual_apply_tick()
	_expect(
		streamer._hot_object_presentation_root != null \
				and streamer._hot_object_presentation_layers.has(coord) \
				and not streamer._pending_hot_object_prestage_set.has(coord),
		"the first dispatcher envelope phase owns acquire and begin",
	)
	streamer.free()


func _test_terminal_failure_is_dispatcher_only() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	var coord := Vector2i(7, 0)
	var revision: int = 52
	streamer._generation_epoch = 23
	streamer._player_chunk_coord = coord
	streamer._base_chunk_packets[coord] = {"chunk_coord": coord}
	streamer._chunk_packets[coord] = {"chunk_coord": coord}
	streamer._object_presentation_revision_by_chunk[coord] = revision
	streamer._object_presentation_inflight_chunks[coord] = revision
	streamer._object_presentation_retry_by_chunk[coord] = {
		"revision": revision,
		"attempts": streamer.OBJECT_PRESENTATION_MAX_RETRY_ATTEMPTS,
	}
	var live_view: ChunkView = ChunkView.new()
	live_view.visible = false
	streamer.add_child(live_view)
	streamer._chunk_views[coord] = live_view
	var streamer_child_count: int = streamer.get_child_count()
	var failed_result := {
		"success": false,
		"message": "synthetic terminal dispatcher proof",
		"target_chunk": coord,
		"epoch": streamer._generation_epoch,
		"revision": revision,
		"catalog_generation": streamer._layered_object_asset_catalog.get_catalog_generation(),
	}
	streamer._object_presentation_backend._completed_object_presentation_buffers.append(failed_result)
	streamer._drain_completed_object_presentation_buffers(1)
	_expect(
		streamer._object_presentation_terminal_fallback_by_chunk.has(coord) \
				and streamer._pending_object_packet_visual_upload_set.has(coord),
		"terminal worker failure records and queues fallback",
	)
	_expect(
		streamer.get_child_count() == streamer_child_count \
				and streamer._hot_object_presentation_root == null \
				and live_view._object_packet_layer == null,
		"terminal failure drain does not allocate the compatibility graph",
	)

	# If the view disappears before its dispatcher turn, retain the terminal
	# marker and let the next publish-side queue-only handoff restore its token.
	streamer._chunk_views.erase(coord)
	streamer.remove_child(live_view)
	live_view.free()
	_advance_object_presentation_work_phase(streamer)
	_expect(
		streamer._object_presentation_terminal_fallback_by_chunk.has(coord) \
				and not streamer._pending_object_packet_visual_upload_set.has(coord),
		"terminal fallback survives view eviction without an idle upload spin",
	)
	var replacement_view: ChunkView = ChunkView.new()
	replacement_view.visible = false
	streamer.add_child(replacement_view)
	streamer._chunk_views[coord] = replacement_view
	_expect(
		streamer._queue_object_presentation_for_live_view(coord) \
				and streamer._pending_object_packet_visual_upload_set.has(coord),
		"republish requeues a retained terminal fallback without applying it",
	)
	_expect(
		replacement_view._object_packet_layer == null,
		"republish handoff remains queue-only",
	)
	_advance_object_presentation_work_phase(streamer)
	_expect(
		not streamer._object_presentation_terminal_fallback_by_chunk.has(coord) \
				and replacement_view._object_packet_layer != null \
				and replacement_view.is_object_blocking_presentation_ready(),
		"terminal compatibility graph is built only in its dispatcher phase",
	)
	streamer.free()


func _make_live_object_completion(
		streamer: Node,
		coord: Vector2i,
		revision: int,
) -> Dictionary:
	var tree_buffers: Array = []
	var rock_buffers: Array = []
	tree_buffers.resize(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK)
	rock_buffers.resize(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK)
	for stripe_index: int in range(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK):
		tree_buffers[stripe_index] = PackedFloat32Array()
		rock_buffers[stripe_index] = PackedFloat32Array()
	tree_buffers[0] = PackedFloat32Array([
		1.0, 0.0, 0.0, 1.0, 32.0, 32.0,
		1.0, 1.0, 1.0, 1.0, 0.0, 0.0,
	])
	return {
		"success": true,
		"target_chunk": coord,
		"epoch": streamer._generation_epoch,
		"revision": revision,
		"catalog_generation": streamer._layered_object_asset_catalog.get_catalog_generation(),
		"object_count": 1,
		"tree_instance_count": 1,
		"rock_instance_count": 0,
		"living_flora_count": 0,
		"spiky_flora_count": 0,
		"living_flora_record_count": 0,
		"spiky_flora_record_count": 0,
		"suppressed_instance_count": 0,
		"ignored_instance_count": 0,
		"tree_atlas_bucket_buffers": tree_buffers,
		"rock_atlas_bucket_buffers": rock_buffers,
		"tree_collision_records": PackedFloat32Array([32.0, 17.0, 20.0, 34.0]),
		"living_flora_bucket_buffers": [],
		"living_flora_shadow_buffer": PackedFloat32Array(),
		"spiky_flora_atlas_bucket_buffers": [],
		"spiky_flora_atlas_bank_count": 0,
		"buffer_float_count": 16,
		"payload_bytes": 64,
	}


func _test_stale_hidden_hot_work_is_pruned() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	streamer._player_chunk_coord = Vector2i.ZERO
	var stale_coord := Vector2i(40, 0)
	var stale_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	streamer.add_child(stale_layer)
	streamer._add_hot_object_entry(
		stale_coord,
		{
			"layer": stale_layer,
			"ready": false,
			"gpu_buffer_bytes": 48,
			"canvas_item_count": 1,
			"collider_count": 0,
		},
	)
	streamer._queue_object_packet_visual_upload(stale_coord)
	streamer._queue_hot_object_prestage(stale_coord)
	streamer._prune_stale_hot_object_presentation_work()
	_expect(
		not streamer._hot_object_presentation_layers.has(stale_coord),
		"an incomplete hidden transaction outside source demand must be evicted",
	)
	_expect(
		not streamer._pending_object_packet_visual_upload_set.has(stale_coord) \
				and not streamer._pending_hot_object_prestage_set.has(stale_coord),
		"stale hidden upload and prestage envelopes must be removed together",
	)
	streamer.free()


func _test_live_hot_budget_pressure_does_not_restage_recursively() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	var coord := Vector2i(2, 1)
	streamer._player_chunk_coord = coord
	var live_view: ChunkView = ChunkView.new()
	live_view.visible = false
	streamer.add_child(live_view)
	streamer._chunk_views[coord] = live_view
	var staging_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	streamer.add_child(staging_layer)
	streamer._add_hot_object_entry(
		coord,
		{
			"layer": staging_layer,
			"ready": false,
			"gpu_buffer_bytes": int(streamer.HOT_OBJECT_PRESENTATION_CACHE_MAX_BYTES) + 1,
			"canvas_item_count": 1,
			"collider_count": 0,
		},
	)
	streamer._trim_hot_object_presentation_cache_to_budget()
	_expect(
		streamer._hot_object_presentation_layers.has(coord),
		"cache pressure must exempt the only incomplete transaction of a live view",
	)
	streamer._chunk_views.erase(coord)
	streamer._trim_hot_object_presentation_cache_to_budget()
	_expect(
		not streamer._hot_object_presentation_layers.has(coord),
		"the same reservation must become evictable after its live view is gone",
	)
	streamer.free()


func _test_retire_dispatcher_and_hidden_admission_backpressure() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	streamer._generation_epoch = 71
	streamer._player_chunk_coord = Vector2i.ZERO
	var retiring_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	streamer.add_child(retiring_layer)
	_expect(
		retiring_layer.prepare_presentation_envelope(
			streamer._layered_object_asset_catalog,
			0,
		),
		"retire dispatcher probe prepares a production envelope",
	)
	var retiring_result: Dictionary = _make_live_object_completion(
		streamer,
		Vector2i(9, 9),
		1,
	)
	_expect(
		retiring_layer.begin_presentation_result(
			retiring_result,
			streamer._layered_object_asset_catalog,
		),
		"retire dispatcher probe begins",
	)
	var prepare_guard: int = 32
	while retiring_layer.has_pending_presentation_apply() and prepare_guard > 0:
		retiring_layer.apply_next_presentation_slice(1, 4, 1)
		prepare_guard -= 1
	_expect(prepare_guard > 0 and retiring_layer.is_presentation_complete(), "retire probe commits")
	streamer._release_object_presentation_layer(retiring_layer)
	_expect(streamer._object_presentation_retire_queue.size() == 1, "release enters retire queue")

	var dispatcher: FrameBudgetDispatcherNode = FrameBudgetDispatcherNode.new()
	root.add_child(dispatcher)
	dispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		10.0,
		Callable(streamer, "_object_presentation_retire_tick"),
		&"test.object_retire_one_phase",
	)
	var phase_count_before: int = streamer._object_presentation_retire_phase_count_total
	dispatcher._process(0.0)
	_expect(
		streamer._object_presentation_retire_phase_count_total - phase_count_before == 1,
		"FrameBudgetDispatcher runs exactly one retire phase per frame",
	)
	_expect(
		streamer._object_presentation_retire_queue.size() == 1 \
				and streamer._object_presentation_retire_colliders == 1,
		"final visual reset is not chained with collider or pool transition",
	)
	_expect(
		streamer._object_presentation_retire_phase_usec_max_total < 50_000,
		"retire phase stays below the hard smoke watchdog",
	)

	var hidden_coords: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(0, -1),
		Vector2i(1, 1),
	]
	for index: int in range(hidden_coords.size()):
		var coord: Vector2i = hidden_coords[index]
		var revision: int = 100 + index
		streamer._object_presentation_revision_by_chunk[coord] = revision
		streamer._object_presentation_results_by_chunk[coord] = \
				_make_live_object_completion(streamer, coord, revision)
		streamer._queue_hot_object_prestage(coord)
	var hot_count_before: int = streamer._hot_object_presentation_layers.size()
	var total_gpu_before: int = streamer._object_presentation_total_gpu_bytes()
	var total_canvas_before: int = streamer._object_presentation_total_canvas_items()
	for attempt: int in range(hidden_coords.size() * 2):
		_advance_object_presentation_work_phase(streamer)
	_expect(
		streamer._hot_object_presentation_layers.size() == hot_count_before \
				and streamer._pending_hot_object_prestage_set.size() == hidden_coords.size(),
		"busy retirement backpressures every source-only GPU envelope without losing it",
	)
	_expect(
		streamer._object_presentation_total_gpu_bytes() == total_gpu_before \
				and streamer._object_presentation_total_canvas_items() == total_canvas_before,
		"blocked hidden envelopes cannot grow exact residency",
	)

	var live_coord := Vector2i.ZERO
	var live_revision: int = 200
	var live_view: ChunkView = ChunkView.new()
	live_view.visible = false
	streamer.add_child(live_view)
	streamer._chunk_views[live_coord] = live_view
	streamer._object_presentation_revision_by_chunk[live_coord] = live_revision
	streamer._object_presentation_results_by_chunk[live_coord] = \
			_make_live_object_completion(streamer, live_coord, live_revision)
	streamer._queue_hot_object_prestage(live_coord)
	_advance_object_presentation_work_phase(streamer)
	_expect(
		streamer._hot_object_presentation_layers.has(live_coord) \
				and not streamer._pending_hot_object_prestage_set.has(live_coord),
		"live/reveal envelope bypasses hidden admission backpressure",
	)
	var live_entry: Dictionary = streamer._take_hot_object_entry(live_coord)
	var live_layer: WorldObjectPacketLayer = live_entry.get("layer", null) as WorldObjectPacketLayer
	streamer._drop_object_packet_visual_upload(live_coord)
	if live_layer != null:
		streamer._release_object_presentation_layer(live_layer)
	streamer._chunk_views.erase(live_coord)
	streamer.remove_child(live_view)
	live_view.free()

	var drain_guard: int = 64
	while not streamer._object_presentation_retire_queue.is_empty() and drain_guard > 0:
		phase_count_before = streamer._object_presentation_retire_phase_count_total
		dispatcher._process(0.0)
		_expect(
			streamer._object_presentation_retire_phase_count_total - phase_count_before == 1,
			"each autonomous retire frame performs one phase",
		)
		drain_guard -= 1
	_expect(drain_guard > 0, "retire queue drains without a new streaming event")
	var pending_hidden_before: int = streamer._pending_hot_object_prestage_set.size()
	_advance_object_presentation_work_phase(streamer)
	_expect(
		streamer._hot_object_presentation_layers.size() == 1 \
				and streamer._pending_hot_object_prestage_set.size() == pending_hidden_before - 1,
		"retained hidden token starts automatically after retirement clears",
	)
	dispatcher.free()
	streamer.free()


func _test_incremental_cold_envelope_revision_and_accounting() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	streamer._generation_epoch = 81
	streamer._player_chunk_coord = Vector2i.ZERO
	var stale_coord := Vector2i(1, 0)
	var stale_revision: int = 301
	streamer._object_presentation_revision_by_chunk[stale_coord] = stale_revision
	streamer._object_presentation_results_by_chunk[stale_coord] = \
			_make_live_object_completion(streamer, stale_coord, stale_revision)
	streamer._queue_hot_object_prestage(stale_coord)
	streamer._object_presentation_visual_apply_tick()
	_expect(
		streamer._object_packet_visual_selection_phase_prepared \
				and not streamer._hot_object_presentation_layers.has(stale_coord),
		"dirty O(queue) priority selection is a standalone dispatcher phase",
	)
	streamer._object_presentation_visual_apply_tick()
	var stale_entry: Dictionary = streamer._hot_object_presentation_layers.get(
		stale_coord,
		{ },
	) as Dictionary
	var stale_layer: WorldObjectPacketLayer = stale_entry.get("layer", null) as WorldObjectPacketLayer
	_expect(
		stale_layer != null \
				and bool(stale_entry.get("envelope_pending", false)) \
				and str(stale_layer.get_debug_state().get("native_apply_state", "")) == "IDLE",
		"cold acquire stores an owned IDLE shell before fixed graph construction",
	)
	var planned_canvas_items: int = int(stale_entry.get("canvas_item_count", 0))
	_advance_object_presentation_work_phase(streamer)
	_expect(
		stale_layer.get_node_or_null("LayeredTreeBatchLayer/TreeDepthLadder") != null \
				and stale_layer.get_node_or_null("LayeredSmallRockBatchLayer") == null,
		"one cold envelope callback prepares only the tree fixed graph",
	)
	var actual_partial_canvas: int = int(
		stale_layer.get_retained_residency_weight().get("canvas_item_count", 0),
	)
	_expect(
		streamer._hot_object_presentation_cache_canvas_items == planned_canvas_items \
				and planned_canvas_items >= actual_partial_canvas,
		"partial shell remains conservatively accounted while its real graph grows",
	)
	streamer._object_presentation_revision_by_chunk[stale_coord] = stale_revision + 1
	_advance_object_presentation_work_phase(streamer)
	_expect(
		not streamer._hot_object_presentation_layers.has(stale_coord) \
				and streamer._object_presentation_retire_queue.size() == 1 \
				and str(stale_layer.get_debug_state().get("native_apply_state", "")) == "IDLE",
		"stale mid-envelope revision is evicted into bounded retirement before begin",
	)
	var retire_guard: int = 16
	while not streamer._object_presentation_retire_queue.is_empty() and retire_guard > 0:
		streamer._object_presentation_retire_tick()
		retire_guard -= 1
	_expect(retire_guard > 0, "partial stale shell retirement drains")

	var coord := Vector2i(0, 1)
	var revision: int = 302
	streamer._object_presentation_revision_by_chunk[coord] = revision
	streamer._object_presentation_results_by_chunk[coord] = \
			_make_live_object_completion(streamer, coord, revision)
	streamer._queue_hot_object_prestage(coord)
	_advance_object_presentation_work_phase(streamer)
	var entry: Dictionary = streamer._hot_object_presentation_layers.get(coord, { }) as Dictionary
	var layer: WorldObjectPacketLayer = entry.get("layer", null) as WorldObjectPacketLayer
	var previous_actual_canvas: int = int(
		layer.get_retained_residency_weight().get("canvas_item_count", 0),
	)
	var envelope_guard: int = 16
	while bool(entry.get("envelope_pending", false)) and envelope_guard > 0:
		_expect(
			str(layer.get_debug_state().get("native_apply_state", "")) == "IDLE",
			"fixed envelope phases cannot enter ordinary apply",
		)
		_advance_object_presentation_work_phase(streamer)
		entry = streamer._hot_object_presentation_layers.get(coord, { }) as Dictionary
		var actual_canvas: int = int(
			layer.get_retained_residency_weight().get("canvas_item_count", 0),
		)
		_expect(actual_canvas >= previous_actual_canvas, "fixed graph CanvasItem growth is monotonic")
		_expect(
			int(entry.get("canvas_item_count", 0)) >= actual_canvas,
			"every partial fixed graph stays inside its cache reservation",
		)
		previous_actual_canvas = actual_canvas
		envelope_guard -= 1
	_expect(
		envelope_guard > 0 \
				and not bool(entry.get("envelope_pending", true)) \
				and str(layer.get_debug_state().get("native_apply_state", "")) == "TREE_BUCKETS" \
				and layer.get_raw_multimesh_upload_count_total() == 0,
		"begin runs only after fixed graph readiness and performs no raw upload",
	)
	var allocation_has_safe_continuation: bool = \
			streamer._object_presentation_visual_apply_tick()
	entry = streamer._hot_object_presentation_layers.get(coord, { }) as Dictionary
	var allocation_started_families: Dictionary = entry.get(
		"allocation_started_families",
		{ },
	) as Dictionary
	_expect(
		bool(
			(layer.get_debug_state().get("tree_batch", { }) as Dictionary).get(
				"last_slice_created_slot",
				false,
			),
		),
		"missing first slot is a standalone visual allocation phase",
	)
	_expect(
		allocation_started_families.has(
			WorldObjectPacketLayer.PRESENTATION_PHASE_TREE_SLOT_ALLOCATION,
		) \
				and layer.get_next_presentation_apply_phase_hint() \
						== WorldObjectPacketLayer.PRESENTATION_PHASE_TREE_APPLY,
		"first tree allocation is recorded per family and leaves raw apply as the next phase",
	)
	_expect(
		not allocation_has_safe_continuation,
		"first family allocation yields before the dispatcher can upload in the same frame",
	)
	_expect(
		layer.get_raw_multimesh_upload_count_total() == 0,
		"standalone slot allocation does not upload its pending raw buffer",
	)
	var upload_has_safe_continuation: bool = \
			streamer._object_presentation_visual_apply_tick()
	_expect(
		layer.get_raw_multimesh_upload_count_total() == 2,
		"the following warmed phase uploads tree visual and shadow buffers",
	)
	_expect(
		not upload_has_safe_continuation \
				and layer.get_next_presentation_apply_phase_hint() \
						== WorldObjectPacketLayer.PRESENTATION_PHASE_TREE_COLLISIONS,
		"tree upload to collider transition yields at the heterogeneous frame boundary",
	)
	streamer.free()


func _test_multi_victim_retirement_drains_autonomously() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	streamer._player_chunk_coord = Vector2i.ZERO
	var initial_count: int = int(streamer.HOT_OBJECT_PRESENTATION_CACHE_MAX_CHUNKS) + 3
	for index: int in range(initial_count):
		var layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
		streamer.add_child(layer)
		streamer._add_hot_object_entry(
			Vector2i(index % 64, 1000 + index),
			{
				"layer": layer,
				"ready": true,
				"gpu_buffer_bytes": 0,
				"canvas_item_count": 1,
				"collider_count": 0,
			},
		)
	streamer._trim_hot_object_presentation_cache_to_budget()
	_expect(
		streamer._hot_object_presentation_layers.size() == initial_count - 1 \
				and streamer._object_presentation_retire_queue.size() == 1,
		"one trim call selects exactly one victim",
	)
	streamer._trim_hot_object_presentation_cache_to_budget()
	_expect(
		streamer._hot_object_presentation_layers.size() == initial_count - 1,
		"pending retirement blocks selection of a second victim",
	)
	var previous_hot_count: int = streamer._hot_object_presentation_layers.size()
	var previous_gpu_bytes: int = streamer._object_presentation_total_gpu_bytes()
	var previous_canvas_items: int = streamer._object_presentation_total_canvas_items()
	var guard: int = 64
	while (streamer._hot_object_presentation_cache_is_over_budget() \
			or not streamer._object_presentation_retire_queue.is_empty()) and guard > 0:
		var phase_before: int = streamer._object_presentation_retire_phase_count_total
		streamer._object_presentation_retire_tick()
		var hot_count: int = streamer._hot_object_presentation_layers.size()
		var gpu_bytes: int = streamer._object_presentation_total_gpu_bytes()
		var canvas_items: int = streamer._object_presentation_total_canvas_items()
		_expect(
			streamer._object_presentation_retire_phase_count_total - phase_before <= 1,
			"autonomous cache drain performs at most one phase per frame",
		)
		_expect(hot_count <= previous_hot_count, "autonomous cache size is monotonic")
		_expect(
			gpu_bytes <= previous_gpu_bytes and canvas_items <= previous_canvas_items,
			"autonomous exact residency is monotonic",
		)
		previous_hot_count = hot_count
		previous_gpu_bytes = gpu_bytes
		previous_canvas_items = canvas_items
		guard -= 1
	_expect(
		guard > 0 \
				and streamer._hot_object_presentation_layers.size() \
						<= streamer.HOT_OBJECT_PRESENTATION_CACHE_MAX_CHUNKS \
				and streamer._object_presentation_retire_queue.is_empty(),
		"multi-victim pressure returns under cap without a new insert",
	)
	streamer.free()


func _test_clean_retire_pool_decision_tracks_violated_dimension() -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var gpu_streamer: Node = streamer_script.new() as Node
	var clean_candidate: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	gpu_streamer.add_child(clean_candidate)
	gpu_streamer._release_object_presentation_layer(clean_candidate)
	var gpu_hot_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	gpu_streamer.add_child(gpu_hot_layer)
	gpu_streamer._add_hot_object_entry(
		Vector2i(50, 0),
		{
			"layer": gpu_hot_layer,
			"ready": true,
			"gpu_buffer_bytes": int(gpu_streamer.HOT_OBJECT_PRESENTATION_CACHE_MAX_BYTES) + 1,
			"canvas_item_count": 1,
			"collider_count": 0,
		},
	)
	gpu_streamer._object_presentation_retire_tick()
	_expect(
		gpu_streamer._object_presentation_retire_queue.is_empty() \
				and gpu_streamer._object_presentation_layer_pool.size() == 1,
		"GPU-only overage pools a clean zero-GPU candidate in one transition",
	)
	gpu_streamer._object_presentation_retire_tick()
	_expect(
		not gpu_streamer._hot_object_presentation_layers.has(Vector2i(50, 0)) \
				and gpu_streamer._object_presentation_retire_queue.size() == 1,
		"the next autonomous phase evicts the real GPU-heavy hot victim",
	)
	gpu_streamer.free()

	var canvas_streamer: Node = streamer_script.new() as Node
	var canvas_candidate: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	canvas_streamer.add_child(canvas_candidate)
	_expect(
		canvas_candidate.prepare_presentation_envelope(
			canvas_streamer._layered_object_asset_catalog,
			1,
		),
		"canvas-pressure candidate owns reusable slot groups",
	)
	var candidate_weight: Dictionary = canvas_candidate.get_retained_residency_weight()
	var candidate_canvas_items: int = int(candidate_weight.get("canvas_item_count", 0))
	var slots_before: int = _pooled_family_slot_count(canvas_candidate)
	canvas_streamer._release_object_presentation_layer(canvas_candidate)
	var canvas_hot_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	canvas_streamer.add_child(canvas_hot_layer)
	canvas_streamer._add_hot_object_entry(
		Vector2i(60, 0),
		{
			"layer": canvas_hot_layer,
			"ready": true,
			"gpu_buffer_bytes": 0,
			"canvas_item_count": int(canvas_streamer.HOT_OBJECT_PRESENTATION_CACHE_MAX_CANVAS_ITEMS) \
					- candidate_canvas_items + 1,
			"collider_count": 0,
		},
	)
	canvas_streamer._object_presentation_retire_tick()
	var slots_after_one_shrink: int = _pooled_family_slot_count(canvas_candidate)
	_expect(
		slots_after_one_shrink == slots_before - 1 \
				and canvas_streamer._object_presentation_retire_queue.size() == 1,
		"canvas overage removes exactly one useful slot group",
	)
	canvas_streamer._object_presentation_retire_tick()
	_expect(
		canvas_streamer._object_presentation_retire_queue.is_empty() \
				and canvas_streamer._object_presentation_layer_pool.has(canvas_candidate) \
				and _pooled_family_slot_count(canvas_candidate) == slots_after_one_shrink,
		"shrink re-evaluates pressure and preserves the now-admissible remainder",
	)
	canvas_streamer.free()


func _pooled_family_slot_count(layer: WorldObjectPacketLayer) -> int:
	var state: Dictionary = layer.get_debug_state()
	return int((state.get("tree_batch", { }) as Dictionary).get("pooled_slot_count", 0)) \
			+ int((state.get("rock_batch", { }) as Dictionary).get("pooled_slot_count", 0)) \
			+ int((state.get("living_flora_batch", { }) as Dictionary).get("pooled_slot_count", 0)) \
			+ int((state.get("spiky_flora_batch", { }) as Dictionary).get("pooled_slot_count", 0))


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## Test helper for one logical work phase. Production intentionally spends a
## separate callback on a dirty O(queue) priority refresh; tests that validate
## envelope/upload state advance past that scheduling phase explicitly.
func _advance_object_presentation_work_phase(streamer: Node) -> void:
	streamer._object_presentation_visual_apply_tick()
	var priority_guard: int = 128
	while streamer._object_packet_visual_priority_scan_active and priority_guard > 0:
		streamer._object_presentation_visual_apply_tick()
		priority_guard -= 1
	_expect(priority_guard > 0, "bounded object priority scan completes")
	if streamer._object_packet_visual_selection_phase_prepared:
		streamer._object_presentation_visual_apply_tick()
