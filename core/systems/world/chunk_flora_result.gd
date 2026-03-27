class_name ChunkFloraResult
extends RefCounted

## Результат compute-фазы размещения флоры/декора для одного чанка.

var chunk_coord: Vector2i = Vector2i.ZERO
var chunk_size: int = 0
var placements: Array[Dictionary] = []
var _placements_by_local_pos: Dictionary = {}

func add_placement(local_pos: Vector2i, entry_id: StringName, is_flora: bool, color: Color, size: Vector2i, z_offset: int) -> void:
	var placement: Dictionary = {
		"local_pos": local_pos,
		"entry_id": entry_id,
		"is_flora": is_flora,
		"color": color,
		"size": size,
		"z_offset": z_offset,
	}
	placements.append(placement)
	var placements_for_tile: Array = _placements_by_local_pos.get(local_pos, [])
	placements_for_tile.append(placement)
	_placements_by_local_pos[local_pos] = placements_for_tile

func get_placement_count() -> int:
	return placements.size()

func is_empty() -> bool:
	return placements.is_empty()

func get_placements_for_local_pos(local_pos: Vector2i) -> Array:
	return _placements_by_local_pos.get(local_pos, [])
