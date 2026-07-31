extends SceneTree

const AssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")

const OBJECT_KIND_TREE: int = 4
const OBJECT_KIND_SMALL_ROCK: int = 7
const DEPTH_STRIPE_COUNT: int = 64
const TREE_VISUAL_NODES_PER_STRIPE: int = 4
const ROCK_VISUAL_NODES_PER_STRIPE: int = 3
const TREE_STRIPES_PER_SLICE: int = 1
const COLLIDERS_PER_SLICE: int = 4
const ROCK_STRIPES_PER_SLICE: int = 1
const RETIRE_PHASE_HARD_TEST_LIMIT_USEC: int = 50_000

# Current authored generation has at most a 6x6 primary tree grid and 18 small
# rocks per chunk. The first payload is therefore >14x/>42x respectively, while
# keeping every depth stripe occupied.
const FIRST_TREE_COUNT: int = 512
const FIRST_ROCK_COUNT: int = 768
const SECOND_TREE_COUNT: int = 896
const SECOND_ROCK_COUNT: int = 1152

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: AssetCatalog = AssetCatalog.new()
	_expect(catalog.is_ready(), "asset catalog is boot-prepared")
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_expect(world_core != null, "WorldCore native class is available")
	_expect(
		world_core != null and world_core.has_method("build_object_presentation_buffers"),
		"native presentation builder is available",
	)
	if world_core == null or not world_core.has_method("build_object_presentation_buffers"):
		_finish(null)
		return

	var first_build_start_usec: int = Time.get_ticks_usec()
	var first_result: Dictionary = _make_native_result(
		world_core,
		catalog,
		FIRST_TREE_COUNT,
		FIRST_ROCK_COUNT,
		17,
	)
	var first_build_usec: int = Time.get_ticks_usec() - first_build_start_usec
	_verify_native_result(first_result, FIRST_TREE_COUNT, FIRST_ROCK_COUNT, "first")
	_verify_cancel_preserves_cached_result(first_result, catalog)

	var object_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	root.add_child(object_layer)
	_expect(
		object_layer.begin_presentation_result(first_result, catalog),
		"first native result begins",
	)
	_verify_staged_blocking_state(object_layer, "first")
	var first_apply: Dictionary = _drain_result(
		object_layer,
		FIRST_TREE_COUNT,
		FIRST_ROCK_COUNT,
		"first",
	)
	_verify_completed_result(object_layer, FIRST_TREE_COUNT, FIRST_ROCK_COUNT, "first")

	var tree_batch: Node = object_layer.get_node_or_null("LayeredTreeBatchLayer")
	var rock_batch: Node = object_layer.get_node_or_null("LayeredSmallRockBatchLayer")
	_expect(tree_batch != null, "first tree batch node exists")
	_expect(rock_batch != null, "first rock batch node exists")
	_verify_visual_node_bound(
		tree_batch,
		DEPTH_STRIPE_COUNT * TREE_VISUAL_NODES_PER_STRIPE,
		FIRST_TREE_COUNT,
		"first tree",
	)
	_verify_visual_node_bound(
		rock_batch,
		DEPTH_STRIPE_COUNT * ROCK_VISUAL_NODES_PER_STRIPE,
		FIRST_ROCK_COUNT,
		"first rock",
	)
	_expect(
		_count_descendants_of_class(object_layer, "Sprite2D") == 0,
		"native path creates no per-object Sprite2D nodes",
	)
	_expect(
		_count_descendants_of_class(object_layer, "CollisionShape2D") == 0,
		"tree colliders use shape owners, not per-object CollisionShape2D nodes",
	)
	var first_tree_child_ids: PackedInt64Array = _child_instance_ids(tree_batch)
	var first_rock_child_ids: PackedInt64Array = _child_instance_ids(rock_batch)
	var tree_batch_id: int = tree_batch.get_instance_id() if tree_batch != null else 0
	var rock_batch_id: int = rock_batch.get_instance_id() if rock_batch != null else 0

	var second_build_start_usec: int = Time.get_ticks_usec()
	var second_result: Dictionary = _make_native_result(
		world_core,
		catalog,
		SECOND_TREE_COUNT,
		SECOND_ROCK_COUNT,
		91,
	)
	var second_build_usec: int = Time.get_ticks_usec() - second_build_start_usec
	_verify_native_result(second_result, SECOND_TREE_COUNT, SECOND_ROCK_COUNT, "second")
	_expect(
		object_layer.begin_presentation_result(second_result, catalog),
		"second native result begins",
	)
	_verify_staged_blocking_state(object_layer, "second", FIRST_TREE_COUNT)
	var replacement_reservation: Dictionary = object_layer.get_hot_cache_reservation_weight()
	var replacement_expected_gpu_bytes: int = \
			(SECOND_TREE_COUNT + SECOND_ROCK_COUNT) * 2 * 12 * 4
	var phantom_double_reservation_bytes: int = \
			(FIRST_TREE_COUNT + FIRST_ROCK_COUNT + SECOND_TREE_COUNT + SECOND_ROCK_COUNT) \
			* 2 * 12 * 4
	_expect(
		int(replacement_reservation.get("gpu_buffer_bytes", -1)) \
				== replacement_expected_gpu_bytes,
		"replacement reservation uses per-family max residency, not old + new buffers",
	)
	_expect(
		int(replacement_reservation.get("gpu_buffer_bytes", 0)) \
				< phantom_double_reservation_bytes,
		"replacement reservation has no phantom 2x dense charge",
	)
	_expect(
		int(replacement_reservation.get("collider_count", -1)) == SECOND_TREE_COUNT,
		"replacement collider reservation uses max(old, expected)",
	)
	_expect(
		object_layer.get_node_or_null("LayeredTreeBatchLayer").get_instance_id() == tree_batch_id,
		"second result reuses the tree batch layer",
	)
	_expect(
		object_layer.get_node_or_null("LayeredSmallRockBatchLayer").get_instance_id() == rock_batch_id,
		"second result reuses the rock batch layer",
	)
	var second_apply: Dictionary = _drain_result(
		object_layer,
		SECOND_TREE_COUNT,
		SECOND_ROCK_COUNT,
		"second",
		FIRST_TREE_COUNT,
	)
	_verify_completed_result(object_layer, SECOND_TREE_COUNT, SECOND_ROCK_COUNT, "second")

	tree_batch = object_layer.get_node_or_null("LayeredTreeBatchLayer")
	rock_batch = object_layer.get_node_or_null("LayeredSmallRockBatchLayer")
	_expect(
		_child_instance_ids(tree_batch) == first_tree_child_ids,
		"second result reuses every tree stripe slot",
	)
	_expect(
		_child_instance_ids(rock_batch) == first_rock_child_ids,
		"second result reuses every rock stripe slot",
	)
	_verify_visual_node_bound(
		tree_batch,
		DEPTH_STRIPE_COUNT * TREE_VISUAL_NODES_PER_STRIPE,
		SECOND_TREE_COUNT,
		"second tree",
	)
	_verify_visual_node_bound(
		rock_batch,
		DEPTH_STRIPE_COUNT * ROCK_VISUAL_NODES_PER_STRIPE,
		SECOND_ROCK_COUNT,
		"second rock",
	)
	_verify_dense_to_empty_retirement(world_core, catalog)
	_verify_sparse_reuse_releases_inactive_residency(world_core, catalog, object_layer)

	var first_max_usec: Dictionary = first_apply.get("max_slice_usec", { }) as Dictionary
	var reuse_max_usec: Dictionary = second_apply.get("max_slice_usec", { }) as Dictionary
	print(
		(
			"OBJECT_PRESENTATION_STRESS "
			+ "first=%d_tree/%d_rock second=%d_tree/%d_rock "
			+ "native_build_ms=%.3f/%.3f slices=%d/%d "
			+ "first_use_max_us(tree/collision/commit/rock)=%d/%d/%d/%d "
			+ "reuse_max_us(reset/tree/collision/commit/rock)=%d/%d/%d/%d/%d"
		) % [
			FIRST_TREE_COUNT,
			FIRST_ROCK_COUNT,
			SECOND_TREE_COUNT,
			SECOND_ROCK_COUNT,
			float(first_build_usec) / 1000.0,
			float(second_build_usec) / 1000.0,
			int(first_apply.get("slice_count", 0)),
			int(second_apply.get("slice_count", 0)),
			int(first_max_usec.get("TREE_BUCKETS", 0)),
			int(first_max_usec.get("TREE_COLLISIONS", 0)),
			int(first_max_usec.get("COMMIT_BLOCKING", 0)),
			int(first_max_usec.get("ROCK_BUCKETS", 0)),
			int(reuse_max_usec.get("RESET_PREVIOUS_COLLISIONS", 0)),
			int(reuse_max_usec.get("TREE_BUCKETS", 0)),
			int(reuse_max_usec.get("TREE_COLLISIONS", 0)),
			int(reuse_max_usec.get("COMMIT_BLOCKING", 0)),
			int(reuse_max_usec.get("ROCK_BUCKETS", 0)),
		],
	)
	_finish(object_layer)


