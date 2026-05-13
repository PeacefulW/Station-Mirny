class_name ChunkView
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const ChunkDebugVisualLayer = preload("res://core/systems/world/chunk_debug_visual_layer.gd")
const MOUNTAIN_COVER_SHADER = preload("res://assets/shaders/mountain_cover_overlay.gdshader")
const CONTOUR_GROUND_SHADER = preload("res://assets/shaders/contour_ground_material.gdshader")
const CONTOUR_MOUNTAIN_SHADER = preload("res://assets/shaders/contour_mountain_material.gdshader")

const CONTOUR_GROUND_Z_INDEX: int = 0
const CONTOUR_WATER_Z_INDEX: int = 1
const CONTOUR_MOUNTAIN_Z_INDEX: int = 10
const CONTOUR_DEBUG_Z_INDEX: int = 100
const FALLBACK_MOUNTAIN_CONTOUR_ID: int = -1

var chunk_coord: Vector2i = Vector2i.ZERO

var _base_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var _water_layer: TileMapLayer = null
var _debug_layer: ChunkDebugVisualLayer = null
var _contour_root: Node2D = null
var _contour_ground_visual: Sprite2D = null
var _contour_mountain_visuals_by_id: Dictionary = {}
var _contour_membership_images_by_mountain: Dictionary = {}
var _contour_membership_textures_by_mountain: Dictionary = {}
var roof_layers_by_mountain: Dictionary = {}
var _roof_mask_images_by_mountain: Dictionary = {}
var _roof_mask_textures_by_mountain: Dictionary = {}
var _pending_terrain_ids: PackedInt32Array = PackedInt32Array()
var _pending_terrain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _pending_walkable_flags: PackedByteArray = PackedByteArray()
var _pending_lake_flags: PackedByteArray = PackedByteArray()
var _pending_mountain_ids: PackedInt32Array = PackedInt32Array()
var _pending_mountain_flags: PackedByteArray = PackedByteArray()
var _pending_mountain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _apply_index: int = 0
var _contour_rendering_enabled: bool = false
var _contour_render_ready: bool = false
var _contour_render_stale: bool = false
var _target_tilemap_apply_count: int = 0
var _debug_grid_visible: bool = false
var _debug_solid_mask_visible: bool = false
var _debug_contour_visible: bool = false
var _debug_solid_mask: PackedByteArray = PackedByteArray()
var _debug_contour_vertices: PackedVector2Array = PackedVector2Array()
var _debug_contour_indices: PackedInt32Array = PackedInt32Array()

func _exit_tree() -> void:
	_roof_mask_images_by_mountain.clear()
	_roof_mask_textures_by_mountain.clear()
	_contour_membership_images_by_mountain.clear()
	_contour_membership_textures_by_mountain.clear()
	_contour_mountain_visuals_by_id.clear()

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
	_target_tilemap_apply_count = 0
	_contour_render_ready = false
	_contour_render_stale = false
	visible = false
	_ensure_layers()
	if _contour_rendering_enabled:
		_clear_tilemap_terrain_layers()
		_clear_roof_tile_layers()
		_clear_contour_visuals()
		_contour_membership_images_by_mountain.clear()
		_contour_membership_textures_by_mountain.clear()
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
		if not _is_contour_cutover_terrain(terrain_id):
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
	mountain_flags: int = 0
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
		elif mountain_id > 0 and _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_mountain_ids[index] = mountain_id
			if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
				_pending_mountain_flags[index] = mountain_flags
	_apply_cell(local_coord, terrain_id, terrain_atlas_index)
	_apply_water_patch_around(local_coord)
	_refresh_debug_solid_mask()

func apply_runtime_contour_cell_state(
	local_coord: Vector2i,
	terrain_id: int,
	walkable: bool = true,
	mountain_id: int = 0,
	mountain_flags: int = 0
) -> void:
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index < 0 or index >= WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return
	if _pending_terrain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_pending_terrain_ids[index] = terrain_id
	if _pending_terrain_atlas_indices.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_pending_terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_pending_terrain_atlas_indices[index] = 0
	if _pending_walkable_flags.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_pending_walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_pending_walkable_flags[index] = 1 if walkable else 0
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		if _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_mountain_ids[index] = 0
		if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_mountain_flags[index] = 0
	elif mountain_id > 0 and _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_pending_mountain_ids[index] = mountain_id
		if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_mountain_flags[index] = mountain_flags
	if _debug_solid_mask_visible or _debug_contour_visible:
		_refresh_debug_solid_mask()

