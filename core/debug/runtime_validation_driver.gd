class_name RuntimeValidationDriver
extends Node

## Small debug-only driver for reproducible runtime perf validation.
## Activates only when launched with the user arg `codex_validate_runtime`.

signal validation_run_completed(summary: Dictionary)

const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")
const ValidationContextScript = preload("res://core/debug/scenarios/validation_context.gd")
const RouteValidationScenarioScript = preload("res://core/debug/scenarios/route_validation_scenario.gd")
const RoomValidationScenarioScript = preload("res://core/debug/scenarios/room_validation_scenario.gd")
const PowerValidationScenarioScript = preload("res://core/debug/scenarios/power_validation_scenario.gd")
const MiningValidationScenarioScript = preload("res://core/debug/scenarios/mining_validation_scenario.gd")
const MassPlacementValidationScenarioScript = preload("res://core/debug/scenarios/mass_placement_validation_scenario.gd")

const ENABLE_ARG: String = "codex_validate_runtime"
const PERF_TEST_ARG: String = "codex_perf_test"
const SCENARIOS_ARG_PREFIX: String = "codex_validate_scenarios="
const ROUTE_ARG_PREFIX: String = "codex_validate_route="
const DEFAULT_ROUTE_PRESET: StringName = &"local_ring"
const START_SETTLE_FRAMES: int = 60
const MOVE_SPEED_PX_PER_SEC: float = 8192.0
const SPEED_TRAVERSE_MOVE_SPEED_PX_PER_SEC: float = 16384.0
const FINAL_PROOF_FULL_NEAR_OP: StringName = &"scheduler.visual_queue_depth.full_near"
const FINAL_PROOF_TERRAIN_NEAR_OP: StringName = &"scheduler.visual_queue_depth.terrain_near"
const ROUTE_PRESETS := {
	&"local_ring": [
		Vector2i(6, 0),
		Vector2i(6, 5),
		Vector2i(-5, 5),
		Vector2i(-5, -4),
		Vector2i(0, -4),
		Vector2i(0, 0),
	],
	&"seam_cross": [
		Vector2i(2, 0),
		Vector2i(2, 2),
		Vector2i(-2, 2),
		Vector2i(-2, -2),
		Vector2i(2, -2),
		Vector2i(0, 0),
	],
	&"far_loop": [
		Vector2i(12, 0),
		Vector2i(12, 8),
		Vector2i(-10, 8),
		Vector2i(-10, -8),
		Vector2i(0, -8),
		Vector2i(0, 0),
	],
}
const CHUNK_REVISIT_OFFSETS := [
	Vector2i(3, 0),
	Vector2i(0, 0),
	Vector2i(-3, 0),
	Vector2i(0, 0),
]
const INVALID_CHUNK_COORD: Vector2i = Vector2i(999999, 999999)
const DEFAULT_SCENARIO_NAMES: Array[StringName] = [&"room", &"power", &"mining", &"route"]
const SCENARIO_ORDER := {
	&"room": 10,
	&"power": 20,
	&"mining": 30,
	&"deep_mine": 40,
	&"mass_placement": 50,
	&"route": 60,
	&"speed_traverse": 70,
	&"chunk_revisit": 80,
}

var _game_world: GameWorld = null
var _player: Player = null
var _building_system: BuildingSystem = null
var _power_system: PowerSystem = null
var _life_support: BaseLifeSupport = null
var _chunk_manager: ChunkManager = null
var _mountain_roof_system: MountainRoofSystem = null
var _command_executor: CommandExecutor = null
var _validation_context = null
var _selected_scenario_names: Array[StringName] = []
var _scenarios: Array = []
var _active_scenario_index: int = -1
var _active_scenario = null
var _targets: Array[Vector2] = []
var _route_preset_name: StringName = DEFAULT_ROUTE_PRESET
var _target_index: int = 0
var _start_frames_remaining: int = START_SETTLE_FRAMES
var _started: bool = false
var _run_completion_summary: Dictionary = {}
var _run_completed: bool = false

func _ready() -> void:
	_game_world = get_parent() as GameWorld
	if not _is_enabled():
		queue_free()
		return
	_route_preset_name = _resolve_route_preset_name()
	_selected_scenario_names = _resolve_selected_scenario_names()
	_scenarios = _build_selected_scenarios()
	_log_validation_status("runtime validation driver enabled; route_preset=%s scenarios=%s" % [
		_route_preset_name,
		", ".join(_stringify_scenario_names(_selected_scenario_names)),
	])

