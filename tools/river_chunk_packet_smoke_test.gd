extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HYDROLOGY_OCEAN_ID: int = 2000000

var _failed: bool = false

func _init() -> void:
	var core := WorldCore.new()
	var packed_settings: PackedFloat32Array = _build_settings_packed()
	var build_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	_assert(bool(build_result.get("success", false)), "hydrology prepass should build before river packet generation")
	var debug_snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	_assert(_debug_snapshot_exposes_v2_shape_fields(debug_snapshot), "debug hydrology snapshot should expose V2 shape review fields")
	_assert(_lake_spill_points_are_river_outlets(debug_snapshot), "lake spill points should be the actual non-terminal river outlets")
	_assert(_refined_centerlines_avoid_mountain_clearance(debug_snapshot), "refined river centerline samples should stay out of mountain exclusion cells")

	var river_chunk: Vector2i = _find_river_chunk(core, packed_settings)
	_assert(river_chunk != Vector2i(-99999, -99999), "hydrology snapshot should provide a river chunk candidate")

	var coords := PackedVector2Array()
	coords.append(Vector2(float(river_chunk.x), float(river_chunk.y)))
	var packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	_assert(packets.size() == 1, "river chunk generation should return one packet")
	var packet: Dictionary = packets[0] if not packets.is_empty() else {}
	_assert(int(packet.get("world_version", 0)) == WorldRuntimeConstants.WORLD_VERSION, "packet should carry current river-enabled world version")
	_assert((packet.get("hydrology_id_per_tile", PackedInt32Array()) as PackedInt32Array).size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "hydrology_id_per_tile should be emitted per tile")
	_assert((packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array).size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "hydrology_flags should be emitted per tile")
	_assert((packet.get("floodplain_strength", PackedByteArray()) as PackedByteArray).size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "floodplain_strength should be emitted per tile")
	_assert((packet.get("water_class", PackedByteArray()) as PackedByteArray).size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "water_class should be emitted per tile")
	_assert((packet.get("flow_dir_quantized", PackedByteArray()) as PackedByteArray).size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "flow_dir_quantized should be emitted per tile")
	_assert((packet.get("stream_order", PackedByteArray()) as PackedByteArray).size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "stream_order should be emitted per tile")
	_assert((packet.get("water_atlas_indices", PackedInt32Array()) as PackedInt32Array).size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "water_atlas_indices should be emitted per tile")
	_assert(_packet_has_riverbed(packet), "river candidate chunk should contain riverbed terrain")
	_assert(_riverbed_walkability_matches_water(packet), "riverbed walkability should follow shallow/deep water class")
	_assert(_riverbed_avoids_mountain(packet), "riverbed tiles should not overlap mountain wall or foot")
	_assert(_ground_has_edge_next_to_hydrology_surface(packet), "plains ground next to a riverbed or river bank should use a non-solid 47-tile edge variant")
	_assert(_packet_hydrology_matches_cold_repeat(packed_settings, river_chunk, packet), "river chunk hydrology output should be deterministic across cold WorldCore instances")

	var lake_chunk: Vector2i = _find_lake_edge_chunk(core, packed_settings)
	_assert(lake_chunk != Vector2i(-99999, -99999), "hydrology snapshot should provide a lake edge chunk candidate")
	var lake_coords := PackedVector2Array()
	lake_coords.append(Vector2(float(lake_chunk.x), float(lake_chunk.y)))
	var lake_packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		lake_coords,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	_assert(lake_packets.size() == 1, "lake chunk generation should return one packet")
	var lake_packet: Dictionary = lake_packets[0] if not lake_packets.is_empty() else {}
	_assert(_packet_has_lakebed(lake_packet), "lake candidate chunk should contain lakebed terrain")
	_assert(_lakebed_has_irregular_outline(lake_packet), "lakebed outline should not rasterize as a perfect hydrology-cell rectangle")
	_assert(_lakebed_walkability_matches_water(lake_packet), "lakebed walkability should follow shallow/deep water class")
	_assert(_lakebed_avoids_mountain(lake_packet), "lakebed tiles should not overlap mountain wall or foot")
	_assert(_ground_has_edge_next_to_hydrology_surface(lake_packet), "plains ground next to a lakebed or lake bank should use a non-solid 47-tile edge variant")
	_assert(WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_BRAID_LOOP_RIVER_VERSION, "current chunk output should advance beyond braid island loops for basin-contour lake rasterization")
	_assert(_lakebed_has_basin_depth_gradient(lake_packet), "basin-contour lake output should keep a shallow rim and deeper low basin in the same packet")

	var ocean_chunk: Vector2i = _find_ocean_edge_chunk(core, packed_settings)
	_assert(ocean_chunk != Vector2i(-99999, -99999), "hydrology snapshot should provide an ocean edge chunk candidate")
	var ocean_coords := PackedVector2Array()
	ocean_coords.append(Vector2(float(ocean_chunk.x), float(ocean_chunk.y)))
	var ocean_packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		ocean_coords,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	_assert(ocean_packets.size() == 1, "ocean edge chunk generation should return one packet")
	var ocean_packet: Dictionary = ocean_packets[0] if not ocean_packets.is_empty() else {}
	_assert(_packet_has_ocean_shore_band(ocean_packet), "ocean edge chunk should contain a walkable ocean shore band")
	_assert(_ground_has_edge_next_to_hydrology_surface(ocean_packet), "plains ground next to ocean shore should use a non-solid 47-tile edge variant")
	var ocean_floor_chunk: Vector2i = _find_ocean_floor_chunk(core, packed_settings)
	_assert(ocean_floor_chunk != Vector2i(-99999, -99999), "hydrology snapshot should provide an ocean floor chunk candidate")
	var ocean_floor_packet: Dictionary = _generate_single_packet(core, packed_settings, ocean_floor_chunk)
	_assert(_packet_has_deep_ocean_floor(ocean_floor_packet), "ocean chunks should contain deep ocean floor terrain")
	_assert(WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_BASIN_CONTOUR_LAKE_VERSION, "current chunk output should advance beyond basin-contour lakes for organic coastline and shelf rasterization")
	var ocean_shelf_chunk: Vector2i = _find_ocean_shelf_chunk(core, packed_settings)
	_assert(ocean_shelf_chunk != Vector2i(-99999, -99999), "hydrology snapshot should provide an ocean shelf gradient chunk candidate")
	var ocean_shelf_packet: Dictionary = _generate_single_packet(core, packed_settings, ocean_shelf_chunk)
	_assert(_packet_has_ocean_shelf_gradient(ocean_shelf_packet), "organic ocean chunks should include shore, shallow shelf, and deep ocean bands")
	_assert(_ocean_surface_avoids_mountain(ocean_shelf_packet), "ocean shore/shelf/deep water should not overlap mountain wall or foot")
	_assert(_packet_hydrology_matches_cold_repeat(packed_settings, ocean_shelf_chunk, ocean_shelf_packet), "ocean shelf chunk hydrology output should be deterministic across cold WorldCore instances")

	var v1_r5_settings: PackedFloat32Array = _build_v1_r5_settings_packed()
	var v1_r5_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		v1_r5_settings
	)
	_assert(bool(v1_r5_result.get("success", false)), "V1-R5 hydrology prepass should build with delta/split settings")
	_assert(WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_Y_CONFLUENCE_RIVER_VERSION, "current chunk output should advance beyond Y-shaped confluences for native braid island loops")
	var braid_loop_candidates: int = int(v1_r5_result.get("braid_loop_candidate_count", 0))
	var braid_loop_edges: int = int(v1_r5_result.get("braid_loop_refined_river_edge_count", 0))
	_assert(braid_loop_candidates > 0, "V1-R5 dense hydrology should accept at least one braid island loop candidate")
	_assert(braid_loop_edges >= braid_loop_candidates * 4, "braid island loops should rasterize from multi-edge rejoin geometry")
	_assert(int(v1_r5_result.get("oxbow_candidate_count", 0)) > 0, "dense hydrology should create at least one oxbow lake geometry")
	var dense_debug_snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	_assert(_oxbow_candidates_are_lake_geometry(dense_debug_snapshot), "oxbow candidates should be materialized into lakebed nodes")
	var confluence_chunk: Vector2i = _find_confluence_chunk(core, v1_r5_settings)
	_assert(confluence_chunk != Vector2i(-99999, -99999), "dense hydrology snapshot should provide a confluence candidate")
	var confluence_packet: Dictionary = _generate_single_packet(core, v1_r5_settings, confluence_chunk)
	_assert(_packet_has_confluence_riverbed(confluence_packet), "curvature-aware river output should mark a widened post-confluence riverbed in chunk packets")
	_assert(_dense_confluence_has_y_zone(core, v1_r5_settings), "Y-shaped confluence output should mark two upstream arms and the downstream reach near the join")

	var delta_chunk: Vector2i = _find_delta_chunk(core)
	_assert(delta_chunk != Vector2i(-99999, -99999), "hydrology snapshot should provide a delta/estuary river-mouth candidate")
	var delta_coords := PackedVector2Array()
	delta_coords.append(Vector2(float(delta_chunk.x), float(delta_chunk.y)))
	var delta_packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		delta_coords,
		WorldRuntimeConstants.WORLD_VERSION,
		v1_r5_settings
	)
	_assert(delta_packets.size() == 1, "delta chunk generation should return one packet")
	var delta_packet: Dictionary = delta_packets[0] if not delta_packets.is_empty() else {}
	_assert(_packet_has_delta_estuary(delta_packet), "delta candidate chunk should contain delta/estuary hydrology flags")
	_assert(_delta_estuary_avoids_mountain(delta_packet), "delta/estuary tiles should not overlap mountain wall or foot")

	var braid_chunk: Vector2i = _find_braid_chunk(core)
	_assert(braid_chunk != Vector2i(-99999, -99999), "hydrology snapshot should provide a braid/split candidate")
	var braid_coords := PackedVector2Array()
	braid_coords.append(Vector2(float(braid_chunk.x), float(braid_chunk.y)))
	var braid_packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		braid_coords,
		WorldRuntimeConstants.WORLD_VERSION,
		v1_r5_settings
	)
	_assert(braid_packets.size() == 1, "braid chunk generation should return one packet")
	var braid_packet: Dictionary = braid_packets[0] if not braid_packets.is_empty() else {}
	_assert(_packet_has_braid_split(braid_packet), "braid candidate chunk should contain controlled split hydrology flags")
	_assert(_braid_split_uses_valid_river_water(braid_packet), "braid split tiles should keep river water and a stable hydrology id")

	var legacy_delta_packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		delta_coords,
		WorldRuntimeConstants.WORLD_LAKE_VERSION,
		v1_r5_settings
	)
	_assert(legacy_delta_packets.size() == 1, "legacy V1-R4 delta chunk generation should return one packet")
	var legacy_delta_packet: Dictionary = legacy_delta_packets[0] if not legacy_delta_packets.is_empty() else {}
	_assert(not _packet_has_delta_estuary(legacy_delta_packet), "world_version 18 should not emit V1-R5 delta flags")
	_assert(not _packet_has_braid_split(legacy_delta_packet), "world_version 18 should not emit V1-R5 braid split flags")

	if _failed:
		quit(1)
		return
	print("river_chunk_packet_smoke_test: OK")
	quit(0)

