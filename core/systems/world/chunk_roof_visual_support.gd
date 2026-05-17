class_name ChunkRoofVisualSupport
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const TerrainPresentationRegistry = preload(
	"res://core/systems/world/terrain_presentation_registry.gd"
)
const MOUNTAIN_COVER_SHADER = preload("res://assets/shaders/mountain_cover_overlay.gdshader")


static func build_roof_material(
		chunk_coord: Vector2i,
		_mountain_id: int,
		terrain_id: int,
		cover_mask: ImageTexture,
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = MOUNTAIN_COVER_SHADER
	material.set_shader_parameter("cover_mask", cover_mask)
	material.set_shader_parameter(
		"mask_tile_count",
		Vector2(float(WorldRuntimeConstants.CHUNK_SIZE), float(WorldRuntimeConstants.CHUNK_SIZE)),
	)
	material.set_shader_parameter("tile_size_px", float(WorldRuntimeConstants.TILE_SIZE_PX))
	material.set_shader_parameter(
		"chunk_origin_px",
		WorldRuntimeConstants.chunk_origin_px(chunk_coord),
	)
	_apply_roof_presentation_params(material, terrain_id)
	return material


static func get_cover_render_debug(
		local_coord: Vector2i,
		mountain_id: int,
		expected_open_bit: int,
		pending_mountain_ids: PackedInt32Array,
		pending_mountain_flags: PackedByteArray,
		roof_layers_by_mountain: Dictionary,
		roof_mask_images_by_mountain: Dictionary,
) -> Dictionary:
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
	var pending_mountain_id := _read_int(pending_mountain_ids, index)
	var pending_flags := _read_byte(pending_mountain_flags, index)
	result["pending_mountain_id"] = pending_mountain_id
	result["pending_flags"] = pending_flags
	var resolved_mountain_id: int = mountain_id if mountain_id > 0 else pending_mountain_id
	if resolved_mountain_id <= 0:
		result["ready"] = true
		return result
	var roof_terrain_id: int = _resolve_roof_terrain_id_from_flags(pending_flags)
	result["roof_terrain_id"] = roof_terrain_id
	var layer: TileMapLayer = _get_roof_layer(
		roof_layers_by_mountain,
		resolved_mountain_id,
		roof_terrain_id,
	)
	_apply_roof_layer_debug(result, layer, local_coord)
	var image: Image = roof_mask_images_by_mountain.get(resolved_mountain_id, null) as Image
	if image != null:
		result["mask_value"] = image.get_pixel(local_coord.x, local_coord.y).r
	result["ready"] = true
	return result


static func _apply_roof_presentation_params(material: ShaderMaterial, terrain_id: int) -> void:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var shape_set: TerrainShapeSet = TerrainPresentationRegistry.get_shape_set_for_terrain(
		roof_terrain_id,
	)
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(
		roof_terrain_id,
	)
	material.set_shader_parameter(
		"shape_normal_atlas",
		shape_set.get_texture_slot(&"shape_normal_atlas"),
	)
	material.set_shader_parameter("top_albedo_tex", material_set.get_texture_slot(&"top_albedo"))
	material.set_shader_parameter(
		"face_albedo_tex",
		material_set.get_texture_slot(&"face_albedo"),
	)
	material.set_shader_parameter(
		"top_modulation",
		material_set.get_texture_slot(&"top_modulation"),
	)
	material.set_shader_parameter(
		"face_modulation",
		material_set.get_texture_slot(&"face_modulation"),
	)
	material.set_shader_parameter("top_normal_tex", material_set.get_texture_slot(&"top_normal"))
	material.set_shader_parameter(
		"face_normal_tex",
		material_set.get_texture_slot(&"face_normal"),
	)
	for parameter_name_variant: Variant in material_set.sampling_params.keys():
		material.set_shader_parameter(
			parameter_name_variant,
			material_set.sampling_params[parameter_name_variant],
		)


static func _apply_roof_layer_debug(
		result: Dictionary,
		layer: TileMapLayer,
		local_coord: Vector2i,
) -> void:
	result["has_roof_layer"] = layer != null and is_instance_valid(layer)
	if layer == null or not is_instance_valid(layer):
		return
	result["layer_has_cover_material"] = layer.material != null
	var roof_cell_source_id: int = layer.get_cell_source_id(local_coord)
	result["roof_cell_source_id"] = roof_cell_source_id
	var roof_cell_atlas_coords: Vector2i = layer.get_cell_atlas_coords(local_coord)
	result["roof_cell_atlas_coords"] = roof_cell_atlas_coords
	if roof_cell_source_id < 0 or layer.tile_set == null:
		return
	var source: TileSetAtlasSource = (
		layer.tile_set.get_source(roof_cell_source_id) as TileSetAtlasSource
	)
	if source == null:
		return
	var tile_data: TileData = source.get_tile_data(roof_cell_atlas_coords, 0)
	result["roof_tile_material_present"] = tile_data != null and tile_data.material != null


static func _get_roof_layer(
		roof_layers_by_mountain: Dictionary,
		mountain_id: int,
		terrain_id: int,
) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, { }) as Dictionary
	return terrain_layers.get(roof_terrain_id, null) as TileMapLayer


static func _resolve_roof_terrain_id_from_flags(mountain_flags: int) -> int:
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_WALL) != 0:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT) != 0:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL


static func _resolve_roof_terrain_id(terrain_id: int) -> int:
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL


static func _read_int(values: PackedInt32Array, index: int) -> int:
	if index < 0 or index >= values.size():
		return 0
	return int(values[index])


static func _read_byte(values: PackedByteArray, index: int) -> int:
	if index < 0 or index >= values.size():
		return 0
	return int(values[index])
