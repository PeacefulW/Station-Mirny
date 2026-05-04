extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DefaultFoundationGenSettings = preload("res://data/balance/foundation_gen_settings.tres")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const DefaultMountainGenSettings = preload("res://data/balance/mountain_gen_settings.tres")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

var _failed: bool = false

func _init() -> void:
	_assert_lake_classification_uses_foundation_height()
	_assert_overview_uses_lake_settings()
	_assert_basin_bfs_uses_dynamic_rim()
	_assert_l5_settings_layout_and_connectivity()
	_assert_l5_basin_shape_and_merge_pass()
	_assert_lake_drift_guards()
	_assert_l5_native_lake_snapshot_is_deterministic()
	_assert_l6_world_version_and_cross_cell_lakes()
	_assert_l6_native_chunk_packets_are_deterministic()
	_assert_l6_spawn_tiles_are_not_published_water()
	_assert_l7_shore_warp_ui_and_persistence()
	_assert_water_seam_refresh_contract()
	if _failed:
		quit(1)
		return
	print("lake_generation_regression_smoke_test: OK")
	quit(0)

func _assert_lake_classification_uses_foundation_height() -> void:
	var source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		source.contains("sample_foundation_height_bilinear"),
		"WorldCore lake classification must sample foundation_height in the same units as lake_water_level_q16."
	)
	_assert(
		not source.contains("mountain_elevations[static_cast<size_t>(sample_index)] + shore_warp"),
		"WorldCore lake classification must not compare raw mountain elevation against foundation_height water level."
	)

func _assert_overview_uses_lake_settings() -> void:
	var source: String = FileAccess.get_file_as_string("res://gdextension/src/world_prepass.cpp")
	_assert(
		source.contains("const LakeSettings &p_lake_settings"),
		"Overview lake classification must receive the active LakeSettings."
	)
	_assert(
		source.contains("lake_settings_(p_lake_settings)"),
		"OverviewTerrainSampler must store the active LakeSettings."
	)
	_assert(
		not source.contains("const LakeSettings lake_settings;"),
		"Overview lake classification must not instantiate default LakeSettings."
	)

func _assert_basin_bfs_uses_dynamic_rim() -> void:
	var source: String = FileAccess.get_file_as_string("res://gdextension/src/lake_field.cpp")
	_assert(
		source.contains("rim_height_so_far"),
		"Lake basin BFS must track a dynamic observed rim height."
	)
	_assert(
		not source.contains("height_ceiling"),
		"Lake basin BFS must not use fixed center_height + fill_depth as the water boundary."
	)
	_assert(
		not source.contains("fill_depth"),
		"Lake basin shape must not carry a fixed fill_depth cutoff."
	)

func _assert_l5_settings_layout_and_connectivity() -> void:
	var constants_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_runtime_constants.gd")
	_assert(
		constants_source.contains("const SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY: int = 21"),
		"L5 must reserve settings_packed[21] for LakeGenSettings.connectivity."
	)
	_assert(
		constants_source.contains("const SETTINGS_PACKED_LAYOUT_FIELD_COUNT: int = 22"),
		"L5 must bump SETTINGS_PACKED_LAYOUT_FIELD_COUNT to 22."
	)

	var lake_settings_source: String = FileAccess.get_file_as_string("res://core/resources/lake_gen_settings.gd")
	_assert(
		lake_settings_source.contains("@export_range(0.0, 1.0, 0.01) var connectivity: float = 0.4"),
		"LakeGenSettings.connectivity must be exported with range 0..1 and default 0.4."
	)
	_assert(
		lake_settings_source.contains("\"connectivity\": connectivity"),
		"LakeGenSettings.to_save_dict must include connectivity."
	)
	_assert(
		lake_settings_source.contains("SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY"),
		"LakeGenSettings.write_to_settings_packed must write connectivity through the named layout constant."
	)

	var lake_balance_source: String = FileAccess.get_file_as_string("res://data/balance/lake_gen_settings.tres")
	_assert(
		lake_balance_source.contains("connectivity = 0.4"),
		"Default lake_gen_settings.tres must persist connectivity = 0.4."
	)

	var world_core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		world_core_source.contains("SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY = 21"),
		"Native settings layout must reserve index 21 for lake connectivity."
	)
	_assert(
		world_core_source.contains("settings.connectivity = world_utils::clamp_value"),
		"Native unpack_lake_settings must clamp and copy LakeSettings.connectivity."
	)

