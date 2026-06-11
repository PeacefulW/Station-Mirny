extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const FRAME_COUNT: int = 900
const SETTLE_FRAMES: int = 180
const STEP_PX: float = 42.0

var _streamer: Node = null
var _player: Node2D = null
var _max_streaming_ms: float = 0.0
var _max_visual_ms: float = 0.0
var _max_total_ms: float = 0.0
var _max_publish_begin_ms: float = 0.0
var _max_publish_begin_mountain_ready_ms: float = 0.0
var _max_publish_begin_terrain_edge_prepare_ms: float = 0.0
var _max_publish_begin_track_roof_ms: float = 0.0
var _max_publish_begin_ensure_view_ms: float = 0.0
var _max_publish_begin_apply_mountain_mask_ms: float = 0.0
var _max_publish_begin_apply_terrain_edge_mask_ms: float = 0.0
var _max_publish_begin_chunk_begin_apply_ms: float = 0.0
var _max_publish_apply_ms: float = 0.0
var _max_publish_finalize_ms: float = 0.0
var _max_visual_ensure_mountain_sources_ms: float = 0.0
var _max_visual_ensure_terrain_sources_ms: float = 0.0
var _max_mountain_visual_create_image_ms: float = 0.0
var _max_mountain_visual_upload_texture_ms: float = 0.0
var _max_terrain_edge_visual_create_image_ms: float = 0.0
var _max_terrain_edge_visual_upload_texture_ms: float = 0.0
var _max_visual_object_packet_ms: float = 0.0
var _max_chunk_begin_copy_packet_ms: float = 0.0
var _max_chunk_begin_state_ms: float = 0.0
var _max_chunk_begin_ensure_layers_ms: float = 0.0
var _max_chunk_begin_sync_water_ms: float = 0.0
var _max_chunk_begin_sync_objects_ms: float = 0.0
var _max_chunk_begin_refresh_debug_ms: float = 0.0
var _sum_streaming_ms: float = 0.0
var _sum_total_ms: float = 0.0
var _over_budget_frames: int = 0
var _max_pending_masks: int = 0
var _max_publish_queue: int = 0
var _samples: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	_player = scene.get_node_or_null("Player") as Node2D
	assert(_streamer != null, "world_streaming_perf_probe requires WorldStreamer")
	assert(_player != null, "world_streaming_perf_probe requires Player")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		mountain,
		bounds,
		foundation,
		lakes
	)
	var time_manager: Node = root.get_node_or_null("TimeManager")
	if time_manager != null:
		time_manager.call("set_paused", true)
		time_manager.call("restore_persisted_state", 7.0, 1, 0)
		time_manager.call("set_paused", true)
	for _i: int in range(SETTLE_FRAMES):
		await _step_frame(false)
	var start: Vector2 = _player.global_position
	for frame_index: int in range(FRAME_COUNT):
		var phase: float = float(frame_index) / float(FRAME_COUNT)
		var x: float = (float(frame_index) - float(FRAME_COUNT) * 0.5) * STEP_PX
		var y: float = sin(phase * TAU * 3.0) * 820.0 + cos(phase * TAU * 1.7) * 340.0
		_player.global_position = start + Vector2(x, y)
		await _step_frame(true)
	_print_summary()
	scene.queue_free()
	await process_frame
	quit(0)

