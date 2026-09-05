extends SceneTree
## Verifies the seamless-presentation contract while the player moves.
##
## Two independent failure modes are checked every frame:
##   1. pop      - a chunk is visible while one of its presentation layers
##                 (mountain mask, shoreline mask, objects, grass) is still
##                 arriving, which the player would see appear;
##   2. hole     - a chunk inside the visible envelope stays hidden for longer
##                 than the reveal budget, which the player would see as an
##                 empty square.
##
## Both must be zero. A stricter reveal gate that trades pops for holes is not
## an improvement, so neither number may be read without the other.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_STARTUP_FRAMES: int = 20000
const PLAYER_SPEED_PX_PER_SECOND: float = 320.0
const DEFAULT_ROUTE_SECONDS: int = 60
const TARGET_FPS: int = 60
const MAX_ZOOM_OUT: float = 0.2
## A chunk entering the visible envelope was already prepared in the reserve
## ring, so it may never need catch-up time once it is on screen.
const REVEAL_BUDGET_FRAMES: int = 1
## The very first route frames still carry the startup transition; the honest
## loading gate owns that window, so steady-state holes are counted after it.
const SETTLE_FRAMES: int = 60

var _failed: bool = false
var _route_seconds: int = DEFAULT_ROUTE_SECONDS


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_apply_command_line_overrides()
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	if packed_scene == null:
		printerr("SEAMLESS: dev scene failed to load")
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)

	var world_scene: Node = null
	var streamer: Node = null
	var player: Node2D = null
	var camera: Camera2D = null
	var loading_state: Dictionary = { }
	for _frame_index: int in range(MAX_STARTUP_FRAMES):
		await process_frame
		if world_scene == null:
			world_scene = scene.get_node_or_null("WorldRuntimeV0")
			if world_scene != null:
				streamer = world_scene.get_node_or_null("WorldStreamer")
				player = world_scene.get_node_or_null("Player") as Node2D
		if camera == null:
			camera = root.get_viewport().get_camera_2d()
		if camera != null:
			camera.set("_target_zoom", MAX_ZOOM_OUT)
			camera.zoom = Vector2(MAX_ZOOM_OUT, MAX_ZOOM_OUT)
		if world_scene == null or streamer == null or player == null:
			continue
		loading_state = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(loading_state.get("presented", false)):
			break
	if not bool(loading_state.get("presented", false)):
		printerr("SEAMLESS: initial loading gate never presented")
		await _finish(scene, 1)
		return

	Engine.max_fps = TARGET_FPS
	var start_position: Vector2 = player.global_position
	var route_frames: int = _route_seconds * TARGET_FPS
	var step_px: float = PLAYER_SPEED_PX_PER_SECOND / float(TARGET_FPS)

	var pop_samples: int = 0
	var hole_samples: int = 0
	var newly_visible_chunks: int = 0
	var boundary_crossings: int = 0
	var hidden_since_frame: Dictionary = { }
	var seen_visible: Dictionary = { }
	var failures: Array[String] = []
	var blocking_layer_counts: Dictionary = { }
	var queue_peaks: Dictionary = { }
	var previous_player_chunk: Vector2i = Vector2i(1 << 30, 1 << 30)

	for frame_index: int in range(route_frames):
		camera.set("_target_zoom", MAX_ZOOM_OUT)
		camera.zoom = Vector2(MAX_ZOOM_OUT, MAX_ZOOM_OUT)
		# North is the honest dense-world route for this seed. The old southbound
		# route crossed the mountain biome whose lower object density made both the
		# render and streaming result look better than normal forest traversal.
		player.global_position = start_position \
				+ Vector2(0.0, -step_px * float(frame_index + 1))
		await process_frame

		var hud: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary
		var player_chunk: Vector2i = hud.get("player_chunk", previous_player_chunk) as Vector2i
		if player_chunk != previous_player_chunk:
			boundary_crossings += 1
			previous_player_chunk = player_chunk
		_track_queue_peaks(queue_peaks, hud)

		var chunk_views: Dictionary = streamer.get("_chunk_views") as Dictionary
		var visible_coords: Array[Vector2i] = _get_coord_array(
			streamer,
			"_desired_visible_chunk_coords",
		)
		for chunk_coord: Vector2i in visible_coords:
			var view: Node = chunk_views.get(chunk_coord, null) as Node
			var is_visible: bool = view != null \
					and is_instance_valid(view) \
					and bool(view.get("visible"))
			if not is_visible:
				# Any chunk inside the visible envelope that is not on screen is a
				# hole the player can see, whether it is arriving for the first
				# time or went dark again. Excusing first entry here would hide
				# exactly the leading-edge defect this probe exists to catch.
				if not hidden_since_frame.has(chunk_coord):
					hidden_since_frame[chunk_coord] = frame_index
				if frame_index >= SETTLE_FRAMES \
						and frame_index - int(hidden_since_frame[chunk_coord]) \
								>= REVEAL_BUDGET_FRAMES:
					hole_samples += 1
					var blocking: String = "no_view"
					if view != null and is_instance_valid(view):
						var pending: Array[String] = _incomplete_layers(view)
						blocking = "ready" if pending.is_empty() else ",".join(pending)
						blocking_layer_counts[blocking] = int(
							blocking_layer_counts.get(blocking, 0),
						) + 1
					else:
						blocking_layer_counts[blocking] = int(
							blocking_layer_counts.get(blocking, 0),
						) + 1
					if failures.size() < 10:
						failures.append(
							"frame=%d hole chunk=%s hidden_for=%d first_entry=%s blocked_by=%s diagnostics=%s"
							% [
								frame_index,
								str(chunk_coord),
								frame_index - int(hidden_since_frame[chunk_coord]),
								str(not seen_visible.has(chunk_coord)),
								blocking,
								_describe_hole(streamer, view, chunk_coord),
							],
						)
				continue
			hidden_since_frame.erase(chunk_coord)
			if not seen_visible.has(chunk_coord):
				seen_visible[chunk_coord] = true
				newly_visible_chunks += 1
			var incomplete: Array[String] = _incomplete_layers(view)
			if not incomplete.is_empty():
				pop_samples += 1
				if failures.size() < 10:
					failures.append(
						"frame=%d pop chunk=%s layers=%s"
						% [frame_index, str(chunk_coord), ",".join(incomplete)],
					)

	_assert(boundary_crossings >= 2, "Route must cross at least two chunk boundaries.")
	_assert(newly_visible_chunks > 0, "Route must reveal new chunks.")
	_assert(
		pop_samples == 0,
		"No chunk may be visible while a presentation layer is still arriving.",
	)
	_assert(
		hole_samples == 0,
		"No presented chunk may go dark inside the visible envelope.",
	)

	if not _failed:
		print(
			"world_seamless_presentation_probe: OK seconds=%d boundaries=%d new_visible=%d pop=%d hole=%d"
			% [
				_route_seconds,
				boundary_crossings,
				newly_visible_chunks,
				pop_samples,
				hole_samples,
			],
		)
	else:
		printerr("  hole blockers: %s" % JSON.stringify(blocking_layer_counts))
		printerr("  pipeline peaks: %s" % JSON.stringify(queue_peaks))
		for failure: String in failures:
			printerr("  %s" % failure)
	await _finish(scene, 1 if _failed else 0)


