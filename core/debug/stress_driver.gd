class_name StressDriver
extends Node

## Debug-only scale driver for explicit observatory stress runs.
## Activates only when launched with the user arg `codex_stress_mode=...`.

const ValidationContextScript = preload("res://core/debug/scenarios/validation_context.gd")

const MODE_ARG_PREFIX: String = "codex_stress_mode="
const COUNT_ARG_PREFIX: String = "codex_stress_count="
const CHUNKS_ARG_PREFIX: String = "codex_stress_chunks="
const SPEED_ARG_PREFIX: String = "codex_stress_speed="
const DEPTH_ARG_PREFIX: String = "codex_stress_depth="
const FLORA_MULTIPLIER_ARG_PREFIX: String = "codex_stress_flora_multiplier="

const DEFAULT_BUILDING_STRESS_COUNT: int = 200
const DEFAULT_ENTITY_STRESS_COUNT: int = 500
const DEFAULT_LONG_TRAVERSE_CHUNKS: int = 50
const DEFAULT_SPEED_TRAVERSE_CHUNKS: int = 12
const DEFAULT_SPEED_TRAVERSE_PX_PER_SEC: float = 8192.0
const DEFAULT_DEEP_MINE_DEPTH: int = 30
const DEFAULT_DENSE_WORLD_MULTIPLIER: float = 3.0

const MASS_BUILDINGS_BATCH_PER_FRAME: int = 8
const MASS_BUILDINGS_SETTLE_FRAMES: int = 12
const MASS_BUILDINGS_SETTLE_TIMEOUT_FRAMES: int = 240
const MASS_BUILDINGS_SCAN_RADIUS_TILES: int = 48
const MASS_BUILDINGS_TILE_STEP: int = 2

const ROUTE_SEGMENT_SETTLE_FRAMES: int = 30
const ROUTE_TAIL_SETTLE_FRAMES: int = 180
const ROUTE_CATCH_UP_TIMEOUT_FRAMES: int = 360
const ROUTE_ARRIVE_DISTANCE_PX: float = 16.0
const HITCH_THRESHOLD_MS: float = 22.0
const MINE_SETTLE_FRAMES: int = 20

const INVALID_TILE: Vector2i = Vector2i(999999, 999999)
const DEFAULT_ROUTE_PRESET: StringName = &"stress_default"

signal stress_run_completed(summary: Dictionary)

var _game_world: GameWorld = null
var _player: Player = null
var _building_system: BuildingSystem = null
var _chunk_manager: ChunkManager = null
var _mountain_roof_system: MountainRoofSystem = null
var _command_executor: CommandExecutor = null
var _validation_context = null

var _mode: StringName = &""
var _started: bool = false
var _run_completed: bool = false
var _run_completion_summary: Dictionary = {}
var _start_usec: int = 0
var _target_count: int = 0
var _actual_count: int = 0
var _primary_action_label: String = ""
var _primary_action_samples_ms: Array[float] = []
var _cleanup_action_samples_ms: Array[float] = []
var _frame_samples_ms: Array[float] = []
var _hitches_during: int = 0

var _mass_building_data: BuildingData = null
var _candidate_tiles: Array[Vector2i] = []
var _placed_tiles: Array[Vector2i] = []
var _candidate_index: int = 0
var _cleanup_index: int = 0
var _mass_phase: StringName = &""
var _mass_wait_frames_remaining: int = 0
var _mass_wait_timeout_frames_remaining: int = -1

var _route_targets: Array[Vector2] = []
var _route_target_index: int = 0
var _route_move_speed_px_per_sec: float = DEFAULT_SPEED_TRAVERSE_PX_PER_SEC
var _route_segment_frames_remaining: int = 0
var _route_tail_frames_remaining: int = -1
var _route_catch_up_timeout_frames_remaining: int = -1

var _mine_direction: Vector2i = Vector2i.ZERO
var _next_mine_tile: Vector2i = INVALID_TILE
var _mine_wait_frames_remaining: int = 0

static func is_enabled_for_current_run() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(MODE_ARG_PREFIX):
			return true
	return false

func _ready() -> void:
	_game_world = get_parent() as GameWorld
	if not is_enabled_for_current_run():
		set_process(false)
		queue_free()
		return
	_mode = _resolve_mode()
	if _mode == StringName():
		_complete_with_failure("stress mode argument is present but empty")

