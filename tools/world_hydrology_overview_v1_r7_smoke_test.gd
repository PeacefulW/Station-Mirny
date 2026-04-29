extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldFoundationPalette = preload("res://core/systems/world/world_foundation_palette.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HYDROLOGY_WATER_MODE: StringName = &"hydrology_water"
const HYDROLOGY_WATER_LAYER_MASK: int = 1 << 5
const LARGE_PRESET_BUDGET_MS: float = 1500.0
const WORKER_TIMEOUT_MS: int = 5000

var _failed: bool = false

func _init() -> void:
	_assert(WorldFoundationPalette.all_modes().has(HYDROLOGY_WATER_MODE), "overview mode list should expose the hydrology water overlay mode")

	var large_settings: PackedFloat32Array = _build_settings_packed(WorldBoundsSettings.PRESET_LARGE)
	var core := WorldCore.new()
	var build_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		large_settings
	)
	_assert(bool(build_result.get("success", false)), "largest-preset hydrology prepass should build")
	var compute_time_ms: float = float(build_result.get("compute_time_ms", 999999.0))
	_assert(compute_time_ms <= LARGE_PRESET_BUDGET_MS, "largest-preset hydrology prepass should stay under the V1-R7 budget")

	var overview: Image = core.get_world_hydrology_overview(0, 2)
	_assert(overview != null and not overview.is_empty(), "hydrology overview should return a non-empty image")
	var counts: Dictionary = _count_water_overlay_pixels(overview)
	_assert(int(counts.get("ocean", 0)) > 0, "hydrology overview should render ocean overlay pixels")
	_assert(int(counts.get("lake", 0)) > 0, "hydrology overview should render lake overlay pixels")
	_assert(int(counts.get("river", 0)) > 0, "hydrology overview should render river overlay pixels")
	_assert(_overview_has_partial_river_cells(core), "organic hydrology overview should not render every river node as a full rectangle")

	var second_core := WorldCore.new()
	var second_build_result: Dictionary = second_core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		large_settings
	)
	_assert(bool(second_build_result.get("success", false)), "second largest-preset hydrology prepass should build")
	var second_overview: Image = second_core.get_world_hydrology_overview(0, 2)
	_assert(
		second_overview != null and overview.get_data() == second_overview.get_data(),
		"matching largest-preset hydrology overview images should be deterministic"
	)

	_assert(_overview_nodes_match_chunk_packets(core, large_settings), "overview river/lake/ocean nodes should agree with chunk packet rasterization")
	_assert(_backend_publishes_hydrology_overview(), "new-game overview worker should publish native hydrology overlay images")
	_assert(_gdscript_keeps_hydrology_generation_native(), "GDScript should not read hydrology debug arrays or rasterize river generation")

	if _failed:
		quit(1)
		return
	print("world_hydrology_overview_v1_r7_smoke_test: OK largest_compute_time_ms=%.3f" % compute_time_ms)
	quit(0)

func _build_settings_packed(preset: StringName) -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(preset)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _count_water_overlay_pixels(image: Image) -> Dictionary:
	var counts: Dictionary = {
		"ocean": 0,
		"lake": 0,
		"river": 0,
	}
	if image == null or image.is_empty():
		return counts
	var data: PackedByteArray = image.get_data()
	for offset: int in range(0, data.size(), 4):
		var r: int = int(data[offset])
		var g: int = int(data[offset + 1])
		var b: int = int(data[offset + 2])
		if _is_ocean_pixel(r, g, b):
			counts["ocean"] = int(counts["ocean"]) + 1
		elif _is_lake_pixel(r, g, b):
			counts["lake"] = int(counts["lake"]) + 1
		elif _is_river_pixel(r, g, b):
			counts["river"] = int(counts["river"]) + 1
	return counts

func _overview_has_partial_river_cells(core: WorldCore) -> bool:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	var mountain_mask: PackedByteArray = snapshot.get("mountain_exclusion_mask", PackedByteArray()) as PackedByteArray
	var pixels_per_cell: int = 4
	var overview: Image = core.get_world_hydrology_overview(0, pixels_per_cell)
	if overview == null or overview.is_empty():
		return false
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			if index >= river_mask.size() or river_mask[index] == 0:
				continue
			if index < lake_ids.size() and int(lake_ids[index]) > 0:
				continue
			if index < ocean_mask.size() and ocean_mask[index] != 0:
				continue
			if index < mountain_mask.size() and mountain_mask[index] != 0:
				continue
			var river_pixels: int = 0
			for py: int in range(pixels_per_cell):
				for px: int in range(pixels_per_cell):
					var color: Color = overview.get_pixel(x * pixels_per_cell + px, y * pixels_per_cell + py)
					var r: int = roundi(color.r * 255.0)
					var g: int = roundi(color.g * 255.0)
					var b: int = roundi(color.b * 255.0)
					if _is_river_pixel(r, g, b):
						river_pixels += 1
			if river_pixels > 0 and river_pixels < pixels_per_cell * pixels_per_cell:
				return true
	return false

func _overview_nodes_match_chunk_packets(core: WorldCore, packed_settings: PackedFloat32Array) -> bool:
	var snapshot: Dictionary = core.get_world_hydrology_snapshot(0, 1)
	var river_node: Vector2i = _find_snapshot_node(snapshot, "river")
	var lake_node: Vector2i = _find_snapshot_node(snapshot, "lake")
	var ocean_node: Vector2i = _find_snapshot_node(snapshot, "ocean")
	if river_node == Vector2i(-1, -1) or lake_node == Vector2i(-1, -1) or ocean_node == Vector2i(-1, -1):
		return false
	var overview: Image = core.get_world_hydrology_overview(0, 1)
	if not _node_pixel_matches(overview, river_node, "river"):
		return false
	if not _node_pixel_matches(overview, lake_node, "lake"):
		return false
	if not _node_pixel_matches(overview, ocean_node, "ocean"):
		return false
	return _chunk_packet_matches_node(core, packed_settings, snapshot, river_node, "river") \
			and _chunk_packet_matches_node(core, packed_settings, snapshot, lake_node, "lake") \
			and _chunk_packet_matches_node(core, packed_settings, snapshot, ocean_node, "ocean")

