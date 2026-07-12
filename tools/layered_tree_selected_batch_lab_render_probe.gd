extends SceneTree

const LAB_SCENE: PackedScene = preload("res://scenes/dev/layered_tree_asset_lab_scene.tscn")
const ASSET_ROOT: String = "res://artifacts/layered_tree_10_oclock_fill_20_batch/candidates"
const OUTPUT_DIR: String = "res://artifacts/layered_tree_10_oclock_fill_20_batch/lab"
const VIEWPORT_SIZE: Vector2i = Vector2i(1024, 768)

var _snapshots: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEWPORT_SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for tree_index: int in range(1, 7):
		var tree_id: String = "tree_%02d" % tree_index
		await _capture(tree_id, 0.0, "summer")
		await _capture(tree_id, 1.0, "winter")
	var report := FileAccess.open("%s/snapshots.json" % OUTPUT_DIR, FileAccess.WRITE)
	report.store_string(JSON.stringify(_snapshots, "\t"))
	report.close()
	print("layered_tree_selected_batch_lab_render_probe: wrote %d captures" % _snapshots.size())
	quit(0)


func _capture(tree_id: String, season_amount: float, state_name: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var scene: Node = LAB_SCENE.instantiate()
	scene.set("tree_dir", "%s/%s" % [ASSET_ROOT, tree_id])
	scene.set("shadow_texture_override", "")
	viewport.add_child(scene)
	for _frame: int in range(8):
		await process_frame
	scene.call("set_debug_wind_strength_px", 0.0)
	scene.call("set_debug_shadow_hour", 14.5)
	scene.call("set_debug_winter_state", season_amount)
	for _frame: int in range(8):
		await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image: Image = viewport.get_texture().get_image()
	var label: String = "%s_%s" % [tree_id, state_name]
	var path: String = "%s/%s.png" % [OUTPUT_DIR, label]
	image.save_png(ProjectSettings.globalize_path(path))
	var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	snapshot["capture"] = label
	snapshot["tree_id"] = tree_id
	snapshot["state"] = state_name
	snapshot["path"] = ProjectSettings.globalize_path(path)
	_snapshots.append(snapshot)
	viewport.queue_free()
	await process_frame
	await process_frame
