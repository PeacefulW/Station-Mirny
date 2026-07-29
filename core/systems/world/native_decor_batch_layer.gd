class_name NativeDecorBatchLayer
extends Node2D

## Incremental consumer for worker-prepared classic decor buffers. It owns a
## bounded pool of stripe MultiMeshes, never scans the canonical object packet,
## and never calls per-instance MultiMesh setters on the main thread.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DepthLadderBandRoot = preload("res://core/systems/world/depth_ladder_band_root.gd")

const BUFFER_STRIDE: int = 12
const STRIPE_COUNT: int = WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK
const LADDER_ANCHOR_UNSET: int = 1 << 30
const CONTACT_SHADOW_Z_INDEX: int = 4

static var _shared_unit_texture: ImageTexture = null

var _atlases: Array[Texture2D] = []
var _mesh: Mesh = null
var _sprite_material: ShaderMaterial = null
var _shadow_material: ShaderMaterial = null
var _depth_ladder_root: DepthLadderBandRoot = null
var _with_shadow: bool = false
var _is_configured: bool = false

var _slots: Array[Dictionary] = []
var _active_slot_count: int = 0
var _required_slot_count: int = 0
var _shadow_layer: MultiMeshInstance2D = null
var _shadow_multimesh: MultiMesh = null
var _instance_count: int = 0
var _shadow_instance_count: int = 0

var _staged_buffers_by_atlas: Array = []
var _staged_shadow_buffer := PackedFloat32Array()
var _next_atlas: int = 0
var _next_stripe: int = 0
var _shadow_pending: bool = false
var _has_pending_apply: bool = false
var _last_slice_upload_count: int = 0
var _raw_multimesh_upload_count_total: int = 0
var _resident_instance_count: int = 0
var _resident_shadow_instance_count: int = 0
var _resident_slot_count: int = 0
var _retire_cursor: int = 0
var _retire_end: int = 0
var _retire_keep_slot_count: int = 0
var _shadow_retire_pending: bool = false
var _has_pending_retire: bool = false
var _last_slice_created_slot: bool = false

var _world_origin_y: float = 0.0
var _applied_anchor_stripe: int = LADDER_ANCHOR_UNSET


func configure(
		atlases: Array[Texture2D],
		mesh: Mesh,
		sprite_material: ShaderMaterial,
		shadow_material: ShaderMaterial = null,
) -> bool:
	if atlases.is_empty() or mesh == null or sprite_material == null:
		push_error("NativeDecorBatchLayer: prepared atlases, mesh, and shared material are required")
		return false
	for atlas: Texture2D in atlases:
		if atlas == null:
			push_error("NativeDecorBatchLayer: atlas bank contains a null texture")
			return false
	_atlases = atlases.duplicate()
	_mesh = mesh
	_sprite_material = sprite_material
	_shadow_material = shadow_material
	_with_shadow = shadow_material != null
	_ensure_depth_ladder_root()
	_is_configured = true
	return true


## Validates the complete envelope before hiding the previous committed batch.
## The outer array is atlas-major and every atlas owns exactly 64 prebucketed
## raw buffers. The optional shadow buffer is one flat raw MultiMesh payload.
func begin_apply(
		buffers_by_atlas: Array,
		shadow_buffer: PackedFloat32Array,
		expected_instance_count: int,
		expected_shadow_count: int,
) -> bool:
	if not _is_configured:
		push_error("NativeDecorBatchLayer: configure() must run before begin_apply()")
		return false
	if not _buffers_are_valid(
		buffers_by_atlas,
		expected_instance_count,
		shadow_buffer,
		expected_shadow_count,
	):
		return false
	# One parent write hides the previous committed family. Child buffers are
	# overwritten or retired later in bounded dispatcher slices.
	visible = false
	_staged_buffers_by_atlas = buffers_by_atlas.duplicate(false)
	_staged_shadow_buffer = shadow_buffer
	_next_atlas = 0
	_next_stripe = 0
	_shadow_pending = expected_shadow_count > 0
	_active_slot_count = 0
	_required_slot_count = _count_non_empty_buffers(buffers_by_atlas)
	_instance_count = 0
	_shadow_instance_count = 0
	_last_slice_upload_count = 0
	_has_pending_apply = true
	_has_pending_retire = false
	return true


