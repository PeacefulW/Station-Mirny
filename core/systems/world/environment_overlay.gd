class_name EnvironmentOverlay
extends RefCounted

const RuntimeDirtyQueueScript = preload("res://core/runtime/runtime_dirty_queue.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const SAVE_FORMAT_VERSION: int = 1
const WATER_DIRTY_BLOCK_SIZE: int = WorldRuntimeConstants.WATER_OVERLAY_DIRTY_BLOCK_SIZE

signal water_overlay_changed(region: Rect2i, reason: StringName)

var _overrides_by_chunk: Dictionary = {}
var _dirty_regions: RuntimeDirtyQueue = RuntimeDirtyQueueScript.new()

func set_water_class_override(
	tile_coord: Vector2i,
	water_class: int,
	reason: StringName = &"manual"
) -> bool:
	if not is_valid_water_class(water_class):
		return false
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var chunk_overrides: Dictionary = _overrides_by_chunk.get(chunk_coord, {}) as Dictionary
	if int(chunk_overrides.get(local_coord, -1)) == water_class:
		return false
	chunk_overrides[local_coord] = water_class
	_overrides_by_chunk[chunk_coord] = chunk_overrides
	_mark_tile_dirty(tile_coord, reason)
	return true

func clear_water_class_override(tile_coord: Vector2i, reason: StringName = &"manual") -> bool:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var chunk_overrides: Dictionary = _overrides_by_chunk.get(chunk_coord, {}) as Dictionary
	if not chunk_overrides.has(local_coord):
		return false
	chunk_overrides.erase(local_coord)
	if chunk_overrides.is_empty():
		_overrides_by_chunk.erase(chunk_coord)
	else:
		_overrides_by_chunk[chunk_coord] = chunk_overrides
	_mark_tile_dirty(tile_coord, reason)
	return true

func clear_all() -> void:
	_overrides_by_chunk.clear()
	_dirty_regions.clear()

func has_water_class_override(tile_coord: Vector2i) -> bool:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var chunk_overrides: Dictionary = _overrides_by_chunk.get(chunk_coord, {}) as Dictionary
	return chunk_overrides.has(local_coord)

func get_effective_water_class(tile_coord: Vector2i, default_water_class: int) -> int:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var chunk_overrides: Dictionary = _overrides_by_chunk.get(chunk_coord, {}) as Dictionary
	return int(chunk_overrides.get(local_coord, default_water_class))

func consume_dirty_regions(max_count: int) -> Array[Rect2i]:
	var regions: Array[Rect2i] = []
	var remaining: int = maxi(0, max_count)
	while remaining > 0 and _dirty_regions.has_work():
		regions.append(_dirty_regions.pop_next() as Rect2i)
		remaining -= 1
	return regions

func apply_to_packet(packet: Dictionary) -> Dictionary:
	var merged_packet: Dictionary = packet.duplicate(true)
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var chunk_overrides: Dictionary = _overrides_by_chunk.get(chunk_coord, {}) as Dictionary
	if chunk_overrides.is_empty():
		return merged_packet

	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
	if terrain_ids.is_empty() or walkable_flags.is_empty():
		return merged_packet

	for local_coord_variant: Variant in chunk_overrides.keys():
		var local_coord: Vector2i = local_coord_variant as Vector2i
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
			continue
		var water_class: int = int(chunk_overrides.get(local_coord, WorldRuntimeConstants.WATER_CLASS_NONE))
		walkable_flags[index] = 1 if is_walkable_for_water(
			int(terrain_ids[index]),
			water_class,
			int(walkable_flags[index]) != 0
		) else 0
	merged_packet["walkable_flags"] = walkable_flags
	return merged_packet

func apply_dirty_region_to_packet(packet: Dictionary, region: Rect2i) -> Dictionary:
	var merged_packet: Dictionary = packet.duplicate(true)
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var chunk_rect := Rect2i(
		chunk_coord * WorldRuntimeConstants.CHUNK_SIZE,
		Vector2i(WorldRuntimeConstants.CHUNK_SIZE, WorldRuntimeConstants.CHUNK_SIZE)
	)
	var target_region: Rect2i = chunk_rect.intersection(region)
	if target_region.size.x <= 0 or target_region.size.y <= 0:
		return merged_packet

	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = packet.get("water_class", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
	if terrain_ids.is_empty() or water_class.is_empty() or walkable_flags.is_empty():
		return merged_packet

	for y: int in range(target_region.position.y, target_region.end.y):
		for x: int in range(target_region.position.x, target_region.end.x):
			var tile_coord := Vector2i(x, y)
			var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
			var index: int = WorldRuntimeConstants.local_to_index(local_coord)
			if index < 0 or index >= terrain_ids.size() or index >= water_class.size() or index >= walkable_flags.size():
				continue
			var effective_water: int = get_effective_water_class(tile_coord, int(water_class[index]))
			walkable_flags[index] = 1 if is_walkable_for_water(
				int(terrain_ids[index]),
				effective_water,
				int(walkable_flags[index]) != 0
			) else 0
	merged_packet["walkable_flags"] = walkable_flags
	return merged_packet

func save_state() -> Dictionary:
	if _overrides_by_chunk.is_empty():
		return {}
	var overrides: Array[Dictionary] = []
	for chunk_coord: Vector2i in _sorted_chunk_coords():
		var chunk_overrides: Dictionary = _overrides_by_chunk.get(chunk_coord, {}) as Dictionary
		var local_coords: Array[Vector2i] = []
		for local_coord_variant: Variant in chunk_overrides.keys():
			local_coords.append(local_coord_variant as Vector2i)
		local_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x if a.x != b.x else a.y < b.y
		)
		for local_coord: Vector2i in local_coords:
			var tile_coord := Vector2i(
				chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE + local_coord.x,
				chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE + local_coord.y
			)
			overrides.append({
				"x": tile_coord.x,
				"y": tile_coord.y,
				"water_class": int(chunk_overrides.get(local_coord, WorldRuntimeConstants.WATER_CLASS_NONE)),
			})
	return {
		"format": SAVE_FORMAT_VERSION,
		"dirty_block_size": WATER_DIRTY_BLOCK_SIZE,
		"overrides": overrides,
	}

func load_state(data: Dictionary) -> void:
	clear_all()
	var entries: Variant = data.get("overrides", [])
	if entries is not Array:
		return
	for entry_variant: Variant in entries:
		var entry: Dictionary = entry_variant as Dictionary
		if entry.is_empty():
			continue
		var water_class: int = int(entry.get("water_class", WorldRuntimeConstants.WATER_CLASS_NONE))
		if not is_valid_water_class(water_class):
			continue
		_set_water_class_override_silent(
			Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))),
			water_class
		)
	_dirty_regions.clear()

