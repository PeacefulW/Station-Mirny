class_name PlainsSmallRockPlacementSettings
extends Resource

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DENSITY_MIN: float = 0.0
const DENSITY_MAX: float = 1.0
const SCATTER_GRID_SIDE_MIN: int = 1
const SCATTER_GRID_SIDE_MAX: int = 16
const MAX_PER_CHUNK_MIN: int = 0
const MAX_PER_CHUNK_MAX: int = 64
const SIZE_MIN: float = 1.0
const SIZE_MAX: float = 254.0
const ASSET_VARIANT_COUNT_MIN: int = 1
const ASSET_VARIANT_COUNT_MAX: int = 64

@export_group("Identity")
@export var id: StringName = &"core:plains_small_rocks"
@export var object_family: StringName = &"small_rock"
@export var biome_id: StringName = &"core:plains"
@export var placement_mask: StringName = &"sparse_grass_edge"

@export_group("Placement")
@export_range(0.0, 1.0, 0.01) var density: float = 0.56
@export_range(1, 16) var scatter_grid_side: int = 6
@export_range(0, 64) var max_per_chunk: int = 5
@export_range(0.0, 256.0) var edge_padding_px: float = 42.0
@export_range(0.0, 512.0) var min_distance_px: float = 92.0
@export_range(0.0, 1.0, 0.01) var grass_density_min: float = 0.05
@export_range(0.0, 1.0, 0.01) var grass_density_max: float = 0.46

@export_group("Size")
@export_range(1.0, 254.0) var visual_size_min_px: float = 42.0
@export_range(1.0, 254.0) var visual_size_max_px: float = 76.0
@export_range(1, 64) var asset_variant_count: int = 10

@export_group("Ground Field")
@export var grass_field_scale_px: float = 720.0
@export_range(0.0, 1.0, 0.01) var grass_coverage: float = 0.80
@export var rock_field_scale_px: float = 1200.0
@export_range(0.0, 1.0, 0.01) var rock_coverage: float = 0.22
@export var macro_mass_scale_px: float = 7000.0
@export_range(0.0, 1.0, 0.01) var macro_mass_strength: float = 0.34
@export var path_scale_px: float = 2600.0
@export_range(0.0, 1.0, 0.01) var path_width: float = 0.06
@export var path_warp_px: float = 700.0
@export_range(0.0, 1.0, 0.01) var path_strength: float = 0.85


func apply_ground_sampling_params(ground_params: Dictionary) -> void:
	grass_field_scale_px = _read_float(ground_params, "grass_field_scale_px", grass_field_scale_px)
	grass_coverage = clampf(_read_float(ground_params, "grass_coverage", grass_coverage), 0.0, 1.0)
	rock_field_scale_px = _read_float(ground_params, "rock_field_scale_px", rock_field_scale_px)
	rock_coverage = clampf(_read_float(ground_params, "rock_coverage", rock_coverage), 0.0, 1.0)
	macro_mass_scale_px = _read_float(ground_params, "macro_mass_scale_px", macro_mass_scale_px)
	macro_mass_strength = clampf(_read_float(ground_params, "macro_mass_strength", macro_mass_strength), 0.0, 1.0)
	path_scale_px = _read_float(ground_params, "path_scale_px", path_scale_px)
	path_width = clampf(_read_float(ground_params, "path_width", path_width), 0.0, 1.0)
	path_warp_px = _read_float(ground_params, "path_warp_px", path_warp_px)
	path_strength = clampf(_read_float(ground_params, "path_strength", path_strength), 0.0, 1.0)


func to_save_dict() -> Dictionary:
	return {
		"id": String(id),
		"object_family": String(object_family),
		"biome_id": String(biome_id),
		"placement_mask": String(placement_mask),
		"density": density,
		"scatter_grid_side": scatter_grid_side,
		"max_per_chunk": max_per_chunk,
		"edge_padding_px": edge_padding_px,
		"min_distance_px": min_distance_px,
		"grass_density_min": grass_density_min,
		"grass_density_max": grass_density_max,
		"visual_size_min_px": visual_size_min_px,
		"visual_size_max_px": visual_size_max_px,
		"asset_variant_count": asset_variant_count,
		"grass_field_scale_px": grass_field_scale_px,
		"grass_coverage": grass_coverage,
		"rock_field_scale_px": rock_field_scale_px,
		"rock_coverage": rock_coverage,
		"macro_mass_scale_px": macro_mass_scale_px,
		"macro_mass_strength": macro_mass_strength,
		"path_scale_px": path_scale_px,
		"path_width": path_width,
		"path_warp_px": path_warp_px,
		"path_strength": path_strength,
	}


