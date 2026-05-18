extends GdUnitTestSuite

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const VIEWPORT_SIZE := Vector2i(640, 360)
const RENDER_SCALE := 0.377
const CHUNK_SCREEN_SIZE := int(
	WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX * RENDER_SCALE,
)
const RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"
const SEAM_DARKENING_THRESHOLD := 35
const PUBLISH_SPIKE_RATIO_THRESHOLD := 2.0


func test_adjacent_chunk_views_do_not_render_dark_boundary_gap_under_fractional_transform() -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var root := Node2D.new()
	root.position = Vector2(0.37, 0.41)
	root.scale = Vector2(RENDER_SCALE, RENDER_SCALE)
	viewport.add_child(root)

	var left_chunk := _new_plain_chunk_view(Vector2i.ZERO)
	var right_chunk := _new_plain_chunk_view(Vector2i.RIGHT)
	root.add_child(left_chunk)
	root.add_child(right_chunk)
	_apply_plain_packet(left_chunk, Vector2i.ZERO)
	_apply_plain_packet(right_chunk, Vector2i.RIGHT)

	await await_idle_frame()
	await await_idle_frame()
	await await_millis(50)

	var image := viewport.get_texture().get_image()
	assert_that(image).is_not_null()
	if image == null:
		viewport.free()
		return

	var seam_x := int(round(root.position.x + float(CHUNK_SCREEN_SIZE)))
	var sample_y0 := 32
	var sample_y1 := VIEWPORT_SIZE.y - 32
	var seam_luma := _average_luma_on_column(image, seam_x, sample_y0, sample_y1)
	var left_luma := _average_luma_on_column(image, seam_x - 4, sample_y0, sample_y1)
	var right_luma := _average_luma_on_column(image, seam_x + 4, sample_y0, sample_y1)
	var neighbor_luma := int(round((float(left_luma) + float(right_luma)) * 0.5))
	var darkening := neighbor_luma - seam_luma

	assert_that(darkening).is_less(SEAM_DARKENING_THRESHOLD)

	viewport.free()


func test_final_chunk_publish_batch_has_no_visual_apply_spike() -> void:
	var chunk_view := _build_rock_chunk(Vector2i.ZERO)
	add_child(chunk_view)

	var packet := _chunk_packet_with_rock_block(Vector2i.ZERO)
	chunk_view.begin_apply(packet)

	var first_batch_start := Time.get_ticks_usec()
	var has_more := chunk_view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE)
	var first_batch_ms := _elapsed_ms(first_batch_start)
	assert_that(has_more).is_true()

	var final_batch_start := Time.get_ticks_usec()
	has_more = chunk_view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE)
	var final_batch_ms := _elapsed_ms(final_batch_start)
	assert_that(has_more).is_false()

	var allowed_ms := maxf(first_batch_ms * PUBLISH_SPIKE_RATIO_THRESHOLD, first_batch_ms + 0.25)
	assert_that(final_batch_ms).is_less_equal(allowed_ms)

	chunk_view.free()


func test_full_v2_visual_apply_is_staged_across_texture_steps() -> void:
	var chunk_view := _build_rock_chunk(Vector2i.ZERO)
	add_child(chunk_view)

	var packet := _chunk_packet_with_rock_block(Vector2i.ZERO)
	chunk_view.begin_apply(packet)
	while chunk_view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass

	var has_more_visual_work := chunk_view.apply_pending_terrain_visual_v2_full()
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(has_more_visual_work).is_true()
	assert_that(debug.get("full_solve_request_count")).is_equal(1)
	assert_that(debug.get("full_solve_count")).is_equal(0)
	assert_that(debug.get("has_pending_full_solve")).is_equal(true)
	assert_that(debug.get("has_pending_full_apply")).is_equal(false)
	assert_that(debug.get("has_visual_layer")).is_equal(false)

	await _drain_v2_full_apply(chunk_view)
	debug = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("full_solve_count")).is_equal(1)
	assert_that(debug.get("has_pending_full_solve")).is_equal(false)
	assert_that(debug.get("has_pending_full_apply")).is_equal(false)
	assert_that(debug.get("has_visual_layer")).is_equal(true)
	assert_that(debug.get("full_apply_texture_count")).is_equal(
		debug.get("full_apply_texture_total"),
	)

	chunk_view.free()


