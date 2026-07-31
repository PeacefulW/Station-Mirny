extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/tree_collision_depth_dev_scene.tscn"
const OUTPUT_PATH: String = "res://artifacts/tree_collision_depth_dev_probe/full.png"
const VARIANT_07_PATH: String = "res://artifacts/tree_collision_depth_dev_probe/variant_07.png"
const SETTLE_FRAMES: int = 30


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var error: Error = change_scene_to_file(SCENE_PATH)
	if error != OK:
		push_error("tree_collision_depth_dev_scene_probe: scene load failed (%d)" % error)
		quit(1)
		return
	for frame_index: int in range(SETTLE_FRAMES):
		await process_frame
	if not _save_viewport_png(OUTPUT_PATH):
		quit(1)
		return
	var scene: Node = current_scene
	var camera: Camera2D = scene.get_node_or_null("Camera2D") as Camera2D
	var hud: CanvasLayer = scene.get_node_or_null("HUD") as CanvasLayer
	if camera == null or hud == null:
		push_error("tree_collision_depth_dev_scene_probe: focus controls are unavailable")
		quit(1)
		return
	camera.position = scene.call("get_variant_focus_world_position", 6) as Vector2
	camera.zoom = Vector2.ONE * 1.2
	hud.visible = false
	for frame_index: int in range(4):
		await process_frame
	if not _save_viewport_png(VARIANT_07_PATH):
		quit(1)
		return
	print(
		"tree_collision_depth_dev_scene_probe: saved %s and %s"
		% [OUTPUT_PATH, VARIANT_07_PATH],
	)
	quit(0)


func _save_viewport_png(output_path: String) -> bool:
	var output_absolute: String = ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
	var image: Image = root.get_viewport().get_texture().get_image()
	var save_error: Error = image.save_png(output_absolute)
	if save_error == OK:
		return true
	push_error(
		"tree_collision_depth_dev_scene_probe: screenshot save failed for %s (%d)"
		% [output_path, save_error],
	)
	return false
