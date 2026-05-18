extends GdUnitTestSuite

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const TerrainVisualPacketBackend = preload(
	"res://core/systems/world/terrain_visual_packet_backend.gd"
)

const RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"
const VISUAL_DRAIN_STEP_LIMIT := 128


func test_terrain_visual_packet_backend_uses_multiple_native_workers() -> void:
	var backend := TerrainVisualPacketBackend.new()
	assert_that(backend.has_method("get_worker_count")).is_true()
	if not backend.has_method("get_worker_count"):
		return

	backend.start()
	assert_that(int(backend.call("get_worker_count"))).is_greater_equal(2)
	backend.stop()


func test_plains_biome_binds_runtime_rock_visual_recipe() -> void:
	var biome: Resource = load("res://data/biomes/plains_biome.tres") as Resource
	assert_that(biome).is_not_null()
	if biome == null:
		return

	var recipe: Resource = biome.get("rock_visual_recipe") as Resource
	assert_that(recipe).is_not_null()
	if recipe == null:
		return
	assert_that(recipe.get("id")).is_equal(&"core:rock_default")


func test_chunk_view_applies_v2_packet_layer_from_recipe_when_feature_enabled() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i(2, 3))
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i(2, 3)))
	while chunk_view.apply_next_batch(256):
		pass
	await _drain_v2_full_apply(chunk_view)

	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("enabled")).is_equal(true)
	assert_that(debug.get("ready")).is_equal(true)
	assert_that(debug.get("has_visual_layer")).is_equal(true)
	assert_that(debug.get("chunk_coord")).is_equal(Vector2i(2, 3))
	assert_that(debug.get("world_origin_tile")).is_equal(Vector2i(34, 50))
	assert_that(debug.get("tile_size_px")).is_equal(64)
	assert_that(debug.get("pixel_width")).is_equal(256)
	assert_that(debug.get("pixel_height")).is_equal(256)
	assert_that(debug.get("full_solve_count")).is_equal(1)
	assert_that(debug.get("shader_path")).is_equal(
		"res://assets/shaders/terrain_visual_packet.gdshader",
	)
	var layer_path := "TerrainVisualV2RuntimePresenter/TerrainVisualV2PacketLayer"
	var layer := chunk_view.get_node(layer_path) as ColorRect
	var material := layer.material as ShaderMaterial
	assert_that(material.get_shader_parameter("base_source")).is_equal(2)
	assert_that(material.get_shader_parameter("base_flat_color").a).is_equal(0.0)
	assert_that(chunk_view.get_node_or_null("RockFillLayer")).is_null()
	assert_that(chunk_view.get_node_or_null("RockOutlineLayer")).is_null()

	chunk_view.free()


func test_chunk_view_hides_legacy_mountain_tilemap_under_v2_packet_layer() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass

	var rock_coord := Vector2i(3, 3)
	var overlay_layer := chunk_view.get_node_or_null("TerrainOverlayLayer") as TileMapLayer
	var base_layer := chunk_view.get_node_or_null("TerrainBaseLayer") as TileMapLayer
	assert_that(overlay_layer).is_not_null()
	assert_that(base_layer).is_not_null()
	if overlay_layer == null or base_layer == null:
		chunk_view.free()
		return

	assert_that(overlay_layer.get_cell_source_id(rock_coord)).is_equal(-1)
	assert_that(base_layer.get_cell_source_id(rock_coord)).is_not_equal(-1)

	chunk_view.free()


func test_chunk_view_v2_halo_solver_suppresses_facade_on_internal_chunk_edge() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	chunk_view.set_terrain_visual_solid_halo(_right_edge_rock_solid_halo())
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_right_edge_rock(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass
	await _drain_v2_full_apply(chunk_view)

	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("ready")).is_equal(true)
	assert_that(debug.get("has_chunk_solid_halo")).is_equal(true)
	assert_that(debug.get("last_solver_method")).is_equal(&"build_chunk_visual_packet_with_halo")
	assert_that(debug.get("world_origin_tile")).is_equal(Vector2i(14, 6))
	assert_that(debug.get("tile_size_px")).is_equal(64)
	assert_that(debug.get("pixel_width")).is_equal(128)
	assert_that(debug.get("pixel_height")).is_equal(192)

	var zone := _sample_v2_zone_id_at_tile_pixel(
		chunk_view,
		Vector2i(15, 7),
		Vector2i(WorldRuntimeConstants.TILE_SIZE_PX - 1, WorldRuntimeConstants.TILE_SIZE_PX / 2),
	)
	assert_that(zone).is_equal(1)

	chunk_view.free()


