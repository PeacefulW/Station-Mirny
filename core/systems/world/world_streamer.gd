class_name WorldStreamer
extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MountainEntrance = preload("res://core/systems/world/mountain_entrance.gd")
const MountainRevealRegistry = preload("res://core/systems/world/mountain_reveal_registry.gd")
const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const WorldDiffStore = preload("res://core/systems/world/world_diff_store.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

const INVALID_CHUNK_COORD: Vector2i = Vector2i(2147483647, 2147483647)

var world_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var world_version: int = WorldRuntimeConstants.WORLD_VERSION

var _world_core: Object = null
var _diff_store: WorldDiffStore = WorldDiffStore.new()
var _chunk_packets: Dictionary = {}
var _chunk_views: Dictionary = {}
var _requested_chunks: Dictionary = {}
var _pending_publish_queue: Array[Vector2i] = []
var _active_publish_chunk: Vector2i = INVALID_CHUNK_COORD
var _player_chunk_coord: Vector2i = INVALID_CHUNK_COORD
var _stream_job_id: StringName = &""
var _generation_epoch: int = 0
var _settings_packed: PackedFloat32Array = PackedFloat32Array()
var roof_layers_per_chunk_max: int = 0

var _worker_thread: Thread = Thread.new()
var _request_mutex: Mutex = Mutex.new()
var _result_mutex: Mutex = Mutex.new()
var _request_semaphore: Semaphore = Semaphore.new()
var _pending_requests: Array[Dictionary] = []
var _completed_packets: Array[Dictionary] = []
var _worker_should_exit: bool = false
var _mountain_reveal_registry: MountainRevealRegistry = null
var _did_warn_roof_layer_explosion: bool = false

func _ready() -> void:
	add_to_group("chunk_manager")
	name = "WorldStreamer"
	_world_core = ClassDB.instantiate("WorldCore")
	assert(_world_core != null, "WorldCore required - build GDExtension first")
	_settings_packed = _resolve_settings_packed_for_world_version(world_version)
	WorldTileSetFactory.bootstrap()
	_ensure_mountain_reveal_registry()
	_start_worker_thread()
	_stream_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		1.5,
		_streaming_tick,
		&"world.streaming_v0",
		RuntimeWorkTypes.CadenceKind.NEAR_PLAYER,
		RuntimeWorkTypes.ThreadingRole.COMPUTE_THEN_APPLY,
		true,
		"World runtime V0 streaming"
	)

func _exit_tree() -> void:
	if _stream_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_stream_job_id)
	_stop_worker_thread()

func reset_for_new_game(
	seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED,
	version: int = WorldRuntimeConstants.WORLD_VERSION
) -> void:
	world_seed = seed
	world_version = version
	_settings_packed = _resolve_settings_packed_for_world_version(world_version)
	_diff_store.clear()
	_reset_runtime_state()
	EventBus.world_initialized.emit(world_seed)

func load_world_state(data: Dictionary) -> void:
	world_seed = int(data.get("world_seed", WorldRuntimeConstants.DEFAULT_WORLD_SEED))
	world_version = int(data.get("world_version", WorldRuntimeConstants.WORLD_VERSION))
	_settings_packed = _resolve_settings_packed_for_world_version(world_version)
	_diff_store.clear()
	_reset_runtime_state()
	EventBus.world_initialized.emit(world_seed)

func save_world_state() -> Dictionary:
	return {
		"world_rebuild_frozen": false,
		"world_scene_present": true,
		"world_seed": world_seed,
		"world_version": world_version,
	}

func collect_chunk_diffs() -> Array[Dictionary]:
	return _diff_store.serialize_dirty_chunks()

func load_chunk_diffs(entries: Array) -> void:
	_diff_store.load_serialized_chunks(entries)
	_refresh_loaded_packets_from_diffs()

func get_world_seed() -> int:
	return world_seed

func get_world_version() -> int:
	return world_version

func get_chunk_packet(chunk_coord: Vector2i) -> Dictionary:
	return _chunk_packets.get(chunk_coord, {}) as Dictionary

func get_mountain_reveal_registry() -> MountainRevealRegistry:
	return _mountain_reveal_registry

