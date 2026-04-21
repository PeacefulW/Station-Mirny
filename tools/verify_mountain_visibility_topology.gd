extends SceneTree

const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const MountainVisibilityTopology = preload("res://core/systems/world/mountain_visibility_topology.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const MOUNTAIN_COVER_SHADER = preload("res://assets/shaders/mountain_cover_overlay.gdshader")

var _failures: PackedStringArray = PackedStringArray()

func _init() -> void:
	_run()

func _run() -> void:
	_test_settings_roundtrip()
	_test_roof_tile_set_bundle()
	_test_topology_visibility_rules()
	if _failures.is_empty():
		print("mountain_visibility_topology: OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)

func _test_settings_roundtrip() -> void:
	var settings := MountainGenSettings.new()
	settings.density = 0.42
	settings.scale = 640.0
	settings.continuity = 0.71
	settings.ruggedness = 0.33
	settings.anchor_cell_size = 160
	settings.gravity_radius = 80
	settings.foot_band = 0.12
	settings.interior_margin = 2
	settings.latitude_influence = -0.25
	var restored: MountainGenSettings = MountainGenSettings.from_save_dictionary(
		settings.to_save_dictionary(),
		MountainGenSettings.hard_coded_defaults()
	)
	_expect(is_equal_approx(restored.density, settings.density), "settings density round-trip mismatch")
	_expect(is_equal_approx(restored.scale, settings.scale), "settings scale round-trip mismatch")
	_expect(is_equal_approx(restored.continuity, settings.continuity), "settings continuity round-trip mismatch")
	_expect(is_equal_approx(restored.ruggedness, settings.ruggedness), "settings ruggedness round-trip mismatch")
	_expect(restored.anchor_cell_size == settings.anchor_cell_size, "settings anchor_cell_size round-trip mismatch")
	_expect(restored.gravity_radius == settings.gravity_radius, "settings gravity_radius round-trip mismatch")
	_expect(is_equal_approx(restored.foot_band, settings.foot_band), "settings foot_band round-trip mismatch")
	_expect(restored.interior_margin == settings.interior_margin, "settings interior_margin round-trip mismatch")
	_expect(is_equal_approx(restored.latitude_influence, settings.latitude_influence), "settings latitude_influence round-trip mismatch")

func _test_topology_visibility_rules() -> void:
	var chunk_coord := Vector2i.ZERO
	var packet := _build_packet(
		chunk_coord,
		[
			Vector2i(2, 2),
			Vector2i(3, 2),
			Vector2i(4, 2),
			Vector2i(5, 3),
			Vector2i(6, 3),
			Vector2i(8, 3),
		],
		[
			Vector2i(2, 1),
			Vector2i(3, 1),
			Vector2i(4, 1),
			Vector2i(5, 1),
			Vector2i(5, 2),
			Vector2i(6, 2),
			Vector2i(8, 2),
			Vector2i(2, 3),
			Vector2i(3, 3),
			Vector2i(4, 3),
		]
	)
	var opening_tiles := {
		Vector2i(2, 2): true,
		Vector2i(8, 3): true,
	}
	var topology := MountainVisibilityTopology.new()
	topology.rebuild_from_loaded_world(
		{chunk_coord: packet},
		func(tile_coord: Vector2i) -> bool:
			return opening_tiles.has(tile_coord)
	)

	var entrance_state: Dictionary = topology.get_tile_state(Vector2i(2, 2))
	var primary_state: Dictionary = topology.get_tile_state(Vector2i(4, 2))
	var diagonal_state: Dictionary = topology.get_tile_state(Vector2i(5, 3))
	var foreign_opening_state: Dictionary = topology.get_tile_state(Vector2i(8, 3))
	_expect(int(entrance_state.get("component_id", 0)) > 0, "entrance tile must belong to a cavity component")
	_expect(int(entrance_state.get("opening_id", 0)) > 0, "entrance tile must resolve an opening id")
	_expect(bool(entrance_state.get("visible_opening", false)), "outside state must mark the real opening visible")
	_expect(int(primary_state.get("component_id", 0)) > 0, "primary cavity tile must resolve a component id")
	_expect(int(diagonal_state.get("component_id", 0)) > 0, "secondary cavity tile must resolve a component id")
	_expect(bool(foreign_opening_state.get("visible_opening", false)), "outside state must mark every real opening visible")
	_expect(
		int(primary_state.get("component_id", 0)) != int(diagonal_state.get("component_id", 0)),
		"diagonal-only cavity contact must not merge components"
	)

	topology.set_active_component(101, int(primary_state.get("component_id", 0)), Vector2i(2, 2))
	entrance_state = topology.get_tile_state(Vector2i(2, 2))
	foreign_opening_state = topology.get_tile_state(Vector2i(8, 3))
	_expect(bool(entrance_state.get("visible_opening", false)), "current cavity opening must stay visible while inside")
	_expect(bool(foreign_opening_state.get("visible_opening", false)), "opening tiles remain globally visible in the current roof-hole path")
	var cover_masks: Dictionary = topology.build_cover_masks_for_chunk(
		chunk_coord,
		packet,
		func(tile_coord: Vector2i) -> bool:
			return opening_tiles.has(tile_coord)
	)
	var mask: PackedByteArray = cover_masks.get(101, PackedByteArray()) as PackedByteArray
	_expect(mask.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "cover mask must cover one full chunk")
	_expect(mask[WorldRuntimeConstants.local_to_index(Vector2i(3, 1))] == 255, "boundary wall shell must open with the active cavity")
	_expect(mask[WorldRuntimeConstants.local_to_index(Vector2i(5, 1))] == 255, "diagonal wall shell must open for 47-tile notch visibility")
	_expect(mask[WorldRuntimeConstants.local_to_index(Vector2i(3, 2))] == 255, "active cavity interior must open immediately")
	_expect(mask[WorldRuntimeConstants.local_to_index(Vector2i(4, 2))] == 255, "connected orthogonal cavity tile must stay open")
	_expect(mask[WorldRuntimeConstants.local_to_index(Vector2i(8, 2))] == 255, "global opening shell stays visible in the current roof-hole path")
	_expect(mask[WorldRuntimeConstants.local_to_index(Vector2i(8, 3))] == 255, "global opening tiles stay visible in the current roof-hole path")
	_expect(mask[WorldRuntimeConstants.local_to_index(Vector2i(5, 3))] == 0, "separate cavity must stay concealed")

	var lingering_change: Dictionary = topology.set_active_component(0, 0, Vector2i(0, 0))
	_expect(bool(lingering_change.get("changed", false)), "leaving a cavity must keep presented-component state for conceal fade")
	var lingering_masks: Dictionary = topology.build_cover_masks_for_chunk(
		chunk_coord,
		packet,
		func(tile_coord: Vector2i) -> bool:
			return opening_tiles.has(tile_coord)
	)
	var lingering_mask: PackedByteArray = lingering_masks.get(101, PackedByteArray()) as PackedByteArray
	_expect(lingering_mask[WorldRuntimeConstants.local_to_index(Vector2i(3, 1))] == 255, "conceal fade must keep shell visible until fade completes")
	_expect(lingering_mask[WorldRuntimeConstants.local_to_index(Vector2i(3, 2))] == 255, "conceal fade must keep cavity mask open until fade completes")
	var cleared_change: Dictionary = topology.clear_lingering_component_for_mountain(101)
	_expect(bool(cleared_change.get("changed", false)), "clearing lingering component must update presented cover state")
	var cleared_masks: Dictionary = topology.build_cover_masks_for_chunk(
		chunk_coord,
		packet,
		func(tile_coord: Vector2i) -> bool:
			return opening_tiles.has(tile_coord)
	)
	var cleared_mask: PackedByteArray = cleared_masks.get(101, PackedByteArray()) as PackedByteArray
	_expect(cleared_mask[WorldRuntimeConstants.local_to_index(Vector2i(2, 2))] == 255, "outside state must keep the current opening visible")
	_expect(cleared_mask[WorldRuntimeConstants.local_to_index(Vector2i(2, 1))] == 255, "opening shell must remain visible outside")
	_expect(cleared_mask[WorldRuntimeConstants.local_to_index(Vector2i(3, 1))] == 255, "opening diagonal shell must remain visible outside")
	_expect(cleared_mask[WorldRuntimeConstants.local_to_index(Vector2i(8, 3))] == 255, "outside state must keep other real openings visible")
	_expect(cleared_mask[WorldRuntimeConstants.local_to_index(Vector2i(8, 2))] == 255, "outside state must reveal shell for every real opening")
	_expect(cleared_mask[WorldRuntimeConstants.local_to_index(Vector2i(3, 2))] == 0, "non-opening cavity floor must remain concealed outside")
	_expect(cleared_mask[WorldRuntimeConstants.local_to_index(Vector2i(4, 2))] == 0, "non-opening cavity tiles must close after conceal completes")

	topology.apply_walkable_updates(
		[
			{
				"ready": true,
				"walkable": true,
				"tile_coord": Vector2i(5, 2),
				"chunk_coord": chunk_coord,
				"local_coord": Vector2i(5, 2),
				"terrain_id": WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
				"mountain_id": 101,
				"mountain_flags": WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR,
				"is_interior": true,
				"is_opening": false,
			}
		]
	)
	var bridged_state: Dictionary = topology.get_tile_state(Vector2i(5, 2))
	var merged_state: Dictionary = topology.get_tile_state(Vector2i(5, 3))
	_expect(int(bridged_state.get("component_id", 0)) > 0, "newly excavated bridge tile must resolve a component id immediately")
	_expect(
		int(bridged_state.get("component_id", 0)) == int(merged_state.get("component_id", 0)),
		"orthogonal bridge must merge previously separate cavities"
	)

func _test_roof_tile_set_bundle() -> void:
	var roof_bundle: Dictionary = WorldTileSetFactory.create_roof_tile_set_bundle()
	var tile_set: TileSet = roof_bundle.get("tile_set", null) as TileSet
	var material: ShaderMaterial = roof_bundle.get("material", null) as ShaderMaterial
	var source_id: int = int(roof_bundle.get("source_id", -1))
	_expect(tile_set != null, "roof tile set bundle must provide a TileSet")
	_expect(material != null, "roof tile set bundle must provide a ShaderMaterial")
	_expect(source_id >= 0, "roof tile set bundle must provide a valid source id")
	if tile_set == null or material == null or source_id < 0:
		return
	var source: TileSetSource = tile_set.get_source(source_id)
	var atlas_source: TileSetAtlasSource = source as TileSetAtlasSource
	_expect(atlas_source != null, "roof tile set source must be an atlas source")
	if atlas_source == null:
		return
	var tile_data: TileData = atlas_source.get_tile_data(Vector2i.ZERO, 0)
	_expect(tile_data != null, "roof tile set source must expose tile data")
	if tile_data == null:
		return
	_expect(tile_data.material == material, "roof tile tiles must use the dedicated cover material")
	_expect(material.shader == MOUNTAIN_COVER_SHADER, "roof tile material must use the mountain cover shader")

func _build_packet(
	chunk_coord: Vector2i,
	walkable_tiles: Array[Vector2i],
	solid_mountain_tiles: Array[Vector2i] = []
) -> Dictionary:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var terrain_atlas_indices := PackedInt32Array()
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_atlas_indices := PackedInt32Array()
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for local_coord: Vector2i in solid_mountain_tiles:
		var solid_index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[solid_index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		walkable_flags[solid_index] = 0
		mountain_ids[solid_index] = 101
		mountain_flags[solid_index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	for local_coord: Vector2i in walkable_tiles:
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_DUG
		walkable_flags[index] = 1
		mountain_ids[index] = 101
		mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	return {
		"chunk_coord": chunk_coord,
		"world_seed": 1,
		"world_version": 4,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
