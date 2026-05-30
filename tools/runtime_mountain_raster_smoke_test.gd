extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var backend := WorldChunkPacketBackend.new()
	_assert(backend.has_method("queue_mountain_raster_request"), "WorldChunkPacketBackend must queue mountain raster work.")
	_assert(backend.has_method("drain_completed_mountain_rasters"), "WorldChunkPacketBackend must drain completed mountain raster work.")
	_assert(backend.has_method("has_completed_mountain_rasters"), "WorldChunkPacketBackend must expose completed mountain raster work.")
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		not streamer_source.contains("build_mountain_plateau_raster_image"),
		"WorldStreamer must not call the native raster builder directly."
	)
	_assert(
		not streamer_source.contains("WorldMountainRasterPresenter"),
		"WorldStreamer must own chunk render pages directly, not the retired merged presenter."
	)
	_assert(
		streamer_source.contains("_mountain_mask_backend"),
		"WorldStreamer must run chunk-owned mountain page work on a dedicated backend."
	)
	_assert(
		streamer_source.contains("_build_mountain_page_request_preset"),
		"WorldStreamer must build native runtime page presets explicitly."
	)
	_assert(
		streamer_source.contains("_sample_mountain_mask_hit"),
		"WorldStreamer must sample chunk page hit masks for gameplay queries."
	)
	_assert(
		streamer_source.contains("_resolve_mask_mining_tile"),
		"WorldStreamer must resolve visual contour mining back to authoritative tiles."
	)
	_assert(
		streamer_source.contains("_can_publish_chunk_with_mountain_mask"),
		"WorldStreamer must keep the mountain page publication seam explicit."
	)
	_assert(
		streamer_source.contains("runtime_emit_top_mask"),
		"WorldStreamer must request native top masks for the runtime split payload."
	)
	_assert(
		streamer_source.contains("runtime_edge_overlay_only"),
		"WorldStreamer must request cropped edge/facade overlays instead of full top RGBA pages."
	)
	_assert(
		streamer_source.contains("runtime_visual_clip_to_target_rect"),
		"WorldStreamer must tell native raster pages to clip visual overlay ownership to the target chunk."
	)
	_assert(
		streamer_source.contains("MOUNTAIN_MASK_WORKER_COUNT"),
		"WorldStreamer must run native page jobs on explicit workers."
	)
	_assert(
		streamer_source.contains("MOUNTAIN_PAGE_PREFETCH_RADIUS_CHUNKS")
			and streamer_source.contains("_is_mountain_page_prefetch_desired"),
		"WorldStreamer must prebuild mountain pages outside the visible ring."
	)
	_assert(
		streamer_source.contains("_build_mountain_page_dirty_chunks_for_tile")
			and streamer_source.contains("_mountain_mask_revision_by_chunk"),
		"WorldStreamer must use bounded per-page dirty invalidation for mining."
	)
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	_assert(
		chunk_view_source.contains("set_mountain_tile_visuals_enabled"),
		"ChunkView must expose square mountain tile suppression for runtime raster."
	)
	_assert(
		chunk_view_source.contains("_mountain_tile_visuals_enabled"),
		"ChunkView must track whether square mountain visuals are suppressed."
	)
	_assert(
		chunk_view_source.contains("_apply_ground_underlay_cell"),
		"ChunkView must draw ground under suppressed mountain tiles so unloaded raster areas do not become black rectangles."
	)
	_assert(
		chunk_view_source.contains("MountainTopMaskUnderlay") and chunk_view_source.contains("Image.FORMAT_L8"),
		"ChunkView must draw top underlay from a native L8 top mask."
	)
	_assert(
		chunk_view_source.contains("apply_mountain_render_page(result: Dictionary, top_texture: Texture2D"),
		"ChunkView must receive the reusable top texture when applying a page."
	)
	_assert(
		chunk_view_source.contains("_apply_mountain_full_top_fill")
			and chunk_view_source.contains("invalidate_mountain_render_page_hit_mask_keep_visual"),
		"ChunkView must draw interior fills through the same shader and preserve stale visuals while dirty hit masks rebuild."
	)

	var chunk := ChunkView.new()
	root.add_child(chunk)
	chunk.configure(Vector2i.ZERO)
	var result: Dictionary = _make_raster_result()
	var top_texture: ImageTexture = ImageTexture.create_from_image(_make_source_image(Color(0.78, 0.33, 0.10, 1.0)))
	chunk.apply_mountain_render_page(result, top_texture)
	await process_frame
	var debug: Dictionary = chunk.get_mountain_render_page_debug_state()
	_assert(bool(debug.get("ready", false)), "ChunkView must become ready from a native page result.")
	_assert(bool(debug.get("runtime_emit_top_mask", false)), "ChunkView debug must preserve native top mask metadata.")
	_assert(bool(debug.get("runtime_edge_overlay_only", false)), "ChunkView debug must preserve edge-overlay metadata.")
	_assert(bool(debug.get("runtime_visual_clip_to_target_rect", false)), "ChunkView debug must preserve visual chunk-clip metadata.")
	var solid_sample: Dictionary = chunk.sample_mountain_page_hit_at_world(Vector2(4.5, 4.5))
	_assert(bool(solid_sample.get("ready", false)), "Runtime page hit mask must be ready.")
	_assert(bool(solid_sample.get("in_bounds", false)), "Runtime page hit mask must sample in bounds.")
	_assert(bool(solid_sample.get("solid", false)), "Runtime page hit mask must detect solid pixels.")
	var empty_sample: Dictionary = chunk.sample_mountain_page_hit_at_world(Vector2(0.5, 0.5))
	_assert(bool(empty_sample.get("ready", false)), "Runtime page hit mask must stay ready on empty pixels.")
	_assert(not bool(empty_sample.get("solid", true)), "Runtime page hit mask must detect empty pixels.")
	chunk.queue_free()
	await process_frame

	if _failed:
		quit(1)
		return
	print("runtime_mountain_raster_smoke_test: OK")
	quit(0)

