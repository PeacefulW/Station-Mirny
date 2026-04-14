class_name ChunkManager
extends Node2D

## Менеджер чанков мира.
## Загружает чанки, рендерит землю/горы и выполняет mining горной породы.

const RuntimeWorkTypes = preload("res://core/runtime/runtime_work_types.gd")
const ChunkFloraBuilderScript = preload("res://core/systems/world/chunk_flora_builder.gd")
const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")
const ChunkFinalPacketScript = preload("res://core/systems/world/chunk_final_packet.gd")
const ChunkDebugSystem = preload("res://core/systems/world/chunk_debug_system.gd")
const ChunkStreamingService = preload("res://core/systems/world/chunk_streaming_service.gd")
const ChunkSurfacePayloadCache = preload("res://core/systems/world/chunk_surface_payload_cache.gd")
const ChunkSeamService = preload("res://core/systems/world/chunk_seam_service.gd")
const ChunkVisualScheduler = preload("res://core/systems/world/chunk_visual_scheduler.gd")
const ChunkTopologyService = preload("res://core/systems/world/chunk_topology_service.gd")
const ChunkBootPipeline = preload("res://core/systems/world/chunk_boot_pipeline.gd")
const TravelStateResolver = preload("res://core/systems/world/travel_state_resolver.gd")
const ViewEnvelopeResolver = preload("res://core/systems/world/view_envelope_resolver.gd")
const FrontierPlanner = preload("res://core/systems/world/frontier_planner.gd")
const FrontierScheduler = preload("res://core/systems/world/frontier_scheduler.gd")
const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")
const NATIVE_TOPOLOGY_BUILDER_CLASS: StringName = &"MountainTopologyBuilder"
const NATIVE_LOADED_OPEN_POCKET_QUERY_CLASS: StringName = &"LoadedOpenPocketQuery"
const JOB_STREAMING_LOAD: StringName = &"chunk_manager.streaming_load"
const JOB_STREAMING_REDRAW: StringName = &"chunk_manager.streaming_redraw"
const JOB_TOPOLOGY: StringName = &"chunk_manager.topology_rebuild"
const _CARDINAL_DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MAX_LOAD_REQUESTS_SCANNED_PER_TICK: int = 16
const MAX_RELEVANT_LOAD_QUEUE_OVERSCAN: int = 8
const SURFACE_PAYLOAD_CACHE_LIMIT: int = 192
const INVALID_CHUNK_STATE_KEY: Vector3i = Vector3i(999999, 999999, 999999)
const INVALID_Z_LEVEL: int = 999999

enum VisualTaskKind {
	TASK_FIRST_PASS,
	TASK_FULL_REDRAW,
	TASK_BORDER_FIX,
	TASK_COSMETIC,
}

enum VisualPriorityBand {
	TERRAIN_FAST,
	TERRAIN_URGENT,
	TERRAIN_NEAR,
	FULL_NEAR,
	BORDER_FIX_NEAR,
	BORDER_FIX_FAR,
	FULL_FAR,
	COSMETIC,
}

enum VisualTaskRunState {
	DROPPED,
	REQUEUE,
	COMPLETED,
}

enum VisualComputeSubmitState {
	UNAVAILABLE,
	SUBMITTED,
	BLOCKED,
}

const BORDER_FIX_REDRAW_MICRO_BATCH_TILES: int = 4
const PLAYER_CHUNK_DIAG_LOG_INTERVAL_MSEC: int = 2000
const PLAYER_CHUNK_DIAG_BLOCKED_AGE_MS: float = 250.0
const PLAYER_CHUNK_DIAG_SPIKE_MS: float = 12.0
const VISUAL_ADAPTIVE_APPLY_MIN_MS: float = 0.25
const VISUAL_ADAPTIVE_APPLY_MAX_MS: float = 1.25
const VISUAL_ADAPTIVE_FEEDBACK_BLEND: float = 0.55
const VISUAL_ADAPTIVE_MIN_TILES: int = 2
const VISUAL_ADAPTIVE_MIN_BORDER_TILES: int = 1
const VISUAL_ADAPTIVE_FAST_SAFETY: float = 0.30
const VISUAL_ADAPTIVE_URGENT_SAFETY: float = 0.35
const VISUAL_ADAPTIVE_NEAR_SAFETY: float = 0.40
const VISUAL_ADAPTIVE_FAR_SAFETY: float = 0.45
const VISUAL_FAST_PHASE_TILE_CAP_TERRAIN: int = 48
const VISUAL_FAST_PHASE_TILE_CAP_COVER: int = 24
const VISUAL_FAST_PHASE_TILE_CAP_CLIFF: int = 48
const VISUAL_URGENT_PHASE_TILE_CAP_TERRAIN: int = 64
const VISUAL_URGENT_PHASE_TILE_CAP_COVER: int = 32
const VISUAL_URGENT_PHASE_TILE_CAP_CLIFF: int = 64
const VISUAL_BOOTSTRAP_FULL_TERRAIN_TILES: int = 12
const VISUAL_BOOTSTRAP_FULL_COVER_TILES: int = 6
const VISUAL_BOOTSTRAP_FULL_CLIFF_TILES: int = 6
const VISUAL_BOOTSTRAP_BORDER_TILES: int = 2
const VISUAL_COMPLETED_COMPUTE_MAX_INTAKE_PER_STEP: int = 2
const VISUAL_MAX_CONCURRENT_COMPUTE: int = 2
const VISUAL_MAX_FAR_CONCURRENT_COMPUTE: int = 1
const SEAM_REFRESH_MAX_TILES_PER_STEP: int = 4
const DEBUG_OVERLAY_MAX_RADIUS: int = 8
const DEBUG_OVERLAY_STALL_MS: float = 750.0
const DEBUG_OVERLAY_RECENT_MS: float = 2000.0
const DEBUG_OVERLAY_RATE_WINDOW_MS: float = 1000.0
const DEBUG_OVERLAY_RECENT_EVENT_LIMIT: int = 64
const DEBUG_OVERLAY_DEFAULT_QUEUE_ROWS: int = 14
const LOADED_OPEN_POCKET_QUERY_TILE_CAP: int = 65536

var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(99999, 99999)
var _last_player_chunk_for_priority: Vector2i = Vector2i(99999, 99999)
var _player_chunk_motion: Vector2i = Vector2i.ZERO
var _last_display_sync_reference: Vector2i = Vector2i(99999, 99999)
var _player: Node2D = null
var _chunk_container: Node2D = null
var _redrawing_chunks: Array[Chunk] = []
var _player_chunk_diag_last_usec: int = 0
var _player_chunk_diag_last_signature: String = ""
var _saved_chunk_data: Dictionary = {}
var _terrain_tileset: TileSet = null
var _overlay_tileset: TileSet = null
var _underground_terrain_tileset: TileSet = null
var _tileset_bundles_by_biome: Dictionary = {}
var _fog_tileset: TileSet = null
var _fog_state: UndergroundFogState = UndergroundFogState.new()
var _fog_job_id: StringName = &""
var _initialized: bool = false
var _active_z: int = 0
var _z_containers: Dictionary = {}
var _z_chunks: Dictionary = {}
var _native_loaded_open_pocket_query_available: bool = false
var _native_loaded_open_pocket_query: RefCounted = null
var _native_runtime_capabilities_valid: bool = false
var _wg_has_canonicalize_tile: bool = false
var _wg_has_canonicalize_chunk_coord: bool = false
var _wg_has_offset_tile: bool = false
var _wg_has_offset_chunk_coord: bool = false
var _wg_has_tile_to_local_in_chunk: bool = false
var _wg_has_chunk_local_to_tile: bool = false
var _wg_has_chunk_wrap_delta_x: bool = false
var _wg_has_get_world_wrap_width_tiles: bool = false
var _wg_has_get_registered_biomes: bool = false
var _wg_has_create_detached_chunk_content_builder: bool = false
var _wg_has_resolve_biome_with_channels: bool = false
var _wg_chunk_biome_method: StringName = &""
var _wg_tile_biome_method: StringName = &""
var _flora_builder: ChunkFloraBuilderScript = null
var _flora_texture_path_by_entry_id: Dictionary = {}
var _flora_texture_path_cache_ready: bool = false
var _chunk_debug_system: ChunkDebugSystem = null
var _chunk_streaming_service: ChunkStreamingService = null
var _chunk_surface_payload_cache: ChunkSurfacePayloadCache = null
var _chunk_seam_service: ChunkSeamService = null
var _chunk_visual_scheduler: ChunkVisualScheduler = null
var _chunk_topology_service: ChunkTopologyService = null
var _chunk_boot_pipeline: ChunkBootPipeline = null
var _travel_state_resolver: TravelStateResolver = null
var _view_envelope_resolver: ViewEnvelopeResolver = null
var _frontier_planner: FrontierPlanner = null
var _frontier_scheduler: FrontierScheduler = null
var _is_boot_in_progress: bool = true  ## Fail-closed: block runtime player-chunk checks until boot entrypoint really runs.

## --- Boot readiness state (boot_chunk_readiness_spec) ---
enum BootChunkState {
	QUEUED_COMPUTE,
	COMPUTED,
	QUEUED_APPLY,
	APPLIED,
	VISUAL_COMPLETE,
}
## Ring 0 (player) + ring 1 (immediate neighbors) = first-playable gate.
## Outer rings are required for boot_complete only.
const BOOT_FIRST_PLAYABLE_MAX_RING: int = 1
## Topology is part of boot_complete but NOT part of first_playable.
## --- Boot performance instrumentation (boot_performance_instrumentation_spec) ---

## --- Boot compute pipeline (boot_chunk_compute_pipeline_spec) ---
const BOOT_MAX_CONCURRENT_COMPUTE: int = 3
## --- Boot apply budget (boot_chunk_apply_budget_spec) ---
const BOOT_MAX_PREPARE_PER_STEP: int = 2
const BOOT_MAX_APPLY_PER_STEP: int = 1
const BOOT_APPLY_WARNING_MS: float = 8.0
const BOOT_FIRST_PLAYABLE_VISUAL_BUDGET_USEC: int = 8000
const BOOT_FINALIZATION_STREAMING_STEPS_PER_FRAME: int = 2
const BOOT_FINALIZATION_VISUAL_BUDGET_USEC: int = 6000
const RUNTIME_MAX_CONCURRENT_COMPUTE: int = 4

## --- Boot apply queue (boot_chunk_apply_budget_spec) ---
## --- Async generation (runtime only) ---
var _debug_recent_lifecycle_events: Array[Dictionary] = []
var _debug_recent_unloads: Dictionary = {}  ## Vector3i -> usec
var _shutdown_in_progress: bool = false

func _ready() -> void:
	set_process(false)
	_chunk_topology_service = ChunkTopologyService.new()
	_chunk_topology_service.setup(self, NATIVE_TOPOLOGY_BUILDER_CLASS)
	_chunk_boot_pipeline = ChunkBootPipeline.new()
	_chunk_boot_pipeline.setup(self)
	_native_runtime_capabilities_valid = _validate_required_native_capabilities()
	if not _native_runtime_capabilities_valid:
		_block_runtime_startup()
		return
	add_to_group("chunk_manager")
	_chunk_debug_system = ChunkDebugSystem.new()
	_chunk_debug_system.setup(self, OS.is_debug_build())
	_chunk_visual_scheduler = ChunkVisualScheduler.new()
	_chunk_visual_scheduler.setup(self)
	_chunk_surface_payload_cache = ChunkSurfacePayloadCache.new()
	_chunk_surface_payload_cache.setup(self, SURFACE_PAYLOAD_CACHE_LIMIT)
	_travel_state_resolver = TravelStateResolver.new()
	_travel_state_resolver.setup(self)
	_view_envelope_resolver = ViewEnvelopeResolver.new()
	_view_envelope_resolver.setup(self)
	_frontier_planner = FrontierPlanner.new()
	_frontier_planner.call("setup", self, _travel_state_resolver, _view_envelope_resolver)
	_frontier_scheduler = FrontierScheduler.new()
	_frontier_scheduler.setup(self)
	_chunk_streaming_service = ChunkStreamingService.new()
	_chunk_streaming_service.call(
		"setup",
		self,
		_chunk_visual_scheduler,
		_chunk_surface_payload_cache,
		_frontier_planner,
		_frontier_scheduler
	)
	_chunk_seam_service = ChunkSeamService.new()
	_chunk_seam_service.setup(self, SEAM_REFRESH_MAX_TILES_PER_STEP)
	_chunk_container = Node2D.new()
	_chunk_container.name = "Chunks"
	add_child(_chunk_container)
	_setup_z_containers()
	call_deferred("_deferred_init")

func _exit_tree() -> void:
	_shutdown_in_progress = true
	_redrawing_chunks.clear()
	_invalidate_display_sync_cache()
	_clear_visual_task_state()
	if _chunk_streaming_service != null:
		_chunk_streaming_service.clear_runtime_state()
	if _chunk_debug_system != null:
		_chunk_debug_system.clear_runtime_state()
	if _chunk_seam_service != null:
		_chunk_seam_service.clear()
	if _native_loaded_open_pocket_query != null:
		_native_loaded_open_pocket_query.call("clear")
	_native_loaded_open_pocket_query = null
	if _chunk_surface_payload_cache != null:
		_chunk_surface_payload_cache.clear()
	_boot_wait_all_compute()
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.clear_runtime_state()
	if _chunk_topology_service != null:
		_chunk_topology_service.clear_runtime_state()
	if FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(JOB_STREAMING_LOAD)
		FrameBudgetDispatcher.unregister_job(JOB_STREAMING_REDRAW)
		FrameBudgetDispatcher.unregister_job(JOB_TOPOLOGY)
		if _fog_job_id:
			FrameBudgetDispatcher.unregister_job(_fog_job_id)

func _process(_delta: float) -> void:
	if not _initialized or not _player:
		return
	if _chunk_boot_pipeline != null and _chunk_boot_pipeline.has_remaining_chunks():
		_tick_boot_remaining()
	if _is_boot_in_progress:
		return
	_check_player_chunk()

func _await_boot_entrypoint_ready() -> bool:
	if _chunk_boot_pipeline != null and _initialized and _player != null:
		return true
	var wait_frames: int = 0
	while wait_frames < 8 and (_chunk_boot_pipeline == null or not _initialized or _player == null):
		if _shutdown_in_progress:
			return false
		await get_tree().process_frame
		wait_frames += 1
	return _chunk_boot_pipeline != null and _initialized and _player != null

## Boot-time загрузка стартового пузыря. Вызывается из GameWorld под loading screen.
## progress_callback: func(percent: float, text: String) -> void
func boot_load_initial_chunks(progress_callback: Callable) -> void:
	_is_boot_in_progress = true
	var boot_entry_ready: bool = await _await_boot_entrypoint_ready()
	if not boot_entry_ready:
		push_error("ChunkManager.boot_load_initial_chunks(): boot entrypoint was called before deferred init became ready.")
		return
	await _chunk_boot_pipeline.boot_load_initial_chunks(progress_callback)
	_is_boot_in_progress = false

func set_saved_data(data: Dictionary) -> void:
	var normalized: Dictionary = {}
	for key: Variant in data:
		var normalized_key: Vector3i = _normalize_saved_chunk_key(key)
		if normalized_key == INVALID_CHUNK_STATE_KEY:
			continue
		normalized[normalized_key] = data[key]
	_saved_chunk_data = normalized

func get_save_data() -> Dictionary:
	var result: Dictionary = _saved_chunk_data.duplicate()
	for z_value: int in _z_chunks:
		var z_loaded_chunks: Dictionary = _z_chunks[z_value] as Dictionary
		for coord: Vector2i in z_loaded_chunks:
			var chunk: Chunk = z_loaded_chunks[coord]
			if chunk.is_dirty:
				result[_make_chunk_state_key(z_value, coord)] = chunk.get_modifications()
	return result

func is_tile_loaded(gt: Vector2i) -> bool:
	return _loaded_chunks.has(WorldGenerator.tile_to_chunk(_canonical_tile(gt)))

func get_chunk_at_tile(gt: Vector2i) -> Chunk:
	return _loaded_chunks.get(WorldGenerator.tile_to_chunk(_canonical_tile(gt)))

func get_chunk(cc: Vector2i) -> Chunk:
	return _loaded_chunks.get(_canonical_chunk_coord(cc))

func get_terrain_type_at_global(tile_pos: Vector2i) -> int:
	var canonical_tile: Vector2i = _canonical_tile(tile_pos)
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(canonical_tile)
	var loaded_chunk: Chunk = _loaded_chunks.get(chunk_coord)
	if loaded_chunk:
		return loaded_chunk.get_terrain_type_at(loaded_chunk.global_to_local(canonical_tile))
	var saved_chunk_state: Dictionary = _get_saved_chunk_modifications(_active_z, chunk_coord)
	var local_tile: Vector2i = _tile_to_local(canonical_tile, chunk_coord, WorldGenerator.balance.chunk_size_tiles)
	var tile_state: Dictionary = saved_chunk_state.get(local_tile, {}) as Dictionary
	if tile_state.has("terrain"):
		return int(tile_state["terrain"])
	# Underground: unloaded tiles are solid rock, not surface terrain
	if _active_z != 0:
		return TileGenData.TerrainType.ROCK
	if WorldGenerator and WorldGenerator._is_initialized:
		return WorldGenerator.get_terrain_type_fast(canonical_tile)
	return TileGenData.TerrainType.GROUND

func get_loaded_chunks() -> Dictionary:
	return _loaded_chunks

func get_chunk_debug_overlay_snapshot(max_queue_rows: int = DEBUG_OVERLAY_DEFAULT_QUEUE_ROWS, debug_radius: int = -1) -> Dictionary:
	if _chunk_debug_system == null:
		var now_usec: int = Time.get_ticks_usec()
		return {
			"timestamp_usec": now_usec,
			"active_z": _active_z,
			"player_chunk": _player_chunk,
			"player_motion": _player_chunk_motion,
			"radii": {},
			"chunks": [],
			"queue_rows": [],
			"queue_hidden_count": 0,
			"metrics": {},
			"timeline_events": WorldRuntimeDiagnosticLog.get_timeline_snapshot(16),
			"incident_summary": {},
			"trace_events": [],
			"chunk_causality_rows": [],
			"task_debug_rows": [],
			"suspicion_flags": [],
			"mode_hint": "unavailable",
		}
	return _chunk_debug_system.build_overlay_snapshot(max_queue_rows, debug_radius)

func _debug_make_forensics_trace_id() -> String:
	if _chunk_debug_system == null:
		return ""
	return _chunk_debug_system._make_forensics_trace_id()

func _debug_forensics_timestamp_label(timestamp_usec: int) -> String:
	if _chunk_debug_system == null:
		return ""
	return _chunk_debug_system._forensics_timestamp_label(timestamp_usec)

func _debug_visual_kind_name(kind: int) -> String:
	match kind:
		VisualTaskKind.TASK_FIRST_PASS:
			return "first_pass"
		VisualTaskKind.TASK_FULL_REDRAW:
			return "full_redraw"
		VisualTaskKind.TASK_BORDER_FIX:
			return "border_fix"
		_:
			return "cosmetic"

func _debug_visual_band_name(band: int) -> String:
	match band:
		VisualPriorityBand.TERRAIN_FAST:
			return "terrain_fast"
		VisualPriorityBand.TERRAIN_URGENT:
			return "terrain_urgent"
		VisualPriorityBand.TERRAIN_NEAR:
			return "terrain_near"
		VisualPriorityBand.FULL_NEAR:
			return "full_near"
		VisualPriorityBand.BORDER_FIX_NEAR:
			return "border_fix_near"
		VisualPriorityBand.BORDER_FIX_FAR:
			return "border_fix_far"
		VisualPriorityBand.FULL_FAR:
			return "full_far"
		_:
			return "cosmetic"

func _debug_forensics_event_label(event_key: String) -> String:
	if _chunk_debug_system == null:
		return WorldRuntimeDiagnosticLog.humanize_known_term(event_key)
	return _chunk_debug_system._forensics_event_label(event_key)

func _debug_duplicate_trace_context(trace_context: Dictionary) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system._duplicate_trace_context(trace_context)

func _debug_is_valid_trace_context(trace_context: Dictionary, now_usec: int = -1) -> bool:
	if _chunk_debug_system == null:
		return false
	return _chunk_debug_system._is_valid_trace_context(trace_context, now_usec)

func _debug_resolve_chunk_trace_context(coord: Vector2i, z_level: int, now_usec: int = -1) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system.resolve_chunk_trace_context(coord, z_level, now_usec)

func _debug_attach_trace_context_to_chunks(
	trace_context: Dictionary,
	coords: Array[Vector2i],
	z_level: int,
	now_usec: int
) -> void:
	if _chunk_debug_system == null:
		return
	_chunk_debug_system._attach_trace_context_to_chunks(trace_context, coords, z_level, now_usec)

func _debug_register_forensics_event(
	trace_context: Dictionary,
	source_system: String,
	event_key: String,
	coord: Vector2i,
	z_level: int,
	detail_fields: Dictionary = {},
	target_chunks: Array[Vector2i] = []
) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system._register_forensics_event(
		trace_context,
		source_system,
		event_key,
		coord,
		z_level,
		detail_fields,
		target_chunks
	)

