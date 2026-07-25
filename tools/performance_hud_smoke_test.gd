extends SceneTree

const PerformanceHudMetrics = preload("res://core/runtime/performance_hud_metrics.gd")
const PerformanceHudWidget = preload("res://scenes/ui/hud/hud_performance_widget.gd")
const PerformanceFlightRecorderScript = preload(
	"res://core/runtime/performance_flight_recorder.gd"
)
const PerformanceArtifactWriterScript = preload(
	"res://core/runtime/performance_flight_recorder_artifact_writer.gd"
)
const TEST_CAPTURE_ROOT: String = "user://test_artifacts/performance_hud_smoke_test"

var _failed: bool = false


class FakePerfSource extends Node:
	func get_perf_hud_snapshot() -> Dictionary:
		return {
			"resident_views": 49,
			"desired_visible_chunks": 81,
			"packet_count": 121,
			"requested_packets": 3,
			"publish_queue": 12,
			"visibility_wait": 0,
			"object_upload_queue": 18,
			"object_prestage_queue": 14,
			"object_inflight": 6,
			"grass_upload_queue": 2,
			"grass_inflight": 4,
			"grass_ready_cpu": 11,
			"mountain_mask_inflight": 7,
			"terrain_mask_inflight": 5,
			"mountain_mask_upload_queue": 2,
			"terrain_mask_upload_queue": 1,
			"mask_retry_queue": 0,
			"hot_view_cache": 32,
			"hot_view_cache_capacity": 64,
			"warm_packet_cache": 121,
		}

	func get_streaming_readiness_debug_snapshot() -> Dictionary:
		return {
			"schema_version": 1,
			"missing_chunk_count": 1,
			"entries": [{
				"chunk_coord": Vector2i(3, 4),
				"lifecycle_stage": "requested",
				"ready": false,
				"blocking_layer": "packet",
				"blocking_reason": "packet_generation_inflight",
				"blocking_elapsed_ms": 12,
			}],
		}


class PressurePerfSource extends Node:
	func get_perf_hud_snapshot() -> Dictionary:
		return {
			"visibility_wait": 12,
			"object_upload_queue": 0,
			"object_prestage_queue": 0,
			"publish_queue": 0,
		}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_test_directory(TEST_CAPTURE_ROOT)
	_test_static_contract()
	_test_metrics_contract()
	await _test_live_observer_contract()
	_test_recorder_retention_contract()
	_test_recorder_event_bounds_contract()
	await _test_recorder_observer_contract()
	await _test_recorder_shutdown_contract()
	await _test_widget_contract()
	_remove_test_directory(TEST_CAPTURE_ROOT)

	if _failed:
		quit(1)
		return
	print("performance_hud_smoke_test: PASS")
	quit(0)


func _test_static_contract() -> void:
	var runtime_source: String = FileAccess.get_file_as_string(
		"res://scenes/world/world_runtime_v0_scene.gd",
	)
	var manager_source: String = FileAccess.get_file_as_string(
		"res://scenes/ui/hud/hud_manager.gd",
	)
	var streamer_source: String = FileAccess.get_file_as_string(
		"res://core/systems/world/world_streamer.gd",
	)
	var ru_locale: String = FileAccess.get_file_as_string("res://locale/ru/messages.po")
	var en_locale: String = FileAccess.get_file_as_string("res://locale/en/messages.po")
	_assert(runtime_source.contains("KEY_F3"), "F3 must own the performance HUD cycle.")
	_assert(runtime_source.contains("KEY_F2"), "F2 must own the manual diagnostic capture.")
	_assert(runtime_source.contains("KEY_F4"), "F4 must own the flight recorder cycle.")
	_assert(not runtime_source.contains("KEY_F8"), "F8 must remain reserved for Godot Stop.")
	_assert(
		manager_source.contains("cycle_performance_mode")
		and manager_source.contains("hud_performance_widget.gd"),
		"HudManager must own the performance widget and public mode cycle.",
	)
	_assert(
		streamer_source.contains("func get_perf_hud_snapshot() -> Dictionary:")
		and streamer_source.contains("HUD-safe O(1) snapshot"),
		"WorldStreamer must expose the dedicated O(1) HUD snapshot.",
	)
	for localization_key: String in [
		"UI_PERF_TITLE",
		"UI_PERF_GRAPH_WINDOW",
		"UI_PERF_SUMMARY",
		"UI_PERF_CAUSE_WORLD_STREAMING",
		"UI_PERF_STATUS_STABLE",
		"UI_PERF_SECTION_STREAMING",
		"UI_PERF_LAST_HITCH",
		"UI_PERF_HINT_MORE",
		"UI_PERF_RECORDING_SAVED",
		"UI_PERF_EVENT_LIMIT_REACHED",
	]:
		_assert(
			ru_locale.contains(localization_key) and en_locale.contains(localization_key),
			"Performance HUD localization key missing: %s" % localization_key,
		)


