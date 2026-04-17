class_name PerfTelemetryCollector
extends Node

## Debug-only collector for explicit perf runs.
## It assembles one self-contained JSON artifact from existing owner-fed data.

const WorldPerfProbe = preload("res://core/systems/world/world_perf_probe.gd")

const ENABLE_ARG: String = "codex_perf_test"
const VALIDATE_ARG: String = "codex_validate_runtime"
const OUTPUT_ARG_PREFIX: String = "codex_perf_output="
const QUIT_ON_COMPLETE_ARG: String = "codex_quit_on_perf_complete"
const DEFAULT_OUTPUT_PATH: String = "res://debug_exports/perf/result.json"
const TIMELINE_LIMIT: int = 128
const DEBUG_QUEUE_ROWS: int = 24

const _BOOT_STATE_LABELS := {
	0: "queued_compute",
	1: "computed",
	2: "queued_apply",
	3: "applied",
	4: "visual_complete",
}

static var _active_instance: PerfTelemetryCollector = null

var _game_world: GameWorld = null
var _chunk_manager: ChunkManager = null
var _validation_driver: Node = null
var _stress_driver: Node = null
var _artifact_written: bool = false
var _ready_to_finalize_frame: int = -1
var _validation_completion_summary: Dictionary = {}
var _stress_completion_summary: Dictionary = {}
var _chunk_generator_profiles: Array[Dictionary] = []
var _topology_builder_profiles: Array[Dictionary] = []
var _output_path: String = DEFAULT_OUTPUT_PATH

signal artifact_written(output_path: String, exit_code: int)

static func is_enabled_for_current_run() -> bool:
	return ENABLE_ARG in OS.get_cmdline_user_args()

static func get_active() -> PerfTelemetryCollector:
	return _active_instance

func _enter_tree() -> void:
	if is_enabled_for_current_run():
		_active_instance = self

func _exit_tree() -> void:
	if _active_instance == self:
		_active_instance = null

func _ready() -> void:
	if not is_enabled_for_current_run():
		set_process(false)
		queue_free()
		return

func setup(
	game_world: GameWorld,
	chunk_manager: ChunkManager,
	validation_driver: Node = null,
	stress_driver: Node = null
) -> void:
	_game_world = game_world
	_chunk_manager = chunk_manager
	_validation_driver = validation_driver
	_stress_driver = stress_driver
	_output_path = _resolve_output_path()
	if _validation_driver != null and not _validation_driver.validation_run_completed.is_connected(_on_validation_run_completed):
		_validation_driver.validation_run_completed.connect(_on_validation_run_completed)
	if _stress_driver != null and _stress_driver.has_signal("stress_run_completed") and not _stress_driver.stress_run_completed.is_connected(_on_stress_run_completed):
		_stress_driver.stress_run_completed.connect(_on_stress_run_completed)
	if _stress_is_requested() and _stress_driver == null:
		_stress_completion_summary = {
			"mode": _resolve_requested_stress_mode(),
			"state": "failed",
			"message": "stress driver was requested but not initialized",
			"exit_code": 1,
		}

func record_chunk_generator_profile(profile: Dictionary, context: Dictionary = {}) -> void:
	if not is_enabled_for_current_run() or profile.is_empty():
		return
	_chunk_generator_profiles.append(_merge_profile_with_context(profile, context))

func record_topology_builder_profile(profile: Dictionary, context: Dictionary = {}) -> void:
	if not is_enabled_for_current_run() or profile.is_empty():
		return
	_topology_builder_profiles.append(_merge_profile_with_context(profile, context))

func _process(_delta: float) -> void:
	if _artifact_written or _game_world == null or _chunk_manager == null:
		return
	if _is_completion_gate_reached() and _ready_to_finalize_frame < 0:
		_ready_to_finalize_frame = Engine.get_process_frames()
	if _ready_to_finalize_frame < 0:
		return
	if _validation_is_requested() and _validation_completion_summary.is_empty():
		return
	if _stress_is_requested() and _stress_completion_summary.is_empty():
		return
	if Engine.get_process_frames() <= _ready_to_finalize_frame:
		return
	_finalize_and_optionally_quit(_resolve_exit_code())

func _is_completion_gate_reached() -> bool:
	if _validation_is_requested() or _stress_is_requested():
		return _game_world.is_boot_complete()
	return _game_world.is_boot_complete() or _chunk_manager.is_boot_first_playable()

func _on_validation_run_completed(summary: Dictionary) -> void:
	_validation_completion_summary = summary.duplicate(true)

func _on_stress_run_completed(summary: Dictionary) -> void:
	_stress_completion_summary = summary.duplicate(true)