func _find_snapshot_node(snapshot: Dictionary, kind: String) -> Vector2i:
	var width: int = int(snapshot.get("grid_width", 0))
	var height: int = int(snapshot.get("grid_height", 0))
	var river_mask: PackedByteArray = snapshot.get("river_node_mask", PackedByteArray()) as PackedByteArray
	var lake_ids: PackedInt32Array = snapshot.get("lake_id", PackedInt32Array()) as PackedInt32Array
	var ocean_mask: PackedByteArray = snapshot.get("ocean_sink_mask", PackedByteArray()) as PackedByteArray
	for y: int in range(height):
		for x: int in range(width):
			var index: int = y * width + x
			match kind:
				"river":
					if index < river_mask.size() and river_mask[index] != 0 and (index >= ocean_mask.size() or ocean_mask[index] == 0):
						return Vector2i(x, y)
				"lake":
					if index < lake_ids.size() and int(lake_ids[index]) > 0:
						return Vector2i(x, y)
				"ocean":
					if index < ocean_mask.size() and ocean_mask[index] != 0:
						return Vector2i(x, y)
	return Vector2i(-1, -1)

func _node_pixel_matches(image: Image, node: Vector2i, kind: String) -> bool:
	if image == null or image.is_empty():
		return false
	var color: Color = image.get_pixel(node.x, node.y)
	var r: int = roundi(color.r * 255.0)
	var g: int = roundi(color.g * 255.0)
	var b: int = roundi(color.b * 255.0)
	match kind:
		"river":
			return _is_river_pixel(r, g, b)
		"lake":
			return _is_lake_pixel(r, g, b)
		"ocean":
			return _is_ocean_pixel(r, g, b)
	return false

func _chunk_packet_matches_node(
	core: WorldCore,
	packed_settings: PackedFloat32Array,
	snapshot: Dictionary,
	node: Vector2i,
	kind: String
) -> bool:
	var cell_size_tiles: int = int(snapshot.get("cell_size_tiles", 16))
	var tile := Vector2i(node.x * cell_size_tiles + cell_size_tiles / 2, node.y * cell_size_tiles + cell_size_tiles / 2)
	var chunk_coord := Vector2i(tile.x / WorldRuntimeConstants.CHUNK_SIZE, tile.y / WorldRuntimeConstants.CHUNK_SIZE)
	var coords := PackedVector2Array()
	coords.append(Vector2(float(chunk_coord.x), float(chunk_coord.y)))
	var packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		packed_settings
	)
	if packets.size() != 1:
		return false
	var packet: Dictionary = packets[0] as Dictionary
	match kind:
		"river":
			return _packet_has_terrain(packet, WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW) \
					or _packet_has_terrain(packet, WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP)
		"lake":
			return _packet_has_terrain(packet, WorldRuntimeConstants.TERRAIN_LAKEBED)
		"ocean":
			return _packet_has_terrain(packet, WorldRuntimeConstants.TERRAIN_OCEAN_FLOOR)
	return false

func _packet_has_terrain(packet: Dictionary, terrain_id: int) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	for current_id: int in terrain_ids:
		if current_id == terrain_id:
			return true
	return false

func _backend_publishes_hydrology_overview() -> bool:
	var backend := WorldChunkPacketBackend.new()
	backend.start()
	backend.queue_overview_request(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed(WorldBoundsSettings.PRESET_SMALL),
		1,
		HYDROLOGY_WATER_LAYER_MASK,
		2
	)
	var deadline: int = Time.get_ticks_msec() + WORKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		var results: Array[Dictionary] = backend.drain_completed_overviews(1)
		if not results.is_empty():
			backend.stop()
			var result: Dictionary = results[0]
			if not bool(result.get("success", false)):
				return false
			var image: Image = result.get("image", null) as Image
			var counts: Dictionary = _count_water_overlay_pixels(image)
			return int(counts.get("ocean", 0)) > 0 \
					and int(counts.get("lake", 0)) > 0 \
					and int(counts.get("river", 0)) > 0
		OS.delay_msec(10)
	backend.stop()
	return false

func _gdscript_keeps_hydrology_generation_native() -> bool:
	var backend_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_chunk_packet_backend.gd")
	var controller_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_preview_controller.gd")
	if not backend_source.contains("build_world_hydrology_prepass") or not backend_source.contains("get_world_hydrology_overview"):
		return false
	if backend_source.contains("get_world_hydrology_snapshot"):
		return false
	for forbidden: String in ["river_node_mask", "lake_id", "ocean_sink_mask", "flow_accumulation"]:
		if controller_source.contains(forbidden) or backend_source.contains(forbidden):
			return false
	return true

func _is_ocean_pixel(r: int, g: int, b: int) -> bool:
	return r >= 30 and r <= 48 and g >= 80 and g <= 100 and b >= 118 and b <= 140

func _is_lake_pixel(r: int, g: int, b: int) -> bool:
	return r >= 34 and r <= 62 and g >= 116 and g <= 146 and b >= 146 and b <= 176

func _is_river_pixel(r: int, g: int, b: int) -> bool:
	return r >= 30 and r <= 52 and g >= 118 and g <= 190 and b >= 184 and b <= 205

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
