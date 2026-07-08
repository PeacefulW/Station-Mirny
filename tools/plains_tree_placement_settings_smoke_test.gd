extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const PlainsTreePlacementSettings = preload("res://core/resources/plains_tree_placement_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DefaultFoundationGenSettings = preload("res://data/balance/foundation_gen_settings.tres")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const DefaultMountainGenSettings = preload("res://data/balance/mountain_gen_settings.tres")
const DefaultPlainsTreePlacementSettings = preload("res://data/world_objects/placement_groups/plains_trees.tres")

const OBJECT_KIND_TREE: int = 4

var _failed: bool = false


func _init() -> void:
	_assert_default_resource_shape()
	_assert_settings_pack_shape()
	_assert_native_tree_density_comes_from_settings()

	if _failed:
		quit(1)
		return
	print("plains_tree_placement_settings_smoke_test: OK")
	quit(0)


func _assert_default_resource_shape() -> void:
	_assert(
		DefaultPlainsTreePlacementSettings is PlainsTreePlacementSettings,
		"plains_trees.tres must use PlainsTreePlacementSettings.",
	)
	_assert(
		DefaultPlainsTreePlacementSettings.id == &"core:plains_trees",
		"plains tree settings must keep the stable core:plains_trees id.",
	)
	_assert(
		DefaultPlainsTreePlacementSettings.object_family == &"tree",
		"plains tree settings must describe the tree object family.",
	)
	_assert(
		DefaultPlainsTreePlacementSettings.density > 0.0,
		"plains tree density must be authored in the .tres resource.",
	)


func _assert_settings_pack_shape() -> void:
	var packed: PackedFloat32Array = _build_tree_settings_packed(0.37, 0.23)
	_assert(
		packed.size() == WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_TREE_FIELD_COUNT,
		"Tree placement settings must extend the native settings packet.",
	)
	_assert(
		is_equal_approx(
			packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_TREE_DENSITY],
			0.37,
		),
		"Tree density must be packed through the named tree density slot.",
	)
	_assert(
		is_equal_approx(
			packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_TREE_GRASS_DENSITY_MIN],
			0.23,
		),
		"Tree grass-density threshold must be packed through the named slot.",
	)


func _assert_native_tree_density_comes_from_settings() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for native tree placement checks.")
	if world_core == null:
		return

	var no_tree_count: int = _count_trees_in_scan(world_core, _build_tree_settings_packed(0.0, 0.0))
	_assert(no_tree_count == 0, "Tree density 0.0 in plains_trees.tres settings must emit zero native trees.")

	var dense_tree_count: int = _count_trees_in_scan(world_core, _build_tree_settings_packed(1.0, 0.0))
	_assert(dense_tree_count > 0, "Tree density 1.0 in plains_trees.tres settings must emit native trees.")
	print("PLAINS_TREE_DENSITY_PROBE no_tree_count=%d dense_tree_count=%d" % [no_tree_count, dense_tree_count])


func _count_trees_in_scan(world_core: Object, settings_packed: PackedFloat32Array) -> int:
	var coords := PackedVector2Array()
	var center_chunk := Vector2i(128, 64)
	for y_offset: int in range(32):
		for x_offset: int in range(32):
			coords.append(Vector2(center_chunk.x + x_offset, center_chunk.y + y_offset))

	var packets_variant: Variant = world_core.call(
		"generate_chunk_packets_batch",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed,
	)
	_assert(packets_variant is Array, "WorldCore must return an Array for tree placement density checks.")
	if not (packets_variant is Array):
		return 0

	var tree_count: int = 0
	for packet_variant: Variant in packets_variant as Array:
		var packet: Dictionary = packet_variant as Dictionary
		var object_kind: PackedByteArray = packet.get("object_kind", PackedByteArray()) as PackedByteArray
		for kind: int in object_kind:
			if kind == OBJECT_KIND_TREE:
				tree_count += 1
	return tree_count


func _build_tree_settings_packed(tree_density: float, grass_density_min: float) -> PackedFloat32Array:
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var mountain_settings: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	mountain_settings.density = 0.0
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		world_bounds,
	)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lake_settings.density = 0.0

	var tree_settings: PlainsTreePlacementSettings = PlainsTreePlacementSettings.from_save_dict(
		DefaultPlainsTreePlacementSettings.to_save_dict(),
	)
	tree_settings.density = tree_density
	tree_settings.grass_density_min = grass_density_min

	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	packed = lake_settings.write_to_settings_packed(packed)
	return tree_settings.write_to_settings_packed(packed)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
