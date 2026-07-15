extends SceneTree

const GrassRenderPage = preload("res://core/systems/world/grass_render_page.gd")
const GrassRenderPageManager = preload(
	"res://core/systems/world/grass_render_page_manager.gd"
)

const EPOCH: int = 17
const STRIDE: int = 12

var _failures: Array[String] = []


class FakeBackend:
	extends RefCounted

	var requests: Array[Dictionary] = []
	var pending_by_page: Dictionary = { }
	var completed: Array[Dictionary] = []
	var request_count: int = 0
	var sync_count: int = 0

	func queue_grass_render_page_request(
			page_coord: Vector2i,
			contributors: Array,
			page_width_chunks: int,
			chunk_size_px: float,
			epoch: int,
			page_revision: int,
			priority: int = 0,
			priority_class: int = 2,
	) -> void:
		var request := {
			"page_coord": page_coord,
			"contributors": contributors.duplicate(false),
			"page_width_chunks": page_width_chunks,
			"chunk_size_px": chunk_size_px,
			"epoch": epoch,
			"page_revision": page_revision,
			"priority": priority,
			"priority_class": priority_class,
		}
		requests.append(request)
		pending_by_page[page_coord] = request
		request_count += 1

	func sync_grass_render_page_requests(
			epoch: int,
			desired: Dictionary,
	) -> Array[Vector2i]:
		var removed: Array[Vector2i] = []
		for page_variant: Variant in pending_by_page.keys():
			var page_coord: Vector2i = page_variant as Vector2i
			var request: Dictionary = pending_by_page[page_coord] as Dictionary
			if int(request.epoch) != epoch:
				continue
			var current: Dictionary = desired.get(page_coord, { }) as Dictionary
			if current.is_empty() or int(current.get("page_revision", -1)) \
					!= int(request.page_revision):
				pending_by_page.erase(page_coord)
				removed.append(page_coord)
		sync_count += 1
		return removed

	func drain_completed_grass_render_pages(max_count: int) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		while result.size() < max_count and not completed.is_empty():
			result.append(completed.pop_front() as Dictionary)
		return result

	func inject_result(request: Dictionary, revision_override: int = -1) -> void:
		completed.append(_make_page_result(request, revision_override))

	func _make_page_result(request: Dictionary, revision_override: int) -> Dictionary:
		var buckets: Array = []
		buckets.resize(GrassRenderPage.STRIPE_COUNT)
		for stripe: int in range(buckets.size()):
			buckets[stripe] = PackedFloat32Array()
		var merged := PackedFloat32Array()
		var revisions := PackedInt64Array()
		revisions.resize(GrassRenderPage.PAGE_SLOT_COUNT)
		revisions.fill(0)
		var mask: int = 0
		for contributor_variant: Variant in request.contributors as Array:
			var contributor: Dictionary = contributor_variant as Dictionary
			var slot: int = int(contributor.slot)
			mask |= 1 << slot
			revisions[slot] = int(contributor.revision)
			merged.append_array(
				(contributor.bucket_buffers as Array)[0] as PackedFloat32Array,
			)
		buckets[0] = merged
		return {
			"success": true,
			"epoch": int(request.epoch),
			"page_coord": request.page_coord as Vector2i,
			"page_revision": revision_override if revision_override >= 0 \
					else int(request.page_revision),
			"contributor_mask": mask,
			"contributor_revisions": revisions,
			"bucket_buffers": buckets,
			"directional_shadow_buffer": merged,
			"shadow_buffer": PackedFloat32Array(),
			"spore_buffer": PackedFloat32Array(),
			"worker_elapsed_ms": 2.5,
			"request_to_complete_ms": 4.0,
		}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var owner := Node2D.new()
	owner.name = "GrassPageOwner"
	root.add_child(owner)
	var backend := FakeBackend.new()
	var manager := GrassRenderPageManager.new()
	var texture: Texture2D = _make_texture()
	var material: ShaderMaterial = _make_material()
	_expect(
		manager.configure(
			owner,
			backend,
			texture,
			material,
			texture,
			material,
			material,
			material,
			1,
		),
		"manager configures against the fixed page/backend contract",
	)
	manager.set_epoch(EPOCH)
	var sync_baseline: int = backend.sync_count

	var first_chunks: Array[Vector2i] = []
	var first_results: Array[Dictionary] = []
	var first_priorities: Dictionary = { }
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		var coord := Vector2i(slot, 0)
		var revision: int = 101 + slot
		first_chunks.append(coord)
		first_priorities[coord] = slot
		manager.set_chunk_active(coord, true, revision, slot)
		var result: Dictionary = _make_chunk_result(coord, revision, float(slot))
		first_results.append(result)
		_expect(manager.accept_chunk_result(coord, result, slot), "slot %d result accepts" % slot)
	manager.set_source_demand(first_chunks, first_priorities)
	_expect(owner.get_child_count() == 0, "accept/demand allocate no page Nodes")
	_expect(backend.sync_count == sync_baseline, "batched mutators defer backend queue sync")
	var first_queued: int = manager.flush_dirty_requests()
	_expect(first_queued == 1, "four dirty accepts coalesce into one merge")
	_expect(backend.request_count == 1, "backend observes one page request")
	_expect(backend.sync_count == sync_baseline + 1, "flush performs one coalesced queue sync")
	_expect(owner.get_child_count() == 0, "flush allocates no page Nodes")

	var first_request: Dictionary = backend.requests[0]
	var requested_contributors: Array = first_request.contributors as Array
	_expect(requested_contributors.size() == 4, "request owns four contributor envelopes")
	for slot: int in range(requested_contributors.size()):
		var contributor: Dictionary = requested_contributors[slot] as Dictionary
		_expect(int(contributor.slot) == slot, "contributors retain fixed slot order")
		_expect(
			is_same(contributor.bucket_buffers, first_results[slot].bucket_buffers),
			"slot %d keeps its immutable packed payload handles" % slot,
		)
	_expect(int(first_request.priority_class) == 1, "active page submits as REVEAL")

	backend.inject_result(first_request, int(first_request.page_revision) - 1)
	_expect(manager.drain_completed(1) == 0, "stale page completion rejects")
	_expect(owner.get_child_count() == 0, "stale drain allocates no page Node")
	_expect(
		int(manager.get_debug_state().stale_completion_reject_count_total) == 1,
		"stale rejection is observable",
	)
	backend.inject_result(first_request)
	_expect(manager.drain_completed(1) == 1, "current native page result enters visual queue")
	_expect(owner.get_child_count() == 0, "successful drain still allocates no page Node")
	var timing_state: Dictionary = manager.get_debug_state()
	_expect(is_equal_approx(float(timing_state.get("worker_elapsed_ms_last", -1.0)), 2.5),
		"accepted page completion exposes native worker timing")
	_expect(is_equal_approx(float(timing_state.get("request_to_complete_ms_last", -1.0)), 4.0),
		"accepted page completion exposes request latency")

	_expect(manager.apply_next_visual_phase(), "cold page shell configures")
	_expect(owner.get_child_count() == 1, "first visual callback creates exactly one page")
	var first_page: GrassRenderPage = owner.get_child(0) as GrassRenderPage
	var shell_state: Dictionary = first_page.get_debug_state()
	var actual_shell_canvas_items: int = _count_canvas_items(first_page)
	_expect(bool(shell_state.configured), "cold shell is configured")
	_expect(actual_shell_canvas_items == 5, "cold shell owns exactly five real CanvasItems")
	var manager_shell_state: Dictionary = manager.get_debug_state()
	_expect(
		int(manager_shell_state.last_visual_callback_canvas_item_allocation_count) \
				== actual_shell_canvas_items,
		"manager reports every CanvasItem allocated by the cold shell callback",
	)
	_expect(actual_shell_canvas_items <= 5, "cold shell callback has an explicit bounded allocation")
	_expect(not bool(shell_state.pending), "configure callback does not also stage")
	_expect(int(shell_state.raw_multimesh_upload_count_total) == 0, "shell performs no upload")
	_expect(manager.apply_next_visual_phase(), "second callback stages native result")
	_expect(first_page.has_pending_upload(), "stage and first upload are separate callbacks")
	_expect(
		int(first_page.get_debug_state().raw_multimesh_upload_count_total) == 0,
		"stage callback performs no raw upload",
	)
	_drain_page_commit(manager, first_chunks[0], 101, 0)
	_expect(manager.is_chunk_committed(first_chunks[0], 101), "atomic page commit reveals slot")
	var committed_state: Dictionary = manager.get_debug_state()
	_expect(int(committed_state.commit_count_total) == 1, "manager records one atomic commit")
	_expect(int(committed_state.native_merge_complete_count_total) == 1, "one merge completes")
	manager.update_anchor(777)
	_expect(
		int(manager.get_debug_state().raw_upload_count_total) \
				== int(committed_state.raw_upload_count_total),
		"anchor update performs no visual upload",
	)

	var first_layer: MultiMeshInstance2D = first_page._albedo_layers[0]
	var first_rid: RID = first_layer.multimesh.get_rid()
	var requests_before_restore: int = backend.request_count
	var raw_before_restore: int = int(committed_state.raw_upload_count_total)
	var commits_before_restore: int = int(committed_state.commit_count_total)
	manager.set_source_demand([], { })
	for slot: int in range(first_chunks.size()):
		manager.set_chunk_active(first_chunks[slot], false, 101 + slot, slot)
	manager.set_chunk_active(first_chunks[0], true, 101, 0)
	manager.set_source_demand([first_chunks[0]], {first_chunks[0]: 0})
	_expect(manager.is_chunk_committed(first_chunks[0], 101), "exact inactive page restores immediately")
	_expect(manager.flush_dirty_requests() == 0, "exact restore needs no native merge")
	var restored_state: Dictionary = manager.get_debug_state()
	_expect(backend.request_count == requests_before_restore, "restore emits no backend request")
	_expect(int(restored_state.raw_upload_count_total) == raw_before_restore, "restore uploads nothing")
	_expect(int(restored_state.commit_count_total) == commits_before_restore, "restore recommits nothing")
	_expect(int(restored_state.cache_hit_count_total) == 1, "exact restore is a cache hit")
	_expect(first_layer.multimesh.get_rid() == first_rid, "exact restore preserves front RID")

	var second_chunks: Array[Vector2i] = []
	var all_source: Array[Vector2i] = [first_chunks[0]]
	var all_priorities: Dictionary = {first_chunks[0]: 0}
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		var coord := Vector2i(4 + slot, 0)
		second_chunks.append(coord)
		all_source.append(coord)
		all_priorities[coord] = 20 + slot
	manager.set_source_demand(all_source, all_priorities)
	for slot: int in range(second_chunks.size()):
		_expect(
			manager.accept_chunk_result(
				second_chunks[slot],
				_make_chunk_result(second_chunks[slot], 201 + slot, 10.0 + slot),
				20 + slot,
			),
			"second page slot %d accepts" % slot,
		)
	_expect(manager.flush_dirty_requests() == 1, "second cold page also merges once")
	var second_request: Dictionary = backend.requests.back() as Dictionary
	_expect(int(second_request.priority_class) == 2, "source-only page submits as STREAMING")
	backend.inject_result(second_request)
	_expect(manager.drain_completed(1) == 1, "second page result queues")
	_drain_until_commit_count(manager, 2)
	_expect(int(manager.get_debug_state().resident_pages) == 2, "protected pages may exceed cap")
	manager.set_source_demand([first_chunks[0]], {first_chunks[0]: 0})
	_expect(manager.apply_next_visual_phase(), "one visual callback applies pending LRU eviction")
	var final_state: Dictionary = manager.get_debug_state()
	_expect(int(final_state.resident_pages) == 1, "inactive source-free LRU page evicts")
	_expect(int(final_state.eviction_count_total) == 1, "eviction counter advances once")
	_expect(is_instance_valid(first_page), "LRU never evicts the active page")
	_expect(first_layer.multimesh.get_rid() == first_rid, "active page front survives LRU trim")

	manager.clear()
	_expect(owner.get_child_count() == 0, "clear releases every page Node and payload owner")
	owner.free()
	_test_edge_page_demand(texture, material)
	_test_nonresident_traversal_pruning(texture, material)
	_test_ticket_queue_recreation(texture, material)
	_test_shell_pool_reuse_and_epoch_reset(texture, material)
	_test_completed_zero_demand_cancellation(texture, material)
	_test_staged_back_cancellation_preserves_front(texture, material)
	_finish()