func test_world_streamer_requeues_staged_v2_full_apply_until_complete() -> void:
	var streamer := WorldStreamer.new()
	add_child(streamer)
	var chunk_view := _build_rock_chunk(Vector2i.ZERO)
	streamer.add_child(chunk_view)

	var packet := _chunk_packet_with_rock_block(Vector2i.ZERO)
	chunk_view.begin_apply(packet)
	while chunk_view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	streamer._chunk_views[Vector2i.ZERO] = chunk_view
	streamer._chunk_packets[Vector2i.ZERO] = packet
	streamer.call("_queue_terrain_visual_v2_full_refresh", Vector2i.ZERO)

	var first_tick_has_more := bool(streamer.call("_terrain_visual_tick"))
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(first_tick_has_more).is_true()
	assert_that(debug.get("has_pending_full_solve")).is_equal(true)

	await _drain_terrain_visual_streamer(streamer)
	debug = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("has_pending_full_solve")).is_equal(false)
	assert_that(debug.get("has_pending_full_apply")).is_equal(false)
	assert_that(debug.get("has_visual_layer")).is_equal(true)

	streamer.free()


func test_world_streamer_requeues_staged_v2_dirty_patch_until_complete() -> void:
	var streamer := WorldStreamer.new()
	add_child(streamer)
	var chunk_view := _build_rock_chunk(Vector2i.ZERO)
	streamer.add_child(chunk_view)

	var packet := _chunk_packet_with_rock_block(Vector2i.ZERO)
	chunk_view.begin_apply(packet)
	while chunk_view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	streamer._chunk_views[Vector2i.ZERO] = chunk_view
	streamer._chunk_packets[Vector2i.ZERO] = packet
	await _drain_v2_full_apply(chunk_view)

	chunk_view.apply_runtime_cell(
		Vector2i(3, 3),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		true,
		0,
		0,
	)
	streamer.call("_queue_terrain_visual_v2_patch_apply", Vector2i.ZERO)

	var first_tick_has_more := bool(streamer.call("_terrain_visual_tick"))
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(first_tick_has_more).is_true()
	assert_that(debug.get("has_pending_patch_solve")).is_equal(true)

	await _drain_terrain_visual_streamer(streamer)
	debug = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("has_pending_patch_solve")).is_equal(false)
	assert_that(debug.get("has_pending_patch_apply")).is_equal(false)
	assert_that(debug.get("patch_apply_count")).is_equal(1)

	streamer.free()


func test_late_neighbor_halo_rebuild_removes_internal_v2_chunk_facade() -> void:
	var chunk_view := _build_rock_chunk(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_right_edge_rock(Vector2i.ZERO))
	while chunk_view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	await _drain_v2_full_apply(chunk_view)

	var before_zone := _sample_v2_zone_id_at_tile_pixel(
		chunk_view,
		Vector2i(15, 7),
		Vector2i(WorldRuntimeConstants.TILE_SIZE_PX - 1, WorldRuntimeConstants.TILE_SIZE_PX / 2),
	)
	assert_that(before_zone).is_not_equal(1)

	chunk_view.set_terrain_visual_solid_halo(_right_edge_rock_solid_halo())
	await _drain_v2_full_apply(chunk_view)

	var after_zone := _sample_v2_zone_id_at_tile_pixel(
		chunk_view,
		Vector2i(15, 7),
		Vector2i(WorldRuntimeConstants.TILE_SIZE_PX - 1, WorldRuntimeConstants.TILE_SIZE_PX / 2),
	)
	assert_that(after_zone).is_equal(1)

	chunk_view.free()