func _process(delta: float) -> void:
	if not _is_enabled() or _run_completed:
		return
	if not _started:
		if _game_world == null or not _game_world.is_boot_complete():
			return
		_resolve_player()
		_resolve_building_system()
		_resolve_power_system()
		_resolve_life_support()
		_resolve_chunk_manager()
		_resolve_mountain_roof_system()
		_resolve_command_executor()
		if _player == null or _chunk_manager == null or WorldGenerator == null or WorldGenerator.balance == null:
			return
		_validation_context = _build_validation_context()
		_started = true
		_log_validation_status("boot complete; validation scenarios ready")
		return
	if _start_frames_remaining > 0:
		_start_frames_remaining -= 1
		return
	if _active_scenario == null:
		_start_next_scenario()
		return
	_active_scenario.update(_validation_context, delta)
	if not _active_scenario.is_complete():
		return
	if _active_scenario.should_abort_run():
		_complete_validation_run()
		return
	_active_scenario = null
	_start_next_scenario()

func _is_enabled() -> bool:
	return ENABLE_ARG in OS.get_cmdline_user_args()

func _log_validation_status(message: String) -> void:
	if WorldRuntimeDiagnosticLog.should_print_prefix(WorldRuntimeDiagnosticLog.VALIDATION_PREFIX):
		print("[CodexValidation] %s" % [message])

func get_scenario_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for scenario_variant: Variant in _scenarios:
		results.append((scenario_variant as RefCounted).get_result())
	return results

func _resolve_player() -> void:
	_player = PlayerAuthority.get_local_player()

func _resolve_building_system() -> void:
	if _game_world:
		_building_system = _game_world.get_node_or_null("BuildingSystem") as BuildingSystem

func _resolve_power_system() -> void:
	if _game_world:
		_power_system = _game_world.get_node_or_null("PowerSystem") as PowerSystem

func _resolve_life_support() -> void:
	if _game_world:
		_life_support = _game_world.get_node_or_null("BaseLifeSupport") as BaseLifeSupport

func _resolve_chunk_manager() -> void:
	var chunk_managers: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunk_managers.is_empty():
		_chunk_manager = chunk_managers[0] as ChunkManager

func _resolve_mountain_roof_system() -> void:
	if _game_world:
		_mountain_roof_system = _game_world.get_node_or_null("MountainRoofSystem") as MountainRoofSystem

func _resolve_command_executor() -> void:
	var executors: Array[Node] = get_tree().get_nodes_in_group("command_executor")
	if not executors.is_empty():
		_command_executor = executors[0] as CommandExecutor

func _resolve_route_offsets() -> Array[Vector2i]:
	var preset_offsets: Array = ROUTE_PRESETS.get(_route_preset_name, ROUTE_PRESETS.get(DEFAULT_ROUTE_PRESET, [])) as Array
	var resolved: Array[Vector2i] = []
	for offset_variant: Variant in preset_offsets:
		resolved.append(offset_variant as Vector2i)
	return resolved

func _resolve_route_preset_name() -> StringName:
	var requested: String = _get_user_arg_value(ROUTE_ARG_PREFIX)
	if requested.is_empty():
		return DEFAULT_ROUTE_PRESET
	var normalized: StringName = StringName(requested.strip_edges().to_lower())
	if ROUTE_PRESETS.has(normalized):
		return normalized
	_log_validation_status("unknown route preset '%s'; falling back to %s (available=%s)" % [
		requested,
		DEFAULT_ROUTE_PRESET,
		", ".join(_get_route_preset_names()),
	])
	return DEFAULT_ROUTE_PRESET

func _get_route_preset_names() -> Array[String]:
	var names: Array[String] = []
	for preset_name: Variant in ROUTE_PRESETS.keys():
		names.append(String(preset_name))
	names.sort()
	return names

func _get_user_arg_value(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""

func _resolve_selected_scenario_names() -> Array[StringName]:
	var requested: String = _get_user_arg_value(SCENARIOS_ARG_PREFIX)
	if requested.is_empty():
		return DEFAULT_SCENARIO_NAMES.duplicate()
	var resolved: Array[StringName] = []
	var unknown: Array[String] = []
	for raw_name: String in requested.split(","):
		var trimmed: String = raw_name.strip_edges().to_lower()
		if trimmed.is_empty():
			continue
		var scenario_name: StringName = StringName(trimmed)
		if not SCENARIO_ORDER.has(scenario_name):
			unknown.append(trimmed)
			continue
		if not resolved.has(scenario_name):
			resolved.append(scenario_name)
	if resolved.is_empty():
		_log_validation_status("no known validation scenarios requested; falling back to default (%s)" % [
			", ".join(_stringify_scenario_names(DEFAULT_SCENARIO_NAMES)),
		])
		return DEFAULT_SCENARIO_NAMES.duplicate()
	if not unknown.is_empty():
		_log_validation_status("unknown validation scenarios skipped: %s" % [", ".join(unknown)])
	resolved.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(SCENARIO_ORDER.get(a, 999)) < int(SCENARIO_ORDER.get(b, 999))
	)
	return resolved