func _test_edge_page_demand(texture: Texture2D, material: ShaderMaterial) -> void:
	var owner := Node2D.new()
	root.add_child(owner)
	var backend := FakeBackend.new()
	var manager := GrassRenderPageManager.new()
	_expect(
		manager.configure(
			owner, backend, texture, material, texture, material, material, material, 4,
		),
		"edge-page manager configures",
	)
	manager.set_epoch(EPOCH)
	var edge_chunks: Array[Vector2i] = []
	var edge_priorities: Dictionary = { }
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		var coord := Vector2i(8 + slot, 0)
		edge_chunks.append(coord)
		edge_priorities[coord] = slot
	manager.set_source_demand(edge_chunks, edge_priorities)
	manager.set_prestage_demand([edge_chunks[0]])
	manager.accept_chunk_result(edge_chunks[0], _make_chunk_result(edge_chunks[0], 301, 0.0), 0)
	_expect(
		manager.flush_dirty_requests() == 1,
		"prestage edge page does not wait for three optional source-only slots",
	)
	var edge_request: Dictionary = backend.requests.back() as Dictionary
	_expect((edge_request.contributors as Array).size() == 1, "edge merge contains ready contributor")
	_expect(int(edge_request.priority_class) == 1, "prestage page receives REVEAL priority")
	backend.inject_result(edge_request)
	_expect(manager.drain_completed(1) == 1, "edge reveal result queues")
	_drain_until_commit_count(manager, 1)
	manager.set_prestage_demand([])
	manager.set_source_demand([], { })
	manager.set_source_demand(edge_chunks, edge_priorities)
	manager.set_prestage_demand([edge_chunks[0]])
	_expect(
		manager.flush_dirty_requests() == 0,
		"final reveal demand reconciles transient source-first dirty without a rebuild",
	)
	_expect(
		int(manager.get_debug_state().cache_hit_count_total) == 1,
		"exact front re-entering prestage demand records one cache hit",
	)
	manager.set_chunk_active(edge_chunks[0], true, 301, 0)
	_expect(
		int(manager.get_debug_state().cache_hit_count_total) == 1,
		"prestage-to-active reveal does not double-count the same cache hit",
	)

	var pure_chunks: Array[Vector2i] = []
	var pure_priorities: Dictionary = { }
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		var coord := Vector2i(12 + slot, 0)
		pure_chunks.append(coord)
		pure_priorities[coord] = 20 + slot
	manager.set_prestage_demand([])
	manager.set_source_demand(pure_chunks, pure_priorities)
	manager.accept_chunk_result(pure_chunks[0], _make_chunk_result(pure_chunks[0], 401, 0.0), 20)
	_expect(manager.flush_dirty_requests() == 0, "pure-source page waits instead of partial upload")
	for slot: int in range(1, pure_chunks.size()):
		manager.accept_chunk_result(
			pure_chunks[slot],
			_make_chunk_result(pure_chunks[slot], 401 + slot, float(slot)),
			20 + slot,
		)
	_expect(manager.flush_dirty_requests() == 1, "pure-source page merges once all slots are exact")
	_expect(backend.request_count == 2, "edge reveal and complete pure-source page submit once each")
	manager.clear()
	owner.free()


