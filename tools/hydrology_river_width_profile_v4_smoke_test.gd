extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const WIDTH_PROFILE_RECORD_SIZE: int = 6
const EDGE_METADATA_RECORD_SIZE: int = 4
const EDGE_FLAG_SOURCE: int = 1

var _failed: bool = false

func _init() -> void:
	_assert(
		WorldRuntimeConstants.WORLD_VERSION >= WorldRuntimeConstants.WORLD_RIVER_DISCHARGE_WIDTH_V4_VERSION,
		"current WORLD_VERSION should preserve the V4-3 river discharge width boundary"
	)
	_assert(
		WorldRuntimeConstants.WORLD_RIVER_DISCHARGE_WIDTH_V4_VERSION > WorldRuntimeConstants.WORLD_HYDROLOGY_CLEARANCE_V4_VERSION,
		"V4-3 must preserve V4-2 saves behind an older world_version boundary"
	)

	var settings_packed: PackedFloat32Array = _build_settings_packed()
	var core := WorldCore.new()
	var build_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	_assert(bool(build_result.get("success", false)), "hydrology prepass should build for V4-3 river width profiles")
	_assert(int(build_result.get("river_width_profile_edge_count", 0)) > 0, "build result should count profiled river edges")
	_assert(int(build_result.get("river_source_taper_edge_count", 0)) > 0, "build result should count source taper edges")
	_assert(int(build_result.get("river_terminal_expansion_edge_count", 0)) > 0, "build result should count terminal expansion edges")

	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var node_count: int = int(snapshot.get("grid_width", 0)) * int(snapshot.get("grid_height", 0))
	var discharge_normalized: PackedFloat32Array = snapshot.get("river_discharge_normalized", PackedFloat32Array()) as PackedFloat32Array
	_assert(discharge_normalized.size() == node_count, "snapshot should expose normalized node discharge for V4-3")
	_assert(_normalized_values_are_bounded(discharge_normalized), "normalized node discharge should stay within 0..1")
	_assert(int(snapshot.get("river_width_profile_edge_count", 0)) == int(build_result.get("river_width_profile_edge_count", -1)), "snapshot and build result should agree on profiled edge count")

	var edge_count: int = int(snapshot.get("refined_river_edge_count", 0))
	var width_profile: PackedFloat32Array = snapshot.get("refined_river_edge_width_profile", PackedFloat32Array()) as PackedFloat32Array
	var metadata: PackedInt32Array = snapshot.get("refined_river_edge_metadata", PackedInt32Array()) as PackedInt32Array
	_assert(width_profile.size() == edge_count * WIDTH_PROFILE_RECORD_SIZE, "snapshot should expose one V4-3 width profile record per refined river edge")
	_assert(metadata.size() == edge_count * EDGE_METADATA_RECORD_SIZE, "snapshot should expose one metadata record per refined river edge")
	_assert(_profile_values_are_bounded(width_profile), "width profile values should stay bounded")
	_assert(_has_source_taper(metadata, width_profile), "at least one source edge should taper smoothly downstream")
	_assert(_has_terminal_expansion(width_profile), "at least one terminal edge should expand toward the mouth")
	_assert(_has_ford_narrowing(width_profile), "at least one edge should expose a shallow ford narrowing modifier")

	var legacy_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_HYDROLOGY_CLEARANCE_V4_VERSION,
		settings_packed
	)
	_assert(bool(legacy_result.get("success", false)), "legacy V4-2 hydrology prepass should still build")
	_assert(int(legacy_result.get("world_version", 0)) == WorldRuntimeConstants.WORLD_HYDROLOGY_CLEARANCE_V4_VERSION, "legacy V4-2 build should preserve requested world_version")

	_finish()

func _build_settings_packed() -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	river_settings.shallow_crossing_frequency = maxf(0.18, river_settings.shallow_crossing_frequency)
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _normalized_values_are_bounded(values: PackedFloat32Array) -> bool:
	for value: float in values:
		if value < -0.0001 or value > 1.0001:
			return false
	return true

func _profile_values_are_bounded(values: PackedFloat32Array) -> bool:
	if values.size() % WIDTH_PROFILE_RECORD_SIZE != 0:
		return false
	for index: int in range(0, values.size(), WIDTH_PROFILE_RECORD_SIZE):
		var discharge_start: float = values[index + 0]
		var discharge_end: float = values[index + 1]
		var width_start: float = values[index + 2]
		var width_end: float = values[index + 3]
		var ford_start: float = values[index + 4]
		var ford_end: float = values[index + 5]
		if discharge_start < -0.0001 or discharge_start > 1.0001:
			return false
		if discharge_end < -0.0001 or discharge_end > 1.0001:
			return false
		if width_start < 0.2 or width_start > 4.0:
			return false
		if width_end < 0.2 or width_end > 4.0:
			return false
		if ford_start < -0.0001 or ford_start > 1.0001:
			return false
		if ford_end < -0.0001 or ford_end > 1.0001:
			return false
	return true

func _has_source_taper(metadata: PackedInt32Array, profile: PackedFloat32Array) -> bool:
	var edge_count: int = mini(metadata.size() / EDGE_METADATA_RECORD_SIZE, profile.size() / WIDTH_PROFILE_RECORD_SIZE)
	for edge_index: int in range(edge_count):
		var flags: int = metadata[edge_index * EDGE_METADATA_RECORD_SIZE + 3]
		if (flags & EDGE_FLAG_SOURCE) == 0:
			continue
		var profile_index: int = edge_index * WIDTH_PROFILE_RECORD_SIZE
		var width_start: float = profile[profile_index + 2]
		var width_end: float = profile[profile_index + 3]
		if width_start < width_end * 0.95:
			return true
	return false

func _has_terminal_expansion(profile: PackedFloat32Array) -> bool:
	for index: int in range(0, profile.size(), WIDTH_PROFILE_RECORD_SIZE):
		var width_start: float = profile[index + 2]
		var width_end: float = profile[index + 3]
		if width_end > width_start * 1.05:
			return true
	return false

func _has_ford_narrowing(profile: PackedFloat32Array) -> bool:
	for index: int in range(0, profile.size(), WIDTH_PROFILE_RECORD_SIZE):
		var ford_start: float = profile[index + 4]
		var ford_end: float = profile[index + 5]
		if maxf(ford_start, ford_end) > 0.05:
			return true
	return false

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("hydrology_river_width_profile_v4_smoke_test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
