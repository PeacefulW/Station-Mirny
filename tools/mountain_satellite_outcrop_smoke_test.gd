extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const SEED: int = 131071
const PROBE_CENTER_CHUNKS: Array = [
	Vector2i(128, 100),
	Vector2i(96, 96),
	Vector2i(160, 96),
	Vector2i(96, 128),
	Vector2i(128, 128),
	Vector2i(160, 128),
	Vector2i(192, 112),
	Vector2i(128, 64),
	Vector2i(64, 128),
]
const RADIUS_CHUNKS: int = 10
const OUTCROP_MIN_CELLS: int = 3
const OUTCROP_MAX_CELLS: int = 18
const OUTCROP_CLUSTER_MIN_COMPONENTS: int = 2
const OUTCROP_CLUSTER_MAX_COMPONENTS: int = 20
const OUTCROP_CLUSTER_LARGE_COMPONENTS: int = 10
const LARGE_MOUNTAIN_MIN_CELLS: int = 96
const NEAR_MAIN_MAX_DISTANCE_TILES: int = 16
const NEAR_OUTCROP_MAX_DISTANCE_TILES: int = 12
const ROOF_LAYER_GUARDRAIL_PER_CHUNK: int = 24
const SATELLITE_OUTCROP_ID_MIN: int = 0x60000000
const SATELLITE_OUTCROP_ID_MAX_EXCLUSIVE: int = 0x70000000

var _failed: bool = false

func _initialize() -> void:
	var core := WorldCore.new()
	_assert(
		WorldRuntimeConstants.WORLD_VERSION == 47,
		"Strengthened satellite outcrop clusters change canonical mountain output and must bump WORLD_VERSION to 47."
	)
	var settings_packed: PackedFloat32Array = _build_settings_packed()
	var total_outcrops: int = 0
	var total_grouped: int = 0
	var total_valid_groups: int = 0
	var total_large_groups: int = 0
	var max_varied_footprints: int = 0
	var max_unique_mountains_per_chunk: int = 0
	var group_sizes: Array = []
	var group_boxes: Array = []
	var probe_summaries: Array[String] = []
	for center_chunk: Vector2i in PROBE_CENTER_CHUNKS:
		var packets: Array = _generate_packets(core, settings_packed, center_chunk)
		var analysis: Dictionary = _analyze_components(packets)
		var small_components: Array = analysis.get("small_components", []) as Array
		var grouped_components: int = int(analysis.get("grouped_components", 0))
		var valid_group_count: int = int(analysis.get("valid_group_count", 0))
		var large_group_count: int = int(analysis.get("large_group_count", 0))
		var varied_footprint_count: int = int(analysis.get("varied_footprint_count", 0))
		var probe_max_unique: int = int(analysis.get("max_unique_mountains_per_chunk", 0))
		if small_components.size() > 0:
			_assert(
				grouped_components == small_components.size(),
				"Every satellite outcrop component in a populated probe region must belong to a nearby cluster."
			)
		total_outcrops += small_components.size()
		total_grouped += grouped_components
		total_valid_groups += valid_group_count
		total_large_groups += large_group_count
		max_varied_footprints = maxi(max_varied_footprints, varied_footprint_count)
		max_unique_mountains_per_chunk = maxi(max_unique_mountains_per_chunk, probe_max_unique)
		group_sizes.append_array(analysis.get("group_sizes", []) as Array)
		group_boxes.append_array(analysis.get("group_boxes", []) as Array)
		probe_summaries.append(
			"%s: outcrops=%d groups=%d large_groups=%d footprints=%d max_chunk_mountains=%d"
			% [str(center_chunk), small_components.size(), valid_group_count, large_group_count, varied_footprint_count, probe_max_unique]
		)
	_assert(
		total_outcrops > 0,
		"Mountain generation must produce 3-18 tile satellite outcrop components near main mountain masses at density 0.60."
	)
	_assert(
		total_valid_groups > 0,
		"Satellite outcrops must appear in clusters of 2-20 separate components, not as lonely single rocks."
	)
	_assert(
		total_large_groups > 0,
		"Strengthened satellite outcrop generation must produce at least one 10-20 component cluster in the deterministic probe set."
	)
	_assert(
		max_varied_footprints >= 2,
		"Satellite outcrop clusters must include varied footprints instead of repeating one blob shape."
	)
	_assert(
		max_unique_mountains_per_chunk <= ROOF_LAYER_GUARDRAIL_PER_CHUNK,
		"Satellite outcrops must stay bounded enough to avoid roof-layer explosion per chunk."
	)
	print(
		"mountain_satellite_outcrop_smoke_test: outcrops=%d grouped=%d groups=%d large_groups=%d group_sizes=%s group_boxes=%s footprints=%d max_unique_mountains_per_chunk=%d probes=%s"
		% [total_outcrops, total_grouped, total_valid_groups, total_large_groups, str(group_sizes), str(group_boxes), max_varied_footprints, max_unique_mountains_per_chunk, str(probe_summaries)]
	)
	print("mountain_satellite_outcrop_smoke_test: %s" % ("FAIL" if _failed else "OK"))
	quit(1 if _failed else 0)

