class_name Chunk
extends Node2D

const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")

## Один чанк мира.
## Хранит terrain-данные, exterior shell cover и локальные модификации.

const REDRAW_PHASE_TERRAIN: int = 0
const REDRAW_PHASE_COVER: int = 1
const REDRAW_PHASE_CLIFF: int = 2
const REDRAW_PHASE_FLORA: int = 3
const REDRAW_PHASE_DEBUG_INTERIOR: int = 4
const REDRAW_PHASE_DEBUG_COLLISION: int = 5
const REDRAW_PHASE_DONE: int = 6

enum ChunkVisualState {
	UNINITIALIZED,
	NATIVE_READY,
	PROXY_READY,
	TERRAIN_READY,
	FULL_PENDING,
	FULL_READY,
}

const REDRAW_TIME_BUDGET_USEC: int = 2500
const _CARDINAL_DIRS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]
const _INTERIOR_FAMILY_TARGET_COUNT: int = 3
const _INTERIOR_FAMILY_WINDOW_SIZE: int = 3
const _INTERIOR_FAMILY_SCALE: float = 18.0
const _INTERIOR_FAMILY_DETAIL_SCALE: float = 9.0
const _INTERIOR_FAMILY_SEED: int = 13183
const _INTERIOR_VARIATION_SEED: int = 12345
const _INTERIOR_REHASH_SEED: int = 12442
const _INTERIOR_MACRO_ENABLED: bool = false
const _INTERIOR_MACRO_SAMPLES_PER_TILE: int = 1
const _INTERIOR_MACRO_DUST_SEED: int = 16001
const _INTERIOR_MACRO_MOSS_SEED: int = 16057
const _INTERIOR_MACRO_CRACK_SEED: int = 16111
const _INTERIOR_MACRO_PEBBLE_SEED: int = 16183
const _HASH32_MASK: int = 0xffffffff
const _COVER_REVEAL_DIRS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1),
]
const VISUAL_BATCH_MODE_PHASE: StringName = &"phase"
const VISUAL_BATCH_MODE_DIRTY: StringName = &"dirty"
const VISUAL_COMMAND_OP_SET: int = 0
const VISUAL_COMMAND_OP_ERASE: int = 1
const VISUAL_APPLY_BUFFER_STRIDE: int = 7
const VISUAL_LAYER_TERRAIN: int = 0
const VISUAL_LAYER_GROUND_FACE: int = 1
const VISUAL_LAYER_ROCK: int = 2
const VISUAL_LAYER_COVER: int = 3
const VISUAL_LAYER_CLIFF: int = 4
const VISUAL_COMMAND_BUFFER_STRIDE: int = 8
const FLORA_PUBLISH_LOG_ARG: String = "codex_flora_publish_log"
const NATIVE_VISUAL_KERNELS_CLASS: StringName = &"ChunkVisualKernels"

class FloraBatchRenderer:
	extends Node2D

	var _layers: Array = []

	func clear_render_packet() -> void:
		_layers.clear()
		visible = false
		queue_redraw()

	func set_render_packet(packet: Dictionary) -> void:
		_layers = (packet.get("layers", []) as Array).duplicate(true)
		visible = not _layers.is_empty()
		queue_redraw()

	func _draw() -> void:
		for layer_variant: Variant in _layers:
			var layer: Dictionary = layer_variant as Dictionary
			for item_variant: Variant in layer.get("items", []):
				var item: Dictionary = item_variant as Dictionary
				draw_rect(
					Rect2(
						item.get("position", Vector2.ZERO) as Vector2,
						item.get("size", Vector2.ZERO) as Vector2
					),
					item.get("color", Color.WHITE) as Color,
					true
				)

var chunk_coord: Vector2i = Vector2i.ZERO
var is_loaded: bool = false
var is_dirty: bool = false

var _terrain_layer: TileMapLayer = null
var _ground_face_layer: TileMapLayer = null
var _rock_layer: TileMapLayer = null
var _interior_macro_layer: Sprite2D = null
var _cover_layer: TileMapLayer = null
var _cliff_layer: TileMapLayer = null
var _fog_layer: TileMapLayer = null
var _flora_renderer: FloraBatchRenderer = null
var _flora_result: ChunkFloraResultScript = null
var _flora_payload: Dictionary = {}
var _debug_root: Node2D = null
var _tile_size: int = 64
var _chunk_size: int = 64
var _terrain_tileset: TileSet = null
var _overlay_tileset: TileSet = null
var _chunk_manager: ChunkManager = null
var _modified_tiles: Dictionary = {}
var _biome: BiomeData = null
var _terrain_bytes: PackedByteArray = PackedByteArray()
var _height_bytes: PackedFloat32Array = PackedFloat32Array()
var _variation_bytes: PackedByteArray = PackedByteArray()
var _biome_bytes: PackedByteArray = PackedByteArray()
var _has_mountain: bool = false
var _redraw_phase: int = REDRAW_PHASE_DONE
var _redraw_tile_index: int = 0
var _pending_border_dirty: Dictionary = {}
var _revealed_local_cover_tiles: Dictionary = {}
var _is_underground: bool = false
var _use_operation_global_terrain_cache: bool = false
var _operation_global_terrain_cache: Dictionary = {}
var _mining_write_authorized: bool = false
var _visual_state: int = ChunkVisualState.UNINITIALIZED
var _has_full_publication_once: bool = false
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
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	sync_display_position(chunk_coord)
	_terrain_layer = _create_layer("Terrain", _terrain_tileset, -12)
	_ground_face_layer = _create_layer("GroundFaces", _terrain_tileset, -11)
	_rock_layer = _create_layer("Rock", _terrain_tileset, -10)
	if _INTERIOR_MACRO_ENABLED:
		_interior_macro_layer = _create_interior_macro_layer("InteriorMacro", -9)
	_cliff_layer = _create_layer("Cliffs", _overlay_tileset, -9)
	_cover_layer = _create_layer("MountainCover", _terrain_tileset, 6)
	_flora_renderer = FloraBatchRenderer.new()
	_flora_renderer.name = "Flora"
	_flora_renderer.z_index = -5
	add_child(_flora_renderer)
	_debug_root = Node2D.new()
	_debug_root.name = "DebugRoot"
	_debug_root.z_index = 50
	add_child(_debug_root)

func sync_display_position(reference_chunk: Vector2i) -> void:
	var display_chunk: Vector2i = chunk_coord
	if WorldGenerator and WorldGenerator._is_initialized:
		display_chunk = WorldGenerator.get_display_chunk_coord(chunk_coord, reference_chunk)
	var chunk_pixels: int = _chunk_size * _tile_size
	position = Vector2(display_chunk.x * chunk_pixels, display_chunk.y * chunk_pixels)

func populate_native(native_data: Dictionary, saved_modifications: Dictionary, instant: bool = false) -> void:
	_modified_tiles = saved_modifications.duplicate()
	_terrain_bytes = native_data.get("terrain", PackedByteArray())
	_height_bytes = native_data.get("height", PackedFloat32Array())
	_variation_bytes = native_data.get("variation", PackedByteArray())
	_biome_bytes = native_data.get("biome", PackedByteArray())
	_flora_result = null
	_flora_payload = {}
	_has_full_publication_once = false
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
		_biome_bytes.fill(0)
	_apply_saved_modifications()
	_cache_has_mountain()
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
	if _redraw_phase != REDRAW_PHASE_TERRAIN:
		return
	var batch: Dictionary = build_visual_phase_batch(_chunk_size * _chunk_size)
	if batch.is_empty():
		return
	var computed_batch: Dictionary = Chunk.compute_visual_batch(batch)
	apply_visual_phase_batch(computed_batch)

