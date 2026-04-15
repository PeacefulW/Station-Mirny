class_name Chunk
extends Node2D

const ChunkDebugRendererScript = preload("res://core/systems/world/chunk_debug_renderer.gd")
const ChunkFogPresenterScript = preload("res://core/systems/world/chunk_fog_presenter.gd")
const ChunkFloraPresenterScript = preload("res://core/systems/world/chunk_flora_presenter.gd")
const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")
const ChunkFinalPacketScript = preload("res://core/systems/world/chunk_final_packet.gd")
const ChunkVisualKernelScript = preload("res://core/systems/world/chunk_visual_kernel.gd")

## Один чанк мира.
## Хранит terrain-данные, exterior shell cover и локальные модификации.

enum ChunkVisualState {
	UNINITIALIZED,
	NATIVE_READY,
	PROXY_READY,
	TERRAIN_READY,
	FULL_PENDING,
	FULL_READY,
}

const REDRAW_TIME_BUDGET_USEC: int = 2500
const _INTERIOR_MACRO_ENABLED: bool = true
const _INTERIOR_MACRO_SAMPLES_PER_TILE: int = 1
const _INTERIOR_MACRO_DUST_SEED: int = 16001
const _INTERIOR_MACRO_MOSS_SEED: int = 16057
const _INTERIOR_MACRO_CRACK_SEED: int = 16111
const _INTERIOR_MACRO_PEBBLE_SEED: int = 16183
const NATIVE_VISUAL_KERNELS_CLASS: StringName = &"ChunkVisualKernels"

var chunk_coord: Vector2i = Vector2i.ZERO
var is_loaded: bool = false
var is_dirty: bool = false

var _terrain_layer: TileMapLayer = null
var _ground_face_layer: TileMapLayer = null
var _rock_layer: TileMapLayer = null
var _interior_macro_layer: Sprite2D = null
var _cover_layer: TileMapLayer = null
var _cliff_layer: TileMapLayer = null
var _fog_presenter = null
var _flora_presenter = null
var _debug_renderer = null
var _tile_size: int = 64
var _chunk_size: int = 64
var _terrain_tileset: TileSet = null
var _overlay_tileset: TileSet = null
var _chunk_manager: ChunkManager = null
var _wg_has_tile_to_local_in_chunk: bool = false
var _wg_has_chunk_local_to_tile: bool = false
var _modified_tiles: Dictionary = {}
var _biome: BiomeData = null
var _terrain_bytes: PackedByteArray = PackedByteArray()
var _cover_edge_set: PackedByteArray = PackedByteArray()
var _cover_edge_set_dirty_tiles: PackedByteArray = PackedByteArray()
var _cover_edge_set_dirty_tile_queue: Array[int] = []
var _cover_edge_set_valid: bool = false
var _cover_edge_set_requires_full_rebuild: bool = true
var _height_bytes: PackedFloat32Array = PackedFloat32Array()
var _variation_bytes: PackedByteArray = PackedByteArray()
var _biome_bytes: PackedByteArray = PackedByteArray()
var _secondary_biome_bytes: PackedByteArray = PackedByteArray()
var _ecotone_values: PackedFloat32Array = PackedFloat32Array()
var _rock_visual_class_bytes: PackedByteArray = PackedByteArray()
var _ground_face_atlas_bytes: PackedInt32Array = PackedInt32Array()
var _cover_mask_bytes: PackedInt32Array = PackedInt32Array()
var _cliff_overlay_bytes: PackedByteArray = PackedByteArray()
var _variant_id_bytes: PackedByteArray = PackedByteArray()
var _alt_id_bytes: PackedInt32Array = PackedInt32Array()
var _prebaked_visual_payload_valid: bool = false
var _has_mountain: bool = false
var _redraw_phase: int = ChunkVisualKernelScript.REDRAW_PHASE_DONE
var _redraw_tile_index: int = 0
var _pending_border_dirty: PackedByteArray = PackedByteArray()
var _pending_border_dirty_queue: Array[int] = []
var _pending_border_dirty_queue_head: int = 0
var _pending_border_dirty_count: int = 0
var _border_fix_pending_reason_versions: Dictionary = {}
var _border_fix_applied_reason_versions: Dictionary = {}
var _revealed_local_cover_tiles: PackedByteArray = PackedByteArray()
var _revealed_local_cover_tile_count: int = 0
var _cover_tile_version: int = 0
var _is_underground: bool = false
var _terminal_surface_packet_installed: bool = false
var _terminal_surface_packet_version: int = 0
var _terminal_surface_generator_version: int = 0
var _terminal_surface_generation_source: StringName = &""
var _use_operation_global_terrain_cache: bool = false
var _operation_global_terrain_cache: Dictionary = {}
var _mining_write_authorized: bool = false
var _visual_state: int = ChunkVisualState.UNINITIALIZED
var _visual_invalidation_version: int = 0
var _interior_macro_dirty: bool = false

static var _native_visual_kernels: RefCounted = null
static var _native_visual_kernels_checked: bool = false
static var _native_visual_kernels_available: bool = false

func setup(
	p_coord: Vector2i,
	p_tile_size: int,
	p_chunk_size: int,
	p_biome: BiomeData,
	p_terrain_tileset: TileSet,
	p_overlay_tileset: TileSet,
	p_chunk_manager: ChunkManager
) -> void:
	chunk_coord = WorldGenerator.canonicalize_chunk_coord(p_coord) if WorldGenerator else p_coord
	_tile_size = p_tile_size
	_chunk_size = p_chunk_size
	_biome = p_biome
	_terrain_tileset = p_terrain_tileset
	_overlay_tileset = p_overlay_tileset
	_chunk_manager = p_chunk_manager
	_cache_world_generator_capabilities()
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	sync_display_position(chunk_coord)
	_terrain_layer = _create_layer("Terrain", _terrain_tileset, -12)
	_ground_face_layer = _create_layer("GroundFaces", _terrain_tileset, -11)
	_rock_layer = _create_layer("Rock", _terrain_tileset, -10)
	if _INTERIOR_MACRO_ENABLED:
		_interior_macro_layer = _create_interior_macro_layer("InteriorMacro", -9)
	_cliff_layer = _create_layer("Cliffs", _overlay_tileset, -9)
	_cover_layer = _create_layer("MountainCover", _terrain_tileset, 6)
	_fog_presenter = ChunkFogPresenterScript.new()
	_fog_presenter.setup(self, _chunk_size)
	_flora_presenter = ChunkFloraPresenterScript.new()
	_flora_presenter.name = "Flora"
	_flora_presenter.z_index = -5
	_flora_presenter.setup(_tile_size)
	add_child(_flora_presenter)
	if OS.is_debug_build():
		_debug_renderer = ChunkDebugRendererScript.new()
		_debug_renderer.name = "DebugRenderer"
		_debug_renderer.z_index = 50
		add_child(_debug_renderer)
	_ensure_chunk_local_hot_storage()

func _cache_world_generator_capabilities() -> void:
	_wg_has_tile_to_local_in_chunk = WorldGenerator != null and WorldGenerator.has_method("tile_to_local_in_chunk")
	_wg_has_chunk_local_to_tile = WorldGenerator != null and WorldGenerator.has_method("chunk_local_to_tile")

func sync_display_position(reference_chunk: Vector2i) -> void:
	var display_chunk: Vector2i = chunk_coord
	if WorldGenerator and WorldGenerator._is_initialized:
		display_chunk = WorldGenerator.get_display_chunk_coord(chunk_coord, reference_chunk)
	var chunk_pixels: int = _chunk_size * _tile_size
	position = Vector2(display_chunk.x * chunk_pixels, display_chunk.y * chunk_pixels)

func populate_native(native_data: Dictionary, saved_modifications: Dictionary, instant: bool = false) -> void:
	_modified_tiles = saved_modifications.duplicate()
	_ensure_chunk_local_hot_storage()
	_reset_border_fix_dedupe_state()
	_capture_publication_packet_contract(native_data)
	_terrain_bytes = native_data.get("terrain", PackedByteArray())
	_height_bytes = native_data.get("height", PackedFloat32Array())
	_variation_bytes = native_data.get("variation", PackedByteArray())
	_biome_bytes = native_data.get("biome", PackedByteArray())
	_secondary_biome_bytes = native_data.get("secondary_biome", PackedByteArray()) as PackedByteArray
	_ecotone_values = native_data.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array
	_load_prebaked_visual_payload(native_data)
	if _fog_presenter != null:
		_fog_presenter.reset_runtime_state()
	if _flora_presenter != null:
		_flora_presenter.reset_runtime_state()
	if _debug_renderer != null:
		_debug_renderer.clear_markers()
	_interior_macro_dirty = _INTERIOR_MACRO_ENABLED
	if _variation_bytes.size() != _terrain_bytes.size():
		push_error("Chunk.populate_native(): variation array size mismatch for %s" % [chunk_coord])
		assert(false, "variation array size must match terrain array size")
		_variation_bytes.resize(_terrain_bytes.size())
		_variation_bytes.fill(ChunkTilesetFactory.SURFACE_VARIATION_NONE)
	if _biome_bytes.size() != _terrain_bytes.size():
		push_error("Chunk.populate_native(): biome array size mismatch for %s" % [chunk_coord])
		assert(false, "biome array size must match terrain array size")
		_biome_bytes.resize(_terrain_bytes.size())
		_biome_bytes.fill(_default_biome_palette_index())
	if _secondary_biome_bytes.size() != _terrain_bytes.size():
		if not _secondary_biome_bytes.is_empty():
			push_warning("Chunk.populate_native(): secondary biome array size mismatch for %s — falling back to primary biome palette" % [chunk_coord])
		_secondary_biome_bytes = _biome_bytes.duplicate()
	if _ecotone_values.size() != _terrain_bytes.size():
		if not _ecotone_values.is_empty():
			push_warning("Chunk.populate_native(): ecotone array size mismatch for %s — disabling ecotone blending for this payload" % [chunk_coord])
		_ecotone_values.resize(_terrain_bytes.size())
		_ecotone_values.fill(0.0)
	_apply_saved_modifications()
	if not saved_modifications.is_empty():
		_invalidate_prebaked_visual_payload()
	_cache_has_mountain()
	_visual_invalidation_version = 0
	_cover_tile_version = 0
	_bump_visual_invalidation_version()
	_reset_cover_visual_state()
	if instant:
		_redraw_all()
	else:
		_begin_progressive_redraw()
	is_loaded = true

func complete_redraw_now(include_flora: bool = false) -> void:
	_redraw_all(include_flora)

## Draws terrain layer immediately for all tiles, then leaves cover/cliff/flora
## for progressive redraw. Used by boot apply for ring 1 chunks so the player
## never sees green placeholder zones near spawn.
## Forces GPU resource initialization for all tile layers by performing a
## dummy set_cell + erase_cell. This triggers shader compilation and atlas
## preparation, paying the one-time cold-start cost (~950ms) outside the
## timed terrain redraw path. Called by ChunkManager before boot terrain redraw.
## (boot_fast_first_playable_spec Iteration 2, change 2A)
func warmup_tile_layers() -> void:
	var dummy_coord := Vector2i(-1, -1)
	var dummy_source: int = 0
	var dummy_atlas := Vector2i.ZERO
	for layer: TileMapLayer in [_terrain_layer, _ground_face_layer, _rock_layer, _cover_layer, _cliff_layer]:
		if layer == null:
			continue
		layer.set_cell(dummy_coord, dummy_source, dummy_atlas)
		layer.erase_cell(dummy_coord)

func complete_terrain_phase_now() -> void:
	if _redraw_phase != ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN:
		return
	var batch: Dictionary = build_visual_phase_batch(_chunk_size * _chunk_size)
	if batch.is_empty():
		return
	var computed_batch: Dictionary = Chunk.compute_visual_batch(batch)
	apply_visual_phase_batch(computed_batch)

func global_to_local(global_tile: Vector2i) -> Vector2i:
	if _wg_has_tile_to_local_in_chunk and WorldGenerator:
		return WorldGenerator.tile_to_local_in_chunk(global_tile, chunk_coord)
	return Vector2i(
		global_tile.x - chunk_coord.x * _chunk_size,
		global_tile.y - chunk_coord.y * _chunk_size
	)

func has_any_mountain() -> bool:
	return _has_mountain

func get_chunk_size() -> int:
	return _chunk_size

func get_terrain_bytes() -> PackedByteArray:
	return _terrain_bytes

func get_modifications() -> Dictionary:
	return _modified_tiles.duplicate()

func get_visual_invalidation_version() -> int:
	return _visual_invalidation_version

func get_cover_tile_version() -> int:
	return _cover_tile_version

func _bump_visual_invalidation_version() -> int:
	_visual_invalidation_version += 1
	if _visual_invalidation_version <= 0:
		_visual_invalidation_version = 1
	return _visual_invalidation_version

func _bump_cover_tile_version() -> int:
	_cover_tile_version += 1
	if _cover_tile_version <= 0:
		_cover_tile_version = 1
	return _cover_tile_version

func _resize_zero_byte_array(array: PackedByteArray, size: int) -> PackedByteArray:
	if array.size() != size:
		array.resize(size)
	if size > 0:
		array.fill(0)
	return array

func _ensure_chunk_local_hot_storage() -> void:
	var tile_count: int = maxi(0, _chunk_size * _chunk_size)
	_cover_edge_set = _resize_zero_byte_array(_cover_edge_set, tile_count)
	_cover_edge_set_dirty_tiles = _resize_zero_byte_array(_cover_edge_set_dirty_tiles, tile_count)
	_cover_edge_set_dirty_tile_queue.clear()
	_cover_edge_set_valid = false
	_cover_edge_set_requires_full_rebuild = true
	_pending_border_dirty = _resize_zero_byte_array(_pending_border_dirty, tile_count)
	_pending_border_dirty_queue.clear()
	_pending_border_dirty_queue_head = 0
	_pending_border_dirty_count = 0
	_revealed_local_cover_tiles = _resize_zero_byte_array(_revealed_local_cover_tiles, tile_count)
	_revealed_local_cover_tile_count = 0

func _local_tile_index(local_tile: Vector2i) -> int:
	if not _is_inside(local_tile):
		return -1
	return local_tile.y * _chunk_size + local_tile.x

func _has_revealed_local_cover_tile(local_tile: Vector2i) -> bool:
	var tile_index: int = _local_tile_index(local_tile)
	return tile_index >= 0 \
		and tile_index < _revealed_local_cover_tiles.size() \
		and _revealed_local_cover_tiles[tile_index] != 0