func _stringify_scenario_names(names: Array[StringName]) -> Array[String]:
	var string_names: Array[String] = []
	for name: StringName in names:
		string_names.append(String(name))
	return string_names

func _build_selected_scenarios() -> Array:
	var scenarios: Array = []
	var route_offsets: Array[Vector2i] = _resolve_route_offsets()
	for scenario_name: StringName in _selected_scenario_names:
		match scenario_name:
			&"route":
				scenarios.append(RouteValidationScenarioScript.new().configure(
					&"route",
					_route_preset_name,
					route_offsets,
					MOVE_SPEED_PX_PER_SEC
				))
			&"room":
				scenarios.append(RoomValidationScenarioScript.new())
			&"power":
				scenarios.append(PowerValidationScenarioScript.new())
			&"mining":
				scenarios.append(MiningValidationScenarioScript.new().configure(
					&"mining",
					false,
					true,
					true
				))
			&"deep_mine":
				scenarios.append(MiningValidationScenarioScript.new().configure(
					&"deep_mine",
					true,
					false,
					false
				))
			&"mass_placement":
				scenarios.append(MassPlacementValidationScenarioScript.new())
			&"speed_traverse":
				scenarios.append(RouteValidationScenarioScript.new().configure(
					&"speed_traverse",
					_route_preset_name,
					route_offsets,
					SPEED_TRAVERSE_MOVE_SPEED_PX_PER_SEC
				))
			&"chunk_revisit":
				scenarios.append(RouteValidationScenarioScript.new().configure(
					&"chunk_revisit",
					&"chunk_revisit",
					CHUNK_REVISIT_OFFSETS,
					MOVE_SPEED_PX_PER_SEC
				))
			_:
				_log_validation_status("scenario factory skipped unsupported scenario '%s'" % [scenario_name])
	return scenarios

func _build_validation_context():
	return ValidationContextScript.new().configure(
		_game_world,
		_player,
		_building_system,
		_power_system,
		_life_support,
		_chunk_manager,
		_mountain_roof_system,
		_command_executor,
		ROUTE_PRESETS,
		DEFAULT_ROUTE_PRESET,
		Callable(self, "_log_validation_status"),
		Callable(self, "_emit_validation_wait_status"),
		Callable(self, "_emit_validation_outcome"),
		Callable(self, "_set_route_progress"),
		Callable(self, "_is_runtime_caught_up"),
		Callable(self, "_describe_catch_up_blocker"),
		Callable(self, "_build_catch_up_signature"),
		Callable(self, "_has_redraw_backlog")
	)

func _start_next_scenario() -> void:
	while true:
		_active_scenario_index += 1
		if _active_scenario_index >= _scenarios.size():
			_complete_validation_run()
			return
		_active_scenario = _scenarios[_active_scenario_index]
		_active_scenario.start(_validation_context)
		if not _active_scenario.is_complete():
			return
		if _active_scenario.should_abort_run():
			_complete_validation_run()
			return
		_active_scenario = null

func _set_route_progress(route_preset_name: StringName, targets: Array[Vector2], target_index: int) -> void:
	_route_preset_name = route_preset_name
	_targets = targets.duplicate()
	_target_index = target_index

func _is_topology_caught_up() -> bool:
	return _chunk_manager == null or _chunk_manager.is_topology_ready()

func _is_runtime_caught_up() -> bool:
	return _is_streaming_truth_caught_up() and _is_topology_caught_up()

func _is_streaming_truth_caught_up() -> bool:
	if _chunk_manager == null:
		return true
	if _chunk_manager.has_method("_has_streaming_work"):
		return not _variant_to_bool(_chunk_manager.call("_has_streaming_work"))
	return _get_chunk_manager_array_size("_load_queue") <= 0 \
		and not _has_chunk_manager_object("_staged_chunk") \
		and _get_chunk_manager_array_size("_staged_data") <= 0 \
		and _get_chunk_manager_int("_gen_task_id", -1) < 0

func _has_redraw_backlog() -> bool:
	return _chunk_manager != null and _get_variant_size(_chunk_manager.get("_redrawing_chunks")) > 0

