class_name MountainVisibilityTopology
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const INVALID_TILE: Vector2i = Vector2i(2147483647, 2147483647)

var _tile_state_by_coord: Dictionary = {}
var _component_parent: Dictionary = {}
var _component_tiles: Dictionary = {}
var _component_mountain: Dictionary = {}
var _opening_parent: Dictionary = {}
var _opening_tiles: Dictionary = {}
var _opening_mountain: Dictionary = {}
var _next_component_id: int = 1
var _next_opening_id: int = 1
var _active_component_id: int = 0
var _active_mountain_id: int = 0
var _lingering_component_by_mountain: Dictionary = {}
var _last_viewer_tile: Vector2i = INVALID_TILE

func reset() -> void:
	_tile_state_by_coord.clear()
	_component_parent.clear()
	_component_tiles.clear()
	_component_mountain.clear()
	_opening_parent.clear()
	_opening_tiles.clear()
	_opening_mountain.clear()
	_next_component_id = 1
	_next_opening_id = 1
	_active_component_id = 0
	_active_mountain_id = 0
	_lingering_component_by_mountain.clear()
	_last_viewer_tile = INVALID_TILE

func rebuild_from_loaded_world(loaded_chunk_packets: Dictionary, opening_resolver: Callable) -> void:
	var preserved_viewer_tile: Vector2i = _last_viewer_tile
	reset()
	_last_viewer_tile = preserved_viewer_tile

	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in loaded_chunk_packets.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)

	for chunk_coord: Vector2i in chunk_coords:
		var packet: Dictionary = loaded_chunk_packets.get(chunk_coord, {}) as Dictionary
		if packet.is_empty():
			continue
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
		var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
		var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
		var max_count: int = mini(
			mini(terrain_ids.size(), walkable_flags.size()),
			mini(mountain_ids.size(), mountain_flags.size())
		)
		for index: int in range(max_count):
			if int(walkable_flags[index]) == 0:
				continue
			var mountain_id: int = int(mountain_ids[index])
			if mountain_id <= 0:
				continue
			var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
			var tile_coord := Vector2i(
				chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE + local_coord.x,
				chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE + local_coord.y
			)
			var flags: int = int(mountain_flags[index])
			var is_opening: bool = opening_resolver.is_valid() and bool(opening_resolver.call(tile_coord))
			_tile_state_by_coord[tile_coord] = {
				"tile_coord": tile_coord,
				"chunk_coord": chunk_coord,
				"local_coord": local_coord,
				"terrain_id": int(terrain_ids[index]),
				"mountain_id": mountain_id,
				"mountain_flags": flags,
				"is_interior": (flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0,
				"is_opening": is_opening,
				"component_id": 0,
				"opening_id": 0,
			}

	_rebuild_components()
	_rebuild_openings()
	_restore_active_component_from_viewer_tile()

func apply_walkable_updates(tile_states: Array[Dictionary]) -> void:
	for tile_state: Dictionary in tile_states:
		if not bool(tile_state.get("ready", false)):
			continue
		if not bool(tile_state.get("walkable", false)):
			continue
		var mountain_id: int = int(tile_state.get("mountain_id", 0))
		if mountain_id <= 0:
			continue
		var tile_coord: Vector2i = tile_state.get("tile_coord", INVALID_TILE) as Vector2i
		if tile_coord == INVALID_TILE:
			continue
		var tracked_state: Dictionary = (_tile_state_by_coord.get(tile_coord, {}) as Dictionary).duplicate(true)
		var had_opening: bool = bool(tracked_state.get("is_opening", false))
		var is_new_tile: bool = tracked_state.is_empty()
		tracked_state["tile_coord"] = tile_coord
		tracked_state["chunk_coord"] = tile_state.get("chunk_coord", WorldRuntimeConstants.tile_to_chunk(tile_coord)) as Vector2i
		tracked_state["local_coord"] = tile_state.get("local_coord", WorldRuntimeConstants.tile_to_local(tile_coord)) as Vector2i
		tracked_state["terrain_id"] = int(tile_state.get("terrain_id", tracked_state.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_DUG)))
		tracked_state["mountain_id"] = mountain_id
		tracked_state["mountain_flags"] = int(tile_state.get("mountain_flags", tracked_state.get("mountain_flags", 0)))
		tracked_state["is_interior"] = bool(tile_state.get("is_interior", tracked_state.get("is_interior", false)))
		tracked_state["is_opening"] = bool(tile_state.get("is_opening", tracked_state.get("is_opening", false)))
		if not tracked_state.has("component_id"):
			tracked_state["component_id"] = 0
		if not tracked_state.has("opening_id"):
			tracked_state["opening_id"] = 0
		_tile_state_by_coord[tile_coord] = tracked_state
		if is_new_tile or _normalize_component_id(int(tracked_state.get("component_id", 0))) <= 0:
			_attach_tile_to_component(tile_coord, mountain_id)
		if bool(tracked_state.get("is_opening", false)) and (is_new_tile or not had_opening):
			_attach_tile_to_opening(tile_coord, mountain_id)
	_restore_active_component_from_viewer_tile()