func _verify_cancel_preserves_cached_result(
		result: Dictionary,
		catalog: AssetCatalog,
) -> void:
	var collision_records: PackedFloat32Array = result.get(
		"tree_collision_records",
		PackedFloat32Array(),
	) as PackedFloat32Array
	var expected_collision_record_count: int = collision_records.size()
	var eviction_probe: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	root.add_child(eviction_probe)
	_expect(
		eviction_probe.begin_presentation_result(result, catalog),
		"hot eviction probe begins from cached worker truth",
	)
	eviction_probe.cancel_pending_presentation_apply()
	_expect(
		(result.get("tree_collision_records", PackedFloat32Array()) as PackedFloat32Array).size()
				== expected_collision_record_count,
		"cancel drops its collision alias without mutating cached worker truth",
	)
	_expect(
		eviction_probe.begin_presentation_result(result, catalog),
		"the same cached worker result can be restaged after hot eviction",
	)
	eviction_probe.cancel_pending_presentation_apply()
	eviction_probe.queue_free()


func _verify_sparse_reuse_releases_inactive_residency(
		world_core: Object,
		catalog: AssetCatalog,
		object_layer: WorldObjectPacketLayer,
) -> void:
	var sparse_result: Dictionary = _make_native_result(world_core, catalog, 1, 1, 123)
	_expect(bool(sparse_result.get("success", false)), "sparse reuse native build succeeds")
	_expect(int(sparse_result.get("tree_instance_count", -1)) == 1, "sparse reuse tree count")
	_expect(int(sparse_result.get("rock_instance_count", -1)) == 1, "sparse reuse rock count")
	_expect(
		object_layer.begin_presentation_result(sparse_result, catalog),
		"sparse result begins on the dense pooled graph",
	)
	var guard: int = ceili(float(SECOND_TREE_COUNT) / COLLIDERS_PER_SLICE) \
			+ DEPTH_STRIPE_COUNT * 4 + 32
	while object_layer.has_pending_presentation_apply() and guard > 0:
		var before: Dictionary = object_layer.get_debug_state()
		var state_before: String = str(before.get("native_apply_state", ""))
		var visual_retire_before: int = _pending_visual_retire_phase_count(before)
		var cleanup_before: int = int(
			before.get("previous_tree_collider_cleanup_remaining", 0),
		)
		var phase_started_usec: int = Time.get_ticks_usec()
		object_layer.apply_next_presentation_slice(1, 4, 1)
		var phase_elapsed_usec: int = Time.get_ticks_usec() - phase_started_usec
		var after: Dictionary = object_layer.get_debug_state()
		var visual_retire_after: int = _pending_visual_retire_phase_count(after)
		_expect(
			visual_retire_after > visual_retire_before \
					or visual_retire_before - visual_retire_after <= 1,
			"sparse reuse retires at most one visual slot group per phase",
		)
		_expect(
			phase_elapsed_usec < RETIRE_PHASE_HARD_TEST_LIMIT_USEC,
			"sparse reuse phase stays below the hard stress watchdog",
		)
		if state_before == "RESET_PREVIOUS_COLLISIONS":
			var cleanup_after: int = int(
				after.get(
					"previous_tree_collider_cleanup_remaining",
					0,
				),
			)
			_expect(
				cleanup_before - cleanup_after > 0 \
						and cleanup_before - cleanup_after <= COLLIDERS_PER_SLICE,
				"sparse reuse retires at most the collider slice budget",
			)
		guard -= 1
	_expect(guard > 0 and object_layer.is_presentation_complete(), "sparse reuse completes")
	var tree_batch: Node = object_layer.get_node_or_null("LayeredTreeBatchLayer")
	var rock_batch: Node = object_layer.get_node_or_null("LayeredSmallRockBatchLayer")
	_verify_inactive_slot_buffers_are_empty(tree_batch, 1, true, "sparse tree")
	_verify_inactive_slot_buffers_are_empty(rock_batch, 1, false, "sparse rock")
	var weight: Dictionary = object_layer.get_hot_cache_weight()
	_expect(
		int(weight.get("gpu_buffer_bytes", -1)) == 4 * 12 * 4,
		"hot GPU bytes reflect sparse resident buffers after dense reuse",
	)
	_expect(
		int(weight.get("canvas_item_count", -1)) \
				== _count_canvas_items_including(object_layer),
		"hot CanvasItem weight includes owners and depth-band roots",
	)
	var begin_retire_started_usec: int = Time.get_ticks_usec()
	object_layer.begin_pool_retire()
	_expect(
		Time.get_ticks_usec() - begin_retire_started_usec < RETIRE_PHASE_HARD_TEST_LIMIT_USEC,
		"pool retirement begins in O(1) without dense buffer scans",
	)
	var retire_guard: int = DEPTH_STRIPE_COUNT * 4 + SECOND_TREE_COUNT + 32
	var previous_weight: Dictionary = object_layer.get_retained_residency_weight()
	while object_layer.has_pending_pool_retire() and retire_guard > 0:
		var before_state: Dictionary = object_layer.get_debug_state()
		var before_visual_phases: int = _pending_visual_retire_phase_count(before_state)
		var before_gpu_bytes: int = int(previous_weight.get("gpu_buffer_bytes", 0))
		var before_colliders: int = int(previous_weight.get("collider_count", 0))
		var phase_started_usec: int = Time.get_ticks_usec()
		var advanced: bool = object_layer.retire_next_pool_slice(1, COLLIDERS_PER_SLICE)
		var phase_elapsed_usec: int = Time.get_ticks_usec() - phase_started_usec
		var after_state: Dictionary = object_layer.get_debug_state()
		var after_visual_phases: int = _pending_visual_retire_phase_count(after_state)
		var after_weight: Dictionary = object_layer.get_retained_residency_weight()
		var after_gpu_bytes: int = int(after_weight.get("gpu_buffer_bytes", 0))
		var after_colliders: int = int(after_weight.get("collider_count", 0))
		_expect(advanced, "pool retirement advances exactly one pending resource phase")
		_expect(
			before_visual_phases - after_visual_phases >= 0 \
					and before_visual_phases - after_visual_phases <= 1,
			"pool retirement releases at most one visual slot group",
		)
		_expect(
			before_colliders - after_colliders >= 0 \
					and before_colliders - after_colliders <= COLLIDERS_PER_SLICE,
			"pool retirement releases at most the collider slice budget",
		)
		_expect(
			after_gpu_bytes <= before_gpu_bytes and after_colliders <= before_colliders,
			"pool retained residency is monotonic while retirement drains",
		)
		_expect(
			phase_elapsed_usec < RETIRE_PHASE_HARD_TEST_LIMIT_USEC,
			"pool retirement phase stays below the hard stress watchdog",
		)
		previous_weight = after_weight
		retire_guard -= 1
	_expect(retire_guard > 0 and not object_layer.has_pending_pool_retire(), "pool retire drains")
	_expect(
		int(previous_weight.get("gpu_buffer_bytes", -1)) == 0 \
				and int(previous_weight.get("collider_count", -1)) == 0,
		"clean pool exposes no retained buffers or colliders",
	)
	_verify_inactive_slot_buffers_are_empty(tree_batch, 0, true, "cancelled tree pool")
	_verify_inactive_slot_buffers_are_empty(rock_batch, 0, false, "cancelled rock pool")


