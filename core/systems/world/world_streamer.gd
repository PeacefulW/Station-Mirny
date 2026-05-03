class_name WorldStreamer
extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const HarvestQuery = preload("res://core/systems/world/harvest_query.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const MountainCavityCache = preload("res://core/systems/world/mountain_cavity_cache.gd")
const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldDiffStore = preload("res://core/systems/world/world_diff_store.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldSpawnResolver = preload("res://core/systems/world/world_spawn_resolver.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const INVALID_CHUNK_COORD: Vector2i = Vector2i(2147483647, 2147483647)
const MAX_SPAWN_RESULTS_PER_TICK: int = 1

var world_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var world_version: int = WorldRuntimeConstants.WORLD_VERSION

var _diff_store: WorldDiffStore = WorldDiffStore.new()
var _chunk_packets: Dictionary = {}
var _chunk_views: Dictionary = {}
var _requested_chunks: Dictionary = {}
var _pending_publish_queue: Array[Vector2i] = []
var _active_publish_chunk: Vector2i = INVALID_CHUNK_COORD
var _player_chunk_coord: Vector2i = INVALID_CHUNK_COORD
var _stream_job_id: StringName = &""
var _generation_epoch: int = 0
var _worldgen_settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
var _world_bounds_settings: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
var _foundation_settings: FoundationGenSettings = FoundationGenSettings.hard_coded_defaults()
var _lake_settings: LakeGenSettings = LakeGenSettings.hard_coded_defaults()
var _worldgen_settings_packed: PackedFloat32Array = PackedFloat32Array()
var _pending_new_world_settings: MountainGenSettings = null
var _pending_new_world_bounds: WorldBoundsSettings = null
var _pending_new_foundation_settings: FoundationGenSettings = null
var _pending_new_lake_settings: LakeGenSettings = null
var _packet_backend: WorldChunkPacketBackend = WorldChunkPacketBackend.new()
var _awaiting_new_game_spawn_result: bool = false
var _new_game_spawn_failed: bool = false
var roof_layers_per_chunk_max: int = 0

var _mountain_cavity_cache: MountainCavityCache = MountainCavityCache.new()
var _active_cover_mountain_id: int = 0
var _active_cover_component_id: int = 0
var _did_warn_roof_layer_explosion: bool = false

func _ready() -> void:
	add_to_group("chunk_manager")
	name = "WorldStreamer"
	_apply_worldgen_settings(
		MountainGenSettings.hard_coded_defaults(),
		WorldBoundsSettings.hard_coded_defaults(),
		FoundationGenSettings.hard_coded_defaults(),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	)
	WorldTileSetFactory.bootstrap()
	_packet_backend.start()
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
	_packet_backend.stop()

func initialize_new_world(
	seed_value: int,
	settings: MountainGenSettings,
	world_bounds: WorldBoundsSettings = null,
	foundation_settings: FoundationGenSettings = null,
	lake_settings: LakeGenSettings = null
) -> void:
	_pending_new_world_settings = _clone_worldgen_settings(settings)
	_pending_new_world_bounds = _clone_world_bounds(world_bounds)
	_pending_new_foundation_settings = _clone_foundation_settings(
		foundation_settings,
		_pending_new_world_bounds
	)
	_pending_new_lake_settings = _clone_lake_settings(lake_settings)
	reset_for_new_game(seed_value, WorldRuntimeConstants.WORLD_VERSION)

func reset_for_new_game(
	seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED,
	version: int = WorldRuntimeConstants.WORLD_VERSION
) -> void:
	world_seed = seed
	world_version = version
	if _pending_new_world_settings != null:
		_apply_worldgen_settings(
			_pending_new_world_settings,
			_pending_new_world_bounds,
			_pending_new_foundation_settings,
			_pending_new_lake_settings
		)
	else:
		var default_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
		_apply_worldgen_settings(
			MountainGenSettings.hard_coded_defaults(),
			default_bounds,
			FoundationGenSettings.for_bounds(default_bounds),
			LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
		)
	_pending_new_world_settings = null
	_pending_new_world_bounds = null
	_pending_new_foundation_settings = null
	_pending_new_lake_settings = null
	_diff_store.clear()
	_reset_runtime_state()
	_queue_new_game_spawn_resolution()
	EventBus.world_initialized.emit(world_seed)

func load_world_state(data: Dictionary) -> bool:
	var loaded_world_version: int = int(data.get("world_version", -1))
	if not WorldRuntimeConstants.is_current_world_version(loaded_world_version):
		_reject_world_save(
			"world.json world_version %d is incompatible with current world_version %d. Pre-alpha world saves are not migrated." % [
				loaded_world_version,
				WorldRuntimeConstants.WORLD_VERSION,
			]
		)
		return false
	if not _validate_current_world_save_shape(data):
		return false
	world_seed = int(data.get("world_seed", WorldRuntimeConstants.DEFAULT_WORLD_SEED))
	world_version = loaded_world_version
	_pending_new_world_settings = null
	_pending_new_world_bounds = null
	_pending_new_foundation_settings = null
	_pending_new_lake_settings = null
	var loaded_bounds: WorldBoundsSettings = _load_world_bounds_from_save(data)
	_apply_worldgen_settings(
		_load_worldgen_settings_from_save(data),
		loaded_bounds,
		_load_foundation_settings_from_save(data, loaded_bounds),
		_load_lake_settings_from_save(data)
	)
	_diff_store.clear()
	_reset_runtime_state()
	_awaiting_new_game_spawn_result = false
	_new_game_spawn_failed = false
	EventBus.world_initialized.emit(world_seed)
	return true

func save_world_state() -> Dictionary:
	var current_settings: MountainGenSettings = _worldgen_settings
	var worldgen_settings: Dictionary = {
		"mountains": current_settings.to_save_dict(),
	}
	if WorldRuntimeConstants.uses_world_foundation(world_version):
		worldgen_settings["world_bounds"] = _world_bounds_settings.to_save_dict()
		worldgen_settings["foundation"] = _foundation_settings.to_save_dict()
		worldgen_settings["lakes"] = _lake_settings.to_save_dict()
	return {
		"world_rebuild_frozen": false,
		"world_scene_present": true,
		"world_seed": world_seed,
		"world_version": world_version,
		"worldgen_settings": worldgen_settings,
		"worldgen_signature": _compute_worldgen_signature(worldgen_settings),
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

func get_mountain_cover_sample(world_tile: Vector2i) -> Dictionary:
	return _mountain_cavity_cache.get_sample(
		world_tile,
		Callable(self, "_sample_mountain_cover_tile")
	)

func get_mountain_cover_debug_snapshot(world_tile: Vector2i) -> Dictionary:
	var debug_snapshot: Dictionary = _mountain_cavity_cache.get_debug_snapshot(
		world_tile,
		_active_cover_component_id,
		Callable(self, "_sample_mountain_cover_tile")
	)
	debug_snapshot["active_mountain_id"] = _active_cover_mountain_id
	debug_snapshot["active_component_id"] = _active_cover_component_id
	debug_snapshot["roof_layers_per_chunk_max"] = roof_layers_per_chunk_max
	return debug_snapshot

func get_mountain_cover_render_debug_snapshot(world_tile: Vector2i) -> Dictionary:
	var probe_tile: Vector2i = _canonicalize_tile_coord(_resolve_cover_debug_probe_tile(world_tile))
	var probe_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(probe_tile)
	var probe_local: Vector2i = WorldRuntimeConstants.tile_to_local(probe_tile)
	var probe_sample: Dictionary = get_mountain_cover_sample(probe_tile)
	var expected_open_bit: int = -1
	var visible_mask: PackedByteArray = _mountain_cavity_cache.build_chunk_visibility_mask(
		probe_chunk,
		_active_cover_component_id
	)
	var probe_index: int = WorldRuntimeConstants.local_to_index(probe_local)
	if probe_index >= 0 and probe_index < visible_mask.size():
		expected_open_bit = int(visible_mask[probe_index])
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
		expected_open_bit
	)
	for key_variant: Variant in render_debug.keys():
		debug_snapshot[key_variant] = render_debug[key_variant]
	return debug_snapshot

func set_active_mountain_component(mountain_id: int, component_id: int) -> void:
	var resolved_component_id: int = component_id if _mountain_cavity_cache.has_component(component_id) else 0
	var resolved_mountain_id: int = mountain_id if resolved_component_id > 0 else 0
	if resolved_mountain_id == _active_cover_mountain_id \
			and resolved_component_id == _active_cover_component_id:
		return
	_active_cover_mountain_id = resolved_mountain_id
	_active_cover_component_id = resolved_component_id
	_refresh_cover_visibility_for_loaded_chunks()

func is_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	return bool(tile_data.get("walkable", false))

func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	if not _is_diggable_surface_terrain(terrain_id):
		return false
	return HarvestQuery.is_tile_orthogonally_exposed(
		_chunk_local_to_tile(
			tile_data.get("chunk_coord", Vector2i.ZERO) as Vector2i,
			tile_data.get("local_coord", Vector2i.ZERO) as Vector2i
		),
		Callable(self, "_sample_harvest_gate_tile")
	)

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
	var world_tile: Vector2i = _chunk_local_to_tile(
		tile_data.get("chunk_coord", Vector2i.ZERO) as Vector2i,
		tile_data.get("local_coord", Vector2i.ZERO) as Vector2i
	)
	if not HarvestQuery.is_tile_orthogonally_exposed(world_tile, Callable(self, "_sample_harvest_gate_tile")):
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
	_handle_cover_tile_dug(_chunk_local_to_tile(chunk_coord, local_coord))
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
	_drain_new_game_spawn_result()
	if _awaiting_new_game_spawn_result or _new_game_spawn_failed:
		return false
	_wrap_local_player_position_if_needed()
	_update_player_chunk_coord()
	_enqueue_desired_chunks()
	_drain_completed_packets(1)
	_publish_next_batch()
	_evict_outside_ring(1)
	return _has_pending_streaming_work()

func _update_player_chunk_coord() -> void:
	var player_pos: Vector2 = PlayerAuthority.get_local_player_position()
	var tile_coord: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(player_pos))
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
		_packet_backend.queue_packet_request(
			desired_coord,
			world_seed,
			world_version,
			_worldgen_settings_packed,
			_generation_epoch
		)

func _drain_completed_packets(max_count: int) -> void:
	var drained: Array[Dictionary] = _packet_backend.drain_completed_packets(max_count)
	for packet: Dictionary in drained:
		if int(packet.get("epoch", -1)) != _generation_epoch:
			continue
		var chunk_coord: Vector2i = _canonicalize_chunk_coord(packet.get("chunk_coord", Vector2i.ZERO) as Vector2i)
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
		_handle_cover_chunk_published(_active_publish_chunk)
		_handle_water_chunk_published(_active_publish_chunk)
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
		_handle_cover_chunk_unloaded(chunk_coord)
		EventBus.chunk_unloaded.emit(chunk_coord)
		evicted += 1

func _has_pending_streaming_work() -> bool:
	if _awaiting_new_game_spawn_result:
		return true
	if not _pending_publish_queue.is_empty():
		return true
	if _active_publish_chunk != INVALID_CHUNK_COORD:
		return true
	if _packet_backend.has_pending_requests():
		return true
	if _packet_backend.has_completed_packets():
		return true
	for chunk_coord_variant: Variant in _chunk_views.keys():
		if not _is_chunk_desired(chunk_coord_variant as Vector2i):
			return true
	return false

func _get_tile_data(world_pos: Vector2) -> Dictionary:
	var tile_coord: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(world_pos))
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_tile_y_in_bounds(tile_coord.y):
		return {
			"ready": false,
			"chunk_coord": WorldRuntimeConstants.tile_to_chunk(tile_coord),
			"local_coord": WorldRuntimeConstants.tile_to_local(tile_coord),
		}
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