func test_v2_chunk_view_samples_packet_contour_for_collision_shape() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass
	await _drain_v2_full_apply(chunk_view)

	assert_that(chunk_view.has_method("is_terrain_visual_v2_solid_at_world")).is_true()
	if not chunk_view.has_method("is_terrain_visual_v2_solid_at_world"):
		chunk_view.free()
		return

	var empty_sample: Dictionary = _find_v2_mountain_tile_contour_sample(chunk_view, false)
	var solid_sample: Dictionary = _find_v2_mountain_tile_contour_sample(chunk_view, true)
	assert_that(empty_sample.is_empty()).is_false()
	assert_that(solid_sample.is_empty()).is_false()
	if empty_sample.is_empty() or solid_sample.is_empty():
		chunk_view.free()
		return

	assert_that(
		bool(
			chunk_view.call(
				"is_terrain_visual_v2_solid_at_world",
				empty_sample.get("world_pos", Vector2.ZERO),
			),
		),
	).is_false()
	assert_that(
		bool(
			chunk_view.call(
				"is_terrain_visual_v2_solid_at_world",
				solid_sample.get("world_pos", Vector2.ZERO),
			),
		),
	).is_true()

	chunk_view.free()


func test_runtime_cell_marks_dirty_patch_without_full_v2_resolve() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass
	await _drain_v2_full_apply(chunk_view)
	var before: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()

	chunk_view.apply_runtime_cell(
		Vector2i(3, 3),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		true,
		0,
		0,
	)

	var after: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(after.get("full_solve_count")).is_equal(before.get("full_solve_count"))
	assert_that(after.get("dirty_mark_count")).is_equal(1)
	assert_that(after.get("last_dirty_rect_tiles")).is_equal(Rect2i(Vector2i(2, 2), Vector2i(3, 3)))
	assert_that(after.get("has_pending_dirty_patch")).is_equal(true)

	chunk_view.free()


func test_multiple_runtime_cells_union_v2_dirty_patch() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass
	await _drain_v2_full_apply(chunk_view)

	chunk_view.apply_runtime_cell(
		Vector2i(3, 3),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		true,
		0,
		0,
	)
	chunk_view.apply_runtime_cell(
		Vector2i(4, 4),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		true,
		0,
		0,
	)

	var after: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(after.get("dirty_mark_count")).is_equal(2)
	assert_that(after.get("last_dirty_rect_tiles")).is_equal(Rect2i(Vector2i(2, 2), Vector2i(4, 4)))

	chunk_view.free()


func test_dirty_patch_apply_commits_all_packet_fields_after_native_solve() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass
	await _drain_v2_full_apply(chunk_view)
	var full_before: int = chunk_view.get_terrain_visual_v2_debug_state()["full_solve_count"]

	chunk_view.apply_runtime_cell(
		Vector2i(3, 3),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		true,
		0,
		0,
	)

	assert_that(chunk_view.apply_pending_terrain_visual_v2_patch()).is_true()
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("has_pending_patch_solve")).is_equal(true)

	await _drain_until_patch_solve_completed(chunk_view)
	debug = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("full_solve_count")).is_equal(full_before)
	assert_that(debug.get("patch_solve_count")).is_equal(1)
	assert_that(debug.get("patch_apply_count")).is_equal(1)
	assert_that(debug.get("has_pending_patch_apply")).is_equal(false)
	assert_that(debug.get("pending_patch_texture_index")).is_equal(0)
	assert_that(debug.get("has_pending_dirty_patch")).is_equal(false)

	chunk_view.free()