func _verify_dense_to_empty_retirement(
		world_core: Object,
		catalog: AssetCatalog,
) -> void:
	var dense_result: Dictionary = _make_native_result(
		world_core,
		catalog,
		DEPTH_STRIPE_COUNT,
		DEPTH_STRIPE_COUNT,
		211,
	)
	var empty_result: Dictionary = _make_native_result(world_core, catalog, 0, 0, 212)
	_expect(bool(dense_result.get("success", false)), "dense-to-empty source build succeeds")
	_expect(bool(empty_result.get("success", false)), "empty replacement build succeeds")
	var probe: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	root.add_child(probe)
	_expect(probe.begin_presentation_result(dense_result, catalog), "dense-to-empty dense stage begins")
	_drain_result(probe, DEPTH_STRIPE_COUNT, DEPTH_STRIPE_COUNT, "dense-to-empty dense")
	probe.set_blocking_collision_active(true)
	var begin_started_usec: int = Time.get_ticks_usec()
	_expect(probe.begin_presentation_result(empty_result, catalog), "dense-to-empty empty stage begins")
	_expect(
		Time.get_ticks_usec() - begin_started_usec < RETIRE_PHASE_HARD_TEST_LIMIT_USEC,
		"dense-to-empty begin is O(1)",
	)
	var guard: int = DEPTH_STRIPE_COUNT * 3 + 32
	var max_phase_usec: int = 0
	while probe.has_pending_presentation_apply() and guard > 0:
		var before: Dictionary = probe.get_debug_state()
		var before_visual_phases: int = _pending_visual_retire_phase_count(before)
		var before_colliders: int = int(before.get("previous_tree_collider_cleanup_remaining", 0))
		var phase_started_usec: int = Time.get_ticks_usec()
		var advanced: bool = probe.apply_next_presentation_slice(1, COLLIDERS_PER_SLICE, 1)
		var elapsed_usec: int = Time.get_ticks_usec() - phase_started_usec
		max_phase_usec = maxi(max_phase_usec, elapsed_usec)
		var after: Dictionary = probe.get_debug_state()
		var after_visual_phases: int = _pending_visual_retire_phase_count(after)
		var after_colliders: int = int(after.get("previous_tree_collider_cleanup_remaining", 0))
		_expect(advanced, "dense-to-empty bounded phase advances")
		_expect(
			before_visual_phases - after_visual_phases >= 0 \
					and before_visual_phases - after_visual_phases <= 1,
			"dense-to-empty releases at most one visual slot group per phase",
		)
		_expect(
			before_colliders - after_colliders >= 0 \
					and before_colliders - after_colliders <= COLLIDERS_PER_SLICE,
			"dense-to-empty collision cleanup is sliced",
		)
		_expect(elapsed_usec < RETIRE_PHASE_HARD_TEST_LIMIT_USEC, "dense-to-empty phase watchdog")
		if not probe.is_presentation_complete():
			_expect(not probe.visible, "empty replacement stays atomically hidden while retiring")
		guard -= 1
	_expect(guard > 0 and probe.is_presentation_complete(), "dense-to-empty completes autonomously")
	_expect(not probe.visible, "committed empty replacement remains invisible")
	var final_weight: Dictionary = probe.get_hot_cache_weight()
	_expect(
		int(final_weight.get("gpu_buffer_bytes", -1)) == 0 \
				and int(final_weight.get("collider_count", -1)) == 0,
		"dense-to-empty releases all GPU buffers and colliders",
	)
	_verify_inactive_slot_buffers_are_empty(
		probe.get_node_or_null("LayeredTreeBatchLayer"),
		0,
		true,
		"dense-to-empty tree",
	)
	_verify_inactive_slot_buffers_are_empty(
		probe.get_node_or_null("LayeredSmallRockBatchLayer"),
		0,
		false,
		"dense-to-empty rock",
	)
	print("OBJECT_PRESENTATION_DENSE_EMPTY retire_max_us=%d" % max_phase_usec)
	probe.free()


