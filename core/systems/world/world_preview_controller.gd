class_name WorldPreviewController
extends RefCounted

const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldFoundationPalette = preload("res://core/systems/world/world_foundation_palette.gd")
const WorldOverviewCanvas = preload("res://scenes/ui/world_overview_canvas.gd")
const WorldPreviewCanvas = preload("res://scenes/ui/world_preview_canvas.gd")
const WorldPreviewPalette = preload("res://core/systems/world/world_preview_palette.gd")
const WorldPreviewPatchCache = preload("res://core/systems/world/world_preview_patch_cache.gd")
const WorldPreviewRenderMode = preload("res://core/systems/world/world_preview_render_mode.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldSpawnResolver = preload("res://core/systems/world/world_spawn_resolver.gd")

const STAGE_RADII_CHUNKS := [2, 6, 10, 16]
const REBUILD_DEBOUNCE_SECONDS: float = 0.12
const IN_FLIGHT_REQUEST_CAP: int = 8
const MAX_RESULTS_PER_TICK: int = 4
const MAX_SPAWN_RESULTS_PER_TICK: int = 2
const MAX_OVERVIEW_RESULTS_PER_TICK: int = 2
const MAX_PUBLISHES_PER_TICK: int = 4
const PACKET_BACKEND_MAX_BATCH_SIZE: int = 64

var _packet_backend: WorldChunkPacketBackend = WorldChunkPacketBackend.new()
var _patch_cache: WorldPreviewPatchCache = WorldPreviewPatchCache.new()
var _foundation_palette: WorldFoundationPalette = WorldFoundationPalette.new()
var _palette: WorldPreviewPalette = WorldPreviewPalette.new()
var _overview_canvas: WorldOverviewCanvas = null
var _canvas: WorldPreviewCanvas = null
var _is_started: bool = false
var _preview_epoch: int = 0
var _debounce_remaining: float = -1.0
var _pending_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var _pending_settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
var _pending_world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
var _pending_foundation_settings: FoundationGenSettings = FoundationGenSettings.hard_coded_defaults()
var _pending_settings_signature: String = ""
var _active_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var _active_world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
var _active_settings_signature: String = ""
var _active_settings_packed: PackedFloat32Array = PackedFloat32Array()
var _active_render_mode: StringName = WorldPreviewRenderMode.TERRAIN
var _current_center_chunk: Vector2i = Vector2i.ZERO
var _current_spawn_tile: Vector2i = Vector2i.ZERO
var _current_spawn_safe_patch_rect: Rect2i = Rect2i()
var _stage_plans: Array[Dictionary] = []
var _current_stage_index: int = -1
var _current_stage_window: Array[Vector2i] = []
var _current_stage_request_queue: Array[Vector2i] = []
var _in_flight_requests: Dictionary = {}
var _ready_patches: Dictionary = {}
var _ready_publish_queue: Array[Vector2i] = []
var _ready_publish_lookup: Dictionary = {}
var _published_patches: Dictionary = {}
var _awaiting_spawn_result: bool = false
var _awaiting_overview_result: bool = false
var _has_spawn_context: bool = false
var _overview_texture: Texture2D = null

func start() -> void:
	if _is_started:
		return
	_packet_backend.set_max_batch_size(PACKET_BACKEND_MAX_BATCH_SIZE)
	_packet_backend.start()
	_is_started = true

func stop() -> void:
	if not _is_started:
		return
	_packet_backend.stop()
	_is_started = false

func attach_overview_canvas(canvas: WorldOverviewCanvas) -> void:
	_overview_canvas = canvas
	if _overview_canvas == null:
		return
	_overview_canvas.reset_overview(_active_world_bounds)
	_sync_overview_detail_context()
	if _overview_texture != null:
		_overview_canvas.publish_overview(_overview_texture)
	else:
		_overview_canvas.set_loading(_awaiting_overview_result)

func attach_canvas(canvas: WorldPreviewCanvas) -> void:
	_canvas = canvas
	if _canvas == null:
		return
	_canvas.reset_preview(
		_current_center_chunk,
		_current_spawn_tile,
		_resolve_full_radius_chunks()
	)
	_canvas.set_render_mode(_active_render_mode, _current_spawn_safe_patch_rect)
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _published_patches.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	for chunk_coord: Vector2i in chunk_coords:
		_canvas.publish_chunk_patch(
			chunk_coord,
			_published_patches.get(chunk_coord, null) as Texture2D
		)
	_update_canvas_progress()

func get_render_mode() -> StringName:
	return _active_render_mode

func get_overview_mode() -> StringName:
	return _foundation_palette.get_mode()

func set_overview_mode(overview_mode: StringName) -> void:
	var normalized_mode: StringName = WorldFoundationPalette.coerce_mode(overview_mode)
	if normalized_mode == _foundation_palette.get_mode():
		return
	_foundation_palette.set_mode(normalized_mode)
	_queue_overview_for_active_snapshot()

func set_render_mode(render_mode: StringName) -> void:
	var normalized_mode: StringName = WorldPreviewRenderMode.coerce(render_mode)
	if normalized_mode == _active_render_mode:
		return
	var previous_patch_mode: StringName = _resolve_patch_render_mode()
	_active_render_mode = normalized_mode
	if _canvas != null:
		_canvas.set_render_mode(_active_render_mode, _current_spawn_safe_patch_rect)
	if previous_patch_mode == _resolve_patch_render_mode():
		return
	_republish_visible_patches_for_current_mode()

func queue_preview_rebuild(
	seed_value: int,
	settings: MountainGenSettings,
	world_bounds: WorldBoundsSettings = null,
	foundation_settings: FoundationGenSettings = null
) -> void:
	_pending_seed = seed_value
	_pending_settings = _clone_settings(settings)
	_pending_world_bounds = _clone_world_bounds(world_bounds)
	_pending_foundation_settings = _clone_foundation_settings(
		foundation_settings,
		_pending_world_bounds
	)
	_pending_settings_signature = _compute_worldgen_signature(
		_pending_settings,
		_pending_world_bounds,
		_pending_foundation_settings
	)
	_preview_epoch += 1
	_debounce_remaining = REBUILD_DEBOUNCE_SECONDS
	_packet_backend.clear_queued_work()
	_awaiting_spawn_result = false
	_awaiting_overview_result = false
	_has_spawn_context = false
	_overview_texture = null
	_current_stage_request_queue.clear()
	_in_flight_requests.clear()
	_ready_patches.clear()
	_ready_publish_queue.clear()
	_ready_publish_lookup.clear()
	_stage_plans.clear()
	_current_stage_window.clear()
	_current_stage_index = -1
	if _overview_canvas != null:
		_overview_canvas.reset_overview(_pending_world_bounds)
		_overview_canvas.clear_detail_region_context()
		_overview_canvas.set_loading(true)
	_update_canvas_progress()

func tick(delta: float) -> void:
	if not _is_started:
		return
	if _debounce_remaining >= 0.0:
		_debounce_remaining -= delta
		if _debounce_remaining <= 0.0:
			_debounce_remaining = -1.0
			_start_rebuild_from_pending_snapshot()
	_drain_ready_spawn_results()
	_drain_ready_overview_results()
	_drain_ready_packets()
	_advance_stage_if_needed()
	_fill_request_window()
	_publish_ready_patches()
	_update_canvas_progress()

func _queue_overview_for_active_snapshot() -> void:
	if _active_settings_packed.is_empty():
		return
	_awaiting_overview_result = true
	_overview_texture = null
	_packet_backend.queue_overview_request(
		_active_seed,
		WorldRuntimeConstants.WORLD_VERSION,
		_active_settings_packed,
		_preview_epoch,
		_foundation_palette.get_layer_mask(),
		_foundation_palette.get_pixels_per_cell()
	)
	if _overview_canvas != null:
		_overview_canvas.reset_overview(_active_world_bounds)
		_sync_overview_detail_context()
		_overview_canvas.set_loading(true)

func _start_rebuild_from_pending_snapshot() -> void:
	_published_patches.clear()
	_ready_patches.clear()
	_ready_publish_queue.clear()
	_ready_publish_lookup.clear()
	_current_stage_request_queue.clear()
	_in_flight_requests.clear()
	_packet_backend.clear_queued_work()
	_active_seed = _pending_seed
	_active_world_bounds = _clone_world_bounds(_pending_world_bounds)
	_active_settings_signature = _pending_settings_signature
	_active_settings_packed = _build_settings_packed(
		_pending_settings,
		_pending_world_bounds,
		_pending_foundation_settings
	)
	_awaiting_spawn_result = true
	_has_spawn_context = false
	_packet_backend.queue_spawn_request(
		_active_seed,
		WorldRuntimeConstants.WORLD_VERSION,
		_active_settings_packed,
		_preview_epoch
	)
	_awaiting_overview_result = true
	_overview_texture = null
	_packet_backend.queue_overview_request(
		_active_seed,
		WorldRuntimeConstants.WORLD_VERSION,
		_active_settings_packed,
		_preview_epoch,
		_foundation_palette.get_layer_mask(),
		_foundation_palette.get_pixels_per_cell()
	)
	_current_center_chunk = WorldRuntimeConstants.tile_to_chunk(_current_spawn_tile)
	_stage_plans.clear()
	_current_stage_window.clear()
	_current_stage_index = -1
	if _canvas != null:
		_canvas.reset_preview(
			_current_center_chunk,
			_current_spawn_tile,
			_resolve_full_radius_chunks()
		)
		_canvas.set_render_mode(_active_render_mode, _current_spawn_safe_patch_rect)
	if _overview_canvas != null:
		_overview_canvas.reset_overview(_active_world_bounds)
		_overview_canvas.clear_detail_region_context()
		_overview_canvas.set_loading(true)
	_update_canvas_progress()

func _drain_ready_spawn_results() -> void:
	if not _awaiting_spawn_result:
		return
	var ready_results: Array[Dictionary] = _packet_backend.drain_completed_spawn_results(MAX_SPAWN_RESULTS_PER_TICK)
	for spawn_result: Dictionary in ready_results:
		if int(spawn_result.get("epoch", -1)) != _preview_epoch:
			continue
		_awaiting_spawn_result = false
		if not bool(spawn_result.get("success", false)):
			push_error(
				"WorldPreviewController native spawn resolution failed: %s"
				% str(spawn_result.get("message", "unknown error"))
			)
			_stage_plans.clear()
			_current_stage_window.clear()
			_current_stage_request_queue.clear()
			_in_flight_requests.clear()
			_update_canvas_progress()
			return
		_begin_rebuild_from_spawn_result(spawn_result)
		return

func _drain_ready_overview_results() -> void:
	if not _awaiting_overview_result:
		return
	var ready_results: Array[Dictionary] = _packet_backend.drain_completed_overviews(MAX_OVERVIEW_RESULTS_PER_TICK)
	for overview_result: Dictionary in ready_results:
		if int(overview_result.get("epoch", -1)) != _preview_epoch:
			continue
		if int(overview_result.get("layer_mask", -1)) != _foundation_palette.get_layer_mask():
			continue
		_awaiting_overview_result = false
		if not bool(overview_result.get("success", false)):
			push_error(
				"WorldPreviewController native overview generation failed: %s"
				% str(overview_result.get("message", "unknown error"))
			)
			if _overview_canvas != null:
				_overview_canvas.set_loading(false)
			return
		var overview_image_variant: Variant = overview_result.get("image", null)
		if overview_image_variant is Image:
			_overview_texture = _foundation_palette.build_overview_texture(overview_image_variant as Image)
		else:
			var snapshot: Dictionary = overview_result.get("snapshot", {}) as Dictionary
			_overview_texture = _foundation_palette.build_overview_texture_from_snapshot(snapshot)
		if _overview_canvas != null:
			if _overview_texture != null:
				_overview_canvas.publish_overview(_overview_texture)
			else:
				_overview_canvas.set_loading(false)
		return

func _begin_rebuild_from_spawn_result(spawn_result: Dictionary) -> void:
	_current_spawn_tile = WorldSpawnResolver.resolve_spawn_tile_from_native_result(spawn_result)
	_current_spawn_safe_patch_rect = WorldSpawnResolver.resolve_spawn_safe_patch_rect_from_native_result(spawn_result)
	_current_center_chunk = WorldRuntimeConstants.tile_to_chunk(_current_spawn_tile)
	_has_spawn_context = true
	_stage_plans = _build_stage_plans(_current_center_chunk)
	_current_stage_window.clear()
	_current_stage_index = -1
	if _canvas != null:
		_canvas.reset_preview(
			_current_center_chunk,
			_current_spawn_tile,
			_resolve_full_radius_chunks()
		)
		_canvas.set_render_mode(_active_render_mode, _current_spawn_safe_patch_rect)
	_advance_stage_if_needed()
	_fill_request_window()
	_publish_ready_patches()
	_sync_overview_detail_context()
	_update_canvas_progress()

func _sync_overview_detail_context() -> void:
	if _overview_canvas == null:
		return
	if not _has_spawn_context:
		_overview_canvas.clear_detail_region_context()
		return
	_overview_canvas.set_detail_region_context(
		_current_center_chunk,
		_current_spawn_tile,
		_resolve_full_radius_chunks()
	)

func _drain_ready_packets() -> void:
	var ready_packets: Array[Dictionary] = _packet_backend.drain_completed_packets(MAX_RESULTS_PER_TICK)
	for packet: Dictionary in ready_packets:
		if int(packet.get("epoch", -1)) != _preview_epoch:
			continue
		var chunk_coord: Vector2i = packet.get(
			"request_chunk_coord",
			packet.get("chunk_coord", Vector2i.ZERO)
		) as Vector2i
		_in_flight_requests.erase(chunk_coord)
		_patch_cache.store_packet(_build_packet_cache_key(chunk_coord), packet)
		if _has_available_patch(chunk_coord):
			continue
		var patch_texture: Texture2D = _resolve_patch_texture(chunk_coord, packet)
		if patch_texture != null:
			_store_ready_patch(chunk_coord, patch_texture)

func _advance_stage_if_needed() -> void:
	if _awaiting_spawn_result:
		return
	while true:
		if _current_stage_index >= 0 and not _is_stage_complete(_current_stage_index):
			return
		if _current_stage_index + 1 >= _stage_plans.size():
			return
		_current_stage_index += 1
		var stage_plan: Dictionary = _stage_plans[_current_stage_index] as Dictionary
		_current_stage_window = _coerce_chunk_coords(stage_plan.get("window_coords", []))
		_current_stage_request_queue.clear()
		for chunk_coord: Vector2i in _coerce_chunk_coords(stage_plan.get("request_coords", [])):
			if _has_available_patch(chunk_coord):
				continue
			var cached_patch: Texture2D = _resolve_patch_texture(chunk_coord)
			if cached_patch != null:
				_store_ready_patch(chunk_coord, cached_patch)
				continue
			_current_stage_request_queue.append(chunk_coord)

func _fill_request_window() -> void:
	if _awaiting_spawn_result:
		return
	if _current_stage_index < 0:
		return
	while _in_flight_requests.size() < IN_FLIGHT_REQUEST_CAP and not _current_stage_request_queue.is_empty():
		var chunk_coord: Vector2i = _current_stage_request_queue.pop_front()
		if _has_available_patch(chunk_coord) or _in_flight_requests.has(chunk_coord):
			continue
		_in_flight_requests[chunk_coord] = true
		_packet_backend.queue_packet_request(
			chunk_coord,
			_active_seed,
			WorldRuntimeConstants.WORLD_VERSION,
			_active_settings_packed,
			_preview_epoch
		)

func _publish_ready_patches() -> void:
	var published_this_tick: int = 0
	while published_this_tick < MAX_PUBLISHES_PER_TICK and not _ready_publish_queue.is_empty():
		var chunk_coord: Vector2i = _ready_publish_queue.pop_front()
		_ready_publish_lookup.erase(chunk_coord)
		var patch_texture: Texture2D = _ready_patches.get(chunk_coord, null) as Texture2D
		if patch_texture == null:
			continue
		_ready_patches.erase(chunk_coord)
		_published_patches[chunk_coord] = patch_texture
		if _canvas != null:
			_canvas.publish_chunk_patch(chunk_coord, patch_texture)
		published_this_tick += 1

func _build_stage_plans(center_chunk: Vector2i) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	var seen_chunks: Dictionary = {}
	for radius: int in STAGE_RADII_CHUNKS:
		var window_coords: Array[Vector2i] = []
		var request_coords: Array[Vector2i] = []
		for chunk_coord: Vector2i in _build_square_spiral(center_chunk, radius):
			if not _is_preview_chunk_y_in_bounds(chunk_coord):
				continue
			window_coords.append(chunk_coord)
			if seen_chunks.has(chunk_coord):
				continue
			seen_chunks[chunk_coord] = true
			request_coords.append(chunk_coord)
		plans.append({
			"radius": radius,
			"window_coords": window_coords,
			"request_coords": request_coords,
		})
	return plans

func _build_square_spiral(center_chunk: Vector2i, max_radius: int) -> Array[Vector2i]:
	var order: Array[Vector2i] = [center_chunk]
	for radius: int in range(1, max_radius + 1):
		var min_x: int = center_chunk.x - radius
		var max_x: int = center_chunk.x + radius
		var min_y: int = center_chunk.y - radius
		var max_y: int = center_chunk.y + radius
		for x: int in range(min_x, max_x + 1):
			order.append(Vector2i(x, min_y))
		for y: int in range(min_y + 1, max_y + 1):
			order.append(Vector2i(max_x, y))
		for x: int in range(max_x - 1, min_x - 1, -1):
			order.append(Vector2i(x, max_y))
		for y: int in range(max_y - 1, min_y, -1):
			order.append(Vector2i(min_x, y))
	return order

func _is_preview_chunk_y_in_bounds(chunk_coord: Vector2i) -> bool:
	return _active_world_bounds == null or _active_world_bounds.is_chunk_y_in_bounds(chunk_coord.y)

func _store_ready_patch(chunk_coord: Vector2i, patch_texture: Texture2D) -> void:
	if patch_texture == null:
		return
	if _published_patches.has(chunk_coord) or _ready_patches.has(chunk_coord):
		return
	_ready_patches[chunk_coord] = patch_texture
	if not _ready_publish_lookup.has(chunk_coord):
		_ready_publish_lookup[chunk_coord] = true
		_ready_publish_queue.append(chunk_coord)

func _has_available_patch(chunk_coord: Vector2i) -> bool:
	return _published_patches.has(chunk_coord) or _ready_patches.has(chunk_coord)

func _resolve_patch_texture(
	chunk_coord: Vector2i,
	packet_override: Dictionary = {}
) -> Texture2D:
	var patch_cache_key: String = _build_patch_cache_key(chunk_coord)
	var cached_patch: Texture2D = _patch_cache.get_patch(patch_cache_key)
	if cached_patch != null:
		return cached_patch
	var source_packet: Dictionary = packet_override
	if source_packet.is_empty():
		source_packet = _patch_cache.get_packet(_build_packet_cache_key(chunk_coord))
	if source_packet.is_empty():
		return null
	var patch_texture: Texture2D = _palette.build_patch_texture(
		source_packet,
		_resolve_patch_render_mode()
	)
	_patch_cache.store_patch(patch_cache_key, patch_texture)
	return patch_texture

func _republish_visible_patches_for_current_mode() -> void:
	var visible_chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _published_patches.keys():
		visible_chunk_coords.append(chunk_coord_variant as Vector2i)
	for chunk_coord_variant: Variant in _ready_patches.keys():
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		if not visible_chunk_coords.has(chunk_coord):
			visible_chunk_coords.append(chunk_coord)
	visible_chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	_published_patches.clear()
	_ready_patches.clear()
	_ready_publish_queue.clear()
	_ready_publish_lookup.clear()
	if _canvas != null:
		_canvas.set_render_mode(_active_render_mode, _current_spawn_safe_patch_rect)
		_canvas.clear_patches()
	for chunk_coord: Vector2i in visible_chunk_coords:
		var patch_texture: Texture2D = _resolve_patch_texture(chunk_coord)
		if patch_texture != null:
			_store_ready_patch(chunk_coord, patch_texture)
	_publish_ready_patches()
	_update_canvas_progress()

func _is_stage_complete(stage_index: int) -> bool:
	if stage_index < 0 or stage_index >= _stage_plans.size():
		return false
	for chunk_coord: Vector2i in _coerce_chunk_coords((_stage_plans[stage_index] as Dictionary).get("window_coords", [])):
		if not _has_available_patch(chunk_coord):
			return false
	return true

func _build_patch_cache_key(chunk_coord: Vector2i) -> String:
	return _patch_cache.make_patch_key(
		_active_seed,
		WorldRuntimeConstants.WORLD_VERSION,
		_active_settings_signature,
		chunk_coord,
		_palette.get_palette_id(_resolve_patch_render_mode())
	)

func _build_packet_cache_key(chunk_coord: Vector2i) -> String:
	return _patch_cache.make_packet_key(
		_active_seed,
		WorldRuntimeConstants.WORLD_VERSION,
		_active_settings_signature,
		chunk_coord
	)

func _resolve_full_radius_chunks() -> int:
	if STAGE_RADII_CHUNKS.is_empty():
		return 0
	return int(STAGE_RADII_CHUNKS[STAGE_RADII_CHUNKS.size() - 1])

func _resolve_stage_span_chunks() -> int:
	if _awaiting_spawn_result:
		return 0
	if _current_stage_index < 0 or _current_stage_index >= _stage_plans.size():
		return 0
	return int((_stage_plans[_current_stage_index] as Dictionary).get("radius", 0)) * 2 + 1

func _resolve_total_target_count() -> int:
	if _awaiting_spawn_result:
		return 0
	if _stage_plans.is_empty():
		return 0
	return _coerce_chunk_coords((_stage_plans[_stage_plans.size() - 1] as Dictionary).get("window_coords", [])).size()

func _resolve_ready_chunk_count() -> int:
	return _published_patches.size() + _ready_patches.size()

func _update_canvas_progress() -> void:
	if _canvas == null:
		return
	_canvas.set_progress(
		_resolve_stage_span_chunks(),
		_resolve_ready_chunk_count(),
		_published_patches.size(),
		_resolve_total_target_count()
	)

func _coerce_chunk_coords(value: Variant) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	if value is not Array:
		return coords
	for coord_variant: Variant in value:
		coords.append(coord_variant as Vector2i)
	return coords

func _clone_settings(settings: MountainGenSettings) -> MountainGenSettings:
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

func _build_settings_packed(
	settings: MountainGenSettings,
	world_bounds: WorldBoundsSettings,
	foundation_settings: FoundationGenSettings
) -> PackedFloat32Array:
	var packed: PackedFloat32Array = settings.flatten_to_packed()
	return foundation_settings.write_to_settings_packed(packed, world_bounds)

func _compute_worldgen_signature(
	settings: MountainGenSettings,
	world_bounds: WorldBoundsSettings,
	foundation_settings: FoundationGenSettings
) -> String:
	var hashing_context: HashingContext = HashingContext.new()
	var start_error: Error = hashing_context.start(HashingContext.HASH_SHA1)
	if start_error != OK:
		return ""
	hashing_context.update(JSON.stringify({
		"mountains": settings.to_save_dict(),
		"world_bounds": world_bounds.to_save_dict(),
		"foundation": foundation_settings.to_save_dict(),
	}).to_utf8_buffer())
	return hashing_context.finish().hex_encode()

func _resolve_patch_render_mode() -> StringName:
	return WorldPreviewRenderMode.TERRAIN \
		if _active_render_mode == WorldPreviewRenderMode.SPAWN_SAFE_PATCH \
		else _active_render_mode