func test_dirty_patch_apply_updates_material_textures_without_full_rebuild() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass
	await _drain_v2_full_apply(chunk_view)

	var before_zone := _sample_v2_zone_id(chunk_view, Vector2i(3, 3))
	assert_that(before_zone).is_greater(0)
	var full_before: int = chunk_view.get_terrain_visual_v2_debug_state()["full_solve_count"]

	chunk_view.apply_runtime_cell(
		Vector2i(3, 3),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		true,
		0,
		0,
	)

	assert_that(chunk_view.has_method("apply_pending_terrain_visual_v2_patch")).is_true()
	if not chunk_view.has_method("apply_pending_terrain_visual_v2_patch"):
		chunk_view.free()
		return

	var first_step: bool = chunk_view.call("apply_pending_terrain_visual_v2_patch")
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(first_step).is_true()
	assert_that(debug.get("full_solve_count")).is_equal(full_before)
	assert_that(debug.get("has_pending_patch_solve")).is_equal(true)
	assert_that(debug.get("patch_solve_count")).is_equal(0)

	await _drain_v2_patch_apply(chunk_view)
	debug = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("full_solve_count")).is_equal(full_before)
	assert_that(debug.get("patch_solve_count")).is_equal(1)
	assert_that(debug.get("patch_apply_count")).is_equal(1)
	assert_that(debug.get("has_pending_dirty_patch")).is_equal(false)
	assert_that(debug.get("has_pending_patch_solve")).is_equal(false)
	assert_that(debug.get("has_pending_patch_apply")).is_equal(false)
	assert_that(debug.get("last_patch_world_origin_tile")).is_equal(Vector2i(2, 2))
	assert_that(debug.get("last_patch_pixel_size")).is_equal(Vector2i(192, 192))

	await await_idle_frame()
	var after_zone := _sample_v2_zone_id(chunk_view, Vector2i(3, 3))
	assert_that(after_zone).is_equal(0)
	assert_that(_sample_v2_packet_zone_id(chunk_view, Vector2i(3, 3))).is_equal(0)

	chunk_view.free()


func test_dirty_patch_before_first_v2_packet_requeues_fresh_full_visual() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass
	chunk_view.apply_runtime_cell(
		Vector2i(3, 3),
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		0,
		true,
		0,
		0,
	)

	var first_step: bool = chunk_view.call("apply_pending_terrain_visual_v2_patch")
	assert_that(first_step).is_true()
	await _drain_v2_patch_apply(chunk_view)

	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("ready")).is_equal(true)
	assert_that(debug.get("full_solve_count")).is_equal(1)
	assert_that(debug.get("has_pending_dirty_patch")).is_equal(false)
	assert_that(_sample_v2_packet_zone_id(chunk_view, Vector2i(3, 3))).is_equal(0)

	chunk_view.free()


func _build_v2_chunk_view(chunk_coord: Vector2i) -> ChunkView:
	var recipe: Resource = load(RECIPE_PATH).duplicate(true) as Resource
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	chunk_view.set_terrain_visual_v2_enabled(true)
	chunk_view.set_terrain_visual_recipe(recipe)
	return chunk_view


func _drain_v2_full_apply(chunk_view: ChunkView) -> void:
	var has_more_visual_work := true
	for step_index: int in range(VISUAL_DRAIN_STEP_LIMIT):
		has_more_visual_work = chunk_view.apply_pending_terrain_visual_v2_full()
		if not has_more_visual_work:
			return
		await await_idle_frame()
	assert_that(has_more_visual_work).is_false()


func _drain_v2_patch_apply(chunk_view: ChunkView) -> void:
	var has_more_visual_work := true
	for step_index: int in range(VISUAL_DRAIN_STEP_LIMIT):
		has_more_visual_work = chunk_view.apply_pending_terrain_visual_v2_patch()
		if not has_more_visual_work:
			return
		await await_idle_frame()
	assert_that(has_more_visual_work).is_false()


