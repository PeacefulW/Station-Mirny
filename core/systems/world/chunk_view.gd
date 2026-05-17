class_name ChunkView
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const ChunkDebugVisualLayer = preload("res://core/systems/world/chunk_debug_visual_layer.gd")
const ChunkRoofVisualSupport = preload("res://core/systems/world/chunk_roof_visual_support.gd")
const TerrainVisualRuntimePresenter = preload(
	"res://core/systems/world/terrain_visual_runtime_presenter.gd"
)
const ROCK_VARIANT_D_SHADER = preload("res://assets/shaders/rock_variant_d.gdshader")
const ROCK_MASK_VALUE: int = 1
const ROCK_FILL_Z_INDEX: int = 11
const ROCK_OUTLINE_Z_INDEX: int = 12
const ROCK_OUTLINE_WIDTH_PX: float = 2.0
const ROCK_OUTLINE_ALPHA: float = 0.85

var chunk_coord: Vector2i = Vector2i.ZERO

var _base_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var _water_layer: TileMapLayer = null
var _debug_layer: ChunkDebugVisualLayer = null
var roof_layers_by_mountain: Dictionary = { }
var _roof_mask_images_by_mountain: Dictionary = { }
var _roof_mask_textures_by_mountain: Dictionary = { }
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
var _rock_visual: RockVisualResource = null
var _rock_visual_material: ShaderMaterial = null
var _rock_fill_layer: Node2D = null
var _rock_outline_layer: Node2D = null
var _rock_marching_squares: Object = null
var _did_warn_missing_rock_marching_squares: bool = false
var _rock_mask_image: Image = null
var _rock_mask_texture: ImageTexture = null
var _rock_sdf_texture: ImageTexture = null
var _terrain_visual_presenter: TerrainVisualRuntimePresenter = null


func _exit_tree() -> void:
	_clear_rock_regions()
	if _terrain_visual_presenter != null and is_instance_valid(_terrain_visual_presenter):
		_terrain_visual_presenter.clear()
	if _rock_marching_squares != null:
		_rock_marching_squares.free()
	_rock_marching_squares = null
	_roof_mask_images_by_mountain.clear()
	_roof_mask_textures_by_mountain.clear()


func configure(new_chunk_coord: Vector2i) -> void:
	chunk_coord = new_chunk_coord
	position = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_ensure_layers()