func global_to_local(global_tile: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("tile_to_local_in_chunk"):
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

func set_revealed_local_cover_tiles(cover_tiles: Dictionary) -> void:
	_apply_local_zone_cover_state(cover_tiles)

func set_mining_write_authorized(value: bool) -> void:
	_mining_write_authorized = value

# --- Underground Fog of War ---

## Mark this chunk as underground. Must be called BEFORE redraw.
func set_underground(value: bool) -> void:
	_is_underground = value

## Initialize fog layer for underground chunks. Fills all tiles with UNSEEN.
func init_fog_layer(fog_tileset: TileSet) -> void:
	if _fog_layer:
		return
	_fog_layer = TileMapLayer.new()
	_fog_layer.name = "FogLayer"
	_fog_layer.tile_set = fog_tileset
	_fog_layer.z_index = 7  # Above cover_layer(6), below debug(50)
	add_child(_fog_layer)
	# Fill with UNSEEN
	for y: int in range(_chunk_size):
		for x: int in range(_chunk_size):
			_fog_layer.set_cell(
				Vector2i(x, y),
				ChunkTilesetFactory.FOG_SOURCE_ID,
				ChunkTilesetFactory.TILE_FOG_UNSEEN
			)

## Erase fog for tiles that are currently visible (player nearby).
## Also redraws terrain to update wall variants with current neighbor data.
func apply_fog_visible(visible_locals: Dictionary) -> void:
	if not _fog_layer:
		return
	for local: Vector2i in visible_locals:
		if _is_inside(local):
			_fog_layer.erase_cell(local)
			_redraw_terrain_tile(local)

## Set DISCOVERED fog tile for tiles that were visible but player moved away.
func apply_fog_discovered(discovered_locals: Dictionary) -> void:
	if not _fog_layer:
		return
	for local: Vector2i in discovered_locals:
		if _is_inside(local):
			_fog_layer.set_cell(
				local,
				ChunkTilesetFactory.FOG_SOURCE_ID,
				ChunkTilesetFactory.TILE_FOG_DISCOVERED
			)

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
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	var new_type: int = _resolve_open_tile_type(local)
	_set_terrain_type(local, new_type)
	# ChunkManager redraws the local patch after neighbor normalization so mining
	# does not pay for two overlapping same-chunk redraw passes.
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache
	WorldPerfProbe.end("Chunk.try_mine_at %s" % [chunk_coord], started_usec)
	return {"old_type": old_type, "new_type": new_type}

func redraw_mining_patch(local_tile: Vector2i) -> void:
	var dirty_tiles: Dictionary = _collect_mining_dirty_tiles(local_tile)
	if dirty_tiles.is_empty():
		return
	enqueue_dirty_border_redraw(dirty_tiles)

func cleanup() -> void:
	is_loaded = false
	_terrain_bytes = PackedByteArray()
	_height_bytes = PackedFloat32Array()
	_variation_bytes = PackedByteArray()
	_biome_bytes = PackedByteArray()
	_revealed_local_cover_tiles = {}
	_interior_macro_dirty = false
	_clear_interior_macro_layer()
	_visual_state = ChunkVisualState.UNINITIALIZED
	_has_full_publication_once = false

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
		for dir: Vector2i in _CARDINAL_DIRS:
			var neighbor_tile: Vector2i = tile_pos + dir
			if _is_inside(neighbor_tile):
				tiles_to_refresh[neighbor_tile] = true
	for tile_pos: Vector2i in tiles_to_refresh:
		_refresh_open_tile(tile_pos)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache

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
	for child: Node in _debug_root.get_children():
		child.queue_free()
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var tile := Vector2i(local_x, local_y)
			_redraw_terrain_tile(tile)
			_redraw_cover_tile(tile)
			_redraw_cliff_tile(tile)
	_refresh_interior_macro_layer()
	_rebuild_debug_markers()
	if include_flora:
		_apply_flora_render_packet(_build_flora_render_packet(), &"batched_renderer")
		_redraw_phase = REDRAW_PHASE_DONE
	else:
		## Flora is deferred to progressive redraw. Set phase to FLORA so
		## progressive path can draw flora without re-doing terrain/cover/cliff.
		_redraw_phase = REDRAW_PHASE_FLORA
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
	for child: Node in _debug_root.get_children():
		child.queue_free()
	_redraw_phase = REDRAW_PHASE_TERRAIN
	_redraw_tile_index = 0
	_mark_visual_native_ready()

func is_redraw_complete() -> bool:
	return _redraw_phase == REDRAW_PHASE_DONE

func is_first_pass_ready() -> bool:
	return _visual_state == ChunkVisualState.TERRAIN_READY \
		or _visual_state == ChunkVisualState.FULL_PENDING \
		or _visual_state == ChunkVisualState.FULL_READY

func is_full_redraw_ready() -> bool:
	return _visual_state == ChunkVisualState.FULL_READY

func _is_visibility_publication_ready() -> bool:
	return _has_full_publication_once or is_full_redraw_ready()

func needs_full_redraw() -> bool:
	return _visual_state == ChunkVisualState.TERRAIN_READY \
		or _visual_state == ChunkVisualState.FULL_PENDING

func is_terrain_phase_done() -> bool:
	return _redraw_phase > REDRAW_PHASE_TERRAIN

## True when terrain + cover + cliff are complete. Flora and debug phases
## are NOT required — they are cosmetic/debug and must not block boot gates.
func is_gameplay_redraw_complete() -> bool:
	return _redraw_phase >= REDRAW_PHASE_FLORA

func is_flora_phase_done() -> bool:
	return _redraw_phase > REDRAW_PHASE_FLORA

func continue_redraw(max_rows: int) -> bool:
	if _redraw_phase == REDRAW_PHASE_DONE:
		_sync_visual_state_after_redraw_mutation()
		return true
	while _redraw_phase != REDRAW_PHASE_DONE:
		if _redraw_phase == REDRAW_PHASE_DEBUG_INTERIOR or _redraw_phase == REDRAW_PHASE_DEBUG_COLLISION:
			if not _should_build_debug_markers():
				_advance_redraw_phase()
				continue
		var processed_phase: int = _redraw_phase
		var phase_start_index: int = _redraw_tile_index
		var processed: int = _process_redraw_phase_tiles(_resolve_redraw_phase_tile_budget(max_rows))
		if processed <= 0:
			_advance_redraw_phase()
			continue
		if processed_phase == REDRAW_PHASE_COVER:
			_reapply_local_zone_cover_state_for_index_range(phase_start_index, _redraw_tile_index)
		if _redraw_tile_index >= _chunk_size * _chunk_size:
			_advance_redraw_phase()
		_sync_visual_state_after_redraw_mutation()
		return _redraw_phase == REDRAW_PHASE_DONE
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
	_has_full_publication_once = true

func _can_publish_full_redraw_ready() -> bool:
	return is_first_pass_ready() \
		and _redraw_phase == REDRAW_PHASE_DONE \
		and _pending_border_dirty.is_empty()

func _sync_visual_state_after_redraw_mutation() -> void:
	if _redraw_phase > REDRAW_PHASE_COVER:
		_mark_visual_first_pass_ready()

func _redraw_dynamic_visibility(_dirty_tiles: Dictionary) -> void:
	_rebuild_cover_layer()
	_reapply_local_zone_cover_state()
	if WorldGenerator and WorldGenerator.balance and WorldGenerator.balance.mountain_debug_visualization:
		for child: Node in _debug_root.get_children():
			child.queue_free()
		_rebuild_debug_markers()

## Enqueue border tiles for deferred redraw. Called by ChunkManager when a
## new neighbor chunk is loaded and border seam tiles need updating.
## The actual redraw happens during the next progressive redraw tick.
## (boot_fast_first_playable_spec Iteration 3, change 3A)
func enqueue_dirty_border_redraw(dirty_tiles: Dictionary) -> void:
	_pending_border_dirty.merge(dirty_tiles, true)

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
	return _redraw_phase == REDRAW_PHASE_TERRAIN \
		or _redraw_phase == REDRAW_PHASE_COVER \
		or _redraw_phase == REDRAW_PHASE_CLIFF \
		or _redraw_phase == REDRAW_PHASE_FLORA

func build_visual_phase_batch(tile_budget: int) -> Dictionary:
	if not supports_worker_visual_phase():
		return {}
	var total_tiles: int = _chunk_size * _chunk_size
	if _redraw_tile_index >= total_tiles:
		return {}
	if _redraw_phase == REDRAW_PHASE_FLORA:
		var flora_payload: Dictionary = _ensure_flora_payload()
		var prebuilt_packet: Dictionary = _get_prebuilt_flora_render_packet(flora_payload)
		return {
			"mode": VISUAL_BATCH_MODE_PHASE,
			"phase": REDRAW_PHASE_FLORA,
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
	var start_index: int = _redraw_tile_index
	var end_index: int = mini(total_tiles, start_index + maxi(1, tile_budget))
	var tiles: Array[Vector2i] = []
	for tile_index: int in range(start_index, end_index):
		tiles.append(_tile_from_index(tile_index))
	return _build_visual_compute_request(VISUAL_BATCH_MODE_PHASE, tiles, _redraw_phase, start_index, end_index)

func build_visual_dirty_batch(dirty_tiles: Dictionary, limit: int = -1) -> Dictionary:
	var tiles: Array[Vector2i] = []
	for tile_variant: Variant in dirty_tiles.keys():
		var local_tile: Vector2i = tile_variant as Vector2i
		if not _is_inside(local_tile):
			continue
		tiles.append(local_tile)
	if tiles.is_empty():
		return {}
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	if limit > 0 and tiles.size() > limit:
		tiles.resize(limit)
	return _build_visual_compute_request(VISUAL_BATCH_MODE_DIRTY, tiles)

func apply_visual_phase_batch(batch: Dictionary) -> bool:
	if StringName(batch.get("mode", &"")) != VISUAL_BATCH_MODE_PHASE:
		return false
	var phase: int = int(batch.get("phase", REDRAW_PHASE_DONE))
	var start_index: int = int(batch.get("start_index", -1))
	var end_index: int = int(batch.get("end_index", -1))
	if phase != _redraw_phase or start_index != _redraw_tile_index:
		return false
	if phase == REDRAW_PHASE_FLORA:
		_apply_flora_render_packet(batch.get("flora_packet", {}) as Dictionary, &"batched_renderer")
	else:
		_apply_visual_prepared_batch(batch)
	_redraw_tile_index = end_index
	if phase == REDRAW_PHASE_COVER:
		_reapply_local_zone_cover_state_for_index_range(start_index, end_index)
	if _redraw_tile_index >= _chunk_size * _chunk_size:
		_advance_redraw_phase()
	_sync_visual_state_after_redraw_mutation()
	return true

func apply_visual_dirty_batch(batch: Dictionary) -> bool:
	if StringName(batch.get("mode", &"")) != VISUAL_BATCH_MODE_DIRTY:
		return false
	_apply_visual_prepared_batch(batch)
	_mark_interior_macro_dirty()
	var dirty_tiles: Dictionary = {}
	for tile_variant: Variant in batch.get("tiles", []):
		var local_tile: Vector2i = tile_variant as Vector2i
		dirty_tiles[local_tile] = true
	_reapply_local_zone_cover_state_for_tiles(dirty_tiles)
	if WorldGenerator and WorldGenerator.balance and WorldGenerator.balance.mountain_debug_visualization:
		for child: Node in _debug_root.get_children():
			child.queue_free()
		_rebuild_debug_markers()
	return true

func _build_visual_compute_request(
	mode: StringName,
	tiles: Array[Vector2i],
	phase: int = REDRAW_PHASE_DONE,
	start_index: int = -1,
	end_index: int = -1
) -> Dictionary:
	if tiles.is_empty():
		return {}
	var terrain_lookup: Dictionary = {}
	var need_surface_meta: bool = phase == REDRAW_PHASE_TERRAIN or mode == VISUAL_BATCH_MODE_DIRTY
	var height_lookup: Dictionary = {}
	var variation_lookup: Dictionary = {}
	var biome_lookup: Dictionary = {}
	var previous_cache_enabled: bool = _use_operation_global_terrain_cache
	var previous_global_terrain_cache: Dictionary = _operation_global_terrain_cache
	_use_operation_global_terrain_cache = true
	_operation_global_terrain_cache = {}
	for local_tile: Vector2i in tiles:
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var neighbor_tile: Vector2i = local_tile + Vector2i(offset_x, offset_y)
				if terrain_lookup.has(neighbor_tile):
					continue
				terrain_lookup[neighbor_tile] = _get_neighbor_terrain(neighbor_tile)
		if not need_surface_meta:
			continue
		height_lookup[local_tile] = _height_at(local_tile)
		variation_lookup[local_tile] = _variation_at(local_tile)
		biome_lookup[local_tile] = _biome_palette_index_at(local_tile)
	_use_operation_global_terrain_cache = previous_cache_enabled
	_operation_global_terrain_cache = previous_global_terrain_cache
	var request: Dictionary = {
		"mode": mode,
		"phase": phase,
		"phase_name": &"dirty" if mode == VISUAL_BATCH_MODE_DIRTY else Chunk._visual_phase_name(phase),
		"chunk_coord": chunk_coord,
		"chunk_size": _chunk_size,
		"is_underground": _is_underground,
		"start_index": start_index,
		"end_index": end_index,
		"tiles": tiles,
		"terrain_lookup": terrain_lookup,
		"height_lookup": height_lookup,
		"variation_lookup": variation_lookup,
		"biome_lookup": biome_lookup,
	}
	if Chunk._has_native_visual_kernels():
		request["native_visual_tables"] = Chunk._build_native_visual_tables()
	return request

func _apply_visual_commands(
	commands: Array,
	command_buffer: PackedInt32Array = PackedInt32Array(),
	command_stride: int = VISUAL_COMMAND_BUFFER_STRIDE
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
		if int(command.get("op", VISUAL_COMMAND_OP_SET)) == VISUAL_COMMAND_OP_SET:
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
	if not terrain_buffer.is_empty() \
		or not ground_face_buffer.is_empty() \
		or not rock_buffer.is_empty() \
		or not cover_buffer.is_empty() \
		or not cliff_buffer.is_empty():
		return _apply_visual_layer_buffers(
			terrain_buffer,
			ground_face_buffer,
			rock_buffer,
			cover_buffer,
			cliff_buffer,
			int(batch.get("buffer_stride", VISUAL_APPLY_BUFFER_STRIDE))
		)
	return _apply_visual_commands(
		batch.get("commands", []) as Array,
		batch.get("command_buffer", PackedInt32Array()),
		int(batch.get("command_stride", VISUAL_COMMAND_BUFFER_STRIDE))
	)

func _apply_visual_layer_buffers(
	terrain_buffer: PackedInt32Array,
	ground_face_buffer: PackedInt32Array,
	rock_buffer: PackedInt32Array,
	cover_buffer: PackedInt32Array,
	cliff_buffer: PackedInt32Array,
	buffer_stride: int = VISUAL_APPLY_BUFFER_STRIDE
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

func _apply_visual_command_buffer(command_buffer: PackedInt32Array, command_stride: int = VISUAL_COMMAND_BUFFER_STRIDE) -> int:
	if command_stride <= 0:
		return 0
	var applied_commands: int = 0
	var command_limit: int = command_buffer.size() - command_stride + 1
	var index: int = 0
	while index < command_limit:
		var layer: TileMapLayer = _visual_layer_for_command(command_buffer[index])
		if layer != null:
			var local_tile: Vector2i = Vector2i(command_buffer[index + 1], command_buffer[index + 2])
			if command_buffer[index + 3] == VISUAL_COMMAND_OP_SET:
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
	buffer_stride: int = VISUAL_APPLY_BUFFER_STRIDE
) -> int:
	if layer == null or buffer.is_empty() or buffer_stride <= 0:
		return 0
	var applied_commands: int = 0
	var command_limit: int = buffer.size() - buffer_stride + 1
	var index: int = 0
	while index < command_limit:
		var local_tile: Vector2i = Vector2i(buffer[index], buffer[index + 1])
		if buffer[index + 2] == VISUAL_COMMAND_OP_SET:
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
	buffer_stride: int = VISUAL_APPLY_BUFFER_STRIDE
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
		VISUAL_LAYER_TERRAIN:
			return _terrain_layer
		VISUAL_LAYER_GROUND_FACE:
			return _ground_face_layer
		VISUAL_LAYER_ROCK:
			return _rock_layer
		VISUAL_LAYER_COVER:
			return _cover_layer
		VISUAL_LAYER_CLIFF:
			return _cliff_layer
		_:
			return null

static func compute_visual_batch(request: Dictionary) -> Dictionary:
	var native_batch: Dictionary = Chunk._try_compute_visual_batch_native(request)
	if not native_batch.is_empty():
		return native_batch
	var tiles: Array = request.get("tiles", [])
	var result: Dictionary = {
		"mode": request.get("mode", &""),
		"phase": int(request.get("phase", REDRAW_PHASE_DONE)),
		"phase_name": request.get("phase_name", &"done"),
		"start_index": int(request.get("start_index", -1)),
		"end_index": int(request.get("end_index", -1)),
		"tiles": tiles,
		"tile_count": tiles.size(),
		"commands": [],
	}
	var commands: Array[Dictionary] = []
	var mode: StringName = StringName(request.get("mode", &""))
	match mode:
		VISUAL_BATCH_MODE_PHASE:
			var phase: int = int(request.get("phase", REDRAW_PHASE_DONE))
			match phase:
				REDRAW_PHASE_FLORA:
					var prebuilt_packet: Dictionary = request.get("flora_packet", {}) as Dictionary
					if prebuilt_packet.is_empty():
						prebuilt_packet = ChunkFloraResultScript.build_render_packet_from_payload(
							request.get("flora_payload", {}) as Dictionary,
							int(request.get("tile_size", 0))
						)
					result["flora_packet"] = prebuilt_packet
				_:
					for tile_variant: Variant in tiles:
						var local_tile: Vector2i = tile_variant as Vector2i
						match phase:
							REDRAW_PHASE_TERRAIN:
								Chunk._append_terrain_visual_commands(request, local_tile, commands, false)
							REDRAW_PHASE_COVER:
								Chunk._append_cover_visual_command(request, local_tile, commands, false)
							REDRAW_PHASE_CLIFF:
								Chunk._append_cliff_visual_command(request, local_tile, commands, false)
		VISUAL_BATCH_MODE_DIRTY:
			for tile_variant: Variant in tiles:
				var local_tile: Vector2i = tile_variant as Vector2i
				Chunk._append_terrain_visual_commands(request, local_tile, commands, true)
				Chunk._append_cover_visual_command(request, local_tile, commands, true)
				Chunk._append_cliff_visual_command(request, local_tile, commands, true)
		_:
			pass
	result["commands"] = commands
	result["command_count"] = commands.size()
	return result

static func _try_compute_visual_batch_native(request: Dictionary) -> Dictionary:
	if not Chunk._has_native_visual_kernels():
		return {}
	var mode: StringName = StringName(request.get("mode", &""))
	if mode != VISUAL_BATCH_MODE_DIRTY and mode != VISUAL_BATCH_MODE_PHASE:
		return {}
	if mode == VISUAL_BATCH_MODE_PHASE:
		var phase: int = int(request.get("phase", REDRAW_PHASE_DONE))
		if phase != REDRAW_PHASE_TERRAIN and phase != REDRAW_PHASE_COVER and phase != REDRAW_PHASE_CLIFF:
			return {}
	if not request.has("native_visual_tables"):
		return {}
	var helper: RefCounted = Chunk._get_native_visual_kernels()
	if helper == null or not helper.has_method("compute_visual_batch"):
		return {}
	var batch: Dictionary = helper.call("compute_visual_batch", request) as Dictionary
	return batch if not batch.is_empty() else {}

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

static func _append_terrain_visual_commands(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	var terrain_type: int = Chunk._visual_request_terrain(request, local_tile)
	var atlas: Vector2i = ChunkTilesetFactory.TILE_GROUND
	var rock_atlas: Vector2i = Vector2i(-1, -1)
	var rock_alt_id: int = 0
	var biome_palette_index: int = Chunk._visual_request_biome(request, local_tile)
	var variation_id: int = ChunkTilesetFactory.SURFACE_VARIATION_NONE
	var variation_tile: Vector2i = Vector2i(-1, -1)
	var is_underground: bool = bool(request.get("is_underground", false))
	if not is_underground:
		variation_id = Chunk._visual_request_variation(request, local_tile)
		variation_tile = ChunkTilesetFactory.get_surface_variation_tile(variation_id, biome_palette_index)
	match terrain_type:
		TileGenData.TerrainType.ROCK:
			atlas = Chunk._visual_request_surface_ground_atlas(request, local_tile)
			var rock_visual: Vector2i = Chunk._visual_request_rock_visual_class(request, local_tile)
			if not is_underground:
				rock_visual = Chunk._visual_request_surface_rock_visual_class(request, local_tile)
			var global_tile: Vector2i = Chunk._visual_request_to_global_tile(request, local_tile)
			rock_atlas = Chunk._visual_request_variant_atlas(rock_visual, global_tile.x, global_tile.y)
			rock_alt_id = Chunk._visual_request_variant_alt_id(rock_visual, global_tile.x, global_tile.y, is_underground)
		TileGenData.TerrainType.WATER:
			if variation_id == ChunkTilesetFactory.SURFACE_VARIATION_ICE and variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.SAND:
			if variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.GRASS:
			if variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.MINED_FLOOR:
			atlas = ChunkTilesetFactory.TILE_MINED_FLOOR
		TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			atlas = ChunkTilesetFactory.TILE_MOUNTAIN_ENTRANCE
		_:
			if variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = Chunk._visual_request_surface_ground_atlas(request, local_tile)
	commands.append(Chunk._make_visual_set_command(
		VISUAL_LAYER_TERRAIN,
		local_tile,
		ChunkTilesetFactory.TERRAIN_SOURCE_ID,
		atlas,
		0
	))
	Chunk._append_ground_face_visual_command(request, local_tile, terrain_type, commands, explicit_clear)
	if rock_atlas.x >= 0:
		commands.append(Chunk._make_visual_set_command(
			VISUAL_LAYER_ROCK,
			local_tile,
			ChunkTilesetFactory.TERRAIN_SOURCE_ID,
			rock_atlas,
			rock_alt_id
		))
	elif explicit_clear:
		commands.append(Chunk._make_visual_erase_command(VISUAL_LAYER_ROCK, local_tile))

static func _append_ground_face_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	terrain_type: int,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	if bool(request.get("is_underground", false)):
		if explicit_clear:
			commands.append(Chunk._make_visual_erase_command(VISUAL_LAYER_GROUND_FACE, local_tile))
		return
	var atlas: Vector2i = Vector2i(-1, -1)
	var alt_id: int = 0
	if Chunk._visual_request_is_surface_face_terrain(terrain_type):
		var wall_def: Vector2i = ChunkTilesetFactory.WALL_INTERIOR
		var interior_variant: Vector2i = Vector2i.ZERO
		var global_tile: Vector2i = Chunk._visual_request_to_global_tile(request, local_tile)
		if Chunk._visual_request_has_water_face_neighbor(request, local_tile):
			wall_def = Chunk._visual_request_water_face_visual_class(request, local_tile)
		else:
			interior_variant = Chunk._visual_request_interior_variant(global_tile.x, global_tile.y)
			alt_id = interior_variant.y
		var biome_palette_index: int = Chunk._visual_request_biome(request, local_tile)
		match terrain_type:
			TileGenData.TerrainType.GROUND, TileGenData.TerrainType.GRASS:
				atlas = ChunkTilesetFactory.get_ground_face_coords(wall_def, biome_palette_index, interior_variant.x)
			TileGenData.TerrainType.SAND:
				atlas = ChunkTilesetFactory.get_sand_face_coords(wall_def, biome_palette_index, interior_variant.x)
	if atlas.x >= 0:
		commands.append(Chunk._make_visual_set_command(
			VISUAL_LAYER_GROUND_FACE,
			local_tile,
			ChunkTilesetFactory.TERRAIN_SOURCE_ID,
			atlas,
			alt_id
		))
	elif explicit_clear:
		commands.append(Chunk._make_visual_erase_command(VISUAL_LAYER_GROUND_FACE, local_tile))

static func _append_cover_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	if bool(request.get("is_underground", false)):
		if explicit_clear:
			commands.append(Chunk._make_visual_erase_command(VISUAL_LAYER_COVER, local_tile))
		return
	var terrain_type: int = Chunk._visual_request_terrain(request, local_tile)
	var need_cover: bool = terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or Chunk._visual_request_is_cave_edge_rock(request, local_tile)
	if not need_cover:
		if explicit_clear:
			commands.append(Chunk._make_visual_erase_command(VISUAL_LAYER_COVER, local_tile))
		return
	var base: Vector2i = Chunk._visual_request_cover_rock_atlas(request, local_tile)
	var global_tile: Vector2i = Chunk._visual_request_to_global_tile(request, local_tile)
	var atlas: Vector2i = Chunk._visual_request_variant_atlas(base, global_tile.x, global_tile.y)
	var alt_id: int = Chunk._visual_request_variant_alt_id(base, global_tile.x, global_tile.y, false)
	commands.append(Chunk._make_visual_set_command(
		VISUAL_LAYER_COVER,
		local_tile,
		ChunkTilesetFactory.TERRAIN_SOURCE_ID,
		atlas,
		alt_id
	))

static func _append_cliff_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	if bool(request.get("is_underground", false)):
		if explicit_clear:
			commands.append(Chunk._make_visual_erase_command(VISUAL_LAYER_CLIFF, local_tile))
		return
	if Chunk._visual_request_terrain(request, local_tile) != TileGenData.TerrainType.ROCK:
		if explicit_clear:
			commands.append(Chunk._make_visual_erase_command(VISUAL_LAYER_CLIFF, local_tile))
		return
	var south_open: bool = Chunk._visual_request_is_open_exterior(Chunk._visual_request_terrain(request, local_tile + _CARDINAL_DIRS[3]))
	var west_open: bool = Chunk._visual_request_is_open_exterior(Chunk._visual_request_terrain(request, local_tile + _CARDINAL_DIRS[0]))
	var east_open: bool = Chunk._visual_request_is_open_exterior(Chunk._visual_request_terrain(request, local_tile + _CARDINAL_DIRS[1]))
	var north_open: bool = Chunk._visual_request_is_open_exterior(Chunk._visual_request_terrain(request, local_tile + _CARDINAL_DIRS[2]))
	var overlay: Vector2i = Vector2i(-1, -1)
	if south_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_SOUTH
	elif west_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_WEST
	elif east_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_EAST
	elif north_open:
		overlay = ChunkTilesetFactory.TILE_TOP_EDGE
	if overlay.x >= 0:
		commands.append(Chunk._make_visual_set_command(
			VISUAL_LAYER_CLIFF,
			local_tile,
			ChunkTilesetFactory.OVERLAY_SOURCE_ID,
			overlay,
			0
		))
	elif explicit_clear:
		commands.append(Chunk._make_visual_erase_command(VISUAL_LAYER_CLIFF, local_tile))

static func _make_visual_set_command(layer: int, local_tile: Vector2i, source_id: int, atlas: Vector2i, alt_id: int) -> Dictionary:
	return {
		"layer": layer,
		"tile": local_tile,
		"op": VISUAL_COMMAND_OP_SET,
		"source_id": source_id,
		"atlas": atlas,
		"alt_id": alt_id,
	}

static func _make_visual_erase_command(layer: int, local_tile: Vector2i) -> Dictionary:
	return {
		"layer": layer,
		"tile": local_tile,
		"op": VISUAL_COMMAND_OP_ERASE,
	}

static func _visual_request_terrain(request: Dictionary, local_tile: Vector2i) -> int:
	var terrain_lookup: Dictionary = request.get("terrain_lookup", {}) as Dictionary
	return int(terrain_lookup.get(local_tile, TileGenData.TerrainType.ROCK))

static func _visual_request_height(request: Dictionary, local_tile: Vector2i) -> float:
	var height_lookup: Dictionary = request.get("height_lookup", {}) as Dictionary
	return float(height_lookup.get(local_tile, 0.5))

static func _visual_request_variation(request: Dictionary, local_tile: Vector2i) -> int:
	var variation_lookup: Dictionary = request.get("variation_lookup", {}) as Dictionary
	return int(variation_lookup.get(local_tile, ChunkTilesetFactory.SURFACE_VARIATION_NONE))

static func _visual_request_biome(request: Dictionary, local_tile: Vector2i) -> int:
	var biome_lookup: Dictionary = request.get("biome_lookup", {}) as Dictionary
	return int(biome_lookup.get(local_tile, 0))

static func _visual_request_to_global_tile(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	var chunk_coord: Vector2i = request.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var chunk_size: int = int(request.get("chunk_size", 64))
	return Vector2i(
		chunk_coord.x * chunk_size + local_tile.x,
		chunk_coord.y * chunk_size + local_tile.y
	)

static func _visual_request_is_open_for_visual(terrain_type: int) -> bool:
	return terrain_type != TileGenData.TerrainType.ROCK

static func _visual_request_is_open_exterior(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.WATER \
		or terrain_type == TileGenData.TerrainType.SAND \
		or terrain_type == TileGenData.TerrainType.GRASS

static func _visual_request_is_open_for_surface_rock_visual(terrain_type: int) -> bool:
	return Chunk._visual_request_is_open_exterior(terrain_type) \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

static func _visual_request_is_open_for_surface_visual(terrain_type: int, water_only: bool) -> bool:
	if water_only:
		return terrain_type == TileGenData.TerrainType.WATER
	return Chunk._visual_request_is_open_for_surface_rock_visual(terrain_type)

static func _visual_request_has_water_face_neighbor(request: Dictionary, local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		if Chunk._visual_request_terrain(request, local_tile + dir) == TileGenData.TerrainType.WATER:
			return true
	return false

static func _visual_request_is_surface_face_terrain(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.GRASS \
		or terrain_type == TileGenData.TerrainType.SAND

static func _visual_request_ground_atlas_for_height(height_value: float) -> Vector2i:
	if height_value < 0.38:
		return ChunkTilesetFactory.TILE_GROUND_DARK
	if height_value > 0.62:
		return ChunkTilesetFactory.TILE_GROUND_LIGHT
	return ChunkTilesetFactory.TILE_GROUND

static func _visual_request_surface_ground_atlas(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	if bool(request.get("is_underground", false)):
		return Chunk._visual_request_ground_atlas_for_height(Chunk._visual_request_height(request, local_tile))
	var biome_palette_index: int = Chunk._visual_request_biome(request, local_tile)
	var variation_tile: Vector2i = ChunkTilesetFactory.get_surface_variation_tile(
		Chunk._visual_request_variation(request, local_tile),
		biome_palette_index
	)
	if variation_tile.x >= 0:
		return variation_tile
	return ChunkTilesetFactory.get_surface_ground_tile(
		biome_palette_index,
		Chunk._visual_request_height(request, local_tile)
	)

static func _visual_request_surface_rock_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return Chunk._visual_request_surface_visual_class(request, local_tile, false)

static func _visual_request_water_face_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return Chunk._visual_request_surface_visual_class(request, local_tile, true)

static func _visual_request_surface_visual_class(request: Dictionary, local_tile: Vector2i, water_only: bool) -> Vector2i:
	var s: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i.DOWN), water_only)
	var n: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i.UP), water_only)
	var w: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i.LEFT), water_only)
	var e: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i.RIGHT), water_only)
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		if not n:
			return ChunkTilesetFactory.WALL_PENINSULA_S
		if not s:
			return ChunkTilesetFactory.WALL_PENINSULA_N
		if not w:
			return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		if s and w:
			return ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			return ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			return ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			return ChunkTilesetFactory.WALL_CORNER_NE
		if w and e:
			return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	if count == 1:
		if s:
			var s_ne: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, -1)), water_only)
			var s_nw: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, -1)), water_only)
			if s_ne and s_nw:
				return ChunkTilesetFactory.WALL_T_SOUTH
			if s_ne:
				return ChunkTilesetFactory.WALL_SOUTH_NE
			if s_nw:
				return ChunkTilesetFactory.WALL_SOUTH_NW
			return ChunkTilesetFactory.WALL_SOUTH
		if n:
			var n_se: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, 1)), water_only)
			var n_sw: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, 1)), water_only)
			if n_se and n_sw:
				return ChunkTilesetFactory.WALL_T_NORTH
			if n_se:
				return ChunkTilesetFactory.WALL_NORTH_SE
			if n_sw:
				return ChunkTilesetFactory.WALL_NORTH_SW
			return ChunkTilesetFactory.WALL_NORTH
		if w:
			var w_ne: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, -1)), water_only)
			var w_se: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, 1)), water_only)
			if w_ne and w_se:
				return ChunkTilesetFactory.WALL_T_WEST
			if w_ne:
				return ChunkTilesetFactory.WALL_WEST_NE
			if w_se:
				return ChunkTilesetFactory.WALL_WEST_SE
			return ChunkTilesetFactory.WALL_WEST
		var e_nw: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, -1)), water_only)
		var e_sw: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, 1)), water_only)
		if e_nw and e_sw:
			return ChunkTilesetFactory.WALL_T_EAST
		if e_nw:
			return ChunkTilesetFactory.WALL_EAST_NW
		if e_sw:
			return ChunkTilesetFactory.WALL_EAST_SW
		return ChunkTilesetFactory.WALL_EAST
	var d_sw: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, 1)), water_only)
	var d_se: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, 1)), water_only)
	var d_ne: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, -1)), water_only)
	var d_nw: bool = Chunk._visual_request_is_open_for_surface_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, -1)), water_only)
	var d_count: int = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw)
	if d_count == 4:
		return ChunkTilesetFactory.WALL_CROSS
	if d_count == 3:
		if not d_sw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SW
		if not d_se:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SE
		if not d_nw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_NW
		return ChunkTilesetFactory.WALL_DIAG3_NO_NE
	if d_count == 2:
		if d_sw and d_se:
			return ChunkTilesetFactory.WALL_EDGE_EW
		if d_ne and d_nw:
			return ChunkTilesetFactory.WALL_DIAG_NE_NW
		if d_ne and d_se:
			return ChunkTilesetFactory.WALL_DIAG_NE_SE
		if d_nw and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NW_SW
		if d_ne and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NE_SW
		return ChunkTilesetFactory.WALL_DIAG_NW_SE
	if d_sw:
		return ChunkTilesetFactory.WALL_NOTCH_SW
	if d_se:
		return ChunkTilesetFactory.WALL_NOTCH_SE
	if d_ne:
		return ChunkTilesetFactory.WALL_NOTCH_NE
	if d_nw:
		return ChunkTilesetFactory.WALL_NOTCH_NW
	return ChunkTilesetFactory.WALL_INTERIOR