func _build_settings_packed() -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _build_v1_r5_settings_packed() -> PackedFloat32Array:
	var packed: PackedFloat32Array = _build_settings_packed()
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_DENSITY] = 1.0
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_BRAID_CHANCE] = 1.0
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_DELTA_SCALE] = 2.0
	packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_MEANDER_STRENGTH] = 1.0
	return packed

func _debug_snapshot_exposes_v2_shape_fields(snapshot: Dictionary) -> bool:
	var node_count: int = int(snapshot.get("grid_width", 0)) * int(snapshot.get("grid_height", 0))
	var edge_count: int = int(snapshot.get("refined_river_edge_count", 0))
	var lake_depth: PackedFloat32Array = snapshot.get("lake_depth_ratio", PackedFloat32Array()) as PackedFloat32Array
	var spill_mask: PackedByteArray = snapshot.get("lake_spill_node_mask", PackedByteArray()) as PackedByteArray
	var oxbow_mask: PackedByteArray = snapshot.get("oxbow_lake_node_mask", PackedByteArray()) as PackedByteArray
	var edge_points: PackedFloat32Array = snapshot.get("refined_river_edge_points", PackedFloat32Array()) as PackedFloat32Array
	var edge_tangents: PackedFloat32Array = snapshot.get("refined_river_edge_tangents", PackedFloat32Array()) as PackedFloat32Array
	var edge_shape: PackedFloat32Array = snapshot.get("refined_river_edge_shape_metrics", PackedFloat32Array()) as PackedFloat32Array
	var edge_metadata: PackedInt32Array = snapshot.get("refined_river_edge_metadata", PackedInt32Array()) as PackedInt32Array
	return node_count > 0 \
			and edge_count > 0 \
			and lake_depth.size() == node_count \
			and spill_mask.size() == node_count \
			and oxbow_mask.size() == node_count \
			and edge_points.size() == edge_count * 4 \
			and edge_tangents.size() == edge_count * 4 \
			and edge_shape.size() == edge_count * 4 \
			and edge_metadata.size() == edge_count * 4

