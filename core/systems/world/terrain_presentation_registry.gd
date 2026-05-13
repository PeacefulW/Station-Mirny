class_name TerrainPresentationRegistry
extends RefCounted

const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const TOPOLOGY_AUTOTILE_47: StringName = &"autotile_47"
const TOPOLOGY_SINGLE_TILE: StringName = &"single_tile"

const RENDER_LAYER_BASE: StringName = &"base"
const RENDER_LAYER_OVERLAY: StringName = &"overlay"
const CONTOUR_CUTOVER_TERRAIN_IDS: Array[int] = [
	WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
	WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED,
	WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
	WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
	WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
]

const SHAPE_SET_DIRECTORY: String = "res://data/terrain/shape_sets"
const MATERIAL_SET_DIRECTORY: String = "res://data/terrain/material_sets"
const PROFILE_DIRECTORY: String = "res://data/terrain/presentation_profiles"
const SHADER_FAMILY_DIRECTORY: String = "res://data/terrain/shader_families"
const CONTOUR_RECIPE_PATHS_BY_CLASS: Dictionary = {
	WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE: [
		"res://assets/textures/terrain/ground/unnamed_runtime_sdf_recipe.json",
	],
	WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: [
		"res://assets/textures/terrain/mountains/unnamed_runtime_sdf_recipe.json",
	],
	WorldRuntimeConstants.CONTOUR_CLASS_WATER_SURFACE: [
		"res://tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/earth_runtime_sdf_recipe.json",
	],
}

static var _bootstrapped: bool = false
static var _shader_families_by_id: Dictionary = {}
static var _shape_sets_by_id: Dictionary = {}
static var _material_sets_by_id: Dictionary = {}
static var _profiles_by_id: Dictionary = {}
static var _profile_id_by_terrain_id: Dictionary = {}
static var _contour_recipes_by_class: Dictionary = {}
static var _contour_recipe_source_by_class: Dictionary = {}

static func bootstrap() -> void:
	if _bootstrapped:
		return
	_shader_families_by_id.clear()
	_shape_sets_by_id.clear()
	_material_sets_by_id.clear()
	_profiles_by_id.clear()
	_profile_id_by_terrain_id.clear()

	for shader_family_resource: Resource in _load_resources_from_directory(SHADER_FAMILY_DIRECTORY):
		_register_shader_family(shader_family_resource)

	# Resource discovery is bootstrap-only; hot paths consume the validated registry cache.
	for shape_set_resource: Resource in _load_resources_from_directory(SHAPE_SET_DIRECTORY):
		_register_shape_set(shape_set_resource)

	for material_set_resource: Resource in _load_resources_from_directory(MATERIAL_SET_DIRECTORY):
		_register_material_set(material_set_resource)

	for profile_resource: Resource in _load_resources_from_directory(PROFILE_DIRECTORY):
		_register_profile(profile_resource)

	_validate_registered_resources()
	_bootstrapped = true

static func get_profile_for_terrain(terrain_id: int) -> TerrainPresentationProfile:
	bootstrap()
	return _resolve_profile_for_terrain(terrain_id)

static func get_profile_by_id(id: StringName) -> TerrainPresentationProfile:
	bootstrap()
	var profile: TerrainPresentationProfile = _profiles_by_id.get(id, null) as TerrainPresentationProfile
	assert(profile != null, "Missing TerrainPresentationProfile resource for profile_id=%s" % [id])
	return profile

static func get_shader_family(id: StringName) -> TerrainShaderFamily:
	bootstrap()
	return _shader_families_by_id.get(id, null) as TerrainShaderFamily

static func get_shape_set(id: StringName) -> TerrainShapeSet:
	bootstrap()
	return _shape_sets_by_id.get(id, null) as TerrainShapeSet

static func get_material_set(id: StringName) -> TerrainMaterialSet:
	bootstrap()
	return _material_sets_by_id.get(id, null) as TerrainMaterialSet

