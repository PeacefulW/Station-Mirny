class_name ValidationContext
extends RefCounted

const HarvestTileCommandScript = preload("res://core/systems/commands/harvest_tile_command.gd")

const INVALID_TILE: Vector2i = Vector2i(999999, 999999)
const _CARDINAL_DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const _ALLOWED_CHUNK_STATE_KEYS := {
	&"terrain": true,
}

var game_world: GameWorld = null
var player: Player = null
var building_system: BuildingSystem = null
var power_system: PowerSystem = null
var life_support: BaseLifeSupport = null
var chunk_manager: ChunkManager = null
var mountain_roof_system: MountainRoofSystem = null
var command_executor: CommandExecutor = null
var route_presets: Dictionary = {}
var default_route_preset: StringName = &"local_ring"

var _log_status_callback: Callable = Callable()
var _emit_route_wait_status_callback: Callable = Callable()
var _emit_route_outcome_callback: Callable = Callable()
var _set_route_progress_callback: Callable = Callable()
var _is_runtime_caught_up_callback: Callable = Callable()
var _describe_catch_up_blocker_callback: Callable = Callable()
var _build_catch_up_signature_callback: Callable = Callable()
var _has_redraw_backlog_callback: Callable = Callable()
var _used_mining_entry_keys: Dictionary = {}

func configure(
	in_game_world: GameWorld,
	in_player: Player,
	in_building_system: BuildingSystem,
	in_power_system: PowerSystem,
	in_life_support: BaseLifeSupport,
	in_chunk_manager: ChunkManager,
	in_mountain_roof_system: MountainRoofSystem,
	in_command_executor: CommandExecutor,
	in_route_presets: Dictionary,
	in_default_route_preset: StringName,
	log_status_callback: Callable,
	emit_route_wait_status_callback: Callable,
	emit_route_outcome_callback: Callable,
	set_route_progress_callback: Callable,
	is_runtime_caught_up_callback: Callable,
	describe_catch_up_blocker_callback: Callable,
	build_catch_up_signature_callback: Callable,
	has_redraw_backlog_callback: Callable
) -> ValidationContext:
	game_world = in_game_world
	player = in_player
	building_system = in_building_system
	power_system = in_power_system
	life_support = in_life_support
	chunk_manager = in_chunk_manager
	mountain_roof_system = in_mountain_roof_system
	command_executor = in_command_executor
	route_presets = in_route_presets.duplicate(true)
	default_route_preset = in_default_route_preset
	_log_status_callback = log_status_callback
	_emit_route_wait_status_callback = emit_route_wait_status_callback
	_emit_route_outcome_callback = emit_route_outcome_callback
	_set_route_progress_callback = set_route_progress_callback
	_is_runtime_caught_up_callback = is_runtime_caught_up_callback
	_describe_catch_up_blocker_callback = describe_catch_up_blocker_callback
	_build_catch_up_signature_callback = build_catch_up_signature_callback
	_has_redraw_backlog_callback = has_redraw_backlog_callback
	return self

func log_status(message: String) -> void:
	if _log_status_callback.is_valid():
		_log_status_callback.call(message)

func emit_route_wait_status(blocker: String, stalled_intervals: int = -1) -> void:
	if _emit_route_wait_status_callback.is_valid():
		_emit_route_wait_status_callback.call(blocker, stalled_intervals)

func emit_route_outcome(
	outcome: String,
	blocker: String,
	stalled_intervals: int = -1,
	failure_message: String = ""
) -> void:
	if _emit_route_outcome_callback.is_valid():
		_emit_route_outcome_callback.call(outcome, blocker, stalled_intervals, failure_message)

func set_route_progress(route_preset_name: StringName, targets: Array[Vector2], target_index: int) -> void:
	if _set_route_progress_callback.is_valid():
		_set_route_progress_callback.call(route_preset_name, targets, target_index)

func is_runtime_caught_up() -> bool:
	if _is_runtime_caught_up_callback.is_valid():
		return bool(_is_runtime_caught_up_callback.call())
	return true

func describe_catch_up_blocker() -> String:
	if _describe_catch_up_blocker_callback.is_valid():
		return str(_describe_catch_up_blocker_callback.call())
	return "none"

func build_catch_up_signature() -> String:
	if _build_catch_up_signature_callback.is_valid():
		return str(_build_catch_up_signature_callback.call())
	return "none"

func has_redraw_backlog() -> bool:
	if _has_redraw_backlog_callback.is_valid():
		return bool(_has_redraw_backlog_callback.call())
	return false

func resolve_route_offsets(route_preset_name: StringName) -> Array[Vector2i]:
	var preset_offsets: Array = route_presets.get(route_preset_name, route_presets.get(default_route_preset, [])) as Array
	var resolved: Array[Vector2i] = []
	for offset_variant: Variant in preset_offsets:
		resolved.append(offset_variant as Vector2i)
	return resolved

func build_route_targets(route_offsets: Array) -> Array[Vector2]:
	var targets: Array[Vector2] = []
	if player == null or WorldGenerator == null or WorldGenerator.balance == null:
		return targets
	var chunk_pixels: float = float(WorldGenerator.balance.get_chunk_size_pixels())
	var start: Vector2 = canonicalize_world_position(player.global_position)
	for offset_variant: Variant in route_offsets:
		var offset: Vector2i = offset_variant as Vector2i
		targets.append(canonicalize_world_position(
			start + Vector2(offset.x, offset.y) * chunk_pixels
		))
	return targets

