class_name WorldChunkDebugOverlay
extends Node2D

## F11 chunk/world diagnostic overlay.
## Presentation-only: reads ChunkManager snapshots and never mutates world state.

const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")
const WorldPerfGraphUI = preload("res://core/debug/world_perf_graph_ui.gd")

const SNAPSHOT_INTERVAL_SEC: float = 0.10
const LOG_INTERVAL_SEC: float = 0.25
const LOG_DIR: String = "user://debug"
const LOG_PATH: String = "user://debug/f11_chunk_overlay.log"
const INCIDENT_LOG_PREFIX: String = "user://debug/f11_chunk_incident_"
const DEFAULT_QUEUE_ROWS: int = 16
const FONT_SIZE_CHUNK: int = 12
const FONT_SIZE_CHUNK_EXPANDED: int = 11
const MODES: Array[String] = ["compact", "expanded", "queue", "timeline", "perf", "forensics"]

var _chunk_manager: Node = null
var _ui_layer: CanvasLayer = null
var _game_world: Node2D = null
var _overlay_visible: bool = false
var _mode_index: int = 0
var _snapshot_timer: float = 0.0
var _log_timer: float = LOG_INTERVAL_SEC
var _log_write_index: int = 0
var _log_reset_for_session: bool = false
var _log_file: FileAccess = null
var _last_log_error: String = ""
var _snapshot: Dictionary = {}

var _ui_root: Control = null
var _top_label: Label = null
var _queue_label: Label = null
var _timeline_label: Label = null
var _legend_label: Label = null
var _perf_graph_panel: PanelContainer = null
var _perf_graph: WorldPerfGraphUI = null

func setup(chunk_manager: Node, ui_layer: CanvasLayer, game_world: Node2D = null) -> void:
	_chunk_manager = chunk_manager
	_ui_layer = ui_layer
	_game_world = game_world
	z_index = 900
	_build_ui()
	set_overlay_visible(false)

func _exit_tree() -> void:
	_close_log_file()

func is_overlay_visible() -> bool:
	return _overlay_visible

func toggle_overlay() -> void:
	set_overlay_visible(not _overlay_visible)

func cycle_mode() -> void:
	_mode_index = (_mode_index + 1) % MODES.size()
	_apply_mode_layout()
	if _overlay_visible:
		_refresh_snapshot()

func request_incident_dump() -> String:
	if _chunk_manager == null or not is_instance_valid(_chunk_manager):
		return ""
	if not _chunk_manager.has_method("get_chunk_debug_overlay_snapshot"):
		return ""
	var snapshot: Dictionary = _chunk_manager.get_chunk_debug_overlay_snapshot(DEFAULT_QUEUE_ROWS)
	return _write_incident_dump(snapshot)

func set_overlay_visible(value: bool) -> void:
	_overlay_visible = value
	visible = value
	if _ui_root != null:
		_ui_root.visible = value
	set_process(value)
	if value:
		_ensure_log_file()
		_snapshot_timer = SNAPSHOT_INTERVAL_SEC
		_log_timer = LOG_INTERVAL_SEC
		_refresh_snapshot()
	else:
		_close_log_file()
		queue_redraw()

func _process(delta: float) -> void:
	if not _overlay_visible:
		return
	_snapshot_timer += delta
	_log_timer += delta
	if _snapshot_timer >= SNAPSHOT_INTERVAL_SEC:
		_snapshot_timer = 0.0
		_refresh_snapshot()

func _draw() -> void:
	if not _overlay_visible or _snapshot.is_empty():
		return
	var generator: Node = _get_world_generator()
	if generator == null:
		return
	var chunks: Array = _snapshot.get("chunks", []) as Array
	if chunks.is_empty():
		return
	var player_chunk: Vector2i = _snapshot.get("player_chunk", Vector2i.ZERO) as Vector2i
	var chunk_px: float = _chunk_pixel_size(generator)
	if chunk_px <= 0.0:
		return
	_draw_radius_layers(player_chunk, chunk_px)
	for raw_entry: Variant in chunks:
		var entry: Dictionary = raw_entry as Dictionary
		_draw_chunk_entry(entry, player_chunk, chunk_px)

func _refresh_snapshot() -> void:
	if _chunk_manager == null or not is_instance_valid(_chunk_manager):
		return
	if not _chunk_manager.has_method("get_chunk_debug_overlay_snapshot"):
		return
	_snapshot = _chunk_manager.get_chunk_debug_overlay_snapshot(DEFAULT_QUEUE_ROWS)
	_update_ui()
	_write_log_snapshot_if_due()
	queue_redraw()

