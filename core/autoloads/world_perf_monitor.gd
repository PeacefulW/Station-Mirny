class_name WorldPerfMonitorNode
extends Node

## Мониторинг производительности мировых систем.
## Autoload — собирает frame time, детектит hitches, логирует budget usage.
## Работает совместно с WorldPerfProbe (статический инструмент измерений).

const HITCH_THRESHOLD_MS: float = 22.0
const LOW_FPS_THRESHOLD: float = 50.0
const SUMMARY_INTERVAL_FRAMES: int = 300
const BUDGET_TOTAL_MS: float = 6.0

var _frame_count: int = 0
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _hitch_count: int = 0
var _category_totals: Dictionary = {}
var _summary_frame_count: int = 0

func _ready() -> void:
	name = "WorldPerfMonitor"
	process_priority = 1000

func _process(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	_frame_count += 1
	_summary_frame_count += 1
	_frame_times.append(frame_ms)
	var frame_ops: Dictionary = WorldPerfProbe.flush_frame()
	_accumulate_categories(frame_ops)
	if frame_ms > HITCH_THRESHOLD_MS:
		_hitch_count += 1
	if _summary_frame_count >= SUMMARY_INTERVAL_FRAMES:
		_print_summary()
		_reset_summary()

func _accumulate_categories(ops: Dictionary) -> void:
	for key: String in ops:
		var category: String = _categorize(key)
		_category_totals[category] = _category_totals.get(category, 0.0) + (ops[key] as float)

func _categorize(label: String) -> String:
	if label.contains(".boot"):
		if label.contains("topology") or label.contains("Topology"):
			return "topology_boot"
		if label.begins_with("ChunkManager._load_chunk") or label.begins_with("Chunk._redraw"):
			return "streaming_boot"
	if label == "FrameBudgetDispatcher.total":
		return "dispatcher"
	if label.begins_with("FrameBudgetDispatcher.streaming."):
		return "streaming"
	if label.begins_with("FrameBudgetDispatcher.topology."):
		return "topology"
	if label.begins_with("FrameBudgetDispatcher.visual."):
		return "visual"
	if label.begins_with("FrameBudgetDispatcher.spawn."):
		return "spawn"
	if label.begins_with("ChunkManager._load_chunk") or label.begins_with("Chunk._redraw"):
		return "streaming"
	if label.contains("topology") or label.contains("Topology"):
		return "topology"
	if label.contains("cover") or label.contains("shadow") or label.contains("Shadow") or label.contains("Roof") or label.contains("cliff"):
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
	var avg_ms: float = _calc_average()
	var p99_ms: float = _calc_percentile(99.0)
	var streaming_avg: float = _category_totals.get("streaming", 0.0) / float(_summary_frame_count)
	var topology_avg: float = _category_totals.get("topology", 0.0) / float(_summary_frame_count)
	var visual_avg: float = _category_totals.get("visual", 0.0) / float(_summary_frame_count)
	var spawn_avg: float = _category_totals.get("spawn", 0.0) / float(_summary_frame_count)
	var dispatcher_avg: float = _category_totals.get("dispatcher", 0.0) / float(_summary_frame_count)
	var boot_streaming_avg: float = _category_totals.get("streaming_boot", 0.0) / float(_summary_frame_count)
	var boot_topology_avg: float = _category_totals.get("topology_boot", 0.0) / float(_summary_frame_count)
	var total_avg: float = streaming_avg + topology_avg + visual_avg + spawn_avg
	print("[WorldPerf] === Frame Summary (%d frames) ===" % _summary_frame_count)
	print("[WorldPerf] Frame time: avg=%.1f ms, p99=%.1f ms, hitches=%d" % [avg_ms, p99_ms, _hitch_count])
	print("[WorldPerf] Frame budget: dispatcher=%.1fms streaming=%.1fms topology=%.1fms visual=%.1fms spawn=%.1fms total=%.1fms/%.1fms" % [
		dispatcher_avg, streaming_avg, topology_avg, visual_avg, spawn_avg, total_avg, BUDGET_TOTAL_MS
	])
	if boot_streaming_avg > 0.0 or boot_topology_avg > 0.0:
		print("[WorldPerf] Boot work: streaming=%.1fms topology=%.1fms" % [boot_streaming_avg, boot_topology_avg])

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
	_summary_frame_count = 0
