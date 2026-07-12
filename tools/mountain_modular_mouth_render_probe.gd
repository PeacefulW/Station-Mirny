extends SceneTree

## TOOLS ONLY. Exercises the production mountain shader against deterministic
## full-resolution CLOSED / V / physical-mouth-aperture masks. The component
## selector is deliberately zero outside: direction metadata may transfer local
## facade ownership, but blend must never punch a hole through ROOF. GPU evidence
## lives in its own facade-only artifact folder.

const MOUNTAIN_SHADER: Shader = preload("res://assets/shaders/mountain_top_mask_underlay.gdshader")
const TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png"
const TOP_NORMAL_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_normal.png"
const FACE_NORMAL_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_normal.png"
const GROUND_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/ground/orange_biofield_albedo.png"
const OUTPUT_DIR: String = "res://artifacts/mountain_mouth_facade_probe"
const CAPTURE_PREFIX: String = "facade_probe_"

const SELECTOR_SIDE: int = 13
const NATIVE_CHUNK_SIZE: int = 9
const HALO_RADIUS_TILES: int = 2
const PIXELS_PER_TILE: int = 8
const MASK_SIDE: int = SELECTOR_SIDE * PIXELS_PER_TILE
const TILE_SIZE_PX: int = 64
const MASK_STEP_PX: float = 8.0
const VIEW_SIZE: Vector2i = Vector2i(928, 928)
const CONTENT_OFFSET: Vector2 = Vector2(48.0, 56.0)
const CORE_MIN_TILE: int = HALO_RADIUS_TILES
const CORE_MAX_TILE: int = HALO_RADIUS_TILES + NATIVE_CHUNK_SIZE - 1
const CENTER_LATERAL_TILE: int = SELECTOR_SIDE / 2
const NORTH_BIT: int = 1
const EAST_BIT: int = 2
const SOUTH_BIT: int = 4
const WEST_BIT: int = 8
const CONTINUES_NEGATIVE_BIT: int = 16
const CONTINUES_POSITIVE_BIT: int = 32
const EXTERIOR_PROJECTION_BIT: int = 64
const BG_COLOR: Color = Color(0.055, 0.042, 0.030, 1.0)