static func _visual_request_rock_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	var s: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i.DOWN))
	var n: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i.UP))
	var w: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i.LEFT))
	var e: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i.RIGHT))
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		if not n:
			return ChunkTilesetFactory.WALL_PENINSULA_S
		if not s:
			return ChunkTilesetFactory.WALL_PENINSULA_N
		if not w:
			return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		if s and w:
			if Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, -1))):
				return ChunkTilesetFactory.WALL_CORNER_SW_T
			return ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			if Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, -1))):
				return ChunkTilesetFactory.WALL_CORNER_SE_T
			return ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			if Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, 1))):
				return ChunkTilesetFactory.WALL_CORNER_NW_T
			return ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			if Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, 1))):
				return ChunkTilesetFactory.WALL_CORNER_NE_T
			return ChunkTilesetFactory.WALL_CORNER_NE
		if e and w:
			return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	if count == 1:
		if s:
			var s_ne: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, -1)))
			var s_nw: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, -1)))
			if s_ne and s_nw:
				return ChunkTilesetFactory.WALL_T_SOUTH
			if s_ne:
				return ChunkTilesetFactory.WALL_SOUTH_NE
			if s_nw:
				return ChunkTilesetFactory.WALL_SOUTH_NW
			return ChunkTilesetFactory.WALL_SOUTH
		if n:
			var n_se: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, 1)))
			var n_sw: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, 1)))
			if n_se and n_sw:
				return ChunkTilesetFactory.WALL_T_NORTH
			if n_se:
				return ChunkTilesetFactory.WALL_NORTH_SE
			if n_sw:
				return ChunkTilesetFactory.WALL_NORTH_SW
			return ChunkTilesetFactory.WALL_NORTH
		if w:
			var w_ne: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, -1)))
			var w_se: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, 1)))
			if w_ne and w_se:
				return ChunkTilesetFactory.WALL_T_WEST
			if w_ne:
				return ChunkTilesetFactory.WALL_WEST_NE
			if w_se:
				return ChunkTilesetFactory.WALL_WEST_SE
			return ChunkTilesetFactory.WALL_WEST
		var e_nw: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, -1)))
		var e_sw: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, 1)))
		if e_nw and e_sw:
			return ChunkTilesetFactory.WALL_T_EAST
		if e_nw:
			return ChunkTilesetFactory.WALL_EAST_NW
		if e_sw:
			return ChunkTilesetFactory.WALL_EAST_SW
		return ChunkTilesetFactory.WALL_EAST
	var d_sw: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, 1)))
	var d_se: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, 1)))
	var d_ne: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(1, -1)))
	var d_nw: bool = Chunk._visual_request_is_open_for_visual(Chunk._visual_request_terrain(request, local_tile + Vector2i(-1, -1)))
	var d_count: int = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw)
	if d_count == 4:
		return ChunkTilesetFactory.WALL_CROSS
	if d_count == 3:
		if not d_sw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SW
		if not d_se:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SE
		if not d_nw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_NW
		return ChunkTilesetFactory.WALL_DIAG3_NO_NE
	if d_count == 2:
		if d_sw and d_se:
			return ChunkTilesetFactory.WALL_EDGE_EW
		if d_ne and d_nw:
			return ChunkTilesetFactory.WALL_DIAG_NE_NW
		if d_ne and d_se:
			return ChunkTilesetFactory.WALL_DIAG_NE_SE
		if d_nw and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NW_SW
		if d_ne and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NE_SW
		return ChunkTilesetFactory.WALL_DIAG_NW_SE
	if d_sw:
		return ChunkTilesetFactory.WALL_NOTCH_SW
	if d_se:
		return ChunkTilesetFactory.WALL_NOTCH_SE
	if d_ne:
		return ChunkTilesetFactory.WALL_NOTCH_NE
	if d_nw:
		return ChunkTilesetFactory.WALL_NOTCH_NW
	return ChunkTilesetFactory.WALL_INTERIOR

