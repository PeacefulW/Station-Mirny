class_name PerformanceFlightRecorder
extends Node
## Bounded developer flight recorder. Ordinary gameplay pays only for the
## inactive Node; all telemetry and render measurements are opt-in through F4.
## Sampling, event detection, and the async capture lifecycle deliberately stay
## in one state machine; artifact serialization and retention are split out.

const ArtifactWriter = preload("res://core/runtime/performance_flight_recorder_artifact_writer.gd")

signal state_changed
signal notification_requested(message_key: StringName, message_args: Dictionary)

const CAPTURE_ROOT: String = "user://performance_captures"
const MAX_SESSION_SECONDS: float = 120.0
const MAX_FRAME_SAMPLES: int = 28_800
const CONTEXT_INTERVAL_SECONDS: float = 0.25
const WARMUP_FRAMES: int = 120
const SUSTAINED_SLOW_THRESHOLD_MS: float = 22.0
const SUSTAINED_SLOW_SECONDS: float = 2.0
const SPIKE_MINIMUM_MS: float = 50.0
const SPIKE_BASELINE_MULTIPLIER: float = 1.75
const BASELINE_SMOOTHING: float = 0.035
const CAPTURE_COOLDOWN_SECONDS: float = 5.0
const MAX_AUTOMATIC_CAPTURES: int = 12
const MAX_EVENT_RECORDS: int = 64
const CAPTURE_TAINT_FRAMES: int = 3
const RENDER_MEASUREMENT_WARMUP_FRAMES: int = 3
const INVALID_TASK_ID: int = -1
const TRACE_STRIDE: int = 57

const TRACE_COLUMNS: Array[String] = [
	"frame",
	"elapsed_ms",
	"frame_ms",
	"fps",
	"frame_total_monitor_ms",
	"physics_ms",
	"viewport_cpu_ms",
	"viewport_gpu_ms",
	"frame_setup_cpu_ms",
	"draw_calls",
	"render_objects",
	"render_primitives",
	"player_x",
	"player_y",
	"velocity_x",
	"velocity_y",
	"camera_zoom",
	"player_chunk_x",
	"player_chunk_y",
	"stream_radius",
	"resident_views",
	"desired_visible_chunks",
	"desired_source_chunks",
	"packet_count",
	"requested_packets",
	"publish_queue",
	"visibility_wait",
	"object_upload_queue",
	"object_prestage_queue",
	"object_inflight",
	"object_ready_cpu",
	"grass_upload_queue",
	"grass_inflight",
	"grass_ready_cpu",
	"mask_inflight",
	"mask_upload_queue",
	"mask_retry_queue",
	"dispatcher_ms",
	"streaming_job_ms",
	"packet_integrate_ms",
	"publish_begin_ms",
	"publish_apply_ms",
	"publish_finalize_ms",
	"object_upload_ms",
	"grass_upload_ms",
	"mountain_visual_ms",
	"capture_tainted",
	"postprocess_enabled",
	"warm_packet_cache",
	"hot_view_cache",
	"object_hot_cache",
	"object_warm_cache",
	"grass_warm_cache",
	"object_worker_ms",
	"object_latency_ms",
	"grass_worker_ms",
	"grass_latency_ms",
]

const LIVE_OP_KEYS: Dictionary = {
	"dispatcher_ms": "FrameBudgetDispatcher.total",
	"streaming_job_ms": "FrameBudgetDispatcher.streaming.world.streaming_v0",
	"packet_integrate_ms": "WorldStreamer.packet_results.integrate_batch",
	"publish_begin_ms": "WorldStreamer.publish.begin",
	"publish_apply_ms": "WorldStreamer.publish.apply_batch",
	"publish_finalize_ms": "WorldStreamer.publish.finalize",
	"object_upload_ms": "FrameBudgetDispatcher.streaming.world.object_presentation_visual_upload",
	"grass_upload_ms": "FrameBudgetDispatcher.streaming.world.grass_scatter_visual_upload",
	"mountain_visual_ms": "FrameBudgetDispatcher.visual.world.mountain_native_mask_visual_upload",
}