func _build_catch_up_signature() -> String:
	if _chunk_manager == null:
		return "chunk_manager=missing"
	return "%s|%d|%d|%s|%d|%d|%s|%s|%s|%s|%s" % [
		_describe_catch_up_blocker(),
		_get_chunk_manager_array_size("_load_queue"),
		_get_variant_size(_chunk_manager.get("_redrawing_chunks")),
		"yes" if _has_chunk_manager_object("_staged_chunk") else "no",
		_get_chunk_manager_array_size("_staged_data"),
		_get_chunk_manager_int("_gen_task_id", -1),
		str(_is_topology_caught_up()),
		str(_get_chunk_manager_bool("_native_topology_active")),
		str(_get_chunk_manager_bool("_native_topology_dirty")),
		str(_get_chunk_manager_bool("_is_topology_dirty")),
		str(_get_chunk_manager_bool("_is_topology_build_in_progress")),
	]

func _describe_catch_up_blocker() -> String:
	if not _is_topology_caught_up():
		return "topology"
	if not _is_streaming_truth_caught_up():
		return "streaming_truth"
	if _has_redraw_backlog():
		return "redraw_only"
	return "none"

func _emit_validation_wait_status(blocker: String, stalled_intervals: int = -1) -> void:
	var snapshot: Dictionary = _build_validation_snapshot(blocker)
	var record: Dictionary = _build_validation_record(
		"await_convergence",
		"ждёт, пока мир сойдётся после маршрута",
		"blocked",
		"ждёт сходимость",
		_resolve_validation_reason_key(blocker),
		_resolve_validation_reason_human(blocker),
		blocker,
		snapshot
	)
	_emit_validation_diag(record, _build_validation_detail_fields(snapshot, blocker, stalled_intervals))

func _emit_validation_outcome(
	outcome: String,
	blocker: String,
	stalled_intervals: int = -1,
	failure_message: String = ""
) -> void:
	var snapshot: Dictionary = _build_validation_snapshot(blocker)
	var action_human: String = "подвёл итог маршрута проверки"
	var state_human: String = "завершён"
	match outcome:
		"finished":
			action_human = "завершил маршрут и подтвердил готовность мира"
			state_human = "завершён"
		"not_converged":
			action_human = "завершил маршрут, но мир ещё не сошёлся"
			state_human = "не сошёлся"
		"blocked":
			action_human = "остановился на блокере сходимости"
			state_human = "заблокирован"
		_:
			state_human = WorldRuntimeDiagnosticLog.humanize_known_term(outcome)
	var record: Dictionary = _build_validation_record(
		"reported_validation_outcome",
		action_human,
		outcome,
		state_human,
		_resolve_validation_reason_key(blocker),
		_resolve_validation_reason_human(blocker, failure_message),
		blocker,
		snapshot
	)
	_emit_validation_diag(
		record,
		_build_validation_detail_fields(snapshot, blocker, stalled_intervals, failure_message)
	)

func _emit_validation_diag(record: Dictionary, detail_fields: Dictionary) -> void:
	WorldRuntimeDiagnosticLog.emit_record(
		record,
		detail_fields,
		WorldRuntimeDiagnosticLog.VALIDATION_PREFIX,
		WorldRuntimeDiagnosticLog.VALIDATION_PREFIX
	)

func _build_validation_record(
	action_key: String,
	action_human: String,
	state_key: String,
	state_human: String,
	reason_key: String,
	reason_human: String,
	blocker: String,
	snapshot: Dictionary
) -> Dictionary:
	var target_scope: String = str(snapshot.get("target_scope", "player_chunk"))
	var impact_key: StringName = _resolve_validation_impact(StringName(target_scope), blocker, state_key)
	var severity_key: StringName = _resolve_validation_severity(action_key, state_key)
	return {
		"actor": "manual_validation_route",
		"actor_human": "Маршрут ручной проверки",
		"action": action_key,
		"action_human": action_human,
		"target": target_scope,
		"target_human": _resolve_validation_target_human(
			target_scope,
			_get_snapshot_chunk_coord(snapshot, "target_chunk")
		),
		"reason": reason_key,
		"reason_human": reason_human,
		"impact": String(impact_key),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact_key),
		"state": state_key,
		"state_human": state_human,
		"severity": String(severity_key),
		"severity_human": WorldRuntimeDiagnosticLog.humanize_severity(severity_key),
		"code": "" if blocker == "none" else blocker,
	}

func _resolve_validation_severity(action_key: String, state_key: String) -> StringName:
	if action_key == "await_convergence":
		return WorldRuntimeDiagnosticLog.SEVERITY_DIAGNOSTIC
	if state_key == "finished":
		return WorldRuntimeDiagnosticLog.SEVERITY_INFORMATIONAL
	if state_key == "blocked" or state_key == "not_converged":
		return WorldRuntimeDiagnosticLog.SEVERITY_ROOT_CAUSE
	return WorldRuntimeDiagnosticLog.SEVERITY_DIAGNOSTIC

