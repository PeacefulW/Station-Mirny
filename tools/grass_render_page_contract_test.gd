extends SceneTree

const GrassRenderPage = preload("res://core/systems/world/grass_render_page.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const STRIDE: int = 12
const DENSE_INSTANCE_COUNT: int = \
		WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK * GrassRenderPage.PAGE_SLOT_COUNT

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_page_key_contract()
	var texture: Texture2D = _make_texture()
	var material_template: ShaderMaterial = _make_material()
	var page := GrassRenderPage.new()
	root.add_child(page)
	var owner_page := Vector2i(-1, -2)
	_expect(
		page.configure(
			owner_page,
			texture,
			material_template,
			texture,
			material_template,
			material_template,
			material_template,
		),
		"full-LOD page configures",
	)
	_expect(
		page.position == Vector2(-4096.0, -2048.0),
		"page root uses exact fixed 4x1 world origin",
	)
	var configured_state: Dictionary = page.get_debug_state()
	_expect(
		int(configured_state.get("shell_canvas_item_count", -1)) == _count_canvas_items(page),
		"shell diagnostics count the real page/depth-band CanvasItems",
	)
	_expect(_count_canvas_items(page) == 5, "cold shell allocation is explicitly bounded at five")
	_expect(
		int(configured_state.get("allocated_albedo_layer_count", -1)) == 0,
		"configure creates no cold stripe CanvasItems",
	)
	_expect(
		int(configured_state.get("allocated_fixed_layer_count", -1)) == 0,
		"configure creates no cold fixed-pass CanvasItems",
	)

	var revisions := PackedInt64Array([101, 102, 103, 104])
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		_expect(page.set_slot_active(slot, true, revisions[slot]), "slot activates")
	var first_result: Dictionary = _make_dense_result(owner_page, 7, revisions, 0.0)
	_expect(page.stage_result(first_result), "first complete native page result stages")
	_assert_front_untouched(page, -1, RID(), PackedFloat32Array(), "initial stage")
	_drain_to_commit(page, -1, RID(), PackedFloat32Array(), "initial stage")
	var precommit: Dictionary = page.get_debug_state()
	_expect(
		int(precommit.get("raw_multimesh_upload_count_total", -1)) == 65,
		"four dense contributors upload 64 albedo buffers plus one flat shadow",
	)
	_expect(page.get_raw_upload_count_total() == 65, "hot counter getter matches diagnostics")
	_expect(page.get_commit_count_total() == 0, "hot commit getter stays zero before COMMIT")
	_expect(page.apply_next_upload_phase(), "initial page commit advances")
	_expect(not page.has_pending_upload(), "initial page commit drains transaction")
	_expect(page.get_commit_count_total() == 1, "hot commit getter advances atomically")

	var first_state: Dictionary = page.get_debug_state()
	_expect(int(first_state.get("page_revision", -1)) == 7, "front page revision commits")
	_expect(int(first_state.get("visible_slot_mask", -1)) == 0b1111, "all four slots reveal")
	_expect(
		int(first_state.get("instance_count", -1)) == DENSE_INSTANCE_COUNT,
		"merged page preserves every contributor instance",
	)
	_expect(
		int(first_state.get("albedo_draw_layer_count", -1)) == 64,
		"four dense chunks collapse to 64 exact global depth-stripe draws",
	)
	_expect(
		int(first_state.get("directional_shadow_draw_layer_count", -1)) == 1,
		"four dense chunk shadows collapse to one fixed-z page draw",
	)
	_expect(
		int(first_state.get("grass_and_directional_shadow_draw_layer_count", -1)) == 65,
		"dense structural contract reduces legacy 260 layers to 65",
	)
	_expect(
		int(first_state.get("max_stripe_multimesh_resource_count", -1)) == 1,
		"first commit owns one MultiMesh per stripe",
	)
	_expect(
		int(first_state.get("canvas_item_allocation_count_total", -1)) == 65,
		"dense cold graph allocates exactly 64 albedo items plus one shadow item",
	)
	_expect(
		int(first_state.get("graph_visibility_sync_count_total", -1)) == 1,
		"initial commit performs one graph visibility synchronization",
	)
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		_expect(page.is_slot_committed(slot), "slot %d exact revision is committed" % slot)

	var first_layer: MultiMeshInstance2D = page._albedo_layers[0]
	var first_multimesh: MultiMesh = first_layer.multimesh
	var first_rid: RID = first_multimesh.get_rid()
	var first_buffer: PackedFloat32Array = first_multimesh.buffer.duplicate()
	_expect(
		first_buffer == first_result.bucket_buffers[0],
		"native merged raw buffer reaches the front without repacking",
	)
	_assert_merged_slot_positions(first_buffer, 0.0)
	_expect(
		first_layer.material != material_template,
		"page owns a material clone instead of mutating the authored template",
	)
	var page_material: ShaderMaterial = first_layer.material as ShaderMaterial
	_expect(
		int(page_material.get_shader_parameter("page_slot_mask")) == 0b1111,
		"material clone receives the committed active slot mask",
	)
	_expect(
		is_equal_approx(
			float(page_material.get_shader_parameter("page_origin_x")),
			-4096.0,
		),
		"material clone receives the exact page origin",
	)
	_expect(
		is_equal_approx(
			float(page_material.get_shader_parameter("page_slot_width_px")),
			1024.0,
		),
		"material clone receives the exact slot width",
	)
	var template_mask: Variant = material_template.get_shader_parameter("page_slot_mask")
	_expect(
		template_mask == null or int(template_mask) == 0,
		"page mask never mutates the shared authored template",
	)

	_assert_depth_contract(page, owner_page, first_rid)
	_test_active_revision_gate(page, revisions)

	# A newer result uploads entirely into back resources. Even after every raw
	# upload, the front RID, buffer and page revision remain the old transaction.
	var second_revisions: PackedInt64Array = revisions.duplicate()
	second_revisions[1] = 202
	_expect(page.set_slot_active(1, true, 202), "new slot revision becomes required")
	_expect(not page.is_slot_committed(1), "old front is hidden for mismatched required revision")
	var second_result: Dictionary = _make_sparse_result(owner_page, 8, second_revisions, 0.5)
	_expect(page.stage_result(second_result), "second complete result stages")
	_drain_to_commit(page, 7, first_rid, first_buffer, "second stage")
	_expect(
		page._albedo_layers[0].multimesh.get_rid() == first_rid,
		"precommit keeps the exact old front RID",
	)
	_expect(page.apply_next_upload_phase(), "second atomic commit advances")
	var second_state: Dictionary = page.get_debug_state()
	var second_rid: RID = page._albedo_layers[0].multimesh.get_rid()
	_expect(int(second_state.get("page_revision", -1)) == 8, "second revision commits")
	_expect(second_rid != first_rid, "second transaction swaps to its unattached back RID")
	_expect(page.is_slot_committed(1), "new contributor revision reveals only after commit")
	_expect(
		int(second_state.get("max_stripe_multimesh_resource_count", -1)) == 2,
		"front/back pool is bounded to two resources per stripe",
	)
	_assert_merged_slot_positions(page._albedo_layers[0].multimesh.buffer, 0.5)

	# Third commit must reuse the first RID instead of allocating a third resource.
	var third_revisions: PackedInt64Array = second_revisions.duplicate()
	third_revisions[1] = 203
	page.set_slot_active(1, true, 203)
	var third_result: Dictionary = _make_sparse_result(owner_page, 9, third_revisions, 1.0)
	_expect(page.stage_result(third_result), "third result stages")
	_drain_all(page)
	_expect(
		page._albedo_layers[0].multimesh.get_rid() == first_rid,
		"third transaction ping-pongs back to the first RID",
	)
	_expect(page.is_slot_committed(1), "third required revision commits")
	var commits_before_stale: int = int(page.get_debug_state().get("commit_count_total", -1))
	_expect(not page.stage_result(second_result), "stale page result is rejected")
	_expect(
		int(page.get_debug_state().get("commit_count_total", -1)) == commits_before_stale,
		"stale result cannot mutate the committed front",
	)
	var cancel_front_rid: RID = page._albedo_layers[0].multimesh.get_rid()
	var cancel_front_buffer: PackedFloat32Array = \
			page._albedo_layers[0].multimesh.buffer.duplicate()
	var uploads_before_cancel: int = page.get_raw_upload_count_total()
	var cancel_result: Dictionary = _make_sparse_result(owner_page, 10, third_revisions, 2.0)
	_expect(page.stage_result(cancel_result), "new back-buffer candidate stages for cancellation")
	_expect(page.apply_next_upload_phase(), "staged candidate performs bounded partial upload")
	_expect(page.get_raw_upload_count_total() == uploads_before_cancel + 1,
		"cancellation fixture reaches one unpublished raw back upload")
	_expect(page.cancel_pending_upload(), "pending back-buffer candidate cancels")
	_expect(not page.has_pending_upload(), "cancellation drains only staged transaction state")
	_expect(not page.cancel_pending_upload(), "idle page cancellation is an allocation-free no-op")
	_assert_front_untouched(page, 9, cancel_front_rid, cancel_front_buffer, "canceled stage")
	_expect(page.get_commit_count_total() == commits_before_stale,
		"canceled staged candidate cannot increment commit count")

	_test_contact_and_spore_fallback(texture, material_template)
	page.clear()
	_expect(
		not bool(page.get_debug_state().get("configured", true)),
		"clear returns a pooled page to an unconfigured admission state",
	)
	page.free()
	texture = null
	material_template = null
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	print("grass_render_page_contract_test: PASS")
	quit(0)


func _test_page_key_contract() -> void:
	var cases := {
		-5: Vector2i(-2, 7),
		-4: Vector2i(-1, 7),
		-1: Vector2i(-1, 7),
		0: Vector2i(0, 7),
		3: Vector2i(0, 7),
		4: Vector2i(1, 7),
	}
	for chunk_x_variant: Variant in cases:
		var chunk_x: int = int(chunk_x_variant)
		var chunk_coord := Vector2i(chunk_x, 7)
		var expected_page: Vector2i = cases[chunk_x] as Vector2i
		_expect(
			GrassRenderPage.page_coord_for_chunk(chunk_coord) == expected_page,
			"chunk x=%d uses mathematical floor page key" % chunk_x,
		)
		var slot: int = GrassRenderPage.page_slot_for_chunk(chunk_coord)
		_expect(slot >= 0 and slot < 4, "chunk x=%d maps to a bounded page slot" % chunk_x)
		_expect(
			expected_page.x * 4 + slot == chunk_x,
			"page key plus slot exactly reconstructs chunk x=%d" % chunk_x,
		)


func _assert_depth_contract(page: GrassRenderPage, owner_page: Vector2i, first_rid: RID) -> void:
	var chunk_row_base: int = owner_page.y * WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK
	var anchor: int = chunk_row_base + 31
	page.update_anchor(anchor)
	for stripe_index: int in [0, 31, 63]:
		var expected_z: int = WorldRuntimeConstants.z_for_stripe_vs_anchor(
			chunk_row_base + stripe_index,
			anchor,
			false,
		)
		_expect(
			_effective_z(page._albedo_layers[stripe_index], page) == expected_z,
			"page stripe %d preserves exact global depth z" % stripe_index,
		)
	var uploads_before: int = int(
		page.get_debug_state().get("raw_multimesh_upload_count_total", -1),
	)
	page.update_anchor(anchor + 1)
	var ladder: Dictionary = page.get_debug_state().get("depth_ladder", { }) as Dictionary
	_expect(
		int(ladder.get("last_root_z_writes", 99)) <= 1,
		"one-stripe page anchor move writes at most one band-root z",
	)
	_expect(
		int(ladder.get("last_boundary_migrations", 99)) <= 2,
		"one-stripe page anchor move migrates at most two boundary items",
	)
	_expect(
		int(page.get_debug_state().get("raw_multimesh_upload_count_total", -1)) \
				== uploads_before,
		"depth rebase performs zero raw GPU uploads",
	)
	_expect(
		page._albedo_layers[0].multimesh.get_rid() == first_rid,
		"depth rebase preserves front MultiMesh RID",
	)
	_expect(
		page._directional_shadow_layer.z_index == WorldRuntimeConstants.Z_GRASS_SHADOW + 1,
		"directional shadow remains at exact fixed pre-ladder z",
	)
	_expect(
		page._contact_shadow_layer == null,
		"unused contact pass performs no cold CanvasItem allocation",
	)
	_expect(
		page._spore_layer == null,
		"empty spore pass performs no cold CanvasItem allocation",
	)


func _test_active_revision_gate(page: GrassRenderPage, revisions: PackedInt64Array) -> void:
	var graph_syncs_before: int = int(
		page.get_debug_state().get("graph_visibility_sync_count_total", -1),
	)
	_expect(page.set_slot_active(2, false, revisions[2]), "slot deactivates")
	_expect(not page.is_slot_committed(2), "inactive resident slot is not reveal-ready")
	_expect(
		int(page.get_debug_state().get("visible_slot_mask", -1)) == 0b1011,
		"deactivation changes only the material gate",
	)
	_expect(page.set_slot_active(2, true, 999), "slot activates with newer requirement")
	_expect(not page.is_slot_committed(2), "revision mismatch remains hidden")
	_expect(
		int(page.get_debug_state().get("visible_slot_mask", -1)) == 0b1011,
		"mismatched revision does not leak through page mask",
	)
	_expect(page.set_slot_active(2, true, revisions[2]), "slot exact requirement restores")
	_expect(page.is_slot_committed(2), "resident exact revision restores without upload")
	_expect(
		int(page.get_debug_state().get("visible_slot_mask", -1)) == 0b1111,
		"exact warm slot restore returns to the visible mask",
	)
	_expect(
		int(page.get_debug_state().get("graph_visibility_sync_count_total", -1)) \
				== graph_syncs_before,
		"nonzero-to-nonzero slot changes touch only material masks",
	)
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		page.set_slot_active(slot, false, revisions[slot])
	_expect(
		int(page.get_debug_state().get("graph_visibility_sync_count_total", -1)) \
				== graph_syncs_before + 1,
		"last active slot leaving performs one visible-to-hidden graph sync",
	)
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		page.set_slot_active(slot, true, revisions[slot])
	_expect(
		int(page.get_debug_state().get("graph_visibility_sync_count_total", -1)) \
				== graph_syncs_before + 2,
		"first warm slot entering performs one hidden-to-visible graph sync",
	)


func _test_contact_and_spore_fallback(
		texture: Texture2D,
		material_template: ShaderMaterial,
) -> void:
	var page := GrassRenderPage.new()
	root.add_child(page)
	_expect(
		page.configure(
			Vector2i.ZERO,
			texture,
			material_template,
			null,
			null,
			material_template,
			material_template,
		),
		"contact/spore fallback page configures",
	)
	page.set_slot_active(0, true, 1)
	var buckets: Array = []
	buckets.resize(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK)
	for stripe_index: int in range(buckets.size()):
		buckets[stripe_index] = PackedFloat32Array()
	var instance: PackedFloat32Array = _make_instance(0, 3, 0.0)
	buckets[3] = instance
	var result := {
		"page_coord": Vector2i.ZERO,
		"page_revision": 1,
		"contributor_mask": 1,
		"contributor_revisions": PackedInt64Array([1, 0, 0, 0]),
		"bucket_buffers": buckets,
		"directional_shadow_buffer": instance,
		"shadow_buffer": instance,
		"spore_buffer": instance,
	}
	_expect(page.stage_result(result), "contact/spore result stages")
	_drain_all(page)
	var state: Dictionary = page.get_debug_state()
	_expect(int(state.get("albedo_draw_layer_count", -1)) == 1, "fallback albedo commits")
	_expect(
		int(state.get("directional_shadow_draw_layer_count", -1)) == 0,
		"contact mode ignores the mutually exclusive directional payload",
	)
	_expect(int(state.get("contact_shadow_draw_layer_count", -1)) == 1, "contact pass commits")
	_expect(int(state.get("spore_draw_layer_count", -1)) == 1, "spore pass commits")
	_expect(
		page._contact_shadow_layer.z_index == WorldRuntimeConstants.Z_GRASS_SHADOW,
		"contact fallback remains below the ladder",
	)
	_expect(
		page._spore_layer.z_index == WorldRuntimeConstants.Z_GRASS_SPORE,
		"spore fallback remains above the complete ladder",
	)
	page.free()


func _make_dense_result(
		owner_page: Vector2i,
		page_revision: int,
		contributor_revisions: PackedInt64Array,
		translation_delta: float,
) -> Dictionary:
	var buckets: Array = []
	buckets.resize(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK)
	var directional := PackedFloat32Array()
	for stripe_index: int in range(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK):
		var stripe_buffer := PackedFloat32Array()
		for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
			stripe_buffer.append_array(_make_instance(slot, stripe_index, translation_delta))
		buckets[stripe_index] = stripe_buffer
		directional.append_array(stripe_buffer)
	return {
		"page_coord": owner_page,
		"page_revision": page_revision,
		"contributor_mask": 0b1111,
		"contributor_revisions": contributor_revisions,
		"bucket_buffers": buckets,
		"directional_shadow_buffer": directional,
		"shadow_buffer": PackedFloat32Array(),
		"spore_buffer": PackedFloat32Array(),
	}


func _make_sparse_result(
		owner_page: Vector2i,
		page_revision: int,
		contributor_revisions: PackedInt64Array,
		translation_delta: float,
) -> Dictionary:
	var buckets: Array = []
	buckets.resize(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK)
	for stripe_index: int in range(buckets.size()):
		buckets[stripe_index] = PackedFloat32Array()
	var stripe_buffer := PackedFloat32Array()
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		stripe_buffer.append_array(_make_instance(slot, 0, translation_delta))
	buckets[0] = stripe_buffer
	return {
		"page_coord": owner_page,
		"page_revision": page_revision,
		"contributor_mask": 0b1111,
		"contributor_revisions": contributor_revisions,
		"bucket_buffers": buckets,
		"directional_shadow_buffer": stripe_buffer,
		"shadow_buffer": PackedFloat32Array(),
		"spore_buffer": PackedFloat32Array(),
	}


func _make_instance(slot: int, stripe_index: int, translation_delta: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		1.0 + float(slot) * 0.1,
		0.0,
		0.0,
		float(slot * GrassRenderPage.CHUNK_SIZE_PX + 10 + stripe_index) + translation_delta,
		0.0,
		1.0 + float(slot) * 0.2,
		0.0,
		float(stripe_index * WorldRuntimeConstants.DEPTH_STRIPE_PX + 2),
		float(slot) / 255.0,
		0.8 + float(slot) * 0.05,
		0.1 + float(stripe_index) / 255.0,
		1.0,
	])