static func get_shape_set_for_terrain(terrain_id: int) -> TerrainShapeSet:
	var profile: TerrainPresentationProfile = get_profile_for_terrain(terrain_id)
	return get_shape_set(profile.shape_set_id)

static func get_material_set_for_terrain(terrain_id: int) -> TerrainMaterialSet:
	var profile: TerrainPresentationProfile = get_profile_for_terrain(terrain_id)
	return get_material_set(profile.material_set_id)

static func get_render_layer_for_terrain(terrain_id: int) -> StringName:
	var profile: TerrainPresentationProfile = get_profile_for_terrain(terrain_id)
	var shader_family: TerrainShaderFamily = get_shader_family(profile.shader_family_id)
	assert(shader_family != null, "Missing TerrainShaderFamily for terrain_id=%d" % terrain_id)
	return shader_family.render_layer_id

static func get_terrain_ids_for_layer(layer_id: StringName) -> Array[int]:
	bootstrap()
	var terrain_ids: Array[int] = []
	for terrain_id_variant: Variant in _profile_id_by_terrain_id.keys():
		var terrain_id: int = int(terrain_id_variant)
		if get_render_layer_for_terrain(terrain_id) == layer_id:
			terrain_ids.append(terrain_id)
	terrain_ids.sort()
	return terrain_ids

static func get_tilemap_terrain_ids_for_layer(layer_id: StringName) -> Array[int]:
	var terrain_ids: Array[int] = []
	for terrain_id: int in get_terrain_ids_for_layer(layer_id):
		if is_contour_cutover_terrain(terrain_id):
			continue
		terrain_ids.append(terrain_id)
	return terrain_ids

static func is_contour_cutover_terrain(terrain_id: int) -> bool:
	return CONTOUR_CUTOVER_TERRAIN_IDS.has(terrain_id)

static func get_contour_recipe_for_class(contour_class: StringName) -> Dictionary:
	_ensure_contour_recipes_loaded()
	var recipe: Dictionary = _contour_recipes_by_class.get(contour_class, {}) as Dictionary
	assert(not recipe.is_empty(), "Missing runtime SDF contour recipe for class=%s" % contour_class)
	return recipe.duplicate(true)

static func get_contour_recipe_source_for_class(contour_class: StringName) -> String:
	_ensure_contour_recipes_loaded()
	return str(_contour_recipe_source_by_class.get(contour_class, ""))

static func get_contour_recipe_id_for_class(contour_class: StringName) -> StringName:
	var recipe: Dictionary = get_contour_recipe_for_class(contour_class)
	return StringName(str(recipe.get("asset_name", contour_class)))

static func _resolve_profile_for_terrain(terrain_id: int) -> TerrainPresentationProfile:
	assert(_profile_id_by_terrain_id.has(terrain_id), "Missing terrain presentation profile mapping for terrain_id=%d" % terrain_id)
	var profile_id: StringName = _profile_id_by_terrain_id[terrain_id] as StringName
	var profile: TerrainPresentationProfile = _profiles_by_id.get(profile_id, null) as TerrainPresentationProfile
	assert(profile != null, "Missing TerrainPresentationProfile resource for terrain_id=%d profile_id=%s" % [terrain_id, profile_id])
	return profile

static func _ensure_contour_recipes_loaded() -> void:
	if _contour_recipes_by_class.size() == WorldRuntimeConstants.CONTOUR_CLASSES.size():
		return
	_contour_recipes_by_class.clear()
	_contour_recipe_source_by_class.clear()
	for contour_class_variant: Variant in WorldRuntimeConstants.CONTOUR_CLASSES:
		var contour_class: StringName = contour_class_variant as StringName
		var recipe: Dictionary = _load_contour_recipe_for_class(contour_class)
		assert(not recipe.is_empty(), "Failed to load runtime SDF contour recipe for class=%s" % contour_class)
		if recipe.is_empty():
			continue
		_contour_recipes_by_class[contour_class] = recipe

