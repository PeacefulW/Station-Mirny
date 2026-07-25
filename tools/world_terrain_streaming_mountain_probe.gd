extends SceneTree
## S4 integration probe: after the honest S3 startup gate, move through the
## real deterministic F scene at the ordinary maximum speed and require every
## visible terrain/water/mountain presentation owner to be ready on entry.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_STARTUP_FRAMES: int = 6000
const DEFAULT_ROUTE_SECONDS: int = 12
const TARGET_FPS: int = 60
const PLAYER_SPEED_PX_PER_SECOND: float = 320.0
const MAX_ZOOM_OUT: float = 0.2
const EXPECTED_VISIBLE_CHUNKS: int = 81
const EXPECTED_TERRAIN_SOURCE_CHUNKS: int = 121
const EXPECTED_PACKET_SUPPORT_CHUNKS: int = 169

var _failed: bool = false
var _route_seconds: int = DEFAULT_ROUTE_SECONDS
var _allow_accepted_s3_terrain_handoff: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_apply_command_line_overrides()
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "S4 mountain scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var world_scene: Node = null
	var streamer: Node = null
	var player: Node2D = null
	var camera: Camera2D = null
	var loading_state: Dictionary = { }
	var used_accepted_s3_terrain_handoff: bool = false
	for frame_index: int in range(MAX_STARTUP_FRAMES):
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
		if _allow_accepted_s3_terrain_handoff \
				and _initial_target_terrain_is_ready(streamer, loading_state):
			var loading_gate: RefCounted = streamer.get("_initial_loading_gate") as RefCounted
			loading_gate.set("_active", false)
			player.process_mode = Node.PROCESS_MODE_INHERIT
			used_accepted_s3_terrain_handoff = true
			break
		if frame_index > 0 and frame_index % 1200 == 0:
			print(
				"S4_STARTUP frame=%d stage=%s reserve=%d/%d"
				% [
					frame_index,
					String(loading_state.get("current_stage", "")),
					int(loading_state.get("reserve_ready_chunk_count", 0)),
					int(loading_state.get("target_chunk_count", 0)),
				],
			)
	_assert(
		bool(loading_state.get("presented", false)) or used_accepted_s3_terrain_handoff,
		"S4 route requires the accepted S3 gate to finish before movement.",
	)
	if not bool(loading_state.get("presented", false)) \
			and not used_accepted_s3_terrain_handoff:
		_print_startup_failure(streamer, loading_state)
		await _finish(scene)
		return

	Engine.max_fps = TARGET_FPS
	var initial_hud: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary
	_assert(
		int(initial_hud.get("stream_radius", -1)) == 4,
		"S4 route must run at the maximum zoom-out stream radius.",
	)
	_assert(
		int(initial_hud.get("desired_visible_chunks", -1)) == EXPECTED_VISIBLE_CHUNKS,
		"S4 route must begin with the complete maximum-zoom visible envelope.",
	)
	_assert(
		int(initial_hud.get("desired_source_chunks", -1)) == EXPECTED_TERRAIN_SOURCE_CHUNKS,
		"S4 route must begin with the complete materialized terrain reserve.",
	)
	_assert(
		_get_coord_array(streamer, "_terrain_packet_support_chunk_coords").size()
		== EXPECTED_PACKET_SUPPORT_CHUNKS,
		"S4 route must begin with the complete packet-only halo support ring.",
	)

	var initial_source: Dictionary = { }
	for coord: Vector2i in _get_coord_array(streamer, "_desired_source_chunk_coords"):
		initial_source[coord] = true
	var source_enter_frame: Dictionary = { }
	var terrain_ready_frame: Dictionary = { }
	var visible_enter_frame: Dictionary = { }
	var first_failures: Array[String] = []
	var missing_visible_samples: int = 0
	var visible_size_mismatch_samples: int = 0
	var source_size_mismatch_samples: int = 0
	var support_size_mismatch_samples: int = 0
	var max_resident_views: int = int(initial_hud.get("resident_views", 0))
	var max_resident_packets: int = int(initial_hud.get("packet_count", 0))
	var late_visible_chunks: int = 0
	var min_lead_frames: int = 1 << 30
	var boundary_crossings: int = 0
	var previous_player_chunk: Vector2i = initial_hud.get(
		"player_chunk",
		Vector2i(2147483647, 2147483647),
	) as Vector2i
	var start_position: Vector2 = player.global_position
	var route_frames: int = _route_seconds * TARGET_FPS
	var step_px: float = PLAYER_SPEED_PX_PER_SECOND / float(TARGET_FPS)
	for frame_index: int in range(route_frames):
		camera.set("_target_zoom", MAX_ZOOM_OUT)
		camera.zoom = Vector2(MAX_ZOOM_OUT, MAX_ZOOM_OUT)
		player.global_position = start_position + Vector2(0.0, step_px * float(frame_index + 1))
		await process_frame
		var hud: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary
		max_resident_views = maxi(
			max_resident_views,
			int(hud.get("resident_views", 0)),
		)
		max_resident_packets = maxi(
			max_resident_packets,
			int(hud.get("packet_count", 0)),
		)
		var player_chunk: Vector2i = hud.get("player_chunk", previous_player_chunk) as Vector2i
		if player_chunk != previous_player_chunk:
			boundary_crossings += 1
			previous_player_chunk = player_chunk
		var source_coords: Array[Vector2i] = _get_coord_array(
			streamer,
			"_desired_source_chunk_coords",
		)
		if source_coords.size() != EXPECTED_TERRAIN_SOURCE_CHUNKS:
			source_size_mismatch_samples += 1
		var support_coords: Array[Vector2i] = _get_coord_array(
			streamer,
			"_terrain_packet_support_chunk_coords",
		)
		if support_coords.size() != EXPECTED_PACKET_SUPPORT_CHUNKS:
			support_size_mismatch_samples += 1
		for chunk_coord: Vector2i in source_coords:
			if initial_source.has(chunk_coord):
				continue
			if not source_enter_frame.has(chunk_coord):
				source_enter_frame[chunk_coord] = frame_index
			if not terrain_ready_frame.has(chunk_coord) \
					and _terrain_readiness_issues(streamer, chunk_coord, false).is_empty():
				terrain_ready_frame[chunk_coord] = frame_index
		var visible_coords: Array[Vector2i] = _get_coord_array(
			streamer,
			"_desired_visible_chunk_coords",
		)
		if visible_coords.size() != EXPECTED_VISIBLE_CHUNKS:
			visible_size_mismatch_samples += 1
			if first_failures.size() < 12:
				first_failures.append(
					"frame=%d visible_count=%d expected=%d"
					% [frame_index, visible_coords.size(), EXPECTED_VISIBLE_CHUNKS],
				)
		for chunk_coord: Vector2i in visible_coords:
			var issues: Array[String] = _terrain_readiness_issues(
				streamer,
				chunk_coord,
				true,
			)
			if not issues.is_empty():
				missing_visible_samples += 1
				if first_failures.size() < 12:
					first_failures.append(
						"frame=%d player=%s chunk=%s issues=%s"
						% [frame_index, str(player_chunk), str(chunk_coord), ",".join(issues)],
					)
			if initial_source.has(chunk_coord) or visible_enter_frame.has(chunk_coord):
				continue
			visible_enter_frame[chunk_coord] = frame_index
			if not terrain_ready_frame.has(chunk_coord):
				late_visible_chunks += 1
				continue
			var lead_frames: int = frame_index - int(
				terrain_ready_frame.get(chunk_coord, frame_index),
			)
			min_lead_frames = mini(min_lead_frames, lead_frames)

	var endpoint_issues: int = _count_visible_terrain_issues(streamer, first_failures, route_frames)
	missing_visible_samples += endpoint_issues
	_assert(boundary_crossings >= 2, "S4 route must cross at least two chunk boundaries.")
	_assert(
		visible_size_mismatch_samples == 0,
		"Visible envelope must stay at maximum zoom-out for the complete route.",
	)
	_assert(
		source_size_mismatch_samples == 0,
		"Materialized terrain reserve must stay bounded and complete for the complete route.",
	)
	_assert(
		support_size_mismatch_samples == 0,
		"Packet-only terrain halo support must stay bounded and complete for the complete route.",
	)
	_assert(
		max_resident_views <= EXPECTED_TERRAIN_SOURCE_CHUNKS,
		"Materialized terrain residency must remain inside the bounded reserve.",
	)
	_assert(
		max_resident_packets <= EXPECTED_PACKET_SUPPORT_CHUNKS,
		"Base packet residency must remain inside the bounded halo support ring.",
	)
	_assert(
		late_visible_chunks == 0,
		"Every newly visible terrain chunk must be ready before entry.",
	)
	_assert(
		missing_visible_samples == 0,
		"Visible terrain must remain complete during movement and at the immediate stop frame.",
	)
	if not _failed:
		print(
			(
				"world_terrain_streaming_mountain_probe: OK seconds=%d frames=%d "
				+ "distance_px=%.1f boundaries=%d new_visible=%d min_lead_frames=%d "
				+ "missing_visible_samples=%d envelope_mismatches=%d/%d/%d "
				+ "resident_max=%d/%d endpoint_issues=%d s3_handoff=%s"
			)
			% [
				_route_seconds,
				route_frames,
				step_px * float(route_frames),
				boundary_crossings,
				visible_enter_frame.size(),
				0 if min_lead_frames == (1 << 30) else min_lead_frames,
				missing_visible_samples,
				visible_size_mismatch_samples,
				source_size_mismatch_samples,
				support_size_mismatch_samples,
				max_resident_views,
				max_resident_packets,
				endpoint_issues,
				"terrain_only" if used_accepted_s3_terrain_handoff else "strict_presented",
			],
		)
	else:
		print(
			(
				"S4_TERRAIN_FAILURE missing_samples=%d late_chunks=%d "
				+ "envelope_mismatches=%d/%d/%d resident_max=%d/%d "
				+ "endpoint=%d first=%s"
			)
			% [
				missing_visible_samples,
				late_visible_chunks,
				visible_size_mismatch_samples,
				source_size_mismatch_samples,
				support_size_mismatch_samples,
				max_resident_views,
				max_resident_packets,
				endpoint_issues,
				JSON.stringify(first_failures),
			],
		)
	await _finish(scene)