## Preallocates only a bounded first stripe. The pool keeps this envelope
## hidden and later native packets reuse it without a first-use RS allocation.
func reserve_pool_slots(slot_count: int) -> void:
	if not _is_configured:
		return
	prepare_presentation_envelope_fixed_graph()
	for slot_index: int in range(clampi(slot_count, 0, STRIPE_COUNT)):
		_ensure_slot(slot_index)
	if _with_shadow:
		# The first living-flora packet must only upload its packed buffer. Create
		# the fixed shadow MultiMesh/CanvasItem and shared unit texture here.
		_ensure_shadow_layer()
		_hide_shadow()
	_hide_all_slots()
	visible = false


func prepare_presentation_envelope_fixed_graph() -> void:
	if not _is_configured:
		return
	_ensure_depth_ladder_root().prepare_presentation_envelope()
	if _with_shadow:
		_ensure_shadow_layer()
		_hide_shadow()
	visible = false


func is_presentation_envelope_fixed_graph_ready() -> bool:
	if _depth_ladder_root == null \
			or not is_instance_valid(_depth_ladder_root) \
			or not _depth_ladder_root.is_presentation_envelope_ready():
		return false
	return not _with_shadow \
			or (_shadow_layer != null and is_instance_valid(_shadow_layer))


## Uploads at most max_buffers non-empty raw buffers. Empty fixed-table entries
## are skipped in the same call, including trailing empties after the last
## upload, so sparse packets do not acquire no-op scheduler frames.
func apply_next_batch(max_buffers: int) -> bool:
	_last_slice_upload_count = 0
	_last_slice_created_slot = false
	if not _has_pending_apply:
		return false
	# Capacity reservation is deliberately separate from raw upload. This also
	# covers the defensive living-shadow path if a caller skipped fixed-graph
	# envelope preparation before begin_apply().
	if has_pending_required_slot_allocation():
		allocate_next_required_slot()
		return true
	var upload_budget: int = maxi(1, max_buffers)
	_skip_empty_sprite_buffers()
	while _next_atlas < _staged_buffers_by_atlas.size() \
			and _last_slice_upload_count < upload_budget:
		var atlas_buffers: Array = _staged_buffers_by_atlas[_next_atlas] as Array
		var buffer: PackedFloat32Array = atlas_buffers[_next_stripe] as PackedFloat32Array
		var atlas_index: int = _next_atlas
		var stripe_index: int = _next_stripe
		if _active_slot_count >= _slots.size():
			if _last_slice_upload_count > 0:
				return true
			_ensure_slot(_active_slot_count)
			_last_slice_created_slot = true
			return true
		_advance_sprite_cursor()
		_sync_sprite_slot(_active_slot_count, atlas_index, stripe_index, buffer)
		_active_slot_count += 1
		_instance_count += buffer.size() / BUFFER_STRIDE
		_last_slice_upload_count += 1
		_skip_empty_sprite_buffers()
	if _next_atlas < _staged_buffers_by_atlas.size():
		return true
	if _shadow_pending:
		if _last_slice_upload_count >= upload_budget:
			return true
		if _shadow_layer == null or not is_instance_valid(_shadow_layer):
			if _last_slice_upload_count > 0:
				return true
			_ensure_shadow_layer()
			_last_slice_created_slot = true
			return true
		_sync_shadow(_staged_shadow_buffer)
		_shadow_pending = false
		_last_slice_upload_count += 1
	_staged_buffers_by_atlas.clear()
	_staged_shadow_buffer = PackedFloat32Array()
	_has_pending_apply = false
	_required_slot_count = 0
	_begin_retire_inactive_slots(_active_slot_count, _shadow_instance_count > 0)
	return false


func has_pending_required_slot_allocation() -> bool:
	if not _has_pending_apply:
		return false
	if _slots.size() < _required_slot_count:
		return true
	return _shadow_pending \
			and (_shadow_layer == null or not is_instance_valid(_shadow_layer))


