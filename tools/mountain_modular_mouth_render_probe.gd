extends SceneTree

## TOOLS ONLY. Renders the production mountain mask shader against deterministic
## synthetic L8 masks. The two fixtures differ only by mouth width: one SOUTH
## mouth tile versus three adjacent SOUTH mouth tiles with continuation bits.
## No world save, runtime cache, production mask, or native code is mutated.

const MOUNTAIN_SHADER: Shader = preload("res://assets/shaders/mountain_top_mask_underlay.gdshader")
const TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png"
const TOP_NORMAL_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_normal.png"
const FACE_NORMAL_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_normal.png"
const GROUND_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/ground/orange_biofield_albedo.png"
const OUTPUT_DIR: String = "res://artifacts/mountain_modular_mouth_probe"

const SELECTOR_SIDE: int = 10
const PIXELS_PER_TILE: int = 8
const MASK_SIDE: int = SELECTOR_SIDE * PIXELS_PER_TILE
const TILE_SIZE_PX: int = 64
const MASK_STEP_PX: float = float(TILE_SIZE_PX) / float(PIXELS_PER_TILE)
const VIEW_SIZE: Vector2i = Vector2i(720, 720)
const CONTENT_OFFSET: Vector2 = Vector2(40.0, 54.0)
const ROCK_LAST_TILE_Y: int = 6
const MOUTH_TILE_Y: int = ROCK_LAST_TILE_Y
const CORRIDOR_FIRST_TILE_Y: int = 2
const GAP_PX: int = 18

const SOUTH_BIT: int = 4
const CONTINUES_NEGATIVE_BIT: int = 16
const CONTINUES_POSITIVE_BIT: int = 32
const EXTERIOR_PROJECTION_BIT: int = 64
const BG_COLOR: Color = Color(0.055, 0.042, 0.030, 1.0)
const GRID_COLOR: Color = Color(0.90, 0.74, 0.45, 0.18)

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_modular_mouth_render_probe must run windowed (GPU shader capture required).")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_clear_previous_outputs()

	var resources: Dictionary = _load_resources()
	if _failed:
		_finish()
		return

	var scenarios: Array[Dictionary] = [
		_build_scenario("one_tile_mouth", [4]),
		_build_scenario("three_tile_mouth", [3, 4, 5]),
	]
	var viewports: Array[SubViewport] = []
	for scenario: Dictionary in scenarios:
		var viewport: SubViewport = _build_viewport(scenario, resources)
		root.add_child(viewport)
		viewports.append(viewport)

	for _frame: int in range(12):
		await process_frame
	await RenderingServer.frame_post_draw

	var rendered_images: Array[Image] = []
	for index: int in range(viewports.size()):
		var rendered: Image = _capture(viewports[index])
		_assert(rendered != null, "%s GPU capture must produce an image" % str(scenarios[index].get("name", "fixture")))
		if rendered == null:
			continue
		var scenario_name: String = str(scenarios[index].get("name", "fixture"))
		rendered.save_png("%s/%02d_%s.png" % [OUTPUT_DIR, index + 1, scenario_name])
		rendered_images.append(rendered)

	if rendered_images.size() == scenarios.size():
		_save_horizontal_sheet(rendered_images, "%s/render_contact_sheet.png" % OUTPUT_DIR)
	_save_cpu_aperture_sheet(scenarios)

	var report: Dictionary = {
		"probe": "mountain_modular_mouth_render_probe",
		"production_shader": "res://assets/shaders/mountain_top_mask_underlay.gdshader",
		"selector_side": SELECTOR_SIDE,
		"pixels_per_tile": PIXELS_PER_TILE,
		"mask_step_px": MASK_STEP_PX,
		"scenarios": [],
	}
	for scenario: Dictionary in scenarios:
		var metrics: Dictionary = _measure_aperture(scenario)
		(report["scenarios"] as Array).append(metrics)
		_assert_aperture_contract(scenario, metrics)
	_write_report(report)

	for viewport: SubViewport in viewports:
		viewport.queue_free()
	await process_frame
	print("MOUNTAIN_MODULAR_MOUTH_PROBE report=%s/report.json failed=%s" % [OUTPUT_DIR, str(_failed)])
	_finish()