static func _load_contour_recipe_for_class(contour_class: StringName) -> Dictionary:
	var paths: Array = CONTOUR_RECIPE_PATHS_BY_CLASS.get(contour_class, []) as Array
	for path_variant: Variant in paths:
		var path: String = str(path_variant)
		if not FileAccess.file_exists(path):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is not Dictionary:
			continue
		var recipe: Dictionary = _normalize_contour_recipe(parsed as Dictionary, contour_class)
		if recipe.is_empty():
			continue
		_contour_recipe_source_by_class[contour_class] = path
		return recipe
	return {}

static func _normalize_contour_recipe(source: Dictionary, contour_class: StringName) -> Dictionary:
	if str(source.get("schema", "")) == "station_peaceful.runtime_sdf_contour_recipe.v1":
		var recipe: Dictionary = source.duplicate(true)
		recipe["solid_class"] = str(contour_class)
		var collision: Dictionary = (recipe.get("collision", {}) as Dictionary).duplicate(true)
		collision["blocks_inside"] = contour_class == WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
		recipe["collision"] = collision
		if contour_class == WorldRuntimeConstants.CONTOUR_CLASS_WATER_SURFACE:
			recipe["asset_name"] = "water"
		return recipe
	return {}

static func _register_shader_family(shader_family_resource: Resource) -> void:
	var shader_family: TerrainShaderFamily = shader_family_resource as TerrainShaderFamily
	assert(shader_family != null, "TerrainPresentationRegistry requires TerrainShaderFamily resources")
	assert(shader_family.is_valid_family(), "Invalid TerrainShaderFamily resource")
	assert(not _shader_families_by_id.has(shader_family.id), "Duplicate TerrainShaderFamily id: %s" % [shader_family.id])
	_shader_families_by_id[shader_family.id] = shader_family

static func _register_shape_set(shape_set_resource: Resource) -> void:
	var shape_set: TerrainShapeSet = shape_set_resource as TerrainShapeSet
	assert(shape_set != null, "TerrainPresentationRegistry requires TerrainShapeSet resources")
	assert(shape_set.is_valid_shape(), "Invalid TerrainShapeSet resource")
	assert(not _shape_sets_by_id.has(shape_set.id), "Duplicate TerrainShapeSet id: %s" % [shape_set.id])
	_shape_sets_by_id[shape_set.id] = shape_set

static func _register_material_set(material_set_resource: Resource) -> void:
	var material_set: TerrainMaterialSet = material_set_resource as TerrainMaterialSet
	assert(material_set != null, "TerrainPresentationRegistry requires TerrainMaterialSet resources")
	assert(material_set.is_valid_material(), "Invalid TerrainMaterialSet resource")
	assert(not _material_sets_by_id.has(material_set.id), "Duplicate TerrainMaterialSet id: %s" % [material_set.id])
	_material_sets_by_id[material_set.id] = material_set

static func _register_profile(profile_resource: Resource) -> void:
	var profile: TerrainPresentationProfile = profile_resource as TerrainPresentationProfile
	assert(profile != null, "TerrainPresentationRegistry requires TerrainPresentationProfile resources")
	assert(_is_valid_profile_resource(profile), "Invalid TerrainPresentationProfile resource")
	assert(not _profiles_by_id.has(profile.id), "Duplicate TerrainPresentationProfile id: %s" % [profile.id])
	_profiles_by_id[profile.id] = profile
	for terrain_id: int in profile.terrain_ids:
		assert(not _profile_id_by_terrain_id.has(terrain_id), "Duplicate terrain presentation mapping for terrain_id=%d" % terrain_id)
		_profile_id_by_terrain_id[terrain_id] = profile.id

