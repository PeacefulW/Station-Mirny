class_name LayeredTreeBatchLayer
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const AssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")
const DepthLadderBandRoot = preload("res://core/systems/world/depth_ladder_band_root.gd")

const RESULT_KEY: StringName = &"tree_atlas_bucket_buffers"
const MULTIMESH_BUFFER_STRIDE: int = 12
const STRIPE_COUNT: int = WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK
const LADDER_ANCHOR_UNSET: int = 1 << 30

var _catalog: AssetCatalog = null
var _slots: Array[Dictionary] = []
var _staged_buffers: Array[PackedFloat32Array] = []
var _next_stripe: int = 0
var _active_slot_count: int = 0
var _instance_count: int = 0
var _world_origin_y: float = 0.0
var _applied_anchor_stripe: int = LADDER_ANCHOR_UNSET
var _season_amount: float = 0.0
var _sun_shadow_length_px: float = 0.0
var _sun_shadow_opacity: float = 0.0
var _has_pending_apply: bool = false
var _depth_ladder: DepthLadderBandRoot = null
var _raw_multimesh_upload_count_total: int = 0
var _resident_instance_count: int = 0
var _resident_slot_count: int = 0
var _retire_cursor: int = 0
var _retire_end: int = 0
var _retire_keep_slot_count: int = 0
var _has_pending_retire: bool = false
var _last_slice_created_slot: bool = false


func configure_catalog(catalog: AssetCatalog) -> void:
	if catalog == null or not catalog.is_ready():
		push_error("LayeredTreeBatchLayer: a boot-prepared asset catalog is required")
		return
	_catalog = catalog
	# Catalog/WorldStreamer is the single writer for shared shader materials.
	# A newly allocated or pooled chunk layer only adopts the current global state.
	_season_amount = _catalog.get_season_amount()
	_sun_shadow_length_px = _catalog.get_sun_shadow_length_px()
	_sun_shadow_opacity = _catalog.get_sun_shadow_opacity()


func begin_apply(native_result: Dictionary) -> bool:
	if _catalog == null or not _catalog.is_ready():
		push_error("LayeredTreeBatchLayer: configure_catalog() must run before chunk publish")
		return false
	var buffers: Array[PackedFloat32Array] = _validated_buffers(native_result.get(RESULT_KEY, null))
	if buffers.size() != STRIPE_COUNT:
		clear_batches()
		return false
	# One parent visibility write gates the complete previous batch. Individual
	# slot buffers are overwritten/retired in bounded slices below.
	visible = false
	_staged_buffers = buffers
	_next_stripe = 0
	_active_slot_count = 0
	_instance_count = 0
	_has_pending_apply = true
	_has_pending_retire = false
	return true


## Boot/pool warm-up owns the first RenderingServer allocation outside the
## streaming deadline. One slot is enough to compile the resource path; later
## packet slices still grow the bounded 64-stripe pool one slot at a time.
func reserve_pool_slots(slot_count: int) -> void:
	if _catalog == null or not _catalog.is_ready():
		return
	prepare_presentation_envelope_fixed_graph()
	for slot_index: int in range(clampi(slot_count, 0, STRIPE_COUNT)):
		_ensure_slot(slot_index)
	_hide_all_slots()
	visible = false


func prepare_presentation_envelope_fixed_graph() -> void:
	_ensure_depth_ladder().prepare_presentation_envelope()
	visible = false


func is_presentation_envelope_fixed_graph_ready() -> bool:
	return _depth_ladder != null \
			and is_instance_valid(_depth_ladder) \
			and _depth_ladder.is_presentation_envelope_ready()


## Applies at most max_stripes non-empty native buffers. Empty buckets are only
## a fixed 64-entry lookup table and are skipped in the same slice; counting
## them as uploads would turn sparse chunks into an artificial multi-frame
## queue with no useful work.
func apply_next_batch(max_stripes: int) -> bool:
	_last_slice_created_slot = false
	if not _has_pending_apply:
		return false
	var stripe_budget: int = maxi(max_stripes, 1)
	var applied_stripes: int = 0
	while _next_stripe < STRIPE_COUNT and applied_stripes < stripe_budget:
		var buffer: PackedFloat32Array = _staged_buffers[_next_stripe]
		var stripe_index: int = _next_stripe
		if not buffer.is_empty():
			if _active_slot_count >= _slots.size():
				if applied_stripes > 0:
					return true
				_ensure_slot(_active_slot_count)
				_last_slice_created_slot = true
				return true
			var slot: Dictionary = _ensure_slot(_active_slot_count)
			_sync_slot(slot, stripe_index, buffer)
			_active_slot_count += 1
			_instance_count += buffer.size() / MULTIMESH_BUFFER_STRIDE
			applied_stripes += 1
		_next_stripe += 1
	if _next_stripe < STRIPE_COUNT:
		return true
	_staged_buffers.clear()
	_has_pending_apply = false
	_begin_retire_inactive_slots(_active_slot_count)
	return false


