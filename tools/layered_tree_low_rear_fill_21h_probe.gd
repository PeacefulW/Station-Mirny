extends SceneTree

const LAB_SCENE: PackedScene = preload("res://scenes/dev/layered_tree_asset_lab_scene.tscn")
const BASE_ASSET: String = "res://artifacts/layered_tree_brightness_variants/c_clock_10_exposure_075"
const CANDIDATE_ASSET: String = "res://artifacts/layered_tree_brightness_variants/low_rear_fill_10_oclock/candidate_08"
const OUTPUT_DIR: String = "res://artifacts/layered_tree_brightness_variants/low_rear_fill_10_oclock/lab_21h"
const VIEWPORT_SIZE: Vector2i = Vector2i(1024, 768)
const TEST_HOUR: float = 21.0
const NIGHT_AMBIENT: Color = Color(0.03, 0.035, 0.05, 1.0)

var _snapshots: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEWPORT_SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	await _capture("baseline_00_at_21h", BASE_ASSET, 0.0)
	await _capture("candidate_08_at_21h", CANDIDATE_ASSET, 8.0)

	var report := FileAccess.open("%s/snapshots.json" % OUTPUT_DIR, FileAccess.WRITE)
	report.store_string(JSON.stringify(_snapshots, "\t"))
	report.close()
	print("layered_tree_low_rear_fill_21h_probe: wrote %d captures" % _snapshots.size())
	quit(0)


func _capture(label: String, tree_dir: String, lift_percent: float) -> void:
	var scene: Node = LAB_SCENE.instantiate()
	scene.set("tree_dir", tree_dir)
	scene.set("shadow_texture_override", "")
	root.add_child(scene)
	for _frame: int in range(8):
		await process_frame
	scene.call("set_debug_wind_strength_px", 0.0)
	scene.call("set_debug_winter_state", 0.0)
	var hud: Node = scene.get_node_or_null("HudLayer")
	if hud != null:
		hud.set("visible", false)
	var shadow: CanvasItem = scene.get_node_or_null("Shadow") as CanvasItem
	if shadow != null:
		shadow.visible = false

	var daylight := CanvasModulate.new()
	daylight.name = "NightAmbient21h"
	daylight.color = NIGHT_AMBIENT
	scene.add_child(daylight)
	await process_frame
	for _frame: int in range(4):
		await process_frame

	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [OUTPUT_DIR, label]
	image.save_png(ProjectSettings.globalize_path(path))
	var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	snapshot.merge({
		"capture": label,
		"path": ProjectSettings.globalize_path(path),
		"world_hour": TEST_HOUR,
		"lift_percent": lift_percent,
		"ambient_color": [daylight.color.r, daylight.color.g, daylight.color.b, daylight.color.a],
		"direct_sun_energy": 0.0,
		"direct_sun_enabled": false,
		"sun_cast_shadow_visibility": 0.0,
		"torch_enabled": false,
		"local_light_count": 0,
	}, true)
	_snapshots.append(snapshot)
	scene.queue_free()
	await process_frame
	await process_frame