func set_contour_rendering_enabled(enabled: bool) -> void:
	_contour_rendering_enabled = enabled
	_target_tilemap_apply_count = 0
	_ensure_layers()
	if not enabled:
		_clear_contour_visuals()
		_contour_render_ready = false
		_contour_render_stale = false
		return
	_ensure_contour_root()
	_clear_tilemap_terrain_layers()
	_clear_roof_tile_layers()
	_contour_render_ready = false
	_contour_render_stale = false
	visible = false

func apply_contour_results(results_by_class: Dictionary, required_diff_revision: int) -> void:
	if not _contour_rendering_enabled:
		return
	_ensure_layers()
	_ensure_contour_root()
	var ground_result: Dictionary = results_by_class.get(
		WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE,
		{}
	) as Dictionary
	var mountain_result: Dictionary = results_by_class.get(
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
		{}
	) as Dictionary
	if not _is_contour_result_fresh(ground_result, required_diff_revision) \
			or not _is_contour_result_fresh(mountain_result, required_diff_revision):
		_clear_contour_visuals()
		_contour_render_ready = false
		_contour_render_stale = true
		visible = false
		return
	var ground_textures: Dictionary = _build_contour_textures(ground_result)
	var mountain_textures: Dictionary = _build_contour_textures(mountain_result)
	if ground_textures.is_empty() or mountain_textures.is_empty():
		_clear_contour_visuals()
		_contour_render_ready = false
		_contour_render_stale = false
		visible = false
		return
	_apply_ground_contour_visual(ground_textures)
	_apply_mountain_contour_visuals(mountain_textures)
	_contour_render_ready = true
	_contour_render_stale = false
	visible = true

func mark_contour_render_stale() -> void:
	if not _contour_rendering_enabled:
		return
	_contour_render_ready = false
	_contour_render_stale = true
	if _has_valid_contour_ground_visual() or _count_valid_mountain_contour_visuals() > 0:
		visible = true

func get_contour_render_debug_state() -> Dictionary:
	var ground_state: Dictionary = _build_contour_visual_debug_state(_contour_ground_visual)
	var mountain_states: Array = []
	var mountain_ids: Array = _contour_mountain_visuals_by_id.keys()
	mountain_ids.sort()
	for mountain_id_variant: Variant in mountain_ids:
		var mountain_id: int = int(mountain_id_variant)
		var state: Dictionary = _build_contour_visual_debug_state(
			_contour_mountain_visuals_by_id[mountain_id] as Sprite2D
		)
		state["mountain_id"] = mountain_id
		state["has_cover_mask"] = _visual_has_shader_parameter(
			_contour_mountain_visuals_by_id[mountain_id] as Sprite2D,
			&"cover_mask"
		)
		mountain_states.append(state)
	var mask_texture_instance_id: int = 0
	if _contour_ground_visual != null \
			and is_instance_valid(_contour_ground_visual) \
			and _contour_ground_visual.texture != null:
		mask_texture_instance_id = _contour_ground_visual.texture.get_instance_id()
	return {
		"ready": _contour_render_ready,
		"stale": _contour_render_stale,
		"enabled": _contour_rendering_enabled,
		"visible": visible,
		"target_tilemap_apply_count": _target_tilemap_apply_count,
		"target_tilemap_cell_count": _count_target_tilemap_cells(),
		"ground_visual_count": 1 if _has_valid_contour_ground_visual() else 0,
		"mountain_bucket_count": _count_valid_mountain_contour_visuals(),
		"mask_texture_instance_id": mask_texture_instance_id,
		"ground": ground_state,
		"mountain_buckets": mountain_states,
	}

func set_debug_overlays(grid_visible: bool, solid_mask_visible: bool, contour_visible: bool) -> void:
	_debug_grid_visible = grid_visible
	_debug_solid_mask_visible = solid_mask_visible
	_debug_contour_visible = contour_visible
	_sync_debug_layer()

