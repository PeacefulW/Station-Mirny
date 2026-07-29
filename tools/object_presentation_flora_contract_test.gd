extends SceneTree

const AssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")
const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")

const OBJECT_KIND_LIVING_FLORA: int = 2
const OBJECT_KIND_SPIKY_FLORA: int = 3
const STRIPE_COUNT: int = 64
const BUFFER_STRIDE: int = 12

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: AssetCatalog = AssetCatalog.new()
	_expect(catalog.is_ready(), "asset catalog is ready")
	_expect(catalog.get_catalog_generation() == 5, "flora policy contract bumps catalog generation")
	_expect(catalog.get_native_params().size() == 20, "native flora parameter layout")
	_verify_chunk_view_lazy_source_sync()
	_verify_pool_envelope_prepares_fixed_render_graph(catalog)
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_expect(world_core != null, "WorldCore native class")
	if world_core == null:
		_finish(null)
		return

	_verify_lazy_empty_payload(world_core, catalog)
	_verify_disabled_policy_suppresses_known_records(world_core, catalog)
	_verify_invalid_spiky_bank_is_rejected(world_core, catalog)
	var result: Dictionary = _build_flora_result(world_core, catalog)
	_verify_exact_native_buffers(result)
	var object_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	root.add_child(object_layer)
	object_layer.set_living_flora_atlas(_make_texture(4096, 1024))
	object_layer.set_spiky_flora_atlases([
		_make_texture(2048, 512),
		_make_texture(2048, 512),
	])
	_expect(object_layer.begin_presentation_result(result, catalog), "flora native result begins")
	object_layer.set_world_origin_y(0.0)
	object_layer.update_ladder_z(0)
	_expect(not object_layer.visible, "flora stays hidden while staged")
	_expect(
		str(object_layer.get_debug_state().get("native_apply_state", "")) \
				== "LIVING_FLORA_BUFFERS",
		"flora-only transaction starts at living buffers",
	)
	var first_slices: int = _drain_atomic_flora_apply(object_layer, "first")
	_expect(
		first_slices == 12,
		"cold flora separates five slot allocations from uploads, retire gate, and commit",
	)
	_verify_completed_flora_state(object_layer, "first")

	var living_layer: Node = object_layer.get_node_or_null("NativeLivingFloraBatchLayer")
	var spiky_layer: Node = object_layer.get_node_or_null("NativeSpikyFloraBatchLayer")
	var living_slot_ids: PackedInt64Array = _stripe_slot_ids(living_layer)
	var spiky_slot_ids: PackedInt64Array = _stripe_slot_ids(spiky_layer)
	_expect(living_slot_ids.size() == 2, "living visual nodes scale by occupied stripes")
	_expect(spiky_slot_ids.size() == 2, "spiky visual nodes scale by occupied stripes")
	_verify_shared_flora_materials(living_layer, spiky_layer, catalog)

	_expect(object_layer.begin_presentation_result(result, catalog), "flora result begins again")
	_expect(not object_layer.visible, "reused flora pool is hidden before commit")
	var second_slices: int = _drain_atomic_flora_apply(object_layer, "reuse")
	_expect(second_slices == 7, "flora reuse skips cold allocation phases")
	_expect(_stripe_slot_ids(living_layer) == living_slot_ids, "living stripe slots are reused")
	_expect(_stripe_slot_ids(spiky_layer) == spiky_slot_ids, "spiky stripe slots are reused")
	_verify_completed_flora_state(object_layer, "reuse")

	object_layer.update_ladder_z(100)
	object_layer.update_ladder_z(101)
	_verify_depth_rebase_is_bounded(object_layer)
	object_layer = _verify_hot_cache_transfer_without_reupload(object_layer)
	_finish(object_layer)


func _verify_chunk_view_lazy_source_sync() -> void:
	var view: ChunkView = ChunkView.new()
	root.add_child(view)
	view.configure(Vector2i(3, -2))
	var living: Texture2D = _make_texture(1, 1)
	var spiky_a: Texture2D = _make_texture(1, 1)
	var spiky_b: Texture2D = _make_texture(1, 1)
	view.set_living_flora_source(living)
	view.set_spiky_flora_sources([spiky_a, spiky_b])
	_expect(view._object_packet_layer == null, "flora sources stay lazy before packet presentation")
	var layer: WorldObjectPacketLayer = view._ensure_object_packet_layer()
	_expect(layer._living_flora_atlas == living, "lazy packet layer replays living atlas")
	_expect(layer._spiky_flora_atlases.size() == 2, "lazy packet layer replays spiky banks")
	if layer._spiky_flora_atlases.size() == 2:
		_expect(layer._spiky_flora_atlases[0] == spiky_a, "spiky bank zero keeps identity")
		_expect(layer._spiky_flora_atlases[1] == spiky_b, "spiky bank one keeps identity")
	view.free()


