extends SceneTree
## Zoom must be a pure render-side operation for grass.
##
## The earlier version of this test encoded the opposite contract: it waited for
## the streaming radius to shrink on zoom-in and then checked that the warm/hot
## caches absorbed the resulting recompute. Residency no longer follows the
## camera at all, so the caches are not what protects a zoom round-trip - there
## is simply no churn to absorb. This test now asserts that stronger property
## directly: across a full zoom-out/zoom-in/zoom-out cycle nothing is
## recomputed, re-uploaded, created or destroyed.

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const ZOOM_IN: float = 1.0
const ZOOM_OUT: float = 0.2
const SETTLE_TIMEOUT_FRAMES: int = 3000

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
	var initial: Dictionary = await _wait_for_committed_visible_grass()
	_expect(bool(initial.get("settled", false)), "initial grass did not settle")

	var baseline_radius: int = int(_streamer._current_stream_radius_chunks)
	var baseline_visible: int = _streamer._desired_visible_chunk_coords.size()
	var baseline_views: Dictionary = _chunk_view_identities()

	# Full round trip. Every stage must settle without changing residency.
	var stages: Array[float] = [ZOOM_OUT, ZOOM_IN, ZOOM_OUT]
	var stage_names: Array[String] = ["zoom_out", "zoom_in", "second_zoom_out"]
	var max_upload_queue: int = 0
	var max_inflight: int = 0
	for stage_index: int in range(stages.size()):
		_set_zoom(stages[stage_index])
		var stage: Dictionary = await _wait_for_committed_visible_grass()
		_expect(
			bool(stage.get("settled", false)),
			"%s grass did not settle" % stage_names[stage_index],
		)
		max_upload_queue = maxi(max_upload_queue, int(stage.get("max_upload_queue", 0)))
		max_inflight = maxi(max_inflight, int(stage.get("max_inflight", 0)))
		_expect(
			int(_streamer._current_stream_radius_chunks) == baseline_radius,
			"%s changed the residency radius" % stage_names[stage_index],
		)
		_expect(
			_streamer._desired_visible_chunk_coords.size() == baseline_visible,
			"%s changed the resident envelope size" % stage_names[stage_index],
		)

	var final_views: Dictionary = _chunk_view_identities()
	var destroyed: int = 0
	var recreated: int = 0
	for coord_variant: Variant in baseline_views.keys():
		if not final_views.has(coord_variant):
			destroyed += 1
		elif final_views[coord_variant] != baseline_views[coord_variant]:
			recreated += 1
	_expect(destroyed == 0, "zoom round-trip destroyed %d ChunkViews" % destroyed)
	_expect(recreated == 0, "zoom round-trip recreated %d ChunkViews" % recreated)
	_expect(
		max_upload_queue == 0,
		"zoom round-trip enqueued grass GPU re-upload (peak %d)" % max_upload_queue,
	)
	_expect(
		max_inflight == 0,
		"zoom round-trip enqueued grass worker recompute (peak %d)" % max_inflight,
	)

	if _failures.is_empty():
		print(
			(
				"grass_zoom_roundtrip_smoke_test: initial_frames=%d radius=%d visible=%d "
				+ "views=%d destroyed=%d recreated=%d upload_queue_max=%d inflight_max=%d PASS"
			) % [
				int(initial.get("frames", 0)),
				baseline_radius,
				baseline_visible,
				baseline_views.size(),
				destroyed,
				recreated,
				max_upload_queue,
				max_inflight,
			]
		)
	_finish(scene)


func _set_zoom(value: float) -> void:
	_camera.set("_target_zoom", value)
	_camera.zoom = Vector2(value, value)


func _chunk_view_identities() -> Dictionary:
	var identities: Dictionary = { }
	for coord_variant: Variant in (_streamer._chunk_views as Dictionary).keys():
		var view: Object = _streamer._chunk_views[coord_variant] as Object
		if view != null and is_instance_valid(view):
			identities[coord_variant] = view.get_instance_id()
	return identities


func _wait_for_committed_visible_grass() -> Dictionary:
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
	if int(debug.get("grass_scatter_visual_upload_queue_count", 0)) != 0 \
			or int(debug.get("grass_scatter_inflight_count", 0)) != 0:
		return false
	# Residency now covers the reserve ring too, so the view table is a superset
	# of the visible envelope rather than equal to it.
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
