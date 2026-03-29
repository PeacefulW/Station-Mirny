class_name RuntimeValidationDriver
extends Node

## Small debug-only driver for reproducible runtime perf validation.
## Activates only when launched with the user arg `codex_validate_runtime`.

const ENABLE_ARG: String = "codex_validate_runtime"
const HarvestTileCommandScript = preload("res://core/systems/commands/harvest_tile_command.gd")
const START_SETTLE_FRAMES: int = 60
const SEGMENT_SETTLE_FRAMES: int = 30
const TAIL_SETTLE_FRAMES: int = 180
const TOPOLOGY_WAIT_TIMEOUT_FRAMES: int = 360
const CATCH_UP_STATUS_LOG_INTERVAL_FRAMES: int = 60
const MINING_SETTLE_FRAMES: int = 20
const ROOM_SETTLE_FRAMES: int = 12
const ROOM_WAIT_TIMEOUT_FRAMES: int = 180
const POWER_SETTLE_FRAMES: int = 12
const POWER_WAIT_TIMEOUT_FRAMES: int = 180
const ARRIVE_DISTANCE_PX: float = 16.0
const MOVE_SPEED_PX_PER_SEC: float = 8192.0
const ROUTE_CHUNK_OFFSETS: Array[Vector2i] = [
	Vector2i(6, 0),
	Vector2i(6, 5),
	Vector2i(-5, 5),
	Vector2i(-5, -4),
	Vector2i(0, -4),
	Vector2i(0, 0),
]
const INVALID_TILE: Vector2i = Vector2i(999999, 999999)
const _CARDINAL_DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const _ALLOWED_CHUNK_STATE_KEYS := {
	&"terrain": true,
}

var _game_world: GameWorld = null
var _player: Player = null
var _building_system: BuildingSystem = null
var _power_system: PowerSystem = null
var _life_support: BaseLifeSupport = null
var _chunk_manager: ChunkManager = null
var _mountain_roof_system: MountainRoofSystem = null
var _command_executor: CommandExecutor = null
var _targets: Array[Vector2] = []
var _target_index: int = 0
var _start_frames_remaining: int = START_SETTLE_FRAMES
var _segment_frames_remaining: int = 0
var _tail_frames_remaining: int = -1
var _topology_wait_frames_remaining: int = -1
var _catch_up_status_frames_remaining: int = -1
var _last_catch_up_signature: String = ""
var _unchanged_catch_up_status_count: int = 0
var _started: bool = false
var _route_announced: bool = false
var _room_validation_stage: int = -1
var _room_wait_frames_remaining: int = 0
var _room_wait_timeout_frames_remaining: int = -1
var _room_case: Dictionary = {}
var _power_validation_stage: int = -1
var _power_wait_frames_remaining: int = 0
var _power_wait_timeout_frames_remaining: int = -1
var _power_case: Dictionary = {}
var _mining_validation_stage: int = -1
var _mining_wait_frames_remaining: int = 0
var _mining_case: Dictionary = {}
var _mining_zone_tile_count_before_extension: int = 0
var _mining_save_snapshot: Dictionary = {}

func _ready() -> void:
	_game_world = get_parent() as GameWorld
	if not _is_enabled():
		queue_free()
		return
	print("[CodexValidation] runtime validation driver enabled")

