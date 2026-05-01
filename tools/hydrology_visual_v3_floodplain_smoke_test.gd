extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HYDROLOGY_VISUAL_V3_VERSION: int = WorldRuntimeConstants.WORLD_HYDROLOGY_VISUAL_V3_VERSION
const HYDROLOGY_FLAG_FLOODPLAIN: int = 1 << 4
const HYDROLOGY_FLAG_FLOODPLAIN_NEAR: int = 1 << 9
const HYDROLOGY_FLAG_FLOODPLAIN_FAR: int = 1 << 10
const MISSING_CHUNK := Vector2i(-99999, -99999)

var _failed: bool = false

func _init() -> void:
	_assert(WorldRuntimeConstants.WORLD_VERSION >= HYDROLOGY_VISUAL_V3_VERSION, "current WORLD_VERSION should preserve the V3 boundary")
	var packed_settings: PackedFloat32Array = _build_settings_packed()
	var core := WorldCore.new()
	var result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		HYDROLOGY_VISUAL_V3_VERSION,
		packed_settings
	)
	_assert(bool(result.get("success", false)), "V3 hydrology prepass should build for floodplain validation")
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var candidate_chunks: Array[Vector2i] = _collect_floodplain_candidate_chunks(snapshot, 48)
	_assert(not candidate_chunks.is_empty(), "V3 floodplain validation should find candidate chunks")
	var metrics: Dictionary = _collect_floodplain_metrics(
		core,
		packed_settings,
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		HYDROLOGY_VISUAL_V3_VERSION,
		candidate_chunks
	)
	_assert(bool(metrics.get("has_low_nonzero_strength", false)), "V3 floodplain should expose a soft non-terrain strength ramp")
	_assert(bool(metrics.get("has_far_flag", false)), "V3 floodplain should mark far gradient tiles with bit 10")
	_assert(bool(metrics.get("has_near_flag", false)), "V3 floodplain should mark near gradient tiles with bit 9")
	_assert(int(metrics.get("distinct_strength_values", 0)) >= 6, "V3 floodplain strength should have a smooth distribution, not a binary spike")
	_assert(not bool(metrics.get("invalid_flag_range", true)), "V3 floodplain near/far flags should match their strength ranges")
	_assert(not bool(metrics.get("missing_floodplain_flag", true)), "V3 floodplain terrain should carry the legacy floodplain bit")

	var legacy_core := WorldCore.new()
	var legacy_result: Dictionary = legacy_core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_HEADLAND_COAST_VERSION,
		packed_settings
	)
	_assert(bool(legacy_result.get("success", false)), "legacy world_version 29 hydrology prepass should build")
	var legacy_metrics: Dictionary = _collect_floodplain_metrics(
		legacy_core,
		packed_settings,
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_HEADLAND_COAST_VERSION,
		candidate_chunks
	)
	_assert(not bool(legacy_metrics.get("has_far_flag", false)), "legacy world_version 29 should not emit floodplain far bit")
	_assert(not bool(legacy_metrics.get("has_near_flag", false)), "legacy world_version 29 should not emit floodplain near bit")

	if _failed:
		quit(1)
		return
	print("hydrology_visual_v3_floodplain_smoke_test: OK")
	quit(0)

func _build_settings_packed() -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	river_settings.density = 1.0
	river_settings.meander_strength = 1.0
	river_settings.lake_chance = 0.35
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _collect_floodplain_candidate_chunks(snapshot: Dictionary, limit: int) -> Array[Vector2i]:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var floodplain: PackedFloat32Array = snapshot.get("floodplain_potential", PackedFloat32Array()) as PackedFloat32Array
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var mountain_mask: PackedByteArray = snapshot.get("mountain_exclusion_mask", PackedByteArray()) as PackedByteArray
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var chunks: Array[Vector2i] = []
	var seen: Dictionary = {}
	if width <= 0 or height <= 0:
		return chunks
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= floodplain.size() or float(floodplain[index]) < 0.42:
				continue
			if index < ocean_mask.size() and ocean_mask[index] != 0:
				continue
			if index < mountain_mask.size() and mountain_mask[index] != 0:
				continue
			if index < lake_ids.size() and int(lake_ids[index]) > 0:
				continue
			var center := Vector2i(x * cell_size_tiles + cell_size_tiles / 2, y * cell_size_tiles + cell_size_tiles / 2)
			var base_chunk := Vector2i(center.x / WorldRuntimeConstants.CHUNK_SIZE, center.y / WorldRuntimeConstants.CHUNK_SIZE)
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var chunk: Vector2i = base_chunk + offset
				var key: String = "%d,%d" % [chunk.x, chunk.y]
				if seen.has(key):
					continue
				seen[key] = true
				chunks.append(chunk)
				if chunks.size() >= limit:
					return chunks
	return chunks

func _collect_floodplain_metrics(
	core: WorldCore,
	packed_settings: PackedFloat32Array,
	seed: int,
	world_version: int,
	chunks: Array[Vector2i]
) -> Dictionary:
	var coords := PackedVector2Array()
	for chunk: Vector2i in chunks:
		if chunk == MISSING_CHUNK:
			continue
		coords.append(Vector2(float(chunk.x), float(chunk.y)))
	var packets: Array = core.generate_chunk_packets_batch(seed, coords, world_version, packed_settings)
	var strength_values: Dictionary = {}
	var has_low_nonzero_strength: bool = false
	var has_far_flag: bool = false
	var has_near_flag: bool = false
	var invalid_flag_range: bool = false
	var missing_floodplain_flag: bool = false
	for packet: Dictionary in packets:
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
		var floodplain_strength: PackedByteArray = packet.get("floodplain_strength", PackedByteArray()) as PackedByteArray
		var count: int = mini(terrain_ids.size(), mini(hydrology_flags.size(), floodplain_strength.size()))
		for index: int in range(count):
			var terrain_id: int = int(terrain_ids[index])
			var flags: int = int(hydrology_flags[index])
			var strength: int = int(floodplain_strength[index])
			if strength > 0:
				strength_values[strength] = true
			if strength > 0 and strength < 96 and terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
				has_low_nonzero_strength = true
			if (flags & HYDROLOGY_FLAG_FLOODPLAIN_FAR) != 0:
				has_far_flag = true
				if strength < 96 or strength >= 192:
					invalid_flag_range = true
			if (flags & HYDROLOGY_FLAG_FLOODPLAIN_NEAR) != 0:
				has_near_flag = true
				if strength < 192:
					invalid_flag_range = true
			if terrain_id == WorldRuntimeConstants.TERRAIN_FLOODPLAIN and (flags & HYDROLOGY_FLAG_FLOODPLAIN) == 0:
				missing_floodplain_flag = true
			if ((flags & (HYDROLOGY_FLAG_FLOODPLAIN_NEAR | HYDROLOGY_FLAG_FLOODPLAIN_FAR)) != 0) \
					and terrain_id != WorldRuntimeConstants.TERRAIN_FLOODPLAIN:
				invalid_flag_range = true
	return {
		"has_low_nonzero_strength": has_low_nonzero_strength,
		"has_far_flag": has_far_flag,
		"has_near_flag": has_near_flag,
		"distinct_strength_values": strength_values.size(),
		"invalid_flag_range": invalid_flag_range,
		"missing_floodplain_flag": missing_floodplain_flag,
	}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
