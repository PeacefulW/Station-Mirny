extends SceneTree

const COLLISION_CACHE_PATH: String = "res://core/systems/world/mountain_contour_collision_cache.gd"

var _failed: bool = false
var _collision_cache_script: Script = null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	if _failed:
		quit(1)
		return

	_collision_cache_script = load(COLLISION_CACHE_PATH) as Script
	_assert(_collision_cache_script != null, "MountainContourCollisionCache script must load.")
	if _collision_cache_script == null:
		quit(1)
		return

	_assert_missing_cache_blocks()
	_assert_single_tile_lower_footprint()
	_assert_blob_collision()
	_assert_diagonal_gap_capsule_fit()
	_assert_inner_hole_is_passable()
	_assert_capsule_against_diagonal_edge()
	_assert_simple_slide_result()
	_assert_building_footprint_queries()
	_assert_aabb_broad_phase_is_used()

	if _failed:
		quit(1)
		return
	print("mountain_contour_collision_probe: OK")
	quit(0)

func _assert_static_contract() -> void:
	_assert(FileAccess.file_exists(COLLISION_CACHE_PATH), "MountainContourCollisionCache script must exist.")
	if not FileAccess.file_exists(COLLISION_CACHE_PATH):
		return
	var source: String = FileAccess.get_file_as_string(COLLISION_CACHE_PATH)
	_assert(source.contains("class_name MountainContourCollisionCache"), "Collision cache must expose MountainContourCollisionCache.")
	_assert(source.contains("func configure"), "Collision cache must implement configure().")
	_assert(source.contains("func is_point_blocked"), "Collision cache must implement is_point_blocked().")
	_assert(source.contains("func is_capsule_blocked"), "Collision cache must implement is_capsule_blocked().")
	_assert(source.contains("func slide_capsule"), "Collision cache must implement slide_capsule().")
	_assert(source.contains("func intersects_building_footprint"), "Collision cache must implement intersects_building_footprint().")
	_assert(source.contains("collision_aabbs"), "Collision cache must use supplied collision AABBs for broad-phase rejection.")
	_assert(not source.contains("walkable_flags"), "Collision cache must not fall back to square walkable_flags.")
	_assert(not source.contains("SaveManager"), "Collision cache must remain transient and must not touch SaveManager.")
	_assert(not source.contains("save_state"), "Collision cache must not expose save_state().")

func _assert_missing_cache_blocks() -> void:
	var cache: Object = _new_cache()
	_assert(cache.call("is_point_blocked", Vector2(999.0, 999.0)), "Unconfigured cache must block point queries.")
	_assert(cache.call("is_capsule_blocked", Vector2(999.0, 999.0), 8.0), "Unconfigured cache must block capsule queries.")
	var slide: Dictionary = cache.call("slide_capsule", Vector2.ZERO, Vector2(32.0, 0.0), 8.0) as Dictionary
	_assert(bool(slide.get("blocked", false)), "Unconfigured cache slide result must be blocked.")
	_assert(bool(slide.get("collided", false)), "Unconfigured cache slide result must report a collision.")
	_assert(cache.call("intersects_building_footprint", Rect2(Vector2.ZERO, Vector2(32.0, 32.0))), "Unconfigured cache must block building footprint queries.")

func _assert_single_tile_lower_footprint() -> void:
	var cache: Object = _new_cache()
	var loop: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 64.0, 99.0))
	cache.call("configure", Vector2i.ZERO, [loop], [_loop_aabb(loop)])
	_assert(cache.call("is_point_blocked", Vector2(32.0, 32.0)), "Single tile top must be blocked.")
	_assert(cache.call("is_point_blocked", Vector2(32.0, 88.0)), "Single tile facade/lower visible footprint must be blocked below square tile center.")
	_assert(not cache.call("is_point_blocked", Vector2(32.0, 112.0)), "Area below lower contact line must remain passable.")
	_assert(cache.call("is_capsule_blocked", Vector2(-4.0, 32.0), 8.0), "Capsule overlapping single-tile side edge must be blocked.")
	_assert(not cache.call("is_capsule_blocked", Vector2(-14.0, 32.0), 4.0), "Capsule outside single-tile edge radius must pass.")

func _assert_blob_collision() -> void:
	var cache: Object = _new_cache()
	var loop: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 128.0, 163.0))
	cache.call("configure", Vector2i(2, 3), [loop], [_loop_aabb(loop)])
	_assert(cache.call("is_point_blocked", Vector2(96.0, 150.0)), "Blob lower facade footprint must be blocked.")
	_assert(not cache.call("is_point_blocked", Vector2(148.0, 96.0)), "Point outside blob AABB must pass.")
	_assert(cache.call("is_capsule_blocked", Vector2(130.0, 96.0), 4.0), "Capsule touching blob side must be blocked.")

