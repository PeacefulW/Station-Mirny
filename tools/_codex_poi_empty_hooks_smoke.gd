extends SceneTree

const RESOLVER_SCRIPT_PATH: String = "res://core/systems/world/world_poi_resolver.gd"
const COMPUTE_CONTEXT_SCRIPT_PATH: String = "res://core/systems/world/world_compute_context.gd"

func _initialize() -> void:
	call_deferred("_run_validation")

func _run_validation() -> void:
	var resolver_script: GDScript = load(RESOLVER_SCRIPT_PATH) as GDScript
	var compute_context_script: GDScript = load(COMPUTE_CONTEXT_SCRIPT_PATH) as GDScript
	if resolver_script == null or compute_context_script == null:
		push_error("scripts missing")
		quit(1)
		return
	var ctx: WorldComputeContext = compute_context_script.new().configure(
		null,
		123456,
		Vector2i.ZERO,
		null,
		null,
		null,
		null,
		null,
		null,
		{},
		{},
		[]
	)
	var placements: Array[Dictionary] = resolver_script.resolve_for_origin(Vector2i(10, 10), [], ctx)
	print("[CodexPoiEmptyHooksSmoke] placements=%d" % placements.size())
	quit(0)
