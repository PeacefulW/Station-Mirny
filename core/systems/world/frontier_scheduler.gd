class_name FrontierScheduler
extends RefCounted

const LANE_FRONTIER_CRITICAL: int = 0
const LANE_CAMERA_VISIBLE_SUPPORT: int = 1
const LANE_BACKGROUND: int = 2
const RESERVED_CRITICAL_WORKERS: int = 1

var _owner: Node = null

func setup(owner: Node) -> void:
	_owner = owner

func resolve_lane_for_coord(coord: Vector2i, plan: Dictionary) -> int:
	var critical_set: Dictionary = plan.get("frontier_critical_set", {}) as Dictionary
	if critical_set.has(coord):
		return LANE_FRONTIER_CRITICAL
	var high_set: Dictionary = plan.get("frontier_high_set", {}) as Dictionary
	if high_set.has(coord):
		return LANE_CAMERA_VISIBLE_SUPPORT
	return LANE_BACKGROUND

func can_submit_lane(lane: int, active_lanes: Dictionary, max_concurrent: int) -> bool:
	var active_total: int = active_lanes.size()
	if max_concurrent <= 0 or active_total >= max_concurrent:
		return false
	if lane == LANE_FRONTIER_CRITICAL:
		return true
	return active_total < noncritical_capacity_limit(max_concurrent)

func noncritical_capacity_limit(max_concurrent: int) -> int:
	return maxi(0, max_concurrent - RESERVED_CRITICAL_WORKERS)

func lane_name(lane: int) -> String:
	match lane:
		LANE_FRONTIER_CRITICAL:
			return "frontier_critical"
		LANE_CAMERA_VISIBLE_SUPPORT:
			return "camera_visible_support"
		_:
			return "background"

func lane_human(lane: int) -> String:
	match lane:
		LANE_FRONTIER_CRITICAL:
			return "критический frontier"
		LANE_CAMERA_VISIBLE_SUPPORT:
			return "поддержка видимой камеры"
		_:
			return "фон"

func lane_order(lane: int) -> int:
	match lane:
		LANE_FRONTIER_CRITICAL:
			return 0
		LANE_CAMERA_VISIBLE_SUPPORT:
			return 1
		_:
			return 2

func build_capacity_snapshot(active_lanes: Dictionary, queue_depths: Dictionary, max_concurrent: int) -> Dictionary:
	return {
		"reserved_critical_workers": RESERVED_CRITICAL_WORKERS,
		"max_concurrent": max_concurrent,
		"noncritical_capacity_limit": noncritical_capacity_limit(max_concurrent),
		"active_total": active_lanes.size(),
		"active_frontier_critical": _count_active_lane(active_lanes, LANE_FRONTIER_CRITICAL),
		"active_camera_visible_support": _count_active_lane(active_lanes, LANE_CAMERA_VISIBLE_SUPPORT),
		"active_background": _count_active_lane(active_lanes, LANE_BACKGROUND),
		"queue_frontier_critical": int(queue_depths.get("frontier_critical", 0)),
		"queue_camera_visible_support": int(queue_depths.get("camera_visible_support", 0)),
		"queue_background": int(queue_depths.get("background", 0)),
	}

func _count_active_lane(active_lanes: Dictionary, lane: int) -> int:
	var count: int = 0
	for lane_variant: Variant in active_lanes.values():
		if int(lane_variant) == lane:
			count += 1
	return count