func _test_nonresident_traversal_pruning(
		texture: Texture2D,
		material: ShaderMaterial,
) -> void:
	var owner := Node2D.new()
	root.add_child(owner)
	var backend := FakeBackend.new()
	var manager := GrassRenderPageManager.new()
	manager.configure(owner, backend, texture, material, texture, material, material, material, 4)
	manager.set_epoch(EPOCH)
	var absent := Vector2i(4000, 7)
	manager.invalidate_chunk(absent, 1)
	manager.set_chunk_active(absent, false, 1, 0)
	_expect(
		not manager.accept_chunk_result(absent, _make_chunk_result(absent, 1, 0.0), 0),
		"late zero-demand chunk result is rejected by the presentation cache",
	)
	_expect(int(manager.get_debug_state().entry_count) == 0,
		"invalidate, inactive update and late result create no empty entry")

	for step: int in range(512):
		var coord := Vector2i(step * GrassRenderPage.PAGE_WIDTH_CHUNKS, 7)
		manager.set_source_demand([coord], {coord: step})
		manager.set_prestage_demand([coord])
		manager.set_prestage_demand([])
		manager.set_source_demand([], { })
		manager.set_chunk_active(coord, true, 1000 + step, step)
		manager.set_chunk_active(coord, false, 1000 + step, step)
	var state: Dictionary = manager.get_debug_state()
	_expect(int(state.entry_count) == 0,
		"512-page traversal leaves zero nonresident demand tombstones")
	_expect(int(state.resident_pages) == 0, "demand-only traversal creates no residency")
	_expect(int(state.eviction_queue_physical) <= int(state.eviction_queue_capacity),
		"physical eviction queue stays inside its configured hard bound")
	manager.clear()
	owner.free()