func _debug_begin_forensics_trace(
	source_system: String,
	event_key: String,
	primary_coord: Vector2i,
	z_level: int,
	target_chunks: Array[Vector2i] = [],
	detail_fields: Dictionary = {}
) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system._begin_forensics_trace(
		source_system,
		event_key,
		primary_coord,
		z_level,
		target_chunks,
		detail_fields
	)

func _debug_record_forensics_event(
	trace_context: Dictionary,
	source_system: String,
	event_key: String,
	coord: Vector2i,
	z_level: int,
	detail_fields: Dictionary = {},
	target_chunks: Array[Vector2i] = []
) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system.record_forensics_event(
		trace_context,
		source_system,
		event_key,
		coord,
		z_level,
		detail_fields,
		target_chunks
	)

func _debug_is_incident_worthy_coord(coord: Vector2i, z_level: int) -> bool:
	if z_level != _active_z or _player_chunk == Vector2i(99999, 99999):
		return false
	return _chunk_chebyshev_distance(_canonical_chunk_coord(coord), _player_chunk) <= 1

func _debug_ensure_forensics_context(
	coord: Vector2i,
	z_level: int,
	source_system: String,
	event_key: String,
	detail_fields: Dictionary = {},
	target_chunks: Array[Vector2i] = []
) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system.ensure_forensics_context(
		coord,
		z_level,
		source_system,
		event_key,
		detail_fields,
		target_chunks
	)

func _debug_enrich_record_with_trace(
	record: Dictionary,
	detail_fields: Dictionary,
	coord: Vector2i,
	z_level: int,
	trace_context: Dictionary = {}
) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system.enrich_record_with_trace(record, detail_fields, coord, z_level, trace_context)

func _debug_prune_forensics_state(now_usec: int) -> void:
	if _chunk_debug_system == null:
		return
	_chunk_debug_system.prune_forensics_state(now_usec)

func _debug_get_active_incident(now_usec: int) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system.get_active_incident(now_usec)

func _debug_build_incident_summary(metrics: Dictionary, now_usec: int) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system.build_incident_summary(metrics, now_usec)

func _debug_build_trace_events(incident_summary: Dictionary) -> Array[Dictionary]:
	if _chunk_debug_system == null:
		return []
	return _chunk_debug_system.build_trace_events(incident_summary)

func _debug_collect_incident_chunk_keys(incident_id: int) -> Array[String]:
	return []

func _debug_build_chunk_causality_rows(
	incident_summary: Dictionary,
	lookups: Dictionary,
	now_usec: int
) -> Array[Dictionary]:
	if _chunk_debug_system == null:
		return []
	return _chunk_debug_system.build_chunk_causality_rows(incident_summary, lookups, now_usec)

func _debug_build_task_debug_rows(incident_summary: Dictionary, now_usec: int) -> Array[Dictionary]:
	if _chunk_debug_system == null:
		return []
	return _chunk_debug_system.build_task_debug_rows(incident_summary, now_usec)

func _debug_build_suspicion_flags(
	incident_summary: Dictionary,
	trace_events: Array[Dictionary],
	chunk_causality_rows: Array[Dictionary],
	task_debug_rows: Array[Dictionary],
	metrics: Dictionary,
	now_usec: int
) -> Array[Dictionary]:
	if _chunk_debug_system == null:
		return []
	return _chunk_debug_system.build_suspicion_flags(
		incident_summary,
		trace_events,
		chunk_causality_rows,
		task_debug_rows,
		metrics,
		now_usec
	)

func sync_display_to_player() -> void:
	if not _initialized or not _player or not WorldGenerator:
		return
	var reference_chunk: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	var chunk_changed: bool = reference_chunk != _player_chunk
	_player_chunk = reference_chunk
	_sync_loaded_chunk_display_positions(reference_chunk)
	if chunk_changed and not _is_boot_in_progress:
		_update_chunks(reference_chunk)

func _make_chunk_state_key(z_level: int, coord: Vector2i) -> Vector3i:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	return Vector3i(canonical_coord.x, canonical_coord.y, z_level)

func _normalize_saved_chunk_key(key: Variant) -> Vector3i:
	if key is Vector3i:
		var coord3: Vector3i = key as Vector3i
		var canonical_coord: Vector2i = _canonical_chunk_coord(Vector2i(coord3.x, coord3.y))
		return Vector3i(canonical_coord.x, canonical_coord.y, coord3.z)
	if key is Vector2i:
		var coord2: Vector2i = key as Vector2i
		var canonical_coord: Vector2i = _canonical_chunk_coord(coord2)
		return Vector3i(canonical_coord.x, canonical_coord.y, 0)
	return INVALID_CHUNK_STATE_KEY

func _get_saved_chunk_modifications(z_level: int, coord: Vector2i) -> Dictionary:
	return _saved_chunk_data.get(_make_chunk_state_key(z_level, coord), {}) as Dictionary

func _canonical_tile(tile_pos: Vector2i) -> Vector2i:
	if WorldGenerator and _wg_has_canonicalize_tile:
		return WorldGenerator.canonicalize_tile(tile_pos)
	return tile_pos

func _canonical_chunk_coord(coord: Vector2i) -> Vector2i:
	if WorldGenerator and _wg_has_canonicalize_chunk_coord:
		return WorldGenerator.canonicalize_chunk_coord(coord)
	return coord

func _offset_tile(tile_pos: Vector2i, offset: Vector2i) -> Vector2i:
	if WorldGenerator and _wg_has_offset_tile:
		return WorldGenerator.offset_tile(tile_pos, offset)
	return tile_pos + offset

func _offset_chunk_coord(coord: Vector2i, offset: Vector2i) -> Vector2i:
	if WorldGenerator and _wg_has_offset_chunk_coord:
		return WorldGenerator.offset_chunk_coord(coord, offset)
	return coord + offset

func _tile_to_local(tile_pos: Vector2i, chunk_coord: Vector2i, chunk_size: int) -> Vector2i:
	if WorldGenerator and _wg_has_tile_to_local_in_chunk:
		return WorldGenerator.tile_to_local_in_chunk(tile_pos, chunk_coord)
	return Vector2i(
		tile_pos.x - chunk_coord.x * chunk_size,
		tile_pos.y - chunk_coord.y * chunk_size
	)

func _chunk_local_to_tile(chunk_coord: Vector2i, local_tile: Vector2i) -> Vector2i:
	if WorldGenerator and _wg_has_chunk_local_to_tile:
		return WorldGenerator.chunk_local_to_tile(chunk_coord, local_tile)
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles if WorldGenerator and WorldGenerator.balance else 1
	return Vector2i(
		chunk_coord.x * chunk_size + local_tile.x,
		chunk_coord.y * chunk_size + local_tile.y
	)

func _chunk_wrap_delta_x(chunk_x: int, center_x: int) -> int:
	if WorldGenerator and _wg_has_chunk_wrap_delta_x:
		return WorldGenerator.chunk_wrap_delta_x(chunk_x, center_x)
	return chunk_x - center_x

func _chunk_axis_distance(chunk_x: int, center_x: int) -> int:
	return absi(_chunk_wrap_delta_x(chunk_x, center_x))

func _chunk_manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return _chunk_axis_distance(a.x, b.x) + absi(a.y - b.y)

func _chunk_chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(_chunk_axis_distance(a.x, b.x), absi(a.y - b.y))

func _chunk_priority_less(a: Vector2i, b: Vector2i, center: Vector2i) -> bool:
	var ring_a: int = _chunk_chebyshev_distance(a, center)
	var ring_b: int = _chunk_chebyshev_distance(b, center)
	if ring_a != ring_b:
		return ring_a < ring_b
	var dist_a: int = _chunk_manhattan_distance(a, center)
	var dist_b: int = _chunk_manhattan_distance(b, center)
	if dist_a != dist_b:
		return dist_a < dist_b
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y

func _is_chunk_within_radius(coord: Vector2i, center: Vector2i, radius: int) -> bool:
	return _chunk_axis_distance(coord.x, center.x) <= radius and absi(coord.y - center.y) <= radius

func _resolve_display_reference_chunk(fallback_chunk: Vector2i) -> Vector2i:
	if _player and WorldGenerator:
		return WorldGenerator.world_to_chunk(_player.global_position)
	return _canonical_chunk_coord(fallback_chunk)

func _get_player_chunk_coord() -> Vector2i:
	return _player_chunk

func _get_player_chunk_motion() -> Vector2i:
	return _player_chunk_motion

func _sync_chunk_display_position(chunk: Chunk, reference_chunk: Vector2i) -> void:
	if not is_instance_valid(chunk):
		return
	chunk.sync_display_position(_resolve_display_reference_chunk(reference_chunk))

func _invalidate_display_sync_cache() -> void:
	_last_display_sync_reference = Vector2i(99999, 99999)

func _sync_loaded_chunk_display_positions(reference_chunk: Vector2i, force: bool = false) -> void:
	var canonical_reference: Vector2i = _resolve_display_reference_chunk(reference_chunk)
	if not force and canonical_reference == _last_display_sync_reference:
		return
	_last_display_sync_reference = canonical_reference
	for coord: Vector2i in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[coord]
		if not is_instance_valid(chunk):
			continue
		chunk.sync_display_position(canonical_reference)

func _make_load_request_key(coord: Vector2i, z_level: int) -> Vector3i:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	return Vector3i(canonical_coord.x, canonical_coord.y, z_level)

func _has_load_request(coord: Vector2i, z_level: int) -> bool:
	return _chunk_streaming_service != null \
		and _chunk_streaming_service.load_queue_set.has(_make_load_request_key(coord, z_level))

func _debug_build_radii() -> Dictionary:
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	var unload_radius: int = WorldGenerator.balance.unload_radius if WorldGenerator and WorldGenerator.balance else load_radius
	var near_visual_radius: int = WorldGenerator.balance.near_visible_chunk_radius if WorldGenerator and WorldGenerator.balance else load_radius
	var far_visual_radius: int = WorldGenerator.balance.far_visible_chunk_radius if WorldGenerator and WorldGenerator.balance else unload_radius
	return {
		"shape": "square_chebyshev",
		"render_radius": far_visual_radius,
		"preload_radius": load_radius,
		"simulation_radius": load_radius,
		"retention_radius": unload_radius,
		"near_visual_radius": near_visual_radius,
		"far_visual_radius": far_visual_radius,
		"max_debug_radius": DEBUG_OVERLAY_MAX_RADIUS,
	}

func _debug_build_snapshot_lookups(now_usec: int) -> Dictionary:
	var load_requests: Dictionary = {}
	for request: Dictionary in _chunk_streaming_service.load_queue:
		var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
		var z_level: int = int(request.get("z", INVALID_Z_LEVEL))
		load_requests[_make_chunk_state_key(z_level, coord)] = request
	var ready_entries: Dictionary = {}
	for ready_entry: Dictionary in _chunk_streaming_service.gen_ready_queue:
		var coord: Vector2i = _canonical_chunk_coord(ready_entry.get("coord", Vector2i.ZERO) as Vector2i)
		var z_level: int = int(ready_entry.get("z", INVALID_Z_LEVEL))
		ready_entries[_make_chunk_state_key(z_level, coord)] = ready_entry
	return {
		"now_usec": now_usec,
		"load_requests": load_requests,
		"ready_entries": ready_entries,
		"recent_unloads": _debug_recent_unloads.duplicate(),
	}

func _debug_build_chunk_entry(
	coord: Vector2i,
	z_level: int,
	chunk: Chunk,
	lookups: Dictionary,
	now_usec: int
) -> Dictionary:
	var key: Vector3i = _make_chunk_state_key(z_level, coord)
	var load_requests: Dictionary = lookups.get("load_requests", {}) as Dictionary
	var ready_entries: Dictionary = lookups.get("ready_entries", {}) as Dictionary
	var recent_unloads: Dictionary = lookups.get("recent_unloads", {}) as Dictionary
	var distance: int = _chunk_chebyshev_distance(coord, _player_chunk)
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	var unload_radius: int = WorldGenerator.balance.unload_radius if WorldGenerator and WorldGenerator.balance else load_radius
	var state: String = "absent"
	var state_age_ms: float = -1.0
	var requested_usec: int = 0
	var requested_frame: int = -1
	var reason: String = _debug_reason_for_chunk(coord, distance, "absent")
	var technical_code: String = "chunk_absent"
	var is_visible: bool = false
	var is_simulating: bool = false
	var visual_phase: String = ""
	if chunk != null and is_instance_valid(chunk):
		is_visible = chunk.visible
		is_simulating = distance <= load_radius
		visual_phase = chunk.get_redraw_phase_name()
		state = _debug_resolve_loaded_chunk_state(chunk, coord, z_level)
		state_age_ms = _debug_resolve_loaded_chunk_age_ms(coord, z_level, state, now_usec)
		reason = _debug_reason_for_chunk(coord, distance, state)
		technical_code = _describe_chunk_visual_state(chunk)
		if state == "visible" and is_simulating:
			state = "simulating"
			reason = "чанк видим и входит в активную область симуляции вокруг игрока"
			technical_code = "simulation_active"
	elif _is_generating_request(coord, z_level):
		state = "generating"
		state_age_ms = _debug_age_ms(_chunk_streaming_service.debug_generate_started_usec.get(key, 0), now_usec)
		reason = "задача генерации уже взята worker thread"
		technical_code = "stream_load"
	elif ready_entries.has(key):
		var ready_entry: Dictionary = ready_entries.get(key, {}) as Dictionary
		state = "data_ready"
		state_age_ms = _debug_age_ms(ready_entry.get("ready_usec", 0), now_usec)
		reason = "данные чанка готовы и ждут применения на основном потоке"
		technical_code = "queued_not_applied"
	elif _is_staged_request(coord, z_level) and (not _chunk_streaming_service.staged_data.is_empty() or _chunk_streaming_service.staged_chunk != null or not _chunk_streaming_service.staged_install_entry.is_empty()):
		state = "data_ready" if _chunk_streaming_service.staged_chunk == null else "building_visual"
		state_age_ms = _debug_age_ms(_chunk_streaming_service.staged_install_entry.get("staged_usec", 0), now_usec)
		reason = "подготовленный результат ждёт поэтапной установки в сцену"
		technical_code = "queued_not_applied"
	elif load_requests.has(key):
		var request: Dictionary = load_requests.get(key, {}) as Dictionary
		requested_usec = int(request.get("requested_usec", 0))
		requested_frame = int(request.get("requested_frame", -1))
		state_age_ms = _debug_age_ms(requested_usec, now_usec)
		state = "requested" if state_age_ms >= 0.0 and state_age_ms < 180.0 else "queued"
		reason = str(request.get("reason", _debug_reason_for_chunk(coord, distance, state)))
		technical_code = "stream_load"
	elif recent_unloads.has(key):
		state = "unloading"
		state_age_ms = _debug_age_ms(recent_unloads.get(key, 0), now_usec)
		reason = "чанк недавно вышел из области удержания и был выгружен"
		technical_code = "stream_unload"
	var stalled_stage: String = ""
	var is_stalled: bool = _debug_is_stalled_state(state, state_age_ms)
	if is_stalled:
		stalled_stage = state
		state = "stalled"
		technical_code = "observed_stall"
		reason = "%s; это наблюдаемая задержка, а не доказанная корневая причина" % reason
	return {
		"coord": coord,
		"z": z_level,
		"state": state,
		"state_human": _debug_chunk_state_human(state),
		"stalled_stage": stalled_stage,
		"stage_age_ms": state_age_ms,
		"priority": _debug_priority_label(coord),
		"priority_rank": _debug_priority_rank(coord),
		"distance": distance,
		"requested_frame": requested_frame,
		"requested_timestamp_usec": requested_usec,
		"reason": reason,
		"impact": _debug_impact_for_chunk(distance, state),
		"frontier_lane": _chunk_streaming_service._frontier_lane_name(_chunk_streaming_service._resolve_frontier_lane(coord)),
		"is_player_chunk": coord == _player_chunk,
		"is_visible": is_visible,
		"is_simulating": is_simulating,
		"is_stalled": is_stalled,
		"visual_phase": visual_phase,
		"source_system": "ChunkManager",
		"technical_code": technical_code,
		"within_load_radius": distance <= load_radius,
		"within_unload_radius": distance <= unload_radius,
	}

func _debug_resolve_loaded_chunk_state(chunk: Chunk, coord: Vector2i, z_level: int) -> String:
	if chunk == null or not is_instance_valid(chunk):
		return "absent"
	var has_visual_task: bool = false
	for kind: int in [
		VisualTaskKind.TASK_FIRST_PASS,
		VisualTaskKind.TASK_FULL_REDRAW,
		VisualTaskKind.TASK_BORDER_FIX,
		VisualTaskKind.TASK_COSMETIC,
	]:
		if _chunk_visual_scheduler.task_pending.has(_make_visual_task_key(coord, z_level, kind)):
			has_visual_task = true
			break
	if has_visual_task or not chunk.is_redraw_complete() or not chunk.is_full_redraw_ready():
		return "building_visual"
	if chunk.visible:
		return "visible"
	return "ready"

func _debug_resolve_loaded_chunk_age_ms(coord: Vector2i, z_level: int, state: String, now_usec: int) -> float:
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	var age_ms: float = -1.0
	if state == "building_visual":
		age_ms = maxf(age_ms, _debug_age_ms(_chunk_visual_scheduler.apply_started_usec.get(chunk_key, 0), now_usec))
		age_ms = maxf(age_ms, _debug_age_ms(_chunk_visual_scheduler.convergence_started_usec.get(chunk_key, 0), now_usec))
		for kind: int in [
			VisualTaskKind.TASK_FIRST_PASS,
			VisualTaskKind.TASK_FULL_REDRAW,
			VisualTaskKind.TASK_BORDER_FIX,
			VisualTaskKind.TASK_COSMETIC,
		]:
			age_ms = maxf(age_ms, _get_visual_task_age_ms(coord, z_level, kind))
	elif state == "visible" or state == "ready":
		age_ms = _debug_age_ms(_chunk_visual_scheduler.full_ready_usec.get(chunk_key, 0), now_usec)
	return age_ms

func _debug_is_stalled_state(state: String, age_ms: float) -> bool:
	if age_ms < DEBUG_OVERLAY_STALL_MS:
		return false
	return state == "requested" \
		or state == "queued" \
		or state == "generating" \
		or state == "data_ready" \
		or state == "building_visual"

func _debug_reason_for_chunk(coord: Vector2i, distance: int, state: String) -> String:
	if coord == _player_chunk:
		return "это текущий чанк игрока"
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	var unload_radius: int = WorldGenerator.balance.unload_radius if WorldGenerator and WorldGenerator.balance else load_radius
	if state == "absent" and distance > unload_radius:
		return "чанк вне области удержания"
	if distance <= load_radius:
		return "чанк входит в фактическую область загрузки вокруг игрока"
	if distance <= unload_radius:
		return "чанк удерживается как хвост после движения игрока"
	return "чанк вне текущей рабочей области"

func _debug_chunk_state_human(state: String) -> String:
	match state:
		"absent":
			return "отсутствует"
		"requested":
			return "запрошен"
		"queued":
			return "стоит в очереди"
		"generating":
			return "генерируются данные"
		"data_ready":
			return "данные готовы"
		"building_visual":
			return "строится визуал"
		"ready":
			return "готов"
		"visible":
			return "видим"
		"simulating":
			return "участвует в симуляции"
		"unloading":
			return "выгружается"
		"error":
			return "ошибка"
		"stalled":
			return "подозрительно долго висит"
		_:
			return state

func _debug_priority_rank(coord: Vector2i) -> int:
	var distance: int = _chunk_chebyshev_distance(coord, _player_chunk)
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	if coord == _player_chunk:
		return 0
	if distance <= 1:
		return 1
	if distance <= load_radius:
		return 2
	return 3

func _debug_priority_label(coord: Vector2i) -> String:
	match _debug_priority_rank(coord):
		0:
			return "немедленный"
		1:
			return "высокий"
		2:
			return "средний"
		_:
			return "низкий"

func _debug_impact_for_chunk(distance: int, state: String) -> String:
	if state == "stalled" and distance <= 1:
		return String(WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE)
	if distance <= 1 and (state == "generating" or state == "building_visual" or state == "data_ready"):
		return String(WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE)
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	if distance <= load_radius:
		return String(WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT)
	return String(WorldRuntimeDiagnosticLog.IMPACT_INFORMATIONAL)

func _debug_age_ms(raw_start_usec: Variant, now_usec: int) -> float:
	var start_usec: int = int(raw_start_usec)
	if start_usec <= 0:
		return -1.0
	return float(now_usec - start_usec) / 1000.0

func _debug_visual_queue_depth() -> int:
	return _chunk_visual_scheduler.queue_depth() if _chunk_visual_scheduler != null else 0

func _get_visual_scheduler() -> ChunkVisualScheduler:
	return _chunk_visual_scheduler

func _debug_seam_refresh_queue_depth() -> int:
	return _chunk_seam_service.pending_count() if _chunk_seam_service != null else 0