func _build_ui() -> void:
	if _ui_root != null:
		return
	_ui_root = Control.new()
	_ui_root.name = "WorldChunkDebugOverlayUI"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _ui_layer != null:
		_ui_layer.add_child(_ui_root)
	else:
		add_child(_ui_root)

	var top_panel: PanelContainer = _make_panel("TopMetricsPanel", Color(0.03, 0.04, 0.05, 0.86), Color(0.45, 0.58, 0.62, 0.80))
	top_panel.anchor_left = 0.0
	top_panel.anchor_right = 1.0
	top_panel.anchor_top = 0.0
	top_panel.anchor_bottom = 0.0
	top_panel.offset_left = 8.0
	top_panel.offset_right = -8.0
	top_panel.offset_top = 8.0
	top_panel.offset_bottom = 46.0
	_ui_root.add_child(top_panel)
	_top_label = _make_label(13, Color(0.84, 0.94, 0.92, 1.0))
	top_panel.add_child(_top_label)

	var queue_panel: PanelContainer = _make_panel("QueuePanel", Color(0.04, 0.05, 0.06, 0.88), Color(0.72, 0.52, 0.30, 0.84))
	queue_panel.anchor_left = 1.0
	queue_panel.anchor_right = 1.0
	queue_panel.anchor_top = 0.0
	queue_panel.anchor_bottom = 1.0
	queue_panel.offset_left = -430.0
	queue_panel.offset_right = -8.0
	queue_panel.offset_top = 58.0
	queue_panel.offset_bottom = -178.0
	_ui_root.add_child(queue_panel)
	_queue_label = _make_label(12, Color(0.93, 0.89, 0.78, 1.0))
	_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	queue_panel.add_child(_queue_label)

	var timeline_panel: PanelContainer = _make_panel("TimelinePanel", Color(0.03, 0.04, 0.06, 0.88), Color(0.38, 0.55, 0.80, 0.82))
	timeline_panel.anchor_left = 0.0
	timeline_panel.anchor_right = 1.0
	timeline_panel.anchor_top = 1.0
	timeline_panel.anchor_bottom = 1.0
	timeline_panel.offset_left = 8.0
	timeline_panel.offset_right = -438.0
	timeline_panel.offset_top = -168.0
	timeline_panel.offset_bottom = -8.0
	_ui_root.add_child(timeline_panel)
	_timeline_label = _make_label(12, Color(0.82, 0.88, 0.98, 1.0))
	_timeline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timeline_panel.add_child(_timeline_label)

	var legend_panel: PanelContainer = _make_panel("LegendPanel", Color(0.03, 0.04, 0.05, 0.76), Color(0.40, 0.48, 0.52, 0.70))
	legend_panel.anchor_left = 0.0
	legend_panel.anchor_right = 0.0
	legend_panel.anchor_top = 0.0
	legend_panel.anchor_bottom = 0.0
	legend_panel.offset_left = 8.0
	legend_panel.offset_right = 420.0
	legend_panel.offset_top = 58.0
	legend_panel.offset_bottom = 112.0
	_ui_root.add_child(legend_panel)
	_legend_label = _make_label(11, Color(0.78, 0.84, 0.84, 1.0))
	legend_panel.add_child(_legend_label)

	_perf_graph_panel = _make_panel("PerfGraphPanel", Color(0.02, 0.02, 0.02, 0.90), Color(0.20, 0.80, 0.40, 0.80))
	_perf_graph_panel.anchor_left = 0.0
	_perf_graph_panel.anchor_right = 1.0
	_perf_graph_panel.anchor_top = 1.0
	_perf_graph_panel.anchor_bottom = 1.0
	_perf_graph_panel.offset_left = 8.0
	_perf_graph_panel.offset_right = -438.0
	_perf_graph_panel.offset_top = -250.0
	_perf_graph_panel.offset_bottom = -8.0
	_perf_graph_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_perf_graph_panel)
	
	_perf_graph = WorldPerfGraphUI.new()
	_perf_graph_panel.add_child(_perf_graph)

	_apply_mode_layout()

func _make_panel(node_name: String, bg_color: Color, border_color: Color) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_label(font_size: int, font_color: Color) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _apply_mode_layout() -> void:
	if _legend_label != null:
		_legend_label.text = "%s: %s | F11: %s | Shift+F11: %s | Ctrl+F11: %s" % [
			_tr("UI_DEBUG_CHUNK_OVERLAY_TITLE"),
			_current_mode_label(),
			_tr("UI_DEBUG_CHUNK_OVERLAY_TOGGLE_HINT"),
			_tr("UI_DEBUG_CHUNK_OVERLAY_MODE_HINT"),
			_tr("UI_DEBUG_CHUNK_OVERLAY_DUMP_HINT"),
		]
	
	var mode: String = _current_mode()
	var show_queue: bool = mode in ["queue", "expanded", "forensics"]
	var show_timeline: bool = mode in ["timeline", "forensics"]
	var show_perf: bool = mode == "perf"
	
	if _queue_label != null and _queue_label.get_parent() != null:
		_queue_label.get_parent().visible = show_queue
	if _timeline_label != null and _timeline_label.get_parent() != null:
		_timeline_label.get_parent().visible = show_timeline
	if _perf_graph_panel != null:
		_perf_graph_panel.visible = show_perf

