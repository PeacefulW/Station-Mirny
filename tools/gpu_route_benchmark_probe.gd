extends SceneTree
## Windowed automated GPU/frame benchmark on a deterministic cardinal route.
##
## Unlike the headless streaming probes this one must render, so it is launched
## WITHOUT --headless. It walks a named cardinal route at a fixed zoom, samples
## real viewport GPU/CPU timings, and can hide individual presentation layer
## families so their cost can be attributed instead of guessed.
##
## Usage:
##   godot_console --path . --script res://tools/gpu_route_benchmark_probe.gd -- \
##       --seconds=20 --zoom=0.2 --direction=north --label=dense_forest
##
## Layer group names accepted by --hide:
##   grass, grass_shadow, grass_spore, objects, mountain, terrain_edge,
##   overlays, tiles, postprocess

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const MAX_STARTUP_FRAMES: int = 20000
const PLAYER_SPEED_PX_PER_SECOND: float = 320.0
const DEFAULT_ROUTE_SECONDS: float = 90.0
const DEFAULT_ZOOM: float = 0.2
const WARMUP_SECONDS: float = 2.0
const CONTENT_VALIDATION_INTERVAL_FRAMES: int = 1
const OBJECT_PIXEL_DIFFERENCE_THRESHOLD: float = 0.08
const MIN_OBJECT_CHANGED_PIXELS: int = 2000
const TARGET_VIEWPORT_SIZE: Vector2i = Vector2i(1920, 1080)
const MAX_ALLOWED_FRAME_MS: float = 1000.0 / 60.0
const MAX_RETAINED_SLOW_FRAMES: int = 10
const WorldPerfProbeScript = preload("res://core/runtime/world_perf_probe.gd")