func _verify_pool_envelope_prepares_fixed_render_graph(catalog: AssetCatalog) -> void:
	var layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	root.add_child(layer)
	layer.set_living_flora_atlas(_make_texture(4096, 1024))
	layer.set_spiky_flora_atlases([
		_make_texture(2048, 512),
		_make_texture(2048, 512),
	])
	_expect(
		layer.prepare_presentation_envelope(catalog, 1),
		"pool envelope prepares all enabled object families",
	)
	_expect(not layer.visible, "prepared pool envelope remains hidden")
	for ladder_path: NodePath in [
		NodePath("LayeredTreeBatchLayer/TreeDepthLadder"),
		NodePath("LayeredSmallRockBatchLayer/RockDepthLadder"),
		NodePath("NativeLivingFloraBatchLayer/DepthLadderBandRoot"),
		NodePath("NativeSpikyFloraBatchLayer/DepthLadderBandRoot"),
	]:
		var ladder: Node = layer.get_node_or_null(ladder_path)
		_expect(ladder != null, "%s is allocated by the pool envelope" % ladder_path)
		if ladder != null:
			_expect(
				ladder.get_child_count() == 3,
				"%s preallocates all three depth-band roots" % ladder_path,
			)
	var living_shadow: MultiMeshInstance2D = layer.get_node_or_null(
		"NativeLivingFloraBatchLayer/NativeDecorShadowBatch",
	) as MultiMeshInstance2D
	_expect(living_shadow != null, "pool envelope preallocates living contact-shadow CanvasItem")
	if living_shadow != null:
		_expect(living_shadow.multimesh != null, "pool envelope preallocates living shadow MultiMesh")
		_expect(living_shadow.texture != null, "pool envelope preallocates shared unit shadow texture")
		_expect(not living_shadow.visible, "prepared living shadow remains hidden")
		if living_shadow.multimesh != null:
			_expect(living_shadow.multimesh.instance_count == 0, "prepared shadow owns no instances")
	_expect(
		layer.get_node_or_null("NativeSpikyFloraBatchLayer/NativeDecorShadowBatch") == null,
		"shadowless spiky family does not allocate a shadow graph",
	)
	_expect(
		layer.get_raw_multimesh_upload_count_total() == 0,
		"pool graph preparation performs no packet buffer uploads",
	)
	layer.free()


func _build_flora_result(world_core: Object, catalog: AssetCatalog) -> Dictionary:
	var result_variant: Variant = world_core.call(
		"build_object_presentation_buffers",
		PackedByteArray([
			OBJECT_KIND_LIVING_FLORA,
			OBJECT_KIND_LIVING_FLORA,
			OBJECT_KIND_SPIKY_FLORA,
			OBJECT_KIND_SPIKY_FLORA,
		]),
		PackedByteArray([10, 30, 20, 40]),
		PackedByteArray([10, 30, 20, 40]),
		PackedByteArray([100, 84, 80, 60]),
		PackedByteArray([0, 0, 0, 1]),
		PackedByteArray([0, 16, 0, 3]),
		PackedByteArray([0, 0, 0, 0]),
		PackedByteArray([255, 200, 240, 220]),
		PackedByteArray([0, 128, 64, 192]),
		catalog.get_tree_native_metrics(),
		catalog.get_rock_native_metrics(),
		catalog.get_bush_native_metrics(),
		catalog.get_native_params(true, true),
	)
	_expect(result_variant is Dictionary, "native flora result is a Dictionary")
	if not result_variant is Dictionary:
		return {"success": false}
	var result: Dictionary = result_variant as Dictionary
	result["success"] = not result.has("error")
	_expect(bool(result.get("success", false)), "native flora result succeeds")
	return result


