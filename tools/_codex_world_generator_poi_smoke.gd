extends SceneTree

func _initialize() -> void:
	call_deferred("_run_validation")

func _run_validation() -> void:
	var world_generator: Node = get_root().get_node_or_null("WorldGenerator")
	if world_generator == null:
		push_error("WorldGenerator autoload missing")
		quit(1)
		return
	world_generator.call("initialize_world", 123456)
	var placements: Array = world_generator.call("_resolve_poi_placement_decisions", Vector2i(10, 10)) as Array
	print("[CodexWorldGeneratorPoiSmoke] placements=%d" % placements.size())
	quit(0)