func _sample_harvest_gate_tile(world_tile: Vector2i) -> Dictionary:
	return _get_tile_data(WorldRuntimeConstants.tile_to_world_center(world_tile))

func _sample_mountain_cover_tile(world_tile: Vector2i) -> Dictionary:
	var canonical_tile: Vector2i = _canonicalize_tile_coord(world_tile)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var packet: Dictionary = get_chunk_packet(chunk_coord)
	if packet.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": WorldRuntimeConstants.tile_to_local(canonical_tile),
		}
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
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

func _resolve_cover_debug_probe_tile(world_tile: Vector2i) -> Vector2i:
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
		var candidate_sample: Dictionary = _sample_mountain_cover_tile(candidate_tile)
		if int(candidate_sample.get("mountain_id", 0)) > 0:
			return candidate_tile
	return world_tile

func _enqueue_chunk_if_needed(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
		return
	if _requested_chunks.has(chunk_coord) or _chunk_packets.has(chunk_coord):
		return
	_requested_chunks[chunk_coord] = true
	_packet_backend.queue_packet_request(
		chunk_coord,
		world_seed,
		world_version,
		_worldgen_settings_packed,
		_generation_epoch
	)

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
	_mountain_cavity_cache.clear()
	_active_cover_mountain_id = 0
	_active_cover_component_id = 0
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
	# Ground uses solid atlas variants only in the current mountain-only worldgen.
	return Autotile47.build_solid_atlas_index(tile_coord, world_seed)

func _try_resolve_loaded_mountain_atlas_index(tile_coord: Vector2i) -> Dictionary:
	var north: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(0, -1))
	var east: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(1, 0))
	var south: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(0, 1))
	var west: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(-1, 0))
	if not bool(north.get("ready", false)) \
			or not bool(east.get("ready", false)) \
			or not bool(south.get("ready", false)) \
			or not bool(west.get("ready", false)):
		return {"ready": false}
	var is_north_mountain: bool = _is_loaded_mountain_geometry_surface(north)
	var is_east_mountain: bool = _is_loaded_mountain_geometry_surface(east)
	var is_south_mountain: bool = _is_loaded_mountain_geometry_surface(south)
	var is_west_mountain: bool = _is_loaded_mountain_geometry_surface(west)
	var is_north_east_mountain: bool = false
	var is_south_east_mountain: bool = false
	var is_south_west_mountain: bool = false
	var is_north_west_mountain: bool = false
	if is_north_mountain and is_east_mountain:
		var north_east: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(1, -1))
		if not bool(north_east.get("ready", false)):
			return {"ready": false}
		is_north_east_mountain = _is_loaded_mountain_geometry_surface(north_east)
	if is_south_mountain and is_east_mountain:
		var south_east: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(1, 1))
		if not bool(south_east.get("ready", false)):
			return {"ready": false}
		is_south_east_mountain = _is_loaded_mountain_geometry_surface(south_east)
	if is_south_mountain and is_west_mountain:
		var south_west: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(-1, 1))
		if not bool(south_west.get("ready", false)):
			return {"ready": false}
		is_south_west_mountain = _is_loaded_mountain_geometry_surface(south_west)
	if is_north_mountain and is_west_mountain:
		var north_west: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(-1, -1))
		if not bool(north_west.get("ready", false)):
			return {"ready": false}
		is_north_west_mountain = _is_loaded_mountain_geometry_surface(north_west)
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

