extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HYDROLOGY_VISUAL_V3_VERSION: int = 30
const HYDROLOGY_LAKE_ID_OFFSET: int = 1000000
const MISSING_LAKE_ID: int = -1

var _failed: bool = false

func _init() -> void:
	var packed_settings: PackedFloat32Array = _build_settings_packed()
	var seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
	var core := WorldCore.new()
	var result: Dictionary = core.build_world_hydrology_prepass(
		seed,
		HYDROLOGY_VISUAL_V3_VERSION,
		packed_settings
	)
	_assert(bool(result.get("success", false)), "V3 hydrology prepass should build for lake SDF validation")
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var lake_id: int = _select_lake_for_sdf_validation(snapshot)
	_assert(lake_id != MISSING_LAKE_ID, "V3 hydrology snapshot should expose a lake candidate for SDF validation")
	var metrics: Dictionary = _collect_lake_sdf_metrics(
		core,
		packed_settings,
		seed,
		HYDROLOGY_VISUAL_V3_VERSION,
		snapshot,
		lake_id
	)
	_assert(int(metrics.get("lake_area", 0)) > 0, "V3 lake SDF validation should find lakebed packet tiles")
	_assert(float(metrics.get("area_ratio", 1.0)) <= 0.70, "V3 lakebed area should not fill more than 70% of its hydrology-cell bounding rect")
	_assert(float(metrics.get("sharedplane_edge_ratio", 1.0)) <= 0.20, "V3 lake shoreline should not align primarily to 16-tile hydrology cell planes")

	var legacy_core := WorldCore.new()
	var legacy_result: Dictionary = legacy_core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_HEADLAND_COAST_VERSION,
		packed_settings
	)
	_assert(bool(legacy_result.get("success", false)), "legacy world_version 29 hydrology prepass should still build")

	if _failed:
		quit(1)
		return
	print("hydrology_visual_v3_lake_sdf_smoke_test: OK")
	quit(0)

func _build_settings_packed() -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	river_settings.lake_chance = 1.0
	river_settings.density = 0.75
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _select_lake_for_sdf_validation(snapshot: Dictionary) -> int:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	if width <= 0 or height <= 0 or lake_ids.size() < width * height:
		return MISSING_LAKE_ID
	var stats_by_lake: Dictionary = {}
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			var lake_id: int = int(lake_ids[index])
			if lake_id <= 0:
				continue
			var stats: Dictionary = stats_by_lake.get(lake_id, {
				"count": 0,
				"min_x": x,
				"max_x": x,
				"min_y": y,
				"max_y": y,
			})
			stats["count"] = int(stats["count"]) + 1
			stats["min_x"] = mini(int(stats["min_x"]), x)
			stats["max_x"] = maxi(int(stats["max_x"]), x)
			stats["min_y"] = mini(int(stats["min_y"]), y)
			stats["max_y"] = maxi(int(stats["max_y"]), y)
			stats_by_lake[lake_id] = stats
	var best_lake_id: int = MISSING_LAKE_ID
	var best_score: float = -1.0
	for lake_key: Variant in stats_by_lake.keys():
		var stats: Dictionary = stats_by_lake[lake_key]
		var node_count: int = int(stats["count"])
		var rect_cells: int = (int(stats["max_x"]) - int(stats["min_x"]) + 1) * (int(stats["max_y"]) - int(stats["min_y"]) + 1)
		if node_count <= 0 or rect_cells <= 0:
			continue
		var rect_fill: float = float(node_count) / float(rect_cells)
		var score: float = rect_fill * 1000.0 + float(node_count)
		if score > best_score:
			best_score = score
			best_lake_id = int(lake_key)
	return best_lake_id

