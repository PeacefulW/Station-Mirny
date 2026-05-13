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
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const INVALID_CHUNK_COORD: Vector2i = Vector2i(2147483647, 2147483647)
const MAX_SPAWN_RESULTS_PER_TICK: int = 1
const CONTOUR_WORKER_THREAD_COUNT: int = 4

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
var _debug_tile_grid_visible: bool = false
var _debug_mountain_solid_visible: bool = false
var _debug_mountain_contour_visible: bool = false
var _contour_world_core: Object = null
var _contour_worker_threads: Array[Thread] = []
var _contour_request_mutex: Mutex = Mutex.new()
var _contour_result_mutex: Mutex = Mutex.new()
var _contour_request_semaphore: Semaphore = Semaphore.new()
var _contour_pending_requests: Array[Dictionary] = []
var _contour_completed_results: Array[Dictionary] = []
var _contour_worker_should_exit: bool = false
var _contour_inflight_count: int = 0
var _contour_requested_keys: Dictionary = {}
var _contour_dirty_request_queue: Array[Vector2i] = []
var _contour_dirty_request_lookup: Dictionary = {}
var _contour_results_by_chunk: Dictionary = {}
var _contour_diff_revision: int = 0
var _contour_requested_revision_by_chunk: Dictionary = {}
var _contour_ready_revision_by_chunk: Dictionary = {}

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
	_start_contour_worker()
	_packet_backend.start()
	var frame_budget_dispatcher: Node = _get_frame_budget_dispatcher()
	if frame_budget_dispatcher != null:
		_stream_job_id = frame_budget_dispatcher.register_job(
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
	var frame_budget_dispatcher: Node = _get_frame_budget_dispatcher()
	if _stream_job_id and frame_budget_dispatcher != null:
		frame_budget_dispatcher.unregister_job(_stream_job_id)
	_stop_contour_worker()
	_packet_backend.stop()

func _get_frame_budget_dispatcher() -> Node:
	return get_node_or_null("/root/FrameBudgetDispatcher")

func _get_event_bus() -> Node:
	return get_node_or_null("/root/EventBus")

func _emit_world_event(signal_name: StringName, args: Array = []) -> void:
	var event_bus: Node = _get_event_bus()
	if event_bus == null:
		return
	var call_args: Array = [signal_name]
	call_args.append_array(args)
	event_bus.callv("emit_signal", call_args)

func _get_player_authority() -> Node:
	return get_node_or_null("/root/PlayerAuthority")

func _get_local_player_node() -> Node2D:
	var player_authority: Node = _get_player_authority()
	if player_authority == null or not player_authority.has_method("get_local_player"):
		return null
	return player_authority.call("get_local_player") as Node2D

func _get_local_player_position() -> Vector2:
	var player_authority: Node = _get_player_authority()
	if player_authority == null or not player_authority.has_method("get_local_player_position"):
		return Vector2.ZERO
	return player_authority.call("get_local_player_position") as Vector2

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
	_emit_world_event(&"world_initialized", [world_seed])

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
	_emit_world_event(&"world_initialized", [world_seed])
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
	_sync_contour_diff_revision_from_store()
	_request_contour_results_for_loaded_chunks()

func get_world_seed() -> int:
	return world_seed

func get_world_version() -> int:
	return world_version

func toggle_debug_tile_grid() -> bool:
	_debug_tile_grid_visible = not _debug_tile_grid_visible
	_apply_debug_overlay_visibility_to_loaded_chunks()
	return _debug_tile_grid_visible

func toggle_debug_mountain_solid_mask() -> bool:
	_debug_mountain_solid_visible = not _debug_mountain_solid_visible
	_refresh_debug_visuals_for_loaded_chunks()
	return _debug_mountain_solid_visible

func toggle_debug_mountain_contour() -> bool:
	_debug_mountain_contour_visible = not _debug_mountain_contour_visible
	_refresh_debug_visuals_for_loaded_chunks()
	return _debug_mountain_contour_visible

func get_mountain_contour_debug_state(chunk_coord: Vector2i) -> Dictionary:
	var chunk_view: ChunkView = _chunk_views.get(_canonicalize_chunk_coord(chunk_coord)) as ChunkView
	if chunk_view == null:
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
		}
	var debug_state: Dictionary = chunk_view.get_mountain_contour_debug_state()
	debug_state["ready"] = true
	return debug_state

func get_contour_halo_debug_state(chunk_coord: Vector2i, contour_class: StringName) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var request: Dictionary = _build_contour_worker_request(chunk_coord)
	if request.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"contour_class": contour_class,
		}
	var world_core: Object = ClassDB.instantiate("WorldCore")
	if world_core == null:
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"contour_class": contour_class,
		}
	var packet_map: Dictionary = _build_contour_packet_map_for_request(world_core, request)
	var input: Dictionary = _build_contour_input_from_request(request, packet_map, contour_class)
	input["ready"] = not input.is_empty()
	return input

func request_contour_results_for_chunk_debug(chunk_coord: Vector2i) -> void:
	_request_contour_results_for_chunk(chunk_coord)

func drain_contour_results_debug(max_count: int = 8) -> int:
	return _drain_completed_contour_results(max_count)

func get_contour_result_debug_state(chunk_coord: Vector2i, contour_class: StringName) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var required_revision: int = _get_contour_required_revision_for_chunk(chunk_coord)
	var chunk_results: Dictionary = _contour_results_by_chunk.get(chunk_coord, {}) as Dictionary
	var result: Dictionary = chunk_results.get(contour_class, {}) as Dictionary
	if result.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"contour_class": contour_class,
			"current_diff_revision": _contour_diff_revision,
			"required_diff_revision": required_revision,
		}
	var stored_revision: int = int(result.get("diff_revision", -1))
	if stored_revision != required_revision:
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"contour_class": contour_class,
			"stored_diff_revision": stored_revision,
			"current_diff_revision": _contour_diff_revision,
			"required_diff_revision": required_revision,
		}
	return {
		"ready": bool(result.get("ready", false)),
		"chunk_coord": chunk_coord,
		"contour_class": contour_class,
		"recipe_id": result.get("recipe_id", &""),
		"diff_revision": stored_revision,
		"current_diff_revision": _contour_diff_revision,
		"required_diff_revision": required_revision,
		"pixel_size": result.get("pixel_size", Vector2i.ZERO),
		"collision_size": result.get("collision_size", Vector2i.ZERO),
		"collision_sample_px": int(result.get("collision_sample_px", 0)),
		"mask_byte_count": (result.get("mask_rgba8", PackedByteArray()) as PackedByteArray).size(),
		"height_byte_count": (result.get("height_r16", PackedByteArray()) as PackedByteArray).size(),
		"normal_byte_count": (result.get("normal_rgba8", PackedByteArray()) as PackedByteArray).size(),
		"collision_sample_count": (result.get("collision_sdf_f32", PackedFloat32Array()) as PackedFloat32Array).size(),
	}