func recompute_entrance_for_tile(world_tile: Vector2i) -> void:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(world_tile)
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if chunk_view == null:
		return
	if get_chunk_packet(chunk_coord).is_empty():
		return
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(world_tile)
	chunk_view.set_entrance_flag(
		local_coord,
		MountainEntrance.recompute_entrance_flag(world_tile, self)
	)

func recompute_entrance_for_neighborhood(world_tile: Vector2i) -> void:
	recompute_entrance_for_tile(world_tile)
	recompute_entrance_for_tile(world_tile + Vector2i.LEFT)
	recompute_entrance_for_tile(world_tile + Vector2i.RIGHT)
	recompute_entrance_for_tile(world_tile + Vector2i.UP)
	recompute_entrance_for_tile(world_tile + Vector2i.DOWN)

func recompute_entrance_for_chunk_load(chunk_coord: Vector2i) -> void:
	var dirty_local_coords: Array[Vector2i] = _diff_store.get_chunk_override_local_coords(chunk_coord)
	if dirty_local_coords.is_empty():
		return
	var dirty_world_tiles: Dictionary = {}
	for local_coord: Vector2i in dirty_local_coords:
		var world_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_coord)
		dirty_world_tiles[world_tile] = true
		dirty_world_tiles[world_tile + Vector2i.LEFT] = true
		dirty_world_tiles[world_tile + Vector2i.RIGHT] = true
		dirty_world_tiles[world_tile + Vector2i.UP] = true
		dirty_world_tiles[world_tile + Vector2i.DOWN] = true
	var tiles_to_recompute: Array[Vector2i] = []
	for tile_variant: Variant in dirty_world_tiles.keys():
		tiles_to_recompute.append(tile_variant as Vector2i)
	tiles_to_recompute.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	for world_tile: Vector2i in tiles_to_recompute:
		recompute_entrance_for_tile(world_tile)

func is_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	return bool(tile_data.get("walkable", false))

func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	return _is_diggable_surface_terrain(int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))

func try_harvest_at_world(world_pos: Vector2) -> Dictionary:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return {
			"success": false,
			"message_key": "SYSTEM_WORLD_CHUNK_NOT_READY",
		}
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	if not _is_diggable_surface_terrain(terrain_id):
		return {
			"success": false,
			"message_key": "SYSTEM_WORLD_TILE_NOT_DIGGABLE",
		}

	var chunk_coord: Vector2i = tile_data.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var local_coord: Vector2i = tile_data.get("local_coord", Vector2i.ZERO) as Vector2i
	_diff_store.set_tile_override(
		chunk_coord,
		local_coord,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		true
	)
	_apply_loaded_override(chunk_coord, local_coord, WorldRuntimeConstants.TERRAIN_PLAINS_DUG, true)
	recompute_entrance_for_neighborhood(_chunk_local_to_tile(chunk_coord, local_coord))
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		EventBus.mountain_tile_mined.emit(_chunk_local_to_tile(chunk_coord, local_coord), terrain_id, WorldRuntimeConstants.TERRAIN_PLAINS_DUG)
	return {
		"success": true,
		"item_id": "base:scrap",
		"amount": 1,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
	}

func _streaming_tick() -> bool:
	_update_player_chunk_coord()
	_enqueue_desired_chunks()
	_drain_completed_packets(1)
	_publish_next_batch()
	_evict_outside_ring(1)
	return _has_pending_streaming_work()

func _update_player_chunk_coord() -> void:
	var player_pos: Vector2 = PlayerAuthority.get_local_player_position()
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(player_pos)
	_player_chunk_coord = WorldRuntimeConstants.tile_to_chunk(tile_coord)

func _enqueue_desired_chunks() -> void:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		return
	for desired_coord: Vector2i in _build_desired_chunk_coords(_player_chunk_coord):
		if _chunk_packets.has(desired_coord):
			if not _pending_publish_queue.has(desired_coord) and not _chunk_views.has(desired_coord):
				_pending_publish_queue.append(desired_coord)
			continue
		if _requested_chunks.has(desired_coord):
			continue
		_requested_chunks[desired_coord] = true
		_request_mutex.lock()
		_pending_requests.append({
			"coord": desired_coord,
			"seed": world_seed,
			"world_version": world_version,
			"settings_packed": _settings_packed,
			"epoch": _generation_epoch,
		})
		_request_mutex.unlock()
		_request_semaphore.post()

