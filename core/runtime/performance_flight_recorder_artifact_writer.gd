class_name PerformanceFlightRecorderArtifactWriter
extends RefCounted
## Worker-only artifact serialization for PerformanceFlightRecorder.
## Methods receive immutable payloads and never touch SceneTree or render state.


func write_capture(payload: Dictionary) -> Dictionary:
	var image: Image = payload.get("image") as Image
	var png_path: String = String(payload.get("png_path", ""))
	var json_path: String = String(payload.get("json_path", ""))
	if image == null or image.is_empty():
		return {
			"ok": false,
			"manual": bool(payload.get("manual", false)),
			"error": "empty viewport image",
		}
	var png_error: Error = image.save_png(png_path)
	if png_error != OK:
		return {
			"ok": false,
			"manual": bool(payload.get("manual", false)),
			"error": error_string(png_error),
		}
	var file: FileAccess = FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"manual": bool(payload.get("manual", false)),
			"error": error_string(FileAccess.get_open_error()),
		}
	file.store_string(JSON.stringify(payload.get("snapshot", { }), "  "))
	file.close()
	_trim_capture_sessions(
		String(payload.get("capture_root", "")),
		String(payload.get("current_directory", "")),
		8,
	)
	return {
		"ok": true,
		"manual": bool(payload.get("manual", false)),
		"directory": png_path.get_base_dir(),
	}


func write_session(payload: Dictionary) -> Dictionary:
	var session_dir: String = String(payload.get("session_dir", ""))
	var sample_count: int = int(payload.get("sample_count", 0))
	var stride: int = int(payload.get("stride", 0))
	var columns: Array = payload.get("columns", []) as Array
	var trace_data: PackedFloat64Array = payload.get(
		"trace_data",
		PackedFloat64Array(),
	) as PackedFloat64Array
	if session_dir.is_empty() or stride <= 0 or columns.size() != stride:
		return {"ok": false, "directory": session_dir, "error": "invalid trace payload"}
	var trace_path: String = session_dir.path_join("trace.csv")
	var trace_file: FileAccess = FileAccess.open(trace_path, FileAccess.WRITE)
	if trace_file == null:
		return {
			"ok": false,
			"directory": session_dir,
			"error": error_string(FileAccess.get_open_error()),
		}
	var header: PackedStringArray = PackedStringArray()
	for column_variant: Variant in columns:
		header.append(String(column_variant))
	trace_file.store_csv_line(header)
	for sample_index: int in range(sample_count):
		var row: PackedStringArray = PackedStringArray()
		var offset: int = sample_index * stride
		for column_index: int in range(stride):
			row.append("%.6f" % trace_data[offset + column_index])
		trace_file.store_csv_line(row)
	trace_file.close()

	var summary: Dictionary = payload.get("metadata", { }) as Dictionary
	summary["sample_count"] = sample_count
	summary["trace_columns"] = columns
	summary["events"] = payload.get("events", [])
	summary["statistics"] = _calculate_trace_statistics(
		trace_data,
		sample_count,
		stride,
		columns,
	)
	var session_file: FileAccess = FileAccess.open(
		session_dir.path_join("session.json"),
		FileAccess.WRITE,
	)
	if session_file == null:
		return {
			"ok": false,
			"directory": session_dir,
			"error": error_string(FileAccess.get_open_error()),
		}
	session_file.store_string(JSON.stringify(summary, "  "))
	session_file.close()
	_trim_capture_sessions(String(payload.get("capture_root", "")), session_dir, 8)
	return {"ok": true, "directory": session_dir}