var _failed: bool = false
var _direction_texture_binding_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_modular_mouth_render_probe must run windowed (GPU capture required).")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_clear_previous_outputs()
	var resources: Dictionary = _load_resources()
	if _failed:
		_finish()
		return
	var core := WorldCore.new()
	_assert(
		core.has_method("build_mountain_halo_mask"),
		"WorldCore.build_mountain_halo_mask is required; rebuild the GDExtension.",
	)
	if not core.has_method("build_mountain_halo_mask"):
		_finish()
		return

	var scenarios: Array[Dictionary] = [
		_build_scenario(core, "north_one_tile", Vector2i.UP, [CENTER_LATERAL_TILE], 10),
		_build_scenario(core, "east_one_tile", Vector2i.RIGHT, [CENTER_LATERAL_TILE], 10),
		_build_scenario(core, "south_one_tile", Vector2i.DOWN, [CENTER_LATERAL_TILE], 10),
		_build_scenario(core, "south_three_tile", Vector2i.DOWN, [5, 6, 7], 10),
		_build_scenario(core, "west_one_tile", Vector2i.LEFT, [CENTER_LATERAL_TILE], 10),
	]
	for scenario: Dictionary in scenarios:
		_assert_scenario_contract(scenario)
		_assert_depth_stability(
			core,
			str(scenario.get("name", "fixture")),
			scenario.get("direction", Vector2i.ZERO) as Vector2i,
			scenario.get("mouth_laterals", []) as Array,
		)

	var captures: Array[Dictionary] = []
	var viewports: Array[SubViewport] = []
	var capture_modes: Array[Dictionary] = [
		{
			"suffix": "solid_reference",
			"inside": false,
			"blend": 0.0,
			"solid_reference": true,
			"save": false,
		},
		{"suffix": "outside_closed_blend0", "inside": false, "blend": 0.0, "save": true},
		{"suffix": "outside_closed_blend1", "inside": false, "blend": 1.0, "save": true},
		{"suffix": "inside_open", "inside": true, "blend": 1.0, "save": true},
	]
	for scenario: Dictionary in scenarios:
		for mode: Dictionary in capture_modes:
			var viewport: SubViewport = _build_viewport(scenario, mode, resources)
			root.add_child(viewport)
			viewports.append(viewport)
			captures.append({
				"scenario": str(scenario.get("name", "fixture")),
				"suffix": str(mode.get("suffix", "capture")),
				"save": bool(mode.get("save", false)),
				"viewport": viewport,
			})
	_assert(
		_direction_texture_binding_count == scenarios.size() * capture_modes.size() * 2,
		"every BASE/ROOF material must bind and enable the physical direction texture",
	)

	for _frame: int in range(12):
		await process_frame
	await RenderingServer.frame_post_draw

	var images: Array[Image] = []
	var image_by_key: Dictionary = {}
	var saved_index: int = 0
	for index: int in range(captures.size()):
		var capture: Dictionary = captures[index]
		var image: Image = _capture(capture.get("viewport") as SubViewport)
		_assert(image != null, "%s GPU capture must produce an image" % str(capture))
		if image == null:
			continue
		var key: String = "%s_%s" % [capture.get("scenario", "fixture"), capture.get("suffix", "capture")]
		image_by_key[key] = image
		if bool(capture.get("save", false)):
			saved_index += 1
			image.save_png(
				"%s/%s%02d_%s.png" % [OUTPUT_DIR, CAPTURE_PREFIX, saved_index, key],
			)
			images.append(image)

	var report_scenarios: Array[Dictionary] = []
	for scenario: Dictionary in scenarios:
		var name: String = str(scenario.get("name", "fixture"))
		var blend0: Image = image_by_key.get("%s_outside_closed_blend0" % name) as Image
		var blend1: Image = image_by_key.get("%s_outside_closed_blend1" % name) as Image
		var solid_reference: Image = image_by_key.get("%s_solid_reference" % name) as Image
		var inside_open: Image = image_by_key.get("%s_inside_open" % name) as Image
		var outside_diff: int = _count_pixel_differences(blend0, blend1)
		var opening_diff: int = _count_pixel_differences_in_rect(
			solid_reference,
			blend0,
			_content_rect(),
		)
		var inside_diff: int = _count_pixel_differences_in_rect(
			blend0,
			inside_open,
			_content_rect(),
		)
		_assert(
			outside_diff == 0,
			"%s outside CLOSED render must be identical at reveal blend 0 and 1" % name,
		)
		_assert(opening_diff > 64, "%s outside facade opening must be visible on GPU" % name)
		_assert(inside_diff > 256, "%s inside selector must visibly open the roof on GPU" % name)
		report_scenarios.append({
			"name": name,
			"direction": _direction_name(scenario.get("direction", Vector2i.ZERO) as Vector2i),
			"direction_bit": _direction_bit(scenario.get("direction", Vector2i.ZERO) as Vector2i),
			"mouth_width_tiles": (scenario.get("mouth_laterals", []) as Array).size(),
			"outside_selector_nonzero": _count_nonzero(
				scenario.get("outside_selector", PackedByteArray()) as PackedByteArray,
			),
			"physical_metadata_nonzero": _count_nonzero(
				scenario.get("physical_selector", PackedByteArray()) as PackedByteArray,
			),
			"aperture_nonzero_pixels": _count_nonzero(
				scenario.get("aperture", PackedByteArray()) as PackedByteArray,
			),
			"outside_blend_pixel_differences": outside_diff,
			"outside_opening_pixel_differences_from_solid": opening_diff,
			"inside_open_pixel_differences_from_outside": inside_diff,
			"closed_mask_hash": hash(scenario.get("closed", PackedByteArray())),
			"aperture_hash": hash(scenario.get("aperture", PackedByteArray())),
		})

	if images.size() == scenarios.size() * 3:
		_save_contact_sheet(images, "%s/render_contact_sheet.png" % OUTPUT_DIR)
	_write_report({
		"probe": "mountain_modular_mouth_render_probe",
		"production_shader": "res://assets/shaders/mountain_top_mask_underlay.gdshader",
		"renderer": "D3D12",
		"contract": "CLOSED roof + component alpha blend; aperture on BASE only; N/E/S/W facade ownership from direction metadata",
		"direction_texture_material_bindings": _direction_texture_binding_count,
		"scenarios": report_scenarios,
	})

	for viewport: SubViewport in viewports:
		viewport.queue_free()
	await process_frame
	print("MOUNTAIN_MOUTH_FACADE_PROBE report=%s/report.json failed=%s" % [OUTPUT_DIR, str(_failed)])
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


