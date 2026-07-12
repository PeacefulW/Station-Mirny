extends SceneTree
## Windowed regression proof for the detached L-shaped facade reported around
## the deterministic construction-roof mouth at (2108, 468).

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/mountain_l_artifact_probe"
const OUTPUT_PATH: String = OUTPUT_DIR + "/large_cavity_inside.png"
const MAX_READY_FRAMES: int = 3000
const MAX_SETTLE_FRAMES: int = 3000
const TARGET_MOUTH := Vector2i(2108, 468)
const PLAYER_TILE := Vector2i(2107, 467)
const DIG_MIN := Vector2i(2105, 463)
const DIG_MAX := Vector2i(2110, 468)

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_l_artifact_render_probe requires a real renderer")
		quit(1)
		return
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "construction-roof dev scene must load")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var snapshot: Dictionary = {}
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("ready", false)) or bool(snapshot.get("failed", false)):
			break
	_assert(bool(snapshot.get("ready", false)), "dev scene must become ready")
	_assert(
		snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i == TARGET_MOUTH,
		"probe must resolve the deterministic (2108, 468) mouth",
	)
	if _failed:
		await _finish(scene)
		return

	var streamer: Variant = scene.get("_streamer")
	var player: Node2D = scene.get("_player") as Node2D
	var target_mountain_id: int = int((snapshot.get("prototype", {}) as Dictionary).get("mountain_id", 0))
	_assert(streamer != null and player != null, "dev scene must expose production streamer/player")
	_assert(target_mountain_id > 0, "probe mouth must have immutable mountain ownership")
	if _failed:
		await _finish(scene)
		return
	player.global_position = WorldRuntimeConstants.tile_to_world_center(
		snapshot.get("stand_tile", TARGET_MOUTH + Vector2i.DOWN) as Vector2i,
	)
	streamer._update_player_chunk_coord()
	for _frame: int in range(MAX_SETTLE_FRAMES):
		await process_frame
		if bool(streamer._get_tile_data(
			WorldRuntimeConstants.tile_to_world_center(TARGET_MOUTH),
		).get("ready", false)):
			break
	_assert(
		bool(streamer._get_tile_data(
			WorldRuntimeConstants.tile_to_world_center(TARGET_MOUTH),
		).get("ready", false)),
		"target mouth chunk must stream before the large dig",
	)
	var camera: Camera2D = scene.get_node_or_null("WorldRuntimeV0/Player/Camera2D") as Camera2D
	_assert(camera != null, "player camera must exist")
	if camera != null:
		camera.top_level = true
		camera.global_position = WorldRuntimeConstants.tile_to_world_center(TARGET_MOUTH + Vector2i(0, -2))
		camera.reset_smoothing()
		camera.force_update_scroll()
		camera.process_mode = Node.PROCESS_MODE_DISABLED

	var dug_tiles: Array[Vector2i] = []
	var x_dig_order: Array[int] = [2108, 2107, 2109, 2106, 2110, 2105]
	for y: int in range(DIG_MAX.y, DIG_MIN.y - 1, -1):
		for x: int in x_dig_order:
			var tile := Vector2i(x, y)
			var world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(tile)
			var data: Dictionary = streamer._get_tile_data(world_pos)
			var mountain_data: Dictionary = streamer._sample_mountain_cover_tile(tile)
			if int(mountain_data.get("mountain_id", 0)) != target_mountain_id:
				continue
			var terrain_id: int = int(data.get("terrain_id", -1))
			if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
				continue
			var result: Dictionary = streamer.try_harvest_at_world(world_pos)
			_assert(bool(result.get("success", false)), "public harvest must dig %s" % str(tile))
			if bool(result.get("success", false)):
				dug_tiles.append(tile)
			if streamer._mining_feedback_layer != null:
				streamer._mining_feedback_layer.clear_feedback()
			await process_frame
	_assert(dug_tiles.size() >= 24, "large cavity fixture must dig at least 24 owned tiles")
	await _wait_native_settled(streamer)

	_assert(
		bool(scene.call("debug_place_player_for_prototype", true)),
		"dev scene must place Player inside the large cavity",
	)
	for _frame: int in range(360):
		await physics_frame
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		var prototype: Dictionary = snapshot.get("prototype", {}) as Dictionary
		var roof_debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
		var roof_state: StringName = roof_debug.get(
			"mountain_roof_reveal_transition_state",
			&"UNKNOWN",
		) as StringName
		if bool(prototype.get("inside", false)) \
				and bool(prototype.get("active_floor_reveal_active", false)) \
				and roof_state == &"OPEN" \
				and float(roof_debug.get("mountain_roof_reveal_blend", 0.0)) >= 0.999:
			break
	var inside: Dictionary = snapshot.get("prototype", {}) as Dictionary
	var final_roof_debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
	var final_roof_state: StringName = final_roof_debug.get(
		"mountain_roof_reveal_transition_state",
		&"UNKNOWN",
	) as StringName
	_assert(
		bool(inside.get("inside", false)) \
			and bool(inside.get("active_floor_reveal_active", false)) \
			and final_roof_state == &"OPEN" \
			and float(final_roof_debug.get("mountain_roof_reveal_blend", 0.0)) >= 0.999,
		"MountainResolver must select the large connected cavity",
	)
	for _frame: int in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_assert(image != null and not image.is_empty(), "probe must capture the production viewport")
	if image != null and not image.is_empty():
		DirAccess.open("res://").make_dir_recursive(OUTPUT_DIR.trim_prefix("res://"))
		_assert(image.save_png(OUTPUT_PATH) == OK, "probe screenshot must save")
	print("MOUNTAIN_L_PROBE dug=%d mountain_id=%d player=%s output=%s" % [
		dug_tiles.size(),
		target_mountain_id,
		str(PLAYER_TILE),
		OUTPUT_PATH,
	])
	await _finish(scene)


func _wait_native_settled(streamer: Variant) -> void:
	for _frame: int in range(MAX_SETTLE_FRAMES):
		await process_frame
		var debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
		if not bool(debug.get("request_in_flight", false)) \
				and not bool(debug.get("dirty", false)) \
				and int(debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("native_mask_visual_pending_count", 0)) == 0:
			return
	_assert(false, "native mask worker/upload queues must settle")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	if not _failed:
		print("mountain_l_artifact_render_probe: OK")
	quit(1 if _failed else 0)