func _step_frame(record_sample: bool) -> void:
	await process_frame
	var frame_ops: Dictionary = WorldPerfProbe.flush_frame()
	if not record_sample:
		return
	var streaming_ms: float = float(frame_ops.get(
		"FrameBudgetDispatcher.streaming.world.streaming_v0",
		0.0
	))
	var visual_ms: float = float(frame_ops.get(
		"FrameBudgetDispatcher.visual.world.mountain_native_mask_visual_upload",
		0.0
	))
	var total_ms: float = float(frame_ops.get("FrameBudgetDispatcher.total", 0.0))
	_max_publish_begin_ms = maxf(_max_publish_begin_ms, float(frame_ops.get(
		"WorldStreamer.publish.begin",
		0.0
	)))
	_max_publish_begin_mountain_ready_ms = maxf(_max_publish_begin_mountain_ready_ms, float(frame_ops.get(
		"WorldStreamer.publish.begin.mountain_ready",
		0.0
	)))
	_max_publish_begin_terrain_edge_prepare_ms = maxf(_max_publish_begin_terrain_edge_prepare_ms, float(frame_ops.get(
		"WorldStreamer.publish.begin.terrain_edge_prepare",
		0.0
	)))
	_max_publish_begin_track_roof_ms = maxf(_max_publish_begin_track_roof_ms, float(frame_ops.get(
		"WorldStreamer.publish.begin.track_roof",
		0.0
	)))
	_max_publish_begin_ensure_view_ms = maxf(_max_publish_begin_ensure_view_ms, float(frame_ops.get(
		"WorldStreamer.publish.begin.ensure_view",
		0.0
	)))
	_max_publish_begin_apply_mountain_mask_ms = maxf(_max_publish_begin_apply_mountain_mask_ms, float(frame_ops.get(
		"WorldStreamer.publish.begin.apply_mountain_mask",
		0.0
	)))
	_max_publish_begin_apply_terrain_edge_mask_ms = maxf(_max_publish_begin_apply_terrain_edge_mask_ms, float(frame_ops.get(
		"WorldStreamer.publish.begin.apply_terrain_edge_mask",
		0.0
	)))
	_max_publish_begin_chunk_begin_apply_ms = maxf(_max_publish_begin_chunk_begin_apply_ms, float(frame_ops.get(
		"WorldStreamer.publish.begin.chunk_begin_apply",
		0.0
	)))
	_max_publish_apply_ms = maxf(_max_publish_apply_ms, float(frame_ops.get(
		"WorldStreamer.publish.apply_batch",
		0.0
	)))
	_max_publish_finalize_ms = maxf(_max_publish_finalize_ms, float(frame_ops.get(
		"WorldStreamer.publish.finalize",
		0.0
	)))
	_max_visual_ensure_mountain_sources_ms = maxf(_max_visual_ensure_mountain_sources_ms, float(frame_ops.get(
		"WorldStreamer.visual_upload.ensure_mountain_sources",
		0.0
	)))
	_max_visual_ensure_terrain_sources_ms = maxf(_max_visual_ensure_terrain_sources_ms, float(frame_ops.get(
		"WorldStreamer.visual_upload.ensure_terrain_sources",
		0.0
	)))
	_max_mountain_visual_create_image_ms = maxf(_max_mountain_visual_create_image_ms, float(frame_ops.get(
		"ChunkView.mountain_visual.create_image",
		0.0
	)))
	_max_mountain_visual_upload_texture_ms = maxf(_max_mountain_visual_upload_texture_ms, float(frame_ops.get(
		"ChunkView.mountain_visual.upload_texture",
		0.0
	)))
	_max_terrain_edge_visual_create_image_ms = maxf(_max_terrain_edge_visual_create_image_ms, float(frame_ops.get(
		"ChunkView.terrain_edge_visual.create_image",
		0.0
	)))
	_max_terrain_edge_visual_upload_texture_ms = maxf(_max_terrain_edge_visual_upload_texture_ms, float(frame_ops.get(
		"ChunkView.terrain_edge_visual.upload_texture",
		0.0
	)))
	_max_visual_object_packet_ms = maxf(_max_visual_object_packet_ms, float(frame_ops.get(
		"WorldStreamer.visual_upload.object_packet",
		0.0
	)))
	_max_chunk_begin_copy_packet_ms = maxf(_max_chunk_begin_copy_packet_ms, float(frame_ops.get(
		"ChunkView.begin_apply.copy_packet",
		0.0
	)))
	_max_chunk_begin_state_ms = maxf(_max_chunk_begin_state_ms, float(frame_ops.get(
		"ChunkView.begin_apply.state",
		0.0
	)))
	_max_chunk_begin_ensure_layers_ms = maxf(_max_chunk_begin_ensure_layers_ms, float(frame_ops.get(
		"ChunkView.begin_apply.ensure_layers",
		0.0
	)))
	_max_chunk_begin_sync_water_ms = maxf(_max_chunk_begin_sync_water_ms, float(frame_ops.get(
		"ChunkView.begin_apply.sync_water_fill",
		0.0
	)))
	_max_chunk_begin_sync_objects_ms = maxf(_max_chunk_begin_sync_objects_ms, float(frame_ops.get(
		"ChunkView.begin_apply.sync_objects",
		0.0
	)))
	_max_chunk_begin_refresh_debug_ms = maxf(_max_chunk_begin_refresh_debug_ms, float(frame_ops.get(
		"ChunkView.begin_apply.refresh_debug",
		0.0
	)))
	_samples += 1
	_sum_streaming_ms += streaming_ms
	_sum_total_ms += total_ms
	_max_streaming_ms = maxf(_max_streaming_ms, streaming_ms)
	_max_visual_ms = maxf(_max_visual_ms, visual_ms)
	_max_total_ms = maxf(_max_total_ms, total_ms)
	if streaming_ms > 1.5 or total_ms > 6.0:
		_over_budget_frames += 1
	var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
	var pending_masks: int = int(debug.get("native_mask_inflight_count", 0)) \
		+ int(debug.get("terrain_edge_mask_inflight_count", 0)) \
		+ int(debug.get("native_mask_visual_upload_queue_count", 0)) \
		+ int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0))
	_max_pending_masks = maxi(_max_pending_masks, pending_masks)
	_max_publish_queue = maxi(_max_publish_queue, _streamer._pending_publish_queue.size())