## Grows exactly one CanvasItem/MultiMesh slot and never advances the staged
## cursor. Sprite slots are reserved first; the optional shadow graph is one
## final allocation-only phase.
func allocate_next_required_slot() -> bool:
	_last_slice_created_slot = false
	if not _has_pending_apply:
		return false
	if _slots.size() < _required_slot_count:
		_ensure_slot(_slots.size())
		_last_slice_created_slot = true
		return true
	if _shadow_pending \
			and (_shadow_layer == null or not is_instance_valid(_shadow_layer)):
		_ensure_shadow_layer()
		_last_slice_created_slot = true
		return true
	return false


func next_batch_requires_slot_allocation() -> bool:
	return has_pending_required_slot_allocation()


func did_last_slice_create_slot() -> bool:
	return _last_slice_created_slot


func cancel_pending_apply() -> void:
	_staged_buffers_by_atlas.clear()
	_staged_shadow_buffer = PackedFloat32Array()
	_next_atlas = 0
	_next_stripe = 0
	_shadow_pending = false
	_has_pending_apply = false
	_last_slice_upload_count = 0
	_active_slot_count = 0
	_required_slot_count = 0
	_instance_count = 0
	_shadow_instance_count = 0
	visible = false
	_begin_retire_inactive_slots(0, false)


func has_pending_retire() -> bool:
	return _has_pending_retire


func retire_next_batch(max_slots: int) -> bool:
	if not _has_pending_retire:
		return false
	var budget: int = maxi(1, max_slots)
	while budget > 0 and _retire_cursor < _retire_end:
		_reset_slot(_slots[_retire_cursor])
		_retire_cursor += 1
		budget -= 1
	if _retire_cursor >= _retire_end:
		_resident_slot_count = mini(_retire_keep_slot_count, _slots.size())
	if budget > 0 and _shadow_retire_pending:
		_reset_shadow_multimesh()
		_shadow_retire_pending = false
	_has_pending_retire = _retire_cursor < _retire_end or _shadow_retire_pending
	return _has_pending_retire


func commit_staged_slots() -> void:
	if _shadow_layer != null and is_instance_valid(_shadow_layer):
		_shadow_layer.visible = _shadow_instance_count > 0
	visible = _active_slot_count > 0 or _shadow_instance_count > 0


func shrink_pool_next_slot() -> bool:
	if _has_pending_apply or _has_pending_retire:
		return false
	if not _slots.is_empty():
		var slot: Dictionary = _slots.pop_back() as Dictionary
		var layer: MultiMeshInstance2D = slot.get("layer") as MultiMeshInstance2D
		if layer != null and is_instance_valid(layer):
			if _depth_ladder_root != null and is_instance_valid(_depth_ladder_root):
				_depth_ladder_root.unregister_item(layer)
			layer.free()
		_resident_slot_count = mini(_resident_slot_count, _slots.size())
		return true
	if _shadow_layer != null and is_instance_valid(_shadow_layer):
		_shadow_layer.free()
		_shadow_layer = null
		_shadow_multimesh = null
		return true
	return false


func clear_batches() -> void:
	cancel_pending_apply()


func set_world_origin_y(world_origin_y: float) -> void:
	_world_origin_y = world_origin_y
	if _depth_ladder_root != null:
		_depth_ladder_root.set_world_origin_y(world_origin_y)


func update_ladder_z(anchor_stripe: int) -> void:
	_applied_anchor_stripe = anchor_stripe
	_ensure_depth_ladder_root().update_anchor(anchor_stripe)


func set_wind(wind_time: float, wind_direction: Vector2, wind_strength_px: float) -> void:
	if _sprite_material == null:
		return
	var safe_direction: Vector2 = wind_direction.normalized()
	if safe_direction == Vector2.ZERO:
		safe_direction = Vector2.RIGHT
	_sprite_material.set_shader_parameter("wind_time", wind_time)
	_sprite_material.set_shader_parameter("wind_direction", safe_direction)
	_sprite_material.set_shader_parameter("wind_strength_px", maxf(0.0, wind_strength_px))