func _build_scenario(
		core: Object,
		name: String,
		direction: Vector2i,
		mouth_laterals: Array,
		tunnel_depth: int,
) -> Dictionary:
	var closed_halo: PackedByteArray = _build_directional_closed_halo(direction)
	var native_dug := PackedByteArray()
	var dug := PackedByteArray()
	var inside_selector := PackedByteArray()
	var outside_selector := PackedByteArray()
	var physical_selector := PackedByteArray()
	native_dug.resize(SELECTOR_SIDE * SELECTOR_SIDE)
	dug.resize(SELECTOR_SIDE * SELECTOR_SIDE)
	inside_selector.resize(SELECTOR_SIDE * SELECTOR_SIDE)
	outside_selector.resize(SELECTOR_SIDE * SELECTOR_SIDE)
	physical_selector.resize(SELECTOR_SIDE * SELECTOR_SIDE)

	var mouth_tiles: Array[Vector2i] = []
	var direction_bit: int = _direction_bit(direction)
	for mouth_index: int in range(mouth_laterals.size()):
		var mouth_tile: Vector2i = _mouth_tile(direction, int(mouth_laterals[mouth_index]))
		mouth_tiles.append(mouth_tile)
		var code: int = direction_bit
		if mouth_index > 0:
			code |= CONTINUES_NEGATIVE_BIT
		if mouth_index + 1 < mouth_laterals.size():
			code |= CONTINUES_POSITIVE_BIT
		physical_selector[_selector_index(mouth_tile)] = code
		physical_selector[_selector_index(mouth_tile + direction)] = (
			code | EXTERIOR_PROJECTION_BIT
		)
		for depth: int in range(tunnel_depth):
			var dug_tile: Vector2i = mouth_tile - direction * depth
			if not _selector_contains(dug_tile):
				break
			var dug_index: int = _selector_index(dug_tile)
			native_dug[dug_index] = 1
			dug[dug_index] = 255
			inside_selector[dug_index] = 255

	var mask_origin := Vector2.ONE * float(-HALO_RADIUS_TILES * TILE_SIZE_PX)
	var result: Dictionary = core.call(
		"build_mountain_halo_mask",
		closed_halo,
		NATIVE_CHUNK_SIZE,
		TILE_SIZE_PX,
		PIXELS_PER_TILE,
		mask_origin.x,
		mask_origin.y,
		native_dug,
	) as Dictionary
	var closed: PackedByteArray = result.get("closed_roof_mask", PackedByteArray()) as PackedByteArray
	var remaining: PackedByteArray = result.get(
		"visual_remaining_mass_mask",
		PackedByteArray(),
	) as PackedByteArray
	var aperture: PackedByteArray = result.get(
		"physical_mouth_aperture_mask",
		PackedByteArray(),
	) as PackedByteArray
	return {
		"name": name,
		"direction": direction,
		"mouth_laterals": mouth_laterals.duplicate(),
		"mouth_tiles": mouth_tiles,
		"tunnel_depth": tunnel_depth,
		"closed": closed,
		"remaining": remaining,
		"aperture": aperture,
		"dug": dug,
		"inside_selector": inside_selector,
		"outside_selector": outside_selector,
		"physical_selector": physical_selector,
	}


func _build_directional_closed_halo(direction: Vector2i) -> PackedByteArray:
	var closed := PackedByteArray()
	closed.resize(SELECTOR_SIDE * SELECTOR_SIDE)
	for tile_y: int in range(SELECTOR_SIDE):
		for tile_x: int in range(SELECTOR_SIDE):
			var solid: bool = (
				(direction == Vector2i.UP and tile_y >= CORE_MIN_TILE)
				or (direction == Vector2i.RIGHT and tile_x <= CORE_MAX_TILE)
				or (direction == Vector2i.DOWN and tile_y <= CORE_MAX_TILE)
				or (direction == Vector2i.LEFT and tile_x >= CORE_MIN_TILE)
			)
			closed[tile_y * SELECTOR_SIDE + tile_x] = 1 if solid else 0
	return closed


