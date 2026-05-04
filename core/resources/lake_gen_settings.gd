class_name LakeGenSettings
extends Resource

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DENSITY_MIN: float = 0.0
const DENSITY_MAX: float = 1.0
const SCALE_MIN: float = 64.0
const SCALE_MAX: float = 2048.0
const SHORE_WARP_AMPLITUDE_MIN: float = 0.0
const SHORE_WARP_AMPLITUDE_MAX: float = 1.0
const SHORE_WARP_SCALE_MIN: float = 8.0
const SHORE_WARP_SCALE_MAX: float = 64.0
const DEEP_THRESHOLD_MIN: float = 0.05
const DEEP_THRESHOLD_MAX: float = 0.5
const MOUNTAIN_CLEARANCE_MIN: float = 0.0
const MOUNTAIN_CLEARANCE_MAX: float = 0.5
const CONNECTIVITY_MIN: float = 0.0
const CONNECTIVITY_MAX: float = 1.0

@export_range(0.0, 1.0, 0.01) var density: float = 0.35
@export_range(64.0, 2048.0) var scale: float = 512.0
@export_range(0.0, 1.0, 0.05) var shore_warp_amplitude: float = 0.4
@export_range(8.0, 64.0) var shore_warp_scale: float = 16.0
@export_range(0.05, 0.5, 0.01) var deep_threshold: float = 0.18
@export_range(0.0, 0.5, 0.01) var mountain_clearance: float = 0.10
@export_range(0.0, 1.0, 0.01) var connectivity: float = 0.4

func to_save_dict() -> Dictionary:
	return {
		"density": density,
		"scale": scale,
		"shore_warp_amplitude": shore_warp_amplitude,
		"shore_warp_scale": shore_warp_scale,
		"deep_threshold": deep_threshold,
		"mountain_clearance": mountain_clearance,
		"connectivity": connectivity,
	}

func write_to_settings_packed(settings_packed: PackedFloat32Array) -> PackedFloat32Array:
	var normalized_settings: LakeGenSettings = from_save_dict(to_save_dict())
	var packed: PackedFloat32Array = settings_packed.duplicate()
	packed.resize(WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FIELD_COUNT)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_DENSITY] = normalized_settings.density
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_SCALE] = normalized_settings.scale
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_AMPLITUDE] = normalized_settings.shore_warp_amplitude
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_SCALE] = normalized_settings.shore_warp_scale
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_DEEP_THRESHOLD] = normalized_settings.deep_threshold
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_MOUNTAIN_CLEARANCE] = normalized_settings.mountain_clearance
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY] = normalized_settings.connectivity
	return packed

static func from_save_dict(data: Dictionary) -> LakeGenSettings:
	var settings: LakeGenSettings = hard_coded_defaults()
	settings.density = clampf(_read_float(data, "density", settings.density), DENSITY_MIN, DENSITY_MAX)
	settings.scale = clampf(_read_float(data, "scale", settings.scale), SCALE_MIN, SCALE_MAX)
	settings.shore_warp_amplitude = clampf(
		_read_float(data, "shore_warp_amplitude", settings.shore_warp_amplitude),
		SHORE_WARP_AMPLITUDE_MIN,
		SHORE_WARP_AMPLITUDE_MAX
	)
	settings.shore_warp_scale = clampf(
		_read_float(data, "shore_warp_scale", settings.shore_warp_scale),
		SHORE_WARP_SCALE_MIN,
		SHORE_WARP_SCALE_MAX
	)
	settings.deep_threshold = clampf(
		_read_float(data, "deep_threshold", settings.deep_threshold),
		DEEP_THRESHOLD_MIN,
		DEEP_THRESHOLD_MAX
	)
	settings.mountain_clearance = clampf(
		_read_float(data, "mountain_clearance", settings.mountain_clearance),
		MOUNTAIN_CLEARANCE_MIN,
		MOUNTAIN_CLEARANCE_MAX
	)
	settings.connectivity = clampf(
		_read_float(data, "connectivity", settings.connectivity),
		CONNECTIVITY_MIN,
		CONNECTIVITY_MAX
	)
	return settings

static func hard_coded_defaults() -> LakeGenSettings:
	return new()

static func _read_float(data: Dictionary, key: String, fallback: float) -> float:
	if not data.has(key):
		return fallback
	return float(data.get(key, fallback))
