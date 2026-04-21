class_name MountainGenSettings
extends Resource

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

@export_group("Mountains")
@export_range(0.0, 1.0, 0.01) var density: float = 0.30
@export_range(32.0, 2048.0, 1.0) var scale: float = 512.0
@export_range(0.0, 1.0, 0.01) var continuity: float = 0.65
@export_range(0.0, 1.0, 0.01) var ruggedness: float = 0.55
@export_range(32, 512, 1) var anchor_cell_size: int = 128
@export_range(32, 256, 1) var gravity_radius: int = 96
@export_range(0.02, 0.3, 0.01) var foot_band: float = 0.08
@export_range(0, 4, 1) var interior_margin: int = 1
@export_range(-1.0, 1.0, 0.01) var latitude_influence: float = 0.0

func duplicate_settings() -> MountainGenSettings:
	var copy := MountainGenSettings.new()
	copy.density = density
	copy.scale = scale
	copy.continuity = continuity
	copy.ruggedness = ruggedness
	copy.anchor_cell_size = anchor_cell_size
	copy.gravity_radius = gravity_radius
	copy.foot_band = foot_band
	copy.interior_margin = interior_margin
	copy.latitude_influence = latitude_influence
	return copy

func to_packed_array() -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	packed.resize(WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FIELD_COUNT)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_DENSITY] = density
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SCALE] = scale
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_CONTINUITY] = continuity
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RUGGEDNESS] = ruggedness
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE] = float(anchor_cell_size)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS] = float(gravity_radius)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FOOT_BAND] = foot_band
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN] = float(interior_margin)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE] = latitude_influence
	return packed

func to_save_dictionary() -> Dictionary:
	return {
		"density": density,
		"scale": scale,
		"continuity": continuity,
		"ruggedness": ruggedness,
		"anchor_cell_size": anchor_cell_size,
		"gravity_radius": gravity_radius,
		"foot_band": foot_band,
		"interior_margin": interior_margin,
		"latitude_influence": latitude_influence,
	}

static func hard_coded_defaults() -> MountainGenSettings:
	return MountainGenSettings.new()

static func from_save_dictionary(
	data: Dictionary,
	fallback: MountainGenSettings = null
) -> MountainGenSettings:
	var settings: MountainGenSettings = fallback.duplicate_settings() if fallback != null else hard_coded_defaults()
	if data.is_empty():
		return settings
	settings.density = clampf(float(data.get("density", settings.density)), 0.0, 1.0)
	settings.scale = clampf(float(data.get("scale", settings.scale)), 32.0, 2048.0)
	settings.continuity = clampf(float(data.get("continuity", settings.continuity)), 0.0, 1.0)
	settings.ruggedness = clampf(float(data.get("ruggedness", settings.ruggedness)), 0.0, 1.0)
	settings.anchor_cell_size = clampi(int(data.get("anchor_cell_size", settings.anchor_cell_size)), 32, 512)
	settings.gravity_radius = clampi(int(data.get("gravity_radius", settings.gravity_radius)), 32, 256)
	settings.foot_band = clampf(float(data.get("foot_band", settings.foot_band)), 0.02, 0.3)
	settings.interior_margin = clampi(int(data.get("interior_margin", settings.interior_margin)), 0, 4)
	settings.latitude_influence = clampf(float(data.get("latitude_influence", settings.latitude_influence)), -1.0, 1.0)
	return settings