func _pending_visual_retire_phase_count(state: Dictionary) -> int:
	var total: int = 0
	for key: StringName in [
		&"tree_batch",
		&"living_flora_batch",
		&"spiky_flora_batch",
		&"rock_batch",
	]:
		var family: Dictionary = state.get(key, { }) as Dictionary
		total += int(family.get("retire_remaining_slot_count", 0))
	return total


func _verify_inactive_slot_buffers_are_empty(
		batch_layer: Node,
		active_slot_count: int,
		is_tree: bool,
		label: String,
) -> void:
	if batch_layer == null:
		_failures.append("%s batch layer exists" % label)
		return
	var slots: Array = batch_layer.get("_slots") as Array
	for slot_index: int in range(active_slot_count, slots.size()):
		var slot: Dictionary = slots[slot_index] as Dictionary
		var visual_multimesh: MultiMesh = slot.get("visual_multimesh") as MultiMesh
		var shadow_multimesh: MultiMesh = slot.get("shadow_multimesh") as MultiMesh
		_expect(
			visual_multimesh != null and visual_multimesh.instance_count == 0,
			"%s inactive visual buffer %d is released" % [label, slot_index],
		)
		_expect(
			shadow_multimesh != null and shadow_multimesh.instance_count == 0,
			"%s inactive shadow buffer %d is released" % [label, slot_index],
		)
	if is_tree:
		_expect(slots.size() >= active_slot_count, "%s keeps its bounded slot pool" % label)