var _route_seconds: float = DEFAULT_ROUTE_SECONDS
var _sample_after_seconds: float = WARMUP_SECONDS
var _zoom: float = DEFAULT_ZOOM
var _player_speed_px_per_second: float = PLAYER_SPEED_PX_PER_SECOND
var _route_direction: Vector2 = Vector2.UP
var _route_direction_name: String = "north"
var _label: String = "baseline"
var _hidden_groups: Dictionary = { }
var _grass_lod_override: float = -1.0
var _ground_organic_override: float = -1.0
var _render_scale: float = 1.0
var _world_render_scale_override: float = -1.0
var _viewport_rid: RID = RID()
var _benchmark_viewport: Viewport = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_apply_command_line_overrides()
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	if packed_scene == null:
		printerr("GPU_BENCH: dev scene failed to load")
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	if _world_render_scale_override > 0.0:
		var configured_compositor: Node = scene.get_node_or_null(
			"WorldRuntimeV0/WorldResolutionCompositor",
		)
		if configured_compositor != null:
			configured_compositor.set("enable_render_time_measurement", true)
			configured_compositor.set(
				"world_render_scale",
				_world_render_scale_override,
			)
	var render_size := Vector2i(
		maxi(1, roundi(float(TARGET_VIEWPORT_SIZE.x) * _render_scale)),
		maxi(1, roundi(float(TARGET_VIEWPORT_SIZE.y) * _render_scale)),
	)
	# Benchmarking must observe real capability, not the 60 Hz presentation cap.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(TARGET_VIEWPORT_SIZE)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if is_equal_approx(_render_scale, 1.0):
		# Production-real path: the world scene owns the actual output Window.
		# An extra off-screen parent viewport can serialize a nested compositor
		# and nearly double wall time while each measured GPU pass looks healthy.
		root.size = TARGET_VIEWPORT_SIZE
		root.content_scale_size = TARGET_VIEWPORT_SIZE
		_benchmark_viewport = root
		root.add_child(scene)
	else:
		# Explicit diagnostic matrix only. It preserves logical 1920x1080 FOV
		# while changing the physical backing texture.
		var offscreen_viewport := SubViewport.new()
		offscreen_viewport.name = "BenchmarkViewport1920x1080"
		offscreen_viewport.size = render_size
		offscreen_viewport.size_2d_override = TARGET_VIEWPORT_SIZE
		offscreen_viewport.size_2d_override_stretch = true
		offscreen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(offscreen_viewport)
		offscreen_viewport.add_child(scene)
		_benchmark_viewport = offscreen_viewport
	_viewport_rid = _benchmark_viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)

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
				if _world_render_scale_override > 0.0:
					var runtime_compositor: Node = world_scene.get_node_or_null(
						"WorldResolutionCompositor",
					)
					if runtime_compositor != null:
						runtime_compositor.set("enable_render_time_measurement", true)
						runtime_compositor.set(
							"world_render_scale",
							_world_render_scale_override,
						)
						runtime_compositor.call("_sync_render_size")
				streamer = world_scene.get_node_or_null("WorldStreamer")
				player = world_scene.get_node_or_null("Player") as Node2D
		if camera == null:
			camera = _benchmark_viewport.get_camera_2d()
		if camera != null:
			camera.set("_target_zoom", _zoom)
			camera.zoom = Vector2(_zoom, _zoom)
		if world_scene == null or streamer == null or player == null:
			continue
		loading_state = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(loading_state.get("presented", false)):
			break
	if not bool(loading_state.get("presented", false)):
		printerr("GPU_BENCH: initial loading gate never presented")
		await _finish(scene, 1)
		return
	# get_visible_rect() reports the logical 2D override. The backing texture is
	# the actual raster workload whose size the matrix must verify.
	var measured_viewport_size: Vector2i = Vector2i(_benchmark_viewport.size)
	if measured_viewport_size != render_size:
		printerr(
			"GPU_BENCH: viewport must be exactly %s, got %s" % [
				str(render_size),
				str(measured_viewport_size),
			],
		)
		await _finish(scene, 1)
		return

	if _grass_lod_override >= 0.0:
		streamer.set("_grass_lod_min_fraction", _grass_lod_override)
		streamer.set("_grass_lod_fraction", -1.0)
	if _ground_organic_override >= 0.0:
		var ground_material: ShaderMaterial = \
				WorldTileSetFactory.get_built_material_for_terrain(
					WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
				)
		if ground_material == null:
			printerr("GPU_BENCH: plains ground material is unavailable")
			await _finish(scene, 1)
			return
		ground_material.set_shader_parameter(
			"organic_overlay_strength",
			_ground_organic_override,
		)

	var start_position: Vector2 = player.global_position

	var frame_ms_samples: PackedFloat32Array = PackedFloat32Array()
	var gpu_ms_samples: PackedFloat32Array = PackedFloat32Array()
	var terrain_gpu_ms_samples: PackedFloat32Array = PackedFloat32Array()
	var cpu_ms_samples: PackedFloat32Array = PackedFloat32Array()
	var draw_call_max: int = 0
	var draw_call_sum: float = 0.0
	var object_max: int = 0
	var object_sum: float = 0.0
	var content_validation_samples: int = 0
	var content_invalid_samples: int = 0
	var content_invalid_examples: Array[Dictionary] = []
	var expected_tree_max: int = 0
	var expected_rock_max: int = 0
	var expected_bush_max: int = 0
	var actual_tree_max: int = 0
	var actual_rock_max: int = 0
	var actual_bush_max: int = 0
	var last_content_state: Dictionary = { }
	var previous_usec: int = Time.get_ticks_usec()
	var route_started_usec: int = previous_usec
	var route_frame_index: int = 0
	var slow_frames: Array[Dictionary] = []
	var frames_over_budget: int = 0
	WorldPerfProbeScript.begin_live_observation()

	while float(Time.get_ticks_usec() - route_started_usec) / 1000000.0 < _route_seconds:
		var route_elapsed_seconds: float = \
				float(Time.get_ticks_usec() - route_started_usec) / 1000000.0
		camera.set("_target_zoom", _zoom)
		camera.zoom = Vector2(_zoom, _zoom)
		player.global_position = start_position \
				+ _route_direction * _player_speed_px_per_second * route_elapsed_seconds
		_apply_hidden_groups(world_scene, streamer)
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		var frame_ms: float = float(now_usec - previous_usec) / 1000.0
		route_frame_index += 1
		var live_perf: Dictionary = \
				WorldPerfProbeScript.copy_completed_live_frame_snapshot()
		var is_sampled_frame: bool = route_elapsed_seconds >= _sample_after_seconds
		if is_sampled_frame and frame_ms > MAX_ALLOWED_FRAME_MS:
			frames_over_budget += 1
		if is_sampled_frame and frame_ms >= 12.0:
			_retain_slow_frame(slow_frames, {
				"frame_ms": frame_ms,
				"route_seconds": route_elapsed_seconds,
				"player_position": player.global_position,
				"player_chunk": streamer.get("_player_chunk_coord"),
				"dispatcher": live_perf.get("ops", { }),
				"world_render_pending": bool(
						(streamer.get("_world_render_world") as Node).call(
							"has_pending_snapshot",
						),
				),
				"world_render_pending_page": int(
						(streamer.get("_world_render_world") as Node).get(
							"_pending_snapshot_page_cursor",
						),
				),
				"world_render_pending_stream": int(
						(streamer.get("_world_render_world") as Node).get(
							"_pending_snapshot_stream_cursor",
						),
				),
				"world_render_generation": int(
						((streamer.get("_world_render_world") as Node).call(
							"get_debug_state",
						) as Dictionary).get("snapshot_generation", -1),
				),
				"world_render_worker_inflight": int(
						streamer.get("_world_render_inflight_generation"),
				),
			})
		if route_frame_index % CONTENT_VALIDATION_INTERVAL_FRAMES == 0:
			last_content_state = _inspect_visible_content(streamer)
			content_validation_samples += 1
			if not bool(last_content_state.get("valid", false)):
				content_invalid_samples += 1
				if content_invalid_examples.size() < 6:
					content_invalid_examples.append(
						_compact_content_failure(last_content_state, route_elapsed_seconds),
					)
			expected_tree_max = maxi(expected_tree_max, int(last_content_state.get("expected_tree", 0)))
			expected_rock_max = maxi(expected_rock_max, int(last_content_state.get("expected_rock", 0)))
			expected_bush_max = maxi(expected_bush_max, int(last_content_state.get("expected_bush", 0)))
			actual_tree_max = maxi(actual_tree_max, int(last_content_state.get("actual_tree", 0)))
			actual_rock_max = maxi(actual_rock_max, int(last_content_state.get("actual_rock", 0)))
			actual_bush_max = maxi(actual_bush_max, int(last_content_state.get("actual_bush", 0)))
		if route_elapsed_seconds < _sample_after_seconds:
			# Probe-side validation and monitor reads are observer work, not part
			# of the game's process/render frame being measured.
			previous_usec = Time.get_ticks_usec()
			continue
		frame_ms_samples.append(frame_ms)
		gpu_ms_samples.append(
			RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid),
		)
		var compositor: Node = world_scene.get_node_or_null("WorldResolutionCompositor")
		var terrain_viewport_rid: RID = compositor.call("get_static_terrain_viewport_rid") \
				if compositor != null else RID()
		terrain_gpu_ms_samples.append(
			RenderingServer.viewport_get_measured_render_time_gpu(terrain_viewport_rid) \
					if terrain_viewport_rid.is_valid() else 0.0,
		)
		cpu_ms_samples.append(
			RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid),
		)
		var draw_calls: int = int(
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		)
		var render_objects: int = int(
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		)
		draw_call_max = maxi(draw_call_max, draw_calls)
		draw_call_sum += float(draw_calls)
		object_max = maxi(object_max, render_objects)
		object_sum += float(render_objects)
		previous_usec = Time.get_ticks_usec()
	WorldPerfProbeScript.end_live_observation()

	var sample_count: int = frame_ms_samples.size()
	if sample_count <= 0:
		printerr("GPU_BENCH: no samples collected")
		await _finish(scene, 1)
		return

	last_content_state = _inspect_visible_content(streamer)
	var object_evidence: Dictionary = await _capture_object_evidence(streamer, camera)
	var content_is_nonempty: bool = expected_tree_max > 0 \
			and actual_tree_max > 0 \
			and int(object_evidence.get("visible_object_layers", 0)) > 0 \
			and int(object_evidence.get("changed_pixels", 0)) >= maxi(
				1,
				roundi(float(MIN_OBJECT_CHANGED_PIXELS) * _render_scale * _render_scale),
			)
	var content_is_complete: bool = content_validation_samples > 0 \
			and content_invalid_samples == 0 \
			and bool(last_content_state.get("valid", false))
	var frame_budget_valid: bool = frames_over_budget == 0 \
			and _percentile(frame_ms_samples, 1.0) <= MAX_ALLOWED_FRAME_MS
	var benchmark_valid: bool = content_is_nonempty and content_is_complete \
			and frame_budget_valid
	var hud: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary
	var report: Dictionary = {
		"label": _label,
		"zoom": _zoom,
		"player_speed_px_per_second": _player_speed_px_per_second,
		"route_direction": _route_direction_name,
		"camera_zoom": camera.zoom.x,
		"viewport_size": measured_viewport_size,
		"logical_viewport_size": TARGET_VIEWPORT_SIZE,
		"render_scale": _render_scale,
		"world_render_scale": (
			float((world_scene.get_node("WorldResolutionCompositor") as Node).get(
				"world_render_scale",
			))
		),
		"world_render_size": (
			(world_scene.get_node("WorldResolutionCompositor") as Node).call(
				"get_world_render_size",
			)
		),
		"streamer_grass_lod_fraction": float(streamer.get("_grass_lod_fraction")),
		"hidden": _hidden_groups.keys(),
		"grass_lod_min_fraction": _grass_lod_override,
		"ground_organic_override": _ground_organic_override,
		"samples": sample_count,
		"frame_avg_ms": _mean(frame_ms_samples),
		"frame_p95_ms": _percentile(frame_ms_samples, 0.95),
		"frame_p99_ms": _percentile(frame_ms_samples, 0.99),
		"frame_max_ms": _percentile(frame_ms_samples, 1.0),
		"frame_budget_ms": MAX_ALLOWED_FRAME_MS,
		"frames_over_budget": frames_over_budget,
		"frame_budget_valid": frame_budget_valid,
		"slow_frames": slow_frames,
		"fps_from_avg": 1000.0 / maxf(_mean(frame_ms_samples), 0.001),
		"gpu_avg_ms": _mean(gpu_ms_samples),
		"gpu_p95_ms": _percentile(gpu_ms_samples, 0.95),
		"gpu_max_ms": _percentile(gpu_ms_samples, 1.0),
		"terrain_gpu_avg_ms": _mean(terrain_gpu_ms_samples),
		"terrain_gpu_p95_ms": _percentile(terrain_gpu_ms_samples, 0.95),
		"combined_viewport_gpu_avg_ms": _mean(gpu_ms_samples) \
				+ _mean(terrain_gpu_ms_samples),
		"render_cpu_avg_ms": _mean(cpu_ms_samples),
		"render_cpu_p95_ms": _percentile(cpu_ms_samples, 0.95),
		"draw_calls_avg": draw_call_sum / float(sample_count),
		"draw_calls_max": draw_call_max,
		"render_objects_avg": object_sum / float(sample_count),
		"render_objects_max": object_max,
		"content_validation_samples": content_validation_samples,
		"content_invalid_samples": content_invalid_samples,
		"content_invalid_examples": content_invalid_examples,
		"content_valid": content_is_complete,
		"content_nonempty": content_is_nonempty,
		"expected_tree_max": expected_tree_max,
		"expected_rock_max": expected_rock_max,
		"expected_bush_max": expected_bush_max,
		"actual_tree_max": actual_tree_max,
		"actual_rock_max": actual_rock_max,
		"actual_bush_max": actual_bush_max,
		"last_content_state": last_content_state,
		"object_evidence": object_evidence,
		"benchmark_valid": benchmark_valid,
		"resident_views": int(hud.get("resident_views", -1)),
		"packet_count": int(hud.get("packet_count", -1)),
		"stream_radius": int(hud.get("stream_radius", -1)),
		"vram_mib": float(
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		) / 1048576.0,
		"ram_mib": float(
			Performance.get_monitor(Performance.MEMORY_STATIC),
		) / 1048576.0,
	}
	var report_path: String = "user://gpu_bench_%s_result.json" % _label.validate_filename()
	report["report_path"] = ProjectSettings.globalize_path(report_path)
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	else:
		push_warning("GPU_BENCH: result report could not be written to %s" % report_path)
	print("GPU_BENCH_RESULT %s" % JSON.stringify(report))
	if not benchmark_valid:
		printerr(
			"GPU_BENCH: INVALID — content proof or strict 60 FPS frame budget failed",
		)
	await _finish(scene, 0 if benchmark_valid else 1)


