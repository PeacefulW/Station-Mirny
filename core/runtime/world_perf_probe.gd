class_name WorldPerfProbe
extends RefCounted

## Runtime-safe no-op/per-frame perf collector used by menus and non-world systems
## while the world stack is frozen and rebuilt.

const MAX_CONTRACT_VIOLATIONS: int = 64

static var _frame_ops: Dictionary = {}
static var _milestones: Dictionary = {}
static var _contract_violations: Array[Dictionary] = []

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

static func mark(label: String) -> void:
	if label.is_empty():
		return
	_frame_ops[label] = float(_frame_ops.get(label, 0.0))

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
	budget_ms: float
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

static func copy_contract_violation_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for entry: Dictionary in _contract_violations:
		snapshot.append(entry.duplicate(true))
	return snapshot