func _load_resources() -> Dictionary:
	var resources: Dictionary = {
		"top": load(TOP_TEXTURE_PATH) as Texture2D,
		"face": load(FACE_TEXTURE_PATH) as Texture2D,
		"top_normal": load(TOP_NORMAL_PATH) as Texture2D,
		"face_normal": load(FACE_NORMAL_PATH) as Texture2D,
		"ground": load(GROUND_TEXTURE_PATH) as Texture2D,
	}
	for key: String in resources.keys():
		_assert(resources[key] != null, "required texture must load: %s" % key)
	return resources


func _build_scenario(scenario_name: String, mouth_xs: Array[int]) -> Dictionary:
	var closed: PackedByteArray = _build_closed_mask()
	var remaining: PackedByteArray = closed.duplicate()
	var selector := PackedByteArray()
	var reveal_selector := PackedByteArray()
	var dug := PackedByteArray()
	selector.resize(SELECTOR_SIDE * SELECTOR_SIDE)
	reveal_selector.resize(SELECTOR_SIDE * SELECTOR_SIDE)
	dug.resize(SELECTOR_SIDE * SELECTOR_SIDE)

	for mouth_index: int in range(mouth_xs.size()):
		var tile_x: int = mouth_xs[mouth_index]
		for tile_y: int in range(CORRIDOR_FIRST_TILE_Y, MOUTH_TILE_Y + 1):
			dug[tile_y * SELECTOR_SIDE + tile_x] = 255
			_clear_mask_tile(remaining, tile_x, tile_y)
		var code: int = SOUTH_BIT
		if mouth_index > 0:
			code |= CONTINUES_NEGATIVE_BIT
		if mouth_index + 1 < mouth_xs.size():
			code |= CONTINUES_POSITIVE_BIT
		selector[MOUTH_TILE_Y * SELECTOR_SIDE + tile_x] = code
		reveal_selector[MOUTH_TILE_Y * SELECTOR_SIDE + tile_x] = code
		selector[(MOUTH_TILE_Y + 1) * SELECTOR_SIDE + tile_x] = code | EXTERIOR_PROJECTION_BIT
		_clear_projected_mouth_tile(
			remaining,
			tile_x,
			MOUTH_TILE_Y + 1,
			(code & CONTINUES_NEGATIVE_BIT) != 0,
			(code & CONTINUES_POSITIVE_BIT) != 0,
		)

	return {
		"name": scenario_name,
		"mouth_xs": mouth_xs,
		"closed": closed,
		"remaining": remaining,
		"selector": selector,
		"reveal_selector": reveal_selector,
		"dug": dug,
	}


func _build_closed_mask() -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(MASK_SIDE * MASK_SIDE)
	var base_boundary_y: float = float((ROCK_LAST_TILE_Y + 1) * PIXELS_PER_TILE)
	for py: int in range(MASK_SIDE):
		for px: int in range(MASK_SIDE):
			# A tiny deterministic crag wobble keeps the fixture visually close to
			# the native C mask without obscuring the modular aperture contract.
			var boundary_y: float = base_boundary_y \
					+ sin(float(px) * 0.21) * 0.75 \
					+ sin(float(px) * 0.067 + 1.7) * 0.55
			var signed_distance: float = boundary_y - (float(py) + 0.5)
			var coverage: float = _smoothstep(-1.35, 1.35, signed_distance)
			result[py * MASK_SIDE + px] = clampi(roundi(coverage * 255.0), 0, 255)
	return result


func _clear_mask_tile(mask: PackedByteArray, tile_x: int, tile_y: int) -> void:
	var start_x: int = tile_x * PIXELS_PER_TILE
	var start_y: int = tile_y * PIXELS_PER_TILE
	for py: int in range(start_y, start_y + PIXELS_PER_TILE):
		for px: int in range(start_x, start_x + PIXELS_PER_TILE):
			mask[py * MASK_SIDE + px] = 0


