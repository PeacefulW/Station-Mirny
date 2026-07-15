extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HALO_RADIUS_TILES: int = 8
const PIXELS_PER_TILE: int = 8
const EPOCH: int = 41
const REVISION: int = 7
const RESULT_TIMEOUT_MSEC: int = 8000
const WEST_CHUNK: Vector2i = Vector2i(0, 0)
const EAST_CHUNK: Vector2i = Vector2i(1, 0)

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var backend := WorldChunkPacketBackend.new()
	_assert(
		backend.has_method("queue_mountain_halo_mask_request"),
		"WorldChunkPacketBackend must queue chunk-owned native halo-mask work.",
	)
	_assert(
		backend.has_method("drain_completed_mountain_halo_masks"),
		"WorldChunkPacketBackend must expose completed native halo masks.",
	)
	_assert(
		backend.has_method("has_completed_mountain_halo_masks"),
		"WorldChunkPacketBackend must expose native halo-mask readiness.",
	)
	if _failed:
		quit(1)
		return

	var solid_world_tiles: Dictionary = _build_seam_mountain_tiles()
	backend.start(1)
	_queue_mask(backend, WEST_CHUNK, solid_world_tiles)
	_queue_mask(backend, EAST_CHUNK, solid_world_tiles)
	var results: Array[Dictionary] = await _await_mask_results(backend, 2)
	backend.stop()

	_assert(results.size() == 2, "Both adjacent chunk halo-mask jobs must complete before timeout.")
	if results.size() == 2:
		var west_result: Dictionary = _find_result(results, WEST_CHUNK)
		var east_result: Dictionary = _find_result(results, EAST_CHUNK)
		_assert(not west_result.is_empty(), "West chunk native mask result is missing.")
		_assert(not east_result.is_empty(), "East chunk native mask result is missing.")
		if not west_result.is_empty() and not east_result.is_empty():
			_assert_result_contract(west_result, WEST_CHUNK, solid_world_tiles)
			_assert_result_contract(east_result, EAST_CHUNK, solid_world_tiles)
			_assert_overlap_is_seam_identical(west_result, east_result)
			await _assert_chunk_view_byte_readiness(west_result, east_result)

	if _failed:
		quit(1)
		return
	print("runtime_mountain_raster_smoke_test: PASS")
	quit(0)


func _queue_mask(
		backend: WorldChunkPacketBackend,
		chunk_coord: Vector2i,
		solid_world_tiles: Dictionary,
) -> void:
	backend.queue_mountain_halo_mask_request(
		_build_halo(chunk_coord, solid_world_tiles),
		chunk_coord,
		_mask_origin_world(chunk_coord),
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		PIXELS_PER_TILE,
		EPOCH,
		REVISION,
		&"smoke_seam",
		&"mountain",
		PackedByteArray(),
		PackedByteArray(),
		0,
		WorldChunkPacketBackend.PRIORITY_CLASS_REVEAL,
	)


