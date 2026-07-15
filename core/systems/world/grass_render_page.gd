class_name GrassRenderPage
extends Node2D

## World-owned full-detail grass presentation for a fixed horizontal 4x1
## chunk page. Native code supplies one complete, immutable page result. GPU
## buffers are uploaded into unattached MultiMesh resources; the committed
## CanvasItems keep their old resources until one synchronous COMMIT phase.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DepthLadderBandRoot = preload("res://core/systems/world/depth_ladder_band_root.gd")
const GrassRenderPageResourceSet = preload(
	"res://core/systems/world/grass_render_page_resource_set.gd"
)

const PAGE_WIDTH_CHUNKS: int = 4
const PAGE_SLOT_COUNT: int = PAGE_WIDTH_CHUNKS
const BUFFER_STRIDE: int = 12
const STRIPE_COUNT: int = WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK
const CHUNK_SIZE_PX: int = \
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX
const PAGE_WIDTH_PX: int = PAGE_WIDTH_CHUNKS * CHUNK_SIZE_PX
const LADDER_ANCHOR_UNSET: int = 1 << 30

enum UploadPhase {
	IDLE,
	STRIPES,
	DIRECTIONAL_SHADOW,
	CONTACT_SHADOW,
	SPORES,
	COMMIT,
}

static var _shared_unit_texture: ImageTexture = null

var page_coord: Vector2i = Vector2i.ZERO

var _configured: bool = false
var _grass_atlas: Texture2D = null
var _directional_shadow_atlas: Texture2D = null
var _albedo_material: ShaderMaterial = null
var _directional_shadow_material: ShaderMaterial = null
var _contact_shadow_material: ShaderMaterial = null
var _spore_material: ShaderMaterial = null
var _uses_directional_shadow_atlas: bool = false

var _depth_ladder: DepthLadderBandRoot = null
var _albedo_layers: Array[MultiMeshInstance2D] = []
var _directional_shadow_layer: MultiMeshInstance2D = null
var _contact_shadow_layer: MultiMeshInstance2D = null
var _spore_layer: MultiMeshInstance2D = null
var _resources: GrassRenderPageResourceSet = GrassRenderPageResourceSet.new()

var _front_page_revision: int = -1
var _front_contributor_mask: int = 0
var _front_contributor_revisions := PackedInt64Array()
var _active_slot_mask: int = 0
var _visible_slot_mask: int = 0
var _required_slot_revisions := PackedInt64Array()

var _staged_result: Dictionary = { }
var _staged_page_revision: int = -1
var _staged_contributor_mask: int = 0
var _staged_contributor_revisions := PackedInt64Array()
var _staged_bucket_buffers: Array = []
var _staged_directional_buffer := PackedFloat32Array()
var _staged_contact_buffer := PackedFloat32Array()
var _staged_spore_buffer := PackedFloat32Array()
var _upload_phase: int = UploadPhase.IDLE
var _upload_stripe: int = 0

var _front_instance_count: int = 0
var _front_albedo_draw_layer_count: int = 0
var _commit_count_total: int = 0
var _stale_result_reject_count_total: int = 0
var _graph_visibility_sync_count_total: int = 0
var _canvas_item_allocation_count_total: int = 0
var _last_callback_canvas_item_allocation_count: int = 0
var _applied_anchor_stripe: int = LADDER_ANCHOR_UNSET


