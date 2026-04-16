extends SceneTree

const BASELINE_ARG_PREFIX: String = "codex_perf_baseline="
const CANDIDATE_ARG_PREFIX: String = "codex_perf_candidate="
const OUTPUT_DIR_ARG_PREFIX: String = "codex_perf_output_dir="
const OUTPUT_PREFIX_ARG_PREFIX: String = "codex_perf_output_prefix="
const DEFAULT_OUTPUT_DIR: String = "res://debug_exports/perf"
const REGRESSION_FAIL_THRESHOLD_PCT: float = 20.0
const IMPROVEMENT_PROGRESS_THRESHOLD_PCT: float = 10.0
const MAX_LISTED_ITEMS: int = 16

const EXACT_METRIC_SPECS: Array[Dictionary] = [
	{"path": "frame_summary.latest_frame_ms", "direction": "lower_is_better"},
	{"path": "frame_summary.hitch_count", "direction": "lower_is_better"},
	{"path": "frame_summary.latest_debug_snapshot.fps", "direction": "higher_is_better"},
	{"path": "frame_summary.latest_debug_snapshot.frame_time_ms", "direction": "lower_is_better"},
	{"path": "frame_summary.latest_debug_snapshot.world_update_ms", "direction": "lower_is_better"},
	{"path": "frame_summary.latest_debug_snapshot.chunk_generation_ms", "direction": "lower_is_better"},
	{"path": "frame_summary.latest_debug_snapshot.visual_build_ms", "direction": "lower_is_better"},
	{"path": "frame_summary.latest_debug_snapshot.dispatcher_ms", "direction": "lower_is_better"},
]