func _validation_is_requested() -> bool:
	return VALIDATE_ARG in OS.get_cmdline_user_args()

func _stress_is_requested() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("codex_stress_mode="):
			return true
	return false

func _resolve_requested_stress_mode() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("codex_stress_mode="):
			return arg.trim_prefix("codex_stress_mode=").strip_edges()
	return ""

func _resolve_exit_code() -> int:
	return maxi(
		int(_validation_completion_summary.get("exit_code", 0)),
		int(_stress_completion_summary.get("exit_code", 0))
	)

func _should_quit_on_complete() -> bool:
	return QUIT_ON_COMPLETE_ARG in OS.get_cmdline_user_args()

func _resolve_output_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(OUTPUT_ARG_PREFIX):
			continue
		var raw_path: String = arg.trim_prefix(OUTPUT_ARG_PREFIX).strip_edges()
		if raw_path.is_empty():
			continue
		if raw_path.begins_with("res://") or raw_path.begins_with("user://") or _is_absolute_windows_path(raw_path):
			return raw_path
		return "res://%s" % raw_path.trim_prefix("./").trim_prefix("/")
	return DEFAULT_OUTPUT_PATH

func _is_absolute_windows_path(path: String) -> bool:
	return path.length() > 2 and path[1] == ":" and (path[2] == "/" or path[2] == "\\")

func _to_absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path

func _merge_profile_with_context(profile: Dictionary, context: Dictionary) -> Dictionary:
	var merged: Dictionary = profile.duplicate(true)
	for key_variant: Variant in context.keys():
		merged[key_variant] = context[key_variant]
	return merged

func _finalize_and_optionally_quit(exit_code: int) -> void:
	_pull_native_topology_profile()
	if _topology_builder_profiles.is_empty():
		_build_topology_profile_from_loaded_chunks()
	var artifact: Dictionary = _build_artifact()
	var write_ok: bool = _write_artifact(artifact)
	_artifact_written = true
	var final_exit_code: int = exit_code if write_ok else 1
	artifact_written.emit(_output_path, final_exit_code)
	if _should_quit_on_complete():
		get_tree().quit(final_exit_code)

func _pull_native_topology_profile() -> void:
	if not ClassDB.class_exists(&"MountainTopologyBuilder"):
		return
	var builder: Object = ClassDB.instantiate(&"MountainTopologyBuilder")
	if builder == null or not builder.has_method("get_last_profile"):
		return
	var profile: Dictionary = builder.call("get_last_profile") as Dictionary
	if profile.is_empty():
		return
	record_topology_builder_profile(profile, {"source": "native_last_profile"})

func _build_topology_profile_from_loaded_chunks() -> void:
	if _chunk_manager == null or not _chunk_manager.has_method("get_loaded_chunks"):
		return
	if not ClassDB.class_exists(&"MountainTopologyBuilder"):
		return
	var builder: Object = ClassDB.instantiate(&"MountainTopologyBuilder")
	if builder == null or not builder.has_method("rebuild_topology"):
		return
	var loaded_chunks: Dictionary = _chunk_manager.get_loaded_chunks()
	var chunk_terrain_by_coord: Dictionary = {}
	var chunk_size: int = 0
	for coord_variant: Variant in loaded_chunks.keys():
		var chunk: Chunk = loaded_chunks.get(coord_variant) as Chunk
		if chunk == null:
			continue
		if chunk_size <= 0:
			chunk_size = chunk.get_chunk_size()
		chunk_terrain_by_coord[coord_variant] = chunk.get_terrain_bytes()
	if chunk_terrain_by_coord.is_empty() or chunk_size <= 0:
		return
	var rebuild_result: Dictionary = builder.call("rebuild_topology", chunk_terrain_by_coord, chunk_size) as Dictionary
	var profile: Dictionary = rebuild_result.get("_prof_topology_builder", {}) as Dictionary
	if profile.is_empty() and builder.has_method("get_last_profile"):
		profile = builder.call("get_last_profile") as Dictionary
	if profile.is_empty():
		return
	record_topology_builder_profile(profile, {
		"source": "loaded_chunk_rebuild_fallback",
		"loaded_chunk_count": chunk_terrain_by_coord.size(),
	})

