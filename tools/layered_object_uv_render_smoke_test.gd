extends SceneTree

const BATCH_SHADER: Shader = preload("res://assets/shaders/layered_object_albedo_batch.gdshader")
const VIEWPORT_SIZE := Vector2i(96, 64)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("layered_object_uv_render_smoke_test requires a windowed GPU renderer")
		quit(2)
		return
	RenderingServer.set_default_clear_color(Color.BLACK)
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	for y: int in range(4):
		for x: int in range(4):
			image.set_pixel(x, y, Color.RED if y < 2 else Color.BLUE)
	var texture := ImageTexture.create_from_image(image)

	# Sprite2D is the authored PNG/Canvas orientation reference.
	var reference := Sprite2D.new()
	reference.texture = texture
	reference.position = Vector2(24.0, 32.0)
	reference.scale = Vector2(12.0, 12.0)
	reference.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(reference)

	# The production path uses primitive QuadMesh + MultiMeshInstance2D.
	var quad := QuadMesh.new()
	quad.size = Vector2(48.0, 48.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = 1
	multimesh.set_instance_transform_2d(0, Transform2D(0.0, Vector2(72.0, 32.0)))
	# R is atlas frame 0, G is tint=1, A is opacity=1.
	multimesh.set_instance_color(0, Color(0.0, 1.0, 0.0, 1.0))
	var batch := MultiMeshInstance2D.new()
	batch.multimesh = multimesh
	batch.texture = texture
	batch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = BATCH_SHADER
	material.set_shader_parameter("atlas_columns", 1.0)
	material.set_shader_parameter("atlas_rows", 1.0)
	material.set_shader_parameter("atlas_frame_count", 1.0)
	material.set_shader_parameter("frame_texel_size", Vector2(0.25, 0.25))
	batch.material = material
	viewport.add_child(batch)

	for frame_index: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = viewport.get_texture().get_image()
	var reference_top: Color = rendered.get_pixel(24, 18)
	var reference_bottom: Color = rendered.get_pixel(24, 46)
	var batch_top: Color = rendered.get_pixel(72, 18)
	var batch_bottom: Color = rendered.get_pixel(72, 46)
	_expect(reference_top.r > 0.8 and reference_top.b < 0.2, "Sprite reference top must be red")
	_expect(reference_bottom.b > 0.8 and reference_bottom.r < 0.2, "Sprite reference bottom must be blue")
	_expect(_color_distance(batch_top, reference_top) < 0.08, "batch top must match Sprite2D top")
	_expect(
		_color_distance(batch_bottom, reference_bottom) < 0.08,
		"batch bottom must match Sprite2D bottom",
	)

	viewport.queue_free()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	print("layered_object_uv_render_smoke_test: PASS")
	quit(0)


func _color_distance(left: Color, right: Color) -> float:
	return absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b) \
			+ absf(left.a - right.a)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