func _update_ui() -> void:
	if _snapshot.is_empty():
		return
	var metrics: Dictionary = _snapshot.get("metrics", {}) as Dictionary
	if _top_label != null:
		_top_label.text = _format_top_summary(metrics)
	if _queue_label != null:
		_queue_label.text = _format_forensics_summary(_snapshot) if _current_mode() == "forensics" else _format_queue(_snapshot)
	if _timeline_label != null:
		_timeline_label.text = _format_forensics_timeline(_snapshot) if _current_mode() == "forensics" else _format_timeline(_snapshot)
	if _legend_label != null:
		_apply_mode_layout()

func _current_mode() -> String:
	return MODES[_mode_index]

func _current_mode_label() -> String:
	if _current_mode() == "forensics":
		return _tr("UI_DEBUG_CHUNK_OVERLAY_MODE_FORENSICS")
	return _current_mode()

func _format_top_summary(metrics: Dictionary) -> String:
	var queue_sizes: Dictionary = metrics.get("queue_sizes", {}) as Dictionary
	return "%s | FPS %.0f | frame %s | world %s | gen %s | visual %s | Q load %d gen %d ready %d visual %d | chunks %d loaded / %d visible / %d sim | unloading %d | stalled %d | worst %s | avg %s | load/s %d unload/s %d" % [
		_tr("UI_DEBUG_CHUNK_OVERLAY_TITLE"),
		float(metrics.get("fps", 0.0)),
		_fmt_ms(float(metrics.get("frame_time_ms", 0.0))),
		_fmt_ms(float(metrics.get("world_update_ms", 0.0))),
		_fmt_ms(float(metrics.get("chunk_generation_ms", 0.0))),
		_fmt_ms(float(metrics.get("visual_build_ms", 0.0))),
		int(queue_sizes.get("load", 0)),
		int(queue_sizes.get("generate_active", 0)),
		int(queue_sizes.get("data_ready", 0)),
		int(queue_sizes.get("visual", 0)),
		int(metrics.get("loaded_chunks", 0)),
		int(metrics.get("visible_chunks", 0)),
		int(metrics.get("simulating_chunks", 0)),
		int(metrics.get("unloading_chunks", 0)),
		int(metrics.get("stalled_chunks", 0)),
		_fmt_ms(float(metrics.get("worst_chunk_stage_time_ms", 0.0))),
		_fmt_ms(float(metrics.get("average_chunk_processing_time_ms", 0.0))),
		int(metrics.get("load_per_sec", 0)),
		int(metrics.get("unload_per_sec", 0)),
	]

func _format_queue(snapshot: Dictionary) -> String:
	var rows: Array = snapshot.get("queue_rows", []) as Array
	var lines: Array[String] = [_tr("UI_DEBUG_CHUNK_OVERLAY_QUEUE")]
	if rows.is_empty():
		lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_NO_QUEUE"))
	for raw_row: Variant in rows:
		var row: Dictionary = raw_row as Dictionary
		var coord_text: String = ""
		if str(row.get("scope", "")) == "chunk":
			coord_text = " %s" % [row.get("chunk_coord", Vector2i.ZERO)]
		var count: int = int(row.get("count", 1))
		var count_text: String = " x%d" % count if count > 1 else ""
		var age_ms: float = float(row.get("age_ms", -1.0))
		var age_text: String = _fmt_ms(age_ms) if age_ms >= 0.0 else "-"
		lines.append("%s%s%s | %s | %s | %s | %s" % [
			str(row.get("task_type_human", "")),
			coord_text,
			count_text,
			str(row.get("stage_human", "")),
			age_text,
			str(row.get("priority", "")),
			str(row.get("reason", "")),
		])
	var hidden_count: int = int(snapshot.get("queue_hidden_count", 0))
	if hidden_count > 0:
		lines.append("+%d скрыто антиспам-фильтром" % hidden_count)
	return "\n".join(lines)

func _format_timeline(snapshot: Dictionary) -> String:
	var events: Array = snapshot.get("timeline_events", []) as Array
	var lines: Array[String] = [_tr("UI_DEBUG_CHUNK_OVERLAY_TIMELINE")]
	if events.is_empty():
		lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_NO_EVENTS"))
	var start_index: int = maxi(0, events.size() - 8)
	for idx: int in range(start_index, events.size()):
		var event: Dictionary = events[idx] as Dictionary
		var repeat_count: int = int(event.get("repeat_count", 1))
		var repeat_text: String = " x%d" % repeat_count if repeat_count > 1 else ""
		lines.append("[%s] %s%s" % [
			str(event.get("timestamp_label", "--:--:--.---")),
			str(event.get("summary", "")),
			repeat_text,
		])
	return "\n".join(lines)