func get_contour_dirty_debug_state(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var chunk_results: Dictionary = _contour_results_by_chunk.get(chunk_coord, {}) as Dictionary
	var result_revisions: Dictionary = {}
	for contour_class_variant: Variant in WorldRuntimeConstants.CONTOUR_CLASSES:
		var contour_class: StringName = contour_class_variant as StringName
		var result: Dictionary = chunk_results.get(contour_class, {}) as Dictionary
		result_revisions[contour_class] = int(result.get("diff_revision", -1)) if not result.is_empty() else -1
	var ready_revision: int = int(_contour_ready_revision_by_chunk.get(chunk_coord, -1))
	var required_revision: int = _get_contour_required_revision_for_chunk(chunk_coord)
	return {
		"ready": ready_revision == required_revision,
		"chunk_coord": chunk_coord,
		"store_diff_revision": _diff_store.get_diff_revision(),
		"current_diff_revision": _contour_diff_revision,
		"required_diff_revision": required_revision,
		"requested_revision": int(_contour_requested_revision_by_chunk.get(chunk_coord, -1)),
		"ready_revision": ready_revision,
		"result_revisions": result_revisions,
	}

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
	var tile_data: Dictionary = get_effective_tile_data_at_world(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var raw_walkable: bool = bool(tile_data.get("walkable", false))
	if not raw_walkable and not _is_movement_walkability_contour_controlled(terrain_id):
		return false
	var collision_sample: Dictionary = _sample_movement_collision_at_world(world_pos)
	if not bool(collision_sample.get("ready", false)):
		return false
	return not bool(collision_sample.get("blocked", true))

func is_movement_blocked_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = get_effective_tile_data_at_world(world_pos)
	if not bool(tile_data.get("ready", false)):
		return true
	var collision_sample: Dictionary = _sample_movement_collision_at_world(world_pos)
	if not bool(collision_sample.get("ready", false)):
		return true
	return bool(collision_sample.get("blocked", true))

func is_raw_tile_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = get_effective_tile_data_at_world(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	return bool(tile_data.get("walkable", false))

func get_effective_tile_data_at_world(world_pos: Vector2) -> Dictionary:
	return _get_tile_data(world_pos)

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
	_sync_contour_diff_revision_from_store()
	_apply_loaded_override(chunk_coord, local_coord, WorldRuntimeConstants.TERRAIN_PLAINS_DUG, true)
	_handle_cover_tile_dug(world_tile)
	_mark_contour_diff_changed(world_tile, _contour_diff_revision)
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		_emit_world_event(
			&"mountain_tile_mined",
			[world_tile, terrain_id, WorldRuntimeConstants.TERRAIN_PLAINS_DUG]
		)
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
	_drain_completed_packets(2)
	_drain_completed_contour_results(4)
	_request_queued_dirty_contour_chunks(4)
	_publish_next_batch()
	_evict_outside_ring(1)
	return _has_pending_streaming_work()

func _update_player_chunk_coord() -> void:
	var player_pos: Vector2 = _get_local_player_position()
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
		_request_contour_results_for_chunk(chunk_coord)
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
		_refresh_debug_visuals_for_chunk(_active_publish_chunk)
		if _are_contour_results_ready_for_current_revision(_active_publish_chunk):
			_apply_ready_contour_results_to_chunk_view(_active_publish_chunk)
		else:
			active_view.visible = false
		_emit_world_event(&"chunk_loaded", [_active_publish_chunk])
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
		_release_contour_results_for_chunk(chunk_coord)
		_handle_cover_chunk_unloaded(chunk_coord)
		_emit_world_event(&"chunk_unloaded", [chunk_coord])
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
	if _has_pending_contour_work():
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

func _sample_movement_collision_at_world(world_pos: Vector2) -> Dictionary:
	var raw_tile: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	var tile_coord: Vector2i = _canonicalize_tile_coord(raw_tile)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_tile_y_in_bounds(tile_coord.y):
		return {"ready": false}
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var contour_result: Dictionary = _get_current_contour_result(
		chunk_coord,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	if contour_result.is_empty():
		return {"ready": false}
	if not bool(contour_result.get("collision_blocks_inside", true)):
		return {
			"ready": true,
			"blocked": false,
			"chunk_coord": chunk_coord,
		}
	var sdf_values: PackedFloat32Array = contour_result.get("collision_sdf_f32", PackedFloat32Array()) as PackedFloat32Array
	var collision_size: Vector2i = contour_result.get("collision_size", Vector2i.ZERO) as Vector2i
	var sample_px: int = maxi(1, int(contour_result.get("collision_sample_px", 0)))
	if collision_size.x <= 0 \
			or collision_size.y <= 0 \
			or sdf_values.size() < collision_size.x * collision_size.y:
		return {"ready": false}
	var origin: Vector2 = _resolve_contour_collision_origin(contour_result, chunk_coord)
	var canonical_world_pos: Vector2 = _canonicalize_world_pos_for_collision(world_pos, raw_tile, tile_coord)
	var local_px: Vector2 = canonical_world_pos - origin
	var sample_x: float = clampf(local_px.x / float(sample_px), 0.0, float(collision_size.x - 1))
	var sample_y: float = clampf(local_px.y / float(sample_px), 0.0, float(collision_size.y - 1))
	var sdf_px: float = _sample_collision_sdf_bilinear(sdf_values, collision_size, sample_x, sample_y)
	return {
		"ready": true,
		"blocked": sdf_px >= 0.0,
		"sdf_px": sdf_px,
		"chunk_coord": chunk_coord,
	}

func _get_current_contour_result(chunk_coord: Vector2i, contour_class: StringName) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var required_revision: int = _get_contour_required_revision_for_chunk(chunk_coord)
	if (_contour_requested_revision_by_chunk.has(chunk_coord) or _contour_ready_revision_by_chunk.has(chunk_coord)) \
			and int(_contour_ready_revision_by_chunk.get(chunk_coord, -1)) != required_revision:
		return {}
	var chunk_results: Dictionary = _contour_results_by_chunk.get(chunk_coord, {}) as Dictionary
	var result: Dictionary = chunk_results.get(contour_class, {}) as Dictionary
	if result.is_empty():
		return {}
	if int(result.get("diff_revision", -1)) != required_revision:
		return {}
	if not bool(result.get("ready", false)):
		return {}
	return result

func _resolve_contour_collision_origin(result: Dictionary, chunk_coord: Vector2i) -> Vector2:
	var default_origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	var origin_variant: Variant = result.get("collision_origin_world_px", default_origin)
	if origin_variant is Vector2:
		return origin_variant as Vector2
	if origin_variant is Vector2i:
		return Vector2(origin_variant as Vector2i)
	return default_origin

func _canonicalize_world_pos_for_collision(
	world_pos: Vector2,
	raw_tile: Vector2i,
	canonical_tile: Vector2i
) -> Vector2:
	var tile_size: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	var raw_tile_origin: Vector2 = Vector2(float(raw_tile.x) * tile_size, float(raw_tile.y) * tile_size)
	var local_tile_offset: Vector2 = world_pos - raw_tile_origin
	return Vector2(
		float(canonical_tile.x) * tile_size + local_tile_offset.x,
		float(canonical_tile.y) * tile_size + local_tile_offset.y
	)

func _sample_collision_sdf_bilinear(
	sdf_values: PackedFloat32Array,
	collision_size: Vector2i,
	sample_x: float,
	sample_y: float
) -> float:
	var x0: int = clampi(floori(sample_x), 0, collision_size.x - 1)
	var y0: int = clampi(floori(sample_y), 0, collision_size.y - 1)
	var x1: int = mini(x0 + 1, collision_size.x - 1)
	var y1: int = mini(y0 + 1, collision_size.y - 1)
	var tx: float = sample_x - float(x0)
	var ty: float = sample_y - float(y0)
	var v00: float = sdf_values[y0 * collision_size.x + x0]
	var v10: float = sdf_values[y0 * collision_size.x + x1]
	var v01: float = sdf_values[y1 * collision_size.x + x0]
	var v11: float = sdf_values[y1 * collision_size.x + x1]
	var top: float = lerpf(v00, v10, tx)
	var bottom: float = lerpf(v01, v11, tx)
	return lerpf(top, bottom, ty)

func _is_movement_walkability_contour_controlled(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED

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
	var world_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_coord)
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if TerrainPresentationRegistry.is_contour_cutover_terrain(terrain_id):
		if chunk_view != null:
			chunk_view.apply_runtime_contour_cell_state(local_coord, terrain_id, walkable)
		_refresh_debug_visuals_around_tile(world_tile)
		return
	_refresh_loaded_visual_patch_for_tiles([
		world_tile,
	])
	_refresh_debug_visuals_around_tile(world_tile)

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
			_refresh_debug_visuals_for_chunk(chunk_coord)
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
					int(update.get("terrain_atlas_index", 0)),
					bool(update.get("walkable", true)),
					int(update.get("mountain_id", 0)),
					int(update.get("mountain_flags", 0))
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
		"mountain_id": int(tile_data.get("mountain_id", 0)),
		"mountain_flags": int(tile_data.get("mountain_flags", 0)),
	}

func _resolve_loaded_ground_atlas_index(tile_coord: Vector2i) -> int:
	var north_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(0, -1))
	var east_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(1, 0))
	var south_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(0, 1))
	var west_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(-1, 0))
	var north_east_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(1, -1))
	var south_east_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(1, 1))
	var south_west_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(-1, 1))
	var north_west_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(-1, -1))
	var signature_code: int = Autotile47.build_signature_code(
		not north_is_water,
		not north_east_is_water,
		not east_is_water,
		not south_east_is_water,
		not south_is_water,
		not south_west_is_water,
		not west_is_water,
		not north_west_is_water
	)
	var variant_index: int = Autotile47.pick_variant(tile_coord, world_seed)
	return Autotile47.build_atlas_index(signature_code, variant_index)