func set_active_component(mountain_id: int, component_id: int, viewer_tile: Vector2i = INVALID_TILE) -> Dictionary:
	if viewer_tile != INVALID_TILE:
		_last_viewer_tile = viewer_tile
	var previous_presented_components: Array[int] = _get_presented_component_ids()
	var previous_component_id: int = _active_component_id
	var previous_mountain_id: int = _active_mountain_id
	_active_component_id = _normalize_component_id(component_id)
	_active_mountain_id = mountain_id if _active_component_id > 0 else 0
	if _active_component_id > 0:
		_active_mountain_id = int(_component_mountain.get(_active_component_id, _active_mountain_id))
	if previous_component_id > 0 and previous_component_id != _active_component_id and previous_mountain_id > 0:
		_lingering_component_by_mountain[previous_mountain_id] = previous_component_id
	if _active_component_id > 0:
		var lingering_component_id: int = _normalize_component_id(
			int(_lingering_component_by_mountain.get(_active_mountain_id, 0))
		)
		if lingering_component_id == _active_component_id:
			_lingering_component_by_mountain.erase(_active_mountain_id)
	var changed: bool = previous_component_id != _active_component_id or previous_mountain_id != _active_mountain_id
	var current_presented_components: Array[int] = _get_presented_component_ids()
	return {
		"changed": changed or previous_presented_components != current_presented_components,
		"previous_component_id": previous_component_id,
		"previous_mountain_id": previous_mountain_id,
		"current_component_id": _active_component_id,
		"current_mountain_id": _active_mountain_id,
		"previous_presented_component_ids": previous_presented_components,
		"current_presented_component_ids": current_presented_components,
	}

func get_active_component_id() -> int:
	return _active_component_id

func get_active_mountain_id() -> int:
	return _active_mountain_id

func get_tile_state(tile_coord: Vector2i) -> Dictionary:
	var tracked_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
	if tracked_state.is_empty():
		return {}
	var normalized_component_id: int = _normalize_component_id(int(tracked_state.get("component_id", 0)))
	var normalized_opening_id: int = _normalize_opening_id(int(tracked_state.get("opening_id", 0)))
	var is_opening: bool = bool(tracked_state.get("is_opening", false))
	var visible_opening: bool = is_opening
	var cover_open: bool = visible_opening or _is_component_presented(normalized_component_id)
	var result: Dictionary = tracked_state.duplicate(true)
	result["component_id"] = normalized_component_id
	result["opening_id"] = normalized_opening_id
	result["cover_open"] = cover_open
	result["visible_opening"] = visible_opening
	return result

func build_cover_masks_for_chunk(
	chunk_coord: Vector2i,
	packet: Dictionary,
	opening_resolver: Callable
) -> Dictionary:
	var masks_by_mountain: Dictionary = {}
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var max_count: int = mini(mountain_ids.size(), mountain_flags.size())
	var presented_components_by_mountain: Dictionary = _get_presented_components_by_mountain()
	for index: int in range(max_count):
		var mountain_id: int = int(mountain_ids[index])
		if mountain_id <= 0:
			continue
		var mountain_presented_components: Dictionary = presented_components_by_mountain.get(mountain_id, {}) as Dictionary
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var tile_coord := Vector2i(
			chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE + local_coord.x,
			chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE + local_coord.y
		)
		if not _should_open_cover_for_mountain_tile(
			tile_coord,
			mountain_id,
			mountain_presented_components
		):
			continue
		if not masks_by_mountain.has(mountain_id):
			var mask := PackedByteArray()
			mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
			masks_by_mountain[mountain_id] = mask
		var mask_for_mountain: PackedByteArray = masks_by_mountain[mountain_id] as PackedByteArray
		mask_for_mountain[index] = 255
		masks_by_mountain[mountain_id] = mask_for_mountain
	return masks_by_mountain

