class_name MountainContourCollisionCache
extends RefCounted

const EPSILON: float = 0.001
const MAX_SLIDE_STEPS: int = 64

var chunk_coord: Vector2i = Vector2i.ZERO

var _configured: bool = false
var _collision_loops: Array = []
var _collision_aabbs: Array[Rect2] = []

func configure(new_chunk_coord: Vector2i, collision_loops: Array, collision_aabbs: Array) -> void:
	chunk_coord = new_chunk_coord
	_collision_loops.clear()
	_collision_aabbs.clear()
	for index: int in collision_loops.size():
		var loop: PackedVector2Array = _to_loop(collision_loops[index])
		if loop.size() < 3:
			continue
		_collision_loops.append(loop)
		if index < collision_aabbs.size() and collision_aabbs[index] is Rect2:
			_collision_aabbs.append(collision_aabbs[index] as Rect2)
		else:
			_collision_aabbs.append(_loop_aabb(loop))
	_configured = true

func is_point_blocked(local_pos: Vector2) -> bool:
	if not _configured:
		return true
	var candidates: PackedInt32Array = _candidate_loops_for_point(local_pos)
	if candidates.is_empty():
		return false
	return _point_blocked_by_candidates(local_pos, candidates)

func is_capsule_blocked(local_pos: Vector2, radius_px: float) -> bool:
	if not _configured:
		return true
	var radius: float = maxf(0.0, radius_px)
	if radius <= EPSILON:
		return is_point_blocked(local_pos)
	var candidates: PackedInt32Array = _candidate_loops_for_capsule(local_pos, radius)
	if candidates.is_empty():
		return false
	if _point_blocked_by_candidates(local_pos, candidates):
		return true
	var radius_sq: float = radius * radius
	for loop_index: int in candidates:
		if _distance_sq_to_loop(local_pos, _collision_loops[loop_index] as PackedVector2Array) <= radius_sq:
			return true
	return false

func slide_capsule(local_pos: Vector2, motion: Vector2, radius_px: float) -> Dictionary:
	if not _configured:
		return _blocked_slide_result(local_pos, motion)
	if is_capsule_blocked(local_pos, radius_px):
		return _blocked_slide_result(local_pos, motion)
	if motion.is_zero_approx():
		return _free_slide_result(local_pos, motion)

	var target: Vector2 = local_pos + motion
	if not is_capsule_blocked(target, radius_px):
		return _free_slide_result(target, motion)

	var safe_position: Vector2 = local_pos
	var hit_position: Vector2 = target
	var step_count: int = clampi(ceili(motion.length() / maxf(4.0, radius_px * 0.5)), 1, MAX_SLIDE_STEPS)
	for step: int in range(1, step_count + 1):
		var candidate: Vector2 = local_pos + motion * (float(step) / float(step_count))
		if is_capsule_blocked(candidate, radius_px):
			hit_position = candidate
			break
		safe_position = candidate

	var normal: Vector2 = _nearest_collision_normal(hit_position, maxf(radius_px, EPSILON))
	if normal.is_zero_approx():
		normal = -motion.normalized()
	var remaining: Vector2 = target - safe_position
	var slide_motion: Vector2 = remaining - normal * remaining.dot(normal)
	var final_position: Vector2 = safe_position
	if not slide_motion.is_zero_approx():
		var slide_target: Vector2 = safe_position + slide_motion
		if not is_capsule_blocked(slide_target, radius_px):
			final_position = slide_target
	var motion_applied: Vector2 = final_position - local_pos
	return {
		"blocked": is_capsule_blocked(final_position, radius_px),
		"collided": true,
		"final_position": final_position,
		"motion_applied": motion_applied,
		"remainder": motion - motion_applied,
		"normal": normal,
	}

func intersects_building_footprint(local_shape: Variant) -> bool:
	if not _configured:
		return true
	if local_shape is Rect2:
		return _rect_intersects_collision(local_shape as Rect2)
	var polygon: PackedVector2Array = _to_loop(local_shape)
	if polygon.size() < 3:
		return true
	return _polygon_intersects_collision(polygon)

func _blocked_slide_result(local_pos: Vector2, motion: Vector2) -> Dictionary:
	return {
		"blocked": true,
		"collided": true,
		"final_position": local_pos,
		"motion_applied": Vector2.ZERO,
		"remainder": motion,
		"normal": Vector2.ZERO,
	}

