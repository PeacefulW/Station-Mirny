extends SceneTree
## Замеряет authoritative initial-loading gate настоящего WorldRuntimeV0.
## Локальная READY-фаза mountain dev probe наступает раньше готовности пузыря и
## поэтому не является метрикой загрузки чанков.
##
##     Godot --headless --path . -s tools/world_ready_time_probe.gd
##
## Печатает одну строку READY_TIME_MS=<число>, чтобы её можно было собирать
## внешним циклом при разных настройках размещения.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_READY_FRAMES: int = 20000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Dev scene must load.")
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)

	var world_scene: Node = null
	var loading_state: Dictionary = { }
	var frames: int = 0
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		frames += 1
		if world_scene == null:
			world_scene = scene.get_node_or_null("WorldRuntimeV0")
		if world_scene == null:
			continue
		loading_state = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(loading_state.get("ready", false)):
			break

	if not bool(loading_state.get("ready", false)):
		push_error("Initial chunk bubble did not become ready within %d frames." % MAX_READY_FRAMES)
		quit(1)
		return

	print("READY_TIME_MS=%d" % int(loading_state.get("elapsed_ms", -1)))
	print("READY_FRAMES=%d" % frames)
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0)
