class_name TerrainVisualMaskBuilder
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _chunk_solid_halo: PackedByteArray = PackedByteArray()


func set_chunk_solid_halo(solid_halo: PackedByteArray) -> bool:
	if _chunk_solid_halo == solid_halo:
		return false
	_chunk_solid_halo = solid_halo.duplicate()
	return true


func has_valid_chunk_solid_halo() -> bool:
	var halo_side := WorldRuntimeConstants.CHUNK_SIZE + 2
	return _chunk_solid_halo.size() == halo_side * halo_side


func merge_rects(first: Rect2i, second: Rect2i) -> Rect2i:
	var min_coord := Vector2i(
		mini(first.position.x, second.position.x),
		mini(first.position.y, second.position.y),
	)
	var first_end := first.position + first.size
	var second_end := second.position + second.size
	var max_coord := Vector2i(maxi(first_end.x, second_end.x), maxi(first_end.y, second_end.y))
	return Rect2i(min_coord, max_coord - min_coord)


func build_solid_mask(packet: Dictionary) -> Dictionary:
	var mask := PackedByteArray()
	var mountain_ids: PackedInt32Array = packet.get(
		"mountain_id_per_tile",
		PackedInt32Array(),
	) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get(
		"mountain_flags",
		PackedByteArray(),
	) as PackedByteArray
	if mountain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return { "solid_mask": mask, "solid_count": 0 }

	var min_coord := Vector2i(WorldRuntimeConstants.CHUNK_SIZE, WorldRuntimeConstants.CHUNK_SIZE)
	var max_coord := Vector2i(-1, -1)
	var solid_count := 0
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var flags: int = int(mountain_flags[index])
		if int(mountain_ids[index]) <= 0:
			continue
		if (
			flags
			& (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)
		) == 0:
			continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		min_coord.x = mini(min_coord.x, local_coord.x)
		min_coord.y = mini(min_coord.y, local_coord.y)
		max_coord.x = maxi(max_coord.x, local_coord.x)
		max_coord.y = maxi(max_coord.y, local_coord.y)
		solid_count += 1
	if solid_count <= 0:
		return { "solid_mask": mask, "solid_count": 0 }

	var bounds_size: Vector2i = max_coord - min_coord + Vector2i.ONE
	mask.resize(bounds_size.x * bounds_size.y)
	for y: int in range(min_coord.y, max_coord.y + 1):
		for x: int in range(min_coord.x, max_coord.x + 1):
			var source_index := WorldRuntimeConstants.local_to_index(Vector2i(x, y))
			var source_flags: int = int(mountain_flags[source_index])
			if int(mountain_ids[source_index]) <= 0:
				continue
			var source_surface_flags := (
				WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
			)
			if (source_flags & source_surface_flags) == 0:
				continue
			var mask_index := (y - min_coord.y) * bounds_size.x + (x - min_coord.x)
			mask[mask_index] = 1
	return {
		"solid_mask": mask,
		"solid_count": solid_count,
		"origin_local": min_coord,
		"width_tiles": bounds_size.x,
		"height_tiles": bounds_size.y,
	}


func build_solid_mask_with_halo(packet: Dictionary) -> Dictionary:
	var mountain_ids: PackedInt32Array = packet.get(
		"mountain_id_per_tile",
		PackedInt32Array(),
	) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get(
		"mountain_flags",
		PackedByteArray(),
	) as PackedByteArray
	var bounds := _find_current_chunk_solid_bounds(mountain_ids, mountain_flags)
	if int(bounds.get("solid_count", 0)) <= 0:
		return { "solid_mask": PackedByteArray(), "solid_count": 0 }
	return build_solid_mask_with_halo_for_output_rect(
		mountain_ids,
		mountain_flags,
		bounds.get("output_rect", Rect2i(Vector2i.ZERO, Vector2i.ZERO)) as Rect2i,
	)


