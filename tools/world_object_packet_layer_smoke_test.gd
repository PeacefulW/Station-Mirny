extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const PlainsTreePlacementSettings = preload("res://core/resources/plains_tree_placement_settings.gd")
const PlainsSmallRockPlacementSettings = preload("res://core/resources/plains_small_rock_placement_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")

const DefaultFoundationGenSettings = preload("res://data/balance/foundation_gen_settings.tres")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const DefaultMountainGenSettings = preload("res://data/balance/mountain_gen_settings.tres")
const DefaultPlainsGroundMaterialSet = preload("res://data/terrain/material_sets/plains_ground_material_set.tres")
const DefaultPlainsTreePlacementSettings = preload("res://data/world_objects/placement_groups/plains_trees.tres")
const DefaultPlainsSmallRockPlacementSettings = preload("res://data/world_objects/placement_groups/plains_small_rocks.tres")

const OBJECT_KIND_LIVING_FLORA: int = 2
const OBJECT_KIND_SPIKY_FLORA: int = 3
const OBJECT_KIND_SMALL_ROCK: int = 7
const REMOVED_OBJECT_KIND_1: int = 1
const REMOVED_OBJECT_KIND_5: int = 5
const REMOVED_OBJECT_KIND_6: int = 6
const SPIKY_FLORA_ATLAS_BROWN_SEAWEED: int = 1
const OBJECT_MOUNTAIN_CLEARANCE_PX: float = 48.0
const OBJECT_FIELD_NAMES: Array[String] = [
	"object_kind",
	"object_local_x_px_q4",
	"object_local_y_px_q4",
	"object_size_px",
	"object_atlas_index",
	"object_variant",
	"object_flags",
	"object_tint",
	"object_phase",
]

var _failed: bool = false


func _init() -> void:
	var packet: Dictionary = _find_native_packet_with_objects()
	if not packet.is_empty():
		_assert_packet_arrays(packet)
		_assert_packet_layer_consumes_packet(packet)
	_assert_small_rocks_form_natural_clusters()
	_assert_native_objects_keep_mountain_clearance()

	if _failed:
		quit(1)
		return
	print("WORLD_OBJECT_PACKET_LAYER_SMOKE OK")
	quit(0)


func _find_native_packet_with_objects() -> Dictionary:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native object packet checks.")
	if world_core == null:
		return { }

	var coords := PackedVector2Array()
	var center_chunk := Vector2i(128, 64)
	for y_offset: int in range(64):
		for x_offset: int in range(64):
			coords.append(Vector2(center_chunk.x + x_offset, center_chunk.y + y_offset))

	var packets_variant: Variant = world_core.call(
		"generate_chunk_packets_batch",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed(),
	)
	_assert(packets_variant is Array, "WorldCore must return an Array for object packet smoke.")
	if not (packets_variant is Array):
		return { }

	var packets: Array = packets_variant as Array
	var best_packet: Dictionary = { }
	var best_object_count: int = 0
	var best_spiky_count: int = 0
	var best_living_count: int = 0
	var best_brown_seaweed_count: int = 0
	var best_small_rock_count: int = 0
	var best_score: int = -1
	var small_rock_total: int = 0
	var removed_object_count: int = 0
	for packet_variant: Variant in packets:
		var packet: Dictionary = packet_variant as Dictionary
		var object_kind: PackedByteArray = packet.get("object_kind", PackedByteArray()) as PackedByteArray
		var object_atlas: PackedByteArray = packet.get("object_atlas_index", PackedByteArray()) as PackedByteArray
		var spiky_count: int = _count_kind(object_kind, OBJECT_KIND_SPIKY_FLORA)
		var living_count: int = _count_kind(object_kind, OBJECT_KIND_LIVING_FLORA)
		var brown_seaweed_count: int = _count_kind_atlas(object_kind, object_atlas, OBJECT_KIND_SPIKY_FLORA, SPIKY_FLORA_ATLAS_BROWN_SEAWEED)
		var small_rock_count: int = _count_kind(object_kind, OBJECT_KIND_SMALL_ROCK)
		small_rock_total += small_rock_count
		removed_object_count += _count_removed_object_kinds(object_kind)
		var packet_score: int = object_kind.size() \
				+ (1000 if spiky_count > 0 else 0) \
				+ (1000 if brown_seaweed_count > 0 else 0) \
				+ (1000 if small_rock_count > 0 else 0)
		if packet_score > best_score:
			best_packet = packet
			best_score = packet_score
			best_object_count = object_kind.size()
			best_spiky_count = spiky_count
			best_living_count = living_count
			best_brown_seaweed_count = brown_seaweed_count
			best_small_rock_count = small_rock_count
		if spiky_count > 0 and brown_seaweed_count > 0 and small_rock_count > 0:
			best_packet = packet
			best_object_count = object_kind.size()
			best_spiky_count = spiky_count
			best_living_count = living_count
			best_brown_seaweed_count = brown_seaweed_count
			best_small_rock_count = small_rock_count
			break

	_assert(best_object_count > 0, "Native object packet scan produced no objects.")
	_assert(best_spiky_count > 0, "Native object packet scan produced no spiky flora objects.")
	_assert(best_brown_seaweed_count > 0, "Native object packet scan produced no brown seaweed biofield flora objects.")
	_assert(best_small_rock_count > 0, "Native object packet scan best packet produced no small rock objects.")
	_assert(small_rock_total > 0, "Native object packet scan produced no small rock objects.")
	_assert(removed_object_count == 0, "Native object packet scan must not emit removed stone object kinds 1/5/6.")
	print(
		"WORLD_OBJECT_PACKET_NATIVE objects=%d living=%d spiky=%d brown_seaweed=%d small_rocks=%d removed_object_kinds=%d" %
		[best_object_count, best_living_count, best_spiky_count, best_brown_seaweed_count, best_small_rock_count, removed_object_count],
	)
	return best_packet


