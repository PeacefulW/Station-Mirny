class_name ChunkView
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const ChunkDebugVisualLayer = preload("res://core/systems/world/chunk_debug_visual_layer.gd")
const ChunkRoofLayerBridge = preload("res://core/systems/world/chunk_roof_layer_bridge.gd")
const ChunkVisualBridge = preload("res://core/systems/world/chunk_visual_bridge.gd")
const TerrainVisualPacketBackend = preload(
	"res://core/systems/world/terrain_visual_packet_backend.gd"
)

var chunk_coord: Vector2i = Vector2i.ZERO

var _base_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var _water_layer: TileMapLayer = null
var _debug_layer: ChunkDebugVisualLayer = null
var _roof_bridge: ChunkRoofLayerBridge = ChunkRoofLayerBridge.new()
var roof_layers_by_mountain: Dictionary = _roof_bridge.layers_by_mountain
var _pending_terrain_ids: PackedInt32Array = PackedInt32Array()
var _pending_terrain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _pending_walkable_flags: PackedByteArray = PackedByteArray()
var _pending_lake_flags: PackedByteArray = PackedByteArray()
var _pending_mountain_ids: PackedInt32Array = PackedInt32Array()
var _pending_mountain_flags: PackedByteArray = PackedByteArray()
var _pending_mountain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _apply_index: int = 0
var _debug_grid_visible: bool = false
var _debug_solid_mask_visible: bool = false
var _debug_contour_visible: bool = false
var _debug_solid_mask: PackedByteArray = PackedByteArray()
var _debug_contour_vertices: PackedVector2Array = PackedVector2Array()
var _debug_contour_indices: PackedInt32Array = PackedInt32Array()
var _visual_bridge: ChunkVisualBridge = ChunkVisualBridge.new()


func _exit_tree() -> void:
	_visual_bridge.clear()
	_roof_bridge.clear()


func configure(new_chunk_coord: Vector2i) -> void:
	chunk_coord = new_chunk_coord
	position = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_visual_bridge.configure(self)
	_roof_bridge.configure(self, chunk_coord)
	_ensure_layers()


func begin_apply(packet: Dictionary) -> void:
	_pending_terrain_ids = _packet_int_array(packet, "terrain_ids")
	_pending_terrain_atlas_indices = _packet_int_array(packet, "terrain_atlas_indices")
	_pending_walkable_flags = _packet_byte_array(packet, "walkable_flags")
	_pending_lake_flags = _packet_byte_array(packet, "lake_flags")
	if _pending_lake_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_pending_lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_pending_mountain_ids = _packet_int_array(packet, "mountain_id_per_tile")
	_pending_mountain_flags = _packet_byte_array(packet, "mountain_flags")
	_pending_mountain_atlas_indices = _packet_int_array(packet, "mountain_atlas_indices")
	_apply_index = 0
	visible = false
	_ensure_layers()
	if _visual_bridge.is_enabled():
		_roof_bridge.clear_layers()
		_visual_bridge.begin_chunk_apply(packet)
	_refresh_debug_solid_mask()


func _packet_int_array(packet: Dictionary, key: String) -> PackedInt32Array:
	return (packet.get(key, PackedInt32Array()) as PackedInt32Array).duplicate()


func _packet_byte_array(packet: Dictionary, key: String) -> PackedByteArray:
	return (packet.get(key, PackedByteArray()) as PackedByteArray).duplicate()


func apply_next_batch(batch_size: int) -> bool:
	if _pending_terrain_ids.is_empty():
		return false
	var end_index: int = mini(_apply_index + batch_size, _pending_terrain_ids.size())
	for index: int in range(_apply_index, end_index):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var terrain_id: int = int(_pending_terrain_ids[index])
		var terrain_atlas_index: int = 0
		if index < _pending_terrain_atlas_indices.size():
			terrain_atlas_index = int(_pending_terrain_atlas_indices[index])
		_apply_cell(local_coord, terrain_id, terrain_atlas_index)
		_apply_water_cell(local_coord, index)
		_apply_roof_cell(local_coord, index)
	_apply_index = end_index
	if _apply_index >= _pending_terrain_ids.size():
		return false
	return true


