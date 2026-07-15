extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
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
	_expect(bool(initial.get("settled", false)), "initial radius-2 grass did not settle")

	_set_zoom(ZOOM_OUT)
	var first_out: Dictionary = await _wait_for_committed_visible_grass(4)
	_expect(bool(first_out.get("settled", false)), "first radius-4 grass did not settle")
	var zoomed_out_count: int = _streamer._desired_visible_chunk_coords.size()

	_set_zoom(ZOOM_IN)
	var zoomed_in: Dictionary = await _wait_for_committed_visible_grass(2)
	_expect(bool(zoomed_in.get("settled", false)), "zoom-in eviction did not settle")
	var zoomed_in_count: int = _streamer._desired_visible_chunk_coords.size()
	var expected_outer_ring: int = maxi(0, zoomed_out_count - zoomed_in_count)
	_expect(_streamer._hot_chunk_view_cache.size() >= expected_outer_ring,
		"hot ChunkView cache must retain the complete radius-4 outer ring")

	var preserve_hits_before: int = _streamer._hot_chunk_view_grass_preserve_hit_count_total
	var terrain_hits_before: int = _streamer._hot_chunk_view_terrain_preserve_hit_count_total
	_set_zoom(ZOOM_OUT)
	var second_out: Dictionary = await _wait_for_committed_visible_grass(4)
	_expect(bool(second_out.get("settled", false)), "second radius-4 grass did not settle")
	var preserve_delta: int = \
			_streamer._hot_chunk_view_grass_preserve_hit_count_total - preserve_hits_before
	var terrain_delta: int = \
			_streamer._hot_chunk_view_terrain_preserve_hit_count_total - terrain_hits_before
	_expect(preserve_delta >= expected_outer_ring,
		"second zoom-out must preserve every exact outer-ring grass GPU graph")
	_expect(terrain_delta >= expected_outer_ring,
		"second zoom-out preserved %d/%d exact outer-ring terrain TileMaps" % [
			terrain_delta,
			expected_outer_ring,
		])
	_expect(int(second_out.get("max_upload_queue", -1)) == 0,
		"exact zoom round-trip must not enqueue grass GPU re-upload")
	_expect(int(second_out.get("max_inflight", -1)) == 0,
		"exact zoom round-trip must not enqueue grass worker recompute")

	if _failures.is_empty():
		print(
			(
				"grass_zoom_roundtrip_smoke_test: initial_frames=%d first_out_frames=%d " \
						+ "zoom_in_frames=%d second_out_frames=%d outer_ring=%d " \
						+ "grass_preserve_hits=%d terrain_preserve_hits=%d " \
						+ "second_upload_queue_max=%d PASS"
			) % [
				int(initial.get("frames", 0)),
				int(first_out.get("frames", 0)),
				int(zoomed_in.get("frames", 0)),
				int(second_out.get("frames", 0)),
				expected_outer_ring,
				preserve_delta,
				terrain_delta,
				int(second_out.get("max_upload_queue", 0)),
			]
		)
	_finish(scene)


func _set_zoom(value: float) -> void:
	_camera.set("_target_zoom", value)
	_camera.zoom = Vector2(value, value)


func _wait_for_committed_visible_grass(expected_radius: int) -> Dictionary:
	var max_upload_queue: int = 0
	var max_inflight: int = 0
	for frame_index: int in range(SETTLE_TIMEOUT_FRAMES):
		await process_frame
		var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
		max_upload_queue = maxi(
			max_upload_queue,
			int(debug.get("grass_scatter_visual_upload_queue_count", 0)),
		)
		max_inflight = maxi(
			max_inflight,
			int(debug.get("grass_scatter_inflight_count", 0)),
		)
		if _streamer._current_stream_radius_chunks != expected_radius:
			continue
		if _all_visible_grass_committed(debug):
			return {
				"settled": true,
				"frames": frame_index + 1,
				"max_upload_queue": max_upload_queue,
				"max_inflight": max_inflight,
			}
	return {
		"settled": false,
		"frames": SETTLE_TIMEOUT_FRAMES,
		"max_upload_queue": max_upload_queue,
		"max_inflight": max_inflight,
	}


func _all_visible_grass_committed(debug: Dictionary) -> bool:
	if _streamer._desired_visible_chunk_coords.is_empty():
		return false
	if _streamer._chunk_views.size() != _streamer._desired_visible_chunk_coords.size():
		return false
	if int(debug.get("grass_scatter_visual_upload_queue_count", 0)) != 0 \
			or int(debug.get("grass_scatter_inflight_count", 0)) != 0:
		return false
	for coord: Vector2i in _streamer._desired_visible_chunk_coords:
		var view: Node = _streamer._chunk_views.get(coord, null) as Node
		if view == null \
				or not view.is_grass_scatter_presentation_committed() \
				or not view.is_terrain_cell_presentation_committed():
			return false
	return true


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