func _terrain_readiness_issues(
		streamer: Node,
		chunk_coord: Vector2i,
		require_visible: bool,
) -> Array[String]:
	var issues: Array[String] = []
	var chunk_views: Dictionary = streamer.get("_chunk_views") as Dictionary
	var chunk_view: Node = chunk_views.get(chunk_coord, null) as Node
	if chunk_view == null:
		issues.append("view_absent")
		return issues
	if not bool(chunk_view.call("is_terrain_cell_presentation_committed")):
		issues.append("terrain_uncommitted")
	if bool(chunk_view.get("_water_fill_sync_pending")):
		issues.append("water_visual_pending")
	var mountain_halos: Dictionary = streamer.get("_mountain_solid_halo_cache") as Dictionary
	var mountain_halo: Dictionary = mountain_halos.get(chunk_coord, { }) as Dictionary
	if mountain_halo.is_empty():
		issues.append("mountain_halo_absent")
	elif bool(mountain_halo.get("has_closed", false)):
		var mountain_result: Dictionary = streamer.call(
			"_get_ready_mountain_native_mask_result",
			chunk_coord,
		) as Dictionary
		if mountain_result.is_empty():
			issues.append("mountain_mask_absent")
		elif bool(chunk_view.call("is_mountain_native_mask_visual_pending")):
			issues.append("mountain_mask_visual_pending")
	var terrain_halos: Dictionary = streamer.get("_terrain_edge_solid_halo_cache") as Dictionary
	var terrain_halo: Dictionary = terrain_halos.get(chunk_coord, { }) as Dictionary
	if terrain_halo.is_empty():
		issues.append("shoreline_halo_absent")
	elif bool(terrain_halo.get("has_shoreline", false)):
		var terrain_result: Dictionary = streamer.call(
			"_get_ready_terrain_edge_mask_result",
			chunk_coord,
		) as Dictionary
		if terrain_result.is_empty():
			issues.append("shoreline_mask_absent")
		elif bool(chunk_view.call("is_terrain_edge_mask_visual_pending")):
			issues.append("shoreline_mask_visual_pending")
	if require_visible and not chunk_view.visible:
		issues.append("view_hidden")
	return issues


