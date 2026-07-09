extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/small_rock_dev_scene.tscn"

var _failed: bool = false


func _init() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_assert(packed != null, "small rock dev scene must load.")
	if packed == null:
		_finish()
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	_assert(scene.has_method("get_debug_snapshot"), "small rock dev scene must expose debug snapshot.")
	if scene.has_method("get_debug_snapshot"):
		var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
		var layer_state: Dictionary = snapshot.get("rock_layer", {}) as Dictionary
		_assert(int(snapshot.get("instance_count", 0)) > 0, "small rock dev scene must build rock instances.")
		_assert(int(layer_state.get("instance_count", 0)) > 0, "LayeredRockObjectLayer must create visual nodes.")
		_assert(int(layer_state.get("shadow_instance_count", 0)) > 0, "LayeredRockObjectLayer must create shadow nodes.")
		_assert(not bool(layer_state.get("blocks_movement", true)), "small rock dev scene rocks must be collision-free.")
		_assert(str(snapshot.get("settings_path", "")).ends_with("plains_small_rocks.tres"), "HUD must point at plains_small_rocks.tres.")
		_assert(_first_shadow_is_below_first_rock(scene), "small rock shadow must draw below its rock visual.")
	scene.free()
	_finish()


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("small_rock_dev_scene_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true


func _first_shadow_is_below_first_rock(scene: Node) -> bool:
	var layer := scene.get_node_or_null("LayeredSmallRocks")
	if layer == null:
		return false
	var visual := layer.get_node_or_null("LayeredRockVisualRoot/LayeredRock0") as CanvasItem
	var shadow := layer.get_node_or_null("LayeredRockShadowRoot/LayeredRockShadow0") as CanvasItem
	if visual == null or shadow == null:
		return false
	return _effective_z_until(shadow, layer) < _effective_z_until(visual, layer)


func _effective_z_until(item: CanvasItem, stop_at: Node) -> int:
	var z: int = 0
	var node: Node = item
	while node != null and node != stop_at:
		if node is CanvasItem:
			var canvas_item := node as CanvasItem
			z += canvas_item.z_index
			if not canvas_item.z_as_relative:
				break
		node = node.get_parent()
	return z
