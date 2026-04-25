class_name RiverGenSettings
extends Resource

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const SCALE_MIN: float = 0.25
const SCALE_MAX: float = 4.0

@export_range(0.25, 4.0, 0.01) var lake_density_scale: float = 1.0
@export_range(0.25, 4.0, 0.01) var lake_radius_scale: float = 1.0
@export_range(0.25, 4.0, 0.01) var mouth_width_scale: float = 1.0
@export_range(0.25, 4.0, 0.01) var bed_width_scale: float = 1.0

func to_save_dict() -> Dictionary:
	return {
		"lake_density_scale": lake_density_scale,
		"lake_radius_scale": lake_radius_scale,
		"mouth_width_scale": mouth_width_scale,
		"bed_width_scale": bed_width_scale,
	}

func write_to_settings_packed(settings_packed: PackedFloat32Array) -> PackedFloat32Array:
	var normalized_settings: RiverGenSettings = from_save_dict(to_save_dict())
	var packed: PackedFloat32Array = settings_packed.duplicate()
	packed.resize(WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FIELD_COUNT)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_DENSITY_SCALE] = normalized_settings.lake_density_scale
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_RADIUS_SCALE] = normalized_settings.lake_radius_scale
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_MOUTH_WIDTH_SCALE] = normalized_settings.mouth_width_scale
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_BED_WIDTH_SCALE] = normalized_settings.bed_width_scale
	return packed

static func from_save_dict(data: Dictionary) -> RiverGenSettings:
	var settings: RiverGenSettings = hard_coded_defaults()
	settings.lake_density_scale = clampf(
		float(data.get("lake_density_scale", settings.lake_density_scale)),
		SCALE_MIN,
		SCALE_MAX
	)
	settings.lake_radius_scale = clampf(
		float(data.get("lake_radius_scale", settings.lake_radius_scale)),
		SCALE_MIN,
		SCALE_MAX
	)
	settings.mouth_width_scale = clampf(
		float(data.get("mouth_width_scale", settings.mouth_width_scale)),
		SCALE_MIN,
		SCALE_MAX
	)
	settings.bed_width_scale = clampf(
		float(data.get("bed_width_scale", settings.bed_width_scale)),
		SCALE_MIN,
		SCALE_MAX
	)
	return settings

static func hard_coded_defaults() -> RiverGenSettings:
	return new()
