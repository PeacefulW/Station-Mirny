class_name DepthLadderBandRoot
extends Node2D

## Exact, rebased owner for one chunk's player-relative depth stripes.
##
## z_for_stripe_vs_anchor() is piecewise linear: a north clamp, one linear
## interval, and a south clamp. Keeping one zero-transform CanvasItem root for
## each interval turns the common one-stripe anchor move into one root z write;
## only the two stripes crossing the clamp boundaries change parent.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const STRIPE_COUNT: int = WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK
const HALF_RANGE: int = WorldRuntimeConstants.DEPTH_LADDER_HALF_RANGE_STRIPES
const LADDER_ANCHOR_UNSET: int = 1 << 30

enum Band {
	NORTH_CLAMP,
	LINEAR,
	SOUTH_CLAMP,
}

var _band_roots: Array[Node2D] = []
var _item_entries: Dictionary = { }
var _item_ids_by_stripe: Array[Array] = []
var _world_origin_y: float = 0.0
var _chunk_stripe_base: int = 0
var _anchor_stripe: int = LADDER_ANCHOR_UNSET
var _last_root_z_writes: int = 0
var _last_boundary_migrations: int = 0


func _init() -> void:
	_item_ids_by_stripe.resize(STRIPE_COUNT)
	for stripe_index: int in range(STRIPE_COUNT):
		_item_ids_by_stripe[stripe_index] = []


func set_world_origin_y(world_origin_y: float) -> void:
	var next_chunk_stripe_base: int = floori(
		world_origin_y / float(WorldRuntimeConstants.DEPTH_STRIPE_PX),
	)
	_world_origin_y = world_origin_y
	if next_chunk_stripe_base == _chunk_stripe_base:
		return
	_chunk_stripe_base = next_chunk_stripe_base
	if _anchor_stripe == LADDER_ANCHOR_UNSET:
		return
	_ensure_band_roots()
	_update_band_root_z()
	_reclassify_all_items()


## Registers one already-bucketed stripe CanvasItem. local_z_offset follows the
## shared DEPTH_CHANNEL_* contract: ground surface/shadow, object base,
## authored overlay, then top overlay.
func register_item(item: CanvasItem, stripe_index: int, local_z_offset: int) -> void:
	if item == null or not is_instance_valid(item):
		return
	if stripe_index < 0 or stripe_index >= STRIPE_COUNT:
		push_error("DepthLadderBandRoot: stripe index is outside the chunk")
		return
	_ensure_band_roots()
	var item_id: int = item.get_instance_id()
	var entry: Dictionary = _item_entries.get(item_id, { }) as Dictionary
	var previous_stripe: int = int(entry.get("stripe", -1))
	if previous_stripe != stripe_index:
		if previous_stripe >= 0 and previous_stripe < STRIPE_COUNT:
			_item_ids_by_stripe[previous_stripe].erase(item_id)
		_item_ids_by_stripe[stripe_index].append(item_id)
	entry = {
		"item": item,
		"stripe": stripe_index,
		"offset": local_z_offset,
		"band": -1,
	}
	_item_entries[item_id] = entry
	_place_entry(entry, false)


func unregister_item(item: CanvasItem) -> void:
	if item == null:
		return
	var item_id: int = item.get_instance_id()
	var entry: Dictionary = _item_entries.get(item_id, { }) as Dictionary
	if entry.is_empty():
		return
	var stripe_index: int = int(entry.get("stripe", -1))
	if stripe_index >= 0 and stripe_index < STRIPE_COUNT:
		_item_ids_by_stripe[stripe_index].erase(item_id)
	_item_entries.erase(item_id)


func clear_registered_items() -> void:
	_item_entries.clear()
	for stripe_index: int in range(STRIPE_COUNT):
		_item_ids_by_stripe[stripe_index].clear()


## Pays the fixed three-band CanvasItem allocation at a loading/pool boundary.
## No item is registered or revealed; later packet slices only place already
## allocated draw items into these roots.
func prepare_presentation_envelope() -> void:
	_ensure_band_roots()


func is_presentation_envelope_ready() -> bool:
	if _band_roots.size() != Band.size():
		return false
	for band_root: Node2D in _band_roots:
		if band_root == null or not is_instance_valid(band_root):
			return false
	return true


## Makes every possible reparent target visible to a dedicated Canvas cull
## pass. Callers still choose which leaf CanvasItems carry that layer.
func include_visibility_layer(layer_mask: int) -> void:
	_ensure_band_roots()
	visibility_layer |= layer_mask
	for band_root: Node2D in _band_roots:
		band_root.visibility_layer |= layer_mask


func update_anchor(anchor_stripe: int) -> void:
	_last_root_z_writes = 0
	_last_boundary_migrations = 0
	if anchor_stripe == _anchor_stripe:
		return
	_ensure_band_roots()
	var previous_anchor: int = _anchor_stripe
	_anchor_stripe = anchor_stripe
	_update_band_root_z()
	if previous_anchor == LADDER_ANCHOR_UNSET:
		_reclassify_all_items()
		return
	_reclassify_boundary_delta(previous_anchor, anchor_stripe)


func get_debug_state() -> Dictionary:
	return {
		"anchor_stripe": _anchor_stripe,
		"chunk_stripe_base": _chunk_stripe_base,
		"canvas_item_count": 1 + _band_roots.size(),
		"registered_item_count": _item_entries.size(),
		"last_root_z_writes": _last_root_z_writes,
		"last_boundary_migrations": _last_boundary_migrations,
	}