static func _visual_request_is_cave_edge_rock(request: Dictionary, local_tile: Vector2i) -> bool:
	if Chunk._visual_request_terrain(request, local_tile) != TileGenData.TerrainType.ROCK:
		return false
	var has_open_neighbor: bool = false
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		var neighbor_type: int = Chunk._visual_request_terrain(request, local_tile + dir)
		if Chunk._visual_request_is_open_exterior(neighbor_type):
			return false
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			has_open_neighbor = true
	return has_open_neighbor

static func _visual_request_is_exterior_surface_rock(request: Dictionary, local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		if Chunk._visual_request_is_open_exterior(Chunk._visual_request_terrain(request, local_tile + dir)):
			return true
	return false

static func _visual_request_cover_rock_atlas(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	if Chunk._visual_request_is_exterior_surface_rock(request, local_tile):
		return ChunkTilesetFactory.WALL_SOUTH
	return ChunkTilesetFactory.WALL_INTERIOR

static func _visual_request_variant_atlas(base: Vector2i, global_x: int, global_y: int) -> Vector2i:
	if base == ChunkTilesetFactory.WALL_INTERIOR:
		var interior_variant: Vector2i = Chunk._visual_request_interior_variant(global_x, global_y)
		return ChunkTilesetFactory.get_wall_variant_coords(base, interior_variant.x)
	return ChunkTilesetFactory.get_wall_variant_coords(base, 0)

static func _visual_request_variant_alt_id(base: Vector2i, global_x: int, global_y: int, allow_flip: bool) -> int:
	if base == ChunkTilesetFactory.WALL_INTERIOR:
		return Chunk._visual_request_interior_variant(global_x, global_y).y
	if not allow_flip:
		return 0
	var def_index: int = base.x - 7
	if def_index < 0 or def_index >= ChunkTilesetFactory._WALL_FLIP_CLASS.size():
		return 0
	var flip_class: int = ChunkTilesetFactory._WALL_FLIP_CLASS[def_index]
	if flip_class <= 0:
		return 0
	var alt_count: int = ChunkTilesetFactory.wall_flip_alt_count[flip_class]
	if alt_count <= 0:
		return 0
	return _tile_hash_xy(global_x + 17, global_y + 31) % alt_count

static func _visual_request_resolve_interior_family(global_x: int, global_y: int, base_count: int) -> int:
	var family_count: int = _interior_family_count(base_count)
	if family_count <= 1:
		return 0
	var macro_noise: float = Chunk._visual_request_sample_interior_family_noise(global_x, global_y, _INTERIOR_FAMILY_SCALE, _INTERIOR_FAMILY_SEED)
	var detail_noise: float = Chunk._visual_request_sample_interior_family_noise(
		global_x,
		global_y,
		_INTERIOR_FAMILY_DETAIL_SCALE,
		_INTERIOR_FAMILY_SEED + 53
	)
	var blended_noise: float = clampf(macro_noise * 0.82 + detail_noise * 0.18, 0.0, 0.999999)
	return mini(family_count - 1, int(floor(blended_noise * family_count)))

static func _visual_request_sample_interior_family_noise(global_x: int, global_y: int, scale: float, seed: int) -> float:
	var scaled_x: float = float(global_x) / scale
	var scaled_y: float = float(global_y) / scale
	var cell_x: int = floori(scaled_x)
	var cell_y: int = floori(scaled_y)
	var frac_x: float = _smoothstep01(scaled_x - float(cell_x))
	var frac_y: float = _smoothstep01(scaled_y - float(cell_y))
	var v00: float = _hash32_to_unit_float(_hash32_xy(cell_x, cell_y, seed))
	var v10: float = _hash32_to_unit_float(_hash32_xy(cell_x + 1, cell_y, seed))
	var v01: float = _hash32_to_unit_float(_hash32_xy(cell_x, cell_y + 1, seed))
	var v11: float = _hash32_to_unit_float(_hash32_xy(cell_x + 1, cell_y + 1, seed))
	var nx0: float = lerpf(v00, v10, frac_x)
	var nx1: float = lerpf(v01, v11, frac_x)
	return lerpf(nx0, nx1, frac_y)

static func _visual_request_raw_interior_variant(global_x: int, global_y: int, family_index: int, seed: int = _INTERIOR_VARIATION_SEED) -> Vector2i:
	var base_count: int = ChunkTilesetFactory.get_interior_base_variant_count()
	if base_count <= 0:
		return Vector2i.ZERO
	var family_window: Vector2i = _interior_family_window(base_count, family_index)
	var h: int = _hash32_xy(global_x, global_y, seed)
	return Vector2i(
		family_window.x + (h % family_window.y),
		(h >> 8) & (ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT - 1)
	)

static func _visual_request_interior_variant(global_x: int, global_y: int) -> Vector2i:
	var base_count: int = ChunkTilesetFactory.get_interior_base_variant_count()
	if base_count <= 0:
		return Vector2i.ZERO
	var resolved_family: int = Chunk._visual_request_resolve_interior_family(global_x, global_y, base_count)
	var family_window: Vector2i = _interior_family_window(base_count, resolved_family)
	var resolved: Vector2i = Chunk._visual_request_raw_interior_variant(global_x, global_y, resolved_family)
	var left_variant: Vector2i = Chunk._visual_request_raw_interior_variant(
		global_x - 1,
		global_y,
		Chunk._visual_request_resolve_interior_family(global_x - 1, global_y, base_count)
	)
	var top_variant: Vector2i = Chunk._visual_request_raw_interior_variant(
		global_x,
		global_y - 1,
		Chunk._visual_request_resolve_interior_family(global_x, global_y - 1, base_count)
	)
	var left_conflict: bool = _interior_variant_matches(resolved, left_variant)
	var top_conflict: bool = _interior_variant_matches(resolved, top_variant)
	if left_conflict and top_conflict:
		resolved = Chunk._visual_request_raw_interior_variant(global_x, global_y, resolved_family, _INTERIOR_REHASH_SEED)
	if _interior_variant_matches(resolved, left_variant):
		resolved.y = (resolved.y + 1) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	if _interior_variant_matches(resolved, top_variant):
		if family_window.y > 1:
			resolved.x = _shift_interior_family_base(resolved.x, family_window, 1)
		else:
			resolved.y = (resolved.y + 3) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	if _interior_variant_matches(resolved, left_variant) or _interior_variant_matches(resolved, top_variant):
		resolved = Chunk._visual_request_raw_interior_variant(global_x, global_y, resolved_family, _INTERIOR_REHASH_SEED + 97)
		if _interior_variant_matches(resolved, left_variant):
			resolved.y = (resolved.y + 5) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
		if _interior_variant_matches(resolved, top_variant):
			if family_window.y > 1:
				resolved.x = _shift_interior_family_base(resolved.x, family_window, 2)
			else:
				resolved.y = (resolved.y + 2) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	return resolved

static func _visual_phase_name(phase: int) -> StringName:
	match phase:
		REDRAW_PHASE_TERRAIN:
			return &"terrain"
		REDRAW_PHASE_COVER:
			return &"cover"
		REDRAW_PHASE_CLIFF:
			return &"cliff"
		REDRAW_PHASE_FLORA:
			return &"flora"
		REDRAW_PHASE_DEBUG_INTERIOR:
			return &"debug_interior"
		REDRAW_PHASE_DEBUG_COLLISION:
			return &"debug_collision"
		_:
			return &"done"

func _reset_cover_visual_state() -> void:
	if _cover_layer:
		_cover_layer.visible = true
	_reapply_local_zone_cover_state()

func _redraw_terrain_tile(local_tile: Vector2i) -> void:
	var terrain_type: int = get_terrain_type_at(local_tile)
	var atlas: Vector2i = ChunkTilesetFactory.TILE_GROUND
	var alt_id: int = 0
	var rock_atlas: Vector2i = Vector2i(-1, -1)
	var rock_alt_id: int = 0
	var biome_palette_index: int = _biome_palette_index_at(local_tile)
	var variation_id: int = ChunkTilesetFactory.SURFACE_VARIATION_NONE
	var variation_tile: Vector2i = Vector2i(-1, -1)
	if not _is_underground:
		variation_id = _variation_at(local_tile)
		variation_tile = ChunkTilesetFactory.get_surface_variation_tile(variation_id, biome_palette_index)
	match terrain_type:
		TileGenData.TerrainType.ROCK:
			# Base terrain under mountain: biome ground tile (always visible through rock alpha)
			atlas = _resolve_surface_ground_atlas(local_tile)
			# Rock wall form goes to separate rock_layer (alpha-blended over terrain)
			var rock_visual: Vector2i = _rock_visual_class(local_tile)
			if not _is_underground:
				rock_visual = _surface_rock_visual_class(local_tile)
			var global_tile: Vector2i = _to_global_tile(local_tile)
			rock_atlas = _resolve_variant_atlas(rock_visual, global_tile.x, global_tile.y)
			rock_alt_id = _resolve_variant_alt_id(rock_visual, global_tile.x, global_tile.y, _is_underground)
		TileGenData.TerrainType.WATER:
			if variation_id == ChunkTilesetFactory.SURFACE_VARIATION_ICE and variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.SAND:
			if variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.GRASS:
			if variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.MINED_FLOOR:
			atlas = ChunkTilesetFactory.TILE_MINED_FLOOR
		TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			atlas = ChunkTilesetFactory.TILE_MOUNTAIN_ENTRANCE
		_:
			if variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = _resolve_surface_ground_atlas(local_tile)
	_terrain_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, atlas, alt_id)
	_redraw_ground_face_tile(local_tile, terrain_type)
	# Rock layer: set wall form if ROCK, erase otherwise
	if rock_atlas.x >= 0:
		_rock_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, rock_atlas, rock_alt_id)
	else:
		_rock_layer.erase_cell(local_tile)

