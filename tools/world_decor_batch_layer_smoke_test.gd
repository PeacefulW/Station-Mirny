extends SceneTree

const WorldDecorBatchLayer = preload("res://core/systems/world/world_decor_batch_layer.gd")

func _init() -> void:
	var layer := WorldDecorBatchLayer.new()
	root.add_child(layer)

	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	var texture := ImageTexture.create_from_image(image)

	var sprite_buffer := PackedFloat32Array()
	WorldDecorBatchLayer.append_instance(
		sprite_buffer,
		Vector2(32.0, 32.0),
		Vector2(24.0, 24.0),
		3,
		Color.WHITE,
		0.0,
		0.25,
		1.0
	)
	WorldDecorBatchLayer.append_instance(
		sprite_buffer,
		Vector2(96.0, 96.0),
		Vector2(32.0, 32.0),
		4,
		Color(0.9, 0.9, 0.9, 1.0),
		0.0,
		0.5,
		1.0
	)

	var shadow_buffer := PackedFloat32Array()
	WorldDecorBatchLayer.append_instance(
		shadow_buffer,
		Vector2(32.0, 40.0),
		Vector2(28.0, 10.0),
		0,
		Color.WHITE,
		0.0,
		0.0,
		1.0
	)
	WorldDecorBatchLayer.append_instance(
		shadow_buffer,
		Vector2(96.0, 104.0),
		Vector2(34.0, 12.0),
		0,
		Color.WHITE,
		0.0,
		0.0,
		1.2
	)

	layer.set_atlas_layout(8, 4, 32)
	layer.set_chunk_size_px(1024.0)
	layer.set_batches([texture], [sprite_buffer], shadow_buffer)
	layer.set_sun_lighting(45.0, 128.0, 0.8, 24.0)

	var state: Dictionary = layer.get_debug_state()
	assert(int(state.get("instance_count", -1)) == 2)
	assert(int(state.get("shadow_instance_count", -1)) == 2)
	assert(bool(state.get("uses_multimesh", false)))
	print("WORLD_DECOR_BATCH_SMOKE ", state)

	layer.free()
	quit()
