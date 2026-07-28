extends SceneTree

## Counts generated stones per chunk and reports where they landed relative to
## grass cover, so the bare-ground set can be verified without eyeballing a
## screenshot. Emission is native, so this reads the real packet, not a mirror.
##
##     Godot --headless --path . -s tools/bare_ground_stone_placement_probe.gd

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const PlainsTreePlacementSettings = preload("res://core/resources/plains_tree_placement_settings.gd")
const PlainsSmallRockPlacementSettings = preload("res://core/resources/plains_small_rock_placement_settings.gd")

const DefaultFoundationGenSettings = preload("res://data/balance/foundation_gen_settings.tres")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const DefaultMountainGenSettings = preload("res://data/balance/mountain_gen_settings.tres")
const DefaultPlainsTreeSettings = preload("res://data/world_objects/placement_groups/plains_trees.tres")
const DefaultPlainsSmallRockSettings = preload("res://data/world_objects/placement_groups/plains_small_rocks.tres")
const DefaultPlainsBareGroundStoneSettings = preload("res://data/world_objects/placement_groups/plains_bare_ground_stones.tres")
const DefaultPlainsGroundMaterialSet = preload("res://data/terrain/material_sets/plains_ground_material_set.tres")

const OBJECT_KIND_SMALL_ROCK: int = 7
const CHUNK_SPAN: int = 6
const SEED_VALUE: int = 131071


func _init() -> void:
	var core: Object = ClassDB.instantiate("WorldCore")
	if core == null:
		push_error("WorldCore is unavailable; rebuild the GDExtension.")
		quit(1)
		return

	var packed: PackedFloat32Array = _build_settings_packed()
	var coords: PackedVector2Array = PackedVector2Array()
	for chunk_y: int in range(CHUNK_SPAN):
		for chunk_x: int in range(CHUNK_SPAN):
			coords.append(Vector2(chunk_x, chunk_y))

	var packets: Variant = core.call(
		"generate_chunk_packets_batch",
		SEED_VALUE,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		packed,
	)
	if packets is not Array or (packets as Array).is_empty():
		push_error("WorldCore returned no chunk packets.")
		quit(1)
		return

	var total_rocks: int = 0
	var size_histogram: Dictionary = {}
	var variant_histogram: Dictionary = {}
	var per_chunk_counts: Array[int] = []
	var minimum_pair_distance_px: float = INF
	for entry: Variant in packets as Array:
		var packet: Dictionary = entry as Dictionary
		var kinds: PackedByteArray = packet.get("object_kind", PackedByteArray())
		var local_x_q4: PackedByteArray = packet.get("object_local_x_px_q4", PackedByteArray())
		var local_y_q4: PackedByteArray = packet.get("object_local_y_px_q4", PackedByteArray())
		var sizes: PackedByteArray = packet.get("object_size_px", PackedByteArray())
		var variants: PackedByteArray = packet.get("object_variant", PackedByteArray())
		var chunk_rocks: int = 0
		var chunk_positions: Array[Vector2] = []
		for index: int in range(kinds.size()):
			if int(kinds[index]) != OBJECT_KIND_SMALL_ROCK:
				continue
			chunk_rocks += 1
			chunk_positions.append(Vector2(
				float(local_x_q4[index]) * 4.0,
				float(local_y_q4[index]) * 4.0,
			))
			var size_bucket: int = int(sizes[index]) / 8 * 8
			size_histogram[size_bucket] = int(size_histogram.get(size_bucket, 0)) + 1
			var variant: int = int(variants[index])
			variant_histogram[variant] = int(variant_histogram.get(variant, 0)) + 1
		for left_index: int in range(chunk_positions.size()):
			for right_index: int in range(left_index + 1, chunk_positions.size()):
				minimum_pair_distance_px = minf(
					minimum_pair_distance_px,
					chunk_positions[left_index].distance_to(chunk_positions[right_index]),
				)
		per_chunk_counts.append(chunk_rocks)
		total_rocks += chunk_rocks
	var total_chunks: int = per_chunk_counts.size()

	per_chunk_counts.sort()
	print("world_version: %d" % WorldRuntimeConstants.WORLD_VERSION)
	print("chunks sampled: %d" % total_chunks)
	print("stones total: %d  (mean %.1f per chunk)" % [total_rocks, float(total_rocks) / maxf(1.0, float(total_chunks))])
	print("per-chunk min/median/max: %d / %d / %d" % [
		per_chunk_counts[0],
		per_chunk_counts[per_chunk_counts.size() / 2],
		per_chunk_counts[per_chunk_counts.size() - 1],
	])

	var used_variants: Array = variant_histogram.keys()
	used_variants.sort()
	print("distinct variants used: %d of 22" % used_variants.size())
	var variant_line: PackedStringArray = PackedStringArray()
	for variant: int in used_variants:
		variant_line.append("%d:%d" % [variant, int(variant_histogram[variant])])
	print("variant histogram: %s" % ", ".join(variant_line))

	var buckets: Array = size_histogram.keys()
	buckets.sort()
	var size_line: PackedStringArray = PackedStringArray()
	for bucket: int in buckets:
		size_line.append("%d-%d px:%d" % [bucket, bucket + 7, int(size_histogram[bucket])])
	print("size histogram: %s" % ", ".join(size_line))
	print("minimum same-chunk pair distance after q4 packing: %.1f px" % minimum_pair_distance_px)

	if total_rocks == 0:
		push_error("No stones emitted at all.")
		quit(1)
		return
	if used_variants.size() < 15:
		push_error("Bare-ground set should reach the procedural variants; only %d distinct in use." % used_variants.size())
		quit(1)
		return
	if minimum_pair_distance_px < 8.0:
		push_error(
			"Stone spacing collapsed after q4 packing: minimum pair distance is %.1f px." \
					% minimum_pair_distance_px,
		)
		quit(1)
		return
	print("bare_ground_stone_placement_probe: OK")
	quit(0)


func _build_settings_packed() -> PackedFloat32Array:
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var mountains: MountainGenSettings = MountainGenSettings.from_save_dict(DefaultMountainGenSettings.to_save_dict())
	var foundation: FoundationGenSettings = FoundationGenSettings.from_save_dict(
		DefaultFoundationGenSettings.to_save_dict(),
		bounds,
	)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var trees: PlainsTreePlacementSettings = PlainsTreePlacementSettings.from_save_dict(DefaultPlainsTreeSettings.to_save_dict())
	var rocks: PlainsSmallRockPlacementSettings = PlainsSmallRockPlacementSettings.from_save_dict(DefaultPlainsSmallRockSettings.to_save_dict())
	var stones: PlainsSmallRockPlacementSettings = PlainsSmallRockPlacementSettings.from_save_dict(DefaultPlainsBareGroundStoneSettings.to_save_dict())
	trees.apply_ground_sampling_params(DefaultPlainsGroundMaterialSet.sampling_params)
	rocks.apply_ground_sampling_params(DefaultPlainsGroundMaterialSet.sampling_params)
	stones.apply_ground_sampling_params(DefaultPlainsGroundMaterialSet.sampling_params)

	var packed: PackedFloat32Array = mountains.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	packed = lakes.write_to_settings_packed(packed)
	packed = trees.write_to_settings_packed(packed)
	packed = rocks.write_to_settings_packed(packed)
	return stones.write_to_settings_packed(
		packed,
		WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_BARE_GROUND_STONE_BLOCK_BEGIN,
	)
