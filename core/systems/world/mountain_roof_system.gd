class_name MountainRoofSystem
extends Node

## Управляет скрытием крыши только у активной горы.
## Использует предвычисленную топологию гор из ChunkManager без BFS при входе.

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
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	if player_tile == _last_tile:
		return
	_last_tile = player_tile
	var is_on_mined_floor: bool = _is_player_on_opened_mountain_tile(player_tile)
	if is_on_mined_floor == _is_player_on_mined_floor and (not is_on_mined_floor or _active_mountain_key != Vector2i(999999, 999999)):
		return
	_is_player_on_mined_floor = is_on_mined_floor
	_refresh_now()

func _resolve_dependencies() -> void:
	var chunks: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunks.is_empty():
		_chunk_manager = chunks[0] as ChunkManager
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Player
	_refresh_now()

func _refresh_now(_arg: Variant = null) -> void:
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
		_chunk_manager.set_active_mountain_key(_active_mountain_key)
		return
	var next_mountain_key: Vector2i = _chunk_manager.get_mountain_key_at_tile(start_tile)
	if next_mountain_key == Vector2i(999999, 999999):
		return
	if next_mountain_key == _active_mountain_key:
		return
	_active_mountain_key = next_mountain_key
	_chunk_manager.set_active_mountain_key(_active_mountain_key)
	WorldPerfProbe.end("MountainRoofSystem._refresh_now", started_usec)

func _find_reveal_start(player_tile: Vector2i) -> Vector2i:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return Vector2i(999999, 999999)
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	if terrain_type == TileGenData.TerrainType.MINED_FLOOR:
		return player_tile
	return Vector2i(999999, 999999)

func _is_player_on_opened_mountain_tile(player_tile: Vector2i) -> bool:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return false
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	return chunk.get_terrain_type_at(local_tile) == TileGenData.TerrainType.MINED_FLOOR

func _on_mountain_tile_mined(tile_pos: Vector2i, _old_type: int, new_type: int) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	if new_type != TileGenData.TerrainType.MINED_FLOOR and new_type != TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return
	if _active_mountain_key != Vector2i(999999, 999999):
		return
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var distance: int = absi(player_tile.x - tile_pos.x) + absi(player_tile.y - tile_pos.y)
	if distance > 1:
		return
	# Pre-warm topology/key lookup while the player is still stationary after
	# mining, so the first step into the new opening does not pay the full
	# native ensure_built() cost.
	_chunk_manager.get_mountain_key_at_tile(tile_pos)