func _count_canvas_items_including(node: Node) -> int:
	var count: int = 1 if node is CanvasItem else 0
	for child: Node in node.get_children():
		count += _count_canvas_items_including(child)
	return count


func _make_native_result(
		world_core: Object,
		catalog: AssetCatalog,
		tree_count: int,
		rock_count: int,
		seed: int,
) -> Dictionary:
	var object_count: int = tree_count + rock_count
	var kind := PackedByteArray()
	var x_q4 := PackedByteArray()
	var y_q4 := PackedByteArray()
	var size_px := PackedByteArray()
	var atlas := PackedByteArray()
	var variant := PackedByteArray()
	var flags := PackedByteArray()
	var tint := PackedByteArray()
	var phase := PackedByteArray()
	for buffer: PackedByteArray in [kind, x_q4, y_q4, size_px, atlas, variant, flags, tint, phase]:
		buffer.resize(object_count)
	for object_index: int in range(object_count):
		var is_tree: bool = object_index < tree_count
		var family_index: int = object_index if is_tree else object_index - tree_count
		var stripe: int = family_index % DEPTH_STRIPE_COUNT
		var lane: int = (family_index / DEPTH_STRIPE_COUNT) % 4
		kind[object_index] = OBJECT_KIND_TREE if is_tree else OBJECT_KIND_SMALL_ROCK
		x_q4[object_index] = (family_index * 37 + seed * 11) % 256
		y_q4[object_index] = stripe * 4 + lane
		size_px[object_index] = 176 + (family_index + seed) % 64 \
				if is_tree else 34 + (family_index + seed) % 36
		atlas[object_index] = 0
		variant[object_index] = (family_index * 3 + seed) % 251
		flags[object_index] = 0
		tint[object_index] = 176 + (family_index * 7 + seed) % 80
		phase[object_index] = (family_index * 13 + seed) % 256
	var result_variant: Variant = world_core.call(
		"build_object_presentation_buffers",
		kind,
		x_q4,
		y_q4,
		size_px,
		atlas,
		variant,
		flags,
		tint,
		phase,
		catalog.get_tree_native_metrics(),
		catalog.get_rock_native_metrics(),
		catalog.get_bush_native_metrics(),
		catalog.get_native_params(),
	)
	if not result_variant is Dictionary:
		return {"success": false, "error": "native result is not a Dictionary"}
	var result: Dictionary = result_variant as Dictionary
	result["success"] = not result.has("error")
	return result


