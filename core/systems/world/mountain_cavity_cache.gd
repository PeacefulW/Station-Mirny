class_name MountainCavityCache
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _next_component_id: int = 1
var _component_id_by_tile: Dictionary = {}
var _opening_flag_by_tile: Dictionary = {}
var _component_data_by_id: Dictionary = {}
var _outside_visible_by_chunk: Dictionary = {}

func clear() -> void:
	_next_component_id = 1
	_component_id_by_tile.clear()
	_opening_flag_by_tile.clear()
	_component_data_by_id.clear()
	_outside_visible_by_chunk.clear()

func has_component(component_id: int) -> bool:
	return component_id > 0 and _component_data_by_id.has(component_id)

func get_component_chunks(component_id: int) -> Array[Vector2i]:
	return _collect_component_chunks(component_id)

func get_sample(world_tile: Vector2i, sample_tile: Callable) -> Dictionary:
	var geometry: Dictionary = sample_tile.call(world_tile) as Dictionary
	if not bool(geometry.get("ready", false)):
		return {"ready": false}
	var component_id: int = int(_component_id_by_tile.get(world_tile, 0))
	return {
		"ready": true,
		"mountain_id": int(geometry.get("mountain_id", 0)),
		"mountain_flags": int(geometry.get("mountain_flags", 0)),
		"walkable": bool(geometry.get("walkable", false)),
		"component_id": component_id,
		"is_opening": bool(_opening_flag_by_tile.get(world_tile, false)),
	}

func on_chunk_loaded(
	published_chunk_coord: Vector2i,
	candidate_world_tiles: Array[Vector2i],
	sample_tile: Callable
) -> Dictionary:
	var affected_components: Dictionary = {}
	for world_tile: Vector2i in candidate_world_tiles:
		if WorldRuntimeConstants.tile_to_chunk(world_tile) != published_chunk_coord:
			continue
		var geometry: Dictionary = sample_tile.call(world_tile) as Dictionary
		if not _is_floor_tile(geometry):
			continue
		var component_id: int = _ensure_floor_tile_present(world_tile, geometry, sample_tile)
		if component_id > 0:
			affected_components[component_id] = true
	for world_tile: Vector2i in candidate_world_tiles:
		var component_id: int = int(_component_id_by_tile.get(world_tile, 0))
		if component_id > 0:
			affected_components[component_id] = true
	for component_id_variant: Variant in affected_components.keys():
		_rebuild_component_metadata(int(component_id_variant), sample_tile)
	var affected_chunks: Array[Vector2i] = _collect_affected_chunks_from_components(_dictionary_int_keys(affected_components))
	_rebuild_outside_visibility_for_chunks(affected_chunks)
	return {
		"affected_chunks": affected_chunks,
	}

func on_chunk_unloaded(
	unloaded_chunk_coord: Vector2i,
	dirty_world_tiles: Array[Vector2i],
	sample_tile: Callable
) -> Dictionary:
	var affected_old_components: Dictionary = {}
	for world_tile: Vector2i in dirty_world_tiles:
		var component_id: int = int(_component_id_by_tile.get(world_tile, 0))
		if component_id > 0:
			affected_old_components[component_id] = true
	if affected_old_components.is_empty():
		_outside_visible_by_chunk.erase(unloaded_chunk_coord)
		return {
			"affected_chunks": [unloaded_chunk_coord],
		}

	var affected_chunks: Dictionary = {unloaded_chunk_coord: true}
	for component_id_variant: Variant in affected_old_components.keys():
		var old_component_id: int = int(component_id_variant)
		var old_component: Dictionary = _component_data_by_id.get(old_component_id, {}) as Dictionary
		if old_component.is_empty():
			continue
		var remaining_tiles: Dictionary = {}
		var old_tiles: Dictionary = old_component.get("tiles", {}) as Dictionary
		for tile_variant: Variant in old_tiles.keys():
			var world_tile: Vector2i = tile_variant as Vector2i
			_component_id_by_tile.erase(world_tile)
			if WorldRuntimeConstants.tile_to_chunk(world_tile) == unloaded_chunk_coord:
				continue
			remaining_tiles[world_tile] = true
		var old_openings: Dictionary = old_component.get("openings", {}) as Dictionary
		for opening_variant: Variant in old_openings.keys():
			_opening_flag_by_tile.erase(opening_variant as Vector2i)
		_component_data_by_id.erase(old_component_id)
		if remaining_tiles.is_empty():
			continue
		var rebuilt_component_ids: Array[int] = _rebuild_split_components(remaining_tiles, sample_tile)
		for rebuilt_component_id: int in rebuilt_component_ids:
			for chunk_coord: Vector2i in _collect_component_chunks(rebuilt_component_id):
				affected_chunks[chunk_coord] = true
	_rebuild_outside_visibility_for_chunks(_dictionary_vector2i_keys(affected_chunks))
	return {
		"affected_chunks": _dictionary_vector2i_keys(affected_chunks),
	}

