class_name WorldRuntimeDiagnosticLog
extends RefCounted

## Shared formatter for human-readable runtime diagnostics.
## Keeps Russian-first summaries and stable grep-friendly detail lines.

const SUMMARY_PREFIX: String = "[WorldDiag]"
const DETAIL_PREFIX: String = "[WorldDiagDetail]"
const PERF_PREFIX: String = "[WorldPerf]"
const VALIDATION_PREFIX: String = "[CodexValidation]"

const IMPACT_PLAYER_VISIBLE: StringName = &"player_visible_issue"
const IMPACT_BACKGROUND_DEBT: StringName = &"background_debt_only"
const IMPACT_INFORMATIONAL: StringName = &"informational_only"

const SEVERITY_ROOT_CAUSE: StringName = &"root_cause"
const SEVERITY_FOLLOW_UP: StringName = &"follow_up"
const SEVERITY_DIAGNOSTIC: StringName = &"diagnostic_signal"
const SEVERITY_INFORMATIONAL: StringName = &"informational"

const DEFAULT_SUMMARY_COOLDOWN_MS: float = 1000.0
const EVENT_HISTORY_LIMIT: int = 80
const EVENT_DEDUPE_COOLDOWN_MS: float = 600.0

const _IMPACT_HUMAN: Dictionary = {
	IMPACT_PLAYER_VISIBLE: "заметно игроку сейчас",
	IMPACT_BACKGROUND_DEBT: "только фоновый долг сходимости",
	IMPACT_INFORMATIONAL: "информационно, без текущего риска игроку",
}

const _SEVERITY_HUMAN: Dictionary = {
	SEVERITY_ROOT_CAUSE: "главная причина для текущей проверки",
	SEVERITY_FOLLOW_UP: "последствие или фоновый follow-up, ниже главной причины",
	SEVERITY_DIAGNOSTIC: "диагностический сигнал, не самостоятельная причина",
	SEVERITY_INFORMATIONAL: "информационная отметка",
}

const _CODE_TERM_GLOSSARY: Dictionary = {
	"_request_refresh": "внутренний запрос обновления локальной зоны",
	"streaming_truth": "очередь догрузки мира",
	"border_fix": "правка границы чанка",
	"stream_load": "потоковая догрузка мира",
	"seam_mining_async": "добыча на границе чанка",
	"roof_restore": "восстановление крыши",
	"local_patch": "локальная правка после изменения тайла",
	"shadow_refresh": "обновление теней горы",
	"manual_validation_route": "маршрут ручной проверки",
	"player_chunk": "текущий чанк игрока",
	"adjacent_loaded_chunk": "соседний загруженный чанк",
	"far_runtime_backlog": "дальний runtime backlog",
	"topology": "перестройка топологии",
	"redraw_only": "очередь фоновой перерисовки",
	"queued_not_applied": "работа поставлена в очередь, но ещё не применена",
	"applied_not_converged": "работа применена, но мир ещё не сошёлся",
	"visual_published": "визуал чанка опубликован",
	"simulation_active": "чанк участвует в симуляции",
	"wrong_state_calculated": "неверное состояние посчитано",
	"later_overwrite": "корректное состояние позже перезаписано",
}

const _PERF_LABEL_GLOSSARY: Array[Dictionary] = [
	{"prefix": "ChunkManager.try_harvest_at_world", "text": "добыча тайла через безопасную точку входа"},
	{"prefix": "ChunkManager.query_local_underground_zone", "text": "поиск локальной подземной зоны"},
	{"prefix": "MountainRoofSystem._request_refresh", "text": "внутренний запрос обновления локальной зоны"},
	{"prefix": "MountainRoofSystem._refresh_local_zone", "text": "пересчёт локальной зоны крыши"},
	{"prefix": "MountainRoofSystem._process_cover_step", "text": "шаг публикации покрытия крыши"},
	{"prefix": "FrameBudgetDispatcher.", "text": "шаг диспетчера фонового бюджета кадра"},
	{"prefix": "stream.chunk_border_fix_ms", "text": "время правки границы чанка"},
	{"prefix": "stream.chunk_full_redraw_ms", "text": "время полной перерисовки чанка"},
	{"prefix": "stream.chunk_first_pass_ms", "text": "время первого визуального прохода чанка"},
]