func next_batch_requires_slot_allocation() -> bool:
	if not _has_pending_apply:
		return false
	for stripe_index: int in range(_next_stripe, STRIPE_COUNT):
		if not _staged_buffers[stripe_index].is_empty():
			return _active_slot_count >= _slots.size()
	return false


func did_last_slice_create_slot() -> bool:
	return _last_slice_created_slot


func cancel_pending_apply() -> void:
	_staged_buffers.clear()
	_has_pending_apply = false
	_next_stripe = 0
	_active_slot_count = 0
	_instance_count = 0
	visible = false
	_begin_retire_inactive_slots(0)


func has_pending_retire() -> bool:
	return _has_pending_retire


## Releases at most max_slots resident slot groups. One tree slot owns two raw
## MultiMesh buffers (visual channels share one; shadow owns the other).
func retire_next_batch(max_slots: int) -> bool:
	if not _has_pending_retire:
		return false
	var end_cursor: int = mini(_retire_cursor + maxi(1, max_slots), _retire_end)
	while _retire_cursor < end_cursor:
		_reset_slot(_slots[_retire_cursor])
		_retire_cursor += 1
	if _retire_cursor >= _retire_end:
		_resident_slot_count = mini(_retire_keep_slot_count, _slots.size())
		_has_pending_retire = false
	return _has_pending_retire


## Commit is O(1): uploaded active children were prepared while this family
## root was hidden, and every stale child was retired before this call.
func commit_staged_slots() -> void:
	visible = _active_slot_count > 0


## Pool-overflow destruction removes one already-empty slot group per call.
func shrink_pool_next_slot() -> bool:
	if _has_pending_apply or _has_pending_retire or _slots.is_empty():
		return false
	var slot: Dictionary = _slots.pop_back() as Dictionary
	for key: StringName in [&"trunk", &"foliage", &"snow", &"shadow"]:
		var layer: MultiMeshInstance2D = slot.get(key) as MultiMeshInstance2D
		if layer == null or not is_instance_valid(layer):
			continue
		if _depth_ladder != null and is_instance_valid(_depth_ladder):
			_depth_ladder.unregister_item(layer)
		layer.free()
	_resident_slot_count = mini(_resident_slot_count, _slots.size())
	return true


func clear_batches() -> void:
	cancel_pending_apply()


func set_world_origin_y(world_origin_y: float) -> void:
	_world_origin_y = world_origin_y
	_ensure_depth_ladder().set_world_origin_y(_world_origin_y)


func update_ladder_z(anchor_stripe: int) -> void:
	_applied_anchor_stripe = anchor_stripe
	_ensure_depth_ladder().update_anchor(anchor_stripe)


func set_season_amount(season_amount: float) -> void:
	_season_amount = clampf(season_amount, 0.0, 1.0)
	for slot_index: int in range(_active_slot_count):
		var snow: MultiMeshInstance2D = _slots[slot_index].get("snow") as MultiMeshInstance2D
		if snow != null:
			snow.visible = visible and _season_amount > 0.01


func set_sun_lighting(
		_light_angle_deg: float,
		shadow_length_px: float,
		shadow_opacity: float,
		_shadow_softness_px: float,
) -> void:
	# Shared materials already contain the catalog owner's values. Retain only
	# chunk-local state for diagnostics/future local visibility policy.
	_sun_shadow_length_px = shadow_length_px
	_sun_shadow_opacity = shadow_opacity


func get_debug_state() -> Dictionary:
	var depth_ladder_state: Dictionary = { }
	if _depth_ladder != null and is_instance_valid(_depth_ladder):
		depth_ladder_state = _depth_ladder.get_debug_state()
	return {
		"ready": _catalog != null and _catalog.is_ready(),
		"uses_multimesh": true,
		"uses_channel_atlas": true,
		"season_amount": _season_amount,
		"sun_shadow_length_px": _sun_shadow_length_px,
		"sun_shadow_opacity": _sun_shadow_opacity,
		"instance_count": _instance_count,
		"active_stripe_count": _active_slot_count,
		"pooled_slot_count": _slots.size(),
		"has_pending_apply": _has_pending_apply,
		"raw_multimesh_upload_count_total": _raw_multimesh_upload_count_total,
		"resident_instance_count": _resident_instance_count,
		"resident_slot_count": _resident_slot_count,
		"has_pending_retire": _has_pending_retire,
		"last_slice_created_slot": _last_slice_created_slot,
		"retire_remaining_slot_count": maxi(0, _retire_end - _retire_cursor),
		"next_stripe": _next_stripe,
		"depth_ladder": depth_ladder_state,
		"canvas_item_count": 1 + _slots.size() * 4 \
				+ int(depth_ladder_state.get("canvas_item_count", 0)),
	}