func _build_validation_snapshot(blocker: String) -> Dictionary:
	var player_chunk: Vector2i = _get_current_player_chunk_coord()
	var target_chunk: Vector2i = _resolve_validation_target_chunk(blocker, player_chunk)
	var target_scope: StringName = _resolve_validation_target_scope(target_chunk, player_chunk)
	var load_queue_preview: Array[String] = _build_load_queue_preview()
	return {
		"player_chunk": player_chunk,
		"target_chunk": target_chunk,
		"target_scope": String(target_scope),
		"load_queue": _get_chunk_manager_array_size("_load_queue"),
		"load_queue_preview": ",".join(load_queue_preview) if not load_queue_preview.is_empty() else "-",
		"redraw_backlog": _get_chunk_manager_array_size("_redrawing_chunks"),
		"staged_chunk": _has_chunk_manager_object("_staged_chunk"),
		"staged_coord": _get_chunk_manager_coord("_staged_coord"),
		"staged_data": _get_chunk_manager_array_size("_staged_data"),
		"gen_task_id": _get_chunk_manager_int("_gen_task_id", -1),
		"gen_coord": _get_chunk_manager_coord("_gen_coord"),
		"topology_ready": _is_topology_caught_up(),
		"native_topology": _get_chunk_manager_bool("_native_topology_active"),
		"native_dirty": _get_chunk_manager_bool("_native_topology_dirty"),
		"topology_dirty": _get_chunk_manager_bool("_is_topology_dirty"),
		"topology_build_in_progress": _get_chunk_manager_bool("_is_topology_build_in_progress"),
	}

func _build_validation_detail_fields(
	snapshot: Dictionary,
	blocker: String,
	stalled_intervals: int = -1,
	failure_message: String = ""
) -> Dictionary:
	var detail_fields: Dictionary = {
		"blocker": blocker,
		"gen_coord": _format_chunk_coord(_get_snapshot_chunk_coord(snapshot, "gen_coord")),
		"gen_task_id": int(snapshot.get("gen_task_id", -1)),
		"load_queue": int(snapshot.get("load_queue", 0)),
		"load_queue_preview": str(snapshot.get("load_queue_preview", "-")),
		"native_dirty": _get_snapshot_bool(snapshot, "native_dirty"),
		"native_topology": _get_snapshot_bool(snapshot, "native_topology"),
		"player_chunk": _format_chunk_coord(_get_snapshot_chunk_coord(snapshot, "player_chunk")),
		"reached_waypoints": "%d/%d" % [_target_index, _targets.size()],
		"redraw_backlog": int(snapshot.get("redraw_backlog", 0)),
		"route": String(_route_preset_name),
		"scope": str(snapshot.get("target_scope", "player_chunk")),
		"staged_chunk": _get_snapshot_bool(snapshot, "staged_chunk"),
		"staged_coord": _format_chunk_coord(_get_snapshot_chunk_coord(snapshot, "staged_coord")),
		"staged_data": int(snapshot.get("staged_data", 0)),
		"target_chunk": _format_chunk_coord(_get_snapshot_chunk_coord(snapshot, "target_chunk")),
		"topology_build_in_progress": _get_snapshot_bool(snapshot, "topology_build_in_progress"),
		"topology_dirty": _get_snapshot_bool(snapshot, "topology_dirty"),
		"topology_ready": _get_snapshot_bool(snapshot, "topology_ready"),
	}
	if stalled_intervals >= 0:
		detail_fields["stalled_intervals"] = stalled_intervals
	if failure_message != "":
		detail_fields["failure_message"] = failure_message
	return detail_fields

func _resolve_validation_reason_key(blocker: String) -> String:
	match blocker:
		"topology":
			return "topology_rebuild_not_complete"
		"streaming_truth":
			return "streaming_truth_not_caught_up"
		"redraw_only":
			return "redraw_backlog_remaining"
		"validation_step_failed":
			return "validation_step_failed"
		"none":
			return "no_blocker"
		_:
			return blocker

func _resolve_validation_reason_human(blocker: String, failure_message: String = "") -> String:
	match blocker:
		"topology":
			return "перестройка топологии ещё не завершена"
		"streaming_truth":
			return "очередь догрузки мира ещё не довела данные до актуального состояния"
		"redraw_only":
			return "после маршрута осталась очередь фоновой перерисовки"
		"validation_step_failed":
			if failure_message != "":
				return "встроенная проверка сценария остановилась на ошибке; подробность сохранена в technical detail"
			return "встроенная проверка сценария остановилась на ошибке"
		"none":
			return "критичных блокеров после маршрута не осталось"
		_:
			return WorldRuntimeDiagnosticLog.humanize_known_term(blocker)

