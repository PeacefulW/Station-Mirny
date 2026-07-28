class_name VisualRuntimeLabAuthoring
extends RefCounted

const TerrainPresentationRegistry = preload(
	"res://core/systems/world/terrain_presentation_registry.gd"
)
const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)

const GROUND_PATH: String = "res://data/terrain/material_sets/plains_ground_material_set.tres"
const GRASS_PATH: String = "res://data/terrain/material_sets/grass_scatter_material_set.tres"
const TREE_PATH: String = "res://data/world_objects/placement_groups/plains_trees.tres"
const SMALL_ROCK_PATH: String = "res://data/world_objects/placement_groups/plains_small_rocks.tres"
const BARE_STONE_PATH: String = "res://data/world_objects/placement_groups/plains_bare_ground_stones.tres"
const MOUNTAIN_PATH: String = "res://data/balance/mountain_gen_settings.tres"
const LAKE_PATH: String = "res://data/balance/lake_gen_settings.tres"
const FOUNDATION_PATH: String = "res://data/balance/foundation_gen_settings.tres"

var ground: TerrainMaterialSet = null
var grass: TerrainMaterialSet = null
var trees: PlainsTreePlacementSettings = null
var small_rocks: PlainsSmallRockPlacementSettings = null
var bare_stones: PlainsSmallRockPlacementSettings = null
var mountains: MountainGenSettings = null
var lakes: LakeGenSettings = null
var foundation: FoundationGenSettings = null
var world_bounds: WorldBoundsSettings = null