var _streamer: Node = null
var _postprocess_overlay: Node = null
var _capture_root: String = CAPTURE_ROOT
var _viewport_rid: RID = RID()
var _is_recording: bool = false
var _is_saving: bool = false
var _observer_active: bool = false
var _manual_observer_active: bool = false
var _capture_in_progress: bool = false
var _stop_requested: bool = false
var _session_dir: String = ""
var _session_absolute_dir: String = ""
var _session_started_usec: int = 0
var _last_frame_usec: int = 0
var _sample_count: int = 0
var _trace_data: PackedFloat64Array = PackedFloat64Array()
var _events: Array[Dictionary] = []
var _context_snapshot: Dictionary = { }
var _context_elapsed: float = 0.0
var _baseline_ms: float = 0.0
var _slow_elapsed: float = 0.0
var _slow_event_active: bool = false
var _queue_pressure_active: bool = false
var _last_capture_usec: int = -1
var _automatic_capture_count: int = 0
var _capture_taint_until_frame: int = -1
var _capture_count: int = 0
var _worker_task_id: int = INVALID_TASK_ID
var _worker_kind: StringName = &""
var _worker_context: Dictionary = { }
var _pending_manual_capture: bool = false
var _session_metadata: Dictionary = { }
var _artifact_writer: PerformanceFlightRecorderArtifactWriter = ArtifactWriter.new()


func _ready() -> void:
	name = "PerformanceFlightRecorder"
	process_priority = 1100
	set_process(true)
	_viewport_rid = get_viewport().get_viewport_rid()


func _exit_tree() -> void:
	_end_observation()
	_end_manual_observation()
	_set_render_measurement_enabled(false)
	if _worker_task_id != INVALID_TASK_ID:
		var completed_kind: StringName = _worker_kind
		var completed_context: Dictionary = _worker_context.duplicate(true)
		var wait_error: Error = WorkerThreadPool.wait_for_task_completion(_worker_task_id)
		_worker_task_id = INVALID_TASK_ID
		_worker_kind = &""
		_worker_context.clear()
		if completed_kind == &"capture":
			_settle_capture_worker_on_exit(completed_context, wait_error)
	# Scene changes and application shutdown must not leave an empty F4 folder.
	# Serialization is allowed to block here: gameplay has already stopped and
	# losing the trace would erase the evidence for the failure being diagnosed.
	if _is_recording and not _is_saving:
		_mark_unfinished_events_interrupted()
		_is_recording = false
		_stop_requested = false
		var payload: Dictionary = _build_session_payload()
		_artifact_writer.write_session(payload)
		_trace_data = PackedFloat64Array()
		_events.clear()


func setup(
		streamer: Node,
		postprocess_overlay: Node = null,
		capture_root: String = CAPTURE_ROOT,
	) -> void:
	_streamer = streamer
	_postprocess_overlay = postprocess_overlay
	_capture_root = CAPTURE_ROOT if capture_root.is_empty() else capture_root.simplify_path()


func toggle_recording() -> void:
	if _is_saving:
		notification_requested.emit(&"UI_PERF_RECORDING_SAVING", { })
		return
	if _is_recording:
		request_stop_recording()
	else:
		start_recording()


func start_recording() -> bool:
	if _is_recording or _is_saving:
		return false
	# A standalone F2 owns the single artifact worker and a temporary render-time
	# observer. Starting F4 inside that transaction would let the old capture
	# disable measurements and mutate counters belonging to the new session.
	if _capture_in_progress or _worker_task_id != INVALID_TASK_ID \
			or _manual_observer_active:
		notification_requested.emit(&"UI_PERF_RECORDING_WAIT_CAPTURE", { })
		return false
	var timestamp: String = _make_timestamp()
	_session_dir = "%s/%s" % [_capture_root, timestamp]
	_session_absolute_dir = ProjectSettings.globalize_path(_session_dir)
	var error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("%s/events" % _session_dir),
	)
	if error != OK:
		notification_requested.emit(
			&"UI_PERF_CAPTURE_FAILED",
			{"error": error_string(error)},
		)
		return false

	_trace_data = PackedFloat64Array()
	_trace_data.resize(MAX_FRAME_SAMPLES * TRACE_STRIDE)
	_events.clear()
	_context_snapshot.clear()
	_context_elapsed = CONTEXT_INTERVAL_SECONDS
	_sample_count = 0
	_baseline_ms = 0.0
	_slow_elapsed = 0.0
	_slow_event_active = false
	_queue_pressure_active = false
	_last_capture_usec = -1
	_automatic_capture_count = 0
	_capture_count = 0
	_stop_requested = false
	_pending_manual_capture = false
	_session_started_usec = Time.get_ticks_usec()
	_last_frame_usec = _session_started_usec
	_session_metadata = _build_environment_metadata()
	_session_metadata["started_at"] = Time.get_datetime_string_from_system(true)
	_session_metadata["artifact_directory"] = _session_absolute_dir
	_begin_observation()
	_set_render_measurement_enabled(true)
	_is_recording = true
	state_changed.emit()
	notification_requested.emit(&"UI_PERF_RECORDING_STARTED", { })
	return true


