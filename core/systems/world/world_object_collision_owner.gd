class_name WorldObjectCollisionOwner
extends Node2D
## Narrow chunk-local owner for blocking object collision.
##
## Static world pixels belong exclusively to WorldRenderWorld. This owner accepts
## only the worker-produced compact tree collision records, creates/removes shape
## owners in bounded slices, and participates in the streamer's hot-cache lifecycle.

const WorldLayeredObjectAssetCatalog = preload(
	"res://core/systems/world/world_layered_object_asset_catalog.gd"
)
const ObjectCollisionDebugLayer = preload(
	"res://core/systems/world/object_collision_debug_layer.gd"
)

const OBJECT_COLLISION_LAYER: int = 2
const COLLISION_RECORD_STRIDE: int = 4
const FLOAT_BYTES: int = 4

const PRESENTATION_PHASE_NONE: StringName = &""
const PRESENTATION_PHASE_TREE_COLLISIONS: StringName = &"tree_collisions"
const PRESENTATION_PHASE_RETIRE: StringName = &"retire"
const PRESENTATION_PHASE_COMMIT: StringName = &"commit"


enum BeginState {
	IDLE,
	HEADER,
	COMPLETE,
	FAILED,
}


enum ApplyState {
	IDLE,
	RESET_PREVIOUS_COLLISIONS,
	TREE_COLLISIONS,
	COMMIT,
	COMPLETE,
}


var _collision_body: StaticBody2D = null
var _collision_shape_owner_ids: Array[int] = []
var _collision_records: PackedFloat32Array = PackedFloat32Array()
var _collision_record_index: int = 0
var _tree_count: int = 0
var _blocking_ready: bool = false
var _complete: bool = false
var _begin_state: BeginState = BeginState.IDLE
var _begin_result: Dictionary = { }
var _apply_state: ApplyState = ApplyState.IDLE
var _asset_catalog: WorldLayeredObjectAssetCatalog = null
var _debug_layer: ObjectCollisionDebugLayer = null
var _debug_visible: bool = false
var _debug_rects: Array[Rect2] = []
var _streaming_world_parented: bool = false
var _hot_cache_resident: bool = false


func prepare_presentation_envelope(
		catalog: WorldLayeredObjectAssetCatalog,
		_initial_slots_per_family: int = 1,
) -> bool:
	if catalog == null or not catalog.is_ready():
		return false
	_asset_catalog = catalog
	_ensure_collision_body().collision_layer = 0
	visible = false
	return true


func prepare_next_presentation_envelope_phase(
		catalog: WorldLayeredObjectAssetCatalog,
) -> bool:
	if catalog == null or not catalog.is_ready():
		return false
	_asset_catalog = catalog
	if _collision_body == null or not is_instance_valid(_collision_body):
		_ensure_collision_body().collision_layer = 0
		return true
	return false


func is_presentation_envelope_ready() -> bool:
	return _collision_body != null and is_instance_valid(_collision_body)


func begin_presentation_result(
		result: Dictionary,
		catalog: WorldLayeredObjectAssetCatalog,
) -> bool:
	if not begin_incremental_presentation_result(result, catalog):
		return false
	while has_pending_incremental_presentation_begin():
		if not advance_incremental_presentation_begin_phase():
			return false
	return is_incremental_presentation_begin_complete()


func begin_incremental_presentation_result(
		result: Dictionary,
		catalog: WorldLayeredObjectAssetCatalog,
) -> bool:
	if catalog == null or not catalog.is_ready() or not bool(result.get("success", false)):
		push_error("WorldObjectCollisionOwner requires a valid native result and source catalog")
		return false
	_asset_catalog = catalog
	_begin_result = result
	_begin_state = BeginState.HEADER
	_apply_state = ApplyState.IDLE
	_blocking_ready = false
	_complete = false
	_hot_cache_resident = false
	if _collision_body != null and is_instance_valid(_collision_body):
		_collision_body.collision_layer = 0
	return true


func has_pending_incremental_presentation_begin() -> bool:
	return _begin_state == BeginState.HEADER


func is_incremental_presentation_begin_complete() -> bool:
	return _begin_state == BeginState.COMPLETE


func has_incremental_presentation_begin_failed() -> bool:
	return _begin_state == BeginState.FAILED


func advance_incremental_presentation_begin_phase() -> bool:
	if _begin_state != BeginState.HEADER:
		return false
	var tree_count: int = maxi(0, int(_begin_result.get("tree_instance_count", 0)))
	var collision_value: Variant = _begin_result.get("tree_collision_records", null)
	if not collision_value is PackedFloat32Array:
		return _fail_begin("tree_collision_records must be PackedFloat32Array")
	var records: PackedFloat32Array = collision_value as PackedFloat32Array
	if records.size() != tree_count * COLLISION_RECORD_STRIDE:
		return _fail_begin("tree collision record count does not match tree_instance_count")
	if int(_begin_result.get("ignored_instance_count", 0)) > 0:
		return _fail_begin("native object result contains unsupported records")

	_tree_count = tree_count
	_collision_records = records
	_collision_record_index = 0
	_debug_rects.clear()
	_apply_state = ApplyState.RESET_PREVIOUS_COLLISIONS \
			if not _collision_shape_owner_ids.is_empty() \
			else (ApplyState.TREE_COLLISIONS if not records.is_empty() else ApplyState.COMMIT)
	_begin_result = { }
	_begin_state = BeginState.COMPLETE
	return true