static var _summary_dedupe_state: Dictionary = {}
static var _summary_dedupe_mutex: Mutex = Mutex.new()
static var _timeline_events: Array[Dictionary] = []
static var _timeline_last_key_usec: Dictionary = {}
static var _timeline_last_key_index: Dictionary = {}
static var _timeline_event_id: int = 0
static var _timeline_mutex: Mutex = Mutex.new()

static func should_print_human_debug_logs() -> bool:
	return false

static func should_print_prefix(prefix: String) -> bool:
	if not should_print_human_debug_logs():
		return false
	return prefix != SUMMARY_PREFIX \
		and prefix != DETAIL_PREFIX \
		and prefix != PERF_PREFIX \
		and prefix != VALIDATION_PREFIX

static func emit_summary(
	record: Dictionary,
	prefix: String = SUMMARY_PREFIX,
	dedupe_options: Dictionary = {}
) -> bool:
	var should_emit: bool = _claim_summary_emission(record, dedupe_options)
	var summary: String = format_summary(record)
	_record_timeline_event(record, prefix, summary)
	if not should_emit:
		return false
	if should_print_prefix(prefix):
		print("%s %s" % [prefix, summary])
	return true

static func emit_detail(
	record: Dictionary,
	detail_fields: Dictionary = {},
	prefix: String = DETAIL_PREFIX
) -> void:
	if should_print_prefix(prefix):
		print("%s %s" % [prefix, format_detail(record, detail_fields)])
	_attach_timeline_detail(record, detail_fields)

static func emit_record(
	record: Dictionary,
	detail_fields: Dictionary = {},
	summary_prefix: String = SUMMARY_PREFIX,
	detail_prefix: String = DETAIL_PREFIX,
	dedupe_options: Dictionary = {}
) -> bool:
	if not emit_summary(record, summary_prefix, dedupe_options):
		return false
	var resolved_detail_fields: Dictionary = detail_fields.duplicate()
	var suppressed_repeats: int = int(record.get("_diagnostic_suppressed_repeats", 0))
	if suppressed_repeats > 0:
		resolved_detail_fields["suppressed_repeats"] = suppressed_repeats
	emit_detail(record, resolved_detail_fields, detail_prefix)
	return true

static func format_summary(record: Dictionary) -> String:
	_apply_default_semantics(record)
	var actor_text: String = _resolve_human_field(record, "actor")
	var action_text: String = _resolve_human_field(record, "action")
	var target_text: String = _resolve_human_field(record, "target")
	var reason_text: String = _resolve_human_field(record, "reason")
	var impact_text: String = _resolve_human_field(record, "impact")
	var state_text: String = _resolve_human_field(record, "state")
	var severity_text: String = _resolve_human_field(record, "severity")
	return "%s %s: %s; причина — %s; важность — %s; состояние — %s; приоритет — %s." % [
		actor_text,
		action_text,
		target_text,
		reason_text,
		impact_text,
		state_text,
		severity_text,
	]