func _redraw_ground_face_tile(local_tile: Vector2i, terrain_type: int) -> void:
	if not _ground_face_layer:
		return
	if _is_underground:
		_ground_face_layer.erase_cell(local_tile)
		return
	var atlas: Vector2i = Vector2i(-1, -1)
	var alt_id: int = 0
	if _is_surface_face_terrain(terrain_type):
		var wall_def: Vector2i = ChunkTilesetFactory.WALL_INTERIOR
		var interior_variant: Vector2i = Vector2i.ZERO
		var global_tile: Vector2i = _to_global_tile(local_tile)
		if _has_water_face_neighbor(local_tile):
			wall_def = _water_face_visual_class(local_tile)
		else:
			interior_variant = _resolve_interior_variant(global_tile.x, global_tile.y)
			alt_id = interior_variant.y
		var biome_palette_index: int = _biome_palette_index_at(local_tile)
		match terrain_type:
			TileGenData.TerrainType.GROUND, TileGenData.TerrainType.GRASS:
				atlas = ChunkTilesetFactory.get_ground_face_coords(wall_def, biome_palette_index, interior_variant.x)
			TileGenData.TerrainType.SAND:
				atlas = ChunkTilesetFactory.get_sand_face_coords(wall_def, biome_palette_index, interior_variant.x)
	if atlas.x >= 0:
		_ground_face_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, atlas, alt_id)
	else:
		_ground_face_layer.erase_cell(local_tile)

