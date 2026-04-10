class_name WorldPerfProbe
extends RefCounted

## Инструментальный профайлер для мировых систем.
## Статические методы — не требует autoload.
## Проверяет контракты из docs/00_governance/PERFORMANCE_CONTRACTS.md.

const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")

const _DEFAULT_PRINT_THRESHOLD_MS: float = 8.0
const _SUPPRESSED_PRINT_PREFIXES: Array[String] = [
	"scheduler.visual_tasks_processed",
	"scheduler.visual_queue_depth.",
	"scheduler.visual_budget_exhausted_count",
	"scheduler.starvation_incident_count",
]
const _PRINT_THRESHOLD_OVERRIDES: Array[Dictionary] = [
	{"prefix": "FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw", "threshold_ms": 24.0},
	{"prefix": "FrameBudgetDispatcher.total", "threshold_ms": 28.0},
	{"prefix": "FrameBudgetDispatcher.", "threshold_ms": 20.0},
	{"prefix": "Scheduler.urgent_visual_wait_ms", "threshold_ms": 100.0},
	{"prefix": "scheduler.max_urgent_wait_ms", "threshold_ms": 100.0},
	{"prefix": "Shadow.edge_cache_compute", "threshold_ms": 60.0},
	{"prefix": "Shadow.compute", "threshold_ms": 12.0},
	{"prefix": "ChunkManager.streaming_redraw_prepare_step.", "threshold_ms": 8.0},
	{"prefix": "ChunkManager.streaming_redraw_step.", "threshold_ms": 8.0},
	{"prefix": "Boot.loop_step_ms", "threshold_ms": 35.0},
	{"prefix": "stream.chunk_first_pass_ms", "threshold_ms": 50.0},
	{"prefix": "stream.chunk_full_redraw_ms", "threshold_ms": 50.0},
	{"prefix": "stream.chunk_border_fix_ms", "threshold_ms": 50.0},
]
const _PRINT_COOLDOWN_OVERRIDES: Array[Dictionary] = [
	{"prefix": "FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw", "cooldown_ms": 1000.0, "delta_ms": 6.0},
	{"prefix": "FrameBudgetDispatcher.total", "cooldown_ms": 1000.0, "delta_ms": 6.0},
	{"prefix": "Boot.loop_step_ms", "cooldown_ms": 1000.0, "delta_ms": 10.0},
]
const _BUDGET_OVERRUN_MIN_DELTA_MS: float = 0.05
const _BUDGET_OVERRUN_COOLDOWN_MS: float = 1000.0
const _BUDGET_OVERRUN_DELTA_MS: float = 1.0
const _PERF_HUMAN_SUMMARY_COOLDOWN_MS: float = 1000.0

## Контракты на интерактивные операции (максимально допустимое время в мс).
const _CONTRACTS: Dictionary = {
	"ChunkManager.try_harvest_at_world": 2.0,
	"ChunkManager._on_mountain_tile_changed": 0.5,
	"ChunkManager.query_local_underground_zone": 2.0,
	"Chunk.try_mine_at": 2.0,
	"MountainRoofSystem._request_refresh": 4.0,
	"MountainRoofSystem._refresh_local_zone": 2.0,
	"MountainRoofSystem._process_cover_step": 2.0,
	"BuildingSystem.place_building": 2.0,
	"BuildingSystem.remove_building": 2.0,
	"BuildingSystem.destroy_building": 2.0,
}

## Per-frame аккумулятор: операция → время в мс. Сбрасывается каждый кадр WorldPerfMonitor.
static var _frame_operations: Dictionary = {}
static var _milestones_usec: Dictionary = {}
static var _print_gate_last_usec: Dictionary = {}
static var _print_gate_last_value_ms: Dictionary = {}
static var _budget_overrun_last_usec: Dictionary = {}
static var _budget_overrun_last_used_ms: Dictionary = {}
static var _mutex: Mutex = Mutex.new()

## Суммарные hitches за сессию.
static var _hitch_count: int = 0