func _assert_l5_basin_shape_and_merge_pass() -> void:
	var source: String = FileAccess.get_file_as_string("res://gdextension/src/lake_field.cpp")
	_assert(
		source.contains("4096"),
		"L5 basin mapping must raise lake_max_basin_cells cap to 4096."
	)
	_assert(
		source.contains("coarse_diameter * coarse_diameter / 16.0f"),
		"L5 basin mapping must derive lake_min_basin_cells from d*d/16."
	)
	_assert(
		source.contains("k_lake_merge_iteration_cap = 16"),
		"L5 merge pass must define merge_iteration_cap = 16."
	)
	_assert(
		source.contains("merge_lake_basins"),
		"L5 must run a deterministic basin merge pass after basin solve."
	)
	_assert(
		source.contains("settings.connectivity <= 0.0f"),
		"L5 merge pass must be a no-op when connectivity is 0."
	)
	_assert(
		source.contains("std::sort(candidate_pairs.begin(), candidate_pairs.end()"),
		"L5 merge candidates must be sorted deterministically before merging."
	)
	var merge_call_index: int = source.find("merge_lake_basins(r_snapshot")
	var min_lookup_index: int = source.find("BasinMinElevationLookup build_basin_min_elevation_lookup")
	_assert(
		merge_call_index >= 0 and min_lookup_index >= 0 and merge_call_index < min_lookup_index,
		"Lake basin min-elevation lookup must observe post-merge lake_id values."
	)

func _assert_lake_drift_guards() -> void:
	var lake_field_header: String = FileAccess.get_file_as_string("res://gdextension/src/lake_field.h")
	var lake_field_source: String = FileAccess.get_file_as_string("res://gdextension/src/lake_field.cpp")
	var lake_spec: String = FileAccess.get_file_as_string("res://docs/02_system_specs/world/lake_generation.md")
	var foundation_spec: String = FileAccess.get_file_as_string("res://docs/02_system_specs/world/world_foundation_v1.md")
	_assert(
		not lake_field_source.contains("clamp_value(rim_height, 0.0f, 1.0f) * 65536.0f"),
		"Lake water_level_q16 encoding must not clamp rim_height before fixed-point conversion."
	)
	_assert(
		lake_field_source.contains("std::lround(rim_height * 65536.0f)"),
		"Lake water_level_q16 encoding must follow round(rim_height * 65536.0)."
	)
	_assert(
		not lake_field_header.contains("std::unordered_map<int32_t, float>"),
		"BasinMinElevationLookup must not be an unordered_map foot-gun."
	)
	_assert(
		lake_field_header.contains("std::vector<std::pair<int32_t, float>>"),
		"BasinMinElevationLookup must be a sorted vector of lake_id/min-elevation pairs."
	)
	_assert(
		lake_field_source.contains("std::lower_bound"),
		"BasinMinElevationLookup must resolve by deterministic binary search."
	)
	_assert(
		lake_field_source.contains("std::priority_queue"),
		"Lake basin frontier must use a deterministic priority queue instead of linear pop scans."
	)
	_assert(
		not lake_field_source.contains("survivor.bfs_root_index = std::min"),
		"Lake merge must not redundantly rewrite the survivor bfs_root_index."
	)
	_assert(
		lake_field_source.contains("assert(survivor.bfs_root_index <= loser.bfs_root_index"),
		"Lake merge must assert the documented survivor root ordering."
	)
	_assert(
		foundation_spec.contains("`foundation_height` is clamped to `[0, 1]`"),
		"World Foundation spec must explicitly guarantee the foundation_height range."
	)
	_assert(
		lake_spec.contains("deterministic Bernoulli mask"),
		"Lake spec must define density as a deterministic Bernoulli mask."
	)
	_assert(
		lake_spec.contains("Basins must not touch Y bounds"),
		"Lake spec must define the Y-boundary rejection rule for basin growth."
	)
	_assert(
		lake_spec.contains("low-frequency FBM (2 octaves)"),
		"Lake spec must match the native two-octave fbm_shore implementation."
	)

