class_name HudPerformanceWidget
extends HudWidget

const PerformanceHudMetrics = preload("res://core/runtime/performance_hud_metrics.gd")
const PerformanceGraph = preload("res://scenes/ui/hud/hud_performance_graph.gd")

enum DisplayMode {
	HIDDEN,
	COMPACT,
	DETAILED,
}

const UPDATE_INTERVAL_SECONDS: float = 0.25
const COMPACT_SIZE: Vector2 = Vector2(460.0, 168.0)
const DETAILED_SIZE: Vector2 = Vector2(610.0, 536.0)
const PANEL_POSITION: Vector2 = Vector2(12.0, 108.0)
const OBJECT_QUEUE_WARNING: int = 56
const OBJECT_QUEUE_CRITICAL: int = 96
const PUBLISH_QUEUE_WARNING: int = 24
const PUBLISH_QUEUE_CRITICAL: int = 48
const VISIBILITY_WAIT_CRITICAL: int = 8
const DISPLAY_TIMING_KEYS: Array[String] = [
	"dispatcher_ms",
	"streaming_ms",
	"packet_ms",
	"publish_begin_ms",
	"publish_apply_ms",
	"object_upload_ms",
	"grass_upload_ms",
	"visual_ms",
]

const SURFACE_COLOR: Color = Color(0.025, 0.037, 0.048, 0.95)
const SURFACE_BORDER_COLOR: Color = Color(0.28, 0.78, 0.90, 0.34)
const SURFACE_INSET_COLOR: Color = Color(0.015, 0.024, 0.031, 0.78)
const ACCENT_COLOR: Color = Color(0.31, 0.84, 0.94)
const TEXT_PRIMARY_COLOR: Color = Color(0.93, 0.96, 0.97)
const TEXT_SECONDARY_COLOR: Color = Color(0.55, 0.64, 0.68)
const GOOD_COLOR: Color = Color(0.35, 0.94, 0.61)
const WARNING_COLOR: Color = Color(0.98, 0.75, 0.31)
const CRITICAL_COLOR: Color = Color(1.0, 0.34, 0.28)

var _display_mode: int = DisplayMode.HIDDEN
var _streamer: Node = null
var _recorder: PerformanceFlightRecorder = null
var _metrics := PerformanceHudMetrics.new()
var _observer_active: bool = false
var _refresh_elapsed: float = 0.0
var _panel: PanelContainer = null
var _content: VBoxContainer = null
var _details: VBoxContainer = null
var _graph: HudPerformanceGraph = null
var _status_dot: Label = null
var _status_label: Label = null
var _mode_label: Label = null
var _recording_label: Label = null
var _fps_value: Label = null
var _frame_value: Label = null
var _p95_value: Label = null
var _peak_value: Label = null
var _budget_bar: ProgressBar = null
var _budget_fill_style: StyleBoxFlat = null
var _summary_label: Label = null
var _last_hitch_label: Label = null
var _hint_label: Label = null
var _value_labels: Dictionary = { }
var _last_stream_snapshot: Dictionary = { }
var _display_timing_peaks: Dictionary = { }
var _active_tween: Tween = null
var _localized_labels: Dictionary = { }


func _setup() -> void:
	name = "PerformanceHud"
	process_priority = 1000
	position = PANEL_POSITION
	size = COMPACT_SIZE
	custom_minimum_size = COMPACT_SIZE
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_build_panel()
	var event_bus: Node = get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.has_signal("language_changed"):
		event_bus.connect("language_changed", Callable(self, "_on_language_changed"))
	_apply_localization()


func _exit_tree() -> void:
	_stop_observation()


func set_performance_source(streamer: Node) -> void:
	_streamer = streamer


func set_performance_recorder(recorder: PerformanceFlightRecorder) -> void:
	_recorder = recorder
	if visible:
		_refresh_recorder_presentation()