func _process(delta: float) -> void:
	if not _is_enabled():
		return
	if not _started:
		if not _game_world or not _game_world.is_boot_complete():
			return
		_resolve_player()
		_resolve_building_system()
		_resolve_power_system()
		_resolve_life_support()
		_resolve_chunk_manager()
		_resolve_mountain_roof_system()
		_resolve_command_executor()
		if not _player or not _building_system or not _power_system or not _life_support or not WorldGenerator or not WorldGenerator.balance or not _mountain_roof_system:
			return
		_build_route()
		_prepare_room_validation()
		_prepare_power_validation()
		_prepare_mining_validation()
		_started = true
		print("[CodexValidation] boot complete; route prepared")
		return
	if _start_frames_remaining > 0:
		_start_frames_remaining -= 1
		return
	if _room_validation_stage >= 0:
		_process_room_validation()
		return
	if _power_validation_stage >= 0:
		_process_power_validation()
		return
	if _mining_validation_stage >= 0:
		_process_mining_validation()
		return
	if _segment_frames_remaining > 0:
		_segment_frames_remaining -= 1
		return
	if _tail_frames_remaining >= 0:
		if _tail_frames_remaining > 0:
			_tail_frames_remaining -= 1
			return
		if _is_runtime_caught_up():
			if _has_redraw_backlog():
				print("[CodexValidation] route drain complete with redraw backlog: %s" % [_describe_chunk_manager_catch_up_state()])
			else:
				print("[CodexValidation] route drain complete; quitting")
			get_tree().quit()
			return
		if _topology_wait_frames_remaining < 0:
			_topology_wait_frames_remaining = TOPOLOGY_WAIT_TIMEOUT_FRAMES
			_catch_up_status_frames_remaining = 0
			_last_catch_up_signature = ""
			_unchanged_catch_up_status_count = 0
			print("[CodexValidation] waiting for world catch-up")
		if _catch_up_status_frames_remaining <= 0:
			var catch_up_signature: String = _build_catch_up_signature()
			if catch_up_signature == _last_catch_up_signature:
				_unchanged_catch_up_status_count += 1
			else:
				_last_catch_up_signature = catch_up_signature
				_unchanged_catch_up_status_count = 0
			print("[CodexValidation] catch-up status: blocker=%s stalled_intervals=%d %s" % [
				_describe_catch_up_blocker(),
				_unchanged_catch_up_status_count,
				_describe_chunk_manager_catch_up_state(),
			])
			_catch_up_status_frames_remaining = CATCH_UP_STATUS_LOG_INTERVAL_FRAMES
		if _topology_wait_frames_remaining > 0:
			_topology_wait_frames_remaining -= 1
			_catch_up_status_frames_remaining -= 1
			return
		_fail_validation("world catch-up timeout: blocker=%s stalled_intervals=%d %s" % [
			_describe_catch_up_blocker(),
			_unchanged_catch_up_status_count,
			_describe_chunk_manager_catch_up_state(),
		])
		return
	if _target_index >= _targets.size():
		_tail_frames_remaining = TAIL_SETTLE_FRAMES
		_topology_wait_frames_remaining = -1
		_catch_up_status_frames_remaining = -1
		_last_catch_up_signature = ""
		_unchanged_catch_up_status_count = 0
		print("[CodexValidation] route complete; draining background work")
		return
	if not _route_announced:
		_route_announced = true
		print("[CodexValidation] route start")
	var target: Vector2 = _targets[_target_index]
	var display_target: Vector2 = _resolve_route_display_target(target)
	_player.global_position = _player.global_position.move_toward(
		display_target,
		MOVE_SPEED_PX_PER_SEC * delta
	)
	if _player.global_position.distance_to(display_target) <= ARRIVE_DISTANCE_PX:
		_player.global_position = _canonicalize_world_position(target)
		print("[CodexValidation] reached waypoint %d/%d at %s" % [
			_target_index + 1,
			_targets.size(),
			target,
		])
		_target_index += 1
		_segment_frames_remaining = SEGMENT_SETTLE_FRAMES

func _is_enabled() -> bool:
	return ENABLE_ARG in OS.get_cmdline_user_args()

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

func _build_route() -> void:
	_targets.clear()
	var chunk_pixels: float = float(WorldGenerator.balance.get_chunk_size_pixels())
	var start: Vector2 = _canonicalize_world_position(_player.global_position)
	for offset: Vector2i in ROUTE_CHUNK_OFFSETS:
		_targets.append(_canonicalize_world_position(
			start + Vector2(offset.x, offset.y) * chunk_pixels
		))

func _resolve_route_display_target(canonical_target: Vector2) -> Vector2:
	if _player == null or WorldGenerator == null:
		return canonical_target
	return WorldGenerator.get_display_world_position(canonical_target, _player.global_position)

func _canonicalize_world_position(world_pos: Vector2) -> Vector2:
	if WorldGenerator == null:
		return world_pos
	return WorldGenerator.canonicalize_world_position(world_pos)