func _ensure_band_roots() -> void:
	if _band_roots.size() == Band.size():
		return
	_band_roots.resize(Band.size())
	for band: int in range(Band.size()):
		var root := Node2D.new()
		root.name = [&"NorthClamp", &"Linear", &"SouthClamp"][band]
		root.z_as_relative = true
		add_child(root)
		_band_roots[band] = root
	# Before the first real anchor, keep newly registered hidden/staged content
	# in a harmless local ordering. WorldStreamer seeds the anchor before reveal.
	_set_root_z(Band.NORTH_CLAMP, 0)
	_set_root_z(Band.LINEAR, 0)
	_set_root_z(Band.SOUTH_CLAMP, 0)


func _update_band_root_z() -> void:
	_set_root_z(Band.NORTH_CLAMP, WorldRuntimeConstants.Z_MID_LADDER_BASE)
	_set_root_z(
		Band.SOUTH_CLAMP,
		WorldRuntimeConstants.Z_MID_LADDER_BASE + HALF_RANGE * 4,
	)
	# Only chunks intersecting the linear window can own LINEAR children. Clamp
	# the empty-root value as well so a far-away streamed chunk never asks Godot
	# for an out-of-range CanvasItem z_index.
	var linear_chunk_relative: int = clampi(
		_chunk_stripe_base - _anchor_stripe,
		-HALF_RANGE - (STRIPE_COUNT - 1),
		HALF_RANGE - 1,
	)
	_set_root_z(
		Band.LINEAR,
		WorldRuntimeConstants.Z_MID_LADDER_BASE
			+ (linear_chunk_relative + HALF_RANGE) * 2,
	)


func _set_root_z(band: int, value: int) -> void:
	var root: Node2D = _band_roots[band]
	if root.z_index == value:
		return
	root.z_index = value
	_last_root_z_writes += 1


func _reclassify_all_items() -> void:
	for stripe_index: int in range(STRIPE_COUNT):
		_reclassify_stripe(stripe_index)


func _reclassify_boundary_delta(previous_anchor: int, next_anchor: int) -> void:
	# north: local stripe <= anchor-K-base
	var old_north_max: int = previous_anchor - HALF_RANGE - _chunk_stripe_base
	var new_north_max: int = next_anchor - HALF_RANGE - _chunk_stripe_base
	_reclassify_local_range(
		mini(old_north_max, new_north_max) + 1,
		maxi(old_north_max, new_north_max),
	)
	# south: local stripe >= anchor+K-base
	var old_south_min: int = previous_anchor + HALF_RANGE - _chunk_stripe_base
	var new_south_min: int = next_anchor + HALF_RANGE - _chunk_stripe_base
	_reclassify_local_range(
		mini(old_south_min, new_south_min),
		maxi(old_south_min, new_south_min) - 1,
	)


func _reclassify_local_range(first_stripe: int, last_stripe: int) -> void:
	var clamped_first: int = maxi(first_stripe, 0)
	var clamped_last: int = mini(last_stripe, STRIPE_COUNT - 1)
	if clamped_first > clamped_last:
		return
	for stripe_index: int in range(clamped_first, clamped_last + 1):
		_reclassify_stripe(stripe_index)


func _reclassify_stripe(stripe_index: int) -> void:
	# Reparenting does not mutate this registry, but duplicate protects iteration
	# from an item being freed by an owner callback during teardown.
	var item_ids: Array = _item_ids_by_stripe[stripe_index].duplicate()
	for item_id_variant: Variant in item_ids:
		var item_id: int = int(item_id_variant)
		var entry: Dictionary = _item_entries.get(item_id, { }) as Dictionary
		if entry.is_empty():
			_item_ids_by_stripe[stripe_index].erase(item_id)
			continue
		var item: CanvasItem = entry.get("item", null) as CanvasItem
		if item == null or not is_instance_valid(item):
			_item_entries.erase(item_id)
			_item_ids_by_stripe[stripe_index].erase(item_id)
			continue
		_place_entry(entry, true)


func _place_entry(entry: Dictionary, count_migration: bool) -> void:
	var item: CanvasItem = entry.get("item", null) as CanvasItem
	if item == null or not is_instance_valid(item):
		return
	var stripe_index: int = int(entry.get("stripe", -1))
	var band: int = _band_for_stripe(stripe_index)
	var previous_band: int = int(entry.get("band", -1))
	var target_root: Node2D = _band_roots[band]
	if item.get_parent() == null:
		target_root.add_child(item)
	elif item.get_parent() != target_root:
		item.reparent(target_root, true)
		if count_migration and previous_band >= 0:
			_last_boundary_migrations += 1
	item.z_as_relative = true
	item.z_index = _local_z_for_entry(stripe_index, int(entry.get("offset", 0)), band)
	entry["band"] = band


func _band_for_stripe(stripe_index: int) -> int:
	if _anchor_stripe == LADDER_ANCHOR_UNSET:
		return Band.LINEAR
	var relative: int = _chunk_stripe_base + stripe_index - _anchor_stripe
	if relative <= -HALF_RANGE:
		return Band.NORTH_CLAMP
	if relative >= HALF_RANGE:
		return Band.SOUTH_CLAMP
	return Band.LINEAR


static func _local_z_for_entry(stripe_index: int, offset: int, band: int) -> int:
	if band == Band.LINEAR:
		return stripe_index * 2 + offset
	return offset