func _verify_exact_native_buffers(result: Dictionary) -> void:
	_expect(int(result.get("object_count", -1)) == 4, "flora object count")
	_expect(int(result.get("living_flora_count", -1)) == 2, "living flora count")
	_expect(int(result.get("spiky_flora_count", -1)) == 2, "spiky flora count")
	_expect(int(result.get("spiky_flora_atlas_bank_count", -1)) == 2, "spiky atlas bank count")
	_expect(int(result.get("buffer_float_count", -1)) == 72, "flora raw float count")
	_expect(int(result.get("payload_bytes", -1)) == 288, "flora payload byte accounting")

	var living_buckets: Array = result.get("living_flora_bucket_buffers", []) as Array
	_expect(living_buckets.size() == STRIPE_COUNT, "living flora has 64 worker buckets")
	if living_buckets.size() == STRIPE_COUNT:
		var first: PackedFloat32Array = living_buckets[5] as PackedFloat32Array
		_expect(first.size() == BUFFER_STRIDE, "living root+size uses exact legacy stripe")
		if first.size() == BUFFER_STRIDE:
			_expect_close(first[0], 100.0, "living transform width")
			_expect_close(first[3], 42.0, "living q4 X center decode")
			_expect_close(first[7], 42.0, "living q4 Y center decode")
			_expect_close(first[8], 0.0, "living frame color")
			_expect_close(first[9], 1.0, "living tint color")
			_expect_close(first[10], 0.0, "living phase color")
			_expect_close(first[11], 0.96, "living alpha")

	var shadow: PackedFloat32Array = result.get(
		"living_flora_shadow_buffer",
		PackedFloat32Array(),
	) as PackedFloat32Array
	_expect(shadow.size() == 2 * BUFFER_STRIDE, "one raw contact shadow per living instance")
	if shadow.size() >= BUFFER_STRIDE:
		_expect_close(shadow[0], 42.0, "living shadow width")
		_expect_close(shadow[3], 42.0, "living shadow X")
		_expect_close(shadow[4], 0.0, "living shadow transform row")
		_expect_close(shadow[5], 13.0, "living shadow height")
		_expect_close(shadow[7], 74.0, "living shadow Y offset")
		_expect_close(shadow[8], (100.0 / 96.0) / 4.0, "living shadow scale color")
		_expect_close(shadow[9], 1.0 / 42.0, "living shadow inverse width")
		_expect_close(shadow[10], 1.0 / 13.0, "living shadow inverse height")
		_expect_close(shadow[11], 0.58, "living shadow alpha")

	var spiky_atlases: Array = result.get("spiky_flora_atlas_bucket_buffers", []) as Array
	_expect(spiky_atlases.size() == 2, "spiky buffers remain atlas-major")
	if spiky_atlases.size() == 2:
		var bank_zero: Array = spiky_atlases[0] as Array
		var bank_one: Array = spiky_atlases[1] as Array
		_expect(bank_zero.size() == STRIPE_COUNT, "spiky bank zero has 64 buckets")
		_expect(bank_one.size() == STRIPE_COUNT, "spiky bank one has 64 buckets")
		if bank_zero.size() == STRIPE_COUNT:
			var orange: PackedFloat32Array = bank_zero[7] as PackedFloat32Array
			_expect(orange.size() == BUFFER_STRIDE, "orange spiky exact depth bucket")
			if orange.size() == BUFFER_STRIDE:
				_expect_close(orange[3], 82.0, "spiky q4 X center decode")
				_expect_close(orange[11], 0.98, "spiky alpha")
		if bank_one.size() == STRIPE_COUNT:
			var seaweed: PackedFloat32Array = bank_one[11] as PackedFloat32Array
			_expect(seaweed.size() == BUFFER_STRIDE, "seaweed exact atlas/depth bucket")
			if seaweed.size() == BUFFER_STRIDE:
				_expect_close(seaweed[8], 3.0 / 255.0, "seaweed packet frame is preserved")


func _verify_lazy_empty_payload(world_core: Object, catalog: AssetCatalog) -> void:
	var empty := PackedByteArray()
	var result: Dictionary = world_core.call(
		"build_object_presentation_buffers",
		empty,
		empty,
		empty,
		empty,
		empty,
		empty,
		empty,
		empty,
		empty,
		catalog.get_tree_native_metrics(),
		catalog.get_rock_native_metrics(),
		catalog.get_bush_native_metrics(),
		catalog.get_native_params(),
	) as Dictionary
	_expect((result.get("living_flora_bucket_buffers", []) as Array).is_empty(), "zero living uses lazy buckets")
	_expect(
		(result.get("living_flora_shadow_buffer", PackedFloat32Array()) as PackedFloat32Array).is_empty(),
		"zero living uses lazy shadow",
	)
	_expect(
		(result.get("spiky_flora_atlas_bucket_buffers", []) as Array).is_empty(),
		"zero spiky uses lazy atlas buckets",
	)
	_expect(int(result.get("spiky_flora_atlas_bank_count", -1)) == 0, "zero spiky omits banks")
	_expect(int(result.get("payload_bytes", -1)) == 0, "zero-object payload bytes")