func _assert_l6_world_version_and_cross_cell_lakes() -> void:
	var source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		source.contains("struct NeighbourLake"),
		"L6 must define an explicit neighbour-lake selection result."
	)
	_assert(
		source.contains("k_lake_neighbour_priority"),
		"L6 must keep the documented deterministic 3x3 neighbour priority order in native code."
	)
	_assert(
		source.contains("{ 0, 0 },") and
				source.contains("{ 0, -1 },") and
				source.contains("{ 1, 0 },") and
				source.contains("{ 0, 1 },") and
				source.contains("{ -1, 0 },") and
				source.contains("{ -1, -1 },") and
				source.contains("{ 1, -1 },") and
				source.contains("{ 1, 1 },") and
				source.contains("{ -1, 1 },"),
		"L6 neighbour scan must keep centre, cardinal, then diagonal priority."
	)
	_assert(
		source.contains("resolve_best_neighbour_lake"),
		"WorldCore lake classification must scan the 3x3 coarse-cell neighbourhood."
	)
	_assert(
		source.contains("candidate.water_level_q16 > best.water_level_q16"),
		"L6 neighbour selection must prefer the highest water level."
	)
	_assert(
		source.contains("candidate.lake_id < best.lake_id"),
		"L6 neighbour selection must break equal-level ties by lowest lake_id."
	)
	_assert(
		source.contains("is_water_at_world_from_neighbour_lake"),
		"WorldCore spawn rejection must use the same 3x3 effective-elevation water test."
	)
	_assert(
		source.contains("resolve_world_foundation_spawn_tile_l6"),
		"WorldCore spawn resolver must run the L6 spawn filter before returning a spawn tile."
	)
	_assert(
		not source.contains("world_prepass::resolve_spawn_tile(snapshot);"),
		"WorldCore spawn resolver must not use the old in-cell lake_id rejection path."
	)