func _drain_completed_packets(max_count: int) -> void:
	var drained: Array[Dictionary] = []
	_result_mutex.lock()
	var drain_count: int = mini(max_count, _completed_packets.size())
	for _i: int in range(drain_count):
		drained.append(_completed_packets.pop_front() as Dictionary)
	_result_mutex.unlock()

	for packet: Dictionary in drained:
		if int(packet.get("epoch", -1)) != _generation_epoch:
			continue
		var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
		_requested_chunks.erase(chunk_coord)
		var merged_packet: Dictionary = _diff_store.apply_to_packet(packet)
		_chunk_packets[chunk_coord] = merged_packet
		_refresh_loaded_visuals_around_chunk_overrides(chunk_coord)
		if _is_chunk_desired(chunk_coord) and not _pending_publish_queue.has(chunk_coord) and chunk_coord != _active_publish_chunk:
			_pending_publish_queue.append(chunk_coord)

func _publish_next_batch() -> void:
	if _active_publish_chunk == INVALID_CHUNK_COORD:
		if _pending_publish_queue.is_empty():
			return
		_active_publish_chunk = _pending_publish_queue.pop_front()
		var packet: Dictionary = _chunk_packets.get(_active_publish_chunk, {}) as Dictionary
		if packet.is_empty():
			_active_publish_chunk = INVALID_CHUNK_COORD
			return
		_track_roof_layer_metric(_active_publish_chunk, packet)
		var chunk_view: ChunkView = _ensure_chunk_view(_active_publish_chunk)
		chunk_view.begin_apply(packet)

	var active_view: ChunkView = _chunk_views.get(_active_publish_chunk) as ChunkView
	if active_view == null:
		_active_publish_chunk = INVALID_CHUNK_COORD
		return
	var has_more: bool = active_view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE)
	if not has_more:
		_recompute_entrance_after_chunk_publish(_active_publish_chunk)
		active_view.visible = true
		EventBus.chunk_loaded.emit(_active_publish_chunk)
		_active_publish_chunk = INVALID_CHUNK_COORD

func _evict_outside_ring(max_count: int) -> void:
	var evicted: int = 0
	var loaded_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _chunk_views.keys():
		loaded_coords.append(chunk_coord_variant as Vector2i)
	loaded_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	for chunk_coord: Vector2i in loaded_coords:
		if evicted >= max_count:
			break
		if chunk_coord == _active_publish_chunk or _is_chunk_desired(chunk_coord):
			continue
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view:
			chunk_view.queue_free()
		_chunk_views.erase(chunk_coord)
		_chunk_packets.erase(chunk_coord)
		_requested_chunks.erase(chunk_coord)
		_pending_publish_queue.erase(chunk_coord)
		EventBus.chunk_unloaded.emit(chunk_coord)
		evicted += 1

func _has_pending_streaming_work() -> bool:
	if not _pending_publish_queue.is_empty():
		return true
	if _active_publish_chunk != INVALID_CHUNK_COORD:
		return true
	_request_mutex.lock()
	var has_pending_requests: bool = not _pending_requests.is_empty()
	_request_mutex.unlock()
	if has_pending_requests:
		return true
	_result_mutex.lock()
	var has_completed_packets: bool = not _completed_packets.is_empty()
	_result_mutex.unlock()
	if has_completed_packets:
		return true
	for chunk_coord_variant: Variant in _chunk_views.keys():
		if not _is_chunk_desired(chunk_coord_variant as Vector2i):
			return true
	return false

func _get_tile_data(world_pos: Vector2) -> Dictionary:
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)

	var override_data: Dictionary = _diff_store.get_tile_override(chunk_coord, local_coord)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
	if packet.is_empty():
		_enqueue_chunk_if_needed(chunk_coord)
		if not override_data.is_empty():
			return {
				"ready": true,
				"chunk_coord": chunk_coord,
				"local_coord": local_coord,
				"terrain_id": int(override_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
				"walkable": bool(override_data.get("walkable", true)),
			}
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}

	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": int(terrain_ids[index]),
		"walkable": int(walkable_flags[index]) != 0,
	}