func _debug_queue_sizes() -> Dictionary:
	var sizes: Dictionary = {
		"load": _chunk_streaming_service.load_queue.size(),
		"frontier_critical": _chunk_streaming_service.frontier_critical_queue.size(),
		"camera_visible_support": _chunk_streaming_service.camera_visible_support_queue.size(),
		"background": _chunk_streaming_service.background_queue.size(),
		"generate_active": _chunk_streaming_service.gen_active_tasks.size(),
		"data_ready": _chunk_streaming_service.gen_ready_queue.size(),
		"visual": _debug_visual_queue_depth(),
		"seam_refresh": _debug_seam_refresh_queue_depth(),
		"topology_dirty": 1 if _chunk_topology_service != null and _chunk_topology_service.is_dirty() else 0,
	}
	sizes["frontier_reserved_capacity_blocks"] = _chunk_streaming_service.debug_frontier_reservation_block_count
	sizes["frontier_capacity"] = _chunk_streaming_service._get_frontier_capacity_snapshot()
	sizes["frontier_plan"] = _chunk_streaming_service._get_frontier_plan_summary()
	return sizes

func _debug_count_recent_events(kind: String, window_ms: float, now_usec: int) -> int:
	var count: int = 0
	for event: Dictionary in _debug_recent_lifecycle_events:
		if str(event.get("kind", "")) != kind:
			continue
		var age_ms: float = _debug_age_ms(event.get("timestamp_usec", 0), now_usec)
		if age_ms >= 0.0 and age_ms <= window_ms:
			count += 1
	return count

func _debug_record_recent_lifecycle_event(
	kind: String,
	coord: Vector2i,
	z_level: int,
	task_type_human: String,
	reason: String,
	duration_ms: float = -1.0,
	show_in_queue: bool = true
) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	var entry: Dictionary = {
		"kind": kind,
		"coord": canonical_coord,
		"z": z_level,
		"timestamp_usec": now_usec,
		"duration_ms": duration_ms,
		"task_type_human": task_type_human,
		"reason": reason,
		"priority": _debug_priority_label(canonical_coord),
		"impact": _debug_impact_for_chunk(_chunk_chebyshev_distance(canonical_coord, _player_chunk), "ready"),
		"show_in_queue": show_in_queue,
	}
	_debug_recent_lifecycle_events.append(entry)
	if kind == "unloaded":
		_debug_recent_unloads[_make_chunk_state_key(z_level, canonical_coord)] = now_usec
	_debug_prune_recent_lifecycle_events(now_usec)

func _debug_prune_recent_lifecycle_events(now_usec: int) -> void:
	while _debug_recent_lifecycle_events.size() > DEBUG_OVERLAY_RECENT_EVENT_LIMIT:
		_debug_recent_lifecycle_events.pop_front()
	while not _debug_recent_lifecycle_events.is_empty():
		var first: Dictionary = _debug_recent_lifecycle_events[0] as Dictionary
		if _debug_age_ms(first.get("timestamp_usec", 0), now_usec) <= DEBUG_OVERLAY_RECENT_MS:
			break
		_debug_recent_lifecycle_events.pop_front()
	for key_variant: Variant in _debug_recent_unloads.keys():
		if _debug_age_ms(_debug_recent_unloads.get(key_variant, 0), now_usec) > DEBUG_OVERLAY_RECENT_MS:
			_debug_recent_unloads.erase(key_variant)

func _debug_collect_queue_rows(max_queue_rows: int, now_usec: int) -> Dictionary:
	var rows: Array[Dictionary] = []
	var hidden_count: int = 0
	var resolved_limit: int = clampi(max_queue_rows, 1, 48)
	var active_coords: Array[Vector2i] = []
	for coord_variant: Variant in _chunk_streaming_service.gen_active_tasks.keys():
		active_coords.append(coord_variant as Vector2i)
	active_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_priority_less(a, b, _player_chunk)
	)
	for coord: Vector2i in active_coords:
		var z_level: int = int(_chunk_streaming_service.gen_active_z_levels.get(coord, _active_z))
		hidden_count += _debug_append_queue_row(rows, _debug_make_generation_queue_row(coord, z_level, "active", now_usec), resolved_limit)
	if _chunk_streaming_service.staged_chunk != null or not _chunk_streaming_service.staged_data.is_empty() or not _chunk_streaming_service.staged_install_entry.is_empty():
		hidden_count += _debug_append_queue_row(rows, _debug_make_staged_queue_row(now_usec), resolved_limit)
	var active_visual_keys: Array[String] = []
	for key_variant: Variant in _chunk_visual_scheduler.compute_active.keys():
		active_visual_keys.append(str(key_variant))
	active_visual_keys.sort()
	for key: String in active_visual_keys:
		var task: Dictionary = _chunk_visual_scheduler.compute_waiting_tasks.get(key, {}) as Dictionary
		if not task.is_empty():
			hidden_count += _debug_append_queue_row(rows, _debug_make_visual_queue_row(task, "active", now_usec), resolved_limit)
	hidden_count += _debug_append_load_queue_rows(rows, resolved_limit, now_usec)
	if not _chunk_streaming_service.gen_ready_queue.is_empty():
		hidden_count += _debug_append_queue_row(
			rows,
			_debug_make_group_queue_row(
				"data_ready",
				"Загрузка представления в мир",
				"Ожидает применения",
				_chunk_streaming_service.gen_ready_queue.size(),
				"сгенерированные данные ждут main-thread apply",
				"средний"
			),
			resolved_limit
		)
	for queue: Array[Dictionary] in _get_visual_queues_in_priority_order():
		hidden_count += _debug_append_visual_queue_group(rows, resolved_limit, queue, "waiting", now_usec)
	var seam_refresh_depth: int = _debug_seam_refresh_queue_depth()
	if seam_refresh_depth > 0:
		hidden_count += _debug_append_queue_row(
			rows,
			_debug_make_group_queue_row(
				"seam_refresh",
				"Перестройка границы чанков",
				"Ожидает",
				seam_refresh_depth,
				"есть локальные seam-tile правки после изменения соседей",
				"средний"
			),
			resolved_limit
		)
	for idx: int in range(_debug_recent_lifecycle_events.size() - 1, -1, -1):
		var event: Dictionary = _debug_recent_lifecycle_events[idx] as Dictionary
		if bool(event.get("show_in_queue", false)):
			hidden_count += _debug_append_queue_row(rows, _debug_make_completed_queue_row(event, now_usec), resolved_limit)
	return {
		"rows": rows,
		"hidden_count": hidden_count,
	}

func _debug_append_queue_row(rows: Array[Dictionary], row: Dictionary, max_rows: int) -> int:
	if row.is_empty():
		return 0
	if rows.size() < max_rows:
		rows.append(row)
		return 0
	return maxi(1, int(row.get("count", 1)))

func _debug_append_load_queue_rows(rows: Array[Dictionary], max_rows: int, now_usec: int) -> int:
	if _chunk_streaming_service.load_queue.is_empty():
		return 0
	var hidden_count: int = 0
	if _chunk_streaming_service.load_queue.size() <= 3:
		for request: Dictionary in _chunk_streaming_service.load_queue:
			hidden_count += _debug_append_queue_row(rows, _debug_make_load_queue_row(request, now_usec), max_rows)
		return hidden_count
	var first_request: Dictionary = _chunk_streaming_service.load_queue[0] as Dictionary
	hidden_count += _debug_append_queue_row(rows, _debug_make_load_queue_row(first_request, now_usec), max_rows)
	hidden_count += _debug_append_queue_row(
		rows,
		_debug_make_group_queue_row(
			"load_queue_group",
			"Запрос чанка",
			"Ожидает",
			_chunk_streaming_service.load_queue.size() - 1,
			"однотипные запросы догрузки сгруппированы, чтобы не засорять экран",
			"средний"
		),
		max_rows
	)
	return hidden_count

func _debug_append_visual_queue_group(
	rows: Array[Dictionary],
	max_rows: int,
	queue: Array[Dictionary],
	status: String,
	now_usec: int
) -> int:
	if queue.is_empty():
		return 0
	var hidden_count: int = 0
	if queue.size() <= 2:
		for task: Dictionary in queue:
			hidden_count += _debug_append_queue_row(rows, _debug_make_visual_queue_row(task, status, now_usec), max_rows)
		return hidden_count
	var first_task: Dictionary = queue[0] as Dictionary
	hidden_count += _debug_append_queue_row(rows, _debug_make_visual_queue_row(first_task, status, now_usec), max_rows)
	hidden_count += _debug_append_queue_row(
		rows,
		_debug_make_group_queue_row(
			"visual_group_%s_%s" % [int(first_task.get("kind", VisualTaskKind.TASK_COSMETIC)), int(first_task.get("priority_band", VisualPriorityBand.COSMETIC))],
			_debug_visual_task_type_human(int(first_task.get("kind", VisualTaskKind.TASK_COSMETIC))),
			_debug_status_human(status),
			queue.size() - 1,
			"однотипная очередь визуала сгруппирована",
			_debug_visual_band_human(int(first_task.get("priority_band", VisualPriorityBand.COSMETIC)))
		),
		max_rows
	)
	return hidden_count

func _debug_make_load_queue_row(request: Dictionary, now_usec: int) -> Dictionary:
	var coord: Vector2i = _canonical_chunk_coord(request.get("coord", Vector2i.ZERO) as Vector2i)
	var z_level: int = int(request.get("z", _active_z))
	var distance: int = _chunk_chebyshev_distance(coord, _player_chunk)
	return {
		"task_id": "load:%s:%d" % [coord, z_level],
		"group_key": "load_request",
		"status": "waiting",
		"task_type": "chunk_request",
		"task_type_human": "Запрос чанка",
		"chunk_coord": coord,
		"scope": "chunk",
		"stage": "queued",
		"stage_human": "Ожидает",
		"age_ms": _debug_age_ms(request.get("requested_usec", 0), now_usec),
		"priority": str(request.get("frontier_lane_human", request.get("priority", _debug_priority_label(coord)))),
		"reason": "%s; lane=%s" % [
			str(request.get("reason", _debug_reason_for_chunk(coord, distance, "queued"))),
			str(request.get("frontier_lane_name", "background")),
		],
		"impact": _debug_impact_for_chunk(distance, "queued"),
		"state": "queued",
		"queue_depth": _chunk_streaming_service.load_queue.size(),
		"count": 1,
		"hidden_count": 0,
		"completed_recently": false,
		"correlation_id": "chunk:%s:%d" % [coord, z_level],
		"predecessor_id": "",
	}

func _debug_make_generation_queue_row(coord: Vector2i, z_level: int, status: String, now_usec: int) -> Dictionary:
	var key: Vector3i = _make_chunk_state_key(z_level, coord)
	var frontier_lane: int = int(_chunk_streaming_service.gen_active_lanes.get(coord, FrontierScheduler.LANE_BACKGROUND))
	return {
		"task_id": "generate:%s:%d" % [coord, z_level],
		"group_key": "chunk_generation",
		"status": status,
		"task_type": "chunk_generation",
		"task_type_human": "Генерация данных чанка",
		"chunk_coord": coord,
		"scope": "chunk",
		"stage": "generating",
		"stage_human": "Выполняется",
		"age_ms": _debug_age_ms(_chunk_streaming_service.debug_generate_started_usec.get(key, 0), now_usec),
		"priority": _chunk_streaming_service._frontier_lane_human(frontier_lane),
		"reason": "worker thread готовит данные чанка; frontier lane=%s" % _chunk_streaming_service._frontier_lane_name(frontier_lane),
		"impact": _debug_impact_for_chunk(_chunk_chebyshev_distance(coord, _player_chunk), "generating"),
		"state": "generating",
		"queue_depth": _chunk_streaming_service.gen_active_tasks.size(),
		"count": 1,
		"hidden_count": 0,
		"completed_recently": false,
		"correlation_id": "chunk:%s:%d" % [coord, z_level],
		"predecessor_id": "",
	}

func _debug_make_staged_queue_row(now_usec: int) -> Dictionary:
	var coord: Vector2i = _canonical_chunk_coord(_chunk_streaming_service.staged_coord)
	return {
		"task_id": "stage:%s:%d" % [coord, _chunk_streaming_service.staged_z],
		"group_key": "chunk_apply",
		"status": "active",
		"task_type": "chunk_apply",
		"task_type_human": "Загрузка представления в мир",
		"chunk_coord": coord,
		"scope": "chunk",
		"stage": "apply",
		"stage_human": "Применяется",
		"age_ms": _debug_age_ms(_chunk_streaming_service.staged_install_entry.get("staged_usec", 0), now_usec),
		"priority": _debug_priority_label(coord),
		"reason": "подготовленные данные устанавливаются в scene tree поэтапно",
		"impact": _debug_impact_for_chunk(_chunk_chebyshev_distance(coord, _player_chunk), "data_ready"),
		"state": "data_ready",
		"queue_depth": _chunk_streaming_service.gen_ready_queue.size(),
		"count": 1,
		"hidden_count": 0,
		"completed_recently": false,
		"correlation_id": "chunk:%s:%d" % [coord, _chunk_streaming_service.staged_z],
		"predecessor_id": "",
	}

func _debug_make_visual_queue_row(task: Dictionary, status: String, now_usec: int) -> Dictionary:
	var coord: Vector2i = _canonical_chunk_coord(task.get("chunk_coord", Vector2i.ZERO) as Vector2i)
	var z_level: int = int(task.get("z", _active_z))
	var kind: int = int(task.get("kind", VisualTaskKind.TASK_COSMETIC))
	var band: int = int(task.get("priority_band", VisualPriorityBand.COSMETIC))
	var key: Vector4i = _make_visual_task_key(coord, z_level, kind)
	var meta: Dictionary = _debug_get_visual_task_meta(key)
	return {
		"task_id": _format_visual_task_key(key),
		"group_key": "visual:%d:%d" % [kind, band],
		"status": status,
		"task_type": "visual_task",
		"task_type_human": _debug_visual_task_type_human(kind),
		"chunk_coord": coord,
		"scope": "chunk",
		"stage": "building_visual",
		"stage_human": _debug_status_human(status),
		"age_ms": _debug_age_ms(_chunk_visual_scheduler.task_enqueued_usec.get(key, 0), now_usec),
		"priority": _debug_visual_band_human(band),
		"reason": _debug_visual_reason_human(kind, band),
		"impact": _debug_impact_for_chunk(_chunk_chebyshev_distance(coord, _player_chunk), "building_visual"),
		"state": "building_visual",
		"queue_depth": _debug_visual_queue_depth(),
		"count": 1,
		"hidden_count": 0,
		"completed_recently": false,
		"correlation_id": "chunk:%s:%d" % [coord, z_level],
		"predecessor_id": "",
		"trace_id": str(meta.get("trace_id", "")),
		"incident_id": int(meta.get("incident_id", -1)),
	}

func _debug_make_group_queue_row(
	group_key: String,
	task_type_human: String,
	stage_human: String,
	count: int,
	reason: String,
	priority: String
) -> Dictionary:
	return {
		"task_id": "group:%s" % group_key,
		"group_key": group_key,
		"status": "waiting",
		"task_type": group_key,
		"task_type_human": task_type_human,
		"chunk_coord": Vector2i(999999, 999999),
		"scope": "group",
		"stage": "grouped",
		"stage_human": stage_human,
		"age_ms": -1.0,
		"priority": priority,
		"reason": reason,
		"impact": String(WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT),
		"state": "queued",
		"queue_depth": count,
		"count": count,
		"hidden_count": maxi(0, count),
		"completed_recently": false,
		"correlation_id": "",
		"predecessor_id": "",
	}

func _debug_make_completed_queue_row(event: Dictionary, now_usec: int) -> Dictionary:
	var coord: Vector2i = event.get("coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(event.get("z", _active_z))
	return {
		"task_id": "recent:%s:%d:%s" % [coord, z_level, str(event.get("kind", ""))],
		"group_key": "recent_completion",
		"status": "completed",
		"task_type": str(event.get("kind", "completed")),
		"task_type_human": str(event.get("task_type_human", "Недавно завершено")),
		"chunk_coord": coord,
		"scope": "chunk",
		"stage": "completed",
		"stage_human": "Только что завершено",
		"age_ms": _debug_age_ms(event.get("timestamp_usec", 0), now_usec),
		"priority": str(event.get("priority", _debug_priority_label(coord))),
		"reason": str(event.get("reason", "строка скоро исчезнет из очереди")),
		"impact": str(event.get("impact", String(WorldRuntimeDiagnosticLog.IMPACT_INFORMATIONAL))),
		"state": "completed",
		"queue_depth": 0,
		"count": 1,
		"hidden_count": 0,
		"completed_recently": true,
		"correlation_id": "chunk:%s:%d" % [coord, z_level],
		"predecessor_id": "",
	}

func _debug_status_human(status: String) -> String:
	match status:
		"active":
			return "Выполняется"
		"completed":
			return "Завершено"
		_:
			return "Ожидает"

func _debug_visual_task_type_human(kind: int) -> String:
	match kind:
		VisualTaskKind.TASK_FIRST_PASS:
			return "Подготовка первого визуала чанка"
		VisualTaskKind.TASK_FULL_REDRAW:
			return "Подготовка визуала чанка"
		VisualTaskKind.TASK_BORDER_FIX:
			return "Перестройка границы чанков"
		_:
			return "Косметическое обновление чанка"

func _debug_visual_band_human(band: int) -> String:
	match band:
		VisualPriorityBand.TERRAIN_FAST:
			return "немедленный"
		VisualPriorityBand.TERRAIN_URGENT:
			return "высокий"
		VisualPriorityBand.TERRAIN_NEAR, VisualPriorityBand.FULL_NEAR, VisualPriorityBand.BORDER_FIX_NEAR:
			return "средний"
		_:
			return "низкий"

func _debug_visual_reason_human(kind: int, band: int) -> String:
	var priority_text: String = _debug_visual_band_human(band)
	match kind:
		VisualTaskKind.TASK_FIRST_PASS:
			return "чанку нужен первый читаемый визуал; приоритет %s" % priority_text
		VisualTaskKind.TASK_FULL_REDRAW:
			return "чанку нужно довести визуал до полной публикации; приоритет %s" % priority_text
		VisualTaskKind.TASK_BORDER_FIX:
			return "после соседних изменений нужно закрыть seam-границу; приоритет %s" % priority_text
		_:
			return "фоновое косметическое обновление; приоритет %s" % priority_text

func _debug_build_overlay_metrics(chunks: Array[Dictionary], queue_snapshot: Dictionary, now_usec: int) -> Dictionary:
	var loaded_count: int = 0
	var visible_count: int = 0
	var simulating_count: int = 0
	var unloading_count: int = 0
	var stalled_count: int = 0
	var worst_stage_ms: float = 0.0
	var total_stage_ms: float = 0.0
	var stage_count: int = 0
	for entry: Dictionary in chunks:
		var state: String = str(entry.get("state", ""))
		if state != "absent" and state != "unloading":
			loaded_count += 1
		if bool(entry.get("is_visible", false)):
			visible_count += 1
		if bool(entry.get("is_simulating", false)):
			simulating_count += 1
		if state == "unloading":
			unloading_count += 1
		if bool(entry.get("is_stalled", false)):
			stalled_count += 1
		var age_ms: float = float(entry.get("stage_age_ms", -1.0))
		if age_ms >= 0.0:
			worst_stage_ms = maxf(worst_stage_ms, age_ms)
			total_stage_ms += age_ms
			stage_count += 1
	var perf_snapshot: Dictionary = {}
	if WorldPerfMonitor and WorldPerfMonitor.has_method("get_debug_snapshot"):
		perf_snapshot = WorldPerfMonitor.get_debug_snapshot()
	var avg_stage_ms: float = total_stage_ms / float(stage_count) if stage_count > 0 else 0.0
	return {
		"fps": float(perf_snapshot.get("fps", Engine.get_frames_per_second())),
		"frame_time_ms": float(perf_snapshot.get("frame_time_ms", 0.0)),
		"world_update_ms": float(perf_snapshot.get("world_update_ms", 0.0)),
		"chunk_generation_ms": float(perf_snapshot.get("chunk_generation_ms", 0.0)),
		"visual_build_ms": float(perf_snapshot.get("visual_build_ms", 0.0)),
		"queue_sizes": _debug_queue_sizes(),
		"loaded_chunks": loaded_count,
		"visible_chunks": visible_count,
		"simulating_chunks": simulating_count,
		"unloading_chunks": unloading_count,
		"stalled_chunks": stalled_count,
		"worst_chunk_stage_time_ms": worst_stage_ms,
		"average_chunk_processing_time_ms": avg_stage_ms,
		"load_per_sec": _debug_count_recent_events("loaded", DEBUG_OVERLAY_RATE_WINDOW_MS, now_usec),
		"unload_per_sec": _debug_count_recent_events("unloaded", DEBUG_OVERLAY_RATE_WINDOW_MS, now_usec),
		"queue_hidden_count": int(queue_snapshot.get("hidden_count", 0)),
		"perf": perf_snapshot,
	}

func _debug_emit_chunk_event(
	action: String,
	action_human: String,
	coord: Vector2i,
	z_level: int,
	reason: String,
	impact: StringName,
	state: String,
	state_human: String,
	code_term: String,
	detail_fields: Dictionary = {}
) -> void:
	var target_human: String = "чанк %s" % [coord]
	var record: Dictionary = {
		"actor": "chunk_manager",
		"actor_human": "Система чанков",
		"action": action,
		"action_human": action_human,
		"target": "chunk",
		"target_human": target_human,
		"reason": action,
		"reason_human": reason,
		"impact": String(impact),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact),
		"state": state,
		"state_human": state_human,
		"code": code_term,
	}
	var details: Dictionary = detail_fields.duplicate()
	details["chunk_coord"] = coord
	details["z"] = z_level
	details["distance"] = _chunk_chebyshev_distance(coord, _player_chunk)
	details["priority"] = _debug_priority_label(coord)
	_debug_enrich_record_with_trace(record, details, coord, z_level)
	WorldRuntimeDiagnosticLog.emit_record(
		record,
		details,
		WorldRuntimeDiagnosticLog.SUMMARY_PREFIX,
		WorldRuntimeDiagnosticLog.DETAIL_PREFIX,
		{"cooldown_ms": 700.0}
	)