func _surface_rock_visual_class(local_tile: Vector2i) -> Vector2i:
	return _surface_visual_class(local_tile, false)

func _water_face_visual_class(local_tile: Vector2i) -> Vector2i:
	return _surface_visual_class(local_tile, true)

func _surface_visual_class(local_tile: Vector2i, water_only: bool) -> Vector2i:
	var s: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i.DOWN), water_only)
	var n: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i.UP), water_only)
	var w: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i.LEFT), water_only)
	var e: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i.RIGHT), water_only)
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		if not n:
			return ChunkTilesetFactory.WALL_PENINSULA_S
		if not s:
			return ChunkTilesetFactory.WALL_PENINSULA_N
		if not w:
			return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		if s and w:
			return ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			return ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			return ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			return ChunkTilesetFactory.WALL_CORNER_NE
		if w and e:
			return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	if count == 1:
		if s:
			var s_ne: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)), water_only)
			var s_nw: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)), water_only)
			if s_ne and s_nw:
				return ChunkTilesetFactory.WALL_T_SOUTH
			if s_ne:
				return ChunkTilesetFactory.WALL_SOUTH_NE
			if s_nw:
				return ChunkTilesetFactory.WALL_SOUTH_NW
			return ChunkTilesetFactory.WALL_SOUTH
		if n:
			var n_se: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)), water_only)
			var n_sw: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)), water_only)
			if n_se and n_sw:
				return ChunkTilesetFactory.WALL_T_NORTH
			if n_se:
				return ChunkTilesetFactory.WALL_NORTH_SE
			if n_sw:
				return ChunkTilesetFactory.WALL_NORTH_SW
			return ChunkTilesetFactory.WALL_NORTH
		if w:
			var w_ne: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)), water_only)
			var w_se: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)), water_only)
			if w_ne and w_se:
				return ChunkTilesetFactory.WALL_T_WEST
			if w_ne:
				return ChunkTilesetFactory.WALL_WEST_NE
			if w_se:
				return ChunkTilesetFactory.WALL_WEST_SE
			return ChunkTilesetFactory.WALL_WEST
		var e_nw: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)), water_only)
		var e_sw: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)), water_only)
		if e_nw and e_sw:
			return ChunkTilesetFactory.WALL_T_EAST
		if e_nw:
			return ChunkTilesetFactory.WALL_EAST_NW
		if e_sw:
			return ChunkTilesetFactory.WALL_EAST_SW
		return ChunkTilesetFactory.WALL_EAST
	var d_sw: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)), water_only)
	var d_se: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)), water_only)
	var d_ne: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)), water_only)
	var d_nw: bool = _is_open_for_surface_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)), water_only)
	var d_count: int = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw)
	if d_count == 4:
		return ChunkTilesetFactory.WALL_CROSS
	if d_count == 3:
		if not d_sw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SW
		if not d_se:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SE
		if not d_nw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_NW
		return ChunkTilesetFactory.WALL_DIAG3_NO_NE
	if d_count == 2:
		if d_sw and d_se:
			return ChunkTilesetFactory.WALL_EDGE_EW
		if d_ne and d_nw:
			return ChunkTilesetFactory.WALL_DIAG_NE_NW
		if d_ne and d_se:
			return ChunkTilesetFactory.WALL_DIAG_NE_SE
		if d_nw and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NW_SW
		if d_ne and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NE_SW
		return ChunkTilesetFactory.WALL_DIAG_NW_SE
	if d_sw:
		return ChunkTilesetFactory.WALL_NOTCH_SW
	if d_se:
		return ChunkTilesetFactory.WALL_NOTCH_SE
	if d_ne:
		return ChunkTilesetFactory.WALL_NOTCH_NE
	if d_nw:
		return ChunkTilesetFactory.WALL_NOTCH_NW
	return ChunkTilesetFactory.WALL_INTERIOR

