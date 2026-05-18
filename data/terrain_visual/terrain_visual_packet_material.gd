extends RefCounted

const DEBUG_MODE_ALBEDO := 0
const DEBUG_MODE_ZONE := 1
const DEBUG_MODE_COVERAGE := 2
const DEBUG_MODE_HEIGHT := 3
const DEBUG_MODE_NORMAL := 4
const DEBUG_MODE_MATERIAL_UV := 5
const DEBUG_MODE_LIT_PREVIEW := 6

const SOURCE_PROCEDURAL := 0
const SOURCE_IMAGE := 1
const SOURCE_FLAT := 2

const KIND_STRATIFIED_ROCK := 0
const KIND_ROUGH_STONE := 1
const KIND_CRACKED_DRY_EARTH := 2
const KIND_PACKED_DIRT := 3
const KIND_SAND := 4
const KIND_ASH_BURNT_GROUND := 5
const KIND_SNOW := 6
const KIND_MOSS := 7
const KIND_GRAVEL := 8
const KIND_CONCRETE := 9
const KIND_RIBBED_STEEL := 10
const KIND_ICE_FROST := 11

const PACKET_SHADER: Shader = preload("res://assets/shaders/terrain_visual_packet.gdshader")


func build_material(
		packet: Dictionary,
		debug_mode: int = DEBUG_MODE_ALBEDO,
		recipe: Resource = null,
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PACKET_SHADER
	apply_packet(material, packet)
	apply_recipe_materials(material, recipe)
	set_debug_mode(material, debug_mode)
	return material


func apply_packet(material: ShaderMaterial, packet: Dictionary) -> void:
	var pixel_size := Vector2i(
		int(packet.get("pixel_width", 0)),
		int(packet.get("pixel_height", 0)),
	)
	if pixel_size.x <= 0 or pixel_size.y <= 0:
		push_error("TerrainVisualPacketMaterial requires a positive packet pixel size.")
		return

	material.set_shader_parameter("packet_pixel_size", Vector2(pixel_size))
	material.set_shader_parameter(
		"zone_texture",
		_make_texture(packet, "zone_ids", pixel_size, Image.FORMAT_R8, 1),
	)
	material.set_shader_parameter(
		"coverage_top_texture",
		_make_texture(packet, "coverage_top", pixel_size, Image.FORMAT_R8, 1),
	)
	material.set_shader_parameter(
		"coverage_edge_texture",
		_make_texture(packet, "coverage_edge", pixel_size, Image.FORMAT_R8, 1),
	)
	material.set_shader_parameter(
		"coverage_face_texture",
		_make_texture(packet, "coverage_face", pixel_size, Image.FORMAT_R8, 1),
	)
	material.set_shader_parameter(
		"coverage_back_texture",
		_make_texture(packet, "coverage_back", pixel_size, Image.FORMAT_R8, 1),
	)
	material.set_shader_parameter(
		"height_texture",
		_make_texture(packet, "height_q16", pixel_size, Image.FORMAT_RG8, 2),
	)
	material.set_shader_parameter(
		"normal_texture",
		_make_texture(packet, "normal_rgba8", pixel_size, Image.FORMAT_RGBA8, 4),
	)
	material.set_shader_parameter(
		"material_u_texture",
		_make_texture(packet, "material_u_q16", pixel_size, Image.FORMAT_RG8, 2),
	)
	material.set_shader_parameter(
		"material_v_texture",
		_make_texture(packet, "material_v_q16", pixel_size, Image.FORMAT_RG8, 2),
	)


func set_debug_mode(material: ShaderMaterial, debug_mode: int) -> void:
	material.set_shader_parameter(
		"debug_mode",
		clampi(debug_mode, DEBUG_MODE_ALBEDO, DEBUG_MODE_LIT_PREVIEW),
	)


func apply_recipe_colors(material: ShaderMaterial, recipe: Resource) -> void:
	apply_recipe_materials(material, recipe)


func apply_recipe_materials(material: ShaderMaterial, recipe: Resource) -> void:
	if material == null or recipe == null:
		return
	_apply_slot_material(
		material,
		recipe,
		&"top",
		Color(0.60, 0.58, 0.52, 1.0),
	)
	_apply_slot_material(
		material,
		recipe,
		&"edge",
		Color(0.40, 0.38, 0.34, 1.0),
	)
	_apply_slot_material(
		material,
		recipe,
		&"face",
		Color(0.34, 0.32, 0.29, 1.0),
	)
	_apply_slot_material(
		material,
		recipe,
		&"back",
		Color(0.22, 0.20, 0.18, 1.0),
	)
	_apply_slot_material(
		material,
		recipe,
		&"base",
		Color(0.31, 0.24, 0.15, 1.0),
	)
	_apply_recipe_render_controls(material, recipe)


func _make_texture(
		packet: Dictionary,
		field_name: String,
		pixel_size: Vector2i,
		image_format: int,
		bytes_per_pixel: int,
) -> ImageTexture:
	var bytes: PackedByteArray = packet.get(field_name, PackedByteArray())
	var expected_size := pixel_size.x * pixel_size.y * bytes_per_pixel
	if bytes.size() != expected_size:
		push_error(
			"TerrainVisualPacketMaterial field %s has %d bytes, expected %d."
			% [field_name, bytes.size(), expected_size],
		)
		return null
	var image := Image.create_from_data(
		pixel_size.x,
		pixel_size.y,
		false,
		image_format,
		bytes,
	)
	return ImageTexture.create_from_image(image)


func _apply_slot_material(
		material: ShaderMaterial,
		recipe: Resource,
		slot_id: StringName,
		fallback: Color,
) -> void:
	var slot := _slot(recipe, slot_id)
	if slot == null and slot_id == &"edge":
		slot = _slot(recipe, &"face")

	var prefix := str(slot_id)
	var source_id := SOURCE_PROCEDURAL
	var kind_id := KIND_STRATIFIED_ROCK
	var flat_color := fallback
	var color_a := fallback
	var color_b := fallback.lightened(0.25)
	var highlight_color := fallback.lightened(0.45)
	var params := Vector4(1.0, 1.0, 0.35, 0.25)
	var params2 := Vector4(0.45, 0.35, 1.0, 0.75)
	var seed := 0
	var image_albedo: Texture2D = null

	if slot != null:
		source_id = _source_id(slot)
		kind_id = _kind_id(slot)
		flat_color = _color_property(slot, &"flat_color", fallback)
		color_a = _color_property(slot, &"color_a", fallback)
		color_b = _color_property(slot, &"color_b", color_a.lightened(0.25))
		highlight_color = _color_property(slot, &"highlight_color", color_b.lightened(0.25))
		params = Vector4(
			_float_property(slot, &"scale", 1.0),
			_float_property(slot, &"contrast", 1.0),
			_float_property(slot, &"crack_amount", 0.35),
			_float_property(slot, &"wear", 0.25),
		)
		params2 = Vector4(
			_float_property(slot, &"grain", 0.45),
			_float_property(slot, &"edge_darkening", 0.35),
			_float_property(slot, &"normal_mix", 1.0),
			_float_property(slot, &"modulation_strength", 0.75),
		)
		seed = int(slot.get("seed"))
		image_albedo = slot.get("image_albedo") as Texture2D

	material.set_shader_parameter("%s_source" % prefix, source_id)
	material.set_shader_parameter("%s_kind" % prefix, kind_id)
	material.set_shader_parameter("%s_flat_color" % prefix, flat_color)
	material.set_shader_parameter("%s_color_a" % prefix, color_a)
	material.set_shader_parameter("%s_color_b" % prefix, color_b)
	material.set_shader_parameter("%s_highlight_color" % prefix, highlight_color)
	material.set_shader_parameter("%s_params" % prefix, params)
	material.set_shader_parameter("%s_params2" % prefix, params2)
	material.set_shader_parameter("%s_seed" % prefix, seed)
	material.set_shader_parameter(
		"%s_image_albedo" % prefix,
		image_albedo if image_albedo != null else _solid_texture(flat_color),
	)

	# Legacy color uniforms stay wired for existing debug tools and sabotage tests.
	var legacy_color := flat_color if source_id == SOURCE_FLAT else color_a
	material.set_shader_parameter("%s_color" % prefix, legacy_color)


func _slot(recipe: Resource, slot_id: StringName) -> Resource:
	if not recipe.has_method("get_material_slot"):
		return null
	var slot: Resource = recipe.call("get_material_slot", slot_id) as Resource
	return slot


func _source_id(slot: Resource) -> int:
	var source: Variant = slot.get("source")
	match source:
		&"image":
			return SOURCE_IMAGE
		&"flat":
			return SOURCE_FLAT
		_:
			return SOURCE_PROCEDURAL


func _kind_id(slot: Resource) -> int:
	var kind: Variant = slot.get("procedural_kind")
	match kind:
		&"stratified_rock", &"layered_rock", &"sedimentary_rock", &"cliff_rock":
			return KIND_STRATIFIED_ROCK
		&"rough_stone", &"stone":
			return KIND_ROUGH_STONE
		&"cracked_dry_earth", &"cracked_earth", &"dry_earth":
			return KIND_CRACKED_DRY_EARTH
		&"packed_dirt", &"dirt":
			return KIND_PACKED_DIRT
		&"sand", &"sand_dune":
			return KIND_SAND
		&"ash_burnt_ground", &"ash", &"burnt_ground":
			return KIND_ASH_BURNT_GROUND
		&"snow", &"snow_surface":
			return KIND_SNOW
		&"moss", &"moss_patch":
			return KIND_MOSS
		&"gravel", &"regolith", &"gravel_regolith":
			return KIND_GRAVEL
		&"concrete", &"concrete_floor", &"floor_concrete", &"tiled_concrete":
			return KIND_CONCRETE
		&"ribbed_steel", &"steel_ribbed", &"diamond_plate", &"ribbed_metal":
			return KIND_RIBBED_STEEL
		&"ice_frost", &"ice", &"frost":
			return KIND_ICE_FROST
		_:
			return KIND_ROUGH_STONE


func _color_property(slot: Resource, property_name: StringName, fallback: Color) -> Color:
	var color_value: Variant = slot.get(property_name)
	if color_value is Color:
		return color_value
	return fallback


func _float_property(slot: Resource, property_name: StringName, fallback: float) -> float:
	var value: Variant = slot.get(property_name)
	if value == null:
		return fallback
	return float(value)


func _apply_recipe_render_controls(material: ShaderMaterial, recipe: Resource) -> void:
	material.set_shader_parameter(
		"edge_color_strength",
		clampf(_recipe_float(recipe, &"edge_color_strength", 0.0), 0.0, 1.0),
	)
	material.set_shader_parameter(
		"contact_outline_enabled",
		bool(recipe.get("contact_outline_enabled")),
	)
	material.set_shader_parameter(
		"contact_outline_width_px",
		maxf(0.0, _recipe_float(recipe, &"contact_outline_width_px", 0.0)),
	)
	var outline_color: Variant = recipe.get("contact_outline_color")
	material.set_shader_parameter(
		"contact_outline_color",
		outline_color if outline_color is Color else Color(0.05, 0.045, 0.04, 1.0),
	)


func _recipe_float(recipe: Resource, property_name: StringName, fallback: float) -> float:
	var value: Variant = recipe.get(property_name)
	if value == null:
		return fallback
	return float(value)


func _solid_texture(color: Color) -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
