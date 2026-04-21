class_name MountainGenSettings
extends Resource

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DENSITY_MIN: float = 0.0
const DENSITY_MAX: float = 1.0
const SCALE_MIN: float = 32.0
const SCALE_MAX: float = 2048.0
const CONTINUITY_MIN: float = 0.0
const CONTINUITY_MAX: float = 1.0
const RUGGEDNESS_MIN: float = 0.0
const RUGGEDNESS_MAX: float = 1.0
const ANCHOR_CELL_SIZE_MIN: int = 32
const ANCHOR_CELL_SIZE_MAX: int = 512
const GRAVITY_RADIUS_MIN: int = 32
const GRAVITY_RADIUS_MAX: int = 256
const FOOT_BAND_MIN: float = 0.02
const FOOT_BAND_MAX: float = 0.3
const INTERIOR_MARGIN_MIN: int = 0
const INTERIOR_MARGIN_MAX: int = 4
const LATITUDE_INFLUENCE_MIN: float = -1.0
const LATITUDE_INFLUENCE_MAX: float = 1.0

@export_range(0.0, 1.0, 0.01) var density: float = 0.30
@export_range(32.0, 2048.0) var scale: float = 512.0
@export_range(0.0, 1.0, 0.01) var continuity: float = 0.65
@export_range(0.0, 1.0, 0.01) var ruggedness: float = 0.55
@export_range(32, 512) var anchor_cell_size: int = 128
@export_range(32, 256) var gravity_radius: int = 96
@export_range(0.02, 0.3, 0.01) var foot_band: float = 0.08
@export_range(0, 4) var interior_margin: int = 1
@export_range(-1.0, 1.0, 0.05) var latitude_influence: float = 0.0

func flatten_to_packed() -> PackedFloat32Array:
	var settings_packed: PackedFloat32Array = PackedFloat32Array()
	settings_packed.resize(WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FIELD_COUNT)
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_DENSITY] = density
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_SCALE] = scale
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_CONTINUITY] = continuity
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RUGGEDNESS] = ruggedness
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE] = float(anchor_cell_size)
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS] = float(gravity_radius)
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FOOT_BAND] = foot_band
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN] = float(interior_margin)
	settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE] = latitude_influence
	return settings_packed

func to_save_dict() -> Dictionary:
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

static func from_save_dict(d: Dictionary) -> MountainGenSettings:
	var settings: MountainGenSettings = hard_coded_defaults()
	settings.density = clampf(_read_float(d, "density", settings.density), DENSITY_MIN, DENSITY_MAX)
	settings.scale = clampf(_read_float(d, "scale", settings.scale), SCALE_MIN, SCALE_MAX)
	settings.continuity = clampf(_read_float(d, "continuity", settings.continuity), CONTINUITY_MIN, CONTINUITY_MAX)
	settings.ruggedness = clampf(_read_float(d, "ruggedness", settings.ruggedness), RUGGEDNESS_MIN, RUGGEDNESS_MAX)
	settings.anchor_cell_size = clampi(
		_read_int(d, "anchor_cell_size", settings.anchor_cell_size),
		ANCHOR_CELL_SIZE_MIN,
		ANCHOR_CELL_SIZE_MAX
	)
	settings.gravity_radius = clampi(
		_read_int(d, "gravity_radius", settings.gravity_radius),
		GRAVITY_RADIUS_MIN,
		GRAVITY_RADIUS_MAX
	)
	settings.foot_band = clampf(_read_float(d, "foot_band", settings.foot_band), FOOT_BAND_MIN, FOOT_BAND_MAX)
	settings.interior_margin = clampi(
		_read_int(d, "interior_margin", settings.interior_margin),
		INTERIOR_MARGIN_MIN,
		INTERIOR_MARGIN_MAX
	)
	settings.latitude_influence = clampf(
		_read_float(d, "latitude_influence", settings.latitude_influence),
		LATITUDE_INFLUENCE_MIN,
		LATITUDE_INFLUENCE_MAX
	)
	return settings

static func hard_coded_defaults() -> MountainGenSettings:
	return new()

func compute_signature() -> String:
	var hashing_context: HashingContext = HashingContext.new()
	var start_error: Error = hashing_context.start(HashingContext.HASH_SHA1)
	if start_error != OK:
		return ""
	var payload: String = JSON.stringify(to_save_dict())
	hashing_context.update(payload.to_utf8_buffer())
	return hashing_context.finish().hex_encode()

static func _read_float(data: Dictionary, key: String, fallback: float) -> float:
	if not data.has(key):
		return fallback
	return float(data.get(key, fallback))

static func _read_int(data: Dictionary, key: String, fallback: int) -> int:
	if not data.has(key):
		return fallback
	return int(data.get(key, fallback))