func get_debug_state() -> Dictionary:
	var depth_ladder_state: Dictionary = { }
	if _depth_ladder_root != null:
		depth_ladder_state = _depth_ladder_root.get_debug_state()
	return {
		"ready": _is_configured,
		"uses_multimesh": true,
		"uses_worker_bucket_buffers": true,
		"instance_count": _instance_count,
		"shadow_instance_count": _shadow_instance_count,
		"active_stripe_count": _active_slot_count,
		"pooled_slot_count": _slots.size(),
		"required_slot_count": _required_slot_count,
		"has_pending_slot_allocation": has_pending_required_slot_allocation(),
		"has_pending_apply": _has_pending_apply,
		"next_atlas": _next_atlas,
		"next_stripe": _next_stripe,
		"last_slice_upload_count": _last_slice_upload_count,
		"last_slice_created_slot": _last_slice_created_slot,
		"raw_multimesh_upload_count_total": _raw_multimesh_upload_count_total,
		"resident_instance_count": _resident_instance_count,
		"resident_shadow_instance_count": _resident_shadow_instance_count,
		"resident_slot_count": _resident_slot_count,
		"has_pending_retire": _has_pending_retire,
		"retire_remaining_slot_count": maxi(0, _retire_end - _retire_cursor) \
				+ (1 if _shadow_retire_pending else 0),
		"depth_ladder": depth_ladder_state,
		"canvas_item_count": 1 + _slots.size() \
				+ int(depth_ladder_state.get("canvas_item_count", 0)) \
				+ (1 if _shadow_layer != null and is_instance_valid(_shadow_layer) else 0),
	}


func _buffers_are_valid(
		buffers_by_atlas: Array,
		expected_instance_count: int,
		shadow_buffer: PackedFloat32Array,
		expected_shadow_count: int,
) -> bool:
	if buffers_by_atlas.size() != _atlases.size():
		push_error("NativeDecorBatchLayer: atlas buffer bank count does not match textures")
		return false
	var instance_count: int = 0
	for atlas_index: int in range(buffers_by_atlas.size()):
		if not buffers_by_atlas[atlas_index] is Array:
			push_error("NativeDecorBatchLayer: atlas %d bucket table has an invalid type" % atlas_index)
			return false
		var atlas_buffers: Array = buffers_by_atlas[atlas_index] as Array
		if atlas_buffers.size() != STRIPE_COUNT:
			push_error(
				"NativeDecorBatchLayer: atlas %d must contain %d stripes" \
						% [atlas_index, STRIPE_COUNT],
			)
			return false
		for stripe_index: int in range(STRIPE_COUNT):
			if not atlas_buffers[stripe_index] is PackedFloat32Array:
				push_error(
					"NativeDecorBatchLayer: atlas %d stripe %d has an invalid buffer" \
							% [atlas_index, stripe_index],
				)
				return false
			var buffer: PackedFloat32Array = atlas_buffers[stripe_index] as PackedFloat32Array
			if buffer.size() % BUFFER_STRIDE != 0:
				push_error(
					"NativeDecorBatchLayer: atlas %d stripe %d violates raw MultiMesh stride" \
							% [atlas_index, stripe_index],
				)
				return false
			instance_count += buffer.size() / BUFFER_STRIDE
	if instance_count != expected_instance_count:
		push_error("NativeDecorBatchLayer: sprite instance total does not match metadata")
		return false
	if shadow_buffer.size() % BUFFER_STRIDE != 0 \
			or shadow_buffer.size() / BUFFER_STRIDE != expected_shadow_count:
		push_error("NativeDecorBatchLayer: shadow instance total does not match metadata")
		return false
	if not _with_shadow and expected_shadow_count > 0:
		push_error("NativeDecorBatchLayer: shadow payload supplied to a shadowless family")
		return false
	return true


static func _count_non_empty_buffers(buffers_by_atlas: Array) -> int:
	var count: int = 0
	for atlas_buffers_variant: Variant in buffers_by_atlas:
		var atlas_buffers: Array = atlas_buffers_variant as Array
		for buffer_variant: Variant in atlas_buffers:
			var buffer: PackedFloat32Array = buffer_variant as PackedFloat32Array
			if not buffer.is_empty():
				count += 1
	return count


