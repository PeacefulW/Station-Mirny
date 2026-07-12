extends SceneTree

# Windowed render regression for the cave-facing MountainTorchShadowField contract.
#
# A torch stands inside one active chamber. The chamber has a straight mouth to the
# exterior and retains one isolated island of solid mountain. The shadow field must:
#   * leave clear floor inside the chamber lit;
#   * cast a shadow from the retained island;
#   * let the torch pool continue through the mouth to exterior ground;
#   * keep exterior ground behind the solid mouth lip dark.
#
# Run (the shader needs a real renderer):
#   Godot_v4.7-stable_win64_console.exe --path . \
#     -s tools/mountain_torch_shadow_cave_island_probe.gd

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const SHADOW_FIELD_SHADER = preload("res://assets/shaders/mountain_torch_shadow_field.gdshader")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_torch_shadow_cave_island_probe"
const TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png"

const VIEW_W: int = 1024
const VIEW_H: int = 768
const MASK_STEP_PX: float = 8.0
const FACADE_HEIGHT_PX: float = 72.0

# Everything north of this line begins as mountain. The active cave removes the
# chamber and the straight portal; the island is deliberately retained.
const EXTERIOR_Y: float = 586.0
const CHAMBER_CENTER: Vector2 = Vector2(470.0, 350.0)
const CHAMBER_RADIUS: Vector2 = Vector2(294.0, 224.0)
const MOUTH_X0: float = 452.0
const MOUTH_X1: float = 572.0
const MOUTH_Y0: float = 490.0

const ISLAND_CENTER: Vector2 = Vector2(600.0, 352.0)
const ISLAND_RADIUS: Vector2 = Vector2(56.0, 100.0)

const TORCH_POS: Vector2 = Vector2(420.0, 355.0)
const TORCH_RADIUS_PX: float = 560.0

# Pairs are chosen at nearly equal distance from the torch where comparisons need
# to isolate occlusion rather than the radial falloff of the PointLight2D.
const OPEN_INSIDE_SAMPLE: Vector2i = Vector2i(318, 360)
const BEHIND_ISLAND_SAMPLE: Vector2i = Vector2i(724, 355)
const OUTSIDE_MOUTH_SAMPLE: Vector2i = Vector2i(494, 704)
const OUTSIDE_LIP_SAMPLE: Vector2i = Vector2i(306, 704)
const ISLAND_MASK_SAMPLE: Vector2i = Vector2i(600, 352)

var _failed: bool = false
var _view: ChunkView = null
var _torch: PointLight2D = null
var _field: Sprite2D = null
var _field_material: ShaderMaterial = null
var _mask: PackedByteArray = PackedByteArray()
var _mask_width: int = 0
var _mask_height: int = 0
var _capture_luma_by_label: Dictionary = {}
var _last_view_origin: Vector2 = Vector2.ZERO
var _last_view_size: Vector2 = Vector2(VIEW_W, VIEW_H)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_torch_shadow_cave_island_probe: must run windowed")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(VIEW_W, VIEW_H))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	_mask_width = roundi(float(VIEW_W) / MASK_STEP_PX)
	_mask_height = roundi(float(VIEW_H) / MASK_STEP_PX)
	_mask = _build_mask()
	_assert_mask_contract()
	_save_mask_preview()

	var scene := Node2D.new()
	root.add_child(scene)
	_build_backdrop(scene)
	_build_camera(scene)
	_build_mountain(scene)
	_build_torch(scene)
	_build_field(scene)
	await _wait(20)

	_torch.enabled = false
	_field.visible = false
	await _wait(3)
	await _capture("00_ambient")

	_torch.enabled = true
	await _wait(5)
	await _capture("01_torch_no_field")

	_field.visible = true
	await _wait(6)
	await _capture("02_torch_with_field")
	_assert_render_contract()

	scene.queue_free()
	await process_frame
	if not _failed:
		print("mountain_torch_shadow_cave_island_probe: OK")
	quit(1 if _failed else 0)


func _build_backdrop(parent: Node2D) -> void:
	var ambient := CanvasModulate.new()
	ambient.color = Color(0.025, 0.027, 0.034)
	parent.add_child(ambient)
	var ground := ColorRect.new()
	ground.color = Color(0.19, 0.15, 0.105)
	ground.size = Vector2(VIEW_W, VIEW_H)
	ground.position = Vector2.ZERO
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ground)


func _build_camera(parent: Node2D) -> void:
	var camera := Camera2D.new()
	camera.enabled = true
	camera.position = Vector2(VIEW_W, VIEW_H) * 0.5
	camera.zoom = Vector2.ONE
	parent.add_child(camera)
	camera.make_current()


