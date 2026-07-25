class_name WorldInitialLoadingGate
extends RefCounted
## Bounded transient accounting for WorldStreamer's initial materialized bubble.
## This helper never schedules work or inspects scene state; the streamer feeds
## it one authoritative per-chunk stage at a time.

const STAGE_REQUESTED: int = 0
const STAGE_GENERATED: int = 1
const STAGE_GAMEPLAY_READY: int = 2
const STAGE_PRESENTATION_READY: int = 3
const STAGE_RESERVE_READY: int = 4

var _generation_epoch: int = -1
var _active: bool = false
var _ready: bool = false
var _presented: bool = false
var _target_established: bool = false
var _target_center_chunk: Vector2i = Vector2i.ZERO
var _visible_radius_chunks: int = 0
var _reserve_radius_chunks: int = 0
var _target_coords: Array[Vector2i] = []
var _target_set: Dictionary = { }
var _visible_set: Dictionary = { }
var _stage_by_chunk: Dictionary = { }
var _stage_counts: PackedInt32Array = PackedInt32Array()
var _completed_units: int = 0
var _started_usec: int = 0
var _target_established_usec: int = 0
var _milestone_usec: Dictionary = { }
var _ready_at_process_frame: int = -1
var _first_presented_process_frame: int = -1
var _memory_static_bytes: int = 0
var _memory_static_peak_bytes: int = 0
var _video_memory_bytes: int = 0
var _confirmation_checks_remaining: int = -1


func begin(generation_epoch: int) -> void:
	_generation_epoch = generation_epoch
	_active = true
	_ready = false
	_presented = false
	_target_established = false
	_target_center_chunk = Vector2i.ZERO
	_visible_radius_chunks = 0
	_reserve_radius_chunks = 0
	_target_coords.clear()
	_target_set.clear()
	_visible_set.clear()
	_stage_by_chunk.clear()
	_stage_counts = PackedInt32Array([0, 0, 0, 0, 0])
	_completed_units = 0
	_started_usec = Time.get_ticks_usec()
	_target_established_usec = 0
	_milestone_usec.clear()
	_ready_at_process_frame = -1
	_first_presented_process_frame = -1
	_memory_static_bytes = 0
	_memory_static_peak_bytes = 0
	_video_memory_bytes = 0
	_confirmation_checks_remaining = -1


func is_active() -> bool:
	return _active


func is_ready() -> bool:
	return _ready


func has_target() -> bool:
	return _target_established


func get_target_center_chunk() -> Vector2i:
	return _target_center_chunk


func get_target_coords() -> Array[Vector2i]:
	return _target_coords


func contains_target(chunk_coord: Vector2i) -> bool:
	return _target_set.has(chunk_coord)


func is_visible_target(chunk_coord: Vector2i) -> bool:
	return _visible_set.has(chunk_coord)


func establish_target(
		center_chunk: Vector2i,
		visible_coords: Array[Vector2i],
		target_coords: Array[Vector2i],
		visible_radius_chunks: int,
		reserve_radius_chunks: int,
) -> bool:
	if not _active:
		return false
	if _target_established \
			and center_chunk == _target_center_chunk \
			and target_coords.size() == _target_coords.size() \
			and visible_coords.size() == _visible_set.size():
		return false
	_target_established = true
	_target_center_chunk = center_chunk
	_visible_radius_chunks = visible_radius_chunks
	_reserve_radius_chunks = reserve_radius_chunks
	_target_coords = target_coords.duplicate()
	_target_set.clear()
	_visible_set.clear()
	_stage_by_chunk.clear()
	_stage_counts = PackedInt32Array([0, 0, 0, 0, 0])
	_completed_units = 0
	_ready = false
	_presented = false
	_ready_at_process_frame = -1
	_first_presented_process_frame = -1
	_memory_static_bytes = 0
	_memory_static_peak_bytes = 0
	_video_memory_bytes = 0
	_confirmation_checks_remaining = -1
	for chunk_coord: Vector2i in _target_coords:
		_target_set[chunk_coord] = true
		_stage_by_chunk[chunk_coord] = STAGE_REQUESTED
	for chunk_coord: Vector2i in visible_coords:
		_visible_set[chunk_coord] = true
	_target_established_usec = Time.get_ticks_usec()
	_milestone_usec.clear()
	return true


