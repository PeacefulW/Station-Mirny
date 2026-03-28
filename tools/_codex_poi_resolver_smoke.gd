extends SceneTree

const RESOLVER_SCRIPT_PATH: String = "res://core/systems/world/world_poi_resolver.gd"

func _initialize() -> void:
	call_deferred("_run_validation")

func _run_validation() -> void:
	var registry: Node = get_root().get_node_or_null("WorldFeatureRegistry")
	var world_generator: Node = get_root().get_node_or_null("WorldGenerator")
	if registry == null or world_generator == null:
		push_error("autoloads missing")
		quit(1)
		return
	world_generator.call("initialize_world", 123456)
	var ctx: Variant = world_generator.get("_compute_context")
	var resolver_script: GDScript = load(RESOLVER_SCRIPT_PATH) as GDScript
	if ctx == null or resolver_script == null:
		push_error("ctx or resolver missing")
		quit(1)
		return
	var poi: Resource = registry.call("get_poi_by_id", &"base:test_poi") as Resource
	if poi == null:
		push_error("poi missing")
		quit(1)
		return
	var resolved_hook_ids: Array[StringName] = resolver_script._collect_resolved_hook_ids([{"hook_id": &"base:test_feature"}])
	var matches: bool = resolver_script._matches_required_feature_hooks(poi, resolved_hook_ids)
	print("[CodexPoiResolverSmoke] matches=%s" % str(matches))
	var candidate: Dictionary = resolver_script._build_candidate(Vector2i(10, 10), poi, ctx)
	print("[CodexPoiResolverSmoke] candidate_keys=%d" % candidate.size())
	quit(0)