func _clear_projected_mouth_tile(
		mask: PackedByteArray,
		tile_x: int,
		tile_y: int,
		negative_continues: bool,
		positive_continues: bool,
) -> void:
	var start_x: int = tile_x * PIXELS_PER_TILE
	var start_y: int = tile_y * PIXELS_PER_TILE
	var local_min: float = 0.0 if negative_continues else float(PIXELS_PER_TILE) * 0.125
	var local_max: float = (
		float(PIXELS_PER_TILE) if positive_continues else float(PIXELS_PER_TILE) * 0.875
	)
	for py: int in range(start_y, start_y + PIXELS_PER_TILE):
		for local_x: int in range(PIXELS_PER_TILE):
			var sample_x: float = float(local_x) + 0.5
			if sample_x < local_min or sample_x > local_max:
				continue
			mask[py * MASK_SIDE + start_x + local_x] = 0


func _build_viewport(scenario: Dictionary, resources: Dictionary) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(_make_background(resources.get("ground") as Texture2D))

	var title := Label.new()
	title.text = "1 TILE / FLAT SHOULDERS" if (scenario.get("mouth_xs", []) as Array).size() == 1 \
			else "3 TILES / CONTINUOUS MODULAR OPENING"
	title.position = Vector2(24.0, 14.0)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.89, 0.68, 1.0))
	viewport.add_child(title)

	var closed_texture: ImageTexture = _make_l8_texture(scenario.get("closed", PackedByteArray()) as PackedByteArray, MASK_SIDE)
	var remaining_texture: ImageTexture = _make_l8_texture(scenario.get("remaining", PackedByteArray()) as PackedByteArray, MASK_SIDE)
	var selector_texture: ImageTexture = _make_l8_texture(scenario.get("selector", PackedByteArray()) as PackedByteArray, SELECTOR_SIDE)
	var reveal_selector_texture: ImageTexture = _make_l8_texture(scenario.get("reveal_selector", PackedByteArray()) as PackedByteArray, SELECTOR_SIDE)
	var dug_texture: ImageTexture = _make_l8_texture(scenario.get("dug", PackedByteArray()) as PackedByteArray, SELECTOR_SIDE)

	# BASE: real excavated visual mass. ROOF: immutable C composed through the
	# directional selector. This is the same two-pass relationship as ChunkView.
	var base: Sprite2D = _make_mountain_sprite(
		remaining_texture,
		remaining_texture,
		remaining_texture,
		reveal_selector_texture,
		selector_texture,
		dug_texture,
		resources,
		false,
	)
	base.position = CONTENT_OFFSET
	viewport.add_child(base)
	var roof: Sprite2D = _make_mountain_sprite(
		closed_texture,
		closed_texture,
		remaining_texture,
		reveal_selector_texture,
		selector_texture,
		dug_texture,
		resources,
		true,
	)
	roof.position = CONTENT_OFFSET
	viewport.add_child(roof)

	# Fine guides make an accidental inner post visible without dominating the
	# real material render. They sit behind the mountain and show only in holes.
	var guide := Node2D.new()
	guide.z_index = -1
	for tile_index: int in range(1, SELECTOR_SIDE):
		var x: float = CONTENT_OFFSET.x + float(tile_index * TILE_SIZE_PX)
		var vertical := Line2D.new()
		vertical.default_color = GRID_COLOR
		vertical.width = 1.0
		vertical.add_point(Vector2(x, CONTENT_OFFSET.y))
		vertical.add_point(Vector2(x, CONTENT_OFFSET.y + float(MASK_SIDE) * MASK_STEP_PX))
		guide.add_child(vertical)
	viewport.add_child(guide)
	viewport.move_child(guide, 2)
	return viewport


func _make_background(ground_texture: Texture2D) -> TextureRect:
	var background := TextureRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(VIEW_SIZE)
	background.texture = ground_texture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	background.modulate = Color(0.62, 0.55, 0.48, 1.0)
	return background