func _assert_merged_slot_positions(buffer: PackedFloat32Array, translation_delta: float) -> void:
	_expect(buffer.size() == GrassRenderPage.PAGE_SLOT_COUNT * STRIDE, "merged stripe has four instances")
	if buffer.size() != GrassRenderPage.PAGE_SLOT_COUNT * STRIDE:
		return
	for slot: int in range(GrassRenderPage.PAGE_SLOT_COUNT):
		var offset: int = slot * STRIDE
		_expect(
			is_equal_approx(
				buffer[offset + 3],
				float(slot * GrassRenderPage.CHUNK_SIZE_PX + 10) + translation_delta,
			),
			"slot %d keeps exact page-local X translation" % slot,
		)
		_expect(is_equal_approx(buffer[offset + 7], 2.0), "slot %d keeps local Y" % slot)
		_expect(
			is_equal_approx(buffer[offset + 8], float(slot) / 255.0),
			"slot %d keeps native color/frame data" % slot,
		)


func _drain_to_commit(
		page: GrassRenderPage,
		expected_front_revision: int,
		expected_front_rid: RID,
		expected_front_buffer: PackedFloat32Array,
		label: String,
) -> void:
	var guard: int = 256
	while str(page.get_debug_state().get("upload_phase", "")) != "COMMIT" and guard > 0:
		_expect(page.apply_next_upload_phase(), "%s upload phase advances" % label)
		_assert_callback_budget(page, label)
		_assert_front_untouched(
			page,
			expected_front_revision,
			expected_front_rid,
			expected_front_buffer,
			label,
		)
		guard -= 1
	_expect(guard > 0, "%s reaches bounded commit phase" % label)


