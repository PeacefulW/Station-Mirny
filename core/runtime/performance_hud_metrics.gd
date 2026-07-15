class_name PerformanceHudMetrics
extends RefCounted
## Bounded, allocation-light telemetry model for the in-game performance HUD.
## Frame samples are written into a fixed ring every frame; sorting and string
## formatting happen only on the HUD's slow presentation cadence.

enum Health {
	UNKNOWN,
	GOOD,
	WARNING,
	CRITICAL,
}

const DEFAULT_HISTORY_CAPACITY: int = 300
const FRAME_BUDGET_60_FPS_MS: float = 1000.0 / 60.0
const HITCH_THRESHOLD_MS: float = 22.0
const CAUSE_MIN_DURATION_MS: float = 1.5
const CAUSE_MIN_FRAME_SHARE: float = 0.20
const CAUSE_MIN_EXCESS_SHARE: float = 0.40
const WORLD_STREAMING_JOB_KEY: String = "FrameBudgetDispatcher.streaming.world.streaming_v0"

const STREAMING_JOB_KEYS: Array[String] = [
	WORLD_STREAMING_JOB_KEY,
	"FrameBudgetDispatcher.streaming.world.object_presentation_visual_upload",
	"FrameBudgetDispatcher.streaming.world.object_presentation_retire",
	"FrameBudgetDispatcher.streaming.world.grass_scatter_visual_upload",
]
const TIMING_KEYS: Array[String] = [
	"dispatcher_ms",
	"streaming_ms",
	"visual_ms",
	"packet_ms",
	"publish_begin_ms",
	"publish_apply_ms",
	"publish_finalize_ms",
	"object_upload_ms",
	"grass_upload_ms",
]

const HITCH_CAUSE_KEYS: Array[Dictionary] = [
	{
		"key": "WorldStreamer.packet_results.integrate_batch",
		"name": "packet_integration",
	},
	{
		"key": "WorldStreamer.publish.begin",
		"name": "publish_begin",
	},
	{
		"key": "WorldStreamer.publish.apply_batch",
		"name": "publish_apply",
	},
	{
		"key": "WorldStreamer.publish.finalize",
		"name": "publish_finalize",
	},
	{
		"key": "WorldStreamer.visual_upload.object_packet_slice",
		"name": "object_upload",
	},
	{
		"key": "WorldStreamer.visual_upload.object_packet_adopt",
		"name": "object_adopt",
	},
	{
		"key": "FrameBudgetDispatcher.streaming.world.object_presentation_visual_upload",
		"name": "object_upload",
	},
	{
		"key": "WorldStreamer.visual_upload.grass_scatter_phase",
		"name": "grass_upload",
	},
	{
		"key": "FrameBudgetDispatcher.streaming.world.grass_scatter_visual_upload",
		"name": "grass_upload",
	},
	{
		"key": "FrameBudgetDispatcher.visual.world.mountain_native_mask_visual_upload",
		"name": "mountain_upload",
	},
]

var _capacity: int = DEFAULT_HISTORY_CAPACITY
var _frame_samples: PackedFloat32Array = PackedFloat32Array()
var _hitch_samples: PackedByteArray = PackedByteArray()
var _sample_count: int = 0
var _sample_cursor: int = 0
var _sample_sequence: int = 0
var _hitch_count: int = 0
var _last_hitch: Dictionary = { }
var _latest_timings: Dictionary = { }
var _interval_timing_peaks: Dictionary = { }


func _init(capacity: int = DEFAULT_HISTORY_CAPACITY) -> void:
	_capacity = maxi(1, capacity)
	_frame_samples.resize(_capacity)
	_hitch_samples.resize(_capacity)


func reset() -> void:
	_sample_count = 0
	_sample_cursor = 0
	_sample_sequence = 0
	_hitch_count = 0
	_hitch_samples.fill(0)
	_last_hitch.clear()
	_latest_timings.clear()
	_interval_timing_peaks.clear()


