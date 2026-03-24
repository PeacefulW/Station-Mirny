class_name FrameBudgetDispatcherNode
extends Node

## Центральный диспетчер бюджета кадра для background-систем.
## Вызывает tick() каждой зарегистрированной системы в порядке приоритета.
## Следит, чтобы суммарное время не превысило общий бюджет.
## Приоритеты: streaming > topology > visual > spawn.

const TOTAL_BUDGET_MS: float = 6.0
const LOG_INTERVAL_FRAMES: int = 60

## Порядок приоритетов — первые получают бюджет раньше.
const _PRIORITY_ORDER: Array[StringName] = [&"streaming", &"topology", &"visual", &"spawn"]

var _jobs: Dictionary = {}
var _frame_count: int = 0
var _category_time_accum: Dictionary = {}

func _ready() -> void:
	name = "FrameBudgetDispatcher"
	process_priority = 100

func _process(_delta: float) -> void:
	_frame_count += 1
	var frame_start: int = Time.get_ticks_usec()
	var remaining_ms: float = TOTAL_BUDGET_MS
	for category: StringName in _PRIORITY_ORDER:
		if remaining_ms <= 0.0:
			break
		if not _jobs.has(category):
			continue
		var jobs: Array = _jobs[category] as Array
		for job: Dictionary in jobs:
			if remaining_ms <= 0.0:
				break
			var budget_ms: float = minf(job["budget_ms"] as float, remaining_ms)
			var tick_start: int = Time.get_ticks_usec()
			var callable: Callable = job["callable"] as Callable
			var has_work: bool = true
			while has_work and _elapsed_ms(tick_start) < budget_ms:
				has_work = callable.call() as bool
			var used_ms: float = _elapsed_ms(tick_start)
			remaining_ms -= used_ms
			_category_time_accum[category] = (_category_time_accum.get(category, 0.0) as float) + used_ms
	var total_used: float = _elapsed_ms(frame_start)
	WorldPerfProbe._frame_operations["FrameBudgetDispatcher.total"] = total_used
	if _frame_count % LOG_INTERVAL_FRAMES == 0:
		_print_log()
		_category_time_accum.clear()

## Регистрация системы в диспетчере.
func register_job(category: StringName, budget_ms: float, callable: Callable) -> void:
	if not _jobs.has(category):
		_jobs[category] = []
	(_jobs[category] as Array).append({
		"budget_ms": budget_ms,
		"callable": callable,
	})

## Убрать систему из диспетчера.
func unregister_job(category: StringName) -> void:
	_jobs.erase(category)

func _print_log() -> void:
	var parts: Array[String] = []
	var total: float = 0.0
	for category: StringName in _PRIORITY_ORDER:
		var avg: float = (_category_time_accum.get(category, 0.0) as float) / float(LOG_INTERVAL_FRAMES)
		total += avg
		parts.append("%s=%.1fms" % [category, avg])
	parts.append("total=%.1fms/%.1fms" % [total, TOTAL_BUDGET_MS])
	print("[FrameBudget] %s" % " ".join(parts))

func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0
