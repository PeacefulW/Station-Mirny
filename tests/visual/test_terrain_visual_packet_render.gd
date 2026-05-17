extends GdUnitTestSuite

const MATERIAL_SCRIPT_PATH := "res://data/terrain_visual/terrain_visual_packet_material.gd"
const PACKET_SHADER_PATH := "res://assets/shaders/terrain_visual_packet.gdshader"
const PREVIEW_SCENE_PATH := "res://tests/visual/terrain_visual_packet_render_scene.tscn"
const VIEWPORT_SIZE := Vector2i(64, 64)

const DEBUG_MODE_ALBEDO := 0
const DEBUG_MODE_ZONE := 1
const DEBUG_MODE_HEIGHT := 3
const DEBUG_MODE_NORMAL := 4


func test_shader_consumes_packet_textures_without_topology_inference() -> void:
	var source := FileAccess.get_file_as_string(PACKET_SHADER_PATH)

	assert_that(source.contains("uniform sampler2D zone_texture")).is_true()
	assert_that(source.contains("uniform sampler2D height_texture")).is_true()
	assert_that(source.contains("uniform sampler2D normal_texture")).is_true()
	assert_that(source.contains("uniform sampler2D coverage_face_texture")).is_true()
	assert_that(source.contains("uniform int debug_mode")).is_true()
	assert_that(source.contains("MODE_ZONE")).is_true()
	assert_that(source.contains("MODE_HEIGHT")).is_true()
	assert_that(source.contains("MODE_NORMAL")).is_true()
	assert_that(source.contains("TEXTURE")).is_false()
	assert_that(source.to_lower().contains("sdf")).is_false()
	assert_that(source.contains("dFdx")).is_false()
	assert_that(source.contains("dFdy")).is_false()


func test_material_builder_wires_packet_textures() -> void:
	var packet := _build_packet()
	var builder: RefCounted = _new_material_builder()
	if builder == null:
		return

	var material: ShaderMaterial = builder.call("build_material", packet, DEBUG_MODE_ZONE)

	assert_that(material).is_not_null()
	assert_that(material.get_shader_parameter("debug_mode")).is_equal(DEBUG_MODE_ZONE)
	assert_that(_texture_size(material, "zone_texture")).is_equal(Vector2i(48, 48))
	assert_that(_texture_size(material, "height_texture")).is_equal(Vector2i(48, 48))
	assert_that(_texture_size(material, "normal_texture")).is_equal(Vector2i(48, 48))
	assert_that(_texture_size(material, "material_u_texture")).is_equal(Vector2i(48, 48))


func test_render_scene_draws_albedo_zone_height_and_normal_from_packet() -> void:
	var packet := _build_packet()
	var hashes := { }
	for debug_mode: int in [
		DEBUG_MODE_ALBEDO,
		DEBUG_MODE_ZONE,
		DEBUG_MODE_HEIGHT,
		DEBUG_MODE_NORMAL,
	]:
		var image := await _render_mode(packet, debug_mode)
		assert_that(image).is_not_null()
		if image == null:
			return
		assert_that(_count_visible_pixels(image)).is_greater(0)
		hashes[debug_mode] = _image_lsb_hash(image)

	assert_that(hashes[DEBUG_MODE_ALBEDO]).is_not_equal(hashes[DEBUG_MODE_ZONE])
	assert_that(hashes[DEBUG_MODE_ZONE]).is_not_equal(hashes[DEBUG_MODE_HEIGHT])
	assert_that(hashes[DEBUG_MODE_HEIGHT]).is_not_equal(hashes[DEBUG_MODE_NORMAL])


func _build_packet() -> Dictionary:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		return { }
	var solver: Object = ClassDB.instantiate(&"TerrainVisualSolver")
	assert_that(solver).is_not_null()
	if solver == null:
		return { }

	var mask := PackedByteArray(
		[
			1,
			1,
			1,
			1,
			0,
			1,
			1,
			1,
			1,
		],
	)
	var packet: Dictionary = solver.call(
		"build_editor_preview_packet",
		mask,
		3,
		3,
		{
			"schema_version": 1,
			"recipe_id": &"test:packet_render",
			"surface_kind": &"rock",
			"tile_size_px": 16,
			"rim_width_px": 2.0,
			"south_height_px": 6.0,
			"north_height_px": 0.0,
			"side_height_px": 4.0,
			"face_power": 1.0,
			"back_drop": 0.5,
			"normal_strength": 2.0,
		},
		Vector2i.ZERO,
		37,
	)
	solver.free()
	return packet


func _new_material_builder() -> RefCounted:
	var script: Script = load(MATERIAL_SCRIPT_PATH)
	assert_that(script).is_not_null()
	if script == null:
		return null
	return script.new()


func _texture_size(material: ShaderMaterial, parameter_name: StringName) -> Vector2i:
	var texture: Texture2D = material.get_shader_parameter(parameter_name) as Texture2D
	assert_that(texture).is_not_null()
	if texture == null:
		return Vector2i.ZERO
	return texture.get_size()


func _render_mode(packet: Dictionary, debug_mode: int) -> Image:
	var scene: PackedScene = load(PREVIEW_SCENE_PATH) as PackedScene
	assert_that(scene).is_not_null()
	if scene == null:
		return null
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var preview: Node2D = scene.instantiate() as Node2D
	assert_that(preview).is_not_null()
	if preview == null:
		viewport.free()
		return null
	viewport.add_child(preview)
	preview.call("apply_packet", packet, debug_mode)

	await await_idle_frame()
	await await_idle_frame()
	await await_millis(50)

	var image: Image = viewport.get_texture().get_image()
	viewport.free()
	return image


func _count_visible_pixels(image: Image) -> int:
	var count := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if _to_lsb(image.get_pixel(x, y).a) > 0:
				count += 1
	return count


func _image_lsb_hash(image: Image) -> int:
	var hash := 17
	for y: int in range(0, image.get_height(), 3):
		for x: int in range(0, image.get_width(), 3):
			var color := image.get_pixel(x, y)
			hash = int(hash * 31 + _to_lsb(color.r))
			hash = int(hash * 31 + _to_lsb(color.g))
			hash = int(hash * 31 + _to_lsb(color.b))
			hash = int(hash * 31 + _to_lsb(color.a))
	return hash


func _to_lsb(value: float) -> int:
	return clampi(roundi(value * 255.0), 0, 255)