static func is_valid_water_class(water_class: int) -> bool:
	return water_class >= WorldRuntimeConstants.WATER_CLASS_NONE \
		and water_class <= WorldRuntimeConstants.WATER_CLASS_OCEAN

static func is_walkable_for_water(terrain_id: int, water_class: int, fallback_walkable: bool = true) -> bool:
	if terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if water_class == WorldRuntimeConstants.WATER_CLASS_DEEP \
			or water_class == WorldRuntimeConstants.WATER_CLASS_OCEAN:
		return false
	if water_class == WorldRuntimeConstants.WATER_CLASS_NONE \
			or water_class == WorldRuntimeConstants.WATER_CLASS_SHALLOW:
		return true
	return fallback_walkable

func _set_water_class_override_silent(tile_coord: Vector2i, water_class: int) -> void:
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var chunk_overrides: Dictionary = _overrides_by_chunk.get(chunk_coord, {}) as Dictionary
	chunk_overrides[local_coord] = water_class
	_overrides_by_chunk[chunk_coord] = chunk_overrides

func _mark_tile_dirty(tile_coord: Vector2i, reason: StringName) -> void:
	var region: Rect2i = _dirty_region_for_tile(tile_coord)
	_dirty_regions.enqueue(region)
	water_overlay_changed.emit(region, reason)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var event_bus: Node = tree.root.get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.has_signal("water_overlay_changed"):
		event_bus.emit_signal("water_overlay_changed", region, reason)

func _dirty_region_for_tile(tile_coord: Vector2i) -> Rect2i:
	var origin := Vector2i(
		floori(float(tile_coord.x) / float(WATER_DIRTY_BLOCK_SIZE)) * WATER_DIRTY_BLOCK_SIZE,
		floori(float(tile_coord.y) / float(WATER_DIRTY_BLOCK_SIZE)) * WATER_DIRTY_BLOCK_SIZE
	)
	return Rect2i(origin, Vector2i(WATER_DIRTY_BLOCK_SIZE, WATER_DIRTY_BLOCK_SIZE))

func _sorted_chunk_coords() -> Array[Vector2i]:
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _overrides_by_chunk.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return chunk_coords
