extends SceneTree

func _initialize() -> void:
	call_deferred("_run_validation")

func _run_validation() -> void:
	var registry: Node = get_root().get_node_or_null("WorldFeatureRegistry")
	var world_generator: Node = get_root().get_node_or_null("WorldGenerator")
	if registry == null:
		_fail("WorldFeatureRegistry autoload must exist")
		return
	if world_generator == null:
		_fail("WorldGenerator autoload must exist")
		return
	if not bool(registry.call("is_ready")):
		_fail("WorldFeatureRegistry must be ready at boot")
		return
	if registry.call("get_feature_by_id", &"base:test_feature") == null:
		_fail("base:test_feature must load through the registry")
		return
	if registry.call("get_poi_by_id", &"base:test_poi") == null:
		_fail("base:test_poi must load through the registry")
		return
	if (registry.call("get_all_feature_hooks") as Array).size() < 1:
		_fail("registry must expose at least one feature hook")
		return
	if (registry.call("get_all_pois") as Array).size() < 1:
		_fail("registry must expose at least one poi")
		return
	var poi: Resource = registry.call("get_poi_by_id", &"base:test_poi") as Resource
	if poi == null or not bool(poi.call("has_explicit_anchor_offset")):
		_fail("base:test_poi must have explicit anchor_offset")
		return
	if poi == null or not bool(poi.call("has_explicit_priority")):
		_fail("base:test_poi must have explicit priority")
		return
	world_generator.call("initialize_world", 123456)
	if not bool(registry.call("is_ready")):
		_fail("WorldFeatureRegistry must stay ready through world initialization")
		return
	print("[WorldFeatureRegistryValidation] OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	print("[WorldFeatureRegistryValidation] FAILED: %s" % message)
	quit(1)