func _make_mountain_sprite(
	draw_texture: ImageTexture,
	closed_texture: ImageTexture,
	remaining_texture: ImageTexture,
	reveal_selector_texture: ImageTexture,
	physical_selector_texture: ImageTexture,
	dug_texture: ImageTexture,
	resources: Dictionary,
	is_roof: bool,
) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = draw_texture
	sprite.scale = Vector2.ONE * MASK_STEP_PX
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	material.shader = MOUNTAIN_SHADER
	var top: Texture2D = resources.get("top") as Texture2D
	var face: Texture2D = resources.get("face") as Texture2D
	material.set_shader_parameter("top_texture", top)
	material.set_shader_parameter("face_texture", face)
	material.set_shader_parameter("top_normal_texture", resources.get("top_normal") as Texture2D)
	material.set_shader_parameter("face_normal_texture", resources.get("face_normal") as Texture2D)
	material.set_shader_parameter("top_texture_size", Vector2(top.get_size()))
	material.set_shader_parameter("face_texture_size", Vector2(face.get_size()))
	material.set_shader_parameter("closed_mask_texture", closed_texture)
	material.set_shader_parameter("remaining_mask_texture", remaining_texture)
	material.set_shader_parameter("active_floor_halo_texture", reveal_selector_texture)
	material.set_shader_parameter("active_floor_halo_soft_texture", reveal_selector_texture)
	material.set_shader_parameter("physical_mouth_halo_texture", physical_selector_texture)
	material.set_shader_parameter("physical_mouth_enabled", 1.0)
	material.set_shader_parameter("any_cutout_halo_texture", dug_texture)
	material.set_shader_parameter("roof_component_reveal_enabled", 1.0 if is_roof else 0.0)
	material.set_shader_parameter("roof_overlay_mode", 1.0 if is_roof else 0.0)
	material.set_shader_parameter("world_origin_px", Vector2.ZERO)
	material.set_shader_parameter("sample_step_px", MASK_STEP_PX)
	material.set_shader_parameter("top_texture_scale", 0.70)
	material.set_shader_parameter("face_texture_scale", 1.15)
	material.set_shader_parameter("texture_zoom", 0.70)
	material.set_shader_parameter("facade_height_px", 72.0)
	material.set_shader_parameter("overhang_px", 0.0)
	material.set_shader_parameter("base_outline_strength", 0.0)
	material.set_shader_parameter("mask_warp_px", 0.0)
	material.set_shader_parameter("normal_strength", 0.48)
	material.set_shader_parameter("material_normal_mix", 1.0)
	material.set_shader_parameter("material_normal_strength", 1.45)
	material.set_shader_parameter("light_ambient", 0.58)
	material.set_shader_parameter("light_diffuse", 0.44)
	material.set_shader_parameter("wall_shade_top", 1.02)
	material.set_shader_parameter("wall_shade_bottom", 0.52)
	material.set_shader_parameter("wall_shade_tint", Color(0.93, 0.96, 1.06, 1.0))
	material.set_shader_parameter("wall_desaturate", 0.22)
	material.set_shader_parameter("wall_streak_strength", 0.30)
	material.set_shader_parameter("wall_crack_strength", 0.36)
	material.set_shader_parameter("wall_texture_v_stretch", 2.4)
	material.set_shader_parameter("crest_light_strength", 0.6)
	material.set_shader_parameter("crest_height_frac", 0.16)
	material.set_shader_parameter("projected_shadow_opacity", 0.0)
	material.set_shader_parameter("projected_shadow_draw_enabled", 0.0)
	material.set_shader_parameter("chunk_uv_min", Vector2.ZERO)
	material.set_shader_parameter("chunk_uv_max", Vector2.ONE)
	material.set_shader_parameter("shadow_uv_min", Vector2.ZERO)
	material.set_shader_parameter("shadow_uv_max", Vector2.ONE)
	material.set_shader_parameter("shadow_draw_uv_min", Vector2.ZERO)
	material.set_shader_parameter("shadow_draw_uv_max", Vector2.ONE)
	sprite.material = material
	return sprite


func _make_l8_texture(bytes: PackedByteArray, side: int) -> ImageTexture:
	_assert(bytes.size() == side * side, "L8 texture must be square %dx%d" % [side, side])
	var image: Image = Image.create_from_data(side, side, false, Image.FORMAT_L8, bytes)
	return ImageTexture.create_from_image(image)


