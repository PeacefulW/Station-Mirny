class_name MountainCoverRuntime
extends RefCounted

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MountainCavityCache = preload("res://core/systems/world/mountain_cavity_cache.gd")
const WorldDiffStore = preload("res://core/systems/world/world_diff_store.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var roof_layers_per_chunk_max: int = 0

var _cache: MountainCavityCache = MountainCavityCache.new()
var _active_mountain_id: int = 0
var _active_component_id: int = 0
var _chunk_views: Dictionary = { }
var _chunk_packets: Dictionary = { }
var _diff_store: WorldDiffStore = null
var _canonicalize_tile: Callable = Callable()
var _chunk_local_to_tile: Callable = Callable()
var _has_local_player: Callable = Callable()
var _get_local_player_position: Callable = Callable()
var _did_warn_roof_layer_explosion: bool = false


func configure_context(
		chunk_views: Dictionary,
		chunk_packets: Dictionary,
		diff_store: WorldDiffStore,
		canonicalize_tile: Callable,
		chunk_local_to_tile: Callable,
		has_local_player: Callable,
		get_local_player_position: Callable,
) -> void:
	_chunk_views = chunk_views
	_chunk_packets = chunk_packets
	_diff_store = diff_store
	_canonicalize_tile = canonicalize_tile
	_chunk_local_to_tile = chunk_local_to_tile
	_has_local_player = has_local_player
	_get_local_player_position = get_local_player_position


func clear() -> void:
	_cache.clear()
	_active_mountain_id = 0
	_active_component_id = 0
	roof_layers_per_chunk_max = 0
	_did_warn_roof_layer_explosion = false


func get_sample(world_tile: Vector2i) -> Dictionary:
	return _cache.get_sample(world_tile, Callable(self, "_sample_tile"))


func get_debug_snapshot(world_tile: Vector2i) -> Dictionary:
	var debug_snapshot: Dictionary = _cache.get_debug_snapshot(
		world_tile,
		_active_component_id,
		Callable(self, "_sample_tile"),
	)
	debug_snapshot["active_mountain_id"] = _active_mountain_id
	debug_snapshot["active_component_id"] = _active_component_id
	debug_snapshot["roof_layers_per_chunk_max"] = roof_layers_per_chunk_max
	return debug_snapshot


func get_render_debug_snapshot(world_tile: Vector2i) -> Dictionary:
	var probe_tile: Vector2i = _canonicalize_tile_coord(_resolve_debug_probe_tile(world_tile))
	var probe_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(probe_tile)
	var probe_local: Vector2i = WorldRuntimeConstants.tile_to_local(probe_tile)
	var probe_sample: Dictionary = get_sample(probe_tile)
	var expected_open_bit := _expected_open_bit(probe_chunk, probe_local)
	var debug_snapshot := {
		"ready": true,
		"probe_tile": probe_tile,
		"probe_chunk": probe_chunk,
		"probe_local": probe_local,
		"probe_mountain_id": int(probe_sample.get("mountain_id", 0)),
		"probe_component_id": int(probe_sample.get("component_id", 0)),
		"probe_is_opening": bool(probe_sample.get("is_opening", false)),
		"expected_open_bit": expected_open_bit,
		"chunk_view_ready": false,
	}
	var chunk_view: ChunkView = _chunk_views.get(probe_chunk) as ChunkView
	if chunk_view == null:
		return debug_snapshot
	debug_snapshot["chunk_view_ready"] = true
	var render_debug: Dictionary = chunk_view.get_cover_render_debug(
		probe_local,
		int(probe_sample.get("mountain_id", 0)),
		expected_open_bit,
	)
	for key_variant: Variant in render_debug.keys():
		debug_snapshot[key_variant] = render_debug[key_variant]
	return debug_snapshot


func set_active_mountain_component(mountain_id: int, component_id: int) -> void:
	var resolved_component_id: int = component_id if _cache.has_component(component_id) else 0
	var resolved_mountain_id: int = mountain_id if resolved_component_id > 0 else 0
	if resolved_mountain_id == _active_mountain_id \
			and resolved_component_id == _active_component_id:
		return
	_active_mountain_id = resolved_mountain_id
	_active_component_id = resolved_component_id
	_refresh_visibility_for_loaded_chunks()


func on_chunk_published(published_chunk_coord: Vector2i) -> void:
	var cover_result: Dictionary = _cache.on_chunk_loaded(
		published_chunk_coord,
		_collect_candidate_tiles_for_chunk(published_chunk_coord),
		Callable(self, "_sample_tile"),
	)
	var active_change: Dictionary = _repair_active_component_from_player_position()
	var affected_chunks: Dictionary = { }
	for chunk_coord: Vector2i in _variant_to_vector2i_array(
		cover_result.get("affected_chunks", []),
	):
		affected_chunks[chunk_coord] = true
	if bool(active_change.get("state_changed", false)):
		_refresh_visibility_for_loaded_chunks()
		return
	_refresh_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func on_chunk_unloaded(chunk_coord: Vector2i) -> void:
	var cover_result: Dictionary = _cache.on_chunk_unloaded(
		chunk_coord,
		_collect_diff_world_tiles_for_chunk(chunk_coord),
		Callable(self, "_sample_tile"),
	)
	var active_change: Dictionary = _repair_active_component_from_player_position()
	if bool(active_change.get("state_changed", false)):
		_refresh_visibility_for_loaded_chunks()
		return
	var unloaded_chunks: Array[Vector2i] = _variant_to_vector2i_array(
		cover_result.get("affected_chunks", []),
	)
	_refresh_visibility_for_loaded_chunks(unloaded_chunks)


func on_tile_dug(world_tile: Vector2i) -> void:
	var previous_active_component_id: int = _active_component_id
	var cover_result: Dictionary = _cache.on_tile_dug(
		world_tile,
		Callable(self, "_sample_tile"),
	)
	var active_change: Dictionary = _repair_active_component_from_player_position()
	if bool(active_change.get("state_changed", false)):
		_refresh_visibility_for_loaded_chunks()
		return
	var affected_chunks: Dictionary = { }
	for chunk_coord: Vector2i in _variant_to_vector2i_array(
		cover_result.get("affected_chunks", []),
	):
		affected_chunks[chunk_coord] = true
	for component_id: int in [previous_active_component_id, _active_component_id]:
		if component_id <= 0:
			continue
		for component_chunk_coord: Vector2i in _cache.get_component_chunks(component_id):
			affected_chunks[component_chunk_coord] = true
	_refresh_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func track_roof_layer_metric(chunk_coord: Vector2i, packet: Dictionary) -> void:
	var mountain_ids: PackedInt32Array = packet.get(
		"mountain_id_per_tile",
		PackedInt32Array(),
	) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get(
		"mountain_flags",
		PackedByteArray(),
	) as PackedByteArray
	if mountain_ids.is_empty() or mountain_flags.is_empty():
		return
	var present_mountains: Dictionary = { }
	for index: int in range(mini(mountain_ids.size(), mountain_flags.size())):
		var mountain_id: int = int(mountain_ids[index])
		var flags: int = int(mountain_flags[index])
		if mountain_id <= 0 or not _is_mountain_surface_flag(flags):
			continue
		present_mountains[mountain_id] = true
	var mountain_count: int = present_mountains.size()
	if mountain_count > roof_layers_per_chunk_max:
		roof_layers_per_chunk_max = mountain_count
	if mountain_count > 4 and not _did_warn_roof_layer_explosion:
		_did_warn_roof_layer_explosion = true
		push_warning(
			"roof layer explosion: chunk %s has %d mountains" % [chunk_coord, mountain_count],
		)


func _sample_tile(world_tile: Vector2i) -> Dictionary:
	var canonical_tile: Vector2i = _canonicalize_tile_coord(world_tile)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": WorldRuntimeConstants.tile_to_local(canonical_tile),
		}
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var mountain_ids: PackedInt32Array = packet.get(
		"mountain_id_per_tile",
		PackedInt32Array(),
	) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get(
		"mountain_flags",
		PackedByteArray(),
	) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get(
		"walkable_flags",
		PackedByteArray(),
	) as PackedByteArray
	if index < 0 \
			or index >= mountain_ids.size() \
			or index >= mountain_flags.size() \
			or index >= walkable_flags.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"mountain_id": int(mountain_ids[index]),
		"mountain_flags": int(mountain_flags[index]),
		"walkable": int(walkable_flags[index]) != 0,
	}