func _format_forensics_summary(snapshot: Dictionary) -> String:
	var summary: Dictionary = snapshot.get("incident_summary", {}) as Dictionary
	var suspicion_flags: Array = snapshot.get("suspicion_flags", []) as Array
	var chunk_rows: Array = snapshot.get("chunk_causality_rows", []) as Array
	var task_rows: Array = snapshot.get("task_debug_rows", []) as Array
	var lines: Array[String] = [_tr("UI_DEBUG_CHUNK_OVERLAY_MODE_FORENSICS")]
	if str(summary.get("status", "no_active_incident")) == "no_active_incident":
		lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_NO_INCIDENT"))
	else:
		lines.append("trace=%s | incident=%s | source=%s | stage=%s | age=%s" % [
			str(summary.get("trace_id", "")),
			str(summary.get("incident_id", "")),
			str(summary.get("source_system", "")),
			str(summary.get("stage", "")),
			_fmt_ms(float(summary.get("age_ms", -1.0))),
		])
		lines.append("primary=%s | player=%s | chunks=%d | events=%d | full_far=%d | border_fix_near=%d | shadow=%s" % [
			str(summary.get("primary_chunk", Vector2i.ZERO)),
			str(summary.get("player_chunk", Vector2i.ZERO)),
			int(summary.get("chunk_count", 0)),
			int(summary.get("event_count", 0)),
			int(summary.get("queue_full_far", 0)),
			int(summary.get("queue_border_fix_near", 0)),
			_fmt_ms(float(summary.get("shadow_ms", 0.0))),
		])
	lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_SUSPICIONS"))
	if suspicion_flags.is_empty():
		lines.append("-")
	else:
		for raw_flag: Variant in suspicion_flags:
			var flag: Dictionary = raw_flag as Dictionary
			lines.append("- %s | %s" % [str(flag.get("label", "")), str(flag.get("detail", ""))])
	lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_CHUNK_CAUSALITY"))
	if chunk_rows.is_empty():
		lines.append("-")
	else:
		for raw_row: Variant in chunk_rows:
			lines.append(_format_forensics_chunk_row(raw_row as Dictionary))
	lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_TASK_CAUSALITY"))
	if task_rows.is_empty():
		lines.append("-")
	else:
		for raw_task: Variant in task_rows:
			lines.append(_format_forensics_task_row(raw_task as Dictionary))
	return "\n".join(lines)

func _format_forensics_timeline(snapshot: Dictionary) -> String:
	var lines: Array[String] = [_tr("UI_DEBUG_CHUNK_OVERLAY_TRACE_EVENTS")]
	var events: Array = snapshot.get("trace_events", []) as Array
	if events.is_empty():
		lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_NO_INCIDENT"))
	else:
		for raw_event: Variant in events:
			lines.append(_format_forensics_trace_event(raw_event as Dictionary))
	lines.append("")
	lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_TIMELINE"))
	var timeline_events: Array = snapshot.get("timeline_events", []) as Array
	if timeline_events.is_empty():
		lines.append(_tr("UI_DEBUG_CHUNK_OVERLAY_NO_EVENTS"))
	else:
		var start_index: int = maxi(0, timeline_events.size() - 5)
		for idx: int in range(start_index, timeline_events.size()):
			var event: Dictionary = timeline_events[idx] as Dictionary
			lines.append("[%s] %s" % [
				str(event.get("timestamp_label", "--:--:--.---")),
				str(event.get("summary", "")),
			])
	return "\n".join(lines)

func _format_forensics_chunk_row(row: Dictionary) -> String:
	var pending_tasks: Array = row.get("pending_tasks", []) as Array
	var pending_text: String = ",".join(pending_tasks) if not pending_tasks.is_empty() else "-"
	return "%s%s | %s | phase=%s | age=%s | trace_age=%s | pending=%s | last=%s/%s" % [
		"[P] " if bool(row.get("is_player_chunk", false)) else "",
		str(row.get("coord", Vector2i.ZERO)),
		str(row.get("state_human", row.get("state", ""))),
		str(row.get("visual_phase", "")),
		_fmt_ms(float(row.get("stage_age_ms", -1.0))),
		_fmt_ms(float(row.get("trace_age_ms", -1.0))),
		pending_text,
		str(row.get("last_source_system", "")),
		str(row.get("last_event", "")),
	]

func _format_forensics_task_row(row: Dictionary) -> String:
	return "%s %s | %s | age=%s | requeue=%d | status=%s | skip=%s | budget=%s" % [
		str(row.get("kind", "")),
		str(row.get("coord", Vector2i.ZERO)),
		str(row.get("band", "")),
		_fmt_ms(float(row.get("age_ms", -1.0))),
		int(row.get("requeue_count", 0)),
		str(row.get("status", "")),
		str(row.get("last_skip_reason", "")),
		str(row.get("last_budget_state", "")),
	]