func _get_loaded_mountain_geometry_no_enqueue(tile_coord: Vector2i) -> Dictionary:
	tile_coord = _canonicalize_tile_coord(tile_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_tile_y_in_bounds(tile_coord.y):
		return {"ready": false}
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
	if packet.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	if index < 0 or index >= terrain_ids.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	var has_mountain_geometry: bool = index < mountain_ids.size() and index < mountain_flags.size()
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": int(terrain_ids[index]),
		"mountain_id": int(mountain_ids[index]) if has_mountain_geometry else 0,
		"mountain_flags": int(mountain_flags[index]) if has_mountain_geometry else 0,
	}

func _is_loaded_mountain_geometry_surface(sample: Dictionary) -> bool:
	return _uses_mountain_surface_presentation(
		int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	)

func _get_loaded_tile_data_no_enqueue(tile_coord: Vector2i) -> Dictionary:
	tile_coord = _canonicalize_tile_coord(tile_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_tile_y_in_bounds(tile_coord.y):
		return {
			"ready": false,
			"chunk_coord": WorldRuntimeConstants.tile_to_chunk(tile_coord),
			"local_coord": WorldRuntimeConstants.tile_to_local(tile_coord),
		}
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
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	return Vector2i(
		canonical_chunk.x * WorldRuntimeConstants.CHUNK_SIZE + local_coord.x,
		canonical_chunk.y * WorldRuntimeConstants.CHUNK_SIZE + local_coord.y
	)

func _ensure_chunk_view(chunk_coord: Vector2i) -> ChunkView:
	var existing: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if existing != null:
		return existing
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	chunk_view.set_water_neighbour_resolver(Callable(self, "_has_water_at_world_tile_for_presentation"))
	add_child(chunk_view)
	_chunk_views[chunk_coord] = chunk_view
	return chunk_view

func _reset_runtime_state() -> void:
	_generation_epoch += 1
	_packet_backend.clear_queued_work()
	_awaiting_new_game_spawn_result = false
	_new_game_spawn_failed = false
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
	_mountain_cavity_cache.clear()
	_active_cover_mountain_id = 0
	_active_cover_component_id = 0
	_did_warn_roof_layer_explosion = false

func _queue_new_game_spawn_resolution() -> void:
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		var legacy_spawn_tile: Vector2i = WorldSpawnResolver.resolve_preview_spawn_tile(
			world_seed,
			world_version,
			_worldgen_settings,
			_world_bounds_settings,
			_foundation_settings
		)
		_position_local_player_at_spawn_tile(legacy_spawn_tile)
		return
	_awaiting_new_game_spawn_result = true
	_new_game_spawn_failed = false
	_packet_backend.queue_spawn_request(
		world_seed,
		world_version,
		_worldgen_settings_packed,
		_generation_epoch
	)

func _drain_new_game_spawn_result() -> void:
	if not _awaiting_new_game_spawn_result:
		return
	var ready_results: Array[Dictionary] = _packet_backend.drain_completed_spawn_results(MAX_SPAWN_RESULTS_PER_TICK)
	for spawn_result: Dictionary in ready_results:
		if int(spawn_result.get("epoch", -1)) != _generation_epoch:
			continue
		if not bool(spawn_result.get("success", false)):
			var message: String = "WorldStreamer native spawn resolution failed: %s" \
				% str(spawn_result.get("message", "unknown error"))
			_fail_new_game_spawn_resolution(message)
			return
		var spawn_tile_variant: Variant = spawn_result.get("spawn_tile", null)
		if spawn_tile_variant is not Vector2i:
			_fail_new_game_spawn_resolution(
				"WorldStreamer native spawn resolution returned no Vector2i spawn_tile."
			)
			return
		_awaiting_new_game_spawn_result = false
		_position_local_player_at_spawn_tile(spawn_tile_variant as Vector2i)
		return

func _fail_new_game_spawn_resolution(message: String) -> void:
	push_error(message)
	assert(false, message)
	_awaiting_new_game_spawn_result = false
	_new_game_spawn_failed = true

func _position_local_player_at_spawn_tile(spawn_tile: Vector2i) -> void:
	var player: Node2D = PlayerAuthority.get_local_player()
	if player == null:
		_fail_new_game_spawn_resolution(
			"WorldStreamer could not apply new-game spawn because local player is missing."
		)
		return
	var canonical_spawn_tile: Vector2i = _canonicalize_tile_coord(spawn_tile)
	player.global_position = WorldRuntimeConstants.tile_to_world_center(canonical_spawn_tile)
	_player_chunk_coord = WorldRuntimeConstants.tile_to_chunk(canonical_spawn_tile)
	_new_game_spawn_failed = false

func _build_desired_chunk_coords(center_chunk: Vector2i) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var seen: Dictionary = {}
	for y: int in range(center_chunk.y - WorldRuntimeConstants.STREAM_RADIUS_CHUNKS, center_chunk.y + WorldRuntimeConstants.STREAM_RADIUS_CHUNKS + 1):
		for x: int in range(center_chunk.x - WorldRuntimeConstants.STREAM_RADIUS_CHUNKS, center_chunk.x + WorldRuntimeConstants.STREAM_RADIUS_CHUNKS + 1):
			var coord: Vector2i = _canonicalize_chunk_coord(Vector2i(x, y))
			if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(coord.y):
				continue
			if seen.has(coord):
				continue
			seen[coord] = true
			coords.append(coord)
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var dist_a: int = _chunk_distance_sq(center_chunk, a)
		var dist_b: int = _chunk_distance_sq(center_chunk, b)
		return dist_a < dist_b if dist_a != dist_b else (a.x < b.x if a.x != b.x else a.y < b.y)
	)
	return coords

