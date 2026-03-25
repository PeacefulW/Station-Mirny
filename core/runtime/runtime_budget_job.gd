class_name RuntimeBudgetJob
extends RefCounted

## Явное описание budgeted background/presentation job.

const RuntimeWorkTypes = preload("res://core/runtime/runtime_work_types.gd")

var job_id: StringName = &""
var category: StringName = &""
var budget_ms: float = 0.0
var tick_callable: Callable = Callable()
var cadence_kind: int = RuntimeWorkTypes.CadenceKind.BACKGROUND
var threading_role: int = RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY
var authoritative: bool = false
var debug_name: String = ""

func setup(
	new_job_id: StringName,
	new_category: StringName,
	new_budget_ms: float,
	new_tick_callable: Callable,
	new_cadence_kind: int = RuntimeWorkTypes.CadenceKind.BACKGROUND,
	new_threading_role: int = RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
	new_authoritative: bool = false,
	new_debug_name: String = ""
) -> RuntimeBudgetJob:
	job_id = new_job_id
	category = new_category
	budget_ms = new_budget_ms
	tick_callable = new_tick_callable
	cadence_kind = new_cadence_kind
	threading_role = new_threading_role
	authoritative = new_authoritative
	debug_name = new_debug_name
	return self

func is_valid() -> bool:
	return not job_id.is_empty() \
		and RuntimeWorkTypes.is_supported_budget_category(category) \
		and budget_ms > 0.0 \
		and tick_callable.is_valid()

func get_effective_name() -> String:
	if not debug_name.is_empty():
		return debug_name
	return str(job_id)