func _free_slide_result(final_position: Vector2, motion: Vector2) -> Dictionary:
	return {
		"blocked": false,
		"collided": false,
		"final_position": final_position,
		"motion_applied": motion,
		"remainder": Vector2.ZERO,
		"normal": Vector2.ZERO,
	}

func _rect_intersects_collision(rect: Rect2) -> bool:
	var candidates: PackedInt32Array = _candidate_loops_for_rect(rect)
	if candidates.is_empty():
		return false
	for point: Vector2 in _rect_points(rect):
		if _point_blocked_by_candidates(point, candidates):
			return true
	if _point_blocked_by_candidates(rect.get_center(), candidates):
		return true
	var rect_edges: Array = _rect_edges(rect)
	for loop_index: int in candidates:
		var loop: PackedVector2Array = _collision_loops[loop_index] as PackedVector2Array
		for point: Vector2 in loop:
			if _rect_contains_point(rect, point, EPSILON):
				return true
		for edge: Array in rect_edges:
			if _loop_intersects_segment(loop, edge[0] as Vector2, edge[1] as Vector2):
				return true
	return false

func _polygon_intersects_collision(polygon: PackedVector2Array) -> bool:
	var polygon_aabb: Rect2 = _loop_aabb(polygon)
	var candidates: PackedInt32Array = _candidate_loops_for_rect(polygon_aabb)
	if candidates.is_empty():
		return false
	for point: Vector2 in polygon:
		if _point_blocked_by_candidates(point, candidates):
			return true
	for loop_index: int in candidates:
		var loop: PackedVector2Array = _collision_loops[loop_index] as PackedVector2Array
		for point: Vector2 in loop:
			if _point_in_polygon_even_odd(point, polygon):
				return true
		for polygon_index: int in polygon.size():
			var a: Vector2 = polygon[polygon_index]
			var b: Vector2 = polygon[(polygon_index + 1) % polygon.size()]
			if _loop_intersects_segment(loop, a, b):
				return true
	return false

func _point_blocked_by_candidates(local_pos: Vector2, candidates: PackedInt32Array) -> bool:
	var inside_count: int = 0
	for loop_index: int in candidates:
		var loop: PackedVector2Array = _collision_loops[loop_index] as PackedVector2Array
		var relation: int = _point_loop_relation(local_pos, loop)
		if relation == 2:
			return true
		if relation == 1:
			inside_count += 1
	return inside_count % 2 == 1

func _candidate_loops_for_point(local_pos: Vector2) -> PackedInt32Array:
	var candidates := PackedInt32Array()
	for index: int in _collision_loops.size():
		if _rect_contains_point(_collision_aabbs[index], local_pos, EPSILON):
			candidates.append(index)
	return candidates

func _candidate_loops_for_capsule(local_pos: Vector2, radius: float) -> PackedInt32Array:
	var candidates := PackedInt32Array()
	for index: int in _collision_loops.size():
		if _point_near_rect(local_pos, _collision_aabbs[index], radius + EPSILON):
			candidates.append(index)
	return candidates

func _candidate_loops_for_rect(rect: Rect2) -> PackedInt32Array:
	var candidates := PackedInt32Array()
	for index: int in _collision_loops.size():
		if _rects_intersect_or_touch(rect, _collision_aabbs[index], EPSILON):
			candidates.append(index)
	return candidates

func _nearest_collision_normal(local_pos: Vector2, radius: float) -> Vector2:
	var candidates: PackedInt32Array = _candidate_loops_for_capsule(local_pos, radius)
	var best_distance_sq: float = INF
	var best_point: Vector2 = local_pos
	for loop_index: int in candidates:
		var loop: PackedVector2Array = _collision_loops[loop_index] as PackedVector2Array
		for edge_index: int in loop.size():
			var a: Vector2 = loop[edge_index]
			var b: Vector2 = loop[(edge_index + 1) % loop.size()]
			var closest: Vector2 = _closest_point_on_segment(local_pos, a, b)
			var distance_sq: float = local_pos.distance_squared_to(closest)
			if distance_sq < best_distance_sq:
				best_distance_sq = distance_sq
				best_point = closest
	var normal: Vector2 = local_pos - best_point
	if normal.length_squared() <= EPSILON * EPSILON:
		return Vector2.ZERO
	return normal.normalized()