func _validated_buffers(value: Variant) -> Array[PackedFloat32Array]:
	var result: Array[PackedFloat32Array] = []
	if not value is Array:
		push_error("LayeredTreeBatchLayer: missing %s" % RESULT_KEY)
		return result
	var source: Array = value as Array
	if source.size() != STRIPE_COUNT:
		push_error("LayeredTreeBatchLayer: %s must contain %d stripes" % [RESULT_KEY, STRIPE_COUNT])
		return result
	for stripe_index: int in range(STRIPE_COUNT):
		if not source[stripe_index] is PackedFloat32Array:
			push_error("LayeredTreeBatchLayer: stripe %d has an invalid buffer" % stripe_index)
			return []
		var buffer: PackedFloat32Array = source[stripe_index] as PackedFloat32Array
		if buffer.size() % MULTIMESH_BUFFER_STRIDE != 0:
			push_error("LayeredTreeBatchLayer: stripe %d violates raw MultiMesh stride" % stripe_index)
			return []
		result.append(buffer)
	return result


func _ensure_slot(slot_index: int) -> Dictionary:
	while _slots.size() <= slot_index:
		_slots.append(_create_slot(_slots.size()))
	return _slots[slot_index]


func _create_slot(slot_index: int) -> Dictionary:
	var allocation_started_usec: int = WorldPerfProbe.begin()
	var visual_multimesh: MultiMesh = _make_multimesh(_catalog.get_unit_quad_mesh())
	var shadow_multimesh: MultiMesh = _make_multimesh(_catalog.get_shadow_mesh())
	var trunk: MultiMeshInstance2D = _make_layer(
		"TreeBatch%dTrunk" % slot_index,
		AssetCatalog.TREE_TRUNK_ATLAS,
		_catalog.get_tree_trunk_material(),
		visual_multimesh,
	)
	var foliage: MultiMeshInstance2D = _make_layer(
		"TreeBatch%dFoliage" % slot_index,
		AssetCatalog.TREE_FOLIAGE_ATLAS,
		_catalog.get_tree_foliage_material(),
		visual_multimesh,
	)
	var snow: MultiMeshInstance2D = _make_layer(
		"TreeBatch%dSnow" % slot_index,
		AssetCatalog.TREE_SNOW_OVERLAY_ATLAS,
		_catalog.get_tree_snow_material(),
		visual_multimesh,
	)
	var shadow: MultiMeshInstance2D = _make_layer(
		"TreeBatch%dShadow" % slot_index,
		AssetCatalog.TREE_SHADOW_ATLAS,
		_catalog.get_tree_shadow_material(),
		shadow_multimesh,
	)
	var slot: Dictionary = {
		"stripe": -1,
		"instance_count": 0,
		"visual_multimesh": visual_multimesh,
		"shadow_multimesh": shadow_multimesh,
		"trunk": trunk,
		"foliage": foliage,
		"snow": snow,
		"shadow": shadow,
	}
	WorldPerfProbe.end(
		"WorldObjectPacketLayer.tree.slot_allocate",
		allocation_started_usec,
	)
	return slot


func _make_layer(
		layer_name: String,
		texture: Texture2D,
		material: Material,
		multimesh: MultiMesh,
) -> MultiMeshInstance2D:
	var layer := MultiMeshInstance2D.new()
	layer.name = layer_name
	layer.texture = texture
	layer.material = material
	layer.multimesh = multimesh
	# Authored 2D atlases stay lossless and intentionally have no mip chain.
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.visible = false
	add_child(layer)
	return layer