func request_stop_recording() -> void:
	if not _is_recording or _stop_requested:
		return
	_stop_requested = true
	state_changed.emit()
	if not _capture_in_progress and _worker_task_id == INVALID_TASK_ID:
		_finalize_recording()


func capture_manual_snapshot() -> void:
	if not _can_capture_viewport() and not _is_recording:
		notification_requested.emit(
			&"UI_PERF_CAPTURE_FAILED",
			{"error": "headless display"},
		)
		return
	if _capture_in_progress:
		_pending_manual_capture = true
		notification_requested.emit(&"UI_PERF_CAPTURE_QUEUED", { })
		return
	if _is_saving:
		notification_requested.emit(&"UI_PERF_RECORDING_SAVING", { })
		return
	if _is_recording:
		_trigger_event(&"manual", true)
		return
	if _worker_task_id != INVALID_TASK_ID:
		_pending_manual_capture = true
		notification_requested.emit(&"UI_PERF_CAPTURE_QUEUED", { })
		return
	_begin_manual_observation()
	_set_render_measurement_enabled(true)
	var manual_dir: String = "%s/manual_%s" % [_capture_root, _make_timestamp()]
	var absolute_dir: String = ProjectSettings.globalize_path(manual_dir)
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if error != OK:
		_end_manual_observation()
		_set_render_measurement_enabled(false)
		notification_requested.emit(
			&"UI_PERF_CAPTURE_FAILED",
			{"error": error_string(error)},
		)
		return
	_capture_in_progress = true
	notification_requested.emit(&"UI_PERF_CAPTURE_PENDING", { })
	_capture_manual_after_draw(manual_dir, absolute_dir)


func get_ui_state() -> Dictionary:
	var elapsed_seconds: float = 0.0
	if _is_recording:
		elapsed_seconds = minf(
			float(Time.get_ticks_usec() - _session_started_usec) / 1_000_000.0,
			MAX_SESSION_SECONDS,
		)
	return {
		"recording": _is_recording,
		"saving": _is_saving,
		"stopping": _stop_requested,
		"capturing": _capture_in_progress,
		"elapsed_seconds": elapsed_seconds,
		"sample_count": _sample_count,
		"capture_count": _capture_count,
		"artifact_directory": _session_absolute_dir,
		"capture_tainted": is_capture_tainted(),
	}


func is_capture_tainted() -> bool:
	return Engine.get_process_frames() <= _capture_taint_until_frame


func _process(delta: float) -> void:
	_poll_worker()
	if _is_recording and not _stop_requested:
		_record_frame(maxf(delta, 0.0))
		if float(Time.get_ticks_usec() - _session_started_usec) / 1_000_000.0 \
				>= MAX_SESSION_SECONDS or _sample_count >= MAX_FRAME_SAMPLES:
			request_stop_recording()
	if _stop_requested and not _capture_in_progress \
			and _worker_task_id == INVALID_TASK_ID:
		_finalize_recording()