const MAP_METRIC_SPECS: Array[Dictionary] = [
	{"path": "boot.observations", "direction": "lower_is_better"},
	{"path": "frame_summary.category_peaks", "direction": "lower_is_better"},
	{"path": "native_profiling.chunk_generator.phase_avg_ms", "direction": "lower_is_better"},
	{"path": "native_profiling.chunk_generator.phase_peak_ms", "direction": "lower_is_better"},
	{"path": "native_profiling.topology_builder.phase_avg_ms", "direction": "lower_is_better"},
	{"path": "native_profiling.topology_builder.phase_peak_ms", "direction": "lower_is_better"},
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var baseline_arg: String = _get_user_arg_value(BASELINE_ARG_PREFIX)
	var candidate_arg: String = _get_user_arg_value(CANDIDATE_ARG_PREFIX)
	if baseline_arg.is_empty() or candidate_arg.is_empty():
		_fail(
			"Missing required user args `%s<path>` and `%s<path>`"
			% [BASELINE_ARG_PREFIX, CANDIDATE_ARG_PREFIX]
		)
		return
	var baseline_path: String = _resolve_path(baseline_arg)
	var candidate_path: String = _resolve_path(candidate_arg)
	var baseline_artifact: Dictionary = _read_json_dictionary(baseline_path)
	var candidate_artifact: Dictionary = _read_json_dictionary(candidate_path)
	if baseline_artifact.is_empty() or candidate_artifact.is_empty():
		return
	var summary: Dictionary = _build_summary(
		baseline_artifact,
		candidate_artifact,
		baseline_path,
		candidate_path
	)
	var output_paths: Dictionary = _write_summary_artifacts(summary, baseline_path, candidate_path)
	print("[PerfBaselineDiff] summary written: json=%s md=%s" % [
		output_paths.get("json_path", ""),
		output_paths.get("md_path", ""),
	])
	print("[PerfBaselineDiff] status=%s compared=%d regressions=%d improvements=%d contract_violations=%d" % [
		String(summary.get("overall_status", "unknown")),
		int(summary.get("compared_metric_count", 0)),
		int(summary.get("regression_count", 0)),
		int(summary.get("improvement_count", 0)),
		int((summary.get("contract_violations", {}) as Dictionary).get("candidate_count", 0)),
	])
	if String(summary.get("overall_status", "unknown")) == "fail":
		quit(2)
		return
	quit(0)

func _build_summary(
	baseline_artifact: Dictionary,
	candidate_artifact: Dictionary,
	baseline_path: String,
	candidate_path: String
) -> Dictionary:
	var contract_summary: Dictionary = _build_contract_violation_summary(
		baseline_artifact,
		candidate_artifact
	)
	var missing_metrics: Array[String] = []
	var metric_diffs: Array[Dictionary] = []
	for metric_spec: Dictionary in EXACT_METRIC_SPECS:
		_append_exact_metric_diff(metric_diffs, missing_metrics, baseline_artifact, candidate_artifact, metric_spec)
	for metric_spec: Dictionary in MAP_METRIC_SPECS:
		_append_map_metric_diffs(metric_diffs, missing_metrics, baseline_artifact, candidate_artifact, metric_spec)
	metric_diffs.sort_custom(_sort_metric_diffs)
	var regressions: Array[Dictionary] = []
	var improvements: Array[Dictionary] = []
	var stable_metrics: Array[Dictionary] = []
	for metric_diff: Dictionary in metric_diffs:
		match String(metric_diff.get("classification", "stable")):
			"fail":
				regressions.append(metric_diff)
			"progress":
				improvements.append(metric_diff)
			_:
				stable_metrics.append(metric_diff)
	var overall_status: String = "stable"
	if bool(contract_summary.get("candidate_has_failure", false)) or not regressions.is_empty():
		overall_status = "fail"
	elif not improvements.is_empty():
		overall_status = "progress"
	return {
		"baseline_path": baseline_path,
		"candidate_path": candidate_path,
		"generated_at": Time.get_datetime_string_from_system(false, true),
		"overall_status": overall_status,
		"thresholds": {
			"regression_fail_pct": REGRESSION_FAIL_THRESHOLD_PCT,
			"improvement_progress_pct": IMPROVEMENT_PROGRESS_THRESHOLD_PCT,
			"contract_violations_fail": true,
		},
		"contract_violations": contract_summary,
		"compared_metric_count": metric_diffs.size(),
		"regression_count": regressions.size(),
		"improvement_count": improvements.size(),
		"missing_metric_paths": missing_metrics,
		"regressions": regressions.slice(0, min(MAX_LISTED_ITEMS, regressions.size())),
		"improvements": improvements.slice(0, min(MAX_LISTED_ITEMS, improvements.size())),
		"stable_metrics": stable_metrics.slice(0, min(MAX_LISTED_ITEMS, stable_metrics.size())),
	}

func _build_contract_violation_summary(
	baseline_artifact: Dictionary,
	candidate_artifact: Dictionary
) -> Dictionary:
	var baseline_violations: Array = _get_dictionary_array(baseline_artifact.get("contract_violations", []))
	var candidate_violations: Array = _get_dictionary_array(candidate_artifact.get("contract_violations", []))
	var baseline_by_key: Dictionary = _index_contract_violations(baseline_violations)
	var candidate_by_key: Dictionary = _index_contract_violations(candidate_violations)
	var new_keys: Array[String] = []
	var resolved_keys: Array[String] = []
	var carried_keys: Array[String] = []
	for violation_key: Variant in candidate_by_key.keys():
		var key_string: String = String(violation_key)
		if baseline_by_key.has(key_string):
			carried_keys.append(key_string)
		else:
			new_keys.append(key_string)
	for violation_key: Variant in baseline_by_key.keys():
		var key_string: String = String(violation_key)
		if not candidate_by_key.has(key_string):
			resolved_keys.append(key_string)
	new_keys.sort()
	resolved_keys.sort()
	carried_keys.sort()
	var details: Array[Dictionary] = []
	for candidate_record: Dictionary in candidate_violations:
		var violation_key: String = _build_contract_violation_key(candidate_record)
		var detail: Dictionary = {
			"key": violation_key,
			"type": String(candidate_record.get("type", "")),
			"category": String(candidate_record.get("category", "")),
			"job_id": String(candidate_record.get("job_id", "")),
			"candidate_used_ms": _variant_to_float(candidate_record.get("used_ms", 0.0)),
			"candidate_budget_ms": _variant_to_float(candidate_record.get("budget_ms", 0.0)),
			"candidate_over_budget_pct": _variant_to_float(candidate_record.get("over_budget_pct", 0.0)),
		}
		if baseline_by_key.has(violation_key):
			var baseline_record: Dictionary = baseline_by_key.get(violation_key, {}) as Dictionary
			detail["baseline_used_ms"] = _variant_to_float(baseline_record.get("used_ms", 0.0))
			detail["baseline_over_budget_pct"] = _variant_to_float(baseline_record.get("over_budget_pct", 0.0))
		details.append(detail)
	return {
		"baseline_count": baseline_violations.size(),
		"candidate_count": candidate_violations.size(),
		"candidate_has_failure": not candidate_violations.is_empty(),
		"new_keys": new_keys,
		"resolved_keys": resolved_keys,
		"carried_keys": carried_keys,
		"details": details,
	}

func _append_exact_metric_diff(
	metric_diffs: Array[Dictionary],
	missing_metrics: Array[String],
	baseline_artifact: Dictionary,
	candidate_artifact: Dictionary,
	metric_spec: Dictionary
) -> void:
	var path: String = String(metric_spec.get("path", ""))
	var baseline_value: Variant = _get_nested_value(baseline_artifact, path)
	var candidate_value: Variant = _get_nested_value(candidate_artifact, path)
	if not _is_numeric_variant(baseline_value) or not _is_numeric_variant(candidate_value):
		missing_metrics.append(path)
		return
	metric_diffs.append(
		_build_metric_diff(
			path,
			_variant_to_float(baseline_value),
			_variant_to_float(candidate_value),
			String(metric_spec.get("direction", "lower_is_better"))
		)
	)

func _append_map_metric_diffs(
	metric_diffs: Array[Dictionary],
	missing_metrics: Array[String],
	baseline_artifact: Dictionary,
	candidate_artifact: Dictionary,
	metric_spec: Dictionary
) -> void:
	var root_path: String = String(metric_spec.get("path", ""))
	var baseline_map: Dictionary = _get_nested_dictionary(baseline_artifact, root_path)
	var candidate_map: Dictionary = _get_nested_dictionary(candidate_artifact, root_path)
	if baseline_map.is_empty() or candidate_map.is_empty():
		missing_metrics.append(root_path)
		return
	var shared_keys: Array[String] = []
	for map_key: Variant in baseline_map.keys():
		var key_string: String = String(map_key)
		if candidate_map.has(key_string) and _is_numeric_variant(baseline_map.get(key_string)) and _is_numeric_variant(candidate_map.get(key_string)):
			shared_keys.append(key_string)
	shared_keys.sort()
	for key_string: String in shared_keys:
		metric_diffs.append(
			_build_metric_diff(
				"%s.%s" % [root_path, key_string],
				_variant_to_float(baseline_map.get(key_string, 0.0)),
				_variant_to_float(candidate_map.get(key_string, 0.0)),
				String(metric_spec.get("direction", "lower_is_better"))
			)
		)

func _build_metric_diff(
	path: String,
	baseline_value: float,
	candidate_value: float,
	direction: String
) -> Dictionary:
	var delta_abs: float = candidate_value - baseline_value
	var delta_pct: float = _calculate_delta_pct(baseline_value, candidate_value)
	var worse_delta_pct: float = delta_pct if direction == "lower_is_better" else -delta_pct
	var better_delta_pct: float = -delta_pct if direction == "lower_is_better" else delta_pct
	var classification: String = "stable"
	if worse_delta_pct >= REGRESSION_FAIL_THRESHOLD_PCT:
		classification = "fail"
	elif better_delta_pct >= IMPROVEMENT_PROGRESS_THRESHOLD_PCT:
		classification = "progress"
	return {
		"path": path,
		"direction": direction,
		"baseline": baseline_value,
		"candidate": candidate_value,
		"delta_abs": delta_abs,
		"delta_pct": delta_pct,
		"classification": classification,
	}

func _calculate_delta_pct(baseline_value: float, candidate_value: float) -> float:
	if is_zero_approx(baseline_value):
		if is_zero_approx(candidate_value):
			return 0.0
		return 100.0 if candidate_value > 0.0 else -100.0
	return ((candidate_value - baseline_value) / absf(baseline_value)) * 100.0

func _index_contract_violations(violations: Array) -> Dictionary:
	var indexed: Dictionary = {}
	for violation: Variant in violations:
		if typeof(violation) != TYPE_DICTIONARY:
			continue
		var violation_dict: Dictionary = violation as Dictionary
		indexed[_build_contract_violation_key(violation_dict)] = violation_dict
	return indexed

func _build_contract_violation_key(record: Dictionary) -> String:
	return "%s|%s|%s" % [
		String(record.get("type", "")),
		String(record.get("category", "")),
		String(record.get("job_id", "")),
	]

func _get_dictionary_array(raw_value: Variant) -> Array:
	if typeof(raw_value) != TYPE_ARRAY:
		return []
	var dictionaries: Array = []
	for item: Variant in raw_value as Array:
		if typeof(item) == TYPE_DICTIONARY:
			dictionaries.append(item)
	return dictionaries

func _get_nested_value(root: Dictionary, dotted_path: String) -> Variant:
	var current: Variant = root
	for path_part: String in dotted_path.split("."):
		if typeof(current) != TYPE_DICTIONARY:
			return null
		var current_dict: Dictionary = current as Dictionary
		if not current_dict.has(path_part):
			return null
		current = current_dict.get(path_part)
	return current

func _get_nested_dictionary(root: Dictionary, dotted_path: String) -> Dictionary:
	var value: Variant = _get_nested_value(root, dotted_path)
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}