func _get_entrance_tile_state(world_tile: Vector2i) -> Dictionary:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(world_tile)
	var packet: Dictionary = get_chunk_packet(chunk_coord)
	if packet.is_empty():
		return {"ready": false}
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(world_tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	if index < 0 \
			or index >= mountain_ids.size() \
			or index >= mountain_flags.size() \
			or index >= walkable_flags.size():
		return {"ready": false}
	var override_data: Dictionary = _diff_store.get_tile_override(chunk_coord, local_coord)
	var walkable: bool = int(walkable_flags[index]) != 0
	if not override_data.is_empty():
		walkable = bool(override_data.get("walkable", walkable))
	return {
		"ready": true,
		"mountain_id": int(mountain_ids[index]),
		"mountain_flags": int(mountain_flags[index]),
		"walkable": walkable,
	}

func _enqueue_chunk_if_needed(chunk_coord: Vector2i) -> void:
	if _requested_chunks.has(chunk_coord) or _chunk_packets.has(chunk_coord):
		return
	_requested_chunks[chunk_coord] = true
	_request_mutex.lock()
	_pending_requests.append({
		"coord": chunk_coord,
		"seed": world_seed,
		"world_version": world_version,
		"settings_packed": _settings_packed,
		"epoch": _generation_epoch,
	})
	_request_mutex.unlock()
	_request_semaphore.post()

func _apply_loaded_override(chunk_coord: Vector2i, local_coord: Vector2i, terrain_id: int, walkable: bool) -> void:
	if not _chunk_packets.has(chunk_coord):
		return
	var packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
	var terrain_ids: PackedInt32Array = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
	var terrain_atlas_indices: PackedInt32Array = (packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	var walkable_flags: PackedByteArray = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return
	if terrain_atlas_indices.size() < terrain_ids.size():
		terrain_atlas_indices.resize(terrain_ids.size())
	terrain_ids[index] = terrain_id
	walkable_flags[index] = 1 if walkable else 0
	terrain_atlas_indices[index] = 0
	packet["terrain_ids"] = terrain_ids
	packet["terrain_atlas_indices"] = terrain_atlas_indices
	packet["walkable_flags"] = walkable_flags
	_chunk_packets[chunk_coord] = packet
	_refresh_loaded_visual_patch_for_tiles([
		_chunk_local_to_tile(chunk_coord, local_coord),
	])

func _refresh_loaded_packets_from_diffs() -> void:
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _chunk_packets.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	for chunk_coord: Vector2i in chunk_coords:
		var base_packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
		_chunk_packets[chunk_coord] = _diff_store.apply_to_packet(base_packet)
		_refresh_loaded_visuals_around_chunk_overrides(chunk_coord)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view:
			_track_roof_layer_metric(chunk_coord, _chunk_packets[chunk_coord] as Dictionary)
			chunk_view.begin_apply(_chunk_packets[chunk_coord] as Dictionary)
			if not _pending_publish_queue.has(chunk_coord):
				_pending_publish_queue.append(chunk_coord)

func _refresh_loaded_visuals_around_chunk_overrides(center_chunk_coord: Vector2i) -> void:
	var origin_tiles: Array[Vector2i] = []
	for y: int in range(center_chunk_coord.y - 1, center_chunk_coord.y + 2):
		for x: int in range(center_chunk_coord.x - 1, center_chunk_coord.x + 2):
			var sample_chunk_coord := Vector2i(x, y)
			for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(sample_chunk_coord):
				origin_tiles.append(_chunk_local_to_tile(sample_chunk_coord, local_coord))
	if origin_tiles.is_empty():
		return
	_refresh_loaded_visual_patch_for_tiles(origin_tiles)

func _refresh_loaded_visual_patch_for_tiles(origin_tiles: Array[Vector2i]) -> void:
	var seen_tiles: Dictionary = {}
	var updates_by_chunk: Dictionary = {}
	for origin_tile: Vector2i in origin_tiles:
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var tile_coord: Vector2i = origin_tile + Vector2i(offset_x, offset_y)
				if seen_tiles.has(tile_coord):
					continue
				seen_tiles[tile_coord] = true
				var update: Dictionary = _build_loaded_visual_update(tile_coord)
				if update.is_empty():
					continue
				var chunk_coord: Vector2i = update.get("chunk_coord", INVALID_CHUNK_COORD) as Vector2i
				if chunk_coord == INVALID_CHUNK_COORD:
					continue
				if not updates_by_chunk.has(chunk_coord):
					updates_by_chunk[chunk_coord] = {}
				var local_coord: Vector2i = update.get("local_coord", Vector2i.ZERO) as Vector2i
				var chunk_updates: Dictionary = updates_by_chunk[chunk_coord] as Dictionary
				chunk_updates[local_coord] = update
	for chunk_coord_variant: Variant in updates_by_chunk.keys():
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		var packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
		if packet.is_empty():
			continue
		var terrain_ids: PackedInt32Array = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
		var terrain_atlas_indices: PackedInt32Array = (packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
		var walkable_flags: PackedByteArray = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
		if terrain_atlas_indices.size() < terrain_ids.size():
			terrain_atlas_indices.resize(terrain_ids.size())
		var chunk_updates: Dictionary = updates_by_chunk[chunk_coord] as Dictionary
		for local_coord_variant: Variant in chunk_updates.keys():
			var local_coord: Vector2i = local_coord_variant as Vector2i
			var update: Dictionary = chunk_updates.get(local_coord, {}) as Dictionary
			var index: int = WorldRuntimeConstants.local_to_index(local_coord)
			if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
				continue
			terrain_ids[index] = int(update.get("terrain_id", terrain_ids[index]))
			walkable_flags[index] = 1 if bool(update.get("walkable", int(walkable_flags[index]) != 0)) else 0
			terrain_atlas_indices[index] = int(update.get("terrain_atlas_index", terrain_atlas_indices[index]))
		packet["terrain_ids"] = terrain_ids
		packet["terrain_atlas_indices"] = terrain_atlas_indices
		packet["walkable_flags"] = walkable_flags
		_chunk_packets[chunk_coord] = packet
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view:
			for local_coord_variant: Variant in chunk_updates.keys():
				var local_coord: Vector2i = local_coord_variant as Vector2i
				var update: Dictionary = chunk_updates.get(local_coord, {}) as Dictionary
				chunk_view.apply_runtime_cell(
					local_coord,
					int(update.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
					int(update.get("terrain_atlas_index", 0))
				)

func _build_loaded_visual_update(tile_coord: Vector2i) -> Dictionary:
	var tile_data: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord)
	if not bool(tile_data.get("ready", false)):
		return {}
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var terrain_atlas_index: int = 0
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
		terrain_atlas_index = _resolve_loaded_ground_atlas_index(tile_coord)
	elif _uses_mountain_surface_presentation(terrain_id):
		var mountain_atlas_data: Dictionary = _try_resolve_loaded_mountain_atlas_index(tile_coord)
		if not bool(mountain_atlas_data.get("ready", false)):
			return {}
		terrain_atlas_index = int(mountain_atlas_data.get("terrain_atlas_index", 0))
	return {
		"chunk_coord": tile_data.get("chunk_coord", INVALID_CHUNK_COORD) as Vector2i,
		"local_coord": tile_data.get("local_coord", Vector2i.ZERO) as Vector2i,
		"terrain_id": terrain_id,
		"terrain_atlas_index": terrain_atlas_index,
		"walkable": bool(tile_data.get("walkable", true)),
	}

func _resolve_loaded_ground_atlas_index(tile_coord: Vector2i) -> int:
	# TODO: switch plains-ground edge solving to water adjacency once water
	# terrain exists. For now, ground always uses solid atlas variants only.
	return Autotile47.build_solid_atlas_index(tile_coord, world_seed)

func _try_resolve_loaded_mountain_atlas_index(tile_coord: Vector2i) -> Dictionary:
	var north: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord + Vector2i(0, -1))
	var east: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord + Vector2i(1, 0))
	var south: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord + Vector2i(0, 1))
	var west: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord + Vector2i(-1, 0))
	if not bool(north.get("ready", false)) \
			or not bool(east.get("ready", false)) \
			or not bool(south.get("ready", false)) \
			or not bool(west.get("ready", false)):
		return {"ready": false}
	var is_north_mountain: bool = _uses_mountain_surface_presentation(int(north.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))
	var is_east_mountain: bool = _uses_mountain_surface_presentation(int(east.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))
	var is_south_mountain: bool = _uses_mountain_surface_presentation(int(south.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))
	var is_west_mountain: bool = _uses_mountain_surface_presentation(int(west.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))
	var is_north_east_mountain: bool = false
	var is_south_east_mountain: bool = false
	var is_south_west_mountain: bool = false
	var is_north_west_mountain: bool = false
	if is_north_mountain and is_east_mountain:
		var north_east: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord + Vector2i(1, -1))
		if not bool(north_east.get("ready", false)):
			return {"ready": false}
		is_north_east_mountain = _uses_mountain_surface_presentation(int(north_east.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))
	if is_south_mountain and is_east_mountain:
		var south_east: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord + Vector2i(1, 1))
		if not bool(south_east.get("ready", false)):
			return {"ready": false}
		is_south_east_mountain = _uses_mountain_surface_presentation(int(south_east.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))
	if is_south_mountain and is_west_mountain:
		var south_west: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord + Vector2i(-1, 1))
		if not bool(south_west.get("ready", false)):
			return {"ready": false}
		is_south_west_mountain = _uses_mountain_surface_presentation(int(south_west.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))
	if is_north_mountain and is_west_mountain:
		var north_west: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord + Vector2i(-1, -1))
		if not bool(north_west.get("ready", false)):
			return {"ready": false}
		is_north_west_mountain = _uses_mountain_surface_presentation(int(north_west.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)))
	var signature_code: int = Autotile47.build_signature_code(
		is_north_mountain,
		is_north_east_mountain,
		is_east_mountain,
		is_south_east_mountain,
		is_south_mountain,
		is_south_west_mountain,
		is_west_mountain,
		is_north_west_mountain
	)
	var variant_index: int = Autotile47.pick_variant(tile_coord, world_seed)
	return {
		"ready": true,
		"terrain_atlas_index": Autotile47.build_atlas_index(signature_code, variant_index),
	}