func _count_visible_terrain_issues(
		streamer: Node,
		first_failures: Array[String],
		frame_index: int,
) -> int:
	var issue_count: int = 0
	for chunk_coord: Vector2i in _get_coord_array(streamer, "_desired_visible_chunk_coords"):
		var issues: Array[String] = _terrain_readiness_issues(streamer, chunk_coord, true)
		if issues.is_empty():
			continue
		issue_count += 1
		if first_failures.size() < 12:
			first_failures.append(
				"stop_frame=%d chunk=%s issues=%s"
				% [frame_index, str(chunk_coord), ",".join(issues)],
			)
	return issue_count


func _get_coord_array(owner: Node, property_name: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var values: Array = owner.get(property_name) as Array
	for value: Variant in values:
		result.append(value as Vector2i)
	return result


func _initial_target_terrain_is_ready(streamer: Node, state: Dictionary) -> bool:
	if not bool(state.get("target_established", false)):
		return false
	var loading_gate: RefCounted = streamer.get("_initial_loading_gate") as RefCounted
	var target_coords: Array = loading_gate.call("get_target_coords") as Array
	if target_coords.is_empty() \
			or target_coords.size() != int(state.get("target_chunk_count", 0)):
		return false
	for coord_variant: Variant in target_coords:
		if not _terrain_readiness_issues(
			streamer,
			coord_variant as Vector2i,
			false,
		).is_empty():
			return false
	print(
		(
			"S4_ACCEPTED_S3_TERRAIN_HANDOFF target=%d object_blockers=%d "
			+ "reason=accepted_S3_headless_object_staging_is_out_of_scope"
		)
		% [
			target_coords.size(),
			int(state.get("target_chunk_count", 0))
			- int(state.get("reserve_ready_chunk_count", 0)),
		],
	)
	return true


func _print_startup_failure(streamer: Node, state: Dictionary) -> void:
	var reasons: Dictionary = { }
	if streamer != null:
		var snapshot: Dictionary = streamer.call(
			"get_streaming_readiness_debug_snapshot",
		) as Dictionary
		reasons = snapshot.get("reason_counts", { }) as Dictionary
	print("S4_STARTUP_BLOCKED state=%s reasons=%s" % [str(state), str(reasons)])


func _apply_command_line_overrides() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_route_seconds = maxi(1, int(argument.trim_prefix("--seconds=")))
		elif argument == "--allow-accepted-s3-terrain-handoff":
			_allow_accepted_s3_terrain_handoff = true


func _finish(scene: Node) -> void:
	Engine.max_fps = 0
	scene.queue_free()
	await process_frame
	await process_frame
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