func _has_water_face_neighbor(local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		if _is_water_for_face_visual(_get_neighbor_terrain(local_tile + dir)):
			return true
	return false

func _is_surface_face_terrain(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.GRASS \
		or terrain_type == TileGenData.TerrainType.SAND

func _resolve_surface_ground_atlas(local_tile: Vector2i) -> Vector2i:
	if _is_underground:
		return _ground_atlas_for_height(_height_at(local_tile))
	var biome_palette_index: int = _biome_palette_index_at(local_tile)
	var variation_tile: Vector2i = ChunkTilesetFactory.get_surface_variation_tile(_variation_at(local_tile), biome_palette_index)
	if variation_tile.x >= 0:
		return variation_tile
	return ChunkTilesetFactory.get_surface_ground_tile(biome_palette_index, _height_at(local_tile))

func _ground_atlas_for_height(height_value: float) -> Vector2i:
	if height_value < 0.38:
		return ChunkTilesetFactory.TILE_GROUND_DARK
	if height_value > 0.62:
		return ChunkTilesetFactory.TILE_GROUND_LIGHT
	return ChunkTilesetFactory.TILE_GROUND

func _resolve_open_tile_type(local_tile: Vector2i) -> int:
	for dir: Vector2i in _CARDINAL_DIRS:
		if _is_open_exterior(_get_neighbor_terrain(local_tile + dir)):
			return TileGenData.TerrainType.MOUNTAIN_ENTRANCE
	return TileGenData.TerrainType.MINED_FLOOR

func _refresh_open_neighbors(local_tile: Vector2i) -> void:
	_refresh_open_tile(local_tile)
	for dir: Vector2i in _CARDINAL_DIRS:
		_refresh_open_tile(local_tile + dir)

func _refresh_open_tile(local_tile: Vector2i) -> void:
	if not _is_inside(local_tile):
		return
	var terrain_type: int = get_terrain_type_at(local_tile)
	if terrain_type != TileGenData.TerrainType.MINED_FLOOR and terrain_type != TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		return
	_set_terrain_type(local_tile, _resolve_open_tile_type(local_tile), false)

func _set_terrain_type(local_tile: Vector2i, terrain_type: int, mark_modified: bool = true) -> void:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _terrain_bytes.size():
		return
	_terrain_bytes[idx] = terrain_type
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
	for dir: Vector2i in _COVER_REVEAL_DIRS:
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
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			_redraw_cover_tile(Vector2i(local_x, local_y))
	_reapply_local_zone_cover_state()

func refresh_cliffs() -> void:
	if not _cliff_layer:
		return
	_cliff_layer.clear()
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			_redraw_cliff_tile(Vector2i(local_x, local_y))

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
	if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
		return
	var south_open: bool = _is_open_exterior(_get_neighbor_terrain(local_tile + _CARDINAL_DIRS[3]))
	var west_open: bool = _is_open_exterior(_get_neighbor_terrain(local_tile + _CARDINAL_DIRS[0]))
	var east_open: bool = _is_open_exterior(_get_neighbor_terrain(local_tile + _CARDINAL_DIRS[1]))
	var north_open: bool = _is_open_exterior(_get_neighbor_terrain(local_tile + _CARDINAL_DIRS[2]))
	var overlay: Vector2i = Vector2i(-1, -1)
	if south_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_SOUTH
	elif west_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_WEST
	elif east_open:
		overlay = ChunkTilesetFactory.TILE_SHADOW_EAST
	elif north_open:
		overlay = ChunkTilesetFactory.TILE_TOP_EDGE
	if overlay.x >= 0:
		_cliff_layer.set_cell(local_tile, ChunkTilesetFactory.OVERLAY_SOURCE_ID, overlay)

func _redraw_cover_tile(local_tile: Vector2i) -> void:
	# Underground z-levels don't use roof/cover system (ADR-0006).
	# Visibility handled by fog layer instead.
	if _is_underground:
		return
	var terrain: int = get_terrain_type_at(local_tile)
	var need_cover: bool = terrain == TileGenData.TerrainType.MINED_FLOOR \
		or _is_cave_edge_rock(local_tile)
	if not need_cover:
		return
	# Use the same variant hash as terrain layer — mountain looks identical before/after mining
	var base: Vector2i = _cover_rock_atlas(local_tile)
	var global_tile: Vector2i = _to_global_tile(local_tile)
	var atlas: Vector2i = _resolve_variant_atlas(base, global_tile.x, global_tile.y)
	var alt_id: int = _resolve_variant_alt_id(base, global_tile.x, global_tile.y, false)
	_cover_layer.set_cell(local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, atlas, alt_id)

## XOR-shift hash — no visible linear patterns.
static func _tile_hash_xy(tile_x: int, tile_y: int) -> int:
	return _hash32_xy(tile_x, tile_y, 0)

static func _tile_hash(pos: Vector2i) -> int:
	return _tile_hash_xy(pos.x, pos.y)

static func _hash32_xy(tile_x: int, tile_y: int, seed: int) -> int:
	var h: int = (tile_x * 374761393 + tile_y * 668265263 + seed * 1442695041) & _HASH32_MASK
	h = (h ^ (h >> 13)) & _HASH32_MASK
	h = (h * 1274126177) & _HASH32_MASK
	h = (h ^ (h >> 16)) & _HASH32_MASK
	return h

static func _interior_family_count(base_count: int) -> int:
	return maxi(1, mini(_INTERIOR_FAMILY_TARGET_COUNT, base_count))

static func _interior_family_window(base_count: int, family_index: int) -> Vector2i:
	var family_count: int = _interior_family_count(base_count)
	var clamped_family_index: int = clampi(family_index, 0, family_count - 1)
	var window_size: int = maxi(1, mini(base_count, _INTERIOR_FAMILY_WINDOW_SIZE))
	if base_count <= window_size or family_count <= 1:
		return Vector2i(0, base_count)
	var max_start: int = base_count - window_size
	var start: int = int(round(float(clamped_family_index * max_start) / float(family_count - 1)))
	return Vector2i(start, window_size)

static func _hash32_to_unit_float(h: int) -> float:
	return float(h & _HASH32_MASK) / float(_HASH32_MASK)

static func _smoothstep01(t: float) -> float:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	return clamped_t * clamped_t * (3.0 - 2.0 * clamped_t)

func _sample_interior_family_noise(global_x: int, global_y: int, scale: float, seed: int) -> float:
	var scaled_x: float = float(global_x) / scale
	var scaled_y: float = float(global_y) / scale
	var cell_x: int = floori(scaled_x)
	var cell_y: int = floori(scaled_y)
	var frac_x: float = _smoothstep01(scaled_x - float(cell_x))
	var frac_y: float = _smoothstep01(scaled_y - float(cell_y))
	var v00: float = _hash32_to_unit_float(_hash32_xy(cell_x, cell_y, seed))
	var v10: float = _hash32_to_unit_float(_hash32_xy(cell_x + 1, cell_y, seed))
	var v01: float = _hash32_to_unit_float(_hash32_xy(cell_x, cell_y + 1, seed))
	var v11: float = _hash32_to_unit_float(_hash32_xy(cell_x + 1, cell_y + 1, seed))
	var nx0: float = lerpf(v00, v10, frac_x)
	var nx1: float = lerpf(v01, v11, frac_x)
	return lerpf(nx0, nx1, frac_y)

func _resolve_interior_family(global_x: int, global_y: int, base_count: int) -> int:
	var family_count: int = _interior_family_count(base_count)
	if family_count <= 1:
		return 0
	var macro_noise: float = _sample_interior_family_noise(global_x, global_y, _INTERIOR_FAMILY_SCALE, _INTERIOR_FAMILY_SEED)
	var detail_noise: float = _sample_interior_family_noise(
		global_x,
		global_y,
		_INTERIOR_FAMILY_DETAIL_SCALE,
		_INTERIOR_FAMILY_SEED + 53
	)
	var blended_noise: float = clampf(macro_noise * 0.82 + detail_noise * 0.18, 0.0, 0.999999)
	return mini(family_count - 1, int(floor(blended_noise * family_count)))

static func _shift_interior_family_base(base_index: int, family_window: Vector2i, step: int) -> int:
	if family_window.y <= 1:
		return family_window.x
	return family_window.x + ((base_index - family_window.x + step) % family_window.y)

func _raw_interior_variant(global_x: int, global_y: int, family_index: int, seed: int = _INTERIOR_VARIATION_SEED) -> Vector2i:
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
	var base_count: int = ChunkTilesetFactory.get_interior_base_variant_count()
	if base_count <= 0:
		return Vector2i.ZERO
	var resolved_family: int = _resolve_interior_family(global_x, global_y, base_count)
	var family_window: Vector2i = _interior_family_window(base_count, resolved_family)
	var resolved: Vector2i = _raw_interior_variant(global_x, global_y, resolved_family)
	var left_variant: Vector2i = _raw_interior_variant(
		global_x - 1,
		global_y,
		_resolve_interior_family(global_x - 1, global_y, base_count)
	)
	var top_variant: Vector2i = _raw_interior_variant(
		global_x,
		global_y - 1,
		_resolve_interior_family(global_x, global_y - 1, base_count)
	)
	var left_conflict: bool = _interior_variant_matches(resolved, left_variant)
	var top_conflict: bool = _interior_variant_matches(resolved, top_variant)
	if left_conflict and top_conflict:
		resolved = _raw_interior_variant(global_x, global_y, resolved_family, _INTERIOR_REHASH_SEED)
	if _interior_variant_matches(resolved, left_variant):
		resolved.y = (resolved.y + 1) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	if _interior_variant_matches(resolved, top_variant):
		if family_window.y > 1:
			resolved.x = _shift_interior_family_base(resolved.x, family_window, 1)
		else:
			resolved.y = (resolved.y + 3) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	if _interior_variant_matches(resolved, left_variant) or _interior_variant_matches(resolved, top_variant):
		resolved = _raw_interior_variant(global_x, global_y, resolved_family, _INTERIOR_REHASH_SEED + 97)
		if _interior_variant_matches(resolved, left_variant):
			resolved.y = (resolved.y + 5) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
		if _interior_variant_matches(resolved, top_variant):
			if family_window.y > 1:
				resolved.x = _shift_interior_family_base(resolved.x, family_window, 2)
			else:
				resolved.y = (resolved.y + 2) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	return resolved

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
	var interior_tiles: Dictionary = _collect_interior_macro_tiles()
	if interior_tiles.is_empty():
		_clear_interior_macro_layer()
		return
	var sample_size: int = _chunk_size * _INTERIOR_MACRO_SAMPLES_PER_TILE
	var image := Image.create(sample_size, sample_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var world_sample_origin: Vector2i = Vector2i(
		chunk_coord.x * sample_size,
		chunk_coord.y * sample_size
	)
	for sample_y: int in range(sample_size):
		var local_tile_y: int = sample_y / _INTERIOR_MACRO_SAMPLES_PER_TILE
		for sample_x: int in range(sample_size):
			var local_tile: Vector2i = Vector2i(
				sample_x / _INTERIOR_MACRO_SAMPLES_PER_TILE,
				local_tile_y
			)
			if not interior_tiles.has(local_tile):
				continue
			var world_sample_x: int = world_sample_origin.x + sample_x
			var world_sample_y: int = world_sample_origin.y + sample_y
			var overlay_color: Color = _resolve_interior_macro_color(world_sample_x, world_sample_y, local_tile)
			if overlay_color.a <= 0.0:
				continue
			image.set_pixel(sample_x, sample_y, overlay_color)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_interior_macro_layer.texture = texture
	_interior_macro_layer.scale = Vector2(
		float(_tile_size) / float(_INTERIOR_MACRO_SAMPLES_PER_TILE),
		float(_tile_size) / float(_INTERIOR_MACRO_SAMPLES_PER_TILE)
	)
	_interior_macro_layer.visible = true
	_interior_macro_dirty = false

func _collect_interior_macro_tiles() -> Dictionary:
	var interior_tiles: Dictionary = {}
	for local_y: int in range(_chunk_size):
		for local_x: int in range(_chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			if _is_interior_macro_target(local_tile):
				interior_tiles[local_tile] = true
	return interior_tiles

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
	if base == ChunkTilesetFactory.WALL_INTERIOR:
		var interior_variant: Vector2i = _resolve_interior_variant(global_x, global_y)
		return ChunkTilesetFactory.get_wall_variant_coords(base, interior_variant.x)
	## Atlas variant selection disabled — always use variant 0 (base sprite set).
	return ChunkTilesetFactory.get_wall_variant_coords(base, 0)

func _resolve_variant_alt_id(base: Vector2i, global_x: int, global_y: int, allow_flip: bool) -> int:
	if base == ChunkTilesetFactory.WALL_INTERIOR:
		return _resolve_interior_variant(global_x, global_y).y
	if not allow_flip:
		return 0
	var def_index: int = base.x - 7
	if def_index < 0 or def_index >= ChunkTilesetFactory._WALL_FLIP_CLASS.size():
		return 0
	var flip_class: int = ChunkTilesetFactory._WALL_FLIP_CLASS[def_index]
	if flip_class <= 0:
		return 0
	var alt_count: int = ChunkTilesetFactory.wall_flip_alt_count[flip_class]
	if alt_count <= 0:
		return 0
	return _tile_hash_xy(global_x + 17, global_y + 31) % alt_count

func _rock_visual_class(local_tile: Vector2i) -> Vector2i:
	var s: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i.DOWN))
	var n: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i.UP))
	var w: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i.LEFT))
	var e: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i.RIGHT))
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		if not n: return ChunkTilesetFactory.WALL_PENINSULA_S
		if not s: return ChunkTilesetFactory.WALL_PENINSULA_N
		if not w: return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		if s and w:
			if _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1))):
				return ChunkTilesetFactory.WALL_CORNER_SW_T
			return ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			if _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1))):
				return ChunkTilesetFactory.WALL_CORNER_SE_T
			return ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			if _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1))):
				return ChunkTilesetFactory.WALL_CORNER_NW_T
			return ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			if _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1))):
				return ChunkTilesetFactory.WALL_CORNER_NE_T
			return ChunkTilesetFactory.WALL_CORNER_NE
		if e and w: return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	if count == 1:
		if s:
			var s_ne: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
			var s_nw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
			if s_ne and s_nw: return ChunkTilesetFactory.WALL_T_SOUTH
			if s_ne: return ChunkTilesetFactory.WALL_SOUTH_NE
			if s_nw: return ChunkTilesetFactory.WALL_SOUTH_NW
			return ChunkTilesetFactory.WALL_SOUTH
		if n:
			var n_se: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
			var n_sw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
			if n_se and n_sw: return ChunkTilesetFactory.WALL_T_NORTH
			if n_se: return ChunkTilesetFactory.WALL_NORTH_SE
			if n_sw: return ChunkTilesetFactory.WALL_NORTH_SW
			return ChunkTilesetFactory.WALL_NORTH
		if w:
			var w_ne: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
			var w_se: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
			if w_ne and w_se: return ChunkTilesetFactory.WALL_T_WEST
			if w_ne: return ChunkTilesetFactory.WALL_WEST_NE
			if w_se: return ChunkTilesetFactory.WALL_WEST_SE
			return ChunkTilesetFactory.WALL_WEST
		var e_nw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
		var e_sw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
		if e_nw and e_sw: return ChunkTilesetFactory.WALL_T_EAST
		if e_nw: return ChunkTilesetFactory.WALL_EAST_NW
		if e_sw: return ChunkTilesetFactory.WALL_EAST_SW
		return ChunkTilesetFactory.WALL_EAST
	var d_sw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, 1)))
	var d_se: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, 1)))
	var d_ne: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(1, -1)))
	var d_nw: bool = _is_open_for_visual(_get_neighbor_terrain(local_tile + Vector2i(-1, -1)))
	var d_count: int = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw)
	if d_count == 4:
		return ChunkTilesetFactory.WALL_CROSS
	if d_count == 3:
		if not d_sw: return ChunkTilesetFactory.WALL_DIAG3_NO_SW
		if not d_se: return ChunkTilesetFactory.WALL_DIAG3_NO_SE
		if not d_nw: return ChunkTilesetFactory.WALL_DIAG3_NO_NW
		return ChunkTilesetFactory.WALL_DIAG3_NO_NE
	if d_count == 2:
		if d_sw and d_se: return ChunkTilesetFactory.WALL_EDGE_EW
		if d_ne and d_nw: return ChunkTilesetFactory.WALL_DIAG_NE_NW
		if d_ne and d_se: return ChunkTilesetFactory.WALL_DIAG_NE_SE
		if d_nw and d_sw: return ChunkTilesetFactory.WALL_DIAG_NW_SW
		if d_ne and d_sw: return ChunkTilesetFactory.WALL_DIAG_NE_SW
		return ChunkTilesetFactory.WALL_DIAG_NW_SE
	if d_sw: return ChunkTilesetFactory.WALL_NOTCH_SW
	if d_se: return ChunkTilesetFactory.WALL_NOTCH_SE
	if d_ne: return ChunkTilesetFactory.WALL_NOTCH_NE
	if d_nw: return ChunkTilesetFactory.WALL_NOTCH_NW
	return ChunkTilesetFactory.WALL_INTERIOR