func _assert_packet_arrays(packet: Dictionary) -> void:
	var expected_count: int = -1
	for field_name: String in OBJECT_FIELD_NAMES:
		var field: PackedByteArray = packet.get(field_name, PackedByteArray()) as PackedByteArray
		_assert(field.size() > 0, "%s must be present in the native object packet." % field_name)
		if expected_count < 0:
			expected_count = field.size()
		_assert(
			field.size() == expected_count,
			"%s must match the object packet record count." % field_name,
		)

	var object_size: PackedByteArray = packet.get("object_size_px", PackedByteArray()) as PackedByteArray
	for size_byte: int in object_size:
		_assert(size_byte > 0, "object_size_px entries must be positive.")


func _assert_packet_layer_consumes_packet(packet: Dictionary) -> void:
	var layer := WorldObjectPacketLayer.new()
	root.add_child(layer)
	layer.set_living_flora_atlas(_make_texture(4096, 1024))
	layer.set_spiky_flora_atlases([_make_texture(2048, 512), _make_texture(2048, 512)])
	layer.set_layered_small_rock_asset_dirs([
		"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_01",
	])
	layer.configure_packet(packet)
	layer.set_sun_lighting(WorldVisualLightingProfile.FIXED_LIGHT_ANGLE_DEG, 96.0, 0.55, 18.0)

	var state: Dictionary = layer.get_debug_state()
	_assert(int(state.get("spiky_flora_count", 0)) > 0, "WorldObjectPacketLayer must render spiky flora packet records.")
	_assert(int(state.get("small_rock_count", 0)) > 0, "WorldObjectPacketLayer must render small rock packet records.")
	_assert(int(state.get("layered_small_rock_count", 0)) > 0, "WorldObjectPacketLayer must create layered small rock nodes.")
	_assert(int(state.get("layered_small_rock_shadow_count", 0)) > 0, "WorldObjectPacketLayer must create layered small rock shadows.")
	_assert(not bool(state.get("small_rock_uses_collision", true)), "Small rocks must remain visual-only and collision-free.")
	print("WORLD_OBJECT_PACKET_LAYER_STATE ", state)
	layer.free()