func _verify_disabled_policy_suppresses_known_records(
		world_core: Object,
		catalog: AssetCatalog,
) -> void:
	var result: Dictionary = world_core.call(
		"build_object_presentation_buffers",
		PackedByteArray([
			OBJECT_KIND_LIVING_FLORA,
			OBJECT_KIND_LIVING_FLORA,
			OBJECT_KIND_SPIKY_FLORA,
			OBJECT_KIND_SPIKY_FLORA,
		]),
		PackedByteArray([10, 30, 20, 40]),
		PackedByteArray([10, 30, 20, 40]),
		PackedByteArray([100, 84, 80, 60]),
		PackedByteArray([0, 0, 0, 1]),
		PackedByteArray([0, 16, 0, 3]),
		PackedByteArray([0, 0, 0, 0]),
		PackedByteArray([255, 200, 240, 220]),
		PackedByteArray([0, 128, 64, 192]),
		catalog.get_tree_native_metrics(),
		catalog.get_rock_native_metrics(),
		catalog.get_bush_native_metrics(),
		catalog.get_native_params(),
	) as Dictionary
	result["success"] = not result.has("error")
	_expect(bool(result.get("success", false)), "disabled known flora records remain valid")
	_expect(int(result.get("object_count", -1)) == 4, "disabled flora keeps canonical object count")
	_expect(int(result.get("living_flora_record_count", -1)) == 2, "disabled living records counted")
	_expect(int(result.get("spiky_flora_record_count", -1)) == 2, "disabled spiky records counted")
	_expect(int(result.get("living_flora_count", -1)) == 0, "disabled living presented count is zero")
	_expect(int(result.get("spiky_flora_count", -1)) == 0, "disabled spiky presented count is zero")
	_expect(int(result.get("suppressed_instance_count", -1)) == 4, "known disabled records are suppressed")
	_expect(int(result.get("ignored_instance_count", -1)) == 0, "known disabled records are not ignored")
	_expect(int(result.get("payload_bytes", -1)) == 0, "disabled flora spends no warm payload bytes")
	_expect((result.get("living_flora_bucket_buffers", []) as Array).is_empty(), "disabled living is lazy-empty")
	_expect(
		(result.get("spiky_flora_atlas_bucket_buffers", []) as Array).is_empty(),
		"disabled spiky is lazy-empty",
	)
	var layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	root.add_child(layer)
	_expect(
		layer.begin_presentation_result(result, catalog),
		"production-disabled generated flora begins without missing-atlas failure",
	)
	_expect(layer.is_presentation_complete(), "suppressed-only presentation is immediately complete")
	_expect(layer.is_blocking_presentation_ready(), "suppressed-only chunk is immediately publish-ready")
	_expect(not layer.has_pending_presentation_apply(), "suppressed-only chunk does not enter upload queue")
	_expect(not layer.visible, "suppressed families do not change production visuals")
	layer.free()


func _verify_invalid_spiky_bank_is_rejected(world_core: Object, catalog: AssetCatalog) -> void:
	var result: Dictionary = world_core.call(
		"build_object_presentation_buffers",
		PackedByteArray([OBJECT_KIND_SPIKY_FLORA]),
		PackedByteArray([10]),
		PackedByteArray([10]),
		PackedByteArray([80]),
		PackedByteArray([2]),
		PackedByteArray([0]),
		PackedByteArray([0]),
		PackedByteArray([255]),
		PackedByteArray([0]),
		catalog.get_tree_native_metrics(),
		catalog.get_rock_native_metrics(),
		catalog.get_bush_native_metrics(),
		catalog.get_native_params(false, true),
	) as Dictionary
	_expect(result.has("error"), "out-of-contract spiky atlas bank fails explicitly")


