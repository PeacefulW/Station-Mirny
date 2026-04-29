extends SceneTree

const EnvironmentOverlay = preload("res://core/systems/world/environment_overlay.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failed: bool = false
var _event_count: int = 0
var _last_event_region: Rect2i = Rect2i()
var _last_event_reason: StringName = &""

func _init() -> void:
	var event_bus_source: String = FileAccess.get_file_as_string("res://core/autoloads/event_bus.gd")
	_assert(
		event_bus_source.contains("signal water_overlay_changed(region: Rect2i, reason: StringName)"),
		"EventBus must declare the V1-R6 water_overlay_changed signal"
	)

	var overlay := EnvironmentOverlay.new()
	overlay.water_overlay_changed.connect(_on_water_overlay_changed)
	var tile := Vector2i(17, 33)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var packet: Dictionary = _build_packet(chunk_coord)

	var default_packet: Dictionary = overlay.apply_to_packet(packet)
	var default_walkable: PackedByteArray = default_packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var default_water: PackedByteArray = default_packet.get("water_class", PackedByteArray()) as PackedByteArray
	_assert(int(default_walkable[index]) == 0, "deep default river water should block before override")
	_assert(int(default_water[index]) == WorldRuntimeConstants.WATER_CLASS_DEEP, "apply_to_packet must keep seed-derived default water_class immutable")

	_assert(
		overlay.set_water_class_override(tile, WorldRuntimeConstants.WATER_CLASS_NONE, &"test_dry"),
		"setting an explicit dry override should report a mutation"
	)
	_assert(_event_count == 1, "explicit water override should emit one water_overlay_changed event")
	_assert(_last_event_region == Rect2i(16, 32, 16, 16), "dirty unit should be the aligned 16x16 water block")
	_assert(_last_event_reason == &"test_dry", "water overlay event should carry the reason")
	_assert(
		overlay.get_effective_water_class(tile, WorldRuntimeConstants.WATER_CLASS_DEEP) == WorldRuntimeConstants.WATER_CLASS_NONE,
		"explicit override should replace the packet default water class at read time"
	)

	var dirty_regions: Array[Rect2i] = overlay.consume_dirty_regions(8)
	_assert(dirty_regions.size() == 1, "one dirty block should be queued for one tile override")
	_assert(dirty_regions[0] == Rect2i(16, 32, 16, 16), "queued dirty block should match the emitted region")
	_assert(overlay.consume_dirty_regions(8).is_empty(), "dirty regions should be consumed, not persisted")

	var dried_packet: Dictionary = overlay.apply_to_packet(packet)
	var dried_walkable: PackedByteArray = dried_packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var dried_water: PackedByteArray = dried_packet.get("water_class", PackedByteArray()) as PackedByteArray
	_assert(int(dried_walkable[index]) == 1, "dry riverbed override should make the tile walkable")
	_assert(int(dried_water[index]) == WorldRuntimeConstants.WATER_CLASS_DEEP, "runtime overlay must not rewrite the packet water_class array")

	var saved: Dictionary = overlay.save_state()
	_assert(saved.has("overrides"), "explicit water overrides should have an approved save shape")
	_assert(not saved.has("dirty_regions"), "dirty queue state must remain transient and unsaved")

	var loaded_overlay := EnvironmentOverlay.new()
	loaded_overlay.load_state(saved)
	_assert(loaded_overlay.consume_dirty_regions(8).is_empty(), "loading water overlay state should not enqueue runtime dirty work")
	_assert(
		loaded_overlay.get_effective_water_class(tile, WorldRuntimeConstants.WATER_CLASS_DEEP) == WorldRuntimeConstants.WATER_CLASS_NONE,
		"loaded explicit override should restore effective current water class"
	)
	var loaded_packet: Dictionary = loaded_overlay.apply_to_packet(packet)
	var loaded_walkable: PackedByteArray = loaded_packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	_assert(int(loaded_walkable[index]) == 1, "loaded dry override should apply to regenerated packet walkability")

	_assert(
		overlay.clear_water_class_override(tile, &"test_refill"),
		"clearing an explicit override should report a mutation"
	)
	_assert(_event_count == 2, "clearing an override should emit one EventBus event")
	var cleared_packet: Dictionary = overlay.apply_to_packet(packet)
	var cleared_walkable: PackedByteArray = cleared_packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	_assert(int(cleared_walkable[index]) == 0, "clearing override should restore default deep-water blocking")

	var mountain_tile := Vector2i(18, 33)
	var mountain_local: Vector2i = WorldRuntimeConstants.tile_to_local(mountain_tile)
	var mountain_index: int = WorldRuntimeConstants.local_to_index(mountain_local)
	var mountain_packet: Dictionary = _build_packet(chunk_coord)
	var terrain_ids: PackedInt32Array = mountain_packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var water_class: PackedByteArray = mountain_packet.get("water_class", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = mountain_packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	terrain_ids[mountain_index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	water_class[mountain_index] = WorldRuntimeConstants.WATER_CLASS_NONE
	walkable_flags[mountain_index] = 0
	mountain_packet["terrain_ids"] = terrain_ids
	mountain_packet["water_class"] = water_class
	mountain_packet["walkable_flags"] = walkable_flags
	overlay.set_water_class_override(mountain_tile, WorldRuntimeConstants.WATER_CLASS_SHALLOW, &"test_shallow")
	var wet_mountain_packet: Dictionary = overlay.apply_to_packet(mountain_packet)
	var wet_mountain_walkable: PackedByteArray = wet_mountain_packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	_assert(int(wet_mountain_walkable[mountain_index]) == 0, "water overlay must not make mountain wall terrain walkable")

	if _failed:
		quit(1)
		return
	print("water_overlay_seam_smoke_test: OK")
	quit(0)

func _build_packet(chunk_coord: Vector2i) -> Dictionary:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var water_class := PackedByteArray()
	water_class.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		water_class[index] = WorldRuntimeConstants.WATER_CLASS_NONE
		walkable_flags[index] = 1
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(Vector2i(17, 33))
	var river_index: int = WorldRuntimeConstants.local_to_index(local_coord)
	terrain_ids[river_index] = WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP
	water_class[river_index] = WorldRuntimeConstants.WATER_CLASS_DEEP
	walkable_flags[river_index] = 0
	return {
		"chunk_coord": chunk_coord,
		"terrain_ids": terrain_ids,
		"water_class": water_class,
		"walkable_flags": walkable_flags,
	}

func _on_water_overlay_changed(region: Rect2i, reason: StringName) -> void:
	_event_count += 1
	_last_event_region = region
	_last_event_reason = reason

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
