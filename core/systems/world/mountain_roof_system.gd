class_name MountainRoofSystem
extends Node

## Управляет скрытием крыши только у активной горы.
## Cover setup + redraw — полностью через FrameBudgetDispatcher.

const COVER_ROWS_PER_STEP: int = 4
const COVER_SETUP_PER_TICK: int = 2

var _chunk_manager: ChunkManager = null
var _player: Player = null
var _last_tile: Vector2i = Vector2i(999999, 999999)
var _active_mountain_key: Vector2i = Vector2i(999999, 999999)
var _is_player_on_mined_floor: bool = false
var _cover_dirty_queue: Array[Vector2i] = []
var _cover_redrawing_chunks: Array[Chunk] = []

func _ready() -> void:
	EventBus.mountain_tile_mined.connect(_on_mountain_tile_mined)
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
	FrameBudgetDispatcher.register_job(&"visual", 2.0, _tick_cover)
	_request_refresh()

func _check_player_mountain_state() -> void:
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	if player_tile == _last_tile:
		return
	_last_tile = player_tile
	var is_on_mined_floor: bool = _is_player_on_opened_mountain_tile(player_tile)
	if is_on_mined_floor == _is_player_on_mined_floor and (not is_on_mined_floor or _active_mountain_key != Vector2i(999999, 999999)):
		return
	_is_player_on_mined_floor = is_on_mined_floor
	_request_refresh()

func _request_refresh() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var start_tile: Vector2i = _find_reveal_start(player_tile)
	if start_tile == Vector2i(999999, 999999):
		if _active_mountain_key == Vector2i(999999, 999999):
			return
		_active_mountain_key = Vector2i(999999, 999999)
		_is_player_on_mined_floor = false
		_enqueue_chunks(_chunk_manager.set_active_mountain_key(_active_mountain_key))
		WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)
		return
	var next_mountain_key: Vector2i = _chunk_manager.get_mountain_key_at_tile(start_tile)
	if next_mountain_key == Vector2i(999999, 999999):
		return
	if next_mountain_key == _active_mountain_key:
		return
	_active_mountain_key = next_mountain_key
	_enqueue_chunks(_chunk_manager.set_active_mountain_key(_active_mountain_key))
	WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)

## Единый budgeted tick: setup dirty coords → progressive redraw.
func _tick_cover() -> bool:
	var started_usec: int = WorldPerfProbe.begin()
	var setup_count: int = 0
	while not _cover_dirty_queue.is_empty() and setup_count < COVER_SETUP_PER_TICK:
		var coord: Vector2i = _cover_dirty_queue.pop_front()
		_chunk_manager.update_chunk_cover(coord)
		var chunk: Chunk = _chunk_manager.get_chunk(coord)
		if chunk and not chunk.is_cover_redraw_complete() and chunk not in _cover_redrawing_chunks:
			_cover_redrawing_chunks.append(chunk)
		setup_count += 1
	while not _cover_redrawing_chunks.is_empty():
		var chunk: Chunk = _cover_redrawing_chunks[0]
		if not is_instance_valid(chunk):
			_cover_redrawing_chunks.remove_at(0)
			continue
		if chunk.continue_cover_redraw(COVER_ROWS_PER_STEP):
			_cover_redrawing_chunks.remove_at(0)
		WorldPerfProbe.end("Cover.tick_slice", started_usec)
		return true
	WorldPerfProbe.end("Cover.tick_slice", started_usec)
	return not _cover_dirty_queue.is_empty()

func _enqueue_chunks(chunks: Array[Vector2i]) -> void:
	for coord: Vector2i in chunks:
		if coord not in _cover_dirty_queue:
			_cover_dirty_queue.append(coord)

func _find_reveal_start(player_tile: Vector2i) -> Vector2i:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return Vector2i(999999, 999999)
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	if terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return player_tile
	return Vector2i(999999, 999999)

func _is_player_on_opened_mountain_tile(player_tile: Vector2i) -> bool:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return false
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	return terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _on_mountain_tile_mined(_tile_pos: Vector2i, _old_type: int, new_type: int) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	if new_type != TileGenData.TerrainType.MINED_FLOOR and new_type != TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return
	if _active_mountain_key != Vector2i(999999, 999999):
		return
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var distance: int = absi(player_tile.x - _tile_pos.x) + absi(player_tile.y - _tile_pos.y)
	if distance > 1:
		return
	pass