func _test_ticket_queue_recreation(texture: Texture2D, material: ShaderMaterial) -> void:
	var owner := Node2D.new()
	root.add_child(owner)
	var backend := FakeBackend.new()
	var manager := GrassRenderPageManager.new()
	manager.configure(owner, backend, texture, material, texture, material, material, material, 1)
	manager.set_epoch(EPOCH)
	var coord := Vector2i(40, 11)
	var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(coord)
	var keeper_coord := Vector2i(44, 11)
	var keeper_page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(keeper_coord)
	var keeper: Dictionary = manager._get_or_create_entry(keeper_page_coord)
	keeper.resident = true
	keeper.active_mask = 1
	var old_entry: Dictionary = manager._get_or_create_entry(page_coord)
	old_entry.resident = true
	manager._resident_page_count = 2
	manager._touch_entry(old_entry)
	manager._schedule_lru_evictions()
	_expect(int(manager.get_debug_state().eviction_queue) == 1,
		"resident zero-demand entry receives one live eviction ticket")
	manager._cancel_scheduled_eviction(old_entry)
	old_entry.resident = false
	manager._resident_page_count = 1
	manager._retire_zero_demand_entry(page_coord, old_entry)

	var recreated: Dictionary = manager._get_or_create_entry(page_coord)
	recreated.resident = true
	manager._resident_page_count = 2
	manager._touch_entry(recreated)
	manager._schedule_lru_evictions()
	var queued: Dictionary = manager.get_debug_state()
	_expect(int(queued.eviction_queue) == 1,
		"same-coordinate recreation owns exactly one new live ticket")
	_expect(int(queued.eviction_queue_physical) == 2,
		"canceled old and live new generations coexist without aliasing")
	_expect(manager.apply_next_visual_phase(),
		"bounded cursor skips stale generation and applies the exact live ticket")
	var final_state: Dictionary = manager.get_debug_state()
	_expect(int(final_state.entry_count) == 1, "only protected keeper survives recreated eviction")
	_expect(int(final_state.resident_pages) == 1, "ticket recreation returns residency to cap")
	_expect(int(final_state.eviction_queue) == 0, "pending ticket count returns to zero")
	_expect(int(final_state.eviction_count_total) == 1,
		"stale generation cannot consume or double-count the new eviction")
	manager.clear()
	owner.free()


