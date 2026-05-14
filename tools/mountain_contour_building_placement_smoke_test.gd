extends SceneTree

const MountainContourCollisionCache = preload("res://core/systems/world/mountain_contour_collision_cache.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_contour_building_placement_smoke_test"
const REPORT_PATH: String = "%s/report.json" % OUTPUT_DIR

var _failed: bool = false
var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	if _failed:
		_write_report()
		quit(1)
		return

	_assert_missing_cache_blocks_mountain_placement()
	_assert_missing_cache_does_not_block_unrelated_chunk_seam_placement()
	_assert_logical_mountain_square_does_not_block_clear_contour_footprint()
	_assert_visible_lower_footprint_blocks_placement()
	_assert_non_contour_blocked_tile_still_blocks_placement()
	_assert_ground_shape_clear_without_contour_collision()

	if _failed:
		_write_report()
		quit(1)
		return
	_write_report()
	print("mountain_contour_building_placement_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("func is_placement_shape_clear"),
		"WorldStreamer must expose is_placement_shape_clear(world_shape)."
	)
	_assert(
		_function_body(streamer_source, "is_placement_shape_clear").contains("intersects_building_footprint"),
		"Placement shape query must use contour collision footprint loops."
	)
	_assert(
		_function_body(streamer_source, "is_placement_shape_clear").contains("_is_world_shape_clear_for_non_contour_terrain"),
		"Placement shape query must preserve ordinary non-contour terrain blocking."
	)

	var building_source: String = FileAccess.get_file_as_string("res://core/systems/building/building_system.gd")
	_assert(
		building_source.contains("is_placement_shape_clear"),
		"Building placement must call WorldStreamer.is_placement_shape_clear(...)."
	)
	_assert(
		building_source.contains("_build_selected_placement_world_shape"),
		"Building placement must keep grid anchoring separate from the collision footprint shape."
	)

func _assert_missing_cache_blocks_mountain_placement() -> void:
	var streamer: WorldStreamer = _build_streamer([Vector2i.ZERO], [])
	_assert(
		not streamer.is_placement_shape_clear(Rect2(Vector2(0.0, 0.0), Vector2(12.0, 12.0))),
		"Missing contour cache must block placement near contour-owned mountain terrain."
	)
	streamer.free()

func _assert_missing_cache_does_not_block_unrelated_chunk_seam_placement() -> void:
	var streamer: WorldStreamer = _build_streamer([], [])
	streamer._chunk_packets[Vector2i(1, 0)] = _build_packet(Vector2i(1, 0), [
		Vector2i(15, 15),
	], [])
	_assert(
		streamer.is_placement_shape_clear(Rect2(Vector2(984.0, 16.0), Vector2(24.0, 24.0))),
		"Missing contour cache in a neighbouring chunk must not block placement on unrelated seam ground."
	)
	streamer.free()

func _assert_logical_mountain_square_does_not_block_clear_contour_footprint() -> void:
	var streamer: WorldStreamer = _build_streamer([Vector2i.ZERO], [])
	var loop: PackedVector2Array = _rect_loop(Rect2(16.0, 16.0, 48.0, 48.0))
	_install_collision_cache(streamer, Vector2i.ZERO, [loop])

	var clear_corner_shape := Rect2(Vector2(0.0, 0.0), Vector2(12.0, 12.0))
	_assert(
		not streamer.is_raw_tile_walkable_at_world(clear_corner_shape.get_center()),
		"Raw logical mountain square must remain blocked."
	)
	_assert(
		streamer.is_placement_shape_clear(clear_corner_shape),
		"Placement must pass when contour geometry leaves a logical mountain square corner clear."
	)
	streamer.free()

func _assert_visible_lower_footprint_blocks_placement() -> void:
	var streamer: WorldStreamer = _build_streamer([Vector2i.ZERO], [])
	var loop: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 64.0, 99.0))
	_install_collision_cache(streamer, Vector2i.ZERO, [loop])

	var lower_footprint_shape := Rect2(Vector2(24.0, 80.0), Vector2(16.0, 16.0))
	_assert(
		streamer.is_raw_tile_walkable_at_world(lower_footprint_shape.get_center()),
		"Raw lower-footprint placement center must be a normal walkable ground tile."
	)
	_assert(
		not streamer.is_placement_shape_clear(lower_footprint_shape),
		"Placement must fail when a shape intersects the visible lower mountain footprint."
	)
	streamer.free()

func _assert_non_contour_blocked_tile_still_blocks_placement() -> void:
	var streamer: WorldStreamer = _build_streamer([], [Vector2i(2, 0)])
	_assert(
		not streamer.is_placement_shape_clear(Rect2(Vector2(128.0, 0.0), Vector2(16.0, 16.0))),
		"Ordinary non-contour blocked terrain must still block placement."
	)
	streamer.free()

func _assert_ground_shape_clear_without_contour_collision() -> void:
	var streamer: WorldStreamer = _build_streamer([], [])
	_assert(
		streamer.is_placement_shape_clear(Rect2(Vector2(128.0, 128.0), Vector2(32.0, 32.0))),
		"Ordinary ground placement shape must pass without requiring contour cache."
	)
	streamer.free()

func _build_streamer(mountain_locals: Array[Vector2i], blocked_locals: Array[Vector2i]) -> WorldStreamer:
	var streamer := WorldStreamer.new()
	streamer._chunk_packets[Vector2i.ZERO] = _build_packet(Vector2i.ZERO, mountain_locals, blocked_locals)
	return streamer

func _build_packet(
	chunk_coord: Vector2i,
	mountain_locals: Array[Vector2i],
	blocked_locals: Array[Vector2i]
) -> Dictionary:
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
	for local_coord: Vector2i in blocked_locals:
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED
		walkable_flags[index] = 0
	for local_coord: Vector2i in mountain_locals:
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		walkable_flags[index] = 0
		mountain_ids[index] = 23
		mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	return {
		"chunk_coord": chunk_coord,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _install_collision_cache(streamer: WorldStreamer, chunk_coord: Vector2i, loops: Array) -> void:
	var aabbs: Array[Rect2] = []
	for loop_variant: Variant in loops:
		aabbs.append(_loop_aabb(loop_variant as PackedVector2Array))
	var cache := MountainContourCollisionCache.new()
	cache.configure(chunk_coord, loops, aabbs)
	streamer._mountain_contour_collision_caches[chunk_coord] = cache
	streamer._mountain_contour_runtime_debug_snapshots[chunk_coord] = {
		"ready": true,
		"collision_ready": true,
		"runtime_revision": 1,
		"collision_revision": 1,
	}

func _rect_loop(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Vector2(rect.position.x, rect.position.y + rect.size.y),
	])

func _loop_aabb(loop: PackedVector2Array) -> Rect2:
	if loop.is_empty():
		return Rect2()
	var min_x: float = loop[0].x
	var min_y: float = loop[0].y
	var max_x: float = loop[0].x
	var max_y: float = loop[0].y
	for point: Vector2 in loop:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _function_body(source: String, function_name: String) -> String:
	var start: int = source.find("func %s" % [function_name])
	if start < 0:
		return ""
	var next: int = source.find("\nfunc ", start + 1)
	if next < 0:
		return source.substr(start)
	return source.substr(start, next - start)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_errors.append(message)
	_failed = true

func _write_report() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR).replace("\\", "/")
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		push_error("Failed to create report directory %s: %d" % [absolute_dir, err])
		return
	var file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if file == null:
		push_error("Failed to open report %s: %d" % [REPORT_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({
		"ok": not _failed,
		"errors": _errors,
	}, "\t"))
	file.close()