func _skip_empty_sprite_buffers() -> void:
	while _next_atlas < _staged_buffers_by_atlas.size():
		var atlas_buffers: Array = _staged_buffers_by_atlas[_next_atlas] as Array
		while _next_stripe < STRIPE_COUNT:
			var buffer: PackedFloat32Array = atlas_buffers[_next_stripe] as PackedFloat32Array
			if not buffer.is_empty():
				return
			_next_stripe += 1
		_next_atlas += 1
		_next_stripe = 0


func _advance_sprite_cursor() -> void:
	_next_stripe += 1
	if _next_stripe >= STRIPE_COUNT:
		_next_atlas += 1
		_next_stripe = 0


func _sync_sprite_slot(
		slot_index: int,
		atlas_index: int,
		stripe_index: int,
		buffer: PackedFloat32Array,
) -> void:
	var slot: Dictionary = _ensure_slot(slot_index)
	var layer: MultiMeshInstance2D = slot.get("layer") as MultiMeshInstance2D
	var multimesh: MultiMesh = slot.get("multimesh") as MultiMesh
	var count: int = buffer.size() / BUFFER_STRIDE
	var previous_count: int = int(slot.get("instance_count", 0))
	_resident_instance_count = maxi(0, _resident_instance_count - previous_count + count)
	var upload_started_usec: int = WorldPerfProbe.begin()
	_apply_raw_buffer(multimesh, buffer)
	WorldPerfProbe.end(
		"WorldObjectPacketLayer.decor.raw_visual_upload",
		upload_started_usec,
	)
	_raw_multimesh_upload_count_total += 1
	layer.texture = _atlases[atlas_index]
	layer.material = _sprite_material
	layer.visible = true
	slot["atlas"] = atlas_index
	slot["stripe"] = stripe_index
	slot["instance_count"] = count
	_resident_slot_count = maxi(_resident_slot_count, slot_index + 1)
	var ladder_started_usec: int = WorldPerfProbe.begin()
	_ensure_depth_ladder_root().register_item(
		layer,
		stripe_index,
		WorldRuntimeConstants.DEPTH_CHANNEL_OBJECT_BASE_OFFSET,
	)
	WorldPerfProbe.end("WorldObjectPacketLayer.decor.ladder_register", ladder_started_usec)


func _ensure_slot(slot_index: int) -> Dictionary:
	while _slots.size() <= slot_index:
		var allocation_started_usec: int = WorldPerfProbe.begin()
		var multimesh: MultiMesh = _make_multimesh(_mesh)
		var layer := MultiMeshInstance2D.new()
		layer.name = "NativeDecorStripe%d" % _slots.size()
		layer.z_as_relative = true
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		layer.material = _sprite_material
		layer.multimesh = multimesh
		layer.visible = false
		add_child(layer)
		_slots.append({
			"atlas": -1,
			"stripe": -1,
			"instance_count": 0,
			"layer": layer,
			"multimesh": multimesh,
		})
		WorldPerfProbe.end(
			"WorldObjectPacketLayer.decor.slot_allocate",
			allocation_started_usec,
		)
	return _slots[slot_index]


func _sync_shadow(buffer: PackedFloat32Array) -> void:
	var layer: MultiMeshInstance2D = _ensure_shadow_layer()
	var upload_started_usec: int = WorldPerfProbe.begin()
	_apply_raw_buffer(_shadow_multimesh, buffer)
	WorldPerfProbe.end(
		"WorldObjectPacketLayer.decor.raw_shadow_upload",
		upload_started_usec,
	)
	_raw_multimesh_upload_count_total += 1
	_shadow_instance_count = buffer.size() / BUFFER_STRIDE
	_resident_shadow_instance_count = _shadow_instance_count
	layer.visible = _shadow_instance_count > 0


