extends SceneTree

# Windowed micro-benchmark for torch shadow-field cost.
#
# This intentionally avoids WorldStreamer/ChunkView/native mask work. The mountain
# mask is all-open, so any frame-time jump between torch_only and field_* is the
# shader ray-march pass itself, not CPU stitching or native workers.
#
# Run:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/mountain_torch_shadow_field_perf_probe.gd

const SHADOW_FIELD_SHADER = preload("res://assets/shaders/mountain_torch_shadow_field.gdshader")

const VIEW_SIZE: Vector2i = Vector2i(1280, 720)
const SAMPLE_FRAMES: int = 180
const WARMUP_FRAMES: int = 30
const TORCH_RADIUS_PX: float = 512.0 * 2.2 * 0.5

var _root_2d: Node2D = null
var _torch: PointLight2D = null
var _field: Sprite2D = null
var _field_material: ShaderMaterial = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_torch_shadow_field_perf_probe: must run windowed")
		quit(1)
		return
	DisplayServer.window_set_size(VIEW_SIZE)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_build_scene()
	await _wait(30)

	var results: Dictionary = {}
	results["baseline"] = await _measure_case(false, false, TORCH_RADIUS_PX)
	results["torch_only"] = await _measure_case(true, false, TORCH_RADIUS_PX)
	results["field_radius_563"] = await _measure_case(true, true, TORCH_RADIUS_PX)
	results["field_radius_360"] = await _measure_case(true, true, 360.0)
	results["field_radius_240"] = await _measure_case(true, true, 240.0)

	print("mountain_torch_shadow_field_perf_probe results:")
	for key: String in results.keys():
		var data: Dictionary = results[key] as Dictionary
		print("%s avg_ms=%.3f p95_ms=%.3f min_ms=%.3f max_ms=%.3f fps_avg=%.1f" % [
			key,
			float(data.get("avg_ms", 0.0)),
			float(data.get("p95_ms", 0.0)),
			float(data.get("min_ms", 0.0)),
			float(data.get("max_ms", 0.0)),
			1000.0 / maxf(float(data.get("avg_ms", 1000.0)), 0.001),
		])

	_root_2d.queue_free()
	await process_frame
	quit(0)


func _build_scene() -> void:
	_root_2d = Node2D.new()
	root.add_child(_root_2d)

	var ground := ColorRect.new()
	ground.size = VIEW_SIZE
	ground.color = Color(0.12, 0.10, 0.08)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_2d.add_child(ground)

	var camera := Camera2D.new()
	camera.enabled = true
	camera.position = Vector2(VIEW_SIZE) * 0.5
	_root_2d.add_child(camera)
	camera.make_current()

	_torch = PointLight2D.new()
	_torch.position = Vector2(VIEW_SIZE) * 0.5
	_torch.texture = _make_radial(512)
	_torch.texture_scale = 2.2
	_torch.energy = 0.9
	_torch.color = Color(1.0, 0.78, 0.5)
	_torch.shadow_enabled = false
	_root_2d.add_child(_torch)

	_field = Sprite2D.new()
	_field.centered = true
	_field.position = Vector2(VIEW_SIZE) * 0.5
	_field.scale = VIEW_SIZE
	_field.texture = _make_unit_texture()
	_field_material = ShaderMaterial.new()
	_field_material.shader = SHADOW_FIELD_SHADER
	_field.material = _field_material
	_field.z_index = 100
	_field.z_as_relative = false
	_root_2d.add_child(_field)

	var mask_image := Image.create(1, 1, false, Image.FORMAT_L8)
	mask_image.fill(Color.BLACK)
	var mask_texture := ImageTexture.create_from_image(mask_image)
	_field_material.set_shader_parameter("mountain_mask", mask_texture)
	_field_material.set_shader_parameter("mask_origin_px", Vector2.ZERO)
	_field_material.set_shader_parameter("mask_size_px", Vector2.ONE)
	_field_material.set_shader_parameter("view_world_origin", Vector2.ZERO)
	_field_material.set_shader_parameter("view_world_size", Vector2(VIEW_SIZE))
	_field_material.set_shader_parameter("torch_world_pos", Vector2(VIEW_SIZE) * 0.5)
	_field_material.set_shader_parameter("torch_strength", 1.0)


func _measure_case(torch_enabled: bool, field_enabled: bool, radius_px: float) -> Dictionary:
	_torch.enabled = torch_enabled
	_field.visible = field_enabled
	_field_material.set_shader_parameter("torch_radius_px", radius_px)
	await _wait(WARMUP_FRAMES)

	var samples: Array[float] = []
	samples.resize(SAMPLE_FRAMES)
	var previous_usec: int = Time.get_ticks_usec()
	for index: int in range(SAMPLE_FRAMES):
		await RenderingServer.frame_post_draw
		var now_usec: int = Time.get_ticks_usec()
		samples[index] = float(now_usec - previous_usec) / 1000.0
		previous_usec = now_usec
	samples.sort()
	var sum: float = 0.0
	for value: float in samples:
		sum += value
	return {
		"avg_ms": sum / float(samples.size()),
		"p95_ms": samples[mini(samples.size() - 1, int(floorf(float(samples.size()) * 0.95)))],
		"min_ms": samples[0],
		"max_ms": samples[samples.size() - 1],
	}


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _make_unit_texture() -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


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