func _inspect_visible_content(streamer: Node) -> Dictionary:
	var chunk_views: Dictionary = streamer.get("_chunk_views") as Dictionary
	var desired_coords: Array = streamer.get("_desired_visible_chunk_coords") as Array
	var source_coords: Array = streamer.get("_desired_source_chunk_coords") as Array
	var desired_set: Dictionary = { }
	for coord_variant: Variant in desired_coords:
		desired_set[coord_variant as Vector2i] = true
	# Do not let the streamer's own demand list validate itself. Derive the
	# physically visible chunks independently from the rendered viewport corners;
	# this is what catches a narrow edge strip outside an otherwise internally
	# consistent but undersized residency envelope.
	var viewport_coords: Array[Vector2i] = _get_viewport_chunk_coords(streamer)
	var viewport_outside_demand: int = 0
	var viewport_missing_views: int = 0
	var object_results: Dictionary = streamer.get("_object_presentation_results_by_chunk") as Dictionary
	var expected_tree: int = 0
	var expected_rock: int = 0
	var expected_bush: int = 0
	var actual_tree: int = 0
	var actual_rock: int = 0
	var actual_bush: int = 0
	var missing_views: int = 0
	var hidden_views: int = 0
	var incomplete_views: int = 0
	var stale_render_chunks: int = 0
	var bad_view_details: Array[Dictionary] = []
	for coord: Vector2i in viewport_coords:
		if not desired_set.has(coord):
			viewport_outside_demand += 1
		var view: Node = chunk_views.get(coord, null) as Node
		if view == null or not is_instance_valid(view):
			viewport_missing_views += 1
			missing_views += 1
			if bad_view_details.size() < 8:
				bad_view_details.append({
					"coord": coord,
					"viewport_intersection": true,
					"in_desired_demand": desired_set.has(coord),
					"view_exists": false,
					"visible": false,
				})
			continue
		if not view.visible:
			viewport_missing_views += 1
			hidden_views += 1
		if not bool(view.call("is_object_presentation_complete")):
			incomplete_views += 1
		if not bool(streamer.call("_world_render_chunk_is_current", coord)):
			stale_render_chunks += 1
		if (not view.visible \
				or not bool(view.call("is_object_presentation_complete")) \
				or not bool(streamer.call("_world_render_chunk_is_current", coord))) \
				and bad_view_details.size() < 8:
			bad_view_details.append({
				"coord": coord,
				"viewport_intersection": true,
				"in_desired_demand": desired_set.has(coord),
				"visible": view.visible,
				"complete": bool(view.call("is_object_presentation_complete")),
				"blocking_ready": bool(view.call("is_object_blocking_presentation_ready")),
				"pending_apply": bool(view.call("has_pending_object_presentation_apply")),
				"staged": bool(view.call("has_staged_object_presentation_result")),
				"world_render_current": bool(streamer.call("_world_render_chunk_is_current", coord)),
			})
	for coord_variant: Variant in desired_coords:
		var coord: Vector2i = coord_variant as Vector2i
		var result: Dictionary = object_results.get(coord, { }) as Dictionary
		expected_tree += int(result.get("tree_instance_count", 0))
		expected_rock += int(result.get("rock_instance_count", 0))
		expected_bush += int(result.get("bush_instance_count", 0))
	var render_world: Node = streamer.get("_world_render_world") as Node
	var render_state: Dictionary = { }
	if render_world != null and is_instance_valid(render_world):
		render_state = render_world.call("get_debug_state") as Dictionary
	# The fixed-pass renderer no longer owns family-specific layers or counters.
	# Its registry-labelled descriptor totals are the authoritative resident GPU
	# evidence and remain independent from the packet-side expected counts above.
	var descriptor_counts_by_id: Dictionary = render_state.get(
		"descriptor_counts_by_id",
		{ },
	) as Dictionary
	actual_tree = int(descriptor_counts_by_id.get("layered_tree", 0))
	actual_rock = int(descriptor_counts_by_id.get("small_rock", 0))
	actual_bush = int(descriptor_counts_by_id.get("layered_bush", 0))
	# The world renderer deliberately owns the one-chunk source lead ring, while
	# expected_* above counts only the streamer's visible demand envelope.
	# Every visible object must therefore be present, but additional off-screen
	# source objects are the proof that presentation is genuinely preloaded.
	var mismatched_views: int = int(actual_tree < expected_tree) \
			+ int(actual_rock < expected_rock) + int(actual_bush < expected_bush)
	return {
		# Correctness is scoped to chunks which physically intersect the viewport.
		# A desired lead-ring chunk may legitimately be staging while still fully
		# off-screen; rejecting that state would measure preload work as a pop.
		"valid": viewport_outside_demand == 0 and viewport_missing_views == 0 \
				and missing_views == 0 and hidden_views == 0 \
				and incomplete_views == 0 and stale_render_chunks == 0 \
				and mismatched_views == 0 and bool(render_state.get("ready", false)),
		"viewport_intersected_chunks": viewport_coords.size(),
		"viewport_outside_demand": viewport_outside_demand,
		"viewport_missing_views": viewport_missing_views,
		"desired_views": desired_coords.size(),
		"missing_views": missing_views,
		"hidden_views": hidden_views,
		"incomplete_views": incomplete_views,
		"mismatched_views": mismatched_views,
		"stale_render_chunks": stale_render_chunks,
		"bad_view_details": bad_view_details,
		"source_chunks": source_coords.size(),
		"render_state": render_state,
		"expected_tree": expected_tree,
		"expected_rock": expected_rock,
		"expected_bush": expected_bush,
		"actual_tree": actual_tree,
		"actual_rock": actual_rock,
		"actual_bush": actual_bush,
	}