func apply_runtime_cell(
		local_coord: Vector2i,
		terrain_id: int,
		terrain_atlas_index: int,
		walkable: bool = true,
		mountain_id: int = 0,
		mountain_flags: int = 0,
) -> void:
	_ensure_layers()
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index >= 0 and index < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		if _pending_terrain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_terrain_ids[index] = terrain_id
		if _pending_terrain_atlas_indices.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
		_pending_terrain_atlas_indices[index] = terrain_atlas_index
		if _pending_walkable_flags.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
		_pending_walkable_flags[index] = 1 if walkable else 0
		if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			if _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
				_pending_mountain_ids[index] = 0
			if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
				_pending_mountain_flags[index] = 0
		elif mountain_id > 0 \
				and _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_mountain_ids[index] = mountain_id
			if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
				_pending_mountain_flags[index] = mountain_flags
	_apply_cell(local_coord, terrain_id, terrain_atlas_index)
	_apply_water_patch_around(local_coord)
	_refresh_debug_solid_mask()
	if _visual_bridge.is_enabled():
		_visual_bridge.mark_dirty_patch(local_coord)


func set_terrain_visual_v2_enabled(enabled: bool) -> void:
	_visual_bridge.set_enabled(enabled)


func set_terrain_visual_recipe(recipe: Resource) -> void:
	_visual_bridge.set_recipe(recipe)


func set_terrain_visual_packet_backend(packet_backend: TerrainVisualPacketBackend) -> void:
	_visual_bridge.set_packet_backend(packet_backend)


func set_terrain_visual_solid_halo(solid_halo: PackedByteArray) -> void:
	_visual_bridge.set_solid_halo(solid_halo)


func set_terrain_visual_world_wrap_width_tiles(width_tiles: int) -> void:
	_visual_bridge.set_world_wrap_width_tiles(width_tiles)


func get_terrain_visual_v2_debug_state() -> Dictionary:
	return _visual_bridge.get_debug_state()


func is_terrain_visual_v2_active() -> bool:
	return _visual_bridge.is_enabled()


func is_terrain_visual_v2_ready() -> bool:
	return _visual_bridge.is_ready()


func is_terrain_visual_v2_solid_at_world(world_pos: Vector2) -> bool:
	return _visual_bridge.is_solid_at_world(world_pos)


func apply_pending_terrain_visual_v2_patch() -> bool:
	return _visual_bridge.apply_dirty_patch(
		chunk_coord,
		_pending_mountain_ids,
		_pending_mountain_flags,
	)


func apply_pending_terrain_visual_v2_full() -> bool:
	return _visual_bridge.apply_full_pending(
		chunk_coord,
		_pending_mountain_ids,
		_pending_mountain_flags,
	)


func set_debug_overlays(
		grid_visible: bool,
		solid_mask_visible: bool,
		contour_visible: bool,
) -> void:
	_debug_grid_visible = grid_visible
	_debug_solid_mask_visible = solid_mask_visible
	_debug_contour_visible = contour_visible
	_sync_debug_layer()


func apply_contour_debug_data(
		solid_mask: PackedByteArray,
		contour_vertices: PackedVector2Array,
		contour_indices: PackedInt32Array,
) -> void:
	_debug_solid_mask = solid_mask.duplicate()
	if _debug_solid_mask.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_debug_solid_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_debug_contour_vertices = contour_vertices.duplicate()
	_debug_contour_indices = contour_indices.duplicate()
	_sync_debug_layer()


func get_mountain_contour_debug_state() -> Dictionary:
	if _debug_layer != null and is_instance_valid(_debug_layer):
		return _debug_layer.get_debug_state()
	return {
		"chunk_coord": chunk_coord,
		"grid_visible": _debug_grid_visible,
		"solid_mask_visible": _debug_solid_mask_visible,
		"contour_visible": _debug_contour_visible,
		"solid_tile_count": _count_debug_solid_tiles(),
		"contour_vertex_count": _debug_contour_vertices.size(),
		"contour_index_count": _debug_contour_indices.size(),
		"contour_triangle_count": _debug_contour_indices.size() / 3,
	}


