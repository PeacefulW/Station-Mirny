extends SceneTree
## Short lifecycle probe for the production world scene. It intentionally exits
## during active streaming so every owner must cancel workers, detach shared
## viewports and release render resources without relying on a ready-state path.
##
## The probe asserts the observable teardown result. Printing PASS after merely
## reaching the end of the script would report a leak regression as green.

const SETTLE_FRAMES: int = 8
const TEARDOWN_FRAMES: int = 24

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/world/world_runtime_v0.tscn") as PackedScene
	if packed == null:
		push_error("world_runtime_teardown_smoke_test: scene failed to load")
		quit(1)
		return
	var baseline_orphans: int = int(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
	)
	var baseline_nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for _frame: int in range(SETTLE_FRAMES):
		await process_frame
	_expect(is_instance_valid(scene), "world scene survives its streaming warm-up")
	scene.queue_free()
	# queue_free is deferred and owners release viewports/workers over several
	# frames; a short window would report an unfinished teardown as clean.
	for _frame: int in range(TEARDOWN_FRAMES):
		await process_frame
	_expect(
		not is_instance_valid(scene),
		"world scene instance is freed after queue_free",
	)
	var orphan_delta: int = int(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
	) - baseline_orphans
	_expect(
		orphan_delta <= 0,
		"teardown leaves no orphan nodes (delta %d)" % orphan_delta,
	)
	var node_delta: int = int(
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	) - baseline_nodes
	_expect(
		node_delta <= 0,
		"teardown returns the node count to its baseline (delta %d)" % node_delta,
	)
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("world_runtime_teardown_smoke_test: %s" % failure)
		print("world_runtime_teardown_smoke_test: FAIL")
		quit(1)
		return
	print("world_runtime_teardown_smoke_test: PASS")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