func begin_apply(packet: Dictionary) -> void:
	_pending_terrain_ids = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_terrain_atlas_indices = (packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_walkable_flags = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
	_pending_lake_flags = (packet.get("lake_flags", PackedByteArray()) as PackedByteArray).duplicate()
	if _pending_lake_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_pending_lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_pending_mountain_ids = (packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_mountain_flags = (packet.get("mountain_flags", PackedByteArray()) as PackedByteArray).duplicate()
	_pending_mountain_atlas_indices = (packet.get("mountain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	_apply_index = 0
	visible = false
	_ensure_layers()
	_clear_rock_regions()
	if _terrain_visual_presenter != null and _terrain_visual_presenter.is_enabled():
		_rock_visual = null
		_rock_visual_material = null
		_clear_roof_layers()
		_terrain_visual_presenter.begin_chunk_apply(packet)
	else:
		_rock_visual = _resolve_rock_visual_resource()
		_rock_visual_material = _build_rock_visual_material(_rock_visual)
	_refresh_debug_solid_mask()


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
		if _terrain_visual_presenter != null and _terrain_visual_presenter.is_enabled():
			_terrain_visual_presenter.apply_full_pending(
				chunk_coord,
				_pending_mountain_ids,
				_pending_mountain_flags,
			)
		else:
			_refresh_rock_regions()
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
	if _terrain_visual_presenter != null and _terrain_visual_presenter.is_enabled():
		_terrain_visual_presenter.mark_dirty_patch(local_coord)
	else:
		_refresh_rock_regions()


func set_terrain_visual_v2_enabled(enabled: bool) -> void:
	_ensure_terrain_visual_presenter().set_enabled(enabled)


func set_terrain_visual_recipe(recipe: Resource) -> void:
	_ensure_terrain_visual_presenter().set_recipe(recipe)


func get_terrain_visual_v2_debug_state() -> Dictionary:
	if _terrain_visual_presenter != null and is_instance_valid(_terrain_visual_presenter):
		return _terrain_visual_presenter.get_debug_state()
	return { "enabled": false }


func apply_pending_terrain_visual_v2_patch() -> bool:
	var tv := _terrain_visual_presenter
	if tv == null or not tv.is_enabled():
		return false
	return tv.apply_dirty_patch(chunk_coord, _pending_mountain_ids, _pending_mountain_flags)


func _ensure_terrain_visual_presenter() -> TerrainVisualRuntimePresenter:
	if _terrain_visual_presenter != null and is_instance_valid(_terrain_visual_presenter):
		return _terrain_visual_presenter
	_terrain_visual_presenter = TerrainVisualRuntimePresenter.new()
	_terrain_visual_presenter.name = "TerrainVisualV2RuntimePresenter"
	add_child(_terrain_visual_presenter)
	return _terrain_visual_presenter


func set_debug_overlays(grid_visible: bool, solid_mask_visible: bool, contour_visible: bool) -> void:
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
	var resolved_mask: PackedByteArray = visible_mask
	if resolved_mask.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		resolved_mask = PackedByteArray()
		resolved_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var updated_mountains: Dictionary = { }
	for mountain_id_variant: Variant in roof_layers_by_mountain.keys():
		var mountain_id: int = int(mountain_id_variant)
		var image: Image = _ensure_roof_mask_image(mountain_id)
		image.fill(Color(1.0, 0.0, 0.0, 1.0))
	for index: int in range(mini(_pending_mountain_ids.size(), _pending_mountain_flags.size())):
		var mountain_id: int = int(_pending_mountain_ids[index])
		var mountain_flags: int = int(_pending_mountain_flags[index])
		if not _is_roof_bearing_mountain_tile(mountain_id, mountain_flags):
			continue
		var image: Image = _ensure_roof_mask_image(mountain_id)
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var hide_value: float = 0.0 if resolved_mask[index] != 0 else 1.0
		image.set_pixel(local_coord.x, local_coord.y, Color(hide_value, 0.0, 0.0, 1.0))
		updated_mountains[mountain_id] = true
	for mountain_id_variant: Variant in updated_mountains.keys():
		var mountain_id: int = int(mountain_id_variant)
		var texture: ImageTexture = _roof_mask_textures_by_mountain.get(mountain_id, null) as ImageTexture
		var image: Image = _roof_mask_images_by_mountain.get(mountain_id, null) as Image
		if texture != null and image != null:
			texture.update(image)


func _resolve_rock_visual_resource() -> RockVisualResource:
	var registry: Node = get_node_or_null("/root/BiomeRegistry")
	if registry == null or not registry.has_method("get_default_biome"):
		return null
	var default_biome: Object = registry.call("get_default_biome") as Object
	if default_biome == null:
		return null
	return default_biome.get("rock_visual") as RockVisualResource


func _build_rock_visual_material(rock_visual: RockVisualResource) -> ShaderMaterial:
	if rock_visual == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = ROCK_VARIANT_D_SHADER
	_apply_rock_visual_uniforms(material, rock_visual)
	return material


func _apply_rock_visual_uniforms(material: ShaderMaterial, rock_visual: RockVisualResource) -> void:
	if material == null or rock_visual == null:
		return
	material.set_shader_parameter("top_color", rock_visual.top_color)
	material.set_shader_parameter("face_color", rock_visual.face_color)
	material.set_shader_parameter("back_color", rock_visual.back_color)
	material.set_shader_parameter("top_to_face_cutoff", rock_visual.top_to_face_cutoff)
	material.set_shader_parameter("face_to_back_cutoff", rock_visual.face_to_back_cutoff)
	material.set_shader_parameter("ledge_contrast", rock_visual.ledge_contrast)
	material.set_shader_parameter("top_coverage", rock_visual.top_coverage)
	material.set_shader_parameter("face_coverage", rock_visual.face_coverage)
	material.set_shader_parameter("back_coverage", rock_visual.back_coverage)
	material.set_shader_parameter("normal_strength", rock_visual.normal_strength)


func _refresh_rock_regions() -> void:
	_clear_rock_regions()
	if _rock_visual == null \
			or _rock_visual_material == null \
			or _pending_terrain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return
	var rock_mask: PackedInt32Array = _build_rock_mask_from_pending()
	var bounds: Rect2i = _compute_rock_bounds(rock_mask)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	_update_rock_mask_texture(rock_mask)
	_update_rock_sdf_texture(rock_mask)
	_spawn_unified_rock_polygon(bounds)
	var polylines: Array = _extract_rock_polylines(
		rock_mask,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
	)
	_spawn_rock_outlines(polylines)


func _build_rock_mask_from_pending() -> PackedInt32Array:
	var size: int = WorldRuntimeConstants.CHUNK_SIZE
	var cell_count: int = size * size
	var mask := PackedInt32Array()
	mask.resize(cell_count)
	if _pending_mountain_ids.size() != cell_count or _pending_mountain_flags.size() != cell_count:
		return mask
	for index: int in range(cell_count):
		var mountain_id: int = int(_pending_mountain_ids[index])
		var mountain_flags: int = int(_pending_mountain_flags[index])
		if _is_roof_bearing_mountain_tile(mountain_id, mountain_flags):
			mask[index] = ROCK_MASK_VALUE
	return mask


func _extract_rock_polylines(rock_mask: PackedInt32Array, width: int, height: int) -> Array:
	if width < 2 or height < 2:
		return []
	var marching_squares: Object = _ensure_rock_marching_squares()
	if marching_squares == null:
		return []
	var result: Variant = marching_squares.call(
		"extract_polylines",
		rock_mask,
		width,
		height,
		ROCK_MASK_VALUE,
	)
	return result as Array


func _ensure_rock_marching_squares() -> Object:
	if _rock_marching_squares != null and is_instance_valid(_rock_marching_squares):
		return _rock_marching_squares
	if not ClassDB.class_exists(&"RockMarchingSquares"):
		if not _did_warn_missing_rock_marching_squares:
			push_error("RockMarchingSquares native class is required for Variant D rock rendering.")
			_did_warn_missing_rock_marching_squares = true
		return null
	_rock_marching_squares = ClassDB.instantiate(&"RockMarchingSquares")
	if _rock_marching_squares == null and not _did_warn_missing_rock_marching_squares:
		push_error("Failed to instantiate RockMarchingSquares native class.")
		_did_warn_missing_rock_marching_squares = true
	return _rock_marching_squares


func _compute_rock_bounds(mask: PackedInt32Array) -> Rect2i:
	var size: int = WorldRuntimeConstants.CHUNK_SIZE
	var min_cell := Vector2i(size, size)
	var max_cell := Vector2i(-1, -1)
	for y: int in range(size):
		for x: int in range(size):
			if mask[y * size + x] == ROCK_MASK_VALUE:
				min_cell.x = mini(min_cell.x, x)
				min_cell.y = mini(min_cell.y, y)
				max_cell.x = maxi(max_cell.x, x)
				max_cell.y = maxi(max_cell.y, y)
	if max_cell.x < 0:
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


func _update_rock_mask_texture(mask: PackedInt32Array) -> void:
	var size: int = WorldRuntimeConstants.CHUNK_SIZE
	if _rock_mask_image == null:
		_rock_mask_image = Image.create(size, size, false, Image.FORMAT_R8)
	for y: int in range(size):
		for x: int in range(size):
			var is_rock: bool = mask[y * size + x] == ROCK_MASK_VALUE
			_rock_mask_image.set_pixel(x, y, Color(1.0 if is_rock else 0.0, 0.0, 0.0, 1.0))
	if _rock_mask_texture == null:
		_rock_mask_texture = ImageTexture.create_from_image(_rock_mask_image)
	else:
		_rock_mask_texture.update(_rock_mask_image)


func _update_rock_sdf_texture(mask: PackedInt32Array) -> void:
	var size: int = WorldRuntimeConstants.CHUNK_SIZE
	var sdf_image: Image = SdfHelper.compute_sdf_image(mask, size, size)
	if _rock_sdf_texture == null:
		_rock_sdf_texture = ImageTexture.create_from_image(sdf_image)
	else:
		_rock_sdf_texture.update(sdf_image)


func _spawn_unified_rock_polygon(bounds: Rect2i) -> void:
	var fill_parent: Node2D = _ensure_rock_fill_layer()
	var tile_px: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	var bbox_min := Vector2(float(bounds.position.x), float(bounds.position.y))
	var bbox_max := Vector2(
		float(bounds.position.x + bounds.size.x),
		float(bounds.position.y + bounds.size.y),
	)
	var rect_pixels := PackedVector2Array(
		[
			bbox_min * tile_px,
			Vector2(bbox_max.x, bbox_min.y) * tile_px,
			bbox_max * tile_px,
			Vector2(bbox_min.x, bbox_max.y) * tile_px,
		],
	)
	var rect_uv := PackedVector2Array(
		[
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
			Vector2(1.0, 1.0),
			Vector2(0.0, 1.0),
		],
	)
	var polygon := Polygon2D.new()
	polygon.polygon = rect_pixels
	polygon.uv = rect_uv
	# Bind SDF as TEXTURE — shader reads it via texture(TEXTURE, uv). Required
	# also to keep canvas_item UV interpolation alive.
	polygon.texture = _rock_sdf_texture
	polygon.material = _rock_visual_material
	var size: int = WorldRuntimeConstants.CHUNK_SIZE
	_rock_visual_material.set_shader_parameter("mask_size", Vector2(size, size))
	_rock_visual_material.set_shader_parameter("bbox_min", bbox_min)
	_rock_visual_material.set_shader_parameter("bbox_max", bbox_max)
	_rock_visual_material.set_shader_parameter("sdf_max_dist", SdfHelper.max_dist_for(size, size))
	fill_parent.add_child(polygon)


func _spawn_rock_outlines(polylines: Array) -> void:
	var outline_parent: Node2D = _ensure_rock_outline_layer()
	var outline_color: Color = _resolve_rock_outline_color()
	var tile_px: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	for polyline_variant: Variant in polylines:
		var polyline: PackedVector2Array = polyline_variant as PackedVector2Array
		if polyline.size() < 2:
			continue
		var pixels := PackedVector2Array()
		pixels.resize(polyline.size())
		for i: int in range(polyline.size()):
			pixels[i] = polyline[i] * tile_px
		var line := Line2D.new()
		line.points = pixels
		line.closed = polyline.size() > 2
		line.width = ROCK_OUTLINE_WIDTH_PX
		line.default_color = outline_color
		outline_parent.add_child(line)


func _resolve_rock_outline_color() -> Color:
	if _rock_visual == null:
		return Color(0.08, 0.08, 0.08, ROCK_OUTLINE_ALPHA)
	var color: Color = _rock_visual.face_color.lerp(_rock_visual.back_color, 0.6)
	color.a = ROCK_OUTLINE_ALPHA
	return color


func _clear_rock_regions() -> void:
	if _rock_fill_layer != null and is_instance_valid(_rock_fill_layer):
		for child: Node in _rock_fill_layer.get_children():
			child.queue_free()
	if _rock_outline_layer != null and is_instance_valid(_rock_outline_layer):
		for child: Node in _rock_outline_layer.get_children():
			child.queue_free()


func _clear_roof_layers() -> void:
	for terrain_layers_variant: Variant in roof_layers_by_mountain.values():
		var terrain_layers: Dictionary = terrain_layers_variant as Dictionary
		for layer_variant: Variant in terrain_layers.values():
			var layer: TileMapLayer = layer_variant as TileMapLayer
			if layer != null and is_instance_valid(layer):
				layer.queue_free()
	roof_layers_by_mountain.clear()
	_roof_mask_images_by_mountain.clear()
	_roof_mask_textures_by_mountain.clear()


func _ensure_rock_fill_layer() -> Node2D:
	if _rock_fill_layer != null and is_instance_valid(_rock_fill_layer):
		return _rock_fill_layer
	_rock_fill_layer = Node2D.new()
	_rock_fill_layer.name = "RockFillLayer"
	_rock_fill_layer.z_index = ROCK_FILL_Z_INDEX
	add_child(_rock_fill_layer)
	return _rock_fill_layer


func _ensure_rock_outline_layer() -> Node2D:
	if _rock_outline_layer != null and is_instance_valid(_rock_outline_layer):
		return _rock_outline_layer
	_rock_outline_layer = Node2D.new()
	_rock_outline_layer.name = "RockOutlineLayer"
	_rock_outline_layer.z_index = ROCK_OUTLINE_Z_INDEX
	add_child(_rock_outline_layer)
	return _rock_outline_layer


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


func _ensure_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, { }) as Dictionary
	if terrain_layers.has(roof_terrain_id):
		return terrain_layers[roof_terrain_id] as TileMapLayer
	var layer := TileMapLayer.new()
	layer.name = "RoofLayer_%d_%s" % [mountain_id, _get_roof_terrain_name(roof_terrain_id)]
	layer.tile_set = WorldTileSetFactory.get_roof_tile_set(roof_terrain_id)
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_index = 10
	layer.material = _build_roof_material(mountain_id, roof_terrain_id)
	add_child(layer)
	terrain_layers[roof_terrain_id] = layer
	roof_layers_by_mountain[mountain_id] = terrain_layers
	return layer


func _apply_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
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


func _apply_roof_cell(local_coord: Vector2i, index: int) -> void:
	# Variant D rock rendering supersedes the 47-blob roof atlas for biomes
	# that ship a RockVisualResource. Without this suppression the roof
	# atlas paints stepped tile borders on top of the procedural Polygon2D,
	# defeating the organic silhouette goal (spec anti-pattern 7).
	if _rock_visual != null or (_terrain_visual_presenter != null and _terrain_visual_presenter.is_enabled()):
		return
	if index < 0 or index >= _pending_mountain_ids.size() or index >= _pending_mountain_flags.size():
		return
	var mountain_id: int = int(_pending_mountain_ids[index])
	var mountain_flags: int = int(_pending_mountain_flags[index])
	if not _is_roof_bearing_mountain_tile(mountain_id, mountain_flags):
		return
	var terrain_atlas_index: int = 0
	if index < _pending_mountain_atlas_indices.size():
		terrain_atlas_index = int(_pending_mountain_atlas_indices[index])
	var roof_terrain_id: int = _resolve_roof_terrain_id_from_flags(mountain_flags)
	_clear_other_roof_surface_cell(mountain_id, roof_terrain_id, local_coord)
	var layer: TileMapLayer = _ensure_roof_layer(mountain_id, roof_terrain_id)
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
	if _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT \
			and int(_pending_mountain_ids[index]) <= 0:
		return false
	if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
		var flags: int = int(_pending_mountain_flags[index])
		return (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0
	return true


func _sync_debug_layer() -> void:
	if not _debug_grid_visible and not _debug_solid_mask_visible and not _debug_contour_visible:
		if _debug_layer != null and is_instance_valid(_debug_layer):
			_debug_layer.set_debug_visibility(false, false, false)
		return
	var layer: ChunkDebugVisualLayer = _ensure_debug_layer()
	layer.set_debug_visibility(_debug_grid_visible, _debug_solid_mask_visible, _debug_contour_visible)
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


func _build_roof_material(mountain_id: int, terrain_id: int) -> ShaderMaterial:
	return ChunkRoofVisualSupport.build_roof_material(
		chunk_coord,
		mountain_id,
		terrain_id,
		_ensure_roof_mask_texture(mountain_id),
	)


func _get_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, { }) as Dictionary
	return terrain_layers.get(roof_terrain_id, null) as TileMapLayer


func _clear_other_roof_surface_cell(mountain_id: int, terrain_id: int, local_coord: Vector2i) -> void:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, { }) as Dictionary
	for layer_terrain_id_variant: Variant in terrain_layers.keys():
		var layer_terrain_id: int = int(layer_terrain_id_variant)
		if layer_terrain_id == roof_terrain_id:
			continue
		_clear_cell(terrain_layers.get(layer_terrain_id, null) as TileMapLayer, local_coord)


func _resolve_roof_terrain_id_from_flags(mountain_flags: int) -> int:
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_WALL) != 0:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT) != 0:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL


func _resolve_roof_terrain_id(terrain_id: int) -> int:
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL


func _get_roof_terrain_name(terrain_id: int) -> String:
	if _resolve_roof_terrain_id(terrain_id) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return "foot"
	return "wall"


func _ensure_roof_mask_image(mountain_id: int) -> Image:
	if _roof_mask_images_by_mountain.has(mountain_id):
		return _roof_mask_images_by_mountain[mountain_id] as Image
	var image: Image = Image.create(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_L8,
	)
	image.fill(Color(1.0, 0.0, 0.0, 1.0))
	_roof_mask_images_by_mountain[mountain_id] = image
	return image


func _ensure_roof_mask_texture(mountain_id: int) -> ImageTexture:
	if _roof_mask_textures_by_mountain.has(mountain_id):
		return _roof_mask_textures_by_mountain[mountain_id] as ImageTexture
	var texture: ImageTexture = ImageTexture.create_from_image(_ensure_roof_mask_image(mountain_id))
	_roof_mask_textures_by_mountain[mountain_id] = texture
	return texture


func get_cover_render_debug(local_coord: Vector2i, mountain_id: int = 0, expected_open_bit: int = -1) -> Dictionary:
	return ChunkRoofVisualSupport.get_cover_render_debug(
		local_coord,
		mountain_id,
		expected_open_bit,
		_pending_mountain_ids,
		_pending_mountain_flags,
		roof_layers_by_mountain,
		_roof_mask_images_by_mountain,
	)


func _is_roof_bearing_mountain_tile(mountain_id: int, mountain_flags: int) -> bool:
	return mountain_id > 0 \
			and (mountain_flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0