func observe_chunk_stage(chunk_coord: Vector2i, observed_stage: int) -> bool:
	if not _active or not _target_set.has(chunk_coord):
		return false
	observed_stage = clampi(
		observed_stage,
		STAGE_REQUESTED,
		STAGE_RESERVE_READY,
	)
	var previous_stage: int = int(
		_stage_by_chunk.get(chunk_coord, STAGE_REQUESTED),
	)
	var changed: bool = observed_stage != previous_stage
	if changed:
		_stage_by_chunk[chunk_coord] = observed_stage
		_completed_units += observed_stage - previous_stage
		if observed_stage > previous_stage:
			for threshold: int in range(previous_stage + 1, observed_stage + 1):
				_stage_counts[threshold] += 1
		else:
			for threshold: int in range(observed_stage + 1, previous_stage + 1):
				_stage_counts[threshold] -= 1
		_update_milestones()
	_update_confirmation()
	return changed


func capture_ready_memory(
		memory_static_bytes: int,
		memory_static_peak_bytes: int,
		video_memory_bytes: int,
) -> void:
	if not _ready:
		return
	_memory_static_bytes = maxi(memory_static_bytes, 0)
	_memory_static_peak_bytes = maxi(memory_static_peak_bytes, 0)
	_video_memory_bytes = maxi(video_memory_bytes, 0)


func acknowledge_presented() -> bool:
	if not _active or not _ready or _presented:
		return false
	_presented = true
	_active = false
	_first_presented_process_frame = int(Engine.get_process_frames())
	return true


func get_state() -> Dictionary:
	var now_usec: int = Time.get_ticks_usec()
	var target_count: int = _target_coords.size()
	var ready_usec: int = int(_milestone_usec.get(&"reserve_ready", 0))
	var elapsed_end_usec: int = ready_usec if ready_usec > 0 else now_usec
	var elapsed_ms: int = _elapsed_ms(_started_usec, elapsed_end_usec)
	var progress_ratio: float = 0.0
	if target_count > 0:
		progress_ratio = clampf(
			float(_completed_units) / float(target_count * STAGE_RESERVE_READY),
			0.0,
			1.0,
		)
	if not _ready:
		progress_ratio = minf(progress_ratio, 0.995)
	var prepared_chunks_per_second: float = 0.0
	if _ready and elapsed_ms > 0:
		prepared_chunks_per_second = float(target_count) * 1000.0 / float(elapsed_ms)
	return {
		"schema_version": 1,
		"generation_epoch": _generation_epoch,
		"active": _active,
		"target_established": _target_established,
		"ready": _ready,
		"presented": _presented,
		"current_stage": String(_current_stage()),
		"target_center_chunk": _target_center_chunk,
		"visible_radius_chunks": _visible_radius_chunks,
		"reserve_radius_chunks": _reserve_radius_chunks,
		"target_chunk_count": target_count,
		"visible_chunk_count": _visible_set.size(),
		"reserve_chunk_count": maxi(target_count - _visible_set.size(), 0),
		"generated_chunk_count": _stage_counts[STAGE_GENERATED],
		"gameplay_ready_chunk_count": _stage_counts[STAGE_GAMEPLAY_READY],
		"presentation_ready_chunk_count": _stage_counts[STAGE_PRESENTATION_READY],
		"reserve_ready_chunk_count": _stage_counts[STAGE_RESERVE_READY],
		"progress_ratio": progress_ratio,
		"elapsed_ms": elapsed_ms,
		"stage_cumulative_ms": _build_stage_cumulative_ms(now_usec),
		"stage_duration_ms": _build_stage_duration_ms(),
		"prepared_chunks_per_second": prepared_chunks_per_second,
		"ready_at_process_frame": _ready_at_process_frame,
		"first_presented_process_frame": _first_presented_process_frame,
		"memory_static_bytes": _memory_static_bytes,
		"memory_static_peak_bytes": _memory_static_peak_bytes,
		"video_memory_bytes": _video_memory_bytes,
	}


