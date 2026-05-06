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

const SILHOUETTE_EDGE_STRIDE: int = 4
const SILHOUETTE_VARIANT_COUNT: int = 4

var _failed: bool = false

func _init() -> void:
	_assert_static_contract()
	_assert_native_packet_fields()
	_assert_chunk_view_renders_packet_edges()
	_assert_runtime_patch_promotes_new_exposed_surface()

	if _failed:
		quit(1)
		return
	print("mountain_silhouette_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var world_core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		world_core_source.contains("mountain_silhouette"),
		"WorldCore must delegate mountain silhouette edge enumeration to native mountain_silhouette code."
	)
	_assert(
		world_core_source.contains("packet[\"silhouette_edges\"]"),
		"ChunkPacketV1 must include silhouette_edges at the native packet boundary."
	)
	_assert(
		world_core_source.contains("packet[\"silhouette_edge_count\"]"),
		"ChunkPacketV1 must include silhouette_edge_count at the native packet boundary."
	)

	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	_assert(chunk_view_source.contains("_silhouette_layer"), "ChunkView must own one _silhouette_layer.")
	_assert(
		chunk_view_source.contains("MultiMeshInstance2D"),
		"ChunkView silhouette rendering must use MultiMeshInstance2D, not node-per-edge sprites."
	)
	_assert(
		chunk_view_source.contains("get_silhouette_render_debug"),
		"ChunkView must expose a local silhouette debug surface for smoke verification."
	)

	var constants_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_runtime_constants.gd")
	_assert(
		constants_source.contains("const WORLD_VERSION: int = 44"),
		"WORLD_VERSION must remain 44 for visual-only silhouette work."
	)

	var packet_schema_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/packet_schemas.md")
	_assert(packet_schema_source.contains("silhouette_edges"), "packet_schemas.md must document silhouette_edges.")
	_assert(packet_schema_source.contains("silhouette_edge_count"), "packet_schemas.md must document silhouette_edge_count.")

func _assert_native_packet_fields() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native silhouette packet checks.")
	if world_core == null:
		return
	var packets: Variant = world_core.call(
		"generate_chunk_packets_batch",
		240505,
		PackedVector2Array([Vector2(0, 0)]),
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed()
	)
	_assert(packets is Array and (packets as Array).size() == 1, "WorldCore must return one packet for one requested chunk.")
	if packets is not Array or (packets as Array).is_empty():
		return
	var packet: Dictionary = (packets as Array)[0] as Dictionary
	_assert(packet.has("silhouette_edges"), "ChunkPacketV1 must carry silhouette_edges even when empty.")
	_assert(packet.has("silhouette_edge_count"), "ChunkPacketV1 must carry silhouette_edge_count even when zero.")
	var silhouette_edges: PackedInt32Array = packet.get("silhouette_edges", PackedInt32Array()) as PackedInt32Array
	var silhouette_edge_count: int = int(packet.get("silhouette_edge_count", -1))
	_assert(
		silhouette_edges.size() == silhouette_edge_count * SILHOUETTE_EDGE_STRIDE,
		"silhouette_edges must use four int records: foot_tile_index, direction, mountain_id, atlas_variant."
	)
	_assert_native_edge_semantics(world_core)

func _assert_chunk_view_renders_packet_edges() -> void:
	var view := ChunkView.new()
	get_root().add_child(view)
	view.configure(Vector2i.ZERO)
	var foot_coord := Vector2i(2, 2)
	var packet: Dictionary = _build_packet_with_surface(foot_coord, WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT)
	var foot_index: int = WorldRuntimeConstants.local_to_index(foot_coord)
	packet["silhouette_edges"] = PackedInt32Array([foot_index, 1, 77, 2])
	packet["silhouette_edge_count"] = 1
	view.begin_apply(packet)
	while view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	if not view.has_method("get_silhouette_render_debug"):
		_assert(false, "ChunkView must expose get_silhouette_render_debug().")
		view.queue_free()
		return
	var debug: Dictionary = view.call("get_silhouette_render_debug") as Dictionary
	_assert(bool(debug.get("has_layer", false)), "ChunkView must create a silhouette MultiMeshInstance2D.")
	_assert(int(debug.get("z_index", -1)) == 5, "Silhouette layer must render above water/player and below roof.")
	_assert(int(debug.get("instance_count", -1)) == 1, "One silhouette edge record must render one MultiMesh instance.")
	view.queue_free()