func _await_mask_results(
		backend: WorldChunkPacketBackend,
		expected_count: int,
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var deadline_msec: int = Time.get_ticks_msec() + RESULT_TIMEOUT_MSEC
	while results.size() < expected_count and Time.get_ticks_msec() < deadline_msec:
		results.append_array(
			backend.drain_completed_mountain_halo_masks(expected_count - results.size()),
		)
		if results.size() >= expected_count:
			break
		await process_frame
	return results


func _assert_result_contract(
		result: Dictionary,
		chunk_coord: Vector2i,
		solid_world_tiles: Dictionary,
) -> void:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + HALO_RADIUS_TILES * 2
	var expected_side_px: int = halo_side * PIXELS_PER_TILE
	var mask: PackedByteArray = result.get("mask", PackedByteArray()) as PackedByteArray
	_assert(bool(result.get("success", false)), "Native halo-mask worker result must succeed.")
	_assert(
		(result.get("target_chunk", Vector2i(-1, -1)) as Vector2i) == chunk_coord,
		"Native halo-mask result must retain target chunk ownership.",
	)
	_assert(int(result.get("epoch", -1)) == EPOCH, "Native halo-mask result must retain epoch.")
	_assert(int(result.get("revision", -1)) == REVISION, "Native halo-mask result must retain revision.")
	_assert(
		(result.get("reason", &"") as StringName) == &"smoke_seam",
		"Native halo-mask result must retain request reason.",
	)
	_assert(
		(result.get("mask_purpose", &"") as StringName) == &"mountain",
		"Native halo-mask result must remain a mountain mask, not a retired render page.",
	)
	_assert(int(result.get("halo_side", 0)) == halo_side, "Native result must preserve halo geometry.")
	_assert(
		int(result.get("halo_radius_tiles", -1)) == HALO_RADIUS_TILES,
		"Native result must report the chunk-owned halo radius.",
	)
	_assert(int(result.get("width", 0)) == expected_side_px, "Native mask width must match halo resolution.")
	_assert(int(result.get("height", 0)) == expected_side_px, "Native mask height must match halo resolution.")
	_assert(mask.size() == expected_side_px * expected_side_px, "Native L8 mask byte count must be exact.")
	_assert(
		is_equal_approx(
			float(result.get("step_px", 0.0)),
			float(WorldRuntimeConstants.TILE_SIZE_PX) / float(PIXELS_PER_TILE),
		),
		"Native mask step must match pixels-per-tile resolution.",
	)
	_assert(
		int(result.get("solid_sample_count", -1)) == _count_owned_solid_tiles(chunk_coord, solid_world_tiles),
		"Native solid-sample telemetry must count only the owning chunk interior.",
	)
	_assert(
		(result.get("mask_origin_world", Vector2(INF, INF)) as Vector2).is_equal_approx(
			_mask_origin_world(chunk_coord),
		),
		"Worker result must retain the world-aligned halo origin.",
	)


func _assert_overlap_is_seam_identical(west_result: Dictionary, east_result: Dictionary) -> void:
	var step_px: float = float(west_result.get("step_px", 0.0))
	var seam_x: float = float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
	var compared_samples: int = 0
	for sample_y: int in range(4 * WorldRuntimeConstants.TILE_SIZE_PX, 14 * WorldRuntimeConstants.TILE_SIZE_PX, 16):
		for offset_index: int in range(-8, 9):
			var world_pos := Vector2(
				seam_x + (float(offset_index) + 0.5) * step_px,
				float(sample_y) + step_px * 0.5,
			)
			var west_value: int = _sample_result_byte(west_result, world_pos)
			var east_value: int = _sample_result_byte(east_result, world_pos)
			_assert(west_value >= 0 and east_value >= 0, "Compared seam samples must lie in both chunk halos.")
			if west_value < 0 or east_value < 0:
				continue
			_assert(
				west_value == east_value,
				"Adjacent chunk masks must be byte-identical in their shared world-space seam band.",
			)
			compared_samples += 1
	_assert(compared_samples >= 100, "Seam contract must compare a meaningful overlap sample set.")


func _assert_chunk_view_byte_readiness(
		west_result: Dictionary,
		east_result: Dictionary,
) -> void:
	var west_view := ChunkView.new()
	var east_view := ChunkView.new()
	root.add_child(west_view)
	root.add_child(east_view)
	west_view.configure(WEST_CHUNK)
	east_view.configure(EAST_CHUNK)
	_assert(
		west_view.apply_mountain_native_mask_data(west_result, _mask_origin_world(WEST_CHUNK)),
		"ChunkView must accept a valid west native halo mask.",
	)
	_assert(
		east_view.apply_mountain_native_mask_data(east_result, _mask_origin_world(EAST_CHUNK)),
		"ChunkView must accept a valid east native halo mask.",
	)

	var solid_world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(Vector2i(15, 8))
	var empty_world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(Vector2i(16, 2))
	var west_solid: Dictionary = west_view.sample_mountain_page_hit_at_world(solid_world_pos)
	var east_solid: Dictionary = east_view.sample_mountain_page_hit_at_world(solid_world_pos)
	var west_empty: Dictionary = west_view.sample_mountain_page_hit_at_world(empty_world_pos)
	var east_empty: Dictionary = east_view.sample_mountain_page_hit_at_world(empty_world_pos)
	_assert(
		bool(west_solid.get("ready", false)) and bool(west_solid.get("in_bounds", false))
				and bool(west_solid.get("solid", false)),
		"Owning ChunkView must expose gameplay-ready solid bytes before texture upload.",
	)
	_assert(
		bool(east_solid.get("ready", false)) and bool(east_solid.get("in_bounds", false))
				and bool(east_solid.get("solid", false)),
		"Neighbour ChunkView halo must agree on the same solid seam sample.",
	)
	_assert(
		bool(west_empty.get("ready", false)) and bool(west_empty.get("in_bounds", false))
				and not bool(west_empty.get("solid", true)),
		"Owning ChunkView must expose open native-mask bytes.",
	)
	_assert(
		bool(east_empty.get("ready", false)) and bool(east_empty.get("in_bounds", false))
				and not bool(east_empty.get("solid", true)),
		"Neighbour ChunkView halo must agree on the same open seam sample.",
	)
	var debug: Dictionary = west_view.get_mountain_native_mask_debug_state()
	_assert(bool(debug.get("native_mask_active", false)), "ChunkView must mark valid native mask bytes active.")
	_assert(
		bool(debug.get("native_mask_visual_pending", false)),
		"Native mask data publication must mark a separate visual upload pending.",
	)
	_assert(
		not bool(debug.get("native_mask_visual_ready", true)),
		"Gameplay-ready bytes must not pretend the deferred GPU texture already exists.",
	)
	_assert(
		not bool(debug.get("has_visual_texture", true)),
		"Applying native mask data must not create an ImageTexture synchronously.",
	)

	west_view.queue_free()
	east_view.queue_free()
	await process_frame


func _build_seam_mountain_tiles() -> Dictionary:
	var solid_world_tiles: Dictionary = { }
	for y: int in range(6, 12):
		for x: int in range(14, 18):
			solid_world_tiles[Vector2i(x, y)] = true
	return solid_world_tiles


func _build_halo(chunk_coord: Vector2i, solid_world_tiles: Dictionary) -> PackedByteArray:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + HALO_RADIUS_TILES * 2
	var halo := PackedByteArray()
	halo.resize(halo_side * halo_side)
	var origin_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE \
			- Vector2i.ONE * HALO_RADIUS_TILES
	for y: int in range(halo_side):
		for x: int in range(halo_side):
			if solid_world_tiles.has(origin_tile + Vector2i(x, y)):
				halo[y * halo_side + x] = 1
	return halo


func _count_owned_solid_tiles(chunk_coord: Vector2i, solid_world_tiles: Dictionary) -> int:
	var count: int = 0
	var origin_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			if solid_world_tiles.has(origin_tile + Vector2i(x, y)):
				count += 1
	return count


func _mask_origin_world(chunk_coord: Vector2i) -> Vector2:
	return WorldRuntimeConstants.chunk_origin_px(chunk_coord) \
			- Vector2.ONE * float(HALO_RADIUS_TILES * WorldRuntimeConstants.TILE_SIZE_PX)


func _sample_result_byte(result: Dictionary, world_pos: Vector2) -> int:
	var mask: PackedByteArray = result.get("mask", PackedByteArray()) as PackedByteArray
	var width: int = int(result.get("width", 0))
	var height: int = int(result.get("height", 0))
	var step_px: float = float(result.get("step_px", 0.0))
	var origin: Vector2 = result.get("mask_origin_world", Vector2.ZERO) as Vector2
	if width <= 0 or height <= 0 or step_px <= 0.0 or mask.size() != width * height:
		return -1
	var mask_pos: Vector2 = (world_pos - origin) / step_px
	var x: int = floori(mask_pos.x)
	var y: int = floori(mask_pos.y)
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return int(mask[y * width + x])


func _find_result(results: Array[Dictionary], chunk_coord: Vector2i) -> Dictionary:
	for result: Dictionary in results:
		if (result.get("target_chunk", Vector2i(-1, -1)) as Vector2i) == chunk_coord:
			return result
	return { }


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
