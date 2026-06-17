extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const TARGET_TILE: Vector2i = Vector2i(672, 540)

func _init() -> void:
	var core: Object = ClassDB.instantiate("WorldCore")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var mountains: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountains.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	packed = lakes.write_to_settings_packed(packed)

	var chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(TARGET_TILE)
	var local: Vector2i = WorldRuntimeConstants.tile_to_local(TARGET_TILE)
	var packet: Dictionary = core.call(
		"generate_chunk_packet",
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		chunk,
		WorldRuntimeConstants.WORLD_VERSION,
		packed
	) as Dictionary
	var index: int = WorldRuntimeConstants.local_to_index(local)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	print("green_tile_packet_probe target=%s chunk=%s local=%s index=%d" % [str(TARGET_TILE), str(chunk), str(local), index])
	_dump_index("center", index, terrain_ids, walkable_flags, lake_flags, mountain_ids, mountain_flags)
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var tile: Vector2i = TARGET_TILE + offset
		var local_neighbor: Vector2i = WorldRuntimeConstants.tile_to_local(tile)
		var neighbor_index: int = WorldRuntimeConstants.local_to_index(local_neighbor)
		_dump_index("neighbor %s" % str(offset), neighbor_index, terrain_ids, walkable_flags, lake_flags, mountain_ids, mountain_flags)
	quit(0)

func _dump_index(
	label: String,
	index: int,
	terrain_ids: PackedInt32Array,
	walkable_flags: PackedByteArray,
	lake_flags: PackedByteArray,
	mountain_ids: PackedInt32Array,
	mountain_flags: PackedByteArray
) -> void:
	var terrain_id: int = int(terrain_ids[index]) if index >= 0 and index < terrain_ids.size() else -1
	var walkable: int = int(walkable_flags[index]) if index >= 0 and index < walkable_flags.size() else -1
	var lake: int = int(lake_flags[index]) if index >= 0 and index < lake_flags.size() else -1
	var mountain_id: int = int(mountain_ids[index]) if index >= 0 and index < mountain_ids.size() else -1
	var mountain_flag: int = int(mountain_flags[index]) if index >= 0 and index < mountain_flags.size() else -1
	print("%s terrain=%d walkable=%d lake_flags=%d water=%s mountain_id=%d mountain_flags=%d" % [
		label,
		terrain_id,
		walkable,
		lake,
		str((lake & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0),
		mountain_id,
		mountain_flag,
	])