func _test_shell_pool_reuse_and_epoch_reset(
		texture: Texture2D,
		material: ShaderMaterial,
) -> void:
	var owner := Node2D.new()
	root.add_child(owner)
	var backend := FakeBackend.new()
	var manager := GrassRenderPageManager.new()
	manager.configure(owner, backend, texture, material, texture, material, material, material, 1)
	manager.set_epoch(EPOCH)
	var first_coord := Vector2i(80, 13)
	var first_revision: int = 701
	manager.set_chunk_active(first_coord, true, first_revision, 0)
	manager.accept_chunk_result(
		first_coord, _make_chunk_result(first_coord, first_revision, 1.0), 0,
	)
	_expect(manager.flush_dirty_requests() == 1, "pool fixture queues its first page")
	var canceled_request: Dictionary = backend.requests.back() as Dictionary
	manager.set_chunk_active(first_coord, false, first_revision, 0)
	manager.flush_dirty_requests()
	_expect(backend.pending_by_page.is_empty(),
		"demand removal synchronizes and cancels the inflight backend request")
	manager.set_chunk_active(first_coord, true, first_revision, 0)
	manager.accept_chunk_result(
		first_coord, _make_chunk_result(first_coord, first_revision, 1.0), 0,
	)
	_expect(manager.flush_dirty_requests() == 1, "reactivation requeues the exact contributor")
	var first_request: Dictionary = backend.requests.back() as Dictionary
	_expect(not is_same(first_request, canceled_request),
		"reactivation owns a fresh request envelope")
	backend.inject_result(first_request)
	manager.drain_completed(1)
	_drain_until_commit_count(manager, 1)
	var first_page: GrassRenderPage = owner.get_child(0) as GrassRenderPage
	var cold_allocations: int = int(
		manager.get_debug_state().shell_canvas_item_allocation_count_total,
	)
	_expect(cold_allocations == 5, "first page allocates the bounded five-CanvasItem shell")

	var second_coord := Vector2i(84, 13)
	var second_revision: int = 801
	manager.set_chunk_active(second_coord, true, second_revision, 0)
	manager.accept_chunk_result(
		second_coord, _make_chunk_result(second_coord, second_revision, 2.0), 0,
	)
	for cycle: int in range(128):
		manager.set_chunk_active(first_coord, false, first_revision, cycle)
		manager.set_chunk_active(first_coord, true, first_revision, cycle)
	manager.set_chunk_active(first_coord, false, first_revision, 200)
	var churn_state: Dictionary = manager.get_debug_state()
	_expect(int(churn_state.eviction_queue) == 1,
		"cancel/reschedule churn keeps one live ticket per entry")
	_expect(int(churn_state.eviction_queue_physical) == 1,
		"cancel/reschedule reuses its unconsumed physical ticket")

	manager.flush_dirty_requests()
	var second_request: Dictionary = backend.requests.back() as Dictionary
	backend.inject_result(second_request)
	manager.drain_completed(1)
	_expect(manager.apply_next_visual_phase(),
		"over-cap cold focus evicts before allocating another shell")
	var pooled_state: Dictionary = manager.get_debug_state()
	_expect(owner.get_child_count() == 0, "evicted shell is detached from the render tree")
	_expect(int(pooled_state.shell_pool_size) == 1, "evicted shell enters bounded pool")
	_expect(not bool(first_page.get_debug_state().configured),
		"pooled shell is cleared and unconfigured")
	_expect(not first_page.has_pending_upload(), "pooled shell owns no pending upload")
	_expect(manager.apply_next_visual_phase(), "next callback configures the focused pooled shell")
	var reused_page: GrassRenderPage = owner.get_child(0) as GrassRenderPage
	_expect(is_same(reused_page, first_page), "next page reuses the exact detached shell identity")
	var reused_state: Dictionary = manager.get_debug_state()
	_expect(int(reused_state.last_visual_callback_canvas_item_allocation_count) == 0,
		"pooled configure allocates zero CanvasItems")
	_expect(int(reused_state.shell_canvas_item_allocation_count_total) == cold_allocations,
		"reuse does not inflate lifetime CanvasItem allocation telemetry")
	_drain_until_commit_count(manager, 2)

	var third_coord := Vector2i(88, 13)
	manager.set_chunk_active(third_coord, true, 901, 0)
	manager.accept_chunk_result(third_coord, _make_chunk_result(third_coord, 901, 3.0), 0)
	manager.set_chunk_active(second_coord, false, second_revision, 0)
	_expect(manager.apply_next_visual_phase(), "second page returns its shell to the pool")
	var before_epoch: Dictionary = manager.get_debug_state()
	_expect(int(before_epoch.shell_pool_size) == 1, "epoch fixture owns one pooled shell")
	manager.set_source_demand([Vector2i(120, 13)], {Vector2i(120, 13): 0})
	manager.set_epoch(EPOCH + 1)
	var epoch_state: Dictionary = manager.get_debug_state()
	_expect(owner.get_child_count() == 0, "epoch reset leaves no attached page")
	_expect(int(epoch_state.entry_count) == 0, "epoch reset clears resident and demand entries")
	_expect(int(epoch_state.shell_pool_size) == 0, "epoch reset frees the detached shell pool")
	_expect(int(epoch_state.eviction_queue) == 0, "epoch reset clears live eviction tickets")
	_expect(int(epoch_state.eviction_queue_physical) == 0, "epoch reset clears physical tokens")
	_expect(int(epoch_state.eviction_queue_cursor) == 0, "epoch reset rewinds queue cursor")
	_expect(not is_instance_valid(reused_page), "epoch reset frees pooled shell identity")
	manager.clear()
	owner.free()