func _drain_atomic_flora_apply(object_layer: WorldObjectPacketLayer, label: String) -> int:
	var slice_count: int = 0
	var guard: int = 16
	var allocation_counts: Dictionary = { }
	while object_layer.has_pending_presentation_apply():
		var before: Dictionary = object_layer.get_debug_state()
		var state_before: String = str(before.get("native_apply_state", ""))
		var phase_hint: StringName = object_layer.get_next_presentation_apply_phase_hint()
		var allocation_only: bool = \
				object_layer.next_presentation_slice_requires_visual_slot_allocation()
		var uploads_before: int = object_layer.get_raw_multimesh_upload_count_total()
		var advanced: bool = object_layer.apply_next_presentation_allocation_only() \
				if allocation_only \
				else object_layer.apply_next_presentation_slice(1, 4, 1)
		_expect(advanced, "%s %s slice advances" % [label, state_before])
		if allocation_only:
			allocation_counts[phase_hint] = int(allocation_counts.get(phase_hint, 0)) + 1
			_expect(
				object_layer.did_last_presentation_slice_create_visual_slot(),
				"%s %s hint performs one explicit allocation" % [label, phase_hint],
			)
			_expect(
				object_layer.get_raw_multimesh_upload_count_total() == uploads_before,
				"%s %s allocation cannot upload a raw buffer" % [label, phase_hint],
			)
		var after: Dictionary = object_layer.get_debug_state()
		if state_before == "LIVING_FLORA_BUFFERS":
			var living: Dictionary = after.get("living_flora_batch", { }) as Dictionary
			_expect(
				int(living.get("last_slice_upload_count", 0)) <= 1,
				"%s living slice uploads at most one non-empty buffer" % label,
			)
		elif state_before == "SPIKY_FLORA_BUFFERS":
			var spiky: Dictionary = after.get("spiky_flora_batch", { }) as Dictionary
			_expect(
				int(spiky.get("last_slice_upload_count", 0)) <= 1,
				"%s spiky slice uploads at most one non-empty buffer" % label,
			)
		if object_layer.has_pending_presentation_apply():
			_expect(not object_layer.visible, "%s all flora stays hidden before atomic commit" % label)
		slice_count += 1
		guard -= 1
		if guard < 0:
			_failures.append("%s flora apply exceeded structural slice bound" % label)
			break
	if label == "first":
		_expect(
			int(allocation_counts.get(
				WorldObjectPacketLayer.PRESENTATION_PHASE_LIVING_SLOT_ALLOCATION,
				0,
			)) == 3,
			"cold living flora reserves two sprite slots plus its shadow graph",
		)
		_expect(
			int(allocation_counts.get(
				WorldObjectPacketLayer.PRESENTATION_PHASE_SPIKY_SLOT_ALLOCATION,
				0,
			)) == 2,
			"cold spiky flora reserves both sprite slots through its own phase hint",
		)
	return slice_count


func _verify_completed_flora_state(object_layer: WorldObjectPacketLayer, label: String) -> void:
	var state: Dictionary = object_layer.get_debug_state()
	var living: Dictionary = state.get("living_flora_batch", { }) as Dictionary
	var spiky: Dictionary = state.get("spiky_flora_batch", { }) as Dictionary
	_expect(object_layer.visible, "%s flora reveals at coherent commit" % label)
	_expect(object_layer.is_blocking_presentation_ready(), "%s commit is publish-ready" % label)
	_expect(object_layer.is_presentation_complete(), "%s flora presentation completes" % label)
	_expect(int(living.get("instance_count", -1)) == 2, "%s living instance count" % label)
	_expect(int(living.get("shadow_instance_count", -1)) == 2, "%s living shadow count" % label)
	_expect(int(living.get("active_stripe_count", -1)) == 2, "%s living stripe count" % label)
	_expect(int(living.get("pooled_slot_count", -1)) == 2, "%s living pool size" % label)
	_expect(int(spiky.get("instance_count", -1)) == 2, "%s spiky instance count" % label)
	_expect(int(spiky.get("shadow_instance_count", -1)) == 0, "%s spiky remains shadowless" % label)
	_expect(int(spiky.get("active_stripe_count", -1)) == 2, "%s spiky stripe count" % label)
	_expect(int(spiky.get("pooled_slot_count", -1)) == 2, "%s spiky pool size" % label)
	_expect(
		_count_descendants_of_class(object_layer, "Sprite2D") == 0,
		"%s native flora creates no per-object Sprite2D" % label,
	)


func _verify_depth_rebase_is_bounded(object_layer: WorldObjectPacketLayer) -> void:
	var state: Dictionary = object_layer.get_debug_state()
	for family_key: StringName in [&"living_flora_batch", &"spiky_flora_batch"]:
		var batch: Dictionary = state.get(family_key, { }) as Dictionary
		var ladder: Dictionary = batch.get("depth_ladder", { }) as Dictionary
		_expect(
			int(ladder.get("last_root_z_writes", 99)) <= 1,
			"%s anchor+1 performs at most one root z write" % family_key,
		)
		_expect(
			int(ladder.get("last_boundary_migrations", 99)) <= 2,
			"%s anchor+1 performs at most two boundary migrations" % family_key,
		)


