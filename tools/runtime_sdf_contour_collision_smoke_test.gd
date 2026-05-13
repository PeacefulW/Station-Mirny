extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const DIFF_REVISION: int = 5
const COLLISION_SAMPLE_PX: int = 32
const COLLISION_SIDE: int = 33

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	if _failed:
		quit(1)
		return

	_assert_missing_collision_fails_closed()
	_assert_stale_collision_fails_closed()
	_assert_contour_movement_and_raw_tile_split()
	_assert_seam_sampling_uses_neighbor_chunk_field()

	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_collision_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("func is_movement_blocked_at_world"),
		"WorldStreamer must expose is_movement_blocked_at_world(world_pos)."
	)
	_assert(
		streamer_source.contains("func is_raw_tile_walkable_at_world"),
		"WorldStreamer must expose is_raw_tile_walkable_at_world(world_pos)."
	)
	_assert(
		streamer_source.contains("func get_effective_tile_data_at_world"),
		"WorldStreamer must expose get_effective_tile_data_at_world(world_pos)."
	)
	var player_source: String = FileAccess.get_file_as_string("res://core/entities/player/player.gd")
	_assert(
		player_source.contains("chunk_manager.is_walkable_at_world(point)"),
		"Player footprint sampling must keep using contour-aware is_walkable_at_world()."
	)
	_assert(
		player_source.contains("Callable(chunk_manager, \"is_raw_tile_walkable_at_world\")"),
		"Player harvest ray must use raw tile walkability, not contour-aware movement walkability."
	)
	var system_api_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/system_api.md")
	_assert(
		system_api_source.contains("is_movement_blocked_at_world(world_pos: Vector2)"),
		"system_api.md must document contour-aware movement blocking."
	)
	_assert(
		system_api_source.contains("is_raw_tile_walkable_at_world(world_pos: Vector2)"),
		"system_api.md must document raw tile walkability."
	)
	_assert(
		system_api_source.contains("get_effective_tile_data_at_world(world_pos: Vector2)"),
		"system_api.md must document raw effective tile data."
	)

func _assert_missing_collision_fails_closed() -> void:
	var streamer: WorldStreamer = _build_streamer_with_packet(Vector2i.ZERO, _build_packet({}))
	var world_pos := Vector2(160.0, 160.0)
	_assert(streamer.is_raw_tile_walkable_at_world(world_pos), "Raw ground tile walkability must remain true.")
	_assert(
		not streamer.is_walkable_at_world(world_pos),
		"Movement must fail closed while contour collision data is missing."
	)
	_assert(
		streamer.is_movement_blocked_at_world(world_pos),
		"Missing contour collision data must be movement-blocking."
	)
	streamer.free()

func _assert_stale_collision_fails_closed() -> void:
	var streamer: WorldStreamer = _build_streamer_with_packet(Vector2i.ZERO, _build_packet({}))
	streamer._contour_diff_revision = DIFF_REVISION
	streamer._contour_results_by_chunk[Vector2i.ZERO] = {
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: _build_collision_result(Vector2i.ZERO, DIFF_REVISION - 1, -8.0),
	}
	var world_pos := Vector2(160.0, 160.0)
	_assert(streamer.is_raw_tile_walkable_at_world(world_pos), "Raw ground tile walkability must remain true with stale contour data.")
	_assert(
		not streamer.is_walkable_at_world(world_pos),
		"Movement must fail closed while contour collision data is stale."
	)
	streamer.free()