func _report_zero_tolerance_contract_breach(
	event_key: String,
	coord: Vector2i,
	z_level: int,
	action_human: String,
	reason_human: String,
	code_term: String,
	detail_fields: Dictionary = {}
) -> void:
	_debug_emit_chunk_event(
		event_key,
		action_human,
		coord,
		z_level,
		reason_human,
		WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE,
		"breached",
		"контракт нарушен",
		code_term,
		detail_fields
	)
	var message: String = "[ZeroToleranceReadiness] %s %s@z%d: %s" % [
		event_key,
		coord,
		z_level,
		reason_human,
	]
	push_error(message)
	assert(false, message)

func _is_staged_request(coord: Vector2i, z_level: int) -> bool:
	return _chunk_streaming_service != null \
		and _chunk_streaming_service.staged_coord == _canonical_chunk_coord(coord) \
		and _chunk_streaming_service.staged_z == z_level

func _is_generating_request(coord: Vector2i, z_level: int) -> bool:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	return _chunk_streaming_service != null \
		and _chunk_streaming_service.gen_active_tasks.has(canonical_coord) \
		and int(_chunk_streaming_service.gen_active_z_levels.get(canonical_coord, INVALID_Z_LEVEL)) == z_level

func _clear_staged_request() -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.clear_staged_request()

func is_topology_ready() -> bool:
	return _chunk_topology_service != null and _chunk_topology_service.is_topology_ready(_active_z)

func get_mountain_key_at_tile(tile_pos: Vector2i) -> Vector2i:
	tile_pos = _canonical_tile(tile_pos)
	if _chunk_topology_service == null:
		return Vector2i(999999, 999999)
	return _chunk_topology_service.get_mountain_key_at_tile(_active_z, tile_pos)

func get_mountain_tiles(mountain_key: Vector2i) -> Dictionary:
	if _chunk_topology_service == null:
		return {}
	return _chunk_topology_service.get_mountain_tiles(_active_z, mountain_key)

func get_mountain_open_tiles(mountain_key: Vector2i) -> Dictionary:
	if _chunk_topology_service == null:
		return {}
	return _chunk_topology_service.get_mountain_open_tiles(_active_z, mountain_key)

## Возвращает player-local derived product для loaded underground pocket.
## Не использует `mountain_key` как reveal-domain и не является shared world truth.
func query_local_underground_zone(seed_tile: Vector2i) -> Dictionary:
	var started_usec: int = WorldPerfProbe.begin()
	seed_tile = _canonical_tile(seed_tile)
	if not is_tile_loaded(seed_tile):
		WorldPerfProbe.end("ChunkManager.query_local_underground_zone", started_usec)
		return {}
	if _native_loaded_open_pocket_query == null:
		var error_message: String = "Chunk runtime requires %s for query_local_underground_zone(). Build or load the world GDExtension before running the game." % [String(NATIVE_LOADED_OPEN_POCKET_QUERY_CLASS)]
		push_error(error_message)
		WorldPerfProbe.end("ChunkManager.query_local_underground_zone", started_usec)
		return {}
	var zone: Dictionary = _native_loaded_open_pocket_query.call(
		"query_open_pocket",
		seed_tile,
		LOADED_OPEN_POCKET_QUERY_TILE_CAP,
		_resolve_world_wrap_width_tiles()
	) as Dictionary
	WorldPerfProbe.end("ChunkManager.query_local_underground_zone", started_usec)
	if zone.is_empty():
		return {}
	zone["zone_kind"] = &"loaded_open_pocket"
	zone["seed_tile"] = seed_tile
	return zone

func try_harvest_at_world(world_pos: Vector2) -> Dictionary:
	var started_usec: int = WorldPerfProbe.begin()
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var chunk: Chunk = get_chunk_at_tile(tile_pos)
	if not chunk:
		return {}
	var local_tile: Vector2i = chunk.global_to_local(tile_pos)
	chunk.set_mining_write_authorized(true)
	var result: Dictionary = chunk.try_mine_at(local_tile)
	chunk.set_mining_write_authorized(false)
	if result.is_empty():
		return {}
	_invalidate_cover_edge_set_around_world_tile(tile_pos, chunk)
	# Same-chunk neighbor re-normalization (MINED_FLOOR <-> MOUNTAIN_ENTRANCE)
	chunk.refresh_open_neighbors_with_operation_cache(local_tile)
	if chunk.redraw_mining_patch(local_tile):
		# Interactive mining must stay on the authoritative mutation path only.
		# Visual repair escalates to the queued border-fix owner path.
		_ensure_chunk_border_fix_task(chunk, _active_z, true)
	# Cross-chunk seam: normalize + redraw affected neighbor chunks
	_seam_normalize_and_redraw(tile_pos, local_tile, chunk)
	_on_mountain_tile_changed(tile_pos, int(result["old_type"]), int(result["new_type"]))
	EventBus.mountain_tile_mined.emit(tile_pos, int(result["old_type"]), int(result["new_type"]))
	# Underground fog: reveal newly mined tile + neighbors
	if _active_z != 0:
		var reveal_tiles: Array = [tile_pos]
		for offset: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
				Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			reveal_tiles.append(_offset_tile(tile_pos, offset))
		_fog_state.force_reveal(reveal_tiles)
		var visible_tiles: Dictionary = {}
		for t: Variant in reveal_tiles:
			var rv_tile: Vector2i = t as Vector2i
			visible_tiles[rv_tile] = true
		_apply_underground_fog_visible_tiles(visible_tiles)
	WorldPerfProbe.end("ChunkManager.try_harvest_at_world", started_usec)
	return {
		"item_id": str(WorldGenerator.balance.rock_drop_item_id),
		"amount": WorldGenerator.balance.rock_drop_amount,
	}

func _make_border_fix_reason_key(source_coord: Vector2i, z_level: int, tag: StringName = &"seam") -> String:
	return "%d:%d:%d:%s" % [source_coord.x, source_coord.y, z_level, String(tag)]

func _append_unique_chunk_coord(coords: Array[Vector2i], coord: Vector2i) -> void:
	if coord not in coords:
		coords.append(coord)

func _border_dirty_tiles_for_edge(chunk_size: int, edge_dir: Vector2i) -> Dictionary:
	var dirty: Dictionary = {}
	if edge_dir == Vector2i.LEFT:
		for y: int in range(chunk_size):
			dirty[Vector2i(0, y)] = true
	elif edge_dir == Vector2i.RIGHT:
		for y: int in range(chunk_size):
			dirty[Vector2i(chunk_size - 1, y)] = true
	elif edge_dir == Vector2i.UP:
		for x: int in range(chunk_size):
			dirty[Vector2i(x, 0)] = true
	elif edge_dir == Vector2i.DOWN:
		for x: int in range(chunk_size):
			dirty[Vector2i(x, chunk_size - 1)] = true
	return dirty

func _invalidate_cover_edge_set_around_world_tile(tile_pos: Vector2i, source_chunk: Chunk) -> void:
	var dirty_by_chunk: Dictionary = {}
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var affected_tile: Vector2i = _offset_tile(tile_pos, Vector2i(offset_x, offset_y))
			var affected_chunk: Chunk = get_chunk_at_tile(affected_tile)
			if not affected_chunk or affected_chunk == source_chunk:
				continue
			var chunk_coord: Vector2i = affected_chunk.chunk_coord
			var chunk_entry: Dictionary
			if dirty_by_chunk.has(chunk_coord):
				chunk_entry = dirty_by_chunk[chunk_coord] as Dictionary
			else:
				chunk_entry = {
					"chunk": affected_chunk,
					"dirty_tiles": {},
				}
				dirty_by_chunk[chunk_coord] = chunk_entry
			var dirty_tiles: Dictionary = chunk_entry.get("dirty_tiles", {}) as Dictionary
			dirty_tiles[affected_chunk.global_to_local(affected_tile)] = true
			chunk_entry["dirty_tiles"] = dirty_tiles
			dirty_by_chunk[chunk_coord] = chunk_entry
	for entry_variant: Variant in dirty_by_chunk.values():
		var entry: Dictionary = entry_variant as Dictionary
		var affected_chunk: Chunk = entry.get("chunk") as Chunk
		var dirty_tiles: Dictionary = entry.get("dirty_tiles", {}) as Dictionary
		if affected_chunk:
			affected_chunk._mark_cover_edge_set_dirty_tiles(dirty_tiles)

func _resolve_runtime_diag_scope(coord: Vector2i) -> StringName:
	if _player_chunk == Vector2i(99999, 99999):
		return &"far_runtime_backlog"
	var player_coord: Vector2i = _canonical_chunk_coord(_player_chunk)
	if coord == player_coord:
		return &"player_chunk"
	var dx: int = _chunk_wrap_delta_x(coord.x, player_coord.x)
	var dy: int = coord.y - player_coord.y
	if maxi(absi(dx), absi(dy)) <= 1:
		return &"adjacent_loaded_chunk"
	return &"far_runtime_backlog"

func _resolve_runtime_diag_impact(scope: StringName) -> StringName:
	if scope == &"far_runtime_backlog":
		return WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT
	return WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE

func _pick_runtime_diag_target_coord(coords: Array[Vector2i]) -> Vector2i:
	if coords.is_empty():
		return Vector2i.ZERO
	var player_coord: Vector2i = _canonical_chunk_coord(_player_chunk)
	var best_coord: Vector2i = coords[0]
	var best_score: int = 1_000_000
	for coord: Vector2i in coords:
		var dx: int = _chunk_wrap_delta_x(coord.x, player_coord.x)
		var dy: int = coord.y - player_coord.y
		var score: int = dx * dx + dy * dy
		if score < best_score:
			best_score = score
			best_coord = coord
	return best_coord

func _describe_runtime_diag_actor(actor_key: StringName) -> String:
	match String(actor_key):
		"stream_load":
			return "Потоковая догрузка мира"
		"seam_mining_async":
			return "Добыча на границе чанка"
		_:
			var human_text: String = WorldRuntimeDiagnosticLog.humanize_known_term(String(actor_key))
			if human_text.is_empty():
				return "Диагностика мира"
			return human_text.substr(0, 1).to_upper() + human_text.substr(1)

func _emit_border_fix_queue_diag(
	actor_key: StringName,
	source_coord: Vector2i,
	queued_coords: Array[Vector2i],
	reason_human: String,
	follow_up_terms: Array[String],
	source_tile: Vector2i = Vector2i(999999, 999999)
) -> void:
	if queued_coords.is_empty():
		return
	var target_coord: Vector2i = _pick_runtime_diag_target_coord(queued_coords)
	var trace_context: Dictionary = _debug_ensure_forensics_context(
		target_coord,
		_active_z,
		String(actor_key),
		"visual_task_enqueued",
		{
			"queue_reason": reason_human,
			"follow_up": ",".join(follow_up_terms),
		},
		queued_coords
	)
	var scope: StringName = _resolve_runtime_diag_scope(target_coord)
	var impact_key: StringName = _resolve_runtime_diag_impact(scope)
	var code_term: String = "border_fix" if "border_fix" in follow_up_terms else (
		follow_up_terms[0] if not follow_up_terms.is_empty() else ""
	)
	var action_human: String = "поставила в очередь %s" % [
		WorldRuntimeDiagnosticLog.describe_term_list(follow_up_terms)
	]
	if follow_up_terms == ["border_fix"]:
		action_human = "поставила в очередь правку границы чанка"
	elif follow_up_terms == ["local_patch", "border_fix"]:
		action_human = "поставила в очередь локальную правку и правку границы чанка"
	var record: Dictionary = {
		"actor": String(actor_key),
		"actor_human": _describe_runtime_diag_actor(actor_key),
		"action": "queue_follow_up",
		"action_human": action_human,
		"target": String(scope),
		"target_human": WorldRuntimeDiagnosticLog.describe_chunk_scope(scope, target_coord),
		"reason": "queued_not_applied",
		"reason_human": reason_human,
		"impact": String(impact_key),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact_key),
		"state": "queued",
		"state_human": "очередь ещё не применена",
		"severity": String(WorldRuntimeDiagnosticLog.SEVERITY_FOLLOW_UP),
		"severity_human": WorldRuntimeDiagnosticLog.humanize_severity(WorldRuntimeDiagnosticLog.SEVERITY_FOLLOW_UP),
		"code": code_term,
	}
	var detail_fields: Dictionary = {
		"follow_up": ",".join(follow_up_terms),
		"queued_chunks": WorldRuntimeDiagnosticLog.format_coord_list(queued_coords),
		"queued_count": queued_coords.size(),
		"queue_border_fix_far": _chunk_visual_scheduler.q_border_fix_far.size(),
		"queue_border_fix_near": _chunk_visual_scheduler.q_border_fix_near.size(),
		"source_chunk": str(source_coord),
		"target_scope": String(scope),
		"z": _active_z,
	}
	if source_tile != Vector2i(999999, 999999):
		detail_fields["source_tile"] = str(source_tile)
	_debug_enrich_record_with_trace(record, detail_fields, target_coord, _active_z, trace_context)
	WorldRuntimeDiagnosticLog.emit_record(record, detail_fields)
	_debug_record_forensics_event(
		trace_context,
		String(actor_key),
		"visual_task_enqueued",
		target_coord,
		_active_z,
		{
			"follow_up": ",".join(follow_up_terms),
			"queued_count": queued_coords.size(),
			"reason_human": reason_human,
		},
		queued_coords
	)

## Instead of synchronously redrawing all border tiles of 4 neighbors (256
## tiles, 20-49ms), mark dirty tiles and add neighbors to the progressive
## redraw queue. Border tiles will be processed by _tick_redraws() over
## the next 1-2 frames. Used only in streaming finalize path.
## (boot_fast_first_playable_spec Iteration 3, change 3A)
func _enqueue_neighbor_border_redraws(coord: Vector2i) -> void:
	if _chunk_seam_service != null:
		_chunk_seam_service.enqueue_neighbor_border_redraws(coord)

func _seam_normalize_and_redraw(tile_pos: Vector2i, local_tile: Vector2i, source_chunk: Chunk) -> void:
	if _chunk_seam_service != null:
		_chunk_seam_service.seam_normalize_and_redraw(tile_pos, local_tile, source_chunk)

func _process_seam_refresh_queue_step() -> bool:
	return _chunk_seam_service.process_queue_step() if _chunk_seam_service != null else false

func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	return get_terrain_type_at_global(tile_pos) == TileGenData.TerrainType.ROCK

func is_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(world_pos)
	return _is_walkable_terrain(get_terrain_type_at_global(tile_pos))

## Deferred runtime startup after required native capabilities pass validation.
func _deferred_init() -> void:
	if not _native_runtime_capabilities_valid:
		_block_runtime_startup()
		return
	_player = PlayerAuthority.get_local_player()
	_cache_world_generator_capabilities()
	_build_world_tilesets()
	_build_fog_tileset()
	_setup_native_topology_builder()
	_setup_flora_builder()
	_rebuild_native_loaded_open_pocket_query_cache()
	_initialized = _native_runtime_capabilities_valid and _terrain_tileset != null and _overlay_tileset != null
	if _initialized:
		set_process(true)
		_register_budget_jobs()
		_fog_job_id = FrameBudgetDispatcher.register_job(
			RuntimeWorkTypes.CATEGORY_TOPOLOGY,
			1.0,
			_fog_update_tick,
			&"underground.fog_update",
			RuntimeWorkTypes.CadenceKind.NEAR_PLAYER,
			RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
			false,
			"Underground fog update"
		)
	else:
		set_process(false)

func _block_runtime_startup() -> void:
	_initialized = false
	if _chunk_topology_service != null:
		_chunk_topology_service.deactivate()
	set_process(false)
	set_physics_process(false)
	push_error("ChunkManager startup blocked: required native runtime capabilities are unavailable.")

func _block_legacy_chunk_runtime_fallback(coord: Vector2i, z_level: int, reason: String) -> void:
	var message: String = "Zero-Tolerance Chunk Readiness R1 blocked legacy chunk runtime fallback for %s@z%d (%s). Player-reachable chunks must not rely on fallback generation/publication paths." % [
		coord,
		z_level,
		reason,
	]
	push_error(message)
	assert(false, message)

func _get(property: StringName) -> Variant:
	match property:
		&"_native_topology_active":
			return _chunk_topology_service != null and _chunk_topology_service.is_native_enabled()
		&"_native_topology_dirty":
			return _chunk_topology_service != null and _chunk_topology_service.is_dirty()
		_:
			return null

func _require_native_class(native_class_name: StringName, required_methods: Array[String], subsystem_label: String) -> RefCounted:
	var error_message: String = "Chunk runtime requires %s for %s. Build or load the world GDExtension before running the game." % [
		String(native_class_name),
		subsystem_label,
	]
	if not ClassDB.class_exists(native_class_name):
		push_error(error_message)
		return null
	var instance: RefCounted = ClassDB.instantiate(native_class_name) as RefCounted
	if instance == null:
		push_error(error_message)
		return null
	for method_name: String in required_methods:
		if instance.has_method(method_name):
			continue
		push_error("%s Missing method: %s.%s()." % [error_message, String(native_class_name), method_name])
		return null
	return instance

func _validate_required_native_capabilities() -> bool:
	var native_topology_builder: RefCounted = _require_native_class(
		NATIVE_TOPOLOGY_BUILDER_CLASS,
		[
			"clear",
			"set_chunk",
			"remove_chunk",
			"update_tile",
			"ensure_built",
			"get_mountain_key_at_tile",
			"get_mountain_tiles",
			"get_mountain_open_tiles",
			"rebuild_topology",
		],
		"surface topology rebuild"
	)
	if _chunk_topology_service != null:
		_chunk_topology_service.set_validated_native_builder(native_topology_builder)
	_native_loaded_open_pocket_query = _require_native_class(
		NATIVE_LOADED_OPEN_POCKET_QUERY_CLASS,
		["clear", "set_chunk", "remove_chunk", "update_tile", "query_open_pocket"],
		"query_local_underground_zone()"
	)
	_native_loaded_open_pocket_query_available = _native_loaded_open_pocket_query != null
	return (_chunk_topology_service != null and _chunk_topology_service.is_available()) \
		and _native_loaded_open_pocket_query_available

func _cache_world_generator_capabilities() -> void:
	_wg_has_canonicalize_tile = false
	_wg_has_canonicalize_chunk_coord = false
	_wg_has_offset_tile = false
	_wg_has_offset_chunk_coord = false
	_wg_has_tile_to_local_in_chunk = false
	_wg_has_chunk_local_to_tile = false
	_wg_has_chunk_wrap_delta_x = false
	_wg_has_get_world_wrap_width_tiles = false
	_wg_has_get_registered_biomes = false
	_wg_has_create_detached_chunk_content_builder = false
	_wg_has_resolve_biome_with_channels = false
	_wg_chunk_biome_method = &""
	_wg_tile_biome_method = &""
	if WorldGenerator == null:
		return
	_wg_has_canonicalize_tile = WorldGenerator.has_method("canonicalize_tile")
	_wg_has_canonicalize_chunk_coord = WorldGenerator.has_method("canonicalize_chunk_coord")
	_wg_has_offset_tile = WorldGenerator.has_method("offset_tile")
	_wg_has_offset_chunk_coord = WorldGenerator.has_method("offset_chunk_coord")
	_wg_has_tile_to_local_in_chunk = WorldGenerator.has_method("tile_to_local_in_chunk")
	_wg_has_chunk_local_to_tile = WorldGenerator.has_method("chunk_local_to_tile")
	_wg_has_chunk_wrap_delta_x = WorldGenerator.has_method("chunk_wrap_delta_x")
	_wg_has_get_world_wrap_width_tiles = WorldGenerator.has_method("get_world_wrap_width_tiles")
	_wg_has_get_registered_biomes = WorldGenerator.has_method("get_registered_biomes")
	_wg_has_create_detached_chunk_content_builder = WorldGenerator.has_method("create_detached_chunk_content_builder")
	_wg_has_resolve_biome_with_channels = WorldGenerator.has_method("resolve_biome") and WorldGenerator.has_method("sample_world_channels")
	for method_name: String in ["get_dominant_biome_for_chunk", "get_chunk_biome"]:
		if not WorldGenerator.has_method(method_name):
			continue
		_wg_chunk_biome_method = StringName(method_name)
		break
	for method_name: String in [
		"get_tile_biome",
		"resolve_biome_at_tile",
		"get_biome_at_tile",
		"resolve_biome_for_tile",
	]:
		if not WorldGenerator.has_method(method_name):
			continue
		_wg_tile_biome_method = StringName(method_name)
		break