func _make_raster_result() -> Dictionary:
	var light_occluder := PackedVector2Array([
		Vector2(0, 0),
		Vector2(8, 0),
		Vector2(16, 0),
		Vector2(16, 8),
		Vector2(16, 16),
		Vector2(8, 16),
		Vector2(0, 16),
		Vector2(0, 8),
	])
	return {
		"success": true,
		"ready": true,
		"native": true,
		"normal_image": _make_source_image(Color(0.5, 0.5, 1.0, 1.0)),
		"mountain_image": _make_source_image(Color(0.78, 0.33, 0.10, 1.0)),
		"hit_mask": _make_hit_mask(),
		"hit_mask_width": 8,
		"hit_mask_height": 8,
		"hit_mask_origin_world": Vector2.ZERO,
		"hit_mask_step_px": 1.0,
		"hit_mask_solid_pixel_count": 16,
		"top_mask": _make_top_mask(),
		"top_mask_width": 8,
		"top_mask_height": 8,
		"top_mask_origin_world": Vector2.ZERO,
		"top_mask_step_px": 1.0,
		"light_occluder_polygon": light_occluder,
		"render_origin_world": Vector2.ZERO,
		"render_size_world": Vector2(16, 16),
		"mountain_tile_count": 1,
		"top_pixel_count": 64,
		"face_pixel_count": 16,
		"rim_pixel_count": 8,
		"image_width": 8,
		"image_height": 8,
		"normal_ready": true,
		"normal_image_width": 8,
		"normal_image_height": 8,
		"normal_pixel_count": 64,
		"light_occluder_point_count": light_occluder.size(),
		"runtime_emit_top_mask": true,
		"runtime_edge_overlay_only": true,
		"runtime_visual_clip_to_target_rect": true,
	}

func _make_hit_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(64)
	for y: int in range(2, 6):
		for x: int in range(2, 6):
			mask[y * 8 + x] = 1
	return mask

func _make_top_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(64)
	for y: int in range(2, 6):
		for x: int in range(2, 6):
			mask[y * 8 + x] = 255
	return mask

func _make_source_image(color: Color) -> Image:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