func _measure_aperture(scenario: Dictionary) -> Dictionary:
	var mouth_xs: Array = scenario.get("mouth_xs", []) as Array
	var shallow_segments: int = _count_reveal_segments(scenario, 0.14)
	var seam_min_reveal: float = 1.0
	for mouth_index: int in range(1, mouth_xs.size()):
		var seam_x: float = float(int(mouth_xs[mouth_index]))
		seam_min_reveal = minf(seam_min_reveal, _sample_south_aperture(scenario, seam_x - 0.01, 0.20))
		seam_min_reveal = minf(seam_min_reveal, _sample_south_aperture(scenario, seam_x + 0.01, 0.20))
	var first_x: float = float(int(mouth_xs.front()))
	var last_x: float = float(int(mouth_xs.back()))
	return {
		"name": str(scenario.get("name", "fixture")),
		"mouth_tile_count": mouth_xs.size(),
		"selector_codes": _mouth_selector_codes(scenario),
		"shallow_connected_segments": shallow_segments,
		"internal_seam_min_reveal": seam_min_reveal,
		"center_reveal_at_0_20": _sample_south_aperture(scenario, (first_x + last_x + 1.0) * 0.5, 0.20),
		"deep_reveal_at_0_34": _sample_south_aperture(scenario, (first_x + last_x + 1.0) * 0.5, 0.34),
		"negative_outer_shoulder_at_0_18": _sample_south_aperture(scenario, first_x + 0.01, 0.18),
		"positive_outer_shoulder_at_0_18": _sample_south_aperture(scenario, last_x + 0.99, 0.18),
	}


func _assert_aperture_contract(scenario: Dictionary, metrics: Dictionary) -> void:
	var scenario_name: String = str(scenario.get("name", "fixture"))
	_assert(int(metrics.get("shallow_connected_segments", 0)) == 1, "%s aperture must be one connected run" % scenario_name)
	_assert(float(metrics.get("center_reveal_at_0_20", 0.0)) > 0.95, "%s center must stay open at authored depth" % scenario_name)
	_assert(float(metrics.get("deep_reveal_at_0_34", 1.0)) < 0.05, "%s aperture must not reveal deep roof" % scenario_name)
	_assert(float(metrics.get("negative_outer_shoulder_at_0_18", 1.0)) < 0.05, "%s negative outer shoulder must remain" % scenario_name)
	_assert(float(metrics.get("positive_outer_shoulder_at_0_18", 1.0)) < 0.05, "%s positive outer shoulder must remain" % scenario_name)
	if (scenario.get("mouth_xs", []) as Array).size() > 1:
		_assert(float(metrics.get("internal_seam_min_reveal", 0.0)) > 0.95, "%s continuation bits must not create inner posts" % scenario_name)