static func measure(label: String, callable_fn: Callable) -> Variant:
	var started_usec: int = Time.get_ticks_usec()
	var result: Variant = callable_fn.call()
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_record(label, elapsed_ms)
	return result

static func begin() -> int:
	return Time.get_ticks_usec()

static func end(label: String, started_usec: int) -> void:
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_record(label, elapsed_ms)

static func record(label: String, elapsed_ms: float) -> void:
	_record(label, elapsed_ms)

static func report_budget_overrun(
	job_id: StringName,
	category: StringName,
	used_ms: float,
	budget_ms: float
) -> void:
	if budget_ms <= 0.0 or used_ms <= budget_ms:
		return
	var over_budget_ms: float = used_ms - budget_ms
	if over_budget_ms < _BUDGET_OVERRUN_MIN_DELTA_MS:
		return
	var offender_key: String = "%s.%s" % [String(category), String(job_id)]
	var over_budget_pct: float = (over_budget_ms / budget_ms) * 100.0
	var should_warn: bool = false
	_mutex.lock()
	should_warn = _passes_budget_overrun_cooldown_locked(offender_key, used_ms)
	_mutex.unlock()
	if should_warn:
		if _emit_budget_overrun_summary(job_id, category, used_ms, budget_ms, over_budget_pct):
			push_warning(
				"[WorldPerf] WARNING: FrameBudget overrun job_id=%s category=%s used_ms=%.2f budget_ms=%.2f over_budget_pct=%.1f"
				% [String(job_id), String(category), used_ms, budget_ms, over_budget_pct]
			)

## Zero-cost marker for milestones or other state transitions that should be
## visible in summaries without pretending to be timing data.
static func mark(label: String) -> void:
	mark_milestone(label)

## Explicit milestone helper for Boot.* state transitions.
static func mark_milestone(label: String) -> void:
	_mutex.lock()
	_milestones_usec[label] = Time.get_ticks_usec()
	_mutex.unlock()
	_record(label, 0.0)

static func has_milestone(label: String) -> bool:
	_mutex.lock()
	var has_label: bool = _milestones_usec.has(label)
	_mutex.unlock()
	return has_label

static func record_since(label: String, from_label: String) -> float:
	return _record_milestone_delta(label, from_label, Time.get_ticks_usec())

static func record_between(label: String, from_label: String, to_label: String) -> float:
	_mutex.lock()
	if not _milestones_usec.has(to_label):
		_mutex.unlock()
		return -1.0
	var end_usec: int = int(_milestones_usec[to_label])
	_mutex.unlock()
	return _record_milestone_delta(label, from_label, end_usec)

static func _record_milestone_delta(label: String, from_label: String, end_usec: int) -> float:
	_mutex.lock()
	if not _milestones_usec.has(from_label):
		_mutex.unlock()
		return -1.0
	var started_usec: int = int(_milestones_usec[from_label])
	_mutex.unlock()
	if started_usec <= 0 or end_usec < started_usec:
		return -1.0
	var elapsed_ms: float = float(end_usec - started_usec) / 1000.0
	_record(label, elapsed_ms)
	return elapsed_ms

static func _record(label: String, elapsed_ms: float) -> void:
	var contract_key: String = _extract_contract_key(label)
	var should_print: bool = false
	_mutex.lock()
	should_print = _should_print_record_locked(label, elapsed_ms)
	_frame_operations[label] = _frame_operations.get(label, 0.0) + elapsed_ms
	_mutex.unlock()
	var emitted_summary: bool = false
	if _CONTRACTS.has(contract_key):
		var limit: float = _CONTRACTS[contract_key]
		if elapsed_ms > limit:
			emitted_summary = _emit_contract_overrun_summary(label, elapsed_ms, limit)
			if emitted_summary:
				push_warning("[WorldPerf] WARNING: %s took %.2f ms (contract: %.1f ms)" % [label, elapsed_ms, limit])
	if should_print:
		if not emitted_summary:
			_emit_threshold_timing_summary(label, elapsed_ms)
		print("[WorldPerf] %s: %.2f ms" % [label, elapsed_ms])

