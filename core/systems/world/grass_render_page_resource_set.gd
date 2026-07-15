class_name GrassRenderPageResourceSet
extends RefCounted

## Owns the bounded front/back/pending MultiMesh resources for one grass render
## page. It never creates or mutates CanvasItems; GrassRenderPage remains the
## sole owner of graph allocation, depth, visibility, and atomic publication.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const BUFFER_STRIDE: int = 12
const STRIPE_COUNT: int = WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK

enum FixedPass {
	DIRECTIONAL_SHADOW,
	CONTACT_SHADOW,
	SPORES,
}

static var _shared_unit_quad: QuadMesh = null

var raw_upload_count_total: int = 0
var last_callback_multimesh_allocation_count: int = 0
var last_callback_raw_upload_count: int = 0

var _front_stripes: Array[MultiMesh] = []
var _back_stripes: Array[MultiMesh] = []
var _pending_stripes: Array[MultiMesh] = []
var _front_stripe_counts := PackedInt32Array()
var _pending_stripe_counts := PackedInt32Array()
var _fixed_front: Array[MultiMesh] = []
var _fixed_back: Array[MultiMesh] = []
var _fixed_pending: Array[MultiMesh] = []
var _fixed_front_counts := PackedInt32Array()
var _fixed_pending_counts := PackedInt32Array()


func _init() -> void:
	_front_stripes.resize(STRIPE_COUNT)
	_back_stripes.resize(STRIPE_COUNT)
	_pending_stripes.resize(STRIPE_COUNT)
	_front_stripe_counts.resize(STRIPE_COUNT)
	_pending_stripe_counts.resize(STRIPE_COUNT)
	_fixed_front.resize(FixedPass.size())
	_fixed_back.resize(FixedPass.size())
	_fixed_pending.resize(FixedPass.size())
	_fixed_front_counts.resize(FixedPass.size())
	_fixed_pending_counts.resize(FixedPass.size())
	reset_all()


func reset_callback_counters() -> void:
	last_callback_multimesh_allocation_count = 0
	last_callback_raw_upload_count = 0


func begin_staging() -> void:
	_pending_stripes.fill(null)
	_pending_stripe_counts.fill(0)
	_fixed_pending.fill(null)
	_fixed_pending_counts.fill(0)
	reset_callback_counters()


func cancel_staging() -> void:
	_pending_stripes.fill(null)
	_pending_stripe_counts.fill(0)
	_fixed_pending.fill(null)
	_fixed_pending_counts.fill(0)
	reset_callback_counters()


func reset_all() -> void:
	_front_stripes.fill(null)
	_back_stripes.fill(null)
	_pending_stripes.fill(null)
	_front_stripe_counts.fill(0)
	_pending_stripe_counts.fill(0)
	_fixed_front.fill(null)
	_fixed_back.fill(null)
	_fixed_pending.fill(null)
	_fixed_front_counts.fill(0)
	_fixed_pending_counts.fill(0)
	raw_upload_count_total = 0
	reset_callback_counters()


func stripe_candidate_requires_allocation(stripe_index: int, count: int) -> bool:
	var back: MultiMesh = _back_stripes[stripe_index]
	return back == null or back.instance_count != count


func allocate_stripe_candidate(stripe_index: int, count: int) -> void:
	var current: MultiMesh = _back_stripes[stripe_index]
	if current == null or current.instance_count != count:
		last_callback_multimesh_allocation_count += 1
	_back_stripes[stripe_index] = _prepare_multimesh(current, count)


func stage_stripe(stripe_index: int, buffer: PackedFloat32Array) -> void:
	var count: int = buffer.size() / BUFFER_STRIDE
	_pending_stripe_counts[stripe_index] = count
	if count <= 0:
		_pending_stripes[stripe_index] = null
		return
	var multimesh: MultiMesh = _back_stripes[stripe_index]
	assert(multimesh != null and multimesh.instance_count == count)
	multimesh.buffer = buffer
	_pending_stripes[stripe_index] = multimesh
	raw_upload_count_total += 1
	last_callback_raw_upload_count += 1


func fixed_candidate_requires_allocation(pass_index: int, count: int) -> bool:
	var back: MultiMesh = _fixed_back[pass_index]
	return back == null or back.instance_count != count


func allocate_fixed_candidate(pass_index: int, count: int) -> void:
	var current: MultiMesh = _fixed_back[pass_index]
	if current == null or current.instance_count != count:
		last_callback_multimesh_allocation_count += 1
	_fixed_back[pass_index] = _prepare_multimesh(current, count)


func stage_fixed(pass_index: int, buffer: PackedFloat32Array) -> void:
	var count: int = buffer.size() / BUFFER_STRIDE
	_fixed_pending_counts[pass_index] = count
	if count <= 0:
		_fixed_pending[pass_index] = null
		return
	var multimesh: MultiMesh = _fixed_back[pass_index]
	assert(multimesh != null and multimesh.instance_count == count)
	multimesh.buffer = buffer
	_fixed_pending[pass_index] = multimesh
	raw_upload_count_total += 1
	last_callback_raw_upload_count += 1


## Swaps all staged resources synchronously. The caller updates CanvasItem
## references only after this completes, so no partially committed graph exists.
func commit(use_directional_shadow: bool) -> void:
	for stripe_index: int in range(STRIPE_COUNT):
		var previous_front: MultiMesh = _front_stripes[stripe_index]
		_front_stripes[stripe_index] = _pending_stripes[stripe_index]
		_back_stripes[stripe_index] = previous_front
		_front_stripe_counts[stripe_index] = _pending_stripe_counts[stripe_index]
	_commit_fixed_pass(
		FixedPass.DIRECTIONAL_SHADOW,
		use_directional_shadow,
	)
	_commit_fixed_pass(
		FixedPass.CONTACT_SHADOW,
		not use_directional_shadow,
	)
	_commit_fixed_pass(FixedPass.SPORES, true)
	cancel_staging()


func _commit_fixed_pass(pass_index: int, publish_pending: bool) -> void:
	var previous_front: MultiMesh = _fixed_front[pass_index]
	_fixed_front[pass_index] = _fixed_pending[pass_index] if publish_pending else null
	_fixed_back[pass_index] = previous_front
	_fixed_front_counts[pass_index] = \
			_fixed_pending_counts[pass_index] if publish_pending else 0


func front_stripe(stripe_index: int) -> MultiMesh:
	return _front_stripes[stripe_index]


func front_stripe_count(stripe_index: int) -> int:
	return _front_stripe_counts[stripe_index]


func front_fixed(pass_index: int) -> MultiMesh:
	return _fixed_front[pass_index]


func front_fixed_count(pass_index: int) -> int:
	return _fixed_front_counts[pass_index]


func max_stripe_resource_count() -> int:
	var result: int = 0
	for stripe_index: int in range(STRIPE_COUNT):
		var count: int = 0
		if _front_stripes[stripe_index] != null:
			count += 1
		if _back_stripes[stripe_index] != null \
				and _back_stripes[stripe_index] != _front_stripes[stripe_index]:
			count += 1
		result = maxi(result, count)
	return result


static func _prepare_multimesh(current: MultiMesh, count: int) -> MultiMesh:
	var multimesh: MultiMesh = current
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.mesh = _unit_quad()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_colors = true
	multimesh.visible_instance_count = -1
	if multimesh.instance_count != count:
		multimesh.instance_count = count
	return multimesh


static func _unit_quad() -> QuadMesh:
	if _shared_unit_quad != null:
		return _shared_unit_quad
	_shared_unit_quad = QuadMesh.new()
	_shared_unit_quad.size = Vector2.ONE
	return _shared_unit_quad