func _is_chunk_desired(chunk_coord: Vector2i) -> bool:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		return false
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
		return false
	return maxi(
		_wrapped_chunk_delta_abs(chunk_coord.x, _player_chunk_coord.x),
		absi(chunk_coord.y - _player_chunk_coord.y)
	) <= WorldRuntimeConstants.STREAM_RADIUS_CHUNKS

func _chunk_has_diff(chunk_coord: Vector2i) -> bool:
	return not _diff_store.get_chunk_override_local_coords(chunk_coord).is_empty()

func _handle_cover_chunk_published(published_chunk_coord: Vector2i) -> void:
	var cover_result: Dictionary = _mountain_cavity_cache.on_chunk_loaded(
		published_chunk_coord,
		_collect_cover_candidate_tiles_for_chunk(published_chunk_coord),
		Callable(self, "_sample_mountain_cover_tile")
	)
	var active_change: Dictionary = _repair_active_cover_component_from_player_position()
	var affected_chunks: Dictionary = {}
	var published_chunks: Array[Vector2i] = _variant_to_vector2i_array(cover_result.get("affected_chunks", []))
	for chunk_coord: Vector2i in published_chunks:
		affected_chunks[chunk_coord] = true
	if bool(active_change.get("state_changed", false)):
		_refresh_cover_visibility_for_loaded_chunks()
		return
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))