func on_tile_dug(world_tile: Vector2i, sample_tile: Callable) -> Dictionary:
	var geometry: Dictionary = sample_tile.call(world_tile) as Dictionary
	var affected_components: Dictionary = {}
	if _is_floor_tile(geometry):
		var component_id: int = _ensure_floor_tile_present(world_tile, geometry, sample_tile)
		if component_id > 0:
			affected_components[component_id] = true
	var refresh_tiles: Array[Vector2i] = _cross_tiles(world_tile)
	for refresh_tile: Vector2i in refresh_tiles:
		var component_id: int = int(_component_id_by_tile.get(refresh_tile, 0))
		if component_id > 0:
			affected_components[component_id] = true
	var changed_opening_tiles: Array[Vector2i] = _refresh_openings_for_tiles(refresh_tiles, sample_tile)
	var shell_anchor_tiles: Array[Vector2i] = refresh_tiles.duplicate()
	for opening_tile: Vector2i in changed_opening_tiles:
		shell_anchor_tiles.append(opening_tile)
	var shell_chunks: Array[Vector2i] = _refresh_shells_near_tiles(
		_dictionary_int_keys(affected_components),
		shell_anchor_tiles,
		sample_tile
	)
	var affected_chunks: Dictionary = {}
	affected_chunks[WorldRuntimeConstants.tile_to_chunk(world_tile)] = true
	for shell_chunk: Vector2i in shell_chunks:
		affected_chunks[shell_chunk] = true
	for component_id_variant: Variant in affected_components.keys():
		var component_id: int = int(component_id_variant)
		for chunk_coord: Vector2i in _collect_component_chunks(component_id):
			if _chunk_touches_any_anchor(chunk_coord, shell_anchor_tiles):
				affected_chunks[chunk_coord] = true
	_rebuild_outside_visibility_for_chunks(_dictionary_vector2i_keys(affected_chunks))
	return {
		"affected_chunks": _dictionary_vector2i_keys(affected_chunks),
	}

func build_chunk_visibility_mask(chunk_coord: Vector2i, active_component_id: int) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var outside_visible: Dictionary = _outside_visible_by_chunk.get(chunk_coord, {}) as Dictionary
	if has_component(active_component_id):
		var component: Dictionary = _component_data_by_id.get(active_component_id, {}) as Dictionary
		_apply_tiles_to_mask(mask, component.get("tiles", {}) as Dictionary, chunk_coord)
		_apply_tiles_to_mask(mask, component.get("shell", {}) as Dictionary, chunk_coord)
		_apply_local_coords_to_mask(mask, outside_visible)
		return mask
	_apply_local_coords_to_mask(mask, outside_visible)
	return mask

func get_debug_snapshot(
	world_tile: Vector2i,
	active_component_id: int,
	sample_tile: Callable
) -> Dictionary:
	var sample: Dictionary = get_sample(world_tile, sample_tile)
	if not bool(sample.get("ready", false)):
		return {"ready": false}
	return {
		"ready": true,
		"mountain_id": int(sample.get("mountain_id", 0)),
		"component_id": int(sample.get("component_id", 0)),
		"is_opening": bool(sample.get("is_opening", false)),
		"active_component_id": active_component_id,
		"inside_outside_state": "INSIDE" if int(sample.get("component_id", 0)) > 0 else "OUTSIDE",
	}

