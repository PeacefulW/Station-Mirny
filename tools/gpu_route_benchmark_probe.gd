extends SceneTree
## Windowed automated GPU/frame benchmark on the deterministic mountain route.
##
## Unlike the headless streaming probes this one must render, so it is launched
## WITHOUT --headless. It walks the accepted S1 route at a fixed zoom, samples
## real viewport GPU/CPU timings, and can hide individual presentation layer
## families so their cost can be attributed instead of guessed.
##
## Usage:
##   godot_console --path . --script res://tools/gpu_route_benchmark_probe.gd -- \
##       --seconds=20 --zoom=0.2 --hide=grass,grass_shadow --label=no_grass
##
## Layer group names accepted by --hide:
##   grass, grass_shadow, grass_spore, objects, mountain, terrain_edge,
##   overlays, tiles, postprocess

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_STARTUP_FRAMES: int = 20000
const PLAYER_SPEED_PX_PER_SECOND: float = 320.0
const DEFAULT_ROUTE_SECONDS: float = 20.0
const DEFAULT_ZOOM: float = 0.2
const WARMUP_SECONDS: float = 2.0
const NOMINAL_FPS: float = 60.0

var _route_seconds: float = DEFAULT_ROUTE_SECONDS
var _zoom: float = DEFAULT_ZOOM
var _label: String = "baseline"
var _hidden_groups: Dictionary = { }
var _grass_lod_override: float = -1.0
var _viewport_rid: RID = RID()


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
	root.add_child(scene)

	# Benchmarking must observe real capability, not the 60 Hz presentation cap.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_viewport_rid = root.get_viewport().get_viewport_rid()
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
				streamer = world_scene.get_node_or_null("WorldStreamer")
				player = world_scene.get_node_or_null("Player") as Node2D
		if camera == null:
			camera = root.get_viewport().get_camera_2d()
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
		await _finish(scene)
		return

	if _grass_lod_override >= 0.0:
		streamer.set("_grass_lod_min_fraction", _grass_lod_override)
		streamer.set("_grass_lod_fraction", -1.0)

	var start_position: Vector2 = player.global_position
	var warmup_frames: int = int(WARMUP_SECONDS * NOMINAL_FPS)
	var route_frames: int = int(_route_seconds * NOMINAL_FPS)
	var step_px: float = PLAYER_SPEED_PX_PER_SECOND / NOMINAL_FPS

	var frame_ms_samples: PackedFloat32Array = PackedFloat32Array()
	var gpu_ms_samples: PackedFloat32Array = PackedFloat32Array()
	var cpu_ms_samples: PackedFloat32Array = PackedFloat32Array()
	var draw_call_max: int = 0
	var draw_call_sum: float = 0.0
	var object_max: int = 0
	var object_sum: float = 0.0
	var previous_usec: int = Time.get_ticks_usec()

	for frame_index: int in range(warmup_frames + route_frames):
		camera.set("_target_zoom", _zoom)
		camera.zoom = Vector2(_zoom, _zoom)
		player.global_position = start_position \
				+ Vector2(0.0, step_px * float(frame_index + 1))
		_apply_hidden_groups(world_scene, streamer)
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		var frame_ms: float = float(now_usec - previous_usec) / 1000.0
		previous_usec = now_usec
		if frame_index < warmup_frames:
			continue
		frame_ms_samples.append(frame_ms)
		gpu_ms_samples.append(
			RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid),
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

	var sample_count: int = frame_ms_samples.size()
	if sample_count <= 0:
		printerr("GPU_BENCH: no samples collected")
		await _finish(scene)
		return

	var hud: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary
	print("GPU_BENCH_RESULT %s" % JSON.stringify({
		"label": _label,
		"zoom": _zoom,
		"hidden": _hidden_groups.keys(),
		"grass_lod_min_fraction": _grass_lod_override,
		"samples": sample_count,
		"frame_avg_ms": _mean(frame_ms_samples),
		"frame_p95_ms": _percentile(frame_ms_samples, 0.95),
		"frame_p99_ms": _percentile(frame_ms_samples, 0.99),
		"frame_max_ms": _percentile(frame_ms_samples, 1.0),
		"fps_from_avg": 1000.0 / maxf(_mean(frame_ms_samples), 0.001),
		"gpu_avg_ms": _mean(gpu_ms_samples),
		"gpu_p95_ms": _percentile(gpu_ms_samples, 0.95),
		"gpu_max_ms": _percentile(gpu_ms_samples, 1.0),
		"render_cpu_avg_ms": _mean(cpu_ms_samples),
		"render_cpu_p95_ms": _percentile(cpu_ms_samples, 0.95),
		"draw_calls_avg": draw_call_sum / float(sample_count),
		"draw_calls_max": draw_call_max,
		"render_objects_avg": object_sum / float(sample_count),
		"render_objects_max": object_max,
		"resident_views": int(hud.get("resident_views", -1)),
		"packet_count": int(hud.get("packet_count", -1)),
		"stream_radius": int(hud.get("stream_radius", -1)),
		"vram_mib": float(
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		) / 1048576.0,
		"ram_mib": float(
			Performance.get_monitor(Performance.MEMORY_STATIC),
		) / 1048576.0,
	}))
	await _finish(scene)


func _apply_hidden_groups(world_scene: Node, streamer: Node) -> void:
	if _hidden_groups.is_empty():
		return
	if _hidden_groups.has("postprocess"):
		var postprocess: Node = world_scene.get_node_or_null("PostProcessLayer")
		if postprocess != null:
			(postprocess as CanvasLayer).visible = false
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


func _apply_command_line_overrides() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_route_seconds = maxf(1.0, argument.trim_prefix("--seconds=").to_float())
		elif argument.begins_with("--zoom="):
			_zoom = clampf(argument.trim_prefix("--zoom=").to_float(), 0.05, 4.0)
		elif argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
		elif argument.begins_with("--grass-lod="):
			_grass_lod_override = clampf(
				argument.trim_prefix("--grass-lod=").to_float(),
				0.0,
				1.0,
			)
		elif argument.begins_with("--hide="):
			for group: String in argument.trim_prefix("--hide=").split(",", false):
				_hidden_groups[group.strip_edges()] = true


func _finish(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	quit(0)
