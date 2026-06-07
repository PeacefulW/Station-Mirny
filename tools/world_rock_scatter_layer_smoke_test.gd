extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldRockScatterLayer = preload("res://core/systems/world/world_rock_scatter_layer.gd")

func _init() -> void:
	var layer := WorldRockScatterLayer.new()
	root.add_child(layer)
	layer.set_atlases([_make_texture(), _make_texture(), _make_texture()])

	var max_size: float = 0.0
	for salt: int in range(2048):
		max_size = maxf(max_size, layer._choose_size_px(salt, 0, false))
	if max_size > 48.0:
		_fail("Rock visual scale exceeded expected half-size max: %.2f" % max_size)

	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(terrain_ids.size()):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)

	var checked_chunks: int = 0
	var first_rock_count: int = 0
	var collider_count: int = 0
	var collider_chunk := Vector2i.ZERO
	for chunk_y: int in range(32):
		for chunk_x: int in range(32):
			checked_chunks += 1
			var chunk_coord := Vector2i(chunk_x, chunk_y)
			layer.configure_chunk(
				chunk_coord,
				WorldRuntimeConstants.DEFAULT_WORLD_SEED,
				WorldRuntimeConstants.WORLD_VERSION,
				terrain_ids,
				lake_flags
			)
			if first_rock_count <= 0:
				first_rock_count = layer.get_rock_count()
			if layer.get_collider_count() > 0:
				collider_count = layer.get_collider_count()
				collider_chunk = chunk_coord
				break
		if collider_count > 0:
			break

	if first_rock_count <= 0:
		_fail("Rock scatter produced no rocks in checked plains chunks.")
	if collider_count <= 0:
		_fail("Large rock collision proof produced no colliders in checked plains chunks.")

	print(
		"WORLD_ROCK_SCATTER_SMOKE chunks=%d rocks=%d colliders=%d collider_chunk=%s max_size=%.2f" %
		[checked_chunks, layer.get_rock_count(), collider_count, str(collider_chunk), max_size]
	)
	layer.free()
	quit()

func _make_texture() -> Texture2D:
	var image := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