func _rock_atlas(local_tile: Vector2i) -> Vector2i:
	if _is_surface_rock(local_tile):
		return ChunkTilesetFactory.TILE_ROCK
	return ChunkTilesetFactory.TILE_ROCK_INTERIOR

func _cover_rock_atlas(local_tile: Vector2i) -> Vector2i:
	if _is_exterior_surface_rock(local_tile):
		return ChunkTilesetFactory.WALL_SOUTH
	return ChunkTilesetFactory.WALL_INTERIOR

func _is_cave_edge_rock(local_tile: Vector2i) -> bool:
	if get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
		return false
	var has_open_neighbor: bool = false
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		var neighbor_type: int = _get_neighbor_terrain(local_tile + dir)
		if _is_open_exterior(neighbor_type):
			return false
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			has_open_neighbor = true
	return has_open_neighbor

func _is_exterior_surface_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		if _is_open_exterior(_get_neighbor_terrain(local_tile + dir)):
			return true
	return false

func _is_surface_rock(local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
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

func _biome_palette_index_at(local_tile: Vector2i) -> int:
	var idx: int = local_tile.y * _chunk_size + local_tile.x
	if idx < 0 or idx >= _biome_bytes.size():
		return 0
	return int(_biome_bytes[idx])

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
	if WorldGenerator and WorldGenerator.has_method("chunk_local_to_tile"):
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
		REDRAW_PHASE_TERRAIN:
			return maxi(1, base_budget / 2)
		REDRAW_PHASE_COVER, REDRAW_PHASE_FLORA, REDRAW_PHASE_DEBUG_INTERIOR, REDRAW_PHASE_DEBUG_COLLISION:
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
			for dir: Vector2i in _COVER_REVEAL_DIRS:
				var neighbor_tile: Vector2i = WorldGenerator.offset_tile(global_tile, dir) if WorldGenerator else global_tile + dir
				if zone_tiles.has(neighbor_tile):
					reveal_tiles[local_tile] = true
					break
	return reveal_tiles

func _apply_local_zone_cover_state(next_cover_tiles: Dictionary) -> void:
	if not _cover_layer:
		_revealed_local_cover_tiles = next_cover_tiles
		return
	for local_tile: Vector2i in _revealed_local_cover_tiles:
		if next_cover_tiles.has(local_tile):
			continue
		_redraw_cover_tile(local_tile)
	for local_tile: Vector2i in next_cover_tiles:
		if _revealed_local_cover_tiles.has(local_tile):
			continue
		_cover_layer.erase_cell(local_tile)
	_revealed_local_cover_tiles = next_cover_tiles

func _reapply_local_zone_cover_state() -> void:
	if not _cover_layer or _revealed_local_cover_tiles.is_empty():
		return
	for local_tile: Vector2i in _revealed_local_cover_tiles:
		_cover_layer.erase_cell(local_tile)

func _reapply_local_zone_cover_state_for_tiles(tile_map: Dictionary) -> void:
	if not _cover_layer or _revealed_local_cover_tiles.is_empty() or tile_map.is_empty():
		return
	for local_tile: Vector2i in tile_map:
		if _revealed_local_cover_tiles.has(local_tile):
			_cover_layer.erase_cell(local_tile)

func _reapply_local_zone_cover_state_for_mining_patch(center_tile: Vector2i) -> void:
	if not _cover_layer or _revealed_local_cover_tiles.is_empty():
		return
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var local_tile: Vector2i = center_tile + Vector2i(offset_x, offset_y)
			if not _is_inside(local_tile):
				continue
			if _revealed_local_cover_tiles.has(local_tile):
				_cover_layer.erase_cell(local_tile)

func _reapply_local_zone_cover_state_for_index_range(start_index: int, end_index: int) -> void:
	if not _cover_layer or _revealed_local_cover_tiles.is_empty():
		return
	for tile_index: int in range(start_index, end_index):
		var local_tile: Vector2i = _tile_from_index(tile_index)
		if _revealed_local_cover_tiles.has(local_tile):
			_cover_layer.erase_cell(local_tile)

func get_redraw_phase_name() -> StringName:
	match _redraw_phase:
		REDRAW_PHASE_TERRAIN:
			return &"terrain"
		REDRAW_PHASE_COVER:
			return &"cover"
		REDRAW_PHASE_CLIFF:
			return &"cliff"
		REDRAW_PHASE_FLORA:
			return &"flora"
		REDRAW_PHASE_DEBUG_INTERIOR:
			return &"debug_interior"
		REDRAW_PHASE_DEBUG_COLLISION:
			return &"debug_collision"
		_:
			return &"done"

func _process_redraw_phase_tiles(tile_budget: int) -> int:
	var total_tiles: int = _chunk_size * _chunk_size
	var start_index: int = _redraw_tile_index
	if _redraw_phase == REDRAW_PHASE_FLORA:
		_apply_flora_render_packet(_build_flora_render_packet(), &"batched_renderer")
		_redraw_tile_index = total_tiles
		return total_tiles - start_index
	var end_index: int = mini(_redraw_tile_index + tile_budget, total_tiles)
	var processed_end_index: int = start_index
	var started_usec: int = Time.get_ticks_usec()
	for tile_index: int in range(start_index, end_index):
		var local_tile: Vector2i = _tile_from_index(tile_index)
		match _redraw_phase:
			REDRAW_PHASE_TERRAIN:
				_redraw_terrain_tile(local_tile)
			REDRAW_PHASE_COVER:
				_redraw_cover_tile(local_tile)
			REDRAW_PHASE_CLIFF:
				_redraw_cliff_tile(local_tile)
			REDRAW_PHASE_DEBUG_INTERIOR:
				_process_debug_marker_tile(local_tile, false)
			REDRAW_PHASE_DEBUG_COLLISION:
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
	_flora_result = result
	_flora_payload = result.to_serialized_payload(_tile_size) if result != null else {}

func set_flora_payload(payload: Dictionary) -> void:
	_flora_payload = payload if not payload.is_empty() else {}
	_flora_result = null

func _flora_publish_logging_enabled() -> bool:
	return FLORA_PUBLISH_LOG_ARG in OS.get_cmdline_user_args()

func _log_flora_publish_summary(mode: StringName, renderer_nodes: int) -> void:
	if not _flora_publish_logging_enabled():
		return
	var flora_payload: Dictionary = _ensure_flora_payload()
	var placement_count: int = int(flora_payload.get(
		"placement_count",
		_flora_result.get_placement_count() if _flora_result != null else 0
	))
	var group_count: int = int(flora_payload.get(
		"group_count",
		_flora_result.get_render_group_count() if _flora_result != null else 0
	))
	var layer_count: int = int(flora_payload.get(
		"layer_count",
		_flora_result.get_render_layer_count() if _flora_result != null else 0
	))
	print("[FloraPublish] chunk=%s mode=%s placements=%d groups=%d layers=%d renderer_nodes=%d" % [
		chunk_coord,
		String(mode),
		placement_count,
		group_count,
		layer_count,
		renderer_nodes,
	])

func _build_flora_render_packet() -> Dictionary:
	var flora_payload: Dictionary = _ensure_flora_payload()
	if not flora_payload.is_empty():
		return ChunkFloraResultScript.build_render_packet_from_payload(flora_payload, _tile_size)
	if _flora_result == null:
		return {}
	return _flora_result.build_render_packet(_tile_size)

func _clear_flora_renderer() -> void:
	if _flora_renderer != null:
		_flora_renderer.clear_render_packet()

func _apply_flora_render_packet(packet: Dictionary, mode: StringName) -> void:
	if _flora_renderer == null:
		return
	if packet.is_empty():
		_clear_flora_renderer()
	else:
		_flora_renderer.set_render_packet(packet)
	_log_flora_publish_summary(mode, 1 if not packet.is_empty() else 0)

func _ensure_flora_payload() -> Dictionary:
	if _flora_payload.is_empty() and _flora_result != null:
		_flora_payload = _flora_result.to_serialized_payload(_tile_size)
	return _flora_payload

func _get_prebuilt_flora_render_packet(payload: Dictionary) -> Dictionary:
	if payload.is_empty():
		return {}
	var tile_size: int = int(payload.get("render_packet_tile_size", 0))
	if tile_size > 0 and tile_size != _tile_size:
		return {}
	return payload.get("render_packet", {}) as Dictionary

func _advance_redraw_phase() -> void:
	match _redraw_phase:
		REDRAW_PHASE_TERRAIN:
			_mark_interior_macro_dirty()
			_redraw_phase = REDRAW_PHASE_COVER
		REDRAW_PHASE_COVER:
			_redraw_phase = REDRAW_PHASE_CLIFF
		REDRAW_PHASE_CLIFF:
			_redraw_phase = REDRAW_PHASE_FLORA
		REDRAW_PHASE_FLORA:
			if _should_build_debug_markers():
				_redraw_phase = REDRAW_PHASE_DEBUG_INTERIOR
			else:
				_redraw_phase = REDRAW_PHASE_DONE
		REDRAW_PHASE_DEBUG_INTERIOR:
			_redraw_phase = REDRAW_PHASE_DEBUG_COLLISION
		REDRAW_PHASE_DEBUG_COLLISION:
			_redraw_phase = REDRAW_PHASE_DONE
		_:
			_redraw_phase = REDRAW_PHASE_DONE
	_redraw_tile_index = 0

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
	var poly := Polygon2D.new()
	poly.color = color
	var half: Vector2 = size * 0.5
	poly.position = center
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	_debug_root.add_child(poly)
