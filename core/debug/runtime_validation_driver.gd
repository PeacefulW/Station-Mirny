class_name RuntimeValidationDriver
extends Node

## Small debug-only driver for reproducible runtime perf validation.
## Activates only when launched with the user arg `codex_validate_runtime`.

const ENABLE_ARG: String = "codex_validate_runtime"
const START_SETTLE_FRAMES: int = 60
const SEGMENT_SETTLE_FRAMES: int = 30
const TAIL_SETTLE_FRAMES: int = 180
const TOPOLOGY_WAIT_TIMEOUT_FRAMES: int = 360
const MINING_SETTLE_FRAMES: int = 20
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

var _game_world: GameWorld = null
var _player: Player = null
var _chunk_manager: ChunkManager = null
var _mountain_roof_system: MountainRoofSystem = null
var _targets: Array[Vector2] = []
var _target_index: int = 0
var _start_frames_remaining: int = START_SETTLE_FRAMES
var _segment_frames_remaining: int = 0
var _tail_frames_remaining: int = -1
var _topology_wait_frames_remaining: int = -1
var _started: bool = false
var _route_announced: bool = false
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
		_resolve_chunk_manager()
		_resolve_mountain_roof_system()
		if not _player or not WorldGenerator or not WorldGenerator.balance or not _mountain_roof_system:
			return
		_build_route()
		_prepare_mining_validation()
		_started = true
		print("[CodexValidation] boot complete; route prepared")
		return
	if _start_frames_remaining > 0:
		_start_frames_remaining -= 1
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
		if _is_topology_caught_up():
			print("[CodexValidation] route drain complete; quitting")
			get_tree().quit()
			return
		if _topology_wait_frames_remaining < 0:
			_topology_wait_frames_remaining = TOPOLOGY_WAIT_TIMEOUT_FRAMES
			print("[CodexValidation] waiting for topology catch-up")
			return
		if _topology_wait_frames_remaining > 0:
			_topology_wait_frames_remaining -= 1
			return
		print("[CodexValidation] topology catch-up timeout; quitting")
		get_tree().quit()
		return
	if _target_index >= _targets.size():
		_tail_frames_remaining = TAIL_SETTLE_FRAMES
		_topology_wait_frames_remaining = -1
		print("[CodexValidation] route complete; draining background work")
		return
	if not _route_announced:
		_route_announced = true
		print("[CodexValidation] route start")
	var target: Vector2 = _targets[_target_index]
	_player.global_position = _player.global_position.move_toward(
		target,
		MOVE_SPEED_PX_PER_SEC * delta
	)
	if _player.global_position.distance_to(target) <= ARRIVE_DISTANCE_PX:
		_player.global_position = target
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

func _resolve_chunk_manager() -> void:
	var chunk_managers: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunk_managers.is_empty():
		_chunk_manager = chunk_managers[0] as ChunkManager

func _resolve_mountain_roof_system() -> void:
	if _game_world:
		_mountain_roof_system = _game_world.get_node_or_null("MountainRoofSystem") as MountainRoofSystem

func _build_route() -> void:
	_targets.clear()
	var chunk_pixels: float = float(WorldGenerator.balance.get_chunk_size_pixels())
	var start: Vector2 = _player.global_position
	for offset: Vector2i in ROUTE_CHUNK_OFFSETS:
		_targets.append(start + Vector2(offset.x, offset.y) * chunk_pixels)

func _is_topology_caught_up() -> bool:
	return _chunk_manager == null or _chunk_manager.is_topology_ready()

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
	if tile_pos == INVALID_TILE:
		return false
	var result: Dictionary = _chunk_manager.try_harvest_at_world(_tile_to_world_center(tile_pos))
	return not result.is_empty()

func _tile_to_world_center(tile_pos: Vector2i) -> Vector2:
	var tile_size: float = float(WorldGenerator.balance.tile_size)
	return Vector2(
		(float(tile_pos.x) + 0.5) * tile_size,
		(float(tile_pos.y) + 0.5) * tile_size
	)

func _validate_chunk_save_payload(chunk_save_data: Dictionary) -> bool:
	for chunk_coord: Vector2i in chunk_save_data:
		var chunk_entry: Dictionary = chunk_save_data.get(chunk_coord, {}) as Dictionary
		for local_tile: Vector2i in chunk_entry:
			var tile_state: Dictionary = chunk_entry.get(local_tile, {}) as Dictionary
			for state_key in tile_state.keys():
				var key_string: String = str(state_key).to_lower()
				if key_string.contains("reveal") or key_string.contains("roof") or key_string.contains("zone"):
					return false
	return true

func _fail_validation(message: String) -> void:
	push_error(message)
	print("[CodexValidation] validation failed: %s" % [message])
	get_tree().quit(1)