func _mouth_selector_codes(scenario: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var selector: PackedByteArray = scenario.get("selector", PackedByteArray()) as PackedByteArray
	for x_variant: Variant in scenario.get("mouth_xs", []) as Array:
		var x: int = int(x_variant)
		result.append(int(selector[MOUTH_TILE_Y * SELECTOR_SIDE + x]))
	return result


func _count_reveal_segments(scenario: Dictionary, inward: float) -> int:
	var segments: int = 0
	var was_open: bool = false
	for sample_index: int in range(SELECTOR_SIDE * 64):
		var tile_x: float = (float(sample_index) + 0.5) / 64.0
		var is_open: bool = _sample_south_aperture(scenario, tile_x, inward) >= 0.5
		if is_open and not was_open:
			segments += 1
		was_open = is_open
	return segments


func _sample_south_aperture(scenario: Dictionary, tile_x: float, inward: float) -> float:
	if tile_x < 0.0 or tile_x >= float(SELECTOR_SIDE):
		return 0.0
	var cell_x: int = floori(tile_x)
	var selector: PackedByteArray = scenario.get("selector", PackedByteArray()) as PackedByteArray
	var code: int = int(selector[MOUTH_TILE_Y * SELECTOR_SIDE + cell_x])
	if (code & SOUTH_BIT) == 0:
		return 0.0
	var lateral: float = tile_x - float(cell_x)
	var half_width: float = 0.375
	var left_edge: float = 0.5 - half_width
	var right_edge: float = 0.5 + half_width
	var edge_soft: float = 0.018
	var negative_open: bool = (code & CONTINUES_NEGATIVE_BIT) != 0
	var positive_open: bool = (code & CONTINUES_POSITIVE_BIT) != 0
	var chamfer: float = 0.0625
	var left_loss: float = 0.0 if negative_open \
			else clampf(left_edge + chamfer - lateral, 0.0, chamfer)
	var right_loss: float = 0.0 if positive_open \
			else clampf(lateral - (right_edge - chamfer), 0.0, chamfer)
	var header_sd: float = inward - (0.27 - maxf(left_loss, right_loss))
	var left_sd: float = -2.0 if negative_open else left_edge - lateral
	var right_sd: float = -2.0 if positive_open else lateral - right_edge
	var mouth_sd: float = maxf(header_sd, maxf(left_sd, right_sd))
	return 1.0 - _smoothstep(-edge_soft, edge_soft, mouth_sd)


func _save_cpu_aperture_sheet(scenarios: Array[Dictionary]) -> void:
	var cell_scale: int = 6
	var panel_side: int = MASK_SIDE * cell_scale
	var sheet: Image = Image.create(panel_side * scenarios.size() + GAP_PX, panel_side, false, Image.FORMAT_RGBA8)
	sheet.fill(BG_COLOR)
	for scenario_index: int in range(scenarios.size()):
		var scenario: Dictionary = scenarios[scenario_index]
		var panel: Image = Image.create(MASK_SIDE, MASK_SIDE, false, Image.FORMAT_RGBA8)
		panel.fill(Color(0.10, 0.07, 0.045, 1.0))
		var closed: PackedByteArray = scenario.get("closed", PackedByteArray()) as PackedByteArray
		var remaining: PackedByteArray = scenario.get("remaining", PackedByteArray()) as PackedByteArray
		for py: int in range(MASK_SIDE):
			for px: int in range(MASK_SIDE):
				var closed_value: float = float(closed[py * MASK_SIDE + px]) / 255.0
				var remaining_value: float = float(remaining[py * MASK_SIDE + px]) / 255.0
				var tile_y: int = py / PIXELS_PER_TILE
				var reveal: float = 0.0
				if tile_y == MOUTH_TILE_Y:
					var cell_y: float = (float(py % PIXELS_PER_TILE) + 0.5) / float(PIXELS_PER_TILE)
					reveal = _sample_south_aperture(
						scenario,
						(float(px) + 0.5) / float(PIXELS_PER_TILE),
						1.0 - cell_y,
					)
				var effective: float = lerpf(closed_value, remaining_value, reveal)
				var cave_color := Color(0.76, 0.31, 0.08, 1.0)
				var rock_color := Color(0.40, 0.31, 0.22, 1.0)
				panel.set_pixel(px, py, cave_color.lerp(rock_color, effective))
		panel.resize(panel_side, panel_side, Image.INTERPOLATE_NEAREST)
		var dest_x: int = scenario_index * (panel_side + GAP_PX)
		sheet.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(dest_x, 0))
	sheet.save_png("%s/cpu_aperture_sheet.png" % OUTPUT_DIR)


func _capture(viewport: SubViewport) -> Image:
	var texture: Texture2D = viewport.get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _save_horizontal_sheet(images: Array[Image], output_path: String) -> void:
	var width: int = GAP_PX * maxi(0, images.size() - 1)
	var height: int = 0
	for image: Image in images:
		width += image.get_width()
		height = maxi(height, image.get_height())
	var sheet: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(BG_COLOR)
	var cursor_x: int = 0
	for image: Image in images:
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(cursor_x, 0))
		cursor_x += image.get_width() + GAP_PX
	sheet.save_png(output_path)


func _write_report(report: Dictionary) -> void:
	var path: String = "%s/report.json" % OUTPUT_DIR
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "could not write report.json")
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()


func _clear_previous_outputs() -> void:
	var directory: DirAccess = DirAccess.open(OUTPUT_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.ends_with(".png") or file_name == "report.json":
			directory.remove(file_name)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t: float = clampf((value - edge0) / maxf(edge1 - edge0, 0.000001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	quit(1 if _failed else 0)