func _distance_sq_to_loop(point: Vector2, loop: PackedVector2Array) -> float:
	var best_distance_sq: float = INF
	for index: int in loop.size():
		var a: Vector2 = loop[index]
		var b: Vector2 = loop[(index + 1) % loop.size()]
		best_distance_sq = minf(best_distance_sq, point.distance_squared_to(_closest_point_on_segment(point, a, b)))
	return best_distance_sq

func _point_loop_relation(point: Vector2, loop: PackedVector2Array) -> int:
	var inside: bool = false
	var previous: Vector2 = loop[loop.size() - 1]
	for current: Vector2 in loop:
		if _point_on_segment(point, previous, current):
			return 2
		var crosses_y: bool = (current.y > point.y) != (previous.y > point.y)
		if crosses_y:
			var crossing_x: float = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
			if point.x < crossing_x:
				inside = not inside
		previous = current
	return 1 if inside else 0

func _point_in_polygon_even_odd(point: Vector2, polygon: PackedVector2Array) -> bool:
	return _point_loop_relation(point, polygon) > 0

func _loop_intersects_segment(loop: PackedVector2Array, a: Vector2, b: Vector2) -> bool:
	for index: int in loop.size():
		var c: Vector2 = loop[index]
		var d: Vector2 = loop[(index + 1) % loop.size()]
		if _segments_intersect(a, b, c, d):
			return true
	return false

func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c: float = _cross(b - a, c - a)
	var ab_d: float = _cross(b - a, d - a)
	var cd_a: float = _cross(d - c, a - c)
	var cd_b: float = _cross(d - c, b - c)
	if absf(ab_c) <= EPSILON and _point_on_segment(c, a, b):
		return true
	if absf(ab_d) <= EPSILON and _point_on_segment(d, a, b):
		return true
	if absf(cd_a) <= EPSILON and _point_on_segment(a, c, d):
		return true
	if absf(cd_b) <= EPSILON and _point_on_segment(b, c, d):
		return true
	return (ab_c > 0.0) != (ab_d > 0.0) and (cd_a > 0.0) != (cd_b > 0.0)

func _point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> bool:
	var distance_sq: float = point.distance_squared_to(_closest_point_on_segment(point, a, b))
	return distance_sq <= EPSILON * EPSILON

func _closest_point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var segment: Vector2 = b - a
	var length_sq: float = segment.length_squared()
	if length_sq <= EPSILON * EPSILON:
		return a
	var t: float = clampf((point - a).dot(segment) / length_sq, 0.0, 1.0)
	return a + segment * t

func _point_near_rect(point: Vector2, rect: Rect2, radius: float) -> bool:
	var closest_x: float = clampf(point.x, rect.position.x, rect.position.x + rect.size.x)
	var closest_y: float = clampf(point.y, rect.position.y, rect.position.y + rect.size.y)
	return point.distance_squared_to(Vector2(closest_x, closest_y)) <= radius * radius

func _rects_intersect_or_touch(lhs: Rect2, rhs: Rect2, margin: float) -> bool:
	return lhs.position.x <= rhs.position.x + rhs.size.x + margin \
		and lhs.position.x + lhs.size.x + margin >= rhs.position.x \
		and lhs.position.y <= rhs.position.y + rhs.size.y + margin \
		and lhs.position.y + lhs.size.y + margin >= rhs.position.y

func _rect_contains_point(rect: Rect2, point: Vector2, margin: float) -> bool:
	return point.x >= rect.position.x - margin \
		and point.x <= rect.position.x + rect.size.x + margin \
		and point.y >= rect.position.y - margin \
		and point.y <= rect.position.y + rect.size.y + margin

func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Vector2(rect.position.x, rect.position.y + rect.size.y),
	])

func _rect_edges(rect: Rect2) -> Array:
	var points: PackedVector2Array = _rect_points(rect)
	return [
		[points[0], points[1]],
		[points[1], points[2]],
		[points[2], points[3]],
		[points[3], points[0]],
	]

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

func _to_loop(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return (value as PackedVector2Array).duplicate()
	var loop := PackedVector2Array()
	if value is Array:
		for point_variant: Variant in value:
			if point_variant is Vector2:
				loop.append(point_variant as Vector2)
	return loop

func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x