static func format_detail(record: Dictionary, detail_fields: Dictionary = {}) -> String:
	_apply_default_semantics(record)
	var fields: Array[String] = [
		"actor=%s" % _resolve_code_field(record, "actor"),
		"action=%s" % _resolve_code_field(record, "action"),
		"target=%s" % _resolve_code_field(record, "target"),
		"reason=%s" % _resolve_code_field(record, "reason"),
		"impact=%s" % _resolve_code_field(record, "impact"),
		"state=%s" % _resolve_code_field(record, "state"),
		"severity=%s" % _resolve_code_field(record, "severity"),
	]
	var code_term: String = _resolve_code_field(record, "code")
	if code_term != "":
		fields.append("code=%s" % code_term)
	var detail_keys: Array[String] = []
	for raw_key: Variant in detail_fields.keys():
		detail_keys.append(str(raw_key))
	detail_keys.sort()
	for detail_key: String in detail_keys:
		fields.append("%s=%s" % [detail_key, _detail_value_to_string(detail_fields.get(detail_key))])
	return " ".join(fields)

static func humanize_impact(impact: StringName) -> String:
	return str(_IMPACT_HUMAN.get(impact, _humanize_identifier(String(impact))))

static func humanize_severity(severity: StringName) -> String:
	return str(_SEVERITY_HUMAN.get(severity, _humanize_identifier(String(severity))))

static func humanize_known_term(code_term: String) -> String:
	if code_term == "":
		return ""
	return str(_CODE_TERM_GLOSSARY.get(code_term, _humanize_identifier(code_term)))

static func gloss_code_term(code_term: String) -> String:
	if code_term == "":
		return ""
	var human_text: String = humanize_known_term(code_term)
	return "%s (%s)" % [human_text, code_term]

static func describe_perf_label(label: String) -> String:
	for entry: Dictionary in _PERF_LABEL_GLOSSARY:
		var prefix: String = str(entry.get("prefix", ""))
		if prefix != "" and label.begins_with(prefix):
			return "%s (%s)" % [str(entry.get("text", "")), label]
	return "%s (%s)" % [_humanize_identifier(label), label]

static func describe_chunk_scope(scope: StringName, coord: Vector2i) -> String:
	return "%s %s" % [humanize_known_term(String(scope)), coord]

static func describe_term_list(terms: Array[String]) -> String:
	if terms.is_empty():
		return "follow-up работа"
	var human_terms: Array[String] = []
	for term: String in terms:
		human_terms.append(humanize_known_term(term))
	return ", ".join(human_terms)

static func format_coord_list(coords: Array[Vector2i], limit: int = 4) -> String:
	if coords.is_empty():
		return "-"
	var parts: Array[String] = []
	var visible_count: int = mini(limit, coords.size())
	for idx: int in range(visible_count):
		parts.append(str(coords[idx]))
	if coords.size() > limit:
		parts.append("+%d_more" % [coords.size() - limit])
	return ",".join(parts)

static func get_timeline_snapshot(limit: int = 24) -> Array[Dictionary]:
	_timeline_mutex.lock()
	var snapshot: Array[Dictionary] = []
	var resolved_limit: int = clampi(limit, 0, EVENT_HISTORY_LIMIT)
	var start_index: int = maxi(0, _timeline_events.size() - resolved_limit)
	for idx: int in range(start_index, _timeline_events.size()):
		snapshot.append((_timeline_events[idx] as Dictionary).duplicate(true))
	_timeline_mutex.unlock()
	return snapshot

static func _claim_summary_emission(record: Dictionary, dedupe_options: Dictionary) -> bool:
	_apply_default_semantics(record)
	var force: bool = bool(dedupe_options.get("force", false))
	var cooldown_ms: float = float(dedupe_options.get("cooldown_ms", DEFAULT_SUMMARY_COOLDOWN_MS))
	var key: String = _build_summary_dedupe_key(record)
	var now_usec: int = Time.get_ticks_usec()
	record["_diagnostic_suppressed_repeats"] = 0
	_summary_dedupe_mutex.lock()
	var state: Dictionary = _summary_dedupe_state.get(key, {}) as Dictionary
	var should_emit: bool = force or state.is_empty()
	if not should_emit and cooldown_ms <= 0.0:
		should_emit = true
	if not should_emit and cooldown_ms > 0.0:
		var last_usec: int = int(state.get("last_usec", 0))
		should_emit = float(now_usec - last_usec) / 1000.0 >= cooldown_ms
	if should_emit:
		record["_diagnostic_suppressed_repeats"] = int(state.get("suppressed_repeats", 0))
		_summary_dedupe_state[key] = {
			"last_usec": now_usec,
			"suppressed_repeats": 0,
		}
	else:
		state["suppressed_repeats"] = int(state.get("suppressed_repeats", 0)) + 1
		_summary_dedupe_state[key] = state
	_summary_dedupe_mutex.unlock()
	return should_emit

