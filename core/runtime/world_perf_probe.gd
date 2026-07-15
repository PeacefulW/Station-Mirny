class_name WorldPerfProbe
extends RefCounted
## Runtime-safe no-op/per-frame perf collector used by menus and non-world systems
## while the world stack is frozen and rebuilt.

const MAX_CONTRACT_VIOLATIONS: int = 64
const LIVE_TRACKED_LABELS: Dictionary = {
	"FrameBudgetDispatcher.total": true,
	"FrameBudgetDispatcher.streaming.world.streaming_v0": true,
	"FrameBudgetDispatcher.streaming.world.object_presentation_visual_upload": true,
	"FrameBudgetDispatcher.streaming.world.object_presentation_retire": true,
	"FrameBudgetDispatcher.streaming.world.grass_scatter_visual_upload": true,
	"FrameBudgetDispatcher.visual.world.mountain_native_mask_visual_upload": true,
	"WorldStreamer.packet_results.integrate_batch": true,
	"WorldStreamer.publish.begin": true,
	"WorldStreamer.publish.apply_batch": true,
	"WorldStreamer.publish.finalize": true,
	"WorldStreamer.visual_upload.object_packet_slice": true,
	"WorldStreamer.visual_upload.object_packet_adopt": true,
	"WorldStreamer.visual_upload.grass_scatter_phase": true,
}

static var _frame_ops: Dictionary = { }
static var _milestones: Dictionary = { }
static var _contract_violations: Array[Dictionary] = []
## Optional second channel for live UI. It is enabled only while a consumer is
## visible, so ordinary gameplay pays no extra per-record Dictionary write.
## Unlike flush_frame(), reading this channel never steals samples from command-
## line perf probes.
static var _live_observer_count: int = 0
static var _live_frame_index: int = -1
static var _live_frame_ops: Dictionary = { }
static var _live_completed_frame_index: int = -1
static var _live_completed_frame_ops: Dictionary = { }


static func begin() -> int:
	return Time.get_ticks_usec()


static func end(label: String, started_usec: int) -> float:
	var elapsed_ms: float = maxf(float(Time.get_ticks_usec() - started_usec) / 1000.0, 0.0)
	record(label, elapsed_ms)
	return elapsed_ms


static func record(label: String, value_ms: float) -> void:
	if label.is_empty():
		return
	_frame_ops[label] = float(_frame_ops.get(label, 0.0)) + value_ms
	if _live_observer_count > 0 and LIVE_TRACKED_LABELS.has(label):
		_record_tracked_live(label, value_ms)


static func mark(label: String) -> void:
	if label.is_empty():
		return
	_frame_ops[label] = float(_frame_ops.get(label, 0.0))
	if _live_observer_count > 0 and LIVE_TRACKED_LABELS.has(label):
		_record_tracked_live(label, 0.0)


static func mark_milestone(label: String) -> void:
	if label.is_empty():
		return
	_milestones[label] = Time.get_ticks_usec()


static func has_milestone(label: String) -> bool:
	return _milestones.has(label)


static func record_between(label: String, start_label: String, end_label: String) -> void:
	if label.is_empty():
		return
	if not _milestones.has(start_label) or not _milestones.has(end_label):
		return
	var start_usec: int = int(_milestones.get(start_label, 0))
	var end_usec: int = int(_milestones.get(end_label, 0))
	if end_usec < start_usec:
		return
	record(label, float(end_usec - start_usec) / 1000.0)


static func report_budget_overrun(
		job_id: StringName,
		category: StringName,
		used_ms: float,
		budget_ms: float,
) -> void:
	var record_entry: Dictionary = {
		"job_id": String(job_id),
		"category": String(category),
		"used_ms": used_ms,
		"budget_ms": budget_ms,
		"timestamp_usec": Time.get_ticks_usec(),
	}
	_contract_violations.append(record_entry)
	if _contract_violations.size() > MAX_CONTRACT_VIOLATIONS:
		_contract_violations.pop_front()
	record("BudgetOverrun.%s.%s" % [String(category), String(job_id)], used_ms)


static func flush_frame() -> Dictionary:
	var snapshot: Dictionary = _frame_ops.duplicate(true)
	_frame_ops.clear()
	return snapshot


## Starts an independent, non-destructive observation stream. Samples are
## double-buffered so consumers receive the completed frame whose work produced
## their current delta, rather than partially collected work from the new frame.
## Calls are reference-counted so future debug consumers can coexist safely.
static func begin_live_observation() -> void:
	_live_observer_count += 1
	if _live_observer_count == 1:
		_live_frame_index = Engine.get_process_frames()
		_live_frame_ops.clear()
		_live_completed_frame_index = -1
		_live_completed_frame_ops.clear()


static func end_live_observation() -> void:
	_live_observer_count = maxi(0, _live_observer_count - 1)
	if _live_observer_count == 0:
		_live_frame_index = -1
		_live_frame_ops.clear()
		_live_completed_frame_index = -1
		_live_completed_frame_ops.clear()


static func copy_completed_live_frame_snapshot() -> Dictionary:
	if _live_observer_count <= 0:
		return {
			"active": false,
			"frame_index": -1,
			"ops": { },
		}
	_roll_live_frame()
	return {
		"active": true,
		"frame_index": _live_completed_frame_index,
		"ops": _live_completed_frame_ops.duplicate(false),
	}


static func get_live_observer_count() -> int:
	return _live_observer_count


static func copy_contract_violation_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for entry: Dictionary in _contract_violations:
		snapshot.append(entry.duplicate(true))
	return snapshot


static func _record_tracked_live(label: String, value_ms: float) -> void:
	_roll_live_frame()
	_live_frame_ops[label] = float(_live_frame_ops.get(label, 0.0)) + value_ms


static func _roll_live_frame() -> void:
	var current_frame: int = Engine.get_process_frames()
	if _live_frame_index == current_frame:
		return
	var recycled_ops: Dictionary = _live_completed_frame_ops
	_live_completed_frame_ops = _live_frame_ops
	_live_completed_frame_index = _live_frame_index
	_live_frame_ops = recycled_ops
	_live_frame_ops.clear()
	_live_frame_index = current_frame
