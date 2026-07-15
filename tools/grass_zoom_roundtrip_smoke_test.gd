extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const GrassRenderPage = preload("res://core/systems/world/grass_render_page.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const ZOOM_IN: float = 1.0
const ZOOM_OUT: float = 0.2
const SETTLE_TIMEOUT_FRAMES: int = 1200

var _failures: Array[String] = []
var _streamer: Node = null
var _camera: Camera2D = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	_camera = root.get_viewport().get_camera_2d()
	_expect(_streamer != null, "zoom round-trip requires WorldStreamer")
	_expect(_camera != null, "zoom round-trip requires the player Camera2D")
	if _streamer == null or _camera == null:
		_finish(scene)
		return

	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
	)
	var time_manager: Node = root.get_node_or_null("TimeManager")
	if time_manager != null:
		time_manager.call("set_paused", true)

	_set_zoom(ZOOM_IN)
	var initial: Dictionary = await _wait_for_committed_visible_grass(2)
	_expect(
		bool(initial.get("settled", false)),
		"initial radius-2 grass did not settle: %s" % initial.get("blockers", "unknown"),
	)

	_set_zoom(ZOOM_OUT)
	var first_out: Dictionary = await _wait_for_committed_visible_grass(4)
	_expect(
		bool(first_out.get("settled", false)),
		"first radius-4 grass did not settle: %s" % first_out.get("blockers", "unknown"),
	)
	var zoomed_out_coords: Array[Vector2i] = \
			_streamer._desired_visible_chunk_coords.duplicate()

	_set_zoom(ZOOM_IN)
	var zoomed_in: Dictionary = await _wait_for_committed_visible_grass(2)
	_expect(
		bool(zoomed_in.get("settled", false)),
		"zoom-in eviction did not settle: %s" % zoomed_in.get("blockers", "unknown"),
	)
	var zoomed_in_coords: Array[Vector2i] = \
			_streamer._desired_visible_chunk_coords.duplicate()
	var returned_outer_slots: int = _count_coords_not_in(
		zoomed_out_coords,
		zoomed_in_coords,
	)
	var returned_outer_pages: int = _count_pages_not_fully_visible(
		zoomed_out_coords,
		zoomed_in_coords,
	)
	_expect(_streamer._hot_chunk_view_cache.size() >= returned_outer_slots,
		"hot ChunkView cache must retain the complete radius-4 outer ring")

	var page_mode: bool = bool(_streamer._grass_render_pages_enabled)
	var preserve_hits_before: int = _streamer._hot_chunk_view_grass_preserve_hit_count_total
	var terrain_hits_before: int = _streamer._hot_chunk_view_terrain_preserve_hit_count_total
	var page_before: Dictionary = _get_page_debug_state()
	_set_zoom(ZOOM_OUT)
	var second_out: Dictionary = await _wait_for_committed_visible_grass(4)
	_expect(
		bool(second_out.get("settled", false)),
		"second radius-4 grass did not settle: %s" % second_out.get("blockers", "unknown"),
	)
	var preserve_delta: int = \
			_streamer._hot_chunk_view_grass_preserve_hit_count_total - preserve_hits_before
	var terrain_delta: int = \
			_streamer._hot_chunk_view_terrain_preserve_hit_count_total - terrain_hits_before
	_expect(terrain_delta >= returned_outer_slots,
		"second zoom-out preserved %d/%d exact outer-ring terrain TileMaps" % [
			terrain_delta,
			returned_outer_slots,
		])
	_expect(int(second_out.get("max_inflight", -1)) == 0,
		"exact zoom round-trip must not enqueue grass worker recompute")
	if page_mode:
		_assert_page_round_trip_reused_cache(
			page_before,
			_get_page_debug_state(),
			second_out,
			returned_outer_slots,
		)
	else:
		_expect(preserve_delta >= returned_outer_slots,
			"second zoom-out must preserve every exact outer-ring grass GPU graph")
		_expect(int(second_out.get("max_upload_queue", -1)) == 0,
			"exact zoom round-trip must not enqueue grass GPU re-upload")

	if _failures.is_empty():
		print(
			(
				"grass_zoom_roundtrip_smoke_test: mode=%s initial_frames=%d " \
						+ "first_out_frames=%d " \
						+ "zoom_in_frames=%d second_out_frames=%d outer_ring=%d " \
						+ "outer_pages=%d grass_preserve_hits=%d terrain_preserve_hits=%d " \
						+ "second_upload_queue_max=%d second_page_queue_max=%d PASS"
			) % [
				"page" if page_mode else "legacy",
				int(initial.get("frames", 0)),
				int(first_out.get("frames", 0)),
				int(zoomed_in.get("frames", 0)),
				int(second_out.get("frames", 0)),
				returned_outer_slots,
				returned_outer_pages,
				preserve_delta,
				terrain_delta,
				int(second_out.get("max_upload_queue", 0)),
				int(second_out.get("max_page_upload_queue", 0)),
			]
		)
	_finish(scene)