static func _apply_default_semantics(record: Dictionary) -> void:
	if not record.has("severity"):
		var severity: StringName = _resolve_default_severity(record)
		record["severity"] = String(severity)
	if not record.has("severity_human"):
		record["severity_human"] = humanize_severity(StringName(str(record.get("severity", ""))))
	if not record.has("impact_human"):
		record["impact_human"] = humanize_impact(StringName(str(record.get("impact", ""))))

static func _resolve_default_severity(record: Dictionary) -> StringName:
	var action_key: String = _resolve_code_field(record, "action")
	var reason_key: String = _resolve_code_field(record, "reason")
	var impact_key: String = _resolve_code_field(record, "impact")
	var state_key: String = _resolve_code_field(record, "state")
	if action_key == "queue_follow_up":
		return SEVERITY_FOLLOW_UP
	if reason_key == "budget_exceeded" \
		or reason_key == "contract_exceeded" \
		or reason_key == "print_threshold_exceeded" \
		or state_key == "observed":
		return SEVERITY_DIAGNOSTIC
	if impact_key == String(IMPACT_BACKGROUND_DEBT):
		return SEVERITY_FOLLOW_UP
	if state_key == "blocked" \
		or state_key == "not_converged" \
		or state_key == "failed":
		return SEVERITY_ROOT_CAUSE
	if state_key == "converged" \
		or impact_key == String(IMPACT_INFORMATIONAL):
		return SEVERITY_INFORMATIONAL
	return SEVERITY_DIAGNOSTIC

static func _build_summary_dedupe_key(record: Dictionary) -> String:
	var parts: Array[String] = []
	for field_name: String in ["actor", "action", "target", "reason", "impact", "state"]:
		parts.append(_dedupe_field(record, field_name))
	if record.has("trace_id"):
		parts.append("trace=%s" % str(record.get("trace_id", "")))
	if record.has("incident_id"):
		parts.append("incident=%s" % str(record.get("incident_id", "")))
	return "|".join(parts)

static func _build_timeline_dedupe_key(record: Dictionary) -> String:
	var parts: Array[String] = []
	for field_name: String in ["actor", "action", "target", "reason", "impact", "state", "code"]:
		parts.append(_dedupe_field(record, field_name))
	if record.has("trace_id"):
		parts.append("trace=%s" % str(record.get("trace_id", "")))
	if record.has("incident_id"):
		parts.append("incident=%s" % str(record.get("incident_id", "")))
	return "|".join(parts)