func _handle_water_chunk_published(published_chunk_coord: Vector2i) -> void:
	var published_view: ChunkView = _chunk_views.get(published_chunk_coord) as ChunkView
	if published_view == null:
		return
	for neighbor_delta: Vector2i in [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]:
		var neighbor_coord: Vector2i = _canonicalize_chunk_coord(published_chunk_coord + neighbor_delta)
		if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(neighbor_coord.y):
			continue
		if neighbor_coord == published_chunk_coord:
			continue
		var neighbor_view: ChunkView = _chunk_views.get(neighbor_coord) as ChunkView
		if neighbor_view == null:
			continue
		published_view.refresh_water_edge_towards(neighbor_delta)
		neighbor_view.refresh_water_edge_towards(-neighbor_delta)

func _has_water_at_world_tile_for_presentation(tile_coord: Vector2i) -> bool:
	var canonical_tile: Vector2i = _canonicalize_tile_coord(tile_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_tile_y_in_bounds(canonical_tile.y):
		return false
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if chunk_view == null:
		return false
	return chunk_view.has_water_at_local(WorldRuntimeConstants.tile_to_local(canonical_tile))

func _handle_cover_chunk_unloaded(chunk_coord: Vector2i) -> void:
	var cover_result: Dictionary = _mountain_cavity_cache.on_chunk_unloaded(
		chunk_coord,
		_collect_diff_world_tiles_for_chunk(chunk_coord),
		Callable(self, "_sample_mountain_cover_tile")
	)
	var active_change: Dictionary = _repair_active_cover_component_from_player_position()
	if bool(active_change.get("state_changed", false)):
		_refresh_cover_visibility_for_loaded_chunks()
		return
	var unloaded_chunks: Array[Vector2i] = _variant_to_vector2i_array(cover_result.get("affected_chunks", []))
	_refresh_cover_visibility_for_loaded_chunks(unloaded_chunks)

func _handle_cover_tile_dug(world_tile: Vector2i) -> void:
	var previous_active_component_id: int = _active_cover_component_id
	var cover_result: Dictionary = _mountain_cavity_cache.on_tile_dug(
		world_tile,
		Callable(self, "_sample_mountain_cover_tile")
	)
	var active_change: Dictionary = _repair_active_cover_component_from_player_position()
	if bool(active_change.get("state_changed", false)):
		_refresh_cover_visibility_for_loaded_chunks()
		return
	var affected_chunks: Dictionary = {}
	var dug_chunks: Array[Vector2i] = _variant_to_vector2i_array(cover_result.get("affected_chunks", []))
	for chunk_coord: Vector2i in dug_chunks:
		affected_chunks[chunk_coord] = true
	for component_id: int in [previous_active_component_id, _active_cover_component_id]:
		if component_id <= 0:
			continue
		for component_chunk_coord: Vector2i in _mountain_cavity_cache.get_component_chunks(component_id):
			affected_chunks[component_chunk_coord] = true
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))