static func _validate_registered_resources() -> void:
	assert(not _profiles_by_id.is_empty(), "TerrainPresentationRegistry requires at least one TerrainPresentationProfile")
	for shader_family_variant: Variant in _shader_families_by_id.values():
		_validate_shader_family(shader_family_variant as TerrainShaderFamily)
	for shape_set_variant: Variant in _shape_sets_by_id.values():
		_validate_shape_set(shape_set_variant as TerrainShapeSet)
	for material_set_variant: Variant in _material_sets_by_id.values():
		_validate_material_set(material_set_variant as TerrainMaterialSet)
	for profile_variant: Variant in _profiles_by_id.values():
		_validate_profile(profile_variant as TerrainPresentationProfile)
	for terrain_id: int in [
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
		WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
		WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW,
		WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP,
	]:
		assert(_profile_id_by_terrain_id.has(terrain_id), "Missing terrain presentation profile mapping for terrain_id=%d" % terrain_id)
		assert(_resolve_profile_for_terrain(terrain_id) != null, "TerrainPresentationRegistry failed to resolve terrain_id=%d" % terrain_id)

static func _load_resources_from_directory(directory_path: String) -> Array[Resource]:
	var directory: DirAccess = DirAccess.open(directory_path)
	assert(directory != null, "TerrainPresentationRegistry missing directory: %s" % [directory_path])
	var resource_paths: Array[String] = []
	directory.list_dir_begin()
	while true:
		var entry_name: String = directory.get_next()
		if entry_name.is_empty():
			break
		if directory.current_is_dir():
			continue
		if not entry_name.ends_with(".tres") and not entry_name.ends_with(".res"):
			continue
		resource_paths.append("%s/%s" % [directory_path, entry_name])
	directory.list_dir_end()
	resource_paths.sort()
	assert(not resource_paths.is_empty(), "TerrainPresentationRegistry found no resources in %s" % [directory_path])
	var resources: Array[Resource] = []
	for resource_path: String in resource_paths:
		var resource: Resource = ResourceLoader.load(resource_path)
		assert(resource != null, "Failed to load terrain presentation resource: %s" % [resource_path])
		resources.append(resource)
	return resources

static func _validate_shader_family(shader_family: TerrainShaderFamily) -> void:
	assert(shader_family.render_layer_id == RENDER_LAYER_BASE or shader_family.render_layer_id == RENDER_LAYER_OVERLAY, "Unsupported render_layer_id on TerrainShaderFamily %s: %s" % [shader_family.id, shader_family.render_layer_id])
	if not shader_family.shape_texture_params.is_empty() or not shader_family.material_texture_params.is_empty():
		assert(shader_family.shader != null, "TerrainShaderFamily %s requires a shader when parameter bindings are declared" % [shader_family.id])

static func _validate_shape_set(shape_set: TerrainShapeSet) -> void:
	assert(shape_set.mask_atlas != null, "TerrainShapeSet %s is missing mask_atlas" % [shape_set.id])
	if shape_set.topology_family_id == TOPOLOGY_AUTOTILE_47:
		assert(shape_set.shape_normal_atlas != null, "TerrainShapeSet %s requires shape_normal_atlas for autotile_47" % [shape_set.id])
		assert(
			shape_set.shape_normal_atlas.get_width() == shape_set.mask_atlas.get_width()
			and shape_set.shape_normal_atlas.get_height() == shape_set.mask_atlas.get_height(),
			"TerrainShapeSet %s shape_normal_atlas must match mask_atlas dimensions" % [shape_set.id]
		)
		assert(shape_set.case_count == Autotile47.CASE_COUNT, "TerrainShapeSet %s must declare 47 autotile cases" % [shape_set.id])
		assert(shape_set.variant_count >= 1, "TerrainShapeSet %s must declare at least one variant" % [shape_set.id])
	elif shape_set.topology_family_id == TOPOLOGY_SINGLE_TILE:
		assert(shape_set.case_count == 1 and shape_set.variant_count == 1, "TerrainShapeSet %s single_tile must use 1 case and 1 variant" % [shape_set.id])
	else:
		assert(false, "Unsupported topology_family_id on TerrainShapeSet %s: %s" % [shape_set.id, shape_set.topology_family_id])

