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
const OBJECT_PRESENTATION_BREAKDOWN_KEYS: Array[String] = [
	"WorldStreamer.visual_upload.object_packet_priority_refresh",
	"WorldStreamer.visual_upload.object_packet_priority_repair",
	"WorldStreamer.visual_upload.object_packet_envelope.acquire_cold",
	"WorldStreamer.visual_upload.object_packet_envelope.acquire_pool",
	"WorldStreamer.visual_upload.object_packet_envelope.configure",
	"WorldStreamer.visual_upload.object_packet_envelope.tree_fixed",
	"WorldStreamer.visual_upload.object_packet_envelope.rock_fixed",
	"WorldStreamer.visual_upload.object_packet_envelope.collision_fixed",
	"WorldStreamer.visual_upload.object_packet_envelope.begin",
	"WorldStreamer.visual_upload.object_packet_slice.slot_allocation",
	"WorldStreamer.visual_upload.object_packet_slice.warmed_or_upload",
	"WorldStreamer.visual_upload.object_packet_anchor_rebase",
	"WorldObjectPacketLayer.tree.slot_allocate",
	"WorldObjectPacketLayer.tree.raw_visual_upload",
	"WorldObjectPacketLayer.tree.raw_shadow_upload",
	"WorldObjectPacketLayer.tree.ladder_register",
	"WorldObjectPacketLayer.rock.slot_allocate",
	"WorldObjectPacketLayer.rock.raw_visual_upload",
	"WorldObjectPacketLayer.rock.raw_shadow_upload",
	"WorldObjectPacketLayer.rock.ladder_register",
	"WorldObjectPacketLayer.collider_create_slice",
	"WorldObjectPacketLayer.commit",
]

var _frame_count: int = FRAME_COUNT
var _settle_frames: int = SETTLE_FRAMES
var _phase_frame_count: int = FRAME_COUNT
var _step_px: float = STEP_PX
var _print_progress: bool = false
var _streamer: Node = null
var _player: Node2D = null
var _max_streaming_ms: float = 0.0
var _max_object_presentation_dispatch_ms: float = 0.0
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
var _max_visual_object_packet_cache_commit_ms: float = 0.0
var _max_visual_object_packet_finalize_ms: float = 0.0
var _max_visual_object_packet_adopt_ms: float = 0.0
var _max_visual_object_packet_adopt_cache_take_ms: float = 0.0
var _max_visual_object_packet_adopt_view_ms: float = 0.0
var _max_visual_object_packet_reveal_ms: float = 0.0
var _max_object_adopt_parent_ms: float = 0.0
var _max_object_adopt_state_ms: float = 0.0
var _max_object_adopt_clear_ms: float = 0.0
var _max_object_adopt_lighting_ms: float = 0.0
var _max_object_adopt_ladder_ms: float = 0.0
var _max_visual_object_packet_envelope_ms: float = 0.0
var _max_visual_object_packet_anchor_rebase_ms: float = 0.0
var _max_visual_grass_scatter_ms: float = 0.0
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
var _max_object_upload_queue: int = 0
var _max_object_prestage_queue: int = 0
var _max_visibility_wait: int = 0
var _max_object_phases_in_one_frame: int = 0
var _combined_object_phase_frames: int = 0
var _samples: int = 0
var _object_presentation_breakdown_max: Dictionary = { }
var _object_presentation_breakdown_samples: Dictionary = { }

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_apply_command_line_overrides()
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
	for _i: int in range(_settle_frames):
		await _step_frame(false)
	var start: Vector2 = _player.global_position
	for frame_index: int in range(_frame_count):
		var phase: float = float(frame_index) / float(maxi(_phase_frame_count, 1))
		var x: float = (float(frame_index) - float(_frame_count) * 0.5) * _step_px
		var y: float = sin(phase * TAU * 3.0) * 820.0 + cos(phase * TAU * 1.7) * 340.0
		_player.global_position = start + Vector2(x, y)
		await _step_frame(true)
		if _print_progress and frame_index % 30 == 0:
			var progress_debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
			print(
				"world_streaming_perf_probe_progress frame=%d views=%d object_inflight=%d object_upload=%d object_prestage=%d hot_ready=%d hot_staging=%d visibility_wait=%d" % [
					frame_index,
					_streamer._chunk_views.size(),
					int(progress_debug.get("object_presentation_inflight_count", 0)),
					int(progress_debug.get("object_presentation_visual_upload_queue_count", 0)),
					int(progress_debug.get("object_presentation_prestage_queue_count", 0)),
					int(progress_debug.get("object_presentation_hot_cache_ready_count", 0)),
					int(progress_debug.get("object_presentation_hot_cache_staging_count", 0)),
					int(progress_debug.get("chunk_visibility_waiting_for_blocking_visual_count", 0)),
				]
			)
	_print_summary()
	scene.queue_free()
	await process_frame
	_streamer = null
	_player = null
	scene = null
	await process_frame
	await process_frame
	quit(0)


