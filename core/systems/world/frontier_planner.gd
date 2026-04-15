class_name FrontierPlanner
extends RefCounted

var _owner: Node = null
var _travel_state_resolver = null
var _view_envelope_resolver = null

func setup(owner: Node, travel_state_resolver, view_envelope_resolver) -> void:
	_owner = owner
	_travel_state_resolver = travel_state_resolver
	_view_envelope_resolver = view_envelope_resolver

func build_plan(center: Vector2i, active_z: int) -> Dictionary:
	var canonical_center: Vector2i = _owner._canonical_chunk_coord(center)
	var chunk_size_px: float = _chunk_size_px()
	var travel_state: Dictionary = _travel_state_resolver.resolve(
		_owner._player,
		_owner._get_player_chunk_motion(),
		chunk_size_px
	) if _travel_state_resolver != null else {}
	var view_envelope: Dictionary = _view_envelope_resolver.resolve(
		canonical_center,
		_owner._player,
		active_z
	) if _view_envelope_resolver != null else _build_fallback_view(canonical_center, active_z)
	var hot_near_set: Dictionary = view_envelope.get("hot_near_set", {}) as Dictionary
	if hot_near_set.is_empty():
		hot_near_set = view_envelope.get("camera_visible_set", {}) as Dictionary
	var warm_preload_set: Dictionary = view_envelope.get("warm_preload_set", {}) as Dictionary
	if warm_preload_set.is_empty():
		warm_preload_set = view_envelope.get("camera_margin_set", {}) as Dictionary
	var frontier_critical_set: Dictionary = {}
	_merge_set(frontier_critical_set, hot_near_set)
	var motion_frontier_set: Dictionary = _build_motion_frontier_set(canonical_center, travel_state)
	_merge_set(frontier_critical_set, motion_frontier_set)
	var frontier_high_set: Dictionary = {}
	_merge_set(frontier_high_set, warm_preload_set)
	_remove_existing(frontier_high_set, frontier_critical_set)
	var background_set: Dictionary = _build_background_set(canonical_center, frontier_critical_set, frontier_high_set)
	var needed_set: Dictionary = {}
	_merge_set(needed_set, frontier_critical_set)
	_merge_set(needed_set, frontier_high_set)
	_merge_set(needed_set, background_set)
	return {
		"center": canonical_center,
		"active_z": active_z,
		"travel_state": travel_state,
		"view_envelope": view_envelope,
		"frontier_critical_set": frontier_critical_set,
		"frontier_high_set": frontier_high_set,
		"background_set": background_set,
		"needed_set": needed_set,
		"motion_frontier_set": motion_frontier_set,
		"load_radius": _load_radius(),
		"unload_radius": _unload_radius(),
	}

func build_debug_summary(plan: Dictionary) -> Dictionary:
	var travel_state: Dictionary = plan.get("travel_state", {}) as Dictionary
	var view_envelope: Dictionary = plan.get("view_envelope", {}) as Dictionary
	return {
		"travel_mode": String(travel_state.get("travel_mode", &"")),
		"speed_class": String(travel_state.get("speed_class", &"")),
		"planning_speed_class": String(travel_state.get("planning_speed_class", &"")),
		"prediction_horizon_ms": int(travel_state.get("prediction_horizon_ms", 0)),
		"hot_near_count": (view_envelope.get("hot_near_set", {}) as Dictionary).size(),
		"warm_preload_count": (view_envelope.get("warm_preload_set", {}) as Dictionary).size(),
		"debug_camera_visible_count": (view_envelope.get("debug_camera_visible_set", {}) as Dictionary).size(),
		"frontier_critical_count": (plan.get("frontier_critical_set", {}) as Dictionary).size(),
		"frontier_high_count": (plan.get("frontier_high_set", {}) as Dictionary).size(),
		"background_count": (plan.get("background_set", {}) as Dictionary).size(),
		"needed_count": (plan.get("needed_set", {}) as Dictionary).size(),
		"view_source": str(view_envelope.get("source", "")),
		"debug_camera_source": str(view_envelope.get("debug_camera_source", "")),
	}

func _build_motion_frontier_set(center: Vector2i, travel_state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var motion_step: Vector2i = travel_state.get("motion_step", Vector2i.ZERO) as Vector2i
	var forward_chunks: int = maxi(1, int(travel_state.get("max_forward_chunks", 1)))
	var lateral_chunks: int = maxi(0, int(travel_state.get("max_lateral_chunks", 1)))
	if motion_step == Vector2i.ZERO:
		_append_square(result, center, 1)
		return result
	for forward: int in range(1, forward_chunks + 1):
		var base: Vector2i = _owner._offset_chunk_coord(center, motion_step * forward)
		if motion_step.x != 0 and motion_step.y == 0:
			for lateral: int in range(-lateral_chunks, lateral_chunks + 1):
				result[_owner._offset_chunk_coord(base, Vector2i(0, lateral))] = true
		elif motion_step.y != 0 and motion_step.x == 0:
			for lateral: int in range(-lateral_chunks, lateral_chunks + 1):
				result[_owner._offset_chunk_coord(base, Vector2i(lateral, 0))] = true
		else:
			_append_square(result, base, lateral_chunks)
	return result

func _build_background_set(center: Vector2i, critical_set: Dictionary, high_set: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var load_radius: int = _load_radius()
	for dx: int in range(-load_radius, load_radius + 1):
		for dy: int in range(-load_radius, load_radius + 1):
			var coord: Vector2i = _owner._offset_chunk_coord(center, Vector2i(dx, dy))
			if critical_set.has(coord) or high_set.has(coord):
				continue
			result[coord] = true
	return result

func _build_fallback_view(center: Vector2i, active_z: int) -> Dictionary:
	var hot_near_set: Dictionary = {}
	_append_square(hot_near_set, center, 1)
	var warm_preload_set: Dictionary = {}
	_append_square(warm_preload_set, center, 2)
	return {
		"active_z": active_z,
		"camera_center": center,
		"camera_visible_set": hot_near_set,
		"camera_margin_set": warm_preload_set,
		"hot_near_set": hot_near_set,
		"warm_preload_set": warm_preload_set,
		"source": "fallback_fixed_hot_warm",
	}

func _append_square(target: Dictionary, center: Vector2i, radius: int) -> void:
	for dx: int in range(-radius, radius + 1):
		for dy: int in range(-radius, radius + 1):
			target[_owner._offset_chunk_coord(center, Vector2i(dx, dy))] = true

func _merge_set(target: Dictionary, source: Dictionary) -> void:
	for coord_variant: Variant in source.keys():
		target[coord_variant] = true

func _remove_existing(target: Dictionary, existing: Dictionary) -> void:
	for coord_variant: Variant in existing.keys():
		target.erase(coord_variant)

func _chunk_size_px() -> float:
	if WorldGenerator and WorldGenerator.balance:
		return float(WorldGenerator.balance.chunk_size_tiles * WorldGenerator.balance.tile_size)
	return 0.0

func _load_radius() -> int:
	return WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0

func _unload_radius() -> int:
	return WorldGenerator.balance.unload_radius if WorldGenerator and WorldGenerator.balance else _load_radius()