func _test_metrics_contract() -> void:
	var values: Array[float] = []
	for value: int in range(1, 101):
		values.append(float(value))
	_assert(
		is_equal_approx(PerformanceHudMetrics.percentile(values, 95.0), 95.0),
		"Nearest-rank p95 for 1..100 must be 95.",
	)
	_assert(
		is_equal_approx(PerformanceHudMetrics.percentile(values, 99.0), 99.0),
		"Nearest-rank p99 for 1..100 must be 99.",
	)
	_assert(
		PerformanceHudMetrics.classify_frame_time(16.6) \
				== PerformanceHudMetrics.Health.GOOD,
		"16.6 ms must be healthy for the 60 FPS budget.",
	)
	_assert(
		PerformanceHudMetrics.classify_frame_time(22.0) \
				== PerformanceHudMetrics.Health.WARNING,
		"22.0 ms is the inclusive warning boundary.",
	)
	_assert(
		PerformanceHudMetrics.classify_frame_time(22.01) \
				== PerformanceHudMetrics.Health.WARNING,
		"A sustained budget miss must remain pressure, not become a false hitch.",
	)
	_assert(
		PerformanceHudMetrics.classify_frame_time(50.01) \
				== PerformanceHudMetrics.Health.CRITICAL,
		"A frame above 50 ms must be a heavy-frame event.",
	)
	_assert(
		PerformanceHudMetrics.format_ms(16.666) == "16.67 ms",
		"Frame time formatting must use two decimals.",
	)
	_assert(
		PerformanceHudMetrics.format_fps(59.94) == "59.9 FPS",
		"FPS formatting must use one decimal.",
	)
	var bounded := PerformanceHudMetrics.new(300)
	for frame_index: int in range(1000):
		bounded.push_frame(float(frame_index % 40), { })
	_assert(bounded.get_sample_count() == 300, "Frame history must remain bounded at 300.")
	_assert(bounded.get_graph_samples().size() == 300, "Graph history must share the bounded cap.")
	var hitch_metrics := PerformanceHudMetrics.new(8)
	hitch_metrics.push_frame(
		64.0,
		{
			"FrameBudgetDispatcher.visual.world.mountain_native_mask_visual_upload": 20.0,
		},
	)
	var hitch: Dictionary = hitch_metrics.get_last_hitch()
	_assert(
		String(hitch.get("cause", "")) == "mountain_upload" \
				and is_equal_approx(float(hitch.get("cause_ms", 0.0)), 20.0),
		"Mountain visual job must be attributed as the hitch cause.",
	)
	var external_metrics := PerformanceHudMetrics.new(8)
	external_metrics.push_frame(
		70.0,
		{
			"WorldStreamer.publish.begin": 2.0,
		},
	)
	var external_hitch: Dictionary = external_metrics.get_last_hitch()
	_assert(
		String(external_hitch.get("cause", "")) == "external_or_render",
		"A small normal publish must not be blamed for a much larger external hitch.",
	)
	var streaming_metrics := PerformanceHudMetrics.new(8)
	streaming_metrics.push_frame(
		80.0,
		{
			"WorldStreamer.publish.begin": 1.0,
			"FrameBudgetDispatcher.streaming.world.streaming_v0": 30.0,
		},
	)
	_assert(
		String(streaming_metrics.get_last_hitch().get("cause", "")) == "world_streaming",
		"A distributed streaming overrun must retain a coarse but honest cause.",
	)
	var rolling_hitches := PerformanceHudMetrics.new(3)
	rolling_hitches.push_frame(60.0, { })
	var healthy_frames_remaining: int = 3
	while healthy_frames_remaining > 0:
		rolling_hitches.push_frame(16.0, { })
		healthy_frames_remaining -= 1
	_assert(
		rolling_hitches.get_last_hitch().is_empty() \
				and int(rolling_hitches.get_frame_stats().get("hitch_count", -1)) == 0,
		"Last hitch and hitch count must expire with the bounded frame window.",
	)