func _ensure_shadow_layer() -> MultiMeshInstance2D:
	if _shadow_layer != null and is_instance_valid(_shadow_layer):
		return _shadow_layer
	var allocation_started_usec: int = WorldPerfProbe.begin()
	_shadow_multimesh = _make_multimesh(_mesh)
	_shadow_layer = MultiMeshInstance2D.new()
	_shadow_layer.name = "NativeDecorShadowBatch"
	_shadow_layer.z_as_relative = true
	_shadow_layer.z_index = CONTACT_SHADOW_Z_INDEX
	_shadow_layer.texture = _get_unit_texture()
	_shadow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_shadow_layer.material = _shadow_material
	_shadow_layer.multimesh = _shadow_multimesh
	_shadow_layer.visible = false
	add_child(_shadow_layer)
	WorldPerfProbe.end(
		"WorldObjectPacketLayer.decor.shadow_slot_allocate",
		allocation_started_usec,
	)
	return _shadow_layer


func _make_multimesh(mesh: Mesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	return multimesh


static func _apply_raw_buffer(multimesh: MultiMesh, buffer: PackedFloat32Array) -> void:
	var count: int = buffer.size() / BUFFER_STRIDE
	multimesh.instance_count = count
	multimesh.visible_instance_count = count
	multimesh.buffer = buffer


func _hide_all_slots() -> void:
	for slot: Dictionary in _slots:
		var layer: MultiMeshInstance2D = slot.get("layer") as MultiMeshInstance2D
		if layer != null:
			layer.visible = false
	# A new staged transaction owns a fresh active subset. Keeping the invisible
	# previous subset registered would make anchor moves migrate dead pool slots
	# before commit. Each uploaded slot registers itself again in O(1).
	if _depth_ladder_root != null:
		_depth_ladder_root.clear_registered_items()


static func _reset_multimesh(multimesh: MultiMesh) -> void:
	if multimesh == null:
		return
	multimesh.visible_instance_count = 0
	multimesh.instance_count = 0


func _hide_shadow(release_buffer: bool = false) -> void:
	if _shadow_layer != null and is_instance_valid(_shadow_layer):
		_shadow_layer.visible = false
	if release_buffer:
		_reset_shadow_multimesh()


func _reset_slot(slot: Dictionary) -> void:
	var layer: MultiMeshInstance2D = slot.get("layer") as MultiMeshInstance2D
	if layer != null and is_instance_valid(layer):
		layer.visible = false
		if _depth_ladder_root != null and is_instance_valid(_depth_ladder_root):
			_depth_ladder_root.unregister_item(layer)
	var previous_count: int = int(slot.get("instance_count", 0))
	_resident_instance_count = maxi(0, _resident_instance_count - previous_count)
	_reset_multimesh(slot.get("multimesh") as MultiMesh)
	slot["atlas"] = -1
	slot["stripe"] = -1
	slot["instance_count"] = 0


func _reset_shadow_multimesh() -> void:
	if _shadow_layer != null and is_instance_valid(_shadow_layer):
		_shadow_layer.visible = false
	_reset_multimesh(_shadow_multimesh)
	_resident_shadow_instance_count = 0


func _begin_retire_inactive_slots(keep_slot_count: int, keep_shadow: bool) -> void:
	_retire_keep_slot_count = clampi(keep_slot_count, 0, _resident_slot_count)
	_retire_cursor = _retire_keep_slot_count
	_retire_end = _resident_slot_count
	_shadow_retire_pending = not keep_shadow and _resident_shadow_instance_count > 0
	_has_pending_retire = _retire_cursor < _retire_end or _shadow_retire_pending
	if not _has_pending_retire:
		_resident_slot_count = _retire_keep_slot_count


func _ensure_depth_ladder_root() -> DepthLadderBandRoot:
	if _depth_ladder_root != null and is_instance_valid(_depth_ladder_root):
		return _depth_ladder_root
	_depth_ladder_root = DepthLadderBandRoot.new()
	_depth_ladder_root.name = "DepthLadderBandRoot"
	add_child(_depth_ladder_root)
	_depth_ladder_root.set_world_origin_y(_world_origin_y)
	if _applied_anchor_stripe != LADDER_ANCHOR_UNSET:
		_depth_ladder_root.update_anchor(_applied_anchor_stripe)
	return _depth_ladder_root


static func _get_unit_texture() -> ImageTexture:
	if _shared_unit_texture != null:
		return _shared_unit_texture
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_shared_unit_texture = ImageTexture.create_from_image(image)
	return _shared_unit_texture