func apply_contour_debug_data(
	solid_mask: PackedByteArray,
	contour_vertices: PackedVector2Array,
	contour_indices: PackedInt32Array
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
	var updated_mountains: Dictionary = {}
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
		_base_layer.z_index = 0
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
	_water_layer.z_index = CONTOUR_WATER_Z_INDEX
	add_child(_water_layer)
	return _water_layer

func _ensure_debug_layer() -> ChunkDebugVisualLayer:
	if _debug_layer != null and is_instance_valid(_debug_layer):
		return _debug_layer
	_debug_layer = ChunkDebugVisualLayer.new()
	_debug_layer.name = "ChunkDebugVisualLayer"
	_debug_layer.configure(chunk_coord)
	_debug_layer.z_index = CONTOUR_DEBUG_Z_INDEX
	add_child(_debug_layer)
	return _debug_layer

func _ensure_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {}) as Dictionary
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

func _ensure_contour_root() -> Node2D:
	if _contour_root != null and is_instance_valid(_contour_root):
		return _contour_root
	_contour_root = Node2D.new()
	_contour_root.name = "ContourVisualLayer"
	_contour_root.z_index = CONTOUR_GROUND_Z_INDEX
	add_child(_contour_root)
	return _contour_root

func _is_contour_result_fresh(result: Dictionary, required_diff_revision: int) -> bool:
	if result.is_empty():
		return false
	if not bool(result.get("ready", false)):
		return false
	if int(result.get("diff_revision", -1)) != required_diff_revision:
		return false
	var pixel_size: Vector2i = result.get("pixel_size", Vector2i.ZERO) as Vector2i
	return pixel_size.x > 0 and pixel_size.y > 0

func _build_contour_textures(result: Dictionary) -> Dictionary:
	var pixel_size: Vector2i = result.get("pixel_size", Vector2i.ZERO) as Vector2i
	if pixel_size.x <= 0 or pixel_size.y <= 0:
		return {}
	var pixel_count: int = pixel_size.x * pixel_size.y
	var mask_bytes: PackedByteArray = result.get("mask_rgba8", PackedByteArray()) as PackedByteArray
	var height_bytes: PackedByteArray = result.get("height_r16", PackedByteArray()) as PackedByteArray
	var normal_bytes: PackedByteArray = result.get("normal_rgba8", PackedByteArray()) as PackedByteArray
	if mask_bytes.size() != pixel_count * 4 \
			or height_bytes.size() != pixel_count * 2 \
			or normal_bytes.size() != pixel_count * 4:
		return {}
	var mask_image: Image = Image.create_from_data(
		pixel_size.x,
		pixel_size.y,
		false,
		Image.FORMAT_RGBA8,
		mask_bytes
	)
	var height_image: Image = Image.create_from_data(
		pixel_size.x,
		pixel_size.y,
		false,
		Image.FORMAT_RH,
		height_bytes
	)
	var normal_image: Image = Image.create_from_data(
		pixel_size.x,
		pixel_size.y,
		false,
		Image.FORMAT_RGBA8,
		normal_bytes
	)
	return {
		"pixel_size": pixel_size,
		"mask": ImageTexture.create_from_image(mask_image),
		"height": ImageTexture.create_from_image(height_image),
		"normal": ImageTexture.create_from_image(normal_image),
		"has_visual_coverage": bool(result.get("has_visual_coverage", false)),
	}

func _apply_ground_contour_visual(textures: Dictionary) -> void:
	var visual: Sprite2D = _ensure_ground_contour_visual()
	visual.texture = textures.get("mask", null) as Texture2D
	_apply_contour_visual_size(visual, textures.get("pixel_size", Vector2i.ZERO) as Vector2i)
	var material: ShaderMaterial = _ensure_contour_material(
		visual,
		CONTOUR_GROUND_SHADER,
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
	)
	_apply_common_contour_shader_params(material, textures)

