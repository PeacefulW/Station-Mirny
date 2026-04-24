class_name FoundationGenSettings
extends Resource

const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const POLE_ORIENTATION_OCEAN_TOP: int = 0
const POLE_ORIENTATION_REVERSED: int = 1
const BAND_TILES_MIN: int = 64
const BAND_TILES_MAX: int = 1024
const SLOPE_BIAS_MIN: float = -1.0
const SLOPE_BIAS_MAX: float = 1.0
const RIVER_AMOUNT_MIN: float = 0.0
const RIVER_AMOUNT_MAX: float = 1.0

@export_range(64, 1024) var ocean_band_tiles: int = 128
@export_range(64, 1024) var burning_band_tiles: int = 128
@export_range(0, 1) var pole_orientation: int = POLE_ORIENTATION_OCEAN_TOP
@export_range(-1.0, 1.0, 0.05) var slope_bias: float = 0.0
@export_range(0.0, 1.0, 0.01) var river_amount: float = 0.35

func to_save_dict() -> Dictionary:
	return {
		"ocean_band_tiles": ocean_band_tiles,
		"burning_band_tiles": burning_band_tiles,
		"pole_orientation": pole_orientation,
		"slope_bias": slope_bias,
		"river_amount": river_amount,
	}

func write_to_settings_packed(
	settings_packed: PackedFloat32Array,
	world_bounds: WorldBoundsSettings
) -> PackedFloat32Array:
	var normalized_settings: FoundationGenSettings = normalized_for_bounds(world_bounds)
	var packed: PackedFloat32Array = settings_packed.duplicate()
	packed.resize(WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FIELD_COUNT)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_WORLD_WIDTH_TILES] = float(world_bounds.width_tiles)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_WORLD_HEIGHT_TILES] = float(world_bounds.height_tiles)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_OCEAN_BAND_TILES] = float(normalized_settings.ocean_band_tiles)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_BURNING_BAND_TILES] = float(normalized_settings.burning_band_tiles)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_POLE_ORIENTATION] = float(normalized_settings.pole_orientation)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FOUNDATION_SLOPE_BIAS] = normalized_settings.slope_bias
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_AMOUNT] = normalized_settings.river_amount
	return packed

func resolve_spawn_safe_patch_rect(world_bounds: WorldBoundsSettings) -> Rect2i:
	var normalized_settings: FoundationGenSettings = normalized_for_bounds(world_bounds)
	var patch_size: int = WorldRuntimeConstants.SPAWN_SAFE_PATCH_MAX_TILE \
		- WorldRuntimeConstants.SPAWN_SAFE_PATCH_MIN_TILE + 1
	var habitable_min_y: int = normalized_settings.ocean_band_tiles
	var habitable_max_y: int = world_bounds.height_tiles - normalized_settings.burning_band_tiles
	var habitable_height: int = maxi(patch_size, habitable_max_y - habitable_min_y)
	var start_x: int = maxi(0, world_bounds.width_tiles / 2 - patch_size / 2)
	var start_y: int = clampi(
		habitable_min_y + maxi(0, (habitable_height - patch_size) / 2),
		0,
		maxi(0, world_bounds.height_tiles - patch_size)
	)
	return Rect2i(Vector2i(start_x, start_y), Vector2i(patch_size, patch_size))

func normalized_for_bounds(world_bounds: WorldBoundsSettings) -> FoundationGenSettings:
	return from_save_dict(to_save_dict(), world_bounds)

static func for_bounds(world_bounds: WorldBoundsSettings) -> FoundationGenSettings:
	var settings: FoundationGenSettings = new()
	var default_band: int = maxi(BAND_TILES_MIN, world_bounds.height_tiles / 16)
	settings.ocean_band_tiles = _sanitize_band(default_band, world_bounds)
	settings.burning_band_tiles = _sanitize_band(default_band, world_bounds)
	return settings

static func hard_coded_defaults() -> FoundationGenSettings:
	return for_bounds(WorldBoundsSettings.hard_coded_defaults())

static func from_save_dict(data: Dictionary, world_bounds: WorldBoundsSettings) -> FoundationGenSettings:
	var settings: FoundationGenSettings = for_bounds(world_bounds)
	settings.ocean_band_tiles = _sanitize_band(
		int(data.get("ocean_band_tiles", settings.ocean_band_tiles)),
		world_bounds
	)
	settings.burning_band_tiles = _sanitize_band(
		int(data.get("burning_band_tiles", settings.burning_band_tiles)),
		world_bounds
	)
	settings.pole_orientation = clampi(
		int(data.get("pole_orientation", settings.pole_orientation)),
		POLE_ORIENTATION_OCEAN_TOP,
		POLE_ORIENTATION_REVERSED
	)
	settings.slope_bias = clampf(
		float(data.get("slope_bias", settings.slope_bias)),
		SLOPE_BIAS_MIN,
		SLOPE_BIAS_MAX
	)
	settings.river_amount = clampf(
		float(data.get("river_amount", settings.river_amount)),
		RIVER_AMOUNT_MIN,
		RIVER_AMOUNT_MAX
	)
	return settings

static func _sanitize_band(value: int, world_bounds: WorldBoundsSettings) -> int:
	var max_band: int = mini(BAND_TILES_MAX, maxi(BAND_TILES_MIN, world_bounds.height_tiles / 3))
	return clampi(value, BAND_TILES_MIN, max_band)