func _record_frame(delta: float) -> void:
	if _sample_count >= MAX_FRAME_SAMPLES:
		return
	var now_usec: int = Time.get_ticks_usec()
	var frame_ms: float = maxf(float(now_usec - _last_frame_usec) / 1000.0, 0.0)
	_last_frame_usec = now_usec
	if _sample_count == 0 or frame_ms <= 0.0:
		frame_ms = delta * 1000.0

	_context_elapsed += delta
	if _context_elapsed >= CONTEXT_INTERVAL_SECONDS:
		_context_elapsed = fmod(_context_elapsed, CONTEXT_INTERVAL_SECONDS)
		_refresh_context_snapshot()

	var live_snapshot: Dictionary = WorldPerfProbe.copy_completed_live_frame_snapshot()
	var frame_ops: Dictionary = live_snapshot.get("ops", { }) as Dictionary
	var player: CharacterBody2D = _get_local_player()
	var player_position: Vector2 = Vector2.ZERO
	var player_velocity: Vector2 = Vector2.ZERO
	var camera_zoom: float = 0.0
	if player != null:
		player_position = player.global_position
		player_velocity = player.velocity
		var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			camera_zoom = camera.zoom.x

	var player_chunk: Vector2i = _context_snapshot.get(
		"player_chunk",
		Vector2i.ZERO,
	) as Vector2i
	var mask_inflight: int = int(_context_snapshot.get("mountain_mask_inflight", 0)) \
			+ int(_context_snapshot.get("terrain_mask_inflight", 0))
	var mask_upload: int = int(
		_context_snapshot.get("mountain_mask_upload_queue", 0),
	) + int(_context_snapshot.get("terrain_mask_upload_queue", 0))
	var tainted: bool = is_capture_tainted()

	var row: int = _sample_count * TRACE_STRIDE
	var values: Array[float] = [
		float(Engine.get_process_frames()),
		float(now_usec - _session_started_usec) / 1000.0,
		frame_ms,
		Engine.get_frames_per_second(),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		_get_viewport_render_time("viewport_get_measured_render_time_cpu"),
		_get_viewport_render_time("viewport_get_measured_render_time_gpu"),
		_get_frame_setup_time_cpu(),
		float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		player_position.x,
		player_position.y,
		player_velocity.x,
		player_velocity.y,
		camera_zoom,
		float(player_chunk.x),
		float(player_chunk.y),
		float(_context_snapshot.get("stream_radius", 0)),
		float(_context_snapshot.get("resident_views", 0)),
		float(_context_snapshot.get("desired_visible_chunks", 0)),
		float(_context_snapshot.get("desired_source_chunks", 0)),
		float(_context_snapshot.get("packet_count", 0)),
		float(_context_snapshot.get("requested_packets", 0)),
		float(_context_snapshot.get("publish_queue", 0)),
		float(_context_snapshot.get("visibility_wait", 0)),
		float(_context_snapshot.get("object_upload_queue", 0)),
		float(_context_snapshot.get("object_prestage_queue", 0)),
		float(_context_snapshot.get("object_inflight", 0)),
		float(_context_snapshot.get("object_ready_cpu", 0)),
		float(_context_snapshot.get("grass_upload_queue", 0)),
		float(_context_snapshot.get("grass_inflight", 0)),
		float(_context_snapshot.get("grass_ready_cpu", 0)),
		float(mask_inflight),
		float(mask_upload),
		float(_context_snapshot.get("mask_retry_queue", 0)),
		_get_live_op(frame_ops, "dispatcher_ms"),
		_get_live_op(frame_ops, "streaming_job_ms"),
		_get_live_op(frame_ops, "packet_integrate_ms"),
		_get_live_op(frame_ops, "publish_begin_ms"),
		_get_live_op(frame_ops, "publish_apply_ms"),
		_get_live_op(frame_ops, "publish_finalize_ms"),
		_get_live_op(frame_ops, "object_upload_ms"),
		_get_live_op(frame_ops, "grass_upload_ms"),
		_get_live_op(frame_ops, "mountain_visual_ms"),
		1.0 if tainted else 0.0,
		1.0 if _is_postprocess_enabled() else 0.0,
		float(_context_snapshot.get("warm_packet_cache", 0)),
		float(_context_snapshot.get("hot_view_cache", 0)),
		float(_context_snapshot.get("object_hot_cache", 0)),
		float(_context_snapshot.get("object_warm_cache", 0)),
		float(_context_snapshot.get("grass_warm_cache", 0)),
		float(_context_snapshot.get("object_worker_ms", 0.0)),
		float(_context_snapshot.get("object_latency_ms", 0.0)),
		float(_context_snapshot.get("grass_worker_ms", 0.0)),
		float(_context_snapshot.get("grass_latency_ms", 0.0)),
	]
	for column_index: int in range(TRACE_STRIDE):
		_trace_data[row + column_index] = values[column_index]
	_sample_count += 1
	_update_event_detection(frame_ms, delta, tainted)
	if _sample_count % 15 == 0:
		state_changed.emit()


func _refresh_context_snapshot() -> void:
	if _streamer != null and is_instance_valid(_streamer) \
			and _streamer.has_method("get_perf_hud_snapshot"):
		_context_snapshot = _streamer.call("get_perf_hud_snapshot") as Dictionary
	else:
		_context_snapshot = { }
	var object_pressure: int = int(_context_snapshot.get("object_upload_queue", 0)) \
			+ int(_context_snapshot.get("object_prestage_queue", 0))
	var pressure_now: bool = object_pressure > 96 \
			or int(_context_snapshot.get("visibility_wait", 0)) > 8 \
			or int(_context_snapshot.get("publish_queue", 0)) > 48
	# Preserve the previous transition state while readback-tainted. Once the
	# taint expires, a still-active pressure condition emits exactly one deferred
	# event instead of recursively screenshotting the observer's own stall.
	if is_capture_tainted():
		return
	if pressure_now and not _queue_pressure_active and _sample_count >= WARMUP_FRAMES:
		_trigger_event(&"queue_pressure", false)
	_queue_pressure_active = pressure_now