func _assert_contour_movement_and_raw_tile_split() -> void:
	var mountain_locals: Dictionary = {
		Vector2i(0, 0): true,
		Vector2i(1, 1): true,
	}
	var streamer: WorldStreamer = _build_streamer_with_packet(Vector2i.ZERO, _build_packet(mountain_locals))
	streamer._contour_diff_revision = DIFF_REVISION
	var collision_values := PackedFloat32Array()
	collision_values.resize(COLLISION_SIDE * COLLISION_SIDE)
	collision_values.fill(-8.0)
	collision_values[1 * COLLISION_SIDE + 1] = -8.0
	collision_values[3 * COLLISION_SIDE + 3] = 8.0
	streamer._contour_results_by_chunk[Vector2i.ZERO] = {
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: _build_collision_result(Vector2i.ZERO, DIFF_REVISION, -8.0, collision_values),
	}

	var rounded_corner_outside := Vector2(32.0, 32.0)
	var mountain_inside := Vector2(96.0, 96.0)
	var raw_tile_data: Dictionary = streamer.get_effective_tile_data_at_world(rounded_corner_outside)
	_assert(bool(raw_tile_data.get("ready", false)), "Raw effective tile data must be ready for a loaded chunk.")
	_assert(
		int(raw_tile_data.get("terrain_id", -1)) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
		"Raw effective tile data must preserve the logical mountain terrain id."
	)
	_assert(
		not streamer.is_raw_tile_walkable_at_world(rounded_corner_outside),
		"Raw tile walkability must keep logical mountain blocking semantics."
	)
	_assert(
		streamer.is_walkable_at_world(rounded_corner_outside),
		"Movement must allow a logical mountain tile point outside the visible rounded contour."
	)
	_assert(
		not streamer.is_walkable_at_world(mountain_inside),
		"Movement must block inside visible mountain occupancy."
	)
	_assert(
		streamer.is_movement_blocked_at_world(mountain_inside),
		"Movement blocking read must report visible mountain occupancy."
	)
	streamer.free()

func _assert_seam_sampling_uses_neighbor_chunk_field() -> void:
	var streamer := WorldStreamer.new()
	streamer._contour_diff_revision = DIFF_REVISION
	streamer._chunk_packets[Vector2i.ZERO] = _build_packet({})
	streamer._chunk_packets[Vector2i(1, 0)] = _build_packet({})
	streamer._contour_results_by_chunk[Vector2i.ZERO] = {
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: _build_collision_result(Vector2i.ZERO, DIFF_REVISION, 8.0),
	}
	streamer._contour_results_by_chunk[Vector2i(1, 0)] = {
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS: _build_collision_result(Vector2i(1, 0), DIFF_REVISION, -8.0),
	}

	var left_chunk_pos := Vector2(float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX) - 32.0, 32.0)
	var right_chunk_pos := Vector2(float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX) + 32.0, 32.0)
	_assert(
		not streamer.is_walkable_at_world(left_chunk_pos),
		"Movement must sample the left chunk collision field before the seam."
	)
	_assert(
		streamer.is_walkable_at_world(right_chunk_pos),
		"Movement must sample the right chunk collision field after the seam."
	)
	streamer.free()

func _build_streamer_with_packet(chunk_coord: Vector2i, packet: Dictionary) -> WorldStreamer:
	var streamer := WorldStreamer.new()
	streamer._chunk_packets[chunk_coord] = packet
	return streamer

func _build_packet(mountain_locals: Dictionary) -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var terrain_atlas_indices := PackedInt32Array()
	var walkable_flags := PackedByteArray()
	var lake_flags := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	var mountain_atlas_indices := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		walkable_flags[index] = 1
	for local_variant: Variant in mountain_locals.keys():
		var local_coord: Vector2i = local_variant as Vector2i
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		walkable_flags[index] = 0
		mountain_ids[index] = 1
		mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	return {
		"chunk_coord": Vector2i.ZERO,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _build_collision_result(
	chunk_coord: Vector2i,
	diff_revision: int,
	fill_value: float,
	values: PackedFloat32Array = PackedFloat32Array()
) -> Dictionary:
	var collision_values: PackedFloat32Array = values
	if collision_values.is_empty():
		collision_values.resize(COLLISION_SIDE * COLLISION_SIDE)
		collision_values.fill(fill_value)
	return {
		"chunk_coord": chunk_coord,
		"contour_class": WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
		"recipe_id": WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
		"diff_revision": diff_revision,
		"collision_sdf_f32": collision_values,
		"collision_origin_world_px": WorldRuntimeConstants.chunk_origin_px(chunk_coord),
		"collision_sample_px": COLLISION_SAMPLE_PX,
		"collision_size": Vector2i(COLLISION_SIDE, COLLISION_SIDE),
		"collision_blocks_inside": true,
		"ready": true,
	}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
