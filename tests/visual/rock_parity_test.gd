extends GdUnitTestSuite

const VIEWPORT_SIZE: Vector2i = Vector2i(256, 256)
const TOLERANCE_LSB: int = 1
const ROCK_VISUAL_PATH: String = "res://core/data/visuals/rock_biome_visual.tres"
const PREVIEW_SCENE_PATH: String = "res://addons/biome_visual_authoring/biome_visual_preview.tscn"
const SABOTAGE_ENV: String = "IT6_ROCK_PARITY_SABOTAGE"


func test_rock_preview_runtime_parity(
		_do_skip := true,
		_skip_reason := "Legacy ChunkView RockVisualResource runtime path was removed by V2.",
) -> void:
	var rock_visual: RockVisualResource = load(ROCK_VISUAL_PATH) as RockVisualResource
	assert_object(rock_visual).is_not_null()

	var preview_viewport: SubViewport = _make_viewport("RockPreviewParityViewport")
	var runtime_viewport: SubViewport = _make_viewport("RockRuntimeParityViewport")
	add_child(preview_viewport)
	add_child(runtime_viewport)

	var preview_node: Node2D = _make_preview_path(rock_visual)
	var runtime_node: Node2D = _make_runtime_path(rock_visual, preview_node)
	preview_viewport.add_child(preview_node)
	runtime_viewport.add_child(runtime_node)

	await _settle_render_frames()

	if OS.get_environment(SABOTAGE_ENV) == "preview_top_color":
		_sabotage_preview_top_color(preview_node)
		await _settle_render_frames()

	var preview_image: Image = preview_viewport.get_texture().get_image()
	var runtime_image: Image = runtime_viewport.get_texture().get_image()
	var comparison: Dictionary = _compare_images(preview_image, runtime_image)

	preview_viewport.free()
	runtime_viewport.free()

	assert_bool(bool(comparison["matched"])) \
			.override_failure_message(str(comparison["message"])) \
			.is_true()


func _make_viewport(viewport_name: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return viewport


func _settle_render_frames() -> void:
	await await_idle_frame()
	await await_idle_frame()
	await await_millis(50)


func _make_preview_path(rock_visual: RockVisualResource) -> Node2D:
	var preview_scene: PackedScene = load(PREVIEW_SCENE_PATH) as PackedScene
	assert_object(preview_scene).is_not_null()
	var preview_node: Node2D = preview_scene.instantiate() as Node2D
	assert_object(preview_node).is_not_null()
	preview_node.set("biome_visual", rock_visual)
	var preview_shape: Polygon2D = preview_node.get_node("MountainShape") as Polygon2D
	assert_object(preview_shape).is_not_null()
	return preview_node


func _make_runtime_path(rock_visual: RockVisualResource, preview_node: Node2D) -> Node2D:
	var runtime_node := Node2D.new()

	var preview_background: ColorRect = preview_node.get_node("PreviewRect") as ColorRect
	assert_object(preview_background).is_not_null()
	var runtime_background := ColorRect.new()
	runtime_background.name = "PreviewRect"
	runtime_background.position = preview_background.position
	runtime_background.size = preview_background.size
	runtime_background.color = preview_background.color

	var preview_shape: Polygon2D = preview_node.get_node("MountainShape") as Polygon2D
	assert_object(preview_shape).is_not_null()
	var runtime_shape := Polygon2D.new()
	runtime_shape.name = "MountainShape"
	runtime_shape.polygon = preview_shape.polygon
	runtime_shape.uv = preview_shape.uv
	runtime_shape.color = preview_shape.color

	var chunk_view := ChunkView.new()
	var material: ShaderMaterial = (
		chunk_view.call("_build_rock_visual_material", rock_visual) as ShaderMaterial
	)
	chunk_view.free()
	assert_object(material).is_not_null()
	runtime_shape.material = material

	var preview_outline: Line2D = preview_node.get_node("MountainOutline") as Line2D
	assert_object(preview_outline).is_not_null()
	var runtime_outline := Line2D.new()
	runtime_outline.name = "MountainOutline"
	runtime_outline.z_index = preview_outline.z_index
	runtime_outline.points = preview_outline.points
	runtime_outline.closed = preview_outline.closed
	runtime_outline.width = preview_outline.width
	runtime_outline.default_color = preview_outline.default_color

	runtime_node.add_child(runtime_background)
	runtime_node.add_child(runtime_shape)
	runtime_node.add_child(runtime_outline)
	return runtime_node


func _sabotage_preview_top_color(preview_node: Node2D) -> void:
	var preview_shape: Polygon2D = preview_node.get_node("MountainShape") as Polygon2D
	var material: ShaderMaterial = preview_shape.material as ShaderMaterial
	assert_object(material).is_not_null()
	material.set_shader_parameter("top_color", Color.RED)
	preview_shape.queue_redraw()


func _compare_images(preview_image: Image, runtime_image: Image) -> Dictionary:
	if preview_image == null or runtime_image == null:
		return {
			"matched": false,
			"message": (
				"Rock parity failed: one viewport did not return an image. "
				+ "Run GdUnit with -NoHeadless; the headless dummy renderer cannot "
				+ "capture SubViewport images."
			),
		}
	if preview_image.get_size() != runtime_image.get_size():
		return {
			"matched": false,
			"message": "Rock parity failed: viewport size mismatch preview=%s runtime=%s." % [
				preview_image.get_size(),
				runtime_image.get_size(),
			],
		}

	var mismatch_count: int = 0
	var first_coord := Vector2i(-1, -1)
	var first_preview := Color.TRANSPARENT
	var first_runtime := Color.TRANSPARENT
	var first_delta: int = 0
	var image_size: Vector2i = preview_image.get_size()
	for y: int in range(image_size.y):
		for x: int in range(image_size.x):
			var preview_color: Color = preview_image.get_pixel(x, y)
			var runtime_color: Color = runtime_image.get_pixel(x, y)
			var delta: int = _max_lsb_delta(preview_color, runtime_color)
			if delta <= TOLERANCE_LSB:
				continue
			mismatch_count += 1
			if first_coord.x < 0:
				first_coord = Vector2i(x, y)
				first_preview = preview_color
				first_runtime = runtime_color
				first_delta = delta

	if mismatch_count == 0:
		return {
			"matched": true,
			"message": "Rock parity passed.",
		}
	return {
		"matched": false,
		"message": (
			"Rock parity failed: %d pixels exceeded %d LSB tolerance; "
			+ "first diff at %s preview=%s runtime=%s max_delta=%d."
		) % [
			mismatch_count,
			TOLERANCE_LSB,
			first_coord,
			_format_color_lsb(first_preview),
			_format_color_lsb(first_runtime),
			first_delta,
		],
	}


func _max_lsb_delta(a: Color, b: Color) -> int:
	return maxi(
		maxi(abs(_to_lsb(a.r) - _to_lsb(b.r)), abs(_to_lsb(a.g) - _to_lsb(b.g))),
		maxi(abs(_to_lsb(a.b) - _to_lsb(b.b)), abs(_to_lsb(a.a) - _to_lsb(b.a))),
	)


func _to_lsb(value: float) -> int:
	return clampi(roundi(value * 255.0), 0, 255)


func _format_color_lsb(color: Color) -> String:
	return "rgba(%d,%d,%d,%d)" % [
		_to_lsb(color.r),
		_to_lsb(color.g),
		_to_lsb(color.b),
		_to_lsb(color.a),
	]
