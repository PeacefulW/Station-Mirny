extends SceneTree

const MountainContourCollisionCache = preload("res://core/systems/world/mountain_contour_collision_cache.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_contour_movement_smoke_test"
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

	_assert_missing_cache_blocks_mountain_query()
	_assert_missing_cache_does_not_block_unrelated_chunk_seam_ground()
	_assert_logical_square_corner_uses_contour_cache()
	_assert_visible_lower_footprint_blocks_ground_tile()
	_assert_diagonal_gap_uses_capsule_width()
	_assert_contour_slide_moves_along_collision_edge()

	if _failed:
		_write_report()
		quit(1)
		return
	_write_report()
	print("mountain_contour_movement_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("func is_raw_tile_walkable_at_world"),
		"WorldStreamer must keep raw tile walkability separate from contour movement walkability."
	)
	_assert(
		streamer_source.contains("func is_capsule_walkable_at_world"),
		"WorldStreamer must expose capsule movement walkability."
	)
	_assert(
		streamer_source.contains("func move_capsule_with_contour_slide"),
		"WorldStreamer must expose contour slide movement."
	)
	_assert(
		_function_body(streamer_source, "is_walkable_at_world").contains("is_capsule_walkable_at_world"),
		"Point walkability must adapt to the capsule contour movement query."
	)
	_assert(
		_function_body(streamer_source, "is_capsule_walkable_at_world").contains("_query_mountain_contour_collision_for_capsule"),
		"Capsule movement walkability must query the mountain contour collision cache."
	)

	var player_source: String = FileAccess.get_file_as_string("res://core/entities/player/player.gd")
	_assert(
		player_source.contains("move_capsule_with_contour_slide"),
		"Player terrain blocking must use the contour slide movement API."
	)
	_assert(
		player_source.contains("Callable(chunk_manager, \"is_raw_tile_walkable_at_world\")"),
		"Player harvest ray must keep using raw tile walkability instead of contour movement walkability."
	)

func _assert_missing_cache_blocks_mountain_query() -> void:
	var streamer: WorldStreamer = _build_streamer([
		Vector2i.ZERO,
	])
	_assert(
		not streamer.is_capsule_walkable_at_world(Vector2(8.0, 8.0), 4.0),
		"Missing contour cache must block near contour-owned mountain terrain instead of falling back to square walkable flags."
	)
	streamer.free()

func _assert_missing_cache_does_not_block_unrelated_chunk_seam_ground() -> void:
	var streamer: WorldStreamer = _build_streamer([])
	streamer._chunk_packets[Vector2i(1, 0)] = _build_packet(Vector2i(1, 0), [
		Vector2i(15, 15),
	])
	_assert(
		streamer.is_capsule_walkable_at_world(Vector2(1008.0, 32.0), 4.0),
		"Missing contour cache in a neighbouring chunk must not create an invisible wall on unrelated seam ground."
	)
	streamer.free()

func _assert_logical_square_corner_uses_contour_cache() -> void:
	var streamer: WorldStreamer = _build_streamer([
		Vector2i.ZERO,
	])
	var loop: PackedVector2Array = _rect_loop(Rect2(16.0, 16.0, 48.0, 48.0))
	_install_collision_cache(streamer, Vector2i.ZERO, [loop])

	_assert(
		streamer.is_raw_tile_walkable_at_world(Vector2(8.0, 8.0)) == false,
		"Raw logical mountain tile walkability must remain blocked."
	)
	_assert(
		streamer.is_capsule_walkable_at_world(Vector2(8.0, 8.0), 4.0),
		"Movement must pass a logical mountain square corner when contour geometry leaves it outside the footprint."
	)
	_assert(
		not streamer.is_capsule_walkable_at_world(Vector2(32.0, 32.0), 4.0),
		"Movement must still block inside the contour collision footprint."
	)
	streamer.free()

func _assert_visible_lower_footprint_blocks_ground_tile() -> void:
	var streamer: WorldStreamer = _build_streamer([
		Vector2i.ZERO,
	])
	var loop: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 64.0, 99.0))
	_install_collision_cache(streamer, Vector2i.ZERO, [loop])

	var lower_footprint_world := Vector2(32.0, 88.0)
	_assert(
		streamer.is_raw_tile_walkable_at_world(lower_footprint_world),
		"Raw lower-footprint sample must be a normal walkable ground tile."
	)
	_assert(
		not streamer.is_capsule_walkable_at_world(lower_footprint_world, 4.0),
		"Movement must block the visible lower mountain footprint even when the square tile is ground."
	)
	streamer.free()

func _assert_diagonal_gap_uses_capsule_width() -> void:
	var streamer: WorldStreamer = _build_streamer([
		Vector2i(0, 0),
		Vector2i(1, 1),
	])
	var north_west: PackedVector2Array = _rect_loop(Rect2(0.0, 0.0, 64.0, 64.0))
	var south_east: PackedVector2Array = _rect_loop(Rect2(96.0, 96.0, 64.0, 64.0))
	_install_collision_cache(streamer, Vector2i.ZERO, [north_west, south_east])

	var gap_center := Vector2(80.0, 80.0)
	_assert(
		streamer.is_capsule_walkable_at_world(gap_center, 16.0),
		"Diagonal gap must pass when contour geometry says the capsule fits."
	)
	_assert(
		not streamer.is_capsule_walkable_at_world(gap_center, 24.0),
		"Diagonal gap must block when the capsule radius overlaps contour collision."
	)
	streamer.free()

func _assert_contour_slide_moves_along_collision_edge() -> void:
	var streamer: WorldStreamer = _build_streamer([
		Vector2i(2, 0),
	])
	var loop: PackedVector2Array = _rect_loop(Rect2(128.0, 0.0, 64.0, 99.0))
	_install_collision_cache(streamer, Vector2i.ZERO, [loop])

	var slide: Dictionary = streamer.move_capsule_with_contour_slide(
		Vector2(112.0, 32.0),
		Vector2(40.0, 24.0),
		8.0
	)
	var final_position: Vector2 = slide.get("final_position", Vector2.INF) as Vector2
	var motion_applied: Vector2 = slide.get("motion_applied", Vector2.ZERO) as Vector2
	_assert(bool(slide.get("collided", false)), "Contour slide must report a collision.")
	_assert(
		motion_applied.length() > 0.1,
		"Contour slide must preserve safe tangent motion instead of snagging completely."
	)
	_assert(
		final_position.x <= 120.0 + 0.5,
		"Contour slide must not penetrate the contour footprint."
	)
	_assert(
		final_position.y > 32.0,
		"Contour slide must move along the collision edge."
	)
	streamer.free()

func _build_streamer(mountain_locals: Array[Vector2i]) -> WorldStreamer:
	var streamer := WorldStreamer.new()
	streamer._chunk_packets[Vector2i.ZERO] = _build_packet(Vector2i.ZERO, mountain_locals)
	return streamer

func _build_packet(chunk_coord: Vector2i, mountain_locals: Array[Vector2i]) -> Dictionary:
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
	for local_coord: Vector2i in mountain_locals:
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		walkable_flags[index] = 0
		mountain_ids[index] = 11
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