func _resolve_world_wrap_width_tiles() -> int:
	if WorldGenerator and _wg_has_get_world_wrap_width_tiles:
		return int(WorldGenerator.get_world_wrap_width_tiles())
	return 0

func _build_world_tilesets() -> void:
	_tileset_bundles_by_biome.clear()
	if not WorldGenerator or not WorldGenerator.balance:
		return
	var registered_biomes: Array[BiomeData] = []
	if _wg_has_get_registered_biomes:
		registered_biomes = WorldGenerator.get_registered_biomes()
	var biome: BiomeData = _get_default_biome()
	if not biome:
		return
	if registered_biomes.is_empty():
		registered_biomes.append(biome)
	_terrain_tileset = ChunkTilesetFactory.build_surface_tileset(WorldGenerator.balance, registered_biomes)
	_overlay_tileset = ChunkTilesetFactory.build_overlay_tileset(WorldGenerator.balance, biome)
	_underground_terrain_tileset = ChunkTilesetFactory.build_underground_terrain_tileset(WorldGenerator.balance, biome)
	for biome_candidate: BiomeData in registered_biomes:
		_get_or_build_tileset_bundle(biome_candidate)

func _get_default_biome() -> BiomeData:
	if WorldGenerator and WorldGenerator.current_biome:
		return WorldGenerator.current_biome
	if WorldGenerator and _wg_has_get_registered_biomes:
		var registered_biomes: Array[BiomeData] = WorldGenerator.get_registered_biomes()
		if not registered_biomes.is_empty():
			return registered_biomes[0]
	for biome_key: Variant in _tileset_bundles_by_biome:
		var bundle: Dictionary = _tileset_bundles_by_biome.get(biome_key, {}) as Dictionary
		var cached_biome: BiomeData = bundle.get("biome") as BiomeData
		if cached_biome:
			return cached_biome
	return null

func _get_biome_cache_key(biome: BiomeData) -> StringName:
	if not biome:
		return &""
	if not biome.id.is_empty():
		return biome.id
	if not biome.resource_path.is_empty():
		return StringName(biome.resource_path)
	return StringName("%s:%d" % [biome.get_class(), biome.get_instance_id()])

func _get_or_build_tileset_bundle(biome: BiomeData) -> Dictionary:
	if not biome or not WorldGenerator or not WorldGenerator.balance:
		return {}
	var biome_key: StringName = _get_biome_cache_key(biome)
	var cached: Dictionary = _tileset_bundles_by_biome.get(biome_key, {}) as Dictionary
	if not cached.is_empty():
		return cached
	var bundle := {
		"biome": biome,
		"terrain": _terrain_tileset,
		"overlay": _overlay_tileset,
		"underground_terrain": ChunkTilesetFactory.build_underground_terrain_tileset(WorldGenerator.balance, biome),
	}
	_tileset_bundles_by_biome[biome_key] = bundle
	return bundle

func _coerce_biome_candidate(candidate: Variant) -> BiomeData:
	if candidate is BiomeData:
		return candidate as BiomeData
	if candidate is Dictionary:
		var candidate_dict: Dictionary = candidate as Dictionary
		if candidate_dict.get("biome") is BiomeData:
			return candidate_dict.get("biome") as BiomeData
	if candidate != null and candidate is Object:
		var object_biome: Variant = (candidate as Object).get("biome")
		if object_biome is BiomeData:
			return object_biome as BiomeData
	return null

func _get_chunk_center_tile(chunk_coord: Vector2i) -> Vector2i:
	var origin: Vector2i = WorldGenerator.chunk_to_tile_origin(chunk_coord)
	var half_chunk: int = maxi(0, WorldGenerator.balance.chunk_size_tiles / 2)
	return WorldGenerator.offset_tile(origin, Vector2i(half_chunk, half_chunk))

func _resolve_chunk_biome(coord: Vector2i, z_level: int) -> BiomeData:
	if z_level != 0:
		return _get_default_biome()
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	var resolved_biome: BiomeData = _resolve_chunk_biome_from_world_generator(canonical_coord)
	if resolved_biome:
		return resolved_biome
	return _get_default_biome()

func _resolve_chunk_biome_from_world_generator(chunk_coord: Vector2i) -> BiomeData:
	if not WorldGenerator:
		return null
	if _wg_chunk_biome_method != &"":
		var direct_candidate: Variant = WorldGenerator.call(_wg_chunk_biome_method, chunk_coord)
		var direct_biome: BiomeData = _coerce_biome_candidate(direct_candidate)
		if direct_biome:
			return direct_biome
	var center_tile: Vector2i = _get_chunk_center_tile(chunk_coord)
	if _wg_tile_biome_method != &"":
		var tile_candidate: Variant = WorldGenerator.call(_wg_tile_biome_method, center_tile)
		var tile_biome: BiomeData = _coerce_biome_candidate(tile_candidate)
		if tile_biome:
			return tile_biome
	if _wg_has_resolve_biome_with_channels:
		var channels = WorldGenerator.sample_world_channels(center_tile)
		var resolved_candidate: Variant = WorldGenerator.call("resolve_biome", center_tile, channels)
		var resolved_biome: BiomeData = _coerce_biome_candidate(resolved_candidate)
		if resolved_biome:
			return resolved_biome
	return null

func _build_fog_tileset() -> void:
	if not WorldGenerator or not WorldGenerator.balance:
		return
	_fog_tileset = ChunkTilesetFactory.create_fog_tileset(WorldGenerator.balance.tile_size)

func _is_walkable_terrain(terrain_type: int) -> bool:
	return terrain_type != TileGenData.TerrainType.ROCK \
		and terrain_type != TileGenData.TerrainType.WATER

func _fog_update_tick() -> bool:
	if _active_z == 0 or not _player:
		return false
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var delta: Dictionary = _fog_state.update(player_tile)
	var newly_visible: Dictionary = delta.get("newly_visible", {})
	var newly_discovered: Dictionary = delta.get("newly_discovered", {})
	if newly_visible.is_empty() and newly_discovered.is_empty():
		return false
	_apply_underground_fog_visible_tiles(newly_visible)
	_apply_underground_fog_discovered_tiles(newly_discovered)
	return false

func _apply_underground_fog_visible_tiles(global_tiles: Dictionary) -> void:
	var tiles_by_chunk: Dictionary = _collect_underground_revealable_tiles(global_tiles)
	for chunk_coord: Vector2i in tiles_by_chunk:
		var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
		if chunk:
			chunk.apply_fog_visible(tiles_by_chunk[chunk_coord] as Dictionary)

func _apply_underground_fog_discovered_tiles(global_tiles: Dictionary) -> void:
	var tiles_by_chunk: Dictionary = _collect_underground_revealable_tiles(global_tiles)
	for chunk_coord: Vector2i in tiles_by_chunk:
		var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
		if chunk:
			chunk.apply_fog_discovered(tiles_by_chunk[chunk_coord] as Dictionary)

func _collect_underground_revealable_tiles(global_tiles: Dictionary) -> Dictionary:
	var candidate_tiles: Dictionary = global_tiles.duplicate()
	for global_tile: Vector2i in global_tiles:
		_expand_underground_wall_halo(_canonical_tile(global_tile), candidate_tiles)
	var tiles_by_chunk: Dictionary = {}
	for global_tile: Vector2i in candidate_tiles:
		var canonical_tile: Vector2i = _canonical_tile(global_tile)
		var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(canonical_tile)
		var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
		if not chunk:
			continue
		var local: Vector2i = chunk.global_to_local(canonical_tile)
		if not chunk.is_fog_revealable(local):
			continue
		if not tiles_by_chunk.has(chunk_coord):
			tiles_by_chunk[chunk_coord] = {}
		(tiles_by_chunk[chunk_coord] as Dictionary)[local] = true
	return tiles_by_chunk

func _expand_underground_wall_halo(global_tile: Vector2i, candidate_tiles: Dictionary) -> void:
	global_tile = _canonical_tile(global_tile)
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
	if not chunk:
		return
	var local: Vector2i = chunk.global_to_local(global_tile)
	var terrain: int = chunk.get_terrain_type_at(local)
	if terrain != TileGenData.TerrainType.MINED_FLOOR \
		and terrain != TileGenData.TerrainType.MOUNTAIN_ENTRANCE \
		and terrain != TileGenData.TerrainType.GROUND:
		return
	for offset: Vector2i in [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
	]:
		candidate_tiles[_offset_tile(global_tile, offset)] = true

func _setup_native_topology_builder() -> void:
	if _chunk_topology_service != null:
		_chunk_topology_service.setup_native_builder()

func _setup_flora_builder() -> void:
	_flora_texture_path_by_entry_id.clear()
	_flora_texture_path_cache_ready = false
	if WorldGenerator and WorldGenerator._is_initialized:
		_flora_builder = ChunkFloraBuilderScript.new()
		_flora_builder.initialize(WorldGenerator.world_seed)

func _resolve_flora_tile_size() -> int:
	return WorldGenerator.balance.tile_size if WorldGenerator and WorldGenerator.balance else 0

func _create_detached_flora_builder() -> ChunkFloraBuilderScript:
	if WorldGenerator == null or not WorldGenerator._is_initialized:
		return null
	var flora_builder := ChunkFloraBuilderScript.new()
	flora_builder.initialize(WorldGenerator.world_seed)
	return flora_builder

func _compute_flora_for_chunk(chunk: Chunk, build_result: ChunkBuildResult) -> ChunkFloraResultScript:
	if _flora_builder == null or build_result == null or not build_result.is_valid():
		return null
	var flora_result: ChunkFloraResultScript = _compute_flora_result(
		_flora_builder,
		build_result.canonical_chunk_coord,
		build_result.chunk_size,
		build_result.base_tile,
		build_result.biome,
		build_result.variation,
		build_result.terrain,
		build_result.flora_density_values,
		build_result.flora_modulation_values,
		build_result.secondary_biome,
		build_result.ecotone_values
	)
	if flora_result != null:
		chunk.set_flora_result(flora_result)
	return flora_result

func _flora_result_from_payload(flora_payload: Dictionary) -> ChunkFloraResultScript:
	if flora_payload.is_empty():
		return null
	return ChunkFloraResultScript.from_serialized_payload(
		_hydrate_flora_payload_texture_paths(flora_payload)
	)

func _build_native_flora_payload_from_placements(chunk_coord: Vector2i, native_data: Dictionary) -> Dictionary:
	if native_data.is_empty():
		return {}
	var placements: Array = (native_data.get(ChunkFinalPacketScript.FLORA_PLACEMENTS_KEY, []) as Array).duplicate(true)
	if placements.is_empty():
		return {}
	return ChunkFloraResultScript.build_serialized_payload_from_placements(
		chunk_coord,
		int(native_data.get("chunk_size", 0)),
		placements,
		_resolve_flora_tile_size()
	)

func _complete_surface_final_packet_publication_payload(chunk_coord: Vector2i, native_data: Dictionary) -> Dictionary:
	if native_data.is_empty():
		return {}
	if not native_data.has(ChunkFinalPacketScript.FLORA_PLACEMENTS_KEY):
		_block_legacy_chunk_runtime_fallback(chunk_coord, 0, "missing_native_flora_placements")
		return {}
	if not native_data.has(ChunkFinalPacketScript.FLORA_PAYLOAD_KEY):
		var flora_placements: Array = native_data.get(ChunkFinalPacketScript.FLORA_PLACEMENTS_KEY, []) as Array
		if not flora_placements.is_empty():
			var canonical_chunk: Vector2i = native_data.get("canonical_chunk_coord", chunk_coord) as Vector2i
			var flora_payload: Dictionary = _build_native_flora_payload_from_placements(canonical_chunk, native_data)
			if flora_payload.is_empty():
				_block_legacy_chunk_runtime_fallback(chunk_coord, 0, "missing_terminal_flora_payload")
				return {}
			native_data[ChunkFinalPacketScript.FLORA_PAYLOAD_KEY] = flora_payload
	if not ChunkFinalPacketScript.validate_terminal_surface_packet(
		native_data,
		"ChunkManager._complete_surface_final_packet_publication_payload(%s)" % [chunk_coord]
	):
		_block_legacy_chunk_runtime_fallback(chunk_coord, 0, "surface_terminal_packet_contract_invalid")
		return {}
	return native_data

func _compute_flora_result(
	flora_builder: ChunkFloraBuilderScript,
	chunk_coord: Vector2i,
	chunk_size: int,
	base_tile: Vector2i,
	biome_bytes: PackedByteArray,
	variation_bytes: PackedByteArray,
	terrain_bytes: PackedByteArray,
	flora_density_values: PackedFloat32Array,
	flora_modulation_values: PackedFloat32Array,
	secondary_biome_bytes: PackedByteArray = PackedByteArray(),
	ecotone_values: PackedFloat32Array = PackedFloat32Array()
) -> ChunkFloraResultScript:
	if flora_builder == null or WorldGenerator == null or chunk_size <= 0:
		return null
	var tile_count: int = chunk_size * chunk_size
	var secondary_biome_ok: bool = secondary_biome_bytes.is_empty() or secondary_biome_bytes.size() == tile_count
	var ecotone_values_ok: bool = ecotone_values.is_empty() or ecotone_values.size() == tile_count
	if terrain_bytes.size() != tile_count \
		or biome_bytes.size() != tile_count \
		or variation_bytes.size() != tile_count \
		or flora_density_values.size() != tile_count \
		or flora_modulation_values.size() != tile_count \
		or not secondary_biome_ok \
		or not ecotone_values_ok:
		return null
	var biome_palette: Array[BiomeData] = WorldGenerator.get_registered_biomes()
	return flora_builder.compute_placements(
		chunk_coord,
		chunk_size,
		base_tile,
		terrain_bytes,
		biome_palette,
		biome_bytes,
		variation_bytes,
		flora_density_values,
		flora_modulation_values,
		secondary_biome_bytes,
		ecotone_values
	)

func _hydrate_flora_placements_with_texture_paths(serialized_placements: Array) -> Array:
	if serialized_placements.is_empty():
		return serialized_placements
	var hydrated_placements: Array = []
	var changed: bool = false
	for placement_variant: Variant in serialized_placements:
		var placement: Dictionary = placement_variant as Dictionary
		if placement.is_empty():
			hydrated_placements.append(placement)
			continue
		if not bool(placement.get("is_flora", true)):
			hydrated_placements.append(placement)
			continue
		var texture_path: String = String(placement.get("texture_path", ""))
		if not texture_path.is_empty():
			hydrated_placements.append(placement)
			continue
		var entry_id: StringName = placement.get("entry_id", &"") as StringName
		var resolved_texture_path: String = _get_flora_texture_path_for_entry(entry_id)
		if resolved_texture_path.is_empty():
			hydrated_placements.append(placement)
			continue
		var hydrated_placement: Dictionary = placement.duplicate(true)
		hydrated_placement["texture_path"] = resolved_texture_path
		hydrated_placements.append(hydrated_placement)
		changed = true
	if not changed:
		return serialized_placements
	return hydrated_placements

func _hydrate_flora_payload_texture_paths(flora_payload: Dictionary) -> Dictionary:
	if flora_payload.is_empty():
		return flora_payload
	var placements: Array = flora_payload.get("placements", []) as Array
	if placements.is_empty():
		return flora_payload
	var hydrated_placements: Array = _hydrate_flora_placements_with_texture_paths(placements)
	if hydrated_placements == placements:
		return flora_payload
	var tile_size: int = int(flora_payload.get("render_packet_tile_size", 0))
	if tile_size <= 0:
		tile_size = _resolve_flora_tile_size()
	return ChunkFloraResultScript.build_serialized_payload_from_placements(
		flora_payload.get("chunk_coord", Vector2i.ZERO) as Vector2i,
		int(flora_payload.get("chunk_size", 0)),
		hydrated_placements,
		tile_size
	)

func _get_flora_texture_path_for_entry(entry_id: StringName) -> String:
	if entry_id == &"":
		return ""
	_ensure_flora_texture_path_cache()
	return String(_flora_texture_path_by_entry_id.get(entry_id, ""))

func _ensure_flora_texture_path_cache() -> void:
	if _flora_texture_path_cache_ready:
		return
	_flora_texture_path_cache_ready = true
	_flora_texture_path_by_entry_id.clear()
	if not WorldGenerator or not _wg_has_get_registered_biomes or not FloraDecorRegistry:
		return
	var seen_flora_set_ids: Dictionary = {}
	var registered_biomes: Array[BiomeData] = WorldGenerator.get_registered_biomes()
	for biome: BiomeData in registered_biomes:
		if biome == null:
			continue
		for flora_set_id: StringName in biome.flora_set_ids:
			if seen_flora_set_ids.has(flora_set_id):
				continue
			seen_flora_set_ids[flora_set_id] = true
			var flora_set: FloraSetData = FloraDecorRegistry.get_flora_set(flora_set_id) as FloraSetData
			if flora_set == null:
				continue
			for entry_resource: Resource in flora_set.entries:
				var entry: FloraEntry = entry_resource as FloraEntry
				if entry == null or entry.id == &"" or _flora_texture_path_by_entry_id.has(entry.id):
					continue
				var texture_path: String = entry.texture.resource_path if entry.texture != null else ""
				_flora_texture_path_by_entry_id[entry.id] = texture_path

func _is_native_topology_enabled() -> bool:
	return _chunk_topology_service != null and _chunk_topology_service.is_native_enabled()

func _rebuild_native_loaded_open_pocket_query_cache() -> void:
	if _native_loaded_open_pocket_query == null:
		return
	_native_loaded_open_pocket_query.call("clear")
	for coord_variant: Variant in _loaded_chunks.keys():
		var chunk_coord: Vector2i = coord_variant as Vector2i
		var chunk: Chunk = _loaded_chunks.get(chunk_coord) as Chunk
		if chunk == null:
			continue
		_native_loaded_open_pocket_query.call(
			"set_chunk",
			chunk_coord,
			chunk.get_terrain_bytes(),
			chunk.get_chunk_size()
		)

func _sync_native_loaded_open_pocket_query_chunk(coord: Vector2i, chunk: Chunk, z_level: int) -> void:
	if _native_loaded_open_pocket_query == null or chunk == null or z_level != _active_z:
		return
	_native_loaded_open_pocket_query.call(
		"set_chunk",
		coord,
		chunk.get_terrain_bytes(),
		chunk.get_chunk_size()
	)

func _remove_native_loaded_open_pocket_query_chunk(coord: Vector2i, z_level: int) -> void:
	if _native_loaded_open_pocket_query == null or z_level != _active_z:
		return
	_native_loaded_open_pocket_query.call("remove_chunk", coord)

func _clear_visual_task_state() -> void:
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.clear_runtime_state()
	if _chunk_seam_service != null:
		_chunk_seam_service.clear()
	if _chunk_debug_system != null:
		_chunk_debug_system.clear_visual_task_meta()


func _is_player_near_visual_chunk(coord: Vector2i, z_level: int) -> bool:
	if z_level != _active_z or _player_chunk == Vector2i(99999, 99999):
		return false
	return _chunk_chebyshev_distance(_canonical_chunk_coord(coord), _player_chunk) <= 1

func _should_prepare_border_fix_inline(task: Dictionary, chunk: Chunk, requested_tile_budget: int) -> bool:
	if chunk == null or not is_instance_valid(chunk):
		return false
	if bool(task.get("force_inline_prepare", false)):
		return true
	if int(task.get("kind", VisualTaskKind.TASK_COSMETIC)) != VisualTaskKind.TASK_BORDER_FIX:
		return false
	if int(task.get("priority_band", VisualPriorityBand.COSMETIC)) != VisualPriorityBand.BORDER_FIX_NEAR:
		return false
	var coord: Vector2i = task.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var z_level: int = int(task.get("z", _active_z))
	if not _is_player_near_visual_chunk(coord, z_level):
		return false
	var dirty_count: int = chunk.get_pending_border_dirty_count()
	if dirty_count <= 0:
		return false
	return dirty_count <= maxi(BORDER_FIX_REDRAW_MICRO_BATCH_TILES, requested_tile_budget)