func _drain_until_patch_solve_completed(chunk_view: ChunkView) -> void:
	for step_index: int in range(VISUAL_DRAIN_STEP_LIMIT):
		var has_more_visual_work := chunk_view.apply_pending_terrain_visual_v2_patch()
		var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
		if int(debug.get("patch_solve_count", 0)) >= 1:
			return
		if not has_more_visual_work:
			return
		await await_idle_frame()
	var solve_count := int(
		chunk_view.get_terrain_visual_v2_debug_state().get("patch_solve_count", 0),
	)
	assert_that(solve_count).is_equal(1)


func _chunk_packet_with_rock_block(chunk_coord: Vector2i) -> Dictionary:
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
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var is_rock := (
			local_coord.x >= 2 and local_coord.x <= 5 and local_coord.y >= 2 and local_coord.y <= 5
		)
		terrain_ids[index] = (
			WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
			if is_rock
			else WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		)
		walkable_flags[index] = 0 if is_rock else 1
		if is_rock:
			mountain_ids[index] = 1
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL

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


func _chunk_packet_with_right_edge_rock(chunk_coord: Vector2i) -> Dictionary:
	var packet := _chunk_packet_with_rock_block(chunk_coord)
	var terrain_ids: PackedInt32Array = packet["terrain_ids"]
	var walkable_flags: PackedByteArray = packet["walkable_flags"]
	var mountain_ids: PackedInt32Array = packet["mountain_id_per_tile"]
	var mountain_flags: PackedByteArray = packet["mountain_flags"]

	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var is_rock := (
			local_coord.x >= 14
			and local_coord.x <= 15
			and local_coord.y >= 6
			and local_coord.y <= 8
		)
		terrain_ids[index] = (
			WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
			if is_rock
			else WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		)
		walkable_flags[index] = 0 if is_rock else 1
		mountain_ids[index] = 1 if is_rock else 0
		mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL if is_rock else 0
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


func _sample_v2_zone_id(chunk_view: ChunkView, local_coord: Vector2i) -> int:
	return _sample_v2_zone_id_at_tile_pixel(
		chunk_view,
		local_coord,
		Vector2i(WorldRuntimeConstants.TILE_SIZE_PX / 2, WorldRuntimeConstants.TILE_SIZE_PX / 2),
	)


func _sample_v2_packet_zone_id(chunk_view: ChunkView, local_coord: Vector2i) -> int:
	var presenter := chunk_view.get_node_or_null("TerrainVisualV2RuntimePresenter")
	if presenter == null:
		return -1
	var packet: Dictionary = presenter.get("_last_packet")
	var zone_ids: PackedByteArray = packet.get("zone_ids", PackedByteArray())
	if zone_ids.is_empty():
		return -1
	var pixel := _packet_pixel_for_local_coord(
		chunk_view,
		local_coord,
		Vector2i(WorldRuntimeConstants.TILE_SIZE_PX / 2, WorldRuntimeConstants.TILE_SIZE_PX / 2),
		Vector2i(
			int(packet.get("pixel_width", 0)),
			int(packet.get("pixel_height", 0)),
		),
	)
	if pixel.x < 0:
		return -1
	return int(zone_ids[pixel.y * int(packet.get("pixel_width", 0)) + pixel.x])


func _sample_v2_zone_id_at_tile_pixel(
		chunk_view: ChunkView,
		local_coord: Vector2i,
		tile_pixel_offset: Vector2i,
) -> int:
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	if not debug.get("has_visual_layer", false):
		return -1
	var layer := chunk_view.get_node_or_null(
		"TerrainVisualV2RuntimePresenter/TerrainVisualV2PacketLayer",
	) as ColorRect
	if layer == null or layer.material == null:
		return -1
	var image := _get_v2_packet_zone_image(chunk_view)
	if image == null:
		return -1
	var pixel := _packet_pixel_for_local_coord(
		chunk_view,
		local_coord,
		tile_pixel_offset,
		Vector2i(image.get_width(), image.get_height()),
	)
	if pixel.x < 0:
		return -1
	return int(round(image.get_pixel(pixel.x, pixel.y).r * 255.0))