func apply_cover_visibility(visible_mask: PackedByteArray) -> void:
	_ensure_layers()
	_roof_bridge.apply_cover_visibility(
		visible_mask,
		_pending_mountain_ids,
		_pending_mountain_flags,
	)


func _ensure_layers() -> void:
	if _base_layer != null \
			and is_instance_valid(_base_layer) \
			and _overlay_layer != null \
			and is_instance_valid(_overlay_layer):
		return
	if _base_layer == null or not is_instance_valid(_base_layer):
		_base_layer = TileMapLayer.new()
		_base_layer.name = "TerrainBaseLayer"
		_base_layer.tile_set = WorldTileSetFactory.get_base_tile_set()
		_base_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_base_layer)
	if _overlay_layer == null or not is_instance_valid(_overlay_layer):
		_overlay_layer = TileMapLayer.new()
		_overlay_layer.name = "TerrainOverlayLayer"
		_overlay_layer.tile_set = WorldTileSetFactory.get_overlay_tile_set()
		_overlay_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_overlay_layer.z_index = 1
		add_child(_overlay_layer)


func _ensure_water_layer() -> TileMapLayer:
	if _water_layer != null and is_instance_valid(_water_layer):
		return _water_layer
	_water_layer = TileMapLayer.new()
	_water_layer.name = "WaterSurfaceLayer"
	_water_layer.tile_set = WorldTileSetFactory.get_water_tile_set()
	_water_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_water_layer.z_index = 0
	add_child(_water_layer)
	return _water_layer


func _ensure_debug_layer() -> ChunkDebugVisualLayer:
	if _debug_layer != null and is_instance_valid(_debug_layer):
		return _debug_layer
	_debug_layer = ChunkDebugVisualLayer.new()
	_debug_layer.name = "ChunkDebugVisualLayer"
	_debug_layer.configure(chunk_coord)
	add_child(_debug_layer)
	return _debug_layer


func _apply_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if _uses_terrain_visual_v2_mountain_surface(terrain_id):
		_apply_terrain_visual_v2_underlay_cell(local_coord)
		return
	if WorldTileSetFactory.uses_overlay_layer(terrain_id):
		_clear_cell(_base_layer, local_coord)
		_overlay_layer.set_cell(
			local_coord,
			WorldTileSetFactory.get_source_id(terrain_id),
			WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index),
		)
		return
	_clear_cell(_overlay_layer, local_coord)
	_base_layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_source_id(terrain_id),
		WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index),
	)


func _uses_terrain_visual_v2_mountain_surface(terrain_id: int) -> bool:
	if not _visual_bridge.is_enabled():
		return false
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT


func _apply_terrain_visual_v2_underlay_cell(local_coord: Vector2i) -> void:
	_clear_cell(_overlay_layer, local_coord)
	_base_layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
		WorldTileSetFactory.get_atlas_coords(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, 0),
	)


func _apply_roof_cell(local_coord: Vector2i, index: int) -> void:
	if _visual_bridge.is_enabled():
		return
	if index < 0 \
			or index >= _pending_mountain_ids.size() \
			or index >= _pending_mountain_flags.size():
		return
	var mountain_id: int = int(_pending_mountain_ids[index])
	var mountain_flags: int = int(_pending_mountain_flags[index])
	if not _roof_bridge.is_roof_bearing_mountain_tile(mountain_id, mountain_flags):
		return
	var terrain_atlas_index: int = 0
	if index < _pending_mountain_atlas_indices.size():
		terrain_atlas_index = int(_pending_mountain_atlas_indices[index])
	var roof_terrain_id: int = _roof_bridge.resolve_roof_terrain_id_from_flags(mountain_flags)
	_roof_bridge.clear_other_roof_surface_cell(mountain_id, roof_terrain_id, local_coord)
	var layer: TileMapLayer = _roof_bridge.ensure_roof_layer(mountain_id, roof_terrain_id)
	layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_roof_source_id(roof_terrain_id),
		WorldTileSetFactory.get_atlas_coords(roof_terrain_id, terrain_atlas_index),
	)