func _test_live_observer_contract() -> void:
	WorldPerfProbe.flush_frame()
	var baseline_observers: int = WorldPerfProbe.get_live_observer_count()
	WorldPerfProbe.begin_live_observation()
	var recorded_frame: int = Engine.get_process_frames()
	WorldPerfProbe.record("WorldStreamer.publish.begin", 3.25)
	WorldPerfProbe.record("PerformanceHud.untracked_marker", 7.0)
	var frame_waits_remaining: int = 3
	while frame_waits_remaining > 0:
		await process_frame
		if Engine.get_process_frames() != recorded_frame:
			break
		frame_waits_remaining -= 1
	var live: Dictionary = WorldPerfProbe.copy_completed_live_frame_snapshot()
	var live_ops: Dictionary = live.get("ops", { }) as Dictionary
	var flushed: Dictionary = WorldPerfProbe.flush_frame()
	_assert(
		int(live.get("frame_index", -1)) == recorded_frame,
		"Live observation must expose the completed frame, not the collecting frame.",
	)
	_assert(
		is_equal_approx(float(live_ops.get("WorldStreamer.publish.begin", 0.0)), 3.25),
		"Live observer must receive current-frame operations.",
	)
	_assert(
		not live_ops.has("PerformanceHud.untracked_marker"),
		"Live observation must ignore labels outside its bounded HUD schema.",
	)
	_assert(
		is_equal_approx(float(flushed.get("WorldStreamer.publish.begin", 0.0)), 3.25) \
				and is_equal_approx(
					float(flushed.get("PerformanceHud.untracked_marker", 0.0)),
					7.0,
				),
		"Live observation must not steal the destructive perf-probe channel.",
	)
	WorldPerfProbe.end_live_observation()
	_assert(
		WorldPerfProbe.get_live_observer_count() == baseline_observers,
		"Live observer reference count must return to its baseline.",
	)


func _test_recorder_observer_contract() -> void:
	var source := FakePerfSource.new()
	get_root().add_child(source)
	var recorder: PerformanceFlightRecorder = (
		PerformanceFlightRecorderScript.new() as PerformanceFlightRecorder
	)
	get_root().add_child(recorder)
	recorder.setup(source, null, TEST_CAPTURE_ROOT)
	await process_frame
	var manual_snapshot: Dictionary = recorder._build_diagnostic_snapshot(&"manual")
	var automatic_snapshot: Dictionary = recorder._build_diagnostic_snapshot(&"frame_spike")
	_assert(
		manual_snapshot.has("streaming_readiness")
				and not automatic_snapshot.has("streaming_readiness"),
		"Detailed readiness must be F2/final-only, never automatic-event overhead.",
	)
	var baseline_observers: int = WorldPerfProbe.get_live_observer_count()
	_assert(recorder.start_recording(), "Flight recorder must start from idle.")
	await process_frame
	await process_frame
	var active_state: Dictionary = recorder.get_ui_state()
	_assert(
		bool(active_state.get("recording", false))
				and int(active_state.get("sample_count", 0)) > 0,
		"Flight recorder must collect bounded samples while active.",
	)
	_assert(
		WorldPerfProbe.get_live_observer_count() == baseline_observers + 1,
		"Flight recorder must own one independent live observer.",
	)
	recorder.request_stop_recording()
	var frames_remaining: int = 600
	while frames_remaining > 0:
		await process_frame
		var state: Dictionary = recorder.get_ui_state()
		if not bool(state.get("recording", false)) \
				and not bool(state.get("saving", false)):
			break
		frames_remaining -= 1
	_assert(frames_remaining > 0, "Flight recorder must finish its worker save.")
	_assert(
		WorldPerfProbe.get_live_observer_count() == baseline_observers,
		"Stopping the recorder must release its independent live observer.",
	)
	var session_directory: String = String(
		active_state.get("artifact_directory", ""),
	)
	var session_file: FileAccess = FileAccess.open(
		session_directory.path_join("session.json"),
		FileAccess.READ,
	)
	_assert(session_file != null, "F4 session metadata must be readable.")
	if session_file != null:
		var parsed: Variant = JSON.parse_string(session_file.get_as_text())
		session_file.close()
		_assert(parsed is Dictionary, "F4 session metadata must be valid JSON.")
		if parsed is Dictionary:
			var readiness: Dictionary = (
				parsed as Dictionary
			).get("streaming_readiness", { }) as Dictionary
			_assert(
				int(readiness.get("schema_version", 0)) == 1
						and int(readiness.get("missing_chunk_count", 0)) == 1,
				"Final F4 metadata must include bounded readiness diagnostics.",
			)
	recorder.queue_free()
	source.queue_free()
	await process_frame