func _build_settings_packed() -> PackedFloat32Array:
	var mountain_settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	mountain_settings.density = 0.60
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.for_bounds(world_bounds)
	var lake_settings: LakeGenSettings = LakeGenSettings.hard_coded_defaults()
	lake_settings.density = 0.0
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	return lake_settings.write_to_settings_packed(packed)

func _generate_packets(core: Object, settings_packed: PackedFloat32Array, center_chunk: Vector2i) -> Array:
	var coords := PackedVector2Array()
	for y: int in range(center_chunk.y - RADIUS_CHUNKS, center_chunk.y + RADIUS_CHUNKS + 1):
		for x: int in range(center_chunk.x - RADIUS_CHUNKS, center_chunk.x + RADIUS_CHUNKS + 1):
			coords.append(Vector2(x, y))
	return core.call(
		"generate_chunk_packets_batch",
		SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	) as Array

func _analyze_components(packets: Array) -> Dictionary:
	var solid_tiles: Dictionary = {}
	var chunk_unique_ids: Dictionary = {}
	var min_tile := Vector2i(1 << 30, 1 << 30)
	var max_tile := Vector2i(-(1 << 30), -(1 << 30))
	for packet: Dictionary in packets:
		var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
		var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
		var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
		var unique_ids: Dictionary = {}
		for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
			var terrain_id: int = int(terrain_ids[index])
			var mountain_id: int = int(mountain_ids[index])
			var mountain_flag: int = int(mountain_flags[index])
			if mountain_id <= 0:
				continue
			if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
				continue
			_assert(
				int(walkable_flags[index]) == 0,
				"Satellite outcrop cells must use the existing blocking mountain terrain contract."
			)
			_assert(
				(mountain_flag & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0,
				"Satellite outcrop cells must carry wall/foot flags like ordinary mountain cells."
			)
			var local: Vector2i = WorldRuntimeConstants.index_to_local(index)
			var world_tile := Vector2i(
				chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE + local.x,
				chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE + local.y
			)
			solid_tiles[world_tile] = mountain_id
			unique_ids[mountain_id] = true
			min_tile.x = mini(min_tile.x, world_tile.x)
			min_tile.y = mini(min_tile.y, world_tile.y)
			max_tile.x = maxi(max_tile.x, world_tile.x)
			max_tile.y = maxi(max_tile.y, world_tile.y)
		chunk_unique_ids[chunk_coord] = unique_ids.size()

	var components: Array = _collect_components(solid_tiles)
	var large_components: Array = []
	for component: Dictionary in components:
		if int(component.get("size", 0)) >= LARGE_MOUNTAIN_MIN_CELLS:
			large_components.append(component)

	var small_components: Array = []
	var footprint_signatures: Dictionary = {}
	for component: Dictionary in components:
		var size: int = int(component.get("size", 0))
		var mountain_id: int = int(component.get("mountain_id", 0))
		if not _is_satellite_outcrop_id(mountain_id):
			continue
		if size < OUTCROP_MIN_CELLS or size > OUTCROP_MAX_CELLS:
			continue
		if _component_touches_scan_border(component, min_tile, max_tile):
			continue
		small_components.append(component)
		footprint_signatures[_footprint_signature(component)] = true

	var group_analysis: Dictionary = _analyze_outcrop_groups(small_components, large_components)

	var max_unique_mountains_per_chunk: int = 0
	for count: int in chunk_unique_ids.values():
		max_unique_mountains_per_chunk = maxi(max_unique_mountains_per_chunk, count)
	return {
		"small_components": small_components,
		"grouped_components": int(group_analysis.get("grouped_components", 0)),
		"valid_group_count": int(group_analysis.get("valid_group_count", 0)),
		"large_group_count": int(group_analysis.get("large_group_count", 0)),
		"group_sizes": group_analysis.get("group_sizes", []),
		"group_boxes": group_analysis.get("group_boxes", []),
		"varied_footprint_count": footprint_signatures.size(),
		"max_unique_mountains_per_chunk": max_unique_mountains_per_chunk,
	}

func _collect_components(solid_tiles: Dictionary) -> Array:
	var components: Array = []
	var visited: Dictionary = {}
	for start_tile: Vector2i in solid_tiles.keys():
		if visited.has(start_tile):
			continue
		var mountain_id: int = int(solid_tiles[start_tile])
		var queue: Array[Vector2i] = [start_tile]
		visited[start_tile] = true
		var members: Array[Vector2i] = []
		var min_tile: Vector2i = start_tile
		var max_tile: Vector2i = start_tile
		while not queue.is_empty():
			var tile: Vector2i = queue.pop_back()
			members.append(tile)
			min_tile.x = mini(min_tile.x, tile.x)
			min_tile.y = mini(min_tile.y, tile.y)
			max_tile.x = maxi(max_tile.x, tile.x)
			max_tile.y = maxi(max_tile.y, tile.y)
			for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var neighbour: Vector2i = tile + offset
				if visited.has(neighbour):
					continue
				if int(solid_tiles.get(neighbour, 0)) != mountain_id:
					continue
				visited[neighbour] = true
				queue.append(neighbour)
		components.append({
			"mountain_id": mountain_id,
			"size": members.size(),
			"members": members,
			"min": min_tile,
			"max": max_tile,
		})
	return components

func _component_touches_scan_border(component: Dictionary, min_tile: Vector2i, max_tile: Vector2i) -> bool:
	var component_min: Vector2i = component.get("min", Vector2i.ZERO) as Vector2i
	var component_max: Vector2i = component.get("max", Vector2i.ZERO) as Vector2i
	return component_min.x <= min_tile.x \
		or component_min.y <= min_tile.y \
		or component_max.x >= max_tile.x \
		or component_max.y >= max_tile.y

func _is_near_large_component(component: Dictionary, large_components: Array) -> bool:
	var component_members: Array = component.get("members", []) as Array
	for large: Dictionary in large_components:
		var large_members: Array = large.get("members", []) as Array
		for tile: Vector2i in component_members:
			for large_tile: Vector2i in large_members:
				var distance: int = abs(tile.x - large_tile.x) + abs(tile.y - large_tile.y)
				if distance <= NEAR_MAIN_MAX_DISTANCE_TILES:
					return true
	return false

func _analyze_outcrop_groups(small_components: Array, large_components: Array) -> Dictionary:
	var visited: Dictionary = {}
	var grouped_components: int = 0
	var valid_group_count: int = 0
	var large_group_count: int = 0
	var group_sizes: Array[int] = []
	var group_boxes: Array[String] = []
	for start_index: int in range(small_components.size()):
		if visited.has(start_index):
			continue
		var queue: Array[int] = [start_index]
		visited[start_index] = true
		var group_indices: Array[int] = []
		while not queue.is_empty():
			var index: int = queue.pop_back()
			group_indices.append(index)
			for next_index: int in range(small_components.size()):
				if visited.has(next_index):
					continue
				if _components_are_near(
					small_components[index] as Dictionary,
					small_components[next_index] as Dictionary
				):
					visited[next_index] = true
					queue.append(next_index)
		if group_indices.size() >= OUTCROP_CLUSTER_MIN_COMPONENTS \
				and group_indices.size() <= OUTCROP_CLUSTER_MAX_COMPONENTS \
				and _group_is_near_large_component(group_indices, small_components, large_components):
			valid_group_count += 1
			grouped_components += group_indices.size()
			if group_indices.size() >= OUTCROP_CLUSTER_LARGE_COMPONENTS:
				large_group_count += 1
		group_sizes.append(group_indices.size())
		group_boxes.append(_group_box_signature(group_indices, small_components))
	return {
		"grouped_components": grouped_components,
		"valid_group_count": valid_group_count,
		"large_group_count": large_group_count,
		"group_sizes": group_sizes,
		"group_boxes": group_boxes,
	}

func _components_are_near(a: Dictionary, b: Dictionary) -> bool:
	var a_members: Array = a.get("members", []) as Array
	var b_members: Array = b.get("members", []) as Array
	for tile: Vector2i in a_members:
		for other: Vector2i in b_members:
			var distance: int = abs(tile.x - other.x) + abs(tile.y - other.y)
			if distance <= NEAR_OUTCROP_MAX_DISTANCE_TILES:
				return true
	return false

func _group_is_near_large_component(group_indices: Array[int], small_components: Array, large_components: Array) -> bool:
	for index: int in group_indices:
		if _is_near_large_component(small_components[index] as Dictionary, large_components):
			return true
	return false

func _footprint_signature(component: Dictionary) -> String:
	var min_tile: Vector2i = component.get("min", Vector2i.ZERO) as Vector2i
	var max_tile: Vector2i = component.get("max", Vector2i.ZERO) as Vector2i
	var width: int = max_tile.x - min_tile.x + 1
	var height: int = max_tile.y - min_tile.y + 1
	var size: int = int(component.get("size", 0))
	return "%dx%d:%d" % [width, height, size]

func _is_satellite_outcrop_id(mountain_id: int) -> bool:
	return mountain_id >= SATELLITE_OUTCROP_ID_MIN and mountain_id < SATELLITE_OUTCROP_ID_MAX_EXCLUSIVE

func _group_box_signature(group_indices: Array[int], components: Array) -> String:
	var min_tile := Vector2i(1 << 30, 1 << 30)
	var max_tile := Vector2i(-(1 << 30), -(1 << 30))
	var mountain_ids: Array[int] = []
	for index: int in group_indices:
		var component: Dictionary = components[index] as Dictionary
		var mountain_id: int = int(component.get("mountain_id", 0))
		mountain_ids.append(mountain_id)
		var component_min: Vector2i = component.get("min", Vector2i.ZERO) as Vector2i
		var component_max: Vector2i = component.get("max", Vector2i.ZERO) as Vector2i
		min_tile.x = mini(min_tile.x, component_min.x)
		min_tile.y = mini(min_tile.y, component_min.y)
		max_tile.x = maxi(max_tile.x, component_max.x)
		max_tile.y = maxi(max_tile.y, component_max.y)
	return "%s..%s ids=%s" % [str(min_tile), str(max_tile), str(mountain_ids)]

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