func _compact_content_failure(state: Dictionary, route_seconds: float) -> Dictionary:
	return {
		"route_seconds": route_seconds,
		"viewport_outside_demand": int(state.get("viewport_outside_demand", 0)),
		"viewport_missing_views": int(state.get("viewport_missing_views", 0)),
		"missing_views": int(state.get("missing_views", 0)),
		"hidden_views": int(state.get("hidden_views", 0)),
		"incomplete_views": int(state.get("incomplete_views", 0)),
		"stale_render_chunks": int(state.get("stale_render_chunks", 0)),
		"mismatched_views": int(state.get("mismatched_views", 0)),
		"expected": Vector3i(
			int(state.get("expected_tree", 0)),
			int(state.get("expected_rock", 0)),
			int(state.get("expected_bush", 0)),
		),
		"actual": Vector3i(
			int(state.get("actual_tree", 0)),
			int(state.get("actual_rock", 0)),
			int(state.get("actual_bush", 0)),
		),
		"bad_view_details": (state.get("bad_view_details", []) as Array).duplicate(true),
	}


func _get_viewport_chunk_coords(streamer: Node) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	if _benchmark_viewport == null or not is_instance_valid(_benchmark_viewport):
		return coords
	var viewport_size := Vector2(_benchmark_viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return coords
	var screen_to_world: Transform2D = \
			_benchmark_viewport.canvas_transform.affine_inverse()
	var corners: Array[Vector2] = [
		screen_to_world * Vector2.ZERO,
		screen_to_world * Vector2(viewport_size.x, 0.0),
		screen_to_world * viewport_size,
		screen_to_world * Vector2(0.0, viewport_size.y),
	]
	var world_min: Vector2 = corners[0]
	var world_max: Vector2 = corners[0]
	for corner: Vector2 in corners:
		world_min = world_min.min(corner)
		world_max = world_max.max(corner)
	var chunk_span_px: float = float(
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX
	)
	var min_chunk := Vector2i(
		floori(world_min.x / chunk_span_px),
		floori(world_min.y / chunk_span_px),
	)
	# A viewport edge exactly on a chunk boundary does not intersect the next
	# chunk. Subtract a tiny world-space epsilon before flooring the far edge.
	var max_chunk := Vector2i(
		floori((world_max.x - 0.001) / chunk_span_px),
		floori((world_max.y - 0.001) / chunk_span_px),
	)
	var seen: Dictionary = { }
	for chunk_y: int in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x: int in range(min_chunk.x, max_chunk.x + 1):
			var coord: Vector2i = streamer.call(
				"_canonicalize_chunk_coord",
				Vector2i(chunk_x, chunk_y),
			) as Vector2i
			if seen.has(coord):
				continue
			seen[coord] = true
			coords.append(coord)
	return coords


func _count_packet_layered_objects(packet: Dictionary) -> Dictionary:
	var counts: Dictionary = {4: 0, 7: 0, 8: 0}
	var kinds: PackedByteArray = packet.get("object_kind", PackedByteArray()) as PackedByteArray
	for kind: int in kinds:
		if counts.has(kind):
			counts[kind] = int(counts[kind]) + 1
	return counts


func _capture_object_evidence(streamer: Node, camera: Camera2D) -> Dictionary:
	_pin_camera_zoom(camera)
	await process_frame
	_pin_camera_zoom(camera)
	var with_objects: Image = _benchmark_viewport.get_texture().get_image()
	var safe_label: String = _label.validate_filename()
	var with_path: String = "user://gpu_bench_%s_with_objects.png" % safe_label
	var without_path: String = "user://gpu_bench_%s_without_objects.png" % safe_label
	with_objects.save_png(with_path)
	var render_world: Node = streamer.get("_world_render_world") as Node
	if render_world == null or not is_instance_valid(render_world):
		return {"visible_object_layers": 0, "changed_pixels": 0}
	render_world.call("set_group_enabled", &"objects", false)
	await process_frame
	_pin_camera_zoom(camera)
	await process_frame
	_pin_camera_zoom(camera)
	var without_objects: Image = _benchmark_viewport.get_texture().get_image()
	render_world.call("set_group_enabled", &"objects", true)
	_pin_camera_zoom(camera)
	without_objects.save_png(without_path)
	var changed_pixels: int = 0
	if with_objects.get_size() == without_objects.get_size():
		for y: int in range(with_objects.get_height()):
			for x: int in range(with_objects.get_width()):
				var before: Color = with_objects.get_pixel(x, y)
				var after: Color = without_objects.get_pixel(x, y)
				var difference: float = maxf(
					absf(before.r - after.r),
					maxf(absf(before.g - after.g), absf(before.b - after.b)),
				)
				if difference >= OBJECT_PIXEL_DIFFERENCE_THRESHOLD:
					changed_pixels += 1
	return {
		"visible_object_layers": 2,
		"changed_pixels": changed_pixels,
		"minimum_changed_pixels": maxi(
			1,
			roundi(float(MIN_OBJECT_CHANGED_PIXELS) * _render_scale * _render_scale),
		),
		"with_objects": with_path,
		"without_objects": without_path,
		"image_size": with_objects.get_size(),
	}


func _pin_camera_zoom(camera: Camera2D) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	camera.set("_target_zoom", _zoom)
	camera.zoom = Vector2(_zoom, _zoom)


func _apply_hidden_groups(world_scene: Node, streamer: Node) -> void:
	if _hidden_groups.is_empty():
		return
	if _hidden_groups.has("postprocess"):
		var postprocess: Node = world_scene.get_node_or_null("PostProcessLayer")
		if postprocess != null:
			(postprocess as CanvasLayer).visible = false
	var render_world: Node = streamer.get("_world_render_world") as Node
	if render_world != null and is_instance_valid(render_world):
		for render_group: StringName in [
			&"grass", &"grass_shadow", &"grass_spore", &"objects", &"obj_shadow",
			&"body", &"shadow",
		]:
			if _hidden_groups.has(String(render_group)):
				render_world.call("set_group_enabled", render_group, false)
	var chunk_views: Dictionary = streamer.get("_chunk_views") as Dictionary
	for view_variant: Variant in chunk_views.values():
		var view: Node = view_variant as Node
		if view == null or not is_instance_valid(view):
			continue
		if _hidden_groups.has("grass"):
			_hide_node_array(view, "_grass_scatter_layers")
		if _hidden_groups.has("grass_shadow"):
			_hide_node_array(view, "_grass_shadow_atlas_layers")
			_hide_node(view, "_grass_directional_shadow_layer")
			_hide_node(view, "_grass_shadow_layer")
		if _hidden_groups.has("grass_spore"):
			_hide_node(view, "_grass_spore_layer")
		if _hidden_groups.has("objects"):
			_hide_node(view, "_object_packet_layer")
		if _hidden_groups.has("obj_snow"):
			_hide_object_slot_channel(view, "snow")
		if _hidden_groups.has("obj_shadow"):
			_hide_object_slot_channel(view, "shadow")
		if _hidden_groups.has("obj_trunk"):
			_hide_object_slot_channel(view, "trunk")
		if _hidden_groups.has("obj_foliage"):
			_hide_object_slot_channel(view, "foliage")
		if _hidden_groups.has("mountain"):
			_hide_node(view, "_mountain_page_sprite")
			_hide_node(view, "_mountain_top_mask_sprite")
			_hide_node(view, "_mountain_closed_roof_mask_sprite")
			_hide_node(view, "_mountain_rock_underlay_sprite")
			_hide_node(view, "_mountain_foothill_overlay_sprite")
		if _hidden_groups.has("mtn_page"):
			_hide_node(view, "_mountain_page_sprite")
		if _hidden_groups.has("mtn_top"):
			_hide_node(view, "_mountain_top_mask_sprite")
		if _hidden_groups.has("mtn_roof"):
			_hide_node(view, "_mountain_closed_roof_mask_sprite")
		if _hidden_groups.has("mtn_underlay"):
			_hide_node(view, "_mountain_rock_underlay_sprite")
		if _hidden_groups.has("mtn_foothill"):
			_hide_node(view, "_mountain_foothill_overlay_sprite")
		if _hidden_groups.has("terrain_edge"):
			_hide_node(view, "_terrain_edge_mask_sprite")
		if _hidden_groups.has("overlays"):
			_hide_node(view, "_rock_patch_overlay_sprite")
			_hide_node(view, "_grass_blob_overlay_sprite")
		if _hidden_groups.has("tiles"):
			_hide_node(view, "_base_layer")
			_hide_node(view, "_overlay_layer")
			_hide_node(view, "_water_layer")
			_hide_node(view, "_water_fill_sprite")


## Hides one named MultiMesh channel of every batched object slot so a single
## alpha pass (snow, cast shadow, trunk, foliage) can be priced on its own.
func _hide_object_slot_channel(view: Node, channel: String) -> void:
	var packet_layer: Node = view.get("_object_packet_layer") as Node
	if packet_layer == null or not is_instance_valid(packet_layer):
		return
	for batch_property: String in [
		"_layered_tree_batch_layer",
		"_layered_small_rock_batch_layer",
	]:
		var batch_layer: Node = packet_layer.get(batch_property) as Node
		if batch_layer == null or not is_instance_valid(batch_layer):
			continue
		var slots: Array = batch_layer.get("_slots") as Array
		if slots == null:
			continue
		for slot_variant: Variant in slots:
			var slot: Dictionary = slot_variant as Dictionary
			if slot == null or not slot.has(channel):
				continue
			var node: CanvasItem = slot.get(channel, null) as CanvasItem
			if node != null and is_instance_valid(node) and node.visible:
				node.visible = false


func _hide_node(owner_node: Node, property_name: String) -> void:
	var node: CanvasItem = owner_node.get(property_name) as CanvasItem
	if node != null and is_instance_valid(node) and node.visible:
		node.visible = false


func _hide_node_array(owner_node: Node, property_name: String) -> void:
	var nodes: Array = owner_node.get(property_name) as Array
	if nodes == null:
		return
	for node_variant: Variant in nodes:
		var node: CanvasItem = node_variant as CanvasItem
		if node != null and is_instance_valid(node) and node.visible:
			node.visible = false


func _mean(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in samples:
		total += value
	return total / float(samples.size())


func _percentile(samples: PackedFloat32Array, ratio: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: Array[float] = []
	for value: float in samples:
		sorted.append(value)
	sorted.sort()
	var index: int = clampi(
		int(round(ratio * float(sorted.size() - 1))),
		0,
		sorted.size() - 1,
	)
	return sorted[index]


func _retain_slow_frame(entries: Array[Dictionary], entry: Dictionary) -> void:
	entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("frame_ms", 0.0)) > float(b.get("frame_ms", 0.0))
	)
	if entries.size() > MAX_RETAINED_SLOW_FRAMES:
		entries.resize(MAX_RETAINED_SLOW_FRAMES)


func _apply_command_line_overrides() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_route_seconds = maxf(1.0, argument.trim_prefix("--seconds=").to_float())
		elif argument.begins_with("--sample-after="):
			_sample_after_seconds = maxf(
				0.0,
				argument.trim_prefix("--sample-after=").to_float(),
			)
		elif argument.begins_with("--zoom="):
			_zoom = clampf(argument.trim_prefix("--zoom=").to_float(), 0.05, 4.0)
		elif argument.begins_with("--speed="):
			_player_speed_px_per_second = maxf(
				0.0,
				argument.trim_prefix("--speed=").to_float(),
			)
		elif argument.begins_with("--direction="):
			var requested_direction: String = \
					argument.trim_prefix("--direction=").strip_edges().to_lower()
			match requested_direction:
				"north":
					_route_direction = Vector2.UP
				"south":
					_route_direction = Vector2.DOWN
				"east":
					_route_direction = Vector2.RIGHT
				"west":
					_route_direction = Vector2.LEFT
				_:
					push_error("GPU_BENCH: unsupported route direction '%s'" % requested_direction)
					continue
			_route_direction_name = requested_direction
		elif argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
		elif argument.begins_with("--grass-lod="):
			_grass_lod_override = clampf(
				argument.trim_prefix("--grass-lod=").to_float(),
				0.0,
				1.0,
			)
		elif argument.begins_with("--ground-organic="):
			_ground_organic_override = clampf(
				argument.trim_prefix("--ground-organic=").to_float(),
				0.0,
				1.0,
			)
		elif argument.begins_with("--render-scale="):
			_render_scale = clampf(
				argument.trim_prefix("--render-scale=").to_float(),
				0.25,
				1.0,
			)
		elif argument.begins_with("--world-scale="):
			_world_render_scale_override = clampf(
				argument.trim_prefix("--world-scale=").to_float(),
				0.25,
				1.0,
			)
		elif argument.begins_with("--hide="):
			for group: String in argument.trim_prefix("--hide=").split(",", false):
				_hidden_groups[group.strip_edges()] = true


func _finish(scene: Node, exit_code: int) -> void:
	scene.queue_free()
	await process_frame
	quit(exit_code)