func cycle_display_mode() -> int:
	match _display_mode:
		DisplayMode.HIDDEN:
			_set_display_mode(DisplayMode.COMPACT)
		DisplayMode.COMPACT:
			_set_display_mode(DisplayMode.DETAILED)
		_:
			_set_display_mode(DisplayMode.HIDDEN)
	return _display_mode


func get_display_mode() -> int:
	return _display_mode


func get_debug_state() -> Dictionary:
	return {
		"display_mode": _display_mode,
		"visible": visible,
		"details_visible": _details != null and _details.visible,
		"observer_active": _observer_active,
		"sample_count": _metrics.get_sample_count(),
		"sample_capacity": _metrics.get_capacity(),
		"update_interval_seconds": UPDATE_INTERVAL_SECONDS,
		"panel_position": position,
		"panel_size": size,
		"stream_snapshot": _last_stream_snapshot.duplicate(false),
	}


func _process(delta: float) -> void:
	var live_snapshot: Dictionary = WorldPerfProbe.copy_completed_live_frame_snapshot()
	var frame_ops: Dictionary = live_snapshot.get("ops", { }) as Dictionary
	# Viewport readback is intentionally rare, but it can stall the following
	# frames. Do not let an F2/F4 evidence capture accuse gameplay of the observer's
	# own cost or leave a fake peak in the 300-frame HUD window.
	var capture_tainted: bool = _recorder != null \
			and is_instance_valid(_recorder) \
			and _recorder.is_capture_tainted()
	if not capture_tainted:
		_metrics.push_frame(maxf(delta, 0.0) * 1000.0, frame_ops)
	_refresh_elapsed += maxf(delta, 0.0)
	if _refresh_elapsed < UPDATE_INTERVAL_SECONDS:
		return
	_refresh_elapsed = fmod(_refresh_elapsed, UPDATE_INTERVAL_SECONDS)
	_refresh_presentation()


func _set_display_mode(next_mode: int) -> void:
	if next_mode == _display_mode:
		return
	_display_mode = next_mode
	if _display_mode == DisplayMode.HIDDEN:
		_stop_observation()
		visible = false
		set_process(false)
		return
	if not _observer_active:
		_metrics.reset()
		_refresh_elapsed = 0.0
		_start_observation()
	visible = true
	set_process(true)
	var detailed: bool = _display_mode == DisplayMode.DETAILED
	_details.visible = detailed
	custom_minimum_size = DETAILED_SIZE if detailed else COMPACT_SIZE
	size = custom_minimum_size
	_apply_localization()
	_refresh_presentation()
	_animate_mode_change(detailed)


func _start_observation() -> void:
	if _observer_active:
		return
	WorldPerfProbe.begin_live_observation()
	_observer_active = true


func _stop_observation() -> void:
	if not _observer_active:
		return
	WorldPerfProbe.end_live_observation()
	_observer_active = false


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_panel.mouse_filter = MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = SURFACE_COLOR
	panel_style.border_color = SURFACE_BORDER_COLOR
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_top = 11.0
	panel_style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 7)
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	_panel.add_child(_content)
	_build_header()
	_build_primary_metrics()
	_build_budget_bar()

	_summary_label = _make_label("", 11, TEXT_SECONDARY_COLOR)
	_summary_label.clip_text = true
	_content.add_child(_summary_label)

	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 6)
	_details.mouse_filter = MOUSE_FILTER_IGNORE
	_details.visible = false
	_content.add_child(_details)
	_build_details()
	_build_footer()


