class_name FrameBudgetDispatcherNode
extends Node

## Центральный диспетчер бюджета кадра для background-систем.
## Вызывает tick() каждой зарегистрированной системы в порядке приоритета.
## Следит, чтобы суммарное время не превысило общий бюджет.
## Приоритеты: streaming > topology > visual > spawn.

const RuntimeBudgetJob = preload("res://core/runtime/runtime_budget_job.gd")
const RuntimeWorkTypes = preload("res://core/runtime/runtime_work_types.gd")

const TOTAL_BUDGET_MS: float = 6.0
const LOG_INTERVAL_FRAMES: int = 60

## Порядок приоритетов — первые получают бюджет раньше.
const _PRIORITY_ORDER: Array[StringName] = [
	RuntimeWorkTypes.CATEGORY_STREAMING,
	RuntimeWorkTypes.CATEGORY_TOPOLOGY,
	RuntimeWorkTypes.CATEGORY_VISUAL,
	RuntimeWorkTypes.CATEGORY_SPAWN,
]

var _jobs_by_category: Dictionary = {}
var _jobs_by_id: Dictionary = {}
var _frame_count: int = 0
var _category_time_accum: Dictionary = {}
var _job_time_accum: Dictionary = {}
var _job_run_count_accum: Dictionary = {}
var _job_last_step_ms: Dictionary = {}

func _ready() -> void:
	name = "FrameBudgetDispatcher"
	process_priority = 100
	for category: StringName in RuntimeWorkTypes.supported_budget_categories():
		_jobs_by_category[category] = []

func _process(_delta: float) -> void:
	_frame_count += 1
	var frame_start: int = Time.get_ticks_usec()
	var remaining_ms: float = TOTAL_BUDGET_MS
	for category: StringName in _PRIORITY_ORDER:
		if remaining_ms <= 0.0:
			break
		var jobs: Array = (_jobs_by_category.get(category, []) as Array).duplicate()
		for job_variant: Variant in jobs:
			if remaining_ms <= 0.0:
				break
			var job: RuntimeBudgetJob = job_variant as RuntimeBudgetJob
			if not job or not job.is_valid():
				if job:
					unregister_job(job.job_id)
				continue
			var budget_ms: float = minf(job.budget_ms, remaining_ms)
			var tick_start: int = Time.get_ticks_usec()
			var has_work: bool = true
			var step_count: int = 0
			var predicted_step_ms: float = _job_last_step_ms.get(job.job_id, 0.0) as float
			while has_work:
				var elapsed_before_step: float = _elapsed_ms(tick_start)
				if elapsed_before_step >= budget_ms:
					break
				if step_count > 0 and predicted_step_ms > 0.0 and elapsed_before_step + predicted_step_ms > budget_ms:
					break
				var step_start: int = Time.get_ticks_usec()
				has_work = job.tick_callable.call() as bool
				predicted_step_ms = _elapsed_ms(step_start)
				_job_last_step_ms[job.job_id] = predicted_step_ms
				step_count += 1
			var used_ms: float = _elapsed_ms(tick_start)
			remaining_ms -= used_ms
			_category_time_accum[category] = (_category_time_accum.get(category, 0.0) as float) + used_ms
			_job_time_accum[job.job_id] = (_job_time_accum.get(job.job_id, 0.0) as float) + used_ms
			_job_run_count_accum[job.job_id] = (_job_run_count_accum.get(job.job_id, 0) as int) + 1
			WorldPerfProbe.record("FrameBudgetDispatcher.%s.%s" % [String(category), String(job.job_id)], used_ms)
			if used_ms > job.budget_ms:
				WorldPerfProbe.report_budget_overrun(job.job_id, category, used_ms, job.budget_ms)
	var total_used: float = _elapsed_ms(frame_start)
	WorldPerfProbe.record("FrameBudgetDispatcher.total", total_used)
	if _frame_count % LOG_INTERVAL_FRAMES == 0:
		_print_log()
		_category_time_accum.clear()
		_job_time_accum.clear()
		_job_run_count_accum.clear()

