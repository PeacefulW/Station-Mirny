class_name RiverGenSettings
extends Resource

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const TARGET_TRUNK_COUNT_MIN: int = 0
const TARGET_TRUNK_COUNT_MAX: int = 256
const DENSITY_MIN: float = 0.0
const DENSITY_MAX: float = 1.0
const WIDTH_SCALE_MIN: float = 0.25
const WIDTH_SCALE_MAX: float = 4.0
const LAKE_CHANCE_MIN: float = 0.0
const LAKE_CHANCE_MAX: float = 1.0
const MEANDER_STRENGTH_MIN: float = 0.0
const MEANDER_STRENGTH_MAX: float = 1.0
const BRAID_CHANCE_MIN: float = 0.0
const BRAID_CHANCE_MAX: float = 1.0
const SHALLOW_CROSSING_FREQUENCY_MIN: float = 0.0
const SHALLOW_CROSSING_FREQUENCY_MAX: float = 1.0
const MOUNTAIN_CLEARANCE_TILES_MIN: int = 1
const MOUNTAIN_CLEARANCE_TILES_MAX: int = 16
const DELTA_SCALE_MIN: float = 0.0
const DELTA_SCALE_MAX: float = 2.0
const NORTH_DRAINAGE_BIAS_MIN: float = 0.0
const NORTH_DRAINAGE_BIAS_MAX: float = 1.0
const HYDROLOGY_CELL_SIZE_TILES_MIN: int = 8
const HYDROLOGY_CELL_SIZE_TILES_MAX: int = 64

const PRESET_FULL_HYDROLOGY: StringName = &"full_hydrology"
const PRESET_LAKES_ONLY: StringName = &"lakes_only"
const PRESET_SPARSE_ARCTIC_RIVERS: StringName = &"sparse_arctic_rivers"
const PRESET_WET_RIVER_NETWORK: StringName = &"wet_river_network"
const PRESET_DELTA_HEAVY: StringName = &"delta_heavy"
const PRESET_CUSTOM: StringName = &"custom"
const DEFAULT_PRESET: StringName = PRESET_FULL_HYDROLOGY

@export var preset_id: StringName = DEFAULT_PRESET
@export var enabled: bool = true
@export_range(0, 256) var target_trunk_count: int = 0
@export_range(0.0, 1.0, 0.01) var density: float = 0.55
@export_range(0.25, 4.0, 0.05) var width_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var lake_chance: float = 0.22
@export_range(0.0, 1.0, 0.01) var meander_strength: float = 0.65
@export_range(0.0, 1.0, 0.01) var braid_chance: float = 0.18
@export_range(0.0, 1.0, 0.01) var shallow_crossing_frequency: float = 0.22
@export_range(1, 16) var mountain_clearance_tiles: int = 3
@export_range(0.0, 2.0, 0.05) var delta_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var north_drainage_bias: float = 0.75
@export_range(8, 64) var hydrology_cell_size_tiles: int = 16

func write_to_settings_packed(settings_packed: PackedFloat32Array) -> PackedFloat32Array:
	var packed: PackedFloat32Array = settings_packed.duplicate()
	packed.resize(WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FIELD_COUNT_WITH_RIVERS)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_ENABLED] = 1.0 if enabled else 0.0
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_TARGET_TRUNK_COUNT] = float(target_trunk_count)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_DENSITY] = density
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_WIDTH_SCALE] = width_scale
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_LAKE_CHANCE] = lake_chance
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_MEANDER_STRENGTH] = meander_strength
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_BRAID_CHANCE] = braid_chance
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_SHALLOW_CROSSING_FREQUENCY] = shallow_crossing_frequency
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_MOUNTAIN_CLEARANCE_TILES] = float(mountain_clearance_tiles)
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_DELTA_SCALE] = delta_scale
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_NORTH_DRAINAGE_BIAS] = north_drainage_bias
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_HYDROLOGY_CELL_SIZE_TILES] = float(hydrology_cell_size_tiles)
	return packed