func write_to_settings_packed(settings_packed: PackedFloat32Array) -> PackedFloat32Array:
	var settings: PlainsSmallRockPlacementSettings = from_save_dict(to_save_dict())
	var packed: PackedFloat32Array = settings_packed.duplicate()
	packed.resize(WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_FIELD_COUNT)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_DENSITY] = settings.density
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_SCATTER_GRID_SIDE] = float(settings.scatter_grid_side)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_EDGE_PADDING_PX] = settings.edge_padding_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_MIN_DISTANCE_PX] = settings.min_distance_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_MAX_PER_CHUNK] = float(settings.max_per_chunk)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_MIN_SIZE_PX] = settings.visual_size_min_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_MAX_SIZE_PX] = settings.visual_size_max_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_GRASS_DENSITY_MIN] = settings.grass_density_min
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_GRASS_DENSITY_MAX] = settings.grass_density_max
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_GRASS_FIELD_SCALE_PX] = settings.grass_field_scale_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_GRASS_COVERAGE] = settings.grass_coverage
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_ROCK_FIELD_SCALE_PX] = settings.rock_field_scale_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_ROCK_COVERAGE] = settings.rock_coverage
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_MACRO_MASS_SCALE_PX] = settings.macro_mass_scale_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_MACRO_MASS_STRENGTH] = settings.macro_mass_strength
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_PATH_SCALE_PX] = settings.path_scale_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_PATH_WIDTH] = settings.path_width
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_PATH_WARP_PX] = settings.path_warp_px
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_PATH_STRENGTH] = settings.path_strength
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SMALL_ROCK_ASSET_VARIANT_COUNT] = float(settings.asset_variant_count)
	return packed


static func from_save_dict(data: Dictionary) -> PlainsSmallRockPlacementSettings:
	var settings: PlainsSmallRockPlacementSettings = hard_coded_defaults()
	settings.id = StringName(str(data.get("id", settings.id)))
	settings.object_family = StringName(str(data.get("object_family", settings.object_family)))
	settings.biome_id = StringName(str(data.get("biome_id", settings.biome_id)))
	settings.placement_mask = StringName(str(data.get("placement_mask", settings.placement_mask)))
	settings.density = clampf(_read_float(data, "density", settings.density), DENSITY_MIN, DENSITY_MAX)
	settings.scatter_grid_side = clampi(
		_read_int(data, "scatter_grid_side", settings.scatter_grid_side),
		SCATTER_GRID_SIDE_MIN,
		SCATTER_GRID_SIDE_MAX,
	)
	settings.max_per_chunk = clampi(
		_read_int(data, "max_per_chunk", settings.max_per_chunk),
		MAX_PER_CHUNK_MIN,
		MAX_PER_CHUNK_MAX,
	)
	settings.edge_padding_px = maxf(0.0, _read_float(data, "edge_padding_px", settings.edge_padding_px))
	settings.min_distance_px = maxf(0.0, _read_float(data, "min_distance_px", settings.min_distance_px))
	settings.grass_density_min = clampf(
		_read_float(data, "grass_density_min", settings.grass_density_min),
		0.0,
		1.0,
	)
	settings.grass_density_max = clampf(
		_read_float(data, "grass_density_max", settings.grass_density_max),
		settings.grass_density_min,
		1.0,
	)
	settings.visual_size_min_px = clampf(
		_read_float(data, "visual_size_min_px", settings.visual_size_min_px),
		SIZE_MIN,
		SIZE_MAX,
	)
	settings.visual_size_max_px = clampf(
		_read_float(data, "visual_size_max_px", settings.visual_size_max_px),
		settings.visual_size_min_px,
		SIZE_MAX,
	)
	settings.asset_variant_count = clampi(
		_read_int(data, "asset_variant_count", settings.asset_variant_count),
		ASSET_VARIANT_COUNT_MIN,
		ASSET_VARIANT_COUNT_MAX,
	)
	settings.grass_field_scale_px = maxf(1.0, _read_float(data, "grass_field_scale_px", settings.grass_field_scale_px))
	settings.grass_coverage = clampf(_read_float(data, "grass_coverage", settings.grass_coverage), 0.0, 1.0)
	settings.rock_field_scale_px = maxf(1.0, _read_float(data, "rock_field_scale_px", settings.rock_field_scale_px))
	settings.rock_coverage = clampf(_read_float(data, "rock_coverage", settings.rock_coverage), 0.0, 1.0)
	settings.macro_mass_scale_px = maxf(1.0, _read_float(data, "macro_mass_scale_px", settings.macro_mass_scale_px))
	settings.macro_mass_strength = clampf(
		_read_float(data, "macro_mass_strength", settings.macro_mass_strength),
		0.0,
		1.0,
	)
	settings.path_scale_px = maxf(1.0, _read_float(data, "path_scale_px", settings.path_scale_px))
	settings.path_width = clampf(_read_float(data, "path_width", settings.path_width), 0.0, 1.0)
	settings.path_warp_px = maxf(0.0, _read_float(data, "path_warp_px", settings.path_warp_px))
	settings.path_strength = clampf(_read_float(data, "path_strength", settings.path_strength), 0.0, 1.0)
	return settings


static func hard_coded_defaults() -> PlainsSmallRockPlacementSettings:
	return new()


static func _read_float(data: Dictionary, key: String, fallback: float) -> float:
	if not data.has(key):
		return fallback
	return float(data.get(key, fallback))


static func _read_int(data: Dictionary, key: String, fallback: int) -> int:
	if not data.has(key):
		return fallback
	return int(data.get(key, fallback))