func _assert_front_untouched(
		page: GrassRenderPage,
		expected_front_revision: int,
		expected_front_rid: RID,
		expected_front_buffer: PackedFloat32Array,
		label: String,
) -> void:
	_expect(
		int(page.get_debug_state().get("page_revision", -99)) == expected_front_revision,
		"%s cannot publish revision before commit" % label,
	)
	var layer: MultiMeshInstance2D = page._albedo_layers[0]
	if expected_front_revision < 0:
		_expect(
			layer == null or layer.multimesh == null,
			"%s keeps initial front unattached" % label,
		)
		return
	_expect(layer.multimesh != null, "%s keeps previous front resource" % label)
	if layer.multimesh == null:
		return
	_expect(layer.multimesh.get_rid() == expected_front_rid, "%s keeps previous front RID" % label)
	_expect(layer.multimesh.buffer == expected_front_buffer, "%s keeps previous front buffer" % label)


func _drain_all(page: GrassRenderPage) -> void:
	var guard: int = 256
	while page.has_pending_upload() and guard > 0:
		page.apply_next_upload_phase()
		_assert_callback_budget(page, "drain")
		guard -= 1
	_expect(guard > 0, "page upload transaction drains within structural phase bound")


func _assert_callback_budget(page: GrassRenderPage, label: String) -> void:
	var state: Dictionary = page.get_debug_state()
	var canvas_allocations: int = int(
		state.get("last_callback_canvas_item_allocation_count", 0),
	)
	var multimesh_allocations: int = int(
		state.get("last_callback_multimesh_allocation_count", 0),
	)
	var raw_uploads: int = int(state.get("last_callback_raw_upload_count", 0))
	_expect(canvas_allocations <= 1, "%s callback allocates at most one CanvasItem" % label)
	_expect(multimesh_allocations <= 1, "%s callback allocates at most one MultiMesh" % label)
	_expect(raw_uploads <= 1, "%s callback uploads at most one raw buffer" % label)
	_expect(
		(canvas_allocations == 0 and multimesh_allocations == 0) or raw_uploads == 0,
		"%s callback separates cold allocation from raw upload" % label,
	)


static func _effective_z(item: CanvasItem, stop_parent: CanvasItem) -> int:
	var result: int = item.z_index
	var parent: Node = item.get_parent()
	while parent != null and parent != stop_parent:
		if parent is CanvasItem:
			result += (parent as CanvasItem).z_index
		parent = parent.get_parent()
	return result


static func _count_canvas_items(node: Node) -> int:
	var count: int = 1 if node is CanvasItem else 0
	for child: Node in node.get_children():
		count += _count_canvas_items(child)
	return count


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
