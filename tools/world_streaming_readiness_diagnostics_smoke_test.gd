extends SceneTree

const ReadinessTrackerScript = preload(
	"res://core/systems/world/world_streaming_readiness_tracker.gd"
)

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_tracker_elapsed_contract()
	_test_streamer_snapshot_contract()
	_test_flight_recorder_contract()
	if _failed:
		quit(1)
		return
	print("world_streaming_readiness_diagnostics_smoke_test: PASS")
	quit(0)


func _test_tracker_elapsed_contract() -> void:
	var tracker: WorldStreamingReadinessTracker = ReadinessTrackerScript.new()
	var coord := Vector2i(4, 7)
	tracker.reset(11)
	tracker.mark_stage(coord, &"requested")
	tracker.mark_layer(coord, &"packet", &"waiting", &"packet_generation_inflight")
	var observed_msec: int = Time.get_ticks_msec() + 80
	var first: Dictionary = tracker.observe(
		coord,
		&"requested",
		{&"packet": {"state": &"waiting", "reason": &"packet_generation_inflight"}},
		observed_msec,
	)
	var first_layer: Dictionary = (
		first.get("layers", { }) as Dictionary
	).get("packet", { }) as Dictionary
	_assert(int(first.get("stage_elapsed_ms", 0)) > 0, "Stage elapsed time must advance.")
	_assert(int(first_layer.get("elapsed_ms", 0)) > 0, "Layer wait time must advance.")
	tracker.mark_layer(coord, &"packet", &"ready", &"packet_resident")
	var second: Dictionary = tracker.observe(
		coord,
		&"generated",
		{&"packet": {"state": &"ready", "reason": &"packet_resident"}},
		Time.get_ticks_msec(),
	)
	var second_layer: Dictionary = (
		second.get("layers", { }) as Dictionary
	).get("packet", { }) as Dictionary
	_assert(
		String(second_layer.get("state", "")) == "ready",
		"A real reason transition must replace the waiting layer state.",
	)
	_assert(
		int(second_layer.get("elapsed_ms", -1)) <= 2,
		"A changed layer reason must start a new elapsed interval.",
	)
	tracker.mark_terminal(coord, &"evicted")
	_assert(
		tracker.get_terminal_history().size() == 1,
		"Terminal lifecycle history must retain the evicted transition.",
	)


func _test_streamer_snapshot_contract() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://core/systems/world/world_streamer.gd",
	)
	_assert(
		source.contains("func get_streaming_readiness_debug_snapshot() -> Dictionary:"),
		"WorldStreamer must expose the bounded detailed snapshot.",
	)
	for required_layer: String in [
		"packet", "gameplay", "terrain", "mountain_mask", "terrain_edge_mask",
		"objects", "grass", "roof_cavity", "visibility",
	]:
		_assert(
			source.contains("layers[&\"%s\"]" % required_layer),
			"Missing diagnostic layer: %s" % required_layer,
		)
	_assert(
		source.contains("packet_generation_inflight")
				and source.contains("blocking_elapsed_ms"),
		"Snapshot must expose a concrete packet reason and timed blocker.",
	)


func _test_flight_recorder_contract() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://core/runtime/performance_flight_recorder.gd",
	)
	var refresh_start: int = source.find("func _refresh_context_snapshot()")
	var event_start: int = source.find("func _update_event_detection", refresh_start)
	var refresh_body: String = source.substr(refresh_start, event_start - refresh_start)
	_assert(
		not refresh_body.contains("get_streaming_readiness_debug_snapshot"),
		"The four-Hz context sampler must not build detailed readiness.",
	)
	_assert(
		source.contains("streaming_readiness\"] = _get_streaming_readiness_snapshot()")
				and source.contains("if reason == &\"manual\":"),
		"Final F4 metadata and explicit F2 sidecars must attach readiness snapshots.",
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
