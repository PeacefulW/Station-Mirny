extends SceneTree

# Рендерит контактку процедурных деревьев в SubViewport фиксированного размера
# (независимо от stretch окна) и сохраняет PNG.
# Windowed. Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --path . -s artifacts/tree_proc_sketch/proc_tree_sketch.gd

const CANVAS = preload("res://artifacts/tree_proc_sketch/proc_tree_canvas.gd")
const OUT_PATH: String = "res://artifacts/tree_proc_sketch/proc_trees_contact.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("proc_tree_sketch: must run windowed")
		quit(1)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(1800, 1240)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var canvas: Node2D = CANVAS.new()
	vp.add_child(canvas)
	root.add_child(vp)
	for _i: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	var img: Image = vp.get_texture().get_image()
	var err: int = img.save_png(OUT_PATH)
	if err != OK:
		push_error("proc_tree_sketch: save failed (err %d)" % err)
		quit(1)
		return
	print("proc_tree_sketch: saved %s (%dx%d)" % [ProjectSettings.globalize_path(OUT_PATH), img.get_width(), img.get_height()])
	print("proc_tree_sketch: DONE")
	quit(0)