func _try_complete_visible_border_fix_inline(chunk: Chunk, z_level: int) -> bool:
	if chunk == null or not is_instance_valid(chunk) or _chunk_visual_scheduler == null:
		return false
	if not chunk.is_first_pass_ready() or not chunk.is_redraw_complete():
		return false
	if not _is_player_near_visual_chunk(chunk.chunk_coord, z_level):
		return false
	var dirty_count: int = chunk.get_pending_border_dirty_count()
	if dirty_count <= 0:
		return false
	if dirty_count > maxi(1, chunk.get_chunk_size()):
		return false
	var task_key: Vector4i = _make_visual_task_key(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX)
	var task_version: int = int(_chunk_visual_scheduler.task_pending.get(task_key, -1))
	var started_usec: int = WorldPerfProbe.begin()
	var has_more: bool = _chunk_visual_scheduler.process_border_fix_task(chunk, dirty_count, 0)
	WorldPerfProbe.end("ChunkManager.visible_border_fix_inline %s@z%d" % [chunk.chunk_coord, z_level], started_usec)
	if has_more or chunk.has_pending_border_dirty():
		if task_version >= 0:
			_enqueue_player_near_border_fix_relief_task(
				chunk,
				z_level,
				task_version,
				"player_near_inline_partial"
			)
		return false
	chunk._mark_border_fix_reasons_applied()
	if task_version >= 0:
		_chunk_visual_scheduler.clear_task(
			_build_visual_task(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX, task_version)
		)
	return _try_finalize_chunk_visual_convergence(chunk, z_level)

func _stabilize_player_near_border_fix_chunks(z_level: int) -> void:
	if _chunk_visual_scheduler == null or _player_chunk == Vector2i(99999, 99999):
		return
	var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(z_level)
	for chunk_variant: Variant in loaded_chunks_for_z.values():
		var chunk: Chunk = chunk_variant as Chunk
		if chunk == null or not is_instance_valid(chunk):
			continue
		if not _is_player_near_visual_chunk(chunk.chunk_coord, z_level):
			continue
		if not chunk.has_pending_border_dirty():
			continue
		_ensure_chunk_border_fix_task(chunk, z_level)

func _enqueue_player_near_border_fix_relief_task(
	chunk: Chunk,
	z_level: int,
	task_version: int,
	relief_reason: String = "player_near_sync_relief"
) -> bool:
	if chunk == null or not is_instance_valid(chunk):
		return false
	if task_version < 0:
		return false
	if not _is_player_near_visual_chunk(chunk.chunk_coord, z_level):
		return false
	if _chunk_visual_scheduler != null \
		and _chunk_visual_scheduler.promote_existing_task_to_front(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX):
		return true
	var task: Dictionary = _build_visual_task(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX, task_version)
	_debug_upsert_visual_task_meta(task)
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.push_task_front(task)
	_debug_note_visual_task_event(
		task,
		"visual_task_requeued",
		{
			"relief_reason": relief_reason,
		},
		"",
		"player_near_sync_relief"
	)
	return true

func _try_force_complete_stuck_player_border_fix(
	chunk: Chunk,
	z_level: int,
	border_fix_age_ms: float,
	min_age_ms: float = ChunkDebugSystem.DEBUG_FORENSICS_OWNER_STUCK_MS
) -> Dictionary:
	var relief: Dictionary = {
		"recovered_inline_border_fix": false,
		"forced_border_fix_progress": false,
		"promoted_border_fix_task": false,
		"remaining_dirty_tiles": 0,
	}
	if chunk == null or not is_instance_valid(chunk):
		return relief
	if border_fix_age_ms < min_age_ms:
		return relief
	if not chunk.visible or chunk.get_redraw_phase_name() != "done":
		return relief
	if not _is_player_near_visual_chunk(chunk.chunk_coord, z_level):
		return relief
	var task_key: Vector4i = _make_visual_task_key(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX)
	var dirty_count: int = chunk.get_pending_border_dirty_count()
	if not _chunk_visual_scheduler.task_pending.has(task_key):
		if dirty_count > 0:
			_ensure_chunk_border_fix_task(chunk, z_level)
			relief["promoted_border_fix_task"] = true
			relief["remaining_dirty_tiles"] = dirty_count
		return relief
	var task_version: int = int(_chunk_visual_scheduler.task_pending.get(task_key, 0))
	if dirty_count <= 0:
		chunk._mark_border_fix_reasons_applied()
		if _chunk_visual_scheduler != null:
			_chunk_visual_scheduler.clear_task(_build_visual_task(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX, task_version))
		_try_finalize_chunk_visual_convergence(chunk, z_level)
		relief["recovered_inline_border_fix"] = true
		return relief
	relief["remaining_dirty_tiles"] = dirty_count
	relief["promoted_border_fix_task"] = _enqueue_player_near_border_fix_relief_task(
		chunk,
		z_level,
		task_version,
		"player_near_relief"
	)
	if bool(relief.get("promoted_border_fix_task", false)):
		_debug_note_visual_task_event(
			_build_visual_task(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX, task_version),
			"visual_task_requeued",
			{
				"remaining_dirty_tiles": dirty_count,
				"relief_reason": "player_near_relief",
			},
			"",
			"owner_stuck_relief_queued"
		)
	return relief


func _make_visual_task_key(coord: Vector2i, z_level: int, kind: int) -> Vector4i:
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	return Vector4i(canonical_coord.x, canonical_coord.y, z_level, kind)

func _format_visual_task_key(task_key: Vector4i) -> String:
	return "%d:%d:%d:%d" % [task_key.x, task_key.y, task_key.z, task_key.w]

