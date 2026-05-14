class_name WorldStreamer
extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const HarvestQuery = preload("res://core/systems/world/harvest_query.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const MountainCavityCache = preload("res://core/systems/world/mountain_cavity_cache.gd")
const MountainContourCollisionCache = preload("res://core/systems/world/mountain_contour_collision_cache.gd")
const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")
const MountainContourStyleRegistry = preload("res://core/systems/world/mountain_contour_style_registry.gd")
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
var _debug_tile_grid_visible: bool = false
var _debug_mountain_solid_visible: bool = false
var _debug_mountain_contour_visible: bool = false
var _contour_world_core: Object = null
var _mountain_contour_style_registry: MountainContourStyleRegistry = MountainContourStyleRegistry.new()
var _mountain_contour_style: MountainContourStyle = null
var _mountain_contour_collision_caches: Dictionary = {}
var _mountain_contour_runtime_debug_snapshots: Dictionary = {}
var _mountain_contour_runtime_visible: bool = true
var _mountain_contour_runtime_revision: int = 0

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
	_load_default_mountain_contour_style()
	_packet_backend.start()
	var dispatcher: Object = _get_frame_budget_dispatcher()
	if dispatcher != null:
		_stream_job_id = dispatcher.call(
			"register_job",
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
	var dispatcher: Object = _get_frame_budget_dispatcher()
	if _stream_job_id and dispatcher != null:
		dispatcher.call("unregister_job", _stream_job_id)
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
	var event_bus: Object = _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal("world_initialized", world_seed)

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
	var event_bus: Object = _get_event_bus()
	if event_bus != null:
		event_bus.emit_signal("world_initialized", world_seed)
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

func reload_mountain_contour_style_from_disk() -> Dictionary:
	var previous_signature: Dictionary = {}
	if _mountain_contour_style != null:
		previous_signature = _mountain_contour_style.get_source_signature()
	var new_registry := MountainContourStyleRegistry.new()
	if not new_registry.load_default_styles():
		return {
			"ok": false,
			"kept_previous_style": _mountain_contour_style != null,
			"validation_errors": new_registry.validation_errors.duplicate(),
			"previous_source_signature": previous_signature,
		}
	var new_style: MountainContourStyle = new_registry.require_style(&"mountain")
	if new_style == null:
		return {
			"ok": false,
			"kept_previous_style": _mountain_contour_style != null,
			"validation_errors": new_registry.validation_errors.duplicate(),
			"previous_source_signature": previous_signature,
		}
	_mountain_contour_style_registry = new_registry
	_mountain_contour_style = new_style
	var refresh_report: Dictionary = _refresh_mountain_contour_runtime_for_loaded_chunks(&"style_reload")
	return {
		"ok": true,
		"style_id": String(_mountain_contour_style.asset_name),
		"previous_source_signature": previous_signature,
		"source_signature": _mountain_contour_style.get_source_signature(),
		"refreshed_chunk_count": int(refresh_report.get("chunk_count", 0)),
		"refresh_usec": int(refresh_report.get("refresh_usec", 0)),
	}

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

func get_mountain_contour_runtime_debug_snapshot(chunk_coord: Vector2i) -> Dictionary:
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	var snapshot: Dictionary = _mountain_contour_runtime_debug_snapshots.get(canonical_chunk, {}) as Dictionary
	if not snapshot.is_empty():
		return snapshot.duplicate(true)
	var chunk_view: ChunkView = _chunk_views.get(canonical_chunk) as ChunkView
	if chunk_view != null:
		return chunk_view.get_mountain_contour_runtime_debug_snapshot()
	return {
		"ready": false,
		"chunk_coord": canonical_chunk,
		"visual_ready": false,
		"collision_ready": false,
		"has_visual_layer": false,
		"missing_cache_blocks": true,
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

func get_effective_tile_data_at_world(world_pos: Vector2) -> Dictionary:
	return _get_tile_data(world_pos).duplicate()

func is_raw_tile_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	return bool(tile_data.get("walkable", false))

func is_walkable_at_world(world_pos: Vector2) -> bool:
	return is_capsule_walkable_at_world(world_pos, 0.0)

func is_capsule_walkable_at_world(world_pos: Vector2, radius_px: float) -> bool:
	var radius: float = maxf(0.0, radius_px)
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	var contour_query: Dictionary = _query_mountain_contour_collision_for_capsule(world_pos, radius)
	if bool(contour_query.get("blocked", false)):
		return false
	return _is_raw_capsule_walkable_for_non_contour_terrain(world_pos, radius)

func is_movement_blocked_at_world(world_pos: Vector2) -> bool:
	return not is_capsule_walkable_at_world(world_pos, 0.0)

func move_capsule_with_slide(start: Vector2, motion: Vector2, radius_px: float) -> Dictionary:
	return move_capsule_with_contour_slide(start, motion, radius_px)

func move_capsule_with_contour_slide(start: Vector2, motion: Vector2, radius_px: float) -> Dictionary:
	var radius: float = maxf(0.0, radius_px)
	if not is_capsule_walkable_at_world(start, radius):
		return _blocked_capsule_motion_result(start, motion)
	if motion.is_zero_approx():
		return _free_capsule_motion_result(start, motion)

	var target: Vector2 = start + motion
	if is_capsule_walkable_at_world(target, radius):
		return _free_capsule_motion_result(target, motion)

	var contour_slide: Dictionary = _slide_capsule_against_mountain_contour(start, motion, radius)
	if not contour_slide.is_empty():
		var contour_final_position: Vector2 = contour_slide.get("final_position", start) as Vector2
		if is_capsule_walkable_at_world(contour_final_position, radius):
			return contour_slide
		return _blocked_capsule_motion_result(start, motion)

	return _slide_capsule_against_raw_tiles(start, motion, radius)

func is_placement_shape_clear(world_shape: Variant) -> bool:
	var shape_aabb: Rect2 = _world_shape_aabb(world_shape)
	if shape_aabb.size.x <= 0.0 or shape_aabb.size.y <= 0.0:
		return false
	for chunk_coord: Vector2i in _resolve_mountain_contour_collision_query_chunks_for_rect(shape_aabb):
		if not _chunk_packets.has(chunk_coord):
			continue
		var cache: MountainContourCollisionCache = _mountain_contour_collision_caches.get(chunk_coord) as MountainContourCollisionCache
		var snapshot: Dictionary = _mountain_contour_runtime_debug_snapshots.get(chunk_coord, {}) as Dictionary
		var collision_ready: bool = cache != null and bool(snapshot.get("collision_ready", false))
		if collision_ready:
			var local_shape: Variant = _world_shape_to_chunk_local(world_shape, chunk_coord)
			if cache.intersects_building_footprint(local_shape):
				return false
			continue
		if _world_shape_intersects_contour_owned_mountain_terrain_in_chunk(
			world_shape,
			shape_aabb,
			chunk_coord
		):
			return false
	return _is_world_shape_clear_for_non_contour_terrain(world_shape, shape_aabb)

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
	var mountain_contour_dirty_update: Dictionary = {}
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		mountain_contour_dirty_update = _refresh_mountain_contour_runtime_after_mining(
			chunk_coord,
			local_coord,
			terrain_id,
			WorldRuntimeConstants.TERRAIN_PLAINS_DUG
		)
		var event_bus: Object = _get_event_bus()
		if event_bus != null:
			event_bus.emit_signal(
				"mountain_tile_mined",
				_chunk_local_to_tile(chunk_coord, local_coord),
				terrain_id,
				WorldRuntimeConstants.TERRAIN_PLAINS_DUG
			)
	var result: Dictionary = {
		"success": true,
		"item_id": "base:scrap",
		"amount": 1,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
	}
	if not mountain_contour_dirty_update.is_empty():
		result["mountain_contour_dirty_update"] = mountain_contour_dirty_update
	return result

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
	var player_authority: Object = _get_player_authority()
	if player_authority == null:
		return
	var player_pos: Vector2 = player_authority.call("get_local_player_position") as Vector2
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
		_refresh_mountain_contour_runtime_around_chunk(chunk_coord)
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
		_refresh_mountain_contour_runtime_around_chunk(_active_publish_chunk)
		_refresh_debug_visuals_for_chunk(_active_publish_chunk)
		active_view.visible = true
		var event_bus: Object = _get_event_bus()
		if event_bus != null:
			event_bus.emit_signal("chunk_loaded", _active_publish_chunk)
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
		_mountain_contour_collision_caches.erase(chunk_coord)
		_mountain_contour_runtime_debug_snapshots.erase(chunk_coord)
		_requested_chunks.erase(chunk_coord)
		_pending_publish_queue.erase(chunk_coord)
		_handle_cover_chunk_unloaded(chunk_coord)
		_refresh_mountain_contour_runtime_around_chunk(chunk_coord)
		var event_bus: Object = _get_event_bus()
		if event_bus != null:
			event_bus.emit_signal("chunk_unloaded", chunk_coord)
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

func _query_mountain_contour_collision_for_capsule(world_pos: Vector2, radius_px: float, motion: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary = {
		"blocked": false,
		"missing_cache": false,
		"checked_chunks": [],
	}
	var checked_chunks: Array[Vector2i] = []
	for chunk_coord: Vector2i in _resolve_mountain_contour_collision_query_chunks(world_pos, radius_px, motion):
		if not _chunk_packets.has(chunk_coord):
			continue
		var cache: MountainContourCollisionCache = _mountain_contour_collision_caches.get(chunk_coord) as MountainContourCollisionCache
		var snapshot: Dictionary = _mountain_contour_runtime_debug_snapshots.get(chunk_coord, {}) as Dictionary
		var collision_ready: bool = cache != null and bool(snapshot.get("collision_ready", false))
		if collision_ready:
			checked_chunks.append(chunk_coord)
			var local_pos: Vector2 = _world_to_chunk_local_position(world_pos, chunk_coord)
			if cache.is_capsule_blocked(local_pos, radius_px):
				result["blocked"] = true
				result["checked_chunks"] = checked_chunks
				return result
			continue
		if _missing_contour_cache_blocks_capsule_query(chunk_coord, world_pos, radius_px, motion):
			result["blocked"] = true
			result["missing_cache"] = true
			checked_chunks.append(chunk_coord)
			result["checked_chunks"] = checked_chunks
			return result
	result["checked_chunks"] = checked_chunks
	return result

func _resolve_mountain_contour_collision_query_chunks(world_pos: Vector2, radius_px: float, motion: Vector2 = Vector2.ZERO) -> Array[Vector2i]:
	var query_margin: float = _resolve_mountain_contour_collision_query_margin_px(radius_px)
	var target_pos: Vector2 = world_pos + motion
	var min_pos := Vector2(
		minf(world_pos.x, target_pos.x) - query_margin,
		minf(world_pos.y, target_pos.y) - query_margin
	)
	var max_pos := Vector2(
		maxf(world_pos.x, target_pos.x) + query_margin,
		maxf(world_pos.y, target_pos.y) + query_margin
	)
	var min_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(WorldRuntimeConstants.world_to_tile(min_pos))
	var max_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(WorldRuntimeConstants.world_to_tile(max_pos))
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	for chunk_y: int in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x: int in range(min_chunk.x, max_chunk.x + 1):
			var chunk_coord: Vector2i = _canonicalize_chunk_coord(Vector2i(chunk_x, chunk_y))
			if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
				continue
			if seen.has(chunk_coord):
				continue
			seen[chunk_coord] = true
			result.append(chunk_coord)
	return result

func _resolve_mountain_contour_collision_query_chunks_for_rect(world_rect: Rect2) -> Array[Vector2i]:
	var query_margin: float = _resolve_mountain_contour_collision_query_margin_px(0.0)
	var min_pos: Vector2 = world_rect.position - Vector2(query_margin, query_margin)
	var max_pos: Vector2 = world_rect.position + world_rect.size + Vector2(query_margin, query_margin)
	var min_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(WorldRuntimeConstants.world_to_tile(min_pos))
	var max_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(WorldRuntimeConstants.world_to_tile(max_pos))
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	for chunk_y: int in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x: int in range(min_chunk.x, max_chunk.x + 1):
			var chunk_coord: Vector2i = _canonicalize_chunk_coord(Vector2i(chunk_x, chunk_y))
			if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
				continue
			if seen.has(chunk_coord):
				continue
			seen[chunk_coord] = true
			result.append(chunk_coord)
	return result

func _resolve_mountain_contour_collision_query_margin_px(radius_px: float) -> float:
	var style_margin: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	if _mountain_contour_style != null:
		style_margin = maxf(
			_mountain_contour_style.south_height_px,
			maxf(_mountain_contour_style.side_height_px, _mountain_contour_style.rim_width_px)
		)
	return maxf(maxf(0.0, radius_px), style_margin + 4.0)

func _world_to_chunk_local_position(world_pos: Vector2, chunk_coord: Vector2i) -> Vector2:
	return world_pos - WorldRuntimeConstants.chunk_origin_px(chunk_coord)

func _world_shape_to_chunk_local(world_shape: Variant, chunk_coord: Vector2i) -> Variant:
	var chunk_origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	if world_shape is Rect2:
		var rect: Rect2 = world_shape as Rect2
		return Rect2(rect.position - chunk_origin, rect.size)
	if world_shape is PackedVector2Array:
		var polygon := PackedVector2Array()
		for point: Vector2 in world_shape as PackedVector2Array:
			polygon.append(point - chunk_origin)
		return polygon
	if world_shape is Array:
		var polygon := PackedVector2Array()
		for point_variant: Variant in world_shape:
			if point_variant is Vector2:
				polygon.append((point_variant as Vector2) - chunk_origin)
		return polygon
	return Rect2()

func _world_shape_aabb(world_shape: Variant) -> Rect2:
	if world_shape is Rect2:
		var rect: Rect2 = world_shape as Rect2
		return rect.abs()
	if world_shape is PackedVector2Array:
		return _polygon_aabb(world_shape as PackedVector2Array)
	if world_shape is Array:
		var polygon := PackedVector2Array()
		for point_variant: Variant in world_shape:
			if point_variant is Vector2:
				polygon.append(point_variant as Vector2)
		return _polygon_aabb(polygon)
	return Rect2()

func _polygon_aabb(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var min_x: float = polygon[0].x
	var min_y: float = polygon[0].y
	var max_x: float = polygon[0].x
	var max_y: float = polygon[0].y
	for point: Vector2 in polygon:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _missing_contour_cache_blocks_capsule_query(
	chunk_coord: Vector2i,
	world_pos: Vector2,
	radius_px: float,
	motion: Vector2 = Vector2.ZERO
) -> bool:
	return _world_rect_intersects_contour_owned_mountain_terrain_in_chunk(
		_build_capsule_query_rect(world_pos, radius_px, motion),
		chunk_coord
	)

func _build_capsule_query_rect(world_pos: Vector2, radius_px: float, motion: Vector2 = Vector2.ZERO) -> Rect2:
	var radius: float = maxf(0.0, radius_px)
	var target_pos: Vector2 = world_pos + motion
	var min_pos := Vector2(
		minf(world_pos.x, target_pos.x) - radius,
		minf(world_pos.y, target_pos.y) - radius
	)
	var max_pos := Vector2(
		maxf(world_pos.x, target_pos.x) + radius,
		maxf(world_pos.y, target_pos.y) + radius
	)
	return Rect2(min_pos, max_pos - min_pos)

func _world_shape_intersects_contour_owned_mountain_terrain_in_chunk(
	_world_shape: Variant,
	shape_aabb: Rect2,
	chunk_coord: Vector2i
) -> bool:
	return _world_rect_intersects_contour_owned_mountain_terrain_in_chunk(shape_aabb, chunk_coord)

func _world_rect_intersects_contour_owned_mountain_terrain_in_chunk(
	world_rect: Rect2,
	chunk_coord: Vector2i
) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _chunk_packets.has(chunk_coord):
		return false
	var rect: Rect2 = world_rect.abs()
	var max_pos: Vector2 = rect.position
	if rect.size.x > 0.0 or rect.size.y > 0.0:
		max_pos = rect.position + rect.size - Vector2(0.001, 0.001)
	var min_tile: Vector2i = WorldRuntimeConstants.world_to_tile(rect.position)
	var max_tile: Vector2i = WorldRuntimeConstants.world_to_tile(max_pos)
	for tile_y: int in range(min_tile.y, max_tile.y + 1):
		for tile_x: int in range(min_tile.x, max_tile.x + 1):
			var world_tile: Vector2i = _canonicalize_tile_coord(Vector2i(tile_x, tile_y))
			if WorldRuntimeConstants.tile_to_chunk(world_tile) != chunk_coord:
				continue
			if _is_contour_owned_mountain_terrain_sample(_get_loaded_tile_data_no_enqueue(world_tile)):
				return true
	return false

func _is_raw_capsule_walkable_for_non_contour_terrain(world_pos: Vector2, radius_px: float) -> bool:
	for sample_pos: Vector2 in _build_capsule_walkability_sample_points(world_pos, radius_px):
		var sample: Dictionary = _get_tile_data(sample_pos)
		if not bool(sample.get("ready", false)):
			return false
		if _is_contour_owned_mountain_terrain_sample(sample):
			continue
		if not bool(sample.get("walkable", false)):
			return false
	return true

func _is_world_shape_clear_for_non_contour_terrain(_world_shape: Variant, shape_aabb: Rect2) -> bool:
	var max_pos: Vector2 = shape_aabb.position + shape_aabb.size - Vector2(0.001, 0.001)
	var min_tile: Vector2i = WorldRuntimeConstants.world_to_tile(shape_aabb.position)
	var max_tile: Vector2i = WorldRuntimeConstants.world_to_tile(max_pos)
	for tile_y: int in range(min_tile.y, max_tile.y + 1):
		for tile_x: int in range(min_tile.x, max_tile.x + 1):
			var sample: Dictionary = _get_tile_data(WorldRuntimeConstants.tile_to_world_center(Vector2i(tile_x, tile_y)))
			if not bool(sample.get("ready", false)):
				return false
			if _is_contour_owned_mountain_terrain_sample(sample):
				continue
			if not bool(sample.get("walkable", false)):
				return false
	return true

func _build_capsule_walkability_sample_points(world_pos: Vector2, radius_px: float) -> Array[Vector2]:
	var radius: float = maxf(0.0, radius_px)
	if radius <= 0.001:
		return [world_pos]
	var diagonal: float = radius * 0.70710678118
	return [
		world_pos,
		world_pos + Vector2(-radius, 0.0),
		world_pos + Vector2(radius, 0.0),
		world_pos + Vector2(0.0, -radius),
		world_pos + Vector2(0.0, radius),
		world_pos + Vector2(-diagonal, -diagonal),
		world_pos + Vector2(diagonal, -diagonal),
		world_pos + Vector2(-diagonal, diagonal),
		world_pos + Vector2(diagonal, diagonal),
	]

func _slide_capsule_against_mountain_contour(start: Vector2, motion: Vector2, radius_px: float) -> Dictionary:
	for chunk_coord: Vector2i in _resolve_mountain_contour_collision_query_chunks(start, radius_px, motion):
		if not _chunk_packets.has(chunk_coord):
			continue
		var cache: MountainContourCollisionCache = _mountain_contour_collision_caches.get(chunk_coord) as MountainContourCollisionCache
		var snapshot: Dictionary = _mountain_contour_runtime_debug_snapshots.get(chunk_coord, {}) as Dictionary
		var collision_ready: bool = cache != null and bool(snapshot.get("collision_ready", false))
		if not collision_ready:
			if _missing_contour_cache_blocks_capsule_query(chunk_coord, start, radius_px, motion):
				return _blocked_capsule_motion_result(start, motion)
			continue
		var local_start: Vector2 = _world_to_chunk_local_position(start, chunk_coord)
		var local_target: Vector2 = local_start + motion
		if not cache.is_capsule_blocked(local_target, radius_px):
			continue
		var local_slide: Dictionary = cache.slide_capsule(local_start, motion, radius_px)
		return _local_capsule_slide_to_world(local_slide, start, motion, chunk_coord)
	return {}

func _slide_capsule_against_raw_tiles(start: Vector2, motion: Vector2, radius_px: float) -> Dictionary:
	var final_position: Vector2 = start
	var motion_applied := Vector2.ZERO
	var horizontal_motion := Vector2(motion.x, 0.0)
	if not horizontal_motion.is_zero_approx() and is_capsule_walkable_at_world(start + horizontal_motion, radius_px):
		final_position += horizontal_motion
		motion_applied += horizontal_motion
	var vertical_motion := Vector2(0.0, motion.y)
	if not vertical_motion.is_zero_approx() and is_capsule_walkable_at_world(final_position + vertical_motion, radius_px):
		final_position += vertical_motion
		motion_applied += vertical_motion
	if motion_applied.is_zero_approx():
		return _blocked_capsule_motion_result(start, motion)
	return {
		"blocked": false,
		"collided": true,
		"final_position": final_position,
		"motion_applied": motion_applied,
		"remainder": motion - motion_applied,
		"normal": Vector2.ZERO,
	}

func _local_capsule_slide_to_world(local_slide: Dictionary, start: Vector2, motion: Vector2, chunk_coord: Vector2i) -> Dictionary:
	var chunk_origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	var local_final_position: Vector2 = local_slide.get("final_position", start - chunk_origin) as Vector2
	var final_position: Vector2 = local_final_position + chunk_origin
	var motion_applied: Vector2 = final_position - start
	return {
		"blocked": bool(local_slide.get("blocked", false)),
		"collided": bool(local_slide.get("collided", true)),
		"final_position": final_position,
		"motion_applied": motion_applied,
		"remainder": motion - motion_applied,
		"normal": local_slide.get("normal", Vector2.ZERO) as Vector2,
	}

func _blocked_capsule_motion_result(start: Vector2, motion: Vector2) -> Dictionary:
	return {
		"blocked": true,
		"collided": true,
		"final_position": start,
		"motion_applied": Vector2.ZERO,
		"remainder": motion,
		"normal": Vector2.ZERO,
	}

func _free_capsule_motion_result(final_position: Vector2, motion: Vector2) -> Dictionary:
	return {
		"blocked": false,
		"collided": false,
		"final_position": final_position,
		"motion_applied": motion,
		"remainder": Vector2.ZERO,
		"normal": Vector2.ZERO,
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
	var world_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_coord)
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
	_mountain_contour_collision_caches.clear()
	_mountain_contour_runtime_debug_snapshots.clear()
	_mountain_contour_runtime_revision = 0
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
	var player_authority: Object = _get_player_authority()
	var player: Node2D = null
	if player_authority != null:
		player = player_authority.call("get_local_player") as Node2D
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
	var player_authority: Object = _get_player_authority()
	if player_authority == null or player_authority.call("get_local_player") == null:
		_active_cover_mountain_id = 0
		_active_cover_component_id = 0
		return {
			"state_changed": previous_mountain_id != 0 or previous_component_id != 0,
			"previous_mountain_id": previous_mountain_id,
			"previous_component_id": previous_component_id,
			"mountain_id": 0,
			"component_id": 0,
		}
	var player_position: Vector2 = player_authority.call("get_local_player_position") as Vector2
	var player_tile: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(player_position))
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

func _refresh_mountain_contour_runtime_around_chunk(center_chunk_coord: Vector2i) -> void:
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var chunk_coord: Vector2i = _canonicalize_chunk_coord(center_chunk_coord + Vector2i(offset_x, offset_y))
			if _chunk_views.has(chunk_coord):
				_rebuild_mountain_contour_runtime_for_chunk(chunk_coord)

func _refresh_mountain_contour_runtime_for_loaded_chunks(dirty_reason: StringName) -> Dictionary:
	var loaded_chunks: Array[Vector2i] = _dictionary_vector2i_keys(_chunk_views)
	var refresh_start_usec: int = Time.get_ticks_usec()
	if loaded_chunks.is_empty():
		return {
			"chunk_count": 0,
			"refresh_usec": Time.get_ticks_usec() - refresh_start_usec,
			"chunk_updates": [],
		}
	var runtime_revision: int = _next_mountain_contour_runtime_revision()
	var chunk_updates: Array[Dictionary] = []
	for chunk_coord: Vector2i in loaded_chunks:
		var telemetry: Dictionary = _rebuild_mountain_contour_runtime_for_chunk(
			chunk_coord,
			runtime_revision,
			loaded_chunks.size(),
			dirty_reason
		)
		if not telemetry.is_empty():
			chunk_updates.append(telemetry)
	return {
		"chunk_count": loaded_chunks.size(),
		"refresh_usec": Time.get_ticks_usec() - refresh_start_usec,
		"chunk_updates": chunk_updates,
	}

func _refresh_mountain_contour_runtime_after_mining(
	chunk_coord: Vector2i,
	local_coord: Vector2i,
	old_terrain_id: int,
	new_terrain_id: int
) -> Dictionary:
	if not _is_diggable_surface_terrain(old_terrain_id):
		return {}
	if _is_diggable_surface_terrain(new_terrain_id):
		return {}
	var affected_chunks: Array[Vector2i] = _resolve_mountain_contour_dirty_chunks_for_tile(
		chunk_coord,
		local_coord
	)
	if affected_chunks.is_empty():
		return {}
	var runtime_revision: int = _next_mountain_contour_runtime_revision()
	var update_start_usec: int = Time.get_ticks_usec()
	var chunk_updates: Array[Dictionary] = []
	var visual_apply_usec: int = 0
	var collision_apply_usec: int = 0
	for affected_chunk: Vector2i in affected_chunks:
		var chunk_telemetry: Dictionary = _rebuild_mountain_contour_runtime_for_chunk(
			affected_chunk,
			runtime_revision,
			affected_chunks.size(),
			&"mining_dirty"
		)
		if chunk_telemetry.is_empty():
			continue
		chunk_updates.append(chunk_telemetry)
		visual_apply_usec += int(chunk_telemetry.get("visual_apply_usec", 0))
		collision_apply_usec += int(chunk_telemetry.get("collision_apply_usec", 0))
	return {
		"runtime_revision": runtime_revision,
		"affected_chunk_count": affected_chunks.size(),
		"affected_chunks": affected_chunks,
		"contour_rebuild_usec": Time.get_ticks_usec() - update_start_usec,
		"visual_apply_usec": visual_apply_usec,
		"collision_apply_usec": collision_apply_usec,
		"chunk_updates": chunk_updates,
	}

func _resolve_mountain_contour_dirty_chunks_for_tile(
	chunk_coord: Vector2i,
	local_coord: Vector2i
) -> Array[Vector2i]:
	var affected_chunks: Dictionary = {}
	_add_mountain_contour_dirty_chunk_if_loaded(affected_chunks, chunk_coord)
	var x_offsets: Array[int] = []
	var y_offsets: Array[int] = []
	if local_coord.x == 0:
		x_offsets.append(-1)
	elif local_coord.x == WorldRuntimeConstants.CHUNK_SIZE - 1:
		x_offsets.append(1)
	if local_coord.y == 0:
		y_offsets.append(-1)
	elif local_coord.y == WorldRuntimeConstants.CHUNK_SIZE - 1:
		y_offsets.append(1)
	for x_offset: int in x_offsets:
		_add_mountain_contour_dirty_chunk_if_loaded(
			affected_chunks,
			chunk_coord + Vector2i(x_offset, 0)
		)
	for y_offset: int in y_offsets:
		_add_mountain_contour_dirty_chunk_if_loaded(
			affected_chunks,
			chunk_coord + Vector2i(0, y_offset)
		)
	for x_offset: int in x_offsets:
		for y_offset: int in y_offsets:
			_add_mountain_contour_dirty_chunk_if_loaded(
				affected_chunks,
				chunk_coord + Vector2i(x_offset, y_offset)
			)
	return _dictionary_vector2i_keys(affected_chunks)

func _add_mountain_contour_dirty_chunk_if_loaded(affected_chunks: Dictionary, chunk_coord: Vector2i) -> void:
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(canonical_chunk.y):
		return
	if not _chunk_views.has(canonical_chunk):
		return
	affected_chunks[canonical_chunk] = true

func _rebuild_mountain_contour_runtime_for_chunk(
	chunk_coord: Vector2i,
	runtime_revision: int = -1,
	affected_chunk_count: int = 1,
	dirty_reason: StringName = &"chunk_rebuild"
) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if chunk_view == null:
		return {}
	if runtime_revision < 0:
		runtime_revision = _next_mountain_contour_runtime_revision()
	var rebuild_start_usec: int = Time.get_ticks_usec()
	var telemetry: Dictionary = {
		"runtime_revision": runtime_revision,
		"chunk_coord": chunk_coord,
		"dirty_reason": String(dirty_reason),
		"affected_chunk_count": affected_chunk_count,
		"contour_rebuild_usec": 0,
		"visual_apply_usec": 0,
		"collision_apply_usec": 0,
	}
	var cache := MountainContourCollisionCache.new()
	_mountain_contour_collision_caches[chunk_coord] = cache
	var halo_state: Dictionary = _build_mountain_contour_runtime_halo_state(chunk_coord)
	var style: MountainContourStyle = _ensure_mountain_contour_style()
	if style == null:
		var unavailable_visual_apply_start_usec: int = Time.get_ticks_usec()
		chunk_view.apply_mountain_contour_runtime_data(
			style,
			{"ready": false},
			false,
			halo_state,
			_mountain_contour_runtime_visible
		)
		telemetry["visual_apply_usec"] = Time.get_ticks_usec() - unavailable_visual_apply_start_usec
		telemetry["contour_rebuild_usec"] = Time.get_ticks_usec() - rebuild_start_usec
		_store_mountain_contour_runtime_debug_snapshot(
			chunk_coord,
			chunk_view,
			cache,
			false,
			halo_state,
			telemetry
		)
		return telemetry
	var runtime_result: Dictionary = _build_native_mountain_contour_runtime_for_chunk(chunk_coord, halo_state, style)
	var result_ready: bool = bool(runtime_result.get("ready", false))
	if result_ready:
		halo_state["loop_count"] = (runtime_result.get("collision_loops", []) as Array).size()
		halo_state["aabb_count"] = (runtime_result.get("collision_aabbs", []) as Array).size()
	var collision_ready: bool = result_ready and bool(halo_state.get("ready", false))
	if collision_ready:
		var collision_apply_start_usec: int = Time.get_ticks_usec()
		cache.configure(
			chunk_coord,
			runtime_result.get("collision_loops", []) as Array,
			runtime_result.get("collision_aabbs", []) as Array
		)
		telemetry["collision_apply_usec"] = Time.get_ticks_usec() - collision_apply_start_usec
	var visual_apply_start_usec: int = Time.get_ticks_usec()
	chunk_view.apply_mountain_contour_runtime_data(
		style,
		runtime_result,
		collision_ready,
		halo_state,
		_mountain_contour_runtime_visible
	)
	telemetry["visual_apply_usec"] = Time.get_ticks_usec() - visual_apply_start_usec
	telemetry["contour_rebuild_usec"] = Time.get_ticks_usec() - rebuild_start_usec
	_store_mountain_contour_runtime_debug_snapshot(
		chunk_coord,
		chunk_view,
		cache,
		collision_ready,
		halo_state,
		telemetry
	)
	return telemetry

func _store_mountain_contour_runtime_debug_snapshot(
	chunk_coord: Vector2i,
	chunk_view: ChunkView,
	cache: MountainContourCollisionCache,
	collision_ready: bool,
	halo_state: Dictionary,
	telemetry: Dictionary = {}
) -> void:
	var snapshot: Dictionary = chunk_view.get_mountain_contour_runtime_debug_snapshot()
	snapshot["ready"] = bool(snapshot.get("visual_ready", false)) and collision_ready
	snapshot["chunk_coord"] = chunk_coord
	snapshot["collision_ready"] = collision_ready
	var runtime_revision: int = int(telemetry.get("runtime_revision", -1))
	snapshot["runtime_revision"] = runtime_revision
	snapshot["visual_revision"] = runtime_revision if bool(snapshot.get("visual_ready", false)) else -1
	snapshot["collision_revision"] = runtime_revision if collision_ready else -1
	snapshot["dirty_reason"] = str(telemetry.get("dirty_reason", ""))
	snapshot["affected_chunk_count"] = int(telemetry.get("affected_chunk_count", 0))
	snapshot["contour_rebuild_usec"] = int(telemetry.get("contour_rebuild_usec", 0))
	snapshot["visual_apply_usec"] = int(telemetry.get("visual_apply_usec", 0))
	snapshot["collision_apply_usec"] = int(telemetry.get("collision_apply_usec", 0))
	snapshot["missing_cache_blocks"] = not collision_ready and cache.is_point_blocked(Vector2.ZERO)
	snapshot["loaded_seam_neighbours"] = (halo_state.get("loaded_seam_neighbours", []) as Array).duplicate()
	snapshot["missing_required_seam_neighbours"] = (halo_state.get("missing_required_seam_neighbours", []) as Array).duplicate()
	snapshot["optional_missing_seam_neighbours"] = (halo_state.get("optional_missing_seam_neighbours", []) as Array).duplicate()
	_mountain_contour_runtime_debug_snapshots[chunk_coord] = snapshot

func _next_mountain_contour_runtime_revision() -> int:
	_mountain_contour_runtime_revision += 1
	return _mountain_contour_runtime_revision

func _build_native_mountain_contour_runtime_for_chunk(
	chunk_coord: Vector2i,
	halo_state: Dictionary,
	style: MountainContourStyle
) -> Dictionary:
	var world_core: Object = _get_contour_world_core("build_mountain_contour_runtime")
	if world_core == null:
		return {"ready": false}
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_runtime",
		halo_state.get("solid_halo", PackedByteArray()) as PackedByteArray,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		_build_mountain_contour_style_params(style)
	)
	if result_variant is Dictionary:
		return result_variant as Dictionary
	push_error("WorldCore.build_mountain_contour_runtime returned non-dictionary result for chunk %s." % [str(chunk_coord)])
	return {"ready": false}

func _build_mountain_contour_runtime_halo_state(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(halo_side * halo_side)
	var local_solid_mask: PackedByteArray = _build_local_mountain_solid_mask(chunk_coord)
	var loaded_seam_neighbours: Dictionary = {}
	var missing_required_seam_neighbours: Dictionary = {}
	var optional_missing_seam_neighbours: Dictionary = {}
	var ready: bool = true
	for halo_y: int in range(halo_side):
		for halo_x: int in range(halo_side):
			var local_coord := Vector2i(halo_x - 1, halo_y - 1)
			var halo_index: int = halo_y * halo_side + halo_x
			if WorldRuntimeConstants.is_local_coord_valid(local_coord):
				var local_index: int = WorldRuntimeConstants.local_to_index(local_coord)
				if local_index >= 0 and local_index < local_solid_mask.size():
					solid_halo[halo_index] = local_solid_mask[local_index]
				continue
			var world_tile: Vector2i = _canonicalize_tile_coord(_chunk_local_to_tile(chunk_coord, local_coord))
			var seam_chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(world_tile)
			var sample: Dictionary = _get_loaded_tile_data_no_enqueue(world_tile)
			if bool(sample.get("ready", false)):
				loaded_seam_neighbours[seam_chunk_coord] = true
				if _is_mountain_contour_solid_sample(sample):
					solid_halo[halo_index] = 1
				continue
			if _is_halo_sample_required(local_coord, local_solid_mask):
				missing_required_seam_neighbours[seam_chunk_coord] = true
				ready = false
			else:
				optional_missing_seam_neighbours[seam_chunk_coord] = true
	return {
		"ready": ready,
		"chunk_coord": chunk_coord,
		"halo_side": halo_side,
		"solid_halo": solid_halo,
		"solid_sample_count": _count_solid_values(solid_halo),
		"loaded_seam_neighbours": _dictionary_vector2i_keys(loaded_seam_neighbours),
		"missing_required_seam_neighbours": _dictionary_vector2i_keys(missing_required_seam_neighbours),
		"optional_missing_seam_neighbours": _dictionary_vector2i_keys(optional_missing_seam_neighbours),
		"loop_count": 0,
		"aabb_count": 0,
	}

func _is_halo_sample_required(local_coord: Vector2i, local_solid_mask: PackedByteArray) -> bool:
	var sample_local: Vector2i = Vector2i(
		clampi(local_coord.x, 0, WorldRuntimeConstants.CHUNK_SIZE - 1),
		clampi(local_coord.y, 0, WorldRuntimeConstants.CHUNK_SIZE - 1)
	)
	var sample_index: int = WorldRuntimeConstants.local_to_index(sample_local)
	return sample_index >= 0 \
		and sample_index < local_solid_mask.size() \
		and int(local_solid_mask[sample_index]) != 0

func _count_solid_values(values: PackedByteArray) -> int:
	var count: int = 0
	for value: int in values:
		if value != 0:
			count += 1
	return count

func _build_mountain_contour_style_params(style: MountainContourStyle) -> Dictionary:
	return style.to_runtime_geometry_params()

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
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if bool(sample.get("walkable", true)):
		return false
	var mountain_id: int = int(sample.get("mountain_id", 0))
	var mountain_flags: int = int(sample.get("mountain_flags", 0))
	return mountain_id > 0 \
		and (mountain_flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0

func _is_contour_owned_mountain_terrain_sample(sample: Dictionary) -> bool:
	if not bool(sample.get("ready", false)):
		return false
	var terrain_id: int = int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	return not bool(sample.get("walkable", true))

func _get_contour_world_core(required_method: String = "build_mountain_contour_debug") -> Object:
	if _contour_world_core != null:
		if required_method.is_empty() or _contour_world_core.has_method(required_method):
			return _contour_world_core
		push_error("WorldCore missing %s; mountain contour runtime disabled." % [required_method])
		_contour_world_core = null
		return null
	_contour_world_core = ClassDB.instantiate("WorldCore")
	assert(_contour_world_core != null, "WorldCore required for mountain contour runtime - build GDExtension first")
	if _contour_world_core == null:
		return null
	if not required_method.is_empty() and not _contour_world_core.has_method(required_method):
		push_error("WorldCore missing %s; mountain contour runtime disabled." % [required_method])
		_contour_world_core = null
		return null
	return _contour_world_core

func _load_default_mountain_contour_style() -> void:
	if _mountain_contour_style_registry.load_default_styles():
		_mountain_contour_style = _mountain_contour_style_registry.require_style(&"mountain")
	else:
		_mountain_contour_style = null

func _ensure_mountain_contour_style() -> MountainContourStyle:
	if _mountain_contour_style != null:
		return _mountain_contour_style
	_load_default_mountain_contour_style()
	return _mountain_contour_style

func _get_event_bus() -> Object:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

func _get_player_authority() -> Object:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/PlayerAuthority")

func _get_frame_budget_dispatcher() -> Object:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/FrameBudgetDispatcher")

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
	var player_authority: Object = _get_player_authority()
	var player: Node2D = null
	if player_authority != null:
		player = player_authority.call("get_local_player") as Node2D
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