func _set_zoom(value: float) -> void:
	_camera.set("_target_zoom", value)
	_camera.zoom = Vector2(value, value)


func _wait_for_committed_visible_grass(expected_radius: int) -> Dictionary:
	var max_upload_queue: int = 0
	var max_inflight: int = 0
	var max_page_inflight: int = 0
	var max_page_ready: int = 0
	var max_page_upload_queue: int = 0
	var last_debug: Dictionary = { }
	for frame_index: int in range(SETTLE_TIMEOUT_FRAMES):
		await process_frame
		var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
		last_debug = debug
		max_upload_queue = maxi(
			max_upload_queue,
			int(debug.get("grass_scatter_visual_upload_queue_count", 0)),
		)
		max_inflight = maxi(
			max_inflight,
			int(debug.get("grass_scatter_inflight_count", 0)),
		)
		max_page_inflight = maxi(
			max_page_inflight,
			int(debug.get("grass_render_page_inflight_count", 0)),
		)
		max_page_ready = maxi(
			max_page_ready,
			int(debug.get("grass_render_page_ready_visual_count", 0)),
		)
		max_page_upload_queue = maxi(
			max_page_upload_queue,
			int(debug.get("grass_render_page_visual_upload_queue_count", 0)),
		)
		if _streamer._current_stream_radius_chunks != expected_radius:
			continue
		if _all_visible_grass_committed(debug):
			return {
				"settled": true,
				"frames": frame_index + 1,
				"max_upload_queue": max_upload_queue,
				"max_inflight": max_inflight,
				"max_page_inflight": max_page_inflight,
				"max_page_ready": max_page_ready,
				"max_page_upload_queue": max_page_upload_queue,
			}
	return {
		"settled": false,
		"frames": SETTLE_TIMEOUT_FRAMES,
		"max_upload_queue": max_upload_queue,
		"max_inflight": max_inflight,
		"max_page_inflight": max_page_inflight,
		"max_page_ready": max_page_ready,
		"max_page_upload_queue": max_page_upload_queue,
		"blockers": _describe_settle_blockers(last_debug),
	}