func _fail_begin(message: String) -> bool:
	push_error("WorldObjectCollisionOwner: %s" % message)
	_begin_result = { }
	_begin_state = BeginState.FAILED
	_apply_state = ApplyState.IDLE
	_collision_records = PackedFloat32Array()
	_collision_record_index = 0
	return false


func apply_next_presentation_slice(
		_visual_buffers_per_slice: int,
		colliders_per_slice: int,
		_rock_stripes_per_slice: int,
) -> bool:
	match _apply_state:
		ApplyState.RESET_PREVIOUS_COLLISIONS:
			_remove_collision_slice(maxi(1, colliders_per_slice))
			if _collision_shape_owner_ids.is_empty():
				_apply_state = ApplyState.TREE_COLLISIONS \
						if not _collision_records.is_empty() else ApplyState.COMMIT
			return true
		ApplyState.TREE_COLLISIONS:
			_apply_collision_slice(maxi(1, colliders_per_slice))
			if _collision_record_index * COLLISION_RECORD_STRIDE >= _collision_records.size():
				_apply_state = ApplyState.COMMIT
			return true
		ApplyState.COMMIT:
			_commit_collision()
			_apply_state = ApplyState.COMPLETE
			_complete = true
			return true
		_:
			return false


func get_next_presentation_apply_phase_hint() -> StringName:
	match _apply_state:
		ApplyState.RESET_PREVIOUS_COLLISIONS:
			return PRESENTATION_PHASE_RETIRE
		ApplyState.TREE_COLLISIONS:
			return PRESENTATION_PHASE_TREE_COLLISIONS
		ApplyState.COMMIT:
			return PRESENTATION_PHASE_COMMIT
		_:
			return PRESENTATION_PHASE_NONE


func apply_next_presentation_allocation_only() -> bool:
	return false


func next_presentation_slice_requires_visual_slot_allocation() -> bool:
	return false


func did_last_presentation_slice_create_visual_slot() -> bool:
	return false


func is_blocking_presentation_ready() -> bool:
	return _blocking_ready


func is_presentation_complete() -> bool:
	return _complete


func has_pending_presentation_apply() -> bool:
	return _apply_state > ApplyState.IDLE and _apply_state < ApplyState.COMPLETE


func is_hot_cache_eligible() -> bool:
	# Completed colliders are the cached payload. begin_pool_retire() already
	# clears completion before shape removal, so live shapes are not retire work.
	return _complete and _begin_state == BeginState.COMPLETE


func estimate_presentation_result_reservation_weight(result: Dictionary) -> Dictionary:
	return {
		"gpu_buffer_bytes": 0,
		"canvas_item_count": 1,
		"collider_count": maxi(0, int(result.get("tree_instance_count", 0))),
	}


func get_hot_cache_reservation_weight() -> Dictionary:
	return {
		"gpu_buffer_bytes": 0,
		"canvas_item_count": 1,
		"collider_count": _tree_count,
	}


func get_hot_cache_weight() -> Dictionary:
	return _residency_weight()


func get_retained_residency_weight() -> Dictionary:
	return _residency_weight()


func _residency_weight() -> Dictionary:
	return {
		"gpu_buffer_bytes": 0,
		"canvas_item_count": 1 + (1 if _debug_layer != null and is_instance_valid(_debug_layer) else 0),
		"collider_count": _collision_shape_owner_ids.size(),
	}


func set_hot_cache_resident(resident: bool) -> void:
	_hot_cache_resident = resident
	visible = false
	if _collision_body != null and is_instance_valid(_collision_body):
		_collision_body.collision_layer = 0


func set_streaming_world_parented(world_parented: bool) -> void:
	_streaming_world_parented = world_parented


func is_streaming_world_parented() -> bool:
	return _streaming_world_parented


func set_blocking_collision_active(active: bool) -> void:
	if _collision_body == null or not is_instance_valid(_collision_body):
		return
	_collision_body.collision_layer = OBJECT_COLLISION_LAYER \
			if active and _blocking_ready and not _hot_cache_resident else 0


func cancel_pending_presentation_apply() -> void:
	_begin_state = BeginState.IDLE
	_begin_result = { }
	_apply_state = ApplyState.IDLE
	_collision_records = PackedFloat32Array()
	_collision_record_index = 0
	_blocking_ready = false
	_complete = false
	if _collision_body != null and is_instance_valid(_collision_body):
		_collision_body.collision_layer = 0


