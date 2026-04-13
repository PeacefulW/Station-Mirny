class_name ChunkDebugSystem
extends RefCounted

const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")

const TASK_FIRST_PASS: int = 0
const TASK_FULL_REDRAW: int = 1
const TASK_BORDER_FIX: int = 2
const TASK_COSMETIC: int = 3

const BAND_COSMETIC: int = 7

const DEBUG_FORENSICS_INCIDENT_LIMIT: int = 6
const DEBUG_FORENSICS_TRACE_EVENT_LIMIT: int = 24
const DEBUG_FORENSICS_TRACE_UI_LIMIT: int = 12
const DEBUG_FORENSICS_TASK_ROW_LIMIT: int = 10
const DEBUG_FORENSICS_CHUNK_ROW_LIMIT: int = 8
const DEBUG_FORENSICS_ACTIVE_TTL_MS: float = 15000.0
const DEBUG_FORENSICS_CONTEXT_TTL_MS: float = 12000.0
const DEBUG_FORENSICS_EVENT_DEDUPE_MS: float = 220.0
const DEBUG_FORENSICS_FULL_FAR_PRESSURE_THRESHOLD: int = 12
const DEBUG_FORENSICS_OWNER_STUCK_MS: float = 1500.0

var _owner: Node = null
var _hot_path_forensics_enabled: bool = false
var _next_incident_id: int = 0
var _next_trace_id: int = 0
var _forensics_incidents: Dictionary = {}
var _forensics_incident_order: Array[int] = []
var _active_incident_id: int = -1
var _chunk_trace_contexts: Dictionary = {}
var _visual_task_meta: Dictionary = {}

func setup(owner: Node, hot_path_forensics_enabled: bool = false) -> void:
	_owner = owner
	_hot_path_forensics_enabled = hot_path_forensics_enabled

func _visual_scheduler() -> ChunkVisualScheduler:
	if _owner == null:
		return null
	return _owner._get_visual_scheduler()

func _active_z() -> int:
	return _owner.get_active_z_level()

func _player_chunk_coord() -> Vector2i:
	return _owner._get_player_chunk_coord()

func _player_chunk_motion() -> Vector2i:
	return _owner._get_player_chunk_motion()

func _canonical_chunk_coord(coord: Vector2i) -> Vector2i:
	return _owner._canonical_chunk_coord(coord)

func _make_visual_chunk_key(coord: Vector2i, z_level: int) -> String:
	return _owner._make_visual_chunk_key(coord, z_level)

func _format_visual_task_key(task_key: Vector4i) -> String:
	return _owner._format_visual_task_key(task_key)

func _chunk_priority_less(a: Vector2i, b: Vector2i, center: Vector2i) -> bool:
	return _owner._chunk_priority_less(a, b, center)

func _debug_is_incident_worthy_coord(coord: Vector2i, z_level: int) -> bool:
	return _owner._debug_is_incident_worthy_coord(coord, z_level)

func _loaded_chunks() -> Dictionary:
	return _owner.get_loaded_chunks()

func _loaded_chunks_for_z(z_level: int) -> Dictionary:
	return _owner._get_loaded_chunks_for_z(z_level)

func _debug_build_chunk_entry(
	coord: Vector2i,
	z_level: int,
	chunk: Chunk,
	lookups: Dictionary,
	now_usec: int
) -> Dictionary:
	return _owner._debug_build_chunk_entry(coord, z_level, chunk, lookups, now_usec)

func _chunk_chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return _owner._chunk_chebyshev_distance(a, b)

func _append_unique_chunk_coord(coords: Array[Vector2i], coord: Vector2i) -> void:
	_owner._append_unique_chunk_coord(coords, coord)

func _visual_queue_size(queue_name: StringName) -> int:
	var scheduler: ChunkVisualScheduler = _visual_scheduler()
	if scheduler == null:
		return 0
	match queue_name:
		&"full_far":
			return scheduler.q_full_far.size()
		&"border_fix_near":
			return scheduler.q_border_fix_near.size()
		&"full_near":
			return scheduler.q_full_near.size()
		_:
			return 0

func _has_live_visual_task(task_key: Vector4i) -> bool:
	var scheduler: ChunkVisualScheduler = _visual_scheduler()
	if scheduler == null:
		return false
	return scheduler.task_pending.has(task_key) \
		or scheduler.compute_active.has(task_key) \
		or scheduler.compute_waiting_tasks.has(task_key)

func _visual_task_status(task_key: Vector4i) -> String:
	var scheduler: ChunkVisualScheduler = _visual_scheduler()
	if scheduler == null:
		return "queued"
	if scheduler.compute_active.has(task_key):
		return "worker_active"
	if scheduler.compute_waiting_tasks.has(task_key):
		return "worker_waiting"
	return "queued"

func _visual_task_version(task_key: Vector4i) -> int:
	var scheduler: ChunkVisualScheduler = _visual_scheduler()
	if scheduler == null:
		return -1
	return int(scheduler.task_pending.get(task_key, -1))

func _visual_task_enqueue_usec(task_key: Vector4i, fallback_usec: int) -> int:
	var scheduler: ChunkVisualScheduler = _visual_scheduler()
	if scheduler == null:
		return fallback_usec
	return int(scheduler.task_enqueued_usec.get(task_key, fallback_usec))

func _visual_queues_in_priority_order() -> Array[Array]:
	var scheduler: ChunkVisualScheduler = _visual_scheduler()
	if scheduler == null:
		return []
	return scheduler.ordered_queues()

func is_hot_path_forensics_enabled() -> bool:
	return _hot_path_forensics_enabled

func clear_runtime_state() -> void:
	_next_incident_id = 0
	_next_trace_id = 0
	_forensics_incidents.clear()
	_forensics_incident_order.clear()
	_active_incident_id = -1
	_chunk_trace_contexts.clear()
	_visual_task_meta.clear()