func _make_multimesh(mesh: Mesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	return multimesh


func _sync_slot(slot: Dictionary, stripe_index: int, buffer: PackedFloat32Array) -> void:
	var count: int = buffer.size() / MULTIMESH_BUFFER_STRIDE
	var previous_count: int = int(slot.get("instance_count", 0))
	_resident_instance_count = maxi(0, _resident_instance_count - previous_count + count)
	var visual_multimesh: MultiMesh = slot.get("visual_multimesh") as MultiMesh
	var shadow_multimesh: MultiMesh = slot.get("shadow_multimesh") as MultiMesh
	var visual_upload_started_usec: int = WorldPerfProbe.begin()
	_apply_raw_buffer(visual_multimesh, count, buffer)
	WorldPerfProbe.end(
		"WorldObjectPacketLayer.tree.raw_visual_upload",
		visual_upload_started_usec,
	)
	var shadow_upload_started_usec: int = WorldPerfProbe.begin()
	_apply_raw_buffer(shadow_multimesh, count, buffer)
	WorldPerfProbe.end(
		"WorldObjectPacketLayer.tree.raw_shadow_upload",
		shadow_upload_started_usec,
	)
	_raw_multimesh_upload_count_total += 2
	slot["stripe"] = stripe_index
	slot["instance_count"] = count
	_resident_slot_count = maxi(_resident_slot_count, _active_slot_count + 1)
	var depth_ladder: DepthLadderBandRoot = _ensure_depth_ladder()
	var ladder_started_usec: int = WorldPerfProbe.begin()
	depth_ladder.register_item(slot.get("trunk") as MultiMeshInstance2D, stripe_index, 1)
	depth_ladder.register_item(slot.get("foliage") as MultiMeshInstance2D, stripe_index, 2)
	depth_ladder.register_item(slot.get("snow") as MultiMeshInstance2D, stripe_index, 3)
	# Cast shadows own one fixed layer above the complete ladder; rebasing them
	# with the tree feet would change their visual contract.
	(slot.get("shadow") as MultiMeshInstance2D).z_index = WorldRuntimeConstants.Z_CAST_SHADOW
	WorldPerfProbe.end("WorldObjectPacketLayer.tree.ladder_register", ladder_started_usec)
	(slot.get("trunk") as MultiMeshInstance2D).visible = true
	(slot.get("foliage") as MultiMeshInstance2D).visible = true
	(slot.get("snow") as MultiMeshInstance2D).visible = _season_amount > 0.01
	(slot.get("shadow") as MultiMeshInstance2D).visible = true


func _apply_raw_buffer(multimesh: MultiMesh, count: int, buffer: PackedFloat32Array) -> void:
	multimesh.instance_count = count
	multimesh.visible_instance_count = count
	multimesh.buffer = buffer


func _hide_all_slots() -> void:
	for slot: Dictionary in _slots:
		for key: StringName in [&"trunk", &"foliage", &"snow", &"shadow"]:
			var layer: MultiMeshInstance2D = slot.get(key) as MultiMeshInstance2D
			if layer != null:
				layer.visible = false
	if _depth_ladder != null and is_instance_valid(_depth_ladder):
		_depth_ladder.clear_registered_items()


func _reset_slot(slot: Dictionary) -> void:
	for key: StringName in [&"trunk", &"foliage", &"snow", &"shadow"]:
		var layer: MultiMeshInstance2D = slot.get(key) as MultiMeshInstance2D
		if layer != null:
			layer.visible = false
			if _depth_ladder != null and is_instance_valid(_depth_ladder):
				_depth_ladder.unregister_item(layer)
	var visual_multimesh: MultiMesh = slot.get("visual_multimesh") as MultiMesh
	var shadow_multimesh: MultiMesh = slot.get("shadow_multimesh") as MultiMesh
	var previous_count: int = int(slot.get("instance_count", 0))
	_resident_instance_count = maxi(0, _resident_instance_count - previous_count)
	_reset_multimesh(visual_multimesh)
	_reset_multimesh(shadow_multimesh)
	slot["stripe"] = -1
	slot["instance_count"] = 0


func _begin_retire_inactive_slots(keep_slot_count: int) -> void:
	_retire_keep_slot_count = clampi(keep_slot_count, 0, _resident_slot_count)
	_retire_cursor = _retire_keep_slot_count
	_retire_end = _resident_slot_count
	_has_pending_retire = _retire_cursor < _retire_end
	if not _has_pending_retire:
		_resident_slot_count = _retire_keep_slot_count


static func _reset_multimesh(multimesh: MultiMesh) -> void:
	if multimesh == null:
		return
	multimesh.visible_instance_count = 0
	multimesh.instance_count = 0


func _ensure_depth_ladder() -> DepthLadderBandRoot:
	if _depth_ladder != null and is_instance_valid(_depth_ladder):
		return _depth_ladder
	_depth_ladder = DepthLadderBandRoot.new()
	_depth_ladder.name = "TreeDepthLadder"
	add_child(_depth_ladder)
	_depth_ladder.set_world_origin_y(_world_origin_y)
	if _applied_anchor_stripe != LADDER_ANCHOR_UNSET:
		_depth_ladder.update_anchor(_applied_anchor_stripe)
	return _depth_ladder