func _mouth_tile(direction: Vector2i, lateral: int) -> Vector2i:
	if direction == Vector2i.UP:
		return Vector2i(lateral, CORE_MIN_TILE)
	if direction == Vector2i.RIGHT:
		return Vector2i(CORE_MAX_TILE, lateral)
	if direction == Vector2i.DOWN:
		return Vector2i(lateral, CORE_MAX_TILE)
	return Vector2i(CORE_MIN_TILE, lateral)


func _direction_bit(direction: Vector2i) -> int:
	if direction == Vector2i.UP:
		return NORTH_BIT
	if direction == Vector2i.RIGHT:
		return EAST_BIT
	if direction == Vector2i.DOWN:
		return SOUTH_BIT
	if direction == Vector2i.LEFT:
		return WEST_BIT
	return 0


func _direction_name(direction: Vector2i) -> String:
	if direction == Vector2i.UP:
		return "NORTH"
	if direction == Vector2i.RIGHT:
		return "EAST"
	if direction == Vector2i.DOWN:
		return "SOUTH"
	if direction == Vector2i.LEFT:
		return "WEST"
	return "INVALID"


func _selector_contains(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < SELECTOR_SIDE and tile.y < SELECTOR_SIDE


func _selector_index(tile: Vector2i) -> int:
	return tile.y * SELECTOR_SIDE + tile.x


func _assert_scenario_contract(scenario: Dictionary) -> void:
	var name: String = str(scenario.get("name", "fixture"))
	var direction: Vector2i = scenario.get("direction", Vector2i.ZERO) as Vector2i
	var closed: PackedByteArray = scenario.get("closed", PackedByteArray()) as PackedByteArray
	var remaining: PackedByteArray = scenario.get("remaining", PackedByteArray()) as PackedByteArray
	var aperture: PackedByteArray = scenario.get("aperture", PackedByteArray()) as PackedByteArray
	var mouth_tiles: Array = scenario.get("mouth_tiles", []) as Array
	var physical_selector: PackedByteArray = scenario.get(
		"physical_selector",
		PackedByteArray(),
	) as PackedByteArray
	_assert(_direction_bit(direction) != 0, "%s cardinal direction" % name)
	_assert(closed.size() == MASK_SIDE * MASK_SIDE, "%s CLOSED raster shape" % name)
	_assert(remaining.size() == closed.size(), "%s V raster shape" % name)
	_assert(aperture.size() == closed.size(), "%s aperture raster shape" % name)
	_assert(_count_nonzero(aperture) > 0, "%s aperture must contain the facade cut" % name)
	_assert(physical_selector.size() == SELECTOR_SIDE * SELECTOR_SIDE, "%s direction shape" % name)
	_assert(
		_count_nonzero(scenario.get("outside_selector", PackedByteArray()) as PackedByteArray) == 0,
		"%s outside combined roof selector must be empty" % name,
	)
	for mouth_index: int in range(mouth_tiles.size()):
		var mouth_tile: Vector2i = mouth_tiles[mouth_index] as Vector2i
		var source_code: int = int(physical_selector[_selector_index(mouth_tile)])
		var projection_code: int = int(physical_selector[_selector_index(mouth_tile + direction)])
		_assert((source_code & _direction_bit(direction)) != 0, "%s source direction bit" % name)
		_assert(
			(projection_code & (_direction_bit(direction) | EXTERIOR_PROJECTION_BIT))
					== (_direction_bit(direction) | EXTERIOR_PROJECTION_BIT),
			"%s projected direction metadata" % name,
		)
	for py: int in range(MASK_SIDE):
		for px: int in range(MASK_SIDE):
			var index: int = py * MASK_SIDE + px
			var in_zone: bool = _is_physical_aperture_pixel(px, py, scenario)
			var expected: int = maxi(0, int(closed[index]) - int(remaining[index])) if in_zone else 0
			_assert(
				int(aperture[index]) == expected,
				"%s aperture must equal gated CLOSED-V at pixel (%d,%d)" % [name, px, py],
			)


func _is_physical_aperture_pixel(px: int, py: int, scenario: Dictionary) -> bool:
	var direction: Vector2i = scenario.get("direction", Vector2i.ZERO) as Vector2i
	var mouth_tiles: Array = scenario.get("mouth_tiles", []) as Array
	var pixel_tile := Vector2i(px / PIXELS_PER_TILE, py / PIXELS_PER_TILE)
	var local := Vector2i(px % PIXELS_PER_TILE, py % PIXELS_PER_TILE)
	for mouth_index: int in range(mouth_tiles.size()):
		var mouth_tile: Vector2i = mouth_tiles[mouth_index] as Vector2i
		var in_source: bool = pixel_tile == mouth_tile and _is_outward_half(local, direction)
		var in_projection: bool = pixel_tile == mouth_tile + direction
		if not in_source and not in_projection:
			continue
		var lateral: int = local.x if direction.x == 0 else local.y
		if mouth_index == 0 and lateral < PIXELS_PER_TILE / 8:
			return false
		if mouth_index + 1 == mouth_tiles.size() \
				and lateral >= PIXELS_PER_TILE - PIXELS_PER_TILE / 8:
			return false
		return true
	return false


func _is_outward_half(local: Vector2i, direction: Vector2i) -> bool:
	if direction == Vector2i.UP:
		return local.y < PIXELS_PER_TILE / 2
	if direction == Vector2i.RIGHT:
		return local.x >= PIXELS_PER_TILE / 2
	if direction == Vector2i.DOWN:
		return local.y >= PIXELS_PER_TILE / 2
	return local.x < PIXELS_PER_TILE / 2


func _assert_depth_stability(
		core: Object,
		name: String,
		direction: Vector2i,
		mouth_laterals: Array,
) -> void:
	var depth_1: PackedByteArray = _build_scenario(
		core,
		name,
		direction,
		mouth_laterals,
		1,
	).get("aperture", PackedByteArray()) as PackedByteArray
	var depth_3: PackedByteArray = _build_scenario(
		core,
		name,
		direction,
		mouth_laterals,
		3,
	).get("aperture", PackedByteArray()) as PackedByteArray
	var depth_10: PackedByteArray = _build_scenario(
		core,
		name,
		direction,
		mouth_laterals,
		10,
	).get("aperture", PackedByteArray()) as PackedByteArray
	_assert(depth_1 == depth_3, "%s aperture must not move after digging three tiles" % name)
	_assert(depth_1 == depth_10, "%s aperture must not move after digging ten tiles" % name)


func _build_viewport(
		scenario: Dictionary,
		mode: Dictionary,
		resources: Dictionary,
) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(_make_background(resources.get("ground") as Texture2D))
	var inside: bool = bool(mode.get("inside", false))
	var solid_reference: bool = bool(mode.get("solid_reference", false))
	var direction: Vector2i = scenario.get("direction", Vector2i.ZERO) as Vector2i
	var title := Label.new()
	title.text = "%s %s / %s" % [
		_direction_name(direction),
		"1 TILE" if (scenario.get("mouth_laterals", []) as Array).size() == 1 else "3 TILES",
		"SOLID REFERENCE" if solid_reference else (
			"INSIDE OPEN" if inside else "OUTSIDE CLOSED"
		),
	]
	title.position = Vector2(24.0, 14.0)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.89, 0.68, 1.0))
	viewport.add_child(title)

	var closed_texture: ImageTexture = _make_l8_texture(
		scenario.get("closed", PackedByteArray()) as PackedByteArray,
		MASK_SIDE,
	)
	var remaining_texture: ImageTexture = _make_l8_texture(
		scenario.get("remaining", PackedByteArray()) as PackedByteArray,
		MASK_SIDE,
	)
	var aperture_texture: ImageTexture = _make_l8_texture(
		scenario.get("aperture", PackedByteArray()) as PackedByteArray,
		MASK_SIDE,
	)
	var selector_bytes: PackedByteArray = (
		scenario.get("inside_selector", PackedByteArray())
		if inside
		else scenario.get("outside_selector", PackedByteArray())
	) as PackedByteArray
	var selector_texture: ImageTexture = _make_l8_texture(selector_bytes, SELECTOR_SIDE)
	var direction_texture: ImageTexture = _make_l8_texture(
		scenario.get("physical_selector", PackedByteArray()) as PackedByteArray,
		SELECTOR_SIDE,
	)
	var dug_texture: ImageTexture = _make_l8_texture(
		scenario.get("dug", PackedByteArray()) as PackedByteArray,
		SELECTOR_SIDE,
	)
	var base_draw_texture: ImageTexture = closed_texture if solid_reference else remaining_texture

	var base: Sprite2D = _make_mountain_sprite(
		base_draw_texture,
		base_draw_texture,
		aperture_texture,
		selector_texture,
		direction_texture,
		dug_texture,
		resources,
		false,
		0.0,
	)
	base.position = CONTENT_OFFSET
	viewport.add_child(base)
	var roof: Sprite2D = _make_mountain_sprite(
		closed_texture,
		base_draw_texture,
		aperture_texture,
		selector_texture,
		direction_texture,
		dug_texture,
		resources,
		true,
		float(mode.get("blend", 0.0)),
	)
	roof.position = CONTENT_OFFSET
	viewport.add_child(roof)
	return viewport