func _verify_native_result(
		result: Dictionary,
		tree_count: int,
		rock_count: int,
		label: String,
) -> void:
	_expect(bool(result.get("success", false)), "%s native build succeeds" % label)
	_expect(int(result.get("tree_instance_count", -1)) == tree_count, "%s tree count" % label)
	_expect(int(result.get("rock_instance_count", -1)) == rock_count, "%s rock count" % label)
	_expect(
		(result.get("tree_collision_records", PackedFloat32Array()) as PackedFloat32Array).size()
				== tree_count * 4,
		"%s collision record count" % label,
	)
	var tree_buffers: Array = result.get("tree_atlas_bucket_buffers", []) as Array
	var rock_buffers: Array = result.get("rock_atlas_bucket_buffers", []) as Array
	_expect(tree_buffers.size() == DEPTH_STRIPE_COUNT, "%s tree stripe layout" % label)
	_expect(rock_buffers.size() == DEPTH_STRIPE_COUNT, "%s rock stripe layout" % label)
	if tree_buffers.size() == DEPTH_STRIPE_COUNT and rock_buffers.size() == DEPTH_STRIPE_COUNT:
		for stripe: int in range(DEPTH_STRIPE_COUNT):
			_expect(
				not (tree_buffers[stripe] as PackedFloat32Array).is_empty(),
				"%s tree stripe %d is occupied" % [label, stripe],
			)
			_expect(
				not (rock_buffers[stripe] as PackedFloat32Array).is_empty(),
				"%s rock stripe %d is occupied" % [label, stripe],
			)


func _verify_staged_blocking_state(
		object_layer: WorldObjectPacketLayer,
		label: String,
		previous_collider_count: int = 0,
) -> void:
	var state: Dictionary = object_layer.get_debug_state()
	_expect(not object_layer.visible, "%s staged tree presentation stays hidden" % label)
	_expect(not object_layer.is_blocking_presentation_ready(), "%s blocking state starts unready" % label)
	_expect(int(state.get("tree_collision_layer", -1)) == 0, "%s staged collision is disabled" % label)
	_expect(
		str(state.get("native_apply_state", "")) \
				== ("RESET_PREVIOUS_COLLISIONS" if previous_collider_count > 0 else "TREE_BUCKETS"),
		"%s starts with the bounded cleanup/tree phase" % label,
	)
	_expect(
		int(state.get("previous_tree_collider_cleanup_remaining", 0)) \
				== previous_collider_count,
		"%s accounts every previous collider before sliced reuse" % label,
	)


