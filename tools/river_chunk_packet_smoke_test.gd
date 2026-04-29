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
	var build_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	_assert(bool(build_result.get("success", false)), "hydrology prepass should build before river packet generation")

	var river_chunk: Vector2i = _find_river_chunk(core)
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

func _find_river_chunk(core: WorldCore) -> Vector2i:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	for y: int in range(height - 1, -1, -1):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= river_mask.size() or river_mask[index] == 0:
				continue
			if index < ocean_mask.size() and ocean_mask[index] != 0:
				continue
			var tile := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			return Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
	return Vector2i(-99999, -99999)

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

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