func _sort_metric_diffs(left: Dictionary, right: Dictionary) -> bool:
	var left_delta: float = absf(_variant_to_float(left.get("delta_pct", 0.0)))
	var right_delta: float = absf(_variant_to_float(right.get("delta_pct", 0.0)))
	if absf(left_delta - right_delta) > 0.001:
		return left_delta > right_delta
	return String(left.get("path", "")) < String(right.get("path", ""))

func _write_summary_artifacts(
	summary: Dictionary,
	baseline_path: String,
	candidate_path: String
) -> Dictionary:
	var output_dir: String = _resolve_output_dir()
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_fail("Failed to create output directory: %s" % output_dir)
		return {}
	var output_prefix: String = _get_user_arg_value(OUTPUT_PREFIX_ARG_PREFIX)
	if output_prefix.is_empty():
		output_prefix = "%s_vs_%s" % [
			candidate_path.get_file().get_basename(),
			baseline_path.get_file().get_basename(),
		]
	var json_path: String = output_dir.path_join("%s_diff_summary.json" % output_prefix)
	var md_path: String = output_dir.path_join("%s_diff_summary.md" % output_prefix)
	_write_text(json_path, JSON.stringify(summary, "\t"))
	_write_text(md_path, _build_markdown_summary(summary))
	return {
		"json_path": json_path,
		"md_path": md_path,
	}