func clear_lingering_component_for_mountain(mountain_id: int) -> Dictionary:
	if mountain_id <= 0:
		return {
			"changed": false,
			"previous_presented_component_ids": _get_presented_component_ids(),
			"current_presented_component_ids": _get_presented_component_ids(),
		}
	var previous_presented_components: Array[int] = _get_presented_component_ids()
	var changed: bool = _lingering_component_by_mountain.erase(mountain_id)
	var current_presented_components: Array[int] = _get_presented_component_ids()
	return {
		"changed": changed and previous_presented_components != current_presented_components,
		"previous_presented_component_ids": previous_presented_components,
		"current_presented_component_ids": current_presented_components,
	}

func collect_chunks_for_mountain(mountain_id: int) -> Array[Vector2i]:
	var unique_chunks: Dictionary = {}
	for component_id_variant: Variant in _component_mountain.keys():
		var component_id: int = _normalize_component_id(int(component_id_variant))
		if component_id <= 0 or int(_component_mountain.get(component_id, 0)) != mountain_id:
			continue
		for chunk_coord: Vector2i in collect_chunks_for_component(component_id):
			unique_chunks[chunk_coord] = true
	return _sorted_chunk_list(unique_chunks)

func collect_chunks_for_component(component_id: int) -> Array[Vector2i]:
	var root_component_id: int = _normalize_component_id(component_id)
	if root_component_id <= 0:
		return []
	var unique_chunks: Dictionary = {}
	var tiles: Array[Vector2i] = _get_component_tile_list(root_component_id)
	for tile_coord: Vector2i in tiles:
		var tracked_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
		var chunk_coord: Vector2i = tracked_state.get("chunk_coord", WorldRuntimeConstants.tile_to_chunk(tile_coord)) as Vector2i
		unique_chunks[chunk_coord] = true
	return _sorted_chunk_list(unique_chunks)

func _rebuild_components() -> void:
	var pending_tiles: Dictionary = _tile_state_by_coord.duplicate()
	var tile_coords: Array[Vector2i] = _sorted_tile_list(pending_tiles)
	for tile_coord: Vector2i in tile_coords:
		var tracked_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
		if tracked_state.is_empty() or int(tracked_state.get("component_id", 0)) != 0:
			continue
		var mountain_id: int = int(tracked_state.get("mountain_id", 0))
		if mountain_id <= 0:
			continue
		var component_id: int = _allocate_component_id(mountain_id)
		var frontier: Array[Vector2i] = [tile_coord]
		var tiles: Array[Vector2i] = []
		var seed_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
		seed_state["component_id"] = component_id
		_tile_state_by_coord[tile_coord] = seed_state
		while not frontier.is_empty():
			var current_tile: Vector2i = frontier.pop_back()
			tiles.append(current_tile)
			for neighbor_tile: Vector2i in _cardinal_neighbors(current_tile):
				var neighbor_state: Dictionary = _tile_state_by_coord.get(neighbor_tile, {}) as Dictionary
				if neighbor_state.is_empty():
					continue
				if int(neighbor_state.get("mountain_id", 0)) != mountain_id:
					continue
				if int(neighbor_state.get("component_id", 0)) != 0:
					continue
				var updated_neighbor_state: Dictionary = _tile_state_by_coord.get(neighbor_tile, {}) as Dictionary
				updated_neighbor_state["component_id"] = component_id
				_tile_state_by_coord[neighbor_tile] = updated_neighbor_state
				frontier.append(neighbor_tile)
		_component_tiles[component_id] = tiles

func _rebuild_openings() -> void:
	var tile_coords: Array[Vector2i] = _sorted_tile_list(_tile_state_by_coord)
	for tile_coord: Vector2i in tile_coords:
		var tracked_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
		if tracked_state.is_empty() or not bool(tracked_state.get("is_opening", false)):
			continue
		if int(tracked_state.get("opening_id", 0)) != 0:
			continue
		var mountain_id: int = int(tracked_state.get("mountain_id", 0))
		var opening_id: int = _allocate_opening_id(mountain_id)
		var frontier: Array[Vector2i] = [tile_coord]
		var tiles: Array[Vector2i] = []
		var seed_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
		seed_state["opening_id"] = opening_id
		_tile_state_by_coord[tile_coord] = seed_state
		while not frontier.is_empty():
			var current_tile: Vector2i = frontier.pop_back()
			tiles.append(current_tile)
			for neighbor_tile: Vector2i in _cardinal_neighbors(current_tile):
				var neighbor_state: Dictionary = _tile_state_by_coord.get(neighbor_tile, {}) as Dictionary
				if neighbor_state.is_empty():
					continue
				if not bool(neighbor_state.get("is_opening", false)):
					continue
				if int(neighbor_state.get("mountain_id", 0)) != mountain_id:
					continue
				if int(neighbor_state.get("opening_id", 0)) != 0:
					continue
				var updated_neighbor_state: Dictionary = _tile_state_by_coord.get(neighbor_tile, {}) as Dictionary
				updated_neighbor_state["opening_id"] = opening_id
				_tile_state_by_coord[neighbor_tile] = updated_neighbor_state
				frontier.append(neighbor_tile)
		_opening_tiles[opening_id] = tiles

