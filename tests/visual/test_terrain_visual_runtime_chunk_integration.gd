extends GdUnitTestSuite

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"


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

	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(debug.get("enabled")).is_equal(true)
	assert_that(debug.get("ready")).is_equal(true)
	assert_that(debug.get("has_visual_layer")).is_equal(true)
	assert_that(debug.get("chunk_coord")).is_equal(Vector2i(2, 3))
	assert_that(debug.get("world_origin_tile")).is_equal(Vector2i(34, 50))
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


func test_runtime_cell_marks_dirty_patch_without_full_v2_resolve() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass
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


func test_dirty_patch_apply_updates_material_textures_without_full_rebuild() -> void:
	var chunk_view := _build_v2_chunk_view(Vector2i.ZERO)
	add_child(chunk_view)

	chunk_view.begin_apply(_chunk_packet_with_rock_block(Vector2i.ZERO))
	while chunk_view.apply_next_batch(256):
		pass

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

	var applied: bool = chunk_view.call("apply_pending_terrain_visual_v2_patch")
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	assert_that(applied).is_true()
	assert_that(debug.get("full_solve_count")).is_equal(full_before)
	assert_that(debug.get("patch_solve_count")).is_equal(1)
	assert_that(debug.get("patch_apply_count")).is_equal(1)
	assert_that(debug.get("has_pending_dirty_patch")).is_equal(false)
	assert_that(debug.get("last_patch_world_origin_tile")).is_equal(Vector2i(2, 2))
	assert_that(debug.get("last_patch_pixel_size")).is_equal(Vector2i(192, 192))

	var after_zone := _sample_v2_zone_id(chunk_view, Vector2i(3, 3))
	assert_that(after_zone).is_equal(0)

	chunk_view.free()


func _build_v2_chunk_view(chunk_coord: Vector2i) -> ChunkView:
	var recipe: Resource = load(RECIPE_PATH).duplicate(true) as Resource
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	chunk_view.set_terrain_visual_v2_enabled(true)
	chunk_view.set_terrain_visual_recipe(recipe)
	return chunk_view


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


func _sample_v2_zone_id(chunk_view: ChunkView, local_coord: Vector2i) -> int:
	var debug: Dictionary = chunk_view.get_terrain_visual_v2_debug_state()
	if not debug.get("has_visual_layer", false):
		return -1
	var layer := chunk_view.get_node_or_null(
		"TerrainVisualV2RuntimePresenter/TerrainVisualV2PacketLayer",
	) as ColorRect
	if layer == null or layer.material == null:
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
	var pixel := (local_coord - origin) * WorldRuntimeConstants.TILE_SIZE_PX
	var half_tile := WorldRuntimeConstants.TILE_SIZE_PX / 2
	pixel += Vector2i(half_tile, half_tile)
	if pixel.x < 0 \
			or pixel.y < 0 \
			or pixel.x >= image.get_width() \
			or pixel.y >= image.get_height():
		return -1
	return int(round(image.get_pixel(pixel.x, pixel.y).r * 255.0))
