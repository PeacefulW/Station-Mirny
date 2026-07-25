extends SceneTree
## Proves that camera zoom cannot influence chunk residency.
##
## Sweeps the camera across the whole allowed zoom range while standing still
## and while moving, and requires that no chunk packet is requested, no
## ChunkView is destroyed or recreated, and the resident envelope never changes
## size because of zoom. Movement-driven streaming is measured separately: the
## stationary sweep must be completely inert.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_STARTUP_FRAMES: int = 20000
const ZOOM_MIN: float = 0.2
const ZOOM_MAX: float = 3.0
const SWEEP_STEPS: int = 24
const FRAMES_PER_STEP: int = 4
const EXPECTED_VISIBLE_CHUNKS: int = 81
const EXPECTED_SOURCE_CHUNKS: int = 121
const EXPECTED_PACKET_CHUNKS: int = 169

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	if packed_scene == null:
		printerr("ZOOM_INVARIANCE: dev scene failed to load")
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
		if world_scene == null or streamer == null or player == null or camera == null:
			continue
		loading_state = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(loading_state.get("presented", false)):
			break
	if not bool(loading_state.get("presented", false)):
		printerr("ZOOM_INVARIANCE: initial loading gate never presented")
		await _finish(scene, 1)
		return

	var baseline_epoch: int = int(streamer.get("_generation_epoch"))
	var baseline_views: Dictionary = _chunk_view_identities(streamer)
	var baseline_hud: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary

	var zoom_steps: Array[float] = []
	for step_index: int in range(SWEEP_STEPS):
		var t: float = float(step_index) / float(SWEEP_STEPS - 1)
		# Triangle sweep: out -> in -> out, so both directions are covered.
		var folded: float = 1.0 - absf(t * 2.0 - 1.0)
		zoom_steps.append(lerpf(ZOOM_MIN, ZOOM_MAX, folded))

	var destroyed_views: int = 0
	var created_views: int = 0
	var packet_requests: int = 0
	var envelope_mismatches: int = 0
	var radius_changes: int = 0
	var failures: Array[String] = []

	for step_index: int in range(zoom_steps.size()):
		var zoom: float = zoom_steps[step_index]
		for _tick: int in range(FRAMES_PER_STEP):
			camera.set("_target_zoom", zoom)
			camera.zoom = Vector2(zoom, zoom)
			await process_frame
			var hud: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary
			packet_requests = maxi(packet_requests, int(hud.get("requested_packets", 0)))
			if int(hud.get("stream_radius", -1)) != baseline_hud.get("stream_radius", -2):
				radius_changes += 1
			if int(hud.get("desired_visible_chunks", -1)) != EXPECTED_VISIBLE_CHUNKS \
					or int(hud.get("desired_source_chunks", -1)) != EXPECTED_SOURCE_CHUNKS \
					or int(hud.get("packet_count", -1)) != EXPECTED_PACKET_CHUNKS:
				envelope_mismatches += 1
				if failures.size() < 8:
					failures.append(
						"zoom=%.2f visible=%d source=%d packets=%d"
						% [
							zoom,
							int(hud.get("desired_visible_chunks", -1)),
							int(hud.get("desired_source_chunks", -1)),
							int(hud.get("packet_count", -1)),
						],
					)
			var current_views: Dictionary = _chunk_view_identities(streamer)
			for coord_variant: Variant in baseline_views.keys():
				if not current_views.has(coord_variant):
					destroyed_views += 1
					if failures.size() < 8:
						failures.append("zoom=%.2f destroyed chunk=%s" % [zoom, str(coord_variant)])
				elif current_views[coord_variant] != baseline_views[coord_variant]:
					created_views += 1
					if failures.size() < 8:
						failures.append("zoom=%.2f recreated chunk=%s" % [zoom, str(coord_variant)])
			baseline_views = current_views

	_assert(
		int(streamer.get("_generation_epoch")) == baseline_epoch,
		"Zoom must never bump the generation epoch.",
	)
	_assert(radius_changes == 0, "Zoom must never change the residency radius.")
	_assert(envelope_mismatches == 0, "Zoom must never change the resident envelope size.")
	_assert(destroyed_views == 0, "Zoom must never destroy a resident ChunkView.")
	_assert(created_views == 0, "Zoom must never recreate a resident ChunkView.")
	_assert(packet_requests == 0, "A stationary zoom sweep must not request any chunk packet.")

	if not _failed:
		print(
			"world_zoom_residency_invariance_probe: OK steps=%d visible=%d source=%d packets=%d"
			% [
				zoom_steps.size(),
				EXPECTED_VISIBLE_CHUNKS,
				EXPECTED_SOURCE_CHUNKS,
				EXPECTED_PACKET_CHUNKS,
			],
		)
	else:
		for failure: String in failures:
			printerr("  %s" % failure)
	await _finish(scene, 1 if _failed else 0)


func _chunk_view_identities(streamer: Node) -> Dictionary:
	var identities: Dictionary = { }
	var chunk_views: Dictionary = streamer.get("_chunk_views") as Dictionary
	for coord_variant: Variant in chunk_views.keys():
		var view: Object = chunk_views[coord_variant] as Object
		if view != null and is_instance_valid(view):
			identities[coord_variant] = view.get_instance_id()
	return identities


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	printerr("ZOOM_INVARIANCE FAILED: %s" % message)


func _finish(scene: Node, exit_code: int) -> void:
	scene.queue_free()
	await process_frame
	quit(exit_code)