func _assert_native_objects_keep_mountain_clearance() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native object mountain-clearance checks.")
	if world_core == null:
		return

	var coords := PackedVector2Array()
	var center_chunk := Vector2i(112, 48)
	for y_offset: int in range(48):
		for x_offset: int in range(48):
			coords.append(Vector2(center_chunk.x + x_offset, center_chunk.y + y_offset))

	var packets_variant: Variant = world_core.call(
		"generate_chunk_packets_batch",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_mountain_settings_packed(),
	)
	_assert(packets_variant is Array, "WorldCore must return an Array for object mountain-clearance checks.")
	if not (packets_variant is Array):
		return

	var checked_object_count: int = 0
	var mountain_packet_count: int = 0
	for packet_variant: Variant in packets_variant as Array:
		var packet: Dictionary = packet_variant as Dictionary
		if _packet_has_mountain_surface(packet):
			mountain_packet_count += 1
		var object_kind: PackedByteArray = packet.get("object_kind", PackedByteArray()) as PackedByteArray
		var object_x: PackedByteArray = packet.get("object_local_x_px_q4", PackedByteArray()) as PackedByteArray
		var object_y: PackedByteArray = packet.get("object_local_y_px_q4", PackedByteArray()) as PackedByteArray
		var object_count: int = mini(object_kind.size(), mini(object_x.size(), object_y.size()))
		for index: int in range(object_count):
			var local_x: float = float(int(object_x[index]) * 4)
			var local_y: float = float(int(object_y[index]) * 4)
			checked_object_count += 1
			_assert(
				_object_has_mountain_clearance(packet, local_x, local_y, OBJECT_MOUNTAIN_CLEARANCE_PX),
				"Native object packet placed object kind %d inside mountain clearance at chunk %s local=(%.1f, %.1f)." % [
					int(object_kind[index]),
					str(packet.get("chunk_coord", Vector2i.ZERO)),
					local_x,
					local_y,
				],
			)

	_assert(mountain_packet_count > 0, "Mountain-clearance scan must include mountain surface packets.")
	_assert(checked_object_count > 0, "Mountain-clearance scan must include native object records.")


func _assert_small_rocks_form_natural_clusters() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for natural small-rock cluster checks.")
	if world_core == null:
		return

	var coords := PackedVector2Array()
	var center_chunk := Vector2i(128, 64)
	for y_offset: int in range(72):
		for x_offset: int in range(72):
			coords.append(Vector2(center_chunk.x + x_offset, center_chunk.y + y_offset))

	var packets_variant: Variant = world_core.call(
		"generate_chunk_packets_batch",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed(),
	)
	_assert(packets_variant is Array, "WorldCore must return an Array for natural small-rock cluster checks.")
	if not (packets_variant is Array):
		return

	var best_count: int = 0
	var best_close_pair_count: int = 0
	var total_clustered_chunks: int = 0
	for packet_variant: Variant in packets_variant as Array:
		var positions: Array[Vector2] = _small_rock_positions(packet_variant as Dictionary)
		if positions.size() >= 8:
			total_clustered_chunks += 1
		best_count = maxi(best_count, positions.size())
		best_close_pair_count = maxi(best_close_pair_count, _count_close_pairs(positions, 82.0))

	_assert(best_count >= 8, "Default small rocks should produce chunks with rich clustered groups, not sparse singletons.")
	_assert(best_close_pair_count >= 3, "Default small rocks should include close pairs inside clusters.")
	_assert(total_clustered_chunks >= 3, "Default small rocks should produce clustered chunks across the scanned plains.")
	print(
		"WORLD_OBJECT_PACKET_SMALL_ROCK_CLUSTERS best_count=%d close_pairs=%d clustered_chunks=%d" %
		[best_count, best_close_pair_count, total_clustered_chunks],
	)


func _packet_has_mountain_surface(packet: Dictionary) -> bool:
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	for index: int in range(mini(mountain_ids.size(), mountain_flags.size())):
		if int(mountain_ids[index]) <= 0:
			continue
		var flags: int = int(mountain_flags[index])
		if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
			return true
	return false


func _object_has_mountain_clearance(packet: Dictionary, local_x: float, local_y: float, clearance_px: float) -> bool:
	var diagonal_clearance: float = clearance_px * 0.72
	for offset: Vector2 in [
		Vector2.ZERO,
		Vector2(clearance_px, 0.0),
		Vector2(-clearance_px, 0.0),
		Vector2(0.0, clearance_px),
		Vector2(0.0, -clearance_px),
		Vector2(diagonal_clearance, diagonal_clearance),
		Vector2(-diagonal_clearance, diagonal_clearance),
		Vector2(diagonal_clearance, -diagonal_clearance),
		Vector2(-diagonal_clearance, -diagonal_clearance),
	]:
		if not _sample_allows_object(packet, local_x + offset.x, local_y + offset.y):
			return false
	return true


