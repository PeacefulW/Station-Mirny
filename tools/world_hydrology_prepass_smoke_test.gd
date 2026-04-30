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

	var legacy_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_RIVER_VERSION,
		packed_settings
	)
	_assert(bool(legacy_result.get("success", false)), "legacy river-version hydrology prepass should build successfully")
	var legacy_snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	_assert(not _has_any_lake(legacy_snapshot), "world_version 17 should keep pre-R4 lake ids empty")

	var first_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	_assert(bool(first_result.get("success", false)), "hydrology prepass should build successfully")
	_assert(not bool(first_result.get("cache_hit", true)), "first hydrology build should not be a cache hit")
	_assert(WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_REFINED_RIVER_VERSION, "current hydrology should advance beyond the refined-river version for curvature-aware output")
	_assert(int(first_result.get("cell_size_tiles", 0)) == 16, "hydrology cell size should come from river settings")
	_assert(int(first_result.get("grid_width", 0)) > 0, "hydrology grid width should be positive")
	_assert(int(first_result.get("grid_height", 0)) > 0, "hydrology grid height should be positive")
	_assert(int(first_result.get("refined_river_edge_count", 0)) > int(first_result.get("river_segment_count", 0)), "current hydrology should build a refined whole-river centerline substrate")
	_assert(int(first_result.get("river_spatial_index_cell_count", 0)) > 0, "current hydrology should build a river spatial index for bounded chunk queries")
	_assert(int(first_result.get("curvature_refined_river_edge_count", 0)) > 0, "current hydrology should classify curved refined river edges")

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
	_assert((snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array).size() == node_count, "lake_id size should match grid")
	_assert(_has_any_lake(snapshot), "V1-R4 current hydrology snapshot should expose natural lake ids")
	_assert(_lake_nodes_avoid_mountain_and_ocean(snapshot), "lake nodes should not overlap mountain exclusion or ocean sink")
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
	_assert(int(snapshot.get("curvature_refined_river_edge_count", 0)) == int(first_result.get("curvature_refined_river_edge_count", -1)), "debug snapshot should report the same curved refined river edge count as the build result")

	var changed_settings: PackedFloat32Array = packed_settings.duplicate()
	changed_settings[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_DENSITY] = 0.15
	var changed_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		changed_settings
	)
	_assert(int(changed_result.get("signature", first_signature)) != first_signature, "river settings must participate in hydrology cache signature")
	_assert(int(changed_result.get("refined_river_edge_count", 0)) > 0, "changed river settings should still build refined centerline edges")

	var dense_settings: PackedFloat32Array = packed_settings.duplicate()
	dense_settings[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_DENSITY] = 1.0
	var dense_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		dense_settings
	)
	_assert(WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_CURVATURE_RIVER_VERSION, "current hydrology should advance beyond curvature-aware output for Y-shaped confluence zones")
	_assert(int(dense_result.get("confluence_refined_river_edge_count", 0)) > 0, "dense hydrology should classify widened post-confluence refined river edges")
	_assert(int(dense_result.get("y_confluence_zone_count", 0)) > 0, "dense hydrology should build native Y-shaped confluence zones")
	_assert(WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_Y_CONFLUENCE_RIVER_VERSION, "current hydrology should advance beyond Y-shaped confluence output for braid island loops")
	var braid_loop_candidates: int = int(dense_result.get("braid_loop_candidate_count", 0))
	var braid_loop_edges: int = int(dense_result.get("braid_loop_refined_river_edge_count", 0))
	_assert(braid_loop_candidates > 0, "dense hydrology should accept at least one native braid island loop candidate")
	_assert(braid_loop_edges >= braid_loop_candidates * 4, "native braid island loops should use multi-edge rejoin geometry instead of a simple parallel split")
	var dense_snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	_assert(int(dense_snapshot.get("confluence_refined_river_edge_count", 0)) == int(dense_result.get("confluence_refined_river_edge_count", -1)), "debug snapshot should report the same dense confluence refined river edge count as the build result")
	_assert(int(dense_snapshot.get("y_confluence_zone_count", 0)) == int(dense_result.get("y_confluence_zone_count", -1)), "debug snapshot should report the same dense Y-shaped confluence zone count as the build result")
	_assert(int(dense_snapshot.get("braid_loop_candidate_count", 0)) == braid_loop_candidates, "debug snapshot should report the same dense braid loop candidate count as the build result")
	_assert(int(dense_snapshot.get("braid_loop_refined_river_edge_count", 0)) == braid_loop_edges, "debug snapshot should report the same dense braid loop refined river edge count as the build result")
	_assert(WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_BRAID_LOOP_RIVER_VERSION, "current hydrology should advance beyond braid island loops for basin-contour lakes and oxbow prep")
	var basin_contour_nodes: int = int(dense_result.get("basin_contour_lake_node_count", 0))
	var lake_spill_points: int = int(dense_result.get("lake_spill_point_count", 0))
	var lake_outlet_connections: int = int(dense_result.get("lake_outlet_connection_count", 0))
	var oxbow_candidates: int = int(dense_result.get("oxbow_candidate_count", 0))
	_assert(basin_contour_nodes > 0, "dense hydrology should classify lake nodes with basin-contour depth data")
	_assert(lake_spill_points > 0, "dense hydrology should expose native lake spill point diagnostics")
	_assert(lake_outlet_connections > 0, "dense hydrology should keep at least one selected lake connected to an outlet")
	_assert(oxbow_candidates > 0, "dense hydrology should prepare rare oxbow candidates from high-curvature lowland meanders")
	_assert(int(dense_snapshot.get("basin_contour_lake_node_count", 0)) == basin_contour_nodes, "debug snapshot should report the same basin-contour lake node count as the build result")
	_assert(int(dense_snapshot.get("lake_spill_point_count", 0)) == lake_spill_points, "debug snapshot should report the same lake spill point count as the build result")
	_assert(int(dense_snapshot.get("lake_outlet_connection_count", 0)) == lake_outlet_connections, "debug snapshot should report the same lake outlet connection count as the build result")
	_assert(int(dense_snapshot.get("oxbow_candidate_count", 0)) == oxbow_candidates, "debug snapshot should report the same oxbow candidate count as the build result")
	_assert(WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_BASIN_CONTOUR_LAKE_VERSION, "current hydrology should advance beyond basin-contour lakes for organic coastline and shelf output")
	var coastline_nodes: int = int(dense_result.get("ocean_coastline_node_count", 0))
	var shallow_shelf_nodes: int = int(dense_result.get("ocean_shallow_shelf_node_count", 0))
	var river_mouth_nodes: int = int(dense_result.get("ocean_river_mouth_node_count", 0))
	_assert(coastline_nodes > 0, "dense hydrology should expose native organic coastline diagnostics")
	_assert(shallow_shelf_nodes > 0, "dense hydrology should classify a coherent shallow ocean shelf beyond the shore line")
	_assert(river_mouth_nodes > 0, "dense hydrology should detect river-mouth coastline influence nodes")
	_assert((dense_snapshot.get("ocean_coast_distance_tiles", PackedFloat32Array()) as PackedFloat32Array).size() == node_count, "ocean coast distance field should match grid size")
	_assert((dense_snapshot.get("ocean_shelf_depth_ratio", PackedFloat32Array()) as PackedFloat32Array).size() == node_count, "ocean shelf depth ratio should match grid size")
	_assert((dense_snapshot.get("ocean_river_mouth_influence", PackedFloat32Array()) as PackedFloat32Array).size() == node_count, "ocean river-mouth influence field should match grid size")
	_assert(_coastline_is_irregular_and_connected(dense_snapshot), "organic coastline should be irregular while staying connected to the top ocean boundary")
	_assert(_ocean_shelf_depth_is_coherent(dense_snapshot), "organic ocean shelf should include shallow shelf and deep ocean classes")
	_assert(int(dense_snapshot.get("ocean_coastline_node_count", 0)) == coastline_nodes, "debug snapshot should report the same coastline node count as the build result")
	_assert(int(dense_snapshot.get("ocean_shallow_shelf_node_count", 0)) == shallow_shelf_nodes, "debug snapshot should report the same shallow shelf node count as the build result")
	_assert(int(dense_snapshot.get("ocean_river_mouth_node_count", 0)) == river_mouth_nodes, "debug snapshot should report the same river-mouth coastline influence count as the build result")

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