func _resolve_validation_target_scope(target_chunk: Vector2i, player_chunk: Vector2i) -> StringName:
	if not _is_valid_chunk_coord(target_chunk) or not _is_valid_chunk_coord(player_chunk):
		return &"far_runtime_backlog"
	if target_chunk == player_chunk:
		return &"player_chunk"
	var dx: int = absi(target_chunk.x - player_chunk.x)
	var dy: int = absi(target_chunk.y - player_chunk.y)
	if maxi(dx, dy) <= 1:
		return &"adjacent_loaded_chunk"
	return &"far_runtime_backlog"

func _resolve_validation_target_human(target_scope: String, target_chunk: Vector2i) -> String:
	var scope_human: String = WorldRuntimeDiagnosticLog.humanize_known_term(target_scope)
	if _is_valid_chunk_coord(target_chunk):
		return "%s %s" % [scope_human, _format_chunk_coord(target_chunk)]
	return scope_human

func _resolve_validation_impact(
	target_scope: StringName,
	blocker: String,
	state_key: String
) -> StringName:
	if blocker == "none" and state_key == "finished":
		return WorldRuntimeDiagnosticLog.IMPACT_INFORMATIONAL
	if target_scope == &"player_chunk" or target_scope == &"adjacent_loaded_chunk":
		return WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE
	return WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT

func _resolve_validation_target_chunk(blocker: String, player_chunk: Vector2i) -> Vector2i:
	match blocker:
		"streaming_truth":
			var streaming_coord: Vector2i = _resolve_streaming_target_chunk(player_chunk)
			if _is_valid_chunk_coord(streaming_coord):
				return streaming_coord
		"redraw_only":
			var redraw_coord: Vector2i = _resolve_redraw_target_chunk(player_chunk)
			if _is_valid_chunk_coord(redraw_coord):
				return redraw_coord
		"topology":
			var topology_coord: Vector2i = _resolve_redraw_target_chunk(player_chunk)
			if _is_valid_chunk_coord(topology_coord):
				return topology_coord
		_:
			pass
	if _is_valid_chunk_coord(player_chunk):
		return player_chunk
	return INVALID_CHUNK_COORD

func _resolve_streaming_target_chunk(player_chunk: Vector2i) -> Vector2i:
	var candidate_coords: Array[Vector2i] = []
	for request_coord: Vector2i in _get_load_queue_coords():
		candidate_coords.append(request_coord)
	_append_candidate_coord(candidate_coords, _get_chunk_manager_coord("_staged_coord"))
	if _get_chunk_manager_int("_gen_task_id", -1) >= 0:
		_append_candidate_coord(candidate_coords, _get_chunk_manager_coord("_gen_coord"))
	return _pick_nearest_chunk_coord(candidate_coords, player_chunk)

func _resolve_redraw_target_chunk(player_chunk: Vector2i) -> Vector2i:
	var candidate_coords: Array[Vector2i] = []
	if _chunk_manager != null:
		var redrawing_variant: Variant = _chunk_manager.get("_redrawing_chunks")
		if redrawing_variant is Array:
			for chunk_variant: Variant in redrawing_variant:
				var chunk: Chunk = chunk_variant as Chunk
				if chunk == null or not is_instance_valid(chunk):
					continue
				_append_candidate_coord(candidate_coords, chunk.chunk_coord)
	return _pick_nearest_chunk_coord(candidate_coords, player_chunk)

func _get_current_player_chunk_coord() -> Vector2i:
	if _player == null or WorldGenerator == null:
		return INVALID_CHUNK_COORD
	return WorldGenerator.world_to_chunk(_player.global_position)

func _build_load_queue_preview() -> Array[String]:
	var preview: Array[String] = []
	for request_coord: Vector2i in _get_load_queue_coords().slice(0, 3):
		preview.append(_format_chunk_coord(request_coord))
	return preview

func _get_load_queue_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	if _chunk_manager == null:
		return coords
	var load_queue_variant: Variant = _get_chunk_manager_value("_load_queue")
	if load_queue_variant is Array:
		for request_variant: Variant in load_queue_variant:
			var request: Dictionary = request_variant as Dictionary
			var coord_variant: Variant = request.get("coord", INVALID_CHUNK_COORD)
			if coord_variant is Vector2i:
				_append_candidate_coord(coords, coord_variant as Vector2i)
	return coords