func _lake_spill_points_are_river_outlets(snapshot: Dictionary) -> bool:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var spill_mask: PackedByteArray = snapshot.get("lake_spill_node_mask", PackedByteArray()) as PackedByteArray
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var flow_dir: PackedByteArray = snapshot.get("flow_dir", PackedByteArray()) as PackedByteArray
	var spill_count: int = 0
	var connected_count: int = 0
	for index: int in range(spill_mask.size()):
		if spill_mask[index] == 0:
			continue
		spill_count += 1
		if index >= lake_ids.size() or int(lake_ids[index]) <= 0:
			return false
		if index >= river_mask.size() or river_mask[index] == 0:
			return false
		var downstream: int = _resolve_downstream_index(index, width, height, flow_dir)
		if downstream < 0 or downstream >= lake_ids.size():
			continue
		if int(lake_ids[downstream]) == int(lake_ids[index]):
			continue
		if downstream >= river_mask.size() or river_mask[downstream] == 0:
			return false
		connected_count += 1
	return spill_count > 0 and connected_count > 0

func _refined_centerlines_avoid_mountain_clearance(snapshot: Dictionary) -> bool:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var points: PackedFloat32Array = snapshot.get("refined_river_edge_points", PackedFloat32Array()) as PackedFloat32Array
	var mountain_mask: PackedByteArray = snapshot.get("mountain_exclusion_mask", PackedByteArray()) as PackedByteArray
	if width <= 0 or height <= 0 or cell_size_tiles <= 0 or points.size() == 0:
		return false
	for offset: int in range(0, points.size(), 4):
		var ax: float = points[offset]
		var ay: float = points[offset + 1]
		var bx: float = points[offset + 2]
		var by: float = points[offset + 3]
		for step: int in range(5):
			var t: float = float(step) / 4.0
			var x: float = lerpf(ax, bx, t)
			var y: float = lerpf(ay, by, t)
			var node_x: int = posmod(int(floor(x / float(cell_size_tiles))), width)
			var node_y: int = clampi(int(floor(y / float(cell_size_tiles))), 0, height - 1)
			var node_index: int = node_y * width + node_x
			if node_index >= 0 and node_index < mountain_mask.size() and mountain_mask[node_index] != 0:
				return false
	return true

func _oxbow_candidates_are_lake_geometry(snapshot: Dictionary) -> bool:
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var oxbow_mask: PackedByteArray = snapshot.get("oxbow_lake_node_mask", PackedByteArray()) as PackedByteArray
	var oxbow_nodes: int = 0
	for index: int in range(oxbow_mask.size()):
		if oxbow_mask[index] == 0:
			continue
		oxbow_nodes += 1
		if index >= lake_ids.size() or int(lake_ids[index]) <= 0:
			return false
	return oxbow_nodes > 0

func _find_river_chunk(core: WorldCore, packed_settings: PackedFloat32Array) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var seen_chunks: Dictionary = {}
	for y: int in range(height - 1, -1, -1):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= river_mask.size() or river_mask[index] == 0:
				continue
			if index < ocean_mask.size() and ocean_mask[index] != 0:
				continue
			if index < lake_ids.size() and int(lake_ids[index]) > 0:
				continue
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			var chunk := Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
			var chunk_key: String = "%d,%d" % [chunk.x, chunk.y]
			if seen_chunks.has(chunk_key):
				continue
			seen_chunks[chunk_key] = true
			var packet: Dictionary = _generate_single_packet(core, packed_settings, chunk)
			if _packet_has_riverbed(packet) \
					and _riverbed_walkability_matches_water(packet) \
					and _riverbed_avoids_mountain(packet) \
					and _ground_has_edge_next_to_hydrology_surface(packet):
				return chunk
	return Vector2i(-99999, -99999)