func _all_visible_grass_committed(debug: Dictionary) -> bool:
	if _streamer._desired_visible_chunk_coords.is_empty():
		return false
	if _streamer._chunk_views.size() != _streamer._desired_visible_chunk_coords.size():
		return false
	if int(debug.get("grass_scatter_visual_upload_queue_count", 0)) != 0 \
			or int(debug.get("grass_scatter_inflight_count", 0)) != 0:
		return false
	var page_mode: bool = bool(debug.get("grass_render_pages_enabled", false))
	if page_mode:
		if int(debug.get("grass_render_page_inflight_count", 0)) != 0 \
				or int(debug.get("grass_render_page_ready_visual_count", 0)) != 0 \
				or int(debug.get("grass_render_page_visual_upload_queue_count", 0)) != 0 \
				or _streamer._grass_render_page_manager.has_pending_visual_upload():
			return false
	for coord: Vector2i in _streamer._desired_visible_chunk_coords:
		var view: Node = _streamer._chunk_views.get(coord, null) as Node
		if view == null or not view.is_terrain_cell_presentation_committed():
			return false
		if page_mode:
			if not _streamer._grass_scatter_revision_by_chunk.has(coord):
				return false
			var revision: int = int(_streamer._grass_scatter_revision_by_chunk[coord])
			if not _streamer._grass_render_page_manager.is_chunk_committed(
				coord,
				revision,
			):
				return false
		elif not view.is_grass_scatter_presentation_committed():
			return false
	return true


func _describe_settle_blockers(debug: Dictionary) -> String:
	var missing_terrain: int = 0
	var missing_grass: int = 0
	var missing_revision: int = 0
	var page_mode: bool = bool(debug.get("grass_render_pages_enabled", false))
	for coord: Vector2i in _streamer._desired_visible_chunk_coords:
		var view: Node = _streamer._chunk_views.get(coord, null) as Node
		if view == null or not view.is_terrain_cell_presentation_committed():
			missing_terrain += 1
		if page_mode:
			if not _streamer._grass_scatter_revision_by_chunk.has(coord):
				missing_revision += 1
				continue
			var revision: int = int(_streamer._grass_scatter_revision_by_chunk[coord])
			if not _streamer._grass_render_page_manager.is_chunk_committed(
				coord,
				revision,
			):
				missing_grass += 1
		elif view == null or not view.is_grass_scatter_presentation_committed():
			missing_grass += 1
	return (
		"mode=%s radius=%d desired=%d views=%d terrain_missing=%d " \
				+ "grass_missing=%d revision_missing=%d scatter_inflight=%d " \
				+ "scatter_upload=%d page_inflight=%d page_ready=%d page_upload=%d " \
				+ "page_pending=%s missing_slots=%s"
	) % [
		"page" if page_mode else "legacy",
		_streamer._current_stream_radius_chunks,
		_streamer._desired_visible_chunk_coords.size(),
		_streamer._chunk_views.size(),
		missing_terrain,
		missing_grass,
		missing_revision,
		int(debug.get("grass_scatter_inflight_count", 0)),
		int(debug.get("grass_scatter_visual_upload_queue_count", 0)),
		int(debug.get("grass_render_page_inflight_count", 0)),
		int(debug.get("grass_render_page_ready_visual_count", 0)),
		int(debug.get("grass_render_page_visual_upload_queue_count", 0)),
		str(
			page_mode \
					and _streamer._grass_render_page_manager.has_pending_visual_upload(),
		),
		_describe_missing_page_slots() if page_mode else "[]",
	]


func _describe_missing_page_slots() -> String:
	var descriptions: Array[String] = []
	var manager: Object = _streamer._grass_render_page_manager
	for coord: Vector2i in _streamer._desired_visible_chunk_coords:
		var revision: int = int(_streamer._grass_scatter_revision_by_chunk.get(coord, -1))
		if manager.is_chunk_committed(coord, revision):
			continue
		var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(coord)
		var slot: int = GrassRenderPage.page_slot_for_chunk(coord)
		var entry: Dictionary = manager._entries.get(page_coord, { }) as Dictionary
		var contributor_revisions: PackedInt64Array = entry.get(
			"contributor_revisions",
			PackedInt64Array(),
		) as PackedInt64Array
		var committed_revisions: PackedInt64Array = entry.get(
			"committed_revisions",
			PackedInt64Array(),
		) as PackedInt64Array
		descriptions.append(
			"%s:p%s/s%d rev%d result%s masks%d/%d/%d/%d c%d f%d dirty%s req%d" % [
				str(coord),
				str(page_coord),
				slot,
				revision,
				str(_streamer._grass_scatter_results_by_chunk.has(coord)),
				int(entry.get("active_mask", 0)),
				int(entry.get("prestage_mask", 0)),
				int(entry.get("source_mask", 0)),
				int(entry.get("committed_mask", 0)),
				int(contributor_revisions[slot]) if contributor_revisions.size() > slot else -9,
				int(committed_revisions[slot]) if committed_revisions.size() > slot else -9,
				str(entry.get("dirty", false)),
				int(entry.get("requested_revision", -1)),
			],
		)
	return "[" + "; ".join(descriptions) + "]"