func _build_artifact() -> Dictionary:
	var world_perf_monitor: Node = get_node_or_null("/root/WorldPerfMonitor")
	var world_runtime_diag: Node = get_node_or_null("/root/WorldRuntimeDiagnosticLog")
	var monitor_snapshot: Dictionary = {}
	if world_perf_monitor != null and world_perf_monitor.has_method("build_perf_observatory_snapshot"):
		monitor_snapshot = world_perf_monitor.call("build_perf_observatory_snapshot") as Dictionary
	var overlay_snapshot: Dictionary = {}
	if _chunk_manager.has_method("get_chunk_debug_overlay_snapshot"):
		overlay_snapshot = _chunk_manager.get_chunk_debug_overlay_snapshot(DEBUG_QUEUE_ROWS)
	var timeline_snapshot: Array = []
	if world_runtime_diag != null and world_runtime_diag.has_method("get_timeline_snapshot"):
		timeline_snapshot = world_runtime_diag.call("get_timeline_snapshot", TIMELINE_LIMIT)
	var boot_chunk_states: Dictionary = {}
	if _chunk_manager.has_method("get_boot_chunk_states_snapshot"):
		boot_chunk_states = _chunk_manager.get_boot_chunk_states_snapshot()
	var player_full_ready_breaches: Array = []
	if _chunk_manager.has_method("get_recent_player_full_ready_breaches"):
		player_full_ready_breaches = _chunk_manager.get_recent_player_full_ready_breaches()
	var hot_visual_slices: Array = []
	if _chunk_manager.has_method("get_recent_hot_visual_slices"):
		hot_visual_slices = _chunk_manager.get_recent_hot_visual_slices()
	var chunk_transition_snapshots: Array = []
	if _chunk_manager.has_method("get_recent_chunk_transition_snapshots"):
		chunk_transition_snapshots = _chunk_manager.get_recent_chunk_transition_snapshots()
	var debug_diagnostics: Dictionary = _build_debug_diagnostics(overlay_snapshot, timeline_snapshot, monitor_snapshot)
	return {
		"meta": _jsonify_variant({
			"schema_version": 2,
			"generated_at": Time.get_datetime_string_from_system(true),
			"world_seed": _game_world.world_seed if _game_world != null else 0,
			"scene": "res://scenes/world/game_world.tscn",
			"cmdline_args": OS.get_cmdline_user_args(),
			"perf_test_enabled": true,
			"runtime_validation_enabled": _validation_is_requested(),
			"stress_enabled": _stress_is_requested(),
			"output_path": _output_path,
			"output_absolute_path": _to_absolute_path(_output_path),
			"validation_completion": _validation_completion_summary,
			"stress_completion": _stress_completion_summary,
		}),
		"boot": _jsonify_variant({
			"game_world_boot_complete": _game_world.is_boot_complete() if _game_world != null else false,
			"chunk_manager_first_playable": _chunk_manager.is_boot_first_playable() if _chunk_manager != null else false,
			"chunk_manager_boot_complete": _chunk_manager.is_boot_complete() if _chunk_manager != null else false,
			"boot_compute_active": _chunk_manager.get_boot_compute_active_count() if _chunk_manager != null else 0,
			"boot_compute_pending": _chunk_manager.get_boot_compute_pending_count() if _chunk_manager != null else 0,
			"boot_failed_coords": _chunk_manager.get_boot_failed_coords() if _chunk_manager != null else [],
			"chunk_state_counts": _summarize_boot_states(boot_chunk_states),
			"chunk_states": boot_chunk_states,
			"observations": monitor_snapshot.get("session_observations", {}),
		}),
		"streaming": _jsonify_variant({
			"overlay_snapshot": overlay_snapshot,
			"timeline": timeline_snapshot,
			"debug_diagnostics": debug_diagnostics,
			"player_full_ready_breaches": player_full_ready_breaches,
			"hot_visual_slices": hot_visual_slices,
			"chunk_transition_snapshots": chunk_transition_snapshots,
		}),
		"frame_summary": _jsonify_variant(monitor_snapshot),
		"contract_violations": _jsonify_variant(WorldPerfProbe.copy_contract_violation_snapshot()),
		"scenarios": _jsonify_variant(_resolve_scenarios()),
		"stress": _jsonify_variant(_resolve_stress_summary()),
		"native_profiling": _jsonify_variant({
			"chunk_generator": _summarize_native_profile_samples(_chunk_generator_profiles),
			"topology_builder": _summarize_native_profile_samples(_topology_builder_profiles),
		}),
	}