func _format_forensics_trace_event(event: Dictionary) -> String:
	var repeat_count: int = int(event.get("repeat_count", 1))
	var repeat_text: String = " x%d" % repeat_count if repeat_count > 1 else ""
	return "[%s] %s | %s | %s | %s%s" % [
		str(event.get("timestamp_label", "--:--:--.---")),
		str(event.get("source_system", "")),
		str(event.get("label", event.get("event_key", ""))),
		str(event.get("coord", Vector2i.ZERO)),
		var_to_str(event.get("detail_fields", {})),
		repeat_text,
	]

func _ensure_log_file() -> void:
	if _log_file != null:
		return
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		var dir_result: Error = DirAccess.make_dir_recursive_absolute(LOG_DIR)
		if dir_result != OK and not DirAccess.dir_exists_absolute(LOG_DIR):
			_last_log_error = "не удалось создать папку %s: %s" % [LOG_DIR, error_string(dir_result)]
			push_warning(_last_log_error)
			return
	var mode: FileAccess.ModeFlags = FileAccess.WRITE if not _log_reset_for_session else FileAccess.READ_WRITE
	_log_file = FileAccess.open(LOG_PATH, mode)
	if _log_file == null:
		_last_log_error = "не удалось открыть F11 debug log %s: %s" % [LOG_PATH, error_string(FileAccess.get_open_error())]
		push_warning(_last_log_error)
		return
	if _log_reset_for_session:
		_log_file.seek_end()
		_store_log_line("")
		_store_log_line("===== F11 overlay открыт повторно: %s =====" % _system_timestamp())
	else:
		_log_reset_for_session = true
		_write_log_header()

func _close_log_file() -> void:
	if _log_file == null:
		return
	_log_file.flush()
	_log_file.close()
	_log_file = null

func _write_log_header() -> void:
	_store_log_line("F11 Chunk Debug Overlay Log")
	_store_log_line("Создан: %s" % _system_timestamp())
	_store_log_line("Godot path: %s" % LOG_PATH)
	_store_log_line("OS path: %s" % ProjectSettings.globalize_path(LOG_PATH))
	_store_log_line("Пишется только пока F11 overlay открыт. Файл перезаписывается при первом открытии F11 в новом запуске игры.")
	_store_log_line("Источник данных: ChunkManager.get_chunk_debug_overlay_snapshot(); overlay не мутирует мир и не читает консоль.")

func _write_log_snapshot_if_due() -> void:
	if not _overlay_visible or _snapshot.is_empty() or _log_file == null:
		return
	if _log_timer < LOG_INTERVAL_SEC:
		return
	_log_timer = 0.0
	_write_log_snapshot()

func _write_log_snapshot() -> void:
	_log_write_index += 1
	var metrics: Dictionary = _snapshot.get("metrics", {}) as Dictionary
	var queue_rows: Array = _snapshot.get("queue_rows", []) as Array
	var timeline_events: Array = _snapshot.get("timeline_events", []) as Array
	var chunks: Array = _snapshot.get("chunks", []) as Array
	var incident_summary: Dictionary = _snapshot.get("incident_summary", {}) as Dictionary
	var suspicion_flags: Array = _snapshot.get("suspicion_flags", []) as Array
	var trace_events: Array = _snapshot.get("trace_events", []) as Array
	var chunk_rows: Array = _snapshot.get("chunk_causality_rows", []) as Array
	var task_rows: Array = _snapshot.get("task_debug_rows", []) as Array
	_store_log_line("")
	_store_log_line("===== snapshot #%d | %s | frame=%d | mode=%s =====" % [
		_log_write_index,
		_system_timestamp(),
		Engine.get_process_frames(),
		MODES[_mode_index],
	])
	_store_log_line("[Верхняя сводка]")
	_store_log_line(_format_top_summary(metrics))
	_store_log_line("[Игрок и радиусы]")
	_store_log_line("active_z=%s | player_chunk=%s | player_motion=%s | radii=%s" % [
		str(_snapshot.get("active_z", "?")),
		str(_snapshot.get("player_chunk", Vector2i.ZERO)),
		str(_snapshot.get("player_motion", Vector2i.ZERO)),
		var_to_str(_snapshot.get("radii", {})),
	])
	_store_log_line("[Очередь pipeline]")
	_store_log_line("visible_rows=%d | hidden_by_antispam=%d" % [
		queue_rows.size(),
		int(_snapshot.get("queue_hidden_count", 0)),
	])
	if queue_rows.is_empty():
		_store_log_line("- Очередь пуста.")
	else:
		for raw_row: Variant in queue_rows:
			_store_log_line(_format_log_queue_row(raw_row as Dictionary))
	_store_log_line("[Ошибки и зависания]")
	var problem_lines: Array[String] = _collect_log_problem_lines(chunks)
	if problem_lines.is_empty():
		_store_log_line("- Нет видимых error/stalled чанков в текущем bounded snapshot.")
	else:
		for problem_line: String in problem_lines:
			_store_log_line(problem_line)
	_store_log_line("[Таймлайн]")
	if timeline_events.is_empty():
		_store_log_line("- Событий пока нет.")
	else:
		for raw_event: Variant in timeline_events:
			_store_log_line(_format_log_timeline_event(raw_event as Dictionary))
	_store_log_line("[Forensics incident]")
	_store_log_line(var_to_str(incident_summary))
	_store_log_line("[Forensics suspicions]")
	if suspicion_flags.is_empty():
		_store_log_line("- Нет активных подозрений.")
	else:
		for raw_flag: Variant in suspicion_flags:
			_store_log_line("- %s" % var_to_str(raw_flag))
	_store_log_line("[Forensics trace]")
	if trace_events.is_empty():
		_store_log_line("- Trace events отсутствуют.")
	else:
		for raw_trace: Variant in trace_events:
			_store_log_line("- %s" % var_to_str(raw_trace))
	_store_log_line("[Forensics chunk causality]")
	if chunk_rows.is_empty():
		_store_log_line("- Chunk causality rows отсутствуют.")
	else:
		for raw_chunk_row: Variant in chunk_rows:
			_store_log_line("- %s" % var_to_str(raw_chunk_row))
	_store_log_line("[Forensics task debug]")
	if task_rows.is_empty():
		_store_log_line("- Task debug rows отсутствуют.")
	else:
		for raw_task_row: Variant in task_rows:
			_store_log_line("- %s" % var_to_str(raw_task_row))
	_store_log_line("[Чанки в bounded snapshot]")
	for raw_chunk: Variant in chunks:
		_store_log_line(_format_log_chunk_entry(raw_chunk as Dictionary))
	_store_log_line("[Технический снимок]")
	_store_log_line("metrics=%s" % var_to_str(metrics))
	_log_file.flush()