## Uses mathematical floor division, not truncation toward zero. Page Y is one
## chunk high so its coordinate is the source chunk row unchanged.
static func page_coord_for_chunk(chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(_floor_div(chunk_coord.x, PAGE_WIDTH_CHUNKS), chunk_coord.y)


static func page_slot_for_chunk(chunk_coord: Vector2i) -> int:
	var owner_page: Vector2i = page_coord_for_chunk(chunk_coord)
	return chunk_coord.x - owner_page.x * PAGE_WIDTH_CHUNKS


static func slot_for_chunk(chunk_coord: Vector2i) -> int:
	return page_slot_for_chunk(chunk_coord)


static func page_origin_for_coord(owner_page_coord: Vector2i) -> Vector2:
	return Vector2(
		float(owner_page_coord.x * PAGE_WIDTH_PX),
		float(owner_page_coord.y * CHUNK_SIZE_PX),
	)


static func _floor_div(value: int, divisor: int) -> int:
	var remainder: int = posmod(value, divisor)
	return int((value - remainder) / divisor)


func _init() -> void:
	_resize_fixed_state()


## The signature mirrors ChunkView's existing grass presentation sources.
## Directional-shadow atlas mode and contact-blob mode are mutually exclusive:
## when the atlas pair is supplied, shadow_buffer is intentionally ignored.
func configure(
		next_page_coord: Vector2i,
		grass_atlas: Texture2D,
		grass_material: ShaderMaterial,
		grass_shadow_atlas: Texture2D = null,
		grass_shadow_atlas_material: ShaderMaterial = null,
		shadow_material: ShaderMaterial = null,
		spore_material: ShaderMaterial = null,
) -> bool:
	if grass_atlas == null or grass_material == null:
		push_error("GrassRenderPage: grass atlas and material are required")
		return false
	if (grass_shadow_atlas == null) != (grass_shadow_atlas_material == null):
		push_error("GrassRenderPage: directional-shadow atlas and material must be paired")
		return false

	clear()
	page_coord = next_page_coord
	name = "GrassRenderPage_%d_%d" % [page_coord.x, page_coord.y]
	position = page_origin_for_coord(page_coord)
	_grass_atlas = grass_atlas
	_directional_shadow_atlas = grass_shadow_atlas
	_uses_directional_shadow_atlas = \
			grass_shadow_atlas != null and grass_shadow_atlas_material != null
	_albedo_material = _make_page_material(grass_material)
	_directional_shadow_material = _make_page_material(grass_shadow_atlas_material)
	_contact_shadow_material = _make_page_material(shadow_material)
	_spore_material = _make_page_material(spore_material)
	_ensure_page_shell()
	_apply_sources_to_graph()
	_depth_ladder.set_world_origin_y(position.y)
	if _applied_anchor_stripe != LADDER_ANCHOR_UNSET:
		_depth_ladder.update_anchor(_applied_anchor_stripe)
	_configured = true
	_refresh_visible_slot_mask()
	return true


## Accepts one complete native page result. Superseding a partially uploaded
## result only discards its unattached candidates; the committed front remains
## unchanged until the newer transaction reaches COMMIT.
func stage_result(result: Dictionary) -> bool:
	if not _configured:
		push_error("GrassRenderPage: configure() must run before stage_result()")
		return false
	if not _result_is_valid(result):
		return false
	var result_revision: int = int(result.get("page_revision", -1))
	var newest_revision: int = _staged_page_revision \
			if has_pending_upload() else _front_page_revision
	if result_revision <= newest_revision:
		_stale_result_reject_count_total += 1
		return false

	_cancel_pending_upload(false)
	_staged_result = result.duplicate(false)
	_staged_page_revision = result_revision
	_staged_contributor_mask = int(result.get("contributor_mask", 0))
	_staged_contributor_revisions = (
		result.get("contributor_revisions", PackedInt64Array()) as PackedInt64Array
	)
	_staged_bucket_buffers = (result.get("bucket_buffers", []) as Array).duplicate(false)
	_staged_directional_buffer = result.get(
		"directional_shadow_buffer",
		PackedFloat32Array(),
	) as PackedFloat32Array
	_staged_contact_buffer = result.get("shadow_buffer", PackedFloat32Array()) \
			as PackedFloat32Array
	_staged_spore_buffer = result.get("spore_buffer", PackedFloat32Array()) \
			as PackedFloat32Array
	_resources.begin_staging()
	_upload_stripe = 0
	_upload_phase = UploadPhase.STRIPES
	return true


## Advances no more than one raw MultiMesh upload. Empty entries and phase-only
## transitions may be skipped in the same callback; COMMIT performs only cheap
## resource-reference swaps and visibility/material state updates.
func apply_next_upload_phase() -> bool:
	if not has_pending_upload():
		return false
	_last_callback_canvas_item_allocation_count = 0
	_resources.reset_callback_counters()
	match _upload_phase:
		UploadPhase.STRIPES:
			while _upload_stripe < STRIPE_COUNT:
				var stripe_index: int = _upload_stripe
				var buffer: PackedFloat32Array = \
						_staged_bucket_buffers[stripe_index] as PackedFloat32Array
				var count: int = buffer.size() / BUFFER_STRIDE
				if count <= 0 and _resources.front_stripe_count(stripe_index) <= 0:
					_upload_stripe += 1
					continue
				if count > 0 and _stripe_candidate_requires_allocation(stripe_index, count):
					_allocate_stripe_candidate(stripe_index, count)
					return true
				_resources.stage_stripe(stripe_index, buffer)
				_upload_stripe += 1
				return true
			_upload_phase = UploadPhase.DIRECTIONAL_SHADOW
			return true
		UploadPhase.DIRECTIONAL_SHADOW:
			if _uses_directional_shadow_atlas:
				var directional_count: int = _staged_directional_buffer.size() / BUFFER_STRIDE
				if directional_count > 0 and _fixed_candidate_requires_allocation(
					_directional_shadow_layer,
					GrassRenderPageResourceSet.FixedPass.DIRECTIONAL_SHADOW,
					directional_count,
				):
					_allocate_directional_candidate(directional_count)
					return true
				_resources.stage_fixed(
					GrassRenderPageResourceSet.FixedPass.DIRECTIONAL_SHADOW,
					_staged_directional_buffer,
				)
			_upload_phase = UploadPhase.CONTACT_SHADOW
			return true
		UploadPhase.CONTACT_SHADOW:
			if not _uses_directional_shadow_atlas:
				var contact_count: int = _staged_contact_buffer.size() / BUFFER_STRIDE
				if contact_count > 0 and _fixed_candidate_requires_allocation(
					_contact_shadow_layer,
					GrassRenderPageResourceSet.FixedPass.CONTACT_SHADOW,
					contact_count,
				):
					_allocate_contact_candidate(contact_count)
					return true
				_resources.stage_fixed(
					GrassRenderPageResourceSet.FixedPass.CONTACT_SHADOW,
					_staged_contact_buffer,
				)
			_upload_phase = UploadPhase.SPORES
			return true
		UploadPhase.SPORES:
			var spore_count: int = _staged_spore_buffer.size() / BUFFER_STRIDE
			if spore_count > 0 and _fixed_candidate_requires_allocation(
				_spore_layer,
				GrassRenderPageResourceSet.FixedPass.SPORES,
				spore_count,
			):
				_allocate_spore_candidate(spore_count)
				return true
			_resources.stage_fixed(
				GrassRenderPageResourceSet.FixedPass.SPORES,
				_staged_spore_buffer,
			)
			_upload_phase = UploadPhase.COMMIT
			return true
		UploadPhase.COMMIT:
			_commit_staged_result()
			return true
	return false


func has_pending_upload() -> bool:
	return _upload_phase != UploadPhase.IDLE and not _staged_result.is_empty()


## Cancels only the unpublished back-buffer transaction. The committed front
## resources, contributor revisions, slot masks and draw graph stay unchanged.
func cancel_pending_upload() -> bool:
	if not has_pending_upload():
		return false
	_cancel_pending_upload(false)
	return true


## Allocation-free counters for a coordinator's hot visual lane. The complete
## debug snapshot intentionally remains a diagnostics-only API.
func get_raw_upload_count_total() -> int:
	return _resources.raw_upload_count_total


func get_commit_count_total() -> int:
	return _commit_count_total


## Includes this page root, its depth-ladder root and all fixed band roots.
## Layer CanvasItems created later by upload phases are intentionally separate.
func get_shell_canvas_item_count() -> int:
	return 1 + (_depth_ladder.get_canvas_item_count() \
			if _depth_ladder != null and is_instance_valid(_depth_ladder) else 0)


## Active slots are a page-local shader gate. Their committed data remains in
## the front buffers while hidden, enabling an exact zero-upload zoom restore.
func set_slot_active(slot: int, active: bool, required_revision: int) -> bool:
	if slot < 0 or slot >= PAGE_SLOT_COUNT:
		push_error("GrassRenderPage: page slot is outside 0..3")
		return false
	var bit: int = 1 << slot
	if active:
		_active_slot_mask |= bit
		_required_slot_revisions[slot] = required_revision
	else:
		_active_slot_mask &= ~bit
		_required_slot_revisions[slot] = 0
	_refresh_visible_slot_mask()
	return true


func is_slot_committed(slot: int) -> bool:
	if slot < 0 or slot >= PAGE_SLOT_COUNT:
		return false
	var bit: int = 1 << slot
	return (_active_slot_mask & bit) != 0 \
			and (_front_contributor_mask & bit) != 0 \
			and _front_contributor_revisions[slot] == _required_slot_revisions[slot]


func update_anchor(anchor_stripe: int) -> void:
	if anchor_stripe == _applied_anchor_stripe:
		return
	_applied_anchor_stripe = anchor_stripe
	if _depth_ladder == null or not is_instance_valid(_depth_ladder):
		return
	_depth_ladder.set_world_origin_y(position.y)
	_depth_ladder.update_anchor(anchor_stripe)


func get_debug_state() -> Dictionary:
	var directional_draws: int = 1 if _directional_shadow_layer != null \
			and _directional_shadow_layer.visible else 0
	var contact_draws: int = 1 if _contact_shadow_layer != null \
			and _contact_shadow_layer.visible else 0
	var spore_draws: int = 1 if _spore_layer != null and _spore_layer.visible else 0
	return {
		"page_coord": page_coord,
		"page_origin": position,
		"page_revision": _front_page_revision,
		"contributor_mask": _front_contributor_mask,
		"contributor_revisions": _front_contributor_revisions.duplicate(),
		"active_slot_mask": _active_slot_mask,
		"visible_slot_mask": _visible_slot_mask,
		"required_slot_revisions": _required_slot_revisions.duplicate(),
		"pending": has_pending_upload(),
		"staged_page_revision": _staged_page_revision,
		"upload_phase": UploadPhase.keys()[_upload_phase],
		"upload_stripe": _upload_stripe,
		"instance_count": _front_instance_count,
		"albedo_draw_layer_count": _front_albedo_draw_layer_count \
				if _visible_slot_mask != 0 else 0,
		"directional_shadow_draw_layer_count": directional_draws,
		"contact_shadow_draw_layer_count": contact_draws,
		"spore_draw_layer_count": spore_draws,
		"grass_and_directional_shadow_draw_layer_count": \
				(_front_albedo_draw_layer_count if _visible_slot_mask != 0 else 0) \
				+ directional_draws,
		"total_draw_layer_count": \
				(_front_albedo_draw_layer_count if _visible_slot_mask != 0 else 0) \
				+ directional_draws + contact_draws + spore_draws,
		"raw_multimesh_upload_count_total": _resources.raw_upload_count_total,
		"commit_count_total": _commit_count_total,
		"stale_result_reject_count_total": _stale_result_reject_count_total,
		"graph_visibility_sync_count_total": _graph_visibility_sync_count_total,
		"canvas_item_allocation_count_total": _canvas_item_allocation_count_total,
		"last_callback_canvas_item_allocation_count": \
				_last_callback_canvas_item_allocation_count,
		"last_callback_multimesh_allocation_count": \
				_resources.last_callback_multimesh_allocation_count,
		"last_callback_raw_upload_count": _resources.last_callback_raw_upload_count,
		"allocated_albedo_layer_count": _allocated_albedo_layer_count(),
		"allocated_fixed_layer_count": _allocated_fixed_layer_count(),
		"configured": _configured,
		"shell_canvas_item_count": get_shell_canvas_item_count(),
		"max_stripe_multimesh_resource_count": _resources.max_stripe_resource_count(),
		"depth_ladder": _depth_ladder.get_debug_state() \
				if _depth_ladder != null and is_instance_valid(_depth_ladder) else { },
	}


## Releases all front/back GPU buffers and pending result handles while keeping
## the fixed CanvasItem/material graph available for page-pool reuse.
func clear() -> void:
	_configured = false
	_cancel_pending_upload(false)
	for stripe_index: int in range(_albedo_layers.size()):
		var layer: MultiMeshInstance2D = _albedo_layers[stripe_index]
		if layer != null and is_instance_valid(layer):
			layer.multimesh = null
			layer.visible = false
	_clear_fixed_layer(_directional_shadow_layer)
	_clear_fixed_layer(_contact_shadow_layer)
	_clear_fixed_layer(_spore_layer)
	_resources.reset_all()
	_front_page_revision = -1
	_front_contributor_mask = 0
	_front_contributor_revisions.fill(0)
	_active_slot_mask = 0
	_visible_slot_mask = 0
	_required_slot_revisions.fill(0)
	_front_instance_count = 0
	_front_albedo_draw_layer_count = 0
	_commit_count_total = 0
	_stale_result_reject_count_total = 0
	_graph_visibility_sync_count_total = 0
	_canvas_item_allocation_count_total = 0
	_last_callback_canvas_item_allocation_count = 0
	_refresh_page_material_params()


func _resize_fixed_state() -> void:
	_albedo_layers.resize(STRIPE_COUNT)
	_front_contributor_revisions.resize(PAGE_SLOT_COUNT)
	_staged_contributor_revisions.resize(PAGE_SLOT_COUNT)
	_required_slot_revisions.resize(PAGE_SLOT_COUNT)
	_albedo_layers.fill(null)
	_front_contributor_revisions.fill(0)
	_staged_contributor_revisions.fill(0)
	_required_slot_revisions.fill(0)


func _ensure_page_shell() -> void:
	if _depth_ladder == null or not is_instance_valid(_depth_ladder):
		_depth_ladder = DepthLadderBandRoot.new()
		_depth_ladder.name = "GrassPageDepthLadder"
		add_child(_depth_ladder)
	_depth_ladder.prepare_presentation_envelope()


func _allocate_albedo_layer(stripe_index: int) -> MultiMeshInstance2D:
	var layer: MultiMeshInstance2D = _albedo_layers[stripe_index]
	if layer != null and is_instance_valid(layer):
		return layer
	layer = MultiMeshInstance2D.new()
	layer.name = "GrassPageStripe%d" % stripe_index
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.texture = _grass_atlas
	layer.material = _albedo_material
	layer.visible = false
	_albedo_layers[stripe_index] = layer
	_depth_ladder.register_item(layer, stripe_index, 0)
	_canvas_item_allocation_count_total += 1
	_last_callback_canvas_item_allocation_count += 1
	return layer


func _ensure_fixed_layer(
		current: MultiMeshInstance2D,
		layer_name: String,
		z_value: int,
) -> MultiMeshInstance2D:
	var layer: MultiMeshInstance2D = current
	if layer == null or not is_instance_valid(layer):
		layer = MultiMeshInstance2D.new()
		layer.name = layer_name
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		layer.visible = false
		add_child(layer)
		_canvas_item_allocation_count_total += 1
		_last_callback_canvas_item_allocation_count += 1
	layer.z_as_relative = false
	layer.z_index = z_value
	return layer


func _apply_sources_to_graph() -> void:
	for layer: MultiMeshInstance2D in _albedo_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		layer.texture = _grass_atlas
		layer.material = _albedo_material
	if _directional_shadow_layer != null and is_instance_valid(_directional_shadow_layer):
		_directional_shadow_layer.texture = _directional_shadow_atlas
		_directional_shadow_layer.material = _directional_shadow_material
	if _contact_shadow_layer != null and is_instance_valid(_contact_shadow_layer):
		_contact_shadow_layer.texture = _unit_texture()
		_contact_shadow_layer.material = _contact_shadow_material
	if _spore_layer != null and is_instance_valid(_spore_layer):
		_spore_layer.texture = _unit_texture()
		_spore_layer.material = _spore_material


func _make_page_material(source: ShaderMaterial) -> ShaderMaterial:
	if source == null:
		return null
	var clone: ShaderMaterial = source.duplicate(false) as ShaderMaterial
	_apply_page_params_to_material(clone)
	return clone


func _apply_page_params_to_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("page_slot_mask", _visible_slot_mask)
	material.set_shader_parameter("page_origin_x", float(page_coord.x * PAGE_WIDTH_PX))
	material.set_shader_parameter("page_slot_width_px", float(CHUNK_SIZE_PX))


func _refresh_page_material_params() -> void:
	_apply_page_params_to_material(_albedo_material)
	_apply_page_params_to_material(_directional_shadow_material)
	_apply_page_params_to_material(_contact_shadow_material)
	_apply_page_params_to_material(_spore_material)


func _refresh_page_material_slot_masks() -> void:
	for material: ShaderMaterial in [
		_albedo_material,
		_directional_shadow_material,
		_contact_shadow_material,
		_spore_material,
	]:
		if material != null:
			material.set_shader_parameter("page_slot_mask", _visible_slot_mask)


func _result_is_valid(result: Dictionary) -> bool:
	if result.has("error"):
		push_error(
			"GrassRenderPage: native page build failed: %s" % str(result.get("error")),
		)
		return false
	if (result.get("page_coord", Vector2i(1 << 20, 1 << 20)) as Vector2i) != page_coord:
		push_error("GrassRenderPage: native result targets another page")
		return false
	if int(result.get("page_revision", -1)) < 0:
		push_error("GrassRenderPage: page revision is invalid")
		return false
	var contributor_mask: int = int(result.get("contributor_mask", -1))
	if contributor_mask < 0 or (contributor_mask & ~((1 << PAGE_SLOT_COUNT) - 1)) != 0:
		push_error("GrassRenderPage: contributor mask exceeds the 4-slot page")
		return false
	var revisions: PackedInt64Array = result.get(
		"contributor_revisions",
		PackedInt64Array(),
	) as PackedInt64Array
	if revisions.size() != PAGE_SLOT_COUNT:
		push_error("GrassRenderPage: native contributor revision vector must contain 4 entries")
		return false
	var buckets: Array = result.get("bucket_buffers", []) as Array
	if buckets.size() != STRIPE_COUNT:
		push_error("GrassRenderPage: native result must contain 64 exact depth stripes")
		return false
	for buffer_variant: Variant in buckets:
		if not (buffer_variant is PackedFloat32Array) \
				or (buffer_variant as PackedFloat32Array).size() % BUFFER_STRIDE != 0:
			push_error("GrassRenderPage: albedo buffer violates raw MultiMesh stride")
			return false
	for field_name: StringName in [
		&"directional_shadow_buffer",
		&"shadow_buffer",
		&"spore_buffer",
	]:
		var buffer_variant: Variant = result.get(field_name, PackedFloat32Array())
		if not (buffer_variant is PackedFloat32Array) \
				or (buffer_variant as PackedFloat32Array).size() % BUFFER_STRIDE != 0:
			push_error("GrassRenderPage: %s violates raw MultiMesh stride" % field_name)
			return false
	if _uses_directional_shadow_atlas:
		if not (result.get(
			"directional_shadow_buffer",
			PackedFloat32Array(),
		) as PackedFloat32Array).is_empty() and _directional_shadow_material == null:
			return false
	elif not (result.get("shadow_buffer", PackedFloat32Array()) \
			as PackedFloat32Array).is_empty() and _contact_shadow_material == null:
		push_error("GrassRenderPage: contact-shadow payload has no material")
		return false
	if not (result.get("spore_buffer", PackedFloat32Array()) \
			as PackedFloat32Array).is_empty() and _spore_material == null:
		push_error("GrassRenderPage: spore payload has no material")
		return false
	return true


func _stripe_candidate_requires_allocation(stripe_index: int, count: int) -> bool:
	var layer: MultiMeshInstance2D = _albedo_layers[stripe_index]
	return layer == null or not is_instance_valid(layer) \
			or _resources.stripe_candidate_requires_allocation(stripe_index, count)


func _allocate_stripe_candidate(stripe_index: int, count: int) -> void:
	_allocate_albedo_layer(stripe_index)
	_resources.allocate_stripe_candidate(stripe_index, count)


func _fixed_candidate_requires_allocation(
		layer: MultiMeshInstance2D,
		pass_index: int,
		count: int,
) -> bool:
	return layer == null or not is_instance_valid(layer) \
			or _resources.fixed_candidate_requires_allocation(pass_index, count)


func _allocate_directional_candidate(count: int) -> void:
	_directional_shadow_layer = _ensure_fixed_layer(
		_directional_shadow_layer,
		"GrassPageDirectionalShadow",
		WorldRuntimeConstants.Z_GRASS_SHADOW + 1,
	)
	_directional_shadow_layer.texture = _directional_shadow_atlas
	_directional_shadow_layer.material = _directional_shadow_material
	_resources.allocate_fixed_candidate(
		GrassRenderPageResourceSet.FixedPass.DIRECTIONAL_SHADOW,
		count,
	)


func _allocate_contact_candidate(count: int) -> void:
	_contact_shadow_layer = _ensure_fixed_layer(
		_contact_shadow_layer,
		"GrassPageContactShadow",
		WorldRuntimeConstants.Z_GRASS_SHADOW,
	)
	_contact_shadow_layer.texture = _unit_texture()
	_contact_shadow_layer.material = _contact_shadow_material
	_resources.allocate_fixed_candidate(
		GrassRenderPageResourceSet.FixedPass.CONTACT_SHADOW,
		count,
	)


func _allocate_spore_candidate(count: int) -> void:
	_spore_layer = _ensure_fixed_layer(
		_spore_layer,
		"GrassPageSpores",
		WorldRuntimeConstants.Z_GRASS_SPORE,
	)
	_spore_layer.texture = _unit_texture()
	_spore_layer.material = _spore_material
	_resources.allocate_fixed_candidate(
		GrassRenderPageResourceSet.FixedPass.SPORES,
		count,
	)


func _commit_staged_result() -> void:
	_resources.commit(_uses_directional_shadow_atlas)
	_front_instance_count = 0
	_front_albedo_draw_layer_count = 0
	for stripe_index: int in range(STRIPE_COUNT):
		var next_front: MultiMesh = _resources.front_stripe(stripe_index)
		var count: int = _resources.front_stripe_count(stripe_index)
		var layer: MultiMeshInstance2D = _albedo_layers[stripe_index]
		if layer != null and is_instance_valid(layer):
			layer.multimesh = next_front
		if count > 0:
			_front_instance_count += count
			_front_albedo_draw_layer_count += 1

	if _directional_shadow_layer != null and is_instance_valid(_directional_shadow_layer):
		_directional_shadow_layer.multimesh = _resources.front_fixed(
			GrassRenderPageResourceSet.FixedPass.DIRECTIONAL_SHADOW,
		)

	if _contact_shadow_layer != null and is_instance_valid(_contact_shadow_layer):
		_contact_shadow_layer.multimesh = _resources.front_fixed(
			GrassRenderPageResourceSet.FixedPass.CONTACT_SHADOW,
		)

	if _spore_layer != null and is_instance_valid(_spore_layer):
		_spore_layer.multimesh = _resources.front_fixed(
			GrassRenderPageResourceSet.FixedPass.SPORES,
		)

	_front_page_revision = _staged_page_revision
	_front_contributor_mask = _staged_contributor_mask
	_front_contributor_revisions = _staged_contributor_revisions.duplicate()
	_commit_count_total += 1
	_cancel_pending_upload(true)
	_refresh_visible_slot_mask(true)


func _cancel_pending_upload(keep_committed_revision: bool) -> void:
	_staged_result.clear()
	_staged_bucket_buffers.clear()
	_staged_directional_buffer = PackedFloat32Array()
	_staged_contact_buffer = PackedFloat32Array()
	_staged_spore_buffer = PackedFloat32Array()
	_resources.cancel_staging()
	_upload_phase = UploadPhase.IDLE
	_upload_stripe = 0
	if not keep_committed_revision:
		_staged_page_revision = -1
		_staged_contributor_mask = 0
		_staged_contributor_revisions.fill(0)


func _refresh_visible_slot_mask(force_graph_sync: bool = false) -> void:
	var was_page_visible: bool = _visible_slot_mask != 0
	var next_mask: int = 0
	for slot: int in range(PAGE_SLOT_COUNT):
		var bit: int = 1 << slot
		if (_active_slot_mask & bit) == 0 or (_front_contributor_mask & bit) == 0:
			continue
		if _front_contributor_revisions[slot] == _required_slot_revisions[slot]:
			next_mask |= bit
	_visible_slot_mask = next_mask
	_refresh_page_material_slot_masks()
	if force_graph_sync or was_page_visible != (_visible_slot_mask != 0):
		_sync_graph_visibility()


## The common active-slot update only changes four page-local material
## uniforms. Touching 64 CanvasItems is reserved for a page visibility edge or
## an atomic commit that changed the front resource/count graph.
func _sync_graph_visibility() -> void:
	_graph_visibility_sync_count_total += 1
	var page_has_visible_slots: bool = _visible_slot_mask != 0
	for stripe_index: int in range(_albedo_layers.size()):
		var layer: MultiMeshInstance2D = _albedo_layers[stripe_index]
		if layer != null and is_instance_valid(layer):
			layer.visible = page_has_visible_slots \
					and _resources.front_stripe_count(stripe_index) > 0
	if _directional_shadow_layer != null:
		_directional_shadow_layer.visible = page_has_visible_slots \
				and _uses_directional_shadow_atlas \
				and _resources.front_fixed_count(
					GrassRenderPageResourceSet.FixedPass.DIRECTIONAL_SHADOW,
				) > 0
	if _contact_shadow_layer != null:
		_contact_shadow_layer.visible = page_has_visible_slots \
				and not _uses_directional_shadow_atlas \
				and _resources.front_fixed_count(
					GrassRenderPageResourceSet.FixedPass.CONTACT_SHADOW,
				) > 0
	if _spore_layer != null:
		_spore_layer.visible = page_has_visible_slots \
				and _resources.front_fixed_count(
					GrassRenderPageResourceSet.FixedPass.SPORES,
				) > 0


func _allocated_albedo_layer_count() -> int:
	var result: int = 0
	for layer: MultiMeshInstance2D in _albedo_layers:
		if layer != null and is_instance_valid(layer):
			result += 1
	return result


func _allocated_fixed_layer_count() -> int:
	var result: int = 0
	for layer: MultiMeshInstance2D in [
		_directional_shadow_layer,
		_contact_shadow_layer,
		_spore_layer,
	]:
		if layer != null and is_instance_valid(layer):
			result += 1
	return result


static func _clear_fixed_layer(layer: MultiMeshInstance2D) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.multimesh = null
	layer.visible = false


static func _unit_texture() -> Texture2D:
	if _shared_unit_texture != null:
		return _shared_unit_texture
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_shared_unit_texture = ImageTexture.create_from_image(image)
	return _shared_unit_texture
