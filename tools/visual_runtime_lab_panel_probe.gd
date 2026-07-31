extends SceneTree
## Снимает панель visual runtime lab, чтобы проверить, что группа ручек
## действительно появилась в UI, а не только в исходниках.
##
##     Godot_v4.7-stable_win64_console.exe --path . -s tools/visual_runtime_lab_panel_probe.gd
##
## Запускать без --headless: захват кадра требует оконного рендерера.

const LAB_SCENE_PATH: String = "res://scenes/dev/visual_runtime_lab_scene.tscn"
const OUTPUT_PATH: String = "res://artifacts/gravel_relief/lab_panel.png"
const MAX_READY_FRAMES: int = 9000
const SETTLE_FRAMES: int = 120

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("visual_runtime_lab_panel_probe requires a windowed GPU renderer.")
		quit(1)
		return
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/gravel_relief")

	var packed: PackedScene = load(LAB_SCENE_PATH) as PackedScene
	_assert(packed != null, "Lab scene must load.")
	if packed == null:
		_finish()
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)

	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("failed", false)) or bool(snapshot.get("ready", false)):
			break
	_assert(bool(snapshot.get("ready", false)), "Lab scene must become ready: %s" % snapshot)
	if not bool(snapshot.get("ready", false)):
		_finish()
		return

	for _frame: int in range(SETTLE_FRAMES):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	_assert(img != null, "Capture must return an image.")
	if img == null:
		_finish()
		return
	img.save_png(OUTPUT_PATH)
	print("LAB_PANEL_PROBE saved=%s size=%dx%d" % [OUTPUT_PATH, img.get_width(), img.get_height()])

	scene.queue_free()
	await process_frame
	_finish()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("visual_runtime_lab_panel_probe: %s" % message)


func _finish() -> void:
	if _failed:
		print("visual_runtime_lab_panel_probe: FAILED")
		quit(1)
		return
	print("visual_runtime_lab_panel_probe: OK")
	quit(0)