func _apply_water_patch_around(local_coord: Vector2i) -> void:
	for offset: Vector2i in [
		Vector2i.ZERO,
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]:
		var patch_coord: Vector2i = local_coord + offset
		if not WorldRuntimeConstants.is_local_coord_valid(patch_coord):
			continue
		_apply_water_cell(patch_coord, WorldRuntimeConstants.local_to_index(patch_coord))


func _apply_water_cell(local_coord: Vector2i, index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if not _should_render_water_at(index):
		_clear_cell(_water_layer, local_coord)
		return
	var terrain_id: int = int(_pending_terrain_ids[index])
	var layer: TileMapLayer = _ensure_water_layer()
	layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_water_source_id(terrain_id),
		WorldTileSetFactory.get_water_atlas_coords(_resolve_water_atlas_index(local_coord)),
	)


func _clear_cell(layer: TileMapLayer, local_coord: Vector2i) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.set_cell(local_coord, -1, Vector2i(-1, -1))


func _refresh_debug_solid_mask() -> void:
	_debug_solid_mask = _build_debug_solid_mask()
	_sync_debug_layer_data()


func _build_debug_solid_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		if _is_debug_solid_mountain_index(index):
			mask[index] = 1
	return mask


func _is_debug_solid_mountain_index(index: int) -> bool:
	if index < 0 or index >= _pending_terrain_ids.size():
		return false
	var terrain_id: int = int(_pending_terrain_ids[index])
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if index < _pending_walkable_flags.size() and int(_pending_walkable_flags[index]) != 0:
		return false
	var debug_mountain_id := 1
	if _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
		debug_mountain_id = int(_pending_mountain_ids[index])
		if debug_mountain_id <= 0:
			return false
	if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
		var flags: int = int(_pending_mountain_flags[index])
		return _roof_bridge.is_roof_bearing_mountain_tile(
			debug_mountain_id,
			flags,
		)
	return true


func _sync_debug_layer() -> void:
	if not _debug_grid_visible and not _debug_solid_mask_visible and not _debug_contour_visible:
		if _debug_layer != null and is_instance_valid(_debug_layer):
			_debug_layer.set_debug_visibility(false, false, false)
		return
	var layer: ChunkDebugVisualLayer = _ensure_debug_layer()
	layer.set_debug_visibility(
		_debug_grid_visible,
		_debug_solid_mask_visible,
		_debug_contour_visible,
	)
	_sync_debug_layer_data()


func _sync_debug_layer_data() -> void:
	if _debug_layer == null or not is_instance_valid(_debug_layer):
		return
	_debug_layer.set_debug_data(_debug_solid_mask, _debug_contour_vertices, _debug_contour_indices)


func _count_debug_solid_tiles() -> int:
	var count: int = 0
	for value: int in _debug_solid_mask:
		if value != 0:
			count += 1
	return count


func _should_render_water_at(index: int) -> bool:
	if index < 0 \
			or index >= _pending_lake_flags.size() \
			or index >= _pending_terrain_ids.size():
		return false
	if (int(_pending_lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) == 0:
		return false
	return _is_lake_bed_terrain(int(_pending_terrain_ids[index]))


func _resolve_water_atlas_index(_local_coord: Vector2i) -> int:
	return 0


func _is_lake_bed_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
			or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP


func get_cover_render_debug(
		local_coord: Vector2i,
		mountain_id: int = 0,
		expected_open_bit: int = -1,
) -> Dictionary:
	return _roof_bridge.get_cover_render_debug(
		local_coord,
		mountain_id,
		expected_open_bit,
		_pending_mountain_ids,
		_pending_mountain_flags,
	)