func _write_incident_dump(snapshot: Dictionary) -> String:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		var dir_result: Error = DirAccess.make_dir_recursive_absolute(LOG_DIR)
		if dir_result != OK and not DirAccess.dir_exists_absolute(LOG_DIR):
			push_warning("не удалось создать папку incident dump: %s" % error_string(dir_result))
			return ""
	var date_info: Dictionary = Time.get_datetime_dict_from_system()
	var suffix: String = "%04d%02d%02d_%02d%02d%02d" % [
		int(date_info.get("year", 0)),
		int(date_info.get("month", 0)),
		int(date_info.get("day", 0)),
		int(date_info.get("hour", 0)),
		int(date_info.get("minute", 0)),
		int(date_info.get("second", 0)),
	]
	suffix += "_%03d" % int(Time.get_ticks_msec() % 1000)
	var log_path: String = "%s%s.log" % [INCIDENT_LOG_PREFIX, suffix]
	var dump_file: FileAccess = FileAccess.open(log_path, FileAccess.WRITE)
	if dump_file == null:
		push_warning("не удалось открыть incident dump %s: %s" % [log_path, error_string(FileAccess.get_open_error())])
		return ""
	var incident_summary: Dictionary = snapshot.get("incident_summary", {}) as Dictionary
	var suspicion_flags: Array = snapshot.get("suspicion_flags", []) as Array
	var trace_events: Array = snapshot.get("trace_events", []) as Array
	var chunk_rows: Array = snapshot.get("chunk_causality_rows", []) as Array
	var task_rows: Array = snapshot.get("task_debug_rows", []) as Array
	var timeline_events: Array = snapshot.get("timeline_events", []) as Array
	dump_file.store_line("F11 Chunk Incident Dump")
	dump_file.store_line("Создан: %s" % _system_timestamp())
	dump_file.store_line("Godot path: %s" % log_path)
	dump_file.store_line("OS path: %s" % ProjectSettings.globalize_path(log_path))
	dump_file.store_line("[Summary]")
	dump_file.store_line(var_to_str(incident_summary))
	if str(incident_summary.get("status", "no_active_incident")) == "no_active_incident":
		dump_file.store_line("no_active_incident")
	dump_file.store_line("[Suspicion Flags]")
	if suspicion_flags.is_empty():
		dump_file.store_line("-")
	else:
		for raw_flag: Variant in suspicion_flags:
			dump_file.store_line(var_to_str(raw_flag as Dictionary))
	dump_file.store_line("[Trace Events]")
	if trace_events.is_empty():
		dump_file.store_line("-")
	else:
		for raw_event: Variant in trace_events:
			dump_file.store_line(var_to_str(raw_event as Dictionary))
	dump_file.store_line("[Chunk Causality]")
	if chunk_rows.is_empty():
		dump_file.store_line("-")
	else:
		for raw_chunk: Variant in chunk_rows:
			dump_file.store_line(var_to_str(raw_chunk as Dictionary))
	dump_file.store_line("[Task Debug]")
	if task_rows.is_empty():
		dump_file.store_line("-")
	else:
		for raw_task: Variant in task_rows:
			dump_file.store_line(var_to_str(raw_task as Dictionary))
	dump_file.store_line("[Timeline]")
	if timeline_events.is_empty():
		dump_file.store_line("-")
	else:
		for raw_timeline: Variant in timeline_events:
			dump_file.store_line(_format_log_timeline_event(raw_timeline as Dictionary))
	dump_file.store_line("[Raw Snapshot]")
	dump_file.store_line(var_to_str(snapshot))
	dump_file.flush()
	dump_file.close()
	return ProjectSettings.globalize_path(log_path)

