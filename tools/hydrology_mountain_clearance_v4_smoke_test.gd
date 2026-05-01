extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failed: bool = false

func _init() -> void:
	_assert(
		WorldRuntimeConstants.WORLD_VERSION >= WorldRuntimeConstants.WORLD_HYDROLOGY_CLEARANCE_V4_VERSION,
		"current WORLD_VERSION should preserve the V4-2 mountain-clearance boundary"
	)
	_assert(
		WorldRuntimeConstants.WORLD_HYDROLOGY_CLEARANCE_V4_VERSION > WorldRuntimeConstants.WORLD_HYDROLOGY_VISUAL_V3_VERSION,
		"V4-2 must preserve V3 legacy saves behind an older world_version boundary"
	)

	var settings_packed: PackedFloat32Array = _build_settings_packed()
	var clearance_tiles: int = int(settings_packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_MOUNTAIN_CLEARANCE_TILES])
	var core := WorldCore.new()
	var build_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	_assert(bool(build_result.get("success", false)), "hydrology prepass should build for V4-2 clearance")
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var node_count: int = int(snapshot.get("grid_width", 0)) * int(snapshot.get("grid_height", 0))
	var clearance_distances: PackedFloat32Array = snapshot.get("mountain_clearance_distance_tiles", PackedFloat32Array()) as PackedFloat32Array
	_assert(clearance_distances.size() == node_count, "snapshot should expose RAM-only mountain_clearance_distance_tiles")

	var chunks: PackedVector2Array = _find_chunks_near_mountain_hydrology(snapshot)
	_assert(chunks.size() > 0, "V4-2 smoke should inspect chunks near mountain-adjacent river/lake diagnostics")
	var packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		chunks,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	_assert(packets.size() == chunks.size(), "chunk packet batch should return all requested V4-2 chunks")
	_assert(_river_lake_water_respects_mountain_clearance(packets, chunks, clearance_tiles), "river/lake wet tiles should stay outside the mountain clearance radius")

	var legacy_packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		chunks,
		WorldRuntimeConstants.WORLD_HYDROLOGY_VISUAL_V3_VERSION,
		settings_packed
	)
	_assert(legacy_packets.size() == chunks.size(), "legacy V3 chunk packets should still generate")
	_assert(int(legacy_packets[0].get("world_version", 0)) == WorldRuntimeConstants.WORLD_HYDROLOGY_VISUAL_V3_VERSION, "legacy packets should preserve requested V3 world_version")

	_finish()

func _build_settings_packed() -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _find_chunks_near_mountain_hydrology(snapshot: Dictionary) -> PackedVector2Array:
	var chunks := PackedVector2Array()
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size: int = int(snapshot.get("cell_size_tiles", 16))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var mountain_mask: PackedByteArray = snapshot.get("mountain_exclusion_mask", PackedByteArray()) as PackedByteArray
	if width <= 0 or height <= 0 or mountain_mask.size() < width * height:
		return chunks
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			var has_water: bool = (
				(index < river_mask.size() and river_mask[index] != 0) or
				(index < lake_ids.size() and lake_ids[index] > 0)
			)
			if not has_water or not _node_has_adjacent_mountain(width, height, mountain_mask, x, y):
				continue
			var chunk := Vector2i((x * cell_size) / WorldRuntimeConstants.CHUNK_SIZE, (y * cell_size) / WorldRuntimeConstants.CHUNK_SIZE)
			for oy: int in range(-1, 2):
				for ox: int in range(-1, 2):
					_append_unique_chunk(chunks, Vector2i(chunk.x + ox, max(0, chunk.y + oy)))
			if chunks.size() >= 9:
				return chunks
	return chunks

func _node_has_adjacent_mountain(width: int, height: int, mountain_mask: PackedByteArray, x: int, y: int) -> bool:
	for offset: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var nx: int = posmod(x + offset.x, width)
		var ny: int = y + offset.y
		if ny < 0 or ny >= height:
			continue
		if mountain_mask[ny * width + nx] != 0:
			return true
	return false

func _river_lake_water_respects_mountain_clearance(packets: Array, chunks: PackedVector2Array, clearance_tiles: int) -> bool:
	var mountain_by_tile: Dictionary = {}
	var wet_tiles: Array[Vector2i] = []
	for packet_index: int in range(packets.size()):
		var packet: Dictionary = packets[packet_index]
		var chunk := Vector2i(int(chunks[packet_index].x), int(chunks[packet_index].y))
		var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var hydrology_ids: PackedInt32Array = packet.get("hydrology_id_per_tile", PackedInt32Array()) as PackedInt32Array
		var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
		for local_y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			for local_x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
				var index: int = local_y * WorldRuntimeConstants.CHUNK_SIZE + local_x
				var tile := Vector2i(chunk.x * WorldRuntimeConstants.CHUNK_SIZE + local_x, chunk.y * WorldRuntimeConstants.CHUNK_SIZE + local_y)
				if index < mountain_flags.size() and (int(mountain_flags[index]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
					mountain_by_tile[_tile_key(tile)] = true
				if _is_river_or_lake_wet_tile(index, terrain_ids, hydrology_ids, hydrology_flags):
					wet_tiles.append(tile)
	for tile: Vector2i in wet_tiles:
		for dy: int in range(-clearance_tiles, clearance_tiles + 1):
			for dx: int in range(-clearance_tiles, clearance_tiles + 1):
				if dx * dx + dy * dy > clearance_tiles * clearance_tiles:
					continue
				if mountain_by_tile.has(_tile_key(Vector2i(tile.x + dx, tile.y + dy))):
					push_error("river/lake wet tile %s violates clearance near mountain offset %s" % [tile, Vector2i(dx, dy)])
					return false
	return true

func _is_river_or_lake_wet_tile(index: int, terrain_ids: PackedInt32Array, hydrology_ids: PackedInt32Array, hydrology_flags: PackedInt32Array) -> bool:
	if index >= terrain_ids.size():
		return false
	var terrain_id: int = int(terrain_ids[index])
	var hydrology_id: int = int(hydrology_ids[index]) if index < hydrology_ids.size() else 0
	var flags: int = int(hydrology_flags[index]) if index < hydrology_flags.size() else 0
	if terrain_id == WorldRuntimeConstants.TERRAIN_LAKEBED:
		return true
	if terrain_id == WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW or terrain_id == WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP:
		return true
	if terrain_id == WorldRuntimeConstants.TERRAIN_SHORE:
		if (flags & (WorldRuntimeConstants.HYDROLOGY_FLAG_RIVERBED | WorldRuntimeConstants.HYDROLOGY_FLAG_LAKEBED)) != 0:
			return true
		if hydrology_id > 0 and hydrology_id < 2000000:
			return true
	return false

func _append_unique_chunk(chunks: PackedVector2Array, chunk: Vector2i) -> void:
	for existing: Vector2 in chunks:
		if Vector2i(int(existing.x), int(existing.y)) == chunk:
			return
	chunks.append(Vector2(float(chunk.x), float(chunk.y)))

func _tile_key(tile: Vector2i) -> String:
	return "%d:%d" % [tile.x, tile.y]

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("hydrology_mountain_clearance_v4_smoke_test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