func _build_mountain(parent: Node2D) -> void:
	var top_texture := load(TOP_TEXTURE_PATH) as Texture2D
	var face_texture := load(FACE_TEXTURE_PATH) as Texture2D
	_assert(top_texture != null, "missing top texture")
	_assert(face_texture != null, "missing face texture")
	if top_texture == null or face_texture == null:
		return
	_view = ChunkView.new()
	_view.configure(Vector2i.ZERO)
	_view.set_mountain_tile_visuals_enabled(false)
	parent.add_child(_view)

	var solid_samples: int = 0
	for value: int in _mask:
		if value > 0:
			solid_samples += 1
	var result: Dictionary = {
		"success": true,
		"ready": true,
		"native": true,
		"top_mask": _mask,
		"top_mask_width": _mask_width,
		"top_mask_height": _mask_height,
		"top_mask_origin_world": Vector2.ZERO,
		"top_mask_step_px": MASK_STEP_PX,
		"top_texture_scale": 0.70,
		"hit_mask": _mask,
		"hit_mask_width": _mask_width,
		"hit_mask_height": _mask_height,
		"hit_mask_origin_world": Vector2.ZERO,
		"hit_mask_step_px": MASK_STEP_PX,
		"hit_mask_solid_pixel_count": solid_samples,
		"render_origin_world": Vector2.ZERO,
		"render_size_world": Vector2(VIEW_W, VIEW_H),
		"mountain_tile_count": 1,
		"top_pixel_count": solid_samples,
		"face_pixel_count": 0,
		"rim_pixel_count": 0,
		"image_width": _mask_width,
		"image_height": _mask_height,
		"runtime_emit_top_mask": true,
		"runtime_edge_overlay_only": true,
		"runtime_visual_clip_to_target_rect": true,
	}
	_view.apply_mountain_render_page(result, top_texture, face_texture)
	_view.apply_sun_lighting(WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG, 0.0, 0.0, 1.0)


func _build_torch(parent: Node2D) -> void:
	_torch = PointLight2D.new()
	_torch.name = "CaveIslandProbeTorch"
	_torch.position = TORCH_POS
	_torch.texture = _make_radial(512)
	_torch.texture_scale = TORCH_RADIUS_PX * 2.0 / 512.0
	_torch.energy = 3.2
	_torch.color = Color(1.0, 0.76, 0.46)
	# This is intentional: the production field, not engine-generated tile
	# polygons, owns terrain occlusion. The retained island must still cast.
	_torch.shadow_enabled = false
	parent.add_child(_torch)


func _build_field(parent: Node2D) -> void:
	_field_material = ShaderMaterial.new()
	_field_material.shader = SHADOW_FIELD_SHADER
	var mask_image := Image.create_from_data(
		_mask_width,
		_mask_height,
		false,
		Image.FORMAT_L8,
		_mask,
	)
	_field_material.set_shader_parameter("mountain_mask", ImageTexture.create_from_image(mask_image))
	_field_material.set_shader_parameter("mask_origin_px", Vector2.ZERO)
	_field_material.set_shader_parameter("mask_size_px", Vector2(VIEW_W, VIEW_H))
	_field_material.set_shader_parameter("facade_height_px", FACADE_HEIGHT_PX)
	_field_material.set_shader_parameter("torch_world_pos", TORCH_POS)
	_field_material.set_shader_parameter("torch_radius_px", TORCH_RADIUS_PX)
	_field_material.set_shader_parameter("torch_strength", 1.0)

	var unit_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	unit_image.fill(Color.WHITE)
	_field = Sprite2D.new()
	_field.name = "MountainTorchShadowCaveIslandProbe"
	_field.texture = ImageTexture.create_from_image(unit_image)
	_field.centered = true
	_field.z_as_relative = false
	_field.z_index = 30
	_field.position = Vector2(VIEW_W, VIEW_H) * 0.5
	_field.scale = Vector2(VIEW_W, VIEW_H)
	_field.material = _field_material
	parent.add_child(_field)


func _build_mask() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(_mask_width * _mask_height)
	for my: int in range(_mask_height):
		var world_y: float = (float(my) + 0.5) * MASK_STEP_PX
		for mx: int in range(_mask_width):
			var world_x: float = (float(mx) + 0.5) * MASK_STEP_PX
			bytes[my * _mask_width + mx] = 255 if _solid_at(Vector2(world_x, world_y)) else 0
	return bytes


func _solid_at(world_pos: Vector2) -> bool:
	if world_pos.y >= EXTERIOR_Y:
		return false
	var chamber_offset: Vector2 = (world_pos - CHAMBER_CENTER) / CHAMBER_RADIUS
	var inside_chamber: bool = chamber_offset.length_squared() <= 1.0
	var inside_mouth: bool = world_pos.x >= MOUTH_X0 and world_pos.x <= MOUTH_X1 \
			and world_pos.y >= MOUTH_Y0
	var island_offset: Vector2 = (world_pos - ISLAND_CENTER) / ISLAND_RADIUS
	var inside_island: bool = island_offset.length_squared() <= 1.0
	return (not inside_chamber and not inside_mouth) or inside_island