func _update_event_detection(frame_ms: float, delta: float, tainted: bool) -> void:
	if tainted:
		return
	if _baseline_ms <= 0.0:
		_baseline_ms = frame_ms
	else:
		var bounded_sample: float = minf(frame_ms, _baseline_ms * 2.0)
		_baseline_ms = lerpf(_baseline_ms, bounded_sample, BASELINE_SMOOTHING)

	if frame_ms > SUSTAINED_SLOW_THRESHOLD_MS:
		_slow_elapsed += delta
	else:
		_slow_elapsed = maxf(_slow_elapsed - delta * 2.0, 0.0)
		if _slow_elapsed <= 0.0:
			_slow_event_active = false
	if not _slow_event_active and _slow_elapsed >= SUSTAINED_SLOW_SECONDS:
		_slow_event_active = true
		_trigger_event(&"sustained_slow", false)

	if _sample_count >= WARMUP_FRAMES and frame_ms >= SPIKE_MINIMUM_MS \
			and frame_ms >= _baseline_ms * SPIKE_BASELINE_MULTIPLIER:
		_trigger_event(&"frame_spike", false)


func _trigger_event(reason: StringName, is_manual: bool) -> void:
	if _events.size() >= MAX_EVENT_RECORDS:
		if is_manual:
			notification_requested.emit(&"UI_PERF_EVENT_LIMIT_REACHED", { })
		return
	var now_usec: int = Time.get_ticks_usec()
	if not is_manual:
		if _automatic_capture_count >= MAX_AUTOMATIC_CAPTURES:
			return
		if _last_capture_usec >= 0 and float(now_usec - _last_capture_usec) / 1_000_000.0 \
				< CAPTURE_COOLDOWN_SECONDS:
			return
	var event_index: int = _events.size()
	var event_data: Dictionary = _build_diagnostic_snapshot(reason)
	event_data["event_index"] = event_index + 1
	event_data["manual"] = is_manual
	event_data["capture_status"] = "pending"
	_events.append(event_data)
	# Bounds apply to diagnostic events even when a viewport is unavailable. In
	# headless runs this prevents one repeated spike from growing the sidecar list
	# for every remaining sample in the session.
	if not is_manual:
		_automatic_capture_count += 1
	_last_capture_usec = now_usec
	if not _can_capture_viewport():
		_events[event_index]["capture_status"] = "skipped_headless"
		return
	_request_event_capture(event_index)


func _request_event_capture(event_index: int) -> void:
	if _capture_in_progress or _worker_task_id != INVALID_TASK_ID:
		_events[event_index]["capture_status"] = "skipped_busy"
		return
	_capture_in_progress = true
	_capture_event_after_draw(event_index)


func _capture_event_after_draw(event_index: int) -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or event_index < 0 or event_index >= _events.size():
		_capture_in_progress = false
		return
	var image: Image = get_viewport().get_texture().get_image()
	_mark_capture_taint()
	var reason: String = String(_events[event_index].get("reason", "event"))
	var is_manual: bool = bool(_events[event_index].get("manual", false))
	var basename: String = "%04d_%s" % [event_index + 1, _sanitize_filename(reason)]
	var png_path: String = "%s/events/%s.png" % [_session_dir, basename]
	var json_path: String = "%s/events/%s.json" % [_session_dir, basename]
	_events[event_index]["png"] = png_path
	_events[event_index]["sidecar"] = json_path
	_events[event_index]["capture_status"] = "writing"
	_schedule_capture_worker(
		image,
		png_path,
		json_path,
		_events[event_index],
		is_manual,
		event_index,
	)


func _capture_manual_after_draw(manual_dir: String, absolute_dir: String) -> void:
	# Viewport timing is not populated in the frame where measurement is enabled.
	# Warm it across a few real draws so a standalone F2 contains actionable
	# render CPU/GPU values instead of deterministic zeroes.
	await _await_render_measurement_warmup()
	if not is_inside_tree():
		_capture_in_progress = false
		return
	_refresh_context_snapshot()
	var image: Image = get_viewport().get_texture().get_image()
	_mark_capture_taint()
	var snapshot: Dictionary = _build_diagnostic_snapshot(&"manual")
	snapshot["artifact_directory"] = absolute_dir
	snapshot["capture_taint_frames_after_readback"] = CAPTURE_TAINT_FRAMES
	var png_path: String = "%s/snapshot.png" % manual_dir
	var json_path: String = "%s/snapshot.json" % manual_dir
	_schedule_capture_worker(image, png_path, json_path, snapshot, true)
	_end_manual_observation()
	if not _is_recording:
		_set_render_measurement_enabled(false)