func build_solid_mask_with_halo_for_output_rect(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		output_rect: Rect2i,
) -> Dictionary:
	var mask := PackedByteArray()
	if not has_valid_chunk_solid_halo() \
			or mountain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or output_rect.size.x <= 0 \
			or output_rect.size.y <= 0:
		return { "solid_mask": mask, "solid_count": 0 }

	var input_rect := output_rect.grow(1).intersection(
		Rect2i(
			Vector2i(-1, -1),
			Vector2i(WorldRuntimeConstants.CHUNK_SIZE + 2, WorldRuntimeConstants.CHUNK_SIZE + 2),
		),
	)
	if input_rect.size.x <= 0 or input_rect.size.y <= 0:
		return { "solid_mask": mask, "solid_count": 0 }

	mask.resize(input_rect.size.x * input_rect.size.y)
	var output_solid_count := 0
	for local_y: int in range(input_rect.position.y, input_rect.end.y):
		for local_x: int in range(input_rect.position.x, input_rect.end.x):
			var local_coord := Vector2i(local_x, local_y)
			var solid := _is_solid_sample_for_halo_mask(mountain_ids, mountain_flags, local_coord)
			if not solid:
				continue
			var mask_index := (local_y - input_rect.position.y) * input_rect.size.x + (
				local_x - input_rect.position.x
			)
			mask[mask_index] = 1
			if output_rect.has_point(local_coord):
				output_solid_count += 1
	return {
		"solid_mask": mask,
		"solid_count": output_solid_count,
		"input_origin_local": input_rect.position,
		"width_tiles": input_rect.size.x,
		"height_tiles": input_rect.size.y,
		"output_rect_tiles": Rect2i(output_rect.position - input_rect.position, output_rect.size),
		"uses_halo": true,
	}


func build_solid_mask_for_rect(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		dirty_rect: Rect2i,
) -> Dictionary:
	var mask := PackedByteArray()
	if mountain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or dirty_rect.size.x <= 0 \
			or dirty_rect.size.y <= 0:
		return { "solid_mask": mask, "solid_count": 0 }

	mask.resize(dirty_rect.size.x * dirty_rect.size.y)
	var solid_count := 0
	for y: int in range(dirty_rect.position.y, dirty_rect.end.y):
		for x: int in range(dirty_rect.position.x, dirty_rect.end.x):
			var local_coord := Vector2i(x, y)
			var source_index := WorldRuntimeConstants.local_to_index(local_coord)
			var source_flags: int = int(mountain_flags[source_index])
			if int(mountain_ids[source_index]) <= 0:
				continue
			var source_surface_flags := (
				WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
			)
			if (source_flags & source_surface_flags) == 0:
				continue
			var mask_index := (y - dirty_rect.position.y) * dirty_rect.size.x + (
				x - dirty_rect.position.x
			)
			mask[mask_index] = 1
			solid_count += 1
	return {
		"solid_mask": mask,
		"solid_count": solid_count,
		"origin_local": dirty_rect.position,
		"width_tiles": dirty_rect.size.x,
		"height_tiles": dirty_rect.size.y,
	}


func _find_current_chunk_solid_bounds(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
) -> Dictionary:
	if mountain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return { "solid_count": 0 }

	var min_coord := Vector2i(WorldRuntimeConstants.CHUNK_SIZE, WorldRuntimeConstants.CHUNK_SIZE)
	var max_coord := Vector2i(-1, -1)
	var solid_count := 0
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		if not _is_current_chunk_solid_sample(mountain_ids, mountain_flags, local_coord):
			continue
		min_coord.x = mini(min_coord.x, local_coord.x)
		min_coord.y = mini(min_coord.y, local_coord.y)
		max_coord.x = maxi(max_coord.x, local_coord.x)
		max_coord.y = maxi(max_coord.y, local_coord.y)
		solid_count += 1
	if solid_count <= 0:
		return { "solid_count": 0 }
	return {
		"solid_count": solid_count,
		"output_rect": Rect2i(min_coord, max_coord - min_coord + Vector2i.ONE),
	}


func _is_solid_sample_for_halo_mask(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		local_coord: Vector2i,
) -> bool:
	if local_coord.x >= 0 \
			and local_coord.x < WorldRuntimeConstants.CHUNK_SIZE \
			and local_coord.y >= 0 \
			and local_coord.y < WorldRuntimeConstants.CHUNK_SIZE:
		return _is_current_chunk_solid_sample(mountain_ids, mountain_flags, local_coord)
	return _is_chunk_halo_solid(local_coord)


func _is_current_chunk_solid_sample(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		local_coord: Vector2i,
) -> bool:
	var source_index := WorldRuntimeConstants.local_to_index(local_coord)
	if source_index < 0 \
			or source_index >= mountain_ids.size() \
			or source_index >= mountain_flags.size():
		return false
	var source_flags: int = int(mountain_flags[source_index])
	if int(mountain_ids[source_index]) <= 0:
		return false
	var source_surface_flags := (
		WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	)
	return (source_flags & source_surface_flags) != 0


func _is_chunk_halo_solid(local_coord: Vector2i) -> bool:
	if not has_valid_chunk_solid_halo():
		return false
	var halo_side := WorldRuntimeConstants.CHUNK_SIZE + 2
	var halo_coord := local_coord + Vector2i.ONE
	if halo_coord.x < 0 \
			or halo_coord.y < 0 \
			or halo_coord.x >= halo_side \
			or halo_coord.y >= halo_side:
		return false
	return int(_chunk_solid_halo[halo_coord.y * halo_side + halo_coord.x]) != 0
