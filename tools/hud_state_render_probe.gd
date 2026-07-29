extends SceneTree
## Рендер-проба тревожных состояний HUD: низкий кислород, урон и режим стройки.
## Обычная проба снимает только спокойный кадр, поэтому состояния, ради которых
## HUD и меняет цвет, иначе остались бы без визуального доказательства.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_PATH: String = "res://artifacts/hud_runtime/hud_runtime_alarm.png"
const MAX_READY_FRAMES: int = 3000
const PRESENTATION_SETTLE_FRAMES: int = 90


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/hud_runtime")
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)

	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("failed", false)) or bool(snapshot.get("ready", false)):
			break

	var world: Node = scene.get_node_or_null("WorldRuntimeV0")
	if world != null:
		var loading_surface: CanvasLayer = (
			world.get_node_or_null("InitialLoadingScreen") as CanvasLayer
		)
		if loading_surface != null:
			loading_surface.visible = false

	var event_bus: Node = root.get_node_or_null("EventBus")
	event_bus.emit_signal("oxygen_changed", 17.0, 100.0)
	event_bus.emit_signal("player_health_changed", 44.0, 100.0)
	event_bus.emit_signal("build_mode_changed", true)
	for _frame: int in range(PRESENTATION_SETTLE_FRAMES):
		await process_frame
	var image: Image = root.get_texture().get_image()
	if image != null:
		image.save_png(OUTPUT_PATH)
	print("hud_state_probe: OK output=%s" % OUTPUT_PATH)
	scene.queue_free()
	await process_frame
	quit(0)