func _assert_page_round_trip_reused_cache(
		before: Dictionary,
		after: Dictionary,
		second_out: Dictionary,
		returned_outer_slots: int,
) -> void:
	var request_delta: int = int(after.get("native_request_count_total", 0)) \
			- int(before.get("native_request_count_total", 0))
	var merge_delta: int = int(after.get("native_merge_complete_count_total", 0)) \
			- int(before.get("native_merge_complete_count_total", 0))
	var raw_upload_delta: int = int(after.get("raw_upload_count_total", 0)) \
			- int(before.get("raw_upload_count_total", 0))
	var cache_hit_delta: int = int(after.get("cache_hit_count_total", 0)) \
			- int(before.get("cache_hit_count_total", 0))
	_expect(request_delta == 0,
		"page zoom round-trip queued %d native page rebuilds (resident %d->%d, evictions %d->%d)" % [
			request_delta,
			int(before.get("resident_pages", -1)),
			int(after.get("resident_pages", -1)),
			int(before.get("eviction_count_total", -1)),
			int(after.get("eviction_count_total", -1)),
		])
	_expect(merge_delta == 0,
		"page zoom round-trip completed %d native page merges" % merge_delta)
	_expect(raw_upload_delta == 0,
		"page zoom round-trip performed %d raw page-buffer uploads" % raw_upload_delta)
	_expect(cache_hit_delta > 0,
		"page zoom round-trip did not reuse any committed page slots")
	_expect(cache_hit_delta >= returned_outer_slots,
		"page zoom round-trip reused %d/%d returned outer slots" % [
			cache_hit_delta,
			returned_outer_slots,
		])
	_expect(int(second_out.get("max_page_inflight", -1)) == 0,
		"exact page zoom round-trip must not enqueue a page worker request")
	_expect(int(second_out.get("max_page_ready", -1)) == 0,
		"exact page zoom round-trip must not produce a page result")
	_expect(int(second_out.get("max_page_upload_queue", -1)) == 0,
		"exact page zoom round-trip must not enqueue a raw page upload")


func _get_page_debug_state() -> Dictionary:
	if not bool(_streamer._grass_render_pages_enabled):
		return { }
	return _streamer._grass_render_page_manager.get_debug_state()


func _count_coords_not_in(
		outer_coords: Array[Vector2i],
		inner_coords: Array[Vector2i],
) -> int:
	var inner_set: Dictionary = { }
	for coord: Vector2i in inner_coords:
		inner_set[coord] = true
	var count: int = 0
	for coord: Vector2i in outer_coords:
		if not inner_set.has(coord):
			count += 1
	return count


func _count_pages_not_fully_visible(
		outer_coords: Array[Vector2i],
		inner_coords: Array[Vector2i],
) -> int:
	var inner_set: Dictionary = { }
	for coord: Vector2i in inner_coords:
		inner_set[coord] = true
	var outer_pages: Dictionary = { }
	for coord: Vector2i in outer_coords:
		if not inner_set.has(coord):
			outer_pages[GrassRenderPage.page_coord_for_chunk(coord)] = true
	return outer_pages.size()


func _finish(scene: Node) -> void:
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		scene.queue_free()
		quit(1)
		return
	scene.queue_free()
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