func load_from_disk() -> Dictionary:
	var ground_source: TerrainMaterialSet = ResourceLoader.load(
		GROUND_PATH,
		"TerrainMaterialSet",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as TerrainMaterialSet
	var grass_source: TerrainMaterialSet = ResourceLoader.load(
		GRASS_PATH,
		"TerrainMaterialSet",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as TerrainMaterialSet
	var tree_source: PlainsTreePlacementSettings = ResourceLoader.load(
		TREE_PATH,
		"PlainsTreePlacementSettings",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as PlainsTreePlacementSettings
	var small_rock_source: PlainsSmallRockPlacementSettings = ResourceLoader.load(
		SMALL_ROCK_PATH,
		"PlainsSmallRockPlacementSettings",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as PlainsSmallRockPlacementSettings
	var bare_stone_source: PlainsSmallRockPlacementSettings = ResourceLoader.load(
		BARE_STONE_PATH,
		"PlainsSmallRockPlacementSettings",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as PlainsSmallRockPlacementSettings
	var mountain_source: MountainGenSettings = ResourceLoader.load(
		MOUNTAIN_PATH,
		"MountainGenSettings",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as MountainGenSettings
	var lake_source: LakeGenSettings = ResourceLoader.load(
		LAKE_PATH,
		"LakeGenSettings",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as LakeGenSettings
	var foundation_source: FoundationGenSettings = ResourceLoader.load(
		FOUNDATION_PATH,
		"FoundationGenSettings",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as FoundationGenSettings
	if ground_source == null \
			or grass_source == null \
			or tree_source == null \
			or small_rock_source == null \
			or bare_stone_source == null \
			or mountain_source == null \
			or lake_source == null \
			or foundation_source == null:
		return {
			"success": false,
			"error": ERR_FILE_CANT_READ,
		}
	ground = ground_source.duplicate(true) as TerrainMaterialSet
	grass = grass_source.duplicate(true) as TerrainMaterialSet
	ground.sampling_params = ground_source.sampling_params.duplicate(true)
	grass.sampling_params = grass_source.sampling_params.duplicate(true)
	trees = PlainsTreePlacementSettings.from_save_dict(tree_source.to_save_dict())
	small_rocks = PlainsSmallRockPlacementSettings.from_save_dict(
		small_rock_source.to_save_dict()
	)
	bare_stones = PlainsSmallRockPlacementSettings.from_save_dict(
		bare_stone_source.to_save_dict()
	)
	mountains = MountainGenSettings.from_save_dict(mountain_source.to_save_dict())
	lakes = LakeGenSettings.from_save_dict(lake_source.to_save_dict())
	world_bounds = WorldBoundsSettings.hard_coded_defaults()
	foundation = FoundationGenSettings.from_save_dict(
		foundation_source.to_save_dict(),
		world_bounds,
	)
	return { "success": true }


func apply_material_working_copies_to_registry() -> void:
	TerrainPresentationRegistry.bootstrap()
	var runtime_ground: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		&"base:plains_ground_material",
	)
	var runtime_grass: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		&"plains:grass_scatter_material",
	)
	assert(runtime_ground != null and runtime_grass != null)
	runtime_ground.sampling_params = ground.sampling_params.duplicate(true)
	runtime_grass.sampling_params = grass.sampling_params.duplicate(true)


func get_settings_packed() -> PackedFloat32Array:
	var packed: PackedFloat32Array = mountains.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, world_bounds)
	packed = lakes.write_to_settings_packed(packed)
	packed = trees.write_to_settings_packed(packed)
	packed = small_rocks.write_to_settings_packed(packed)
	packed = bare_stones.write_to_settings_packed(
		packed,
		WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_BARE_GROUND_STONE_BLOCK_BEGIN,
	)
	return packed


func get_value(control_id: StringName) -> float:
	match control_id:
		&"ground.grass_coverage":
			return _param(ground.sampling_params, "grass_coverage", 0.8)
		&"ground.orange_coverage":
			return _param(ground.sampling_params, "orange_coverage", 0.22)
		&"ground.rock_visual_coverage":
			return _param(ground.sampling_params, "rock_visual_coverage", 0.45)
		&"ground.path_strength":
			return _param(ground.sampling_params, "path_strength", 0.85)
		&"grass.density_scale":
			return _param(grass.sampling_params, "density_scale", 5.0)
		&"grass.height_scale":
			return _param(grass.sampling_params, "height_scale", 1.0)
		&"grass.tuft_min_height_px":
			return _param(grass.sampling_params, "tuft_min_height_px", 24.0)
		&"grass.tuft_max_height_px":
			return _param(grass.sampling_params, "tuft_max_height_px", 55.0)
		&"grass.variety":
			return _param(grass.sampling_params, "dry_frame_count", 16.0)
		&"grass.wind_sway_fraction":
			return _param(grass.sampling_params, "wind_sway_fraction", 0.19)
		&"trees.density":
			return trees.density
		&"trees.min_distance_px":
			return trees.min_distance_px
		&"trees.visual_size_min_px":
			return trees.visual_size_min_px
		&"trees.visual_size_max_px":
			return trees.visual_size_max_px
		&"rocks.density":
			return small_rocks.density
		&"rocks.max_per_chunk":
			return float(small_rocks.max_per_chunk)
		&"rocks.asset_variant_count":
			return float(small_rocks.asset_variant_count)
		&"lakes.deep_threshold":
			return lakes.deep_threshold
		&"lakes.shore_warp_amplitude":
			return lakes.shore_warp_amplitude
		&"mountains.density":
			return mountains.density
		&"mountains.ruggedness":
			return mountains.ruggedness
	return 0.0


func set_value(control_id: StringName, value: float) -> void:
	match control_id:
		&"ground.grass_coverage":
			_set_param(ground.sampling_params, "grass_coverage", clampf(value, 0.0, 1.0))
			_sync_ground_field_settings()
		&"ground.orange_coverage":
			_set_param(ground.sampling_params, "orange_coverage", clampf(value, 0.0, 1.0))
		&"ground.rock_visual_coverage":
			_set_param(
				ground.sampling_params,
				"rock_visual_coverage",
				clampf(value, 0.0, 1.0),
			)
		&"ground.path_strength":
			_set_param(ground.sampling_params, "path_strength", clampf(value, 0.0, 1.0))
			_sync_ground_field_settings()
		&"grass.density_scale":
			_set_param(grass.sampling_params, "density_scale", clampf(value, 0.0, 8.0))
		&"grass.height_scale":
			_set_param(grass.sampling_params, "height_scale", clampf(value, 0.25, 2.0))
		&"grass.tuft_min_height_px":
			_set_param(
				grass.sampling_params,
				"tuft_min_height_px",
				clampf(value, 8.0, get_value(&"grass.tuft_max_height_px")),
			)
		&"grass.tuft_max_height_px":
			_set_param(
				grass.sampling_params,
				"tuft_max_height_px",
				clampf(value, get_value(&"grass.tuft_min_height_px"), 96.0),
			)
		&"grass.variety":
			var frame_count: float = clampf(roundf(value), 1.0, 16.0)
			_set_param(grass.sampling_params, "dry_frame_count", frame_count)
			_set_param(grass.sampling_params, "orange_frame_count", frame_count)
		&"grass.wind_sway_fraction":
			_set_param(
				grass.sampling_params,
				"wind_sway_fraction",
				clampf(value, 0.0, 0.35),
			)
		&"trees.density":
			trees.density = clampf(value, 0.0, 1.0)
		&"trees.min_distance_px":
			trees.min_distance_px = clampf(value, 32.0, 256.0)
		&"trees.visual_size_min_px":
			trees.visual_size_min_px = clampf(value, 64.0, trees.visual_size_max_px)
		&"trees.visual_size_max_px":
			trees.visual_size_max_px = clampf(value, trees.visual_size_min_px, 254.0)
		&"rocks.density":
			small_rocks.density = clampf(value, 0.0, 1.0)
		&"rocks.max_per_chunk":
			small_rocks.max_per_chunk = clampi(roundi(value), 0, 64)
		&"rocks.asset_variant_count":
			small_rocks.asset_variant_count = clampi(roundi(value), 1, 10)
		&"lakes.deep_threshold":
			lakes.deep_threshold = clampf(value, 0.05, 0.5)
		&"lakes.shore_warp_amplitude":
			lakes.shore_warp_amplitude = clampf(value, 0.0, 1.0)
		&"mountains.density":
			mountains.density = clampf(value, 0.0, 1.0)
		&"mountains.ruggedness":
			mountains.ruggedness = clampf(value, 0.0, 1.0)


func save_to_runtime(save_resource: Callable = Callable()) -> Dictionary:
	var resources: Array[Resource] = [
		ground,
		grass,
		trees,
		small_rocks,
		bare_stones,
		lakes,
		mountains,
	]
	var paths: Array[String] = [
		GROUND_PATH,
		GRASS_PATH,
		TREE_PATH,
		SMALL_ROCK_PATH,
		BARE_STONE_PATH,
		LAKE_PATH,
		MOUNTAIN_PATH,
	]
	for index: int in range(resources.size()):
		var save_error: Error = (
			save_resource.call(resources[index], paths[index])
			if save_resource.is_valid()
			else ResourceSaver.save(resources[index], paths[index])
		) as Error
		if save_error != OK:
			return {
				"success": false,
				"error": save_error,
				"path": paths[index],
			}
	return {
		"success": true,
		"paths": paths,
	}


func get_texture_manifest_text() -> String:
	var lines: Array[String] = []
	lines.append("[color=#b4bea9]ground[/color]")
	for slot_variant: Variant in ground.extra_textures.keys():
		var slot: StringName = StringName(str(slot_variant))
		var texture: Texture2D = ground.get_texture_slot(slot)
		if texture != null:
			lines.append("  %s → %s" % [String(slot), texture.resource_path])
	lines.append("[color=#b4bea9]grass[/color]")
	for slot_variant: Variant in grass.extra_textures.keys():
		var slot: StringName = StringName(str(slot_variant))
		var texture: Texture2D = grass.get_texture_slot(slot)
		if texture != null:
			lines.append("  %s → %s" % [String(slot), texture.resource_path])
	return "\n".join(lines)


func get_ground_zone_texture_info(zone_id: int) -> Dictionary:
	match zone_id:
		0:
			return _zone_texture_info(
				"UI_VISUAL_LAB_ZONE_DIRTY",
				[&"dirty_albedo"],
			)
		1:
			return {
				"label_key": "UI_VISUAL_LAB_ZONE_GRAVEL",
				"texture": ground.top_albedo.resource_path.get_file(),
			}
		2:
			return _zone_texture_info(
				"UI_VISUAL_LAB_ZONE_GRASS_TRANSITION",
				[&"grass_transition_albedo"],
			)
		3:
			return _zone_texture_info(
				"UI_VISUAL_LAB_ZONE_GRASS_SPARSE",
				[&"grass_sparse_albedo"],
			)
		4:
			return _zone_texture_info(
				"UI_VISUAL_LAB_ZONE_GRASS_MEDIUM",
				[&"grass_medium_albedo"],
			)
		5:
			return _zone_texture_info(
				"UI_VISUAL_LAB_ZONE_GRASS_DENSE",
				[&"grass_dense_albedo"],
			)
		6:
			return {
				"label_key": "UI_VISUAL_LAB_ZONE_PATH",
				"texture": "%s + %s" % [
					_texture_file_for_slot(&"dirty_albedo"),
					ground.top_albedo.resource_path.get_file(),
				],
			}
		7:
			return _zone_texture_info(
				"UI_VISUAL_LAB_ZONE_SCREE",
				[&"rock_top_albedo", &"rock_foothill_albedo"],
			)
		8:
			return _zone_texture_info(
				"UI_VISUAL_LAB_ZONE_ROCK",
				[&"rock_top_albedo", &"rock_foothill_albedo"],
			)
		9:
			return _zone_texture_info(
				"UI_VISUAL_LAB_ZONE_ORANGE",
				[&"orange_biofield_albedo"],
			)
	return {
		"label_key": "UI_VISUAL_LAB_TERRAIN_UNKNOWN",
		"texture": "",
	}


func _sync_ground_field_settings() -> void:
	trees.apply_ground_sampling_params(ground.sampling_params)
	small_rocks.apply_ground_sampling_params(ground.sampling_params)
	bare_stones.apply_ground_sampling_params(ground.sampling_params)


func _param(params: Dictionary, key: String, fallback: float) -> float:
	return float(params.get(key, fallback))


func _set_param(params: Dictionary, key: String, value: float) -> void:
	params[key] = value


func _zone_texture_info(label_key: String, slots: Array[StringName]) -> Dictionary:
	var texture_files: Array[String] = []
	for slot: StringName in slots:
		var texture_file: String = _texture_file_for_slot(slot)
		if not texture_file.is_empty():
			texture_files.append(texture_file)
	return {
		"label_key": label_key,
		"texture": " + ".join(texture_files),
	}


func _texture_file_for_slot(slot: StringName) -> String:
	var texture: Texture2D = ground.get_texture_slot(slot)
	return texture.resource_path.get_file() if texture != null else ""
