extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const EDGE_METADATA_RECORD_SIZE: int = 4
const EDGE_FLAG_DELTA: int = 2
const EDGE_FLAG_BRAID_SPLIT: int = 4

var _failed: bool = false

func _init() -> void:
	_assert(
		WorldRuntimeConstants.WORLD_VERSION >= WorldRuntimeConstants.WORLD_ESTUARY_DELTA_V4_VERSION,
		"current WORLD_VERSION should preserve the V4-4 estuary/delta boundary"
	)
	_assert(
		WorldRuntimeConstants.WORLD_ESTUARY_DELTA_V4_VERSION > WorldRuntimeConstants.WORLD_RIVER_DISCHARGE_WIDTH_V4_VERSION,
		"V4-4 must preserve V4-3 saves behind an older world_version boundary"
	)

	var settings_packed: PackedFloat32Array = _build_settings_packed()
	var core := WorldCore.new()
	var build_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	_assert(bool(build_result.get("success", false)), "hydrology prepass should build for V4-4 estuary/delta profiles")
	_assert(int(build_result.get("estuary_delta_fan_terminal_count", 0)) > 0, "default delta_scale should emit at least one qualifying estuary fan terminal")
	_assert(int(build_result.get("estuary_delta_fan_edge_count", 0)) > 0, "estuary fan should add native delta branch edges")
	_assert(int(build_result.get("estuary_discharge_fan_branch_count", 0)) > 0, "estuary fan branch count should be derived from discharge")
	_assert(int(build_result.get("estuary_coast_sdf_modified_node_count", 0)) > 0, "estuary mouth influence should modify local coast SDF diagnostics")
	_assert(float(build_result.get("estuary_terminal_fan_width_ratio_max", 0.0)) >= 3.0, "qualifying estuary fan should be at least 3x trunk width")

	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	_assert(int(snapshot.get("estuary_delta_fan_edge_count", -1)) == int(build_result.get("estuary_delta_fan_edge_count", -2)), "snapshot and build result should agree on estuary fan edge count")
	_assert(int(snapshot.get("estuary_coast_sdf_modified_node_count", -1)) == int(build_result.get("estuary_coast_sdf_modified_node_count", -2)), "snapshot and build result should agree on coast SDF modification count")
	_assert(_has_delta_fan_edge_metadata(snapshot), "refined river metadata should flag distributary fan edges as delta braid-split hydrology")

	var chunks: PackedVector2Array = _find_estuary_chunks(snapshot)
	_assert(chunks.size() > 0, "V4-4 smoke should find chunks near native estuary mouth influence")
	var packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		chunks,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	_assert(packets.size() == chunks.size(), "chunk packet batch should return all requested estuary chunks")
	_assert(_packets_have_delta_tiles(packets), "estuary chunks should rasterize delta flags into packet hydrology_flags")

	var legacy_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_RIVER_DISCHARGE_WIDTH_V4_VERSION,
		settings_packed
	)
	_assert(bool(legacy_result.get("success", false)), "legacy V4-3 hydrology prepass should still build")
	_assert(int(legacy_result.get("world_version", 0)) == WorldRuntimeConstants.WORLD_RIVER_DISCHARGE_WIDTH_V4_VERSION, "legacy V4-3 build should preserve requested world_version")
	_assert(int(legacy_result.get("estuary_delta_fan_edge_count", 0)) == 0, "legacy V4-3 build should not enable V4-4 estuary fan counters")
	_assert(int(legacy_result.get("estuary_coast_sdf_modified_node_count", 0)) == 0, "legacy V4-3 build should not modify coast SDF through V4-4 estuaries")

	_finish()

func _build_settings_packed() -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	river_settings.delta_scale = 1.0
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _has_delta_fan_edge_metadata(snapshot: Dictionary) -> bool:
	var metadata: PackedInt32Array = snapshot.get("refined_river_edge_metadata", PackedInt32Array()) as PackedInt32Array
	for index: int in range(0, metadata.size(), EDGE_METADATA_RECORD_SIZE):
		var flags: int = int(metadata[index + 3])
		if (flags & EDGE_FLAG_DELTA) != 0 and (flags & EDGE_FLAG_BRAID_SPLIT) != 0:
			return true
	return false

func _find_estuary_chunks(snapshot: Dictionary) -> PackedVector2Array:
	var chunks := PackedVector2Array()
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size: int = int(snapshot.get("cell_size_tiles", 16))
	var mouth_influence: PackedFloat32Array = snapshot.get("ocean_river_mouth_influence", PackedFloat32Array()) as PackedFloat32Array
	if width <= 0 or height <= 0 or mouth_influence.size() < width * height:
		return chunks
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if mouth_influence[index] < 0.25:
				continue
			var center_chunk := Vector2i((x * cell_size) / WorldRuntimeConstants.CHUNK_SIZE, (y * cell_size) / WorldRuntimeConstants.CHUNK_SIZE)
			for oy: int in range(-1, 2):
				for ox: int in range(-1, 2):
					_append_unique_chunk(chunks, Vector2i(center_chunk.x + ox, max(0, center_chunk.y + oy)))
			return chunks
	return chunks

func _packets_have_delta_tiles(packets: Array) -> bool:
	for packet: Dictionary in packets:
		var hydrology_flags: PackedInt32Array = packet.get("hydrology_flags", PackedInt32Array()) as PackedInt32Array
		for flags: int in hydrology_flags:
			if (flags & WorldRuntimeConstants.HYDROLOGY_FLAG_DELTA) != 0:
				return true
	return false

func _append_unique_chunk(chunks: PackedVector2Array, chunk: Vector2i) -> void:
	for existing: Vector2 in chunks:
		if Vector2i(int(existing.x), int(existing.y)) == chunk:
			return
	chunks.append(Vector2(float(chunk.x), float(chunk.y)))

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("hydrology_estuary_delta_v4_smoke_test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