func _apply_mountain_contour_visuals(textures: Dictionary) -> void:
	var active_mountain_ids: Array = _collect_contour_mountain_ids()
	if active_mountain_ids.is_empty() and bool(textures.get("has_visual_coverage", false)):
		active_mountain_ids = [FALLBACK_MOUNTAIN_CONTOUR_ID]
	var active_lookup: Dictionary = {}
	for mountain_id_variant: Variant in active_mountain_ids:
		var mountain_id: int = int(mountain_id_variant)
		active_lookup[mountain_id] = true
		var visual: Sprite2D = _ensure_mountain_contour_visual(mountain_id)
		visual.texture = textures.get("mask", null) as Texture2D
		_apply_contour_visual_size(visual, textures.get("pixel_size", Vector2i.ZERO) as Vector2i)
		var material: ShaderMaterial = _ensure_contour_material(
			visual,
			CONTOUR_MOUNTAIN_SHADER,
			WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		)
		_apply_common_contour_shader_params(material, textures)
		material.set_shader_parameter("cover_mask", _ensure_roof_mask_texture(mountain_id))
		material.set_shader_parameter(
			"mask_tile_count",
			Vector2(float(WorldRuntimeConstants.CHUNK_SIZE), float(WorldRuntimeConstants.CHUNK_SIZE))
		)
	var stale_ids: Array = []
	for mountain_id_variant: Variant in _contour_mountain_visuals_by_id.keys():
		var mountain_id: int = int(mountain_id_variant)
		if not active_lookup.has(mountain_id):
			stale_ids.append(mountain_id)
	for mountain_id_variant: Variant in stale_ids:
		var stale_id: int = int(mountain_id_variant)
		var stale_visual: Sprite2D = _contour_mountain_visuals_by_id.get(stale_id, null) as Sprite2D
		if stale_visual != null and is_instance_valid(stale_visual):
			stale_visual.queue_free()
		_contour_mountain_visuals_by_id.erase(stale_id)

func _ensure_ground_contour_visual() -> Sprite2D:
	if _contour_ground_visual != null and is_instance_valid(_contour_ground_visual):
		return _contour_ground_visual
	_contour_ground_visual = Sprite2D.new()
	_contour_ground_visual.name = "GroundContourVisual"
	_contour_ground_visual.centered = false
	_contour_ground_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_contour_ground_visual.z_index = CONTOUR_GROUND_Z_INDEX
	_ensure_contour_root().add_child(_contour_ground_visual)
	return _contour_ground_visual

func _ensure_mountain_contour_visual(mountain_id: int) -> Sprite2D:
	var visual: Sprite2D = _contour_mountain_visuals_by_id.get(mountain_id, null) as Sprite2D
	if visual != null and is_instance_valid(visual):
		return visual
	visual = Sprite2D.new()
	visual.name = "MountainContourVisual_%d" % mountain_id
	visual.centered = false
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visual.z_index = CONTOUR_MOUNTAIN_Z_INDEX
	_ensure_contour_root().add_child(visual)
	_contour_mountain_visuals_by_id[mountain_id] = visual
	return visual

func _apply_contour_visual_size(visual: Sprite2D, pixel_size: Vector2i) -> void:
	visual.position = Vector2.ZERO
	if pixel_size.x <= 0 or pixel_size.y <= 0:
		visual.scale = Vector2.ONE
		return
	var chunk_size_px: float = float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
	visual.scale = Vector2(
		chunk_size_px / float(pixel_size.x),
		chunk_size_px / float(pixel_size.y)
	)

func _ensure_contour_material(visual: Sprite2D, shader: Shader, terrain_id: int) -> ShaderMaterial:
	var material: ShaderMaterial = visual.material as ShaderMaterial
	if material == null or material.shader != shader:
		material = ShaderMaterial.new()
		material.shader = shader
		visual.material = material
		_apply_contour_presentation_params(material, terrain_id)
	return material

func _apply_common_contour_shader_params(material: ShaderMaterial, textures: Dictionary) -> void:
	material.set_shader_parameter("mask_texture", textures.get("mask", null))
	material.set_shader_parameter("height_texture", textures.get("height", null))
	material.set_shader_parameter("normal_texture", textures.get("normal", null))
	material.set_shader_parameter("chunk_origin_px", WorldRuntimeConstants.chunk_origin_px(chunk_coord))
	material.set_shader_parameter("tile_size_px", float(WorldRuntimeConstants.TILE_SIZE_PX))