func _set_revealed_local_cover_tile(local_tile: Vector2i, revealed: bool) -> bool:
	var tile_index: int = _local_tile_index(local_tile)
	if tile_index < 0 or tile_index >= _revealed_local_cover_tiles.size():
		return false
	var next_value: int = 1 if revealed else 0
	if _revealed_local_cover_tiles[tile_index] == next_value:
		return false
	_revealed_local_cover_tiles[tile_index] = next_value
	if revealed:
		_revealed_local_cover_tile_count += 1
	else:
		_revealed_local_cover_tile_count = maxi(0, _revealed_local_cover_tile_count - 1)
	return true

func _revealed_local_cover_tiles_equal(cover_tiles: Dictionary) -> bool:
	if _revealed_local_cover_tile_count != cover_tiles.size():
		return false
	for local_tile: Vector2i in cover_tiles:
		if not _has_revealed_local_cover_tile(local_tile):
			return false
	return true

func _replace_revealed_local_cover_tiles(cover_tiles: Dictionary) -> bool:
	var cover_state_changed: bool = not _revealed_local_cover_tiles_equal(cover_tiles)
	if not cover_state_changed:
		return false
	if not _revealed_local_cover_tiles.is_empty():
		_revealed_local_cover_tiles.fill(0)
	_revealed_local_cover_tile_count = 0
	for local_tile: Vector2i in cover_tiles:
		_set_revealed_local_cover_tile(local_tile, true)
	return true

func _revealed_local_cover_tiles_to_dictionary() -> Dictionary:
	var cover_tiles: Dictionary = {}
	if _revealed_local_cover_tile_count <= 0:
		return cover_tiles
	for tile_index: int in range(_revealed_local_cover_tiles.size()):
		if _revealed_local_cover_tiles[tile_index] == 0:
			continue
		cover_tiles[_tile_from_index(tile_index)] = true
	return cover_tiles

func _queue_cover_edge_set_dirty_tile(local_tile: Vector2i) -> void:
	var tile_index: int = _local_tile_index(local_tile)
	if tile_index < 0 or tile_index >= _cover_edge_set_dirty_tiles.size():
		return
	if _cover_edge_set_dirty_tiles[tile_index] != 0:
		return
	_cover_edge_set_dirty_tiles[tile_index] = 1
	_cover_edge_set_dirty_tile_queue.append(tile_index)

func _add_pending_border_dirty_tile(local_tile: Vector2i) -> bool:
	var tile_index: int = _local_tile_index(local_tile)
	if tile_index < 0 or tile_index >= _pending_border_dirty.size():
		return false
	if _pending_border_dirty[tile_index] != 0:
		return false
	_pending_border_dirty[tile_index] = 1
	_pending_border_dirty_queue.append(tile_index)
	_pending_border_dirty_count += 1
	return true

func _trim_pending_border_dirty_queue() -> void:
	while _pending_border_dirty_queue_head < _pending_border_dirty_queue.size():
		var tile_index: int = int(_pending_border_dirty_queue[_pending_border_dirty_queue_head])
		if tile_index >= 0 \
			and tile_index < _pending_border_dirty.size() \
			and _pending_border_dirty[tile_index] != 0:
			break
		_pending_border_dirty_queue_head += 1
	if _pending_border_dirty_queue_head <= 0:
		return
	if _pending_border_dirty_queue_head >= _pending_border_dirty_queue.size():
		_pending_border_dirty_queue.clear()
		_pending_border_dirty_queue_head = 0
		return
	if _pending_border_dirty_queue_head < 64 \
		and _pending_border_dirty_queue_head * 2 < _pending_border_dirty_queue.size():
		return
	var remaining_queue: Array[int] = []
	for queue_index: int in range(_pending_border_dirty_queue_head, _pending_border_dirty_queue.size()):
		remaining_queue.append(int(_pending_border_dirty_queue[queue_index]))
	_pending_border_dirty_queue = remaining_queue
	_pending_border_dirty_queue_head = 0

func has_pending_border_dirty() -> bool:
	return _pending_border_dirty_count > 0

func get_pending_border_dirty_count() -> int:
	return _pending_border_dirty_count

func collect_pending_border_dirty_tiles(limit: int = -1) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if _pending_border_dirty_count <= 0:
		return tiles
	var target_count: int = _pending_border_dirty_count if limit <= 0 else mini(_pending_border_dirty_count, limit)
	var queue_index: int = _pending_border_dirty_queue_head
	while queue_index < _pending_border_dirty_queue.size() and tiles.size() < target_count:
		var tile_index: int = int(_pending_border_dirty_queue[queue_index])
		if tile_index >= 0 and tile_index < _pending_border_dirty.size() and _pending_border_dirty[tile_index] != 0:
			tiles.append(_tile_from_index(tile_index))
		queue_index += 1
	return tiles

func discard_pending_border_dirty_tiles(tiles: Array) -> void:
	if tiles.is_empty() or _pending_border_dirty_count <= 0:
		return
	for tile_variant: Variant in tiles:
		var local_tile: Vector2i = tile_variant as Vector2i
		var tile_index: int = _local_tile_index(local_tile)
		if tile_index < 0 or tile_index >= _pending_border_dirty.size():
			continue
		if _pending_border_dirty[tile_index] == 0:
			continue
		_pending_border_dirty[tile_index] = 0
		_pending_border_dirty_count = maxi(0, _pending_border_dirty_count - 1)
	_trim_pending_border_dirty_queue()

func _reset_border_fix_dedupe_state() -> void:
	if not _pending_border_dirty.is_empty():
		_pending_border_dirty.fill(0)
	_pending_border_dirty_queue.clear()
	_pending_border_dirty_queue_head = 0
	_pending_border_dirty_count = 0
	_border_fix_pending_reason_versions.clear()
	_border_fix_applied_reason_versions.clear()

func _mark_border_fix_reasons_applied() -> void:
	for reason_variant: Variant in _border_fix_pending_reason_versions.keys():
		var reason_key: String = str(reason_variant)
		_border_fix_applied_reason_versions[reason_key] = int(_border_fix_pending_reason_versions[reason_key])
	_border_fix_pending_reason_versions.clear()

func _load_prebaked_visual_payload(native_data: Dictionary) -> void:
	var tile_count: int = _terrain_bytes.size()
	_rock_visual_class_bytes = native_data.get("rock_visual_class", PackedByteArray()) as PackedByteArray
	_ground_face_atlas_bytes = native_data.get("ground_face_atlas", PackedInt32Array()) as PackedInt32Array
	_cover_mask_bytes = native_data.get("cover_mask", PackedInt32Array()) as PackedInt32Array
	_cliff_overlay_bytes = native_data.get("cliff_overlay", PackedByteArray()) as PackedByteArray
	_variant_id_bytes = native_data.get("variant_id", PackedByteArray()) as PackedByteArray
	_alt_id_bytes = native_data.get("alt_id", PackedInt32Array()) as PackedInt32Array
	_prebaked_visual_payload_valid = tile_count > 0 \
		and _rock_visual_class_bytes.size() == tile_count \
		and _ground_face_atlas_bytes.size() == tile_count \
		and _cover_mask_bytes.size() == tile_count \
		and _cliff_overlay_bytes.size() == tile_count \
		and _variant_id_bytes.size() == tile_count \
		and _alt_id_bytes.size() == tile_count

func _capture_publication_packet_contract(native_data: Dictionary) -> void:
	_terminal_surface_packet_installed = _is_underground
	_terminal_surface_packet_version = 0
	_terminal_surface_generator_version = 0
	_terminal_surface_generation_source = &""
	if _is_underground:
		return
	_terminal_surface_packet_installed = ChunkFinalPacketScript.validate_terminal_surface_packet(
		native_data,
		"Chunk.populate_native(%s)" % [chunk_coord]
	)
	if not _terminal_surface_packet_installed:
		assert(false, "surface chunks must be populated from terminal frontier_surface_final_packet")
		return
	_terminal_surface_packet_version = int(native_data.get(ChunkFinalPacketScript.PACKET_VERSION_KEY, 0))
	_terminal_surface_generator_version = int(native_data.get(ChunkFinalPacketScript.GENERATOR_VERSION_KEY, 0))
	_terminal_surface_generation_source = native_data.get(ChunkFinalPacketScript.GENERATION_SOURCE_KEY, &"") as StringName

func _invalidate_prebaked_visual_payload() -> void:
	_prebaked_visual_payload_valid = false

func _has_prebaked_visual_phase_data() -> bool:
	if not _prebaked_visual_payload_valid or _is_underground or not _modified_tiles.is_empty():
		return false
	return _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_COVER \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_CLIFF

func get_terrain_type_at(local: Vector2i) -> int:
	if not _is_inside(local):
		push_error("Chunk.get_terrain_type_at(): local tile %s is outside chunk %s" % [local, chunk_coord])
		assert(false, "local terrain read must stay inside chunk bounds")
		return TileGenData.TerrainType.ROCK
	var idx: int = local.y * _chunk_size + local.x
	if idx < 0 or idx >= _terrain_bytes.size():
		push_error("Chunk.get_terrain_type_at(): terrain array index %d is invalid for chunk %s" % [idx, chunk_coord])
		assert(false, "terrain byte array must match chunk bounds")
		return TileGenData.TerrainType.ROCK
	return _terrain_bytes[idx]

func mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void:
	_modified_tiles[tile_pos] = state
	is_dirty = true

func set_revealed_local_cover_tiles(
	cover_tiles: Dictionary,
	changed_tiles: Dictionary = {},
	commit_full_state: bool = true
) -> void:
	var cover_state_changed: bool = false
	if changed_tiles.is_empty():
		cover_state_changed = _apply_local_zone_cover_state(cover_tiles)
	else:
		cover_state_changed = _apply_local_zone_cover_state_delta(
			cover_tiles,
			changed_tiles,
			commit_full_state
		)
	if cover_state_changed:
		_bump_cover_tile_version()

func apply_revealed_local_cover_tiles_batch(
	target_cover_tiles: Dictionary,
	changed_tiles: Dictionary
) -> void:
	if changed_tiles.is_empty():
		return
	var cover_state_changed: bool = false
	if not _cover_layer:
		for local_tile: Vector2i in changed_tiles:
			var was_revealed: bool = _has_revealed_local_cover_tile(local_tile)
			if target_cover_tiles.has(local_tile):
				cover_state_changed = _set_revealed_local_cover_tile(local_tile, true) or cover_state_changed
			else:
				cover_state_changed = _set_revealed_local_cover_tile(local_tile, false) or cover_state_changed
			if was_revealed != target_cover_tiles.has(local_tile):
				cover_state_changed = true
		if cover_state_changed:
			_bump_cover_tile_version()
		return
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	for local_tile: Vector2i in changed_tiles:
		var was_revealed: bool = _has_revealed_local_cover_tile(local_tile)
		var should_be_revealed: bool = target_cover_tiles.has(local_tile)
		if was_revealed == should_be_revealed:
			continue
		cover_state_changed = true
		if should_be_revealed:
			_cover_layer.erase_cell(local_tile)
			_set_revealed_local_cover_tile(local_tile, true)
		else:
			_redraw_cover_tile(local_tile)
			_set_revealed_local_cover_tile(local_tile, false)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache
	if cover_state_changed:
		_bump_cover_tile_version()

func defer_revealed_local_cover_tiles_restore(changed_tiles: Dictionary) -> bool:
	if changed_tiles.is_empty():
		return false
	var cover_state_changed: bool = false
	for local_tile: Vector2i in changed_tiles:
		if _set_revealed_local_cover_tile(local_tile, false):
			cover_state_changed = true
	if cover_state_changed:
		_bump_cover_tile_version()
	if not is_first_pass_ready():
		return false
	return enqueue_dirty_border_redraw(changed_tiles, "roof_restore", get_visual_invalidation_version())

func prime_revealed_local_cover_tiles(cover_tiles: Dictionary) -> void:
	if _replace_revealed_local_cover_tiles(cover_tiles):
		_bump_cover_tile_version()

func get_revealed_local_cover_tiles() -> Dictionary:
	return _revealed_local_cover_tiles_to_dictionary()

func set_mining_write_authorized(value: bool) -> void:
	_mining_write_authorized = value

# --- Underground Fog of War ---

## Mark this chunk as underground. Must be called BEFORE redraw.
func set_underground(value: bool) -> void:
	_is_underground = value

## Initialize fog layer for underground chunks. Fills all tiles with UNSEEN.
func init_fog_layer(fog_tileset: TileSet) -> void:
	if _fog_presenter == null:
		return
	_fog_presenter.ensure_layer(fog_tileset)

## Erase fog for tiles that are currently visible (player nearby).
## Also redraws terrain to update wall variants with current neighbor data.
func apply_fog_visible(visible_locals: Dictionary) -> void:
	if _fog_presenter == null:
		return
	_fog_presenter.apply_visible(
		visible_locals,
		Callable(self, "_is_inside"),
		Callable(self, "_redraw_terrain_tile")
	)

## Set DISCOVERED fog tile for tiles that were visible but player moved away.
func apply_fog_discovered(discovered_locals: Dictionary) -> void:
	if _fog_presenter == null:
		return
	_fog_presenter.apply_discovered(discovered_locals, Callable(self, "_is_inside"))

## Returns true if this tile should have fog removed when in reveal radius.
## - MINED_FLOOR / MOUNTAIN_ENTRANCE: always (open space)
## - GROUND: always (surface terrain, shouldn't normally appear underground)
## - ROCK: only if adjacent (8-dir) to open space — visible cave wall face
## - Deep rock with no open neighbors: stays hidden under fog (dark mass)
func is_fog_revealable(local_tile: Vector2i) -> bool:
	if not _is_inside(local_tile):
		return false
	var terrain: int = get_terrain_type_at(local_tile)
	if terrain == TileGenData.TerrainType.MINED_FLOOR \
		or terrain == TileGenData.TerrainType.MOUNTAIN_ENTRANCE \
		or terrain == TileGenData.TerrainType.GROUND:
		return true
	# Rock adjacent to open space (any of 8 directions) = visible wall
	if terrain == TileGenData.TerrainType.ROCK:
		return _is_cave_edge_rock(local_tile)
	return false

func is_revealable_cover_edge(local_tile: Vector2i) -> bool:
	if not _is_inside(local_tile):
		return false
	if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
		return false
	return _is_cave_edge_rock(local_tile)

## Возвращает O(1) packed lookup для тайлов чанка, которые являются
## revealable cover edges. Первый rebuild может стоить O(chunk_size²), но после
## майнинга обновление ограничено dirty tiles вокруг изменённого места.
func has_cover_edge_cached(local_tile: Vector2i) -> bool:
	if not _cover_edge_set_valid:
		_rebuild_cover_edge_set()
	var tile_index: int = _local_tile_index(local_tile)
	return tile_index >= 0 and tile_index < _cover_edge_set.size() and _cover_edge_set[tile_index] != 0