func _visual_task_key_less(a: Vector4i, b: Vector4i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	if a.z != b.z:
		return a.z < b.z
	return a.w < b.w

func _make_visual_chunk_key(coord: Vector2i, z_level: int) -> String:
	return "%d:%d:%d" % [coord.x, coord.y, z_level]

func _debug_get_visual_task_meta(task_key: Vector4i) -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system.get_visual_task_meta(task_key)

func _debug_update_visual_task_meta_band(task_key: Vector4i, band: int) -> void:
	if _chunk_debug_system == null:
		return
	_chunk_debug_system.update_visual_task_band(task_key, band)

func _debug_upsert_visual_task_meta(task: Dictionary, enqueue_reason: String = "") -> Dictionary:
	if _chunk_debug_system == null:
		return {}
	return _chunk_debug_system.upsert_visual_task_meta(task, enqueue_reason)

func _debug_note_visual_task_event(
	task: Dictionary,
	event_key: String,
	detail_fields: Dictionary = {},
	skip_reason: String = "",
	budget_state: String = ""
) -> void:
	if _chunk_debug_system == null:
		return
	_chunk_debug_system.note_visual_task_event(
		task,
		event_key,
		detail_fields,
		skip_reason,
		budget_state
	)

func _debug_drop_visual_task_meta(task: Dictionary) -> void:
	if _chunk_debug_system == null:
		return
	_chunk_debug_system.drop_visual_task_meta(task)

func _debug_note_budget_exhausted_trace_task() -> void:
	if _chunk_debug_system == null:
		return
	_chunk_debug_system.note_budget_exhausted_trace_task()

func _is_forward_ring1_visual_chunk(coord: Vector2i) -> bool:
	if _player_chunk_motion == Vector2i.ZERO:
		return false
	var delta: Vector2i = coord - _player_chunk
	if max(abs(delta.x), abs(delta.y)) != 1:
		return false
	if delta.y == 0 and _player_chunk_motion.x != 0 and delta.x == signi(_player_chunk_motion.x):
		return true
	if delta.x == 0 and _player_chunk_motion.y != 0 and delta.y == signi(_player_chunk_motion.y):
		return true
	return false

func _is_protected_first_pass_chunk(coord: Vector2i, z_level: int) -> bool:
	if z_level != _active_z:
		return false
	if coord == _player_chunk:
		return true
	return _is_forward_ring1_visual_chunk(coord)

func _is_boot_tracked_chunk(coord: Vector2i, z_level: int) -> bool:
	if _chunk_boot_pipeline == null:
		return false
	if z_level != _active_z:
		return false
	return _chunk_boot_pipeline.is_tracking_chunk(_canonical_chunk_coord(coord))

func _boot_tracked_chunk_ring(coord: Vector2i) -> int:
	if _chunk_boot_pipeline == null:
		return 999999
	return _chunk_boot_pipeline.get_chunk_ring(_canonical_chunk_coord(coord))

func _resolve_boot_runtime_handoff_lane(coord: Vector2i, z_level: int) -> int:
	if _chunk_boot_pipeline == null or _is_boot_in_progress:
		return -1
	if z_level != _active_z:
		return -1
	var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
	if not _chunk_boot_pipeline.is_tracking_chunk(canonical_coord):
		return -1
	if _chunk_boot_pipeline.get_chunk_state(canonical_coord) >= BootChunkState.APPLIED:
		return -1
	return FrontierScheduler.LANE_FRONTIER_CRITICAL

func _resolve_visual_band(coord: Vector2i, z_level: int, kind: int) -> int:
	var boot_tracked: bool = _is_boot_tracked_chunk(coord, z_level)
	var boot_ring: int = _boot_tracked_chunk_ring(coord) if boot_tracked else 999999
	if kind == VisualTaskKind.TASK_BORDER_FIX:
		if boot_tracked and not is_boot_complete():
			return VisualPriorityBand.BORDER_FIX_NEAR
		if z_level != _active_z:
			return VisualPriorityBand.BORDER_FIX_FAR
		var border_ring: int = _chunk_chebyshev_distance(coord, _player_chunk)
		if border_ring <= 2:
			return VisualPriorityBand.BORDER_FIX_NEAR
		return VisualPriorityBand.BORDER_FIX_FAR
	if kind == VisualTaskKind.TASK_COSMETIC:
		return VisualPriorityBand.COSMETIC
	if z_level != _active_z:
		return VisualPriorityBand.FULL_FAR
	var ring: int = _chunk_chebyshev_distance(coord, _player_chunk)
	if kind == VisualTaskKind.TASK_FIRST_PASS:
		if boot_tracked and not is_boot_complete():
			if coord == _player_chunk or boot_ring == 0:
				return VisualPriorityBand.TERRAIN_FAST
			if boot_ring <= BOOT_FIRST_PLAYABLE_MAX_RING:
				return VisualPriorityBand.TERRAIN_URGENT
			return VisualPriorityBand.TERRAIN_NEAR
		if _is_protected_first_pass_chunk(coord, z_level):
			return VisualPriorityBand.TERRAIN_FAST
		if ring == 1:
			return VisualPriorityBand.TERRAIN_NEAR
		return VisualPriorityBand.FULL_FAR
	if boot_tracked and not is_boot_complete():
		return VisualPriorityBand.FULL_NEAR
	if ring <= 2:
		return VisualPriorityBand.FULL_NEAR
	return VisualPriorityBand.FULL_FAR

func _build_visual_task(coord: Vector2i, z_level: int, kind: int, version: int) -> Dictionary:
	return {
		"chunk_coord": coord,
		"z": z_level,
		"kind": kind,
		"priority_band": _resolve_visual_band(coord, z_level, kind),
		"camera_score": float(_chunk_chebyshev_distance(coord, _player_chunk)),
		"movement_score": float(_player_chunk_motion.length_squared()),
		"eta_score": 0.0,
		"invalidation_version": version,
		"wait_recorded": false,
	}

func _get_visual_queues_in_priority_order() -> Array[Array]:
	if _chunk_visual_scheduler != null:
		return _chunk_visual_scheduler.ordered_queues()
	return []

func _invalidate_boot_visual_complete(coord: Vector2i, z_level: int) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.invalidate_visual_complete(coord, z_level)

func _sync_chunk_visibility_for_publication(chunk: Chunk) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	var should_be_visible: bool = chunk._is_visibility_publication_ready()
	if chunk.visible and not should_be_visible:
		_report_zero_tolerance_contract_breach(
			"chunk_visible_before_full_ready",
			chunk.chunk_coord,
			_active_z,
			"Запретила видимость неполного чанка",
			"видимый чанк потерял terminal full_ready; publish-now / finish-later semantics больше не разрешены",
			"publish_later",
			{
				"visual_state": _describe_chunk_visual_state(chunk),
				"redraw_phase": String(chunk.get_redraw_phase_name()),
			}
		)
	chunk.visible = should_be_visible

func _try_finalize_chunk_visual_convergence(chunk: Chunk, z_level: int) -> bool:
	if chunk == null or not is_instance_valid(chunk):
		return false
	chunk._refresh_interior_macro_layer_if_dirty()
	if chunk.is_first_pass_ready():
		if _chunk_visual_scheduler != null:
			_chunk_visual_scheduler.mark_first_pass_ready(chunk.chunk_coord, z_level)
	if not chunk._can_publish_full_redraw_ready():
		_sync_chunk_visibility_for_publication(chunk)
		return false
	var chunk_key: String = _make_visual_chunk_key(chunk.chunk_coord, z_level)
	var was_full_ready: bool = _chunk_visual_scheduler.full_ready_usec.has(chunk_key)
	chunk._mark_visual_full_redraw_ready()
	_sync_chunk_visibility_for_publication(chunk)
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.mark_full_ready(chunk.chunk_coord, z_level)
	if not was_full_ready:
		_debug_record_recent_lifecycle_event(
			"visible",
			chunk.chunk_coord,
			z_level,
			"Подготовка визуала чанка",
			"визуал готов и чанк опубликован",
			_debug_age_ms(_chunk_visual_scheduler.apply_started_usec.get(chunk_key, 0), Time.get_ticks_usec())
		)
		_debug_emit_chunk_event(
			"chunk_visible",
			"опубликовала визуал",
			chunk.chunk_coord,
			z_level,
			"полный визуал чанка готов, игрок не должен видеть сырой build-up",
			StringName(_debug_impact_for_chunk(_chunk_chebyshev_distance(chunk.chunk_coord, _player_chunk), "visible")),
			"visible",
			"видим",
			"visual_published",
			{"visual_queue_depth": _debug_visual_queue_depth()}
		)
		_debug_record_forensics_event(
			_debug_resolve_chunk_trace_context(chunk.chunk_coord, z_level),
			"chunk_scheduler",
			"chunk_visual_published",
			chunk.chunk_coord,
			z_level,
			{
				"visual_queue_depth": _debug_visual_queue_depth(),
				"phase": String(chunk.get_redraw_phase_name()),
			},
			[chunk.chunk_coord]
		)
	if not is_boot_complete() and _chunk_boot_pipeline != null and _chunk_boot_pipeline.is_tracking_chunk(chunk.chunk_coord):
		_boot_on_chunk_redraw_progress(chunk)
	return true

func _invalidate_chunk_visual_convergence(chunk: Chunk, z_level: int) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.mark_convergence_started(chunk.chunk_coord, z_level, true)
	chunk._mark_visual_convergence_owed()
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.clear_full_ready(chunk.chunk_coord, z_level)
	_invalidate_boot_visual_complete(chunk.chunk_coord, z_level)

func _ensure_chunk_full_redraw_task(chunk: Chunk, z_level: int, invalidate: bool = false) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	if invalidate:
		_invalidate_chunk_visual_convergence(chunk, z_level)
	if chunk.is_full_redraw_ready() and not invalidate:
		if _chunk_visual_scheduler != null:
			_chunk_visual_scheduler.mark_full_ready(chunk.chunk_coord, z_level)
		return
	if not chunk.needs_full_redraw():
		_try_finalize_chunk_visual_convergence(chunk, z_level)
		return
	if chunk.is_redraw_complete():
		_try_finalize_chunk_visual_convergence(chunk, z_level)
		return
	chunk._mark_visual_full_redraw_pending()
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.ensure_task(chunk, z_level, VisualTaskKind.TASK_FULL_REDRAW, invalidate)

func _ensure_chunk_border_fix_task(chunk: Chunk, z_level: int, invalidate: bool = false) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	if not chunk.has_pending_border_dirty():
		_try_finalize_chunk_visual_convergence(chunk, z_level)
		return
	if invalidate:
		_invalidate_chunk_visual_convergence(chunk, z_level)
	if chunk.needs_full_redraw() and not chunk.is_redraw_complete():
		if _chunk_visual_scheduler != null:
			_chunk_visual_scheduler.ensure_task(chunk, z_level, VisualTaskKind.TASK_FULL_REDRAW, invalidate)
	var border_fix_key: Vector4i = _make_visual_task_key(chunk.chunk_coord, z_level, VisualTaskKind.TASK_BORDER_FIX)
	if _chunk_visual_scheduler.task_pending.has(border_fix_key):
		if _is_player_near_visual_chunk(chunk.chunk_coord, z_level):
			_enqueue_player_near_border_fix_relief_task(
				chunk,
				z_level,
				int(_chunk_visual_scheduler.task_pending.get(border_fix_key, 0)),
				"pending_player_near_relief"
			)
		return
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.ensure_task(chunk, z_level, VisualTaskKind.TASK_BORDER_FIX)

func _schedule_chunk_visual_work(chunk: Chunk, z_level: int) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.mark_apply_started(chunk.chunk_coord, z_level)
	if not chunk.is_first_pass_ready():
		if _chunk_visual_scheduler != null:
			_chunk_visual_scheduler.ensure_task(chunk, z_level, VisualTaskKind.TASK_FIRST_PASS)
	else:
		if _chunk_visual_scheduler != null:
			_chunk_visual_scheduler.mark_first_pass_ready(chunk.chunk_coord, z_level)
		_ensure_chunk_full_redraw_task(chunk, z_level)
	_sync_chunk_visibility_for_publication(chunk)
	if chunk.has_pending_border_dirty():
		_ensure_chunk_border_fix_task(chunk, z_level)
	else:
		_try_finalize_chunk_visual_convergence(chunk, z_level)

func _drive_boot_finalization_budget() -> void:
	if _shutdown_in_progress or _is_boot_in_progress or is_boot_complete():
		return
	if _chunk_boot_pipeline == null or not _chunk_boot_pipeline.has_remaining_chunks():
		return
	if _chunk_streaming_service != null:
		var streaming_steps: int = 0
		while streaming_steps < BOOT_FINALIZATION_STREAMING_STEPS_PER_FRAME:
			if not _chunk_streaming_service.has_streaming_work():
				break
			var has_more_streaming: bool = _chunk_streaming_service.tick_loading()
			streaming_steps += 1
			if not has_more_streaming:
				break
	if _chunk_visual_scheduler != null and _chunk_visual_scheduler.has_pending_tasks():
		_chunk_visual_scheduler.tick_budget(BOOT_FINALIZATION_VISUAL_BUDGET_USEC)
	_tick_topology()

func _emit_visual_scheduler_tick_log(processed_count: int, budget_exhausted: bool) -> void:
	if processed_count <= 0 and not budget_exhausted and (_chunk_visual_scheduler == null or not _chunk_visual_scheduler.has_pending_tasks()):
		return
	WorldPerfProbe.record("scheduler.visual_tasks_processed", float(processed_count))
	WorldPerfProbe.record("scheduler.visual_queue_depth.terrain_fast", float(_chunk_visual_scheduler.q_terrain_fast.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.terrain_urgent", float(_chunk_visual_scheduler.q_terrain_urgent.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.terrain_near", float(_chunk_visual_scheduler.q_terrain_near.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.full_near", float(_chunk_visual_scheduler.q_full_near.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.border_fix_near", float(_chunk_visual_scheduler.q_border_fix_near.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.border_fix_far", float(_chunk_visual_scheduler.q_border_fix_far.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.full_far", float(_chunk_visual_scheduler.q_full_far.size()))
	WorldPerfProbe.record("scheduler.visual_queue_depth.cosmetic", float(_chunk_visual_scheduler.q_cosmetic.size()))
	_chunk_visual_scheduler.log_ticks += 1

func _tick_visuals_budget(max_usec: int) -> bool:
	return _chunk_visual_scheduler.tick_budget(max_usec) if _chunk_visual_scheduler != null else false

func _tick_visuals() -> bool:
	if _shutdown_in_progress:
		return false
	if _is_boot_in_progress:
		return false
	var resolved_budget_usec: int = int(_chunk_visual_scheduler.resolve_scheduler_budget_ms() * 1000.0) if _chunk_visual_scheduler != null else 0
	return _chunk_visual_scheduler.tick_once(resolved_budget_usec) if _chunk_visual_scheduler != null else false

func _reset_visual_runtime_telemetry() -> void:
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.reset_runtime_telemetry()
	_player_chunk_diag_last_usec = 0
	_player_chunk_diag_last_signature = ""

func _get_diag_age_ms(source: Dictionary, key: Variant) -> float:
	if not source.has(key):
		return -1.0
	return float(Time.get_ticks_usec() - int(source[key])) / 1000.0

func _get_visual_task_age_ms(coord: Vector2i, z_level: int, kind: int) -> float:
	var key: Vector4i = _make_visual_task_key(coord, z_level, kind)
	if not _chunk_visual_scheduler.task_pending.has(key):
		return -1.0
	return _get_diag_age_ms(_chunk_visual_scheduler.task_enqueued_usec, key)

func _describe_chunk_visual_state(chunk: Chunk) -> String:
	if chunk == null or not is_instance_valid(chunk):
		return "not_loaded"
	match int(chunk._visual_state):
		0:
			return "uninitialized"
		1:
			return "native_ready"
		2:
			return "proxy_ready"
		3:
			return "terrain_ready"
		4:
			return "full_pending"
		5:
			return "full_ready"
		_:
			return "unknown"

func _format_diag_age_ms(value_ms: float) -> String:
	if value_ms < 0.0:
		return "-"
	return "%.0f" % value_ms

func _emit_player_chunk_visual_status_diag(
	coord: Vector2i,
	z_level: int,
	trigger: String,
	chunk: Chunk,
	state_name: String,
	phase_name: String,
	issues: Array[String],
	load_queued: bool,
	staged: bool,
	generating: bool,
	first_pass_ready: bool,
	full_ready: bool,
	dispatcher_step_ms: float,
	budget_exhausted: bool,
	first_pass_age_ms: float,
	full_redraw_age_ms: float,
	border_fix_age_ms: float,
	apply_age_ms: float,
	convergence_age_ms: float
) -> void:
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	var chunk_is_simulating: bool = _chunk_chebyshev_distance(coord, _player_chunk) <= load_radius
	var diag_record: Dictionary = _build_player_chunk_visual_diag_record(
		issues,
		chunk,
		load_queued,
		staged,
		generating,
		first_pass_ready,
		full_ready,
		dispatcher_step_ms,
		budget_exhausted
	)
	var should_track_incident: bool = not issues.is_empty() or budget_exhausted
	var trace_context: Dictionary = {}
	if should_track_incident:
		trace_context = _debug_ensure_forensics_context(
			coord,
			z_level,
			"chunk_manager",
			"player_chunk_visual_issue",
			{
				"issues_internal": ",".join(issues) if not issues.is_empty() else "healthy",
				"trigger": trigger,
			},
			[coord]
		)
	var detail_fields: Dictionary = {
		"apply_age_ms": _format_diag_age_ms(apply_age_ms),
		"border_fix_age_ms": _format_diag_age_ms(border_fix_age_ms),
		"budget_exhausted": budget_exhausted,
		"chunk": str(coord),
		"chunk_loaded": chunk != null and is_instance_valid(chunk),
		"chunk_visible": chunk != null and is_instance_valid(chunk) and chunk.visible,
		"convergence_age_ms": _format_diag_age_ms(convergence_age_ms),
		"dispatcher_step_ms": "%.2f" % dispatcher_step_ms,
		"first_pass_age_ms": _format_diag_age_ms(first_pass_age_ms),
		"first_pass_ready": first_pass_ready,
		"full_redraw_age_ms": _format_diag_age_ms(full_redraw_age_ms),
		"full_ready": full_ready,
		"issues_internal": ",".join(issues) if not issues.is_empty() else "healthy",
		"phase": phase_name,
		"queue_border_fix_far": _chunk_visual_scheduler.q_border_fix_far.size(),
		"queue_border_fix_near": _chunk_visual_scheduler.q_border_fix_near.size(),
		"queue_full_far": _chunk_visual_scheduler.q_full_far.size(),
		"queue_full_near": _chunk_visual_scheduler.q_full_near.size(),
		"queue_terrain_fast": _chunk_visual_scheduler.q_terrain_fast.size(),
		"queue_terrain_near": _chunk_visual_scheduler.q_terrain_near.size(),
		"queue_terrain_urgent": _chunk_visual_scheduler.q_terrain_urgent.size(),
		"requests_generating": generating,
		"requests_load": load_queued,
		"requests_staged": staged,
		"state_name": state_name,
		"trigger": trigger,
		"z": z_level,
	}
	_debug_enrich_record_with_trace(diag_record, detail_fields, coord, z_level, trace_context)
	WorldRuntimeDiagnosticLog.emit_record(diag_record, detail_fields)
	if should_track_incident:
		_debug_record_forensics_event(
			trace_context,
			"chunk_manager",
			"player_chunk_visual_issue",
			coord,
			z_level,
			{
				"issues_internal": detail_fields.get("issues_internal", "healthy"),
				"phase": phase_name,
				"full_ready": full_ready,
				"border_fix_age_ms": border_fix_age_ms,
				"full_redraw_age_ms": full_redraw_age_ms,
			},
			[coord]
		)
	if chunk != null and is_instance_valid(chunk) \
		and chunk.visible \
		and chunk_is_simulating \
		and phase_name == "done" \
		and (border_fix_age_ms >= ChunkDebugSystem.DEBUG_FORENSICS_OWNER_STUCK_MS or full_redraw_age_ms >= ChunkDebugSystem.DEBUG_FORENSICS_OWNER_STUCK_MS):
		var border_fix_relief: Dictionary = _try_force_complete_stuck_player_border_fix(chunk, z_level, border_fix_age_ms)
		var owner_stuck_context: Dictionary = trace_context
		if owner_stuck_context.is_empty():
			owner_stuck_context = _debug_ensure_forensics_context(
				coord,
				z_level,
				"chunk_manager",
				"player_chunk_owner_stuck",
				{"phase": phase_name},
				[coord]
			)
		_debug_record_forensics_event(
			owner_stuck_context,
			"chunk_manager",
			"player_chunk_owner_stuck",
			coord,
			z_level,
			{
				"phase": phase_name,
				"border_fix_age_ms": border_fix_age_ms,
				"full_redraw_age_ms": full_redraw_age_ms,
				"recovered_inline_border_fix": bool(border_fix_relief.get("recovered_inline_border_fix", false)),
				"forced_border_fix_progress": bool(border_fix_relief.get("forced_border_fix_progress", false)),
				"promoted_border_fix_task": bool(border_fix_relief.get("promoted_border_fix_task", false)),
				"remaining_dirty_tiles": int(border_fix_relief.get("remaining_dirty_tiles", 0)),
			},
			[coord]
		)

func _build_player_chunk_visual_diag_record(
	issues: Array[String],
	chunk: Chunk,
	load_queued: bool,
	staged: bool,
	generating: bool,
	first_pass_ready: bool,
	full_ready: bool,
	dispatcher_step_ms: float,
	budget_exhausted: bool
) -> Dictionary:
	var chunk_visible: bool = chunk != null and is_instance_valid(chunk) and chunk.visible
	var action_key: String = "reported_visual_health"
	var action_human: String = "подтвердил стабильное визуальное состояние"
	var reason_key: String = "healthy"
	var reason_human: String = "ключевые визуальные очереди для текущего чанка пусты"
	var impact_key: StringName = WorldRuntimeDiagnosticLog.IMPACT_INFORMATIONAL
	var state_key: String = "converged"
	var state_human: String = "сошёлся"
	var code_term: String = ""
	if issues.has("visible_before_full_ready"):
		action_key = "reported_visual_blocker"
		action_human = "сообщил о запрещённой ранней публикации"
		reason_key = "applied_not_converged"
		reason_human = "чанк уже виден, хотя terminal full_ready ещё не достигнут"
		impact_key = WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE
		state_key = "blocked"
		state_human = "видимость опережает полную готовность"
	elif issues.has("not_loaded") or load_queued or staged or generating:
		action_key = "reported_visual_blocker"
		action_human = "сообщил о задержке визуальной сходимости"
		reason_key = "queued_not_applied"
		reason_human = "очередь догрузки мира ещё не довела текущий чанк до готового состояния"
		impact_key = WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE
		state_key = "queued"
		state_human = "ждёт догрузку или применение"
		code_term = "streaming_truth"
	elif issues.has("first_pass_pending") or issues.has("first_pass_not_ready"):
		action_key = "reported_visual_blocker"
		action_human = "сообщил о задержке первого визуального прохода"
		reason_key = "queued_not_applied"
		reason_human = "первый визуальный проход ещё не завершён"
		impact_key = WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE
		state_key = "queued"
		state_human = "первый проход ещё в работе"
		code_term = "stream_load"
	elif issues.has("full_redraw_pending"):
		action_key = "reported_visual_blocker"
		action_human = "сообщил о незавершённой полной перерисовке"
		reason_key = "applied_not_converged"
		reason_human = "базовая картинка уже применена, но полная перерисовка ещё не завершена"
		impact_key = WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE
		state_key = "blocked"
		state_human = "ещё не сошёлся"
	elif issues.has("border_fix_pending"):
		action_key = "reported_visual_blocker"
		action_human = "сообщил о хвосте после правки границы"
		reason_key = "queued_not_applied"
		reason_human = "правка границы чанка всё ещё ждёт применения"
		impact_key = WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE
		if chunk_visible and first_pass_ready and full_ready:
			impact_key = WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT
		state_key = "queued"
		state_human = "очередь ещё не применена"
		code_term = "border_fix"
	elif not full_ready:
		action_key = "reported_visual_blocker"
		action_human = "сообщил о незавершённой визуальной сходимости"
		reason_key = "applied_not_converged"
		reason_human = "чанк ещё не дошёл до полной визуальной готовности"
		impact_key = WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE
		state_key = "blocked"
		state_human = "ожидает сходимость"
	elif dispatcher_step_ms >= PLAYER_CHUNK_DIAG_SPIKE_MS or budget_exhausted:
		action_key = "reported_visual_snapshot"
		action_human = "зафиксировал диагностический снимок очередей"
		reason_key = "timing_watch"
		reason_human = "в этом кадре был заметный всплеск нагрузки диспетчера, хотя текущий чанк уже готов"
		impact_key = WorldRuntimeDiagnosticLog.IMPACT_INFORMATIONAL
		state_key = "observed"
		state_human = "требует наблюдения"
	return {
		"actor": "chunk_manager",
		"actor_human": "Менеджер чанков мира",
		"action": action_key,
		"action_human": action_human,
		"target": "player_chunk",
		"target_human": "текущий чанк игрока",
		"reason": reason_key,
		"reason_human": reason_human,
		"impact": String(impact_key),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact_key),
		"state": state_key,
		"state_human": state_human,
		"code": code_term,
	}

func _maybe_log_player_chunk_visual_status(
	trigger: String,
	dispatcher_step_ms: float = 0.0,
	budget_exhausted: bool = false
) -> void:
	if not _initialized or not _player or _is_boot_in_progress:
		return
	var coord: Vector2i = _canonical_chunk_coord(_player_chunk)
	var z_level: int = _active_z
	var chunk: Chunk = get_chunk(coord)
	var chunk_key: String = _make_visual_chunk_key(coord, z_level)
	var load_queued: bool = _has_load_request(coord, z_level)
	var staged: bool = _is_staged_request(coord, z_level)
	var generating: bool = _is_generating_request(coord, z_level)
	var first_pass_age_ms: float = _get_visual_task_age_ms(coord, z_level, VisualTaskKind.TASK_FIRST_PASS)
	var full_redraw_age_ms: float = _get_visual_task_age_ms(coord, z_level, VisualTaskKind.TASK_FULL_REDRAW)
	var border_fix_age_ms: float = _get_visual_task_age_ms(coord, z_level, VisualTaskKind.TASK_BORDER_FIX)
	var apply_age_ms: float = _get_diag_age_ms(_chunk_visual_scheduler.apply_started_usec, chunk_key)
	var convergence_age_ms: float = _get_diag_age_ms(_chunk_visual_scheduler.convergence_started_usec, chunk_key)
	var first_pass_ready: bool = chunk != null and chunk.is_first_pass_ready()
	var full_ready: bool = chunk != null and chunk.is_full_redraw_ready()
	var phase_name: String = String(chunk.get_redraw_phase_name()) if chunk != null and is_instance_valid(chunk) else "none"
	var state_name: String = _describe_chunk_visual_state(chunk)
	var issues: Array[String] = []
	if chunk == null or not is_instance_valid(chunk):
		issues.append("not_loaded")
	if load_queued:
		issues.append("load_queued")
	if staged:
		issues.append("staged_apply")
	if generating:
		issues.append("generating")
	if not first_pass_ready:
		issues.append("first_pass_not_ready")
	if first_pass_age_ms >= 0.0:
		issues.append("first_pass_pending")
	if full_redraw_age_ms >= 0.0:
		issues.append("full_redraw_pending")
	if border_fix_age_ms >= 0.0:
		issues.append("border_fix_pending")
	if chunk != null and is_instance_valid(chunk) and chunk.visible and not full_ready:
		issues.append("visible_before_full_ready")
	var blocked_age_ms: float = maxf(
		first_pass_age_ms,
		maxf(full_redraw_age_ms, maxf(border_fix_age_ms, maxf(apply_age_ms, convergence_age_ms)))
	)
	var is_blocked: bool = not issues.is_empty()
	if trigger == "entered_chunk" and not is_blocked:
		return
	var issues_text: String = ",".join(issues)
	var signature: String = "%s|%d|%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(coord),
		z_level,
		state_name,
		phase_name,
		str(load_queued),
		str(staged),
		str(generating),
		str(first_pass_ready),
		str(full_ready),
		issues_text,
	]
	var now_usec: int = Time.get_ticks_usec()
	var should_log: bool = false
	if signature != _player_chunk_diag_last_signature:
		should_log = true
	elif is_blocked \
		and blocked_age_ms >= PLAYER_CHUNK_DIAG_BLOCKED_AGE_MS \
		and now_usec - _player_chunk_diag_last_usec >= PLAYER_CHUNK_DIAG_LOG_INTERVAL_MSEC * 1000:
		should_log = true
	elif dispatcher_step_ms >= PLAYER_CHUNK_DIAG_SPIKE_MS \
		and now_usec - _player_chunk_diag_last_usec >= PLAYER_CHUNK_DIAG_LOG_INTERVAL_MSEC * 1000:
		should_log = true
	elif budget_exhausted \
		and is_blocked \
		and now_usec - _player_chunk_diag_last_usec >= PLAYER_CHUNK_DIAG_LOG_INTERVAL_MSEC * 1000:
		should_log = true
	if not should_log:
		return
	_player_chunk_diag_last_signature = signature
	_player_chunk_diag_last_usec = now_usec
	_emit_player_chunk_visual_status_diag(
		coord,
		z_level,
		trigger,
		chunk,
		state_name,
		phase_name,
		issues,
		load_queued,
		staged,
		generating,
		first_pass_ready,
		full_ready,
		dispatcher_step_ms,
		budget_exhausted,
		first_pass_age_ms,
		full_redraw_age_ms,
		border_fix_age_ms,
		apply_age_ms,
		convergence_age_ms
	)

func _enforce_player_chunk_full_ready(trigger: String) -> void:
	if _player_chunk == Vector2i(99999, 99999):
		return
	var coord: Vector2i = _canonical_chunk_coord(_player_chunk)
	var chunk: Chunk = get_chunk(coord)
	if chunk != null and is_instance_valid(chunk) and chunk.is_full_redraw_ready():
		return
	_report_zero_tolerance_contract_breach(
		"player_occupied_non_full_ready_chunk",
		coord,
		_active_z,
		"Обнаружила игрока в неполном чанке",
		"игрок оказался в чанке без terminal full_ready; first-pass и deferred convergence не дают права на occupancy",
		"occupancy_not_full_ready",
		{
			"trigger": trigger,
			"chunk_loaded": chunk != null and is_instance_valid(chunk),
			"visual_state": _describe_chunk_visual_state(chunk),
			"redraw_phase": String(chunk.get_redraw_phase_name()) if chunk != null and is_instance_valid(chunk) else "none",
		}
	)

func _check_player_chunk() -> void:
	var cur: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	if cur != _player_chunk:
		_player_chunk_motion = cur - _player_chunk if _player_chunk.x != 99999 else Vector2i.ZERO
		_last_player_chunk_for_priority = _player_chunk
		_player_chunk = cur
		_debug_emit_chunk_event(
			"player_entered_chunk",
			"зафиксировала вход игрока",
			_player_chunk,
			_active_z,
			"игрок пересёк границу чанка, приоритеты загрузки и визуала пересчитаны",
			WorldRuntimeDiagnosticLog.IMPACT_INFORMATIONAL,
			"observed",
			"наблюдается",
			"player_chunk",
			{"motion": _player_chunk_motion}
		)
		if _chunk_visual_scheduler != null:
			_chunk_visual_scheduler.refresh_task_priorities()
		_stabilize_player_near_border_fix_chunks(_active_z)
		_sync_loaded_chunk_display_positions(cur)
		_update_chunks(cur)
		_maybe_log_player_chunk_visual_status("entered_chunk")
	_enforce_player_chunk_full_ready("player_chunk_check")

func _update_chunks(center: Vector2i) -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.update_chunks(center)

func _process_load_queue() -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.process_load_queue()

func _load_chunk(coord: Vector2i) -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.load_chunk(coord)

func _load_chunk_for_z(coord: Vector2i, z_level: int) -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.load_chunk_for_z(coord, z_level)

func _unload_chunk(coord: Vector2i) -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.unload_chunk(coord)

func _register_budget_jobs() -> void:
	FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		3.0,
		_tick_loading,
		JOB_STREAMING_LOAD,
		RuntimeWorkTypes.CadenceKind.BACKGROUND,
		RuntimeWorkTypes.ThreadingRole.COMPUTE_THEN_APPLY,
		false,
		"Chunk streaming load"
	)
	FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_VISUAL,
		_chunk_visual_scheduler.resolve_scheduler_budget_ms() if _chunk_visual_scheduler != null else 4.0,
		_tick_visuals,
		JOB_STREAMING_REDRAW,
		RuntimeWorkTypes.CadenceKind.PRESENTATION,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"Chunk visual scheduler"
	)
	FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_TOPOLOGY,
		2.0,
		_tick_topology,
		JOB_TOPOLOGY,
		RuntimeWorkTypes.CadenceKind.BACKGROUND,
		RuntimeWorkTypes.ThreadingRole.COMPUTE_THEN_APPLY,
		false,
		"Mountain topology rebuild"
	)

## Async staged chunk loading. Generation в WorkerThreadPool, create/finalize на main thread.
## Thread-safety: pure-data compute runs in detached builders; scene-tree apply remains serialized.
func _tick_loading() -> bool:
	return _chunk_streaming_service.tick_loading() if _chunk_streaming_service != null else false

func _has_streaming_work() -> bool:
	return _chunk_streaming_service.has_streaming_work() if _chunk_streaming_service != null else false

func _is_streaming_generation_idle() -> bool:
	return _chunk_streaming_service.is_streaming_generation_idle() if _chunk_streaming_service != null else true

## Отправляет генерацию чанка в WorkerThreadPool.
func _submit_async_generate(coord: Vector2i, z_level: int, frontier_lane: int = FrontierScheduler.LANE_BACKGROUND) -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.submit_async_generate(coord, z_level, frontier_lane)

## Выполняется в worker thread. Только чистые данные, никаких Node/scene tree.
func _worker_generate(coord: Vector2i, z_level: int, builder: ChunkContentBuilder = null) -> void:
	if _shutdown_in_progress:
		return
	var worker_start_usec: int = Time.get_ticks_usec()
	var result_entry: Dictionary = {}
	var data: Dictionary
	var native_data_ms: float = 0.0
	var flora_payload_ms: float = 0.0
	var native_data_start_usec: int = Time.get_ticks_usec()
	if z_level != 0:
		data = _generate_solid_rock_chunk()
	else:
		data = _build_surface_chunk_native_data(coord, builder)
	native_data_ms = float(Time.get_ticks_usec() - native_data_start_usec) / 1000.0
	if z_level == 0:
		var flora_payload_start_usec: int = Time.get_ticks_usec()
		if data.has(ChunkFinalPacketScript.FLORA_PAYLOAD_KEY):
			result_entry["flora_payload"] = (data.get(ChunkFinalPacketScript.FLORA_PAYLOAD_KEY, {}) as Dictionary).duplicate(true)
			flora_payload_ms = float(Time.get_ticks_usec() - flora_payload_start_usec) / 1000.0
	if _shutdown_in_progress:
		return
	var worker_total_ms: float = float(Time.get_ticks_usec() - worker_start_usec) / 1000.0
	WorldPerfProbe.record("ChunkGen.worker_native_data_ms %s@z%d" % [coord, z_level], native_data_ms)
	if flora_payload_ms > 0.0:
		WorldPerfProbe.record("ChunkGen.worker_flora_payload_ms %s@z%d" % [coord, z_level], flora_payload_ms)
	WorldPerfProbe.record("ChunkGen.worker_total_ms %s@z%d" % [coord, z_level], worker_total_ms)
	result_entry["worker_native_data_ms"] = native_data_ms
	result_entry["worker_flora_payload_ms"] = flora_payload_ms
	result_entry["worker_total_ms"] = worker_total_ms
	result_entry["native_data"] = data
	_chunk_streaming_service.gen_mutex.lock()
	_chunk_streaming_service.gen_result[coord] = result_entry
	_chunk_streaming_service.gen_mutex.unlock()

func _build_surface_chunk_native_data(coord: Vector2i, builder: ChunkContentBuilder = null) -> Dictionary:
	var native_data: Dictionary = {}
	if builder != null:
		native_data = builder.build_chunk_native_data(coord)
	elif _chunk_streaming_service.worker_chunk_builder != null:
		native_data = _chunk_streaming_service.worker_chunk_builder.build_chunk_native_data(coord)
	elif WorldGenerator:
		native_data = WorldGenerator.build_chunk_native_data(coord)
	if native_data.is_empty():
		return {}
	return _complete_surface_final_packet_publication_payload(coord, native_data)

func _collect_completed_runtime_generates(load_radius: int) -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.collect_completed_runtime_generates(load_radius)