func _pick_nearest_chunk_coord(candidate_coords: Array[Vector2i], player_chunk: Vector2i) -> Vector2i:
	var best_coord: Vector2i = INVALID_CHUNK_COORD
	var best_distance: int = 1 << 30
	for coord: Vector2i in candidate_coords:
		if not _is_valid_chunk_coord(coord):
			continue
		if not _is_valid_chunk_coord(player_chunk):
			return coord
		var distance: int = maxi(absi(coord.x - player_chunk.x), absi(coord.y - player_chunk.y))
		if distance < best_distance:
			best_distance = distance
			best_coord = coord
	return best_coord

func _append_candidate_coord(candidate_coords: Array[Vector2i], coord: Vector2i) -> void:
	if _is_valid_chunk_coord(coord):
		candidate_coords.append(coord)

func _is_valid_chunk_coord(coord: Vector2i) -> bool:
	return coord != INVALID_CHUNK_COORD

func _get_chunk_manager_coord(field_name: String) -> Vector2i:
	if _chunk_manager == null:
		return INVALID_CHUNK_COORD
	var value: Variant = _get_chunk_manager_value(field_name)
	if value is Vector2i:
		return value as Vector2i
	return INVALID_CHUNK_COORD

func _get_chunk_manager_array_size(field_name: String) -> int:
	if _chunk_manager == null:
		return 0
	var value: Variant = _get_chunk_manager_value(field_name)
	return _get_variant_size(value)

func _get_chunk_manager_int(field_name: String, fallback: int = 0) -> int:
	if _chunk_manager == null:
		return fallback
	var value: Variant = _get_chunk_manager_value(field_name)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback

func _get_chunk_manager_bool(field_name: String, fallback: bool = false) -> bool:
	if _chunk_manager == null:
		return fallback
	return _variant_to_bool(_get_chunk_manager_value(field_name), fallback)

func _get_snapshot_bool(snapshot: Dictionary, field_name: String, fallback: bool = false) -> bool:
	return _variant_to_bool(snapshot.get(field_name, fallback), fallback)

func _variant_to_bool(value: Variant, fallback: bool = false) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT:
			return int(value) != 0
		TYPE_FLOAT:
			return not is_zero_approx(float(value))
		_:
			return fallback

func _has_chunk_manager_object(field_name: String) -> bool:
	return _chunk_manager != null and _get_chunk_manager_value(field_name) != null

func _get_chunk_manager_value(field_name: String) -> Variant:
	var streaming_service: Variant = _chunk_manager.get("_chunk_streaming_service") if _chunk_manager != null else null
	match field_name:
		"_load_queue":
			return streaming_service.get("load_queue") if streaming_service != null else _chunk_manager.get(field_name)
		"_staged_chunk":
			return streaming_service.get("staged_chunk") if streaming_service != null else _chunk_manager.get(field_name)
		"_staged_coord":
			return streaming_service.get("staged_coord") if streaming_service != null else _chunk_manager.get(field_name)
		"_staged_data":
			return streaming_service.get("staged_data") if streaming_service != null else _chunk_manager.get(field_name)
		"_gen_task_id":
			return streaming_service.get("gen_task_id") if streaming_service != null else _chunk_manager.get(field_name)
		"_gen_coord":
			return streaming_service.get("gen_coord") if streaming_service != null else _chunk_manager.get(field_name)
		_:
			return _chunk_manager.get(field_name)

func _get_snapshot_chunk_coord(snapshot: Dictionary, field_name: String) -> Vector2i:
	var value: Variant = snapshot.get(field_name, INVALID_CHUNK_COORD)
	if value is Vector2i:
		return value as Vector2i
	return INVALID_CHUNK_COORD

func _format_chunk_coord(coord: Vector2i) -> String:
	if not _is_valid_chunk_coord(coord):
		return "-"
	return "(%d,%d)" % [coord.x, coord.y]

func _get_variant_size(value: Variant) -> int:
	if value is Array:
		return (value as Array).size()
	if value is Dictionary:
		return (value as Dictionary).size()
	return 0

func _complete_validation_run() -> void:
	if _run_completed:
		return
	_run_completion_summary = _build_run_completion_summary()
	_run_completed = true
	if _validation_context != null:
		_validation_context.set_validation_player_velocity(Vector2.ZERO)
	set_process(false)
	validation_run_completed.emit(_run_completion_summary.duplicate(true))
	if _should_quit_immediately():
		get_tree().quit(int(_run_completion_summary.get("exit_code", 0)))