func _rebuild_cover_edge_set() -> void:
	if _cover_edge_set_requires_full_rebuild:
		if not _cover_edge_set.is_empty():
			_cover_edge_set.fill(0)
		for y: int in range(_chunk_size):
			for x: int in range(_chunk_size):
				var full_local := Vector2i(x, y)
				if is_revealable_cover_edge(full_local):
					_cover_edge_set[_local_tile_index(full_local)] = 1
	else:
		for tile_index: int in _cover_edge_set_dirty_tile_queue:
			if tile_index < 0 or tile_index >= _cover_edge_set_dirty_tiles.size():
				continue
			if _cover_edge_set_dirty_tiles[tile_index] == 0:
				continue
			_cover_edge_set_dirty_tiles[tile_index] = 0
			var local: Vector2i = _tile_from_index(tile_index)
			_cover_edge_set[tile_index] = 0
			if is_revealable_cover_edge(local):
				_cover_edge_set[tile_index] = 1
	_cover_edge_set_dirty_tile_queue.clear()
	_cover_edge_set_requires_full_rebuild = false
	_cover_edge_set_valid = true

func _mark_cover_edge_set_dirty_tiles(dirty_tiles: Dictionary) -> void:
	if dirty_tiles.is_empty():
		return
	_cover_edge_set_valid = false
	if _cover_edge_set_requires_full_rebuild:
		return
	for local_tile: Vector2i in dirty_tiles:
		_queue_cover_edge_set_dirty_tile(local_tile)

func _invalidate_cover_edge_set_around(local_tile: Vector2i) -> void:
	var dirty_tiles: Dictionary = {}
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var dirty_tile: Vector2i = local_tile + Vector2i(dx, dy)
			if _is_inside(dirty_tile):
				dirty_tiles[dirty_tile] = true
	_mark_cover_edge_set_dirty_tiles(dirty_tiles)

func try_mine_at(local: Vector2i) -> Dictionary:
	var started_usec: int = WorldPerfProbe.begin()
	if not _mining_write_authorized:
		push_error("Chunk.try_mine_at(): unauthorized direct call for chunk %s" % [chunk_coord])
		assert(false, "ChunkManager.try_harvest_at_world() is the safe mining orchestration point")
		return {}
	if not _is_inside(local):
		return {}
	var old_type: int = get_terrain_type_at(local)
	if old_type != TileGenData.TerrainType.ROCK:
		return {}
	var new_type: int = _resolve_open_tile_type_for_neighbor_refresh(local)
	_set_terrain_type(local, new_type)
	# ChunkManager redraws the local patch after neighbor normalization so mining
	# does not pay for two overlapping same-chunk redraw passes.
	WorldPerfProbe.end("Chunk.try_mine_at %s" % [chunk_coord], started_usec)
	return {"old_type": old_type, "new_type": new_type}

func redraw_mining_patch(local_tile: Vector2i) -> bool:
	if not is_first_pass_ready():
		return false
	var dirty_tiles: Dictionary = _collect_mining_dirty_tiles(local_tile)
	if dirty_tiles.is_empty():
		return false
	return enqueue_dirty_border_redraw(dirty_tiles, "local_patch", get_visual_invalidation_version())

func refresh_open_neighbors_with_operation_cache(local_tile: Vector2i) -> void:
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	for dir: Vector2i in ChunkVisualKernelScript._CARDINAL_DIRS:
		_refresh_open_tile(local_tile + dir)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache

func refresh_open_tile_with_operation_cache(local_tile: Vector2i) -> void:
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	_refresh_open_tile(local_tile)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache

func cleanup() -> void:
	is_loaded = false
	_terrain_bytes = PackedByteArray()
	_height_bytes = PackedFloat32Array()
	_variation_bytes = PackedByteArray()
	_biome_bytes = PackedByteArray()
	_secondary_biome_bytes = PackedByteArray()
	_ecotone_values = PackedFloat32Array()
	_ensure_chunk_local_hot_storage()
	_interior_macro_dirty = false
	_clear_interior_macro_layer()
	if _fog_presenter != null:
		_fog_presenter.reset_runtime_state()
	_clear_flora_renderer()
	_clear_debug_markers()
	_visual_state = ChunkVisualState.UNINITIALIZED
	_visual_invalidation_version = 0
	_cover_tile_version = 0
	_reset_border_fix_dedupe_state()