func _is_topology_caught_up() -> bool:
	return _chunk_manager == null or _chunk_manager.is_topology_ready()

func _is_runtime_caught_up() -> bool:
	return _is_streaming_truth_caught_up() and _is_topology_caught_up()

func _is_streaming_truth_caught_up() -> bool:
	if _chunk_manager == null:
		return true
	if _get_variant_size(_chunk_manager.get("_load_queue")) > 0:
		return false
	if _chunk_manager.get("_staged_chunk") != null:
		return false
	if _get_variant_size(_chunk_manager.get("_staged_data")) > 0:
		return false
	return int(_chunk_manager.get("_gen_task_id")) < 0

func _has_redraw_backlog() -> bool:
	return _chunk_manager != null and _get_variant_size(_chunk_manager.get("_redrawing_chunks")) > 0

func _build_catch_up_signature() -> String:
	if _chunk_manager == null:
		return "chunk_manager=missing"
	return "%s|%d|%d|%s|%d|%d|%s|%s|%s|%s|%s" % [
		_describe_catch_up_blocker(),
		_get_variant_size(_chunk_manager.get("_load_queue")),
		_get_variant_size(_chunk_manager.get("_redrawing_chunks")),
		"yes" if _chunk_manager.get("_staged_chunk") != null else "no",
		_get_variant_size(_chunk_manager.get("_staged_data")),
		int(_chunk_manager.get("_gen_task_id")),
		str(_is_topology_caught_up()),
		str(bool(_chunk_manager.get("_native_topology_active"))),
		str(bool(_chunk_manager.get("_native_topology_dirty"))),
		str(bool(_chunk_manager.get("_is_topology_dirty"))),
		str(bool(_chunk_manager.get("_is_topology_build_in_progress"))),
	]

func _describe_catch_up_blocker() -> String:
	if not _is_topology_caught_up():
		return "topology"
	if not _is_streaming_truth_caught_up():
		return "streaming_truth"
	if _has_redraw_backlog():
		return "redraw_only"
	return "none"

func _describe_chunk_manager_catch_up_state() -> String:
	if _chunk_manager == null:
		return "chunk_manager=missing"
	var streaming_truth_idle: bool = _is_streaming_truth_caught_up()
	var topology_ready: bool = _is_topology_caught_up()
	var load_queue_preview: Array[String] = []
	var load_queue: Array = _chunk_manager.get("_load_queue") as Array
	for request_variant: Variant in load_queue.slice(0, mini(3, load_queue.size())):
		var request: Dictionary = request_variant as Dictionary
		load_queue_preview.append(str(request.get("coord", Vector2i.ZERO)))
	var gen_coord: Vector2i = _chunk_manager.get("_gen_coord") as Vector2i
	if gen_coord == null:
		gen_coord = Vector2i(999999, 999999)
	return "streaming_truth_idle=%s redraw_idle=%s load_queue=%d load_queue_preview=%s redraw=%d staged_chunk=%s staged_data=%d gen_task_id=%d gen_coord=%s topology_ready=%s native_topology=%s native_dirty=%s dirty=%s build_in_progress=%s" % [
		streaming_truth_idle,
		not _has_redraw_backlog(),
		_get_variant_size(_chunk_manager.get("_load_queue")),
		str(load_queue_preview),
		_get_variant_size(_chunk_manager.get("_redrawing_chunks")),
		"yes" if _chunk_manager.get("_staged_chunk") != null else "no",
		_get_variant_size(_chunk_manager.get("_staged_data")),
		int(_chunk_manager.get("_gen_task_id")),
		str(gen_coord),
		topology_ready,
		bool(_chunk_manager.get("_native_topology_active")),
		bool(_chunk_manager.get("_native_topology_dirty")),
		bool(_chunk_manager.get("_is_topology_dirty")),
		bool(_chunk_manager.get("_is_topology_build_in_progress")),
	]

func _get_variant_size(value: Variant) -> int:
	if value is Array:
		return (value as Array).size()
	if value is Dictionary:
		return (value as Dictionary).size()
	return 0