func _coastline_is_irregular_and_connected(snapshot: Dictionary) -> bool:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	if width <= 0 or height <= 0 or mask.size() < width * height:
		return false
	var deepest_by_x: Array[int] = []
	deepest_by_x.resize(width)
	for x: int in range(width):
		deepest_by_x[x] = -1
	var ocean_count: int = 0
	var queue: Array[int] = []
	var visited: Dictionary = {}
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if mask[index] == 0:
				continue
			ocean_count += 1
			deepest_by_x[x] = maxi(deepest_by_x[x], y)
			if y == 0:
				queue.append(index)
				visited[index] = true
	var head: int = 0
	while head < queue.size():
		var index: int = queue[head]
		head += 1
		var x: int = index % width
		var y: int = index / width
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = posmod(x + offset.x, width)
			var ny: int = y + offset.y
			if ny < 0 or ny >= height:
				continue
			var next_index: int = ny * width + nx
			if mask[next_index] == 0 or visited.has(next_index):
				continue
			visited[next_index] = true
			queue.append(next_index)
	if ocean_count == 0 or visited.size() != ocean_count:
		return false
	var min_y: int = height
	var max_y: int = -1
	for x: int in range(width):
		if deepest_by_x[x] < 0:
			continue
		min_y = mini(min_y, deepest_by_x[x])
		max_y = maxi(max_y, deepest_by_x[x])
	return max_y - min_y >= 2

func _ocean_shelf_depth_is_coherent(snapshot: Dictionary) -> bool:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var shelf_ratio: PackedFloat32Array = snapshot.get("ocean_shelf_depth_ratio", PackedFloat32Array()) as PackedFloat32Array
	if width <= 0 or height <= 0 or mask.size() < width * height or shelf_ratio.size() < width * height:
		return false
	var has_shallow_shelf: bool = false
	var has_deep_ocean: bool = false
	for index: int in range(width * height):
		if mask[index] == 0:
			continue
		var ratio: float = float(shelf_ratio[index])
		if ratio > 0.02 and ratio < 0.72:
			has_shallow_shelf = true
		if ratio >= 0.92:
			has_deep_ocean = true
	return has_shallow_shelf and has_deep_ocean

func _has_any_lake(snapshot: Dictionary) -> bool:
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	for lake_id: int in lake_ids:
		if lake_id > 0:
			return true
	return false

func _lake_nodes_avoid_mountain_and_ocean(snapshot: Dictionary) -> bool:
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var exclusion_mask: PackedByteArray = snapshot.get("mountain_exclusion_mask", PackedByteArray()) as PackedByteArray
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var count: int = mini(lake_ids.size(), mini(exclusion_mask.size(), ocean_mask.size()))
	for index: int in range(count):
		if int(lake_ids[index]) <= 0:
			continue
		if exclusion_mask[index] != 0 or ocean_mask[index] != 0:
			return false
	return true

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