func _test_recorder_event_bounds_contract() -> void:
	var source := PressurePerfSource.new()
	get_root().add_child(source)
	var recorder: PerformanceFlightRecorder = (
		PerformanceFlightRecorderScript.new() as PerformanceFlightRecorder
	)
	get_root().add_child(recorder)
	recorder.setup(source, null, TEST_CAPTURE_ROOT)
	recorder._sample_count = PerformanceFlightRecorder.WARMUP_FRAMES
	recorder._capture_taint_until_frame = Engine.get_process_frames() + 3
	recorder._refresh_context_snapshot()
	_assert(
		recorder._events.is_empty() and not recorder._queue_pressure_active,
		"Capture-tainted queue pressure must defer its transition and screenshot.",
	)
	recorder._capture_taint_until_frame = Engine.get_process_frames() - 1
	recorder._refresh_context_snapshot()
	_assert(
		recorder._events.size() == 1 and recorder._queue_pressure_active,
		"Deferred queue pressure must emit once after capture taint expires.",
	)
	recorder._events.clear()
	for _event_index: int in range(PerformanceFlightRecorder.MAX_EVENT_RECORDS + 8):
		recorder._trigger_event(&"manual", true)
	_assert(
		recorder._events.size() == PerformanceFlightRecorder.MAX_EVENT_RECORDS,
		"Manual and automatic event records must share one hard session bound.",
	)
	recorder.queue_free()
	source.queue_free()


func _test_recorder_shutdown_contract() -> void:
	var source := FakePerfSource.new()
	get_root().add_child(source)
	var recorder: PerformanceFlightRecorder = (
		PerformanceFlightRecorderScript.new() as PerformanceFlightRecorder
	)
	get_root().add_child(recorder)
	recorder.setup(source, null, TEST_CAPTURE_ROOT)
	await process_frame
	var baseline_observers: int = WorldPerfProbe.get_live_observer_count()
	_assert(recorder.start_recording(), "Shutdown fixture recorder must start.")
	await process_frame
	await process_frame
	var session_directory: String = String(
		recorder.get_ui_state().get("artifact_directory", ""),
	)
	recorder.queue_free()
	await process_frame
	_assert(
		FileAccess.file_exists(session_directory.path_join("trace.csv"))
		and FileAccess.file_exists(session_directory.path_join("session.json")),
		"Scene exit must synchronously preserve an active F4 trace.",
	)
	_assert(
		WorldPerfProbe.get_live_observer_count() == baseline_observers,
		"Shutdown finalization must release the recorder observer.",
	)
	source.queue_free()
	await process_frame


