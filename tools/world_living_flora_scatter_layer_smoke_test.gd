extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldLivingFloraScatterLayer = preload("res://core/systems/world/world_living_flora_scatter_layer.gd")

func _init() -> void:
	var layer := WorldLivingFloraScatterLayer.new()
	root.add_child(layer)
	layer.set_atlas(_make_texture())

	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(terrain_ids.size()):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)

	var mask_width: int = 128
	var mask_height: int = 128
	var mask_step_px: float = 8.0
	var solid_mask := PackedByteArray()
	solid_mask.resize(mask_width * mask_height)
	for index: int in range(solid_mask.size()):
		solid_mask[index] = 255

	var checked_chunks: int = 0
	var plant_count: int = 0
	var plant_chunk := Vector2i.ZERO
	for chunk_y: int in range(32):
		for chunk_x: int in range(32):
			checked_chunks += 1
			var chunk_coord := Vector2i(chunk_x, chunk_y)
			layer.configure_chunk(
				chunk_coord,
				WorldRuntimeConstants.DEFAULT_WORLD_SEED,
				WorldRuntimeConstants.WORLD_VERSION,
				terrain_ids,
				lake_flags,
				solid_mask,
				mask_width,
				mask_height,
				WorldRuntimeConstants.chunk_origin_px(chunk_coord),
				mask_step_px
			)
			if layer.get_plant_count() > 0:
				plant_count = layer.get_plant_count()
				plant_chunk = chunk_coord
				break
		if plant_count > 0:
			break

	if plant_count <= 0:
		_fail("Living flora scatter produced no plants inside checked grass masks.")

	var empty_mask := PackedByteArray()
	empty_mask.resize(mask_width * mask_height)
	layer.configure_chunk(
		plant_chunk,
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		terrain_ids,
		lake_flags,
		empty_mask,
		mask_width,
		mask_height,
		WorldRuntimeConstants.chunk_origin_px(plant_chunk),
		mask_step_px
	)
	if layer.get_plant_count() != 0:
		_fail("Living flora scatter must not place plants on an empty grass mask.")

	print(
		"WORLD_LIVING_FLORA_SCATTER_SMOKE chunks=%d plant_chunk=%s plants=%d" %
		[checked_chunks, str(plant_chunk), plant_count]
	)
	layer.free()
	quit()

func _make_texture() -> Texture2D:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