func _build_header() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 7)
	header.mouse_filter = MOUSE_FILTER_IGNORE
	_content.add_child(header)

	var title: Label = _make_localized_label("UI_PERF_TITLE", 12, ACCENT_COLOR)
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	header.add_child(title)
	var live_label: Label = _make_localized_label("UI_PERF_LIVE", 10, TEXT_SECONDARY_COLOR)
	header.add_child(live_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	header.add_child(spacer)

	_status_dot = _make_label("●", 11, GOOD_COLOR)
	header.add_child(_status_dot)
	_status_label = _make_label("", 10, GOOD_COLOR)
	header.add_child(_status_label)
	_mode_label = _make_label("", 9, TEXT_SECONDARY_COLOR)
	header.add_child(_mode_label)
	_recording_label = _make_label("", 9, CRITICAL_COLOR)
	_recording_label.visible = false
	header.add_child(_recording_label)
	var key_label: Label = _make_label("[F3]", 10, ACCENT_COLOR)
	header.add_child(key_label)


func _build_primary_metrics() -> void:
	var primary := HBoxContainer.new()
	primary.add_theme_constant_override("separation", 12)
	primary.mouse_filter = MOUSE_FILTER_IGNORE
	_content.add_child(primary)
	_fps_value = _add_primary_metric(primary, "—", "UI_PERF_PRIMARY_FPS", 28)
	_add_vertical_rule(primary)
	_frame_value = _add_primary_metric(primary, "—", "UI_PERF_PRIMARY_FRAME", 21)
	_p95_value = _add_primary_metric(primary, "—", "UI_PERF_PRIMARY_P95", 17)
	_peak_value = _add_primary_metric(primary, "—", "UI_PERF_PRIMARY_PEAK", 17)


func _build_budget_bar() -> void:
	_budget_bar = ProgressBar.new()
	_budget_bar.min_value = 0.0
	_budget_bar.max_value = 33.34
	_budget_bar.value = 0.0
	_budget_bar.show_percentage = false
	_budget_bar.custom_minimum_size = Vector2(0.0, 4.0)
	_budget_bar.mouse_filter = MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.2, 0.27, 0.30, 0.48)
	background.set_corner_radius_all(2)
	_budget_bar.add_theme_stylebox_override("background", background)
	_set_budget_bar_color(TEXT_SECONDARY_COLOR)
	_content.add_child(_budget_bar)


func _build_details() -> void:
	_graph = PerformanceGraph.new() as HudPerformanceGraph
	_details.add_child(_graph)
	_add_section_title(_details, "UI_PERF_SECTION_STREAMING")
	var streaming_grid := _make_metric_grid()
	_details.add_child(streaming_grid)
	_add_grid_pair(streaming_grid, "UI_PERF_METRIC_DISPATCHER", "dispatcher_ms")
	_add_grid_pair(streaming_grid, "UI_PERF_METRIC_STREAMING", "streaming_ms")
	_add_grid_pair(streaming_grid, "UI_PERF_METRIC_PACKET", "packet_ms")
	_add_grid_pair(streaming_grid, "UI_PERF_METRIC_PUBLISH_BEGIN", "publish_begin_ms")
	_add_grid_pair(streaming_grid, "UI_PERF_METRIC_PUBLISH_APPLY", "publish_apply_ms")
	_add_grid_pair(streaming_grid, "UI_PERF_METRIC_OBJECT_UPLOAD", "object_upload_ms")
	_add_grid_pair(streaming_grid, "UI_PERF_METRIC_GRASS_UPLOAD", "grass_upload_ms")
	_add_grid_pair(streaming_grid, "UI_PERF_METRIC_MOUNTAIN_VISUAL", "visual_ms")

	_add_separator(_details)
	_add_section_title(_details, "UI_PERF_SECTION_QUEUES")
	var queue_grid := _make_metric_grid()
	_details.add_child(queue_grid)
	_add_grid_pair(queue_grid, "UI_PERF_METRIC_CHUNKS", "chunks")
	_add_grid_pair(queue_grid, "UI_PERF_METRIC_PACKETS", "packets")
	_add_grid_pair(queue_grid, "UI_PERF_METRIC_PUBLISH_QUEUE", "publish_queue")
	_add_grid_pair(queue_grid, "UI_PERF_METRIC_REVEAL_WAIT", "visibility_wait")
	_add_grid_pair(queue_grid, "UI_PERF_METRIC_OBJECTS", "objects")
	_add_grid_pair(queue_grid, "UI_PERF_METRIC_GRASS", "grass")
	_add_grid_pair(queue_grid, "UI_PERF_METRIC_MASKS", "masks")
	_add_grid_pair(queue_grid, "UI_PERF_METRIC_CACHES", "caches")

	_add_separator(_details)
	_add_section_title(_details, "UI_PERF_SECTION_RENDER")
	var render_grid := _make_metric_grid()
	_details.add_child(render_grid)
	_add_grid_pair(render_grid, "UI_PERF_METRIC_CPU", "cpu")
	_add_grid_pair(render_grid, "UI_PERF_METRIC_DRAW_CALLS", "draw_calls")
	_add_grid_pair(render_grid, "UI_PERF_METRIC_RENDER_OBJECTS", "render_objects")
	_add_grid_pair(render_grid, "UI_PERF_METRIC_MEMORY", "memory")