func _apply_contour_presentation_params(material: ShaderMaterial, terrain_id: int) -> void:
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(terrain_id)
	material.set_shader_parameter("top_albedo_tex", material_set.get_texture_slot(&"top_albedo"))
	material.set_shader_parameter("face_albedo_tex", material_set.get_texture_slot(&"face_albedo"))
	material.set_shader_parameter("base_albedo_tex", material_set.get_texture_slot(&"base_albedo"))
	material.set_shader_parameter("top_modulation", material_set.get_texture_slot(&"top_modulation"))
	material.set_shader_parameter("face_modulation", material_set.get_texture_slot(&"face_modulation"))
	material.set_shader_parameter("top_normal_tex", material_set.get_texture_slot(&"top_normal"))
	material.set_shader_parameter("face_normal_tex", material_set.get_texture_slot(&"face_normal"))
	for parameter_name_variant: Variant in material_set.sampling_params.keys():
		material.set_shader_parameter(
			parameter_name_variant,
			material_set.sampling_params[parameter_name_variant]
		)

func _collect_contour_mountain_ids() -> Array:
	var max_count: int = mini(_pending_terrain_ids.size(), _pending_mountain_flags.size())
	for index: int in range(max_count):
		if not _is_contour_mountain_index(index):
			continue
		return [FALLBACK_MOUNTAIN_CONTOUR_ID]
	return []

func _ensure_contour_membership_texture(mountain_id: int) -> ImageTexture:
	var image: Image = _build_contour_membership_image(mountain_id)
	_contour_membership_images_by_mountain[mountain_id] = image
	var texture: ImageTexture = _contour_membership_textures_by_mountain.get(mountain_id, null) as ImageTexture
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		_contour_membership_textures_by_mountain[mountain_id] = texture
	else:
		texture.update(image)
	return texture

func _build_contour_membership_image(mountain_id: int) -> Image:
	var image: Image = Image.create(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_L8
	)
	image.fill(Color(0.0, 0.0, 0.0, 1.0))
	var max_count: int = mini(_pending_terrain_ids.size(), _pending_mountain_flags.size())
	var member_locals: Dictionary = {}
	for index: int in range(max_count):
		if not _is_contour_mountain_index(index):
			continue
		var resolved_mountain_id: int = FALLBACK_MOUNTAIN_CONTOUR_ID
		if index < _pending_mountain_ids.size():
			resolved_mountain_id = int(_pending_mountain_ids[index])
			if resolved_mountain_id <= 0:
				resolved_mountain_id = FALLBACK_MOUNTAIN_CONTOUR_ID
		if resolved_mountain_id != mountain_id:
			continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		member_locals[local_coord] = true
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var expanded_coord := Vector2i(local_coord.x + offset_x, local_coord.y + offset_y)
				if not WorldRuntimeConstants.is_local_coord_valid(expanded_coord):
					continue
				var expanded_index: int = WorldRuntimeConstants.local_to_index(expanded_coord)
				if expanded_index >= 0 \
						and expanded_index < _pending_mountain_ids.size() \
						and int(_pending_mountain_ids[expanded_index]) > 0 \
						and int(_pending_mountain_ids[expanded_index]) != mountain_id:
					continue
				member_locals[expanded_coord] = true
	for local_variant: Variant in member_locals.keys():
		var local_coord: Vector2i = local_variant as Vector2i
		image.set_pixel(local_coord.x, local_coord.y, Color(1.0, 0.0, 0.0, 1.0))
	return image

func _clear_contour_visuals() -> void:
	if _contour_ground_visual != null and is_instance_valid(_contour_ground_visual):
		_contour_ground_visual.queue_free()
	_contour_ground_visual = null
	for visual_variant: Variant in _contour_mountain_visuals_by_id.values():
		var visual: Sprite2D = visual_variant as Sprite2D
		if visual != null and is_instance_valid(visual):
			visual.queue_free()
	_contour_mountain_visuals_by_id.clear()

func _clear_tilemap_terrain_layers() -> void:
	if _base_layer != null and is_instance_valid(_base_layer):
		_base_layer.clear()
	if _overlay_layer != null and is_instance_valid(_overlay_layer):
		_overlay_layer.clear()

func _clear_roof_tile_layers() -> void:
	for terrain_layers_variant: Variant in roof_layers_by_mountain.values():
		var terrain_layers: Dictionary = terrain_layers_variant as Dictionary
		for layer_variant: Variant in terrain_layers.values():
			var layer: TileMapLayer = layer_variant as TileMapLayer
			if layer != null and is_instance_valid(layer):
				layer.queue_free()
	roof_layers_by_mountain.clear()

func _has_valid_contour_ground_visual() -> bool:
	return _contour_ground_visual != null \
		and is_instance_valid(_contour_ground_visual) \
		and _contour_ground_visual.texture != null