func resolve_route_display_target(canonical_target: Vector2) -> Vector2:
	if player == null or WorldGenerator == null:
		return canonical_target
	return WorldGenerator.get_display_world_position(canonical_target, player.global_position)

func set_validation_player_velocity(velocity: Vector2) -> void:
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = velocity

func canonicalize_world_position(world_pos: Vector2) -> Vector2:
	if WorldGenerator == null:
		return world_pos
	return WorldGenerator.canonicalize_world_position(world_pos)

func collect_validation_scrap(amount: int) -> void:
	if player != null and player.has_method("collect_scrap"):
		player.collect_scrap(amount)

func place_validation_building(building_id: String, tile_pos: Vector2i) -> bool:
	if building_system == null:
		return false
	var building_data: BuildingData = BuildingCatalog.get_default_building(building_id)
	if building_data == null:
		return false
	building_system.set_selected_building(building_data)
	var result: Dictionary = building_system.place_selected_building_at(building_system.grid_to_world(tile_pos))
	return bool(result.get("success", false))

func remove_validation_building(tile_pos: Vector2i) -> bool:
	if building_system == null:
		return false
	var result: Dictionary = building_system.remove_building_at(building_system.grid_to_world(tile_pos))
	return bool(result.get("success", false))

func destroy_validation_building(tile_pos: Vector2i) -> bool:
	if building_system == null or not building_system.has_building_at(tile_pos):
		return false
	var building_node: Node2D = building_system.get_building_node_at(tile_pos)
	if building_node == null:
		return false
	var health: HealthComponent = building_node.get_node_or_null("HealthComponent")
	if health == null:
		return false
	health.take_damage(health.current_health + health.max_health)
	return true

func acquire_mining_validation_case(require_deeper_tile: bool = false) -> Dictionary:
	if chunk_manager == null or player == null or WorldGenerator == null:
		return {}
	var player_chunk: Vector2i = WorldGenerator.world_to_chunk(player.global_position)
	var chunk_coords: Array[Vector2i] = []
	for coord_variant: Variant in chunk_manager.get_loaded_chunks().keys():
		chunk_coords.append(coord_variant as Vector2i)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = absi(a.x - player_chunk.x) + absi(a.y - player_chunk.y)
		var db: int = absi(b.x - player_chunk.x) + absi(b.y - player_chunk.y)
		return da < db
	)
	for coord: Vector2i in chunk_coords:
		var chunk: Chunk = chunk_manager.get_chunk(coord)
		if chunk == null or not chunk.has_any_mountain():
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
				if _used_mining_entry_keys.has(_vector_key(global_tile)):
					continue
				for dir: Vector2i in _CARDINAL_DIRS:
					var exterior_tile: Vector2i = global_tile - dir
					var interior_tile: Vector2i = global_tile + dir
					if not chunk_manager.is_tile_loaded(exterior_tile) or not chunk_manager.is_tile_loaded(interior_tile):
						continue
					if not _is_validation_exterior_tile(chunk_manager.get_terrain_type_at_global(exterior_tile)):
						continue
					if chunk_manager.get_terrain_type_at_global(interior_tile) != TileGenData.TerrainType.ROCK:
						continue
					var deeper_tile: Vector2i = interior_tile + dir
					if not chunk_manager.is_tile_loaded(deeper_tile) or chunk_manager.get_terrain_type_at_global(deeper_tile) != TileGenData.TerrainType.ROCK:
						deeper_tile = INVALID_TILE
					if require_deeper_tile and deeper_tile == INVALID_TILE:
						continue
					_used_mining_entry_keys[_vector_key(global_tile)] = true
					return {
						"exterior_tile": exterior_tile,
						"entry_tile": global_tile,
						"interior_tile": interior_tile,
						"deeper_tile": deeper_tile,
					}
	return {}

func mine_tile(tile_pos: Vector2i) -> bool:
	if tile_pos == INVALID_TILE or chunk_manager == null or command_executor == null:
		return false
	var command := HarvestTileCommandScript.new().setup(chunk_manager, tile_to_world_center(tile_pos))
	var result: Dictionary = command_executor.execute(command)
	return not result.is_empty()

func tile_to_world_center(tile_pos: Vector2i) -> Vector2:
	var tile_size: float = float(WorldGenerator.balance.tile_size)
	return Vector2(
		(float(tile_pos.x) + 0.5) * tile_size,
		(float(tile_pos.y) + 0.5) * tile_size
	)

func validate_chunk_save_payload(chunk_save_data: Dictionary) -> bool:
	for chunk_key: Variant in chunk_save_data:
		if not (chunk_key is Vector2i or chunk_key is Vector3i):
			return false
		var chunk_entry: Dictionary = chunk_save_data.get(chunk_key, {}) as Dictionary
		for local_tile_key: Variant in chunk_entry:
			if not (local_tile_key is Vector2i):
				return false
			var tile_state: Dictionary = chunk_entry.get(local_tile_key, {}) as Dictionary
			for state_key: Variant in tile_state.keys():
				var key_string: String = str(state_key).to_lower()
				if not _ALLOWED_CHUNK_STATE_KEYS.has(StringName(key_string)):
					return false
	return true

func _is_validation_exterior_tile(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.GRASS \
		or terrain_type == TileGenData.TerrainType.SAND

func _vector_key(tile_pos: Vector2i) -> String:
	return "%d:%d" % [tile_pos.x, tile_pos.y]