## Peak queue depth per pipeline stage tells throughput-bound apart from
## lead-bound: a stage that stays saturated is the limiter, a stage that drains
## is merely waiting on the one before it.
func _track_queue_peaks(peaks: Dictionary, hud: Dictionary) -> void:
	for key: String in [
		"object_inflight",
		"object_ready_cpu",
		"object_upload_queue",
		"object_prestage_queue",
		"object_hot_cache",
		"object_hot_cache_bytes",
		"object_warm_cache",
		"object_retire_queue",
		"object_worker_ms",
		"object_latency_ms",
		"grass_inflight",
		"grass_upload_queue",
		"publish_queue",
		"visibility_wait",
		"requested_packets",
	]:
		peaks[key] = maxf(float(peaks.get(key, 0.0)), float(hud.get(key, 0)))


func _incomplete_layers(view: Node) -> Array[String]:
	var incomplete: Array[String] = []
	if bool(view.call("is_mountain_native_mask_visual_pending")):
		incomplete.append("mountain_mask")
	if bool(view.call("is_terrain_edge_mask_visual_pending")):
		incomplete.append("terrain_edge_mask")
	if not bool(view.call("is_object_presentation_complete")):
		incomplete.append("objects")
	if not bool(view.call("is_object_blocking_presentation_ready")):
		incomplete.append("object_blockers")
	if bool(view.call("has_pending_grass_scatter_visual")):
		incomplete.append("grass")
	return incomplete


func _get_coord_array(streamer: Node, property_name: String) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var raw: Variant = streamer.get(property_name)
	if raw == null:
		return coords
	for coord_variant: Variant in raw as Array:
		coords.append(coord_variant as Vector2i)
	return coords


func _describe_hole(streamer: Node, view: Node, chunk_coord: Vector2i) -> String:
	var description: Dictionary = {
		"readiness": streamer.call(
			"_build_streaming_readiness_entry",
			chunk_coord,
			Time.get_ticks_msec(),
		),
		"mask_result_ready": not (
			streamer.get("_mountain_native_masks_by_chunk") as Dictionary
		).get(chunk_coord, { }).is_empty(),
		"mask_inflight": (
			streamer.get("_mountain_native_mask_inflight_chunks") as Dictionary
		).has(chunk_coord),
		"mask_upload_queued": (
			streamer.get("_pending_mountain_native_mask_visual_upload_set") as Dictionary
		).has(chunk_coord),
	}
	if view != null and is_instance_valid(view):
		description["mountain"] = view.call("get_mountain_native_mask_debug_state")
	return JSON.stringify(description)


func _apply_command_line_overrides() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_route_seconds = maxi(2, int(argument.trim_prefix("--seconds=").to_int()))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	printerr("SEAMLESS FAILED: %s" % message)


func _finish(scene: Node, exit_code: int) -> void:
	scene.queue_free()
	await process_frame
	quit(exit_code)