func push_frame(frame_ms: float, frame_ops: Dictionary = { }) -> void:
	if is_nan(frame_ms) or is_inf(frame_ms) or frame_ms < 0.0:
		return
	var is_hitch: bool = frame_ms > HITCH_THRESHOLD_MS
	if _sample_count >= _capacity and _hitch_samples[_sample_cursor] != 0:
		_hitch_count = maxi(0, _hitch_count - 1)
	_frame_samples[_sample_cursor] = frame_ms
	_hitch_samples[_sample_cursor] = 1 if is_hitch else 0
	_sample_cursor = (_sample_cursor + 1) % _capacity
	_sample_count = mini(_sample_count + 1, _capacity)
	_sample_sequence += 1

	_update_timings(frame_ops)
	for key: String in TIMING_KEYS:
		_interval_timing_peaks[key] = maxf(
			float(_interval_timing_peaks.get(key, 0.0)),
			float(_latest_timings.get(key, 0.0)),
		)

	if is_hitch:
		_hitch_count += 1
		var cause: Dictionary = _find_hitch_cause(frame_ms, frame_ops)
		_last_hitch = {
			"frame_ms": frame_ms,
			"cause": String(cause.get("cause", "external_or_render")),
			"cause_ms": float(cause.get("cause_ms", 0.0)),
			"timestamp_msec": Time.get_ticks_msec(),
			"sample_sequence": _sample_sequence,
		}


func get_frame_stats() -> Dictionary:
	if _sample_count <= 0:
		return {
			"sample_count": 0,
			"current_ms": 0.0,
			"average_ms": 0.0,
			"p95_ms": 0.0,
			"p99_ms": 0.0,
			"max_ms": 0.0,
			"health": Health.UNKNOWN,
			"hitch_count": _hitch_count,
		}
	var samples: Array[float] = []
	samples.resize(_sample_count)
	var total_ms: float = 0.0
	var max_ms: float = 0.0
	for index: int in range(_sample_count):
		var value: float = float(_frame_samples[index])
		samples[index] = value
		total_ms += value
		max_ms = maxf(max_ms, value)
	var current_index: int = posmod(_sample_cursor - 1, _capacity)
	var current_ms: float = float(_frame_samples[current_index])
	var p95_ms: float = percentile(samples, 95.0)
	var p99_ms: float = percentile(samples, 99.0)
	return {
		"sample_count": _sample_count,
		"current_ms": current_ms,
		"average_ms": total_ms / float(_sample_count),
		"p95_ms": p95_ms,
		"p99_ms": p99_ms,
		"max_ms": max_ms,
		"health": classify_frame_time(maxf(current_ms, p95_ms)),
		"hitch_count": _hitch_count,
	}


func get_graph_samples() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(_sample_count)
	var start_index: int = 0 if _sample_count < _capacity else _sample_cursor
	for offset: int in range(_sample_count):
		result[offset] = _frame_samples[(start_index + offset) % _capacity]
	return result


func get_latest_timings() -> Dictionary:
	return _latest_timings.duplicate(false)


func take_interval_timing_peaks() -> Dictionary:
	var snapshot: Dictionary = _interval_timing_peaks.duplicate(false)
	_interval_timing_peaks.clear()
	return snapshot


func get_last_hitch() -> Dictionary:
	if _last_hitch.is_empty():
		return { }
	var hitch_sequence: int = int(_last_hitch.get("sample_sequence", 0))
	if _sample_sequence - hitch_sequence >= _capacity:
		return { }
	return _last_hitch.duplicate(false)


func get_sample_count() -> int:
	return _sample_count


func get_capacity() -> int:
	return _capacity