func _packet_pixel_for_local_coord(
		chunk_view: ChunkView,
		local_coord: Vector2i,
		tile_pixel_offset: Vector2i,
		pixel_size: Vector2i,
) -> Vector2i:
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
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
			or pixel.x >= pixel_size.x \
			or pixel.y >= pixel_size.y:
		return Vector2i(-1, -1)
	return pixel


func _get_v2_packet_zone_image(chunk_view: ChunkView) -> Image:
	var presenter := chunk_view.get_node_or_null("TerrainVisualV2RuntimePresenter")
	if presenter != null:
		var packet_images: Dictionary = presenter.get("_packet_images")
		var image := packet_images.get("zone_ids") as Image
		if image != null:
			return image
	var layer := chunk_view.get_node_or_null(
		"TerrainVisualV2RuntimePresenter/TerrainVisualV2PacketLayer",
	) as ColorRect
	if layer == null or layer.material == null:
		return null
	var material := layer.material as ShaderMaterial
	if material == null:
		return null
	var texture := material.get_shader_parameter("zone_texture") as Texture2D
	if texture == null:
		return null
	return texture.get_image()


func _clamped_world_to_packet_pixel(world_pixel: int, packet_tile_size: int) -> int:
	var packet_pixel := (
		float(world_pixel) * float(packet_tile_size) / float(WorldRuntimeConstants.TILE_SIZE_PX)
	)
	return clampi(
		floori(packet_pixel),
		0,
		packet_tile_size - 1,
	)


func _find_v2_mountain_tile_contour_sample(chunk_view: ChunkView, want_solid: bool) -> Dictionary:
	var presenter := chunk_view.get_node_or_null("TerrainVisualV2RuntimePresenter")
	if presenter == null:
		return { }
	var packet: Dictionary = presenter.get("_last_packet")
	var zone_ids: PackedByteArray = packet.get("zone_ids", PackedByteArray())
	if zone_ids.is_empty():
		return { }
	var pixel_width := int(packet.get("pixel_width", 0))
	var pixel_height := int(packet.get("pixel_height", 0))
	var tile_size_px := int(packet.get("tile_size_px", WorldRuntimeConstants.TILE_SIZE_PX))
	if pixel_width <= 0 or pixel_height <= 0 or tile_size_px <= 0:
		return { }
	var packet_origin_tile: Vector2i = packet.get("world_origin_tile", Vector2i.ZERO) as Vector2i
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	var chunk_coord: Vector2i = debug.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var packet_origin_local := packet_origin_tile - chunk_coord * WorldRuntimeConstants.CHUNK_SIZE
	var terrain_packet := _chunk_packet_with_rock_block(chunk_coord)
	var terrain_ids: PackedInt32Array = terrain_packet["terrain_ids"]
	var walkable_flags: PackedByteArray = terrain_packet["walkable_flags"]

	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		if index >= terrain_ids.size() or index >= walkable_flags.size():
			continue
		if int(terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL:
			continue
		if int(walkable_flags[index]) != 0:
			continue
		var tile_pixel_origin := (local_coord - packet_origin_local) * tile_size_px
		for pixel_y: int in range(tile_size_px):
			for pixel_x: int in range(tile_size_px):
				var packet_pixel := tile_pixel_origin + Vector2i(pixel_x, pixel_y)
				if packet_pixel.x < 0 \
						or packet_pixel.y < 0 \
						or packet_pixel.x >= pixel_width \
						or packet_pixel.y >= pixel_height:
					continue
				var zone := int(zone_ids[packet_pixel.y * pixel_width + packet_pixel.x])
				if (zone > 0) != want_solid:
					continue
				var world_offset := Vector2(
					(float(pixel_x) + 0.5)
					* float(WorldRuntimeConstants.TILE_SIZE_PX)
					/ float(tile_size_px),
					(float(pixel_y) + 0.5)
					* float(WorldRuntimeConstants.TILE_SIZE_PX)
					/ float(tile_size_px),
				)
				var world_tile := chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord
				var sample_world_pos := (
					Vector2(world_tile * WorldRuntimeConstants.TILE_SIZE_PX) + world_offset
				)
				return {
					"world_pos": sample_world_pos,
					"local_coord": local_coord,
					"zone": zone,
				}
	return { }