func to_save_dict() -> Dictionary:
	return {
		"enabled": enabled,
		"target_trunk_count": target_trunk_count,
		"density": density,
		"width_scale": width_scale,
		"lake_chance": lake_chance,
		"meander_strength": meander_strength,
		"braid_chance": braid_chance,
		"shallow_crossing_frequency": shallow_crossing_frequency,
		"mountain_clearance_tiles": mountain_clearance_tiles,
		"delta_scale": delta_scale,
		"north_drainage_bias": north_drainage_bias,
		"hydrology_cell_size_tiles": hydrology_cell_size_tiles,
	}

static func preset_ids() -> Array[StringName]:
	return [
		PRESET_FULL_HYDROLOGY,
		PRESET_LAKES_ONLY,
		PRESET_SPARSE_ARCTIC_RIVERS,
		PRESET_WET_RIVER_NETWORK,
		PRESET_DELTA_HEAVY,
	]

static func preset_select_ids() -> Array[StringName]:
	var ids: Array[StringName] = preset_ids()
	ids.append(PRESET_CUSTOM)
	return ids

static func preset_label_key(preset: StringName) -> StringName:
	match preset:
		PRESET_LAKES_ONLY:
			return &"UI_WORLDGEN_WATER_PRESET_LAKES_ONLY"
		PRESET_SPARSE_ARCTIC_RIVERS:
			return &"UI_WORLDGEN_WATER_PRESET_SPARSE_ARCTIC_RIVERS"
		PRESET_WET_RIVER_NETWORK:
			return &"UI_WORLDGEN_WATER_PRESET_WET_RIVER_NETWORK"
		PRESET_DELTA_HEAVY:
			return &"UI_WORLDGEN_WATER_PRESET_DELTA_HEAVY"
		PRESET_CUSTOM:
			return &"UI_WORLDGEN_WATER_PRESET_CUSTOM"
		_:
			return &"UI_WORLDGEN_WATER_PRESET_FULL_HYDROLOGY"

static func for_preset(preset: StringName) -> RiverGenSettings:
	var settings: RiverGenSettings = new()
	settings.preset_id = preset
	match preset:
		PRESET_LAKES_ONLY:
			settings.density = 0.0
			settings.width_scale = 0.75
			settings.lake_chance = 1.0
			settings.meander_strength = 0.25
			settings.braid_chance = 0.0
			settings.shallow_crossing_frequency = 0.0
			settings.delta_scale = 0.0
		PRESET_SPARSE_ARCTIC_RIVERS:
			settings.density = 0.26
			settings.width_scale = 0.85
			settings.lake_chance = 0.18
			settings.meander_strength = 0.35
			settings.braid_chance = 0.04
			settings.shallow_crossing_frequency = 0.12
			settings.delta_scale = 0.45
			settings.north_drainage_bias = 0.85
		PRESET_WET_RIVER_NETWORK:
			settings.density = 0.88
			settings.width_scale = 1.35
			settings.lake_chance = 0.42
			settings.meander_strength = 0.85
			settings.braid_chance = 0.30
			settings.shallow_crossing_frequency = 0.35
			settings.delta_scale = 1.20
		PRESET_DELTA_HEAVY:
			settings.density = 0.66
			settings.width_scale = 1.20
			settings.lake_chance = 0.30
			settings.meander_strength = 0.75
			settings.braid_chance = 0.26
			settings.shallow_crossing_frequency = 0.24
			settings.delta_scale = 1.80
			settings.north_drainage_bias = 0.88
		PRESET_FULL_HYDROLOGY:
			pass
		_:
			settings.preset_id = PRESET_FULL_HYDROLOGY
	return settings