func _ensure_floor_tile_present(world_tile: Vector2i, geometry: Dictionary, sample_tile: Callable) -> int:
	var existing_component_id: int = int(_component_id_by_tile.get(world_tile, 0))
	if existing_component_id > 0:
		return existing_component_id
	var mountain_id: int = int(geometry.get("mountain_id", 0))
	var neighboring_components: Array[int] = _collect_neighboring_component_ids(world_tile, mountain_id)
	var component_id: int = 0
	if neighboring_components.is_empty():
		component_id = _create_component(mountain_id)
	else:
		component_id = neighboring_components[0]
		if neighboring_components.size() > 1:
			for index: int in range(1, neighboring_components.size()):
				_merge_component_into(component_id, neighboring_components[index])
	_component_id_by_tile[world_tile] = component_id
	var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
	var tiles: Dictionary = component.get("tiles", {}) as Dictionary
	tiles[world_tile] = true
	component["tiles"] = tiles
	_component_data_by_id[component_id] = component
	return component_id

func _collect_neighboring_component_ids(world_tile: Vector2i, mountain_id: int) -> Array[int]:
	var component_ids: Array[int] = []
	var seen: Dictionary = {}
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor_tile: Vector2i = world_tile + offset
		var component_id: int = int(_component_id_by_tile.get(neighbor_tile, 0))
		if component_id <= 0 or seen.has(component_id):
			continue
		var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
		if int(component.get("mountain_id", 0)) != mountain_id:
			continue
		seen[component_id] = true
		component_ids.append(component_id)
	component_ids.sort()
	return component_ids

func _create_component(mountain_id: int) -> int:
	var component_id: int = _next_component_id
	_next_component_id += 1
	_component_data_by_id[component_id] = {
		"mountain_id": mountain_id,
		"tiles": {},
		"openings": {},
		"shell": {},
		"opening_shell": {},
	}
	return component_id

func _merge_component_into(primary_component_id: int, secondary_component_id: int) -> void:
	if primary_component_id == secondary_component_id:
		return
	var primary: Dictionary = _component_data_by_id.get(primary_component_id, {}) as Dictionary
	var secondary: Dictionary = _component_data_by_id.get(secondary_component_id, {}) as Dictionary
	if primary.is_empty() or secondary.is_empty():
		return
	for section_name: String in ["tiles", "openings", "shell", "opening_shell"]:
		var primary_section: Dictionary = primary.get(section_name, {}) as Dictionary
		var secondary_section: Dictionary = secondary.get(section_name, {}) as Dictionary
		for tile_variant: Variant in secondary_section.keys():
			var world_tile: Vector2i = tile_variant as Vector2i
			primary_section[world_tile] = true
			if section_name == "tiles":
				_component_id_by_tile[world_tile] = primary_component_id
			elif section_name == "openings":
				_opening_flag_by_tile[world_tile] = true
		primary[section_name] = primary_section
	_component_data_by_id[primary_component_id] = primary
	_component_data_by_id.erase(secondary_component_id)

func _rebuild_split_components(remaining_tiles: Dictionary, sample_tile: Callable) -> Array[int]:
	var rebuilt_component_ids: Array[int] = []
	var unvisited: Dictionary = remaining_tiles.duplicate(true)
	while not unvisited.is_empty():
		var seed_variant: Variant = unvisited.keys()[0]
		var seed_tile: Vector2i = seed_variant as Vector2i
		var seed_geometry: Dictionary = sample_tile.call(seed_tile) as Dictionary
		if not _is_floor_tile(seed_geometry):
			unvisited.erase(seed_tile)
			continue
		var component_id: int = _create_component(int(seed_geometry.get("mountain_id", 0)))
		var queue: Array[Vector2i] = [seed_tile]
		unvisited.erase(seed_tile)
		while not queue.is_empty():
			var current_tile: Vector2i = queue.pop_front()
			_component_id_by_tile[current_tile] = component_id
			var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
			var tiles: Dictionary = component.get("tiles", {}) as Dictionary
			tiles[current_tile] = true
			component["tiles"] = tiles
			_component_data_by_id[component_id] = component
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor_tile: Vector2i = current_tile + offset
				if not unvisited.has(neighbor_tile):
					continue
				var neighbor_geometry: Dictionary = sample_tile.call(neighbor_tile) as Dictionary
				if not _is_floor_tile(neighbor_geometry):
					unvisited.erase(neighbor_tile)
					continue
				unvisited.erase(neighbor_tile)
				queue.append(neighbor_tile)
		_rebuild_component_metadata(component_id, sample_tile)
		rebuilt_component_ids.append(component_id)
	return rebuilt_component_ids

