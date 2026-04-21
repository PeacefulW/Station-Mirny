class_name WorldTileSetFactory
extends RefCounted

const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

static var _tile_sets_by_layer: Dictionary = {}
static var _source_ids_by_terrain_id: Dictionary = {}
static var _materials_by_profile_id: Dictionary = {}

static func bootstrap() -> void:
	TerrainPresentationRegistry.bootstrap()

static func get_tile_set() -> TileSet:
	return get_base_tile_set()

static func get_source_id(terrain_id: int) -> int:
	var layer_id: StringName = get_render_layer_id(terrain_id)
	_ensure_layer_tileset(layer_id)
	assert(_source_ids_by_terrain_id.has(terrain_id), "Missing TileSet source id for terrain_id=%d layer=%s" % [terrain_id, layer_id])
	return int(_source_ids_by_terrain_id[terrain_id])

static func get_atlas_coords(terrain_id: int, atlas_index: int = 0) -> Vector2i:
	var shape_set: TerrainShapeSet = TerrainPresentationRegistry.get_shape_set_for_terrain(terrain_id)
	assert(shape_set != null, "Missing TerrainShapeSet for terrain_id=%d" % terrain_id)
	if shape_set.topology_family_id == TerrainPresentationRegistry.TOPOLOGY_AUTOTILE_47:
		return Autotile47.atlas_index_to_coords(atlas_index)
	return Vector2i.ZERO

static func get_base_tile_set() -> TileSet:
	_ensure_layer_tileset(TerrainPresentationRegistry.RENDER_LAYER_BASE)
	return _tile_sets_by_layer.get(TerrainPresentationRegistry.RENDER_LAYER_BASE, null) as TileSet

static func get_overlay_tile_set() -> TileSet:
	_ensure_layer_tileset(TerrainPresentationRegistry.RENDER_LAYER_OVERLAY)
	return _tile_sets_by_layer.get(TerrainPresentationRegistry.RENDER_LAYER_OVERLAY, null) as TileSet

static func get_roof_tile_set() -> TileSet:
	# Roof cells reuse the mountain-wall atlas so the outside silhouette stays seamless.
	return get_base_tile_set()

static func get_base_source_id(terrain_id: int) -> int:
	return get_source_id(terrain_id)

static func uses_overlay_layer(terrain_id: int) -> bool:
	return get_render_layer_id(terrain_id) == TerrainPresentationRegistry.RENDER_LAYER_OVERLAY

static func get_render_layer_id(terrain_id: int) -> StringName:
	return TerrainPresentationRegistry.get_render_layer_for_terrain(terrain_id)