func _make_background(ground_texture: Texture2D) -> TextureRect:
	var background := TextureRect.new()
	background.size = Vector2(VIEW_SIZE)
	background.texture = ground_texture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	background.modulate = Color(0.62, 0.55, 0.48, 1.0)
	return background


func _make_mountain_sprite(
		draw_texture: ImageTexture,
		base_visual_texture: ImageTexture,
		aperture_texture: ImageTexture,
		selector_texture: ImageTexture,
		direction_texture: ImageTexture,
		dug_texture: ImageTexture,
		resources: Dictionary,
		is_roof: bool,
		blend: float,
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
	material.set_shader_parameter("closed_mask_texture", draw_texture)
	material.set_shader_parameter("base_visual_mask_texture", base_visual_texture)
	material.set_shader_parameter("active_floor_halo_texture", selector_texture)
	material.set_shader_parameter("active_floor_halo_soft_texture", selector_texture)
	material.set_shader_parameter("any_cutout_halo_texture", dug_texture)
	material.set_shader_parameter("physical_mouth_aperture_texture", aperture_texture)
	material.set_shader_parameter("physical_mouth_aperture_enabled", 0.0 if is_roof else 1.0)
	material.set_shader_parameter("physical_mouth_direction_texture", direction_texture)
	material.set_shader_parameter("physical_mouth_direction_enabled", 1.0)
	material.set_shader_parameter("roof_component_reveal_enabled", 1.0 if is_roof else 0.0)
	material.set_shader_parameter("component_reveal_blend", blend if is_roof else 0.0)
	material.set_shader_parameter("roof_overlay_mode", 1.0 if is_roof else 0.0)
	material.set_shader_parameter("world_origin_px", Vector2.ZERO)
	material.set_shader_parameter("sample_step_px", MASK_STEP_PX)
	material.set_shader_parameter("top_texture_scale", 0.70)
	material.set_shader_parameter("face_texture_scale", 1.15)
	material.set_shader_parameter("texture_zoom", 0.70)
	material.set_shader_parameter("facade_height_px", 72.0)
	material.set_shader_parameter("overhang_px", 0.0)
	material.set_shader_parameter("base_outline_strength", 0.0)
	material.set_shader_parameter("mask_warp_px", 9.0)
	material.set_shader_parameter("projected_shadow_opacity", 0.0)
	material.set_shader_parameter("projected_shadow_draw_enabled", 0.0)
	material.set_shader_parameter("chunk_uv_min", Vector2.ZERO)
	material.set_shader_parameter("chunk_uv_max", Vector2.ONE)
	material.set_shader_parameter("shadow_uv_min", Vector2.ZERO)
	material.set_shader_parameter("shadow_uv_max", Vector2.ONE)
	material.set_shader_parameter("shadow_draw_uv_min", Vector2.ZERO)
	material.set_shader_parameter("shadow_draw_uv_max", Vector2.ONE)
	var direction_texture_bound: bool = (
		material.get_shader_parameter("physical_mouth_direction_texture") == direction_texture
	)
	var direction_enabled: bool = (
		float(material.get_shader_parameter("physical_mouth_direction_enabled")) > 0.5
	)
	_assert(direction_texture_bound, "physical direction texture must be bound on every material")
	_assert(direction_enabled, "physical direction metadata must be enabled on every material")
	if direction_texture_bound and direction_enabled:
		_direction_texture_binding_count += 1
	sprite.material = material
	return sprite


func _make_l8_texture(bytes: PackedByteArray, side: int) -> ImageTexture:
	_assert(bytes.size() == side * side, "L8 texture must be square %dx%d" % [side, side])
	var image: Image = Image.create_from_data(side, side, false, Image.FORMAT_L8, bytes)
	return ImageTexture.create_from_image(image)


func _capture(viewport: SubViewport) -> Image:
	if viewport == null or viewport.get_texture() == null:
		return null
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _count_pixel_differences(first: Image, second: Image) -> int:
	if first == null or second == null or first.get_size() != second.get_size():
		return -1
	var differences: int = 0
	for y: int in range(first.get_height()):
		for x: int in range(first.get_width()):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				differences += 1
	return differences


func _count_pixel_differences_in_rect(first: Image, second: Image, rect: Rect2i) -> int:
	if first == null or second == null or first.get_size() != second.get_size():
		return -1
	var bounds := Rect2i(Vector2i.ZERO, first.get_size())
	var clipped: Rect2i = rect.intersection(bounds)
	var differences: int = 0
	for y: int in range(clipped.position.y, clipped.end.y):
		for x: int in range(clipped.position.x, clipped.end.x):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				differences += 1
	return differences


func _content_rect() -> Rect2i:
	var side_px: int = roundi(float(MASK_SIDE) * MASK_STEP_PX)
	return Rect2i(
		Vector2i(roundi(CONTENT_OFFSET.x), roundi(CONTENT_OFFSET.y)),
		Vector2i(side_px, side_px),
	)


func _count_nonzero(bytes: PackedByteArray) -> int:
	var count: int = 0
	for value: int in bytes:
		if value != 0:
			count += 1
	return count


func _save_contact_sheet(images: Array[Image], output_path: String) -> void:
	var thumb_size := Vector2i(360, 360)
	var columns: int = 3
	var rows: int = ceili(float(images.size()) / float(columns))
	var sheet: Image = Image.create(
		thumb_size.x * columns,
		thumb_size.y * rows,
		false,
		Image.FORMAT_RGBA8,
	)
	sheet.fill(BG_COLOR)
	for index: int in range(images.size()):
		var thumb: Image = images[index].duplicate()
		thumb.resize(thumb_size.x, thumb_size.y, Image.INTERPOLATE_LANCZOS)
		var destination := Vector2i((index % columns) * thumb_size.x, (index / columns) * thumb_size.y)
		sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, thumb_size), destination)
	sheet.save_png(output_path)


func _write_report(report: Dictionary) -> void:
	var file: FileAccess = FileAccess.open("%s/report.json" % OUTPUT_DIR, FileAccess.WRITE)
	_assert(file != null, "could not write report.json")
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()


func _clear_previous_outputs() -> void:
	var directory: DirAccess = DirAccess.open(OUTPUT_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		var old_owned_capture: bool = file_name.begins_with("01_one_tile_") \
				or file_name.begins_with("02_one_tile_") \
				or file_name.begins_with("03_one_tile_") \
				or file_name.begins_with("04_three_tile_") \
				or file_name.begins_with("05_three_tile_") \
				or file_name.begins_with("06_three_tile_")
		var owned_capture: bool = file_name.begins_with(CAPTURE_PREFIX) \
				or old_owned_capture
		if owned_capture \
				or file_name == "render_contact_sheet.png" \
				or file_name == "report.json":
			directory.remove(file_name)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	quit(1 if _failed else 0)
