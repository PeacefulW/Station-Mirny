extends GdUnitTestSuite

const MATERIAL_SCRIPT_PATH := "res://data/terrain_visual/terrain_visual_packet_material.gd"
const MATERIAL_SLOT_SCRIPT_PATH := "res://data/terrain_visual/terrain_visual_material_slot.gd"
const RECIPE_SCRIPT_PATH := "res://data/terrain_visual/terrain_visual_recipe.gd"
const RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"
const OLD_REFERENCE_ALBEDO_PATH := (
	"res://tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/"
	+ "mountain_reference_albedo.png"
)
const VIEWPORT_SIZE := Vector2i(96, 96)
const DEBUG_MODE_ALBEDO := 0


func test_default_recipe_keeps_old_generator_rock_material_kinds() -> void:
	var recipe: Resource = load(RECIPE_PATH) as Resource
	assert_that(recipe).is_not_null()
	if recipe == null:
		return

	assert_that(_slot(recipe, &"top").get("procedural_kind")).is_equal(&"rough_stone")
	assert_that(_slot(recipe, &"face").get("procedural_kind")).is_equal(&"stratified_rock")
	assert_that(_slot(recipe, &"base").get("procedural_kind")).is_equal(&"packed_dirt")
	assert_that(_slot(recipe, &"back").get("procedural_kind")).is_equal(&"stratified_rock")


func test_material_builder_wires_flat_image_and_procedural_sources() -> void:
	var packet := _synthetic_packet(Vector2i(8, 8), &"top")
	var recipe := _recipe_fixture()
	var top_image := _checker_texture(Color.RED, Color.BLUE)
	recipe.set(
		"top_material",
		_material_slot(
			&"image",
			&"rough_stone",
			Color(0.1, 0.2, 0.3, 1.0),
			top_image,
		),
	)
	recipe.set(
		"face_material",
		_material_slot(
			&"procedural",
			&"stratified_rock",
			Color(0.2, 0.2, 0.2, 1.0),
			null,
		),
	)
	recipe.set(
		"base_material",
		_material_slot(
			&"flat",
			&"packed_dirt",
			Color(0.4, 0.3, 0.2, 1.0),
			null,
		),
	)

	var material: ShaderMaterial = _new_material_builder().call(
		"build_material",
		packet,
		DEBUG_MODE_ALBEDO,
		recipe,
	)

	assert_that(material.get_shader_parameter("top_source")).is_equal(1)
	assert_that(material.get_shader_parameter("face_source")).is_equal(0)
	assert_that(material.get_shader_parameter("base_source")).is_equal(2)
	assert_that(material.get_shader_parameter("face_kind")).is_equal(0)
	assert_that(material.get_shader_parameter("top_image_albedo")).is_same(top_image)
	assert_that(material.get_shader_parameter("top_params")).is_equal(
		Vector4(1.5, 1.25, 0.4, 0.35),
	)
	assert_that(material.get_shader_parameter("top_params2")).is_equal(
		Vector4(0.7, 0.25, 0.9, 0.8),
	)


func test_material_builder_maps_old_generator_runtime_kinds() -> void:
	var packet := _synthetic_packet(Vector2i(8, 8), &"top")
	var expected_ids := {
		&"stratified_rock": 0,
		&"rough_stone": 1,
		&"cracked_dry_earth": 2,
		&"packed_dirt": 3,
		&"sand": 4,
		&"ash_burnt_ground": 5,
		&"snow": 6,
		&"moss": 7,
		&"gravel": 8,
		&"concrete": 9,
		&"ribbed_steel": 10,
		&"ice_frost": 11,
	}

	for kind: StringName in expected_ids.keys():
		var recipe := _recipe_fixture()
		recipe.set(
			"top_material",
			_material_slot(
				&"procedural",
				kind,
				Color(0.26, 0.24, 0.20, 1.0),
				null,
			),
		)
		var material: ShaderMaterial = _new_material_builder().call(
			"build_material",
			packet,
			DEBUG_MODE_ALBEDO,
			recipe,
		)
		assert_that(material.get_shader_parameter("top_kind")).is_equal(expected_ids[kind])