func _schedule_capture_worker(
		image: Image,
		png_path: String,
		json_path: String,
		snapshot: Dictionary,
		is_manual: bool,
		event_index: int = -1,
	) -> void:
	var payload: Dictionary = {
		"image": image,
		"png_path": ProjectSettings.globalize_path(png_path),
		"json_path": ProjectSettings.globalize_path(json_path),
		"snapshot": snapshot.duplicate(true),
		"manual": is_manual,
		"capture_root": ProjectSettings.globalize_path(_capture_root),
		"current_directory": (
			_session_absolute_dir
			if _is_recording
			else ProjectSettings.globalize_path(png_path).get_base_dir()
		),
	}
	_worker_kind = &"capture"
	_worker_context = {
		"manual": is_manual,
		"directory": ProjectSettings.globalize_path(png_path).get_base_dir(),
		"png_path": ProjectSettings.globalize_path(png_path),
		"json_path": ProjectSettings.globalize_path(json_path),
		"event_index": event_index,
	}
	_worker_task_id = WorkerThreadPool.add_task(
		_artifact_writer.write_capture.bind(payload),
		false,
		"performance_capture",
	)


func _poll_worker() -> void:
	if _worker_task_id == INVALID_TASK_ID \
			or not WorkerThreadPool.is_task_completed(_worker_task_id):
		return
	var completed_kind: StringName = _worker_kind
	var wait_error: Error = WorkerThreadPool.wait_for_task_completion(_worker_task_id)
	var completed_context: Dictionary = _worker_context.duplicate(true)
	_worker_task_id = INVALID_TASK_ID
	_worker_kind = &""
	_worker_context.clear()
	if completed_kind == &"capture":
		_capture_in_progress = false
		var capture_ok: bool = wait_error == OK \
				and FileAccess.file_exists(String(completed_context.get("png_path", ""))) \
				and FileAccess.file_exists(String(completed_context.get("json_path", "")))
		if capture_ok:
			_capture_count += 1
			var event_index: int = int(completed_context.get("event_index", -1))
			if event_index >= 0 and event_index < _events.size():
				_events[event_index]["capture_status"] = "saved"
			if bool(completed_context.get("manual", false)):
				notification_requested.emit(
					&"UI_PERF_CAPTURE_SAVED",
					{"path": String(completed_context.get("directory", ""))},
				)
		else:
			var failed_event_index: int = int(
				completed_context.get("event_index", -1),
			)
			if failed_event_index >= 0 and failed_event_index < _events.size():
				_events[failed_event_index]["capture_status"] = "failed"
			notification_requested.emit(
				&"UI_PERF_CAPTURE_FAILED",
				{
					"error": error_string(wait_error)
					if wait_error != OK
					else "artifact file missing",
				},
			)
		if _pending_manual_capture:
			_pending_manual_capture = false
			capture_manual_snapshot()
		elif _stop_requested:
			_finalize_recording()
		state_changed.emit()
	elif completed_kind == &"session":
		_is_saving = false
		var saved_path: String = String(
			completed_context.get("directory", _session_absolute_dir),
		)
		var session_ok: bool = wait_error == OK \
				and FileAccess.file_exists(saved_path.path_join("session.json")) \
				and FileAccess.file_exists(saved_path.path_join("trace.csv"))
		if session_ok:
			notification_requested.emit(
				&"UI_PERF_RECORDING_SAVED",
				{"path": saved_path},
			)
		else:
			notification_requested.emit(
				&"UI_PERF_CAPTURE_FAILED",
				{
					"error": error_string(wait_error)
					if wait_error != OK
					else "session artifact missing",
				},
			)
		_trace_data = PackedFloat64Array()
		_events.clear()
		state_changed.emit()


func _finalize_recording() -> void:
	if not _is_recording or _is_saving or _worker_task_id != INVALID_TASK_ID \
			or _capture_in_progress:
		return
	_is_recording = false
	_is_saving = true
	_stop_requested = false
	_end_observation()
	_set_render_measurement_enabled(false)
	var payload: Dictionary = _build_session_payload()
	_trace_data = PackedFloat64Array()
	_worker_kind = &"session"
	_worker_context = {"directory": _session_absolute_dir}
	_worker_task_id = WorkerThreadPool.add_task(
		_artifact_writer.write_session.bind(payload),
		false,
		"performance_trace_write",
	)
	state_changed.emit()
	notification_requested.emit(&"UI_PERF_RECORDING_SAVING", { })