func _count_valid_mountain_contour_visuals() -> int:
	var count: int = 0
	for visual_variant: Variant in _contour_mountain_visuals_by_id.values():
		var visual: Sprite2D = visual_variant as Sprite2D
		if visual != null and is_instance_valid(visual) and visual.texture != null:
			count += 1
	return count

func _build_contour_visual_debug_state(visual: Sprite2D) -> Dictionary:
	return {
		"has_mask_texture": _visual_has_shader_parameter(visual, &"mask_texture"),
		"has_height_texture": _visual_has_shader_parameter(visual, &"height_texture"),
		"has_normal_texture": _visual_has_shader_parameter(visual, &"normal_texture"),
		"has_base_albedo": _visual_has_shader_parameter(visual, &"base_albedo_tex"),
		"has_chunk_origin": _visual_has_shader_parameter(visual, &"chunk_origin_px"),
		"has_tile_size": _visual_has_shader_parameter(visual, &"tile_size_px"),
	}

func _visual_has_shader_parameter(visual: Sprite2D, parameter_name: StringName) -> bool:
	if visual == null or not is_instance_valid(visual):
		return false
	var material: ShaderMaterial = visual.material as ShaderMaterial
	if material == null:
		return false
	return material.get_shader_parameter(parameter_name) != null

func _count_target_tilemap_cells() -> int:
	var count: int = 0
	for index: int in range(_pending_terrain_ids.size()):
		var terrain_id: int = int(_pending_terrain_ids[index])
		if not _is_contour_cutover_terrain(terrain_id):
			continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		if _tilemap_layer_has_cell(_base_layer, local_coord) \
				or _tilemap_layer_has_cell(_overlay_layer, local_coord):
			count += 1
	return count

func _tilemap_layer_has_cell(layer: TileMapLayer, local_coord: Vector2i) -> bool:
	if layer == null or not is_instance_valid(layer):
		return false
	return layer.get_cell_source_id(local_coord) >= 0

func _is_contour_cutover_terrain(terrain_id: int) -> bool:
	return TerrainPresentationRegistry.is_contour_cutover_terrain(terrain_id)

func _is_contour_mountain_index(index: int) -> bool:
	if index < 0 or index >= _pending_terrain_ids.size():
		return false
	var terrain_id: int = int(_pending_terrain_ids[index])
	if not _is_contour_mountain_terrain(terrain_id):
		return false
	if terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
		return true
	if index < _pending_mountain_flags.size():
		var flags: int = int(_pending_mountain_flags[index])
		if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
			return false
	return true

func _is_contour_mountain_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED

func _apply_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if _is_contour_cutover_terrain(terrain_id):
		# Cutover terrain ids are never allowed to fall back to TileMap rendering.
		_clear_cell(_base_layer, local_coord)
		_clear_cell(_overlay_layer, local_coord)
		return
	if WorldTileSetFactory.uses_overlay_layer(terrain_id):
		_clear_cell(_base_layer, local_coord)
		_overlay_layer.set_cell(
			local_coord,
			WorldTileSetFactory.get_source_id(terrain_id),
			WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index)
		)
		return
	_clear_cell(_overlay_layer, local_coord)
	_base_layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_source_id(terrain_id),
		WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index)
	)

func _apply_roof_cell(local_coord: Vector2i, index: int) -> void:
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
		WorldTileSetFactory.get_atlas_coords(roof_terrain_id, terrain_atlas_index)
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
		WorldTileSetFactory.get_water_atlas_coords(_resolve_water_atlas_index(local_coord))
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
	if not _is_contour_mountain_terrain(terrain_id):
		return false
	if index < _pending_walkable_flags.size() and int(_pending_walkable_flags[index]) != 0:
		return false
	if terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
		return true
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
	var material := ShaderMaterial.new()
	material.shader = MOUNTAIN_COVER_SHADER
	material.set_shader_parameter("cover_mask", _ensure_roof_mask_texture(mountain_id))
	material.set_shader_parameter(
		"mask_tile_count",
		Vector2(float(WorldRuntimeConstants.CHUNK_SIZE), float(WorldRuntimeConstants.CHUNK_SIZE))
	)
	material.set_shader_parameter("tile_size_px", float(WorldRuntimeConstants.TILE_SIZE_PX))
	material.set_shader_parameter("chunk_origin_px", WorldRuntimeConstants.chunk_origin_px(chunk_coord))
	_apply_roof_presentation_params(material, terrain_id)
	return material