func clear_visual_task_meta() -> void:
	_visual_task_meta.clear()

func get_active_incident(now_usec: int) -> Dictionary:
	return _get_active_incident(now_usec)

func get_visual_task_meta(task_key: Vector4i) -> Dictionary:
	return (_visual_task_meta.get(task_key, {}) as Dictionary).duplicate(true)

func update_visual_task_band(task_key: Vector4i, band: int) -> void:
	var meta: Dictionary = _visual_task_meta.get(task_key, {}) as Dictionary
	if meta.is_empty():
		return
	meta["band"] = band
	_visual_task_meta[task_key] = meta

func resolve_chunk_trace_context(coord: Vector2i, z_level: int, now_usec: int = -1) -> Dictionary:
	if now_usec < 0:
		now_usec = Time.get_ticks_usec()
	var key: String = _make_visual_chunk_key(_canonical_chunk_coord(coord), z_level)
	var trace_context: Dictionary = _chunk_trace_contexts.get(key, {}) as Dictionary
	if not _is_valid_trace_context(trace_context, now_usec):
		_chunk_trace_contexts.erase(key)
		return {}
	return _duplicate_trace_context(trace_context)

func record_forensics_event(
	trace_context: Dictionary,
	source_system: String,
	event_key: String,
	coord: Vector2i,
	z_level: int,
	detail_fields: Dictionary = {},
	target_chunks: Array[Vector2i] = []
) -> Dictionary:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	if trace_context.is_empty():
		return _begin_forensics_trace(
			source_system,
			event_key,
			canonical_coord,
			z_level,
			target_chunks,
			detail_fields
		)
	return _register_forensics_event(
		trace_context,
		source_system,
		event_key,
		canonical_coord,
		z_level,
		detail_fields,
		target_chunks
	)

func ensure_forensics_context(
	coord: Vector2i,
	z_level: int,
	source_system: String,
	event_key: String,
	detail_fields: Dictionary = {},
	target_chunks: Array[Vector2i] = []
) -> Dictionary:
	var now_usec: int = Time.get_ticks_usec()
	var existing_context: Dictionary = resolve_chunk_trace_context(coord, z_level, now_usec)
	if not existing_context.is_empty():
		return existing_context
	if not _debug_is_incident_worthy_coord(coord, z_level):
		return {}
	return _begin_forensics_trace(
		source_system,
		event_key,
		coord,
		z_level,
		target_chunks,
		detail_fields
	)

func enrich_record_with_trace(
	record: Dictionary,
	detail_fields: Dictionary,
	coord: Vector2i,
	z_level: int,
	trace_context: Dictionary = {}
) -> Dictionary:
	var resolved_context: Dictionary = trace_context
	if resolved_context.is_empty():
		resolved_context = resolve_chunk_trace_context(coord, z_level)
	if resolved_context.is_empty():
		return {}
	var trace_id: String = str(resolved_context.get("trace_id", ""))
	var incident_id: int = int(resolved_context.get("incident_id", -1))
	if trace_id.is_empty() or incident_id < 0:
		return {}
	record["trace_id"] = trace_id
	record["incident_id"] = incident_id
	detail_fields["trace_id"] = trace_id
	detail_fields["incident_id"] = incident_id
	detail_fields["trace_source"] = str(resolved_context.get("source_system", ""))
	return resolved_context

func prune_forensics_state(now_usec: int) -> void:
	if _active_incident_id >= 0:
		var active_incident: Dictionary = _forensics_incidents.get(_active_incident_id, {}) as Dictionary
		if active_incident.is_empty() \
			or _owner._debug_age_ms(active_incident.get("updated_usec", 0), now_usec) > DEBUG_FORENSICS_ACTIVE_TTL_MS:
			_active_incident_id = -1
		else:
			active_incident["state"] = "active"
			_forensics_incidents[_active_incident_id] = active_incident
	for chunk_key_variant: Variant in _chunk_trace_contexts.keys():
		var chunk_key: String = str(chunk_key_variant)
		var trace_context: Dictionary = _chunk_trace_contexts.get(chunk_key, {}) as Dictionary
		if _is_valid_trace_context(trace_context, now_usec):
			continue
		_chunk_trace_contexts.erase(chunk_key)
	var retained_ids: Array[int] = []
	for incident_id: int in _forensics_incident_order:
		var incident: Dictionary = _forensics_incidents.get(incident_id, {}) as Dictionary
		if incident.is_empty():
			continue
		var age_ms: float = _owner._debug_age_ms(incident.get("updated_usec", 0), now_usec)
		if incident_id != _active_incident_id and age_ms > DEBUG_FORENSICS_ACTIVE_TTL_MS * 3.0:
			_forensics_incidents.erase(incident_id)
			continue
		if incident_id != _active_incident_id and age_ms > DEBUG_FORENSICS_ACTIVE_TTL_MS:
			incident["state"] = "recent"
			_forensics_incidents[incident_id] = incident
		retained_ids.append(incident_id)
	while retained_ids.size() > DEBUG_FORENSICS_INCIDENT_LIMIT:
		var retired_id: int = retained_ids.pop_front()
		if retired_id == _active_incident_id:
			retained_ids.append(retired_id)
			break
		_forensics_incidents.erase(retired_id)
	_forensics_incident_order = retained_ids