func _build_session_payload() -> Dictionary:
	_session_metadata["ended_at"] = Time.get_datetime_string_from_system(true)
	_session_metadata["capture_count"] = _capture_count
	_session_metadata["automatic_capture_count"] = _automatic_capture_count
	return {
		"columns": TRACE_COLUMNS,
		"stride": TRACE_STRIDE,
		"sample_count": _sample_count,
		"trace_data": _trace_data,
		"events": _events.duplicate(true),
		"metadata": _session_metadata.duplicate(true),
		"session_dir": _session_absolute_dir,
		"capture_root": ProjectSettings.globalize_path(_capture_root),
	}


func _settle_capture_worker_on_exit(context: Dictionary, wait_error: Error) -> void:
	_capture_in_progress = false
	var capture_ok: bool = wait_error == OK \
			and FileAccess.file_exists(String(context.get("png_path", ""))) \
			and FileAccess.file_exists(String(context.get("json_path", "")))
	var event_index: int = int(context.get("event_index", -1))
	if capture_ok:
		_capture_count += 1
	if event_index >= 0 and event_index < _events.size():
		_events[event_index]["capture_status"] = "saved" if capture_ok else "failed"


func _mark_unfinished_events_interrupted() -> void:
	for event: Dictionary in _events:
		var status: String = String(event.get("capture_status", ""))
		if status == "pending" or status == "writing":
			event["capture_status"] = "interrupted_shutdown"


func _build_diagnostic_snapshot(reason: StringName) -> Dictionary:
	var player: CharacterBody2D = _get_local_player()
	var player_position: Vector2 = Vector2.ZERO
	var player_velocity: Vector2 = Vector2.ZERO
	var camera_zoom: float = 0.0
	if player != null:
		player_position = player.global_position
		player_velocity = player.velocity
		var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			camera_zoom = camera.zoom.x
	var live_snapshot: Dictionary = WorldPerfProbe.copy_completed_live_frame_snapshot()
	var player_chunk: Vector2i = _context_snapshot.get(
		"player_chunk",
		Vector2i.ZERO,
	) as Vector2i
	return {
		"schema_version": 1,
		"reason": String(reason),
		"timestamp": Time.get_datetime_string_from_system(true),
		"frame": Engine.get_process_frames(),
		"sample_index": _sample_count,
		"player": {
			"x": player_position.x,
			"y": player_position.y,
			"velocity_x": player_velocity.x,
			"velocity_y": player_velocity.y,
			"chunk_x": player_chunk.x,
			"chunk_y": player_chunk.y,
		},
		"camera_zoom": camera_zoom,
		"frame_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		"physics_ms": float(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		) * 1000.0,
		"viewport_cpu_ms": _get_viewport_render_time(
			"viewport_get_measured_render_time_cpu",
		),
		"viewport_gpu_ms": _get_viewport_render_time(
			"viewport_get_measured_render_time_gpu",
		),
		"frame_setup_cpu_ms": _get_frame_setup_time_cpu(),
		"draw_calls": int(
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		),
		"render_objects": int(
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		),
		"render_primitives": int(
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		),
		"postprocess_enabled": _is_postprocess_enabled(),
		"streaming": _sanitize_dictionary(_context_snapshot),
		"live_ops": _sanitize_dictionary(
			live_snapshot.get("ops", { }) as Dictionary,
		),
		"environment": _build_environment_metadata(),
	}


func _build_environment_metadata() -> Dictionary:
	var metadata: Dictionary = {
		"schema_version": 1,
		"engine_version": Engine.get_version_info(),
		"engine_max_fps": Engine.max_fps,
		"vsync_mode": int(DisplayServer.window_get_vsync_mode()),
		"refresh_rate_hz": DisplayServer.screen_get_refresh_rate(),
		"window_width": DisplayServer.window_get_size().x,
		"window_height": DisplayServer.window_get_size().y,
		"editor_run": OS.has_feature("editor"),
		"debug_build": OS.has_feature("debug"),
	}
	for method_name: String in [
		"get_current_rendering_method",
		"get_current_rendering_driver_name",
		"get_video_adapter_name",
		"get_video_adapter_vendor",
	]:
		if RenderingServer.has_method(method_name):
			metadata[method_name] = RenderingServer.call(method_name)
	return _sanitize_dictionary(metadata)


func _begin_observation() -> void:
	if _observer_active:
		return
	WorldPerfProbe.begin_live_observation()
	_observer_active = true


func _end_observation() -> void:
	if not _observer_active:
		return
	WorldPerfProbe.end_live_observation()
	_observer_active = false


