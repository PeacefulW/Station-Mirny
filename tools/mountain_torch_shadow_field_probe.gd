extends SceneTree

# Windowed render diagnostic for the mountain torch SHADOW FIELD (the shader
# ground+facade occlusion redesign of world_dynamic_lighting_2d.md Iteration 2).
#
# Scenario: a mountain band across the top with a rectangular SPUR of rock jutting
# south. A torch sits on the open apron to the lower-LEFT of the spur.
#   - Ground and south FACADE to the left of the spur have line of sight to the torch.
#   - Ground and south FACADE to the right of the spur are in the spur's shadow.
#
#   01_no_field.png  -> torch (no occlusion): the whole apron AND the whole facade are
#                       lit, including everything behind the spur == the bug.
#   02_field_on.png  -> shader field: left of the spur stays lit; the apron AND the
#                       facade behind the spur go dark; the facade darkening climbs the
#                       wall from its shadowed foot; the deep roof is unchanged.
#
# Numeric proof (luma per capture):
#   facade_lit   (south wall, foot has LoS)      -> bright in both.
#   facade_dark  (south wall behind the spur)    -> bright in 01, DARK in 02.  <-- the fix
#   floor_lit    (apron, clear LoS)              -> bright in both.
#   floor_dark   (apron behind the spur)         -> bright in 01, DARK in 02.
#   roof         (deep solid interior)           -> unchanged (sprite owns roof dark).
#
# Run (windowed; shaders do not compile headless):
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/mountain_torch_shadow_field_probe.gd

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const SHADOW_FIELD_SHADER = preload("res://assets/shaders/mountain_torch_shadow_field.gdshader")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_torch_shadow_field_probe"
const TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png"

const MASK_W: int = 1024
const MASK_H: int = 768
const MASK_STEP_PX: float = 8.0
const FACADE_HEIGHT_PX: float = 72.0

# Mountain band across the top; a rectangular spur juts south from it.
const MASSIF_X0: int = 64
const MASSIF_X1: int = 960
const MASSIF_Y0: int = 96
const MASSIF_Y1: int = 300
const SPUR_X0: int = 500
const SPUR_X1: int = 590
const SPUR_Y0: int = 300
const SPUR_Y1: int = 470

const TORCH_POS: Vector2 = Vector2(300.0, 540.0)
const TORCH_RADIUS_PX: float = 700.0

const FACADE_LIT_SAMPLE: Vector2i = Vector2i(250, 296)
const FACADE_DARK_SAMPLE: Vector2i = Vector2i(760, 296)
const FLOOR_LIT_SAMPLE: Vector2i = Vector2i(250, 430)
const FLOOR_DARK_SAMPLE: Vector2i = Vector2i(760, 360)
const ROOF_SAMPLE: Vector2i = Vector2i(300, 150)

var _failed: bool = false
var _view: ChunkView = null
var _field: Sprite2D = null
var _field_material: ShaderMaterial = null
var _capture_luma_by_label: Dictionary = {}
var _last_view_origin: Vector2 = Vector2.ZERO
var _last_view_size: Vector2 = Vector2(MASK_W, MASK_H)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_torch_shadow_field_probe: must run windowed (shaders do not compile headless)")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(MASK_W, MASK_H))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var scene := Node2D.new()
	root.add_child(scene)
	_build_backdrop(scene)
	_build_camera(scene)
	_build_mountain(scene)
	_build_torch(scene)
	_build_field(scene)
	await _wait(20)

	_field.visible = false
	await _capture("01_no_field")

	_field.visible = true
	await _wait(6)
	await _capture("02_field_on")
	_assert_shadow_field_behavior()

	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _build_backdrop(parent: Node2D) -> void:
	var ambient := CanvasModulate.new()
	ambient.color = Color(0.025, 0.027, 0.034)
	parent.add_child(ambient)
	var ground := ColorRect.new()
	ground.color = Color(0.15, 0.13, 0.105)
	ground.size = Vector2(MASK_W, MASK_H)
	ground.position = Vector2.ZERO
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ground)


func _build_camera(parent: Node2D) -> void:
	var camera := Camera2D.new()
	camera.enabled = true
	camera.position = Vector2(MASK_W, MASK_H) * 0.5
	camera.zoom = Vector2.ONE
	parent.add_child(camera)
	camera.make_current()


func _solid_at(world_x: float, world_y: float) -> bool:
	var in_massif: bool = world_x >= float(MASSIF_X0) and world_x <= float(MASSIF_X1) \
			and world_y >= float(MASSIF_Y0) and world_y <= float(MASSIF_Y1)
	var in_spur: bool = world_x >= float(SPUR_X0) and world_x <= float(SPUR_X1) \
			and world_y >= float(SPUR_Y0) and world_y <= float(SPUR_Y1)
	return in_massif or in_spur