func test_material_builder_accepts_old_generator_kind_aliases() -> void:
	var packet := _synthetic_packet(Vector2i(8, 8), &"top")
	var expected_alias_ids := {
		&"layered_rock": 0,
		&"stone": 1,
		&"cracked_earth": 2,
		&"dirt": 3,
		&"sand_dune": 4,
		&"ash": 5,
		&"snow_surface": 6,
		&"moss_patch": 7,
		&"regolith": 8,
		&"diamond_plate": 10,
		&"ice": 11,
	}

	for kind: StringName in expected_alias_ids.keys():
		var recipe := _recipe_fixture()
		recipe.set(
			"top_material",
			_material_slot(
				&"procedural",
				kind,
				Color(0.26, 0.24, 0.20, 1.0),
				null,
			),
		)
		var material: ShaderMaterial = _new_material_builder().call(
			"build_material",
			packet,
			DEBUG_MODE_ALBEDO,
			recipe,
		)
		assert_that(material.get_shader_parameter("top_kind")).is_equal(expected_alias_ids[kind])


func test_material_slot_validates_runtime_procedural_kind_registry() -> void:
	for kind: StringName in [
		&"stratified_rock",
		&"rough_stone",
		&"cracked_dry_earth",
		&"packed_dirt",
		&"sand",
		&"ash_burnt_ground",
		&"snow",
		&"moss",
		&"gravel",
		&"concrete",
		&"ribbed_steel",
		&"ice_frost",
	]:
		var slot := _material_slot(
			&"procedural",
			kind,
			Color(0.26, 0.24, 0.20, 1.0),
			null,
		)
		assert_that(slot.call("validate")).is_empty()


func test_procedural_kinds_produce_distinct_albedo_from_material_uv() -> void:
	var packet := _synthetic_packet(Vector2i(32, 32), &"top")
	var hashes := { }

	for kind: StringName in [
		&"stratified_rock",
		&"rough_stone",
		&"cracked_dry_earth",
		&"packed_dirt",
		&"sand",
		&"ash_burnt_ground",
		&"snow",
		&"moss",
		&"gravel",
		&"concrete",
		&"ribbed_steel",
		&"ice_frost",
	]:
		var recipe := _recipe_fixture()
		recipe.set(
			"top_material",
			_material_slot(
				&"procedural",
				kind,
				Color(0.26, 0.24, 0.20, 1.0),
				null,
			),
		)
		var image := await _render_packet(packet, recipe)
		assert_that(image).is_not_null()
		hashes[kind] = _image_lsb_hash(image)

	assert_that(hashes[&"stratified_rock"]).is_not_equal(hashes[&"rough_stone"])
	assert_that(hashes[&"rough_stone"]).is_not_equal(hashes[&"cracked_dry_earth"])
	assert_that(hashes[&"cracked_dry_earth"]).is_not_equal(hashes[&"packed_dirt"])
	assert_that(hashes[&"sand"]).is_not_equal(hashes[&"ash_burnt_ground"])
	assert_that(hashes[&"snow"]).is_not_equal(hashes[&"ice_frost"])
	assert_that(hashes[&"moss"]).is_not_equal(hashes[&"gravel"])
	assert_that(hashes[&"concrete"]).is_not_equal(hashes[&"ribbed_steel"])


func test_image_face_material_uses_packet_projection_not_screen_uv() -> void:
	var recipe := _recipe_fixture()
	recipe.set(
		"face_material",
		_material_slot(
			&"image",
			&"stratified_rock",
			Color.WHITE,
			_stripe_texture(),
		),
	)
	var projected_packet := _synthetic_packet(Vector2i(32, 32), &"face")
	var flat_uv_packet := projected_packet.duplicate(true)
	_fill_q16_field(flat_uv_packet, "material_u_q16", 0.125)
	_fill_q16_field(flat_uv_packet, "material_v_q16", 0.125)

	var projected_image := await _render_packet(projected_packet, recipe)
	var flat_uv_image := await _render_packet(flat_uv_packet, recipe)

	assert_that(_image_lsb_hash(projected_image)).is_not_equal(_image_lsb_hash(flat_uv_image))
	assert_that(_image_luminance_variance(projected_image)).is_greater(
		_image_luminance_variance(flat_uv_image) + 20.0,
	)


func test_generated_reference_keeps_old_generator_texture_variance() -> void:
	var old_reference := _load_png_image(OLD_REFERENCE_ALBEDO_PATH)
	assert_that(old_reference).is_not_null()
	if old_reference == null:
		return

	var recipe: Resource = load(RECIPE_PATH).duplicate(true) as Resource
	recipe.set("tile_size_px", 16)
	recipe.set("rim_width_px", 2.0)
	recipe.set("south_height_px", 6.0)
	recipe.set("side_height_px", 4.0)
	var packet := _solve_fixture_packet(recipe)
	var image := await _render_packet(packet, recipe)

	assert_that(_image_luminance_variance(image)).is_greater(
		_image_luminance_variance(old_reference) * 0.20,
	)