func _attach_tile_to_component(tile_coord: Vector2i, mountain_id: int) -> void:
	var neighbor_component_roots: Dictionary = {}
	for neighbor_tile: Vector2i in _cardinal_neighbors(tile_coord):
		var neighbor_state: Dictionary = _tile_state_by_coord.get(neighbor_tile, {}) as Dictionary
		if neighbor_state.is_empty():
			continue
		if int(neighbor_state.get("mountain_id", 0)) != mountain_id:
			continue
		var neighbor_component_id: int = _normalize_component_id(int(neighbor_state.get("component_id", 0)))
		if neighbor_component_id > 0:
			neighbor_component_roots[neighbor_component_id] = true

	var root_component_id: int = 0
	if neighbor_component_roots.is_empty():
		root_component_id = _allocate_component_id(mountain_id)
		_component_tiles[root_component_id] = _single_tile_list(tile_coord)
	else:
		var sorted_roots: Array[int] = []
		for component_id_variant: Variant in neighbor_component_roots.keys():
			sorted_roots.append(int(component_id_variant))
		sorted_roots.sort()
		root_component_id = sorted_roots[0]
		var root_tiles: Array[Vector2i] = _get_component_tile_list(root_component_id)
		root_tiles.append(tile_coord)
		_component_tiles[root_component_id] = root_tiles
		for component_id: int in sorted_roots:
			root_component_id = _merge_components(root_component_id, component_id)

	var updated_tile_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
	updated_tile_state["component_id"] = root_component_id
	_tile_state_by_coord[tile_coord] = updated_tile_state

func _attach_tile_to_opening(tile_coord: Vector2i, mountain_id: int) -> void:
	var neighbor_opening_roots: Dictionary = {}
	for neighbor_tile: Vector2i in _cardinal_neighbors(tile_coord):
		var neighbor_state: Dictionary = _tile_state_by_coord.get(neighbor_tile, {}) as Dictionary
		if neighbor_state.is_empty():
			continue
		if int(neighbor_state.get("mountain_id", 0)) != mountain_id:
			continue
		if not bool(neighbor_state.get("is_opening", false)):
			continue
		var neighbor_opening_id: int = _normalize_opening_id(int(neighbor_state.get("opening_id", 0)))
		if neighbor_opening_id > 0:
			neighbor_opening_roots[neighbor_opening_id] = true

	var root_opening_id: int = 0
	if neighbor_opening_roots.is_empty():
		root_opening_id = _allocate_opening_id(mountain_id)
		_opening_tiles[root_opening_id] = _single_tile_list(tile_coord)
	else:
		var sorted_roots: Array[int] = []
		for opening_id_variant: Variant in neighbor_opening_roots.keys():
			sorted_roots.append(int(opening_id_variant))
		sorted_roots.sort()
		root_opening_id = sorted_roots[0]
		var root_tiles: Array[Vector2i] = _get_opening_tile_list(root_opening_id)
		root_tiles.append(tile_coord)
		_opening_tiles[root_opening_id] = root_tiles
		for opening_id: int in sorted_roots:
			root_opening_id = _merge_openings(root_opening_id, opening_id)

	var updated_tile_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
	updated_tile_state["opening_id"] = root_opening_id
	_tile_state_by_coord[tile_coord] = updated_tile_state

func _allocate_component_id(mountain_id: int) -> int:
	var component_id: int = _next_component_id
	_next_component_id += 1
	_component_parent[component_id] = component_id
	_component_mountain[component_id] = mountain_id
	return component_id

func _allocate_opening_id(mountain_id: int) -> int:
	var opening_id: int = _next_opening_id
	_next_opening_id += 1
	_opening_parent[opening_id] = opening_id
	_opening_mountain[opening_id] = mountain_id
	return opening_id

