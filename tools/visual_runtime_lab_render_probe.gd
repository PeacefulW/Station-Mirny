extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/visual_runtime_lab_scene.tscn"
const CAPTURE_PATH: String = "user://visual_runtime_lab_capture.png"
const ZONE_CAPTURE_PATH: String = "user://visual_runtime_lab_zone_capture.png"
const MAX_READY_MSEC: int = 210000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Visual runtime lab render probe could not load the scene.")
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var snapshot: Dictionary = {}
	var deadline_msec: int = Time.get_ticks_msec() + MAX_READY_MSEC
	while Time.get_ticks_msec() < deadline_msec:
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("failed", false)) or bool(snapshot.get("ready", false)):
			break
	if not bool(snapshot.get("ready", false)):
		push_error("Visual runtime lab render probe timed out: %s" % str(snapshot))
		scene.queue_free()
		await process_frame
		quit(1)
		return
	var runtime: Node = scene.get_node_or_null("WorldRuntimeV0")
	for _frame: int in range(180):
		await process_frame
		if runtime != null and runtime.get_node_or_null("InitialLoadingScreen") == null:
			break
	for _frame: int in range(8):
		await process_frame
	var capture: Image = root.get_texture().get_image()
	var save_error: Error = capture.save_png(CAPTURE_PATH)
	if save_error != OK:
		push_error("Visual runtime lab render probe could not save the capture.")
		scene.queue_free()
		await process_frame
		quit(1)
		return
	scene.call("debug_set_zone_overlay", true)
	Input.warp_mouse(Vector2(706.0, 158.0))
	var shift_event: InputEventKey = InputEventKey.new()
	shift_event.keycode = KEY_SHIFT
	shift_event.physical_keycode = KEY_SHIFT
	shift_event.pressed = true
	Input.parse_input_event(shift_event)
	for _frame: int in range(12):
		await process_frame
	var tooltip_snapshot: Dictionary = (
		scene.call("get_debug_snapshot") as Dictionary
	).get("shift_tooltip", {}) as Dictionary
	var tooltip_text: String = String(tooltip_snapshot.get("text", ""))
	if not bool(tooltip_snapshot.get("visible", false)) \
			or not tooltip_text.contains("rock_top_albedo.png") \
			or not tooltip_text.contains("foothill_albedo.png"):
		push_error(
			"Shift texture tooltip did not expose an applied texture: %s"
			% str(tooltip_snapshot)
		)
		shift_event.pressed = false
		Input.parse_input_event(shift_event)
		scene.queue_free()
		await process_frame
		quit(1)
		return
	var zone_capture: Image = root.get_texture().get_image()
	var zone_save_error: Error = zone_capture.save_png(ZONE_CAPTURE_PATH)
	shift_event.pressed = false
	Input.parse_input_event(shift_event)
	if zone_save_error != OK:
		push_error("Visual runtime lab render probe could not save the zone capture.")
		scene.queue_free()
		await process_frame
		quit(1)
		return
	print(
		"visual_runtime_lab_render_probe: OK normal=%s zones=%s tooltip=%s"
		% [
			ProjectSettings.globalize_path(CAPTURE_PATH),
			ProjectSettings.globalize_path(ZONE_CAPTURE_PATH),
			String(tooltip_snapshot.get("text", "")),
		]
	)
	scene.queue_free()
	await process_frame
	quit(0)
