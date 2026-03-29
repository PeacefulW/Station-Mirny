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

func to_serialized_payload() -> Dictionary:
	return {
		"chunk_coord": chunk_coord,
		"chunk_size": chunk_size,
		"placements": placements.duplicate(true),
	}

static func from_serialized_payload(payload: Dictionary) -> ChunkFloraResult:
	var result := ChunkFloraResult.new()
	result.chunk_coord = payload.get("chunk_coord", Vector2i.ZERO) as Vector2i
	result.chunk_size = int(payload.get("chunk_size", 0))
	var serialized_placements: Array = payload.get("placements", []) as Array
	for placement_variant: Variant in serialized_placements:
		var placement: Dictionary = placement_variant as Dictionary
		var local_pos: Vector2i = placement.get("local_pos", Vector2i.ZERO) as Vector2i
		result.add_placement(
			local_pos,
			placement.get("entry_id", &"") as StringName,
			bool(placement.get("is_flora", true)),
			placement.get("color", Color.WHITE) as Color,
			placement.get("size", Vector2i.ZERO) as Vector2i,
			int(placement.get("z_offset", 0))
		)
	return result
