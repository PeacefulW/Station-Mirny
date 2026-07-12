extends SceneTree

const LAB_SCENE: PackedScene = preload("res://scenes/dev/layered_tree_asset_lab_scene.tscn")
const PROOF_ASSET: String = "res://artifacts/layered_tree_01_nw_winter_proof/candidate_v3_physical"
const OUTPUT_DIR: String = "res://artifacts/layered_tree_01_nw_winter_proof/lab"
const VIEWPORT_SIZE: Vector2i = Vector2i(1024, 768)

var _snapshots: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEWPORT_SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var root_dawn: Dictionary = await _capture_new_scene("root_shadow_physical_13h", 0.0, 13.0)
	var root_neutral: Dictionary = await _capture_new_scene("root_shadow_physical_14_5h", 0.0, 14.5)
	var root_dusk: Dictionary = await _capture_new_scene("root_shadow_physical_16h", 0.0, 16.0)
	_write_panel(
		[
			root_dawn.get("image") as Image,
			root_neutral.get("image") as Image,
			root_dusk.get("image") as Image,
		],
		Vector2i(341, 256),
		3,
		"root_shadow_hours_grid.png",
	)

	var summer: Dictionary = await _capture_new_scene("summer_full_foliage", 0.0)
	var early_winter: Dictionary = await _capture_new_scene("early_winter_frost_035", 0.35)
	var deep_winter: Dictionary = await _capture_new_scene("deep_winter_snow_070", 0.70)
	var full_winter: Dictionary = await _capture_new_scene("full_winter_frozen_100", 1.0)
	var thawed: Dictionary = await _capture_thaw()
	_write_panel(
		[
			summer.get("image") as Image,
			early_winter.get("image") as Image,
			deep_winter.get("image") as Image,
			full_winter.get("image") as Image,
		],
		Vector2i(512, 384),
		2,
		"full_foliage_winter_grid.png",
	)
	_write_panel(
		[full_winter.get("image") as Image, thawed.get("image") as Image],
		Vector2i(512, 384),
		2,
		"winter_thaw_reversal.png",
	)

	var report := FileAccess.open("%s/snapshots.json" % OUTPUT_DIR, FileAccess.WRITE)
	report.store_string(JSON.stringify(_snapshots, "\t"))
	report.close()
	print("layered_tree_asset_lab_render_probe: wrote %d captures" % _snapshots.size())
	quit(0)


func _capture_new_scene(
	label: String,
	season_amount: float,
	shadow_hour: float = 14.5,
) -> Dictionary:
	var scene: Node = LAB_SCENE.instantiate()
	scene.set("tree_dir", PROOF_ASSET)
	scene.set("shadow_texture_override", "")
	root.add_child(scene)
	for _frame: int in range(8):
		await process_frame
	scene.call("set_debug_wind_strength_px", 0.0)
	scene.call("set_debug_shadow_hour", shadow_hour)
	scene.call("set_debug_winter_state", season_amount)
	for _frame: int in range(8):
		await process_frame
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [OUTPUT_DIR, label]
	image.save_png(ProjectSettings.globalize_path(path))
	var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	snapshot["capture"] = label
	snapshot["path"] = ProjectSettings.globalize_path(path)
	_snapshots.append(snapshot)
	scene.queue_free()
	await process_frame
	await process_frame
	return {"image": image, "snapshot": snapshot}


func _capture_thaw() -> Dictionary:
	var scene: Node = LAB_SCENE.instantiate()
	scene.set("tree_dir", PROOF_ASSET)
	root.add_child(scene)
	for _frame: int in range(8):
		await process_frame
	scene.call("set_debug_wind_strength_px", 0.0)
	scene.call("set_debug_shadow_hour", 14.5)
	scene.call("set_debug_winter_state", 1.0)
	for _frame: int in range(6):
		await process_frame
	scene.call("set_debug_winter_state", 0.0)
	for _frame: int in range(8):
		await process_frame
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/thawed_after_full_winter.png" % OUTPUT_DIR
	image.save_png(ProjectSettings.globalize_path(path))
	var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	snapshot["capture"] = "thawed_after_full_winter"
	snapshot["path"] = ProjectSettings.globalize_path(path)
	_snapshots.append(snapshot)
	scene.queue_free()
	await process_frame
	await process_frame
	return {"image": image, "snapshot": snapshot}


func _write_panel(
	images: Array[Image],
	cell_size: Vector2i,
	columns: int,
	file_name: String,
) -> void:
	var rows: int = ceili(float(images.size()) / float(columns))
	var panel := Image.create(cell_size.x * columns, cell_size.y * rows, false, Image.FORMAT_RGBA8)
	panel.fill(Color(0.04, 0.04, 0.035, 1.0))
	for index: int in range(images.size()):
		var resized: Image = images[index].duplicate()
		resized.convert(Image.FORMAT_RGBA8)
		resized.resize(cell_size.x, cell_size.y, Image.INTERPOLATE_LANCZOS)
		var target := Vector2i((index % columns) * cell_size.x, (index / columns) * cell_size.y)
		panel.blit_rect(resized, Rect2i(Vector2i.ZERO, cell_size), target)
	panel.save_png(ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name]))
