extends SceneTree

const LAB_SCENE_PATH: String = "res://scenes/dev/layered_tree_asset_lab_scene.tscn"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(LAB_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Layered tree asset lab scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	_assert(scene.has_method("get_debug_snapshot"), "Layered tree lab must expose debug snapshot.")
	var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	_assert(bool(snapshot.get("ready", false)), "Layered tree lab must load tree metadata.")
	_assert(str(snapshot.get("asset", "")) == "tree_01_layered_glb", "Layered tree lab must use the generated GLB asset.")
	_assert(bool(snapshot.get("has_shadow", false)), "Layered tree lab must create shadow sprite.")
	_assert(bool(snapshot.get("has_trunk", false)), "Layered tree lab must create trunk sprite.")
	_assert(bool(snapshot.get("has_foliage", false)), "Layered tree lab must create foliage sprite.")
	_assert(bool(snapshot.get("has_snow", false)), "Layered tree lab must create snow overlay sprite.")
	_assert(float(snapshot.get("wind_strength_px", 0.0)) > 0.0, "Layered tree lab must expose nonzero foliage wind.")
	_assert(snapshot.has("season_amount"), "Layered tree lab must expose season amount.")
	_assert(absf(float(snapshot.get("season_amount", -1.0))) < 0.01, "Layered tree lab must start without winter accumulation.")
	_assert(snapshot.has("shadow_hour"), "Layered tree lab must expose baked shadow hour.")
	_assert(absf(float(snapshot.get("shadow_hour", 0.0)) - 14.5) < 0.01, "Layered tree lab must start at the neutral baked shadow hour.")
	scene.queue_free()
	await process_frame
	if _failed:
		quit(1)
		return
	print("layered_tree_asset_lab_scene_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