func _verify_hot_cache_transfer_without_reupload(
		object_layer: WorldObjectPacketLayer,
) -> WorldObjectPacketLayer:
	var upload_count_before: int = object_layer.get_raw_multimesh_upload_count_total()
	var layer_id: int = object_layer.get_instance_id()
	var living: Texture2D = object_layer._living_flora_atlas
	var spiky: Array[Texture2D] = object_layer._spiky_flora_atlases.duplicate()
	var first_view: ChunkView = ChunkView.new()
	root.add_child(first_view)
	first_view.configure(Vector2i(8, 9))
	first_view.set_living_flora_source(living)
	first_view.set_spiky_flora_sources(spiky)
	_expect(
		first_view.adopt_committed_object_layer_from_hot_cache(object_layer),
		"committed flora layer can be adopted without rebuilding",
	)
	var cached: WorldObjectPacketLayer = first_view.detach_committed_object_layer_for_hot_cache()
	_expect(cached == object_layer, "hot-cache detach preserves layer identity")
	var cache_root: Node2D = Node2D.new()
	cache_root.visible = false
	root.add_child(cache_root)
	cache_root.add_child(cached)
	var second_view: ChunkView = ChunkView.new()
	root.add_child(second_view)
	second_view.configure(Vector2i(8, 9))
	second_view.set_living_flora_source(living)
	second_view.set_spiky_flora_sources(spiky)
	_expect(
		second_view.adopt_committed_object_layer_from_hot_cache(cached),
		"zoom restore promotes the resident layer",
	)
	_expect(cached.get_instance_id() == layer_id, "zoom restore reuses the exact object layer")
	_expect(
		cached.get_raw_multimesh_upload_count_total() == upload_count_before,
		"hot-cache detach/promote performs zero raw MultiMesh uploads",
	)
	_expect(
		int(cached.get_debug_state().get("tree_collision_layer", -1)) == 0,
		"promoted layer collision remains off until ChunkView reveal",
	)
	var result_layer: WorldObjectPacketLayer = \
			second_view.detach_committed_object_layer_for_hot_cache()
	root.add_child(result_layer)
	first_view.free()
	second_view.free()
	cache_root.free()
	return result_layer


func _stripe_slot_ids(batch_layer: Node) -> PackedInt64Array:
	var ids := PackedInt64Array()
	if batch_layer == null:
		return ids
	for node: Node in batch_layer.find_children("NativeDecorStripe*", "MultiMeshInstance2D", true, false):
		ids.append(node.get_instance_id())
	ids.sort()
	return ids


func _verify_shared_flora_materials(
		living_layer: Node,
		spiky_layer: Node,
		catalog: AssetCatalog,
) -> void:
	if living_layer != null:
		for node: Node in living_layer.find_children(
			"NativeDecorStripe*",
			"MultiMeshInstance2D",
			true,
			false,
		):
			_expect(
				(node as MultiMeshInstance2D).material == catalog.get_living_flora_material(),
				"living stripe uses the catalog-shared material",
			)
		var shadow: MultiMeshInstance2D = living_layer.get_node_or_null(
			"NativeDecorShadowBatch",
		) as MultiMeshInstance2D
		_expect(shadow != null, "living shadow batch exists")
		if shadow != null:
			_expect(
				shadow.material == catalog.get_classic_decor_shadow_material(),
				"living shadow uses the catalog-shared material",
			)
	if spiky_layer != null:
		for node: Node in spiky_layer.find_children(
			"NativeDecorStripe*",
			"MultiMeshInstance2D",
			true,
			false,
		):
			_expect(
				(node as MultiMeshInstance2D).material == catalog.get_spiky_flora_material(),
				"spiky stripe uses the catalog-shared material",
			)


func _count_descendants_of_class(parent: Node, class_name_to_find: String) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child.is_class(class_name_to_find):
			count += 1
		count += _count_descendants_of_class(child, class_name_to_find)
	return count


func _make_texture(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _expect_close(actual: float, expected: float, label: String) -> void:
	_expect(is_equal_approx(actual, expected), "%s (expected %.6f, got %.6f)" % [label, expected, actual])


func _finish(object_layer: WorldObjectPacketLayer) -> void:
	if object_layer != null and is_instance_valid(object_layer):
		object_layer.free()
	if _failures.is_empty():
		print("Object presentation flora contract: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