func _assert_diagonal_gap_capsule_fit() -> void:
	var cache: Object = _new_cache()
	var north_west: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 64.0, 64.0))
	var south_east: PackedVector2Array = _rect_loop(Rect2(96.0, 96.0, 64.0, 64.0))
	cache.call("configure", Vector2i.ZERO, [north_west, south_east], [_loop_aabb(north_west), _loop_aabb(south_east)])
	_assert(not cache.call("is_point_blocked", Vector2(80.0, 80.0)), "Diagonal gap center must be passable.")
	_assert(not cache.call("is_capsule_blocked", Vector2(80.0, 80.0), 16.0), "Diagonal gap must pass a capsule that fits.")
	_assert(cache.call("is_capsule_blocked", Vector2(80.0, 80.0), 24.0), "Diagonal gap must block a capsule that is too wide.")

func _assert_inner_hole_is_passable() -> void:
	var cache: Object = _new_cache()
	var outer: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 192.0, 192.0))
	var inner: PackedVector2Array = _rect_loop(Rect2(64.0, 64.0, 64.0, 64.0))
	cache.call("configure", Vector2i.ZERO, [outer, inner], [_loop_aabb(outer), _loop_aabb(inner)])
	_assert(cache.call("is_point_blocked", Vector2(32.0, 32.0)), "Outer mountain footprint must be blocked.")
	_assert(not cache.call("is_point_blocked", Vector2(96.0, 96.0)), "Inner dug hole must be passable by even-odd loop parity.")
	_assert(not cache.call("is_capsule_blocked", Vector2(96.0, 96.0), 20.0), "Capsule inside a wide dug hole must pass when it fits.")
	_assert(cache.call("is_capsule_blocked", Vector2(96.0, 96.0), 36.0), "Capsule inside a dug hole must block when radius overlaps hole boundary.")

func _assert_capsule_against_diagonal_edge() -> void:
	var cache: Object = _new_cache()
	var slope := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(96.0, 0.0),
		Vector2(96.0, 96.0),
	])
	cache.call("configure", Vector2i.ZERO, [slope], [_loop_aabb(slope)])
	_assert(cache.call("is_point_blocked", Vector2(72.0, 48.0)), "Point inside diagonal contour triangle must be blocked.")
	_assert(not cache.call("is_point_blocked", Vector2(45.0, 55.0)), "Point just outside diagonal contour edge must pass.")
	_assert(not cache.call("is_capsule_blocked", Vector2(45.0, 55.0), 6.0), "Capsule just outside diagonal edge must pass when radius fits.")
	_assert(cache.call("is_capsule_blocked", Vector2(45.0, 55.0), 8.0), "Capsule near diagonal edge must block when radius overlaps contour.")

func _assert_simple_slide_result() -> void:
	var cache: Object = _new_cache()
	var loop: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 64.0, 99.0))
	cache.call("configure", Vector2i.ZERO, [loop], [_loop_aabb(loop)])
	var slide: Dictionary = cache.call("slide_capsule", Vector2(-16.0, 32.0), Vector2(40.0, 0.0), 8.0) as Dictionary
	_assert(bool(slide.get("collided", false)), "Slide query must report collision against contour.")
	var final_position: Vector2 = slide.get("final_position", Vector2.ZERO) as Vector2
	_assert(final_position.x <= -8.0 + 0.25, "Slide final position must stop before contour penetration.")
	_assert(not bool(slide.get("blocked", true)), "Slide result at the final safe position must not remain blocked.")

func _assert_building_footprint_queries() -> void:
	var cache: Object = _new_cache()
	var outer: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 192.0, 192.0))
	var inner: PackedVector2Array = _rect_loop(Rect2(64.0, 64.0, 64.0, 64.0))
	cache.call("configure", Vector2i.ZERO, [outer, inner], [_loop_aabb(outer), _loop_aabb(inner)])
	_assert(cache.call("intersects_building_footprint", Rect2(24.0, 24.0, 24.0, 24.0)), "Building footprint inside blocked contour must intersect collision.")
	_assert(not cache.call("intersects_building_footprint", Rect2(82.0, 82.0, 28.0, 28.0)), "Building footprint fully inside dug hole must be allowed.")
	_assert(not cache.call("intersects_building_footprint", Rect2(220.0, 220.0, 32.0, 32.0)), "Building footprint outside contour AABBs must be allowed.")

func _assert_aabb_broad_phase_is_used() -> void:
	var cache: Object = _new_cache()
	var loop: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 64.0, 64.0))
	cache.call("configure", Vector2i.ZERO, [loop], [Rect2(256.0, 256.0, 32.0, 32.0)])
	_assert(not cache.call("is_point_blocked", Vector2(32.0, 32.0)), "Supplied AABB must reject point before loop checks.")
	_assert(not cache.call("is_capsule_blocked", Vector2(32.0, 32.0), 8.0), "Supplied AABB must reject capsule before loop checks.")

func _new_cache() -> Object:
	return _collision_cache_script.new()

func _rect_loop(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Vector2(rect.position.x, rect.position.y + rect.size.y),
	])

func _loop_aabb(loop: PackedVector2Array) -> Rect2:
	if loop.is_empty():
		return Rect2()
	var min_x: float = loop[0].x
	var min_y: float = loop[0].y
	var max_x: float = loop[0].x
	var max_y: float = loop[0].y
	for point: Vector2 in loop:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
