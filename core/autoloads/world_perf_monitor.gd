class_name WorldPerfMonitorNode
extends Node

## Мониторинг производительности мировых систем.
## Autoload — собирает frame time, детектит hitches, логирует budget usage.
## Работает совместно с WorldPerfProbe (статический инструмент измерений).

const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")
const HITCH_THRESHOLD_MS: float = 22.0
const LOW_FPS_THRESHOLD: float = 50.0
const SUMMARY_INTERVAL_FRAMES: int = 300
const BUDGET_TOTAL_MS: float = 6.0

var _frame_count: int = 0
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _hitch_count: int = 0
var _category_totals: Dictionary = {}
var _category_counts: Dictionary = {}
var _category_peaks: Dictionary = {}
var _observation_latest: Dictionary = {}
var _session_observations: Dictionary = {}
var _summary_frame_count: int = 0
var _latest_frame_ms: float = 0.0
var _latest_frame_ops: Dictionary = {}
var _latest_frame_categories: Dictionary = {}
var _latest_debug_snapshot: Dictionary = {}

func _ready() -> void:
	name = "WorldPerfMonitor"
	process_priority = 1000

func _process(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	_frame_count += 1
	_summary_frame_count += 1
	_frame_times.append(frame_ms)
	var frame_ops: Dictionary = WorldPerfProbe.flush_frame()
	var frame_categories: Dictionary = _build_frame_categories(frame_ops)
	_latest_frame_ms = frame_ms
	_latest_frame_ops = frame_ops.duplicate()
	_latest_frame_categories = frame_categories
	_update_debug_snapshot(frame_categories)
	_capture_observations(frame_ops)
	_accumulate_categories(frame_ops)
	if frame_ms > HITCH_THRESHOLD_MS:
		_hitch_count += 1
	if _summary_frame_count >= SUMMARY_INTERVAL_FRAMES:
		_print_summary()
		_reset_summary()

func get_debug_snapshot() -> Dictionary:
	return _latest_debug_snapshot.duplicate(true)

func build_perf_observatory_snapshot() -> Dictionary:
	return {
		"frame_count": _frame_count,
		"summary_frame_count": _summary_frame_count,
		"latest_debug_snapshot": _latest_debug_snapshot.duplicate(true),
		"latest_frame_ms": _latest_frame_ms,
		"latest_frame_ops": _latest_frame_ops.duplicate(true),
		"latest_frame_categories": _latest_frame_categories.duplicate(true),
		"hitch_count": _hitch_count,
		"session_observations": _session_observations.duplicate(true),
		"category_totals": _category_totals.duplicate(true),
		"category_counts": _category_counts.duplicate(true),
		"category_peaks": _category_peaks.duplicate(true),
	}

func _build_frame_categories(ops: Dictionary) -> Dictionary:
	var categories: Dictionary = {}
	for key: String in ops:
		var category: String = _categorize(key)
		var value: float = ops[key] as float
		categories[category] = float(categories.get(category, 0.0)) + value
	return categories

func _update_debug_snapshot(frame_categories: Dictionary) -> void:
	var streaming_load_ms: float = float(frame_categories.get("streaming_load", 0.0))
	var streaming_redraw_ms: float = float(frame_categories.get("streaming_redraw", 0.0))
	var streaming_ms: float = float(frame_categories.get("streaming", 0.0))
	var topology_ms: float = float(frame_categories.get("topology", 0.0))
	var visual_ms: float = float(frame_categories.get("visual", 0.0))
	var shadow_ms: float = float(frame_categories.get("shadow", 0.0))
	var dispatcher_ms: float = float(frame_categories.get("dispatcher", 0.0))
	_latest_debug_snapshot = {
		"timestamp_usec": Time.get_ticks_usec(),
		"fps": Engine.get_frames_per_second(),
		"frame_time_ms": _latest_frame_ms,
		"world_update_ms": streaming_ms + streaming_load_ms + streaming_redraw_ms + topology_ms + visual_ms + shadow_ms + dispatcher_ms,
		"chunk_generation_ms": streaming_load_ms,
		"visual_build_ms": streaming_redraw_ms + visual_ms + shadow_ms,
		"dispatcher_ms": dispatcher_ms,
		"categories": frame_categories.duplicate(),
		"ops": _latest_frame_ops.duplicate(),
	}

func _accumulate_categories(ops: Dictionary) -> void:
	for key: String in ops:
		var category: String = _categorize(key)
		var value: float = ops[key] as float
		_category_totals[category] = _category_totals.get(category, 0.0) + value
		_category_counts[category] = int(_category_counts.get(category, 0)) + 1
		if value > float(_category_peaks.get(category, 0.0)):
			_category_peaks[category] = value

func _capture_observations(ops: Dictionary) -> void:
	for key: String in ops:
		if _is_observation_metric(key):
			_observation_latest[key] = float(ops[key])
			_session_observations[key] = float(ops[key])

func _is_observation_metric(label: String) -> bool:
	return label.begins_with("Startup.") \
		or label == "Scheduler.urgent_visual_wait_ms" \
		or label == "scheduler.max_urgent_wait_ms" \
		or label == "Shadow.stale_age_ms" \
		or label == "Autosave.snapshot_ms" \
		or label == "Autosave.write_ms"

func _categorize(label: String) -> String:
	if label.begins_with("Boot.first_playable") or label.begins_with("Boot.boot_complete") \
		or label.begins_with("Boot.milestone") or label.begins_with("Boot.marker") \
		or (label.begins_with("Boot.") and (label.contains("milestone") or label.contains("marker") or label.contains("ready") or label.contains("handoff"))):
		return "boot_milestone"
	if label.begins_with("Boot.compute"):
		return "boot_compute"
	if label.begins_with("Boot.apply_chunk"):
		return "boot_apply"
	if label.begins_with("Boot.redraw_") or label.begins_with("Chunk._redraw_all"):
		return "boot_redraw"
	if label.begins_with("Boot.topology") or (label.begins_with("Boot.") and (label.contains("topology") or label.contains("Topology"))):
		return "boot_topology"
	if label.begins_with("Boot.shadow") or (label.begins_with("Boot.") and (label.contains("shadow") or label.contains("Shadow"))):
		return "boot_shadow"
	if label.begins_with("Boot."):
		return "boot_other"
	if label.begins_with("FrameBudgetDispatcher.streaming.chunk_manager.streaming_load") \
		or label.begins_with("ChunkManager.streaming_load"):
		return "streaming_load"
	if label.begins_with("FrameBudgetDispatcher.streaming.chunk_manager.streaming_redraw") \
		or label.begins_with("ChunkManager.streaming_redraw_step."):
		return "streaming_redraw"
	if label.begins_with("FrameBudgetDispatcher.topology.building.") or label.begins_with("BuildingSystem."):
		return "building"
	if label.begins_with("FrameBudgetDispatcher.topology.power."):
		return "power"
	if label.begins_with("FrameBudgetDispatcher.topology.") or label.contains("Topology.runtime"):
		return "topology"
	if label.begins_with("FrameBudgetDispatcher.visual.") or label.contains("Shadow.") or label.contains("mountain_shadow"):
		return "shadow"
	if label.begins_with("ChunkManager._load_chunk") or label.begins_with("Chunk._redraw"):
		return "streaming"
	if label == "FrameBudgetDispatcher.total":
		return "dispatcher"
	if label.begins_with("FrameBudgetDispatcher.streaming."):
		return "streaming"
	if label.begins_with("FrameBudgetDispatcher.spawn."):
		return "spawn"
	if label.contains("cover") or label.contains("Roof") or label.contains("cliff"):
		return "visual"
	if label.contains("spawn") or label.contains("Spawn") or label.contains("scrap"):
		return "spawn"
	if label.contains("harvest") or label.contains("mine") or label.contains("Mine"):
		return "interactive"
	return "other"

func _find_heaviest(ops: Dictionary) -> String:
	var max_label: String = ""
	var max_ms: float = 0.0
	for key: String in ops:
		var val: float = ops[key] as float
		if val > max_ms:
			max_ms = val
			max_label = key
	return "%s (%.2f ms)" % [max_label, max_ms]

func _print_summary() -> void:
	if _frame_times.is_empty():
		return
	if not WorldRuntimeDiagnosticLog.should_print_prefix(WorldRuntimeDiagnosticLog.PERF_PREFIX):
		return
	var avg_ms: float = _calc_average()
	var p99_ms: float = _calc_percentile(99.0)
	var n: float = float(_summary_frame_count)
	var boot_apply_avg: float = _category_totals.get("boot_apply", 0.0) / n
	var boot_compute_avg: float = _category_totals.get("boot_compute", 0.0) / n
	var boot_redraw_avg: float = _category_totals.get("boot_redraw", 0.0) / n
	var boot_topology_avg: float = _category_totals.get("boot_topology", 0.0) / n
	var boot_shadow_avg: float = _category_totals.get("boot_shadow", 0.0) / n
	var boot_milestone_avg: float = _category_totals.get("boot_milestone", 0.0) / n
	var boot_milestone_count: int = int(_category_counts.get("boot_milestone", 0))
	var boot_milestone_peak: float = float(_category_peaks.get("boot_milestone", 0.0))
	var boot_other_avg: float = _category_totals.get("boot_other", 0.0) / n
	var streaming_load_avg: float = _category_totals.get("streaming_load", 0.0) / n
	var streaming_redraw_avg: float = _category_totals.get("streaming_redraw", 0.0) / n
	var streaming_load_peak: float = float(_category_peaks.get("streaming_load", 0.0))
	var streaming_redraw_peak: float = float(_category_peaks.get("streaming_redraw", 0.0))
	var streaming_avg: float = _category_totals.get("streaming", 0.0) / n
	var topology_avg: float = _category_totals.get("topology", 0.0) / n
	var visual_avg: float = _category_totals.get("visual", 0.0) / n
	var shadow_avg: float = _category_totals.get("shadow", 0.0) / n
	var boot_compute_peak: float = float(_category_peaks.get("boot_compute", 0.0))
	var boot_apply_peak: float = float(_category_peaks.get("boot_apply", 0.0))
	var boot_redraw_peak: float = float(_category_peaks.get("boot_redraw", 0.0))
	var boot_topology_peak: float = float(_category_peaks.get("boot_topology", 0.0))
	var boot_shadow_peak: float = float(_category_peaks.get("boot_shadow", 0.0))
	var spawn_avg: float = _category_totals.get("spawn", 0.0) / n
	var building_avg: float = _category_totals.get("building", 0.0) / n
	var power_avg: float = _category_totals.get("power", 0.0) / n
	var dispatcher_avg: float = _category_totals.get("dispatcher", 0.0) / n
	var total_avg: float = dispatcher_avg + streaming_avg + streaming_load_avg + streaming_redraw_avg + topology_avg + visual_avg + shadow_avg + spawn_avg + building_avg + power_avg + boot_compute_avg + boot_apply_avg + boot_redraw_avg + boot_topology_avg + boot_shadow_avg + boot_milestone_avg + boot_other_avg
	print("[WorldPerf] === Frame Summary (%d frames) ===" % _summary_frame_count)
	print("[WorldPerf] Frame time: avg=%.1f ms, p99=%.1f ms, hitches=%d" % [avg_ms, p99_ms, _hitch_count])
	print("[WorldPerf] Frame budget: dispatcher=%.1fms streaming=%.1fms streaming_load=%.1fms streaming_redraw=%.1fms topology=%.1fms building=%.1fms power=%.1fms visual=%.1fms shadow=%.1fms spawn=%.1fms total=%.1fms/%.1fms" % [
		dispatcher_avg, streaming_avg, streaming_load_avg, streaming_redraw_avg, topology_avg, building_avg, power_avg, visual_avg, shadow_avg, spawn_avg, total_avg, BUDGET_TOTAL_MS
	])
	if boot_compute_avg > 0.0 or boot_apply_avg > 0.0 or boot_redraw_avg > 0.0 or boot_topology_avg > 0.0 or boot_shadow_avg > 0.0 or boot_milestone_count > 0 or boot_other_avg > 0.0:
		print("[WorldPerf] Boot detail: compute=%.1fms apply=%.1fms redraw=%.1fms topology=%.1fms shadow=%.1fms milestones=%d other=%.1fms | peaks: compute=%.1fms apply=%.1fms redraw=%.1fms topology=%.1fms shadow=%.1fms milestones=%.1fms stream_load=%.1fms stream_redraw=%.1fms" % [
			boot_compute_avg, boot_apply_avg, boot_redraw_avg, boot_topology_avg, boot_shadow_avg, boot_milestone_count, boot_other_avg,
			boot_compute_peak, boot_apply_peak, boot_redraw_peak, boot_topology_peak, boot_shadow_peak, boot_milestone_peak, streaming_load_peak, streaming_redraw_peak
		])
	if not _observation_latest.is_empty():
		var labels: Array[String] = []
		for key: Variant in _observation_latest.keys():
			labels.append(String(key))
		labels.sort()
		var parts: Array[String] = []
		for label: String in labels:
			parts.append("%s=%.1fms" % [label, float(_observation_latest.get(label, 0.0))])
		print("[WorldPerf] Observability: %s" % [", ".join(parts)])

func _calc_average() -> float:
	if _frame_times.is_empty():
		return 0.0
	var total: float = 0.0
	for ft: float in _frame_times:
		total += ft
	return total / float(_frame_times.size())

func _calc_percentile(percentile: float) -> float:
	if _frame_times.is_empty():
		return 0.0
	var sorted_times: Array[float] = []
	for ft: float in _frame_times:
		sorted_times.append(ft)
	sorted_times.sort()
	var idx: int = mini(int(float(sorted_times.size()) * percentile / 100.0), sorted_times.size() - 1)
	return sorted_times[idx]

func _reset_summary() -> void:
	_frame_times = PackedFloat32Array()
	_hitch_count = 0
	_category_totals.clear()
	_category_counts.clear()
	_category_peaks.clear()
	_observation_latest.clear()
	_summary_frame_count = 0