func _resolve_debug_probe_tile(world_tile: Vector2i) -> Vector2i:
	for offset: Vector2i in [
		Vector2i.ZERO,
		Vector2i.UP,
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i(1, -1),
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]:
		var candidate_tile: Vector2i = world_tile + offset
		var candidate_sample: Dictionary = _sample_tile(candidate_tile)
		if int(candidate_sample.get("mountain_id", 0)) > 0:
			return candidate_tile
	return world_tile


func _expected_open_bit(probe_chunk: Vector2i, probe_local: Vector2i) -> int:
	var visible_mask: PackedByteArray = _cache.build_chunk_visibility_mask(
		probe_chunk,
		_active_component_id,
	)
	var probe_index: int = WorldRuntimeConstants.local_to_index(probe_local)
	if probe_index >= 0 and probe_index < visible_mask.size():
		return int(visible_mask[probe_index])
	return -1


func _collect_candidate_tiles_for_chunk(published_chunk_coord: Vector2i) -> Array[Vector2i]:
	var candidate_tiles: Dictionary = { }
	if _diff_store == null:
		return []
	for sample_chunk_y: int in range(published_chunk_coord.y - 1, published_chunk_coord.y + 2):
		for sample_chunk_x: int in range(published_chunk_coord.x - 1, published_chunk_coord.x + 2):
			var sample_chunk_coord := Vector2i(sample_chunk_x, sample_chunk_y)
			var local_coords := _diff_store.get_chunk_override_local_coords(sample_chunk_coord)
			for local_coord: Vector2i in local_coords:
				candidate_tiles[_chunk_local_to_tile_coord(sample_chunk_coord, local_coord)] = true
	return _dictionary_vector2i_keys(candidate_tiles)