func build_incident_summary(metrics: Dictionary, now_usec: int) -> Dictionary:
	var incident: Dictionary = _get_active_incident(now_usec)
	if incident.is_empty():
		return {
			"status": "no_active_incident",
			"state_label": "no_active_incident",
			"trace_id": "",
			"incident_id": -1,
			"age_ms": -1.0,
			"updated_age_ms": -1.0,
			"source_system": "",
			"stage": "",
			"player_chunk": _canonical_chunk_coord(_player_chunk_coord()),
			"primary_chunk": Vector2i(999999, 999999),
			"target_chunks": [],
			"event_count": 0,
			"chunk_count": 0,
			"queue_full_far": _visual_queue_size(&"full_far"),
			"queue_border_fix_near": _visual_queue_size(&"border_fix_near"),
			"queue_full_near": _visual_queue_size(&"full_near"),
			"shadow_ms": float(((metrics.get("perf", {}) as Dictionary).get("categories", {}) as Dictionary).get("shadow", 0.0)),
		}
	var touched_chunks: Dictionary = incident.get("chunks", {}) as Dictionary
	var target_chunks: Array = incident.get("target_chunks", []) as Array
	return {
		"status": str(incident.get("state", "active")),
		"state_label": "active",
		"trace_id": str(incident.get("trace_id", "")),
		"incident_id": int(incident.get("incident_id", -1)),
		"age_ms": _owner._debug_age_ms(incident.get("started_usec", 0), now_usec),
		"updated_age_ms": _owner._debug_age_ms(incident.get("updated_usec", 0), now_usec),
		"source_system": str(incident.get("source_system", "")),
		"stage": str(incident.get("last_stage", "")),
		"player_chunk": incident.get("player_chunk", _canonical_chunk_coord(_player_chunk_coord())),
		"primary_chunk": incident.get("primary_chunk", Vector2i(999999, 999999)),
		"target_chunks": target_chunks.duplicate(),
		"event_count": (incident.get("events", []) as Array).size(),
		"chunk_count": touched_chunks.size(),
		"queue_full_far": _visual_queue_size(&"full_far"),
		"queue_border_fix_near": _visual_queue_size(&"border_fix_near"),
		"queue_full_near": _visual_queue_size(&"full_near"),
		"shadow_ms": float(((metrics.get("perf", {}) as Dictionary).get("categories", {}) as Dictionary).get("shadow", 0.0)),
	}

func build_trace_events(incident_summary: Dictionary) -> Array[Dictionary]:
	var incident_id: int = int(incident_summary.get("incident_id", -1))
	if incident_id < 0:
		return []
	var incident: Dictionary = _forensics_incidents.get(incident_id, {}) as Dictionary
	if incident.is_empty():
		return []
	var events: Array = incident.get("events", []) as Array
	var result: Array[Dictionary] = []
	var start_index: int = maxi(0, events.size() - DEBUG_FORENSICS_TRACE_UI_LIMIT)
	for idx: int in range(start_index, events.size()):
		result.append((events[idx] as Dictionary).duplicate(true))
	return result

func build_chunk_causality_rows(
	incident_summary: Dictionary,
	lookups: Dictionary,
	now_usec: int
) -> Array[Dictionary]:
	var incident_id: int = int(incident_summary.get("incident_id", -1))
	var rows: Array[Dictionary] = []
	var seen_coords: Dictionary = {}
	var player_coord: Vector2i = _canonical_chunk_coord(_player_chunk_coord())
	if player_coord != Vector2i(99999, 99999):
		seen_coords[_make_visual_chunk_key(player_coord, _active_z())] = {
			"coord": player_coord,
			"z": _active_z(),
		}
	if incident_id >= 0:
		var incident: Dictionary = _forensics_incidents.get(incident_id, {}) as Dictionary
		var touched_chunks: Dictionary = incident.get("chunks", {}) as Dictionary
		for chunk_key_variant: Variant in touched_chunks.keys():
			var chunk_key: String = str(chunk_key_variant)
			seen_coords[chunk_key] = (touched_chunks.get(chunk_key, {}) as Dictionary).duplicate(true)
	var keys: Array[String] = []
	for chunk_key_variant: Variant in seen_coords.keys():
		keys.append(str(chunk_key_variant))
	keys.sort_custom(func(a: String, b: String) -> bool:
		var a_entry: Dictionary = seen_coords.get(a, {}) as Dictionary
		var b_entry: Dictionary = seen_coords.get(b, {}) as Dictionary
		var a_coord: Vector2i = a_entry.get("coord", Vector2i.ZERO) as Vector2i
		var b_coord: Vector2i = b_entry.get("coord", Vector2i.ZERO) as Vector2i
		return _chunk_priority_less(a_coord, b_coord, _player_chunk_coord())
	)
	for chunk_key: String in keys:
		if rows.size() >= DEBUG_FORENSICS_CHUNK_ROW_LIMIT:
			break
		var trace_entry: Dictionary = seen_coords.get(chunk_key, {}) as Dictionary
		var coord: Vector2i = trace_entry.get("coord", Vector2i.ZERO) as Vector2i
		var z_level: int = int(trace_entry.get("z", _active_z()))
		var chunk: Chunk = _loaded_chunks_for_z(z_level).get(coord) as Chunk
		var base_entry: Dictionary = _debug_build_chunk_entry(coord, z_level, chunk, lookups, now_usec)
		var pending_tasks: Array[String] = []
		for kind: int in [TASK_FIRST_PASS, TASK_FULL_REDRAW, TASK_BORDER_FIX]:
			if _owner._get_visual_task_age_ms(coord, z_level, kind) >= 0.0:
				pending_tasks.append(_owner._debug_visual_kind_name(kind))
		rows.append({
			"coord": coord,
			"z": z_level,
			"is_player_chunk": bool(base_entry.get("is_player_chunk", false)),
			"distance": int(base_entry.get("distance", -1)),
			"state": str(base_entry.get("state", "")),
			"state_human": str(base_entry.get("state_human", "")),
			"is_visible": bool(base_entry.get("is_visible", false)),
			"is_simulating": bool(base_entry.get("is_simulating", false)),
			"is_stalled": bool(base_entry.get("is_stalled", false)),
			"stage_age_ms": float(base_entry.get("stage_age_ms", -1.0)),
			"visual_phase": str(base_entry.get("visual_phase", "")),
			"pending_tasks": pending_tasks,
			"trace_age_ms": _owner._debug_age_ms(trace_entry.get("updated_usec", 0), now_usec),
			"last_event": str(trace_entry.get("last_event", "")),
			"last_source_system": str(trace_entry.get("last_source_system", "")),
			"last_state": str(trace_entry.get("last_state", "")),
		})
	return rows