func _build_debug_diagnostics(
	overlay_snapshot: Dictionary,
	timeline_snapshot: Array,
	monitor_snapshot: Dictionary
) -> Dictionary:
	var latest_debug_snapshot: Dictionary = monitor_snapshot.get("latest_debug_snapshot", {}) as Dictionary
	return {
		"queue_state": {
			"rows": overlay_snapshot.get("queue_rows", []),
			"hidden_count": int(overlay_snapshot.get("queue_hidden_count", 0)),
		},
		"timeline_history": timeline_snapshot,
		"forensics": {
			"incident_summary": overlay_snapshot.get("incident_summary", {}),
			"trace_events": overlay_snapshot.get("trace_events", []),
			"chunk_causality_rows": overlay_snapshot.get("chunk_causality_rows", []),
			"task_debug_rows": overlay_snapshot.get("task_debug_rows", []),
			"suspicion_flags": overlay_snapshot.get("suspicion_flags", []),
		},
		"perf_breakdown": {
			"latest_debug_snapshot": latest_debug_snapshot,
			"frame_categories": latest_debug_snapshot.get("categories", {}),
			"frame_ops": latest_debug_snapshot.get("ops", {}),
			"latest_frame_categories": monitor_snapshot.get("latest_frame_categories", {}),
			"latest_frame_ops": monitor_snapshot.get("latest_frame_ops", {}),
			"category_totals": monitor_snapshot.get("category_totals", {}),
			"category_peaks": monitor_snapshot.get("category_peaks", {}),
		},
	}

func _resolve_scenarios() -> Array[Dictionary]:
	if _validation_driver == null or not is_instance_valid(_validation_driver):
		return []
	if _validation_driver.has_method("get_scenario_results"):
		return _validation_driver.get_scenario_results()
	return []

func _resolve_stress_summary() -> Dictionary:
	if not _stress_is_requested():
		return {}
	return _stress_completion_summary.duplicate(true)

func _summarize_boot_states(chunk_states: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for key_variant: Variant in _BOOT_STATE_LABELS.keys():
		counts[_BOOT_STATE_LABELS[key_variant]] = 0
	counts["unknown"] = 0
	for state_variant: Variant in chunk_states.values():
		var state_int: int = int(state_variant)
		var label: String = _BOOT_STATE_LABELS.get(state_int, "unknown")
		counts[label] = int(counts.get(label, 0)) + 1
	return counts

func _summarize_native_profile_samples(samples: Array[Dictionary]) -> Dictionary:
	var phase_totals: Dictionary = {}
	var phase_peaks: Dictionary = {}
	for sample: Dictionary in samples:
		for key_variant: Variant in sample.keys():
			var key: String = str(key_variant)
			if not key.ends_with("_ms"):
				continue
			var value: float = float(sample.get(key, 0.0))
			phase_totals[key] = float(phase_totals.get(key, 0.0)) + value
			phase_peaks[key] = maxf(float(phase_peaks.get(key, 0.0)), value)
	var phase_avg_ms: Dictionary = {}
	if not samples.is_empty():
		for key_variant: Variant in phase_totals.keys():
			var key: String = str(key_variant)
			phase_avg_ms[key] = float(phase_totals.get(key, 0.0)) / float(samples.size())
	return {
		"sample_count": samples.size(),
		"latest": samples[samples.size() - 1] if not samples.is_empty() else {},
		"phase_avg_ms": phase_avg_ms,
		"phase_peak_ms": phase_peaks,
		"samples": samples,
	}

func _write_artifact(artifact: Dictionary) -> bool:
	var absolute_path: String = _to_absolute_path(_output_path)
	var base_dir: String = absolute_path.get_base_dir()
	var make_dir_result: Error = DirAccess.make_dir_recursive_absolute(base_dir)
	if make_dir_result != OK:
		push_error("PerfTelemetryCollector: failed to create directory %s (%s)" % [base_dir, error_string(make_dir_result)])
		return false
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		push_error("PerfTelemetryCollector: failed to open %s (%s)" % [absolute_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(artifact, "\t") + "\n")
	file.close()
	return true

func _jsonify_variant(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return str(value)
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return {"x": v2.x, "y": v2.y}
		TYPE_VECTOR2I:
			var v2i: Vector2i = value
			return {"x": v2i.x, "y": v2i.y}
		TYPE_VECTOR3I:
			var v3i: Vector3i = value
			return {"x": v3i.x, "y": v3i.y, "z": v3i.z}
		TYPE_ARRAY:
			var result_array: Array = []
			for item: Variant in value:
				result_array.append(_jsonify_variant(item))
			return result_array
		TYPE_DICTIONARY:
			var result_dict: Dictionary = {}
			var dict_value: Dictionary = value
			for key_variant: Variant in dict_value.keys():
				result_dict[str(key_variant)] = _jsonify_variant(dict_value[key_variant])
			return result_dict
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var packed_array: Array = []
			for item: Variant in value:
				packed_array.append(_jsonify_variant(item))
			return packed_array
		_:
			return str(value)