func _test_recorder_retention_contract() -> void:
	_remove_test_directory(TEST_CAPTURE_ROOT)
	var directory_names: Array[String] = [
		"20260715_140001_000",
		"manual_20260715_140002_000",
		"20260715_140003_000",
		"manual_20260715_140004_000",
		"20260715_140005_000",
		"manual_20260715_140006_000",
		"20260715_140007_000",
		"manual_20260715_140008_000",
		"20260715_140009_000",
		"manual_20260715_140010_000",
	]
	for directory_name: String in directory_names:
		var make_error: Error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(TEST_CAPTURE_ROOT.path_join(directory_name)),
		)
		_assert(make_error == OK, "Retention fixture directories must be created.")
	var current_session: String = ProjectSettings.globalize_path(
		TEST_CAPTURE_ROOT.path_join(directory_names[0]),
	)
	var writer: PerformanceFlightRecorderArtifactWriter = (
		PerformanceArtifactWriterScript.new() as PerformanceFlightRecorderArtifactWriter
	)
	writer._trim_capture_sessions(
		ProjectSettings.globalize_path(TEST_CAPTURE_ROOT),
		current_session,
		8,
	)
	var root: DirAccess = DirAccess.open(ProjectSettings.globalize_path(TEST_CAPTURE_ROOT))
	var remaining: PackedStringArray = root.get_directories() if root != null else PackedStringArray()
	_assert(remaining.size() == 8, "Retention must remove enough old captures after skipping current.")
	_assert(
		DirAccess.dir_exists_absolute(current_session),
		"Retention must never remove the artifact currently being written.",
	)
	_assert(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(TEST_CAPTURE_ROOT.path_join(directory_names[1])),
		)
		and not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(TEST_CAPTURE_ROOT.path_join(directory_names[2])),
		),
		"Retention must compare F2/F4 directories by their normalized timestamps.",
	)
	_remove_test_directory(TEST_CAPTURE_ROOT)


func _test_widget_contract() -> void:
	var source := FakePerfSource.new()
	get_root().add_child(source)
	var widget: HudPerformanceWidget = PerformanceHudWidget.new() as HudPerformanceWidget
	get_root().add_child(widget)
	widget.set_performance_source(source)
	await process_frame
	var baseline_observers: int = WorldPerfProbe.get_live_observer_count()
	var initial: Dictionary = widget.get_debug_state()
	_assert(not bool(initial.get("visible", true)), "Performance HUD must start hidden.")
	_assert(
		int(initial.get("display_mode", -1)) == HudPerformanceWidget.DisplayMode.HIDDEN,
		"Initial HUD mode must be HIDDEN.",
	)

	var compact_mode: int = widget.cycle_display_mode()
	await process_frame
	var compact: Dictionary = widget.get_debug_state()
	_assert(
		compact_mode == HudPerformanceWidget.DisplayMode.COMPACT \
				and bool(compact.get("visible", false)),
		"First F3 cycle must show compact mode.",
	)
	_assert(not bool(compact.get("details_visible", true)), "Compact mode must hide details.")
	_assert(
		WorldPerfProbe.get_live_observer_count() == baseline_observers + 1,
		"Visible HUD must own one live observer.",
	)

	var detailed_mode: int = widget.cycle_display_mode()
	widget.call("_refresh_presentation")
	await process_frame
	var detailed: Dictionary = widget.get_debug_state()
	_assert(
		detailed_mode == HudPerformanceWidget.DisplayMode.DETAILED \
				and bool(detailed.get("details_visible", false)),
		"Second F3 cycle must show detailed mode.",
	)
	_assert(
		widget.modulate.a >= 0.99,
		"Compact-to-detailed switching must not leave the panel transparent.",
	)
	_assert(
		(detailed.get("panel_size", Vector2.ZERO) as Vector2).x >= 600.0,
		"Detailed HUD must expand to the readable diagnostics width.",
	)
	var stream_snapshot: Dictionary = detailed.get("stream_snapshot", { }) as Dictionary
	_assert(
		int(stream_snapshot.get("resident_views", 0)) == 49,
		"Widget must consume the lightweight streamer snapshot.",
	)

	var hidden_mode: int = widget.cycle_display_mode()
	var hidden: Dictionary = widget.get_debug_state()
	_assert(
		hidden_mode == HudPerformanceWidget.DisplayMode.HIDDEN \
				and not bool(hidden.get("visible", true)),
		"Third F3 cycle must hide the HUD.",
	)
	_assert(
		WorldPerfProbe.get_live_observer_count() == baseline_observers,
		"Hiding the HUD must release its live observer.",
	)
	widget.queue_free()
	source.queue_free()
	await process_frame


func _remove_test_directory(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path).simplify_path()
	var expected_root: String = ProjectSettings.globalize_path("user://test_artifacts").simplify_path()
	if not absolute_path.begins_with(expected_root + "/") \
			and not absolute_path.begins_with(expected_root + "\\"):
		_assert(false, "Smoke cleanup must stay inside user://test_artifacts.")
		return
	var directory: DirAccess = DirAccess.open(absolute_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for child_name: String in directory.get_directories():
		_remove_test_directory(path.path_join(child_name))
	DirAccess.remove_absolute(absolute_path)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
