class_name ChunkFloraResult
extends RefCounted

## Результат compute-фазы размещения флоры/декора для одного чанка.

var chunk_coord: Vector2i = Vector2i.ZERO
var chunk_size: int = 0
var placements: Array[Dictionary] = []

func add_placement(local_pos: Vector2i, entry_id: StringName, is_flora: bool, color: Color, size: Vector2i, z_offset: int) -> void:
	placements.append({
		"local_pos": local_pos,
		"entry_id": entry_id,
		"is_flora": is_flora,
		"color": color,
		"size": size,
		"z_offset": z_offset,
	})

func get_placement_count() -> int:
	return placements.size()

func is_empty() -> bool:
	return placements.is_empty()