func _build_mask() -> PackedByteArray:
	var mask_width: int = roundi(float(MASK_W) / MASK_STEP_PX)
	var mask_height: int = roundi(float(MASK_H) / MASK_STEP_PX)
	var mask := PackedByteArray()
	mask.resize(mask_width * mask_height)
	for my: int in range(mask_height):
		var world_y: float = (float(my) + 0.5) * MASK_STEP_PX
		for mx: int in range(mask_width):
			var world_x: float = (float(mx) + 0.5) * MASK_STEP_PX
			mask[my * mask_width + mx] = 255 if _solid_at(world_x, world_y) else 0
	return mask


func _build_mountain(parent: Node2D) -> void:
	var top_texture := load(TOP_TEXTURE_PATH) as Texture2D
	var face_texture := load(FACE_TEXTURE_PATH) as Texture2D
	_assert(top_texture != null, "missing top texture")
	_assert(face_texture != null, "missing face texture")
	_view = ChunkView.new()
	_view.configure(Vector2i.ZERO)
	_view.set_mountain_tile_visuals_enabled(false)
	parent.add_child(_view)

	var mask_width: int = roundi(float(MASK_W) / MASK_STEP_PX)
	var mask_height: int = roundi(float(MASK_H) / MASK_STEP_PX)
	var mask: PackedByteArray = _build_mask()
	var solid_samples: int = 0
	for value: int in mask:
		if value > 0:
			solid_samples += 1
	var result: Dictionary = {
		"success": true,
		"ready": true,
		"native": true,
		"top_mask": mask,
		"top_mask_width": mask_width,
		"top_mask_height": mask_height,
		"top_mask_origin_world": Vector2.ZERO,
		"top_mask_step_px": MASK_STEP_PX,
		"top_texture_scale": 0.70,
		"hit_mask": mask,
		"hit_mask_width": mask_width,
		"hit_mask_height": mask_height,
		"hit_mask_origin_world": Vector2.ZERO,
		"hit_mask_step_px": MASK_STEP_PX,
		"hit_mask_solid_pixel_count": solid_samples,
		"render_origin_world": Vector2.ZERO,
		"render_size_world": Vector2(MASK_W, MASK_H),
		"mountain_tile_count": 1,
		"top_pixel_count": solid_samples,
		"face_pixel_count": 0,
		"rim_pixel_count": 0,
		"image_width": mask_width,
		"image_height": mask_height,
		"runtime_emit_top_mask": true,
		"runtime_edge_overlay_only": true,
		"runtime_visual_clip_to_target_rect": true,
	}
	_view.apply_mountain_render_page(result, top_texture, face_texture)
	_view.apply_sun_lighting(WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG, 0.0, 0.0, 1.0)


func _build_torch(parent: Node2D) -> void:
	var torch := PointLight2D.new()
	torch.name = "ProbeTorch"
	torch.position = TORCH_POS
	torch.texture = _make_radial(512)
	torch.texture_scale = 2.8
	torch.energy = 3.0
	torch.color = Color(1.0, 0.78, 0.50)
	# No engine occluder shadows: the shader field is what blocks the pool now.
	torch.shadow_enabled = false
	parent.add_child(torch)


func _build_field(parent: Node2D) -> void:
	_field_material = ShaderMaterial.new()
	_field_material.shader = SHADOW_FIELD_SHADER
	var mask_image := Image.create_from_data(
		roundi(float(MASK_W) / MASK_STEP_PX),
		roundi(float(MASK_H) / MASK_STEP_PX),
		false,
		Image.FORMAT_L8,
		_build_mask(),
	)
	var mask_texture := ImageTexture.create_from_image(mask_image)
	_field_material.set_shader_parameter("mountain_mask", mask_texture)
	_field_material.set_shader_parameter("mask_origin_px", Vector2.ZERO)
	_field_material.set_shader_parameter("mask_size_px", Vector2(MASK_W, MASK_H))
	_field_material.set_shader_parameter("facade_height_px", FACADE_HEIGHT_PX)
	_field_material.set_shader_parameter("torch_world_pos", TORCH_POS)
	_field_material.set_shader_parameter("torch_radius_px", TORCH_RADIUS_PX)
	_field_material.set_shader_parameter("torch_strength", 1.0)

	var unit_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	unit_image.fill(Color.WHITE)
	_field = Sprite2D.new()
	_field.name = "MountainTorchShadowFieldProbe"
	_field.texture = ImageTexture.create_from_image(unit_image)
	_field.centered = true
	_field.z_as_relative = false
	_field.z_index = 30
	_field.position = Vector2(MASK_W, MASK_H) * 0.5
	_field.scale = Vector2(MASK_W, MASK_H)
	_field.material = _field_material
	parent.add_child(_field)


