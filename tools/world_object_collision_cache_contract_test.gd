extends SceneTree
## Nonempty completed tree collision belongs in the hot cache; retirement and
## replacement must invalidate that eligibility before any incremental removal.

const CollisionOwner = preload("res://core/systems/world/world_object_collision_owner.gd")
const AssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: AssetCatalog = AssetCatalog.new()
	var owner: CollisionOwner = CollisionOwner.new()
	root.add_child(owner)
	_expect(owner.prepare_presentation_envelope(catalog), "collision shell prepares")
	_expect(not owner.is_hot_cache_eligible(), "empty unbuilt shell is not a completed cache entry")
	var result: Dictionary = {
		"success": true,
		"tree_instance_count": 2,
		"ignored_instance_count": 0,
		"tree_collision_records": PackedFloat32Array([
			10.0, 20.0, 24.0, 34.0,
			50.0, 60.0, 28.0, 36.0,
		]),
	}
	_expect(owner.begin_presentation_result(result, catalog), "compact tree collision is accepted")
	_expect(not owner.is_hot_cache_eligible(), "incomplete transaction cannot enter the cache")
	_complete(owner)
	_expect(owner.is_hot_cache_eligible(), "completed nonempty collision is cache eligible")
	var weight: Dictionary = owner.get_hot_cache_weight()
	_expect(int(weight.get("collider_count", 0)) == 2, "cache accounts for both retained colliders")
	_expect(int(weight.get("gpu_buffer_bytes", -1)) == 0, "collision cache retains zero GPU bytes")
	owner.set_blocking_collision_active(true)
	_expect(int(owner.get_debug_state().get("tree_collision_layer", 0)) != 0,
		"published collision can activate")
	owner.set_hot_cache_resident(true)
	_expect(owner.is_hot_cache_eligible(), "hidden cached collision remains complete")
	_expect(int(owner.get_debug_state().get("tree_collision_layer", -1)) == 0,
		"retained collision stays disabled outside visible demand")
	owner.set_hot_cache_resident(false)
	owner.set_blocking_collision_active(true)
	_expect(int(owner.get_debug_state().get("tree_collider_count", 0)) == 2,
		"hot-cache return reuses both shapes")
	_expect(int(owner.get_debug_state().get("tree_collision_layer", 0)) != 0,
		"hot-cache return can reactivate completed collision")
	owner.begin_pool_retire()
	_expect(not owner.is_hot_cache_eligible(), "retirement invalidates cache eligibility immediately")
	_expect(owner.has_pending_pool_retire(), "shape retirement is pending")
	owner.retire_next_pool_slice(1, 1)
	_expect(int(owner.get_retained_residency_weight().get("collider_count", 0)) == 1,
		"retirement accounting follows the bounded removed slice")
	_expect(not owner.is_hot_cache_eligible(), "partial retirement cannot reenter cache")
	owner.retire_next_pool_slice(1, 1)
	_expect(not owner.has_pending_pool_retire(), "retirement drains")
	_expect(owner.begin_presentation_result(result, catalog), "retired shell can be reused")
	_complete(owner)
	_expect(owner.is_hot_cache_eligible(), "reused completed collision is eligible")
	owner.cancel_pending_presentation_apply()
	_expect(not owner.is_hot_cache_eligible(), "cancelled payload is ineligible")
	owner.free()
	for failure: String in _failures:
		push_error("world_object_collision_cache_contract_test: %s" % failure)
	print("world_object_collision_cache_contract_test: %s" % (
		"PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


func _complete(owner: CollisionOwner) -> void:
	for _slice: int in range(8):
		if owner.is_presentation_complete():
			return
		owner.apply_next_presentation_slice(1, 1, 1)
	_expect(false, "collision completes in bounded slices")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
