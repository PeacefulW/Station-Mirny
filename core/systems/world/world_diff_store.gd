class_name WorldDiffStore
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _diffs_by_chunk: Dictionary = {}

func clear() -> void:
	_diffs_by_chunk.clear()

func set_tile_override(chunk_coord: Vector2i, local_coord: Vector2i, terrain_id: int, walkable: bool) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if not _diffs_by_chunk.has(chunk_coord):
		_diffs_by_chunk[chunk_coord] = {}
	var chunk_diffs: Dictionary = _diffs_by_chunk[chunk_coord] as Dictionary
	chunk_diffs[local_coord] = {
		"terrain_id": terrain_id,
		"walkable": walkable,
	}

func get_tile_override(chunk_coord: Vector2i, local_coord: Vector2i) -> Dictionary:
	var chunk_diffs: Dictionary = _diffs_by_chunk.get(chunk_coord, {}) as Dictionary
	return (chunk_diffs.get(local_coord, {}) as Dictionary).duplicate(true)

func get_tile_override_at_tile(tile_coord: Vector2i) -> Dictionary:
	return get_tile_override(
		WorldRuntimeConstants.tile_to_chunk(tile_coord),
		WorldRuntimeConstants.tile_to_local(tile_coord)
	)

func get_chunk_override_local_coords(chunk_coord: Vector2i) -> Array[Vector2i]:
	var local_coords: Array[Vector2i] = []
	var chunk_diffs: Dictionary = _diffs_by_chunk.get(chunk_coord, {}) as Dictionary
	for local_coord_variant: Variant in chunk_diffs.keys():
		local_coords.append(local_coord_variant as Vector2i)
	local_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return local_coords

func apply_to_packet(packet: Dictionary) -> Dictionary:
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var chunk_diffs: Dictionary = _diffs_by_chunk.get(chunk_coord, {}) as Dictionary
	if chunk_diffs.is_empty():
		return packet.duplicate(true)

	var merged_packet: Dictionary = packet.duplicate(true)
	var terrain_ids: PackedInt32Array = (merged_packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
	var walkable_flags: PackedByteArray = (merged_packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()

	for local_coord_variant: Variant in chunk_diffs.keys():
		var local_coord: Vector2i = local_coord_variant as Vector2i
		var override_data: Dictionary = chunk_diffs.get(local_coord, {}) as Dictionary
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		if index < 0 or index >= terrain_ids.size():
			continue
		terrain_ids[index] = int(override_data.get("terrain_id", terrain_ids[index]))
		walkable_flags[index] = 1 if bool(override_data.get("walkable", true)) else 0

	merged_packet["terrain_ids"] = terrain_ids
	merged_packet["walkable_flags"] = walkable_flags
	return merged_packet

func serialize_dirty_chunks() -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _diffs_by_chunk.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)

	for chunk_coord: Vector2i in chunk_coords:
		var chunk_diffs: Dictionary = _diffs_by_chunk.get(chunk_coord, {}) as Dictionary
		if chunk_diffs.is_empty():
			continue
		var tiles: Array[Dictionary] = []
		var local_coords: Array[Vector2i] = []
		for local_coord_variant: Variant in chunk_diffs.keys():
			local_coords.append(local_coord_variant as Vector2i)
		local_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x if a.x != b.x else a.y < b.y
		)
		for local_coord: Vector2i in local_coords:
			var override_data: Dictionary = chunk_diffs.get(local_coord, {}) as Dictionary
			tiles.append({
				"local_x": local_coord.x,
				"local_y": local_coord.y,
				"terrain_id": int(override_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
				"walkable": bool(override_data.get("walkable", true)),
			})
		serialized.append({
			"chunk_coord": {
				"x": chunk_coord.x,
				"y": chunk_coord.y,
			},
			"tiles": tiles,
		})
	return serialized

func load_serialized_chunks(entries: Array) -> void:
	clear()
	for entry_variant: Variant in entries:
		var entry: Dictionary = entry_variant as Dictionary
		if entry.is_empty():
			continue
		var chunk_coord_data: Dictionary = entry.get("chunk_coord", {}) as Dictionary
		var chunk_coord := Vector2i(
			int(chunk_coord_data.get("x", 0)),
			int(chunk_coord_data.get("y", 0))
		)
		var tiles: Array = entry.get("tiles", [])
		for tile_variant: Variant in tiles:
			var tile_data: Dictionary = tile_variant as Dictionary
			var local_coord := Vector2i(
				int(tile_data.get("local_x", 0)),
				int(tile_data.get("local_y", 0))
			)
			set_tile_override(
				chunk_coord,
				local_coord,
				int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
				bool(tile_data.get("walkable", true))
			)