## Регистрация системы в диспетчере.
func register_job(
	category: StringName,
	budget_ms: float,
	callable: Callable,
	job_id: StringName = &"",
	cadence_kind: int = RuntimeWorkTypes.CadenceKind.BACKGROUND,
	threading_role: int = RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
	authoritative: bool = false,
	debug_name: String = ""
) -> StringName:
	var resolved_job_id: StringName = job_id
	if resolved_job_id.is_empty():
		resolved_job_id = StringName("%s.%d" % [String(category), (_jobs_by_category.get(category, []) as Array).size()])
	var job := RuntimeBudgetJob.new().setup(
		resolved_job_id,
		category,
		budget_ms,
		callable,
		cadence_kind,
		threading_role,
		authoritative,
		debug_name
	)
	register_job_definition(job)
	return resolved_job_id

func register_job_definition(job: RuntimeBudgetJob) -> void:
	if not job or not job.is_valid():
		push_error("FrameBudgetDispatcher: invalid job registration")
		return
	if not RuntimeWorkTypes.is_supported_budget_category(job.category):
		push_error("FrameBudgetDispatcher: unsupported category %s" % String(job.category))
		return
	if _jobs_by_id.has(job.job_id):
		unregister_job(job.job_id)
	(_jobs_by_category[job.category] as Array).append(job)
	_jobs_by_id[job.job_id] = job

## Убрать систему из диспетчера.
func unregister_job(identifier: StringName) -> void:
	if _jobs_by_id.has(identifier):
		var job: RuntimeBudgetJob = _jobs_by_id[identifier] as RuntimeBudgetJob
		_jobs_by_id.erase(identifier)
		_job_last_step_ms.erase(identifier)
		if job and _jobs_by_category.has(job.category):
			var jobs: Array = _jobs_by_category[job.category] as Array
			for idx: int in range(jobs.size() - 1, -1, -1):
				var existing: RuntimeBudgetJob = jobs[idx] as RuntimeBudgetJob
				if existing and existing.job_id == identifier:
					jobs.remove_at(idx)
		return
	if RuntimeWorkTypes.is_supported_budget_category(identifier):
		var jobs_for_category: Array = _jobs_by_category.get(identifier, []) as Array
		for job_variant: Variant in jobs_for_category:
			var category_job: RuntimeBudgetJob = job_variant as RuntimeBudgetJob
			if category_job:
				_jobs_by_id.erase(category_job.job_id)
				_job_last_step_ms.erase(category_job.job_id)
		_jobs_by_category[identifier] = []

func get_supported_categories() -> Array[StringName]:
	return RuntimeWorkTypes.supported_budget_categories()

func describe_registered_jobs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for category: StringName in _PRIORITY_ORDER:
		var jobs: Array = _jobs_by_category.get(category, []) as Array
		for job_variant: Variant in jobs:
			var job: RuntimeBudgetJob = job_variant as RuntimeBudgetJob
			if not job:
				continue
			result.append({
				"job_id": String(job.job_id),
				"category": String(job.category),
				"budget_ms": job.budget_ms,
				"cadence_kind": RuntimeWorkTypes.cadence_name(job.cadence_kind),
				"threading_role": RuntimeWorkTypes.threading_role_name(job.threading_role),
				"authoritative": job.authoritative,
				"debug_name": job.get_effective_name(),
			})
	return result

func _print_log() -> void:
	if not OS.is_debug_build():
		return
	var parts: Array[String] = []
	var total: float = 0.0
	for category: StringName in _PRIORITY_ORDER:
		var avg: float = (_category_time_accum.get(category, 0.0) as float) / float(LOG_INTERVAL_FRAMES)
		total += avg
		parts.append("%s=%.1fms" % [category, avg])
	parts.append("total=%.1fms/%.1fms" % [total, TOTAL_BUDGET_MS])
	for job_id: StringName in _job_time_accum:
		var job_avg: float = (_job_time_accum[job_id] as float) / float(LOG_INTERVAL_FRAMES)
		var runs: int = _job_run_count_accum.get(job_id, 0) as int
		parts.append("%s=%.1fms(%d)" % [String(job_id), job_avg, runs])
	print("[FrameBudget] %s" % " ".join(parts))

func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0