func _drain_result(
		object_layer: WorldObjectPacketLayer,
		tree_count: int,
		rock_count: int,
		label: String,
		previous_collider_count: int = 0,
) -> Dictionary:
	var slice_count: int = 0
	var local_max_slice_usec: Dictionary = { }
	var saw_commit: bool = false
	var saw_rock_staged_before_commit: bool = false
	var initial_state: Dictionary = object_layer.get_debug_state()
	var initial_tree_state: Dictionary = initial_state.get("tree_batch", { }) as Dictionary
	var initial_rock_state: Dictionary = initial_state.get("rock_batch", { }) as Dictionary
	var tree_allocation_slices: int = maxi(
		0,
		mini(tree_count, DEPTH_STRIPE_COUNT) \
				- int(initial_tree_state.get("pooled_slot_count", 0)),
	)
	var rock_allocation_slices: int = maxi(
		0,
		mini(rock_count, DEPTH_STRIPE_COUNT) \
				- int(initial_rock_state.get("pooled_slot_count", 0)),
	)
	var guard: int = DEPTH_STRIPE_COUNT * 2 \
			+ ceili(float(previous_collider_count) / COLLIDERS_PER_SLICE) \
			+ ceili(float(tree_count) / COLLIDERS_PER_SLICE) \
			+ tree_allocation_slices + rock_allocation_slices + 8
	while object_layer.has_pending_presentation_apply():
		var before: Dictionary = object_layer.get_debug_state()
		var state_before: String = str(before.get("native_apply_state", ""))
		var tree_before: Dictionary = before.get("tree_batch", { }) as Dictionary
		var rock_before: Dictionary = before.get("rock_batch", { }) as Dictionary
		var tree_stripe_before: int = int(tree_before.get("next_stripe", 0))
		var rock_stripe_before: int = int(rock_before.get("next_stripe", 0))
		var colliders_before: int = int(before.get("tree_collider_count", 0))
		var phase_hint: StringName = object_layer.get_next_presentation_apply_phase_hint()
		var allocation_only: bool = \
				object_layer.next_presentation_slice_requires_visual_slot_allocation()
		var uploads_before: int = object_layer.get_raw_multimesh_upload_count_total()
		var start_usec: int = Time.get_ticks_usec()
		var advanced: bool = object_layer.apply_next_presentation_slice(
			TREE_STRIPES_PER_SLICE,
			COLLIDERS_PER_SLICE,
			ROCK_STRIPES_PER_SLICE,
		)
		var elapsed_usec: int = Time.get_ticks_usec() - start_usec
		local_max_slice_usec[state_before] = maxi(
			int(local_max_slice_usec.get(state_before, 0)),
			elapsed_usec,
		)
		_expect(advanced, "%s %s slice advances" % [label, state_before])
		if allocation_only:
			var expected_allocation_hint: StringName = \
					WorldObjectPacketLayer.PRESENTATION_PHASE_TREE_SLOT_ALLOCATION \
					if state_before == "TREE_BUCKETS" \
					else WorldObjectPacketLayer.PRESENTATION_PHASE_ROCK_SLOT_ALLOCATION
			_expect(
				phase_hint == expected_allocation_hint,
				"%s %s exposes its family allocation phase" % [label, state_before],
			)
			_expect(
				object_layer.did_last_presentation_slice_create_visual_slot() \
						and object_layer.get_raw_multimesh_upload_count_total() == uploads_before,
				"%s %s allocation advances no raw upload" % [label, state_before],
			)
		var after: Dictionary = object_layer.get_debug_state()
		match state_before:
			"RESET_PREVIOUS_COLLISIONS":
				var cleanup_before: int = int(
					before.get("previous_tree_collider_cleanup_remaining", 0),
				)
				var cleanup_after: int = int(
					after.get("previous_tree_collider_cleanup_remaining", 0),
				)
				var removed_count: int = cleanup_before - cleanup_after
				_expect(
					removed_count > 0 and removed_count <= COLLIDERS_PER_SLICE,
					"%s recycled collision cleanup is bounded to %d owners" \
							% [label, COLLIDERS_PER_SLICE],
				)
			"TREE_BUCKETS":
				var tree_after: Dictionary = after.get("tree_batch", { }) as Dictionary
				var stripe_delta: int = int(tree_after.get("next_stripe", 0)) - tree_stripe_before
				_expect(
					stripe_delta >= 0 and stripe_delta <= TREE_STRIPES_PER_SLICE,
					"%s tree slice is bounded to %d stripe" % [label, TREE_STRIPES_PER_SLICE],
				)
			"TREE_COLLISIONS":
				var collider_delta: int = int(after.get("tree_collider_count", 0)) - colliders_before
				_expect(
					collider_delta >= 0 and collider_delta <= COLLIDERS_PER_SLICE,
					"%s collision slice is bounded to %d shapes" % [label, COLLIDERS_PER_SLICE],
				)
			"COMMIT_BLOCKING":
				saw_commit = true
				_expect(object_layer.is_blocking_presentation_ready(), "%s commit marks blocking-ready" % label)
				_expect(object_layer.visible, "%s commit reveals every object family" % label)
				_expect(
					int(after.get("tree_collision_layer", -1)) == 0,
					"%s prepared collision waits for the owning chunk reveal" % label,
				)
				_expect(
					object_layer.is_presentation_complete(),
					"%s commit completes the coherent presentation" % label,
				)
			"ROCK_BUCKETS":
				saw_rock_staged_before_commit = true
				var rock_after: Dictionary = after.get("rock_batch", { }) as Dictionary
				var rock_delta: int = int(rock_after.get("next_stripe", 0)) - rock_stripe_before
				_expect(
					rock_delta >= 0 and rock_delta <= ROCK_STRIPES_PER_SLICE,
					"%s rock slice is bounded to %d stripe" % [label, ROCK_STRIPES_PER_SLICE],
				)
				_expect(not object_layer.visible, "%s rocks remain hidden while staging" % label)
				_expect(
					int(after.get("tree_collision_layer", 0)) == 0,
					"%s collision remains disabled while rocks stage" % label,
				)
		if not object_layer.is_blocking_presentation_ready():
			_expect(not object_layer.visible, "%s tree remains hidden before commit" % label)
			_expect(
				int(after.get("tree_collision_layer", -1)) == 0,
				"%s collision remains disabled before commit" % label,
			)
		slice_count += 1
		guard -= 1
		if guard < 0:
			_failures.append("%s incremental apply exceeded its structural upper bound" % label)
			break
	_expect(saw_commit, "%s reaches one atomic blocking commit" % label)
	_expect(saw_rock_staged_before_commit, "%s stages rocks before the atomic commit" % label)
	object_layer.set_blocking_collision_active(true)
	_expect(
		int(object_layer.get_debug_state().get("tree_collision_layer", 0)) == 2,
		"%s reveal activates all prepared tree collision" % label,
	)
	var expected_slices: int = DEPTH_STRIPE_COUNT \
			+ ceili(float(previous_collider_count) / float(COLLIDERS_PER_SLICE)) \
			+ ceili(float(tree_count) / float(COLLIDERS_PER_SLICE)) \
			+ 2 \
			+ DEPTH_STRIPE_COUNT \
			+ tree_allocation_slices + rock_allocation_slices
	_expect(
		slice_count == expected_slices,
		"%s slice count is deterministic and bounded (%d, got %d)" \
				% [label, expected_slices, slice_count],
	)
	return {
		"slice_count": slice_count,
		"max_slice_usec": local_max_slice_usec,
	}