func _prepare_room_validation() -> void:
	if not _building_system or not _player:
		print("[CodexValidation] room validation skipped; building system unavailable")
		_room_validation_stage = -1
		return
	_player.collect_scrap(64)
	var origin: Vector2i = _building_system.world_to_grid(_player.global_position) + Vector2i(4, 4)
	_room_case = {
		"wall_tiles": [
			origin + Vector2i(0, 0),
			origin + Vector2i(1, 0),
			origin + Vector2i(2, 0),
			origin + Vector2i(0, 1),
			origin + Vector2i(2, 1),
			origin + Vector2i(0, 2),
			origin + Vector2i(1, 2),
			origin + Vector2i(2, 2),
		],
		"interior_tile": origin + Vector2i(1, 1),
		"removed_tile": origin + Vector2i(1, 0),
		"destroyed_tile": origin + Vector2i(0, 1),
	}
	_room_validation_stage = 0
	print("[CodexValidation] room validation prepared at %s" % [origin])

func _process_room_validation() -> void:
	if _process_room_wait_if_needed():
		return
	match _room_validation_stage:
		0:
			if not _build_validation_room():
				_fail_validation("failed to place validation room walls")
				return
			print("[CodexValidation] built validation room")
			_begin_room_wait()
		1:
			if not _building_system.is_cell_indoor(_room_case.get("interior_tile", Vector2i.ZERO)):
				_fail_validation("closed validation room did not become indoor")
				return
			if not _remove_validation_building(_room_case.get("removed_tile", Vector2i.ZERO)):
				_fail_validation("failed to remove validation room wall")
				return
			print("[CodexValidation] removed validation room wall %s" % [_room_case["removed_tile"]])
			_begin_room_wait()
		2:
			if _building_system.is_cell_indoor(_room_case.get("interior_tile", Vector2i.ZERO)):
				_fail_validation("breached validation room remained indoor")
				return
			if not _place_validation_building("wall", _room_case.get("removed_tile", Vector2i.ZERO)):
				_fail_validation("failed to re-place validation room wall")
				return
			print("[CodexValidation] re-placed validation room wall %s" % [_room_case["removed_tile"]])
			_begin_room_wait()
		3:
			if not _building_system.is_cell_indoor(_room_case.get("interior_tile", Vector2i.ZERO)):
				_fail_validation("reclosed validation room did not become indoor")
				return
			if not _destroy_validation_building(_room_case.get("destroyed_tile", Vector2i.ZERO)):
				_fail_validation("failed to destroy validation room wall")
				return
			print("[CodexValidation] destroyed validation room wall %s" % [_room_case["destroyed_tile"]])
			_begin_room_wait()
		4:
			if _building_system.is_cell_indoor(_room_case.get("interior_tile", Vector2i.ZERO)):
				_fail_validation("destroyed-wall validation room remained indoor")
				return
			print("[CodexValidation] room validation complete")
			_room_validation_stage = -1
		_:
			_room_validation_stage = -1

func _process_room_wait_if_needed() -> bool:
	if _room_wait_timeout_frames_remaining < 0:
		return false
	if _building_system and _building_system.has_pending_room_recompute():
		_room_wait_timeout_frames_remaining -= 1
		_room_wait_frames_remaining = ROOM_SETTLE_FRAMES
		if _room_wait_timeout_frames_remaining <= 0:
			_fail_validation("room recompute did not settle within timeout")
		return true
	if _room_wait_frames_remaining > 0:
		_room_wait_frames_remaining -= 1
		return true
	_room_wait_timeout_frames_remaining = -1
	_room_validation_stage += 1
	return true

func _begin_room_wait() -> void:
	_room_wait_frames_remaining = ROOM_SETTLE_FRAMES
	_room_wait_timeout_frames_remaining = ROOM_WAIT_TIMEOUT_FRAMES

func _build_validation_room() -> bool:
	for tile: Vector2i in _room_case.get("wall_tiles", []):
		if not _place_validation_building("wall", tile):
			return false
	return true