static func _emit_budget_overrun_summary(
	job_id: StringName,
	category: StringName,
	used_ms: float,
	budget_ms: float,
	over_budget_pct: float
) -> bool:
	var record: Dictionary = {
		"actor": "world_perf_probe",
		"actor_human": "Мировой перф-зонд",
		"action": "budget_overrun",
		"action_human": "зафиксировал перерасход фонового бюджета",
		"target": "%s.%s" % [String(category), String(job_id)],
		"target_human": "фоновая задача %s в категории %s" % [String(job_id), String(category)],
		"reason": "budget_exceeded",
		"reason_human": "шаг занял %.2f ms при лимите %.2f ms, перерасход %.1f%%" % [used_ms, budget_ms, over_budget_pct],
		"impact": String(WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT),
		"state": "over_budget",
		"state_human": "вышел за бюджет",
		"severity": String(WorldRuntimeDiagnosticLog.SEVERITY_DIAGNOSTIC),
		"severity_human": WorldRuntimeDiagnosticLog.humanize_severity(WorldRuntimeDiagnosticLog.SEVERITY_DIAGNOSTIC),
	}
	return WorldRuntimeDiagnosticLog.emit_summary(
		record,
		WorldRuntimeDiagnosticLog.PERF_PREFIX,
		{"cooldown_ms": _PERF_HUMAN_SUMMARY_COOLDOWN_MS}
	)

static func _emit_contract_overrun_summary(label: String, elapsed_ms: float, limit: float) -> bool:
	var impact_key: StringName = _resolve_perf_impact_key(label)
	var record: Dictionary = {
		"actor": "world_perf_probe",
		"actor_human": "Мировой перф-зонд",
		"action": "contract_overrun",
		"action_human": "зафиксировал превышение временного контракта",
		"target": _extract_contract_key(label),
		"target_human": WorldRuntimeDiagnosticLog.describe_perf_label(label),
		"reason": "contract_exceeded",
		"reason_human": "операция заняла %.2f ms при согласованном лимите %.1f ms" % [elapsed_ms, limit],
		"impact": String(impact_key),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact_key),
		"state": "slow",
		"state_human": "идёт медленнее контракта",
		"severity": String(WorldRuntimeDiagnosticLog.SEVERITY_DIAGNOSTIC),
		"severity_human": WorldRuntimeDiagnosticLog.humanize_severity(WorldRuntimeDiagnosticLog.SEVERITY_DIAGNOSTIC),
	}
	return WorldRuntimeDiagnosticLog.emit_summary(
		record,
		WorldRuntimeDiagnosticLog.PERF_PREFIX,
		{"cooldown_ms": _PERF_HUMAN_SUMMARY_COOLDOWN_MS}
	)

static func _emit_threshold_timing_summary(label: String, elapsed_ms: float) -> bool:
	var impact_key: StringName = _resolve_perf_impact_key(label)
	var record: Dictionary = {
		"actor": "world_perf_probe",
		"actor_human": "Мировой перф-зонд",
		"action": "timing_threshold",
		"action_human": "зафиксировал заметный по времени шаг",
		"target": label,
		"target_human": WorldRuntimeDiagnosticLog.describe_perf_label(label),
		"reason": "print_threshold_exceeded",
		"reason_human": "замер превысил порог вывода в лог и требует внимания: %.2f ms" % elapsed_ms,
		"impact": String(impact_key),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact_key),
		"state": "observed",
		"state_human": "наблюдается всплеск",
		"severity": String(WorldRuntimeDiagnosticLog.SEVERITY_DIAGNOSTIC),
		"severity_human": WorldRuntimeDiagnosticLog.humanize_severity(WorldRuntimeDiagnosticLog.SEVERITY_DIAGNOSTIC),
	}
	return WorldRuntimeDiagnosticLog.emit_summary(
		record,
		WorldRuntimeDiagnosticLog.PERF_PREFIX,
		{"cooldown_ms": _PERF_HUMAN_SUMMARY_COOLDOWN_MS}
	)