func _calculate_trace_statistics(
		trace_data: PackedFloat64Array,
		sample_count: int,
		stride: int,
		columns: Array,
	) -> Dictionary:
	var frame_index: int = columns.find("frame_ms")
	var taint_index: int = columns.find("capture_tainted")
	var gpu_index: int = columns.find("viewport_gpu_ms")
	var cpu_index: int = columns.find("viewport_cpu_ms")
	var setup_index: int = columns.find("frame_setup_cpu_ms")
	var draw_index: int = columns.find("draw_calls")
	var render_object_index: int = columns.find("render_objects")
	var object_queue_index: int = columns.find("object_upload_queue")
	var visibility_index: int = columns.find("visibility_wait")
	var player_x_index: int = columns.find("player_x")
	var player_y_index: int = columns.find("player_y")
	var frames: Array[float] = []
	var total_ms: float = 0.0
	var max_frame_ms: float = 0.0
	var max_gpu_ms: float = 0.0
	var max_cpu_ms: float = 0.0
	var max_setup_ms: float = 0.0
	var max_draw_calls: int = 0
	var max_render_objects: int = 0
	var max_object_queue: int = 0
	var max_visibility_wait: int = 0
	var start_position: Vector2 = Vector2.ZERO
	var end_position: Vector2 = Vector2.ZERO
	for sample_index: int in range(sample_count):
		var offset: int = sample_index * stride
		if sample_index == 0:
			start_position = Vector2(
				trace_data[offset + player_x_index],
				trace_data[offset + player_y_index],
			)
		end_position = Vector2(
			trace_data[offset + player_x_index],
			trace_data[offset + player_y_index],
		)
		max_gpu_ms = maxf(max_gpu_ms, trace_data[offset + gpu_index])
		max_cpu_ms = maxf(max_cpu_ms, trace_data[offset + cpu_index])
		max_setup_ms = maxf(max_setup_ms, trace_data[offset + setup_index])
		max_draw_calls = maxi(max_draw_calls, int(trace_data[offset + draw_index]))
		max_render_objects = maxi(
			max_render_objects,
			int(trace_data[offset + render_object_index]),
		)
		max_object_queue = maxi(
			max_object_queue,
			int(trace_data[offset + object_queue_index]),
		)
		max_visibility_wait = maxi(
			max_visibility_wait,
			int(trace_data[offset + visibility_index]),
		)
		if trace_data[offset + taint_index] > 0.5:
			continue
		var frame_ms: float = trace_data[offset + frame_index]
		frames.append(frame_ms)
		total_ms += frame_ms
		max_frame_ms = maxf(max_frame_ms, frame_ms)
	frames.sort()
	var average_ms: float = total_ms / float(maxi(frames.size(), 1))
	var p95_ms: float = _percentile_sorted(frames, 0.95)
	var p99_ms: float = _percentile_sorted(frames, 0.99)
	return {
		"clean_sample_count": frames.size(),
		"average_frame_ms": average_ms,
		"average_fps": 1000.0 / maxf(average_ms, 0.001),
		"p95_frame_ms": p95_ms,
		"p99_frame_ms": p99_ms,
		"one_percent_low_fps": 1000.0 / maxf(p99_ms, 0.001),
		"max_frame_ms": max_frame_ms,
		"max_viewport_gpu_ms": max_gpu_ms,
		"max_viewport_cpu_ms": max_cpu_ms,
		"max_frame_setup_cpu_ms": max_setup_ms,
		"max_draw_calls": max_draw_calls,
		"max_render_objects": max_render_objects,
		"max_object_upload_queue": max_object_queue,
		"max_visibility_wait": max_visibility_wait,
		"straight_line_distance_px": start_position.distance_to(end_position),
		"start_position": {"x": start_position.x, "y": start_position.y},
		"end_position": {"x": end_position.x, "y": end_position.y},
	}


func _percentile_sorted(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var index: int = clampi(
		ceili(clampf(percentile, 0.0, 1.0) * float(values.size())) - 1,
		0,
		values.size() - 1,
	)
	return values[index]


func _trim_capture_sessions(
		capture_root: String,
		current_session: String,
		max_sessions: int,
	) -> void:
	if capture_root.is_empty():
		return
	var root: DirAccess = DirAccess.open(capture_root)
	if root == null:
		return
	var directories: Array[String] = []
	for directory_name: String in root.get_directories():
		directories.append(directory_name)
	# F4 uses `<timestamp>` while standalone F2 uses `manual_<timestamp>`.
	# Compare their normalized timestamp portions so retention is chronological,
	# not grouped by prefix.
	directories.sort_custom(
		func(a: String, b: String) -> bool:
			return _capture_directory_sort_key(a) < _capture_directory_sort_key(b)
	)
	var excess: int = maxi(directories.size() - max_sessions, 0)
	var removed: int = 0
	for directory_name: String in directories:
		if removed >= excess:
			break
		var candidate: String = capture_root.path_join(directory_name).simplify_path()
		if candidate == current_session.simplify_path():
			continue
		_remove_directory_recursive(candidate)
		removed += 1


func _capture_directory_sort_key(directory_name: String) -> String:
	if directory_name.begins_with("manual_"):
		return directory_name.substr("manual_".length())
	return directory_name


func _remove_directory_recursive(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for child_name: String in directory.get_directories():
		_remove_directory_recursive(path.path_join(child_name))
	DirAccess.remove_absolute(path)