func _assert_l7_shore_warp_ui_and_persistence() -> void:
	var constants_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_runtime_constants.gd")
	_assert(
		constants_source.contains("const WORLD_VERSION: int = 42"),
		"L7 must advance WorldRuntimeConstants.WORLD_VERSION to 42."
	)

	var lake_settings_source: String = FileAccess.get_file_as_string("res://core/resources/lake_gen_settings.gd")
	_assert(
		lake_settings_source.contains("const SHORE_WARP_AMPLITUDE_MAX: float = 1.0"),
		"L7 must clamp shore_warp_amplitude to the 0..1 basin-depth fraction range."
	)
	_assert(
		lake_settings_source.contains("@export_range(0.0, 1.0, 0.05) var shore_warp_amplitude: float = 0.4"),
		"L7 must export shore_warp_amplitude with range 0..1 and default 0.4."
	)

	var lake_balance_source: String = FileAccess.get_file_as_string("res://data/balance/lake_gen_settings.tres")
	_assert(
		lake_balance_source.contains("shore_warp_amplitude = 0.4"),
		"Default lake_gen_settings.tres must persist shore_warp_amplitude = 0.4."
	)
	_assert(
		lake_balance_source.contains("connectivity = 0.4"),
		"Default lake_gen_settings.tres must keep connectivity = 0.4."
	)

	var lake_field_header: String = FileAccess.get_file_as_string("res://gdextension/src/lake_field.h")
	var lake_field_source: String = FileAccess.get_file_as_string("res://gdextension/src/lake_field.cpp")
	_assert(
		not lake_field_header.contains("float p_amplitude"),
		"L7 fbm_shore signature must drop amplitude and return dimensionless FBM."
	)
	_assert(
		lake_field_source.contains("return world_utils::clamp_value(fbm, -1.0f, 1.0f);"),
		"L7 fbm_shore must return dimensionless FBM in [-1, 1]."
	)
	_assert(
		not lake_field_source.contains("* std::max(0.0f, p_amplitude)"),
		"L7 fbm_shore must not multiply by amplitude internally."
	)

	var world_core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		world_core_source.contains("fbm_unit * p_lake_settings.shore_warp_amplitude * basin_depth"),
		"WorldCore must apply shore_warp as fbm_unit * shore_warp_amplitude * basin_depth."
	)
	var world_prepass_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_prepass.cpp")
	_assert(
		world_prepass_source.contains("fbm_unit * lake_settings_.shore_warp_amplitude * basin_depth"),
		"Overview lake classification must apply shore_warp as a basin-depth fraction."
	)

	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("worldgen_settings.lakes.connectivity is required for world_version >= 42"),
		"WorldStreamer must fail loudly when current-version saves omit worldgen_settings.lakes.connectivity."
	)

	var new_game_source: String = FileAccess.get_file_as_string("res://scenes/ui/new_game_panel.gd")
	_assert(
		new_game_source.contains("\"property\": \"connectivity\"") and
				new_game_source.contains("\"label_key\": \"UI_WORLDGEN_LAKES_CONNECTIVITY\"") and
				new_game_source.contains("\"step\": 0.05"),
		"New-game lake sliders must expose LakeGenSettings.connectivity with the documented step."
	)

	var ru_locale: String = FileAccess.get_file_as_string("res://locale/ru/messages.po")
	var en_locale: String = FileAccess.get_file_as_string("res://locale/en/messages.po")
	_assert(
		ru_locale.contains("UI_WORLDGEN_LAKES_CONNECTIVITY") and
				ru_locale.contains("СВЯЗНОСТЬ ОЗЁР") and
				ru_locale.contains("Доля глубины бассейна"),
		"Russian locale must cover L7 lake connectivity and basin-depth shore-warp copy."
	)
	_assert(
		en_locale.contains("UI_WORLDGEN_LAKES_CONNECTIVITY") and
				en_locale.contains("LAKE CONNECTIVITY") and
				en_locale.contains("Fraction of basin depth"),
		"English locale must cover L7 lake connectivity and basin-depth shore-warp copy."
	)

func _assert_l5_native_lake_snapshot_is_deterministic() -> void:
	var first: Dictionary = _build_lake_snapshot(20260504, 0.4)
	var second: Dictionary = _build_lake_snapshot(20260504, 0.4)
	_assert(
		_packed_int32_equal(first.get("lake_id", PackedInt32Array()), second.get("lake_id", PackedInt32Array())),
		"Same seed/version/settings must produce identical lake_id arrays."
	)
	_assert(
		_packed_int32_equal(
			first.get("lake_water_level_q16", PackedInt32Array()),
			second.get("lake_water_level_q16", PackedInt32Array())
		),
		"Same seed/version/settings must produce identical lake_water_level_q16 arrays."
	)
	var large_started_ms: int = Time.get_ticks_msec()
	var large: Dictionary = _build_lake_snapshot(20260504, 0.4, WorldBoundsSettings.PRESET_LARGE)
	var large_wall_time_ms: int = Time.get_ticks_msec() - large_started_ms
	var large_compute_time_ms: float = float(large.get("compute_time_ms", 999999.0))
	_assert(
		large_compute_time_ms <= 900.0,
		"Large preset WorldPrePass substrate compute must stay <= 900 ms; native compute_time_ms=%.2f wall_time_ms=%d." % [
			large_compute_time_ms,
			large_wall_time_ms,
		]
	)