static func _resolve_perf_impact_key(label: String) -> StringName:
	var contract_key: String = _extract_contract_key(label)
	if contract_key == "ChunkManager.try_harvest_at_world" \
		or contract_key == "Chunk.try_mine_at" \
		or contract_key.begins_with("BuildingSystem."):
		return WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE
	if contract_key.begins_with("MountainRoofSystem.") \
		or contract_key.begins_with("FrameBudgetDispatcher.") \
		or contract_key.begins_with("ChunkManager.streaming_redraw") \
		or contract_key.begins_with("ChunkStreaming.") \
		or contract_key.begins_with("stream.") \
		or contract_key.begins_with("Scheduler.") \
		or contract_key.begins_with("scheduler."):
		return WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT
	return WorldRuntimeDiagnosticLog.IMPACT_INFORMATIONAL

static func _should_print_record_locked(label: String, elapsed_ms: float) -> bool:
	if elapsed_ms <= 0.0:
		return false
	for prefix: String in _SUPPRESSED_PRINT_PREFIXES:
		if label.begins_with(prefix):
			return false
	if elapsed_ms < _resolve_print_threshold_ms(label):
		return false
	return _passes_print_cooldown_locked(label, elapsed_ms)

static func _resolve_print_threshold_ms(label: String) -> float:
	for rule: Dictionary in _PRINT_THRESHOLD_OVERRIDES:
		var prefix: String = str(rule.get("prefix", ""))
		if prefix != "" and label.begins_with(prefix):
			return float(rule.get("threshold_ms", _DEFAULT_PRINT_THRESHOLD_MS))
	return _DEFAULT_PRINT_THRESHOLD_MS

static func _passes_print_cooldown_locked(label: String, elapsed_ms: float) -> bool:
	for rule: Dictionary in _PRINT_COOLDOWN_OVERRIDES:
		var prefix: String = str(rule.get("prefix", ""))
		if prefix == "" or not label.begins_with(prefix):
			continue
		var gate_key: String = prefix
		var now_usec: int = Time.get_ticks_usec()
		var cooldown_ms: float = float(rule.get("cooldown_ms", 0.0))
		var delta_ms: float = float(rule.get("delta_ms", 0.0))
		var last_usec: int = int(_print_gate_last_usec.get(gate_key, 0))
		var last_value_ms: float = float(_print_gate_last_value_ms.get(gate_key, -1.0))
		var should_print: bool = last_usec <= 0
		if not should_print and cooldown_ms > 0.0:
			should_print = float(now_usec - last_usec) / 1000.0 >= cooldown_ms
		if not should_print and delta_ms > 0.0:
			should_print = elapsed_ms >= last_value_ms + delta_ms
		if should_print:
			_print_gate_last_usec[gate_key] = now_usec
			_print_gate_last_value_ms[gate_key] = elapsed_ms
		return should_print
	return true

static func _passes_budget_overrun_cooldown_locked(offender_key: String, used_ms: float) -> bool:
	var now_usec: int = Time.get_ticks_usec()
	var last_usec: int = int(_budget_overrun_last_usec.get(offender_key, 0))
	var last_used_ms: float = float(_budget_overrun_last_used_ms.get(offender_key, -1.0))
	var should_warn: bool = last_usec <= 0
	if not should_warn:
		should_warn = float(now_usec - last_usec) / 1000.0 >= _BUDGET_OVERRUN_COOLDOWN_MS
	if not should_warn and last_used_ms >= 0.0:
		should_warn = used_ms >= last_used_ms + _BUDGET_OVERRUN_DELTA_MS
	if should_warn:
		_budget_overrun_last_usec[offender_key] = now_usec
		_budget_overrun_last_used_ms[offender_key] = used_ms
	return should_warn

## Извлекает ключ контракта из label (отбрасывает параметры вроде chunk coord).
static func _extract_contract_key(label: String) -> String:
	for key: String in _CONTRACTS:
		if label.begins_with(key):
			return key
	return label

## Возвращает и очищает per-frame данные. Вызывается WorldPerfMonitor раз в кадр.
static func flush_frame() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = _frame_operations.duplicate()
	_frame_operations.clear()
	_mutex.unlock()
	return result