func _test_completed_zero_demand_cancellation(
		texture: Texture2D,
		material: ShaderMaterial,
) -> void:
	var owner := Node2D.new()
	root.add_child(owner)
	var backend := FakeBackend.new()
	var manager := GrassRenderPageManager.new()
	manager.configure(owner, backend, texture, material, texture, material, material, material, 4)
	manager.set_epoch(EPOCH)
	for step: int in range(320):
		var coord := Vector2i(step * GrassRenderPage.PAGE_WIDTH_CHUNKS, 17)
		var revision: int = 2000 + step
		manager.set_chunk_active(coord, true, revision, step)
		_expect(manager.accept_chunk_result(
			coord, _make_chunk_result(coord, revision, float(step)), step,
		), "completed-cancel fixture accepts chunk %d" % step)
		_expect(manager.flush_dirty_requests() == 1,
			"completed-cancel fixture queues page %d" % step)
		backend.inject_result(backend.requests.back() as Dictionary)
		_expect(manager.drain_completed(1) == 1,
			"completed-cancel fixture drains page %d" % step)
		manager.set_chunk_active(coord, false, revision, step)
		manager.flush_dirty_requests()
	var state: Dictionary = manager.get_debug_state()
	_expect(int(state.entry_count) == 0,
		"320 completed pages canceled before publish leave no entries")
	_expect(int(state.resident_pages) == 0,
		"completed zero-demand candidates leave no residency")
	_expect(int(state.ready_visual_pages) == 0 and int(state.visual_upload_queue) == 0,
		"completed zero-demand candidates leave no visual queue")
	_expect(int(state.raw_upload_count_total) == 0 and int(state.commit_count_total) == 0,
		"completed zero-demand candidates perform zero upload and commit work")
	_expect(int(state.eviction_queue) == 0 and int(state.eviction_queue_physical) == 0,
		"direct cancellation needs no deferred eviction records")
	_expect(owner.get_child_count() == 0, "canceled completed results allocate no page shell")
	_expect(backend.pending_by_page.is_empty(), "backend has no canceled traversal request")
	_expect(not manager.has_pending_visual_upload(), "canceled traversal reports visual idle")
	manager.clear()
	owner.free()