func _build_markdown_summary(summary: Dictionary) -> String:
	var lines: Array[String] = [
		"# Perf Baseline Diff",
		"",
		"- Baseline: `%s`" % String(summary.get("baseline_path", "")),
		"- Candidate: `%s`" % String(summary.get("candidate_path", "")),
		"- Status: `%s`" % String(summary.get("overall_status", "unknown")),
		"- Compared metrics: `%d`" % int(summary.get("compared_metric_count", 0)),
	]
	var thresholds: Dictionary = summary.get("thresholds", {}) as Dictionary
	if not thresholds.is_empty():
		lines.append("- Regression fail threshold: `%.1f%%`" % _variant_to_float(thresholds.get("regression_fail_pct", 0.0)))
		lines.append("- Improvement progress threshold: `%.1f%%`" % _variant_to_float(thresholds.get("improvement_progress_pct", 0.0)))
	var contract_summary: Dictionary = summary.get("contract_violations", {}) as Dictionary
	lines.append("")
	lines.append("## Contract violations")
	lines.append("- Baseline count: `%d`" % int(contract_summary.get("baseline_count", 0)))
	lines.append("- Candidate count: `%d`" % int(contract_summary.get("candidate_count", 0)))
	lines.append("- Candidate fails heuristic: `%s`" % _bool_to_status(bool(contract_summary.get("candidate_has_failure", false))))
	_append_string_list(lines, "New violations", contract_summary.get("new_keys", []) as Array)
	_append_string_list(lines, "Resolved violations", contract_summary.get("resolved_keys", []) as Array)
	_append_metric_section(lines, "Regressions", summary.get("regressions", []) as Array)
	_append_metric_section(lines, "Improvements", summary.get("improvements", []) as Array)
	_append_metric_section(lines, "Stable sample", summary.get("stable_metrics", []) as Array)
	_append_string_list(lines, "Missing metric paths", summary.get("missing_metric_paths", []) as Array)
	return "\n".join(lines) + "\n"

func _append_metric_section(lines: Array[String], title: String, raw_items: Array) -> void:
	if raw_items.is_empty():
		return
	lines.append("")
	lines.append("## %s" % title)
	for item: Variant in raw_items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var metric: Dictionary = item as Dictionary
		lines.append(
			"- `%s`: baseline=`%.4f`, candidate=`%.4f`, delta=`%.1f%%`, rule=`%s`"
			% [
				String(metric.get("path", "")),
				_variant_to_float(metric.get("baseline", 0.0)),
				_variant_to_float(metric.get("candidate", 0.0)),
				_variant_to_float(metric.get("delta_pct", 0.0)),
				String(metric.get("direction", "")),
			]
		)

func _append_string_list(lines: Array[String], title: String, raw_items: Array) -> void:
	if raw_items.is_empty():
		return
	lines.append("")
	lines.append("## %s" % title)
	for item: Variant in raw_items:
		lines.append("- `%s`" % String(item))

func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("JSON artifact not found: %s" % path)
		return {}
	var raw_text: String = FileAccess.get_file_as_string(path)
	if raw_text.is_empty():
		_fail("JSON artifact is empty: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("JSON artifact must parse to Dictionary: %s" % path)
		return {}
	return parsed as Dictionary

func _resolve_output_dir() -> String:
	var output_dir_arg: String = _get_user_arg_value(OUTPUT_DIR_ARG_PREFIX)
	if not output_dir_arg.is_empty():
		return _resolve_path(output_dir_arg)
	return ProjectSettings.globalize_path(DEFAULT_OUTPUT_DIR)

func _resolve_path(path_value: String) -> String:
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

func _get_user_arg_value(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""

func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Failed to open output file for write: %s" % path)
		return
	file.store_string(text)
	file.close()

func _is_numeric_variant(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func _variant_to_float(value: Variant) -> float:
	return float(value) if _is_numeric_variant(value) else 0.0

func _bool_to_status(value: bool) -> String:
	return "yes" if value else "no"

func _fail(message: String) -> void:
	push_error(message)
	print("[PerfBaselineDiff] %s" % message)
	quit(1)