func _assert_mask_contract() -> void:
	_assert(_mask_value_at(OPEN_INSIDE_SAMPLE) == 0, "open chamber sample must be dug/open")
	_assert(_mask_value_at(BEHIND_ISLAND_SAMPLE) == 0, "island-shadow floor sample must be dug/open")
	_assert(_mask_value_at(OUTSIDE_MOUTH_SAMPLE) == 0, "mouth ray exterior sample must be open")
	_assert(_mask_value_at(OUTSIDE_LIP_SAMPLE) == 0, "lip-shadow exterior sample must be open")
	_assert(_mask_value_at(ISLAND_MASK_SAMPLE) == 255, "retained internal mountain island must remain solid")
	_assert(_mask_value_at(Vector2i(512, 548)) == 0, "straight mouth center must stay open")
	_assert(_mask_value_at(Vector2i(330, 548)) == 255, "solid mouth lip must remain closed")


func _save_mask_preview() -> void:
	var image := Image.create_from_data(_mask_width, _mask_height, false, Image.FORMAT_L8, _mask)
	image.resize(VIEW_W, VIEW_H, Image.INTERPOLATE_NEAREST)
	var err: Error = image.save_png("%s/mask_preview.png" % OUTPUT_DIR)
	_assert(err == OK, "mask preview must save")


func _capture(label: String) -> void:
	_sync_field_view()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		_assert(false, "capture failed %s" % label)
		return
	var lumas: Dictionary = {
		"open_inside": _luma(_sample_world(image, OPEN_INSIDE_SAMPLE)),
		"behind_island": _luma(_sample_world(image, BEHIND_ISLAND_SAMPLE)),
		"outside_mouth": _luma(_sample_world(image, OUTSIDE_MOUTH_SAMPLE)),
		"outside_lip": _luma(_sample_world(image, OUTSIDE_LIP_SAMPLE)),
	}
	_capture_luma_by_label[label] = lumas
	print(
		"%s open_inside=%.4f behind_island=%.4f outside_mouth=%.4f outside_lip=%.4f path=%s/%s.png" % [
			label,
			float(lumas["open_inside"]),
			float(lumas["behind_island"]),
			float(lumas["outside_mouth"]),
			float(lumas["outside_lip"]),
			ProjectSettings.globalize_path(OUTPUT_DIR),
			label,
		]
	)
	var err: Error = image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	_assert(err == OK, "capture %s must save" % label)


func _assert_render_contract() -> void:
	var ambient: Dictionary = _capture_luma_by_label.get("00_ambient", {}) as Dictionary
	var no_field: Dictionary = _capture_luma_by_label.get("01_torch_no_field", {}) as Dictionary
	var with_field: Dictionary = _capture_luma_by_label.get("02_torch_with_field", {}) as Dictionary
	_assert(not ambient.is_empty() and not no_field.is_empty() and not with_field.is_empty(), "all captures must exist")
	if ambient.is_empty() or no_field.is_empty() or with_field.is_empty():
		return

	# (a) Clear floor inside stays lit after the field is enabled.
	_assert(
		absf(float(with_field["open_inside"]) - float(no_field["open_inside"])) <= 0.035,
		"clear line of sight inside the chamber must remain lit",
	)
	# (b) The isolated retained mountain island casts onto open cave floor.
	_assert(
		float(with_field["behind_island"]) <= float(no_field["behind_island"]) * 0.72,
		"open floor behind the retained island must darken",
	)
	# (c) The torch genuinely reaches exterior ground through the straight mouth,
	# and the field must not plug that portal with an invisible blocker.
	_assert(
		float(no_field["outside_mouth"]) >= float(ambient["outside_mouth"]) + 0.035,
		"torch pool must visibly reach exterior ground before occlusion",
	)
	_assert(
		absf(float(with_field["outside_mouth"]) - float(no_field["outside_mouth"])) <= 0.035,
		"light along the open mouth ray must keep exiting the cave",
	)
	# (d) A nearby exterior point at similar radius sits behind the solid mouth lip.
	_assert(
		float(with_field["outside_lip"]) <= float(no_field["outside_lip"]) * 0.72,
		"off-axis exterior ground behind the solid mouth lip must darken",
	)
	_assert(
		float(with_field["outside_mouth"]) >= float(with_field["outside_lip"]) + 0.035,
		"the open mouth ray must remain visibly brighter than the adjacent lip shadow",
	)


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


func _mask_value_at(world_point: Vector2i) -> int:
	var mx: int = clampi(floori(float(world_point.x) / MASK_STEP_PX), 0, _mask_width - 1)
	var my: int = clampi(floori(float(world_point.y) / MASK_STEP_PX), 0, _mask_height - 1)
	return int(_mask[my * _mask_width + mx])


func _sample_world(image: Image, world_point: Vector2i) -> Color:
	var image_size := Vector2(float(image.get_width()), float(image.get_height()))
	var safe_view_size := Vector2(maxf(_last_view_size.x, 1.0), maxf(_last_view_size.y, 1.0))
	var viewport_point: Vector2 = (Vector2(world_point) - _last_view_origin) / safe_view_size
	var pixel: Vector2 = viewport_point * image_size
	return image.get_pixel(
		clampi(roundi(pixel.x), 0, image.get_width() - 1),
		clampi(roundi(pixel.y), 0, image.get_height() - 1),
	)


func _luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114


func _make_radial(size_px: int) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size_px
	texture.height = size_px
	return texture


func _wait(frames: int) -> void:
	for _frame: int in range(frames):
		await process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