func _build_run_completion_summary() -> Dictionary:
	var outcome: String = "finished"
	var blocker: String = "none"
	var exit_code: int = 0
	var failure_message: String = ""
	for scenario_variant: Variant in _scenarios:
		var scenario: RefCounted = scenario_variant as RefCounted
		var result: Dictionary = scenario.get_result()
		var state: String = str(result.get("state", "pending"))
		if state == "failed" or state == "blocked":
			outcome = "blocked"
			blocker = str(result.get("blocker", "validation_step_failed"))
			failure_message = str(result.get("message", ""))
			exit_code = 1
			break
		if state == "not_converged" and outcome != "blocked":
			outcome = "not_converged"
			blocker = str(result.get("blocker", "redraw_only"))
			failure_message = str(result.get("message", ""))
	if outcome == "finished":
		var proof_audit: Dictionary = _audit_final_publication_proof(
			_get_final_overlay_snapshot(),
			_get_final_world_perf_snapshot()
		)
		if not proof_audit.is_empty():
			outcome = str(proof_audit.get("outcome", "not_converged"))
			blocker = str(proof_audit.get("blocker", "streaming_truth"))
			exit_code = int(proof_audit.get("exit_code", 1))
			failure_message = str(proof_audit.get("failure_message", ""))
	return {
		"outcome": outcome,
		"blocker": blocker,
		"exit_code": exit_code,
		"failure_message": failure_message,
		"route_preset": String(_route_preset_name),
		"selected_scenarios": _stringify_scenario_names(_selected_scenario_names),
	}

func _get_final_overlay_snapshot() -> Dictionary:
	if _chunk_manager == null or not _chunk_manager.has_method("get_chunk_debug_overlay_snapshot"):
		return {}
	return _chunk_manager.get_chunk_debug_overlay_snapshot(0, 0)

func _get_final_world_perf_snapshot() -> Dictionary:
	var world_perf_monitor: Node = get_node_or_null("/root/WorldPerfMonitor")
	if world_perf_monitor == null or not world_perf_monitor.has_method("get_debug_snapshot"):
		return {}
	return world_perf_monitor.call("get_debug_snapshot") as Dictionary

func _audit_final_publication_proof(
	overlay_snapshot: Dictionary,
	perf_snapshot: Dictionary
) -> Dictionary:
	var player_hot_stall: Dictionary = _audit_player_hot_stall(overlay_snapshot)
	if not player_hot_stall.is_empty():
		return player_hot_stall
	return _audit_final_near_queue_debt(perf_snapshot, overlay_snapshot)

func _audit_player_hot_stall(overlay_snapshot: Dictionary) -> Dictionary:
	var chunk_causality_rows: Array = overlay_snapshot.get("chunk_causality_rows", []) as Array
	for row_variant: Variant in chunk_causality_rows:
		var row: Dictionary = row_variant as Dictionary
		if not bool(row.get("is_player_chunk", false)):
			continue
		if str(row.get("state", "")) != "stalled":
			continue
		var pending_tasks: Array = row.get("pending_tasks", []) as Array
		return {
			"outcome": "not_converged",
			"blocker": "streaming_truth",
			"exit_code": 1,
			"failure_message": "final player-hot chunk stayed stalled; state=%s visible=%s phase=%s pending_tasks=%s stage_age_ms=%.3f" % [
				str(row.get("state", "")),
				str(bool(row.get("is_visible", false))),
				str(row.get("visual_phase", "")),
				",".join(_stringify_variants(pending_tasks)),
				float(row.get("stage_age_ms", -1.0)),
			],
		}
	return {}

func _audit_final_near_queue_debt(
	perf_snapshot: Dictionary,
	overlay_snapshot: Dictionary
) -> Dictionary:
	var ops: Dictionary = perf_snapshot.get("ops", {}) as Dictionary
	var full_near: float = float(ops.get(FINAL_PROOF_FULL_NEAR_OP, 0.0))
	var terrain_near: float = float(ops.get(FINAL_PROOF_TERRAIN_NEAR_OP, 0.0))
	if is_zero_approx(full_near) and is_zero_approx(terrain_near):
		var overlay_metrics: Dictionary = overlay_snapshot.get("metrics", {}) as Dictionary
		full_near = float(overlay_metrics.get("queue_full_near", 0.0))
		terrain_near = float(overlay_metrics.get("queue_terrain_near", 0.0))
	if full_near <= 0.0 and terrain_near <= 0.0:
		return {}
	return {
		"outcome": "not_converged",
		"blocker": "redraw_only",
		"exit_code": 1,
		"failure_message": "final near visual queue debt remained; %s=%.1f %s=%.1f" % [
			String(FINAL_PROOF_FULL_NEAR_OP),
			full_near,
			String(FINAL_PROOF_TERRAIN_NEAR_OP),
			terrain_near,
		],
	}

func _stringify_variants(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	return result

func _should_quit_immediately() -> bool:
	return PERF_TEST_ARG not in OS.get_cmdline_user_args()