static func from_save_dict(data: Dictionary) -> RiverGenSettings:
	var settings: RiverGenSettings = hard_coded_defaults()
	settings.enabled = _read_bool(data, "enabled", settings.enabled)
	settings.target_trunk_count = clampi(
		_read_int(data, "target_trunk_count", settings.target_trunk_count),
		TARGET_TRUNK_COUNT_MIN,
		TARGET_TRUNK_COUNT_MAX
	)
	settings.density = clampf(_read_float(data, "density", settings.density), DENSITY_MIN, DENSITY_MAX)
	settings.width_scale = clampf(
		_read_float(data, "width_scale", settings.width_scale),
		WIDTH_SCALE_MIN,
		WIDTH_SCALE_MAX
	)
	settings.lake_chance = clampf(
		_read_float(data, "lake_chance", settings.lake_chance),
		LAKE_CHANCE_MIN,
		LAKE_CHANCE_MAX
	)
	settings.meander_strength = clampf(
		_read_float(data, "meander_strength", settings.meander_strength),
		MEANDER_STRENGTH_MIN,
		MEANDER_STRENGTH_MAX
	)
	settings.braid_chance = clampf(
		_read_float(data, "braid_chance", settings.braid_chance),
		BRAID_CHANCE_MIN,
		BRAID_CHANCE_MAX
	)
	settings.shallow_crossing_frequency = clampf(
		_read_float(data, "shallow_crossing_frequency", settings.shallow_crossing_frequency),
		SHALLOW_CROSSING_FREQUENCY_MIN,
		SHALLOW_CROSSING_FREQUENCY_MAX
	)
	settings.mountain_clearance_tiles = clampi(
		_read_int(data, "mountain_clearance_tiles", settings.mountain_clearance_tiles),
		MOUNTAIN_CLEARANCE_TILES_MIN,
		MOUNTAIN_CLEARANCE_TILES_MAX
	)
	settings.delta_scale = clampf(
		_read_float(data, "delta_scale", settings.delta_scale),
		DELTA_SCALE_MIN,
		DELTA_SCALE_MAX
	)
	settings.north_drainage_bias = clampf(
		_read_float(data, "north_drainage_bias", settings.north_drainage_bias),
		NORTH_DRAINAGE_BIAS_MIN,
		NORTH_DRAINAGE_BIAS_MAX
	)
	settings.hydrology_cell_size_tiles = clampi(
		_read_int(data, "hydrology_cell_size_tiles", settings.hydrology_cell_size_tiles),
		HYDROLOGY_CELL_SIZE_TILES_MIN,
		HYDROLOGY_CELL_SIZE_TILES_MAX
	)
	settings.preset_id = match_preset_id(settings)
	return settings

static func hard_coded_defaults() -> RiverGenSettings:
	return for_preset(DEFAULT_PRESET)

static func match_preset_id(settings: RiverGenSettings) -> StringName:
	if settings == null:
		return PRESET_FULL_HYDROLOGY
	var saved: Dictionary = settings.to_save_dict()
	for preset: StringName in preset_ids():
		var preset_settings: RiverGenSettings = for_preset(preset)
		if JSON.stringify(preset_settings.to_save_dict()) == JSON.stringify(saved):
			return preset
	return PRESET_CUSTOM

func compute_signature() -> String:
	var hashing_context: HashingContext = HashingContext.new()
	var start_error: Error = hashing_context.start(HashingContext.HASH_SHA1)
	if start_error != OK:
		return ""
	var payload: String = JSON.stringify(to_save_dict())
	hashing_context.update(payload.to_utf8_buffer())
	return hashing_context.finish().hex_encode()

static func _read_bool(data: Dictionary, key: String, fallback: bool) -> bool:
	if not data.has(key):
		return fallback
	return bool(data.get(key, fallback))

static func _read_float(data: Dictionary, key: String, fallback: float) -> float:
	if not data.has(key):
		return fallback
	return float(data.get(key, fallback))

static func _read_int(data: Dictionary, key: String, fallback: int) -> int:
	if not data.has(key):
		return fallback
	return int(data.get(key, fallback))