static func percentile(samples: Array[float], requested_percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples: Array[float] = samples.duplicate()
	sorted_samples.sort()
	var normalized: float = clampf(requested_percentile, 0.0, 100.0) / 100.0
	var rank: int = ceili(normalized * float(sorted_samples.size()))
	var index: int = clampi(rank - 1, 0, sorted_samples.size() - 1)
	return sorted_samples[index]


static func classify_frame_time(frame_ms: float) -> int:
	if is_nan(frame_ms) or is_inf(frame_ms) or frame_ms < 0.0:
		return Health.UNKNOWN
	if frame_ms <= FRAME_BUDGET_60_FPS_MS:
		return Health.GOOD
	if frame_ms <= HITCH_THRESHOLD_MS:
		return Health.WARNING
	return Health.CRITICAL


static func format_ms(value: float) -> String:
	if is_nan(value) or is_inf(value) or value < 0.0:
		return "—"
	return "%.2f ms" % value


static func format_fps(value: float) -> String:
	if is_nan(value) or is_inf(value) or value < 0.0:
		return "—"
	return "%.1f FPS" % value


static func format_bytes(byte_count: int) -> String:
	if byte_count < 0:
		return "—"
	var value: float = float(byte_count)
	if byte_count >= 1024 * 1024 * 1024:
		return "%.1f GiB" % (value / float(1024 * 1024 * 1024))
	if byte_count >= 1024 * 1024:
		return "%.1f MiB" % (value / float(1024 * 1024))
	if byte_count >= 1024:
		return "%.1f KiB" % (value / 1024.0)
	return "%d B" % byte_count


func _update_timings(frame_ops: Dictionary) -> void:
	var streaming_ms: float = 0.0
	for key: String in STREAMING_JOB_KEYS:
		streaming_ms += float(frame_ops.get(key, 0.0))
	_latest_timings["dispatcher_ms"] = float(
		frame_ops.get("FrameBudgetDispatcher.total", 0.0),
	)
	_latest_timings["streaming_ms"] = streaming_ms
	_latest_timings["visual_ms"] = float(
		frame_ops.get(
			"FrameBudgetDispatcher.visual.world.mountain_native_mask_visual_upload",
			0.0,
		),
	)
	_latest_timings["packet_ms"] = float(
		frame_ops.get("WorldStreamer.packet_results.integrate_batch", 0.0),
	)
	_latest_timings["publish_begin_ms"] = float(
		frame_ops.get("WorldStreamer.publish.begin", 0.0),
	)
	_latest_timings["publish_apply_ms"] = float(
		frame_ops.get("WorldStreamer.publish.apply_batch", 0.0),
	)
	_latest_timings["publish_finalize_ms"] = float(
		frame_ops.get("WorldStreamer.publish.finalize", 0.0),
	)
	_latest_timings["object_upload_ms"] = float(
		frame_ops.get(
			"FrameBudgetDispatcher.streaming.world.object_presentation_visual_upload",
			0.0,
		),
	)
	_latest_timings["grass_upload_ms"] = float(
		frame_ops.get(
			"FrameBudgetDispatcher.streaming.world.grass_scatter_visual_upload",
			0.0,
		),
	)


func _find_hitch_cause(frame_ms: float, frame_ops: Dictionary) -> Dictionary:
	var heaviest_name: String = "external_or_render"
	var heaviest_ms: float = 0.0
	for spec: Dictionary in HITCH_CAUSE_KEYS:
		var value_ms: float = float(frame_ops.get(String(spec.get("key", "")), 0.0))
		if value_ms <= heaviest_ms:
			continue
		heaviest_ms = value_ms
		heaviest_name = String(spec.get("name", "external_or_render"))
	var excess_ms: float = maxf(frame_ms - FRAME_BUDGET_60_FPS_MS, 0.001)
	var frame_share: float = heaviest_ms / maxf(frame_ms, 0.001)
	var excess_share: float = heaviest_ms / excess_ms
	var plausible: bool = heaviest_ms >= CAUSE_MIN_DURATION_MS and (
		frame_share >= CAUSE_MIN_FRAME_SHARE or excess_share >= CAUSE_MIN_EXCESS_SHARE
	)
	if plausible:
		return {
			"cause": heaviest_name,
			"cause_ms": heaviest_ms,
		}
	var streaming_ms: float = float(frame_ops.get(WORLD_STREAMING_JOB_KEY, 0.0))
	frame_share = streaming_ms / maxf(frame_ms, 0.001)
	excess_share = streaming_ms / excess_ms
	plausible = streaming_ms >= CAUSE_MIN_DURATION_MS and (
		frame_share >= CAUSE_MIN_FRAME_SHARE or excess_share >= CAUSE_MIN_EXCESS_SHARE
	)
	if plausible:
		return {
			"cause": "world_streaming",
			"cause_ms": streaming_ms,
		}
	return {
		"cause": "external_or_render",
		"cause_ms": 0.0,
	}