func _sample_allows_object(packet: Dictionary, local_x: float, local_y: float) -> bool:
	if local_x < 0.0 \
			or local_y < 0.0 \
			or local_x >= float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX) \
			or local_y >= float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX):
		return true
	var local_coord := Vector2i(
		floori(local_x / float(WorldRuntimeConstants.TILE_SIZE_PX)),
		floori(local_y / float(WorldRuntimeConstants.TILE_SIZE_PX)),
	)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size():
		return false
	if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
		return false
	return index >= lake_flags.size() \
			or (int(lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) == 0


func _small_rock_positions(packet: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var object_kind: PackedByteArray = packet.get("object_kind", PackedByteArray()) as PackedByteArray
	var object_x: PackedByteArray = packet.get("object_local_x_px_q4", PackedByteArray()) as PackedByteArray
	var object_y: PackedByteArray = packet.get("object_local_y_px_q4", PackedByteArray()) as PackedByteArray
	var object_count: int = mini(object_kind.size(), mini(object_x.size(), object_y.size()))
	for index: int in range(object_count):
		if int(object_kind[index]) != OBJECT_KIND_SMALL_ROCK:
			continue
		result.append(Vector2(float(int(object_x[index]) * 4), float(int(object_y[index]) * 4)))
	return result


func _count_close_pairs(positions: Array[Vector2], max_distance_px: float) -> int:
	var max_distance_sq: float = max_distance_px * max_distance_px
	var count: int = 0
	for i: int in range(positions.size()):
		for j: int in range(i + 1, positions.size()):
			if positions[i].distance_squared_to(positions[j]) <= max_distance_sq:
				count += 1
	return count


func _build_settings_packed() -> PackedFloat32Array:
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var mountain_settings: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	mountain_settings.density = 0.0
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		world_bounds,
	)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lake_settings.density = 0.0
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	packed = lake_settings.write_to_settings_packed(packed)
	return _append_object_settings(packed)


func _build_mountain_settings_packed() -> PackedFloat32Array:
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var mountain_settings: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	mountain_settings.density = 0.45
	mountain_settings.scale = 256.0
	mountain_settings.foot_band = 0.30
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		world_bounds,
	)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lake_settings.density = 0.0
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	packed = lake_settings.write_to_settings_packed(packed)
	return _append_object_settings(packed)


func _append_object_settings(packed: PackedFloat32Array) -> PackedFloat32Array:
	var tree_settings: PlainsTreePlacementSettings = PlainsTreePlacementSettings.from_save_dict(
		DefaultPlainsTreePlacementSettings.to_save_dict(),
	)
	tree_settings.apply_ground_sampling_params(DefaultPlainsGroundMaterialSet.sampling_params)
	var small_rock_settings: PlainsSmallRockPlacementSettings = PlainsSmallRockPlacementSettings.from_save_dict(
		DefaultPlainsSmallRockPlacementSettings.to_save_dict(),
	)
	small_rock_settings.apply_ground_sampling_params(DefaultPlainsGroundMaterialSet.sampling_params)
	packed = tree_settings.write_to_settings_packed(packed)
	return small_rock_settings.write_to_settings_packed(packed)


func _make_texture(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


func _count_kind(object_kind: PackedByteArray, kind: int) -> int:
	var count: int = 0
	for value: int in object_kind:
		if value == kind:
			count += 1
	return count


func _count_kind_atlas(object_kind: PackedByteArray, object_atlas: PackedByteArray, kind: int, atlas_index: int) -> int:
	var count: int = 0
	var object_count: int = mini(object_kind.size(), object_atlas.size())
	for index: int in range(object_count):
		if int(object_kind[index]) == kind and int(object_atlas[index]) == atlas_index:
			count += 1
	return count


func _count_removed_object_kinds(object_kind: PackedByteArray) -> int:
	var count: int = 0
	for value: int in object_kind:
		if value == REMOVED_OBJECT_KIND_1 \
				or value == REMOVED_OBJECT_KIND_5 \
				or value == REMOVED_OBJECT_KIND_6:
			count += 1
	return count


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