func _merge_components(lhs_component_id: int, rhs_component_id: int) -> int:
	var lhs_root: int = _normalize_component_id(lhs_component_id)
	var rhs_root: int = _normalize_component_id(rhs_component_id)
	if lhs_root <= 0:
		return rhs_root
	if rhs_root <= 0 or lhs_root == rhs_root:
		return lhs_root
	var lhs_tiles: Array[Vector2i] = _get_component_tile_list(lhs_root)
	var rhs_tiles: Array[Vector2i] = _get_component_tile_list(rhs_root)
	if rhs_tiles.size() > lhs_tiles.size():
		var swapped_root: int = lhs_root
		lhs_root = rhs_root
		rhs_root = swapped_root
		lhs_tiles = _get_component_tile_list(lhs_root)
		rhs_tiles = _get_component_tile_list(rhs_root)
	lhs_tiles.append_array(rhs_tiles)
	_component_tiles[lhs_root] = lhs_tiles
	_component_parent[rhs_root] = lhs_root
	_component_tiles.erase(rhs_root)
	_component_mountain.erase(rhs_root)
	return lhs_root

func _merge_openings(lhs_opening_id: int, rhs_opening_id: int) -> int:
	var lhs_root: int = _normalize_opening_id(lhs_opening_id)
	var rhs_root: int = _normalize_opening_id(rhs_opening_id)
	if lhs_root <= 0:
		return rhs_root
	if rhs_root <= 0 or lhs_root == rhs_root:
		return lhs_root
	var lhs_tiles: Array[Vector2i] = _get_opening_tile_list(lhs_root)
	var rhs_tiles: Array[Vector2i] = _get_opening_tile_list(rhs_root)
	if rhs_tiles.size() > lhs_tiles.size():
		var swapped_root: int = lhs_root
		lhs_root = rhs_root
		rhs_root = swapped_root
		lhs_tiles = _get_opening_tile_list(lhs_root)
		rhs_tiles = _get_opening_tile_list(rhs_root)
	lhs_tiles.append_array(rhs_tiles)
	_opening_tiles[lhs_root] = lhs_tiles
	_opening_parent[rhs_root] = lhs_root
	_opening_tiles.erase(rhs_root)
	_opening_mountain.erase(rhs_root)
	return lhs_root

func _get_component_tile_list(component_id: int) -> Array[Vector2i]:
	return _typed_tile_list_from_variant(_component_tiles.get(component_id, null))

func _get_opening_tile_list(opening_id: int) -> Array[Vector2i]:
	return _typed_tile_list_from_variant(_opening_tiles.get(opening_id, null))