func _print_summary() -> void:
	var avg_streaming: float = _sum_streaming_ms / maxf(1.0, float(_samples))
	var avg_total: float = _sum_total_ms / maxf(1.0, float(_samples))
	var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
	print(
		"world_streaming_perf_probe: samples=%d avg_streaming=%.3fms max_streaming=%.3fms avg_total=%.3fms max_total=%.3fms max_visual=%.3fms max_publish_begin=%.3fms max_publish_apply=%.3fms max_publish_finalize=%.3fms over_budget_frames=%d max_pending_masks=%d max_publish_queue=%d native_halo=%d terrain_edge_inflight=%d terrain_edge_cached=%d" % [
			_samples,
			avg_streaming,
			_max_streaming_ms,
			avg_total,
			_max_total_ms,
			_max_visual_ms,
			_max_publish_begin_ms,
			_max_publish_apply_ms,
			_max_publish_finalize_ms,
			_over_budget_frames,
			_max_pending_masks,
			_max_publish_queue,
			int(debug.get("native_mask_halo_radius_tiles", 0)),
			int(debug.get("terrain_edge_mask_inflight_count", 0)),
			int(debug.get("terrain_edge_mask_cached_count", 0)),
		]
	)
	print(
		"world_streaming_perf_probe_details: max_mountain_ready=%.3fms max_terrain_edge_prepare=%.3fms max_track_roof=%.3fms max_ensure_view=%.3fms max_apply_mountain_mask=%.3fms max_apply_terrain_edge_mask=%.3fms max_chunk_begin_apply=%.3fms" % [
			_max_publish_begin_mountain_ready_ms,
			_max_publish_begin_terrain_edge_prepare_ms,
			_max_publish_begin_track_roof_ms,
			_max_publish_begin_ensure_view_ms,
			_max_publish_begin_apply_mountain_mask_ms,
			_max_publish_begin_apply_terrain_edge_mask_ms,
			_max_publish_begin_chunk_begin_apply_ms,
		]
	)
	print(
		"world_streaming_perf_probe_visual_details: max_ensure_mountain_sources=%.3fms max_ensure_terrain_sources=%.3fms max_mountain_create_image=%.3fms max_mountain_upload_texture=%.3fms max_terrain_edge_create_image=%.3fms max_terrain_edge_upload_texture=%.3fms max_object_packet=%.3fms" % [
			_max_visual_ensure_mountain_sources_ms,
			_max_visual_ensure_terrain_sources_ms,
			_max_mountain_visual_create_image_ms,
			_max_mountain_visual_upload_texture_ms,
			_max_terrain_edge_visual_create_image_ms,
			_max_terrain_edge_visual_upload_texture_ms,
			_max_visual_object_packet_ms,
		]
	)
	print(
		"world_streaming_perf_probe_chunk_begin_details: max_copy_packet=%.3fms max_state=%.3fms max_ensure_layers=%.3fms max_sync_water=%.3fms max_sync_objects=%.3fms max_refresh_debug=%.3fms" % [
			_max_chunk_begin_copy_packet_ms,
			_max_chunk_begin_state_ms,
			_max_chunk_begin_ensure_layers_ms,
			_max_chunk_begin_sync_water_ms,
			_max_chunk_begin_sync_objects_ms,
			_max_chunk_begin_refresh_debug_ms,
		]
	)