func _process(delta: float) -> void:
	if _run_completed:
		return
	if not _started:
		if _game_world == null or not _game_world.is_boot_complete():
			return
		if not _resolve_runtime_refs():
			return
		_validation_context = _build_validation_context()
		_started = true
		_start_usec = Time.get_ticks_usec()
		_begin_mode()
		if _run_completed:
			return
	_record_frame_sample(delta)
	match _mode:
		&"mass_buildings":
			_update_mass_buildings()
		&"long_traverse", &"speed_traverse":
			_update_route_traverse(delta)
		&"deep_mine":
			_update_deep_mine()
		&"entity_swarm":
			_complete_with_failure(
				"entity_swarm has no sanctioned spawn entrypoint in PUBLIC_API.md; stress run refused to bypass gameplay ownership",
				{
					"requested_entity_count": _resolve_positive_int_arg(COUNT_ARG_PREFIX, DEFAULT_ENTITY_STRESS_COUNT),
					"unsupported_mode": true,
				}
			)
		&"dense_world":
			_complete_with_failure(
				"dense_world has no sanctioned runtime density override in current scope; stress run refused to mutate world generation ownership",
				{
					"requested_flora_multiplier": _resolve_positive_float_arg(FLORA_MULTIPLIER_ARG_PREFIX, DEFAULT_DENSE_WORLD_MULTIPLIER),
					"unsupported_mode": true,
				}
			)
		_:
			_complete_with_failure("unknown stress mode '%s'" % [String(_mode)])

func _resolve_runtime_refs() -> bool:
	_player = PlayerAuthority.get_local_player()
	if _game_world != null:
		_building_system = _game_world.get_node_or_null("BuildingSystem") as BuildingSystem
		_mountain_roof_system = _game_world.get_node_or_null("MountainRoofSystem") as MountainRoofSystem
	var chunk_managers: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunk_managers.is_empty():
		_chunk_manager = chunk_managers[0] as ChunkManager
	var executors: Array[Node] = get_tree().get_nodes_in_group("command_executor")
	if not executors.is_empty():
		_command_executor = executors[0] as CommandExecutor
	return _player != null and _chunk_manager != null and _command_executor != null

func _build_validation_context():
	var route_presets: Dictionary = {
		DEFAULT_ROUTE_PRESET: _build_spiral_route_offsets(maxi(1, _target_count))
	}
	return ValidationContextScript.new().configure(
		_game_world,
		_player,
		_building_system,
		null,
		null,
		_chunk_manager,
		_mountain_roof_system,
		_command_executor,
		route_presets,
		DEFAULT_ROUTE_PRESET,
		Callable(self, "_noop_log_status"),
		Callable(self, "_noop_route_wait_status"),
		Callable(self, "_noop_route_outcome"),
		Callable(self, "_noop_route_progress"),
		Callable(self, "_is_runtime_caught_up"),
		Callable(self, "_describe_catch_up_blocker"),
		Callable(self, "_build_catch_up_signature"),
		Callable(self, "_has_redraw_backlog")
	)

func _begin_mode() -> void:
	match _mode:
		&"mass_buildings":
			_begin_mass_buildings()
		&"long_traverse":
			_begin_route_traverse(
				_resolve_positive_int_arg(CHUNKS_ARG_PREFIX, DEFAULT_LONG_TRAVERSE_CHUNKS),
				DEFAULT_SPEED_TRAVERSE_PX_PER_SEC
			)
		&"speed_traverse":
			_begin_route_traverse(
				_resolve_positive_int_arg(CHUNKS_ARG_PREFIX, DEFAULT_SPEED_TRAVERSE_CHUNKS),
				_resolve_positive_float_arg(SPEED_ARG_PREFIX, DEFAULT_SPEED_TRAVERSE_PX_PER_SEC)
			)
		&"deep_mine":
			_begin_deep_mine()
		&"entity_swarm":
			_target_count = _resolve_positive_int_arg(COUNT_ARG_PREFIX, DEFAULT_ENTITY_STRESS_COUNT)
		&"dense_world":
			_target_count = 0
		_:
			pass