func _get_loaded_tile_data_no_enqueue(tile_coord: Vector2i) -> Dictionary:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var override_data: Dictionary = _diff_store.get_tile_override(chunk_coord, local_coord)
	if not override_data.is_empty():
		return {
			"ready": true,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
			"terrain_id": int(override_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
			"walkable": bool(override_data.get("walkable", true)),
		}
	var packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
	if packet.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": int(terrain_ids[index]),
		"walkable": int(walkable_flags[index]) != 0,
	}

func _chunk_local_to_tile(chunk_coord: Vector2i, local_coord: Vector2i) -> Vector2i:
	return Vector2i(
		chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE + local_coord.x,
		chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE + local_coord.y
	)

func _ensure_chunk_view(chunk_coord: Vector2i) -> ChunkView:
	var existing: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if existing != null:
		return existing
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	add_child(chunk_view)
	_chunk_views[chunk_coord] = chunk_view
	return chunk_view

func _reset_runtime_state() -> void:
	_generation_epoch += 1
	_clear_requested_chunks()
	_clear_completed_packets()
	_requested_chunks.clear()
	_pending_publish_queue.clear()
	_active_publish_chunk = INVALID_CHUNK_COORD
	_player_chunk_coord = INVALID_CHUNK_COORD
	for chunk_view_variant: Variant in _chunk_views.values():
		var chunk_view: ChunkView = chunk_view_variant as ChunkView
		if chunk_view:
			chunk_view.queue_free()
	_chunk_views.clear()
	_chunk_packets.clear()
	roof_layers_per_chunk_max = 0
	_did_warn_roof_layer_explosion = false
	if _mountain_reveal_registry != null and is_instance_valid(_mountain_reveal_registry):
		_mountain_reveal_registry.reset_state()

