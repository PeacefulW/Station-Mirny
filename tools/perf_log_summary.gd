extends SceneTree

const LOG_ARG_PREFIX: String = "codex_perf_log="
const OUTPUT_DIR_ARG_PREFIX: String = "codex_perf_output_dir="
const OUTPUT_PREFIX_ARG_PREFIX: String = "codex_perf_output_prefix="
const DEFAULT_OUTPUT_DIR: String = "res://debug_exports/perf"
const MAX_CAPTURED_LINES: int = 24

var _startup_metric_regex: RegEx = RegEx.new()
var _frame_time_regex: RegEx = RegEx.new()
var _world_perf_timing_regex: RegEx = RegEx.new()
var _route_prepared_regex: RegEx = RegEx.new()
var _route_start_regex: RegEx = RegEx.new()
var _route_complete_regex: RegEx = RegEx.new()
var _route_drain_regex: RegEx = RegEx.new()
var _reached_waypoint_regex: RegEx = RegEx.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _compile_regexes():
		return
	var log_arg: String = _get_user_arg_value(LOG_ARG_PREFIX)
	if log_arg.is_empty():
		_fail("Missing required user arg `%s<path>`" % LOG_ARG_PREFIX)
		return
	var log_path: String = _resolve_input_path(log_arg)
	if not FileAccess.file_exists(log_path):
		_fail("Perf log not found: %s" % log_path)
		return
	var log_text: String = FileAccess.get_file_as_string(log_path)
	if log_text.is_empty():
		_fail("Perf log is empty: %s" % log_path)
		return
	var summary: Dictionary = _build_summary(log_text, log_path)
	var output_paths: Dictionary = _write_summary_artifacts(summary, log_path)
	print("[PerfLogSummary] summary written: json=%s md=%s" % [
		output_paths.get("json_path", ""),
		output_paths.get("md_path", ""),
	])
	if bool(summary.get("validation_failed", false)) or bool(summary.get("catch_up_timeout", false)):
		print("[PerfLogSummary] validation status indicates failure in source log")
		quit(2)
		return
	quit(0)

func _compile_regexes() -> bool:
	return _compile_regex(_startup_metric_regex, "^\\[WorldPerf\\] (Startup\\.[^:]+): ([0-9]+(?:\\.[0-9]+)?) ms$") \
		and _compile_regex(_frame_time_regex, "^\\[WorldPerf\\] Frame time: avg=([0-9]+(?:\\.[0-9]+)?) ms, p99=([0-9]+(?:\\.[0-9]+)?) ms, hitches=(\\d+)$") \
		and _compile_regex(_world_perf_timing_regex, "^\\[WorldPerf\\] ([^:]+): ([0-9]+(?:\\.[0-9]+)?) ms$") \
		and _compile_regex(_route_prepared_regex, "^\\[CodexValidation\\] route prepared: preset=([a-z_]+) waypoints=(\\d+) start=(.+) chunk_pixels=([0-9]+(?:\\.[0-9]+)?)$") \
		and _compile_regex(_route_start_regex, "^\\[CodexValidation\\] route start: preset=([a-z_]+) waypoints=(\\d+)$") \
		and _compile_regex(_route_complete_regex, "^\\[CodexValidation\\] route complete: preset=([a-z_]+) reached=(\\d+)/(\\d+) draining_background_work=true$") \
		and _compile_regex(_route_drain_regex, "^\\[CodexValidation\\] route drain complete(?::|;) preset=([a-z_]+) reached=(\\d+)/(\\d+) redraw_backlog=(true|false)(?: state=(.*))?$") \
		and _compile_regex(_reached_waypoint_regex, "^\\[CodexValidation\\] reached waypoint (\\d+)/(\\d+) at (.+)$")

func _compile_regex(regex: RegEx, pattern: String) -> bool:
	var result: Error = regex.compile(pattern)
	if result != OK:
		_fail("Failed to compile regex: %s" % pattern)
		return false
	return true