func _assert_l6_native_chunk_packets_are_deterministic() -> void:
	var first_packets: Array = _build_chunk_packets(20260506, 0.4, 1.0, PackedVector2Array([Vector2(0, 0), Vector2(1, 0)]))
	var second_packets: Array = _build_chunk_packets(20260506, 0.4, 1.0, PackedVector2Array([Vector2(0, 0), Vector2(1, 0)]))
	_assert(first_packets.size() == second_packets.size(), "Same L6 packet request must return the same packet count.")
	for index: int in first_packets.size():
		var first: Dictionary = first_packets[index] as Dictionary
		var second: Dictionary = second_packets[index] as Dictionary
		_assert(
			_packed_int32_equal(first.get("terrain_ids", PackedInt32Array()), second.get("terrain_ids", PackedInt32Array())),
			"Same seed/version/settings must produce identical L6 terrain_ids arrays."
		)
		_assert(
			_packed_byte_equal(first.get("walkable_flags", PackedByteArray()), second.get("walkable_flags", PackedByteArray())),
			"Same seed/version/settings must produce identical L6 walkable_flags arrays."
		)
		_assert(
			_packed_byte_equal(first.get("lake_flags", PackedByteArray()), second.get("lake_flags", PackedByteArray())),
			"Same seed/version/settings must produce identical L6 lake_flags arrays."
		)

	var no_lake_packets: Array = _build_chunk_packets(20260506, 0.4, 0.0, PackedVector2Array([Vector2(0, 0)]))
	if not no_lake_packets.is_empty():
		var packet: Dictionary = no_lake_packets[0] as Dictionary
		var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray())
		for flag: int in lake_flags:
			_assert(flag == 0, "Lake density 0.0 must not emit lake_flags in generated chunk packets.")

func _assert_l6_spawn_tiles_are_not_published_water() -> void:
	for seed: int in [20260506, 20260507, 20260508]:
		var world_core: Object = ClassDB.instantiate("WorldCore")
		_assert(world_core != null, "WorldCore must be available for native spawn-water regression checks.")
		if world_core == null:
			continue
		var settings_packed: PackedFloat32Array = _build_settings_packed(0.4, 1.0)
		var spawn_result: Variant = world_core.call(
			"resolve_world_foundation_spawn_tile",
			seed,
			WorldRuntimeConstants.WORLD_VERSION,
			settings_packed
		)
		_assert(spawn_result is Dictionary, "WorldCore spawn result must be a Dictionary.")
		if spawn_result is not Dictionary:
			continue
		var spawn_dict: Dictionary = spawn_result as Dictionary
		_assert(bool(spawn_dict.get("success", false)), "WorldCore must resolve a spawn tile for L6 water checks.")
		if not bool(spawn_dict.get("success", false)):
			continue
		var spawn_tile: Vector2i = spawn_dict.get("spawn_tile", Vector2i.ZERO)
		var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn_tile)
		var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(spawn_tile)
		var packets: Variant = world_core.call(
			"generate_chunk_packets_batch",
			seed,
			PackedVector2Array([Vector2(chunk_coord.x, chunk_coord.y)]),
			WorldRuntimeConstants.WORLD_VERSION,
			settings_packed
		)
		_assert(packets is Array and not (packets as Array).is_empty(), "WorldCore must publish the spawn chunk for L6 water checks.")
		if packets is not Array or (packets as Array).is_empty():
			continue
		var packet: Dictionary = (packets as Array)[0] as Dictionary
		var tile_index: int = WorldRuntimeConstants.local_to_index(local_coord)
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array())
		var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray())
		_assert(tile_index >= 0 and tile_index < terrain_ids.size(), "Spawn tile index must be inside terrain_ids.")
		_assert(tile_index >= 0 and tile_index < lake_flags.size(), "Spawn tile index must be inside lake_flags.")
		if tile_index < 0 or tile_index >= terrain_ids.size() or tile_index >= lake_flags.size():
			continue
		var terrain_id: int = terrain_ids[tile_index]
		var lake_flag: int = lake_flags[tile_index]
		_assert(
			terrain_id != WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW and
					terrain_id != WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP and
					(lake_flag & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) == 0,
			"L6 spawn resolver must not emit a tile that becomes water in the published chunk."
		)