func _clear_requested_chunks() -> void:
	_request_mutex.lock()
	_pending_requests.clear()
	_request_mutex.unlock()

func _clear_completed_packets() -> void:
	_result_mutex.lock()
	_completed_packets.clear()
	_result_mutex.unlock()

func _build_desired_chunk_coords(center_chunk: Vector2i) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for y: int in range(center_chunk.y - WorldRuntimeConstants.STREAM_RADIUS_CHUNKS, center_chunk.y + WorldRuntimeConstants.STREAM_RADIUS_CHUNKS + 1):
		for x: int in range(center_chunk.x - WorldRuntimeConstants.STREAM_RADIUS_CHUNKS, center_chunk.x + WorldRuntimeConstants.STREAM_RADIUS_CHUNKS + 1):
			coords.append(Vector2i(x, y))
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var dist_a: int = _distance_sq(center_chunk, a)
		var dist_b: int = _distance_sq(center_chunk, b)
		return dist_a < dist_b if dist_a != dist_b else (a.x < b.x if a.x != b.x else a.y < b.y)
	)
	return coords

func _is_chunk_desired(chunk_coord: Vector2i) -> bool:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		return false
	return maxi(
		absi(chunk_coord.x - _player_chunk_coord.x),
		absi(chunk_coord.y - _player_chunk_coord.y)
	) <= WorldRuntimeConstants.STREAM_RADIUS_CHUNKS