func _build_summary(log_text: String, log_path: String) -> Dictionary:
	var summary: Dictionary = {
		"log_path": log_path,
		"log_file_name": log_path.get_file(),
		"line_count": 0,
		"error_count": 0,
		"warning_count": 0,
		"errors": [],
		"warnings": [],
		"world_perf_line_count": 0,
		"codex_validation_line_count": 0,
		"boot_metrics_ms": {},
		"frame_time_summary": {},
		"world_prepass_phase_ms": {},
		"world_prepass_subphase_ms": {},
		"boot_detail_lines": [],
		"frame_budget_lines": [],
		"observability_lines": [],
		"route_preset": "",
		"route_waypoints": 0,
		"waypoints_reached": 0,
		"route_started": false,
		"route_completed": false,
		"drain_completed": false,
		"validation_failed": false,
		"catch_up_timeout": false,
		"latest_catch_up_status": "",
		"latest_world_perf_lines": [],
		"latest_codex_validation_lines": [],
	}
	var lines: PackedStringArray = log_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	summary["line_count"] = lines.size()
	for line: String in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty():
			continue
		_parse_error_and_warning_lines(summary, trimmed)
		if trimmed.begins_with("[WorldPerf]"):
			summary["world_perf_line_count"] = int(summary.get("world_perf_line_count", 0)) + 1
			_capture_latest_line(summary, "latest_world_perf_lines", trimmed)
			_parse_world_perf_line(summary, trimmed)
		elif trimmed.begins_with("[CodexValidation]"):
			summary["codex_validation_line_count"] = int(summary.get("codex_validation_line_count", 0)) + 1
			_capture_latest_line(summary, "latest_codex_validation_lines", trimmed)
			_parse_codex_validation_line(summary, trimmed)
	return summary

func _parse_error_and_warning_lines(summary: Dictionary, line: String) -> void:
	if line.contains("ERROR"):
		summary["error_count"] = int(summary.get("error_count", 0)) + 1
		_capture_latest_line(summary, "errors", line)
	if line.contains("WARNING"):
		summary["warning_count"] = int(summary.get("warning_count", 0)) + 1
		_capture_latest_line(summary, "warnings", line)

func _parse_world_perf_line(summary: Dictionary, line: String) -> void:
	var startup_match: RegExMatch = _startup_metric_regex.search(line)
	if startup_match != null:
		var boot_metrics: Dictionary = summary.get("boot_metrics_ms", {}) as Dictionary
		boot_metrics[startup_match.get_string(1)] = startup_match.get_string(2).to_float()
		summary["boot_metrics_ms"] = boot_metrics
		return
	var frame_time_match: RegExMatch = _frame_time_regex.search(line)
	if frame_time_match != null:
		summary["frame_time_summary"] = {
			"avg_ms": frame_time_match.get_string(1).to_float(),
			"p99_ms": frame_time_match.get_string(2).to_float(),
			"hitches": frame_time_match.get_string(3).to_int(),
		}
		return
	var timing_match: RegExMatch = _world_perf_timing_regex.search(line)
	if timing_match != null:
		_capture_world_prepass_timing(
			summary,
			timing_match.get_string(1),
			timing_match.get_string(2).to_float()
		)
	if line.begins_with("[WorldPerf] Boot detail:"):
		_capture_latest_line(summary, "boot_detail_lines", line)
		return
	if line.begins_with("[WorldPerf] Frame budget:"):
		_capture_latest_line(summary, "frame_budget_lines", line)
		return
	if line.begins_with("[WorldPerf] Observability:"):
		_capture_latest_line(summary, "observability_lines", line)