func _begin_mass_buildings() -> void:
	_target_count = _resolve_positive_int_arg(COUNT_ARG_PREFIX, DEFAULT_BUILDING_STRESS_COUNT)
	if _building_system == null:
		_complete_with_failure("mass_buildings requires BuildingSystem")
		return
	_mass_building_data = _resolve_wall_building_data()
	if _mass_building_data == null:
		_complete_with_failure("mass_buildings could not resolve wall building data")
		return
	_building_system.set_selected_building(_mass_building_data)
	_validation_context.collect_validation_scrap(maxi(_target_count * 8, 1024))
	_candidate_tiles = _collect_mass_building_tiles(_target_count)
	if _candidate_tiles.size() < _target_count:
		_complete_with_failure(
			"mass_buildings could only find %d placeable tiles for target_count=%d" % [_candidate_tiles.size(), _target_count],
			{
				"available_candidates": _candidate_tiles.size(),
			}
		)
		return
	_primary_action_label = "placement"
	_candidate_index = 0
	_cleanup_index = 0
	_mass_phase = &"placing"

func _resolve_wall_building_data() -> BuildingData:
	var building_data: BuildingData = BuildingCatalog.get_default_building("wall")
	if building_data == null and ItemRegistry != null:
		building_data = ItemRegistry.get_building(&"wall")
	return building_data

