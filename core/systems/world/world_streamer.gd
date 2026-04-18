class_name WorldStreamer
extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldDiffStore = preload("res://core/systems/world/world_diff_store.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

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

var _worker_thread: Thread = Thread.new()
var _request_mutex: Mutex = Mutex.new()
var _result_mutex: Mutex = Mutex.new()
var _request_semaphore: Semaphore = Semaphore.new()
var _pending_requests: Array[Dictionary] = []
var _completed_packets: Array[Dictionary] = []
var _worker_should_exit: bool = false

func _ready() -> void:
	add_to_group("chunk_manager")
	name = "WorldStreamer"
	_world_core = ClassDB.instantiate("WorldCore")
	assert(_world_core != null, "WorldCore required - build GDExtension first")
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
	_diff_store.clear()
	_reset_runtime_state()
	EventBus.world_initialized.emit(world_seed)

func load_world_state(data: Dictionary) -> void:
	world_seed = int(data.get("world_seed", WorldRuntimeConstants.DEFAULT_WORLD_SEED))
	world_version = int(data.get("world_version", WorldRuntimeConstants.WORLD_VERSION))
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

func is_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	return bool(tile_data.get("walkable", false))

func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	return int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)) == WorldRuntimeConstants.TERRAIN_PLAINS_ROCK

func try_harvest_at_world(world_pos: Vector2) -> Dictionary:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return {
			"success": false,
			"message_key": "SYSTEM_WORLD_CHUNK_NOT_READY",
		}
	if int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)) != WorldRuntimeConstants.TERRAIN_PLAINS_ROCK:
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
	return {
		"success": true,
		"item_id": "base:scrap",
		"amount": 1,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
	}

func debug_place_rock_at_world(world_pos: Vector2) -> Dictionary:
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	_diff_store.set_tile_override(
		chunk_coord,
		local_coord,
		WorldRuntimeConstants.TERRAIN_PLAINS_ROCK,
		false
	)
	_apply_loaded_override(
		chunk_coord,
		local_coord,
		WorldRuntimeConstants.TERRAIN_PLAINS_ROCK,
		false
	)
	return {
		"success": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": WorldRuntimeConstants.TERRAIN_PLAINS_ROCK,
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
		var chunk_view: ChunkView = _ensure_chunk_view(_active_publish_chunk)
		chunk_view.begin_apply(packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array)

	var active_view: ChunkView = _chunk_views.get(_active_publish_chunk) as ChunkView
	if active_view == null:
		_active_publish_chunk = INVALID_CHUNK_COORD
		return
	var has_more: bool = active_view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE)
	if not has_more:
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

func _enqueue_chunk_if_needed(chunk_coord: Vector2i) -> void:
	if _requested_chunks.has(chunk_coord) or _chunk_packets.has(chunk_coord):
		return
	_requested_chunks[chunk_coord] = true
	_request_mutex.lock()
	_pending_requests.append({
		"coord": chunk_coord,
		"seed": world_seed,
		"world_version": world_version,
		"epoch": _generation_epoch,
	})
	_request_mutex.unlock()
	_request_semaphore.post()

func _apply_loaded_override(chunk_coord: Vector2i, local_coord: Vector2i, terrain_id: int, walkable: bool) -> void:
	if not _chunk_packets.has(chunk_coord):
		return
	var packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
	var terrain_ids: PackedInt32Array = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
	var walkable_flags: PackedByteArray = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return
	terrain_ids[index] = terrain_id
	walkable_flags[index] = 1 if walkable else 0
	packet["terrain_ids"] = terrain_ids
	packet["walkable_flags"] = walkable_flags
	_chunk_packets[chunk_coord] = packet
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if chunk_view:
		chunk_view.apply_runtime_tile(local_coord, terrain_id)

func _refresh_loaded_packets_from_diffs() -> void:
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _chunk_packets.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	for chunk_coord: Vector2i in chunk_coords:
		var base_packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
		_chunk_packets[chunk_coord] = _diff_store.apply_to_packet(base_packet)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view:
			chunk_view.begin_apply((_chunk_packets[chunk_coord] as Dictionary).get("terrain_ids", PackedInt32Array()) as PackedInt32Array)
			if not _pending_publish_queue.has(chunk_coord):
				_pending_publish_queue.append(chunk_coord)

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

func _distance_sq(a: Vector2i, b: Vector2i) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	return dx * dx + dy * dy

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
			int(request.get("world_version", world_version))
		) as Dictionary
		packet["epoch"] = int(request.get("epoch", -1))
		_result_mutex.lock()
		_completed_packets.append(packet)
		_result_mutex.unlock()