func _build_footer() -> void:
	_add_separator(_content)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.mouse_filter = MOUSE_FILTER_IGNORE
	_content.add_child(footer)
	_last_hitch_label = _make_label("", 10, TEXT_SECONDARY_COLOR)
	_last_hitch_label.clip_text = true
	_last_hitch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_last_hitch_label)
	_hint_label = _make_label("", 9, ACCENT_COLOR)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_hint_label)


func _refresh_presentation() -> void:
	if not visible:
		return
	if _streamer != null and is_instance_valid(_streamer) \
			and _streamer.has_method("get_perf_hud_snapshot"):
		_last_stream_snapshot = _streamer.call("get_perf_hud_snapshot") as Dictionary
	else:
		_last_stream_snapshot = { }
	_display_timing_peaks = _metrics.take_interval_timing_peaks()
	var stats: Dictionary = _metrics.get_frame_stats()
	var current_ms: float = float(stats.get("current_ms", 0.0))
	var sample_count: int = int(stats.get("sample_count", 0))
	var fps: float = Engine.get_frames_per_second()
	_fps_value.text = "—" if sample_count <= 0 else "%.0f" % fps
	_frame_value.text = "—" if sample_count <= 0 else "%.2f" % current_ms
	_p95_value.text = "—" if sample_count <= 0 else "%.2f" % float(stats.get("p95_ms", 0.0))
	_peak_value.text = "—" if sample_count <= 0 else "%.2f" % float(stats.get("max_ms", 0.0))
	_budget_bar.value = minf(current_ms, _budget_bar.max_value)
	var health: int = _resolve_overall_health(
		int(stats.get("health", PerformanceHudMetrics.Health.UNKNOWN)),
	)
	_apply_health(health)
	_refresh_summary()
	_refresh_timing_values()
	_refresh_queue_values()
	_refresh_render_values()
	_refresh_recorder_presentation()
	_refresh_last_hitch()
	if _graph != null and _details.visible:
		_graph.set_samples(_metrics.get_graph_samples())


func _refresh_summary() -> void:
	var streaming_ms: float = float(_display_timing_peaks.get("streaming_ms", 0.0))
	var resident_views: int = int(_last_stream_snapshot.get("resident_views", 0))
	var desired_chunks: int = int(_last_stream_snapshot.get("desired_visible_chunks", 0))
	var queue_total: int = int(_last_stream_snapshot.get("publish_queue", 0)) \
			+ int(_last_stream_snapshot.get("object_upload_queue", 0)) \
			+ int(_last_stream_snapshot.get("object_prestage_queue", 0)) \
			+ int(_last_stream_snapshot.get("grass_upload_queue", 0))
	var summary_format: String = _localize(
		"UI_PERF_SUMMARY",
		"STREAM %.2f ms   •   IN SCENE %d/%d   •   QUEUES %d",
	)
	_summary_label.text = summary_format % [
		streaming_ms,
		resident_views,
		desired_chunks,
		queue_total,
	]