func _rebuild_component_metadata(component_id: int, sample_tile: Callable) -> void:
	var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
	if component.is_empty():
		return
	for opening_variant: Variant in (component.get("openings", {}) as Dictionary).keys():
		_opening_flag_by_tile.erase(opening_variant as Vector2i)
	component["openings"] = {}
	component["shell"] = {}
	component["opening_shell"] = {}
	var tiles: Dictionary = component.get("tiles", {}) as Dictionary
	var shell_candidates: Dictionary = {}
	for tile_variant: Variant in tiles.keys():
		var world_tile: Vector2i = tile_variant as Vector2i
		if _compute_is_opening(world_tile, sample_tile):
			var openings: Dictionary = component.get("openings", {}) as Dictionary
			openings[world_tile] = true
			component["openings"] = openings
			_opening_flag_by_tile[world_tile] = true
		for candidate_tile: Vector2i in _expand_eight_neighbors(world_tile):
			shell_candidates[candidate_tile] = true
	var opening_candidates: Dictionary = {}
	for opening_variant: Variant in (component.get("openings", {}) as Dictionary).keys():
		var opening_tile: Vector2i = opening_variant as Vector2i
		for candidate_tile: Vector2i in _expand_eight_neighbors(opening_tile):
			opening_candidates[candidate_tile] = true
	for candidate_variant: Variant in shell_candidates.keys():
		var candidate_tile: Vector2i = candidate_variant as Vector2i
		if _should_tile_be_component_shell(candidate_tile, component_id, sample_tile):
			var shell: Dictionary = component.get("shell", {}) as Dictionary
			shell[candidate_tile] = true
			component["shell"] = shell
	for candidate_variant: Variant in opening_candidates.keys():
		var candidate_tile: Vector2i = candidate_variant as Vector2i
		if _should_tile_be_opening_shell(candidate_tile, component_id, sample_tile):
			var opening_shell: Dictionary = component.get("opening_shell", {}) as Dictionary
			opening_shell[candidate_tile] = true
			component["opening_shell"] = opening_shell
	_component_data_by_id[component_id] = component

func _refresh_openings_for_tiles(tiles_to_check: Array[Vector2i], sample_tile: Callable) -> Array[Vector2i]:
	var changed_tiles: Array[Vector2i] = []
	var seen: Dictionary = {}
	for world_tile: Vector2i in tiles_to_check:
		if seen.has(world_tile):
			continue
		seen[world_tile] = true
		var component_id: int = int(_component_id_by_tile.get(world_tile, 0))
		if component_id <= 0:
			continue
		var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
		if component.is_empty():
			continue
		var openings: Dictionary = component.get("openings", {}) as Dictionary
		var was_opening: bool = bool(_opening_flag_by_tile.get(world_tile, false))
		var is_opening: bool = _compute_is_opening(world_tile, sample_tile)
		if is_opening:
			openings[world_tile] = true
			_opening_flag_by_tile[world_tile] = true
		else:
			openings.erase(world_tile)
			_opening_flag_by_tile.erase(world_tile)
		component["openings"] = openings
		_component_data_by_id[component_id] = component
		if was_opening != is_opening:
			changed_tiles.append(world_tile)
	return changed_tiles