static func _record_timeline_event(record: Dictionary, prefix: String, summary: String) -> void:
	_apply_default_semantics(record)
	var now_usec: int = Time.get_ticks_usec()
	var dedupe_key: String = _build_timeline_dedupe_key(record)
	_timeline_mutex.lock()
	var last_usec: int = int(_timeline_last_key_usec.get(dedupe_key, 0))
	var last_index: int = int(_timeline_last_key_index.get(dedupe_key, -1))
	var can_update_existing: bool = last_index >= 0 \
		and last_index < _timeline_events.size() \
		and float(now_usec - last_usec) / 1000.0 < EVENT_DEDUPE_COOLDOWN_MS
	if can_update_existing:
		var existing: Dictionary = _timeline_events[last_index] as Dictionary
		existing["repeat_count"] = int(existing.get("repeat_count", 1)) + 1
		existing["last_timestamp_usec"] = now_usec
		existing["summary"] = summary
		_timeline_events[last_index] = existing
	else:
		_timeline_event_id += 1
		var event: Dictionary = {
			"event_id": _timeline_event_id,
			"timestamp_usec": now_usec,
			"last_timestamp_usec": now_usec,
			"timestamp_label": _format_timestamp_label(now_usec),
			"summary": summary,
			"prefix": prefix,
			"record": record.duplicate(true),
			"detail_fields": {},
			"repeat_count": 1,
			"dedupe_key": dedupe_key,
			"actor": _resolve_code_field(record, "actor"),
			"action": _resolve_code_field(record, "action"),
			"target": _resolve_code_field(record, "target"),
			"reason": _resolve_code_field(record, "reason"),
			"impact": _resolve_code_field(record, "impact"),
			"state": _resolve_code_field(record, "state"),
			"severity": _resolve_code_field(record, "severity"),
			"technical_code": _resolve_code_field(record, "code"),
			"trace_id": str(record.get("trace_id", "")),
			"incident_id": int(record.get("incident_id", -1)),
		}
		_timeline_events.append(event)
		while _timeline_events.size() > EVENT_HISTORY_LIMIT:
			_timeline_events.pop_front()
		_rebuild_timeline_index_locked()
	_timeline_last_key_usec[dedupe_key] = now_usec
	if not can_update_existing:
		_timeline_last_key_index[dedupe_key] = _timeline_events.size() - 1
	_timeline_mutex.unlock()

static func _attach_timeline_detail(record: Dictionary, detail_fields: Dictionary) -> void:
	if detail_fields.is_empty():
		return
	var dedupe_key: String = _build_timeline_dedupe_key(record)
	_timeline_mutex.lock()
	var event_index: int = int(_timeline_last_key_index.get(dedupe_key, -1))
	if event_index >= 0 and event_index < _timeline_events.size():
		var event: Dictionary = _timeline_events[event_index] as Dictionary
		event["detail_fields"] = detail_fields.duplicate(true)
		event["record"] = record.duplicate(true)
		_timeline_events[event_index] = event
	_timeline_mutex.unlock()

static func _rebuild_timeline_index_locked() -> void:
	_timeline_last_key_index.clear()
	for idx: int in range(_timeline_events.size()):
		var event: Dictionary = _timeline_events[idx] as Dictionary
		var key: String = str(event.get("dedupe_key", ""))
		if key != "":
			_timeline_last_key_index[key] = idx

static func _format_timestamp_label(now_usec: int) -> String:
	var time_info: Dictionary = Time.get_time_dict_from_system()
	var msec: int = int((now_usec / 1000) % 1000)
	return "%02d:%02d:%02d.%03d" % [
		int(time_info.get("hour", 0)),
		int(time_info.get("minute", 0)),
		int(time_info.get("second", 0)),
		msec,
	]

static func _dedupe_field(record: Dictionary, field_name: String) -> String:
	var code_value: String = _resolve_code_field(record, field_name)
	if field_name == "target":
		var human_value: String = _resolve_human_field(record, field_name)
		if human_value != "" and human_value != code_value:
			return "%s/%s" % [code_value, human_value]
	return code_value

static func _resolve_human_field(record: Dictionary, key: String) -> String:
	var human_key: String = "%s_human" % key
	if record.has(human_key):
		return str(record.get(human_key, ""))
	return _resolve_code_field(record, key)

static func _resolve_code_field(record: Dictionary, key: String) -> String:
	return str(record.get(key, ""))

static func _detail_value_to_string(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return String(value)
		_:
			return str(value)

static func _humanize_identifier(value: String) -> String:
	var human_value: String = value.replace(".", " ").replace("_", " ").replace("-", " ")
	while human_value.find("  ") >= 0:
		human_value = human_value.replace("  ", " ")
	return human_value.strip_edges()