func _collect_cover_candidate_tiles_for_chunk(published_chunk_coord: Vector2i) -> Array[Vector2i]:
	var candidate_tiles: Dictionary = {}
	for sample_chunk_y: int in range(published_chunk_coord.y - 1, published_chunk_coord.y + 2):
		for sample_chunk_x: int in range(published_chunk_coord.x - 1, published_chunk_coord.x + 2):
			var sample_chunk_coord := Vector2i(sample_chunk_x, sample_chunk_y)
			for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(sample_chunk_coord):
				candidate_tiles[_chunk_local_to_tile(sample_chunk_coord, local_coord)] = true
	return _dictionary_vector2i_keys(candidate_tiles)

func _collect_diff_world_tiles_for_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
	var world_tiles: Array[Vector2i] = []
	for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(chunk_coord):
		world_tiles.append(_chunk_local_to_tile(chunk_coord, local_coord))
	return world_tiles

func _repair_active_cover_component_from_player_position() -> Dictionary:
	var previous_mountain_id: int = _active_cover_mountain_id
	var previous_component_id: int = _active_cover_component_id
	if PlayerAuthority.get_local_player() == null:
		_active_cover_mountain_id = 0
		_active_cover_component_id = 0
		return {
			"state_changed": previous_mountain_id != 0 or previous_component_id != 0,
			"previous_mountain_id": previous_mountain_id,
			"previous_component_id": previous_component_id,
			"mountain_id": 0,
			"component_id": 0,
		}
	var player_tile: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(PlayerAuthority.get_local_player_position()))
	var current_sample: Dictionary = get_mountain_cover_sample(player_tile)
	var next_component_id: int = int(current_sample.get("component_id", 0))
	if not _mountain_cavity_cache.has_component(next_component_id):
		next_component_id = 0
	var next_mountain_id: int = int(current_sample.get("mountain_id", 0)) if next_component_id > 0 else 0
	_active_cover_mountain_id = next_mountain_id
	_active_cover_component_id = next_component_id
	return {
		"state_changed": previous_mountain_id != next_mountain_id
			or previous_component_id != next_component_id,
		"previous_mountain_id": previous_mountain_id,
		"previous_component_id": previous_component_id,
		"mountain_id": next_mountain_id,
		"component_id": next_component_id,
	}

func _refresh_cover_visibility_for_loaded_chunks(target_chunks: Array[Vector2i] = []) -> void:
	var refresh_chunks: Array[Vector2i] = target_chunks
	if refresh_chunks.is_empty():
		refresh_chunks = _dictionary_vector2i_keys(_chunk_views)
	var seen_chunks: Dictionary = {}
	for chunk_coord: Vector2i in refresh_chunks:
		if seen_chunks.has(chunk_coord):
			continue
		seen_chunks[chunk_coord] = true
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view == null:
			continue
		chunk_view.apply_cover_visibility(
			_mountain_cavity_cache.build_chunk_visibility_mask(chunk_coord, _active_cover_component_id)
		)