func _refresh_shells_near_tiles(
	component_ids: Array[int],
	anchor_tiles: Array[Vector2i],
	sample_tile: Callable
) -> Array[Vector2i]:
	var candidate_tiles: Dictionary = {}
	for anchor_tile: Vector2i in anchor_tiles:
		for candidate_tile: Vector2i in _expand_eight_neighbors(anchor_tile):
			candidate_tiles[candidate_tile] = true
	var affected_chunks: Dictionary = {}
	for component_id: int in component_ids:
		var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
		if component.is_empty():
			continue
		var shell: Dictionary = component.get("shell", {}) as Dictionary
		var opening_shell: Dictionary = component.get("opening_shell", {}) as Dictionary
		for candidate_variant: Variant in candidate_tiles.keys():
			var candidate_tile: Vector2i = candidate_variant as Vector2i
			if _should_tile_be_component_shell(candidate_tile, component_id, sample_tile):
				shell[candidate_tile] = true
			else:
				shell.erase(candidate_tile)
			if _should_tile_be_opening_shell(candidate_tile, component_id, sample_tile):
				opening_shell[candidate_tile] = true
			else:
				opening_shell.erase(candidate_tile)
			affected_chunks[WorldRuntimeConstants.tile_to_chunk(candidate_tile)] = true
		component["shell"] = shell
		component["opening_shell"] = opening_shell
		_component_data_by_id[component_id] = component
	return _dictionary_vector2i_keys(affected_chunks)

func _compute_is_opening(world_tile: Vector2i, sample_tile: Callable) -> bool:
	var component_id: int = int(_component_id_by_tile.get(world_tile, 0))
	if component_id <= 0:
		return false
	var geometry: Dictionary = sample_tile.call(world_tile) as Dictionary
	if not _is_floor_tile(geometry):
		return false
	var mountain_id: int = int(geometry.get("mountain_id", 0))
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor_geometry: Dictionary = sample_tile.call(world_tile + offset) as Dictionary
		if not bool(neighbor_geometry.get("ready", false)):
			continue
		if not bool(neighbor_geometry.get("walkable", false)):
			continue
		if int(neighbor_geometry.get("mountain_id", 0)) != mountain_id:
			return true
		if not _is_roof_tile(neighbor_geometry):
			return true
	return false

func _should_tile_be_component_shell(world_tile: Vector2i, component_id: int, sample_tile: Callable) -> bool:
	if _component_id_by_tile.has(world_tile):
		return false
	var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
	if component.is_empty():
		return false
	var geometry: Dictionary = sample_tile.call(world_tile) as Dictionary
	if not _is_roof_tile(geometry):
		return false
	if int(geometry.get("mountain_id", 0)) != int(component.get("mountain_id", 0)):
		return false
	for neighbor_tile: Vector2i in _expand_eight_neighbors(world_tile):
		if int(_component_id_by_tile.get(neighbor_tile, 0)) == component_id:
			return true
	return false

func _should_tile_be_opening_shell(world_tile: Vector2i, component_id: int, sample_tile: Callable) -> bool:
	if _component_id_by_tile.has(world_tile):
		return false
	var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
	if component.is_empty():
		return false
	var geometry: Dictionary = sample_tile.call(world_tile) as Dictionary
	if not _is_roof_tile(geometry):
		return false
	if int(geometry.get("mountain_id", 0)) != int(component.get("mountain_id", 0)):
		return false
	var openings: Dictionary = component.get("openings", {}) as Dictionary
	for neighbor_tile: Vector2i in [world_tile + Vector2i.LEFT, world_tile + Vector2i.RIGHT, world_tile + Vector2i.UP, world_tile + Vector2i.DOWN]:
		if openings.has(neighbor_tile):
			return true
	return false