func _is_loaded_water_surface_at(tile_coord: Vector2i) -> bool:
	var sample: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord)
	if not bool(sample.get("ready", false)):
		return false
	return _is_loaded_water_surface_terrain(
		int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	)

func _is_loaded_water_surface_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP

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
			"mountain_id": 0,
			"mountain_flags": 0,
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
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
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
		"walkable": int(walkable_flags[index]) != 0,
		"mountain_id": int(mountain_ids[index]) if has_mountain_geometry else 0,
		"mountain_flags": int(mountain_flags[index]) if has_mountain_geometry else 0,
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
	chunk_view.set_contour_rendering_enabled(true)
	chunk_view.set_debug_overlays(
		_debug_tile_grid_visible,
		_debug_mountain_solid_visible,
		_debug_mountain_contour_visible
	)
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
	_clear_contour_runtime_state()
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
	var player: Node2D = _get_local_player_node()
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
	if _get_local_player_node() == null:
		_active_cover_mountain_id = 0
		_active_cover_component_id = 0
		return {
			"state_changed": previous_mountain_id != 0 or previous_component_id != 0,
			"previous_mountain_id": previous_mountain_id,
			"previous_component_id": previous_component_id,
			"mountain_id": 0,
			"component_id": 0,
		}
	var player_tile: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(_get_local_player_position()))
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

func _apply_debug_overlay_visibility_to_loaded_chunks() -> void:
	for chunk_coord_variant: Variant in _chunk_views.keys():
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord_variant) as ChunkView
		if chunk_view == null:
			continue
		chunk_view.set_debug_overlays(
			_debug_tile_grid_visible,
			_debug_mountain_solid_visible,
			_debug_mountain_contour_visible
		)

func _refresh_debug_visuals_for_loaded_chunks() -> void:
	_apply_debug_overlay_visibility_to_loaded_chunks()
	if not _debug_mountain_solid_visible and not _debug_mountain_contour_visible:
		return
	for chunk_coord: Vector2i in _dictionary_vector2i_keys(_chunk_views):
		_refresh_debug_visuals_for_chunk(chunk_coord)

func _refresh_debug_visuals_for_chunk(chunk_coord: Vector2i) -> void:
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if chunk_view == null:
		return
	chunk_view.set_debug_overlays(
		_debug_tile_grid_visible,
		_debug_mountain_solid_visible,
		_debug_mountain_contour_visible
	)
	if not _debug_mountain_solid_visible and not _debug_mountain_contour_visible:
		return
	var solid_mask: PackedByteArray = _build_local_mountain_solid_mask(chunk_coord)
	var contour_vertices := PackedVector2Array()
	var contour_indices := PackedInt32Array()
	if _debug_mountain_contour_visible:
		var contour_result: Dictionary = _build_native_mountain_contour_for_chunk(chunk_coord)
		contour_vertices = contour_result.get("vertices", PackedVector2Array()) as PackedVector2Array
		contour_indices = contour_result.get("indices", PackedInt32Array()) as PackedInt32Array
	chunk_view.apply_contour_debug_data(solid_mask, contour_vertices, contour_indices)

