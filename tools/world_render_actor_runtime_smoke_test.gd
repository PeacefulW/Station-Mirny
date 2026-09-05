extends SceneTree
## Production-scene smoke for the interactive RenderWorld contract.
##
## It proves that Player is explicitly registered as one visual proxy, its
## legacy Sprite2D/SunShadow presentation is retired only after a successful
## actor publication, and its shared body record migrates across an absolute
## 1024px render-page boundary without a SceneTree discovery scan.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_READY_FRAMES: int = 20000
const GPU_INSTANCE_STRIDE: int = 16
const PROFILE_DYNAMIC_ACTOR: int = 4
const PLAYER_FEET_OFFSET_PX: float = 38.4

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("production dev scene could not be loaded")
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)

	var world_scene: Node = null
	var loading_state: Dictionary = { }
	for _frame_index: int in range(MAX_READY_FRAMES):
		await process_frame
		if world_scene == null:
			world_scene = scene.get_node_or_null("WorldRuntimeV0")
		if world_scene == null:
			continue
		loading_state = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(loading_state.get("ready", false)):
			break
	if not bool(loading_state.get("ready", false)):
		_fail("production world did not reach its authoritative ready gate")
		await _finish(scene)
		return

	var streamer: Node = world_scene.get_node_or_null("WorldStreamer")
	var player: Node2D = world_scene.get_node_or_null("Player") as Node2D
	var renderer: Node = streamer.get("_world_render_world") as Node if streamer != null else null
	_expect(streamer != null, "WorldStreamer exists")
	_expect(player != null, "Player exists")
	_expect(renderer != null and bool(renderer.call("is_ready")), "RenderWorld is ready")
	if player == null or renderer == null:
		await _finish(scene)
		return

	for _frame_index: int in range(3):
		await physics_frame
		await process_frame

	var debug_state: Dictionary = renderer.call("get_debug_state") as Dictionary
	var proxies: Dictionary = renderer.get("_visual_proxies") as Dictionary
	var record: Dictionary = player.call("get_world_render_record") as Dictionary
	var visual: Sprite2D = player.get_node_or_null("Visual") as Sprite2D
	var sun_shadow: Sprite2D = player.get_node_or_null("SunShadow") as Sprite2D
	_expect(proxies.size() == 1, "one explicit production visual proxy is registered")
	_expect(int(debug_state.get("actor_count", 0)) == 1, "one actor record is published")
	_expect(int(debug_state.get("actor_shadow_count", 0)) == 1, "one actor shadow is published")
	_expect(int(record.get("stable_id", -1)) == 1, "Player exposes its stable render id")
	_expect(record.get("body_transform") is Transform2D, "Player publishes a world body transform")
	_expect(visual != null and not visual.visible, "legacy Player body Sprite2D is not rendered")
	_expect(
		sun_shadow != null and bool(sun_shadow.get("_external_rendering_enabled"))
				and not sun_shadow.visible,
		"legacy Player shadow is not rendered",
	)
	_expect(_count_dynamic_actor_instances(renderer) == 1, "GPU body pages contain one actor instance")

	var original_position: Vector2 = player.global_position
	var original_page_y: int = floori(
		(original_position.y + PLAYER_FEET_OFFSET_PX) / 1024.0,
	)
	var crossing_feet_y: float = float(original_page_y + 1) * 1024.0
	player.global_position.y = crossing_feet_y - 1.0 - PLAYER_FEET_OFFSET_PX
	await physics_frame
	await process_frame
	_expect(
		_actor_pages(renderer) == [original_page_y],
		"actor remains on the northern side of its nearest absolute page boundary",
	)
	player.global_position.y = crossing_feet_y + 1.0 - PLAYER_FEET_OFFSET_PX
	await physics_frame
	await process_frame
	_expect(
		_actor_pages(renderer) == [original_page_y + 1],
		"actor migrates across its nearest absolute page boundary",
	)
	_expect(_count_dynamic_actor_instances(renderer) == 1, "page migration does not duplicate the actor")
	player.global_position = original_position
	await physics_frame
	await process_frame

	await _finish(scene)


func _count_dynamic_actor_instances(renderer: Node) -> int:
	var count: int = 0
	var multimeshes: Array = renderer.get("_body_multimeshes") as Array
	for multimesh_variant: Variant in multimeshes:
		var multimesh: MultiMesh = multimesh_variant as MultiMesh
		if multimesh == null:
			continue
		var buffer: PackedFloat32Array = multimesh.buffer
		for instance_index: int in range(multimesh.instance_count):
			var profile_offset: int = instance_index * GPU_INSTANCE_STRIDE + 12
			if profile_offset < buffer.size() \
					and roundi(buffer[profile_offset]) == PROFILE_DYNAMIC_ACTOR:
				count += 1
	return count


func _actor_pages(renderer: Node) -> Array:
	return (renderer.get("_active_actor_page_ys") as Array).duplicate()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error("world_render_actor_runtime_smoke_test: %s" % message)


func _finish(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	await process_frame
	print(
		"world_render_actor_runtime_smoke_test: PASS"
				if not _failed
				else "world_render_actor_runtime_smoke_test: FAIL",
	)
	quit(1 if _failed else 0)