func _single_tile_list(tile_coord: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.append(tile_coord)
	return tiles

func _typed_tile_list_from_variant(source: Variant) -> Array[Vector2i]:
	var typed_tiles: Array[Vector2i] = []
	if source == null:
		return typed_tiles
	for tile_coord_variant: Variant in source as Array:
		typed_tiles.append(tile_coord_variant as Vector2i)
	return typed_tiles

func _normalize_component_id(component_id: int) -> int:
	if component_id <= 0:
		return 0
	var root_component_id: int = component_id
	while _component_parent.has(root_component_id) and int(_component_parent[root_component_id]) != root_component_id:
		root_component_id = int(_component_parent[root_component_id])
	if root_component_id <= 0 or not _component_parent.has(root_component_id):
		return 0
	var current_component_id: int = component_id
	while _component_parent.has(current_component_id) and int(_component_parent[current_component_id]) != root_component_id:
		var parent_component_id: int = int(_component_parent[current_component_id])
		_component_parent[current_component_id] = root_component_id
		current_component_id = parent_component_id
	return root_component_id

func _normalize_opening_id(opening_id: int) -> int:
	if opening_id <= 0:
		return 0
	var root_opening_id: int = opening_id
	while _opening_parent.has(root_opening_id) and int(_opening_parent[root_opening_id]) != root_opening_id:
		root_opening_id = int(_opening_parent[root_opening_id])
	if root_opening_id <= 0 or not _opening_parent.has(root_opening_id):
		return 0
	var current_opening_id: int = opening_id
	while _opening_parent.has(current_opening_id) and int(_opening_parent[current_opening_id]) != root_opening_id:
		var parent_opening_id: int = int(_opening_parent[current_opening_id])
		_opening_parent[current_opening_id] = root_opening_id
		current_opening_id = parent_opening_id
	return root_opening_id

func _restore_active_component_from_viewer_tile() -> void:
	if _last_viewer_tile == INVALID_TILE:
		_active_component_id = 0
		_active_mountain_id = 0
		return
	var tracked_state: Dictionary = get_tile_state(_last_viewer_tile)
	_active_component_id = _normalize_component_id(int(tracked_state.get("component_id", 0)))
	_active_mountain_id = int(tracked_state.get("mountain_id", 0)) if _active_component_id > 0 else 0
	if _active_component_id > 0:
		var lingering_component_id: int = _normalize_component_id(
			int(_lingering_component_by_mountain.get(_active_mountain_id, 0))
		)
		if lingering_component_id == _active_component_id:
			_lingering_component_by_mountain.erase(_active_mountain_id)

func _is_component_presented(component_id: int) -> bool:
	var normalized_component_id: int = _normalize_component_id(component_id)
	if normalized_component_id <= 0:
		return false
	if normalized_component_id == _active_component_id:
		return true
	for lingering_component_variant: Variant in _lingering_component_by_mountain.values():
		if _normalize_component_id(int(lingering_component_variant)) == normalized_component_id:
			return true
	return false

func _get_presented_component_ids() -> Array[int]:
	var unique_components: Dictionary = {}
	if _active_component_id > 0:
		unique_components[_active_component_id] = true
	for lingering_component_variant: Variant in _lingering_component_by_mountain.values():
		var component_id: int = _normalize_component_id(int(lingering_component_variant))
		if component_id > 0:
			unique_components[component_id] = true
	return _sorted_int_keys(unique_components)

func _has_presented_components() -> bool:
	return not _get_presented_component_ids().is_empty()

func _get_presented_components_by_mountain() -> Dictionary:
	var components_by_mountain: Dictionary = {}
	for component_id: int in _get_presented_component_ids():
		var mountain_id: int = int(_component_mountain.get(component_id, 0))
		if mountain_id <= 0:
			continue
		if not components_by_mountain.has(mountain_id):
			components_by_mountain[mountain_id] = {}
		var mountain_components: Dictionary = components_by_mountain[mountain_id] as Dictionary
		mountain_components[component_id] = true
		components_by_mountain[mountain_id] = mountain_components
	return components_by_mountain

func _should_open_cover_for_mountain_tile(
	tile_coord: Vector2i,
	mountain_id: int,
	presented_components: Dictionary
) -> bool:
	var tracked_state: Dictionary = _tile_state_by_coord.get(tile_coord, {}) as Dictionary
	if not tracked_state.is_empty():
		if int(tracked_state.get("mountain_id", 0)) != mountain_id:
			return false
		var component_id: int = _normalize_component_id(int(tracked_state.get("component_id", 0)))
		if bool(tracked_state.get("is_opening", false)):
			return true
		return presented_components.has(component_id)
	for neighbor_tile: Vector2i in _geometry_neighbors_inclusive(tile_coord):
		var neighbor_state: Dictionary = _tile_state_by_coord.get(neighbor_tile, {}) as Dictionary
		if neighbor_state.is_empty():
			continue
		if int(neighbor_state.get("mountain_id", 0)) != mountain_id:
			continue
		var neighbor_component_id: int = _normalize_component_id(int(neighbor_state.get("component_id", 0)))
		if bool(neighbor_state.get("is_opening", false)):
			return true
		if presented_components.has(neighbor_component_id):
			return true
	return false

func _cardinal_neighbors(tile_coord: Vector2i) -> Array[Vector2i]:
	return [
		tile_coord + Vector2i.LEFT,
		tile_coord + Vector2i.RIGHT,
		tile_coord + Vector2i.UP,
		tile_coord + Vector2i.DOWN,
	]

func _geometry_neighbors_inclusive(tile_coord: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			neighbors.append(tile_coord + Vector2i(offset_x, offset_y))
	return neighbors

func _sorted_tile_list(source: Dictionary) -> Array[Vector2i]:
	var tile_coords: Array[Vector2i] = []
	for tile_coord_variant: Variant in source.keys():
		tile_coords.append(tile_coord_variant as Vector2i)
	tile_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return tile_coords

func _sorted_chunk_list(source: Dictionary) -> Array[Vector2i]:
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in source.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return chunk_coords

func _sorted_int_keys(source: Dictionary) -> Array[int]:
	var values: Array[int] = []
	for value_variant: Variant in source.keys():
		values.append(int(value_variant))
	values.sort()
	return values
