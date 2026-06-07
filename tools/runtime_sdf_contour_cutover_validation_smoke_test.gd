extends SceneTree

const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

const GROUND_TEXTURE_PREFIX: String = "res://assets/textures/world/biomes/plains/ground/"
const MOUNTAIN_TEXTURE_PREFIX: String = "res://assets/textures/world/biomes/plains/mountain/"
const WATER_TEXTURE_PREFIX: String = "res://assets/textures/world/biomes/plains/water/"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_registry_bootstraps()
	_assert_presentation_textures_use_biome_assets()
	_assert_runtime_tilesets_bootstrap()

	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_cutover_validation_smoke_test: OK")
	quit(0)

func _assert_registry_bootstraps() -> void:
	TerrainPresentationRegistry.bootstrap()
	for terrain_id: int in [
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
		WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW,
		WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP,
	]:
		_assert(
			TerrainPresentationRegistry.get_shape_set_for_terrain(terrain_id) != null,
			"Terrain id %d must have a registered shape set." % terrain_id
		)
		_assert(
			TerrainPresentationRegistry.get_material_set_for_terrain(terrain_id) != null,
			"Terrain id %d must have a registered material set." % terrain_id
		)

func _assert_presentation_textures_use_biome_assets() -> void:
	var ground_material: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
	)
	var dug_material: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG
	)
	var mountain_wall_material: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	)
	var mountain_foot_material: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	)
	var water_light_material: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		&"lake:water_surface_light_material"
	)
	var water_dark_material: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		&"lake:water_surface_dark_material"
	)

	_assert_material_texture_path_starts_with(ground_material.top_albedo, GROUND_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(ground_material.face_albedo, GROUND_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(ground_material.top_modulation, GROUND_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(ground_material.face_modulation, GROUND_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(ground_material.top_normal, GROUND_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(ground_material.face_normal, GROUND_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(dug_material.top_albedo, GROUND_TEXTURE_PREFIX)

	_assert_material_texture_path_starts_with(mountain_wall_material.top_albedo, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_wall_material.face_albedo, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_wall_material.top_modulation, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_wall_material.face_modulation, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_wall_material.top_normal, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_wall_material.face_normal, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_foot_material.top_albedo, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_foot_material.face_albedo, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_foot_material.top_modulation, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_foot_material.face_modulation, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_foot_material.top_normal, MOUNTAIN_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(mountain_foot_material.face_normal, MOUNTAIN_TEXTURE_PREFIX)

	_assert_material_texture_path_starts_with(water_light_material.top_albedo, WATER_TEXTURE_PREFIX)
	_assert_material_texture_path_starts_with(water_dark_material.top_albedo, WATER_TEXTURE_PREFIX)

func _assert_runtime_tilesets_bootstrap() -> void:
	_assert(WorldTileSetFactory.get_base_tile_set() != null, "Base terrain TileSet must bootstrap.")
	_assert(WorldTileSetFactory.get_overlay_tile_set() != null, "Overlay terrain TileSet must bootstrap.")
	_assert(WorldTileSetFactory.get_water_tile_set() != null, "Water TileSet must bootstrap.")

func _assert_material_texture_path_starts_with(texture: Texture2D, expected_prefix: String) -> void:
	_assert(texture != null, "Terrain material texture slot must be populated.")
	if texture == null:
		return
	_assert(
		texture.resource_path.begins_with(expected_prefix),
		"Terrain material texture must live under %s, got %s." % [expected_prefix, texture.resource_path]
	)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
