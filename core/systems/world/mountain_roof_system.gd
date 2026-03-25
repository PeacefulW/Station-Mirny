class_name MountainRoofSystem
extends Node

## Координирует логическое состояние активной горы и cheap visual transition крыши.
## Persistent roof visuals строятся в фоне, а вход/выход из горы переключает только reveal state.

const INVALID_MOUNTAIN_KEY: Vector2i = Vector2i(999999, 999999)

var _chunk_manager: ChunkManager = null
var _player: Player = null
var _last_tile: Vector2i = INVALID_MOUNTAIN_KEY
var _active_mountain_key: Vector2i = INVALID_MOUNTAIN_KEY
var _is_player_on_mined_floor: bool = false
var _roof_visual_build_queue: Array[Vector2i] = []
var _roof_visual_building_chunks: Array[Chunk] = []
var _needs_full_roof_rebuild: bool = false

func _ready() -> void:
	EventBus.mountain_tile_mined.connect(_on_mountain_tile_mined)
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	call_deferred("_resolve_dependencies")

func _process(_delta: float) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	_check_player_mountain_state()

func _resolve_dependencies() -> void:
	var chunks: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunks.is_empty():
		_chunk_manager = chunks[0] as ChunkManager
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Player
	FrameBudgetDispatcher.register_job(&"visual", 2.0, _tick_roof_visuals)
	_mark_all_loaded_roof_visuals_dirty()
	_request_refresh()

func _check_player_mountain_state() -> void:
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	if player_tile == _last_tile:
		return
	_last_tile = player_tile
	var is_on_mined_floor: bool = _is_player_on_opened_mountain_tile(player_tile)
	if is_on_mined_floor == _is_player_on_mined_floor and (not is_on_mined_floor or _active_mountain_key != INVALID_MOUNTAIN_KEY):
		return
	_is_player_on_mined_floor = is_on_mined_floor
	_request_refresh()

func _request_refresh() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var start_tile: Vector2i = _find_reveal_start(player_tile)
	var next_mountain_key: Vector2i = INVALID_MOUNTAIN_KEY
	if start_tile != INVALID_MOUNTAIN_KEY:
		next_mountain_key = _chunk_manager.get_mountain_key_at_tile(start_tile)
		if next_mountain_key == INVALID_MOUNTAIN_KEY:
			return
	if next_mountain_key == _active_mountain_key:
		WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)
		return
	_active_mountain_key = next_mountain_key
	var affected_chunks: Array[Vector2i] = _chunk_manager.set_active_mountain_key(_active_mountain_key)
	_apply_reveal_state(affected_chunks, true)
	_prioritize_roof_visual_builds(affected_chunks)
	WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)

func _tick_roof_visuals() -> bool:
	if not _chunk_manager:
		return false
	if _needs_full_roof_rebuild and _chunk_manager.is_topology_ready():
		_mark_all_loaded_roof_visuals_dirty()
		_needs_full_roof_rebuild = false
	if not _chunk_manager.is_topology_ready():
		return _needs_full_roof_rebuild or not _roof_visual_build_queue.is_empty() or not _roof_visual_building_chunks.is_empty()
	var setup_count: int = 0
	while not _roof_visual_build_queue.is_empty() and setup_count < 2:
		var coord: Vector2i = _roof_visual_build_queue.pop_front()
		var chunk: Chunk = _chunk_manager.get_chunk(coord)
		if not chunk or not chunk.has_any_mountain():
			continue
		if chunk.begin_roof_visual_build() and chunk not in _roof_visual_building_chunks:
			_roof_visual_building_chunks.append(chunk)
		setup_count += 1
	if _roof_visual_building_chunks.is_empty():
		return not _roof_visual_build_queue.is_empty()
	var chunk: Chunk = _roof_visual_building_chunks[0]
	if not is_instance_valid(chunk):
		_roof_visual_building_chunks.remove_at(0)
		return not _roof_visual_build_queue.is_empty() or not _roof_visual_building_chunks.is_empty()
	var rows_per_tick: int = 8
	if WorldGenerator and WorldGenerator.balance:
		rows_per_tick = WorldGenerator.balance.mountain_roof_visual_build_rows_per_frame
	if chunk.continue_roof_visual_build(rows_per_tick):
		chunk.set_revealed_mountain_key(_active_mountain_key, false)
		_roof_visual_building_chunks.remove_at(0)
	return not _roof_visual_build_queue.is_empty() or not _roof_visual_building_chunks.is_empty()

func _apply_reveal_state(affected_chunks: Array[Vector2i], animate: bool) -> void:
	for coord: Vector2i in affected_chunks:
		var chunk: Chunk = _chunk_manager.get_chunk(coord)
		if not chunk:
			continue
		chunk.set_revealed_mountain_key(_active_mountain_key, animate)

func _prioritize_roof_visual_builds(chunk_coords: Array[Vector2i]) -> void:
	if _player and chunk_coords.size() > 1:
		var center: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
		chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var pa: int = absi(a.x - center.x) + absi(a.y - center.y)
			var pb: int = absi(b.x - center.x) + absi(b.y - center.y)
			return pa < pb
		)
	for idx: int in range(chunk_coords.size() - 1, -1, -1):
		var coord: Vector2i = chunk_coords[idx]
		var existing_idx: int = _roof_visual_build_queue.find(coord)
		if existing_idx >= 0:
			_roof_visual_build_queue.remove_at(existing_idx)
		_roof_visual_build_queue.push_front(coord)

func _mark_all_loaded_roof_visuals_dirty() -> void:
	if not _chunk_manager:
		return
	var queued_coords: Array[Vector2i] = []
	for coord: Vector2i in _chunk_manager.get_loaded_chunks():
		var chunk: Chunk = _chunk_manager.get_chunk(coord)
		if not chunk or not chunk.has_any_mountain():
			continue
		chunk.invalidate_roof_visuals()
		queued_coords.append(coord)
	_prioritize_roof_visual_builds(queued_coords)

func _find_reveal_start(player_tile: Vector2i) -> Vector2i:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return INVALID_MOUNTAIN_KEY
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	if terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return player_tile
	return INVALID_MOUNTAIN_KEY

func _is_player_on_opened_mountain_tile(player_tile: Vector2i) -> bool:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return false
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	return terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _on_mountain_tile_mined(tile_pos: Vector2i, _old_type: int, _new_type: int) -> void:
	if not _chunk_manager or not WorldGenerator:
		return
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(tile_pos)
	var chunk: Chunk = _chunk_manager.get_chunk(chunk_coord)
	if not chunk or chunk.is_roof_visual_build_complete():
		return
	var queue_idx: int = _roof_visual_build_queue.find(chunk_coord)
	if queue_idx < 0:
		_roof_visual_build_queue.push_front(chunk_coord)

func _on_chunk_loaded(_coord: Vector2i) -> void:
	_needs_full_roof_rebuild = true

func _on_chunk_unloaded(_coord: Vector2i) -> void:
	_needs_full_roof_rebuild = true