func _promote_runtime_ready_result_to_stage(load_radius: int) -> bool:
	return _chunk_streaming_service.promote_runtime_ready_result_to_stage(load_radius) if _chunk_streaming_service != null else false

func _sort_runtime_ready_queue() -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.sort_runtime_ready_queue()

func _has_relevant_runtime_generate_task() -> bool:
	var load_radius: int = WorldGenerator.balance.load_radius if WorldGenerator and WorldGenerator.balance else 0
	for coord_variant: Variant in _chunk_streaming_service.gen_active_tasks.keys():
		var coord: Vector2i = coord_variant as Vector2i
		var z_level: int = int(_chunk_streaming_service.gen_active_z_levels.get(coord, INVALID_Z_LEVEL))
		if z_level == _active_z and _is_chunk_within_radius(coord, _player_chunk, load_radius):
			return true
	return false

func _sync_runtime_generation_status() -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.sync_runtime_generation_status()

func _is_load_request_relevant(
	request: Dictionary,
	center: Vector2i,
	active_z_level: int,
	load_radius: int
) -> bool:
	return _chunk_streaming_service.is_load_request_relevant(request, center, active_z_level, load_radius) if _chunk_streaming_service != null else false

func _prune_load_queue(center: Vector2i, active_z_level: int, load_radius: int) -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.prune_load_queue(center, active_z_level, load_radius)

func _should_compact_load_queue(center: Vector2i, active_z_level: int, load_radius: int) -> bool:
	return _chunk_streaming_service.should_compact_load_queue(center, active_z_level, load_radius) if _chunk_streaming_service != null else false

func _resolve_max_relevant_load_queue_size(load_radius: int) -> int:
	return _chunk_streaming_service.resolve_max_relevant_load_queue_size(load_radius) if _chunk_streaming_service != null else 0

func _make_surface_payload_cache_key(coord: Vector2i, z_level: int) -> Vector3i:
	if _chunk_surface_payload_cache == null:
		var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
		return Vector3i(canonical_coord.x, canonical_coord.y, z_level)
	return _chunk_surface_payload_cache.make_key(coord, z_level)

func _has_surface_chunk_cache(coord: Vector2i, z_level: int) -> bool:
	return _chunk_surface_payload_cache.has_chunk(coord, z_level) if _chunk_surface_payload_cache != null else false

func _cache_surface_chunk_payload(coord: Vector2i, z_level: int, native_data: Dictionary) -> void:
	if _chunk_surface_payload_cache != null:
		_chunk_surface_payload_cache.cache_native_payload(coord, z_level, native_data)

func _cache_surface_chunk_flora_result(coord: Vector2i, z_level: int, flora_result: ChunkFloraResultScript) -> void:
	if _chunk_surface_payload_cache != null:
		_chunk_surface_payload_cache.cache_flora_result(coord, z_level, flora_result)

func _cache_surface_chunk_flora_payload(coord: Vector2i, z_level: int, flora_payload: Dictionary) -> void:
	if _chunk_surface_payload_cache != null:
		_chunk_surface_payload_cache.cache_flora_payload(coord, z_level, flora_payload)

func _get_cached_surface_chunk_flora_payload(coord: Vector2i, z_level: int) -> Dictionary:
	return _chunk_surface_payload_cache.get_flora_payload(coord, z_level) if _chunk_surface_payload_cache != null else {}

func _get_cached_surface_chunk_flora_result(coord: Vector2i, z_level: int) -> ChunkFloraResultScript:
	return _chunk_surface_payload_cache.get_flora_result(coord, z_level) if _chunk_surface_payload_cache != null else null

func _try_get_surface_payload_cache_native_data(coord: Vector2i, z_level: int, out_native_data: Dictionary) -> bool:
	return _chunk_surface_payload_cache.try_get_native_data(coord, z_level, out_native_data) if _chunk_surface_payload_cache != null else false

func _try_stage_surface_chunk_from_cache(coord: Vector2i, z_level: int) -> bool:
	return _chunk_streaming_service.try_stage_surface_chunk_from_cache(coord, z_level) if _chunk_streaming_service != null else false

func _duplicate_native_data(native_data: Dictionary) -> Dictionary:
	return ChunkFinalPacketScript.duplicate_surface_packet(native_data)

func _sort_chunk_entry_queue_by_priority(queue: Array[Dictionary], center: Vector2i) -> void:
	if queue.size() <= 1:
		return
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _chunk_priority_less(
			a.get("coord", Vector2i.ZERO) as Vector2i,
			b.get("coord", Vector2i.ZERO) as Vector2i,
			center
		)
	)

func _finalize_chunk_install(coord: Vector2i, z_level: int, chunk: Chunk) -> void:
	var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(z_level)
	if loaded_chunks_for_z.has(coord):
		chunk.queue_free()
		return
	_sync_chunk_display_position(chunk, _player_chunk)
	# Fresh installs must enter the tree hidden; visibility is published only by the full_ready gate.
	chunk.visible = false
	var z_container: Node2D = _z_containers.get(z_level) as Node2D
	if z_container:
		z_container.add_child(chunk)
	else:
		_chunk_container.add_child(chunk)
	loaded_chunks_for_z[coord] = chunk
	if z_level == _active_z:
		_set_loaded_chunks_alias(z_level)
	_sync_native_loaded_open_pocket_query_chunk(coord, chunk, z_level)
	if not chunk.is_redraw_complete():
		_schedule_chunk_visual_work(chunk, z_level)
	_sync_chunk_visibility_for_publication(chunk)
	_boot_on_chunk_applied(coord, chunk)
	if _should_track_surface_topology(z_level):
		_install_surface_chunk_into_topology(coord, chunk)
	_enqueue_neighbor_border_redraws(coord)
	EventBus.chunk_loaded.emit(coord)
	_debug_record_recent_lifecycle_event(
		"loaded",
		coord,
		z_level,
		"Загрузка представления в мир",
		"чанк установлен в мир, визуал продолжает сходиться через scheduler",
		-1.0
	)
	_debug_emit_chunk_event(
		"chunk_installed_hidden",
		"установила скрытый чанк",
		coord,
		z_level,
		"чанк получил node в scene tree, но остаётся скрытым до terminal full_ready publication",
		WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT,
		"queued",
		"ожидает публикации",
		"queued_publication",
		{"visual_queue_depth": _debug_visual_queue_depth()}
	)

func _stage_prepared_chunk_install(
	coord: Vector2i,
	z_level: int,
	native_data: Dictionary,
	prepared_flora_result: ChunkFloraResultScript = null,
	prepared_flora_payload: Dictionary = {}
) -> bool:
	return _chunk_streaming_service.stage_prepared_chunk_install(
		coord,
		z_level,
		native_data,
		prepared_flora_result,
		prepared_flora_payload
	) if _chunk_streaming_service != null else false

func _cache_chunk_install_handoff_entry(entry: Dictionary, z_level: int) -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.cache_chunk_install_handoff_entry(entry, z_level)

## Фаза 0: только генерация terrain данных. CPU-heavy. Используется ТОЛЬКО в boot.
func _staged_loading_generate(coord: Vector2i) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if _loaded_chunks.has(coord) or not _terrain_tileset or not _overlay_tileset:
		return
	if _active_z != 0:
		_chunk_streaming_service.staged_data = _generate_solid_rock_chunk()
	else:
		_chunk_streaming_service.staged_data = _build_surface_chunk_native_data(coord)
	_chunk_streaming_service.staged_coord = coord
	_chunk_streaming_service.staged_z = _active_z
	WorldPerfProbe.end("ChunkStreaming.phase0_generate %s" % [coord], started_usec)

## Фаза 1: создание Chunk node + populate bytes.
func _staged_loading_create() -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.staged_loading_create()

## Фаза 2: добавить в scene tree + topology + enqueue redraw.
func _staged_loading_finalize() -> void:
	if _chunk_streaming_service != null:
		_chunk_streaming_service.staged_loading_finalize()

## Progressive redraw одного шага. Возвращает true если есть ещё работа.
func _tick_redraws() -> bool:
	return _tick_visuals()

## Topology build один шаг. Возвращает true если есть ещё работа.
func _tick_topology() -> bool:
	if _shutdown_in_progress:
		return false
	if _is_boot_in_progress:
		return false
	if _active_z != 0:
		return false
	var seam_has_more: bool = _process_seam_refresh_queue_step()
	if seam_has_more:
		return true
	if _chunk_topology_service == null:
		return false
	return _chunk_topology_service.tick(_active_z, _is_streaming_generation_idle())

func _process_chunk_redraws() -> void:
	if _chunk_visual_scheduler != null:
		_chunk_visual_scheduler.process_one_task(0, {})

func _get_loaded_chunks_for_z(z_level: int) -> Dictionary:
	if not _z_chunks.has(z_level):
		_z_chunks[z_level] = {}
	return _z_chunks[z_level] as Dictionary

func _set_loaded_chunks_alias(z_level: int) -> Dictionary:
	var loaded_chunks_for_z: Dictionary = _get_loaded_chunks_for_z(z_level)
	_loaded_chunks = loaded_chunks_for_z
	return loaded_chunks_for_z

func _setup_z_containers() -> void:
	for z: int in [ZLevelManager.Z_MIN, 0, ZLevelManager.Z_MAX]:
		var container := Node2D.new()
		container.name = "ZLayer_%d" % z
		container.visible = (z == 0)
		_chunk_container.add_child(container)
		_z_containers[z] = container
		_z_chunks[z] = {}
	_set_loaded_chunks_alias(0)

func set_active_z_level(z: int) -> void:
	_active_z = z
	for layer_z: int in _z_containers:
		(_z_containers[layer_z] as Node2D).visible = (layer_z == z)
	_set_loaded_chunks_alias(z)
	_rebuild_native_loaded_open_pocket_query_cache()
	_invalidate_display_sync_cache()
	var reference_chunk: Vector2i = _player_chunk
	if _player and WorldGenerator:
		reference_chunk = WorldGenerator.world_to_chunk(_player.global_position)
	_sync_loaded_chunk_display_positions(reference_chunk, true)
	if _chunk_streaming_service != null:
		_chunk_streaming_service.handle_active_z_changed(z)
	_player_chunk = Vector2i(99999, 99999)
	# Force immediate fog update on z-level entry
	if z != 0 and _player:
		_fog_state.clear()
		var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
		var delta: Dictionary = _fog_state.update(player_tile)
		_apply_underground_fog_visible_tiles(delta.get("newly_visible", {}))

func get_active_z_level() -> int:
	return _active_z

## Generate a chunk filled entirely with ROCK (for underground z != 0).
func _generate_solid_rock_chunk() -> Dictionary:
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles
	var terrain := PackedByteArray()
	var height := PackedFloat32Array()
	var variation := PackedByteArray()
	var biome := PackedByteArray()
	terrain.resize(chunk_size * chunk_size)
	height.resize(chunk_size * chunk_size)
	variation.resize(chunk_size * chunk_size)
	biome.resize(chunk_size * chunk_size)
	terrain.fill(TileGenData.TerrainType.ROCK)
	height.fill(0.5)
	variation.fill(0)
	biome.fill(0)
	return {"chunk_size": chunk_size, "terrain": terrain, "height": height, "variation": variation, "biome": biome}

## Create a tiny underground pocket at z=-1. Ensures ALL needed chunks are loaded
## and sets specified tiles to MINED_FLOOR. Called from debug path only.
func ensure_underground_pocket(center_tile: Vector2i, pocket_tiles: Array) -> void:
	var prev_z: int = _active_z
	if _active_z != -1:
		set_active_z_level(-1)
	# Collect all chunk coords needed: pocket tiles + 1-tile wall ring around them
	var needed_coords: Dictionary = {}
	for tile_pos: Variant in pocket_tiles:
		var t: Vector2i = _canonical_tile(tile_pos as Vector2i)
		needed_coords[WorldGenerator.tile_to_chunk(t)] = true
		for offset: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
				Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			needed_coords[WorldGenerator.tile_to_chunk(_offset_tile(t, offset))] = true
	# Ensure all needed chunks are loaded
	for coord: Vector2i in needed_coords:
		if _loaded_chunks.has(coord):
			continue
		var data: Dictionary = _generate_solid_rock_chunk()
		var chunk_biome: BiomeData = _resolve_chunk_biome(coord, -1)
		var tileset_bundle: Dictionary = _get_or_build_tileset_bundle(chunk_biome)
		var ug_ts: TileSet = tileset_bundle.get("underground_terrain") as TileSet
		var overlay_tileset: TileSet = tileset_bundle.get("overlay") as TileSet
		if not ug_ts or not overlay_tileset:
			continue
		var chunk := Chunk.new()
		chunk.setup(coord, WorldGenerator.balance.tile_size, WorldGenerator.balance.chunk_size_tiles,
			chunk_biome, ug_ts, overlay_tileset, self)
		chunk.set_underground(true)
		chunk.populate_native(data, {}, false)
		if _fog_tileset:
			chunk.init_fog_layer(_fog_tileset)
		var z_container: Node2D = _z_containers.get(-1) as Node2D
		if z_container:
			z_container.add_child(chunk)
		_loaded_chunks[coord] = chunk
		chunk._begin_progressive_redraw()
	# Carve the pocket through the production mining path so topology/reveal/visuals stay aligned.
	var tile_size: int = WorldGenerator.balance.tile_size if WorldGenerator and WorldGenerator.balance else 1
	for tile_pos: Variant in pocket_tiles:
		var t: Vector2i = _canonical_tile(tile_pos as Vector2i)
		var ch: Chunk = get_chunk_at_tile(t)
		if not ch:
			continue
		var local: Vector2i = ch.global_to_local(t)
		if ch.get_terrain_type_at(local) != TileGenData.TerrainType.ROCK:
			continue
		var world_pos := Vector2(
			t.x * tile_size + tile_size * 0.5,
			t.y * tile_size + tile_size * 0.5
		)
		try_harvest_at_world(world_pos)
	# Restore original z
	if prev_z != -1:
		set_active_z_level(prev_z)

func _collect_chunk_coords_from_tiles(tile_map: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tile_pos: Vector2i in tile_map:
		result[WorldGenerator.tile_to_chunk(tile_pos)] = true
	return result

func _group_tiles_by_chunk(tile_map: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tile_pos: Vector2i in tile_map:
		var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(tile_pos)
		if not result.has(chunk_coord):
			result[chunk_coord] = {}
		(result[chunk_coord] as Dictionary)[tile_pos] = true
	return result

func _to_chunk_coord_set(chunk_coords: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in chunk_coords:
		if value is Vector2i:
			result[value] = true
	return result

func _on_mountain_tile_changed(tile_pos: Vector2i, old_type: int, new_type: int) -> void:
	tile_pos = _canonical_tile(tile_pos)
	if _native_loaded_open_pocket_query != null:
		_native_loaded_open_pocket_query.call("update_tile", tile_pos, new_type)
	if _chunk_topology_service != null:
		_chunk_topology_service.note_mountain_tile_changed(_active_z, tile_pos, old_type, new_type)

func _should_track_surface_topology(z_level: int) -> bool:
	return z_level == 0

func _install_surface_chunk_into_topology(coord: Vector2i, chunk: Chunk) -> void:
	if _chunk_topology_service != null:
		_chunk_topology_service.install_surface_chunk(coord, chunk)

func _remove_surface_chunk_from_topology(coord: Vector2i) -> void:
	if _chunk_topology_service != null:
		_chunk_topology_service.remove_surface_chunk(coord)

func _is_mountain_topology_tile(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.ROCK \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _boot_count_applied_chunks() -> int:
	return _chunk_boot_pipeline.count_applied_chunks() if _chunk_boot_pipeline != null else 0

func _boot_on_chunk_applied(coord: Vector2i, chunk: Chunk) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.on_chunk_applied(coord, chunk)

func _boot_on_chunk_redraw_progress(chunk: Chunk) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.on_chunk_redraw_progress(chunk)

func _boot_is_first_playable_slice_ready() -> bool:
	return _chunk_boot_pipeline.is_first_playable_slice_ready() if _chunk_boot_pipeline != null else false

func _boot_has_pending_near_ring_work() -> bool:
	return _chunk_boot_pipeline.has_pending_near_ring_work() if _chunk_boot_pipeline != null else false

func _boot_enqueue_runtime_load(coord: Vector2i) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.enqueue_runtime_load(coord)

func _boot_all_tracked_chunks_visual_complete() -> bool:
	return _chunk_boot_pipeline.all_tracked_chunks_visual_complete() if _chunk_boot_pipeline != null else false

func _boot_has_pending_runtime_handoff_work() -> bool:
	return _chunk_boot_pipeline.has_pending_runtime_handoff_work() if _chunk_boot_pipeline != null else false

func _boot_process_redraw_budget(max_usec: int) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.process_redraw_budget(max_usec)

func _boot_start_runtime_handoff() -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.start_runtime_handoff()

## --- Boot remaining tick (post-first_playable background completion) ---

func _tick_boot_remaining() -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.tick_remaining()

## --- Boot compute/apply helpers (boot_chunk_compute_pipeline_spec) ---

## Pure-data boot compute helper. R1 blocks legacy sync fallback semantics.
func _boot_compute_chunk_native_data(coord: Vector2i, z_level: int) -> Dictionary:
	return _chunk_boot_pipeline.compute_chunk_native_data(coord, z_level) if _chunk_boot_pipeline != null else {}

## Worker function: runs in WorkerThreadPool, writes result through mutex.
func _boot_worker_compute(
	coord: Vector2i,
	z_level: int,
	builder: ChunkContentBuilder,
	generation: int,
	requested_usec: int
) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.worker_compute(coord, z_level, builder, generation, requested_usec)

## Submit pending compute tasks up to BOOT_MAX_CONCURRENT_COMPUTE.
func _boot_submit_pending_tasks() -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.submit_pending_tasks()

## Collect completed worker results. Returns coords that finished.
func _boot_collect_completed() -> Array[Vector2i]:
	return _chunk_boot_pipeline.collect_completed() if _chunk_boot_pipeline != null else []

## Move computed results from worker output into the sorted prepare queue.
## Discards stale (wrong generation) and failed (empty native_data) results.
func _boot_drain_computed_to_apply_queue() -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.drain_computed_to_apply_queue()

func _boot_prepare_apply_entries() -> int:
	return _chunk_boot_pipeline.prepare_apply_entries() if _chunk_boot_pipeline != null else 0

## Apply up to BOOT_MAX_APPLY_PER_STEP chunks from the sorted apply queue.
## Startup chunks publish through the visual scheduler and stay hidden until
## terminal full-ready publication is reached.
func _boot_apply_from_queue() -> int:
	return _chunk_boot_pipeline.apply_from_queue() if _chunk_boot_pipeline != null else 0

## Wait for all active boot compute tasks and clean up.
func _boot_wait_all_compute() -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.wait_all_compute()

func _boot_cleanup_compute_pipeline() -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.cleanup_compute_pipeline()

## Main-thread apply: creates Chunk node, populates, attaches to tree.
func _boot_apply_chunk_from_native_data(
	coord: Vector2i,
	z_level: int,
	native_data: Dictionary,
	flora_payload: Dictionary = {},
	install_entry: Dictionary = {}
) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.apply_chunk_from_native_data(coord, z_level, native_data, flora_payload, install_entry)

## --- Boot readiness helpers (boot_chunk_readiness_spec) ---

func _boot_init_readiness(center: Vector2i, load_radius: int) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.init_readiness(center, load_radius)

func _boot_set_chunk_state(coord: Vector2i, new_state: BootChunkState) -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.set_chunk_state(coord, int(new_state))

func _boot_get_chunk_ring(coord: Vector2i) -> int:
	return _chunk_boot_pipeline.get_chunk_ring(coord) if _chunk_boot_pipeline != null else 0

func _boot_update_gates() -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.update_gates()

func _boot_promote_redrawn_chunks() -> void:
	if _chunk_boot_pipeline != null:
		_chunk_boot_pipeline.promote_redrawn_chunks()

## Read-only boot readiness API.

func is_boot_first_playable() -> bool:
	return _chunk_boot_pipeline.is_first_playable() if _chunk_boot_pipeline != null else false

func is_boot_complete() -> bool:
	return _chunk_boot_pipeline.is_complete() if _chunk_boot_pipeline != null else false

func get_boot_chunk_state(coord: Vector2i) -> int:
	return _chunk_boot_pipeline.get_chunk_state(coord) if _chunk_boot_pipeline != null else -1

func get_boot_chunk_states_snapshot() -> Dictionary:
	return _chunk_boot_pipeline.get_chunk_states_snapshot() if _chunk_boot_pipeline != null else {}

func get_boot_compute_active_count() -> int:
	return _chunk_boot_pipeline.get_compute_active_count() if _chunk_boot_pipeline != null else 0

func get_boot_compute_pending_count() -> int:
	return _chunk_boot_pipeline.get_compute_pending_count() if _chunk_boot_pipeline != null else 0

func get_boot_failed_coords() -> Array[Vector2i]:
	return _chunk_boot_pipeline.get_failed_coords() if _chunk_boot_pipeline != null else []
