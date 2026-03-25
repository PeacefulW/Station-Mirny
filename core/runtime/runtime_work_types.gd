class_name RuntimeWorkTypes
extends RefCounted

## Общие runtime-классификации для background work и bounded apply.

enum CadenceKind {
	INTERACTIVE,
	NEAR_PLAYER,
	LOW_FREQUENCY,
	BACKGROUND,
	PRESENTATION,
	BOOT,
}

enum ThreadingRole {
	MAIN_THREAD_ONLY,
	WORKER_ELIGIBLE,
	COMPUTE_THEN_APPLY,
}

const CATEGORY_STREAMING: StringName = &"streaming"
const CATEGORY_TOPOLOGY: StringName = &"topology"
const CATEGORY_VISUAL: StringName = &"visual"
const CATEGORY_SPAWN: StringName = &"spawn"

const _SUPPORTED_BUDGET_CATEGORIES: Array[StringName] = [
	CATEGORY_STREAMING,
	CATEGORY_TOPOLOGY,
	CATEGORY_VISUAL,
	CATEGORY_SPAWN,
]

static func supported_budget_categories() -> Array[StringName]:
	return _SUPPORTED_BUDGET_CATEGORIES.duplicate()

static func is_supported_budget_category(category: StringName) -> bool:
	return category in _SUPPORTED_BUDGET_CATEGORIES

static func cadence_name(kind: int) -> String:
	match kind:
		CadenceKind.INTERACTIVE:
			return "interactive"
		CadenceKind.NEAR_PLAYER:
			return "near_player"
		CadenceKind.LOW_FREQUENCY:
			return "low_frequency"
		CadenceKind.BACKGROUND:
			return "background"
		CadenceKind.PRESENTATION:
			return "presentation"
		CadenceKind.BOOT:
			return "boot"
		_:
			return "unknown"

static func threading_role_name(kind: int) -> String:
	match kind:
		ThreadingRole.MAIN_THREAD_ONLY:
			return "main_thread_only"
		ThreadingRole.WORKER_ELIGIBLE:
			return "worker_eligible"
		ThreadingRole.COMPUTE_THEN_APPLY:
			return "compute_then_apply"
		_:
			return "unknown"