func _apply_roof_presentation_params(material: ShaderMaterial, terrain_id: int) -> void:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var shape_set: TerrainShapeSet = TerrainPresentationRegistry.get_shape_set_for_terrain(
		roof_terrain_id
	)
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(
		roof_terrain_id
	)
	material.set_shader_parameter("shape_normal_atlas", shape_set.get_texture_slot(&"shape_normal_atlas"))
	material.set_shader_parameter("top_albedo_tex", material_set.get_texture_slot(&"top_albedo"))
	material.set_shader_parameter("face_albedo_tex", material_set.get_texture_slot(&"face_albedo"))
	material.set_shader_parameter("top_modulation", material_set.get_texture_slot(&"top_modulation"))
	material.set_shader_parameter("face_modulation", material_set.get_texture_slot(&"face_modulation"))
	material.set_shader_parameter("top_normal_tex", material_set.get_texture_slot(&"top_normal"))
	material.set_shader_parameter("face_normal_tex", material_set.get_texture_slot(&"face_normal"))
	for parameter_name_variant: Variant in material_set.sampling_params.keys():
		material.set_shader_parameter(
			parameter_name_variant,
			material_set.sampling_params[parameter_name_variant]
		)

func _get_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {}) as Dictionary
	return terrain_layers.get(roof_terrain_id, null) as TileMapLayer

func _clear_other_roof_surface_cell(mountain_id: int, terrain_id: int, local_coord: Vector2i) -> void:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {}) as Dictionary
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
		Image.FORMAT_L8
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
	var result := {
		"ready": false,
		"local_coord": local_coord,
		"expected_open_bit": expected_open_bit,
		"pending_mountain_id": 0,
		"pending_flags": 0,
		"has_roof_layer": false,
		"layer_has_cover_material": false,
		"roof_terrain_id": WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
		"roof_cell_source_id": -1,
		"roof_cell_atlas_coords": Vector2i(-1, -1),
		"roof_tile_material_present": false,
		"mask_value": -1.0,
	}
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return result
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var pending_mountain_id: int = 0
	var pending_flags: int = 0
	if index >= 0 and index < _pending_mountain_ids.size():
		pending_mountain_id = int(_pending_mountain_ids[index])
	if index >= 0 and index < _pending_mountain_flags.size():
		pending_flags = int(_pending_mountain_flags[index])
	result["pending_mountain_id"] = pending_mountain_id
	result["pending_flags"] = pending_flags
	var resolved_mountain_id: int = mountain_id if mountain_id > 0 else pending_mountain_id
	if resolved_mountain_id <= 0:
		result["ready"] = true
		return result
	var roof_terrain_id: int = _resolve_roof_terrain_id_from_flags(pending_flags)
	result["roof_terrain_id"] = roof_terrain_id
	var layer: TileMapLayer = _get_roof_layer(resolved_mountain_id, roof_terrain_id)
	result["has_roof_layer"] = layer != null and is_instance_valid(layer)
	if layer != null and is_instance_valid(layer):
		result["layer_has_cover_material"] = layer.material != null
		var roof_cell_source_id: int = layer.get_cell_source_id(local_coord)
		result["roof_cell_source_id"] = roof_cell_source_id
		var roof_cell_atlas_coords: Vector2i = layer.get_cell_atlas_coords(local_coord)
		result["roof_cell_atlas_coords"] = roof_cell_atlas_coords
		if roof_cell_source_id >= 0 and layer.tile_set != null:
			var source: TileSetAtlasSource = layer.tile_set.get_source(roof_cell_source_id) as TileSetAtlasSource
			if source != null:
				var tile_data: TileData = source.get_tile_data(roof_cell_atlas_coords, 0)
				result["roof_tile_material_present"] = tile_data != null and tile_data.material != null
	var image: Image = _roof_mask_images_by_mountain.get(resolved_mountain_id, null) as Image
	if image != null:
		result["mask_value"] = image.get_pixel(local_coord.x, local_coord.y).r
	result["ready"] = true
	return result

func _is_roof_bearing_mountain_tile(mountain_id: int, mountain_flags: int) -> bool:
	return mountain_id > 0 \
		and (mountain_flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0