static func _ensure_layer_tileset(layer_id: StringName) -> void:
	bootstrap()
	if _tile_sets_by_layer.has(layer_id):
		return
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(
		WorldRuntimeConstants.TILE_SIZE_PX,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	for terrain_id: int in TerrainPresentationRegistry.get_terrain_ids_for_layer(layer_id):
		var source: TileSetAtlasSource = _build_source_for_terrain(terrain_id)
		var source_id: int = tile_set.add_source(source)
		_source_ids_by_terrain_id[terrain_id] = source_id
	_tile_sets_by_layer[layer_id] = tile_set

static func _build_source_for_terrain(terrain_id: int) -> TileSetAtlasSource:
	var shape_set: TerrainShapeSet = TerrainPresentationRegistry.get_shape_set_for_terrain(terrain_id)
	assert(shape_set != null, "Missing TerrainShapeSet for terrain_id=%d" % terrain_id)
	var source: TileSetAtlasSource = _build_source_for_shape_set(shape_set)
	var material: ShaderMaterial = _get_or_create_material_for_terrain(terrain_id)
	if material != null:
		_apply_material_to_source(source, material)
	return source

static func _build_source_for_shape_set(shape_set: TerrainShapeSet) -> TileSetAtlasSource:
	if shape_set.topology_family_id == TerrainPresentationRegistry.TOPOLOGY_AUTOTILE_47:
		return Autotile47.build_full_atlas_source(shape_set.mask_atlas, shape_set.tile_size_px)
	if shape_set.topology_family_id == TerrainPresentationRegistry.TOPOLOGY_SINGLE_TILE:
		return _build_single_tile_source(shape_set.mask_atlas, shape_set.tile_size_px)
	assert(false, "Unsupported topology family in TerrainShapeSet %s" % [shape_set.id])
	return TileSetAtlasSource.new()

static func _get_or_create_material_for_terrain(terrain_id: int) -> ShaderMaterial:
	var profile: TerrainPresentationProfile = TerrainPresentationRegistry.get_profile_for_terrain(terrain_id)
	if _materials_by_profile_id.has(profile.id):
		return _materials_by_profile_id[profile.id] as ShaderMaterial
	var shape_set: TerrainShapeSet = TerrainPresentationRegistry.get_shape_set(profile.shape_set_id)
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(profile.material_set_id)
	var material: ShaderMaterial = _build_material(profile, shape_set, material_set)
	_materials_by_profile_id[profile.id] = material
	return material

static func _build_material(
	profile: TerrainPresentationProfile,
	shape_set: TerrainShapeSet,
	material_set: TerrainMaterialSet
) -> ShaderMaterial:
	var shader_family: TerrainShaderFamily = TerrainPresentationRegistry.get_shader_family(profile.shader_family_id)
	assert(shader_family != null, "Missing TerrainShaderFamily for profile %s" % [profile.id])
	if shader_family.shader == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader_family.shader
	_apply_shape_texture_params(material, shader_family, shape_set)
	_apply_material_texture_params(material, shader_family, material_set)
	for parameter_name_variant: Variant in material_set.sampling_params.keys():
		var parameter_name: Variant = parameter_name_variant
		material.set_shader_parameter(parameter_name, material_set.sampling_params[parameter_name_variant])
	return material

static func _apply_shape_texture_params(
	material: ShaderMaterial,
	shader_family: TerrainShaderFamily,
	shape_set: TerrainShapeSet
) -> void:
	for parameter_name_variant: Variant in shader_family.shape_texture_params.keys():
		var parameter_name: StringName = StringName(str(parameter_name_variant))
		var slot_id: StringName = StringName(str(shader_family.shape_texture_params[parameter_name_variant]))
		var texture: Texture2D = shape_set.get_texture_slot(slot_id)
		assert(texture != null, "Missing shape texture slot %s for shader family %s" % [slot_id, shader_family.id])
		material.set_shader_parameter(parameter_name, texture)

static func _apply_material_texture_params(
	material: ShaderMaterial,
	shader_family: TerrainShaderFamily,
	material_set: TerrainMaterialSet
) -> void:
	for parameter_name_variant: Variant in shader_family.material_texture_params.keys():
		var parameter_name: StringName = StringName(str(parameter_name_variant))
		var slot_id: StringName = StringName(str(shader_family.material_texture_params[parameter_name_variant]))
		var texture: Texture2D = material_set.get_texture_slot(slot_id)
		assert(texture != null, "Missing material texture slot %s for shader family %s" % [slot_id, shader_family.id])
		material.set_shader_parameter(parameter_name, texture)

static func _apply_material_to_source(source: TileSetAtlasSource, material: ShaderMaterial) -> void:
	var texture: Texture2D = source.texture
	var tile_size: Vector2i = source.texture_region_size
	var columns: int = maxi(1, texture.get_width() / tile_size.x)
	var rows: int = maxi(1, texture.get_height() / tile_size.y)
	for row: int in range(rows):
		for column: int in range(columns):
			var coords := Vector2i(column, row)
			var tile_data: TileData = source.get_tile_data(coords, 0)
			if tile_data != null:
				tile_data.material = material

static func _build_single_tile_source(texture: Texture2D, tile_size_px: int) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_size_px, tile_size_px)
	source.create_tile(Vector2i.ZERO)
	return source