func _test_staged_back_cancellation_preserves_front(
		texture: Texture2D,
		material: ShaderMaterial,
) -> void:
	var owner := Node2D.new()
	root.add_child(owner)
	var backend := FakeBackend.new()
	var manager := GrassRenderPageManager.new()
	manager.configure(owner, backend, texture, material, texture, material, material, material, 4)
	manager.set_epoch(EPOCH)
	var first_coord := Vector2i(160, 19)
	var second_coord := Vector2i(161, 19)
	var first_revision: int = 3001
	var second_revision: int = 3002
	manager.set_chunk_active(first_coord, true, first_revision, 0)
	manager.accept_chunk_result(
		first_coord, _make_chunk_result(first_coord, first_revision, 10.0), 0,
	)
	manager.flush_dirty_requests()
	backend.inject_result(backend.requests.back() as Dictionary)
	manager.drain_completed(1)
	_drain_until_commit_count(manager, 1)
	var page: GrassRenderPage = owner.get_child(0) as GrassRenderPage
	var front_revision: int = int(page.get_debug_state().page_revision)
	var front_rid: RID = page._albedo_layers[0].multimesh.get_rid()
	var front_buffer: PackedFloat32Array = page._albedo_layers[0].multimesh.buffer.duplicate()
	var commits_before: int = int(manager.get_debug_state().commit_count_total)
	var uploads_before: int = int(manager.get_debug_state().raw_upload_count_total)

	manager.set_chunk_active(second_coord, true, second_revision, 1)
	manager.accept_chunk_result(
		second_coord, _make_chunk_result(second_coord, second_revision, 20.0), 1,
	)
	_expect(manager.flush_dirty_requests() == 1, "second slot queues a newer page candidate")
	backend.inject_result(backend.requests.back() as Dictionary)
	manager.drain_completed(1)
	_expect(manager.apply_next_visual_phase(), "new result stages into existing page back buffer")
	var guard: int = 8
	while int(manager.get_debug_state().raw_upload_count_total) == uploads_before and guard > 0:
		manager.apply_next_visual_phase()
		guard -= 1
	_expect(guard > 0, "staged manager candidate reaches one raw back upload")
	_expect(page.has_pending_upload(), "new page candidate remains unpublished before demand loss")

	manager.set_chunk_active(second_coord, false, second_revision, 1)
	manager.set_chunk_active(first_coord, false, first_revision, 0)
	var canceled: Dictionary = manager.get_debug_state()
	_expect(not page.has_pending_upload(), "demand zero cancels staged page transaction")
	_expect(canceled.focused_page == GrassRenderPageManager.INVALID_PAGE_COORD,
		"demand-zero cancellation releases focused visual lane")
	_expect(int(canceled.ready_visual_pages) == 0 and int(canceled.visual_upload_queue) == 0,
		"demand-zero cancellation clears every candidate queue owner")
	_expect(int(canceled.entry_count) == 1 and int(canceled.resident_pages) == 1,
		"exact committed front remains as one hot LRU resident")
	_expect(int(canceled.commit_count_total) == commits_before,
		"canceled back candidate never increments manager commits")
	_expect(int(page.get_debug_state().page_revision) == front_revision,
		"canceled back candidate preserves front page revision")
	_expect(page._albedo_layers[0].multimesh.get_rid() == front_rid,
		"canceled back candidate preserves exact front RID")
	_expect(page._albedo_layers[0].multimesh.buffer == front_buffer,
		"canceled back candidate preserves exact front buffer")
	manager.set_chunk_active(first_coord, true, first_revision, 0)
	_expect(manager.is_chunk_committed(first_coord, first_revision),
		"retained exact front restores without publication")
	_expect(manager.flush_dirty_requests() == 0,
		"retained exact front restore queues no native page merge")
	manager.clear()
	owner.free()


