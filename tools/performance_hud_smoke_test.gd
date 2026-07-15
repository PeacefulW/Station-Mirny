extends SceneTree

const PerformanceHudMetrics = preload("res://core/runtime/performance_hud_metrics.gd")
const PerformanceHudWidget = preload("res://scenes/ui/hud/hud_performance_widget.gd")

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


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_static_contract()
	_test_metrics_contract()
	await _test_live_observer_contract()
	await _test_widget_contract()

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
		"UI_PERF_F3_MORE",
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
				== PerformanceHudMetrics.Health.CRITICAL,
		"A frame above 22 ms must be critical.",
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
		24.0,
		{
			"FrameBudgetDispatcher.visual.world.mountain_native_mask_visual_upload": 4.75,
		},
	)
	var hitch: Dictionary = hitch_metrics.get_last_hitch()
	_assert(
		String(hitch.get("cause", "")) == "mountain_upload" \
				and is_equal_approx(float(hitch.get("cause_ms", 0.0)), 4.75),
		"Mountain visual job must be attributed as the hitch cause.",
	)
	var external_metrics := PerformanceHudMetrics.new(8)
	external_metrics.push_frame(
		40.0,
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
		30.0,
		{
			"WorldStreamer.publish.begin": 1.0,
			"FrameBudgetDispatcher.streaming.world.streaming_v0": 8.0,
		},
	)
	_assert(
		String(streaming_metrics.get_last_hitch().get("cause", "")) == "world_streaming",
		"A distributed streaming overrun must retain a coarse but honest cause.",
	)
	var rolling_hitches := PerformanceHudMetrics.new(3)
	rolling_hitches.push_frame(30.0, { })
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


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
