extends SceneTree

const LAB_SCENE_PATH: String = "res://scenes/dev/object_torch_shadow_lab_scene.tscn"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(LAB_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Object torch shadow lab scene must load.")
	if packed_scene == null:
		quit(1)
		return

	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_assert(scene.has_method("get_debug_snapshot"), "Lab scene must expose a debug snapshot.")
	_assert(scene.has_method("set_lab_torch_enabled"), "Lab scene must expose torch toggle API.")
	_assert(scene.has_method("set_lab_hour"), "Lab scene must expose time override API.")
	_assert(scene.has_method("cycle_lab_time"), "Lab scene must expose time cycling API.")
	_assert(scene.has_method("get_mountain_torch_shadow_field_mask"), "Lab scene must serve mountain torch masks.")

	scene.call("set_lab_torch_enabled", true)
	scene.call("set_lab_hour", 23.0)
	await process_frame

	var snapshot: Dictionary = scene.call("get_debug_snapshot") as Dictionary
	_assert(bool(snapshot.get("ready", false)), "Lab scene must become ready.")
	_assert(bool(snapshot.get("chunk_view_ready", false)), "Lab scene must build a ChunkView.")
	_assert(bool(snapshot.get("mountain_ready", false)), "Lab scene must build a visible mountain.")
	_assert(int(snapshot.get("mountain_solid_pixels", 0)) > 0, "Lab mountain mask must contain solid pixels.")
	_assert(bool(snapshot.get("mountain_torch_field_ready", false)), "Lab scene must create MountainTorchShadowField.")
	_assert(int(snapshot.get("tree_count", 0)) >= 2, "Lab scene must place at least two trees.")
	_assert(int(snapshot.get("rock_count", 0)) >= 3, "Lab scene must place several rocks.")
	_assert(int(snapshot.get("big_rock_count", 0)) >= 1, "Lab scene must place at least one big rock.")
	_assert(bool(snapshot.get("player_ready", false)), "Lab scene must place a player.")
	_assert(bool(snapshot.get("torch_ready", false)), "Lab scene must expose the player's torch.")
	_assert(bool(snapshot.get("torch_enabled", false)), "Lab torch toggle API must enable the torch.")
	_assert(absf(float(snapshot.get("current_hour", -1.0)) - 23.0) < 0.1, "Lab time API must set night hour.")
	_assert(bool(snapshot.get("daylight_ready", false)), "Lab scene must create the daylight system.")
	_assert(bool(snapshot.get("hud_ready", false)), "Lab scene must create its HUD.")
	await _assert_player_can_move(scene)

	var mask: Dictionary = scene.call(
		"get_mountain_torch_shadow_field_mask",
		Vector2(512.0, 620.0),
		360.0
	) as Dictionary
	_assert(bool(mask.get("ready", false)), "Lab mountain mask provider must return ready.")
	_assert(int(mask.get("solid_sample_count", 0)) > 0, "Lab mountain mask provider must expose solid samples.")
	_assert(int(mask.get("width", 0)) > 0 and int(mask.get("height", 0)) > 0, "Lab mask provider must expose dimensions.")

	scene.queue_free()
	await process_frame
	if _failed:
		quit(1)
		return
	print("object_torch_shadow_lab_scene_smoke_test: OK")
	quit(0)


func _assert_player_can_move(scene: Node) -> void:
	var player: Node2D = scene.get_node_or_null("LabPlayer") as Node2D
	_assert(player != null, "Lab player must be reachable by name.")
	if player == null:
		return
	var before: Vector2 = player.global_position
	_assert(InputMap.has_action("move_right"), "move_right input action must exist.")
	Input.action_press("move_right")
	var held_input: Vector2 = Vector2.ZERO
	var held_velocity: Vector2 = Vector2.ZERO
	var held_action: bool = false
	var held_state: String = ""
	var has_balance: bool = false
	for _i: int in range(12):
		await physics_frame
		if _i == 3:
			held_action = Input.is_action_pressed("move_right")
			if player.has_method("get_move_input"):
				held_input = player.call("get_move_input") as Vector2
			held_velocity = player.get("velocity") as Vector2
			has_balance = player.get("balance") != null
			var state_machine: Variant = player.get("_state_machine")
			if state_machine != null and state_machine.has_method("get_current_state_name"):
				held_state = str(state_machine.call("get_current_state_name"))
	Input.action_release("move_right")
	await physics_frame
	var after: Vector2 = player.global_position
	_assert(
		after.x > before.x + 8.0,
		"Lab player must move when move_right is pressed. before=%s after=%s held_input=%s held_velocity=%s held_action=%s state=%s balance=%s" % [
			str(before),
			str(after),
			str(held_input),
			str(held_velocity),
			str(held_action),
			held_state,
			str(has_balance),
		],
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