func _recipe_fixture() -> Resource:
	var script: Script = load(RECIPE_SCRIPT_PATH)
	assert_that(script).is_not_null()
	var recipe: Resource = script.new()
	recipe.set("id", &"test:material_parity")
	recipe.set("display_name_key", &"TEST_TERRAIN_VISUAL_MATERIAL_PARITY")
	recipe.set("surface_kind", &"rock")
	recipe.set("tile_size_px", 16)
	recipe.set("variant_count", 1)
	recipe.set("south_height_px", 6.0)
	recipe.set("north_height_px", 0.0)
	recipe.set("side_height_px", 4.0)
	recipe.set("face_power", 1.0)
	recipe.set("back_drop", 0.5)
	recipe.set("shape_supersampling", 4)
	recipe.set("rim_width_px", 2.0)
	recipe.set(
		"top_material",
		_material_slot(&"procedural", &"rough_stone", Color(0.3, 0.26, 0.2, 1.0), null),
	)
	recipe.set(
		"face_material",
		_material_slot(
			&"procedural",
			&"stratified_rock",
			Color(0.18, 0.16, 0.14, 1.0),
			null,
		),
	)
	recipe.set(
		"base_material",
		_material_slot(&"procedural", &"packed_dirt", Color(0.45, 0.27, 0.12, 1.0), null),
	)
	recipe.set(
		"back_material",
		_material_slot(
			&"procedural",
			&"stratified_rock",
			Color(0.14, 0.13, 0.12, 1.0),
			null,
		),
	)
	return recipe


func _material_slot(
		source: StringName,
		kind: StringName,
		color_a: Color,
		image_albedo: Texture2D,
) -> Resource:
	var script: Script = load(MATERIAL_SLOT_SCRIPT_PATH)
	assert_that(script).is_not_null()
	var slot: Resource = script.new()
	slot.set("source", source)
	slot.set("procedural_kind", kind)
	slot.set("image_albedo", image_albedo)
	slot.set("flat_color", color_a)
	slot.set("color_a", color_a)
	slot.set("color_b", color_a.lightened(0.35))
	slot.set("highlight_color", color_a.lightened(0.65))
	slot.set("scale", 1.5)
	slot.set("contrast", 1.25)
	slot.set("crack_amount", 0.4)
	slot.set("wear", 0.35)
	slot.set("grain", 0.7)
	slot.set("edge_darkening", 0.25)
	slot.set("seed", 17)
	slot.set("normal_mix", 0.9)
	slot.set("modulation_strength", 0.8)
	return slot


func _synthetic_packet(size: Vector2i, zone_name: StringName) -> Dictionary:
	var pixel_count := size.x * size.y
	var zone_id := 1 if zone_name == &"top" else 3
	var packet := {
		"schema_version": 1,
		"recipe_id": &"test:synthetic_material_packet",
		"surface_kind": &"rock",
		"world_origin_tile": Vector2i.ZERO,
		"chunk_coord": Vector2i.ZERO,
		"dirty_rect_tiles": Rect2i(Vector2i.ZERO, Vector2i.ONE),
		"dirty_rect_px": Rect2i(Vector2i.ZERO, size),
		"tile_size_px": 16,
		"pixel_width": size.x,
		"pixel_height": size.y,
		"zone_ids": PackedByteArray(),
		"coverage_top": PackedByteArray(),
		"coverage_edge": PackedByteArray(),
		"coverage_face": PackedByteArray(),
		"coverage_back": PackedByteArray(),
		"height_q16": PackedByteArray(),
		"normal_rgba8": PackedByteArray(),
		"material_u_q16": PackedByteArray(),
		"material_v_q16": PackedByteArray(),
		"outline_polylines": [],
		"debug_counters": { },
	}
	for field_name: String in [
		"zone_ids",
		"coverage_top",
		"coverage_edge",
		"coverage_face",
		"coverage_back",
	]:
		packet[field_name].resize(pixel_count)
	packet["height_q16"].resize(pixel_count * 2)
	packet["normal_rgba8"].resize(pixel_count * 4)
	packet["material_u_q16"].resize(pixel_count * 2)
	packet["material_v_q16"].resize(pixel_count * 2)

	for y: int in range(size.y):
		for x: int in range(size.x):
			var index := y * size.x + x
			packet["zone_ids"][index] = zone_id
			packet["coverage_top"][index] = 255 if zone_name == &"top" else 0
			packet["coverage_face"][index] = 255 if zone_name == &"face" else 0
			_write_q16(packet["height_q16"], index, 1.0)
			_write_rgba8(packet["normal_rgba8"], index, Color(0.5, 0.5, 1.0, 1.0))
			_write_q16(packet["material_u_q16"], index, float(x) / float(maxi(1, size.x - 1)))
			_write_q16(packet["material_v_q16"], index, float(y) / float(maxi(1, size.y - 1)))
	return packet