func test_missing_neighbor_visual_halo_does_not_emit_stream_ring_facade() -> void:
	var streamer := WorldStreamer.new()
	var packet := _chunk_packet_with_bottom_edge_rock(Vector2i.ZERO)
	streamer._chunk_packets[Vector2i.ZERO] = packet
	var solid_halo: PackedByteArray = streamer.call("_build_mountain_solid_halo", Vector2i.ZERO)
	var halo_side := WorldRuntimeConstants.CHUNK_SIZE + 2
	var south_halo_index := (WorldRuntimeConstants.CHUNK_SIZE + 1) * halo_side + 8
	assert_that(int(solid_halo[south_halo_index])).is_equal(1)

	var chunk_view := _build_rock_chunk(Vector2i.ZERO)
	add_child(chunk_view)
	chunk_view.set_terrain_visual_solid_halo(solid_halo)
	chunk_view.begin_apply(packet)
	while chunk_view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	await _drain_v2_full_apply(chunk_view)

	var south_boundary_zone := _sample_v2_zone_id_at_tile_pixel(
		chunk_view,
		Vector2i(7, 15),
		Vector2i(WorldRuntimeConstants.TILE_SIZE_PX / 2, WorldRuntimeConstants.TILE_SIZE_PX - 1),
	)
	assert_that(south_boundary_zone).is_equal(1)

	chunk_view.free()
	streamer.free()


func _new_plain_chunk_view(chunk_coord: Vector2i) -> ChunkView:
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	chunk_view.set_terrain_visual_v2_enabled(true)
	chunk_view.set_terrain_visual_recipe(load(RECIPE_PATH))
	return chunk_view


func _apply_plain_packet(chunk_view: ChunkView, chunk_coord: Vector2i) -> void:
	chunk_view.begin_apply(_plain_packet(chunk_coord))
	while chunk_view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		pass
	chunk_view.visible = true


func _drain_v2_full_apply(chunk_view: ChunkView) -> void:
	var has_more_visual_work := true
	for step_index: int in range(32):
		has_more_visual_work = chunk_view.apply_pending_terrain_visual_v2_full()
		if not has_more_visual_work:
			return
		await await_idle_frame()
	assert_that(has_more_visual_work).is_false()


func _drain_terrain_visual_streamer(streamer: WorldStreamer) -> void:
	var has_more_visual_work := true
	for step_index: int in range(32):
		has_more_visual_work = bool(streamer.call("_terrain_visual_tick"))
		if not has_more_visual_work:
			return
		await await_idle_frame()
	assert_that(has_more_visual_work).is_false()


func _build_rock_chunk(chunk_coord: Vector2i) -> ChunkView:
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	chunk_view.set_terrain_visual_v2_enabled(true)
	chunk_view.set_terrain_visual_recipe(load(RECIPE_PATH))
	return chunk_view


func _plain_packet(chunk_coord: Vector2i) -> Dictionary:
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
		terrain_atlas_indices[index] = 0
		walkable_flags[index] = 1

	return {
		"chunk_coord": chunk_coord,
		"biome_id": &"plains",
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
		"world_seed": 12345,
	}


func _chunk_packet_with_rock_block(chunk_coord: Vector2i) -> Dictionary:
	var packet := _plain_packet(chunk_coord)
	var terrain_ids: PackedInt32Array = packet["terrain_ids"]
	var walkable_flags: PackedByteArray = packet["walkable_flags"]
	var mountain_ids: PackedInt32Array = packet["mountain_id_per_tile"]
	var mountain_flags: PackedByteArray = packet["mountain_flags"]

	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord := WorldRuntimeConstants.index_to_local(index)
		var is_rock := (
			local_coord.x >= 1
			and local_coord.x <= 14
			and local_coord.y >= 1
			and local_coord.y <= 14
		)
		if is_rock:
			terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
			walkable_flags[index] = 0
			mountain_ids[index] = 1
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL

	packet["terrain_ids"] = terrain_ids
	packet["walkable_flags"] = walkable_flags
	packet["mountain_id_per_tile"] = mountain_ids
	packet["mountain_flags"] = mountain_flags
	return packet


func _chunk_packet_with_right_edge_rock(chunk_coord: Vector2i) -> Dictionary:
	var packet := _plain_packet(chunk_coord)
	var terrain_ids: PackedInt32Array = packet["terrain_ids"]
	var walkable_flags: PackedByteArray = packet["walkable_flags"]
	var mountain_ids: PackedInt32Array = packet["mountain_id_per_tile"]
	var mountain_flags: PackedByteArray = packet["mountain_flags"]

	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord := WorldRuntimeConstants.index_to_local(index)
		var is_rock := (
			local_coord.x >= 14
			and local_coord.x <= 15
			and local_coord.y >= 6
			and local_coord.y <= 8
		)
		if is_rock:
			terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
			walkable_flags[index] = 0
			mountain_ids[index] = 1
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL

	packet["terrain_ids"] = terrain_ids
	packet["walkable_flags"] = walkable_flags
	packet["mountain_id_per_tile"] = mountain_ids
	packet["mountain_flags"] = mountain_flags
	return packet