func _prepare_power_validation() -> void:
	if not _building_system or not _power_system or not _life_support or not _player:
		print("[CodexValidation] power validation skipped; required systems unavailable")
		_power_validation_stage = -1
		return
	_player.collect_scrap(64)
	var battery_tile: Vector2i = _building_system.world_to_grid(_player.global_position) + Vector2i(8, 4)
	_power_case = {
		"battery_tile": battery_tile,
		"baseline_source_count": _power_system.get_registered_source_count(),
		"baseline_consumer_count": _power_system.get_registered_consumer_count(),
		"baseline_supply": _power_system.total_supply,
		"baseline_demand": _power_system.total_demand,
		"baseline_powered": _life_support.is_powered(),
	}
	_power_validation_stage = 0
	print("[CodexValidation] power validation prepared at %s" % [battery_tile])

func _process_power_validation() -> void:
	if _process_power_wait_if_needed():
		return
	match _power_validation_stage:
		0:
			if int(_power_case.get("baseline_consumer_count", 0)) <= 0:
				_fail_validation("power validation found no registered consumers")
				return
			if not _place_validation_building("ark_battery", _power_case.get("battery_tile", Vector2i.ZERO)):
				_fail_validation("failed to place validation battery")
				return
			print("[CodexValidation] placed validation battery %s" % [_power_case["battery_tile"]])
			_begin_power_wait()
		1:
			var baseline_sources: int = int(_power_case.get("baseline_source_count", 0))
			if _power_system.get_registered_source_count() != baseline_sources + 1:
				_fail_validation("power registry did not add validation battery source")
				return
			if _power_system.total_supply <= float(_power_case.get("baseline_supply", 0.0)):
				_fail_validation("power supply did not increase after validation battery placement")
				return
			if not _life_support.is_powered():
				_fail_validation("life support did not become powered after validation battery placement")
				return
			if not _remove_validation_building(_power_case.get("battery_tile", Vector2i.ZERO)):
				_fail_validation("failed to remove validation battery")
				return
			print("[CodexValidation] removed validation battery %s" % [_power_case["battery_tile"]])
			_begin_power_wait()
		2:
			if _power_system.get_registered_source_count() != int(_power_case.get("baseline_source_count", 0)):
				_fail_validation("power registry did not remove validation battery source")
				return
			if not is_equal_approx(_power_system.total_supply, float(_power_case.get("baseline_supply", 0.0))):
				_fail_validation("power supply did not return to baseline after validation battery removal")
				return
			if _life_support.is_powered() != bool(_power_case.get("baseline_powered", false)):
				_fail_validation("life support power state did not return to baseline after battery removal")
				return
			print("[CodexValidation] power validation complete")
			_power_validation_stage = -1
		_:
			_power_validation_stage = -1

func _process_power_wait_if_needed() -> bool:
	if _power_wait_timeout_frames_remaining < 0:
		return false
	if _power_system and _power_system.has_pending_recompute():
		_power_wait_timeout_frames_remaining -= 1
		_power_wait_frames_remaining = POWER_SETTLE_FRAMES
		if _power_wait_timeout_frames_remaining <= 0:
			_fail_validation("power recompute did not settle within timeout")
		return true
	if _power_wait_frames_remaining > 0:
		_power_wait_frames_remaining -= 1
		return true
	_power_wait_timeout_frames_remaining = -1
	_power_validation_stage += 1
	return true

func _begin_power_wait() -> void:
	_power_wait_frames_remaining = POWER_SETTLE_FRAMES
	_power_wait_timeout_frames_remaining = POWER_WAIT_TIMEOUT_FRAMES

func _place_validation_building(building_id: String, tile_pos: Vector2i) -> bool:
	if not _building_system:
		return false
	var building_data: BuildingData = BuildingCatalog.get_default_building(building_id)
	if not building_data:
		return false
	_building_system.set_selected_building(building_data)
	var result: Dictionary = _building_system.place_selected_building_at(_building_system.grid_to_world(tile_pos))
	return bool(result.get("success", false))

func _remove_validation_building(tile_pos: Vector2i) -> bool:
	if not _building_system:
		return false
	var result: Dictionary = _building_system.remove_building_at(_building_system.grid_to_world(tile_pos))
	return bool(result.get("success", false))