func _refresh_debug_visuals_around_tile(world_tile: Vector2i) -> void:
	if not _debug_mountain_solid_visible and not _debug_mountain_contour_visible:
		return
	var affected_chunks: Dictionary = {}
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(
				_canonicalize_tile_coord(world_tile + Vector2i(offset_x, offset_y))
			)
			affected_chunks[chunk_coord] = true
	for chunk_coord: Vector2i in _dictionary_vector2i_keys(affected_chunks):
		_refresh_debug_visuals_for_chunk(chunk_coord)

func _start_contour_worker() -> void:
	if _has_contour_worker_threads_running():
		return
	var probe_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(probe_world_core != null, "WorldCore required for runtime SDF contour streaming - build GDExtension first")
	if probe_world_core == null:
		return
	assert(probe_world_core.has_method("build_contour_chunk"), "WorldCore.build_contour_chunk(input) is required for runtime SDF contour streaming")
	assert(probe_world_core.has_method("generate_chunk_packets_batch"), "WorldCore.generate_chunk_packets_batch(...) is required for contour halo packet fill")
	_contour_worker_should_exit = false
	_contour_worker_threads.clear()
	for _index: int in range(CONTOUR_WORKER_THREAD_COUNT):
		var thread := Thread.new()
		var start_error: Error = thread.start(_contour_worker_loop)
		assert(start_error == OK, "Failed to start runtime SDF contour worker thread")
		if start_error == OK:
			_contour_worker_threads.append(thread)

func _stop_contour_worker() -> void:
	if not _has_contour_worker_threads_running():
		return
	_contour_worker_should_exit = true
	for _index: int in range(_contour_worker_threads.size()):
		_contour_request_semaphore.post()
	for thread: Thread in _contour_worker_threads:
		if thread.is_started():
			thread.wait_to_finish()
	_contour_worker_threads.clear()

func _has_contour_worker_threads_running() -> bool:
	for thread: Thread in _contour_worker_threads:
		if thread.is_started():
			return true
	return false

func _clear_contour_runtime_state() -> void:
	_contour_request_mutex.lock()
	_contour_pending_requests.clear()
	_contour_requested_keys.clear()
	_contour_inflight_count = 0
	_contour_request_mutex.unlock()
	_contour_dirty_request_queue.clear()
	_contour_dirty_request_lookup.clear()
	_contour_result_mutex.lock()
	_contour_completed_results.clear()
	_contour_result_mutex.unlock()
	_contour_results_by_chunk.clear()
	_contour_diff_revision = 0
	_contour_requested_revision_by_chunk.clear()
	_contour_ready_revision_by_chunk.clear()

func _request_contour_results_for_loaded_chunks() -> void:
	for chunk_coord_variant: Variant in _chunk_packets.keys():
		_request_contour_results_for_chunk(chunk_coord_variant as Vector2i)

