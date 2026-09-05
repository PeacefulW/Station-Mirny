extends SceneTree
## Short backtracking must retire obsolete worker tokens without re-uploading
## the already-current bank or keeping the streaming coordinator awake.

const StreamerScript = preload("res://core/systems/world/world_streamer.gd")
const RendererScript = preload("res://core/systems/world/world_render_world.gd")
const TEST_EPOCH: int = 57
const TEST_GENERATION: int = 19

class RecordingRenderer extends RendererScript:

	var accepted_count: int = 0


	func has_pending_snapshot() -> bool:
		return false


	func begin_built_snapshot(_result: Dictionary, _build_elapsed_usec: int) -> bool:
		accepted_count += 1
		return true


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_return_to_active_envelope()
	_test_old_generation_cannot_release_current_request()
	_test_changed_envelope_still_stages()
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("world_render_streaming_completion_contract_test: PASS")
	quit(0 if _failures.is_empty() else 1)


func _make_streamer() -> Node:
	var streamer: Node = StreamerScript.new()
	streamer._world_render_world = RecordingRenderer.new()
	streamer._generation_epoch = TEST_EPOCH
	streamer._desired_source_chunk_coords.append(Vector2i.ZERO)
	streamer._object_presentation_results_by_chunk[Vector2i.ZERO] = {"revision": 1}
	streamer._grass_scatter_results_by_chunk[Vector2i.ZERO] = {"revision": 2}
	streamer._object_presentation_revision_by_chunk[Vector2i.ZERO] = 1
	streamer._grass_scatter_revision_by_chunk[Vector2i.ZERO] = 2
	streamer._ground_field_input_versions_by_chunk[Vector2i.ZERO] = 2
	streamer._world_render_input_versions_by_chunk[Vector2i.ZERO] = Vector2i(1, 2)
	streamer._world_render_input_lod_fraction = streamer._grass_lod_fraction
	streamer._world_render_inflight_generation = TEST_GENERATION
	streamer._world_render_inflight_input_versions_by_chunk = \
			streamer._world_render_input_versions_by_chunk.duplicate()
	streamer._world_render_inflight_lod_fraction = streamer._grass_lod_fraction
	return streamer


func _complete(streamer: Node, epoch: int, generation: int) -> void:
	streamer._world_compute_backend._completed_world_render_snapshots.append({
		"success": true,
		"epoch": epoch,
		"request_generation": generation,
	})


func _test_return_to_active_envelope() -> void:
	var streamer: Node = _make_streamer()
	# The player entered an extra frontier, requested B, then returned to A.
	streamer._world_render_inflight_input_versions_by_chunk[Vector2i.ONE] = Vector2i(1, 2)
	_complete(streamer, TEST_EPOCH - 1, TEST_GENERATION)
	_complete(streamer, TEST_EPOCH, TEST_GENERATION)
	streamer._publish_world_render_snapshot()
	_expect(streamer._world_render_inflight_generation == -1, "backtrack releases inflight token")
	_expect(not streamer._world_compute_backend.has_completed_world_render_snapshots(),
			"backtrack consumes obsolete completion and old-epoch completion")
	_expect(streamer._world_render_inflight_input_versions_by_chunk.is_empty(),
			"obsolete input envelope is released")
	_expect(not streamer._world_render_refresh_pending, "current bank settles refresh state")
	_expect(not streamer._world_render_owned_streaming_slice, "no redundant upload reserves terrain lane")
	_expect(streamer._world_render_world.accepted_count == 0, "obsolete bank never becomes visible")
	_expect(not streamer._world_compute_backend.has_pending_requests(), "backtrack does not rebuild A")
	_dispose(streamer)


func _test_old_generation_cannot_release_current_request() -> void:
	var streamer: Node = _make_streamer()
	_complete(streamer, TEST_EPOCH, TEST_GENERATION - 1)
	streamer._publish_world_render_snapshot()
	_expect(streamer._world_render_inflight_generation == TEST_GENERATION,
			"unrelated generation cannot release the active worker token")
	_complete(streamer, TEST_EPOCH, TEST_GENERATION)
	streamer._publish_world_render_snapshot()
	_expect(streamer._world_render_inflight_generation == -1, "matching completion still releases token")
	_dispose(streamer)


func _test_changed_envelope_still_stages() -> void:
	var streamer: Node = _make_streamer()
	streamer._world_render_input_versions_by_chunk = { }
	_complete(streamer, TEST_EPOCH, TEST_GENERATION)
	streamer._publish_world_render_snapshot()
	_expect(streamer._world_render_world.accepted_count == 1, "new current bank still stages once")
	_expect(streamer._world_render_staging_input_versions_by_chunk == {Vector2i.ZERO: Vector2i(1, 2)},
			"staging retains the completed current envelope")
	_expect(streamer._world_render_owned_streaming_slice, "real publication owns its bounded slice")
	_dispose(streamer)


func _dispose(streamer: Node) -> void:
	streamer._world_render_world.free()
	streamer.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("world_render_streaming_completion_contract_test: " + message)
