extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const LAYER_MASK_LAYER_WINNER: int = 1 << 7
const LAYER_MASK_MOUNTAIN_CLEARANCE: int = 1 << 8
const LAYER_MASK_WATER_SDF: int = 1 << 9
const LAYER_MASK_RIVER_WIDTH: int = 1 << 10
const LAYER_MASK_RIVER_DISCHARGE: int = 1 << 11
const LAYER_MASK_LAKE_SDF: int = 1 << 12
const LAYER_MASK_COAST_SDF: int = 1 << 13

var _failed: bool = false

func _init() -> void:
	var core := WorldCore.new()
	var settings_packed: PackedFloat32Array = _build_settings_packed()
	var build_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	_assert(bool(build_result.get("success", false)), "hydrology prepass should build for V4 classifier debug")
	_assert(_has_v4_counters(build_result), "build result should expose V4 hydrology debug counters")
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	_assert(_has_v4_counters(snapshot), "debug snapshot should expose V4 hydrology debug counters")

	for layer_mask: int in [
		LAYER_MASK_LAYER_WINNER,
		LAYER_MASK_MOUNTAIN_CLEARANCE,
		LAYER_MASK_WATER_SDF,
		LAYER_MASK_RIVER_WIDTH,
		LAYER_MASK_RIVER_DISCHARGE,
		LAYER_MASK_LAKE_SDF,
		LAYER_MASK_COAST_SDF,
	]:
		var overlay: Image = core.call("get_world_hydrology_overview", layer_mask, 2) as Image
		_assert(overlay != null and not overlay.is_empty(), "V4 debug overlay %d should render a native image" % layer_mask)

	_assert(core.has_method("get_world_hydrology_classifier_debug"), "WorldCore should expose native V4 classifier agreement debug")
	if not core.has_method("get_world_hydrology_classifier_debug"):
		_finish()
		return

	var sample_chunks: PackedVector2Array = _find_sample_chunks(snapshot)
	_assert(sample_chunks.size() >= 3, "V4 classifier debug should sample river, lake, and ocean chunks")
	var agreement: Dictionary = core.call(
		"get_world_hydrology_classifier_debug",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed,
		sample_chunks
	) as Dictionary
	_assert(bool(agreement.get("success", false)), "V4 classifier agreement debug should succeed")
	_assert(int(agreement.get("sampled_tile_count", 0)) > 0, "V4 classifier agreement should inspect sampled tiles")
	_assert(int(agreement.get("overview_sampled_tile_count", 0)) > 0, "V4 classifier agreement should inspect overview layer-winner pixels")
	if int(agreement.get("overview_chunk_layer_mismatch_count", -1)) != 0 \
			or int(agreement.get("preview_chunk_layer_mismatch_count", -1)) != 0 \
			or int(agreement.get("overview_preview_chunk_layer_mismatch_count", -1)) != 0:
		print("hydrology_tile_classifier_v4_smoke_test agreement: ", agreement)
	_assert(int(agreement.get("overview_chunk_layer_mismatch_count", -1)) == 0, "overview and chunk packet should agree on layer winners")
	_assert(int(agreement.get("preview_chunk_layer_mismatch_count", -1)) == 0, "33x33 preview and chunk packet should agree on layer winners")
	_assert(int(agreement.get("overview_preview_chunk_layer_mismatch_count", -1)) == 0, "overview, 33x33 preview and chunk packet should agree on layer winners")

	var legacy_agreement: Dictionary = core.call(
		"get_world_hydrology_classifier_debug",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_HEADLAND_COAST_VERSION,
		settings_packed,
		sample_chunks
	) as Dictionary
	_assert(bool(legacy_agreement.get("success", false)), "legacy V29 classifier debug should still succeed")
	_assert(int(legacy_agreement.get("world_version", 0)) == WorldRuntimeConstants.WORLD_HEADLAND_COAST_VERSION, "legacy debug should preserve requested world_version")

	_finish()

func _build_settings_packed() -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _has_v4_counters(data: Dictionary) -> bool:
	for key: String in [
		"mountain_water_overlap_tile_count",
		"river_tiles_adjacent_to_mountain_count",
		"lake_tiles_adjacent_to_mountain_count",
		"river_mouths_without_terminal_widening_count",
		"rivers_with_cut_endpoint_count",
		"overview_runtime_classifier_mismatch_count",
	]:
		if not data.has(key):
			return false
		if int(data.get(key, -1)) < 0:
			return false
	return true

func _find_sample_chunks(snapshot: Dictionary) -> PackedVector2Array:
	var chunks := PackedVector2Array()
	_append_first_chunk_for_mask(chunks, snapshot, "river_node_mask")
	_append_first_chunk_for_lake(chunks, snapshot)
	_append_first_chunk_for_mask(chunks, snapshot, "ocean_sink_mask")
	return chunks

func _append_first_chunk_for_mask(chunks: PackedVector2Array, snapshot: Dictionary, key: String) -> void:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size: int = int(snapshot.get("cell_size_tiles", 16))
	var mask: PackedByteArray = snapshot.get(key, PackedByteArray()) as PackedByteArray
	if width <= 0 or height <= 0 or mask.size() < width * height:
		return
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if mask[index] == 0:
				continue
			_append_unique_chunk(chunks, Vector2i((x * cell_size) / WorldRuntimeConstants.CHUNK_SIZE, (y * cell_size) / WorldRuntimeConstants.CHUNK_SIZE))
			return

func _append_first_chunk_for_lake(chunks: PackedVector2Array, snapshot: Dictionary) -> void:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var cell_size: int = int(snapshot.get("cell_size_tiles", 16))
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	if width <= 0 or height <= 0 or lake_ids.size() < width * height:
		return
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if lake_ids[index] <= 0:
				continue
			_append_unique_chunk(chunks, Vector2i((x * cell_size) / WorldRuntimeConstants.CHUNK_SIZE, (y * cell_size) / WorldRuntimeConstants.CHUNK_SIZE))
			return

func _append_unique_chunk(chunks: PackedVector2Array, chunk: Vector2i) -> void:
	for existing: Vector2 in chunks:
		if Vector2i(int(existing.x), int(existing.y)) == chunk:
			return
	chunks.append(Vector2(float(chunk.x), float(chunk.y)))

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("hydrology_tile_classifier_v4_smoke_test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