func _collect_lake_sdf_metrics(
	core: WorldCore,
	packed_settings: PackedFloat32Array,
	seed: int,
	world_version: int,
	snapshot: Dictionary,
	target_lake_id: int
) -> Dictionary:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var world_width_tiles: int = int(snapshot.get("world_width_tiles", width * cell_size_tiles))
	var world_height_tiles: int = int(snapshot.get("world_height_tiles", height * cell_size_tiles))
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var min_x: int = width
	var max_x: int = -1
	var min_y: int = height
	var max_y: int = -1
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= lake_ids.size() or int(lake_ids[index]) != target_lake_id:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return {}
	var tile_min_x: int = min_x * cell_size_tiles
	var tile_max_x: int = mini(world_width_tiles - 1, (max_x + 1) * cell_size_tiles - 1)
	var tile_min_y: int = min_y * cell_size_tiles
	var tile_max_y: int = mini(world_height_tiles - 1, (max_y + 1) * cell_size_tiles - 1)
	var sample_tile_min_x: int = maxi(0, tile_min_x - cell_size_tiles)
	var sample_tile_max_x: int = mini(world_width_tiles - 1, tile_max_x + cell_size_tiles)
	var sample_tile_min_y: int = maxi(0, tile_min_y - cell_size_tiles)
	var sample_tile_max_y: int = mini(world_height_tiles - 1, tile_max_y + cell_size_tiles)
	var chunk_min_x: int = sample_tile_min_x / WorldRuntimeConstants.CHUNK_SIZE
	var chunk_max_x: int = sample_tile_max_x / WorldRuntimeConstants.CHUNK_SIZE
	var chunk_min_y: int = sample_tile_min_y / WorldRuntimeConstants.CHUNK_SIZE
	var chunk_max_y: int = sample_tile_max_y / WorldRuntimeConstants.CHUNK_SIZE
	var coords := PackedVector2Array()
	for chunk_y: int in range(chunk_min_y, chunk_max_y + 1):
		for chunk_x: int in range(chunk_min_x, chunk_max_x + 1):
			coords.append(Vector2(float(chunk_x), float(chunk_y)))
	var packets: Array = core.generate_chunk_packets_batch(
		seed,
		coords,
		world_version,
		packed_settings
	)
	var lake_tile_keys: Dictionary = {}
	for packet_index: int in range(packets.size()):
		var packet: Dictionary = packets[packet_index] if packet_index < packets.size() else {}
		var chunk := Vector2i(int(coords[packet_index].x), int(coords[packet_index].y))
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var hydrology_ids: PackedInt32Array = packet.get("hydrology_id_per_tile", PackedInt32Array()) as PackedInt32Array
		var count: int = mini(terrain_ids.size(), hydrology_ids.size())
		for local_y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			for local_x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
				var tile_index: int = local_y * WorldRuntimeConstants.CHUNK_SIZE + local_x
				if tile_index >= count:
					continue
				if int(terrain_ids[tile_index]) != WorldRuntimeConstants.TERRAIN_LAKEBED:
					continue
				if int(hydrology_ids[tile_index]) != HYDROLOGY_LAKE_ID_OFFSET + target_lake_id:
					continue
				var world_x: int = chunk.x * WorldRuntimeConstants.CHUNK_SIZE + local_x
				var world_y: int = chunk.y * WorldRuntimeConstants.CHUNK_SIZE + local_y
				if world_x < sample_tile_min_x or world_x > sample_tile_max_x or world_y < sample_tile_min_y or world_y > sample_tile_max_y:
					continue
				lake_tile_keys[_tile_key(world_x, world_y)] = Vector2i(world_x, world_y)
	var lake_area: int = lake_tile_keys.size()
	var rect_area: int = maxi(1, (tile_max_x - tile_min_x + 1) * (tile_max_y - tile_min_y + 1))
	var boundary_edges: int = 0
	var sharedplane_edges: int = 0
	for tile_variant: Variant in lake_tile_keys.values():
		var tile: Vector2i = tile_variant
		for offset: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var adjacent := tile + offset
			if lake_tile_keys.has(_tile_key(adjacent.x, adjacent.y)):
				continue
			boundary_edges += 1
			if offset.x < 0 and tile.x % cell_size_tiles == 0:
				sharedplane_edges += 1
			elif offset.x > 0 and (tile.x + 1) % cell_size_tiles == 0:
				sharedplane_edges += 1
			elif offset.y < 0 and tile.y % cell_size_tiles == 0:
				sharedplane_edges += 1
			elif offset.y > 0 and (tile.y + 1) % cell_size_tiles == 0:
				sharedplane_edges += 1
	return {
		"lake_area": lake_area,
		"rect_area": rect_area,
		"area_ratio": float(lake_area) / float(rect_area),
		"boundary_edges": boundary_edges,
		"sharedplane_edge_ratio": 0.0 if boundary_edges == 0 else float(sharedplane_edges) / float(boundary_edges),
	}

func _tile_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