func _update_milestones() -> void:
	var target_count: int = _target_coords.size()
	if target_count <= 0:
		return
	var now_usec: int = Time.get_ticks_usec()
	for stage_record: Dictionary in [
		{ "threshold": STAGE_GENERATED, "name": &"generated" },
		{ "threshold": STAGE_GAMEPLAY_READY, "name": &"gameplay_ready" },
		{ "threshold": STAGE_PRESENTATION_READY, "name": &"presentation_ready" },
	]:
		var threshold: int = int(stage_record["threshold"])
		var stage_name: StringName = stage_record["name"] as StringName
		if _stage_counts[threshold] == target_count and not _milestone_usec.has(stage_name):
			_milestone_usec[stage_name] = now_usec
		elif _stage_counts[threshold] < target_count:
			_milestone_usec.erase(stage_name)


func _update_confirmation() -> void:
	var target_count: int = _target_coords.size()
	if target_count <= 0 or _stage_counts[STAGE_RESERVE_READY] != target_count:
		_confirmation_checks_remaining = -1
		return
	if _confirmation_checks_remaining < 0:
		_confirmation_checks_remaining = target_count
		return
	_confirmation_checks_remaining -= 1
	if _confirmation_checks_remaining <= 0 and not _ready:
		var now_usec: int = Time.get_ticks_usec()
		_milestone_usec[&"reserve_ready"] = now_usec
		_ready = true
		_ready_at_process_frame = int(Engine.get_process_frames())


func _current_stage() -> StringName:
	if not _target_established:
		return &"resolving_spawn"
	var target_count: int = _target_coords.size()
	if target_count <= 0 or _stage_counts[STAGE_GENERATED] < target_count:
		return &"generating"
	if _stage_counts[STAGE_GAMEPLAY_READY] < target_count:
		return &"gameplay"
	if _stage_counts[STAGE_PRESENTATION_READY] < target_count:
		return &"presentation"
	if _stage_counts[STAGE_RESERVE_READY] < target_count:
		return &"reserve"
	return &"ready"


func _build_stage_cumulative_ms(now_usec: int) -> Dictionary:
	var result: Dictionary = {
		"target_established": _elapsed_ms(
			_started_usec,
			_target_established_usec if _target_established_usec > 0 else now_usec,
		),
	}
	for stage_name: StringName in [
		&"generated",
		&"gameplay_ready",
		&"presentation_ready",
		&"reserve_ready",
	]:
		var milestone: int = int(_milestone_usec.get(stage_name, 0))
		result[String(stage_name)] = \
		_elapsed_ms(_started_usec, milestone) if milestone > 0 else -1
	return result


func _build_stage_duration_ms() -> Dictionary:
	var result: Dictionary = {
		"target_established": (
			_elapsed_ms(_started_usec, _target_established_usec)
			if _target_established_usec > 0
			else -1
		),
	}
	var previous_usec: int = _target_established_usec
	for stage_name: StringName in [
		&"generated",
		&"gameplay_ready",
		&"presentation_ready",
		&"reserve_ready",
	]:
		var milestone: int = int(_milestone_usec.get(stage_name, 0))
		result[String(stage_name)] = (
			_elapsed_ms(previous_usec, milestone)
			if previous_usec > 0 and milestone > 0
			else -1
		)
		if milestone > 0:
			previous_usec = milestone
	return result


func _elapsed_ms(start_usec: int, end_usec: int) -> int:
	if start_usec <= 0 or end_usec < start_usec:
		return 0
	return int((end_usec - start_usec) / 1000)