func _parse_codex_validation_line(summary: Dictionary, line: String) -> void:
	var prepared_match: RegExMatch = _route_prepared_regex.search(line)
	if prepared_match != null:
		summary["route_preset"] = prepared_match.get_string(1)
		summary["route_waypoints"] = prepared_match.get_string(2).to_int()
		return
	var start_match: RegExMatch = _route_start_regex.search(line)
	if start_match != null:
		summary["route_started"] = true
		summary["route_preset"] = start_match.get_string(1)
		summary["route_waypoints"] = start_match.get_string(2).to_int()
		return
	var waypoint_match: RegExMatch = _reached_waypoint_regex.search(line)
	if waypoint_match != null:
		summary["waypoints_reached"] = waypoint_match.get_string(1).to_int()
		summary["route_waypoints"] = waypoint_match.get_string(2).to_int()
		return
	var complete_match: RegExMatch = _route_complete_regex.search(line)
	if complete_match != null:
		summary["route_completed"] = true
		summary["route_preset"] = complete_match.get_string(1)
		summary["waypoints_reached"] = complete_match.get_string(2).to_int()
		summary["route_waypoints"] = complete_match.get_string(3).to_int()
		return
	var drain_match: RegExMatch = _route_drain_regex.search(line)
	if drain_match != null:
		summary["drain_completed"] = true
		summary["route_preset"] = drain_match.get_string(1)
		summary["waypoints_reached"] = drain_match.get_string(2).to_int()
		summary["route_waypoints"] = drain_match.get_string(3).to_int()
		return
	if line.contains("validation failed:"):
		summary["validation_failed"] = true
	if line.contains("world catch-up timeout"):
		summary["catch_up_timeout"] = true
	if line.begins_with("[CodexValidation] catch-up status:"):
		summary["latest_catch_up_status"] = line

func _capture_latest_line(summary: Dictionary, key: String, line: String) -> void:
	var lines: Array = summary.get(key, []) as Array
	lines.append(line)
	while lines.size() > MAX_CAPTURED_LINES:
		lines.remove_at(0)
	summary[key] = lines

func _capture_world_prepass_timing(summary: Dictionary, label: String, elapsed_ms: float) -> void:
	if not label.begins_with("WorldPrePass.compute."):
		return
	var suffix: String = label.trim_prefix("WorldPrePass.compute.")
	var key: String = "world_prepass_subphase_ms" if suffix.contains(".") else "world_prepass_phase_ms"
	var timings: Dictionary = summary.get(key, {}) as Dictionary
	timings[label] = elapsed_ms
	summary[key] = timings

func _write_summary_artifacts(summary: Dictionary, log_path: String) -> Dictionary:
	var output_dir: String = _resolve_output_dir()
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_fail("Failed to create output directory: %s" % output_dir)
		return {}
	var output_prefix: String = _get_user_arg_value(OUTPUT_PREFIX_ARG_PREFIX)
	if output_prefix.is_empty():
		output_prefix = log_path.get_file().get_basename()
	var json_path: String = output_dir.path_join("%s_summary.json" % output_prefix)
	var md_path: String = output_dir.path_join("%s_summary.md" % output_prefix)
	_write_text(json_path, JSON.stringify(summary, "\t"))
	_write_text(md_path, _build_markdown_summary(summary))
	return {
		"json_path": json_path,
		"md_path": md_path,
	}

