extends SceneTree

# Windowed render diagnostic for torch-vs-mountain LightOccluder2D behavior.
# Captures a synthetic runtime-like ChunkView mountain with a torch below the facade edge:
#   01_no_occluder.png       -> torch washes roof/facade
#   02_chunk_contour.png     -> current ChunkView-built occluders
#   03_manual_line.png       -> a single hand-placed open occluder line
#
# Run:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/mountain_torch_occluder_render_probe.gd

const ChunkView = preload("res://core/systems/world/chunk_view.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_torch_occluder_render_probe"
const TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png"
const LIGHT_LAYER: int = 1
const MASK_W: int = 1024
const MASK_H: int = 768
const MASK_STEP_PX: float = 8.0
const SOLID_X0: int = 128
const SOLID_X1: int = 896
const SOLID_Y0: int = 160
const SOLID_Y1: int = 560
const FACADE_INSET: int = 72
const EDGE_Y: int = SOLID_Y1 - FACADE_INSET
const TORCH_POS: Vector2 = Vector2(512.0, 612.0)
const ROOF_SAMPLE: Vector2i = Vector2i(512, 360)
const FACADE_SAMPLE: Vector2i = Vector2i(512, 532)

var _failed: bool = false
var _view: ChunkView = null
var _manual_occluder: LightOccluder2D = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_torch_occluder_render_probe: must run windowed")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1024, 768))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var scene := Node2D.new()
	root.add_child(scene)
	_build_backdrop(scene)
	_build_camera(scene)
	_build_mountain(scene)
	_build_torch(scene)
	await _wait(20)

	_view.set_mountain_light_occluders_enabled(false)
	await _capture("01_no_occluder")

	_view.set_mountain_light_occluders_enabled(true)
	_view.sync_mountain_light_occluders()
	var chunk_debug: Dictionary = _view.get_mountain_light_occluder_debug_state()
	print("chunk_occluders=%s" % str(chunk_debug))
	await _wait(10)
	await _capture("02_chunk_contour")

	_view.set_mountain_light_occluders_enabled(false)
	_add_manual_line(scene)
	await _wait(10)
	await _capture("03_manual_line")

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
	var mask := PackedByteArray()
	mask.resize(mask_width * mask_height)
	var solid_samples: int = 0
	for my: int in range(mask_height):
		var world_y: float = (float(my) + 0.5) * MASK_STEP_PX
		for mx: int in range(mask_width):
			var world_x: float = (float(mx) + 0.5) * MASK_STEP_PX
			var top_edge: float = float(SOLID_Y0) \
					+ sin(world_x / 154.0) * 28.0 \
					+ sin(world_x / 57.0 + 1.7) * 9.0
			var bottom_edge: float = float(SOLID_Y1) \
					+ sin(world_x / 126.0 + 0.8) * 34.0 \
					+ sin(world_x / 49.0) * 12.0
			var side_wobble: float = sin(world_y / 118.0) * 22.0
			if world_x >= float(SOLID_X0) + side_wobble \
					and world_x <= float(SOLID_X1) + side_wobble * 0.5 \
					and world_y >= top_edge \
					and world_y <= bottom_edge:
				mask[my * mask_width + mx] = 255
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
	_view.apply_sun_lighting(234.0, 0.0, 0.0, 1.0)


func _build_torch(parent: Node2D) -> void:
	var torch := PointLight2D.new()
	torch.name = "ProbeTorch"
	torch.position = TORCH_POS
	torch.texture = _make_radial(512)
	torch.texture_scale = 1.35
	torch.energy = 1.2
	torch.color = Color(1.0, 0.78, 0.50)
	torch.shadow_enabled = true
	torch.shadow_filter = Light2D.SHADOW_FILTER_PCF13
	torch.shadow_filter_smooth = 9.0
	torch.shadow_item_cull_mask = LIGHT_LAYER
	parent.add_child(torch)


func _add_manual_line(parent: Node2D) -> void:
	if _manual_occluder != null and is_instance_valid(_manual_occluder):
		_manual_occluder.queue_free()
	_manual_occluder = LightOccluder2D.new()
	_manual_occluder.occluder_light_mask = LIGHT_LAYER
	var poly := OccluderPolygon2D.new()
	poly.closed = false
	poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
	poly.polygon = PackedVector2Array([
		Vector2(SOLID_X0, EDGE_Y),
		Vector2(SOLID_X1, EDGE_Y),
	])
	_manual_occluder.occluder = poly
	parent.add_child(_manual_occluder)


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
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		_assert(false, "capture failed %s" % label)
		return
	var roof: Color = img.get_pixelv(ROOF_SAMPLE)
	var facade: Color = img.get_pixelv(FACADE_SAMPLE)
	print(
		"%s roof_luma=%.4f facade_luma=%.4f path=%s/%s.png" % [
			label,
			_luma(roof),
			_luma(facade),
			ProjectSettings.globalize_path(OUTPUT_DIR),
			label,
		]
	)
	img.save_png("%s/%s.png" % [OUTPUT_DIR, label])


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