func _chunk_has_diff(chunk_coord: Vector2i) -> bool:
	return not _diff_store.get_chunk_override_local_coords(chunk_coord).is_empty()

func _recompute_entrance_after_chunk_publish(published_chunk_coord: Vector2i) -> void:
	# Re-run adjacent diff-owned neighborhoods so chunk-edge entrances resolve
	# correctly even when only one side of the seam owns the saved mutation.
	for chunk_offset: Vector2i in [
		Vector2i.ZERO,
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]:
		var source_chunk_coord: Vector2i = published_chunk_coord + chunk_offset
		if not _chunk_has_diff(source_chunk_coord):
			continue
		recompute_entrance_for_chunk_load(source_chunk_coord)

func _ensure_mountain_reveal_registry() -> void:
	if _mountain_reveal_registry != null and is_instance_valid(_mountain_reveal_registry):
		return
	_mountain_reveal_registry = MountainRevealRegistry.new()
	add_child(_mountain_reveal_registry)

func _track_roof_layer_metric(chunk_coord: Vector2i, packet: Dictionary) -> void:
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if mountain_ids.is_empty() or mountain_flags.is_empty():
		return
	var present_mountains: Dictionary = {}
	for index: int in range(mini(mountain_ids.size(), mountain_flags.size())):
		var mountain_id: int = int(mountain_ids[index])
		var flags: int = int(mountain_flags[index])
		if mountain_id <= 0 or (flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) == 0:
			continue
		present_mountains[mountain_id] = true
	var mountain_count: int = present_mountains.size()
	if mountain_count > roof_layers_per_chunk_max:
		roof_layers_per_chunk_max = mountain_count
	if mountain_count > 4 and not _did_warn_roof_layer_explosion:
		_did_warn_roof_layer_explosion = true
		push_warning("roof layer explosion: chunk %s has %d mountains" % [chunk_coord, mountain_count])

func _distance_sq(a: Vector2i, b: Vector2i) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	return dx * dx + dy * dy

func _is_diggable_surface_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _uses_mountain_surface_presentation(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _build_m1_dev_default_settings_packed() -> PackedFloat32Array:
	var settings_packed: PackedFloat32Array = PackedFloat32Array()
	settings_packed.resize(WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FIELD_COUNT)
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_DENSITY] = 0.30
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SCALE] = 512.0
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_CONTINUITY] = 0.65
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RUGGEDNESS] = 0.55
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE] = 128.0
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS] = 96.0
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FOOT_BAND] = 0.08
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN] = 1.0
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE] = 0.0
	return settings_packed

func _resolve_settings_packed_for_world_version(version: int) -> PackedFloat32Array:
	if version < 2:
		return PackedFloat32Array()
	return _build_m1_dev_default_settings_packed()

func _start_worker_thread() -> void:
	if _worker_thread.is_started():
		return
	_worker_should_exit = false
	var start_error: Error = _worker_thread.start(_worker_loop)
	assert(start_error == OK, "Failed to start world runtime worker thread")

func _stop_worker_thread() -> void:
	if not _worker_thread.is_started():
		return
	_worker_should_exit = true
	_request_semaphore.post()
	_worker_thread.wait_to_finish()

func _worker_loop() -> void:
	var worker_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(worker_world_core != null, "WorldCore required inside worker thread")
	while true:
		_request_semaphore.wait()
		if _worker_should_exit:
			return
		var request: Dictionary = {}
		_request_mutex.lock()
		if not _pending_requests.is_empty():
			request = _pending_requests.pop_front() as Dictionary
		_request_mutex.unlock()
		if request.is_empty():
			continue
		var packet: Dictionary = worker_world_core.call(
			"generate_chunk_packet",
			int(request.get("seed", world_seed)),
			request.get("coord", Vector2i.ZERO) as Vector2i,
			int(request.get("world_version", world_version)),
			request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array
		) as Dictionary
		packet["epoch"] = int(request.get("epoch", -1))
		_result_mutex.lock()
		_completed_packets.append(packet)
		_result_mutex.unlock()