func _assert_runtime_patch_promotes_new_exposed_surface() -> void:
	var view := ChunkView.new()
	get_root().add_child(view)
	view.configure(Vector2i.ZERO)
	var mined_coord := Vector2i(2, 2)
	var newly_exposed_coord := Vector2i(2, 3)
	var packet: Dictionary = _build_packet_with_surface(mined_coord, WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT)
	var terrain_ids: PackedInt32Array = packet["terrain_ids"] as PackedInt32Array
	var walkable_flags: PackedByteArray = packet["walkable_flags"] as PackedByteArray
	var mountain_ids: PackedInt32Array = packet["mountain_id_per_tile"] as PackedInt32Array
	var mountain_flags: PackedByteArray = packet["mountain_flags"] as PackedByteArray
	var newly_exposed_index: int = WorldRuntimeConstants.local_to_index(newly_exposed_coord)
	terrain_ids[newly_exposed_index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	walkable_flags[newly_exposed_index] = 0
	mountain_ids[newly_exposed_index] = 77
	mountain_flags[newly_exposed_index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	packet["terrain_ids"] = terrain_ids
	packet["walkable_flags"] = walkable_flags
	packet["mountain_id_per_tile"] = mountain_ids
	packet["mountain_flags"] = mountain_flags
	var mined_index: int = WorldRuntimeConstants.local_to_index(mined_coord)
	packet["silhouette_edges"] = PackedInt32Array([mined_index, 2, 77, 1])
	packet["silhouette_edge_count"] = 1
	view.begin_apply(packet)
	while view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	view.apply_runtime_cell(
		mined_coord,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		0,
		0
	)
	if not view.has_method("flush_silhouette_debug_updates"):
		_assert(false, "ChunkView must expose flush_silhouette_debug_updates() for deterministic smoke tests.")
		view.queue_free()
		return
	view.call("flush_silhouette_debug_updates")
	if not view.has_method("get_silhouette_render_debug"):
		_assert(false, "ChunkView must expose get_silhouette_render_debug().")
		view.queue_free()
		return
	var debug: Dictionary = view.call("get_silhouette_render_debug") as Dictionary
	_assert(int(debug.get("instance_count", -1)) == 1, "Local mining refresh should keep one silhouette on the newly exposed surface.")
	_assert(
		(debug.get("edge_keys", []) as Array).has("%d:0" % newly_exposed_index),
		"Local mining refresh must move the silhouette edge from mined foot tile to newly exposed wall tile."
	)
	view.queue_free()

func _build_packet_with_surface(surface_coord: Vector2i, terrain_id: int) -> Dictionary:
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
	var surface_index: int = WorldRuntimeConstants.local_to_index(surface_coord)
	terrain_ids[surface_index] = terrain_id
	walkable_flags[surface_index] = 0
	mountain_ids[surface_index] = 77
	mountain_flags[surface_index] = WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
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
	}

func _build_settings_packed(force_dense_mountains: bool = false) -> PackedFloat32Array:
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var mountain_settings: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	if force_dense_mountains:
		mountain_settings.density = 0.45
		mountain_settings.scale = 256.0
		mountain_settings.foot_band = 0.30
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		world_bounds
	)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lake_settings.density = 0.0
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	return lake_settings.write_to_settings_packed(packed)