func _refresh_timing_values() -> void:
	for key: String in DISPLAY_TIMING_KEYS:
		_set_value(key, PerformanceHudMetrics.format_ms(float(_display_timing_peaks.get(key, 0.0))))


func _refresh_queue_values() -> void:
	var s: Dictionary = _last_stream_snapshot
	_set_value(
		"chunks",
		"%d / %d" % [
			int(s.get("resident_views", 0)),
			int(s.get("desired_visible_chunks", 0)),
		],
	)
	_set_value(
		"packets",
		"%d / %d" % [
			int(s.get("packet_count", 0)),
			int(s.get("requested_packets", 0)),
		],
	)
	_set_value("publish_queue", str(int(s.get("publish_queue", 0))))
	_set_value("visibility_wait", str(int(s.get("visibility_wait", 0))))
	_set_value(
		"objects",
		"%d / %d / %d" % [
			int(s.get("object_upload_queue", 0)),
			int(s.get("object_prestage_queue", 0)),
			int(s.get("object_inflight", 0)),
		],
	)
	_set_value(
		"grass",
		"%d / %d / %d" % [
			int(s.get("grass_upload_queue", 0)),
			int(s.get("grass_inflight", 0)),
			int(s.get("grass_ready_cpu", 0)),
		],
	)
	var mask_inflight: int = int(s.get("mountain_mask_inflight", 0)) \
			+ int(s.get("terrain_mask_inflight", 0))
	var mask_upload: int = int(s.get("mountain_mask_upload_queue", 0)) \
			+ int(s.get("terrain_mask_upload_queue", 0))
	_set_value(
		"masks",
		"%d / %d / %d" % [
			mask_inflight,
			mask_upload,
			int(s.get("mask_retry_queue", 0)),
		],
	)
	_set_value(
		"caches",
		"%d/%d / %d" % [
			int(s.get("hot_view_cache", 0)),
			int(s.get("hot_view_cache_capacity", 0)),
			int(s.get("warm_packet_cache", 0)),
		],
	)


func _refresh_render_values() -> void:
	var cpu_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_ms: float = (
		float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	)
	_set_value("cpu", "%.2f / %.2f ms" % [cpu_ms, physics_ms])
	_set_value(
		"draw_calls",
		str(
			int(
				Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
				),
			),
		),
	)
	_set_value(
		"render_objects",
		str(
			int(
				Performance.get_monitor(
					Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
				),
			),
		),
	)
	var vram_bytes: int = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	var ram_bytes: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var vram_text: String = "—" if vram_bytes <= 0 \
	else PerformanceHudMetrics.format_bytes(vram_bytes)
	_set_value(
		"memory",
		"%s / %s" % [
			vram_text,
			PerformanceHudMetrics.format_bytes(ram_bytes),
		],
	)


func _refresh_recorder_presentation() -> void:
	if _recording_label == null or _hint_label == null:
		return
	var recorder_state: Dictionary = (
		_recorder.get_ui_state()
		if _recorder != null and is_instance_valid(_recorder)
		else { }
	)
	var is_recording: bool = bool(recorder_state.get("recording", false))
	var is_saving: bool = bool(recorder_state.get("saving", false))
	var is_capturing: bool = bool(recorder_state.get("capturing", false))
	_recording_label.visible = is_recording or is_saving or is_capturing
	if is_recording:
		var elapsed_seconds: int = int(recorder_state.get("elapsed_seconds", 0.0))
		_recording_label.text = _localize_with_args(
			"UI_PERF_REC_STATUS",
			{
				"minutes": "%02d" % (elapsed_seconds / 60),
				"seconds": "%02d" % (elapsed_seconds % 60),
				"captures": int(recorder_state.get("capture_count", 0)),
			},
		)
		_recording_label.add_theme_color_override("font_color", CRITICAL_COLOR)
	elif is_saving:
		_recording_label.text = _localize("UI_PERF_REC_SAVING")
		_recording_label.add_theme_color_override("font_color", WARNING_COLOR)
	else:
		_recording_label.text = _localize("UI_PERF_REC_CAPTURING")
		_recording_label.add_theme_color_override("font_color", ACCENT_COLOR)
	var hint_key: String = (
		"UI_PERF_HINT_HIDE"
		if _display_mode == DisplayMode.DETAILED
		else "UI_PERF_HINT_MORE"
	)
	_hint_label.text = _localize(hint_key)