func _collect_diff_world_tiles_for_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
	var world_tiles: Array[Vector2i] = []
	if _diff_store == null:
		return world_tiles
	for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(chunk_coord):
		world_tiles.append(_chunk_local_to_tile_coord(chunk_coord, local_coord))
	return world_tiles


func _repair_active_component_from_player_position() -> Dictionary:
	var previous_mountain_id: int = _active_mountain_id
	var previous_component_id: int = _active_component_id
	if not _has_valid_local_player():
		_active_mountain_id = 0
		_active_component_id = 0
		return {
			"state_changed": previous_mountain_id != 0 or previous_component_id != 0,
			"previous_mountain_id": previous_mountain_id,
			"previous_component_id": previous_component_id,
			"mountain_id": 0,
			"component_id": 0,
		}
	var player_tile: Vector2i = _canonicalize_tile_coord(
		WorldRuntimeConstants.world_to_tile(_get_local_player_position_value()),
	)
	var current_sample: Dictionary = get_sample(player_tile)
	var next_component_id: int = int(current_sample.get("component_id", 0))
	if not _cache.has_component(next_component_id):
		next_component_id = 0
	var next_mountain_id: int = int(current_sample.get("mountain_id", 0)) \
	if next_component_id > 0 \
	else 0
	_active_mountain_id = next_mountain_id
	_active_component_id = next_component_id
	return {
		"state_changed": previous_mountain_id != next_mountain_id
		or previous_component_id != next_component_id,
		"previous_mountain_id": previous_mountain_id,
		"previous_component_id": previous_component_id,
		"mountain_id": next_mountain_id,
		"component_id": next_component_id,
	}


func _refresh_visibility_for_loaded_chunks(target_chunks: Array[Vector2i] = []) -> void:
	var refresh_chunks: Array[Vector2i] = target_chunks
	if refresh_chunks.is_empty():
		refresh_chunks = _dictionary_vector2i_keys(_chunk_views)
	var seen_chunks: Dictionary = { }
	for chunk_coord: Vector2i in refresh_chunks:
		if seen_chunks.has(chunk_coord):
			continue
		seen_chunks[chunk_coord] = true
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view == null:
			continue
		chunk_view.apply_cover_visibility(
			_cache.build_chunk_visibility_mask(chunk_coord, _active_component_id),
		)


func _canonicalize_tile_coord(tile_coord: Vector2i) -> Vector2i:
	if not _canonicalize_tile.is_valid():
		return tile_coord
	var tile_variant: Variant = _canonicalize_tile.call(tile_coord)
	if tile_variant is Vector2i:
		return tile_variant as Vector2i
	return tile_coord


func _chunk_local_to_tile_coord(chunk_coord: Vector2i, local_coord: Vector2i) -> Vector2i:
	if not _chunk_local_to_tile.is_valid():
		return chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord
	var tile_variant: Variant = _chunk_local_to_tile.call(chunk_coord, local_coord)
	if tile_variant is Vector2i:
		return tile_variant as Vector2i
	return chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord


func _has_valid_local_player() -> bool:
	if not _has_local_player.is_valid():
		return false
	return bool(_has_local_player.call())


func _get_local_player_position_value() -> Vector2:
	if not _get_local_player_position.is_valid():
		return Vector2.ZERO
	var position_variant: Variant = _get_local_player_position.call()
	if position_variant is Vector2:
		return position_variant as Vector2
	return Vector2.ZERO


func _dictionary_vector2i_keys(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key_variant: Variant in source.keys():
		result.append(key_variant as Vector2i)
	result.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return result


func _variant_to_vector2i_array(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if value is Array:
		for entry: Variant in value:
			result.append(entry as Vector2i)
	return result


func _is_mountain_surface_flag(flags: int) -> bool:
	var surface_flags := (
		WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	)
	return (flags & surface_flags) != 0