func _find_delta_chunk(core: WorldCore) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var flow_dir: PackedByteArray = snapshot.get("flow_dir", PackedByteArray()) as PackedByteArray
	var best_tile := Vector2i(-99999, -99999)
	var best_order: int = -1
	var stream_order: PackedByteArray = snapshot.get("river_stream_order", PackedByteArray()) as PackedByteArray
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= river_mask.size() or river_mask[index] == 0:
				continue
			if index < ocean_mask.size() and ocean_mask[index] != 0:
				continue
			var downstream: int = _resolve_downstream_index(index, width, height, flow_dir)
			if downstream < 0 or downstream >= ocean_mask.size() or ocean_mask[downstream] == 0:
				continue
			var order: int = int(stream_order[index]) if index < stream_order.size() else 0
			if order <= best_order:
				continue
			best_order = order
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			best_tile = Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
	return best_tile

func _find_braid_chunk(core: WorldCore) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var edge_points: PackedFloat32Array = snapshot.get("refined_river_edge_points", PackedFloat32Array()) as PackedFloat32Array
	var edge_metadata: PackedInt32Array = snapshot.get("refined_river_edge_metadata", PackedInt32Array()) as PackedInt32Array
	var edge_count: int = mini(edge_points.size() / 4, edge_metadata.size() / 4)
	for edge_index: int in range(edge_count):
		var edge_flags: int = int(edge_metadata[edge_index * 4 + 3])
		if (edge_flags & 4) == 0:
			continue
		var ax: float = edge_points[edge_index * 4]
		var ay: float = edge_points[edge_index * 4 + 1]
		var bx: float = edge_points[edge_index * 4 + 2]
		var by: float = edge_points[edge_index * 4 + 3]
		var mid := Vector2((ax + bx) * 0.5, (ay + by) * 0.5)
		return Vector2i(floori(mid.x / float(WorldRuntimeConstants.CHUNK_SIZE)), floori(mid.y / float(WorldRuntimeConstants.CHUNK_SIZE)))
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var flow_dir: PackedByteArray = snapshot.get("flow_dir", PackedByteArray()) as PackedByteArray
	var stream_order: PackedByteArray = snapshot.get("river_stream_order", PackedByteArray()) as PackedByteArray
	for y: int in range(height - 2, 0, -1):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= river_mask.size() or river_mask[index] == 0:
				continue
			if index < ocean_mask.size() and ocean_mask[index] != 0:
				continue
			if index < lake_ids.size() and int(lake_ids[index]) > 0:
				continue
			if index >= stream_order.size() or int(stream_order[index]) < 3:
				continue
			var downstream: int = _resolve_downstream_index(index, width, height, flow_dir)
			if downstream < 0 or downstream >= river_mask.size() or river_mask[downstream] == 0:
				continue
			if downstream < ocean_mask.size() and ocean_mask[downstream] != 0:
				continue
			if downstream < lake_ids.size() and int(lake_ids[downstream]) > 0:
				continue
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			return Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
	return Vector2i(-99999, -99999)

func _find_confluence_chunk(core: WorldCore, packed_settings: PackedFloat32Array) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var flow_dir: PackedByteArray = snapshot.get("flow_dir", PackedByteArray()) as PackedByteArray
	var seen_chunks: Dictionary = {}
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= river_mask.size() or river_mask[index] == 0:
				continue
			if index < ocean_mask.size() and ocean_mask[index] != 0:
				continue
			if index < lake_ids.size() and int(lake_ids[index]) > 0:
				continue
			if _upstream_river_count(index, width, height, river_mask, flow_dir) < 2:
				continue
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			var base_chunk := Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
			for offset: Vector2i in [
				Vector2i(0, 0),
				Vector2i(0, 1),
				Vector2i(0, -1),
				Vector2i(1, 0),
				Vector2i(-1, 0),
			]:
				var chunk: Vector2i = base_chunk + offset
				var chunk_key: String = "%d,%d" % [chunk.x, chunk.y]
				if seen_chunks.has(chunk_key):
					continue
				seen_chunks[chunk_key] = true
				var packet: Dictionary = _generate_single_packet(core, packed_settings, chunk)
				if _packet_has_confluence_riverbed(packet):
					return chunk
	return Vector2i(-99999, -99999)

func _dense_confluence_has_y_zone(core: WorldCore, packed_settings: PackedFloat32Array) -> bool:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var flow_dir: PackedByteArray = snapshot.get("flow_dir", PackedByteArray()) as PackedByteArray
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= river_mask.size() or river_mask[index] == 0:
				continue
			if index < ocean_mask.size() and ocean_mask[index] != 0:
				continue
			if index < lake_ids.size() and int(lake_ids[index]) > 0:
				continue
			var upstreams: Array[int] = _upstream_river_indices(index, width, height, river_mask, flow_dir)
			if upstreams.size() < 2:
				continue
			var downstream: int = _resolve_downstream_index(index, width, height, flow_dir)
			if downstream < 0 or downstream >= river_mask.size() or river_mask[downstream] == 0:
				continue
			if not _confluence_probe_has_flag(core, packed_settings, _branch_probe_tile(index, downstream, width, cell_size_tiles, 0.38)):
				continue
			var matched_upstreams: int = 0
			for upstream: int in upstreams:
				if _confluence_probe_has_flag(core, packed_settings, _branch_probe_tile(index, upstream, width, cell_size_tiles, 0.38)):
					matched_upstreams += 1
			if matched_upstreams >= 2:
				return true
	return false