func _chunk_packet_with_bottom_edge_rock(chunk_coord: Vector2i) -> Dictionary:
	var packet := _plain_packet(chunk_coord)
	var terrain_ids: PackedInt32Array = packet["terrain_ids"]
	var walkable_flags: PackedByteArray = packet["walkable_flags"]
	var mountain_ids: PackedInt32Array = packet["mountain_id_per_tile"]
	var mountain_flags: PackedByteArray = packet["mountain_flags"]

	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord := WorldRuntimeConstants.index_to_local(index)
		var is_rock := (
			local_coord.x >= 2
			and local_coord.x <= 13
			and local_coord.y >= 14
			and local_coord.y <= 15
		)
		if is_rock:
			terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
			walkable_flags[index] = 0
			mountain_ids[index] = 1
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL

	packet["terrain_ids"] = terrain_ids
	packet["walkable_flags"] = walkable_flags
	packet["mountain_id_per_tile"] = mountain_ids
	packet["mountain_flags"] = mountain_flags
	return packet


func _right_edge_rock_solid_halo() -> PackedByteArray:
	var halo_side := WorldRuntimeConstants.CHUNK_SIZE + 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(halo_side * halo_side)
	for local_y: int in range(6, 9):
		for local_x: int in range(14, 17):
			var halo_coord := Vector2i(local_x + 1, local_y + 1)
			solid_halo[halo_coord.y * halo_side + halo_coord.x] = 1
	return solid_halo


func _sample_v2_zone_id_at_tile_pixel(
		chunk_view: ChunkView,
		local_coord: Vector2i,
		tile_pixel_offset: Vector2i,
) -> int:
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	if not bool(debug.get("has_visual_layer", false)):
		return -1
	var layer := chunk_view.get_node_or_null(
		"TerrainVisualV2RuntimePresenter/TerrainVisualV2PacketLayer",
	) as ColorRect
	if layer == null:
		return -1
	var material := layer.material as ShaderMaterial
	if material == null:
		return -1
	var texture := material.get_shader_parameter("zone_texture") as Texture2D
	if texture == null:
		return -1
	var image := texture.get_image()
	var origin: Vector2i = (
		debug["world_origin_tile"] - debug["chunk_coord"] * WorldRuntimeConstants.CHUNK_SIZE
	)
	var packet_tile_size := int(debug.get("tile_size_px", WorldRuntimeConstants.TILE_SIZE_PX))
	var packet_offset := Vector2i(
		_clamped_world_to_packet_pixel(tile_pixel_offset.x, packet_tile_size),
		_clamped_world_to_packet_pixel(tile_pixel_offset.y, packet_tile_size),
	)
	var pixel := (local_coord - origin) * packet_tile_size + packet_offset
	if pixel.x < 0 \
			or pixel.y < 0 \
			or pixel.x >= image.get_width() \
			or pixel.y >= image.get_height():
		return -1
	return int(round(image.get_pixel(pixel.x, pixel.y).r * 255.0))


func _clamped_world_to_packet_pixel(world_pixel: int, packet_tile_size: int) -> int:
	var packet_pixel := (
		float(world_pixel) * float(packet_tile_size) / float(WorldRuntimeConstants.TILE_SIZE_PX)
	)
	return clampi(
		floori(packet_pixel),
		0,
		packet_tile_size - 1,
	)


func _average_luma_on_column(image: Image, x: int, y0: int, y1: int) -> int:
	x = clampi(x, 0, image.get_width() - 1)
	y0 = clampi(y0, 0, image.get_height() - 1)
	y1 = clampi(y1, y0 + 1, image.get_height())
	var total := 0.0
	var count := 0
	for y: int in range(y0, y1):
		var color := image.get_pixel(x, y)
		total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
		count += 1
	return int(round(total * 255.0 / float(maxi(count, 1))))


func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0
