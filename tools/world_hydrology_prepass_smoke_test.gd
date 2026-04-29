extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failed: bool = false

func _init() -> void:
	var core := WorldCore.new()
	var packed_settings: PackedFloat32Array = _build_settings_packed()
	var first_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	_assert(bool(first_result.get("success", false)), "hydrology prepass should build successfully")
	_assert(not bool(first_result.get("cache_hit", true)), "first hydrology build should not be a cache hit")
	_assert(int(first_result.get("cell_size_tiles", 0)) == 16, "hydrology cell size should come from river settings")
	_assert(int(first_result.get("grid_width", 0)) > 0, "hydrology grid width should be positive")
	_assert(int(first_result.get("grid_height", 0)) > 0, "hydrology grid height should be positive")

	var first_signature: int = int(first_result.get("signature", 0))
	var second_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	_assert(bool(second_result.get("cache_hit", false)), "second matching hydrology build should reuse cache")
	_assert(int(second_result.get("signature", -1)) == first_signature, "matching hydrology settings should keep signature stable")

	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var node_count: int = int(snapshot.get("grid_width", 0)) * int(snapshot.get("grid_height", 0))
	_assert(node_count > 0, "hydrology snapshot should expose a non-empty grid")
	_assert((snapshot.get("hydro_elevation", PackedFloat32Array()) as PackedFloat32Array).size() == node_count, "hydro_elevation size should match grid")
	_assert((snapshot.get("filled_elevation", PackedFloat32Array()) as PackedFloat32Array).size() == node_count, "filled_elevation size should match grid")
	_assert((snapshot.get("flow_dir", PackedByteArray()) as PackedByteArray).size() == node_count, "flow_dir size should match grid")
	_assert((snapshot.get("flow_accumulation", PackedFloat32Array()) as PackedFloat32Array).size() == node_count, "flow_accumulation size should match grid")
	_assert((snapshot.get("watershed_id", PackedInt32Array()) as PackedInt32Array).size() == node_count, "watershed_id size should match grid")
	_assert((snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray).size() == node_count, "ocean sink mask size should match grid")
	_assert(_top_row_has_ocean_sink(snapshot), "top hydrology row should include ocean sink cells")
	_assert(int(snapshot.get("river_segment_count", 0)) > 0, "hydrology snapshot should expose selected river segments")
	_assert(int(snapshot.get("river_source_count", 0)) > 0, "hydrology snapshot should expose selected river sources")
	_assert((snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray).size() == node_count, "river node mask size should match grid")
	_assert((snapshot.get("river_segment_id", PackedInt32Array()) as PackedInt32Array).size() == node_count, "river segment id size should match grid")
	_assert((snapshot.get("river_stream_order", PackedByteArray()) as PackedByteArray).size() == node_count, "river stream order size should match grid")
	_assert((snapshot.get("river_discharge", PackedFloat32Array()) as PackedFloat32Array).size() == node_count, "river discharge size should match grid")
	_assert((snapshot.get("river_segment_ranges", PackedInt32Array()) as PackedInt32Array).size() == int(snapshot.get("river_segment_count", 0)) * 6, "river segment ranges should use six-int records")
	_assert((snapshot.get("river_path_node_indices", PackedInt32Array()) as PackedInt32Array).size() >= int(snapshot.get("river_segment_count", 0)) * 2, "river path index should contain at least two nodes per segment")
	_assert(_river_nodes_avoid_mountain_exclusion(snapshot), "selected river nodes should not overlap mountain exclusion")

	var changed_settings: PackedFloat32Array = packed_settings.duplicate()
	changed_settings[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_DENSITY] = 0.15
	var changed_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		changed_settings
	)
	_assert(int(changed_result.get("signature", first_signature)) != first_signature, "river settings must participate in hydrology cache signature")

	if _failed:
		quit(1)
		return
	print("world_hydrology_prepass_smoke_test: OK")
	quit(0)

func _build_settings_packed() -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _top_row_has_ocean_sink(snapshot: Dictionary) -> bool:
	var width: int = int(snapshot.get("grid_width", 0))
	var mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	for x: int in range(width):
		if x < mask.size() and mask[x] != 0:
			return true
	return false

func _river_nodes_avoid_mountain_exclusion(snapshot: Dictionary) -> bool:
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var exclusion_mask: PackedByteArray = snapshot.get("mountain_exclusion_mask", PackedByteArray()) as PackedByteArray
	var count: int = mini(river_mask.size(), exclusion_mask.size())
	for index: int in range(count):
		if river_mask[index] != 0 and exclusion_mask[index] != 0:
			return false
	return true

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