func _refresh_last_hitch() -> void:
	var hitch: Dictionary = _metrics.get_last_hitch()
	if hitch.is_empty():
		_last_hitch_label.text = _localize("UI_PERF_LAST_HITCH_NONE")
		return
	var cause: String = String(hitch.get("cause", "external_or_render"))
	var cause_text: String = _localize("UI_PERF_CAUSE_%s" % cause.to_upper())
	if cause == "external_or_render":
		_last_hitch_label.text = "%s  %.2f ms  •  %s" % [
			_localize("UI_PERF_LAST_HITCH"),
			float(hitch.get("frame_ms", 0.0)),
			cause_text,
		]
	else:
		_last_hitch_label.text = "%s  %.2f ms  •  %s %.2f ms" % [
			_localize("UI_PERF_LAST_HITCH"),
			float(hitch.get("frame_ms", 0.0)),
			cause_text,
			float(hitch.get("cause_ms", 0.0)),
		]


func _resolve_overall_health(frame_health: int) -> int:
	if frame_health == PerformanceHudMetrics.Health.CRITICAL:
		return frame_health
	var object_queue: int = int(_last_stream_snapshot.get("object_upload_queue", 0)) \
			+ int(_last_stream_snapshot.get("object_prestage_queue", 0))
	var visibility_wait: int = int(_last_stream_snapshot.get("visibility_wait", 0))
	var publish_queue: int = int(_last_stream_snapshot.get("publish_queue", 0))
	if visibility_wait > VISIBILITY_WAIT_CRITICAL \
			or object_queue > OBJECT_QUEUE_CRITICAL \
			or publish_queue > PUBLISH_QUEUE_CRITICAL:
		return PerformanceHudMetrics.Health.CRITICAL
	if frame_health == PerformanceHudMetrics.Health.WARNING \
			or visibility_wait > 0 \
			or object_queue > OBJECT_QUEUE_WARNING \
			or publish_queue > PUBLISH_QUEUE_WARNING:
		return PerformanceHudMetrics.Health.WARNING
	return frame_health


func _apply_health(health: int) -> void:
	var color: Color = TEXT_SECONDARY_COLOR
	var status_key: String = "UI_PERF_STATUS_WARMING"
	match health:
		PerformanceHudMetrics.Health.GOOD:
			color = GOOD_COLOR
			status_key = "UI_PERF_STATUS_STABLE"
		PerformanceHudMetrics.Health.WARNING:
			color = WARNING_COLOR
			status_key = "UI_PERF_STATUS_PRESSURE"
		PerformanceHudMetrics.Health.CRITICAL:
			color = CRITICAL_COLOR
			status_key = "UI_PERF_STATUS_HITCH"
	_status_dot.add_theme_color_override("font_color", color)
	_status_label.add_theme_color_override("font_color", color)
	_status_label.text = _localize(status_key)
	_set_budget_bar_color(color)


func _set_budget_bar_color(color: Color) -> void:
	if _budget_fill_style == null:
		_budget_fill_style = StyleBoxFlat.new()
		_budget_fill_style.set_corner_radius_all(2)
		_budget_bar.add_theme_stylebox_override("fill", _budget_fill_style)
	_budget_fill_style.bg_color = color


