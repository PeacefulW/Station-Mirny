class_name WorldTileSetFactory
extends RefCounted

const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const GroundShader = preload("res://assets/shaders/ground_hybrid_material.gdshader")
const RockShader = preload("res://assets/shaders/rock_shape_material.gdshader")

const PLAINS_ATLAS_TEXTURE: Texture2D = preload("res://assets/sprites/terrain/plain_terrain_atlas.png")
const ROCK_MASK_ATLAS_TEXTURE: Texture2D = preload("res://assets/sprites/terrain/plain_rock_mask_atlas.png")
const ROCK_SHAPE_NORMAL_ATLAS_TEXTURE: Texture2D = preload("res://assets/sprites/terrain/plain_rock_shape_normal_atlas.png")
const DUG_TEXTURE: Texture2D = preload("res://assets/textures/terrain/terrain_shore.png")
const PLAINS_GROUND_ALBEDO_TEXTURE: Texture2D = preload("res://assets/textures/terrain/terrain_plains_albedo.png")
const PLAINS_GROUND_MODULATION_TEXTURE: Texture2D = preload("res://assets/textures/terrain/terrain_plains_modulation.png")
const ROCK_TOP_ALBEDO_TEXTURE: Texture2D = preload("res://assets/textures/terrain/rock_top_albedo.png")
const ROCK_FACE_ALBEDO_TEXTURE: Texture2D = preload("res://assets/textures/terrain/rock_face_albedo.png")
const ROCK_TOP_MODULATION_TEXTURE: Texture2D = preload("res://assets/textures/terrain/rock_top_modulation.png")
const ROCK_FACE_MODULATION_TEXTURE: Texture2D = preload("res://assets/textures/terrain/rock_face_modulation.png")
const ROCK_TOP_NORMAL_TEXTURE: Texture2D = preload("res://assets/textures/terrain/rock_top_normal.png")
const ROCK_FACE_NORMAL_TEXTURE: Texture2D = preload("res://assets/textures/terrain/rock_face_normal.png")

static var _base_tile_set: TileSet = null
static var _rock_tile_set: TileSet = null
static var _base_source_ids: Dictionary = {}
static var _rock_source_id: int = -1
static var _ground_material: ShaderMaterial = null
static var _rock_material: ShaderMaterial = null

static func get_tile_set() -> TileSet:
	return get_base_tile_set()

static func get_source_id(terrain_id: int) -> int:
	return get_base_source_id(terrain_id)

static func get_atlas_coords(terrain_id: int, atlas_index: int = 0) -> Vector2i:
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_ROCK:
		return get_rock_atlas_coords(atlas_index)
	if _uses_base_autotile_47(terrain_id):
		return Autotile47.atlas_index_to_coords(atlas_index)
	return Vector2i.ZERO

static func get_base_tile_set() -> TileSet:
	_ensure_base_tileset()
	return _base_tile_set

static func get_rock_tile_set() -> TileSet:
	_ensure_rock_tileset()
	return _rock_tile_set

static func get_base_source_id(terrain_id: int) -> int:
	_ensure_base_tileset()
	return int(_base_source_ids.get(terrain_id, _base_source_ids[WorldRuntimeConstants.TERRAIN_PLAINS_GROUND]))

static func get_rock_source_id() -> int:
	_ensure_rock_tileset()
	return _rock_source_id

static func get_rock_atlas_coords(atlas_index: int = 0) -> Vector2i:
	return Autotile47.atlas_index_to_coords(atlas_index)

static func get_rock_material() -> ShaderMaterial:
	_ensure_rock_material()
	return _rock_material

static func is_rock_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_ROCK