func _destroy_validation_building(tile_pos: Vector2i) -> bool:
	if not _building_system or not _building_system.has_building_at(tile_pos):
		return false
	var building_node: Node2D = _building_system.get_building_node_at(tile_pos)
	if not building_node:
		return false
	var health: HealthComponent = building_node.get_node_or_null("HealthComponent")
	if not health:
		return false
	health.take_damage(health.current_health + health.max_health)
	return true

func _prepare_mining_validation() -> void:
	_mining_case = _find_mining_validation_case()
	if _mining_case.is_empty():
		print("[CodexValidation] mining validation skipped; no suitable mountain edge found in loaded chunks")
		_mining_validation_stage = -1
		return
	_mining_validation_stage = 0
	print("[CodexValidation] mining validation prepared at %s" % [_mining_case.get("entry_tile", INVALID_TILE)])

func _process_mining_validation() -> void:
	if _mining_wait_frames_remaining > 0:
		_mining_wait_frames_remaining -= 1
		return
	match _mining_validation_stage:
		0:
			if not _mine_tile(_mining_case.get("entry_tile", INVALID_TILE)):
				_fail_validation("failed to mine entry tile")
				return
			print("[CodexValidation] mined entry tile %s" % [_mining_case["entry_tile"]])
			_mining_validation_stage = 1
			_mining_wait_frames_remaining = MINING_SETTLE_FRAMES
		1:
			if not _mine_tile(_mining_case.get("interior_tile", INVALID_TILE)):
				_fail_validation("failed to mine interior tile")
				return
			print("[CodexValidation] mined interior tile %s" % [_mining_case["interior_tile"]])
			_player.global_position = _tile_to_world_center(_mining_case["interior_tile"])
			_mining_validation_stage = 2
			_mining_wait_frames_remaining = MINING_SETTLE_FRAMES
		2:
			if not _mountain_roof_system.has_active_local_zone():
				_fail_validation("local reveal zone did not activate after entering mined pocket")
				return
			_mining_zone_tile_count_before_extension = _mountain_roof_system.get_active_local_zone_tile_count()
			if _mining_zone_tile_count_before_extension <= 0:
				_fail_validation("active local zone tile count is zero after entering mined pocket")
				return
			var deeper_tile: Vector2i = _mining_case.get("deeper_tile", INVALID_TILE)
			if deeper_tile == INVALID_TILE:
				print("[CodexValidation] mining validation has no deeper tile; skipping extension step")
				_mining_validation_stage = 4
				return
			if not _mine_tile(deeper_tile):
				_fail_validation("failed to mine deeper tile for local-zone extension")
				return
			print("[CodexValidation] mined deeper tile %s" % [deeper_tile])
			_mining_validation_stage = 3
			_mining_wait_frames_remaining = MINING_SETTLE_FRAMES
		3:
			var extended_count: int = _mountain_roof_system.get_active_local_zone_tile_count()
			if extended_count <= _mining_zone_tile_count_before_extension:
				_fail_validation("local reveal zone did not expand after deeper mining")
				return
			_mining_validation_stage = 4
		4:
			_mining_save_snapshot = _chunk_manager.get_save_data().duplicate(true)
			if not _validate_chunk_save_payload(_mining_save_snapshot):
				_fail_validation("chunk save payload leaked local presentation state")
				return
			_player.global_position = _tile_to_world_center(_mining_case["exterior_tile"])
			print("[CodexValidation] moved player back to exterior tile %s" % [_mining_case["exterior_tile"]])
			_mining_validation_stage = 5
			_mining_wait_frames_remaining = MINING_SETTLE_FRAMES
		5:
			if _mountain_roof_system.has_active_local_zone():
				_fail_validation("local reveal zone remained active after returning to exterior")
				return
			var post_exit_save: Dictionary = _chunk_manager.get_save_data().duplicate(true)
			if post_exit_save != _mining_save_snapshot:
				_fail_validation("chunk save payload changed on reveal-only movement without new mining")
				return
			var collected_chunk_save: Dictionary = SaveCollectors.collect_chunk_data(get_tree()).duplicate(true)
			if collected_chunk_save != _mining_save_snapshot:
				_fail_validation("SaveCollectors chunk payload diverged from ChunkManager save snapshot")
				return
			print("[CodexValidation] mining + persistence validation complete")
			_mining_validation_stage = -1
		_:
			_mining_validation_stage = -1