func _apply_command_line_overrides() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):
			_frame_count = maxi(1, int(argument.trim_prefix("--frames=")))
		elif argument.begins_with("--settle="):
			_settle_frames = maxi(0, int(argument.trim_prefix("--settle=")))
		elif argument.begins_with("--phase-frames="):
			_phase_frame_count = maxi(1, int(argument.trim_prefix("--phase-frames=")))
		elif argument.begins_with("--step-px="):
			_step_px = maxf(0.0, float(argument.trim_prefix("--step-px=")))
		elif argument == "--progress":
			_print_progress = true

func _step_frame(record_sample: bool) -> void:
	await process_frame
	var frame_ops: Dictionary = WorldPerfProbe.flush_frame()
	if not record_sample:
		return
	var world_streaming_ms: float = float(frame_ops.get(
		"FrameBudgetDispatcher.streaming.world.streaming_v0",
		0.0
	))
	var object_presentation_dispatch_ms: float = float(frame_ops.get(
		"FrameBudgetDispatcher.streaming.world.object_presentation_visual_upload",
		0.0
	))
	# Object presentation owns a separate dispatcher job now. Sum both streaming
	# jobs so the A/B result cannot hide upload time by moving it to another key.
	var streaming_ms: float = world_streaming_ms + object_presentation_dispatch_ms
	var visual_ms: float = float(frame_ops.get(
		"FrameBudgetDispatcher.visual.world.mountain_native_mask_visual_upload",
		0.0
	))
	var total_ms: float = float(frame_ops.get("FrameBudgetDispatcher.total", 0.0))
	for breakdown_key: String in OBJECT_PRESENTATION_BREAKDOWN_KEYS:
		var breakdown_value: float = float(frame_ops.get(breakdown_key, 0.0))
		_object_presentation_breakdown_max[breakdown_key] = maxf(
			float(_object_presentation_breakdown_max.get(breakdown_key, 0.0)),
			breakdown_value,
		)
		# These phases are sparse events. Keeping only event frames makes p95
		# describe cold/reuse work instead of being diluted by idle zeroes.
		if breakdown_value > 0.0:
			var breakdown_samples: Array = _object_presentation_breakdown_samples.get(
				breakdown_key,
				[],
			) as Array
			breakdown_samples.append(breakdown_value)
			_object_presentation_breakdown_samples[breakdown_key] = breakdown_samples
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
		"WorldStreamer.visual_upload.object_packet_slice",
		0.0
	)))
	_max_visual_object_packet_cache_commit_ms = maxf(
		_max_visual_object_packet_cache_commit_ms,
		float(frame_ops.get("WorldStreamer.visual_upload.object_packet_cache_commit", 0.0)),
	)
	_max_visual_object_packet_finalize_ms = maxf(
		_max_visual_object_packet_finalize_ms,
		float(frame_ops.get("WorldStreamer.visual_upload.object_packet_finalize", 0.0)),
	)
	_max_visual_object_packet_adopt_ms = maxf(
		_max_visual_object_packet_adopt_ms,
		float(frame_ops.get("WorldStreamer.visual_upload.object_packet_adopt", 0.0)),
	)
	_max_visual_object_packet_adopt_cache_take_ms = maxf(
		_max_visual_object_packet_adopt_cache_take_ms,
		float(frame_ops.get(
			"WorldStreamer.visual_upload.object_packet_adopt.cache_take",
			0.0,
		)),
	)
	_max_visual_object_packet_adopt_view_ms = maxf(
		_max_visual_object_packet_adopt_view_ms,
		float(frame_ops.get("WorldStreamer.visual_upload.object_packet_adopt.view", 0.0)),
	)
	_max_visual_object_packet_reveal_ms = maxf(
		_max_visual_object_packet_reveal_ms,
		float(frame_ops.get("WorldStreamer.visual_upload.object_packet_reveal", 0.0)),
	)
	_max_object_adopt_parent_ms = maxf(
		_max_object_adopt_parent_ms,
		float(frame_ops.get("ChunkView.object_adopt.parent", 0.0)),
	)
	_max_object_adopt_state_ms = maxf(
		_max_object_adopt_state_ms,
		float(frame_ops.get("ChunkView.object_adopt.state", 0.0)),
	)
	_max_object_adopt_clear_ms = maxf(
		_max_object_adopt_clear_ms,
		float(frame_ops.get("ChunkView.object_adopt.clear_staging", 0.0)),
	)
	_max_object_adopt_lighting_ms = maxf(
		_max_object_adopt_lighting_ms,
		float(frame_ops.get("ChunkView.object_adopt.lighting", 0.0)),
	)
	_max_object_adopt_ladder_ms = maxf(
		_max_object_adopt_ladder_ms,
		float(frame_ops.get("ChunkView.object_adopt.ladder", 0.0)),
	)
	_max_visual_object_packet_envelope_ms = maxf(
		_max_visual_object_packet_envelope_ms,
		float(frame_ops.get("WorldStreamer.visual_upload.object_packet_envelope", 0.0)),
	)
	_max_visual_object_packet_anchor_rebase_ms = maxf(
		_max_visual_object_packet_anchor_rebase_ms,
		float(frame_ops.get("WorldStreamer.visual_upload.object_packet_anchor_rebase", 0.0)),
	)
	var object_phase_count: int = 0
	for object_phase_key: String in [
		"WorldStreamer.visual_upload.object_packet_envelope",
		"WorldStreamer.visual_upload.object_packet_anchor_rebase",
		"WorldStreamer.visual_upload.object_packet_slice",
		"WorldStreamer.visual_upload.object_packet_cache_commit",
		"WorldStreamer.visual_upload.object_packet_finalize",
	]:
		if float(frame_ops.get(object_phase_key, 0.0)) > 0.0:
			object_phase_count += 1
	_max_object_phases_in_one_frame = maxi(_max_object_phases_in_one_frame, object_phase_count)
	if object_phase_count > 1:
		_combined_object_phase_frames += 1
	_max_visual_grass_scatter_ms = maxf(_max_visual_grass_scatter_ms, float(frame_ops.get(
		"WorldStreamer.visual_upload.grass_scatter",
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
	_max_object_presentation_dispatch_ms = maxf(
		_max_object_presentation_dispatch_ms,
		object_presentation_dispatch_ms,
	)
	_max_visual_ms = maxf(_max_visual_ms, visual_ms)
	_max_total_ms = maxf(_max_total_ms, total_ms)
	if streaming_ms > 1.5 or total_ms > 6.0:
		_over_budget_frames += 1
	var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
	var pending_masks: int = int(debug.get("native_mask_inflight_count", 0)) \
		+ int(debug.get("terrain_edge_mask_inflight_count", 0)) \
		+ int(debug.get("native_mask_visual_upload_queue_count", 0)) \
		+ int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) \
		+ int(debug.get("object_presentation_inflight_count", 0)) \
		+ int(debug.get("object_presentation_visual_upload_queue_count", 0)) \
		+ int(debug.get("object_presentation_prestage_queue_count", 0))
	_max_pending_masks = maxi(_max_pending_masks, pending_masks)
	_max_publish_queue = maxi(_max_publish_queue, _streamer._pending_publish_queue.size())
	_max_object_upload_queue = maxi(
		_max_object_upload_queue,
		int(debug.get("object_presentation_visual_upload_queue_count", 0)),
	)
	_max_object_prestage_queue = maxi(
		_max_object_prestage_queue,
		int(debug.get("object_presentation_prestage_queue_count", 0)),
	)
	_max_visibility_wait = maxi(
		_max_visibility_wait,
		int(debug.get("chunk_visibility_waiting_for_blocking_visual_count", 0)),
	)

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
		"world_streaming_perf_probe_worker_details: shared_workers=%d logical_cpus=%d grass_worker_max=%.3fms grass_request_to_complete_max=%.3fms object_worker_max=%.3fms object_request_to_complete_max=%.3fms warm_packet_cache=%d/%d warm_packet_hits=%d warm_object_cache=%d bytes=%d/%d hits=%d" % [
			int(debug.get("world_compute_worker_count", 0)),
			int(debug.get("world_compute_logical_processor_count", 0)),
			float(debug.get("grass_scatter_worker_elapsed_ms_max_total", 0.0)),
			float(debug.get("grass_scatter_request_to_complete_ms_max_total", 0.0)),
			float(debug.get("object_presentation_worker_elapsed_ms_max_total", 0.0)),
			float(debug.get("object_presentation_request_to_complete_ms_max_total", 0.0)),
			int(debug.get("warm_packet_cache_count", 0)),
			int(debug.get("warm_packet_cache_capacity", 0)),
			int(debug.get("warm_packet_cache_hit_count_total", 0)),
			int(debug.get("object_presentation_warm_cache_count", 0)),
			int(debug.get("object_presentation_warm_cache_bytes", 0)),
			int(debug.get("object_presentation_warm_cache_max_bytes", 0)),
			int(debug.get("object_presentation_cache_hit_count_total", 0)),
		]
	)
	print(
		"world_streaming_perf_probe_object_queues: upload=%d prestage=%d hot_ready=%d hot_staging=%d max_upload=%d max_prestage=%d max_visibility_wait=%d" % [
			int(debug.get("object_presentation_visual_upload_queue_count", 0)),
			int(debug.get("object_presentation_prestage_queue_count", 0)),
			int(debug.get("object_presentation_hot_cache_ready_count", 0)),
			int(debug.get("object_presentation_hot_cache_staging_count", 0)),
			_max_object_upload_queue,
			_max_object_prestage_queue,
			_max_visibility_wait,
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
		"world_streaming_perf_probe_visual_details: max_ensure_mountain_sources=%.3fms max_ensure_terrain_sources=%.3fms max_mountain_create_image=%.3fms max_mountain_upload_texture=%.3fms max_terrain_edge_create_image=%.3fms max_terrain_edge_upload_texture=%.3fms max_object_packet_slice=%.3fms max_object_packet_cache_commit=%.3fms max_object_packet_finalize=%.3fms max_object_packet_adopt=%.3fms max_object_packet_adopt_cache_take=%.3fms max_object_packet_adopt_view=%.3fms max_object_packet_reveal=%.3fms max_object_packet_envelope=%.3fms max_object_packet_anchor_rebase=%.3fms max_object_dispatch=%.3fms max_object_phases_per_frame=%d combined_object_phase_frames=%d max_grass_scatter_apply=%.3fms" % [
			_max_visual_ensure_mountain_sources_ms,
			_max_visual_ensure_terrain_sources_ms,
			_max_mountain_visual_create_image_ms,
			_max_mountain_visual_upload_texture_ms,
			_max_terrain_edge_visual_create_image_ms,
			_max_terrain_edge_visual_upload_texture_ms,
			_max_visual_object_packet_ms,
			_max_visual_object_packet_cache_commit_ms,
			_max_visual_object_packet_finalize_ms,
			_max_visual_object_packet_adopt_ms,
			_max_visual_object_packet_adopt_cache_take_ms,
			_max_visual_object_packet_adopt_view_ms,
			_max_visual_object_packet_reveal_ms,
			_max_visual_object_packet_envelope_ms,
			_max_visual_object_packet_anchor_rebase_ms,
			_max_object_presentation_dispatch_ms,
			_max_object_phases_in_one_frame,
			_combined_object_phase_frames,
			_max_visual_grass_scatter_ms,
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
	print(
		"world_streaming_perf_probe_object_adopt_details: parent=%.3fms state=%.3fms clear=%.3fms lighting=%.3fms ladder=%.3fms" % [
			_max_object_adopt_parent_ms,
			_max_object_adopt_state_ms,
			_max_object_adopt_clear_ms,
			_max_object_adopt_lighting_ms,
			_max_object_adopt_ladder_ms,
		]
	)
	print(
		"world_streaming_perf_probe_object_phase_breakdown_max: %s" \
				% JSON.stringify(_object_presentation_breakdown_max),
	)
	var object_phase_stats: Dictionary = { }
	for breakdown_key: String in OBJECT_PRESENTATION_BREAKDOWN_KEYS:
		var breakdown_samples: Array = _object_presentation_breakdown_samples.get(
			breakdown_key,
			[],
		) as Array
		if breakdown_samples.is_empty():
			continue
		var sorted_samples: Array = breakdown_samples.duplicate()
		sorted_samples.sort()
		var p95_index: int = clampi(
			ceili(float(sorted_samples.size()) * 0.95) - 1,
			0,
			sorted_samples.size() - 1,
		)
		object_phase_stats[breakdown_key] = {
			"events": sorted_samples.size(),
			"p95_ms": float(sorted_samples[p95_index]),
			"max_ms": float(_object_presentation_breakdown_max.get(breakdown_key, 0.0)),
		}
	print(
		"world_streaming_perf_probe_object_phase_event_stats: %s" \
				% JSON.stringify(object_phase_stats),
	)