func _make_chunk_result(coord: Vector2i, revision: int, marker: float) -> Dictionary:
	var buckets: Array = []
	buckets.resize(GrassRenderPage.STRIPE_COUNT)
	for stripe: int in range(buckets.size()):
		buckets[stripe] = PackedFloat32Array()
	buckets[0] = PackedFloat32Array([
		1.0, 0.0, 0.0, marker, 0.0, 1.0, 0.0, marker,
		0.0, 0.0, 0.0, 1.0,
	])
	return {
		"success": true,
		"epoch": EPOCH,
		"revision": revision,
		"target_chunk": coord,
		"bucket_buffers": buckets,
		"directional_shadow_buffer": buckets[0],
		"shadow_buffer": PackedFloat32Array(),
		"spore_buffer": PackedFloat32Array(),
	}


func _drain_page_commit(
		manager: GrassRenderPageManager,
		chunk_coord: Vector2i,
		revision: int,
		expected_old_commits: int,
) -> void:
	var guard: int = 64
	while int(manager.get_debug_state().commit_count_total) == expected_old_commits and guard > 0:
		_expect(
			not manager.is_chunk_committed(chunk_coord, revision),
			"front remains hidden until the focused transaction commits",
		)
		_expect(
			manager.get_debug_state().focused_page != GrassRenderPageManager.INVALID_PAGE_COORD,
			"focused page retains the visual lane until COMMIT",
		)
		manager.apply_next_visual_phase()
		guard -= 1
	_expect(guard > 0, "focused visual transaction reaches bounded COMMIT")


func _drain_until_commit_count(manager: GrassRenderPageManager, target: int) -> void:
	var guard: int = 64
	while int(manager.get_debug_state().commit_count_total) < target and guard > 0:
		manager.apply_next_visual_phase()
		guard -= 1
	_expect(guard > 0, "visual transaction reaches requested commit count")


func _make_texture() -> Texture2D:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform int page_slot_mask = 0;
uniform float page_origin_x = 0.0;
uniform float page_slot_width_px = 1024.0;
void fragment() { COLOR = texture(TEXTURE, UV); }
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _count_canvas_items(node: Node) -> int:
	var count: int = 1 if node is CanvasItem else 0
	for child: Node in node.get_children():
		count += _count_canvas_items(child)
	return count


func _finish() -> void:
	if _failures.is_empty():
		print("grass_render_page_manager_contract_test: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