static func _ensure_base_tileset() -> void:
	if _base_tile_set != null:
		return
	_ensure_ground_material()
	_base_tile_set = TileSet.new()
	_base_tile_set.tile_size = Vector2i(
		WorldRuntimeConstants.TILE_SIZE_PX,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	var plains_source := Autotile47.build_full_atlas_source(
		PLAINS_ATLAS_TEXTURE,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	var plains_columns: int = maxi(1, PLAINS_ATLAS_TEXTURE.get_width() / WorldRuntimeConstants.TILE_SIZE_PX)
	var plains_rows: int = maxi(1, PLAINS_ATLAS_TEXTURE.get_height() / WorldRuntimeConstants.TILE_SIZE_PX)
	for row: int in range(plains_rows):
		for column: int in range(plains_columns):
			var coords := Vector2i(column, row)
			var tile_data: TileData = plains_source.get_tile_data(coords, 0)
			if tile_data != null:
				tile_data.material = _ground_material
	_base_source_ids = {
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND: _base_tile_set.add_source(plains_source),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG: _base_tile_set.add_source(_build_single_tile_source(DUG_TEXTURE)),
	}

static func _ensure_rock_tileset() -> void:
	if _rock_tile_set != null:
		return
	_ensure_rock_material()
	_rock_tile_set = TileSet.new()
	_rock_tile_set.tile_size = Vector2i(
		WorldRuntimeConstants.TILE_SIZE_PX,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	var source := Autotile47.build_full_atlas_source(
		ROCK_MASK_ATLAS_TEXTURE,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	var columns: int = maxi(1, ROCK_MASK_ATLAS_TEXTURE.get_width() / WorldRuntimeConstants.TILE_SIZE_PX)
	var rows: int = maxi(1, ROCK_MASK_ATLAS_TEXTURE.get_height() / WorldRuntimeConstants.TILE_SIZE_PX)
	for row: int in range(rows):
		for column: int in range(columns):
			var coords := Vector2i(column, row)
			var tile_data: TileData = source.get_tile_data(coords, 0)
			if tile_data != null:
				tile_data.material = _rock_material
	_rock_source_id = _rock_tile_set.add_source(source)

static func _ensure_rock_material() -> void:
	if _rock_material != null:
		return
	_rock_material = ShaderMaterial.new()
	_rock_material.shader = RockShader
	_rock_material.set_shader_parameter("shape_normal_atlas", ROCK_SHAPE_NORMAL_ATLAS_TEXTURE)
	_rock_material.set_shader_parameter("top_albedo_tex", ROCK_TOP_ALBEDO_TEXTURE)
	_rock_material.set_shader_parameter("face_albedo_tex", ROCK_FACE_ALBEDO_TEXTURE)
	_rock_material.set_shader_parameter("top_modulation", ROCK_TOP_MODULATION_TEXTURE)
	_rock_material.set_shader_parameter("face_modulation", ROCK_FACE_MODULATION_TEXTURE)
	_rock_material.set_shader_parameter("top_normal_tex", ROCK_TOP_NORMAL_TEXTURE)
	_rock_material.set_shader_parameter("face_normal_tex", ROCK_FACE_NORMAL_TEXTURE)
	_rock_material.set_shader_parameter("top_albedo_blend", 1.0)
	_rock_material.set_shader_parameter("face_albedo_blend", 1.0)
	_rock_material.set_shader_parameter("top_albedo_chroma_strength", 0.78)
	_rock_material.set_shader_parameter("face_albedo_chroma_strength", 0.92)
	_rock_material.set_shader_parameter("top_albedo_luma_strength", 1.0)
	_rock_material.set_shader_parameter("face_albedo_luma_strength", 1.0)
	_rock_material.set_shader_parameter("dust_strength", 0.0)
	_rock_material.set_shader_parameter("back_rim_darkening", 1.0)

static func _ensure_ground_material() -> void:
	if _ground_material != null:
		return
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = GroundShader
	_ground_material.set_shader_parameter("ground_albedo_tex", PLAINS_GROUND_ALBEDO_TEXTURE)
	_ground_material.set_shader_parameter("ground_modulation_tex", PLAINS_GROUND_MODULATION_TEXTURE)

static func _build_single_tile_source(texture: Texture2D) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(
		WorldRuntimeConstants.TILE_SIZE_PX,
		WorldRuntimeConstants.TILE_SIZE_PX
	)
	source.create_tile(Vector2i.ZERO)
	return source

static func _uses_base_autotile_47(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