static func _validate_material_set(material_set: TerrainMaterialSet) -> void:
	var shader_family: TerrainShaderFamily = _shader_families_by_id.get(material_set.shader_family_id, null) as TerrainShaderFamily
	assert(shader_family != null, "TerrainMaterialSet %s references missing shader_family_id=%s" % [material_set.id, material_set.shader_family_id])
	var validated_slots: Dictionary = {}
	for slot_variant: Variant in shader_family.material_texture_params.values():
		var slot_id: StringName = StringName(str(slot_variant))
		if validated_slots.has(slot_id):
			continue
		validated_slots[slot_id] = true
		assert(material_set.get_texture_slot(slot_id) != null, "TerrainMaterialSet %s requires texture slot %s for shader family %s" % [material_set.id, slot_id, shader_family.id])

static func _validate_profile(profile: TerrainPresentationProfile) -> void:
	var shader_family: TerrainShaderFamily = _shader_families_by_id.get(profile.shader_family_id, null) as TerrainShaderFamily
	var shape_set: TerrainShapeSet = _shape_sets_by_id.get(profile.shape_set_id, null) as TerrainShapeSet
	var material_set: TerrainMaterialSet = _material_sets_by_id.get(profile.material_set_id, null) as TerrainMaterialSet
	assert(shader_family != null, "TerrainPresentationProfile %s references missing shader_family_id=%s" % [profile.id, profile.shader_family_id])
	assert(shape_set != null, "TerrainPresentationProfile %s references missing shape_set_id=%s" % [profile.id, profile.shape_set_id])
	assert(material_set != null, "TerrainPresentationProfile %s references missing material_set_id=%s" % [profile.id, profile.material_set_id])
	assert(profile.shader_family_id == material_set.shader_family_id, "TerrainPresentationProfile %s must match TerrainMaterialSet shader family" % [profile.id])
	var validated_shape_slots: Dictionary = {}
	for slot_variant: Variant in shader_family.shape_texture_params.values():
		var slot_id: StringName = StringName(str(slot_variant))
		if validated_shape_slots.has(slot_id):
			continue
		validated_shape_slots[slot_id] = true
		assert(shape_set.get_texture_slot(slot_id) != null, "TerrainPresentationProfile %s requires shape texture slot %s for shader family %s" % [profile.id, slot_id, shader_family.id])
	for terrain_id: int in profile.terrain_ids:
		var expected_topology_family_id: StringName = _expected_topology_family_for_terrain(terrain_id)
		if not str(expected_topology_family_id).is_empty():
			assert(
				shape_set.topology_family_id == expected_topology_family_id,
				"TerrainPresentationProfile %s terrain_id=%d expects topology_family_id=%s but shape_set=%s declares %s" % [
					profile.id,
					terrain_id,
					expected_topology_family_id,
					shape_set.id,
					shape_set.topology_family_id,
				]
			)

static func _expected_topology_family_for_terrain(terrain_id: int) -> StringName:
	if is_contour_cutover_terrain(terrain_id):
		return &""
	match terrain_id:
		WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW:
			return TOPOLOGY_AUTOTILE_47
		WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP:
			return TOPOLOGY_AUTOTILE_47
		_:
			return &""

static func _is_valid_profile_resource(profile: TerrainPresentationProfile) -> bool:
	if profile.is_valid_profile():
		return true
	return not str(profile.id).is_empty() \
		and not str(profile.terrain_class_id).is_empty() \
		and profile.terrain_ids.is_empty() \
		and not str(profile.shape_set_id).is_empty() \
		and not str(profile.material_set_id).is_empty() \
		and not str(profile.shader_family_id).is_empty()