func _dictionary_vector2i_keys(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key_variant: Variant in source.keys():
		result.append(key_variant as Vector2i)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return result

func _variant_to_vector2i_array(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if value is Array:
		for entry: Variant in value:
			result.append(entry as Vector2i)
	return result

func _track_roof_layer_metric(chunk_coord: Vector2i, packet: Dictionary) -> void:
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if mountain_ids.is_empty() or mountain_flags.is_empty():
		return
	var present_mountains: Dictionary = {}
	for index: int in range(mini(mountain_ids.size(), mountain_flags.size())):
		var mountain_id: int = int(mountain_ids[index])
		var flags: int = int(mountain_flags[index])
		if mountain_id <= 0 or (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
			continue
		present_mountains[mountain_id] = true
	var mountain_count: int = present_mountains.size()
	if mountain_count > roof_layers_per_chunk_max:
		roof_layers_per_chunk_max = mountain_count
	if mountain_count > 4 and not _did_warn_roof_layer_explosion:
		_did_warn_roof_layer_explosion = true
		push_warning("roof layer explosion: chunk %s has %d mountains" % [chunk_coord, mountain_count])

func _chunk_distance_sq(a: Vector2i, b: Vector2i) -> int:
	var dx: int = _wrapped_chunk_delta_abs(a.x, b.x)
	var dy: int = a.y - b.y
	return dx * dx + dy * dy

func _is_diggable_surface_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _uses_mountain_surface_presentation(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _wrap_local_player_position_if_needed() -> void:
	if not _uses_finite_world_bounds():
		return
	var player: Node2D = PlayerAuthority.get_local_player()
	if player == null:
		return
	var width_px: float = float(_world_bounds_settings.width_tiles * WorldRuntimeConstants.TILE_SIZE_PX)
	if width_px <= 0.0:
		return
	var wrapped_x: float = fposmod(player.global_position.x, width_px)
	if is_equal_approx(wrapped_x, player.global_position.x):
		return
	player.global_position = Vector2(wrapped_x, player.global_position.y)

func _uses_finite_world_bounds() -> bool:
	return WorldRuntimeConstants.uses_world_foundation(world_version)

func _canonicalize_tile_coord(tile_coord: Vector2i) -> Vector2i:
	if not _uses_finite_world_bounds():
		return tile_coord
	return _world_bounds_settings.canonicalize_tile(tile_coord)

func _canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	if not _uses_finite_world_bounds():
		return chunk_coord
	return _world_bounds_settings.canonicalize_chunk(chunk_coord)

func _wrapped_chunk_delta_abs(a: int, b: int) -> int:
	if not _uses_finite_world_bounds():
		return absi(a - b)
	var width_chunks: int = _world_bounds_settings.get_width_chunks()
	var direct_delta: int = absi(posmod(a, width_chunks) - posmod(b, width_chunks))
	return mini(direct_delta, width_chunks - direct_delta)

func _apply_worldgen_settings(
	settings: MountainGenSettings,
	world_bounds: WorldBoundsSettings,
	foundation_settings: FoundationGenSettings,
	lake_settings: LakeGenSettings = null
) -> void:
	_worldgen_settings = _clone_worldgen_settings(settings)
	_world_bounds_settings = _clone_world_bounds(world_bounds)
	_foundation_settings = _clone_foundation_settings(foundation_settings, _world_bounds_settings)
	_lake_settings = _clone_lake_settings(lake_settings)
	_worldgen_settings_packed = _build_worldgen_settings_packed()

func _clone_worldgen_settings(settings: MountainGenSettings) -> MountainGenSettings:
	if settings == null:
		return MountainGenSettings.hard_coded_defaults()
	return MountainGenSettings.from_save_dict(settings.to_save_dict())

func _clone_world_bounds(settings: WorldBoundsSettings) -> WorldBoundsSettings:
	if settings == null:
		return WorldBoundsSettings.hard_coded_defaults()
	return WorldBoundsSettings.from_save_dict(settings.to_save_dict())

func _clone_foundation_settings(
	settings: FoundationGenSettings,
	world_bounds: WorldBoundsSettings
) -> FoundationGenSettings:
	if settings == null:
		return FoundationGenSettings.for_bounds(world_bounds)
	return FoundationGenSettings.from_save_dict(settings.to_save_dict(), world_bounds)

func _clone_lake_settings(settings: LakeGenSettings) -> LakeGenSettings:
	if settings == null:
		return LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	return LakeGenSettings.from_save_dict(settings.to_save_dict())

func _build_worldgen_settings_packed() -> PackedFloat32Array:
	var packed: PackedFloat32Array = _worldgen_settings.flatten_to_packed()
	if WorldRuntimeConstants.uses_world_foundation(world_version):
		packed = _foundation_settings.write_to_settings_packed(packed, _world_bounds_settings)
		return _lake_settings.write_to_settings_packed(packed)
	return packed

func _compute_worldgen_signature(worldgen_settings: Dictionary) -> String:
	var hashing_context: HashingContext = HashingContext.new()
	var start_error: Error = hashing_context.start(HashingContext.HASH_SHA1)
	if start_error != OK:
		return ""
	hashing_context.update(JSON.stringify(worldgen_settings).to_utf8_buffer())
	return hashing_context.finish().hex_encode()

func _validate_current_world_save_shape(data: Dictionary) -> bool:
	if not data.has("world_seed"):
		_reject_world_save("world.json is missing required field world_seed")
		return false
	if not data.has("worldgen_settings"):
		_reject_world_save("world.json is missing required field worldgen_settings")
		return false
	var worldgen_settings: Variant = data.get("worldgen_settings", {})
	if worldgen_settings is not Dictionary:
		_reject_world_save("worldgen_settings must be a Dictionary")
		return false
	var settings_dict: Dictionary = worldgen_settings as Dictionary
	if not settings_dict.has("mountains") or settings_dict.get("mountains") is not Dictionary:
		_reject_world_save("worldgen_settings.mountains must be a Dictionary")
		return false
	if WorldRuntimeConstants.uses_world_foundation(WorldRuntimeConstants.WORLD_VERSION):
		if not settings_dict.has("world_bounds") or settings_dict.get("world_bounds") is not Dictionary:
			_reject_world_save("worldgen_settings.world_bounds must be a Dictionary")
			return false
		if not settings_dict.has("foundation") or settings_dict.get("foundation") is not Dictionary:
			_reject_world_save("worldgen_settings.foundation must be a Dictionary")
			return false
		if not settings_dict.has("lakes") or settings_dict.get("lakes") is not Dictionary:
			_reject_world_save("worldgen_settings.lakes must be a Dictionary")
			return false
	return true

func _reject_world_save(message: String) -> void:
	push_error(message)

func _load_worldgen_settings_from_save(data: Dictionary) -> MountainGenSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", {})
	if worldgen_settings is not Dictionary:
		return MountainGenSettings.hard_coded_defaults()
	var mountains_settings: Variant = (worldgen_settings as Dictionary).get("mountains", {})
	if mountains_settings is not Dictionary:
		return MountainGenSettings.hard_coded_defaults()
	return MountainGenSettings.from_save_dict(mountains_settings as Dictionary)

func _load_world_bounds_from_save(data: Dictionary) -> WorldBoundsSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", {})
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		return WorldBoundsSettings.hard_coded_defaults()
	if worldgen_settings is not Dictionary or not (worldgen_settings as Dictionary).has("world_bounds"):
		var message: String = "world_version >= 9 requires worldgen_settings.world_bounds in world.json"
		push_error(message)
		assert(false, message)
		return WorldBoundsSettings.hard_coded_defaults()
	var world_bounds: Variant = (worldgen_settings as Dictionary).get("world_bounds", {})
	if world_bounds is not Dictionary:
		var message: String = "worldgen_settings.world_bounds must be a Dictionary"
		push_error(message)
		assert(false, message)
		return WorldBoundsSettings.hard_coded_defaults()
	return WorldBoundsSettings.from_save_dict(world_bounds as Dictionary)

func _load_foundation_settings_from_save(
	data: Dictionary,
	world_bounds: WorldBoundsSettings
) -> FoundationGenSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", {})
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		return FoundationGenSettings.for_bounds(world_bounds)
	if worldgen_settings is not Dictionary:
		return FoundationGenSettings.for_bounds(world_bounds)
	var foundation_settings: Variant = (worldgen_settings as Dictionary).get("foundation", {})
	if foundation_settings is not Dictionary:
		return FoundationGenSettings.for_bounds(world_bounds)
	return FoundationGenSettings.from_save_dict(foundation_settings as Dictionary, world_bounds)

func _load_lake_settings_from_save(data: Dictionary) -> LakeGenSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", {})
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		return LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	if worldgen_settings is not Dictionary:
		return LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var lake_settings: Variant = (worldgen_settings as Dictionary).get("lakes", {})
	if lake_settings is not Dictionary:
		return LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	return LakeGenSettings.from_save_dict(lake_settings as Dictionary)
