extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldDiffStore = preload("res://core/systems/world/world_diff_store.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DefaultFoundationGenSettings = preload("res://data/balance/foundation_gen_settings.tres")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const DefaultMountainGenSettings = preload("res://data/balance/mountain_gen_settings.tres")

const DECAL_INSTANCE_STRIDE: int = 5
const DECAL_SAFETY_CAP: int = 500
const DECAL_ATLAS_CELL_COUNT: int = 16

var _failed: bool = false

func _init() -> void:
	_assert_static_contract()
	_assert_native_packet_fields()
	_assert_chunk_view_renders_and_reuses_decal_layer()
	_assert_chunk_diff_round_trip_unchanged()

	if _failed:
		quit(1)
		return
	print("terrain_decal_layer_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var world_core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		world_core_source.contains("decal_density"),
		"WorldCore must delegate terrain decal placement to native decal_density code."
	)
	_assert(
		world_core_source.contains("packet[\"decal_instances\"]"),
		"ChunkPacketV1 must include decal_instances at the native packet boundary."
	)
	_assert(
		world_core_source.contains("packet[\"decal_instance_count\"]"),
		"ChunkPacketV1 must include decal_instance_count at the native packet boundary."
	)

	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	_assert(chunk_view_source.contains("_decal_layer"), "ChunkView must own one _decal_layer.")
	_assert(
		chunk_view_source.contains("get_decal_render_debug"),
		"ChunkView must expose a local decal debug surface for smoke verification."
	)
	_assert(
		chunk_view_source.contains("MultiMeshInstance2D"),
		"ChunkView terrain decal rendering must use MultiMeshInstance2D, not node-per-decal sprites."
	)

	var constants_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_runtime_constants.gd")
	_assert(
		constants_source.contains("const WORLD_VERSION: int = 44"),
		"WORLD_VERSION must remain 44 for visual-only decal layer work."
	)

	var diff_store_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_diff_store.gd")
	_assert(
		not diff_store_source.contains("decal_instances") and not diff_store_source.contains("decal_instance_count"),
		"ChunkDiffFile must not persist terrain decal packet data."
	)

	var packet_schema_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/packet_schemas.md")
	_assert(packet_schema_source.contains("decal_instances"), "packet_schemas.md must document decal_instances.")
	_assert(packet_schema_source.contains("decal_instance_count"), "packet_schemas.md must document decal_instance_count.")

	var presentation_spec_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/world/terrain_hybrid_presentation.md")
	_assert(
		presentation_spec_source.contains("terrain decal"),
		"terrain_hybrid_presentation.md must document the terrain decal presentation layer."
	)

	var runtime_spec_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/world/world_runtime.md")
	_assert(
		runtime_spec_source.contains("decal_instances"),
		"world_runtime.md must document that terrain decals are visual-only derived packet data."
	)

func _assert_native_packet_fields() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native terrain decal packet checks.")
	if world_core == null:
		return
	var packets_a: Variant = world_core.call(
		"generate_chunk_packets_batch",
		240505,
		PackedVector2Array([Vector2(0, 0)]),
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed()
	)
	var packets_b: Variant = world_core.call(
		"generate_chunk_packets_batch",
		240505,
		PackedVector2Array([Vector2(0, 0)]),
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed()
	)
	_assert(packets_a is Array and (packets_a as Array).size() == 1, "WorldCore must return one packet for one requested chunk.")
	_assert(packets_b is Array and (packets_b as Array).size() == 1, "WorldCore must return one deterministic comparison packet.")
	if packets_a is not Array or packets_b is not Array or (packets_a as Array).is_empty() or (packets_b as Array).is_empty():
		return
	var packet_a: Dictionary = (packets_a as Array)[0] as Dictionary
	var packet_b: Dictionary = (packets_b as Array)[0] as Dictionary
	_assert(packet_a.has("decal_instances"), "ChunkPacketV1 must carry decal_instances even when empty.")
	_assert(packet_a.has("decal_instance_count"), "ChunkPacketV1 must carry decal_instance_count even when zero.")
	if not packet_a.has("decal_instances") or not packet_a.has("decal_instance_count"):
		return
	var decal_instances_a: PackedFloat32Array = packet_a.get("decal_instances", PackedFloat32Array()) as PackedFloat32Array
	var decal_instances_b: PackedFloat32Array = packet_b.get("decal_instances", PackedFloat32Array()) as PackedFloat32Array
	var decal_instance_count: int = int(packet_a.get("decal_instance_count", -1))
	_assert(
		decal_instances_a.size() == decal_instance_count * DECAL_INSTANCE_STRIDE,
		"decal_instances must use five float records: atlas_index, world_offset_x, world_offset_y, rotation_q16, scale_q16."
	)
	_assert(decal_instance_count <= DECAL_SAFETY_CAP, "decal_instance_count must stay under the per-chunk safety cap.")
	_assert_packed_float_arrays_equal(
		decal_instances_a,
		decal_instances_b,
		"Terrain decal placement must be deterministic from world position and world seed."
	)
	_assert_native_decal_semantics(world_core)

func _assert_native_decal_semantics(world_core: Object) -> void:
	var coords := PackedVector2Array()
	for y: int in range(-1, 3):
		for x: int in range(-1, 3):
			coords.append(Vector2(x, y))
	var packets: Variant = world_core.call(
		"generate_chunk_packets_batch",
		240505,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed()
	)
	_assert(packets is Array, "WorldCore must return packet array for decal semantic search.")
	if packets is not Array:
		return
	var found_decal_packet: bool = false
	for packet_variant: Variant in packets:
		var packet: Dictionary = packet_variant as Dictionary
		var count: int = int(packet.get("decal_instance_count", 0))
		var instances: PackedFloat32Array = packet.get("decal_instances", PackedFloat32Array()) as PackedFloat32Array
		_assert(instances.size() == count * DECAL_INSTANCE_STRIDE, "Generated decal packet must keep decal_instance_count aligned with packed float size.")
		_assert(count <= DECAL_SAFETY_CAP, "Generated decal packet must be bounded by the authored safety cap.")
		if count <= 0:
			continue
		found_decal_packet = true
		var terrain_ids: PackedInt32Array = packet["terrain_ids"] as PackedInt32Array
		var walkable_flags: PackedByteArray = packet["walkable_flags"] as PackedByteArray
		for instance_index: int in range(count):
			var offset: int = instance_index * DECAL_INSTANCE_STRIDE
			var atlas_index: int = int(instances[offset])
			var world_offset_x: float = float(instances[offset + 1])
			var world_offset_y: float = float(instances[offset + 2])
			var rotation_q16: int = int(instances[offset + 3])
			var scale_q16: int = int(instances[offset + 4])
			_assert(atlas_index >= 0 and atlas_index < DECAL_ATLAS_CELL_COUNT, "Terrain decal atlas index must stay inside the 16-cell atlas.")
			var chunk_pixel_size: int = WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX
			_assert(world_offset_x >= 0.0 and world_offset_x < chunk_pixel_size, "Terrain decal x offset must stay inside the emitting chunk.")
			_assert(world_offset_y >= 0.0 and world_offset_y < chunk_pixel_size, "Terrain decal y offset must stay inside the emitting chunk.")
			_assert(rotation_q16 >= 0 and rotation_q16 < 65536, "Terrain decal rotation_q16 must encode one normalized turn.")
			_assert(scale_q16 > 0, "Terrain decal scale_q16 must be positive.")
			var local_coord := Vector2i(
				int(floor(world_offset_x / float(WorldRuntimeConstants.TILE_SIZE_PX))),
				int(floor(world_offset_y / float(WorldRuntimeConstants.TILE_SIZE_PX)))
			)
			if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
				continue
			var terrain_index: int = WorldRuntimeConstants.local_to_index(local_coord)
			_assert(int(walkable_flags[terrain_index]) != 0, "Terrain decals must only be placed on walkable terrain.")
			_assert(not _is_decal_forbidden_terrain(int(terrain_ids[terrain_index])), "Terrain decals must not be placed on mountain wall/foot or deep lake tiles.")
	_assert(found_decal_packet, "Native decal search must find at least one generated decal packet in the first biome.")

func _assert_chunk_view_renders_and_reuses_decal_layer() -> void:
	var view := ChunkView.new()
	get_root().add_child(view)
	view.configure(Vector2i.ZERO)
	var packet: Dictionary = _build_plain_packet()
	packet["decal_instances"] = PackedFloat32Array([
		0.0, 32.0, 32.0, 0.0, 65536.0,
		12.0, 96.0, 32.0, 16384.0, 65536.0,
	])
	packet["decal_instance_count"] = 2
	view.begin_apply(packet)
	while view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	if not view.has_method("get_decal_render_debug"):
		_assert(false, "ChunkView must expose get_decal_render_debug().")
		view.queue_free()
		return
	var debug: Dictionary = view.call("get_decal_render_debug") as Dictionary
	var layer_id: int = int(debug.get("layer_instance_id", 0))
	_assert(bool(debug.get("has_layer", false)), "ChunkView must create a terrain decal MultiMeshInstance2D.")
	_assert(int(debug.get("z_index", -1)) == 1, "Terrain decal layer must render above base terrain and below transition/water/silhouette/roof.")
	_assert(int(debug.get("instance_count", -1)) == 2, "Two decal records must render two MultiMesh instances.")
	_assert(layer_id != 0, "Terrain decal debug must expose the reused layer instance id.")

	view.begin_apply(packet)
	while view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	var republish_debug: Dictionary = view.call("get_decal_render_debug") as Dictionary
	_assert(
		int(republish_debug.get("layer_instance_id", 0)) == layer_id,
		"ChunkView must reuse the same terrain decal MultiMeshInstance2D across chunk republishes."
	)
	_assert(int(republish_debug.get("instance_count", -1)) == 2, "Republish must keep the packet decal instance count.")

	view.apply_runtime_cell(
		Vector2i(2, 2),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		0,
		0
	)
	var runtime_debug: Dictionary = view.call("get_decal_render_debug") as Dictionary
	_assert(
		int(runtime_debug.get("instance_count", -1)) == 2,
		"Interactive runtime tile patches must not synchronously recompute the chunk decal layer in this iteration."
	)
	view.queue_free()

func _assert_chunk_diff_round_trip_unchanged() -> void:
	var chunk_coord := Vector2i(1, -2)
	var local_coord := Vector2i(3, 4)
	var store := WorldDiffStore.new()
	store.set_tile_override(
		chunk_coord,
		local_coord,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		true
	)
	var serialized: Array[Dictionary] = store.serialize_dirty_chunks()
	var serialized_text: String = JSON.stringify(serialized)
	_assert(not serialized_text.contains("decal_instances"), "Serialized chunk diff must not contain decal_instances.")
	_assert(not serialized_text.contains("decal_instance_count"), "Serialized chunk diff must not contain decal_instance_count.")
	var restored := WorldDiffStore.new()
	restored.load_serialized_chunks(serialized)
	var override_data: Dictionary = restored.get_tile_override(chunk_coord, local_coord)
	_assert(
		int(override_data.get("terrain_id", -1)) == WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		"Chunk diff round-trip must preserve authoritative terrain_id override."
	)
	_assert(bool(override_data.get("walkable", false)), "Chunk diff round-trip must preserve walkable override.")

func _build_plain_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var terrain_atlas_indices := PackedInt32Array()
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var base_variant_indices := PackedByteArray()
	base_variant_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var transition_overlay_indices := PackedInt32Array()
	transition_overlay_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_atlas_indices := PackedInt32Array()
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		walkable_flags[index] = 1
	return {
		"chunk_coord": Vector2i.ZERO,
		"world_seed": 77,
		"world_version": WorldRuntimeConstants.WORLD_VERSION,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"base_variant_indices": base_variant_indices,
		"transition_overlay_indices": transition_overlay_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
		"silhouette_edges": PackedInt32Array(),
		"silhouette_edge_count": 0,
	}

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

func _is_decal_forbidden_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP

func _assert_packed_float_arrays_equal(a: PackedFloat32Array, b: PackedFloat32Array, message: String) -> void:
	_assert(a.size() == b.size(), message)
	if a.size() != b.size():
		return
	for index: int in range(a.size()):
		_assert(float(a[index]) == float(b[index]), message)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
