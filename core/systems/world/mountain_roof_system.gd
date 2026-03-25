class_name MountainRoofSystem
extends Node

## Управляет скрытием крыши активной горы.
## НОВАЯ АРХИТЕКТУРА: координатор состояния, не оркестратор redraw.
## Enter/exit — мгновенный diff-based cover update на чанках (O(diff), не O(chunk²)).
## Не зависит от progressive redraw очередей для near-player UX.

var _chunk_manager: ChunkManager = null
var _player: Player = null
var _last_tile: Vector2i = Vector2i(999999, 999999)
var _active_mountain_key: Vector2i = Vector2i(999999, 999999)
var _is_player_on_mined_floor: bool = false

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

## Определяет новый mountain key и применяет cover diff на все затронутые чанки.
## Мгновенная операция — diff-based update, не progressive redraw.
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
		var affected: Array[Vector2i] = _chunk_manager.set_active_mountain_key(_active_mountain_key)
		_apply_cover_on_chunks(affected)
		WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)
		return
	var next_mountain_key: Vector2i = _chunk_manager.get_mountain_key_at_tile(start_tile)
	if next_mountain_key == Vector2i(999999, 999999):
		return
	if next_mountain_key == _active_mountain_key:
		return
	_active_mountain_key = next_mountain_key
	var affected: Array[Vector2i] = _chunk_manager.set_active_mountain_key(_active_mountain_key)
	_apply_cover_on_chunks(affected)
	WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)

## Мгновенно применяет cover diff на всех затронутых чанках.
## set_mountain_cover_hidden внутри делает O(diff) update, не full redraw.
func _apply_cover_on_chunks(chunk_coords: Array[Vector2i]) -> void:
	for coord: Vector2i in chunk_coords:
		_chunk_manager.update_chunk_cover(coord)

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