func _assert_native_edge_semantics(world_core: Object) -> void:
	var coords := PackedVector2Array()
	for y: int in range(20, 33):
		for x: int in range(-6, 7):
			coords.append(Vector2(x, y))
	var packets: Variant = world_core.call(
		"generate_chunk_packets_batch",
		240505,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed(true)
	)
	_assert(packets is Array, "WorldCore must return packet array for silhouette edge search.")
	if packets is not Array:
		return
	var found_edge_packet: bool = false
	var found_local_verified_edge: bool = false
	for packet_variant: Variant in packets:
		var packet: Dictionary = packet_variant as Dictionary
		var edge_count: int = int(packet.get("silhouette_edge_count", 0))
		if edge_count <= 0:
			continue
		found_edge_packet = true
		var edges: PackedInt32Array = packet.get("silhouette_edges", PackedInt32Array()) as PackedInt32Array
		_assert(
			edges.size() == edge_count * SILHOUETTE_EDGE_STRIDE,
			"Generated silhouette packet must keep edge_count aligned with packed edge size."
		)
		var terrain_ids: PackedInt32Array = packet["terrain_ids"] as PackedInt32Array
		var walkable_flags: PackedByteArray = packet["walkable_flags"] as PackedByteArray
		var mountain_ids: PackedInt32Array = packet["mountain_id_per_tile"] as PackedInt32Array
		var mountain_flags: PackedByteArray = packet["mountain_flags"] as PackedByteArray
		for edge_index: int in range(edge_count):
			var offset: int = edge_index * SILHOUETTE_EDGE_STRIDE
			var foot_index: int = int(edges[offset])
			var direction: int = int(edges[offset + 1])
			var mountain_id: int = int(edges[offset + 2])
			var atlas_variant: int = int(edges[offset + 3])
			_assert(foot_index >= 0 and foot_index < WorldRuntimeConstants.CHUNK_CELL_COUNT, "Silhouette edge owner index must stay inside the emitting chunk.")
			_assert(direction >= 0 and direction <= 3, "Silhouette direction must be cardinal N/E/S/W.")
			_assert(atlas_variant >= 0 and atlas_variant < SILHOUETTE_VARIANT_COUNT, "Silhouette atlas variant must stay inside the authored variant range.")
			if foot_index < 0 or foot_index >= WorldRuntimeConstants.CHUNK_CELL_COUNT:
				continue
			_assert(int(terrain_ids[foot_index]) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT, "Native silhouette edges must be owned by mountain foot terrain.")
			_assert((int(mountain_flags[foot_index]) & WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT) != 0, "Native silhouette edge owner must carry MOUNTAIN_FLAG_FOOT.")
			_assert(int(mountain_ids[foot_index]) == mountain_id, "Silhouette edge mountain_id must match the owner tile.")
			var neighbour_coord: Vector2i = WorldRuntimeConstants.index_to_local(foot_index) + _direction_to_offset(direction)
			if not WorldRuntimeConstants.is_local_coord_valid(neighbour_coord):
				continue
			var neighbour_index: int = WorldRuntimeConstants.local_to_index(neighbour_coord)
			_assert(int(walkable_flags[neighbour_index]) != 0, "In-chunk silhouette neighbour must be walkable.")
			_assert(not _is_mountain_terrain(int(terrain_ids[neighbour_index])), "In-chunk silhouette neighbour must be non-mountain terrain.")
			found_local_verified_edge = true
	_assert(found_edge_packet, "Native silhouette search must find at least one generated silhouette edge packet.")
	_assert(found_local_verified_edge, "Native silhouette search must verify at least one in-chunk foot-to-walkable edge.")

func _direction_to_offset(direction: int) -> Vector2i:
	match direction:
		0:
			return Vector2i(0, -1)
		1:
			return Vector2i(1, 0)
		2:
			return Vector2i(0, 1)
		3:
			return Vector2i(-1, 0)
	return Vector2i.ZERO

func _is_mountain_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