func _build_markdown_summary(summary: Dictionary) -> String:
	var lines: Array[String] = [
		"# Perf Log Summary",
		"",
		"- Log: `%s`" % summary.get("log_path", ""),
		"- Lines: `%d`" % int(summary.get("line_count", 0)),
		"- Errors: `%d`" % int(summary.get("error_count", 0)),
		"- Warnings: `%d`" % int(summary.get("warning_count", 0)),
	]
	var boot_metrics: Dictionary = summary.get("boot_metrics_ms", {}) as Dictionary
	if not boot_metrics.is_empty():
		lines.append("")
		lines.append("## Boot metrics")
		var metric_names: Array[String] = []
		for metric_name: Variant in boot_metrics.keys():
			metric_names.append(String(metric_name))
		metric_names.sort()
		for metric_name: String in metric_names:
			lines.append("- `%s`: `%.2f ms`" % [metric_name, float(boot_metrics.get(metric_name, 0.0))])
	var frame_time: Dictionary = summary.get("frame_time_summary", {}) as Dictionary
	if not frame_time.is_empty():
		lines.append("")
		lines.append("## Frame summary")
		lines.append("- Avg: `%.2f ms`" % float(frame_time.get("avg_ms", 0.0)))
		lines.append("- P99: `%.2f ms`" % float(frame_time.get("p99_ms", 0.0)))
		lines.append("- Hitches: `%d`" % int(frame_time.get("hitches", 0)))
	if bool(summary.get("route_started", false)) or int(summary.get("route_waypoints", 0)) > 0:
		lines.append("")
		lines.append("## Runtime validation")
		lines.append("- Route preset: `%s`" % summary.get("route_preset", ""))
		lines.append("- Waypoints reached: `%d/%d`" % [
			int(summary.get("waypoints_reached", 0)),
			int(summary.get("route_waypoints", 0)),
		])
		lines.append("- Route started: `%s`" % _bool_to_status(bool(summary.get("route_started", false))))
		lines.append("- Route completed: `%s`" % _bool_to_status(bool(summary.get("route_completed", false))))
		lines.append("- Drain completed: `%s`" % _bool_to_status(bool(summary.get("drain_completed", false))))
		lines.append("- Validation failed: `%s`" % _bool_to_status(bool(summary.get("validation_failed", false))))
		lines.append("- Catch-up timeout: `%s`" % _bool_to_status(bool(summary.get("catch_up_timeout", false))))
		var latest_catch_up_status: String = String(summary.get("latest_catch_up_status", ""))
		if not latest_catch_up_status.is_empty():
			lines.append("- Latest catch-up status: `%s`" % latest_catch_up_status)
	_append_sorted_timing_section(lines, "WorldPrePass phases", summary.get("world_prepass_phase_ms", {}) as Dictionary, 12)
	_append_sorted_timing_section(lines, "WorldPrePass subphases", summary.get("world_prepass_subphase_ms", {}) as Dictionary, 16)
	_append_line_section(lines, "Recent errors", summary.get("errors", []) as Array)
	_append_line_section(lines, "Recent warnings", summary.get("warnings", []) as Array)
	_append_line_section(lines, "Recent WorldPerf lines", summary.get("latest_world_perf_lines", []) as Array)
	_append_line_section(lines, "Recent CodexValidation lines", summary.get("latest_codex_validation_lines", []) as Array)
	return "\n".join(lines) + "\n"

func _append_line_section(lines: Array[String], title: String, raw_items: Array) -> void:
	if raw_items.is_empty():
		return
	lines.append("")
	lines.append("## %s" % title)
	for item: Variant in raw_items:
		lines.append("- `%s`" % String(item))

func _append_sorted_timing_section(lines: Array[String], title: String, timings: Dictionary, limit: int) -> void:
	if timings.is_empty():
		return
	var keys: Array[String] = []
	for key: Variant in timings.keys():
		keys.append(String(key))
	keys.sort_custom(func(a: String, b: String) -> bool:
		var a_value: float = float(timings.get(a, 0.0))
		var b_value: float = float(timings.get(b, 0.0))
		if absf(a_value - b_value) > 0.001:
			return a_value > b_value
		return a < b
	)
	lines.append("")
	lines.append("## %s" % title)
	var emitted: int = 0
	for key: String in keys:
		lines.append("- `%s`: `%.2f ms`" % [key, float(timings.get(key, 0.0))])
		emitted += 1
		if emitted >= limit:
			break

func _bool_to_status(value: bool) -> String:
	return "yes" if value else "no"

func _resolve_output_dir() -> String:
	var output_dir_arg: String = _get_user_arg_value(OUTPUT_DIR_ARG_PREFIX)
	if not output_dir_arg.is_empty():
		return _resolve_input_path(output_dir_arg)
	return ProjectSettings.globalize_path(DEFAULT_OUTPUT_DIR)

func _resolve_input_path(path_value: String) -> String:
	var normalized: String = path_value.replace("\\", "/").strip_edges()
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return ProjectSettings.globalize_path(normalized)
	if _looks_like_absolute_path(normalized):
		return normalized
	if normalized.begins_with("./"):
		normalized = normalized.trim_prefix("./")
	return ProjectSettings.globalize_path("res://").path_join(normalized)

func _looks_like_absolute_path(path_value: String) -> bool:
	return path_value.begins_with("/") or (path_value.length() >= 3 and path_value[1] == ":" and path_value[2] == "/")

func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Failed to open output file for write: %s" % path)
		return
	file.store_string(text)
	file.close()

func _get_user_arg_value(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""

func _fail(message: String) -> void:
	push_error(message)
	print("[PerfLogSummary] %s" % message)
	quit(1)
