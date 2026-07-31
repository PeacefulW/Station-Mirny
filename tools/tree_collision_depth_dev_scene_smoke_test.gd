extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dev_scene: PackedScene = load(
		"res://scenes/dev/tree_collision_depth_dev_scene.tscn",
	) as PackedScene
	_expect(dev_scene != null, "dev scene must load after autoload initialization")
	if dev_scene == null:
		_finish()
		return
	var scene: Node = dev_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	_expect(bool(snapshot.get("ready", false)), "dev scene must finish native setup")
	for key: String in [
		"variant_count",
		"player_count",
		"player_collision_count",
		"tree_collider_count",
		"active_collision_layer_count",
		"native_layer_count",
		"base_alignment_count",
		"authored_footprint_count",
		"rear_order_pass_count",
		"tree_overlay_count",
		"player_overlay_count",
	]:
		_expect(
			int(snapshot.get(key, -1)) == 8,
			"dev scene %s must cover all eight variants" % key,
		)
	var asset_dirs: Array = snapshot.get("asset_dirs", []) as Array
	_expect(asset_dirs.size() == 8, "dev scene must expose eight production asset dirs")
	scene.call("reset_players_behind_trees")
	await physics_frame
	var reset_snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	_expect(
		int(reset_snapshot.get("rear_order_pass_count", -1)) == 8,
		"reset must return every player to valid rear depth order",
	)
	scene.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("tree_collision_depth_dev_scene_smoke_test: PASS variants=8")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
