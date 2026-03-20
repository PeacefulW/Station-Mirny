class_name MountainRoofSystem
extends Node

## Управляет "крышами" гор и копанием камня.
## Когда игрок внутри горы — крыша скрывается. Снаружи — видна.
## E рядом с ROCK → выкопать (ROCK → MINED_FLOOR/ENTRANCE).

var _player_inside_mountain: bool = false
var _fade_tween: Tween = null
var _chunk_manager: Node = null

func _ready() -> void:
	add_to_group("mountain_roof")
	call_deferred("_find_chunk_manager")

func _process(_delta: float) -> void:
	_check_player_position()

## Попытаться выкопать скалу перед игроком.
func try_mine_at(world_pos: Vector2) -> bool:
	if not _chunk_manager:
		return false
	var tile: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var cc: Vector2i = WorldGenerator.tile_to_chunk(tile)
	var chunk: Chunk = _chunk_manager.get_chunk(cc)
	if not chunk:
		return false
	var local: Vector2i = chunk.global_to_local(tile)
	var terrain_type: int = chunk.get_terrain_type_at(local)
	if terrain_type != TileGenData.TerrainType.ROCK:
		return false

	# Определить: вход или внутренний пол
	var new_type: int = _determine_mined_type(tile, chunk)
	chunk.set_terrain_type_at(local, new_type)

	# Дроп камня
	EventBus.item_collected.emit("base:stone", 1)
	return true

## Определить тип: ENTRANCE если есть сосед не-ROCK, иначе MINED_FLOOR.
func _determine_mined_type(tile: Vector2i, chunk: Chunk) -> int:
	var neighbors: Array[Vector2i] = [
		tile + Vector2i(0, -1), tile + Vector2i(0, 1),
		tile + Vector2i(-1, 0), tile + Vector2i(1, 0),
	]
	for n: Vector2i in neighbors:
		var n_cc: Vector2i = WorldGenerator.tile_to_chunk(n)
		var n_chunk: Chunk = _chunk_manager.get_chunk(n_cc) if _chunk_manager else null
		if not n_chunk:
			continue
		var n_local: Vector2i = n_chunk.global_to_local(n)
		var n_type: int = n_chunk.get_terrain_type_at(n_local)
		# Сосед не горный → это вход
		if n_type != TileGenData.TerrainType.ROCK and n_type != TileGenData.TerrainType.MINED_FLOOR:
			return TileGenData.TerrainType.MOUNTAIN_ENTRANCE
	return TileGenData.TerrainType.MINED_FLOOR

## Проверить позицию игрока — внутри горы или снаружи.
func _check_player_position() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not _chunk_manager:
		return
	var player: Node2D = players[0] as Node2D
	var tile: Vector2i = WorldGenerator.world_to_tile(player.global_position)
	var cc: Vector2i = WorldGenerator.tile_to_chunk(tile)
	var chunk: Chunk = _chunk_manager.get_chunk(cc)
	if not chunk:
		return
	var local: Vector2i = chunk.global_to_local(tile)
	var terrain_type: int = chunk.get_terrain_type_at(local)
	var is_inside: bool = (
		terrain_type == TileGenData.TerrainType.MINED_FLOOR
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE
	)

	if is_inside and not _player_inside_mountain:
		_player_inside_mountain = true
		_set_all_roof_opacity(0.0)
	elif not is_inside and _player_inside_mountain:
		_player_inside_mountain = false
		_set_all_roof_opacity(1.0)

## Плавно менять roof_opacity на всех видимых чанках.
func _set_all_roof_opacity(target: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_apply_roof_opacity, 1.0 - target, target, 0.3)

func _apply_roof_opacity(value: float) -> void:
	if not _chunk_manager:
		return
	# Перебрать все загруженные чанки
	for cc: Vector2i in _chunk_manager._loaded_chunks:
		var chunk: Chunk = _chunk_manager._loaded_chunks[cc]
		if chunk:
			chunk.set_roof_opacity(value)

func _find_chunk_manager() -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not nodes.is_empty():
		_chunk_manager = nodes[0]