func _upstream_river_indices(index: int, width: int, height: int, river_mask: PackedByteArray, flow_dir: PackedByteArray) -> Array[int]:
	var indices: Array[int] = []
	var x: int = index % width
	var y: int = index / width
	for offset: Vector2i in [
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(0, 1),
		Vector2i(-1, 1),
		Vector2i(-1, 0),
		Vector2i(-1, -1),
	]:
		var nx: int = posmod(x + offset.x, width)
		var ny: int = y + offset.y
		if ny < 0 or ny >= height:
			continue
		var upstream_index: int = ny * width + nx
		if upstream_index < 0 or upstream_index >= river_mask.size() or river_mask[upstream_index] == 0:
			continue
		if _resolve_downstream_index(upstream_index, width, height, flow_dir) == index:
			indices.append(upstream_index)
	return indices

func _branch_probe_tile(confluence_index: int, branch_index: int, width: int, cell_size_tiles: int, branch_t: float) -> Vector2i:
	var confluence_node := Vector2i(confluence_index % width, confluence_index / width)
	var branch_node := Vector2i(branch_index % width, branch_index / width)
	var confluence_tile := Vector2(
		float(confluence_node.x * cell_size_tiles + cell_size_tiles / 2),
		float(confluence_node.y * cell_size_tiles + cell_size_tiles / 2)
	)
	var branch_tile := Vector2(
		float(branch_node.x * cell_size_tiles + cell_size_tiles / 2),
		float(branch_node.y * cell_size_tiles + cell_size_tiles / 2)
	)
	var probe: Vector2 = confluence_tile.lerp(branch_tile, branch_t)
	return Vector2i(int(round(probe.x)), int(round(probe.y)))

