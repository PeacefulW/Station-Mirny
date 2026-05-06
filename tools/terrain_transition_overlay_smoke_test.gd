extends SceneTree

const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DefaultFoundationGenSettings = preload("res://data/balance/foundation_gen_settings.tres")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const DefaultMountainGenSettings = preload("res://data/balance/mountain_gen_settings.tres")

var _failed: bool = false

func _init() -> void:
	_assert_static_contract()
	_assert_native_packet_fields()
	_assert_chunk_view_renders_transition_overlay()

	if _failed:
		quit(1)
		return
	print("terrain_transition_overlay_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var world_core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		world_core_source.contains("base_variant_indices"),
		"WorldCore must emit base_variant_indices in ChunkPacketV1."
	)
	_assert(
		world_core_source.contains("transition_overlay_indices"),
		"WorldCore must emit transition_overlay_indices in ChunkPacketV1."
	)
	_assert(
		world_core_source.contains("packet[\"base_variant_indices\"]"),
		"ChunkPacketV1 must include base_variant_indices at the native packet boundary."
	)
	_assert(
		world_core_source.contains("packet[\"transition_overlay_indices\"]"),
		"ChunkPacketV1 must include transition_overlay_indices at the native packet boundary."
	)
	_assert(
		world_core_source.contains("TERRAIN_MOUNTAIN_FOOT") and world_core_source.contains("TERRAIN_MOUNTAIN_WALL"),
		"Transition overlay generation must be able to exclude mountain terrain."
	)

	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	_assert(
		chunk_view_source.contains("_transition_layer"),
		"ChunkView must own a dedicated _transition_layer."
	)
	_assert(
		chunk_view_source.contains("_pending_base_variant_indices"),
		"ChunkView must retain base_variant_indices during publish/apply."
	)
	_assert(
		chunk_view_source.contains("_pending_transition_overlay_indices"),
		"ChunkView must retain transition_overlay_indices during publish/apply."
	)

	var packet_schema_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/packet_schemas.md")
	_assert(
		packet_schema_source.contains("base_variant_indices"),
		"packet_schemas.md must document base_variant_indices."
	)
	_assert(
		packet_schema_source.contains("transition_overlay_indices"),
		"packet_schemas.md must document transition_overlay_indices."
	)

	var constants_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_runtime_constants.gd")
	_assert(
		constants_source.contains("const WORLD_VERSION: int = 44"),
		"WORLD_VERSION must remain 44 for visual-only transition overlay work."
	)

func _assert_native_packet_fields() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native transition overlay packet checks.")
	if world_core == null:
		return
	var seed: int = 240505
	var packets: Variant = world_core.call(
		"generate_chunk_packets_batch",
		seed,
		[Vector2i.ZERO],
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed()
	)
	_assert(packets is Array and (packets as Array).size() == 1, "WorldCore must return one packet for one requested chunk.")
	if not (packets is Array) or (packets as Array).is_empty():
		return
	var packet: Dictionary = (packets as Array)[0] as Dictionary
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var base_variant_indices: PackedByteArray = packet.get("base_variant_indices", PackedByteArray()) as PackedByteArray
	var transition_overlay_indices: PackedInt32Array = packet.get("transition_overlay_indices", PackedInt32Array()) as PackedInt32Array
	_assert(
		base_variant_indices.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT,
		"WorldCore native packet must publish 256 base_variant_indices."
	)
	_assert(
		transition_overlay_indices.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT,
		"WorldCore native packet must publish 256 transition_overlay_indices."
	)
	for index: int in range(base_variant_indices.size()):
		_assert(
			int(base_variant_indices[index]) >= 0 and int(base_variant_indices[index]) < Autotile47.DEFAULT_VARIANT_COUNT,
			"base_variant_indices must stay inside the authored variant bank."
		)
		var tile_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		_assert(
			int(base_variant_indices[index]) == Autotile47.pick_variant(tile_coord, seed),
			"base_variant_indices must be deterministic from tile coord and world seed."
		)
		if index < terrain_ids.size() and _is_mountain_terrain(int(terrain_ids[index])):
			_assert(
				index < transition_overlay_indices.size() and int(transition_overlay_indices[index]) == 0,
				"mountain terrain must not emit transition overlays."
			)

func _assert_chunk_view_renders_transition_overlay() -> void:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var terrain_atlas_indices := PackedInt32Array()
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var base_variant_indices := PackedByteArray()
	base_variant_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var transition_overlay_indices := PackedInt32Array()
	transition_overlay_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_atlas_indices := PackedInt32Array()
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)

	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		walkable_flags[index] = 1
		base_variant_indices[index] = index % Autotile47.DEFAULT_VARIANT_COUNT

	var overlay_coord := Vector2i(2, 2)
	var overlay_index: int = WorldRuntimeConstants.local_to_index(overlay_coord)
	var signature_code: int = Autotile47.build_signature_code(
		true,
		true,
		false,
		false,
		false,
		false,
		true,
		true
	)
	var zero_based_overlay_atlas: int = Autotile47.build_atlas_index(signature_code, 2)
	transition_overlay_indices[overlay_index] = zero_based_overlay_atlas + 1

	var packet: Dictionary = {
		"chunk_coord": Vector2i.ZERO,
		"world_seed": 77,
		"world_version": WorldRuntimeConstants.WORLD_VERSION,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"base_variant_indices": base_variant_indices,
		"transition_overlay_indices": transition_overlay_indices,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

	var chunk_view := ChunkView.new()
	get_root().add_child(chunk_view)
	chunk_view.configure(Vector2i.ZERO)
	chunk_view.begin_apply(packet)
	while chunk_view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass

	var transition_layer: TileMapLayer = chunk_view.get("_transition_layer") as TileMapLayer
	_assert(
		transition_layer != null and is_instance_valid(transition_layer),
		"ChunkView must create a valid transition TileMapLayer."
	)
	if transition_layer == null:
		chunk_view.queue_free()
		return

	_assert(
		transition_layer.get_cell_source_id(Vector2i.ZERO) == -1,
		"transition_overlay_indices value 0 must clear the transition cell."
	)
	_assert(
		transition_layer.get_cell_source_id(overlay_coord) >= 0,
		"non-zero transition_overlay_indices must render a transition cell."
	)
	_assert(
		transition_layer.get_cell_atlas_coords(overlay_coord) == Autotile47.atlas_index_to_coords(zero_based_overlay_atlas),
		"transition overlay field must decode to the shared 47-case mask atlas coordinates."
	)
	chunk_view.queue_free()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true

func _build_settings_packed() -> PackedFloat32Array:
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var mountain_settings: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		world_bounds
	)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lake_settings.density = 0.0
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	return lake_settings.write_to_settings_packed(packed)

func _is_mountain_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