func _verify_completed_result(
		object_layer: WorldObjectPacketLayer,
		tree_count: int,
		rock_count: int,
		label: String,
) -> void:
	var state: Dictionary = object_layer.get_debug_state()
	var tree_state: Dictionary = state.get("tree_batch", { }) as Dictionary
	var rock_state: Dictionary = state.get("rock_batch", { }) as Dictionary
	_expect(object_layer.is_blocking_presentation_ready(), "%s remains blocking-ready" % label)
	_expect(object_layer.is_presentation_complete(), "%s presentation completes" % label)
	_expect(not object_layer.has_pending_presentation_apply(), "%s has no pending apply" % label)
	_expect(object_layer.visible, "%s completed layer is visible" % label)
	_expect(int(state.get("tree_collider_count", -1)) == tree_count, "%s collider total" % label)
	_expect(int(state.get("tree_collision_layer", 0)) == 2, "%s collision layer" % label)
	_expect(int(tree_state.get("instance_count", -1)) == tree_count, "%s tree instance total" % label)
	_expect(int(rock_state.get("instance_count", -1)) == rock_count, "%s rock instance total" % label)
	_expect(
		int(tree_state.get("active_stripe_count", -1)) == DEPTH_STRIPE_COUNT,
		"%s tree stripes stay batch-bounded" % label,
	)
	_expect(
		int(rock_state.get("active_stripe_count", -1)) == DEPTH_STRIPE_COUNT,
		"%s rock stripes stay batch-bounded" % label,
	)
	_expect(
		int(tree_state.get("pooled_slot_count", -1)) == DEPTH_STRIPE_COUNT,
		"%s tree pool size" % label,
	)
	_expect(
		int(rock_state.get("pooled_slot_count", -1)) == DEPTH_STRIPE_COUNT,
		"%s rock pool size" % label,
	)


func _verify_visual_node_bound(
		batch_layer: Node,
		expected_visual_nodes: int,
		instance_count: int,
		label: String,
) -> void:
	if batch_layer == null:
		return
	var visual_node_count: int = _count_descendants_of_class(batch_layer, "MultiMeshInstance2D")
	_expect(
		visual_node_count == expected_visual_nodes,
		"%s visuals are depth-stripe nodes (%d), not object nodes" \
				% [label, expected_visual_nodes],
	)
	_expect(
		visual_node_count < instance_count,
		"%s visual node count does not scale with %d instances" % [label, instance_count],
	)


func _child_instance_ids(parent: Node) -> PackedInt64Array:
	var ids := PackedInt64Array()
	if parent == null:
		return ids
	_collect_multimesh_instance_ids(parent, ids)
	ids.sort()
	return ids


func _collect_multimesh_instance_ids(parent: Node, ids: PackedInt64Array) -> void:
	for child: Node in parent.get_children():
		if child is MultiMeshInstance2D:
			ids.append(child.get_instance_id())
		_collect_multimesh_instance_ids(child, ids)


func _count_descendants_of_class(parent: Node, class_name_to_find: String) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child.is_class(class_name_to_find):
			count += 1
		count += _count_descendants_of_class(child, class_name_to_find)
	return count


func _finish(object_layer: WorldObjectPacketLayer) -> void:
	if object_layer != null and is_instance_valid(object_layer):
		object_layer.free()
	if _failures.is_empty():
		print("Object presentation stress: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