func _store_log_line(line: String) -> void:
	if _log_file == null:
		return
	_log_file.store_line(line)

func _format_log_queue_row(row: Dictionary) -> String:
	return "- id=%s | trace=%s incident=%s | task=%s | coord=%s | stage=%s | status=%s | age=%s | priority=%s | impact=%s | count=%d | depth=%d | completed_recently=%s | reason=%s" % [
		str(row.get("task_id", "")),
		str(row.get("trace_id", "")),
		str(row.get("incident_id", "")),
		str(row.get("task_type_human", row.get("task_type", ""))),
		str(row.get("chunk_coord", "-")) if str(row.get("scope", "")) == "chunk" else str(row.get("scope", "")),
		str(row.get("stage_human", row.get("stage", ""))),
		str(row.get("status", "")),
		_fmt_ms(float(row.get("age_ms", -1.0))),
		str(row.get("priority", "")),
		str(row.get("impact", "")),
		int(row.get("count", 1)),
		int(row.get("queue_depth", 0)),
		str(row.get("completed_recently", false)),
		str(row.get("reason", "")),
	]

func _format_log_timeline_event(event: Dictionary) -> String:
	return "- [%s] id=%s repeat=%d trace=%s incident=%s actor=%s action=%s state=%s impact=%s severity=%s code=%s | %s | details=%s" % [
		str(event.get("timestamp_label", "--:--:--.---")),
		str(event.get("event_id", "")),
		int(event.get("repeat_count", 1)),
		str(event.get("trace_id", "")),
		str(event.get("incident_id", "")),
		str(event.get("actor", "")),
		str(event.get("action", "")),
		str(event.get("state", "")),
		str(event.get("impact", "")),
		str(event.get("severity", "")),
		str(event.get("technical_code", "")),
		str(event.get("summary", "")),
		var_to_str(event.get("detail_fields", {})),
	]

func _format_log_chunk_entry(entry: Dictionary) -> String:
	return "- chunk=%s z=%d | state=%s/%s | age=%s | priority=%s | distance=%d | visible=%s | simulating=%s | player=%s | requested_frame=%d | visual_phase=%s | code=%s | reason=%s" % [
		str(entry.get("coord", Vector2i.ZERO)),
		int(entry.get("z", 0)),
		str(entry.get("state_human", "")),
		str(entry.get("state", "")),
		_fmt_ms(float(entry.get("stage_age_ms", -1.0))),
		str(entry.get("priority", "")),
		int(entry.get("distance", -1)),
		str(entry.get("is_visible", false)),
		str(entry.get("is_simulating", false)),
		str(entry.get("is_player_chunk", false)),
		int(entry.get("requested_frame", -1)),
		str(entry.get("visual_phase", "")),
		str(entry.get("technical_code", "")),
		str(entry.get("reason", "")),
	]

func _collect_log_problem_lines(chunks: Array) -> Array[String]:
	var lines: Array[String] = []
	for raw_chunk: Variant in chunks:
		var entry: Dictionary = raw_chunk as Dictionary
		var state: String = str(entry.get("state", ""))
		if state == "error" or state == "stalled" or bool(entry.get("is_stalled", false)):
			lines.append(_format_log_chunk_entry(entry))
	return lines

func _system_timestamp() -> String:
	return Time.get_datetime_string_from_system(false, true)

func _draw_radius_layers(player_chunk: Vector2i, chunk_px: float) -> void:
	var radii: Dictionary = _snapshot.get("radii", {}) as Dictionary
	_draw_radius_square(player_chunk, int(radii.get("retention_radius", 0)), chunk_px, Color(0.22, 0.42, 0.92, 0.92), "retention/unload", 18.0)
	_draw_radius_square(player_chunk, int(radii.get("render_radius", 0)), chunk_px, Color(0.38, 0.80, 1.0, 0.96), "render/far visual", 34.0)
	_draw_radius_square(player_chunk, int(radii.get("preload_radius", 0)), chunk_px, Color(0.36, 0.86, 0.58, 0.96), "preload/load", 50.0)
	_draw_radius_square(player_chunk, int(radii.get("simulation_radius", 0)), chunk_px, Color(0.96, 0.82, 0.32, 0.96), "simulation", 66.0)