func _confluence_probe_has_flag(core: WorldCore, packed_settings: PackedFloat32Array, tile: Vector2i) -> bool:
	var chunk := Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
	var packet: Dictionary = _generate_single_packet(core, packed_settings, chunk)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var hydrology_ids: PackedInt32Array = packet.get("hydrology_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if terrain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or hydrology_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or hydrology_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return false
	var local := WorldRuntimeConstants.tile_to_local(tile)
	for y_offset: int in range(-5, 6):
		for x_offset: int in range(-5, 6):
			var lx: int = local.x + x_offset
			var ly: int = local.y + y_offset
			if lx < 0 or lx >= WorldRuntimeConstants.CHUNK_SIZE or ly < 0 or ly >= WorldRuntimeConstants.CHUNK_SIZE:
				continue
			var packet_index: int = WorldRuntimeConstants.local_to_index(Vector2i(lx, ly))
			if (int(hydrology_flags[packet_index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_CONFLUENCE) == 0:
				continue
			var terrain_id: int = int(terrain_ids[packet_index])
			if terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW \
					and terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP \
					and terrain_id != WorldRuntimeConstants.TERRAIN_SHORE:
				continue
			if int(hydrology_ids[packet_index]) <= 0:
				continue
			if packet_index < mountain_flags.size() \
					and (int(mountain_flags[packet_index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
				continue
			return true
	return false

func _resolve_downstream_index(index: int, width: int, height: int, flow_dir: PackedByteArray) -> int:
	if index < 0 or index >= flow_dir.size():
		return -1
	var direction: int = int(flow_dir[index])
	if direction < 0 or direction >= 8:
		return -1
	var dx: Array[int] = [0, 1, 1, 1, 0, -1, -1, -1]
	var dy: Array[int] = [-1, -1, 0, 1, 1, 1, 0, -1]
	var x: int = index % width
	var y: int = index / width
	var nx: int = posmod(x + dx[direction], width)
	var ny: int = y + dy[direction]
	if ny < 0 or ny >= height:
		return -1
	return ny * width + nx

func _upstream_river_count(index: int, width: int, height: int, river_mask: PackedByteArray, flow_dir: PackedByteArray) -> int:
	var count: int = 0
	var x: int = index % width
	var y: int = index / width
	for offset: Vector2i in [
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(0, 1),
		Vector2i(-1, 1),
		Vector2i(-1, 0),
		Vector2i(-1, -1),
	]:
		var nx: int = posmod(x + offset.x, width)
		var ny: int = y + offset.y
		if ny < 0 or ny >= height:
			continue
		var upstream_index: int = ny * width + nx
		if upstream_index < 0 or upstream_index >= river_mask.size() or river_mask[upstream_index] == 0:
			continue
		if _resolve_downstream_index(upstream_index, width, height, flow_dir) == index:
			count += 1
	return count

func _find_lake_edge_chunk(core: WorldCore, packed_settings: PackedFloat32Array) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var seen_chunks: Dictionary = {}
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= lake_ids.size() or int(lake_ids[index]) <= 0:
				continue
			var lake_id: int = int(lake_ids[index])
			var has_open_edge: bool = \
				_sample_lake_id(lake_ids, width, height, x, y - 1) != lake_id \
				or _sample_lake_id(lake_ids, width, height, x + 1, y) != lake_id \
				or _sample_lake_id(lake_ids, width, height, x, y + 1) != lake_id \
				or _sample_lake_id(lake_ids, width, height, x - 1, y) != lake_id
			if not has_open_edge:
				continue
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			var chunk := Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
			var chunk_key: String = "%d,%d" % [chunk.x, chunk.y]
			if seen_chunks.has(chunk_key):
				continue
			seen_chunks[chunk_key] = true
			var packet: Dictionary = _generate_single_packet(core, packed_settings, chunk)
			if _packet_has_lakebed(packet) \
					and _lakebed_has_irregular_outline(packet) \
					and _lakebed_walkability_matches_water(packet) \
					and _lakebed_avoids_mountain(packet) \
					and (WorldRuntimeConstants.WORLD_VERSION <= WorldRuntimeConstants.WORLD_BRAID_LOOP_RIVER_VERSION or _lakebed_has_basin_depth_gradient(packet)) \
					and _ground_has_edge_next_to_hydrology_surface(packet):
				return chunk
	return Vector2i(-99999, -99999)

func _find_ocean_edge_chunk(core: WorldCore, packed_settings: PackedFloat32Array) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var seen_chunks: Dictionary = {}
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= ocean_mask.size() or ocean_mask[index] == 0:
				continue
			var has_open_edge: bool = \
				(y > 0 and _sample_ocean_mask(ocean_mask, width, height, x, y - 1) == 0) \
				or _sample_ocean_mask(ocean_mask, width, height, x + 1, y) == 0 \
				or (y < height - 1 and _sample_ocean_mask(ocean_mask, width, height, x, y + 1) == 0) \
				or _sample_ocean_mask(ocean_mask, width, height, x - 1, y) == 0
			if not has_open_edge:
				continue
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			var base_chunk := Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
			for offset: Vector2i in [
				Vector2i(0, 0),
				Vector2i(0, 1),
				Vector2i(0, -1),
				Vector2i(1, 0),
				Vector2i(-1, 0),
			]:
				var chunk := base_chunk + offset
				var chunk_key: String = "%d,%d" % [chunk.x, chunk.y]
				if seen_chunks.has(chunk_key):
					continue
				seen_chunks[chunk_key] = true
				var packet: Dictionary = _generate_single_packet(core, packed_settings, chunk)
				if _packet_has_ocean_shore_band(packet) \
						and _ground_has_edge_next_to_hydrology_surface(packet):
					return chunk
	return Vector2i(-99999, -99999)

func _find_ocean_floor_chunk(core: WorldCore, packed_settings: PackedFloat32Array) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var seen_chunks: Dictionary = {}
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= ocean_mask.size() or ocean_mask[index] == 0:
				continue
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			var chunk := Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
			var chunk_key: String = "%d,%d" % [chunk.x, chunk.y]
			if seen_chunks.has(chunk_key):
				continue
			seen_chunks[chunk_key] = true
			var packet: Dictionary = _generate_single_packet(core, packed_settings, chunk)
			if _packet_has_deep_ocean_floor(packet):
				return chunk
	return Vector2i(-99999, -99999)

func _find_ocean_shelf_chunk(core: WorldCore, packed_settings: PackedFloat32Array) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var seen_chunks: Dictionary = {}
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= ocean_mask.size() or ocean_mask[index] == 0:
				continue
			var has_open_edge: bool = \
				(y > 0 and _sample_ocean_mask(ocean_mask, width, height, x, y - 1) == 0) \
				or _sample_ocean_mask(ocean_mask, width, height, x + 1, y) == 0 \
				or (y < height - 1 and _sample_ocean_mask(ocean_mask, width, height, x, y + 1) == 0) \
				or _sample_ocean_mask(ocean_mask, width, height, x - 1, y) == 0
			if not has_open_edge:
				continue
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			var base_chunk := Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
			for offset: Vector2i in [
				Vector2i(0, 0),
				Vector2i(0, -1),
				Vector2i(0, -2),
				Vector2i(0, 1),
				Vector2i(1, 0),
				Vector2i(-1, 0),
			]:
				var chunk := base_chunk + offset
				var chunk_key: String = "%d,%d" % [chunk.x, chunk.y]
				if seen_chunks.has(chunk_key):
					continue
				seen_chunks[chunk_key] = true
				var packet: Dictionary = _generate_single_packet(core, packed_settings, chunk)
				if _packet_has_ocean_shelf_gradient(packet) and _ocean_surface_avoids_mountain(packet):
					return chunk
	return Vector2i(-99999, -99999)

func _generate_single_packet(core: WorldCore, packed_settings: PackedFloat32Array, chunk: Vector2i) -> Dictionary:
	var coords := PackedVector2Array()
	coords.append(Vector2(float(chunk.x), float(chunk.y)))
	var packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	return packets[0] if packets.size() == 1 else {}

func _packet_hydrology_matches_cold_repeat(packed_settings: PackedFloat32Array, chunk: Vector2i, expected_packet: Dictionary) -> bool:
	var repeat_core := WorldCore.new()
	var repeat_packet: Dictionary = _generate_single_packet(repeat_core, packed_settings, chunk)
	for key: String in [
		"terrain_ids",
		"walkable_flags",
		"hydrology_id_per_tile",
		"hydrology_flags",
		"floodplain_strength",
		"water_class",
		"flow_dir_quantized",
		"stream_order",
		"water_atlas_indices",
	]:
		if not _packet_array_equal(expected_packet.get(key), repeat_packet.get(key)):
			return false
	return true

func _packet_array_equal(left, right) -> bool:
	if left == null or right == null:
		return left == right
	if typeof(left) != typeof(right):
		return false
	if not typeof(left) in [
		TYPE_ARRAY,
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
	]:
		return left == right
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if left[index] != right[index]:
			return false
	return true

func _sample_ocean_mask(ocean_mask: PackedByteArray, width: int, height: int, x: int, y: int) -> int:
	if width <= 0 or height <= 0 or y < 0 or y >= height:
		return 0
	var wrapped_x: int = posmod(x, width)
	var index: int = y * width + wrapped_x
	return int(ocean_mask[index]) if index >= 0 and index < ocean_mask.size() else 0

func _sample_lake_id(lake_ids: PackedInt32Array, width: int, height: int, x: int, y: int) -> int:
	if width <= 0 or height <= 0 or y < 0 or y >= height:
		return 0
	var wrapped_x: int = posmod(x, width)
	var index: int = y * width + wrapped_x
	return int(lake_ids[index]) if index >= 0 and index < lake_ids.size() else 0

func _packet_has_riverbed(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var stream_order: PackedByteArray = packet.get("stream_order", PackedByteArray()) as PackedByteArray
	var count: int = mini(mini(terrain_ids.size(), hydrology_flags.size()), mini(water_class.size(), stream_order.size()))
	for index: int in range(count):
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW and terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP:
			continue
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_RIVERBED) == 0:
			return false
		if int(water_class[index]) == WorldRuntimeConstants.WATER_CLASS_NONE:
			return false
		if int(stream_order[index]) <= 0:
			return false
		return true
	return false

func _packet_has_confluence_riverbed(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var hydrology_ids: PackedInt32Array = packet.get("hydrology_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(mini(terrain_ids.size(), hydrology_ids.size()), mini(hydrology_flags.size(), mini(water_class.size(), mountain_flags.size())))
	for index: int in range(count):
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_CONFLUENCE) == 0:
			continue
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW \
				and terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP:
			return false
		if int(hydrology_ids[index]) <= 0:
			return false
		if int(water_class[index]) == WorldRuntimeConstants.WATER_CLASS_NONE:
			return false
		if (int(mountain_flags[index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
			return false
		return true
	return false

func _riverbed_walkability_matches_water(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(mini(terrain_ids.size(), water_class.size()), walkable_flags.size())
	for index: int in range(count):
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW and terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP:
			continue
		var current_water: int = int(water_class[index])
		var is_walkable: bool = walkable_flags[index] != 0
		if current_water == WorldRuntimeConstants.WATER_CLASS_SHALLOW and not is_walkable:
			return false
		if current_water == WorldRuntimeConstants.WATER_CLASS_DEEP and is_walkable:
			return false
	return true

func _riverbed_avoids_mountain(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(terrain_ids.size(), mountain_flags.size())
	for index: int in range(count):
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW and terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP:
			continue
		if (int(mountain_flags[index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
			return false
	return true

func _ground_has_edge_next_to_hydrology_surface(packet: Dictionary) -> bool:
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var terrain_atlas_indices: PackedInt32Array = packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array
	var count: int = mini(terrain_ids.size(), terrain_atlas_indices.size())
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			var index: int = y * WorldRuntimeConstants.CHUNK_SIZE + x
			if index < 0 or index >= count:
				continue
			if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
				continue
			if not _has_adjacent_hydrology_surface(terrain_ids, x, y):
				continue
			var world_tile := Vector2i(
				chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE + x,
				chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE + y
			)
			var solid_index: int = Autotile47.build_solid_atlas_index(
				world_tile,
				WorldRuntimeConstants.DEFAULT_WORLD_SEED
			)
			if int(terrain_atlas_indices[index]) != solid_index:
				return true
	return false

func _has_adjacent_hydrology_surface(terrain_ids: PackedInt32Array, x: int, y: int) -> bool:
	for offset: Vector2i in [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]:
		var adjacent := Vector2i(x + offset.x, y + offset.y)
		if adjacent.x < 0 \
				or adjacent.y < 0 \
				or adjacent.x >= WorldRuntimeConstants.CHUNK_SIZE \
				or adjacent.y >= WorldRuntimeConstants.CHUNK_SIZE:
			continue
		var adjacent_index: int = adjacent.y * WorldRuntimeConstants.CHUNK_SIZE + adjacent.x
		if adjacent_index < 0 or adjacent_index >= terrain_ids.size():
			continue
		var adjacent_terrain: int = int(terrain_ids[adjacent_index])
		if adjacent_terrain == WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW \
				or adjacent_terrain == WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP \
				or adjacent_terrain == WorldRuntimeConstants.TERRAIN_LAKEBED \
				or adjacent_terrain == WorldRuntimeConstants.TERRAIN_OCEAN_FLOOR \
				or adjacent_terrain == WorldRuntimeConstants.TERRAIN_SHORE:
			return true
	return false

func _packet_has_lakebed(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var count: int = mini(mini(terrain_ids.size(), hydrology_flags.size()), water_class.size())
	for index: int in range(count):
		if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_LAKEBED:
			continue
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_LAKEBED) == 0:
			return false
		if int(water_class[index]) == WorldRuntimeConstants.WATER_CLASS_NONE:
			return false
		return true
	return false

func _packet_has_deep_ocean_floor(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var count: int = mini(terrain_ids.size(), water_class.size())
	for index: int in range(count):
		if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_OCEAN_FLOOR:
			continue
		if int(water_class[index]) == WorldRuntimeConstants.WATER_CLASS_OCEAN:
			return true
	return false

func _packet_has_ocean_shelf_gradient(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(terrain_ids.size(), mini(water_class.size(), walkable_flags.size()))
	var has_shore: bool = false
	var has_shallow_shelf: bool = false
	var has_deep_ocean: bool = false
	for index: int in range(count):
		var terrain_id: int = int(terrain_ids[index])
		var current_water: int = int(water_class[index])
		var is_walkable: bool = walkable_flags[index] != 0
		if terrain_id == WorldRuntimeConstants.TERRAIN_SHORE and current_water == WorldRuntimeConstants.WATER_CLASS_NONE and is_walkable:
			has_shore = true
		elif terrain_id == WorldRuntimeConstants.TERRAIN_OCEAN_FLOOR and current_water == WorldRuntimeConstants.WATER_CLASS_SHALLOW and is_walkable:
			has_shallow_shelf = true
		elif terrain_id == WorldRuntimeConstants.TERRAIN_OCEAN_FLOOR and current_water == WorldRuntimeConstants.WATER_CLASS_OCEAN and not is_walkable:
			has_deep_ocean = true
	return has_shore and has_shallow_shelf and has_deep_ocean

func _packet_has_ocean_shore_band(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var hydrology_ids: PackedInt32Array = packet.get("hydrology_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(mini(terrain_ids.size(), hydrology_ids.size()), mini(hydrology_flags.size(), mini(water_class.size(), walkable_flags.size())))
	for index: int in range(count):
		if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_SHORE:
			continue
		if int(hydrology_ids[index]) != HYDROLOGY_OCEAN_ID:
			continue
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_SHORE) == 0:
			return false
		if int(water_class[index]) != WorldRuntimeConstants.WATER_CLASS_NONE:
			return false
		if walkable_flags[index] == 0:
			return false
		return true
	return false

func _lakebed_has_irregular_outline(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	if terrain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return false
	var row_min_by_y: Dictionary = {}
	var row_max_by_y: Dictionary = {}
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			var index: int = y * WorldRuntimeConstants.CHUNK_SIZE + x
			if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_LAKEBED:
				continue
			row_min_by_y[y] = mini(int(row_min_by_y.get(y, x)), x) if row_min_by_y.has(y) else x
			row_max_by_y[y] = maxi(int(row_max_by_y.get(y, x)), x) if row_max_by_y.has(y) else x
	if row_min_by_y.size() < 4:
		return false
	var min_values: Dictionary = {}
	var max_values: Dictionary = {}
	for y_variant: Variant in row_min_by_y.keys():
		min_values[int(row_min_by_y[y_variant])] = true
		max_values[int(row_max_by_y[y_variant])] = true
	return min_values.size() >= 3 or max_values.size() >= 3

func _lakebed_walkability_matches_water(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(mini(terrain_ids.size(), water_class.size()), walkable_flags.size())
	for index: int in range(count):
		if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_LAKEBED:
			continue
		var current_water: int = int(water_class[index])
		var is_walkable: bool = walkable_flags[index] != 0
		if current_water == WorldRuntimeConstants.WATER_CLASS_SHALLOW and not is_walkable:
			return false
		if current_water == WorldRuntimeConstants.WATER_CLASS_DEEP and is_walkable:
			return false
	return true

func _lakebed_has_basin_depth_gradient(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var count: int = mini(mini(terrain_ids.size(), water_class.size()), hydrology_flags.size())
	var has_shallow_rim: bool = false
	var has_deep_basin: bool = false
	for index: int in range(count):
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_LAKEBED) == 0:
			continue
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id != WorldRuntimeConstants.TERRAIN_LAKEBED:
			continue
		if int(water_class[index]) == WorldRuntimeConstants.WATER_CLASS_SHALLOW:
			has_shallow_rim = true
		elif int(water_class[index]) == WorldRuntimeConstants.WATER_CLASS_DEEP:
			has_deep_basin = true
	return has_shallow_rim and has_deep_basin

func _lakebed_avoids_mountain(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(terrain_ids.size(), mountain_flags.size())
	for index: int in range(count):
		if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_LAKEBED:
			continue
		if (int(mountain_flags[index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
			return false
	return true

func _ocean_surface_avoids_mountain(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(terrain_ids.size(), mini(water_class.size(), mountain_flags.size()))
	for index: int in range(count):
		var terrain_id: int = int(terrain_ids[index])
		var current_water: int = int(water_class[index])
		var is_ocean_surface: bool = terrain_id == WorldRuntimeConstants.TERRAIN_OCEAN_FLOOR \
				or (terrain_id == WorldRuntimeConstants.TERRAIN_SHORE and current_water == WorldRuntimeConstants.WATER_CLASS_NONE)
		if not is_ocean_surface:
			continue
		if (int(mountain_flags[index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
			return false
	return true

func _packet_has_delta_estuary(packet: Dictionary) -> bool:
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var count: int = mini(hydrology_flags.size(), water_class.size())
	for index: int in range(count):
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_DELTA) == 0:
			continue
		if int(water_class[index]) == WorldRuntimeConstants.WATER_CLASS_NONE:
			continue
		return true
	return false

func _delta_estuary_avoids_mountain(packet: Dictionary) -> bool:
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(hydrology_flags.size(), mountain_flags.size())
	for index: int in range(count):
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_DELTA) == 0:
			continue
		if (int(mountain_flags[index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
			return false
	return true

func _packet_has_braid_split(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var count: int = mini(terrain_ids.size(), hydrology_flags.size())
	for index: int in range(count):
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_BRAID_SPLIT) == 0:
			continue
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW \
				and terrain_id != WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP \
				and terrain_id != WorldRuntimeConstants.TERRAIN_SHORE:
			return false
		return true
	return false

func _braid_split_uses_valid_river_water(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var hydrology_ids: PackedInt32Array = packet.get("hydrology_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var count: int = mini(mini(terrain_ids.size(), hydrology_ids.size()), mini(hydrology_flags.size(), mini(water_class.size(), mountain_flags.size())))
	for index: int in range(count):
		if (int(hydrology_flags[index]) & WorldRuntimeConstants.HYDROLOGY_FLAG_BRAID_SPLIT) == 0:
			continue
		if int(hydrology_ids[index]) <= 0:
			return false
		var terrain_id: int = int(terrain_ids[index])
		var is_riverbed: bool = terrain_id == WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW \
				or terrain_id == WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP
		if is_riverbed and int(water_class[index]) == WorldRuntimeConstants.WATER_CLASS_NONE:
			return false
		if (int(mountain_flags[index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
			return false
	return true

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
