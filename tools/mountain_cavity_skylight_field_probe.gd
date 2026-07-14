extends SceneTree

# Windowed numeric/render proof for M8.2 light composition.
#
# Run:
#   Godot_v4.7-stable_win64_console.exe --path . \
#     -s tools/mountain_cavity_skylight_field_probe.gd
#
# Captures are written to artifacts/mountain_cavity_skylight_field_probe/.

const MountainCavitySkylightField = preload(
	"res://core/systems/world/mountain_cavity_skylight_field.gd"
)

const VIEW_SIZE := Vector2i(1280, 720)
const WINDOW_SIZE := Vector2i(1024, 576)
const DEEP_SAMPLE := Vector2i(620, 470)
const ENTRANCE_SOFT_SAMPLE := Vector2i(145, 504)
const ENTRANCE_MID_SAMPLE := Vector2i(145, 488)
const MOUTH_SAMPLE := Vector2i(145, 470)
const STATIONARY_SAMPLE := Vector2i(430, 470)
const EXTERIOR_SAMPLE := Vector2i(880, 200)
# Organic C-V reaches into this tile, while the tile-centre selector does not.
# A direct selector multiply leaves the exact bright square seen in the live
# screenshots; the guarded active fringe must keep it dark.
const ORGANIC_FRINGE_SAMPLE := Vector2i(775, 470)
# A separate excavated component must not inherit the displayed selector.
const FOREIGN_CAVITY_SAMPLE := Vector2i(980, 470)
const INTERNAL_FACADE_SAMPLE := Vector2i(430, 248)
const ROOF_SAMPLE := Vector2i(430, 180)
const OUTPUT_DIR := "res://artifacts/mountain_cavity_skylight_field_probe"