func _draw_radius_square(player_chunk: Vector2i, radius: int, chunk_px: float, color: Color, label: String, label_y_offset: float) -> void:
	if radius < 0:
		return
	var center_display: Vector2i = _get_display_chunk_coord(player_chunk, player_chunk)
	var top_left_chunk: Vector2i = center_display - Vector2i(radius, radius)
	var rect: Rect2 = Rect2(
		Vector2(top_left_chunk.x * chunk_px, top_left_chunk.y * chunk_px),
		Vector2((radius * 2 + 1) * chunk_px, (radius * 2 + 1) * chunk_px)
	)
	draw_rect(rect, color, false, 4.0)
	var font: Font = ThemeDB.fallback_font
	if font != null:
		draw_string(font, rect.position + Vector2(8.0, label_y_offset), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, color)

func _draw_chunk_entry(entry: Dictionary, player_chunk: Vector2i, chunk_px: float) -> void:
	var coord: Vector2i = entry.get("coord", Vector2i.ZERO) as Vector2i
	var display_coord: Vector2i = _get_display_chunk_coord(coord, player_chunk)
	var rect: Rect2 = Rect2(
		Vector2(display_coord.x * chunk_px, display_coord.y * chunk_px),
		Vector2(chunk_px, chunk_px)
	)
	var state: String = str(entry.get("state", "absent"))
	draw_rect(rect, _state_fill_color(state), true)
	var border_color: Color = Color(0.16, 0.19, 0.20, 0.72)
	var border_width: float = 1.5
	if bool(entry.get("is_player_chunk", false)):
		border_color = Color(1.0, 0.94, 0.58, 1.0)
		border_width = 5.0
	elif bool(entry.get("is_simulating", false)):
		border_color = Color(0.74, 0.94, 0.78, 0.90)
		border_width = 2.5
	if bool(entry.get("is_stalled", false)):
		border_color = Color(1.0, 0.20, 0.16, 1.0)
		border_width = 4.0
	draw_rect(rect, border_color, false, border_width)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var label: String = "%d,%d" % [coord.x, coord.y]
	var font_size: int = FONT_SIZE_CHUNK
	if MODES[_mode_index] == "expanded":
		font_size = FONT_SIZE_CHUNK_EXPANDED
		label = "%s\n%s %.0fms\n%s" % [
			label,
			str(entry.get("state_human", state)),
			float(entry.get("stage_age_ms", -1.0)),
			str(entry.get("priority", "")),
		]
	draw_string(font, rect.position + Vector2(8.0, 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, chunk_px - 12.0, font_size, Color(0.94, 0.98, 0.96, 0.95))

func _state_fill_color(state: String) -> Color:
	match state:
		"absent":
			return Color(0.02, 0.02, 0.025, 0.10)
		"requested":
			return Color(0.26, 0.36, 0.88, 0.22)
		"queued":
			return Color(0.22, 0.52, 0.86, 0.30)
		"generating":
			return Color(0.92, 0.56, 0.18, 0.36)
		"data_ready":
			return Color(0.92, 0.82, 0.26, 0.38)
		"building_visual":
			return Color(0.78, 0.42, 0.94, 0.34)
		"ready":
			return Color(0.32, 0.84, 0.52, 0.30)
		"visible":
			return Color(0.42, 0.96, 0.64, 0.26)
		"simulating":
			return Color(0.56, 0.96, 0.86, 0.32)
		"unloading":
			return Color(0.72, 0.70, 0.72, 0.28)
		"error":
			return Color(1.0, 0.05, 0.05, 0.52)
		"stalled":
			return Color(1.0, 0.12, 0.07, 0.46)
		_:
			return Color(0.25, 0.25, 0.25, 0.20)

func _fmt_ms(value: float) -> String:
	if value < 0.0:
		return "-"
	return "%.1f ms" % value

func _tr(key: String) -> String:
	var localization: Node = get_node_or_null("/root/Localization")
	if localization != null and localization.has_method("t"):
		return str(localization.call("t", key))
	return key

func _get_world_generator() -> Node:
	return get_node_or_null("/root/WorldGenerator")

func _chunk_pixel_size(generator: Node) -> float:
	var balance: Resource = generator.get("balance") as Resource
	if balance == null:
		return 0.0
	return float(int(balance.get("chunk_size_tiles")) * int(balance.get("tile_size")))

func _get_display_chunk_coord(coord: Vector2i, reference_chunk: Vector2i) -> Vector2i:
	var generator: Node = _get_world_generator()
	if generator != null and generator.has_method("get_display_chunk_coord"):
		return generator.call("get_display_chunk_coord", coord, reference_chunk) as Vector2i
	return coord