func _create_layer(layer_name: String, tileset: TileSet, z_index_value: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	layer.z_index = z_index_value
	add_child(layer)
	return layer

func _create_interior_macro_layer(layer_name: String, z_index_value: int) -> Sprite2D:
	var layer := Sprite2D.new()
	layer.name = layer_name
	layer.centered = false
	layer.z_index = z_index_value
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.visible = false
	add_child(layer)
	return layer

func _apply_saved_modifications() -> void:
	for tile_pos: Vector2i in _modified_tiles:
		var state: Dictionary = _modified_tiles[tile_pos]
		if state.has("terrain"):
			_set_terrain_type(tile_pos, int(state["terrain"]), false)
	_normalize_saved_open_tiles_after_load()

func _normalize_saved_open_tiles_after_load() -> void:
	if _modified_tiles.is_empty():
		return
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	var tiles_to_refresh: Dictionary = {}
	for tile_pos: Vector2i in _modified_tiles:
		if not _is_inside(tile_pos):
			continue
		tiles_to_refresh[tile_pos] = true
		for dir: Vector2i in ChunkVisualKernelScript._CARDINAL_DIRS:
			var neighbor_tile: Vector2i = tile_pos + dir
			if _is_inside(neighbor_tile):
				tiles_to_refresh[neighbor_tile] = true
	for tile_pos: Vector2i in tiles_to_refresh:
		_refresh_open_tile(tile_pos)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache

func _run_immediate_visual_phase_batches() -> void:
	var total_tiles: int = _chunk_size * _chunk_size
	_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN
	_redraw_tile_index = 0
	while _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_COVER \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_CLIFF:
		var batch: Dictionary = build_visual_phase_batch(total_tiles)
		if batch.is_empty():
			_advance_redraw_phase()
			continue
		var computed_batch: Dictionary = Chunk.compute_visual_batch(batch)
		if not apply_visual_phase_batch(computed_batch):
			break

func _redraw_all(include_flora: bool = false) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	_terrain_layer.clear()
	_ground_face_layer.clear()
	_rock_layer.clear()
	_clear_interior_macro_layer()
	_cover_layer.clear()
	_cliff_layer.clear()
	_clear_flora_renderer()
	_reset_cover_visual_state()
	_clear_debug_markers()
	_run_immediate_visual_phase_batches()
	_refresh_interior_macro_layer()
	_rebuild_debug_markers()
	if include_flora:
		_apply_flora_render_packet(_build_flora_render_packet(), &"batched_renderer")
		_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_DONE
	else:
		## Flora is deferred to progressive redraw. Set phase to FLORA so
		## progressive path can draw flora without re-doing terrain/cover/cliff.
		_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_FLORA
	_redraw_tile_index = 0
	_sync_visual_state_after_redraw_mutation()
	WorldPerfProbe.end("Chunk._redraw_all %s" % [chunk_coord], started_usec)

func _begin_progressive_redraw() -> void:
	_terrain_layer.clear()
	_ground_face_layer.clear()
	_rock_layer.clear()
	_clear_interior_macro_layer()
	_cover_layer.clear()
	_cliff_layer.clear()
	_clear_flora_renderer()
	_reset_cover_visual_state()
	_clear_debug_markers()
	_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN
	_redraw_tile_index = 0
	_mark_visual_native_ready()

func is_redraw_complete() -> bool:
	return _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_DONE

func is_first_pass_ready() -> bool:
	return _visual_state == ChunkVisualState.TERRAIN_READY \
		or _visual_state == ChunkVisualState.FULL_PENDING \
		or _visual_state == ChunkVisualState.FULL_READY

func is_full_redraw_ready() -> bool:
	return _visual_state == ChunkVisualState.FULL_READY and has_terminal_publication_packet()

func _is_visibility_publication_ready() -> bool:
	return is_full_redraw_ready() and has_terminal_publication_packet()

func has_terminal_publication_packet() -> bool:
	return _is_underground or _terminal_surface_packet_installed

func get_publication_contract_snapshot() -> Dictionary:
	return {
		"is_underground": _is_underground,
		"terminal_surface_packet_installed": _terminal_surface_packet_installed,
		"terminal_surface_packet_version": _terminal_surface_packet_version,
		"terminal_surface_generator_version": _terminal_surface_generator_version,
		"terminal_surface_generation_source": _terminal_surface_generation_source,
	}

func needs_full_redraw() -> bool:
	return _visual_state == ChunkVisualState.TERRAIN_READY \
		or _visual_state == ChunkVisualState.FULL_PENDING

func is_terrain_phase_done() -> bool:
	return _redraw_phase > ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN

## Internal non-terminal helper: terrain + cover + cliff are complete.
## This must not be used as a player-visible/full_ready publication gate.
func is_gameplay_redraw_complete() -> bool:
	return _redraw_phase >= ChunkVisualKernelScript.REDRAW_PHASE_FLORA

func is_flora_phase_done() -> bool:
	return _redraw_phase > ChunkVisualKernelScript.REDRAW_PHASE_FLORA

func continue_redraw(max_rows: int) -> bool:
	if _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_DONE:
		_sync_visual_state_after_redraw_mutation()
		return true
	while _redraw_phase != ChunkVisualKernelScript.REDRAW_PHASE_DONE:
		if _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_INTERIOR or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_COLLISION:
			if not _should_build_debug_markers():
				_advance_redraw_phase()
				continue
		var processed_phase: int = _redraw_phase
		var phase_start_index: int = _redraw_tile_index
		var processed: int = _process_redraw_phase_tiles(_resolve_redraw_phase_tile_budget(max_rows))
		if processed <= 0:
			_advance_redraw_phase()
			continue
		if processed_phase == ChunkVisualKernelScript.REDRAW_PHASE_COVER:
			_reapply_local_zone_cover_state_for_index_range(phase_start_index, _redraw_tile_index)
		if _redraw_tile_index >= _chunk_size * _chunk_size:
			_advance_redraw_phase()
		_sync_visual_state_after_redraw_mutation()
		return _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_DONE
	_sync_visual_state_after_redraw_mutation()
	return true

func _mark_visual_native_ready() -> void:
	_visual_state = ChunkVisualState.NATIVE_READY

func _mark_visual_proxy_ready() -> void:
	if _visual_state >= ChunkVisualState.PROXY_READY:
		return
	_visual_state = ChunkVisualState.PROXY_READY

func _mark_visual_first_pass_ready() -> void:
	if _visual_state >= ChunkVisualState.TERRAIN_READY:
		return
	_visual_state = ChunkVisualState.TERRAIN_READY

func _mark_visual_convergence_owed() -> void:
	if not is_first_pass_ready():
		return
	_visual_state = ChunkVisualState.FULL_PENDING

func _mark_visual_full_redraw_pending() -> void:
	if not is_first_pass_ready():
		_mark_visual_first_pass_ready()
	_mark_visual_convergence_owed()

func _mark_visual_full_redraw_ready() -> void:
	assert(_can_publish_full_redraw_ready(),
		"chunk visual state must not publish FULL_READY before redraw is complete and no border fix is pending")
	_visual_state = ChunkVisualState.FULL_READY

func _can_publish_full_redraw_ready() -> bool:
	return has_terminal_publication_packet() \
		and is_first_pass_ready() \
		and _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_DONE \
		and not has_pending_border_dirty()

func _sync_visual_state_after_redraw_mutation() -> void:
	if _redraw_phase > ChunkVisualKernelScript.REDRAW_PHASE_COVER:
		_mark_visual_first_pass_ready()

func _redraw_dynamic_visibility(_dirty_tiles: Dictionary) -> void:
	_rebuild_cover_layer()
	_reapply_local_zone_cover_state()
	if WorldGenerator and WorldGenerator.balance and WorldGenerator.balance.mountain_debug_visualization:
		_clear_debug_markers()
		_rebuild_debug_markers()

## Enqueue border tiles for deferred redraw. Called by ChunkManager when a
## new neighbor chunk is loaded and border seam tiles need updating.
## The actual redraw happens during the next progressive redraw tick.
## (boot_fast_first_playable_spec Iteration 3, change 3A)
func enqueue_dirty_border_redraw(
	dirty_tiles: Dictionary,
	reason_key: String = "",
	reason_version: int = -1
) -> bool:
	var added_new_tiles: bool = false
	for local_tile: Vector2i in dirty_tiles:
		if _add_pending_border_dirty_tile(local_tile):
			added_new_tiles = true
	if not added_new_tiles and dirty_tiles.is_empty():
		return false
	if not reason_key.is_empty() and reason_version >= 0:
		var pending_version: int = int(_border_fix_pending_reason_versions.get(reason_key, -1))
		var applied_version: int = int(_border_fix_applied_reason_versions.get(reason_key, -1))
		var duplicate_reason_version: bool = pending_version == reason_version or applied_version == reason_version
		if duplicate_reason_version and not added_new_tiles:
			return false
		_border_fix_pending_reason_versions[reason_key] = reason_version
	elif not added_new_tiles:
		return false
	return added_new_tiles

func _redraw_dirty_tiles(dirty_tiles: Dictionary) -> void:
	var batch: Dictionary = build_visual_dirty_batch(dirty_tiles)
	if batch.is_empty():
		return
	var computed_batch: Dictionary = Chunk.compute_visual_batch(batch)
	apply_visual_dirty_batch(computed_batch)

func _redraw_cover_tiles(dirty_tiles: Dictionary) -> void:
	for local_tile: Vector2i in dirty_tiles:
		if not _is_inside(local_tile):
			continue
		_cover_layer.erase_cell(local_tile)
		_redraw_cover_tile(local_tile)
	_reapply_local_zone_cover_state_for_tiles(dirty_tiles)

func supports_worker_visual_phase() -> bool:
	return _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_COVER \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_CLIFF \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_FLORA

func build_visual_phase_batch(tile_budget: int) -> Dictionary:
	if not supports_worker_visual_phase():
		return {}
	var total_tiles: int = _chunk_size * _chunk_size
	if _redraw_tile_index >= total_tiles:
		return {}
	if _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_FLORA:
		var flora_payload: Dictionary = _ensure_flora_payload()
		var prebuilt_packet: Dictionary = _get_prebuilt_flora_render_packet(flora_payload)
		return {
			"mode": ChunkVisualKernelScript.VISUAL_BATCH_MODE_PHASE,
			"phase": ChunkVisualKernelScript.REDRAW_PHASE_FLORA,
			"phase_name": &"flora_batch",
			"chunk_coord": chunk_coord,
			"chunk_size": _chunk_size,
			"tile_size": _tile_size,
			"is_underground": _is_underground,
			"start_index": _redraw_tile_index,
			"end_index": total_tiles,
			"tiles": [],
			"flora_payload": flora_payload,
			"flora_packet": prebuilt_packet,
			"skip_worker_compute": not prebuilt_packet.is_empty(),
		}
	if _has_prebaked_visual_phase_data():
		return _build_prebaked_visual_phase_batch(tile_budget)
	var start_index: int = _redraw_tile_index
	var end_index: int = mini(total_tiles, start_index + maxi(1, tile_budget))
	var tiles: Array[Vector2i] = []
	for tile_index: int in range(start_index, end_index):
		tiles.append(_tile_from_index(tile_index))
	return _build_visual_compute_request(ChunkVisualKernelScript.VISUAL_BATCH_MODE_PHASE, tiles, _redraw_phase, start_index, end_index)

func _normalize_dirty_tile_list(dirty_tiles: Array, limit: int = -1) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile_variant: Variant in dirty_tiles:
		var local_tile: Vector2i = tile_variant as Vector2i
		if not _is_inside(local_tile):
			continue
		tiles.append(local_tile)
	if tiles.is_empty():
		return tiles
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	if limit > 0 and tiles.size() > limit:
		tiles.resize(limit)
	return tiles

func build_visual_dirty_batch(dirty_tiles: Dictionary, limit: int = -1) -> Dictionary:
	return build_visual_dirty_batch_from_tiles(dirty_tiles.keys(), limit)

func build_visual_dirty_batch_from_tiles(dirty_tiles: Array, limit: int = -1) -> Dictionary:
	var tiles: Array[Vector2i] = _normalize_dirty_tile_list(dirty_tiles, limit)
	if tiles.is_empty():
		return {}
	return _build_visual_compute_request(ChunkVisualKernelScript.VISUAL_BATCH_MODE_DIRTY, tiles)

func _build_prebaked_visual_phase_batch(tile_budget: int) -> Dictionary:
	var total_tiles: int = _chunk_size * _chunk_size
	var start_index: int = _redraw_tile_index
	var end_index: int = mini(total_tiles, start_index + maxi(1, tile_budget))
	var tiles: Array[Vector2i] = []
	for tile_index: int in range(start_index, end_index):
		tiles.append(_tile_from_index(tile_index))
	var request: Dictionary = {
		"mode": ChunkVisualKernelScript.VISUAL_BATCH_MODE_PHASE,
		"phase": _redraw_phase,
		"phase_name": Chunk._visual_phase_name(_redraw_phase),
		"chunk_coord": chunk_coord,
		"chunk_size": _chunk_size,
		"is_underground": _is_underground,
		"start_index": start_index,
		"end_index": end_index,
		"tiles": tiles,
		"terrain_bytes": _terrain_bytes,
		"height_bytes": _height_bytes,
		"variation_bytes": _variation_bytes,
		"biome_bytes": _biome_bytes,
		"secondary_biome_bytes": _secondary_biome_bytes,
		"ecotone_values": _ecotone_values,
		"rock_visual_class": _rock_visual_class_bytes,
		"ground_face_atlas": _ground_face_atlas_bytes,
		"cover_mask": _cover_mask_bytes,
		"cliff_overlay": _cliff_overlay_bytes,
		"variant_id": _variant_id_bytes,
		"alt_id": _alt_id_bytes,
		"skip_worker_compute": true,
	}
	if Chunk._has_native_visual_kernels():
		request["native_visual_tables"] = Chunk._build_native_visual_tables()
	return request

func apply_visual_phase_batch(batch: Dictionary) -> bool:
	if StringName(batch.get("mode", &"")) != ChunkVisualKernelScript.VISUAL_BATCH_MODE_PHASE:
		return false
	var phase: int = int(batch.get("phase", ChunkVisualKernelScript.REDRAW_PHASE_DONE))
	var start_index: int = int(batch.get("start_index", -1))
	var end_index: int = int(batch.get("end_index", -1))
	if phase != _redraw_phase or start_index != _redraw_tile_index:
		return false
	if phase == ChunkVisualKernelScript.REDRAW_PHASE_FLORA:
		_apply_flora_render_packet(batch.get("flora_packet", {}) as Dictionary, &"batched_renderer")
	else:
		_apply_visual_prepared_batch(batch)
	_redraw_tile_index = end_index
	if phase == ChunkVisualKernelScript.REDRAW_PHASE_COVER:
		_reapply_local_zone_cover_state_for_index_range(start_index, end_index)
	if _redraw_tile_index >= _chunk_size * _chunk_size:
		_advance_redraw_phase()
	_sync_visual_state_after_redraw_mutation()
	return true

func apply_visual_dirty_batch(batch: Dictionary) -> bool:
	if StringName(batch.get("mode", &"")) != ChunkVisualKernelScript.VISUAL_BATCH_MODE_DIRTY:
		return false
	_apply_visual_prepared_batch(batch)
	_mark_interior_macro_dirty()
	_reapply_local_zone_cover_state_for_tile_list(batch.get("tiles", []) as Array)
	if WorldGenerator and WorldGenerator.balance and WorldGenerator.balance.mountain_debug_visualization:
		_clear_debug_markers()
		_rebuild_debug_markers()
	return true

func _build_visual_compute_request(
	mode: StringName,
	tiles: Array[Vector2i],
	phase: int = ChunkVisualKernelScript.REDRAW_PHASE_DONE,
	start_index: int = -1,
	end_index: int = -1
) -> Dictionary:
	if tiles.is_empty():
		return {}
	var terrain_lookup: Dictionary = {}
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	for local_tile: Vector2i in tiles:
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var neighbor_tile: Vector2i = local_tile + Vector2i(offset_x, offset_y)
				if _is_inside(neighbor_tile):
					continue
				if terrain_lookup.has(neighbor_tile):
					continue
				terrain_lookup[neighbor_tile] = _get_neighbor_terrain(neighbor_tile)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache
	var request: Dictionary = {
		"mode": mode,
		"phase": phase,
		"phase_name": &"dirty" if mode == ChunkVisualKernelScript.VISUAL_BATCH_MODE_DIRTY else Chunk._visual_phase_name(phase),
		"chunk_coord": chunk_coord,
		"chunk_size": _chunk_size,
		"is_underground": _is_underground,
		"start_index": start_index,
		"end_index": end_index,
		"tiles": tiles,
		"terrain_lookup": terrain_lookup,
		"terrain_bytes": _terrain_bytes,
		"height_bytes": _height_bytes,
		"variation_bytes": _variation_bytes,
		"biome_bytes": _biome_bytes,
		"secondary_biome_bytes": _secondary_biome_bytes,
		"ecotone_values": _ecotone_values,
	}
	if Chunk._has_native_visual_kernels():
		request["native_visual_tables"] = Chunk._build_native_visual_tables()
	return request

func _build_single_tile_visual_request(local_tile: Vector2i) -> Dictionary:
	var tiles: Array[Vector2i] = [local_tile]
	return _build_visual_compute_request(ChunkVisualKernelScript.VISUAL_BATCH_MODE_DIRTY, tiles)

func _build_all_chunk_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			tiles.append(Vector2i(local_x, local_y))
	return tiles

func _apply_visual_phase_for_tiles_now(phase: int, tiles: Array[Vector2i]) -> void:
	if tiles.is_empty():
		return
	var request: Dictionary = _build_visual_compute_request(
		ChunkVisualKernelScript.VISUAL_BATCH_MODE_PHASE,
		tiles,
		phase,
		0,
		tiles.size()
	)
	var batch: Dictionary = Chunk.compute_visual_batch(request)
	_apply_visual_prepared_batch(batch)

func _apply_single_tile_visual_phase(local_tile: Vector2i, phase: int, explicit_clear: bool = true) -> void:
	var request: Dictionary = _build_single_tile_visual_request(local_tile)
	var commands: Array[Dictionary] = ChunkVisualKernelScript.compute_tile_phase_commands(
		request,
		local_tile,
		phase,
		explicit_clear
	)
	_apply_visual_commands(commands)

func _apply_visual_commands(
	commands: Array,
	command_buffer: PackedInt32Array = PackedInt32Array(),
	command_stride: int = ChunkVisualKernelScript.VISUAL_COMMAND_BUFFER_STRIDE
) -> int:
	if not command_buffer.is_empty():
		return _apply_visual_command_buffer(command_buffer, command_stride)
	var applied_commands: int = 0
	for command_variant: Variant in commands:
		var command: Dictionary = command_variant as Dictionary
		var layer: TileMapLayer = _visual_layer_for_command(int(command.get("layer", -1)))
		if layer == null:
			continue
		var local_tile: Vector2i = command.get("tile", Vector2i.ZERO) as Vector2i
		if int(command.get("op", ChunkVisualKernelScript.VISUAL_COMMAND_OP_SET)) == ChunkVisualKernelScript.VISUAL_COMMAND_OP_SET:
			layer.set_cell(
				local_tile,
				int(command.get("source_id", 0)),
				command.get("atlas", Vector2i.ZERO) as Vector2i,
				int(command.get("alt_id", 0))
			)
		else:
			layer.erase_cell(local_tile)
		applied_commands += 1
	return applied_commands

func _apply_visual_prepared_batch(batch: Dictionary) -> int:
	var terrain_buffer: PackedInt32Array = batch.get("terrain_buffer", PackedInt32Array())
	var ground_face_buffer: PackedInt32Array = batch.get("ground_face_buffer", PackedInt32Array())
	var rock_buffer: PackedInt32Array = batch.get("rock_buffer", PackedInt32Array())
	var cover_buffer: PackedInt32Array = batch.get("cover_buffer", PackedInt32Array())
	var cliff_buffer: PackedInt32Array = batch.get("cliff_buffer", PackedInt32Array())
	var applied_commands: int = 0
	if not terrain_buffer.is_empty() \
		or not ground_face_buffer.is_empty() \
		or not rock_buffer.is_empty() \
		or not cover_buffer.is_empty() \
		or not cliff_buffer.is_empty():
		applied_commands += _apply_visual_layer_buffers(
			terrain_buffer,
			ground_face_buffer,
			rock_buffer,
			cover_buffer,
			cliff_buffer,
			int(batch.get("buffer_stride", ChunkVisualKernelScript.VISUAL_APPLY_BUFFER_STRIDE))
		)
	return applied_commands + _apply_visual_commands(
		batch.get("commands", []) as Array,
		batch.get("command_buffer", PackedInt32Array()),
		int(batch.get("command_stride", ChunkVisualKernelScript.VISUAL_COMMAND_BUFFER_STRIDE))
	)

func _apply_visual_layer_buffers(
	terrain_buffer: PackedInt32Array,
	ground_face_buffer: PackedInt32Array,
	rock_buffer: PackedInt32Array,
	cover_buffer: PackedInt32Array,
	cliff_buffer: PackedInt32Array,
	buffer_stride: int = ChunkVisualKernelScript.VISUAL_APPLY_BUFFER_STRIDE
) -> int:
	var native_applied: int = _try_apply_visual_buffers_native(
		terrain_buffer,
		ground_face_buffer,
		rock_buffer,
		cover_buffer,
		cliff_buffer,
		buffer_stride
	)
	if native_applied >= 0:
		return native_applied
	var applied_commands: int = 0
	applied_commands += _apply_visual_layer_buffer(_terrain_layer, terrain_buffer, buffer_stride)
	applied_commands += _apply_visual_layer_buffer(_ground_face_layer, ground_face_buffer, buffer_stride)
	applied_commands += _apply_visual_layer_buffer(_rock_layer, rock_buffer, buffer_stride)
	applied_commands += _apply_visual_layer_buffer(_cover_layer, cover_buffer, buffer_stride)
	applied_commands += _apply_visual_layer_buffer(_cliff_layer, cliff_buffer, buffer_stride)
	return applied_commands

func _apply_visual_command_buffer(command_buffer: PackedInt32Array, command_stride: int = ChunkVisualKernelScript.VISUAL_COMMAND_BUFFER_STRIDE) -> int:
	if command_stride <= 0:
		return 0
	var applied_commands: int = 0
	var command_limit: int = command_buffer.size() - command_stride + 1
	var index: int = 0
	while index < command_limit:
		var layer: TileMapLayer = _visual_layer_for_command(command_buffer[index])
		if layer != null:
			var local_tile: Vector2i = Vector2i(command_buffer[index + 1], command_buffer[index + 2])
			if command_buffer[index + 3] == ChunkVisualKernelScript.VISUAL_COMMAND_OP_SET:
				layer.set_cell(
					local_tile,
					command_buffer[index + 4],
					Vector2i(command_buffer[index + 5], command_buffer[index + 6]),
					command_buffer[index + 7]
				)
			else:
				layer.erase_cell(local_tile)
			applied_commands += 1
		index += command_stride
	return applied_commands

func _apply_visual_layer_buffer(
	layer: TileMapLayer,
	buffer: PackedInt32Array,
	buffer_stride: int = ChunkVisualKernelScript.VISUAL_APPLY_BUFFER_STRIDE
) -> int:
	if layer == null or buffer.is_empty() or buffer_stride <= 0:
		return 0
	var applied_commands: int = 0
	var command_limit: int = buffer.size() - buffer_stride + 1
	var index: int = 0
	while index < command_limit:
		var local_tile: Vector2i = Vector2i(buffer[index], buffer[index + 1])
		if buffer[index + 2] == ChunkVisualKernelScript.VISUAL_COMMAND_OP_SET:
			layer.set_cell(
				local_tile,
				buffer[index + 3],
				Vector2i(buffer[index + 4], buffer[index + 5]),
				buffer[index + 6]
			)
		else:
			layer.erase_cell(local_tile)
		applied_commands += 1
		index += buffer_stride
	return applied_commands

func _try_apply_visual_buffers_native(
	terrain_buffer: PackedInt32Array,
	ground_face_buffer: PackedInt32Array,
	rock_buffer: PackedInt32Array,
	cover_buffer: PackedInt32Array,
	cliff_buffer: PackedInt32Array,
	buffer_stride: int = ChunkVisualKernelScript.VISUAL_APPLY_BUFFER_STRIDE
) -> int:
	var helper: RefCounted = Chunk._get_native_visual_kernels()
	if helper == null or not helper.has_method("apply_chunk_visual_buffers"):
		return -1
	return int(helper.call(
		"apply_chunk_visual_buffers",
		_terrain_layer,
		terrain_buffer,
		_ground_face_layer,
		ground_face_buffer,
		_rock_layer,
		rock_buffer,
		_cover_layer,
		cover_buffer,
		_cliff_layer,
		cliff_buffer,
		buffer_stride
	))

func _visual_layer_for_command(layer_id: int) -> TileMapLayer:
	match layer_id:
		ChunkVisualKernelScript.VISUAL_LAYER_TERRAIN:
			return _terrain_layer
		ChunkVisualKernelScript.VISUAL_LAYER_GROUND_FACE:
			return _ground_face_layer
		ChunkVisualKernelScript.VISUAL_LAYER_ROCK:
			return _rock_layer
		ChunkVisualKernelScript.VISUAL_LAYER_COVER:
			return _cover_layer
		ChunkVisualKernelScript.VISUAL_LAYER_CLIFF:
			return _cliff_layer
		_:
			return null

static func compute_visual_batch(request: Dictionary) -> Dictionary:
	if bool(request.get("skip_worker_compute", false)) and request.has("rock_visual_class"):
		var native_prebaked_batch: Dictionary = Chunk._try_compute_visual_batch_native(request)
		if not native_prebaked_batch.is_empty():
			return native_prebaked_batch
		return ChunkVisualKernelScript.compute_prebaked_visual_batch(request)
	var native_batch: Dictionary = Chunk._try_compute_visual_batch_native(request)
	if not native_batch.is_empty():
		return native_batch
	var mode: StringName = StringName(request.get("mode", &""))
	match mode:
		ChunkVisualKernelScript.VISUAL_BATCH_MODE_PHASE:
			var phase: int = int(request.get("phase", ChunkVisualKernelScript.REDRAW_PHASE_DONE))
			if phase == ChunkVisualKernelScript.REDRAW_PHASE_FLORA:
				var prebuilt_packet: Dictionary = request.get("flora_packet", {}) as Dictionary
				if prebuilt_packet.is_empty():
					prebuilt_packet = ChunkFloraResultScript.build_render_packet_from_payload(
						request.get("flora_payload", {}) as Dictionary,
						int(request.get("tile_size", 0))
					)
				return {
					"mode": request.get("mode", &""),
					"phase": phase,
					"phase_name": request.get("phase_name", &"done"),
					"start_index": int(request.get("start_index", -1)),
					"end_index": int(request.get("end_index", -1)),
					"tiles": request.get("tiles", []),
					"tile_count": int((request.get("tiles", []) as Array).size()),
					"commands": [],
					"command_count": 0,
					"flora_packet": prebuilt_packet,
				}
			return _block_legacy_visual_batch_fallback(request, "missing_native_phase_batch")
		ChunkVisualKernelScript.VISUAL_BATCH_MODE_DIRTY:
			return _block_legacy_visual_batch_fallback(request, "missing_native_dirty_batch")
		_:
			return _block_legacy_visual_batch_fallback(request, "unsupported_visual_batch_mode")

static func _block_legacy_visual_batch_fallback(request: Dictionary, reason: String) -> Dictionary:
	var coord: Vector2i = request.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var mode: StringName = StringName(request.get("mode", &""))
	var phase_name: StringName = StringName(request.get("phase_name", &""))
	var message: String = "Zero-Tolerance Chunk Readiness R1 blocked legacy visual fallback for %s mode=%s phase=%s (%s). Critical player-reachable visual convergence must stay native-only." % [
		coord,
		String(mode),
		String(phase_name),
		reason,
	]
	push_error(message)
	assert(false, message)
	return {}

static func _try_compute_visual_batch_native(request: Dictionary) -> Dictionary:
	if not Chunk._has_native_visual_kernels():
		return {}
	var mode: StringName = StringName(request.get("mode", &""))
	if mode != ChunkVisualKernelScript.VISUAL_BATCH_MODE_DIRTY and mode != ChunkVisualKernelScript.VISUAL_BATCH_MODE_PHASE:
		return {}
	if mode == ChunkVisualKernelScript.VISUAL_BATCH_MODE_PHASE:
		var phase: int = int(request.get("phase", ChunkVisualKernelScript.REDRAW_PHASE_DONE))
		if phase != ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN and phase != ChunkVisualKernelScript.REDRAW_PHASE_COVER and phase != ChunkVisualKernelScript.REDRAW_PHASE_CLIFF:
			return {}
	if not request.has("native_visual_tables"):
		return {}
	var helper: RefCounted = Chunk._get_native_visual_kernels()
	if helper == null or not helper.has_method("compute_visual_batch"):
		return {}
	var batch: Dictionary = helper.call("compute_visual_batch", request) as Dictionary
	if batch.is_empty():
		return {}
	return batch

static func _get_native_visual_kernels() -> RefCounted:
	if not Chunk._has_native_visual_kernels():
		return null
	if _native_visual_kernels == null:
		_native_visual_kernels = ClassDB.instantiate(NATIVE_VISUAL_KERNELS_CLASS) as RefCounted
	return _native_visual_kernels

static func _has_native_visual_kernels() -> bool:
	if not _native_visual_kernels_checked:
		_native_visual_kernels_checked = true
		_native_visual_kernels_available = ClassDB.class_exists(NATIVE_VISUAL_KERNELS_CLASS)
	return _native_visual_kernels_available

static func build_native_visual_tables() -> Dictionary:
	return _build_native_visual_tables()

static func _build_native_visual_tables() -> Dictionary:
	return {
		"surface_palette_tiles": ChunkTilesetFactory._surface_palette_tiles,
		"wall_flip_class": ChunkTilesetFactory._WALL_FLIP_CLASS,
		"wall_flip_alt_count": ChunkTilesetFactory.wall_flip_alt_count,
		"wall_base_count": ChunkTilesetFactory.wall_base_count,
		"terrain_tiles_per_row": ChunkTilesetFactory.terrain_tiles_per_row,
		"ground_face_tiles_start": ChunkTilesetFactory.ground_face_tiles_start,
		"sand_face_tiles_start": ChunkTilesetFactory.sand_face_tiles_start,
		"interior_base_variant_count": ChunkTilesetFactory.get_interior_base_variant_count(),
		"interior_transform_count": ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT,
		"terrain_source_id": ChunkTilesetFactory.TERRAIN_SOURCE_ID,
		"overlay_source_id": ChunkTilesetFactory.OVERLAY_SOURCE_ID,
		"surface_variation_none": ChunkTilesetFactory.SURFACE_VARIATION_NONE,
		"tile_ground_dark": ChunkTilesetFactory.TILE_GROUND_DARK,
		"tile_ground": ChunkTilesetFactory.TILE_GROUND,
		"tile_ground_light": ChunkTilesetFactory.TILE_GROUND_LIGHT,
		"tile_mined_floor": ChunkTilesetFactory.TILE_MINED_FLOOR,
		"tile_mountain_entrance": ChunkTilesetFactory.TILE_MOUNTAIN_ENTRANCE,
		"tile_water": ChunkTilesetFactory.tile_water,
		"tile_sand": ChunkTilesetFactory.tile_sand,
		"tile_grass": ChunkTilesetFactory.tile_grass,
		"tile_sparse_flora": ChunkTilesetFactory.tile_sparse_flora,
		"tile_dense_flora": ChunkTilesetFactory.tile_dense_flora,
		"tile_clearing": ChunkTilesetFactory.tile_clearing,
		"tile_rocky_patch": ChunkTilesetFactory.tile_rocky_patch,
		"tile_wet_patch": ChunkTilesetFactory.tile_wet_patch,
		"tile_ice": ChunkTilesetFactory.tile_ice,
		"tile_scorched": ChunkTilesetFactory.tile_scorched,
		"tile_salt_flat": ChunkTilesetFactory.tile_salt_flat,
		"tile_dry_riverbed": ChunkTilesetFactory.tile_dry_riverbed,
		"tile_shadow_south": ChunkTilesetFactory.TILE_SHADOW_SOUTH,
		"tile_shadow_north": ChunkTilesetFactory.TILE_SHADOW_NORTH,
		"tile_shadow_west": ChunkTilesetFactory.TILE_SHADOW_WEST,
		"tile_shadow_east": ChunkTilesetFactory.TILE_SHADOW_EAST,
		"tile_top_edge": ChunkTilesetFactory.TILE_TOP_EDGE,
		"terrain_ground": TileGenData.TerrainType.GROUND,
		"terrain_rock": TileGenData.TerrainType.ROCK,
		"terrain_water": TileGenData.TerrainType.WATER,
		"terrain_sand": TileGenData.TerrainType.SAND,
		"terrain_grass": TileGenData.TerrainType.GRASS,
		"terrain_mined_floor": TileGenData.TerrainType.MINED_FLOOR,
		"terrain_mountain_entrance": TileGenData.TerrainType.MOUNTAIN_ENTRANCE,
	}

static func _prebaked_wall_def_from_index(def_index: int) -> Vector2i:
	return Vector2i(7 + def_index, 0)

static func _prebaked_linear_index_to_coords(linear_index: int) -> Vector2i:
	if linear_index < 0:
		return Vector2i(-1, -1)
	return Vector2i(
		linear_index % maxi(1, ChunkTilesetFactory.terrain_tiles_per_row),
		linear_index / maxi(1, ChunkTilesetFactory.terrain_tiles_per_row)
	)

static func _pack_prebaked_mask(atlas_index: int, alt_id: int) -> int:
	if atlas_index < 0:
		return ChunkVisualKernelScript.PREBAKED_COVER_NONE
	return (atlas_index << ChunkVisualKernelScript.PREBAKED_MASK_ALT_SHIFT) | (alt_id & 0xff)

static func _unpack_prebaked_mask_atlas(mask_value: int) -> int:
	if mask_value < 0:
		return -1
	return mask_value >> ChunkVisualKernelScript.PREBAKED_MASK_ALT_SHIFT

static func _unpack_prebaked_mask_alt(mask_value: int) -> int:
	if mask_value < 0:
		return 0
	return mask_value & 0xff

static func _prebaked_cliff_overlay_coords(kind: int) -> Vector2i:
	match kind:
		ChunkVisualKernelScript.PREBAKED_CLIFF_SOUTH:
			return ChunkTilesetFactory.TILE_SHADOW_SOUTH
		ChunkVisualKernelScript.PREBAKED_CLIFF_WEST:
			return ChunkTilesetFactory.TILE_SHADOW_WEST
		ChunkVisualKernelScript.PREBAKED_CLIFF_EAST:
			return ChunkTilesetFactory.TILE_SHADOW_EAST
		ChunkVisualKernelScript.PREBAKED_CLIFF_TOP:
			return ChunkTilesetFactory.TILE_TOP_EDGE
		ChunkVisualKernelScript.PREBAKED_CLIFF_SURFACE_NORTH:
			return ChunkTilesetFactory.TILE_SHADOW_NORTH
		_:
			return Vector2i(-1, -1)

static func build_prebaked_visual_payload(request: Dictionary) -> Dictionary:
	return ChunkVisualKernelScript.build_prebaked_visual_payload(request)

static func _compute_prebaked_visual_batch(request: Dictionary) -> Dictionary:
	return ChunkVisualKernelScript.compute_prebaked_visual_batch(request)

static func _append_terrain_visual_commands(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	ChunkVisualKernelScript.append_terrain_visual_commands(request, local_tile, commands, explicit_clear)

static func _append_ground_face_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	terrain_type: int,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	ChunkVisualKernelScript.append_ground_face_visual_command(
		request,
		local_tile,
		terrain_type,
		commands,
		explicit_clear
	)

static func _append_cover_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	ChunkVisualKernelScript.append_cover_visual_command(request, local_tile, commands, explicit_clear)

static func _append_cliff_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	ChunkVisualKernelScript.append_cliff_visual_command(request, local_tile, commands, explicit_clear)

static func _make_visual_set_command(layer: int, local_tile: Vector2i, source_id: int, atlas: Vector2i, alt_id: int) -> Dictionary:
	return {
		"layer": layer,
		"tile": local_tile,
		"op": ChunkVisualKernelScript.VISUAL_COMMAND_OP_SET,
		"source_id": source_id,
		"atlas": atlas,
		"alt_id": alt_id,
	}

static func _make_visual_erase_command(layer: int, local_tile: Vector2i) -> Dictionary:
	return {
		"layer": layer,
		"tile": local_tile,
		"op": ChunkVisualKernelScript.VISUAL_COMMAND_OP_ERASE,
	}

static func _visual_request_terrain(request: Dictionary, local_tile: Vector2i) -> int:
	return ChunkVisualKernelScript.request_terrain(request, local_tile)

static func _visual_request_height(request: Dictionary, local_tile: Vector2i) -> float:
	return ChunkVisualKernelScript.request_height(request, local_tile)

static func _visual_request_variation(request: Dictionary, local_tile: Vector2i) -> int:
	return ChunkVisualKernelScript.request_variation(request, local_tile)

static func _visual_request_biome(request: Dictionary, local_tile: Vector2i) -> int:
	return ChunkVisualKernelScript.request_biome(request, local_tile)

static func _visual_request_to_global_tile(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.request_to_global_tile(request, local_tile)

static func _visual_request_is_open_for_visual(terrain_type: int) -> bool:
	return ChunkVisualKernelScript.is_open_for_visual(terrain_type)

static func _visual_request_is_open_exterior(terrain_type: int) -> bool:
	return ChunkVisualKernelScript.is_open_exterior(terrain_type)

static func _visual_request_is_open_for_surface_rock_visual(terrain_type: int) -> bool:
	return ChunkVisualKernelScript.is_open_for_surface_rock_visual(terrain_type)

static func _visual_request_is_open_for_surface_visual(terrain_type: int, water_only: bool) -> bool:
	return ChunkVisualKernelScript.is_open_for_surface_visual(terrain_type, water_only)

static func _visual_request_has_water_face_neighbor(request: Dictionary, local_tile: Vector2i) -> bool:
	return ChunkVisualKernelScript.has_water_face_neighbor(request, local_tile)

static func _visual_request_is_surface_face_terrain(terrain_type: int) -> bool:
	return ChunkVisualKernelScript.is_surface_face_terrain(terrain_type)

static func _visual_request_ground_atlas_for_height(height_value: float) -> Vector2i:
	return ChunkVisualKernelScript.request_ground_atlas_for_height(height_value)

static func _visual_request_surface_ground_atlas(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.request_surface_ground_atlas(request, local_tile)

static func _visual_request_surface_rock_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.surface_rock_visual_class(request, local_tile)

static func _visual_request_water_face_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.water_face_visual_class(request, local_tile)

static func _visual_request_surface_visual_class(request: Dictionary, local_tile: Vector2i, water_only: bool) -> Vector2i:
	return ChunkVisualKernelScript.surface_visual_class(request, local_tile, water_only)

static func _visual_request_rock_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.rock_visual_class(request, local_tile)

static func _visual_request_is_cave_edge_rock(request: Dictionary, local_tile: Vector2i) -> bool:
	return ChunkVisualKernelScript.is_cave_edge_rock(request, local_tile)

static func _visual_request_is_exterior_surface_rock(request: Dictionary, local_tile: Vector2i) -> bool:
	return ChunkVisualKernelScript.is_exterior_surface_rock(request, local_tile)

static func _visual_request_cover_rock_atlas(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.cover_rock_atlas(request, local_tile)

static func _visual_request_variant_atlas(base: Vector2i, global_x: int, global_y: int) -> Vector2i:
	return ChunkVisualKernelScript.resolve_variant_atlas(base, global_x, global_y)

static func _visual_request_cliff_overlay_kind(request: Dictionary, local_tile: Vector2i) -> int:
	return ChunkVisualKernelScript.cliff_overlay_kind(request, local_tile)

static func _visual_request_variant_alt_id(base: Vector2i, global_x: int, global_y: int, allow_flip: bool) -> int:
	return ChunkVisualKernelScript.resolve_variant_alt_id(base, global_x, global_y, allow_flip)

static func _visual_request_resolve_interior_family(global_x: int, global_y: int, base_count: int) -> int:
	return ChunkVisualKernelScript.resolve_interior_family(global_x, global_y, base_count)

static func _visual_request_sample_interior_family_noise(global_x: int, global_y: int, scale: float, seed: int) -> float:
	return ChunkVisualKernelScript.sample_interior_family_noise(global_x, global_y, scale, seed)

static func _visual_request_raw_interior_variant(global_x: int, global_y: int, family_index: int, seed: int = ChunkVisualKernelScript._INTERIOR_VARIATION_SEED) -> Vector2i:
	return ChunkVisualKernelScript.raw_interior_variant(global_x, global_y, family_index, seed)

static func _visual_request_interior_variant(global_x: int, global_y: int) -> Vector2i:
	return ChunkVisualKernelScript.resolve_interior_variant(global_x, global_y)

static func _visual_phase_name(phase: int) -> StringName:
	return ChunkVisualKernelScript.visual_phase_name(phase)

func _reset_cover_visual_state() -> void:
	if _cover_layer:
		_cover_layer.visible = true
	_reapply_local_zone_cover_state()

func _redraw_terrain_tile(local_tile: Vector2i) -> void:
	_apply_single_tile_visual_phase(local_tile, ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN)

func _redraw_ground_face_tile(local_tile: Vector2i, terrain_type: int) -> void:
	var request: Dictionary = _build_single_tile_visual_request(local_tile)
	var commands: Array[Dictionary] = []
	ChunkVisualKernelScript.append_ground_face_visual_command(
		request,
		local_tile,
		terrain_type,
		commands,
		true
	)
	_apply_visual_commands(commands)

func _surface_rock_visual_class(local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.surface_rock_visual_class(_build_single_tile_visual_request(local_tile), local_tile)

func _water_face_visual_class(local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.water_face_visual_class(_build_single_tile_visual_request(local_tile), local_tile)

func _surface_visual_class(local_tile: Vector2i, water_only: bool) -> Vector2i:
	return ChunkVisualKernelScript.surface_visual_class(_build_single_tile_visual_request(local_tile), local_tile, water_only)

func _has_water_face_neighbor(local_tile: Vector2i) -> bool:
	return ChunkVisualKernelScript.has_water_face_neighbor(_build_single_tile_visual_request(local_tile), local_tile)

func _is_surface_face_terrain(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.GRASS \
		or terrain_type == TileGenData.TerrainType.SAND

func _resolve_surface_ground_atlas(local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.request_surface_ground_atlas(_build_single_tile_visual_request(local_tile), local_tile)

func _ground_atlas_for_height(height_value: float) -> Vector2i:
	return ChunkVisualKernelScript.request_ground_atlas_for_height(height_value)

func _resolve_open_tile_type(local_tile: Vector2i) -> int:
	for dir: Vector2i in ChunkVisualKernelScript._CARDINAL_DIRS:
		if _is_open_exterior(_get_neighbor_terrain(local_tile + dir)):
			return TileGenData.TerrainType.MOUNTAIN_ENTRANCE
	return TileGenData.TerrainType.MINED_FLOOR

func _resolve_open_tile_type_for_neighbor_refresh(local_tile: Vector2i) -> int:
	for dir: Vector2i in ChunkVisualKernelScript._CARDINAL_DIRS:
		if _is_open_exterior(_get_neighbor_terrain_for_neighbor_refresh(local_tile, dir)):
			return TileGenData.TerrainType.MOUNTAIN_ENTRANCE
	return TileGenData.TerrainType.MINED_FLOOR

func _get_neighbor_terrain_for_neighbor_refresh(local_tile: Vector2i, dir: Vector2i) -> int:
	var neighbor_local: Vector2i = local_tile + dir
	if _is_inside(neighbor_local):
		return get_terrain_type_at(neighbor_local)
	var global_tile: Vector2i = _to_global_tile(neighbor_local)
	if _chunk_manager:
		var neighbor_chunk: Chunk = _chunk_manager.get_chunk_at_tile(global_tile)
		if neighbor_chunk:
			return neighbor_chunk.get_terrain_type_at(neighbor_chunk.global_to_local(global_tile))
	return _get_global_terrain(global_tile)

func _refresh_open_neighbors(local_tile: Vector2i) -> void:
	_refresh_open_tile(local_tile)
	for dir: Vector2i in ChunkVisualKernelScript._CARDINAL_DIRS:
		_refresh_open_tile(local_tile + dir)

func _refresh_open_tile(local_tile: Vector2i) -> void:
	if not _is_inside(local_tile):
		return
	var terrain_type: int = get_terrain_type_at(local_tile)
	if terrain_type != TileGenData.TerrainType.MINED_FLOOR and terrain_type != TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return
	_set_terrain_type(local_tile, _resolve_open_tile_type_for_neighbor_refresh(local_tile), false)

func _set_terrain_type(local_tile: Vector2i, terrain_type: int, mark_modified: bool = true) -> void:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _terrain_bytes.size():
		return
	var previous_type: int = _terrain_bytes[idx]
	if _cover_edge_class(previous_type) != _cover_edge_class(terrain_type):
		_invalidate_cover_edge_set_around(local_tile)
	_terrain_bytes[idx] = terrain_type
	if previous_type != terrain_type:
		_invalidate_prebaked_visual_payload()
		_bump_visual_invalidation_version()
	if not _has_mountain and _is_mountain_terrain(terrain_type):
		_has_mountain = true
	if mark_modified:
		mark_tile_modified(local_tile, {"terrain": terrain_type})
	else:
		_modified_tiles[local_tile] = {"terrain": terrain_type}

func _get_neighbor_terrain(local_tile: Vector2i) -> int:
	if _is_inside(local_tile):
		return get_terrain_type_at(local_tile)
	return _get_global_terrain(_to_global_tile(local_tile))

func _get_global_terrain(global_tile: Vector2i) -> int:
	if _use_operation_global_terrain_cache and _operation_global_terrain_cache.has(global_tile):
		return int(_operation_global_terrain_cache[global_tile])
	var terrain_type: int = TileGenData.TerrainType.GROUND
	if _chunk_manager:
		terrain_type = _chunk_manager.get_terrain_type_at_global(global_tile)
	elif WorldGenerator and WorldGenerator._is_initialized:
		terrain_type = WorldGenerator.get_tile_data(global_tile.x, global_tile.y).terrain
	if _use_operation_global_terrain_cache:
		_operation_global_terrain_cache[global_tile] = terrain_type
	return terrain_type

func _is_open_for_visual(terrain_type: int) -> bool:
	return terrain_type != TileGenData.TerrainType.ROCK

func _is_open_for_surface_rock_visual(terrain_type: int) -> bool:
	return _is_open_exterior(terrain_type) \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _is_open_for_surface_visual(terrain_type: int, water_only: bool) -> bool:
	if water_only:
		return _is_water_for_face_visual(terrain_type)
	return _is_open_for_surface_rock_visual(terrain_type)

func _cover_edge_class(terrain_type: int) -> int:
	if terrain_type == TileGenData.TerrainType.ROCK:
		return 0
	if terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return 1
	return 2

func _is_water_for_face_visual(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.WATER

func _is_open_exterior(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.WATER \
		or terrain_type == TileGenData.TerrainType.SAND \
		or terrain_type == TileGenData.TerrainType.GRASS

func _is_rock_at(local_tile: Vector2i) -> bool:
	return _is_inside(local_tile) and get_terrain_type_at(local_tile) == TileGenData.TerrainType.ROCK

func _should_blacken_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in ChunkVisualKernelScript._COVER_REVEAL_DIRS:
		var neighbor_type: int = _get_neighbor_terrain(local_tile + dir)
		if _is_open_exterior(neighbor_type):
			return false
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR \
		or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			return false
	return true

func _rebuild_cover_layer() -> void:
	if not _cover_layer:
		return
	_cover_layer.clear()
	_apply_visual_phase_for_tiles_now(ChunkVisualKernelScript.REDRAW_PHASE_COVER, _build_all_chunk_tiles())
	_reapply_local_zone_cover_state()

func refresh_cliffs() -> void:
	if not _cliff_layer:
		return
	_cliff_layer.clear()
	_apply_visual_phase_for_tiles_now(ChunkVisualKernelScript.REDRAW_PHASE_CLIFF, _build_all_chunk_tiles())

func _get_sun_direction() -> Vector2:
	if not TimeManager:
		return Vector2(0.0, -1.0)
	var angle: float = TimeManager.get_sun_angle()
	return Vector2(cos(angle), sin(angle))

func _is_cliff_exposed_to_surface(local_tile: Vector2i) -> bool:
	return _is_open_exterior(_get_neighbor_terrain(local_tile))

func _redraw_cliff_tile(local_tile: Vector2i) -> void:
	if not _cliff_layer or _is_underground:
		return
	_apply_single_tile_visual_phase(local_tile, ChunkVisualKernelScript.REDRAW_PHASE_CLIFF)

func _redraw_cover_tile(local_tile: Vector2i) -> void:
	# Underground z-levels don't use roof/cover system (ADR-0006).
	# Visibility handled by fog layer instead.
	if _is_underground or _cover_layer == null:
		return
	_apply_single_tile_visual_phase(local_tile, ChunkVisualKernelScript.REDRAW_PHASE_COVER)

func _cliff_overlay_kind(local_tile: Vector2i) -> int:
	return ChunkVisualKernelScript.cliff_overlay_kind(_build_single_tile_visual_request(local_tile), local_tile)

static func _resolve_effective_surface_palette_index(
	primary_biome_palette_index: int,
	secondary_biome_palette_index: int,
	ecotone_factor: float,
	global_x: int,
	global_y: int
) -> int:
	if secondary_biome_palette_index == primary_biome_palette_index:
		return primary_biome_palette_index
	var secondary_weight: float = _resolve_ecotone_secondary_weight(ecotone_factor)
	if secondary_weight <= 0.0:
		return primary_biome_palette_index
	var blend_noise: float = _sample_ecotone_blend_noise(global_x, global_y, ChunkVisualKernelScript._ECOTONE_BLEND_SCALE, ChunkVisualKernelScript._ECOTONE_BLEND_SEED)
	return secondary_biome_palette_index if blend_noise < secondary_weight else primary_biome_palette_index

static func _resolve_ecotone_secondary_weight(ecotone_factor: float) -> float:
	var normalized_factor: float = clampf(
		(ecotone_factor - ChunkVisualKernelScript._ECOTONE_BLEND_START) / maxf(0.001, 1.0 - ChunkVisualKernelScript._ECOTONE_BLEND_START),
		0.0,
		1.0
	)
	return 0.5 * _smoothstep01(normalized_factor)

static func _sample_ecotone_blend_noise(global_x: int, global_y: int, scale: float, seed: int) -> float:
	var resolved_scale: float = maxf(1.0, scale)
	var scaled_x: float = float(global_x) / resolved_scale
	var scaled_y: float = float(global_y) / resolved_scale
	var cell_x: int = floori(scaled_x)
	var cell_y: int = floori(scaled_y)
	var frac_x: float = _smoothstep01(scaled_x - float(cell_x))
	var frac_y: float = _smoothstep01(scaled_y - float(cell_y))
	var v00: float = _hash32_to_unit_float(_hash32_xy(cell_x, cell_y, seed))
	var v10: float = _hash32_to_unit_float(_hash32_xy(cell_x + 1, cell_y, seed))
	var v01: float = _hash32_to_unit_float(_hash32_xy(cell_x, cell_y + 1, seed))
	var v11: float = _hash32_to_unit_float(_hash32_xy(cell_x + 1, cell_y + 1, seed))
	return lerpf(lerpf(v00, v10, frac_x), lerpf(v01, v11, frac_x), frac_y)

## XOR-shift hash — no visible linear patterns.
static func _tile_hash_xy(tile_x: int, tile_y: int) -> int:
	return _hash32_xy(tile_x, tile_y, 0)

static func _tile_hash(pos: Vector2i) -> int:
	return _tile_hash_xy(pos.x, pos.y)

static func _hash32_xy(tile_x: int, tile_y: int, seed: int) -> int:
	var h: int = (tile_x * 374761393 + tile_y * 668265263 + seed * 1442695041) & ChunkVisualKernelScript._HASH32_MASK
	h = (h ^ (h >> 13)) & ChunkVisualKernelScript._HASH32_MASK
	h = (h * 1274126177) & ChunkVisualKernelScript._HASH32_MASK
	h = (h ^ (h >> 16)) & ChunkVisualKernelScript._HASH32_MASK
	return h

static func _interior_family_count(base_count: int) -> int:
	return maxi(1, mini(ChunkVisualKernelScript._INTERIOR_FAMILY_TARGET_COUNT, base_count))

static func _interior_family_window(base_count: int, family_index: int) -> Vector2i:
	var family_count: int = _interior_family_count(base_count)
	var clamped_family_index: int = clampi(family_index, 0, family_count - 1)
	var window_size: int = maxi(1, mini(base_count, ChunkVisualKernelScript._INTERIOR_FAMILY_WINDOW_SIZE))
	if base_count <= window_size or family_count <= 1:
		return Vector2i(0, base_count)
	var max_start: int = base_count - window_size
	var start: int = int(round(float(clamped_family_index * max_start) / float(family_count - 1)))
	return Vector2i(start, window_size)

static func _hash32_to_unit_float(h: int) -> float:
	return float(h & ChunkVisualKernelScript._HASH32_MASK) / float(ChunkVisualKernelScript._HASH32_MASK)

static func _smoothstep01(t: float) -> float:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	return clamped_t * clamped_t * (3.0 - 2.0 * clamped_t)

func _sample_interior_family_noise(global_x: int, global_y: int, scale: float, seed: int) -> float:
	return ChunkVisualKernelScript.sample_interior_family_noise(global_x, global_y, scale, seed)

func _resolve_interior_family(global_x: int, global_y: int, base_count: int) -> int:
	return ChunkVisualKernelScript.resolve_interior_family(global_x, global_y, base_count)

static func _shift_interior_family_base(base_index: int, family_window: Vector2i, step: int) -> int:
	if family_window.y <= 1:
		return family_window.x
	return family_window.x + ((base_index - family_window.x + step) % family_window.y)

func _raw_interior_variant(global_x: int, global_y: int, family_index: int, seed: int = ChunkVisualKernelScript._INTERIOR_VARIATION_SEED) -> Vector2i:
	var base_count: int = ChunkTilesetFactory.get_interior_base_variant_count()
	if base_count <= 0:
		return Vector2i.ZERO
	var family_window: Vector2i = _interior_family_window(base_count, family_index)
	var h: int = _hash32_xy(global_x, global_y, seed)
	return Vector2i(
		family_window.x + (h % family_window.y),
		(h >> 8) & (ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT - 1)
	)

static func _interior_variant_matches(a: Vector2i, b: Vector2i) -> bool:
	return a.x == b.x and a.y == b.y

func _resolve_interior_variant(global_x: int, global_y: int) -> Vector2i:
	return ChunkVisualKernelScript.resolve_interior_variant(global_x, global_y)

func _clear_interior_macro_layer() -> void:
	if _interior_macro_layer == null:
		return
	_interior_macro_layer.texture = null
	_interior_macro_layer.visible = false
	_interior_macro_dirty = false

func _mark_interior_macro_dirty() -> void:
	if not _INTERIOR_MACRO_ENABLED:
		return
	_interior_macro_dirty = true

func _refresh_interior_macro_layer_if_dirty() -> void:
	if not _INTERIOR_MACRO_ENABLED or not _interior_macro_dirty:
		return
	_refresh_interior_macro_layer()

func _refresh_interior_macro_layer() -> void:
	if not _INTERIOR_MACRO_ENABLED or _interior_macro_layer == null:
		return
	var tile_count: int = _chunk_size * _chunk_size
	var target_mask: PackedByteArray = PackedByteArray()
	target_mask.resize(tile_count)
	var has_targets: bool = false
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			if not _is_interior_macro_target(local_tile):
				continue
			target_mask[local_y * _chunk_size + local_x] = 1
			has_targets = true
	if not has_targets:
		_clear_interior_macro_layer()
		return
	var overlay: Dictionary = _build_interior_macro_overlay_native(target_mask)
	if overlay.is_empty():
		return
	if not bool(overlay.get("has_visible_pixels", false)):
		_clear_interior_macro_layer()
		return
	var sample_size: int = int(overlay.get("sample_size", 0))
	var pixels: PackedByteArray = overlay.get("pixels", PackedByteArray()) as PackedByteArray
	if sample_size <= 0 or pixels.size() != sample_size * sample_size * 4:
		var error_message: String = "Chunk._refresh_interior_macro_layer(): native interior macro overlay returned invalid RGBA payload for %s" % [chunk_coord]
		push_error(error_message)
		assert(false, error_message)
		_clear_interior_macro_layer()
		return
	var image: Image = Image.create_from_data(sample_size, sample_size, false, Image.FORMAT_RGBA8, pixels)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_interior_macro_layer.texture = texture
	_interior_macro_layer.scale = Vector2(
		float(_tile_size) / float(_INTERIOR_MACRO_SAMPLES_PER_TILE),
		float(_tile_size) / float(_INTERIOR_MACRO_SAMPLES_PER_TILE)
	)
	_interior_macro_layer.visible = true
	_interior_macro_dirty = false

func _build_interior_macro_overlay_native(target_mask: PackedByteArray) -> Dictionary:
	if not Chunk._has_native_visual_kernels():
		var missing_class_message: String = "Chunk runtime requires %s.build_interior_macro_overlay() for interior macro overlay. Build or load the world GDExtension before running the game." % [String(NATIVE_VISUAL_KERNELS_CLASS)]
		push_error(missing_class_message)
		assert(false, missing_class_message)
		return {}
	var helper: RefCounted = Chunk._get_native_visual_kernels()
	if helper == null or not helper.has_method("build_interior_macro_overlay"):
		var missing_method_message: String = "Chunk runtime requires %s.build_interior_macro_overlay() for interior macro overlay. Rebuild or reload the world GDExtension before running the game." % [String(NATIVE_VISUAL_KERNELS_CLASS)]
		push_error(missing_method_message)
		assert(false, missing_method_message)
		return {}
	var sand_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	var grass_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	var ground_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	if _biome != null:
		sand_color = _biome.sand_color
		grass_color = _biome.grass_color
		ground_color = _biome.ground_color
	return helper.call("build_interior_macro_overlay", {
		"chunk_coord": chunk_coord,
		"chunk_size": _chunk_size,
		"samples_per_tile": _INTERIOR_MACRO_SAMPLES_PER_TILE,
		"interior_base_variant_count": ChunkTilesetFactory.get_interior_base_variant_count(),
		"interior_target_mask": target_mask,
		"sand_color": sand_color,
		"grass_color": grass_color,
		"ground_color": ground_color,
	}) as Dictionary

func _is_interior_macro_target(local_tile: Vector2i) -> bool:
	var terrain_type: int = get_terrain_type_at(local_tile)
	if terrain_type == TileGenData.TerrainType.ROCK:
		if _is_underground:
			return _rock_visual_class(local_tile) == ChunkTilesetFactory.WALL_INTERIOR
		return _surface_rock_visual_class(local_tile) == ChunkTilesetFactory.WALL_INTERIOR
	if _is_underground:
		return false
	if not _is_surface_face_terrain(terrain_type):
		return false
	return not _has_water_face_neighbor(local_tile)

func _resolve_interior_macro_color(world_sample_x: int, world_sample_y: int, local_tile: Vector2i) -> Color:
	var global_tile: Vector2i = _to_global_tile(local_tile)
	var family_index: int = _resolve_interior_family(
		global_tile.x,
		global_tile.y,
		ChunkTilesetFactory.get_interior_base_variant_count()
	)
	var dust_bias: float = 1.0
	var moss_bias: float = 1.0
	var crack_bias: float = 1.0
	match family_index:
		0:
			dust_bias = 1.25
			moss_bias = 0.70
		1:
			dust_bias = 0.90
			crack_bias = 1.25
		2:
			moss_bias = 1.35
			dust_bias = 0.75
	var blended: Color = Color(0.0, 0.0, 0.0, 0.0)
	var dust_field: float = _sample_interior_family_noise(world_sample_x, world_sample_y, 44.0, _INTERIOR_MACRO_DUST_SEED)
	var dust_detail: float = _sample_interior_family_noise(world_sample_x, world_sample_y, 17.0, _INTERIOR_MACRO_DUST_SEED + 7)
	var dust_alpha: float = clampf((dust_field - 0.58) * 0.30 + maxf(0.0, dust_detail - 0.72) * 0.18, 0.0, 0.18) * dust_bias
	if dust_alpha > 0.01:
		blended = _alpha_blend_colors(
			blended,
			Color(_biome.sand_color.r, _biome.sand_color.g, _biome.sand_color.b, minf(0.22, dust_alpha))
		)
	var moss_field: float = _sample_interior_family_noise(world_sample_x, world_sample_y, 31.0, _INTERIOR_MACRO_MOSS_SEED)
	var moss_detail: float = _sample_interior_family_noise(world_sample_x, world_sample_y, 12.0, _INTERIOR_MACRO_MOSS_SEED + 9)
	var moss_alpha: float = clampf((moss_field - 0.66) * 0.34 + maxf(0.0, moss_detail - 0.74) * 0.10, 0.0, 0.16) * moss_bias
	if moss_alpha > 0.01:
		var moss_color: Color = _biome.grass_color.darkened(0.42)
		blended = _alpha_blend_colors(
			blended,
			Color(moss_color.r, moss_color.g, moss_color.b, minf(0.18, moss_alpha))
		)
	var crack_distance: float = absf(_sample_interior_family_noise(world_sample_x, world_sample_y, 14.0, _INTERIOR_MACRO_CRACK_SEED) - 0.5)
	var crack_support: float = _sample_interior_family_noise(world_sample_x, world_sample_y, 28.0, _INTERIOR_MACRO_CRACK_SEED + 13)
	if crack_support > 0.54 and crack_distance < 0.035:
		var crack_alpha: float = (0.035 - crack_distance) * 2.9 * crack_bias
		var crack_color: Color = _biome.ground_color.darkened(0.58)
		blended = _alpha_blend_colors(
			blended,
			Color(crack_color.r, crack_color.g, crack_color.b, minf(0.16, crack_alpha))
		)
	var pebble_gate: float = _sample_interior_family_noise(world_sample_x, world_sample_y, 9.0, _INTERIOR_MACRO_PEBBLE_SEED)
	if pebble_gate > 0.62 and (_hash32_xy(world_sample_x, world_sample_y, _INTERIOR_MACRO_PEBBLE_SEED + 19) & 7) == 0:
		var pebble_color: Color = _biome.ground_color.darkened(0.45)
		blended = _alpha_blend_colors(
			blended,
			Color(pebble_color.r, pebble_color.g, pebble_color.b, 0.12)
		)
	return blended

static func _alpha_blend_colors(base: Color, over: Color) -> Color:
	if over.a <= 0.0:
		return base
	var out_alpha: float = over.a + base.a * (1.0 - over.a)
	if out_alpha <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(
		(over.r * over.a + base.r * base.a * (1.0 - over.a)) / out_alpha,
		(over.g * over.a + base.g * base.a * (1.0 - over.a)) / out_alpha,
		(over.b * over.a + base.b * base.a * (1.0 - over.a)) / out_alpha,
		out_alpha
	)

## Returns [atlas_coords, alternative_tile_id].
func _apply_variant_full(base: Vector2i, local_tile: Vector2i, allow_flip: bool = true) -> Array:
	var gt: Vector2i = _to_global_tile(local_tile)
	var atlas: Vector2i = _resolve_variant_atlas(base, gt.x, gt.y)
	var alt_id: int = _resolve_variant_alt_id(base, gt.x, gt.y, allow_flip)
	return [atlas, alt_id]

func _apply_variant(base: Vector2i, local_tile: Vector2i) -> Vector2i:
	return _apply_variant_full(base, local_tile)[0]

func _resolve_variant_atlas(base: Vector2i, global_x: int, global_y: int) -> Vector2i:
	return ChunkVisualKernelScript.resolve_variant_atlas(base, global_x, global_y)

func _resolve_variant_alt_id(base: Vector2i, global_x: int, global_y: int, allow_flip: bool) -> int:
	return ChunkVisualKernelScript.resolve_variant_alt_id(base, global_x, global_y, allow_flip)

func _rock_visual_class(local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.rock_visual_class(_build_single_tile_visual_request(local_tile), local_tile)

func _rock_atlas(local_tile: Vector2i) -> Vector2i:
	if _is_surface_rock(local_tile):
		return ChunkTilesetFactory.TILE_ROCK
	return ChunkTilesetFactory.TILE_ROCK_INTERIOR

func _cover_rock_atlas(local_tile: Vector2i) -> Vector2i:
	return ChunkVisualKernelScript.cover_rock_atlas(_build_single_tile_visual_request(local_tile), local_tile)

func _is_cave_edge_rock(local_tile: Vector2i) -> bool:
	return ChunkVisualKernelScript.is_cave_edge_rock(_build_single_tile_visual_request(local_tile), local_tile)

func _is_exterior_surface_rock(local_tile: Vector2i) -> bool:
	return ChunkVisualKernelScript.is_exterior_surface_rock(_build_single_tile_visual_request(local_tile), local_tile)

func _is_surface_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in ChunkVisualKernelScript._COVER_REVEAL_DIRS:
		var neighbor_type: int = _get_neighbor_terrain(local_tile + dir)
		if _is_open_exterior(neighbor_type):
			return true
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			return true
	return false

func _height_at(local_tile: Vector2i) -> float:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _height_bytes.size():
		return 0.5
	return _height_bytes[idx]

func _variation_at(local_tile: Vector2i) -> int:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _variation_bytes.size():
		return ChunkTilesetFactory.SURFACE_VARIATION_NONE
	return _variation_bytes[idx]

func _primary_biome_palette_index_at(local_tile: Vector2i) -> int:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _biome_bytes.size():
		return _default_biome_palette_index()
	return int(_biome_bytes[idx])

func _secondary_biome_palette_index_at(local_tile: Vector2i) -> int:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _secondary_biome_bytes.size():
		return _primary_biome_palette_index_at(local_tile)
	return int(_secondary_biome_bytes[idx])

func _ecotone_factor_at(local_tile: Vector2i) -> float:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _ecotone_values.size():
		return 0.0
	return float(_ecotone_values[idx])

func _biome_palette_index_at(local_tile: Vector2i) -> int:
	var global_tile: Vector2i = _to_global_tile(local_tile)
	return Chunk._resolve_effective_surface_palette_index(
		_primary_biome_palette_index_at(local_tile),
		_secondary_biome_palette_index_at(local_tile),
		_ecotone_factor_at(local_tile),
		global_tile.x,
		global_tile.y
	)

static func _default_biome_palette_index() -> int:
	return BiomeRegistry.get_default_palette_index() if BiomeRegistry else 0

func _cache_has_mountain() -> void:
	_has_mountain = false
	for terrain_type: int in _terrain_bytes:
		if _is_mountain_terrain(terrain_type):
			_has_mountain = true
			return

func _is_mountain_terrain(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.ROCK \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _is_inside(local_tile: Vector2i) -> bool:
	return local_tile.x >= 0 and local_tile.y >= 0 and local_tile.x < _chunk_size and local_tile.y < _chunk_size

func _to_global_tile(local_tile: Vector2i) -> Vector2i:
	if _wg_has_chunk_local_to_tile and WorldGenerator:
		return WorldGenerator.chunk_local_to_tile(chunk_coord, local_tile)
	return Vector2i(
		chunk_coord.x * _chunk_size + local_tile.x,
		chunk_coord.y * _chunk_size + local_tile.y
	)

func _collect_mining_dirty_tiles(local_tile: Vector2i) -> Dictionary:
	var dirty_tiles: Dictionary = {}
	for offset_x: int in range(-1, 2):
		for offset_y: int in range(-1, 2):
			var tile: Vector2i = local_tile + Vector2i(offset_x, offset_y)
			if _is_inside(tile):
				dirty_tiles[tile] = true
	return dirty_tiles

func _blocks_from_surface(local_tile: Vector2i) -> bool:
	var neighbor_type: int = _get_neighbor_terrain(local_tile)
	return neighbor_type == TileGenData.TerrainType.GROUND \
		or neighbor_type == TileGenData.TerrainType.WATER \
		or neighbor_type == TileGenData.TerrainType.SAND \
		or neighbor_type == TileGenData.TerrainType.GRASS

func _resolve_redraw_tile_budget(max_rows: int) -> int:
	var row_budget: int = maxi(1, max_rows) * _chunk_size
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, mini(row_budget, WorldGenerator.balance.chunk_redraw_tiles_per_step))
	return row_budget

func _resolve_redraw_phase_tile_budget(max_rows: int) -> int:
	var base_budget: int = _resolve_redraw_tile_budget(max_rows)
	match _redraw_phase:
		ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN:
			return maxi(1, base_budget / 2)
		ChunkVisualKernelScript.REDRAW_PHASE_COVER, ChunkVisualKernelScript.REDRAW_PHASE_FLORA, ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_INTERIOR, ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_COLLISION:
			return maxi(1, base_budget / 2)
		_:
			return base_budget

func _build_revealed_local_cover_tiles(zone_tiles: Dictionary) -> Dictionary:
	var reveal_tiles: Dictionary = {}
	if zone_tiles.is_empty():
		return reveal_tiles
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			var global_tile: Vector2i = _to_global_tile(local_tile)
			if zone_tiles.has(global_tile):
				reveal_tiles[local_tile] = true
				continue
			if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
				continue
			if not _is_cave_edge_rock(local_tile):
				continue
			for dir: Vector2i in ChunkVisualKernelScript._COVER_REVEAL_DIRS:
				var neighbor_tile: Vector2i = WorldGenerator.offset_tile(global_tile, dir) if WorldGenerator else global_tile + dir
				if zone_tiles.has(neighbor_tile):
					reveal_tiles[local_tile] = true
					break
	return reveal_tiles

func _apply_local_zone_cover_state(next_cover_tiles: Dictionary) -> bool:
	var cover_state_changed: bool = false
	if not _cover_layer:
		return _replace_revealed_local_cover_tiles(next_cover_tiles)
	for tile_index: int in range(_revealed_local_cover_tiles.size()):
		if _revealed_local_cover_tiles[tile_index] == 0:
			continue
		var local_tile: Vector2i = _tile_from_index(tile_index)
		if next_cover_tiles.has(local_tile):
			continue
		_redraw_cover_tile(local_tile)
		cover_state_changed = true
	for local_tile: Vector2i in next_cover_tiles:
		if _has_revealed_local_cover_tile(local_tile):
			continue
		_cover_layer.erase_cell(local_tile)
		cover_state_changed = true
	cover_state_changed = _replace_revealed_local_cover_tiles(next_cover_tiles) or cover_state_changed
	return cover_state_changed

func _apply_local_zone_cover_state_delta(
	next_cover_tiles: Dictionary,
	changed_tiles: Dictionary,
	commit_full_state: bool = true
) -> bool:
	if not _cover_layer:
		return _commit_local_zone_cover_state_delta(next_cover_tiles, changed_tiles, commit_full_state)
	var cover_state_changed: bool = false
	for local_tile: Vector2i in changed_tiles:
		var was_revealed: bool = _has_revealed_local_cover_tile(local_tile)
		var should_be_revealed: bool = next_cover_tiles.has(local_tile)
		if was_revealed == should_be_revealed:
			continue
		cover_state_changed = true
		if should_be_revealed:
			_cover_layer.erase_cell(local_tile)
		else:
			_redraw_cover_tile(local_tile)
	return _commit_local_zone_cover_state_delta(next_cover_tiles, changed_tiles, commit_full_state) \
		or cover_state_changed

func _commit_local_zone_cover_state_delta(
	next_cover_tiles: Dictionary,
	changed_tiles: Dictionary,
	commit_full_state: bool
) -> bool:
	if commit_full_state:
		return _replace_revealed_local_cover_tiles(next_cover_tiles)
	var cover_state_changed: bool = false
	for local_tile: Vector2i in changed_tiles:
		var was_revealed: bool = _has_revealed_local_cover_tile(local_tile)
		_set_revealed_local_cover_tile(local_tile, next_cover_tiles.has(local_tile))
		if was_revealed != next_cover_tiles.has(local_tile):
			cover_state_changed = true
	return cover_state_changed

func _reapply_local_zone_cover_state() -> void:
	if not _cover_layer or _revealed_local_cover_tile_count <= 0:
		return
	for tile_index: int in range(_revealed_local_cover_tiles.size()):
		if _revealed_local_cover_tiles[tile_index] == 0:
			continue
		_cover_layer.erase_cell(_tile_from_index(tile_index))

func _reapply_local_zone_cover_state_for_tiles(tile_map: Dictionary) -> void:
	if not _cover_layer or _revealed_local_cover_tile_count <= 0 or tile_map.is_empty():
		return
	for local_tile: Vector2i in tile_map:
		if _has_revealed_local_cover_tile(local_tile):
			_cover_layer.erase_cell(local_tile)

func _reapply_local_zone_cover_state_for_tile_list(tiles: Array) -> void:
	if not _cover_layer or _revealed_local_cover_tile_count <= 0 or tiles.is_empty():
		return
	for tile_variant: Variant in tiles:
		var local_tile: Vector2i = tile_variant as Vector2i
		if _has_revealed_local_cover_tile(local_tile):
			_cover_layer.erase_cell(local_tile)

func _reapply_local_zone_cover_state_for_mining_patch(center_tile: Vector2i) -> void:
	if not _cover_layer or _revealed_local_cover_tile_count <= 0:
		return
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var local_tile: Vector2i = center_tile + Vector2i(offset_x, offset_y)
			if not _is_inside(local_tile):
				continue
			if _has_revealed_local_cover_tile(local_tile):
				_cover_layer.erase_cell(local_tile)

func _reapply_local_zone_cover_state_for_index_range(start_index: int, end_index: int) -> void:
	if not _cover_layer or _revealed_local_cover_tile_count <= 0:
		return
	for tile_index: int in range(start_index, end_index):
		if tile_index < 0 or tile_index >= _revealed_local_cover_tiles.size():
			continue
		if _revealed_local_cover_tiles[tile_index] != 0:
			_cover_layer.erase_cell(_tile_from_index(tile_index))

func get_redraw_phase_name() -> StringName:
	match _redraw_phase:
		ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN:
			return &"terrain"
		ChunkVisualKernelScript.REDRAW_PHASE_COVER:
			return &"cover"
		ChunkVisualKernelScript.REDRAW_PHASE_CLIFF:
			return &"cliff"
		ChunkVisualKernelScript.REDRAW_PHASE_FLORA:
			return &"flora"
		ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_INTERIOR:
			return &"debug_interior"
		ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_COLLISION:
			return &"debug_collision"
		_:
			return &"done"

func _process_redraw_phase_tiles(tile_budget: int) -> int:
	var total_tiles: int = _chunk_size * _chunk_size
	var start_index: int = _redraw_tile_index
	if _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_FLORA:
		_apply_flora_render_packet(_build_flora_render_packet(), &"batched_renderer")
		_redraw_tile_index = total_tiles
		return total_tiles - start_index
	if _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_COVER \
		or _redraw_phase == ChunkVisualKernelScript.REDRAW_PHASE_CLIFF:
		var processed: int = 0
		var phase_started_usec: int = Time.get_ticks_usec()
		while processed < tile_budget and _redraw_tile_index < total_tiles:
			var remaining: int = tile_budget - processed
			var batch: Dictionary = build_visual_phase_batch(remaining)
			if batch.is_empty():
				break
			var computed_batch: Dictionary = Chunk.compute_visual_batch(batch)
			var applied_start: int = _redraw_tile_index
			if not apply_visual_phase_batch(computed_batch):
				break
			processed += _redraw_tile_index - applied_start
			if Time.get_ticks_usec() - phase_started_usec >= REDRAW_TIME_BUDGET_USEC:
				break
		return processed
	var end_index: int = mini(_redraw_tile_index + tile_budget, total_tiles)
	var processed_end_index: int = start_index
	var started_usec: int = Time.get_ticks_usec()
	for tile_index: int in range(start_index, end_index):
		var local_tile: Vector2i = _tile_from_index(tile_index)
		match _redraw_phase:
			ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_INTERIOR:
				_process_debug_marker_tile(local_tile, false)
			ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_COLLISION:
				_process_debug_marker_tile(local_tile, true)
			_:
				break
		processed_end_index = tile_index + 1
		## Hard time guard: check every 4 tiles (terrain/cover/cliff) or every tile (flora/debug).
		## No end_index bypass — budget must be respected even if tile_budget allows more.
		var tiles_done: int = processed_end_index - start_index
		var check_interval: int = 4
		if tiles_done % check_interval == 0:
			if Time.get_ticks_usec() - started_usec >= REDRAW_TIME_BUDGET_USEC:
				break
	var processed: int = processed_end_index - start_index
	_redraw_tile_index = processed_end_index
	return processed

func set_flora_result(result: ChunkFloraResultScript) -> void:
	if _flora_presenter != null:
		_flora_presenter.set_flora_result(result)

func set_flora_payload(payload: Dictionary) -> void:
	if _flora_presenter != null:
		_flora_presenter.set_flora_payload(payload)

func _build_flora_render_packet() -> Dictionary:
	return _flora_presenter.build_render_packet() if _flora_presenter != null else {}

func _clear_flora_renderer() -> void:
	if _flora_presenter != null:
		_flora_presenter.clear_render_packet()

func _apply_flora_render_packet(packet: Dictionary, mode: StringName) -> void:
	if _flora_presenter != null:
		_flora_presenter.apply_render_packet(packet, mode, chunk_coord)

func _ensure_flora_payload() -> Dictionary:
	return _flora_presenter.ensure_payload() if _flora_presenter != null else {}

func _get_prebuilt_flora_render_packet(payload: Dictionary) -> Dictionary:
	return _flora_presenter.get_prebuilt_render_packet(payload) if _flora_presenter != null else {}

func _advance_redraw_phase() -> void:
	match _redraw_phase:
		ChunkVisualKernelScript.REDRAW_PHASE_TERRAIN:
			_mark_interior_macro_dirty()
			_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_COVER
		ChunkVisualKernelScript.REDRAW_PHASE_COVER:
			_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_CLIFF
		ChunkVisualKernelScript.REDRAW_PHASE_CLIFF:
			_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_FLORA
		ChunkVisualKernelScript.REDRAW_PHASE_FLORA:
			if _should_build_debug_markers():
				_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_INTERIOR
			else:
				_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_DONE
		ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_INTERIOR:
			_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_COLLISION
		ChunkVisualKernelScript.REDRAW_PHASE_DEBUG_COLLISION:
			_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_DONE
		_:
			_redraw_phase = ChunkVisualKernelScript.REDRAW_PHASE_DONE
	_redraw_tile_index = 0

func _clear_debug_markers() -> void:
	if _debug_renderer != null:
		_debug_renderer.clear_markers()

func _should_build_debug_markers() -> bool:
	return WorldGenerator != null \
		and WorldGenerator.balance != null \
		and WorldGenerator.balance.mountain_debug_visualization

func _process_debug_marker_tile(local_tile: Vector2i, collision_only: bool) -> void:
	if collision_only:
		if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
			return
		if _blocks_from_surface(local_tile + Vector2i.UP):
			_add_debug_rect(local_tile, Vector2(0.0, -_tile_size * 0.45), Vector2(_tile_size - 6, 4), WorldGenerator.balance.mountain_debug_collision_color)
		if _blocks_from_surface(local_tile + Vector2i.DOWN):
			_add_debug_rect(local_tile, Vector2(0.0, _tile_size * 0.45), Vector2(_tile_size - 6, 4), WorldGenerator.balance.mountain_debug_collision_color)
		if _blocks_from_surface(local_tile + Vector2i.LEFT):
			_add_debug_rect(local_tile, Vector2(-_tile_size * 0.45, 0.0), Vector2(4, _tile_size - 6), WorldGenerator.balance.mountain_debug_collision_color)
		if _blocks_from_surface(local_tile + Vector2i.RIGHT):
			_add_debug_rect(local_tile, Vector2(_tile_size * 0.45, 0.0), Vector2(4, _tile_size - 6), WorldGenerator.balance.mountain_debug_collision_color)
		return
	var terrain_type: int = get_terrain_type_at(local_tile)
	if terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		_add_debug_rect(local_tile, Vector2.ZERO, Vector2(_tile_size - 18, _tile_size - 18), WorldGenerator.balance.mountain_debug_entrance_color)
	elif terrain_type == TileGenData.TerrainType.MINED_FLOOR:
		_add_debug_rect(local_tile, Vector2.ZERO, Vector2(_tile_size - 24, _tile_size - 24), WorldGenerator.balance.mountain_debug_mined_color)

func _tile_from_index(tile_index: int) -> Vector2i:
	return Vector2i(tile_index % _chunk_size, tile_index / _chunk_size)

func _rebuild_debug_markers() -> void:
	if not WorldGenerator or not WorldGenerator.balance or not WorldGenerator.balance.mountain_debug_visualization:
		return
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			var terrain_type: int = get_terrain_type_at(local_tile)
			if terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
				_add_debug_rect(local_tile, Vector2.ZERO, Vector2(_tile_size - 18, _tile_size - 18), WorldGenerator.balance.mountain_debug_entrance_color)
			elif terrain_type == TileGenData.TerrainType.MINED_FLOOR:
				_add_debug_rect(local_tile, Vector2.ZERO, Vector2(_tile_size - 24, _tile_size - 24), WorldGenerator.balance.mountain_debug_mined_color)
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
				continue
			if _blocks_from_surface(local_tile + Vector2i.UP):
				_add_debug_rect(local_tile, Vector2(0.0, -_tile_size * 0.45), Vector2(_tile_size - 6, 4), WorldGenerator.balance.mountain_debug_collision_color)
			if _blocks_from_surface(local_tile + Vector2i.DOWN):
				_add_debug_rect(local_tile, Vector2(0.0, _tile_size * 0.45), Vector2(_tile_size - 6, 4), WorldGenerator.balance.mountain_debug_collision_color)
			if _blocks_from_surface(local_tile + Vector2i.LEFT):
				_add_debug_rect(local_tile, Vector2(-_tile_size * 0.45, 0.0), Vector2(4, _tile_size - 6), WorldGenerator.balance.mountain_debug_collision_color)
			if _blocks_from_surface(local_tile + Vector2i.RIGHT):
				_add_debug_rect(local_tile, Vector2(_tile_size * 0.45, 0.0), Vector2(4, _tile_size - 6), WorldGenerator.balance.mountain_debug_collision_color)

func _add_debug_rect(local_tile: Vector2i, offset: Vector2, size: Vector2, color: Color) -> void:
	var center: Vector2 = Vector2(
		local_tile.x * _tile_size + _tile_size * 0.5,
		local_tile.y * _tile_size + _tile_size * 0.5
	) + offset
	_add_debug_world_rect(center, size, color)

func _add_debug_world_rect(center: Vector2, size: Vector2, color: Color) -> void:
	if _debug_renderer != null:
		_debug_renderer.add_world_rect(center, size, color)