func build_task_debug_rows(incident_summary: Dictionary, now_usec: int) -> Array[Dictionary]:
	var incident_id: int = int(incident_summary.get("incident_id", -1))
	if incident_id < 0:
		return []
	var rows: Array[Dictionary] = []
	for meta_variant: Variant in _visual_task_meta.values():
		var meta: Dictionary = meta_variant as Dictionary
		if int(meta.get("incident_id", -1)) != incident_id:
			continue
		var task_key_variant: Variant = meta.get("task_key", null)
		if typeof(task_key_variant) != TYPE_VECTOR4I:
			continue
		var task_key: Vector4i = task_key_variant as Vector4i
		if not _has_live_visual_task(task_key):
			continue
		var band: int = int(meta.get("band", BAND_COSMETIC))
		rows.append({
			"task_key": _format_visual_task_key(task_key),
			"coord": meta.get("coord", Vector2i.ZERO),
			"z": int(meta.get("z", _active_z())),
			"kind": str(meta.get("kind_name", "")),
			"kind_human": _owner._debug_visual_task_type_human(int(meta.get("kind", TASK_COSMETIC))),
			"band": _owner._debug_visual_band_name(band),
			"band_human": _owner._debug_visual_band_human(band),
			"version": int(meta.get("version", 0)),
			"enqueue_reason": str(meta.get("enqueue_reason", "")),
			"trace_id": str(meta.get("trace_id", "")),
			"age_ms": _owner._debug_age_ms(meta.get("enqueue_usec", 0), now_usec),
			"selected_last_tick": int(meta.get("selected_frame", -1)) == Engine.get_process_frames(),
			"requeue_count": int(meta.get("requeue_count", 0)),
			"last_skip_reason": str(meta.get("last_skip_reason", "")),
			"last_budget_state": str(meta.get("last_budget_state", "")),
			"status": _visual_task_status(task_key),
			"source_system": str(meta.get("source_system", "")),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_selected: bool = bool(a.get("selected_last_tick", false))
		var b_selected: bool = bool(b.get("selected_last_tick", false))
		if a_selected != b_selected:
			return a_selected and not b_selected
		var a_coord: Vector2i = a.get("coord", Vector2i.ZERO) as Vector2i
		var b_coord: Vector2i = b.get("coord", Vector2i.ZERO) as Vector2i
		return _chunk_priority_less(a_coord, b_coord, _player_chunk_coord())
	)
	if rows.size() > DEBUG_FORENSICS_TASK_ROW_LIMIT:
		rows.resize(DEBUG_FORENSICS_TASK_ROW_LIMIT)
	return rows

func build_suspicion_flags(
	incident_summary: Dictionary,
	trace_events: Array[Dictionary],
	chunk_causality_rows: Array[Dictionary],
	task_debug_rows: Array[Dictionary],
	metrics: Dictionary,
	now_usec: int
) -> Array[Dictionary]:
	var flags: Array[Dictionary] = []
	var player_coord: Vector2i = _canonical_chunk_coord(_player_chunk_coord())
	var immediate_patch_by_chunk: Dictionary = {}
	for event: Dictionary in trace_events:
		var event_key: String = str(event.get("event_key", ""))
		var coord: Vector2i = event.get("coord", Vector2i.ZERO) as Vector2i
		var chunk_key: String = _make_visual_chunk_key(coord, int(event.get("z", _active_z())))
		if event_key == "roof_immediate_patch_applied":
			immediate_patch_by_chunk[chunk_key] = true
		elif event_key == "roof_restore_deferred" and _debug_is_incident_worthy_coord(coord, int(event.get("z", _active_z()))):
			flags.append({
				"flag": "restore_waiting_on_border_fix",
				"label": "restore ждёт owner border_fix рядом с игроком",
				"detail": "coord=%s" % [coord],
			})
			if immediate_patch_by_chunk.has(chunk_key):
				flags.append({
					"flag": "restore_overwrites_immediate_patch",
					"label": "same trace сначала сделал immediate patch, затем ушёл в restore defer",
					"detail": "coord=%s" % [coord],
				})
	var player_pending_age_ms: float = -1.0
	for row: Dictionary in chunk_causality_rows:
		if not bool(row.get("is_player_chunk", false)):
			continue
		if not bool(row.get("is_visible", false)) or not bool(row.get("is_simulating", false)):
			continue
		if str(row.get("visual_phase", "")) != "done":
			continue
		if (row.get("pending_tasks", []) as Array).is_empty():
			continue
		for task_row: Dictionary in task_debug_rows:
			if task_row.get("coord", Vector2i.ZERO) == player_coord:
				player_pending_age_ms = maxf(player_pending_age_ms, float(task_row.get("age_ms", -1.0)))
		if player_pending_age_ms >= DEBUG_FORENSICS_OWNER_STUCK_MS:
			flags.append({
				"flag": "player_chunk_visual_owner_stuck",
				"label": "player chunk видим и в phase=done, но owner-task metadata не очищена",
				"detail": "age=%.1f ms" % player_pending_age_ms,
			})
	if _visual_queue_size(&"full_far") >= DEBUG_FORENSICS_FULL_FAR_PRESSURE_THRESHOLD \
		and (_visual_queue_size(&"border_fix_near") > 0 or _visual_queue_size(&"full_near") > 0):
		flags.append({
			"flag": "far_full_backlog_pressure",
			"label": "full_far backlog давит на near servicing",
			"detail": "full_far=%d border_fix_near=%d full_near=%d" % [
				_visual_queue_size(&"full_far"),
				_visual_queue_size(&"border_fix_near"),
				_visual_queue_size(&"full_near"),
			],
		})
	var perf_snapshot: Dictionary = metrics.get("perf", {}) as Dictionary
	var frame_categories: Dictionary = perf_snapshot.get("categories", {}) as Dictionary
	var frame_ops: Dictionary = perf_snapshot.get("ops", {}) as Dictionary
	var shadow_ms: float = float(frame_categories.get("shadow", 0.0))
	if shadow_ms >= 0.75:
		var heavy_shadow_ops: Array[String] = []
		for label_variant: Variant in frame_ops.keys():
			var label: String = str(label_variant)
			if not label.contains("Shadow") and not label.contains("mountain_shadow"):
				continue
			var op_ms: float = float(frame_ops.get(label, 0.0))
			if op_ms < 0.5:
				continue
			heavy_shadow_ops.append("%s=%.2f" % [label, op_ms])
			if heavy_shadow_ops.size() >= 2:
				break
		flags.append({
			"flag": "shadow_budget_competition",
			"label": "shadow rebuild конкурирует за visual budget",
			"detail": "shadow=%s%s" % [
				"%.1f ms" % shadow_ms,
				" | " + ", ".join(heavy_shadow_ops) if not heavy_shadow_ops.is_empty() else "",
			],
		})
	return flags

func build_overlay_snapshot(max_queue_rows: int, debug_radius: int = -1) -> Dictionary:
	var now_usec: int = Time.get_ticks_usec()
	_owner._debug_prune_recent_lifecycle_events(now_usec)
	prune_forensics_state(now_usec)
	if not _owner._initialized or not WorldGenerator or not WorldGenerator.balance:
		return {
			"timestamp_usec": now_usec,
			"active_z": _active_z(),
			"player_chunk": _player_chunk_coord(),
			"player_motion": _player_chunk_motion(),
			"radii": {},
			"chunks": [],
			"queue_rows": [],
			"queue_hidden_count": 0,
			"metrics": {},
			"timeline_events": WorldRuntimeDiagnosticLog.get_timeline_snapshot(16),
			"incident_summary": build_incident_summary({}, now_usec),
			"trace_events": [],
			"chunk_causality_rows": [],
			"task_debug_rows": [],
			"suspicion_flags": [],
			"mode_hint": "unavailable",
		}
	var center: Vector2i = _canonical_chunk_coord(_player_chunk_coord())
	var radii: Dictionary = _owner._debug_build_radii()
	var resolved_radius: int = debug_radius
	if resolved_radius < 0:
		resolved_radius = maxi(
			int(radii.get("render_radius", 0)),
			maxi(int(radii.get("preload_radius", 0)), int(radii.get("retention_radius", 0)))
		)
	resolved_radius = clampi(resolved_radius, 0, int(radii.get("max_debug_radius", 8)))
	var lookups: Dictionary = _owner._debug_build_snapshot_lookups(now_usec)
	var chunks: Array[Dictionary] = []
	for dy: int in range(-resolved_radius, resolved_radius + 1):
		for dx: int in range(-resolved_radius, resolved_radius + 1):
			var coord: Vector2i = _owner._offset_chunk_coord(center, Vector2i(dx, dy))
			var chunk: Chunk = _loaded_chunks().get(coord) as Chunk
			chunks.append(_debug_build_chunk_entry(coord, _active_z(), chunk, lookups, now_usec))
	var queue_snapshot: Dictionary = _owner._debug_collect_queue_rows(max_queue_rows, now_usec)
	var metrics: Dictionary = _owner._debug_build_overlay_metrics(chunks, queue_snapshot, now_usec)
	var incident_summary: Dictionary = build_incident_summary(metrics, now_usec)
	var trace_events: Array[Dictionary] = build_trace_events(incident_summary)
	var chunk_causality_rows: Array[Dictionary] = build_chunk_causality_rows(incident_summary, lookups, now_usec)
	var task_debug_rows: Array[Dictionary] = build_task_debug_rows(incident_summary, now_usec)
	var suspicion_flags: Array[Dictionary] = build_suspicion_flags(
		incident_summary,
		trace_events,
		chunk_causality_rows,
		task_debug_rows,
		metrics,
		now_usec
	)
	return {
		"timestamp_usec": now_usec,
		"active_z": _active_z(),
		"player_chunk": center,
		"player_motion": _player_chunk_motion(),
		"radii": radii,
		"debug_radius": resolved_radius,
		"chunks": chunks,
		"queue_rows": queue_snapshot.get("rows", []),
		"queue_hidden_count": int(queue_snapshot.get("hidden_count", 0)),
		"metrics": metrics,
		"timeline_events": WorldRuntimeDiagnosticLog.get_timeline_snapshot(16),
		"incident_summary": incident_summary,
		"trace_events": trace_events,
		"chunk_causality_rows": chunk_causality_rows,
		"task_debug_rows": task_debug_rows,
		"suspicion_flags": suspicion_flags,
		"mode_hint": "compact",
	}

func upsert_visual_task_meta(task: Dictionary, enqueue_reason: String = "") -> Dictionary:
	if not _hot_path_forensics_enabled:
		return {}
	var coord: Vector2i = _canonical_chunk_coord(task.get("chunk_coord", Vector2i.ZERO) as Vector2i)
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", TASK_COSMETIC))
	var band: int = int(task.get("priority_band", BAND_COSMETIC))
	var version: int = int(task.get("invalidation_version", -1))
	var task_key: Vector4i = _owner._make_visual_task_key(coord, z_level, kind)
	var trace_context: Dictionary = resolve_chunk_trace_context(coord, z_level)
	var reason_text: String = enqueue_reason if not enqueue_reason.is_empty() else _owner._debug_visual_reason_human(kind, band)
	var meta: Dictionary = {
		"task_key": task_key,
		"coord": coord,
		"z": z_level,
		"kind": kind,
		"kind_name": _owner._debug_visual_kind_name(kind),
		"band": band,
		"version": version,
		"enqueue_reason": reason_text,
		"source_system": str(trace_context.get("source_system", "chunk_scheduler")),
		"trace_id": str(trace_context.get("trace_id", "")),
		"incident_id": int(trace_context.get("incident_id", -1)),
		"enqueue_usec": Time.get_ticks_usec(),
		"last_pick_usec": 0,
		"last_skip_reason": "",
		"last_budget_state": "",
		"selected_frame": -1,
		"requeue_count": 0,
	}
	_visual_task_meta[task_key] = meta
	task["trace_id"] = str(meta.get("trace_id", ""))
	task["incident_id"] = int(meta.get("incident_id", -1))
	return meta

func note_visual_task_event(
	task: Dictionary,
	event_key: String,
	detail_fields: Dictionary = {},
	skip_reason: String = "",
	budget_state: String = ""
) -> void:
	if not _hot_path_forensics_enabled:
		return
	var coord: Vector2i = _canonical_chunk_coord(task.get("chunk_coord", Vector2i.ZERO) as Vector2i)
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", TASK_COSMETIC))
	var band: int = int(task.get("priority_band", BAND_COSMETIC))
	var task_key: Vector4i = _owner._make_visual_task_key(coord, z_level, kind)
	var meta: Dictionary = _visual_task_meta.get(task_key, {}) as Dictionary
	if meta.is_empty():
		meta = upsert_visual_task_meta(task)
	if meta.is_empty():
		return
	meta["band"] = band
	meta["kind"] = kind
	meta["kind_name"] = _owner._debug_visual_kind_name(kind)
	meta["version"] = int(task.get("invalidation_version", meta.get("version", -1)))
	meta["last_event"] = event_key
	meta["updated_usec"] = Time.get_ticks_usec()
	if event_key == "visual_task_selected":
		meta["last_pick_usec"] = Time.get_ticks_usec()
		meta["selected_frame"] = Engine.get_process_frames()
	if event_key == "visual_task_requeued":
		meta["requeue_count"] = int(meta.get("requeue_count", 0)) + 1
	if not skip_reason.is_empty():
		meta["last_skip_reason"] = skip_reason
	if not budget_state.is_empty():
		meta["last_budget_state"] = budget_state
	_visual_task_meta[task_key] = meta
	if str(meta.get("trace_id", "")).is_empty() or int(meta.get("incident_id", -1)) < 0:
		return
	var trace_context: Dictionary = {
		"trace_id": str(meta.get("trace_id", "")),
		"incident_id": int(meta.get("incident_id", -1)),
		"source_system": str(meta.get("source_system", "chunk_scheduler")),
		"coord": coord,
		"z": z_level,
		"updated_usec": int(meta.get("updated_usec", 0)),
	}
	var detail_copy: Dictionary = detail_fields.duplicate(true)
	detail_copy["kind"] = _owner._debug_visual_kind_name(kind)
	detail_copy["band"] = _owner._debug_visual_band_name(band)
	detail_copy["version"] = int(meta.get("version", -1))
	detail_copy["task_key"] = _format_visual_task_key(task_key)
	if not skip_reason.is_empty():
		detail_copy["skip_reason"] = skip_reason
	if not budget_state.is_empty():
		detail_copy["budget_state"] = budget_state
	record_forensics_event(
		trace_context,
		"chunk_scheduler",
		event_key,
		coord,
		z_level,
		detail_copy,
		[coord]
	)

func drop_visual_task_meta(task: Dictionary) -> void:
	var coord: Vector2i = _canonical_chunk_coord(task.get("chunk_coord", Vector2i.ZERO) as Vector2i)
	var z_level: int = int(task.get("z", _active_z()))
	var kind: int = int(task.get("kind", TASK_COSMETIC))
	var task_key: Vector4i = _owner._make_visual_task_key(coord, z_level, kind)
	_visual_task_meta.erase(task_key)

func note_budget_exhausted_trace_task() -> void:
	if not _hot_path_forensics_enabled:
		return
	for queue: Array[Dictionary] in _visual_queues_in_priority_order():
		for queued_task: Dictionary in queue:
			var coord: Vector2i = queued_task.get("chunk_coord", Vector2i.ZERO) as Vector2i
			var z_level: int = int(queued_task.get("z", _active_z()))
			if resolve_chunk_trace_context(coord, z_level).is_empty():
				continue
			note_visual_task_event(
				queued_task,
				"visual_task_skipped_budget",
				{},
				"",
				"scheduler_budget_exhausted"
			)
			return

func _make_forensics_trace_id() -> String:
	_next_trace_id += 1
	return "trace-%04d" % _next_trace_id

func _forensics_timestamp_label(timestamp_usec: int) -> String:
	var time_info: Dictionary = Time.get_time_dict_from_system()
	var msec: int = int((timestamp_usec / 1000) % 1000)
	return "%02d:%02d:%02d.%03d" % [
		int(time_info.get("hour", 0)),
		int(time_info.get("minute", 0)),
		int(time_info.get("second", 0)),
		msec,
	]

func _forensics_event_label(event_key: String) -> String:
	match event_key:
		"trace_started":
			return "trace запущен"
		"mining_event":
			return "копание создало trace инцидента"
		"player_chunk_visual_issue":
			return "чанк игрока сообщил о проблеме визуала"
		"roof_immediate_patch_applied":
			return "быстрый roof patch применён сразу"
		"roof_immediate_patch_skipped":
			return "быстрый roof patch не сработал"
		"roof_chunk_load_eager_refresh":
			return "загрузка чанка принудила ранний refresh roof-зоны"
		"roof_refresh_requested":
			return "поставлен полный refresh локальной зоны"
		"roof_refresh_completed":
			return "локальная roof-зона пересчитана"
		"roof_restore_deferred":
			return "restore передан в owner border_fix"
		"roof_restore_visible_guard":
			return "restore для видимого чанка временно удержан"
		"roof_restore_immediate":
			return "restore применён сразу"
		"visual_task_enqueued":
			return "visual задача поставлена в очередь"
		"visual_task_selected":
			return "scheduler выбрал visual задачу"
		"visual_task_requeued":
			return "visual задача переотложена"
		"visual_task_cleared":
			return "visual задача очищена"
		"visual_task_skipped_kind_cap":
			return "задача пропущена из-за kind cap"
		"visual_task_skipped_budget":
			return "задача пропущена из-за бюджета"
		"visual_task_compute_blocked":
			return "worker-подготовка заблокирована лимитом"
		"chunk_visual_published":
			return "чанк опубликовал финальный визуал"
		"player_chunk_owner_stuck":
			return "owner-метаданные чанка игрока зависли"
		_:
			return WorldRuntimeDiagnosticLog.humanize_known_term(event_key)

func _duplicate_trace_context(trace_context: Dictionary) -> Dictionary:
	if trace_context.is_empty():
		return {}
	return trace_context.duplicate(true)

func _is_valid_trace_context(trace_context: Dictionary, now_usec: int = -1) -> bool:
	if trace_context.is_empty():
		return false
	if now_usec < 0:
		now_usec = Time.get_ticks_usec()
	var incident_id: int = int(trace_context.get("incident_id", -1))
	if incident_id < 0:
		return false
	var incident: Dictionary = _forensics_incidents.get(incident_id, {}) as Dictionary
	if incident.is_empty():
		return false
	var updated_usec: int = int(trace_context.get("updated_usec", incident.get("updated_usec", 0)))
	if _owner._debug_age_ms(updated_usec, now_usec) > DEBUG_FORENSICS_CONTEXT_TTL_MS \
		and incident_id != _active_incident_id:
		return false
	return true

func _attach_trace_context_to_chunks(
	trace_context: Dictionary,
	coords: Array[Vector2i],
	z_level: int,
	now_usec: int
) -> void:
	if trace_context.is_empty():
		return
	var incident_id: int = int(trace_context.get("incident_id", -1))
	if incident_id < 0:
		return
	var incident: Dictionary = _forensics_incidents.get(incident_id, {}) as Dictionary
	if incident.is_empty():
		return
	var touched_chunks: Dictionary = incident.get("chunks", {}) as Dictionary
	var target_chunks: Array = incident.get("target_chunks", []) as Array
	for coord: Vector2i in coords:
		var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
		var chunk_key: String = _make_visual_chunk_key(canonical_coord, z_level)
		var context_copy: Dictionary = _duplicate_trace_context(trace_context)
		context_copy["coord"] = canonical_coord
		context_copy["z"] = z_level
		context_copy["updated_usec"] = now_usec
		_chunk_trace_contexts[chunk_key] = context_copy
		var chunk_entry: Dictionary = touched_chunks.get(chunk_key, {}) as Dictionary
		chunk_entry["coord"] = canonical_coord
		chunk_entry["z"] = z_level
		chunk_entry["updated_usec"] = now_usec
		chunk_entry["distance"] = _chunk_chebyshev_distance(canonical_coord, _player_chunk_coord())
		chunk_entry["is_player_visible_scope"] = _debug_is_incident_worthy_coord(canonical_coord, z_level)
		touched_chunks[chunk_key] = chunk_entry
		if canonical_coord not in target_chunks:
			target_chunks.append(canonical_coord)
		for kind: int in [TASK_FIRST_PASS, TASK_FULL_REDRAW, TASK_BORDER_FIX]:
			var task_key: Vector4i = _owner._make_visual_task_key(canonical_coord, z_level, kind)
			if not _has_live_visual_task(task_key):
				continue
			var meta: Dictionary = _visual_task_meta.get(task_key, {}) as Dictionary
			if meta.is_empty():
				meta = {
					"task_key": task_key,
					"coord": canonical_coord,
					"z": z_level,
					"kind": kind,
					"kind_name": _owner._debug_visual_kind_name(kind),
					"band": BAND_COSMETIC,
					"version": _visual_task_version(task_key),
					"enqueue_reason": "",
					"enqueue_usec": _visual_task_enqueue_usec(task_key, now_usec),
					"requeue_count": 0,
					"selected_frame": -1,
				}
			meta["trace_id"] = str(trace_context.get("trace_id", ""))
			meta["incident_id"] = incident_id
			meta["source_system"] = str(trace_context.get("source_system", meta.get("source_system", "chunk_scheduler")))
			_visual_task_meta[task_key] = meta
	incident["chunks"] = touched_chunks
	incident["target_chunks"] = target_chunks
	incident["updated_usec"] = now_usec
	_forensics_incidents[incident_id] = incident

func _register_forensics_event(
	trace_context: Dictionary,
	source_system: String,
	event_key: String,
	coord: Vector2i,
	z_level: int,
	detail_fields: Dictionary = {},
	target_chunks: Array[Vector2i] = []
) -> Dictionary:
	var now_usec: int = Time.get_ticks_usec()
	if not _is_valid_trace_context(trace_context, now_usec):
		return {}
	var incident_id: int = int(trace_context.get("incident_id", -1))
	var incident: Dictionary = _forensics_incidents.get(incident_id, {}) as Dictionary
	if incident.is_empty():
		return {}
	var coords: Array[Vector2i] = []
	_append_unique_chunk_coord(coords, _canonical_chunk_coord(coord))
	for target_coord: Vector2i in target_chunks:
		_append_unique_chunk_coord(coords, _canonical_chunk_coord(target_coord))
	_attach_trace_context_to_chunks(trace_context, coords, z_level, now_usec)
	var detail_copy: Dictionary = detail_fields.duplicate(true)
	detail_copy["trace_id"] = str(trace_context.get("trace_id", ""))
	detail_copy["incident_id"] = incident_id
	detail_copy["coord"] = str(_canonical_chunk_coord(coord))
	detail_copy["z"] = z_level
	var state_key: String = str(detail_copy.get("state_key", "observed"))
	var signature: String = "%s|%s|%s|%s|%s" % [
		source_system,
		event_key,
		str(_canonical_chunk_coord(coord)),
		state_key,
		var_to_str(detail_copy),
	]
	var events: Array = incident.get("events", []) as Array
	if not events.is_empty() \
		and str(incident.get("last_event_signature", "")) == signature \
		and _owner._debug_age_ms(incident.get("last_event_usec", 0), now_usec) <= DEBUG_FORENSICS_EVENT_DEDUPE_MS:
		var last_event: Dictionary = events[events.size() - 1] as Dictionary
		last_event["repeat_count"] = int(last_event.get("repeat_count", 1)) + 1
		last_event["timestamp_usec"] = now_usec
		last_event["timestamp_label"] = _forensics_timestamp_label(now_usec)
		last_event["detail_fields"] = detail_copy
		events[events.size() - 1] = last_event
	else:
		events.append({
			"timestamp_usec": now_usec,
			"timestamp_label": _forensics_timestamp_label(now_usec),
			"trace_id": str(trace_context.get("trace_id", "")),
			"incident_id": incident_id,
			"source_system": source_system,
			"event_key": event_key,
			"label": _forensics_event_label(event_key),
			"coord": _canonical_chunk_coord(coord),
			"z": z_level,
			"repeat_count": 1,
			"state": state_key,
			"detail_fields": detail_copy,
		})
		while events.size() > DEBUG_FORENSICS_TRACE_EVENT_LIMIT:
			events.pop_front()
	incident["events"] = events
	var touched_chunks: Dictionary = incident.get("chunks", {}) as Dictionary
	for affected_coord: Vector2i in coords:
		var chunk_key: String = _make_visual_chunk_key(affected_coord, z_level)
		var chunk_entry: Dictionary = touched_chunks.get(chunk_key, {}) as Dictionary
		chunk_entry["coord"] = affected_coord
		chunk_entry["z"] = z_level
		chunk_entry["updated_usec"] = now_usec
		chunk_entry["last_event"] = event_key
		chunk_entry["last_source_system"] = source_system
		chunk_entry["last_state"] = state_key
		touched_chunks[chunk_key] = chunk_entry
	incident["chunks"] = touched_chunks
	incident["updated_usec"] = now_usec
	incident["last_stage"] = event_key
	incident["last_source_system"] = source_system
	incident["last_event_signature"] = signature
	incident["last_event_usec"] = now_usec
	_forensics_incidents[incident_id] = incident
	var refreshed_context: Dictionary = _duplicate_trace_context(trace_context)
	refreshed_context["updated_usec"] = now_usec
	refreshed_context["last_stage"] = event_key
	return refreshed_context

func _begin_forensics_trace(
	source_system: String,
	event_key: String,
	primary_coord: Vector2i,
	z_level: int,
	target_chunks: Array[Vector2i] = [],
	detail_fields: Dictionary = {}
) -> Dictionary:
	var now_usec: int = Time.get_ticks_usec()
	prune_forensics_state(now_usec)
	_next_incident_id += 1
	var incident_id: int = _next_incident_id
	var canonical_primary: Vector2i = _canonical_chunk_coord(primary_coord)
	var trace_context: Dictionary = {
		"incident_id": incident_id,
		"trace_id": _make_forensics_trace_id(),
		"source_system": source_system,
		"coord": canonical_primary,
		"z": z_level,
		"updated_usec": now_usec,
		"last_stage": event_key,
	}
	var incident: Dictionary = {
		"incident_id": incident_id,
		"trace_id": str(trace_context.get("trace_id", "")),
		"source_system": source_system,
		"primary_chunk": canonical_primary,
		"player_chunk": _canonical_chunk_coord(_player_chunk_coord()),
		"started_usec": now_usec,
		"updated_usec": now_usec,
		"state": "active",
		"last_stage": event_key,
		"events": [],
		"chunks": {},
		"target_chunks": [],
		"last_event_signature": "",
		"last_event_usec": 0,
	}
	_forensics_incidents[incident_id] = incident
	_forensics_incident_order.append(incident_id)
	while _forensics_incident_order.size() > DEBUG_FORENSICS_INCIDENT_LIMIT:
		var retired_id: int = _forensics_incident_order.pop_front()
		if retired_id == incident_id:
			continue
		_forensics_incidents.erase(retired_id)
	_active_incident_id = incident_id
	var coords: Array[Vector2i] = []
	_append_unique_chunk_coord(coords, canonical_primary)
	for target_coord: Vector2i in target_chunks:
		_append_unique_chunk_coord(coords, _canonical_chunk_coord(target_coord))
	if _player_chunk_coord() != Vector2i(99999, 99999) and z_level == _active_z():
		_append_unique_chunk_coord(coords, _canonical_chunk_coord(_player_chunk_coord()))
	_attach_trace_context_to_chunks(trace_context, coords, z_level, now_usec)
	return _register_forensics_event(
		trace_context,
		source_system,
		event_key,
		canonical_primary,
		z_level,
		detail_fields,
		coords
	)

func _get_active_incident(now_usec: int) -> Dictionary:
	prune_forensics_state(now_usec)
	if _active_incident_id >= 0:
		return (_forensics_incidents.get(_active_incident_id, {}) as Dictionary).duplicate(true)
	return {}