func _begin_manual_observation() -> void:
	if _manual_observer_active:
		return
	WorldPerfProbe.begin_live_observation()
	_manual_observer_active = true


func _end_manual_observation() -> void:
	if not _manual_observer_active:
		return
	WorldPerfProbe.end_live_observation()
	_manual_observer_active = false


func _set_render_measurement_enabled(enabled: bool) -> void:
	if not _viewport_rid.is_valid() \
			or not RenderingServer.has_method("viewport_set_measure_render_time"):
		return
	RenderingServer.call("viewport_set_measure_render_time", _viewport_rid, enabled)


func _await_render_measurement_warmup() -> void:
	for _frame_index: int in range(RENDER_MEASUREMENT_WARMUP_FRAMES):
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
		await RenderingServer.frame_post_draw


func _mark_capture_taint() -> void:
	_capture_taint_until_frame = maxi(
		_capture_taint_until_frame,
		int(Engine.get_process_frames()) + CAPTURE_TAINT_FRAMES,
	)


func _get_viewport_render_time(method_name: String) -> float:
	if not _viewport_rid.is_valid() or not RenderingServer.has_method(method_name):
		return 0.0
	return maxf(float(RenderingServer.call(method_name, _viewport_rid)), 0.0)


func _get_frame_setup_time_cpu() -> float:
	if not RenderingServer.has_method("get_frame_setup_time_cpu"):
		return 0.0
	return maxf(float(RenderingServer.call("get_frame_setup_time_cpu")), 0.0)


func _get_live_op(frame_ops: Dictionary, metric_name: String) -> float:
	var label: String = String(LIVE_OP_KEYS.get(metric_name, ""))
	return maxf(float(frame_ops.get(label, 0.0)), 0.0)


func _is_postprocess_enabled() -> bool:
	return _postprocess_overlay != null \
			and is_instance_valid(_postprocess_overlay) \
			and _postprocess_overlay.has_method("get_postprocess_enabled") \
			and bool(_postprocess_overlay.call("get_postprocess_enabled"))


func _can_capture_viewport() -> bool:
	return DisplayServer.get_name().to_lower() != "headless"


func _get_local_player() -> CharacterBody2D:
	var authority: Node = get_node_or_null("/root/PlayerAuthority")
	if authority == null or not authority.has_method("get_local_player"):
		return null
	return authority.call("get_local_player") as CharacterBody2D


func _make_timestamp() -> String:
	# Derive the calendar fields and millisecond suffix from the same wall-clock
	# sample. `ticks_msec() % 1000` is monotonic but not aligned to wall-clock
	# seconds, which can make two folders created in one second sort backwards.
	var unix_millis: int = int(floor(Time.get_unix_time_from_system() * 1000.0))
	var timezone: Dictionary = Time.get_time_zone_from_system()
	var local_unix_seconds: int = floori(float(unix_millis) / 1000.0) \
			+ int(timezone.get("bias", 0)) * 60
	var value: Dictionary = Time.get_datetime_dict_from_unix_time(local_unix_seconds)
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(value.get("year", 0)),
		int(value.get("month", 0)),
		int(value.get("day", 0)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
		int(value.get("second", 0)),
		posmod(unix_millis, 1000),
	]


func _sanitize_filename(value: String) -> String:
	var result: String = value.to_lower()
	for character: String in ["/", "\\", ":", " ", "."]:
		result = result.replace(character, "_")
	return result


func _sanitize_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = { }
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		var value: Variant = source.get(key_variant)
		if value is Vector2i:
			var vector_i: Vector2i = value as Vector2i
			result[key] = {"x": vector_i.x, "y": vector_i.y}
		elif value is Vector2:
			var vector: Vector2 = value as Vector2
			result[key] = {"x": vector.x, "y": vector.y}
		elif value is Dictionary:
			result[key] = _sanitize_dictionary(value as Dictionary)
		elif value is Array:
			result[key] = _sanitize_array(value as Array)
		elif value is StringName:
			result[key] = String(value)
		else:
			result[key] = value
	return result


func _sanitize_array(source: Array) -> Array:
	var result: Array = []
	for value: Variant in source:
		if value is Dictionary:
			result.append(_sanitize_dictionary(value as Dictionary))
		elif value is Vector2i:
			var vector_i: Vector2i = value as Vector2i
			result.append({"x": vector_i.x, "y": vector_i.y})
		elif value is Vector2:
			var vector: Vector2 = value as Vector2
			result.append({"x": vector.x, "y": vector.y})
		elif value is StringName:
			result.append(String(value))
		else:
			result.append(value)
	return result