func _build_lake_snapshot(
	seed: int,
	connectivity: float,
	world_preset: StringName = WorldBoundsSettings.PRESET_SMALL
) -> Dictionary:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native lake regression checks.")
	if world_core == null:
		return {}
	var settings_packed: PackedFloat32Array = _build_settings_packed(connectivity, 1.0, world_preset)
	var spawn_result: Variant = world_core.call(
		"resolve_world_foundation_spawn_tile",
		seed,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	_assert(spawn_result is Dictionary, "WorldCore spawn prepass result must be a Dictionary.")
	if spawn_result is Dictionary:
		_assert(bool((spawn_result as Dictionary).get("success", false)), "WorldCore must build a valid foundation snapshot.")
	var snapshot: Variant = world_core.call("get_world_foundation_snapshot", 0, 1)
	_assert(snapshot is Dictionary, "WorldCore debug snapshot must be available after prepass build.")
	if snapshot is not Dictionary:
		return {}
	var snapshot_dict: Dictionary = snapshot as Dictionary
	_assert(snapshot_dict.has("lake_id"), "WorldCore debug snapshot must expose lake_id.")
	_assert(snapshot_dict.has("lake_water_level_q16"), "WorldCore debug snapshot must expose lake_water_level_q16.")
	return snapshot_dict

func _build_chunk_packets(seed: int, connectivity: float, density: float, coords: PackedVector2Array) -> Array:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native chunk packet regression checks.")
	if world_core == null:
		return []
	var settings_packed: PackedFloat32Array = _build_settings_packed(connectivity, density)
	var packets: Variant = world_core.call(
		"generate_chunk_packets_batch",
		seed,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	_assert(packets is Array, "WorldCore chunk packet generation must return an Array.")
	if packets is Array:
		return packets as Array
	return []

func _build_settings_packed(
	connectivity: float,
	density: float = 1.0,
	world_preset: StringName = WorldBoundsSettings.PRESET_SMALL
) -> PackedFloat32Array:
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.for_preset(world_preset)
	var mountain_settings: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		world_bounds
	)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lake_settings.density = density
	lake_settings.scale = 256.0
	lake_settings.connectivity = connectivity
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	return lake_settings.write_to_settings_packed(packed)

func _packed_int32_equal(lhs: PackedInt32Array, rhs: PackedInt32Array) -> bool:
	if lhs.size() != rhs.size():
		return false
	for index: int in lhs.size():
		if lhs[index] != rhs[index]:
			return false
	return true

func _packed_byte_equal(lhs: PackedByteArray, rhs: PackedByteArray) -> bool:
	if lhs.size() != rhs.size():
		return false
	for index: int in lhs.size():
		if lhs[index] != rhs[index]:
			return false
	return true

func _assert_water_seam_refresh_contract() -> void:
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	var water_tile_set: TileSet = WorldTileSetFactory.get_water_tile_set()
	_assert(water_tile_set != null, "WorldTileSetFactory.get_water_tile_set() must resolve an existing water TileSet.")
	_assert(
		WorldTileSetFactory.get_water_source_id(WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW) >= 0,
		"Water TileSet must expose a light source for shallow lake beds."
	)
	_assert(
		WorldTileSetFactory.get_water_source_id(WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP) >= 0,
		"Water TileSet must expose a dark source for deep lake beds."
	)
	_assert(
		chunk_view_source.contains("func set_water_neighbour_resolver"),
		"ChunkView must accept a bounded neighbour-water resolver for cross-chunk water autotile checks."
	)
	_assert(
		chunk_view_source.contains("func refresh_water_edge_towards"),
		"ChunkView must expose edge-only water seam refresh."
	)
	_assert(
		chunk_view_source.contains("_water_neighbour_resolver.call"),
		"ChunkView out-of-chunk water neighbour checks must use the resolver."
	)
	_assert(
		streamer_source.contains("func _handle_water_chunk_published"),
		"WorldStreamer must refresh water seams after chunk publish."
	)
	_assert(
		streamer_source.contains("refresh_water_edge_towards"),
		"WorldStreamer water seam refresh must re-evaluate edge tiles only."
	)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