func _collect_mass_building_tiles(target_count: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	var origin: Vector2i = _building_system.world_to_grid(_player.global_position) + Vector2i(12, 8)
	for y_offset: int in range(-MASS_BUILDINGS_SCAN_RADIUS_TILES, MASS_BUILDINGS_SCAN_RADIUS_TILES + 1, MASS_BUILDINGS_TILE_STEP):
		for x_offset: int in range(-MASS_BUILDINGS_SCAN_RADIUS_TILES, MASS_BUILDINGS_SCAN_RADIUS_TILES + 1, MASS_BUILDINGS_TILE_STEP):
			var tile_pos: Vector2i = origin + Vector2i(x_offset, y_offset)
			if not _building_system.can_place_selected_building_at(_building_system.grid_to_world(tile_pos)):
				continue
			results.append(tile_pos)
			if results.size() >= target_count:
				return results
	return results

func _update_mass_buildings() -> void:
	match _mass_phase:
		&"placing":
			var placements_this_frame: int = 0
			while placements_this_frame < MASS_BUILDINGS_BATCH_PER_FRAME \
					and _candidate_index < _candidate_tiles.size() \
					and _actual_count < _target_count:
				var tile_pos: Vector2i = _candidate_tiles[_candidate_index]
				_candidate_index += 1
				var started_usec: int = Time.get_ticks_usec()
				var result: Dictionary = _building_system.place_selected_building_at(_building_system.grid_to_world(tile_pos))
				var duration_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
				_primary_action_samples_ms.append(duration_ms)
				if not bool(result.get("success", false)):
					continue
				_placed_tiles.append(tile_pos)
				_actual_count += 1
				placements_this_frame += 1
			if _actual_count >= _target_count:
				_begin_mass_wait(&"cleanup")
				return
			if _candidate_index >= _candidate_tiles.size():
				_complete_with_failure(
					"mass_buildings placed %d/%d before running out of valid candidates" % [_actual_count, _target_count]
				)
		&"settle_after_place", &"settle_after_cleanup":
			_update_mass_wait()
		&"cleanup":
			var removals_this_frame: int = 0
			while removals_this_frame < MASS_BUILDINGS_BATCH_PER_FRAME and _cleanup_index < _placed_tiles.size():
				var tile_pos: Vector2i = _placed_tiles[_cleanup_index]
				_cleanup_index += 1
				var started_usec: int = Time.get_ticks_usec()
				var result: Dictionary = _building_system.remove_building_at(_building_system.grid_to_world(tile_pos))
				var duration_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
				_cleanup_action_samples_ms.append(duration_ms)
				if not bool(result.get("success", false)):
					_complete_with_failure("mass_buildings cleanup failed at tile %s" % [tile_pos])
					return
				removals_this_frame += 1
			if _cleanup_index >= _placed_tiles.size():
				_begin_mass_wait(&"complete")
		&"complete":
			for tile_pos: Vector2i in _placed_tiles:
				if _building_system.has_building_at(tile_pos):
					_complete_with_failure("mass_buildings cleanup left a building behind at %s" % [tile_pos])
					return
			_complete_with_success({
				"target_count": _target_count,
				"actual_count": _actual_count,
				"cleanup_count": _placed_tiles.size(),
				"total_placement_ms": _sum_samples(_primary_action_samples_ms),
				"avg_placement_ms": _calc_average(_primary_action_samples_ms),
				"peak_placement_ms": _calc_peak(_primary_action_samples_ms),
				"cleanup_total_ms": _sum_samples(_cleanup_action_samples_ms),
				"cleanup_avg_ms": _calc_average(_cleanup_action_samples_ms),
				"cleanup_peak_ms": _calc_peak(_cleanup_action_samples_ms),
			})
		_:
			_complete_with_failure("mass_buildings reached invalid phase '%s'" % [String(_mass_phase)])

func _begin_mass_wait(next_phase: StringName) -> void:
	_mass_phase = &"settle_after_place" if next_phase == &"cleanup" else &"settle_after_cleanup"
	_mass_wait_frames_remaining = MASS_BUILDINGS_SETTLE_FRAMES
	_mass_wait_timeout_frames_remaining = MASS_BUILDINGS_SETTLE_TIMEOUT_FRAMES
	if next_phase == &"complete":
		_mass_phase = &"settle_after_cleanup"

func _update_mass_wait() -> void:
	if _building_system != null and _building_system.has_pending_room_recompute():
		_mass_wait_timeout_frames_remaining -= 1
		_mass_wait_frames_remaining = MASS_BUILDINGS_SETTLE_FRAMES
		if _mass_wait_timeout_frames_remaining <= 0:
			_complete_with_failure("mass_buildings room recompute did not settle within timeout")
		return
	if _mass_wait_frames_remaining > 0:
		_mass_wait_frames_remaining -= 1
		return
	if _mass_phase == &"settle_after_place":
		_mass_phase = &"cleanup"
	else:
		_mass_phase = &"complete"

func _begin_route_traverse(target_chunks: int, move_speed_px_per_sec: float) -> void:
	_target_count = maxi(1, target_chunks)
	_route_move_speed_px_per_sec = maxf(1.0, move_speed_px_per_sec)
	_route_targets = _validation_context.build_route_targets(_build_spiral_route_offsets(_target_count))
	if _route_targets.is_empty():
		_complete_with_failure("route stress could not build any targets")
		return
	_route_target_index = 0
	_route_segment_frames_remaining = 0
	_route_tail_frames_remaining = -1
	_route_catch_up_timeout_frames_remaining = -1

func _build_spiral_route_offsets(target_chunks: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	var current: Vector2i = Vector2i.ZERO
	var step_length: int = 1
	var directions := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	while offsets.size() < target_chunks:
		for dir_index: int in range(directions.size()):
			var direction: Vector2i = directions[dir_index]
			for _step: int in range(step_length):
				current += direction
				offsets.append(current)
				if offsets.size() >= target_chunks:
					return offsets
			if dir_index == 1 or dir_index == 3:
				step_length += 1
	return offsets

func _update_route_traverse(delta: float) -> void:
	if _route_segment_frames_remaining > 0:
		_route_segment_frames_remaining -= 1
		return
	if _route_tail_frames_remaining >= 0:
		_update_route_tail()
		return
	if _route_target_index >= _route_targets.size():
		_validation_context.set_validation_player_velocity(Vector2.ZERO)
		_route_tail_frames_remaining = ROUTE_TAIL_SETTLE_FRAMES
		return
	var target: Vector2 = _route_targets[_route_target_index]
	var display_target: Vector2 = _validation_context.resolve_route_display_target(target)
	var move_direction: Vector2 = _player.global_position.direction_to(display_target)
	_validation_context.set_validation_player_velocity(move_direction * _route_move_speed_px_per_sec)
	_player.global_position = _player.global_position.move_toward(
		display_target,
		_route_move_speed_px_per_sec * delta
	)
	if _player.global_position.distance_to(display_target) > ROUTE_ARRIVE_DISTANCE_PX:
		return
	_player.global_position = _validation_context.canonicalize_world_position(target)
	_validation_context.set_validation_player_velocity(Vector2.ZERO)
	_route_target_index += 1
	_actual_count = _route_target_index
	_route_segment_frames_remaining = ROUTE_SEGMENT_SETTLE_FRAMES

func _update_route_tail() -> void:
	if _route_tail_frames_remaining > 0:
		_route_tail_frames_remaining -= 1
		return
	if _is_runtime_caught_up():
		_complete_with_success({
			"target_count": _target_count,
			"actual_count": _actual_count,
			"route_waypoint_count": _route_targets.size(),
			"move_speed_px_per_sec": _route_move_speed_px_per_sec,
			"readiness_outcome": "finished" if not _has_redraw_backlog() else "not_converged",
			"blocker": "none" if not _has_redraw_backlog() else "redraw_only",
		})
		return
	if _route_catch_up_timeout_frames_remaining < 0:
		_route_catch_up_timeout_frames_remaining = ROUTE_CATCH_UP_TIMEOUT_FRAMES
	if _route_catch_up_timeout_frames_remaining > 0:
		_route_catch_up_timeout_frames_remaining -= 1
		return
	_complete_with_failure(
		"%s stress did not converge after traverse" % [String(_mode)],
		{
			"target_count": _target_count,
			"actual_count": _actual_count,
			"route_waypoint_count": _route_targets.size(),
			"move_speed_px_per_sec": _route_move_speed_px_per_sec,
			"blocker": _describe_catch_up_blocker(),
		}
	)

func _begin_deep_mine() -> void:
	_target_count = _resolve_positive_int_arg(DEPTH_ARG_PREFIX, DEFAULT_DEEP_MINE_DEPTH)
	_primary_action_label = "mine"
	if not _prepare_next_mine_target():
		_complete_with_failure("deep_mine could not find a suitable mining lane")
		return

func _prepare_next_mine_target() -> bool:
	var mining_case: Dictionary = _validation_context.acquire_mining_validation_case(true)
	if mining_case.is_empty():
		_next_mine_tile = INVALID_TILE
		return false
	var entry_tile: Vector2i = mining_case.get("entry_tile", INVALID_TILE)
	var interior_tile: Vector2i = mining_case.get("interior_tile", INVALID_TILE)
	if entry_tile == INVALID_TILE or interior_tile == INVALID_TILE:
		_next_mine_tile = INVALID_TILE
		return false
	_mine_direction = interior_tile - entry_tile
	if _mine_direction == Vector2i.ZERO:
		_next_mine_tile = INVALID_TILE
		return false
	_next_mine_tile = entry_tile
	return true

func _update_deep_mine() -> void:
	if _mine_wait_frames_remaining > 0:
		_mine_wait_frames_remaining -= 1
		return
	if _actual_count >= _target_count:
		_complete_with_success({
			"target_count": _target_count,
			"actual_count": _actual_count,
			"total_mine_ms": _sum_samples(_primary_action_samples_ms),
			"avg_mine_ms": _calc_average(_primary_action_samples_ms),
			"peak_mine_ms": _calc_peak(_primary_action_samples_ms),
		})
		return
	if _next_mine_tile == INVALID_TILE and not _prepare_next_mine_target():
		_complete_with_failure(
			"deep_mine exhausted loaded mining lanes at %d/%d" % [_actual_count, _target_count],
			{
				"target_count": _target_count,
				"actual_count": _actual_count,
			}
		)
		return
	var started_usec: int = Time.get_ticks_usec()
	var mine_ok: bool = _validation_context.mine_tile(_next_mine_tile)
	var duration_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_primary_action_samples_ms.append(duration_ms)
	if not mine_ok:
		_next_mine_tile = INVALID_TILE
		_mine_wait_frames_remaining = MINE_SETTLE_FRAMES
		return
	_actual_count += 1
	if _player != null:
		_player.global_position = _validation_context.tile_to_world_center(_next_mine_tile)
	var candidate_next_tile: Vector2i = _next_mine_tile + _mine_direction
	if _can_continue_mining(candidate_next_tile):
		_next_mine_tile = candidate_next_tile
	else:
		_next_mine_tile = INVALID_TILE
	_mine_wait_frames_remaining = MINE_SETTLE_FRAMES

func _can_continue_mining(tile_pos: Vector2i) -> bool:
	return tile_pos != INVALID_TILE \
		and _chunk_manager != null \
		and _chunk_manager.is_tile_loaded(tile_pos) \
		and _chunk_manager.get_terrain_type_at_global(tile_pos) == TileGenData.TerrainType.ROCK

func _resolve_mode() -> StringName:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(MODE_ARG_PREFIX):
			continue
		return StringName(arg.trim_prefix(MODE_ARG_PREFIX).strip_edges().to_lower())
	return StringName()

func _resolve_positive_int_arg(prefix: String, fallback: int) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(prefix):
			continue
		var parsed: int = arg.trim_prefix(prefix).strip_edges().to_int()
		if parsed > 0:
			return parsed
	return fallback

func _resolve_positive_float_arg(prefix: String, fallback: float) -> float:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(prefix):
			continue
		var raw_value: String = arg.trim_prefix(prefix).strip_edges()
		if raw_value.is_empty():
			continue
		var parsed: float = raw_value.to_float()
		if parsed > 0.0:
			return parsed
	return fallback

func _record_frame_sample(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	_frame_samples_ms.append(frame_ms)
	if frame_ms > HITCH_THRESHOLD_MS:
		_hitches_during += 1

func _complete_with_success(extra: Dictionary = {}) -> void:
	_complete_run("passed", extra, 0)

func _complete_with_failure(message: String, extra: Dictionary = {}) -> void:
	var merged: Dictionary = extra.duplicate(true)
	merged["message"] = message
	_complete_run("failed", merged, 1)

func _complete_run(state: String, extra: Dictionary, exit_code: int) -> void:
	if _run_completed:
		return
	_run_completed = true
	set_process(false)
	if _validation_context != null:
		_validation_context.set_validation_player_velocity(Vector2.ZERO)
	_run_completion_summary = _build_summary(state, extra, exit_code)
	stress_run_completed.emit(_run_completion_summary.duplicate(true))

func _build_summary(state: String, extra: Dictionary, exit_code: int) -> Dictionary:
	var summary: Dictionary = {
		"mode": String(_mode),
		"state": state,
		"target_count": _target_count,
		"actual_count": _actual_count,
		"duration_ms": float(Time.get_ticks_usec() - _start_usec) / 1000.0 if _start_usec > 0 else 0.0,
		"frame_avg_during_ms": _calc_average(_frame_samples_ms),
		"frame_p99_during_ms": _calc_percentile(_frame_samples_ms, 99.0),
		"hitches_during": _hitches_during,
		"exit_code": exit_code,
	}
	if not _primary_action_label.is_empty() and not _primary_action_samples_ms.is_empty():
		summary["action_label"] = _primary_action_label
		summary["total_action_ms"] = _sum_samples(_primary_action_samples_ms)
		summary["avg_action_ms"] = _calc_average(_primary_action_samples_ms)
		summary["peak_action_ms"] = _calc_peak(_primary_action_samples_ms)
	for key_variant: Variant in extra.keys():
		summary[key_variant] = extra[key_variant]
	return summary

func _calc_average(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	return _sum_samples(samples) / float(samples.size())

func _calc_peak(samples: Array[float]) -> float:
	var peak: float = 0.0
	for sample: float in samples:
		peak = maxf(peak, sample)
	return peak

func _sum_samples(samples: Array[float]) -> float:
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	return total

func _calc_percentile(samples: Array[float], percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples: Array[float] = samples.duplicate()
	sorted_samples.sort()
	var max_index: int = sorted_samples.size() - 1
	var target_index: int = mini(int(floor((float(sorted_samples.size()) - 1.0) * percentile / 100.0)), max_index)
	return sorted_samples[target_index]

func _noop_log_status(_message: String) -> void:
	pass

func _noop_route_wait_status(_blocker: String, _stalled_intervals: int = -1) -> void:
	pass

func _noop_route_outcome(
	_outcome: String,
	_blocker: String,
	_stalled_intervals: int = -1,
	_failure_message: String = ""
) -> void:
	pass

func _noop_route_progress(_route_preset_name: StringName, _targets: Array[Vector2], _target_index: int) -> void:
	pass

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

func _get_chunk_manager_array_size(field_name: String) -> int:
	if _chunk_manager == null:
		return 0
	return _get_variant_size(_get_chunk_manager_value(field_name))

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

func _has_chunk_manager_object(field_name: String) -> bool:
	return _chunk_manager != null and _get_chunk_manager_value(field_name) != null

func _get_chunk_manager_value(field_name: String) -> Variant:
	var streaming_service: Variant = _chunk_manager.get("_chunk_streaming_service") if _chunk_manager != null else null
	match field_name:
		"_load_queue":
			return streaming_service.get("load_queue") if streaming_service != null else _chunk_manager.get(field_name)
		"_staged_chunk":
			return streaming_service.get("staged_chunk") if streaming_service != null else _chunk_manager.get(field_name)
		"_staged_data":
			return streaming_service.get("staged_data") if streaming_service != null else _chunk_manager.get(field_name)
		"_gen_task_id":
			return streaming_service.get("gen_task_id") if streaming_service != null else _chunk_manager.get(field_name)
		_:
			return _chunk_manager.get(field_name)

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

func _get_variant_size(value: Variant) -> int:
	if value is Array:
		return (value as Array).size()
	if value is Dictionary:
		return (value as Dictionary).size()
	return 0
