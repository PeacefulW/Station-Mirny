class_name HarvestTileCommand
extends GameCommand

var _chunk_manager: ChunkManager = null
var _world_pos: Vector2 = Vector2.ZERO

func setup(chunk_manager: ChunkManager, world_pos: Vector2) -> HarvestTileCommand:
	_chunk_manager = chunk_manager
	_world_pos = world_pos
	return self

func execute() -> Dictionary:
	if not _chunk_manager:
		return {
			"success": false,
			"message_key": "SYSTEM_CHUNK_MANAGER_MISSING",
		}
	return _chunk_manager.try_harvest_at_world(_world_pos)