func _rebuild_outside_visibility_for_chunks(chunks: Array[Vector2i]) -> void:
	var unique_chunks: Dictionary = {}
	for chunk_coord: Vector2i in chunks:
		unique_chunks[chunk_coord] = true
	for chunk_variant: Variant in unique_chunks.keys():
		var chunk_coord: Vector2i = chunk_variant as Vector2i
		var local_coords: Dictionary = {}
		for component_variant: Variant in _component_data_by_id.values():
			var component: Dictionary = component_variant as Dictionary
			for section_name: String in ["openings", "opening_shell"]:
				var section: Dictionary = component.get(section_name, {}) as Dictionary
				for tile_variant: Variant in section.keys():
					var world_tile: Vector2i = tile_variant as Vector2i
					if WorldRuntimeConstants.tile_to_chunk(world_tile) != chunk_coord:
						continue
					local_coords[WorldRuntimeConstants.tile_to_local(world_tile)] = true
		if local_coords.is_empty():
			_outside_visible_by_chunk.erase(chunk_coord)
			continue
		_outside_visible_by_chunk[chunk_coord] = local_coords

func _collect_component_chunks(component_id: int) -> Array[Vector2i]:
	var component: Dictionary = _component_data_by_id.get(component_id, {}) as Dictionary
	if component.is_empty():
		return []
	var chunks: Dictionary = {}
	for section_name: String in ["tiles", "shell", "openings", "opening_shell"]:
		var section: Dictionary = component.get(section_name, {}) as Dictionary
		for tile_variant: Variant in section.keys():
			chunks[WorldRuntimeConstants.tile_to_chunk(tile_variant as Vector2i)] = true
	return _dictionary_vector2i_keys(chunks)

func _collect_affected_chunks_from_components(component_ids: Array[int]) -> Array[Vector2i]:
	var chunks: Dictionary = {}
	for component_id: int in component_ids:
		for chunk_coord: Vector2i in _collect_component_chunks(component_id):
			chunks[chunk_coord] = true
	return _dictionary_vector2i_keys(chunks)

func _apply_tiles_to_mask(mask: PackedByteArray, tiles: Dictionary, chunk_coord: Vector2i) -> void:
	for tile_variant: Variant in tiles.keys():
		var world_tile: Vector2i = tile_variant as Vector2i
		if WorldRuntimeConstants.tile_to_chunk(world_tile) != chunk_coord:
			continue
		var index: int = WorldRuntimeConstants.local_to_index(WorldRuntimeConstants.tile_to_local(world_tile))
		if index >= 0 and index < mask.size():
			mask[index] = 1

func _apply_local_coords_to_mask(mask: PackedByteArray, local_coords: Dictionary) -> void:
	for local_variant: Variant in local_coords.keys():
		var local_coord: Vector2i = local_variant as Vector2i
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		if index >= 0 and index < mask.size():
			mask[index] = 1

func _is_floor_tile(sample: Dictionary) -> bool:
	return _is_roof_tile(sample) \
		and bool(sample.get("walkable", false)) \
		and int(sample.get("mountain_id", 0)) > 0

func _is_roof_tile(sample: Dictionary) -> bool:
	if not bool(sample.get("ready", false)):
		return false
	var mountain_flags: int = int(sample.get("mountain_flags", 0))
	return int(sample.get("mountain_id", 0)) > 0 \
		and (mountain_flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0

func _cross_tiles(world_tile: Vector2i) -> Array[Vector2i]:
	return [
		world_tile,
		world_tile + Vector2i.LEFT,
		world_tile + Vector2i.RIGHT,
		world_tile + Vector2i.UP,
		world_tile + Vector2i.DOWN,
	]

func _expand_eight_neighbors(world_tile: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			result.append(world_tile + Vector2i(offset_x, offset_y))
	return result

func _dictionary_int_keys(source: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for key_variant: Variant in source.keys():
		result.append(int(key_variant))
	result.sort()
	return result

func _dictionary_vector2i_keys(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key_variant: Variant in source.keys():
		result.append(key_variant as Vector2i)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return result

func _chunk_touches_any_anchor(chunk_coord: Vector2i, anchor_tiles: Array[Vector2i]) -> bool:
	for anchor_tile: Vector2i in anchor_tiles:
		var anchor_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(anchor_tile)
		if absi(anchor_chunk.x - chunk_coord.x) <= 1 and absi(anchor_chunk.y - chunk_coord.y) <= 1:
			return true
	return false