func _apply_localization() -> void:
	if _status_label == null:
		return
	if _graph != null:
		_graph.set_window_label(_localize("UI_PERF_GRAPH_WINDOW"))
	_mode_label.text = _localize(
		"UI_PERF_MODE_DETAILED" \
		if _display_mode == DisplayMode.DETAILED \
		else "UI_PERF_MODE_COMPACT",
	)
	_refresh_recorder_presentation()
	for key_variant: Variant in _localized_labels.keys():
		var localization_key: String = String(key_variant)
		var label: Label = _localized_labels.get(localization_key, null) as Label
		if label != null:
			label.text = _localize(localization_key)
	_refresh_last_hitch()


func _on_language_changed(_locale: String) -> void:
	_apply_localization()
	if visible:
		_refresh_presentation()


func _animate_mode_change(detailed: bool) -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	if detailed:
		# A rapid compact -> detailed switch can interrupt the panel fade-in.
		# Restore the parent state before animating the details themselves.
		modulate.a = 1.0
		position = PANEL_POSITION
		_details.modulate.a = 0.0
		_active_tween = create_tween()
		_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_active_tween.tween_property(_details, "modulate:a", 1.0, 0.14)
		return
	modulate.a = 0.0
	position = PANEL_POSITION + Vector2(0.0, -5.0)
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_active_tween.tween_property(self, "position", PANEL_POSITION, 0.12)


func _add_primary_metric(
		parent: HBoxContainer,
		initial_value: String,
		caption_key: String,
		font_size: int,
) -> Label:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", -2)
	block.mouse_filter = MOUSE_FILTER_IGNORE
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(block)
	var value: Label = _make_label(initial_value, font_size, TEXT_PRIMARY_COLOR)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	block.add_child(value)
	var caption_label: Label = _make_localized_label(caption_key, 9, TEXT_SECONDARY_COLOR)
	block.add_child(caption_label)
	return value


func _add_vertical_rule(parent: HBoxContainer) -> void:
	var rule := ColorRect.new()
	rule.color = Color(0.35, 0.66, 0.72, 0.18)
	rule.custom_minimum_size = Vector2(1.0, 38.0)
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(rule)


func _add_separator(parent: VBoxContainer) -> void:
	var separator := ColorRect.new()
	separator.color = Color(0.35, 0.66, 0.72, 0.16)
	separator.custom_minimum_size = Vector2(0.0, 1.0)
	separator.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(separator)


func _add_section_title(parent: VBoxContainer, localization_key: String) -> void:
	var title: Label = _make_localized_label(localization_key, 10, ACCENT_COLOR)
	parent.add_child(title)


func _make_metric_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = MOUSE_FILTER_IGNORE
	return grid


func _add_grid_pair(grid: GridContainer, label_key: String, value_key: String) -> void:
	var label: Label = _make_localized_label(label_key, 10, TEXT_SECONDARY_COLOR)
	label.custom_minimum_size.x = 150.0
	label.clip_text = true
	grid.add_child(label)
	var value: Label = _make_label("—", 10, TEXT_PRIMARY_COLOR)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size.x = 120.0
	value.clip_text = true
	grid.add_child(value)
	_value_labels[value_key] = value


func _set_value(key: String, text: String) -> void:
	var label: Label = _value_labels.get(key, null) as Label
	if label != null:
		label.text = text


func _make_label(
		text_value: String,
		font_size: int,
		color: Color,
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label


func _make_localized_label(
		localization_key: String,
		font_size: int,
		color: Color,
) -> Label:
	var label: Label = _make_label(_localize(localization_key), font_size, color)
	_localized_labels[localization_key] = label
	return label


func _localize(localization_key: String, fallback: String = "") -> String:
	var localization: Node = get_node_or_null("/root/Localization")
	if localization != null and localization.has_method("t"):
		return String(localization.call("t", localization_key))
	return localization_key if fallback.is_empty() else fallback


func _localize_with_args(localization_key: String, args: Dictionary) -> String:
	var localization: Node = get_node_or_null("/root/Localization")
	if localization != null and localization.has_method("t"):
		return String(localization.call("t", localization_key, args))
	return localization_key