func begin_pool_retire() -> void:
	cancel_pending_presentation_apply()
	_tree_count = 0
	_debug_rects.clear()
	_hot_cache_resident = true
	_sync_collision_debug_layer()


func has_pending_pool_retire() -> bool:
	return not _collision_shape_owner_ids.is_empty()


func retire_next_pool_slice(_max_visual_slots: int, max_colliders: int) -> bool:
	if _collision_shape_owner_ids.is_empty():
		return false
	_remove_collision_slice(maxi(1, max_colliders))
	return true


func shrink_pool_next_slot_group() -> bool:
	return false


func set_world_origin_y(_world_origin_y: float) -> void:
	pass


func update_ladder_z(_anchor_stripe: int) -> void:
	pass


func get_raw_multimesh_upload_count_total() -> int:
	return 0


func _apply_collision_slice(max_colliders: int) -> void:
	var body: StaticBody2D = _ensure_collision_body()
	body.collision_layer = 0
	var record_count: int = _collision_records.size() / COLLISION_RECORD_STRIDE
	var end_index: int = mini(_collision_record_index + max_colliders, record_count)
	while _collision_record_index < end_index:
		var offset: int = _collision_record_index * COLLISION_RECORD_STRIDE
		var shape_position := Vector2(_collision_records[offset], _collision_records[offset + 1])
		var shape_size := Vector2(_collision_records[offset + 2], _collision_records[offset + 3])
		var shape: RectangleShape2D = _asset_catalog.get_tree_collision_shape(shape_size) \
				if _asset_catalog != null else null
		if shape == null:
			shape = RectangleShape2D.new()
			shape.size = shape_size
		var owner_id: int = body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shape)
		body.shape_owner_set_transform(owner_id, Transform2D(0.0, shape_position))
		_collision_shape_owner_ids.append(owner_id)
		if _debug_visible:
			_debug_rects.append(Rect2(shape_position - shape_size * 0.5, shape_size))
		_collision_record_index += 1


func _remove_collision_slice(max_colliders: int) -> void:
	if _collision_shape_owner_ids.is_empty():
		return
	if _collision_body == null or not is_instance_valid(_collision_body):
		_collision_shape_owner_ids.clear()
		return
	var remove_count: int = mini(max_colliders, _collision_shape_owner_ids.size())
	for _remove_index: int in range(remove_count):
		_collision_body.remove_shape_owner(_collision_shape_owner_ids.pop_back())


func _commit_collision() -> void:
	if _collision_body != null and is_instance_valid(_collision_body):
		_collision_body.collision_layer = 0
	_blocking_ready = true
	visible = false
	_sync_collision_debug_layer()


func _ensure_collision_body() -> StaticBody2D:
	if _collision_body != null and is_instance_valid(_collision_body):
		return _collision_body
	_collision_body = StaticBody2D.new()
	_collision_body.name = "WorldObjectCollisionBody"
	_collision_body.collision_layer = 0
	_collision_body.collision_mask = 0
	add_child(_collision_body)
	return _collision_body


func set_debug_collisions_visible(enabled: bool) -> void:
	_debug_visible = enabled
	if not enabled:
		if _debug_layer != null and is_instance_valid(_debug_layer):
			_debug_layer.visible = false
		return
	if _debug_rects.is_empty() and not _collision_records.is_empty():
		_debug_rects = _debug_rects_from_records(_collision_records)
	_sync_collision_debug_layer()


static func _debug_rects_from_records(records: PackedFloat32Array) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for offset: int in range(0, records.size(), COLLISION_RECORD_STRIDE):
		var shape_position := Vector2(records[offset], records[offset + 1])
		var shape_size := Vector2(records[offset + 2], records[offset + 3])
		rects.append(Rect2(shape_position - shape_size * 0.5, shape_size))
	return rects


func _sync_collision_debug_layer() -> void:
	if not _debug_visible:
		return
	if _debug_layer == null or not is_instance_valid(_debug_layer):
		_debug_layer = ObjectCollisionDebugLayer.new()
		_debug_layer.name = "ObjectCollisionDebugLayer"
		add_child(_debug_layer)
	_debug_layer.visible = true
	_debug_layer.set_debug_boxes(_debug_rects)


func get_debug_state() -> Dictionary:
	return {
		"owner": "WorldObjectCollisionOwner",
		"tree_count": _tree_count,
		"tree_collider_count": _collision_shape_owner_ids.size(),
		"tree_collision_layer": _collision_body.collision_layer \
				if _collision_body != null and is_instance_valid(_collision_body) else 0,
		"native_begin_state": BeginState.keys()[_begin_state],
		"native_apply_state": ApplyState.keys()[_apply_state],
		"native_apply_phase_hint": get_next_presentation_apply_phase_hint(),
		"native_blocking_ready": _blocking_ready,
		"native_presentation_complete": _complete,
		"collision_payload_bytes": _collision_records.size() * FLOAT_BYTES,
		"gpu_buffer_bytes": 0,
		"raw_multimesh_upload_count_total": 0,
		"legacy_visual_resource_count": 0,
	}