func _request_contour_results_for_chunk(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
		return
	if (_chunk_packets.get(chunk_coord, {}) as Dictionary).is_empty():
		return
	if _are_contour_results_ready_for_current_revision(chunk_coord):
		return
	var required_revision: int = _get_contour_required_revision_for_chunk(chunk_coord)
	_contour_requested_revision_by_chunk[chunk_coord] = required_revision
	var request: Dictionary = _build_contour_worker_request(chunk_coord, required_revision)
	if request.is_empty():
		return
	_queue_contour_worker_request(request)

func _are_contour_results_ready_for_current_revision(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var required_revision: int = _get_contour_required_revision_for_chunk(chunk_coord)
	if int(_contour_ready_revision_by_chunk.get(chunk_coord, -1)) == required_revision:
		return true
	var chunk_results: Dictionary = _contour_results_by_chunk.get(chunk_coord, {}) as Dictionary
	if chunk_results.size() < WorldRuntimeConstants.CONTOUR_ACTIVE_RESULT_CLASSES.size():
		return false
	for contour_class_variant: Variant in WorldRuntimeConstants.CONTOUR_ACTIVE_RESULT_CLASSES:
		var contour_class: StringName = contour_class_variant as StringName
		var result: Dictionary = chunk_results.get(contour_class, {}) as Dictionary
		if result.is_empty() or int(result.get("diff_revision", -1)) != required_revision:
			return false
		if not bool(result.get("ready", false)):
			return false
	return true

func _build_contour_worker_request(chunk_coord: Vector2i, diff_revision: int = -1) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
	if packet.is_empty():
		return {}
	var request_revision: int = _contour_diff_revision if diff_revision < 0 else diff_revision
	var recipes: Dictionary = {}
	for contour_class_variant: Variant in WorldRuntimeConstants.CONTOUR_CLASSES:
		var contour_class: StringName = contour_class_variant as StringName
		var recipe: Dictionary = TerrainPresentationRegistry.get_contour_recipe_for_class(contour_class)
		if recipe.is_empty():
			return {}
		recipes[contour_class] = recipe
	var contour_classes: Array[StringName] = _build_contour_worker_class_order()
	var loaded_packets: Dictionary = {}
	var diff_overrides: Dictionary = {}
	for halo_chunk: Vector2i in _collect_contour_halo_chunk_coords(chunk_coord):
		var loaded_packet: Dictionary = _chunk_packets.get(halo_chunk, {}) as Dictionary
		if not loaded_packet.is_empty():
			loaded_packets[halo_chunk] = loaded_packet.duplicate(true)
		var chunk_diffs: Dictionary = _snapshot_contour_diffs_for_chunk(halo_chunk)
		if not chunk_diffs.is_empty():
			diff_overrides[halo_chunk] = chunk_diffs
	return {
		"chunk_coord": chunk_coord,
		"world_seed": world_seed,
		"world_version": world_version,
		"settings_packed": _worldgen_settings_packed.duplicate(),
		"epoch": _generation_epoch,
		"diff_revision": request_revision,
		"request_key": _make_contour_request_key(chunk_coord, request_revision),
		"finite_world": _uses_finite_world_bounds(),
		"bounds_width_tiles": _world_bounds_settings.width_tiles,
		"bounds_height_tiles": _world_bounds_settings.height_tiles,
		"loaded_packets": loaded_packets,
		"diff_overrides": diff_overrides,
		"contour_classes": contour_classes,
		"recipes": recipes,
	}

func _build_contour_worker_class_order() -> Array[StringName]:
	var ordered: Array[StringName] = []
	var preferred_order: Array[StringName] = [
		WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
		WorldRuntimeConstants.CONTOUR_CLASS_WATER_SURFACE,
	]
	for contour_class: StringName in preferred_order:
		if WorldRuntimeConstants.CONTOUR_ACTIVE_RESULT_CLASSES.has(contour_class):
			ordered.append(contour_class)
	for contour_class_variant: Variant in WorldRuntimeConstants.CONTOUR_ACTIVE_RESULT_CLASSES:
		var contour_class: StringName = contour_class_variant as StringName
		if not ordered.has(contour_class):
			ordered.append(contour_class)
	return ordered

func _snapshot_contour_diffs_for_chunk(chunk_coord: Vector2i) -> Dictionary:
	var diffs: Dictionary = {}
	for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(chunk_coord):
		diffs[local_coord] = _diff_store.get_tile_override(chunk_coord, local_coord)
	return diffs

func _collect_contour_halo_chunk_coords(chunk_coord: Vector2i) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var seen: Dictionary = {}
	for y: int in range(chunk_coord.y - 1, chunk_coord.y + 2):
		for x: int in range(chunk_coord.x - 1, chunk_coord.x + 2):
			var sample_chunk: Vector2i = _canonicalize_chunk_coord(Vector2i(x, y))
			if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(sample_chunk.y):
				continue
			if seen.has(sample_chunk):
				continue
			seen[sample_chunk] = true
			coords.append(sample_chunk)
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return coords

func _queue_contour_worker_request(request: Dictionary) -> void:
	if not _has_contour_worker_threads_running():
		push_error("Runtime SDF contour worker is not running.")
		return
	var request_key: String = str(request.get("request_key", ""))
	var request_chunk: Vector2i = _canonicalize_chunk_coord(request.get("chunk_coord", Vector2i.ZERO) as Vector2i)
	var request_revision: int = int(request.get("diff_revision", -1))
	_contour_request_mutex.lock()
	if _contour_requested_keys.has(request_key):
		_contour_request_mutex.unlock()
		return
	_drop_stale_pending_contour_requests_locked(request_chunk, request_revision)
	_contour_requested_keys[request_key] = true
	_contour_pending_requests.append(request)
	_contour_inflight_count += 1
	_contour_request_mutex.unlock()
	_contour_request_semaphore.post()

func _queue_dirty_contour_request(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _contour_dirty_request_lookup.has(chunk_coord):
		return
	_contour_dirty_request_lookup[chunk_coord] = true
	_contour_dirty_request_queue.append(chunk_coord)

func _request_queued_dirty_contour_chunks(max_count: int) -> int:
	var requested_count: int = 0
	while requested_count < max_count and not _contour_dirty_request_queue.is_empty():
		var chunk_coord: Vector2i = _contour_dirty_request_queue.pop_front()
		_contour_dirty_request_lookup.erase(chunk_coord)
		_request_contour_results_for_chunk(chunk_coord)
		requested_count += 1
	return requested_count

func _drop_stale_pending_contour_requests_locked(chunk_coord: Vector2i, revision: int) -> void:
	var retained: Array[Dictionary] = []
	var removed_count: int = 0
	for queued_request: Dictionary in _contour_pending_requests:
		var queued_chunk: Vector2i = _canonicalize_chunk_coord(queued_request.get("chunk_coord", INVALID_CHUNK_COORD) as Vector2i)
		if queued_chunk != chunk_coord:
			retained.append(queued_request)
			continue
		var queued_revision: int = int(queued_request.get("diff_revision", -1))
		if queued_revision < revision:
			_contour_requested_keys.erase(str(queued_request.get("request_key", "")))
			removed_count += 1
			continue
		retained.append(queued_request)
	if removed_count > 0:
		_contour_pending_requests = retained
		_contour_inflight_count = maxi(0, _contour_inflight_count - removed_count)

func _drain_completed_contour_results(max_count: int) -> int:
	var drained: Array[Dictionary] = []
	_contour_result_mutex.lock()
	var drain_count: int = mini(max_count, _contour_completed_results.size())
	for _i: int in range(drain_count):
		drained.append(_contour_completed_results.pop_front() as Dictionary)
	_contour_result_mutex.unlock()
	for result: Dictionary in drained:
		_register_contour_result(result)
	return drained.size()

func _register_contour_result(result: Dictionary) -> bool:
	if int(result.get("epoch", -1)) != _generation_epoch:
		return false
	var chunk_coord: Vector2i = _canonicalize_chunk_coord(result.get("chunk_coord", Vector2i.ZERO) as Vector2i)
	var required_revision: int = _get_contour_required_revision_for_chunk(chunk_coord)
	if int(result.get("diff_revision", -1)) != required_revision:
		return false
	if (_chunk_packets.get(chunk_coord, {}) as Dictionary).is_empty():
		return false
	var contour_class: StringName = result.get("contour_class", &"") as StringName
	if not WorldRuntimeConstants.CONTOUR_CLASSES.has(contour_class):
		return false
	if not bool(result.get("ready", false)):
		return false
	var chunk_results: Dictionary = _contour_results_by_chunk.get(chunk_coord, {}) as Dictionary
	chunk_results[contour_class] = result.duplicate(true)
	_contour_results_by_chunk[chunk_coord] = chunk_results
	if _are_contour_results_ready_for_current_revision(chunk_coord):
		_contour_ready_revision_by_chunk[chunk_coord] = required_revision
		_contour_requested_revision_by_chunk.erase(chunk_coord)
		_apply_ready_contour_results_to_chunk_view(chunk_coord)
	return true

func _release_contour_results_for_chunk(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_contour_results_by_chunk.erase(chunk_coord)
	_contour_requested_revision_by_chunk.erase(chunk_coord)
	_contour_ready_revision_by_chunk.erase(chunk_coord)
	_contour_dirty_request_lookup.erase(chunk_coord)
	_contour_dirty_request_queue.erase(chunk_coord)
	var key_prefix: String = "%d:%d:" % [chunk_coord.x, chunk_coord.y]
	_contour_request_mutex.lock()
	for request_key_variant: Variant in _contour_requested_keys.keys():
		var request_key: String = str(request_key_variant)
		if request_key.begins_with(key_prefix):
			_contour_requested_keys.erase(request_key)
	_contour_request_mutex.unlock()

func _has_pending_contour_work() -> bool:
	_contour_request_mutex.lock()
	var has_requests: bool = not _contour_pending_requests.is_empty() or _contour_inflight_count > 0
	_contour_request_mutex.unlock()
	if has_requests:
		return true
	if not _contour_dirty_request_queue.is_empty():
		return true
	_contour_result_mutex.lock()
	var has_results: bool = not _contour_completed_results.is_empty()
	_contour_result_mutex.unlock()
	return has_results

func _sync_contour_diff_revision_from_store() -> void:
	_contour_diff_revision = _diff_store.get_diff_revision()

func _get_contour_required_revision_for_chunk(chunk_coord: Vector2i) -> int:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _contour_requested_revision_by_chunk.has(chunk_coord):
		return int(_contour_requested_revision_by_chunk.get(chunk_coord, _contour_diff_revision))
	if _contour_ready_revision_by_chunk.has(chunk_coord):
		return int(_contour_ready_revision_by_chunk.get(chunk_coord, _contour_diff_revision))
	return _contour_diff_revision

func _mark_contour_diff_revision_changed() -> void:
	_sync_contour_diff_revision_from_store()

func _mark_contour_diff_changed(world_tile: Vector2i, diff_revision: int) -> void:
	var affected_chunks: Array[Vector2i] = _collect_contour_dirty_chunks_for_tile(world_tile)
	for affected_chunk: Vector2i in affected_chunks:
		_mark_contour_chunk_dirty(affected_chunk, diff_revision)
		_queue_dirty_contour_request(affected_chunk)

func _collect_contour_dirty_chunks_for_tile(world_tile: Vector2i) -> Array[Vector2i]:
	var canonical_tile: Vector2i = _canonicalize_tile_coord(world_tile)
	var changed_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	var halo_tiles: int = WorldRuntimeConstants.CONTOUR_HALO_TILES
	var x_offsets: Array[int] = [0]
	var y_offsets: Array[int] = [0]
	if local_coord.x < halo_tiles:
		x_offsets.append(-1)
	if local_coord.x >= WorldRuntimeConstants.CHUNK_SIZE - halo_tiles:
		x_offsets.append(1)
	if local_coord.y < halo_tiles:
		y_offsets.append(-1)
	if local_coord.y >= WorldRuntimeConstants.CHUNK_SIZE - halo_tiles:
		y_offsets.append(1)

	var affected: Array[Vector2i] = []
	var seen: Dictionary = {}
	for y_offset: int in y_offsets:
		for x_offset: int in x_offsets:
			var affected_chunk: Vector2i = _canonicalize_chunk_coord(changed_chunk + Vector2i(x_offset, y_offset))
			if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(affected_chunk.y):
				continue
			if seen.has(affected_chunk):
				continue
			seen[affected_chunk] = true
			affected.append(affected_chunk)
	affected.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return affected

func _mark_contour_chunk_dirty(chunk_coord: Vector2i, diff_revision: int) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_contour_requested_revision_by_chunk[chunk_coord] = diff_revision
	_contour_ready_revision_by_chunk.erase(chunk_coord)
	_contour_results_by_chunk.erase(chunk_coord)
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if chunk_view != null:
		chunk_view.mark_contour_render_stale()

func _apply_ready_contour_results_to_chunk_view(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _are_contour_results_ready_for_current_revision(chunk_coord):
		return
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if chunk_view == null:
		return
	var required_revision: int = _get_contour_required_revision_for_chunk(chunk_coord)
	chunk_view.apply_contour_results(
		_contour_results_by_chunk.get(chunk_coord, {}) as Dictionary,
		required_revision
	)

func _make_contour_request_key(chunk_coord: Vector2i, diff_revision: int) -> String:
	return "%d:%d:%d" % [chunk_coord.x, chunk_coord.y, diff_revision]

func _contour_worker_loop() -> void:
	var worker_world_core: Object = ClassDB.instantiate("WorldCore")
	assert(worker_world_core != null, "WorldCore required inside runtime SDF contour worker")
	while true:
		_contour_request_semaphore.wait()
		if _contour_worker_should_exit:
			return
		while true:
			var request: Dictionary = _pop_contour_worker_request()
			if request.is_empty():
				break
			if worker_world_core != null:
				_process_contour_worker_request(worker_world_core, request)
			_finish_contour_worker_request()

func _pop_contour_worker_request() -> Dictionary:
	_contour_request_mutex.lock()
	var request: Dictionary = {}
	if not _contour_pending_requests.is_empty():
		request = _contour_pending_requests.pop_front() as Dictionary
	_contour_request_mutex.unlock()
	return request

func _finish_contour_worker_request() -> void:
	_contour_request_mutex.lock()
	_contour_inflight_count = maxi(0, _contour_inflight_count - 1)
	_contour_request_mutex.unlock()

func _append_completed_contour_results(results: Array[Dictionary]) -> void:
	if results.is_empty():
		return
	_contour_result_mutex.lock()
	for result: Dictionary in results:
		_contour_completed_results.append(result)
	_contour_result_mutex.unlock()

func _process_contour_worker_request(worker_world_core: Object, request: Dictionary) -> void:
	var packet_map: Dictionary = _build_contour_packet_map_for_request(worker_world_core, request)
	if packet_map.is_empty():
		return
	var contour_classes: Array = request.get("contour_classes", []) as Array
	for contour_class_variant: Variant in contour_classes:
		var contour_class: StringName = contour_class_variant as StringName
		var input: Dictionary = _build_contour_input_from_request(request, packet_map, contour_class)
		if input.is_empty():
			continue
		var result_variant: Variant = worker_world_core.call("build_contour_chunk", input)
		if result_variant is not Dictionary:
			continue
		var result: Dictionary = (result_variant as Dictionary).duplicate(true)
		if result.is_empty():
			continue
		_annotate_contour_result_visual_coverage(result)
		result["contour_class"] = contour_class
		result["epoch"] = int(request.get("epoch", -1))
		result["request_key"] = str(request.get("request_key", ""))
		_append_completed_contour_results([result])

func _annotate_contour_result_visual_coverage(result: Dictionary) -> void:
	if result.has("has_visual_coverage"):
		return
	result["has_visual_coverage"] = _contour_mask_has_visual_coverage(
		result.get("mask_rgba8", PackedByteArray()) as PackedByteArray
	)

func _contour_mask_has_visual_coverage(mask_rgba8: PackedByteArray) -> bool:
	for alpha_offset: int in range(3, mask_rgba8.size(), 4):
		if mask_rgba8[alpha_offset] != 0:
			return true
	return false

func _build_contour_packet_map_for_request(worker_world_core: Object, request: Dictionary) -> Dictionary:
	var packet_map: Dictionary = {}
	var loaded_packets: Dictionary = request.get("loaded_packets", {}) as Dictionary
	for chunk_coord_variant: Variant in loaded_packets.keys():
		packet_map[chunk_coord_variant] = (loaded_packets.get(chunk_coord_variant, {}) as Dictionary).duplicate(true)

	var missing_coords: Array[Vector2i] = []
	for halo_chunk: Vector2i in _collect_contour_halo_chunk_coords_for_request(request):
		if packet_map.has(halo_chunk):
			continue
		missing_coords.append(halo_chunk)
	if missing_coords.is_empty():
		return packet_map

	var coords := PackedVector2Array()
	for chunk_coord: Vector2i in missing_coords:
		coords.append(Vector2(chunk_coord.x, chunk_coord.y))
	var packets_variant: Variant = worker_world_core.call(
		"generate_chunk_packets_batch",
		int(request.get("world_seed", 0)),
		coords,
		int(request.get("world_version", 0)),
		request.get("settings_packed", PackedFloat32Array()) as PackedFloat32Array
	)
	if packets_variant is not Array:
		return packet_map
	var generated_packets: Array = packets_variant as Array
	for index: int in range(mini(missing_coords.size(), generated_packets.size())):
		packet_map[missing_coords[index]] = (generated_packets[index] as Dictionary).duplicate(true)
	return packet_map

func _collect_contour_halo_chunk_coords_for_request(request: Dictionary) -> Array[Vector2i]:
	var chunk_coord: Vector2i = request.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var coords: Array[Vector2i] = []
	var seen: Dictionary = {}
	for y: int in range(chunk_coord.y - 1, chunk_coord.y + 2):
		for x: int in range(chunk_coord.x - 1, chunk_coord.x + 2):
			var sample_chunk: Vector2i = _canonicalize_chunk_coord_for_request(Vector2i(x, y), request)
			if not _request_chunk_y_in_bounds(sample_chunk.y, request):
				continue
			if seen.has(sample_chunk):
				continue
			seen[sample_chunk] = true
			coords.append(sample_chunk)
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return coords

func _build_contour_input_from_request(request: Dictionary, packet_map: Dictionary, contour_class: StringName) -> Dictionary:
	var recipes: Dictionary = request.get("recipes", {}) as Dictionary
	var recipe: Dictionary = recipes.get(contour_class, {}) as Dictionary
	if recipe.is_empty():
		return {}
	var chunk_coord: Vector2i = request.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var halo_tiles: int = WorldRuntimeConstants.CONTOUR_HALO_TILES
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + halo_tiles * 2
	var cell_count: int = halo_side * halo_side
	var solid_mask := PackedByteArray()
	var contour_class_mask := PackedByteArray()
	var source_mask := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var terrain_ids := PackedInt32Array()
	solid_mask.resize(cell_count)
	contour_class_mask.resize(cell_count)
	source_mask.resize(cell_count)
	mountain_ids.resize(cell_count)
	terrain_ids.resize(cell_count)
	var chunk_coords: Array = []
	for halo_y: int in range(halo_side):
		for halo_x: int in range(halo_side):
			var local_coord := Vector2i(halo_x - halo_tiles, halo_y - halo_tiles)
			var world_tile := Vector2i(
				chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE + local_coord.x,
				chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE + local_coord.y
			)
			var sample: Dictionary = _sample_contour_tile_for_request(world_tile, packet_map, request)
			var index: int = halo_y * halo_side + halo_x
			var sample_class_code: int = _contour_class_code_for_sample(sample)
			contour_class_mask[index] = sample_class_code
			source_mask[index] = int(sample.get("source", WorldRuntimeConstants.CONTOUR_SOURCE_EMPTY))
			terrain_ids[index] = int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
			chunk_coords.append(sample.get("chunk_coord", INVALID_CHUNK_COORD) as Vector2i)
			if _is_sample_solid_for_contour_class(sample, contour_class):
				solid_mask[index] = 1
				if contour_class == WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS:
					mountain_ids[index] = int(sample.get("mountain_id", 0))
	return {
		"chunk_coord": chunk_coord,
		"world_seed": int(request.get("world_seed", world_seed)),
		"world_version": int(request.get("world_version", world_version)),
		"tile_size_px": WorldRuntimeConstants.TILE_SIZE_PX,
		"render_tile_size_px": WorldRuntimeConstants.CONTOUR_RENDER_TILE_SIZE_PX,
		"chunk_size_tiles": WorldRuntimeConstants.CHUNK_SIZE,
		"halo_tiles": halo_tiles,
		"halo_side": halo_side,
		"recipe_id": StringName(str(recipe.get("asset_name", contour_class))),
		"recipe": recipe,
		"solid_mask_with_halo": solid_mask,
		"contour_class_mask_with_halo": contour_class_mask,
		"mountain_id_with_halo": mountain_ids,
		"diff_revision": int(request.get("diff_revision", 0)),
		"source_mask_with_halo": source_mask,
		"terrain_id_with_halo": terrain_ids,
		"chunk_coord_with_halo": chunk_coords,
	}

func _sample_contour_tile_for_request(world_tile: Vector2i, packet_map: Dictionary, request: Dictionary) -> Dictionary:
	var canonical_tile: Vector2i = _canonicalize_tile_coord_for_request(world_tile, request)
	if not _request_tile_y_in_bounds(canonical_tile.y, request):
		return {
			"ready": false,
			"chunk_coord": WorldRuntimeConstants.tile_to_chunk(canonical_tile),
			"local_coord": WorldRuntimeConstants.tile_to_local(canonical_tile),
			"source": WorldRuntimeConstants.CONTOUR_SOURCE_OUT_OF_WORLD,
		}
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	var loaded_packets: Dictionary = request.get("loaded_packets", {}) as Dictionary
	var is_loaded_packet: bool = loaded_packets.has(chunk_coord)
	var override_data: Dictionary = _get_contour_diff_override_for_request(chunk_coord, local_coord, request)
	if not override_data.is_empty():
		return _build_contour_override_sample(
			chunk_coord,
			local_coord,
			override_data,
			WorldRuntimeConstants.CONTOUR_SOURCE_LOADED_DIFF if is_loaded_packet else WorldRuntimeConstants.CONTOUR_SOURCE_UNLOADED_DIFF
		)
	var packet: Dictionary = packet_map.get(chunk_coord, {}) as Dictionary
	if packet.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
			"source": WorldRuntimeConstants.CONTOUR_SOURCE_EMPTY,
		}
	return _read_contour_packet_sample(
		packet,
		chunk_coord,
		local_coord,
		WorldRuntimeConstants.CONTOUR_SOURCE_LOADED_PACKET if is_loaded_packet else WorldRuntimeConstants.CONTOUR_SOURCE_GENERATED_BASE
	)

func _get_contour_diff_override_for_request(chunk_coord: Vector2i, local_coord: Vector2i, request: Dictionary) -> Dictionary:
	var diff_overrides: Dictionary = request.get("diff_overrides", {}) as Dictionary
	var chunk_diffs: Dictionary = diff_overrides.get(chunk_coord, {}) as Dictionary
	return (chunk_diffs.get(local_coord, {}) as Dictionary).duplicate(true)

func _build_contour_override_sample(
	chunk_coord: Vector2i,
	local_coord: Vector2i,
	override_data: Dictionary,
	source: int
) -> Dictionary:
	var terrain_id: int = int(override_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var walkable: bool = bool(override_data.get("walkable", true))
	var mountain_id: int = 0
	var mountain_flags: int = 0
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL:
		mountain_id = 1
		mountain_flags = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	elif terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		mountain_id = 1
		mountain_flags = WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	var lake_flags: int = 0
	if terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
			or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP:
		lake_flags = WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": terrain_id,
		"walkable": walkable,
		"mountain_id": mountain_id,
		"mountain_flags": mountain_flags,
		"lake_flags": lake_flags,
		"source": source,
	}

func _read_contour_packet_sample(packet: Dictionary, chunk_coord: Vector2i, local_coord: Vector2i, source: int) -> Dictionary:
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_id_per_tile: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
			"source": source,
		}
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": int(terrain_ids[index]),
		"walkable": int(walkable_flags[index]) != 0,
		"mountain_id": int(mountain_id_per_tile[index]) if index < mountain_id_per_tile.size() else 0,
		"mountain_flags": int(mountain_flags[index]) if index < mountain_flags.size() else 0,
		"lake_flags": int(lake_flags[index]) if index < lake_flags.size() else 0,
		"source": source,
	}

func _contour_class_code_for_sample(sample: Dictionary) -> int:
	if not bool(sample.get("ready", false)):
		return WorldRuntimeConstants.CONTOUR_CLASS_EMPTY_CODE
	var terrain_id: int = int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var lake_flags: int = int(sample.get("lake_flags", 0))
	if (terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
			or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP) \
			and (lake_flags & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0:
		return WorldRuntimeConstants.CONTOUR_CLASS_WATER_CODE
	if _is_mountain_mass_terrain(terrain_id):
		return WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_CODE
	if _is_ground_surface_terrain(terrain_id):
		return WorldRuntimeConstants.CONTOUR_CLASS_GROUND_CODE
	return WorldRuntimeConstants.CONTOUR_CLASS_EMPTY_CODE

func _is_sample_solid_for_contour_class(sample: Dictionary, contour_class: StringName) -> bool:
	if not bool(sample.get("ready", false)):
		return false
	var terrain_id: int = int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	match contour_class:
		WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE:
			return _is_ground_surface_terrain(terrain_id)
		WorldRuntimeConstants.CONTOUR_CLASS_WATER_SURFACE:
			return (terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
					or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP) \
				and (int(sample.get("lake_flags", 0)) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS:
			if not _is_mountain_mass_terrain(terrain_id):
				return false
			if bool(sample.get("walkable", true)):
				return false
			if terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
				return true
			var mountain_id: int = int(sample.get("mountain_id", 0))
			var flags: int = int(sample.get("mountain_flags", 0))
			return mountain_id > 0 \
				and (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0
	return false

func _is_mountain_mass_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED

func _is_ground_surface_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_GROUND \
		or terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP

func _canonicalize_tile_coord_for_request(tile_coord: Vector2i, request: Dictionary) -> Vector2i:
	if not bool(request.get("finite_world", false)):
		return tile_coord
	var width_tiles: int = maxi(1, int(request.get("bounds_width_tiles", 1)))
	return Vector2i(posmod(tile_coord.x, width_tiles), tile_coord.y)

func _canonicalize_chunk_coord_for_request(chunk_coord: Vector2i, request: Dictionary) -> Vector2i:
	if not bool(request.get("finite_world", false)):
		return chunk_coord
	var width_chunks: int = maxi(1, int(request.get("bounds_width_tiles", WorldRuntimeConstants.CHUNK_SIZE)) / WorldRuntimeConstants.CHUNK_SIZE)
	return Vector2i(posmod(chunk_coord.x, width_chunks), chunk_coord.y)

func _request_tile_y_in_bounds(tile_y: int, request: Dictionary) -> bool:
	if not bool(request.get("finite_world", false)):
		return true
	return tile_y >= 0 and tile_y < int(request.get("bounds_height_tiles", 0))

func _request_chunk_y_in_bounds(chunk_y: int, request: Dictionary) -> bool:
	if not bool(request.get("finite_world", false)):
		return true
	var height_chunks: int = maxi(1, int(request.get("bounds_height_tiles", WorldRuntimeConstants.CHUNK_SIZE)) / WorldRuntimeConstants.CHUNK_SIZE)
	return chunk_y >= 0 and chunk_y < height_chunks

func _build_local_mountain_solid_mask(chunk_coord: Vector2i) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, {}) as Dictionary
	if packet.is_empty():
		return mask
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var world_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_coord)
		if _is_mountain_contour_solid_sample(_get_loaded_tile_data_no_enqueue(world_tile)):
			mask[index] = 1
	return mask

func _build_native_mountain_contour_for_chunk(chunk_coord: Vector2i) -> Dictionary:
	var world_core: Object = _get_contour_world_core()
	if world_core == null:
		return {
			"vertices": PackedVector2Array(),
			"indices": PackedInt32Array(),
		}
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_debug",
		_build_mountain_solid_halo(chunk_coord),
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	if result_variant is Dictionary:
		return result_variant as Dictionary
	push_error("WorldCore.build_mountain_contour_debug returned non-dictionary result.")
	return {
		"vertices": PackedVector2Array(),
		"indices": PackedInt32Array(),
	}

func _build_mountain_solid_halo(chunk_coord: Vector2i) -> PackedByteArray:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(halo_side * halo_side)
	for halo_y: int in range(halo_side):
		for halo_x: int in range(halo_side):
			var local_coord := Vector2i(halo_x - 1, halo_y - 1)
			var world_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_coord)
			if _is_mountain_contour_solid_sample(_get_loaded_tile_data_no_enqueue(world_tile)):
				solid_halo[halo_y * halo_side + halo_x] = 1
	return solid_halo

func _is_mountain_contour_solid_sample(sample: Dictionary) -> bool:
	if not bool(sample.get("ready", false)):
		return false
	var terrain_id: int = int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	if not _is_mountain_mass_terrain(terrain_id):
		return false
	if bool(sample.get("walkable", true)):
		return false
	if terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
		return true
	var mountain_id: int = int(sample.get("mountain_id", 0))
	var mountain_flags: int = int(sample.get("mountain_flags", 0))
	return mountain_id > 0 \
		and (mountain_flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0

func _get_contour_world_core() -> Object:
	if _contour_world_core != null:
		return _contour_world_core
	_contour_world_core = ClassDB.instantiate("WorldCore")
	assert(_contour_world_core != null, "WorldCore required for mountain contour debug - build GDExtension first")
	if _contour_world_core == null:
		return null
	if not _contour_world_core.has_method("build_mountain_contour_debug"):
		push_error("WorldCore missing build_mountain_contour_debug; mountain contour debug disabled.")
		_contour_world_core = null
		return null
	return _contour_world_core

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
	var player: Node2D = _get_local_player_node()
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
		var lake_settings: Dictionary = settings_dict.get("lakes") as Dictionary
		if WorldRuntimeConstants.WORLD_VERSION >= 42 and not lake_settings.has("connectivity"):
			_reject_world_save("worldgen_settings.lakes.connectivity is required for world_version >= 42")
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