func _solve_fixture_packet(recipe: Resource) -> Dictionary:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	var solver: Object = ClassDB.instantiate(&"TerrainVisualSolver")
	var mask := PackedByteArray(
		[
			0,
			1,
			1,
			0,
			1,
			1,
			1,
			1,
			1,
			1,
			1,
			0,
			0,
			1,
			1,
			0,
		],
	)
	var packet: Dictionary = solver.call(
		"build_editor_preview_packet",
		mask,
		4,
		4,
		{
			"schema_version": recipe.schema_version,
			"recipe_id": recipe.get("id"),
			"surface_kind": recipe.get("surface_kind"),
			"tile_size_px": recipe.get("tile_size_px"),
			"rim_width_px": recipe.get("rim_width_px"),
			"south_height_px": recipe.get("south_height_px"),
			"north_height_px": recipe.get("north_height_px"),
			"side_height_px": recipe.get("side_height_px"),
			"face_power": recipe.get("face_power"),
			"back_drop": recipe.get("back_drop"),
			"normal_strength": recipe.get("normal_strength"),
		},
		Vector2i.ZERO,
		recipe.get("default_seed"),
	)
	solver.free()
	return packet


func _render_packet(packet: Dictionary, recipe: Resource) -> Image:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var quad := ColorRect.new()
	quad.color = Color.WHITE
	quad.size = Vector2(
		float(packet.get("pixel_width", VIEWPORT_SIZE.x)),
		float(packet.get("pixel_height", VIEWPORT_SIZE.y)),
	)
	quad.material = _new_material_builder().call(
		"build_material",
		packet,
		DEBUG_MODE_ALBEDO,
		recipe,
	)
	viewport.add_child(quad)

	await await_idle_frame()
	await await_idle_frame()
	await await_millis(50)

	var image: Image = viewport.get_texture().get_image()
	viewport.free()
	return image


func _new_material_builder() -> RefCounted:
	var script: Script = load(MATERIAL_SCRIPT_PATH)
	assert_that(script).is_not_null()
	if script == null:
		return null
	return script.new()


func _slot(recipe: Resource, slot_id: StringName) -> Resource:
	if recipe == null or not recipe.has_method("get_material_slot"):
		return null
	return recipe.call("get_material_slot", slot_id) as Resource


func _checker_texture(first: Color, second: Color) -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y: int in range(4):
		for x: int in range(4):
			image.set_pixel(x, y, first if (x + y) % 2 == 0 else second)
	return ImageTexture.create_from_image(image)


func _stripe_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y: int in range(8):
		for x: int in range(8):
			var color := Color(0.08, 0.08, 0.08, 1.0) if y < 4 else Color(0.92, 0.92, 0.92, 1.0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _load_png_image(path: String) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_that(file).is_not_null()
	if file == null:
		return null
	var image := Image.new()
	var result := image.load_png_from_buffer(file.get_buffer(file.get_length()))
	assert_that(result).is_equal(OK)
	if result != OK:
		return null
	return image


func _fill_q16_field(packet: Dictionary, field_name: String, value: float) -> void:
	var bytes: PackedByteArray = packet.get(field_name, PackedByteArray())
	for index: int in range(bytes.size() / 2):
		_write_q16(bytes, index, value)
	packet[field_name] = bytes


func _write_q16(bytes: PackedByteArray, pixel_index: int, value: float) -> void:
	var q16 := clampi(roundi(clampf(value, 0.0, 1.0) * 65535.0), 0, 65535)
	var offset := pixel_index * 2
	bytes[offset] = q16 & 0xff
	bytes[offset + 1] = (q16 >> 8) & 0xff


func _write_rgba8(bytes: PackedByteArray, pixel_index: int, color: Color) -> void:
	var offset := pixel_index * 4
	bytes[offset] = _to_lsb(color.r)
	bytes[offset + 1] = _to_lsb(color.g)
	bytes[offset + 2] = _to_lsb(color.b)
	bytes[offset + 3] = _to_lsb(color.a)


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


func _image_luminance_variance(image: Image) -> float:
	var count := 0
	var sum := 0.0
	var sum_squares := 0.0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a <= 0.01:
				continue
			var luma := (color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722) * 255.0
			count += 1
			sum += luma
			sum_squares += luma * luma
	if count == 0:
		return 0.0
	var mean := sum / float(count)
	return maxf(0.0, sum_squares / float(count) - mean * mean)


func _to_lsb(value: float) -> int:
	return clampi(roundi(value * 255.0), 0, 255)