func _sync_field_view() -> void:
	if _field == null or _field_material == null:
		return
	var camera: Camera2D = root.get_viewport().get_camera_2d()
	if camera == null:
		return
	var zoom: Vector2 = Vector2(maxf(camera.zoom.x, 0.001), maxf(camera.zoom.y, 0.001))
	var view_size: Vector2 = root.get_visible_rect().size / zoom
	var view_center: Vector2 = camera.get_screen_center_position()
	var view_origin: Vector2 = view_center - view_size * 0.5
	_last_view_origin = view_origin
	_last_view_size = view_size
	_field.global_position = view_center
	_field.scale = view_size
	_field_material.set_shader_parameter("view_world_origin", view_origin)
	_field_material.set_shader_parameter("view_world_size", view_size)


func _make_radial(size_px: int) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size_px
	tex.height = size_px
	return tex


func _capture(label: String) -> void:
	_sync_field_view()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		_assert(false, "capture failed %s" % label)
		return
	# The OS window can be smaller than requested, so the capture resolution is not
	# guaranteed. Map world sample points through the camera transform (centered,
	# zoom 1) and the actual image size instead of assuming world == image pixels.
	var lumas: Dictionary = {
		"facade_lit": _luma(_sample_world(img, FACADE_LIT_SAMPLE)),
		"facade_dark": _luma(_sample_world(img, FACADE_DARK_SAMPLE)),
		"floor_lit": _luma(_sample_world(img, FLOOR_LIT_SAMPLE)),
		"floor_dark": _luma(_sample_world(img, FLOOR_DARK_SAMPLE)),
		"roof": _luma(_sample_world(img, ROOF_SAMPLE)),
	}
	_capture_luma_by_label[label] = lumas
	print(
		"%s facade_lit=%.4f facade_dark=%.4f floor_lit=%.4f floor_dark=%.4f roof=%.4f path=%s/%s.png" % [
			label,
			float(lumas["facade_lit"]),
			float(lumas["facade_dark"]),
			float(lumas["floor_lit"]),
			float(lumas["floor_dark"]),
			float(lumas["roof"]),
			ProjectSettings.globalize_path(OUTPUT_DIR),
			label,
		]
	)
	img.save_png("%s/%s.png" % [OUTPUT_DIR, label])


func _assert_shadow_field_behavior() -> void:
	var no_field: Dictionary = _capture_luma_by_label.get("01_no_field", {}) as Dictionary
	var field_on: Dictionary = _capture_luma_by_label.get("02_field_on", {}) as Dictionary
	_assert(not no_field.is_empty() and not field_on.is_empty(), "probe captures must exist before asserting")
	if no_field.is_empty() or field_on.is_empty():
		return
	var facade_lit_delta: float = absf(float(field_on["facade_lit"]) - float(no_field["facade_lit"]))
	var floor_lit_delta: float = absf(float(field_on["floor_lit"]) - float(no_field["floor_lit"]))
	var roof_delta: float = absf(float(field_on["roof"]) - float(no_field["roof"]))
	_assert(facade_lit_delta <= 0.025, "field must not darken lit facade with line of sight")
	_assert(floor_lit_delta <= 0.025, "field must not darken lit floor with line of sight")
	_assert(
		float(field_on["facade_dark"]) <= float(no_field["facade_dark"]) * 0.70,
		"field must darken occluded facade behind the spur",
	)
	_assert(
		float(field_on["floor_dark"]) <= float(no_field["floor_dark"]) * 0.70,
		"field must darken occluded floor behind the spur",
	)
	_assert(roof_delta <= 0.025, "field must not darken deep mountain roof pixels")


func _sample_world(img: Image, world_pt: Vector2i) -> Color:
	var img_size: Vector2 = Vector2(float(img.get_width()), float(img.get_height()))
	var safe_view_size := Vector2(maxf(_last_view_size.x, 1.0), maxf(_last_view_size.y, 1.0))
	var viewport_pt: Vector2 = (Vector2(world_pt) - _last_view_origin) / safe_view_size
	var p: Vector2 = viewport_pt * img_size
	var ix: int = clampi(roundi(p.x), 0, img.get_width() - 1)
	var iy: int = clampi(roundi(p.y), 0, img.get_height() - 1)
	return img.get_pixel(ix, iy)


func _luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
