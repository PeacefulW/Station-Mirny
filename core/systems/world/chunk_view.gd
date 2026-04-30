class_name ChunkView
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const MOUNTAIN_COVER_SHADER = preload("res://assets/shaders/mountain_cover_overlay.gdshader")

var chunk_coord: Vector2i = Vector2i.ZERO

var _base_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var roof_layers_by_mountain: Dictionary = {}
var _roof_mask_images_by_mountain: Dictionary = {}
var _roof_mask_textures_by_mountain: Dictionary = {}
var _pending_terrain_ids: PackedInt32Array = PackedInt32Array()
var _pending_terrain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _pending_hydrology_flags: PackedInt32Array = PackedInt32Array()
var _pending_floodplain_strength: PackedByteArray = PackedByteArray()
var _pending_mountain_ids: PackedInt32Array = PackedInt32Array()
var _pending_mountain_flags: PackedByteArray = PackedByteArray()
var _pending_mountain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _floodplain_overlay_sprite: Sprite2D = null
var _floodplain_overlay_image: Image = null
var _floodplain_overlay_texture: ImageTexture = null
var _floodplain_overlay_dirty: bool = false
var _apply_index: int = 0

func _ready() -> void:
	pass

func _exit_tree() -> void:
	_roof_mask_images_by_mountain.clear()
	_roof_mask_textures_by_mountain.clear()
	_floodplain_overlay_image = null
	_floodplain_overlay_texture = null

func configure(new_chunk_coord: Vector2i) -> void:
	chunk_coord = new_chunk_coord
	position = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_ensure_layers()

func begin_apply(packet: Dictionary) -> void:
	_pending_terrain_ids = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_terrain_atlas_indices = (packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_hydrology_flags = (packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_floodplain_strength = (packet.get("floodplain_strength", PackedByteArray()) as PackedByteArray).duplicate()
	_pending_mountain_ids = (packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_mountain_flags = (packet.get("mountain_flags", PackedByteArray()) as PackedByteArray).duplicate()
	_pending_mountain_atlas_indices = (packet.get("mountain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	_apply_index = 0
	visible = false
	_ensure_layers()
	_reset_floodplain_overlay_image()

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
		_apply_floodplain_overlay_cell(local_coord, index)
		_apply_roof_cell(local_coord, index)
	_apply_index = end_index
	_update_floodplain_overlay_texture()
	if _apply_index >= _pending_terrain_ids.size():
		return false
	return true

func apply_runtime_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	_ensure_layers()
	_apply_cell(local_coord, terrain_id, terrain_atlas_index)
	_clear_floodplain_overlay_cell(local_coord)
	_update_floodplain_overlay_texture()

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
		add_child(_base_layer)
	if _overlay_layer == null or not is_instance_valid(_overlay_layer):
		_overlay_layer = TileMapLayer.new()
		_overlay_layer.name = "TerrainOverlayLayer"
		_overlay_layer.tile_set = WorldTileSetFactory.get_overlay_tile_set()
		_overlay_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_overlay_layer.z_index = 1
		add_child(_overlay_layer)
	if _floodplain_overlay_sprite == null or not is_instance_valid(_floodplain_overlay_sprite):
		_floodplain_overlay_sprite = Sprite2D.new()
		_floodplain_overlay_sprite.name = "FloodplainStrengthOverlay"
		_floodplain_overlay_sprite.centered = false
		_floodplain_overlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_floodplain_overlay_sprite.z_index = 2
		_floodplain_overlay_sprite.scale = Vector2(
			float(WorldRuntimeConstants.TILE_SIZE_PX),
			float(WorldRuntimeConstants.TILE_SIZE_PX)
		)
		_floodplain_overlay_sprite.texture = _ensure_floodplain_overlay_texture()
		add_child(_floodplain_overlay_sprite)

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

func _apply_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if WorldTileSetFactory.uses_overlay_layer(terrain_id):
		if _uses_plains_ground_underlay(terrain_id):
			_base_layer.set_cell(
				local_coord,
				WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
				WorldTileSetFactory.get_atlas_coords(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, 0)
			)
		else:
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

func _uses_plains_ground_underlay(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_FLOODPLAIN

func _apply_floodplain_overlay_cell(local_coord: Vector2i, index: int) -> void:
	if index < 0 \
			or index >= _pending_hydrology_flags.size() \
			or index >= _pending_floodplain_strength.size():
		_clear_floodplain_overlay_cell(local_coord)
		return
	var color: Color = TerrainPresentationRegistry.get_floodplain_overlay_color(
		int(_pending_floodplain_strength[index]),
		int(_pending_hydrology_flags[index])
	)
	_set_floodplain_overlay_cell(local_coord, color)

func _set_floodplain_overlay_cell(local_coord: Vector2i, color: Color) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	var image: Image = _ensure_floodplain_overlay_image()
	image.set_pixel(local_coord.x, local_coord.y, color)
	_floodplain_overlay_dirty = true

func _clear_floodplain_overlay_cell(local_coord: Vector2i) -> void:
	_set_floodplain_overlay_cell(local_coord, Color.TRANSPARENT)

func _reset_floodplain_overlay_image() -> void:
	var image: Image = _ensure_floodplain_overlay_image()
	image.fill(Color.TRANSPARENT)
	_floodplain_overlay_dirty = true
	_update_floodplain_overlay_texture()

func _ensure_floodplain_overlay_image() -> Image:
	if _floodplain_overlay_image != null:
		return _floodplain_overlay_image
	_floodplain_overlay_image = Image.create(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	_floodplain_overlay_image.fill(Color.TRANSPARENT)
	return _floodplain_overlay_image

func _ensure_floodplain_overlay_texture() -> ImageTexture:
	if _floodplain_overlay_texture != null:
		return _floodplain_overlay_texture
	_floodplain_overlay_texture = ImageTexture.create_from_image(_ensure_floodplain_overlay_image())
	return _floodplain_overlay_texture

func _update_floodplain_overlay_texture() -> void:
	if not _floodplain_overlay_dirty:
		return
	_ensure_floodplain_overlay_texture().update(_ensure_floodplain_overlay_image())
	if _floodplain_overlay_sprite != null and is_instance_valid(_floodplain_overlay_sprite):
		_floodplain_overlay_sprite.texture = _floodplain_overlay_texture
	_floodplain_overlay_dirty = false

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

func _clear_cell(layer: TileMapLayer, local_coord: Vector2i) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.set_cell(local_coord, -1, Vector2i(-1, -1))

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

func get_floodplain_overlay_debug(local_coord: Vector2i) -> Dictionary:
	var image: Image = _ensure_floodplain_overlay_image()
	var texture: ImageTexture = _ensure_floodplain_overlay_texture()
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return {
			"ready": false,
			"local_coord": local_coord,
			"color": Color.TRANSPARENT,
			"texture_width": 0,
			"texture_height": 0,
			"has_sprite": _floodplain_overlay_sprite != null and is_instance_valid(_floodplain_overlay_sprite),
		}
	return {
		"ready": image != null and texture != null,
		"local_coord": local_coord,
		"color": image.get_pixel(local_coord.x, local_coord.y),
		"texture_width": image.get_width(),
		"texture_height": image.get_height(),
		"has_sprite": _floodplain_overlay_sprite != null and is_instance_valid(_floodplain_overlay_sprite),
	}

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