func _find_mining_validation_case() -> Dictionary:
	if not _chunk_manager or not _player or not WorldGenerator:
		return {}
	var player_chunk: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	var chunk_coords: Array[Vector2i] = []
	for coord: Vector2i in _chunk_manager.get_loaded_chunks():
		chunk_coords.append(coord)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = absi(a.x - player_chunk.x) + absi(a.y - player_chunk.y)
		var db: int = absi(b.x - player_chunk.x) + absi(b.y - player_chunk.y)
		return da < db
	)
	for coord: Vector2i in chunk_coords:
		var chunk: Chunk = _chunk_manager.get_chunk(coord)
		if not chunk or not chunk.has_any_mountain():
			continue
		var chunk_size: int = chunk.get_chunk_size()
		for local_y: int in range(chunk_size):
			for local_x: int in range(chunk_size):
				var local_tile: Vector2i = Vector2i(local_x, local_y)
				if chunk.get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
					continue
				var global_tile: Vector2i = Vector2i(
					coord.x * chunk_size + local_x,
					coord.y * chunk_size + local_y
				)
				for dir: Vector2i in _CARDINAL_DIRS:
					var exterior_tile: Vector2i = global_tile - dir
					var interior_tile: Vector2i = global_tile + dir
					if not _chunk_manager.is_tile_loaded(exterior_tile) or not _chunk_manager.is_tile_loaded(interior_tile):
						continue
					if not _is_validation_exterior_tile(_chunk_manager.get_terrain_type_at_global(exterior_tile)):
						continue
					if _chunk_manager.get_terrain_type_at_global(interior_tile) != TileGenData.TerrainType.ROCK:
						continue
					var deeper_tile: Vector2i = interior_tile + dir
					if not _chunk_manager.is_tile_loaded(deeper_tile) or _chunk_manager.get_terrain_type_at_global(deeper_tile) != TileGenData.TerrainType.ROCK:
						deeper_tile = INVALID_TILE
					return {
						"exterior_tile": exterior_tile,
						"entry_tile": global_tile,
						"interior_tile": interior_tile,
						"deeper_tile": deeper_tile,
					}
	return {}

func _is_validation_exterior_tile(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.GRASS \
		or terrain_type == TileGenData.TerrainType.SAND

func _mine_tile(tile_pos: Vector2i) -> bool:
	if tile_pos == INVALID_TILE or not _chunk_manager or not _command_executor:
		return false
	var command := HarvestTileCommandScript.new().setup(_chunk_manager, _tile_to_world_center(tile_pos))
	var result: Dictionary = _command_executor.execute(command)
	return not result.is_empty()

func _tile_to_world_center(tile_pos: Vector2i) -> Vector2:
	var tile_size: float = float(WorldGenerator.balance.tile_size)
	return Vector2(
		(float(tile_pos.x) + 0.5) * tile_size,
		(float(tile_pos.y) + 0.5) * tile_size
	)

func _validate_chunk_save_payload(chunk_save_data: Dictionary) -> bool:
	for chunk_key: Variant in chunk_save_data:
		if not (chunk_key is Vector2i or chunk_key is Vector3i):
			return false
		var chunk_entry: Dictionary = chunk_save_data.get(chunk_key, {}) as Dictionary
		for local_tile_key: Variant in chunk_entry:
			if not (local_tile_key is Vector2i):
				return false
			var tile_state: Dictionary = chunk_entry.get(local_tile_key, {}) as Dictionary
			for state_key in tile_state.keys():
				var key_string: String = str(state_key).to_lower()
				if not _ALLOWED_CHUNK_STATE_KEYS.has(StringName(key_string)):
					return false
	return true

func _fail_validation(message: String) -> void:
	push_error(message)
	print("[CodexValidation] validation failed: %s" % [message])
	get_tree().quit(1)