var _root_2d: Node2D = null
var _field: MountainCavitySkylightField = null
var _sun: DirectionalLight2D = null
var _player_light: PointLight2D = null
var _stationary_light: PointLight2D = null
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_cavity_skylight_field_probe: must run windowed")
		quit(1)
		return
	DisplayServer.window_set_size(WINDOW_SIZE)
	_build_scene()
	await _wait(8)

	_field.visible = false
	_set_lights(false, false, false)
	var baseline: Dictionary = await _capture("01_field_disabled")

	_field.set_reveal_blend(0.0)
	var roof_closed: Dictionary = await _capture("02_roof_closed_mouth")

	_player_light.position = Vector2(MOUTH_SAMPLE)
	_set_lights(false, true, false)
	var roof_closed_lit: Dictionary = await _capture("03_roof_closed_mouth_point")
	_player_light.position = Vector2(DEEP_SAMPLE)
	_set_lights(false, false, false)

	_field.set_reveal_blend(1.0)
	var dark: Dictionary = await _capture("04_cavity_dark")

	_set_lights(true, false, false)
	var sun_only: Dictionary = await _capture("05_directional_rejected")

	_set_lights(false, true, false)
	var player_lit: Dictionary = await _capture("06_generic_player_point")

	_set_lights(false, false, true)
	var stationary_lit: Dictionary = await _capture("07_generic_stationary_point")

	_field.set_reveal_blend(0.0)
	_set_lights(false, false, false)
	var roof_closed_again: Dictionary = await _capture("08_roof_closed_again")

	_expect(
		float(dark["deep"]) < float(baseline["deep"]) * 0.60,
		"deep cavity did not become materially darker",
	)
	_expect(
		float(dark["entrance_soft"]) < float(baseline["entrance_soft"]) - 0.004,
		"one-tile ingress did not begin with a visible soft shadow",
	)
	_expect(
		float(dark["entrance_soft"]) > float(dark["entrance_mid"]) + 0.006,
		"entrance shadow did not darken progressively through the first half tile",
	)
	_expect(
		float(dark["entrance_mid"]) > float(dark["mouth"]) + 0.006,
		"entrance shadow reached full darkness too abruptly",
	)
	_expect(
		float(dark["mouth"]) > float(dark["deep"]) + 0.005,
		"one-tile ingress lost its final transition into full cave darkness",
	)
	_expect(
		float(roof_closed["mouth"]) < float(baseline["mouth"]) * 0.80,
		"closed construction roof did not leave natural darkness in the real mouth",
	)
	_expect(
		absf(float(dark["mouth"]) - float(roof_closed["mouth"])) < 0.035,
		"mouth darkness pulsed while the roof opened",
	)
	_expect(
		float(roof_closed_lit["mouth"]) > float(roof_closed["mouth"]) + 0.045,
		"generic PointLight2D did not dissolve closed-mouth darkness",
	)
	_expect(
		absf(float(roof_closed["deep"]) - float(baseline["deep"])) < 0.025,
		"closed-mouth coverage leaked into the covered deep cavity",
	)
	_expect(
		float(sun_only["deep"]) <= float(dark["deep"]) + 0.025,
		"DirectionalLight2D reopened deep skylight",
	)
	_expect(
		float(player_lit["deep"]) > float(dark["deep"]) + 0.045,
		"generic player PointLight2D did not dissolve darkness",
	)
	_expect(
		float(stationary_lit["stationary"]) > float(dark["stationary"]) + 0.045,
		"generic stationary PointLight2D did not dissolve darkness",
	)
	_expect(
		absf(float(dark["exterior"]) - float(baseline["exterior"])) < 0.025,
		"selector clipping darkened unrelated exterior",
	)
	_expect(
		float(dark["organic_fringe"]) < float(baseline["organic_fringe"]) * 0.60,
		"tile selector left a bright square inside the organic cavity fringe",
	)
	_expect(
		absf(float(dark["foreign_cavity"]) - float(baseline["foreign_cavity"])) < 0.025,
		"guarded selector leaked into a foreign cavity",
	)
	_expect(
		float(dark["internal_facade"]) < float(baseline["internal_facade"]) * 0.60,
		"internal facade did not inherit organic cavity darkness",
	)
	_expect(
		absf(float(dark["roof"]) - float(baseline["roof"])) < 0.025,
		"facade coverage leaked onto the closed roof",
	)
	_expect(
		absf(float(roof_closed["roof"]) - float(baseline["roof"])) < 0.025,
		"closed-mouth coverage darkened the roof surface",
	)
	_expect(
		absf(float(roof_closed_again["mouth"]) - float(roof_closed["mouth"])) < 0.025
				and absf(float(roof_closed_again["deep"]) - float(baseline["deep"])) < 0.025,
		"closing the roof did not restore the stable mouth-only field",
	)

	print("mountain_cavity_skylight_field_probe metrics:")
	var all_results: Dictionary = {
		"baseline": baseline,
		"roof_closed": roof_closed,
		"roof_closed_lit": roof_closed_lit,
		"dark": dark,
		"sun_only": sun_only,
		"player_lit": player_lit,
		"stationary_lit": stationary_lit,
		"roof_closed_again": roof_closed_again,
	}
	for case_name: String in [
		"baseline",
		"roof_closed",
		"roof_closed_lit",
		"dark",
		"sun_only",
		"player_lit",
		"stationary_lit",
		"roof_closed_again",
	]:
		var data: Dictionary = all_results.get(case_name, { }) as Dictionary
		print("%s %s" % [case_name, JSON.stringify(data)])

	if _failures.is_empty():
		print("mountain_cavity_skylight_field_probe: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("mountain_cavity_skylight_field_probe: %s" % failure)
	quit(1)


func _build_scene() -> void:
	_root_2d = Node2D.new()
	root.add_child(_root_2d)

	var daylight := CanvasModulate.new()
	daylight.color = Color(0.72, 0.70, 0.68)
	_root_2d.add_child(daylight)

	_add_rect_sprite(
		"Ground",
		Vector2(VIEW_SIZE) * 0.5,
		Vector2(VIEW_SIZE),
		Color(0.36, 0.25, 0.16),
		0,
	)
	_add_rect_sprite(
		"DeepWorldObject",
		Vector2(DEEP_SAMPLE) + Vector2(0.0, -28.0),
		Vector2(72.0, 96.0),
		Color(0.22, 0.45, 0.30),
		120,
	)
	_add_rect_sprite(
		"StationaryWorldObject",
		Vector2(STATIONARY_SAMPLE),
		Vector2(80.0, 80.0),
		Color(0.40, 0.28, 0.48),
		120,
	)

	_sun = DirectionalLight2D.new()
	_sun.name = "ProbeSun"
	_sun.energy = 1.5
	_sun.color = Color(1.0, 0.92, 0.78)
	_sun.enabled = false
	_root_2d.add_child(_sun)

	_player_light = _make_point_light("ArbitraryMovingPoint", Vector2(DEEP_SAMPLE), Color(1.0, 0.72, 0.42))
	_root_2d.add_child(_player_light)
	_stationary_light = _make_point_light(
		"ArbitraryStationaryPoint",
		Vector2(STATIONARY_SAMPLE),
		Color(0.58, 0.78, 1.0),
	)
	_root_2d.add_child(_stationary_light)

	_field = MountainCavitySkylightField.new()
	_root_2d.add_child(_field)
	_field.apply_chunk_source(Vector2i.ZERO, _make_field_source())
	_field.set_reveal_blend(0.0)


func _add_rect_sprite(
		item_name: String,
		position_px: Vector2,
		size_px: Vector2,
		color: Color,
		z_value: int,
) -> void:
	var sprite := Sprite2D.new()
	sprite.name = item_name
	sprite.texture = _make_unit_texture()
	sprite.position = position_px
	sprite.scale = size_px
	sprite.modulate = color
	sprite.z_as_relative = false
	sprite.z_index = z_value
	_root_2d.add_child(sprite)


func _make_field_source() -> Dictionary:
	const MASK_SIDE := 128
	const SELECTOR_SIDE := 16
	var closed_image := Image.create(MASK_SIDE, MASK_SIDE, false, Image.FORMAT_L8)
	closed_image.fill(Color.BLACK)
	var live_image := Image.create(MASK_SIDE, MASK_SIDE, false, Image.FORMAT_L8)
	live_image.fill(Color.WHITE)
	var exposure_image := Image.create(MASK_SIDE, MASK_SIDE, false, Image.FORMAT_L8)
	exposure_image.fill(Color.WHITE)
	const MASK_STEP_PX := 8.0
	const ACTIVE_CENTER := Vector2(430.0, 470.0)
	const ACTIVE_RADIUS := Vector2(360.0, 190.0)
	const FOREIGN_CENTER := Vector2(980.0, 470.0)
	const FOREIGN_RADIUS := Vector2(30.0, 65.0)
	for y: int in range(MASK_SIDE):
		for x: int in range(MASK_SIDE):
			var world_sample := Vector2(float(x) + 0.5, float(y) + 0.5) * MASK_STEP_PX
			var closed_south_edge_y: float = _closed_south_edge_y(world_sample.x)
			var is_closed_mountain: bool = world_sample.y <= closed_south_edge_y
			if is_closed_mountain:
				closed_image.set_pixel(x, y, Color.WHITE)
			var is_active_cutout: bool = _ellipse_contains(
				world_sample,
				ACTIVE_CENTER,
				ACTIVE_RADIUS,
			)
			var is_foreign_cutout: bool = _ellipse_contains(
				world_sample,
				FOREIGN_CENTER,
				FOREIGN_RADIUS,
			)
			if not is_closed_mountain \
					or (not is_active_cutout and not is_foreign_cutout):
				continue
			live_image.set_pixel(x, y, Color.BLACK)
			var exposure: float = 0.0
			if is_active_cutout:
				exposure = clampf(
					1.0 - (closed_south_edge_y - world_sample.y) / 64.0,
					0.0,
					1.0,
				)
			exposure_image.set_pixel(x, y, Color(exposure, exposure, exposure, 1.0))
	var selector_image := Image.create(SELECTOR_SIDE, SELECTOR_SIDE, false, Image.FORMAT_L8)
	selector_image.fill(Color.BLACK)
	var any_cutout_image := Image.create(SELECTOR_SIDE, SELECTOR_SIDE, false, Image.FORMAT_L8)
	any_cutout_image.fill(Color.BLACK)
	for y: int in range(SELECTOR_SIDE):
		for x: int in range(SELECTOR_SIDE):
			var tile_center := Vector2(float(x) + 0.5, float(y) + 0.5) * 64.0
			var is_active_tile: bool = _ellipse_contains(
				tile_center,
				ACTIVE_CENTER,
				ACTIVE_RADIUS,
			)
			var is_foreign_tile: bool = _ellipse_contains(
				tile_center,
				FOREIGN_CENTER,
				FOREIGN_RADIUS,
			)
			if is_active_tile:
				selector_image.set_pixel(x, y, Color.WHITE)
			if is_active_tile or is_foreign_tile:
				any_cutout_image.set_pixel(x, y, Color.WHITE)
	return {
		"ready": true,
		"live_mask_texture": ImageTexture.create_from_image(live_image),
		"closed_roof_mask_texture": ImageTexture.create_from_image(closed_image),
		"sky_exposure_texture": ImageTexture.create_from_image(exposure_image),
		"reveal_selector_texture": ImageTexture.create_from_image(selector_image),
		"any_cutout_texture": ImageTexture.create_from_image(any_cutout_image),
		"chunk_origin_world": Vector2.ZERO,
		"chunk_size_world": Vector2(1024.0, 1024.0),
		"mask_origin_world": Vector2.ZERO,
		"mask_size_world": Vector2(1024.0, 1024.0),
		"selector_origin_world": Vector2.ZERO,
		"selector_size_world": Vector2(1024.0, 1024.0),
		"mask_sample_step_px": 8.0,
		"facade_height_px": 72.0,
	}


func _closed_south_edge_y(world_x: float) -> float:
	var t: float = clampf((world_x - 260.0) / 190.0, 0.0, 1.0)
	var smooth_t: float = t * t * (3.0 - 2.0 * t)
	return lerpf(520.0, 680.0, smooth_t)


func _ellipse_contains(point: Vector2, center: Vector2, radius: Vector2) -> bool:
	var normalized := (point - center) / radius
	return normalized.length_squared() <= 1.0


func _make_point_light(item_name: String, position_px: Vector2, color: Color) -> PointLight2D:
	var light := PointLight2D.new()
	light.name = item_name
	light.position = position_px
	light.texture = _make_radial_texture(512)
	light.texture_scale = 1.35
	light.energy = 1.0
	light.color = color
	light.shadow_enabled = false
	light.enabled = false
	return light


func _set_lights(sun_enabled: bool, player_enabled: bool, stationary_enabled: bool) -> void:
	_sun.enabled = sun_enabled
	_player_light.enabled = player_enabled
	_stationary_light.enabled = stationary_enabled


func _capture(label: String) -> Dictionary:
	await _wait(4)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var absolute_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var save_error: Error = image.save_png("%s/%s.png" % [absolute_dir, label])
	_expect(save_error == OK, "failed to save %s capture" % label)
	return {
		"deep": _sample_world_luma(image, DEEP_SAMPLE),
		"entrance_soft": _sample_world_luma(image, ENTRANCE_SOFT_SAMPLE),
		"entrance_mid": _sample_world_luma(image, ENTRANCE_MID_SAMPLE),
		"mouth": _sample_world_luma(image, MOUTH_SAMPLE),
		"stationary": _sample_world_luma(image, STATIONARY_SAMPLE),
		"exterior": _sample_world_luma(image, EXTERIOR_SAMPLE),
		"organic_fringe": _sample_world_luma(image, ORGANIC_FRINGE_SAMPLE),
		"foreign_cavity": _sample_world_luma(image, FOREIGN_CAVITY_SAMPLE),
		"internal_facade": _sample_world_luma(image, INTERNAL_FACADE_SAMPLE),
		"roof": _sample_world_luma(image, ROOF_SAMPLE),
	}


func _wait(frame_count: int) -> void:
	for _index: int in range(frame_count):
		await process_frame


func _luma(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _sample_world_luma(image: Image, world_position: Vector2i) -> float:
	var logical_size: Vector2 = root.get_visible_rect().size
	var capture_scale: Vector2 = Vector2(image.get_size()) / logical_size
	var capture_position := Vector2i(
		clampi(roundi(float(world_position.x) * capture_scale.x), 0, image.get_width() - 1),
		clampi(roundi(float(world_position.y) * capture_scale.y), 0, image.get_height() - 1),
	)
	return _luma(image.get_pixelv(capture_position))


func _make_unit_texture() -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _make_radial_texture(size_px: int) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size_px
	texture.height = size_px
	return texture


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
