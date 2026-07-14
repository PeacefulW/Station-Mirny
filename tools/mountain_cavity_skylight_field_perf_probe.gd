extends SceneTree

# Windowed GPU/CPU micro-benchmark for M8.2. It reports the bounded selector
# apply and reveal costs separately from frame presentation cost.
#
# Run:
#   Godot_v4.7-stable_win64_console.exe --path . \
#     -s tools/mountain_cavity_skylight_field_perf_probe.gd

const MountainCavitySkylightField = preload(
	"res://core/systems/world/mountain_cavity_skylight_field.gd"
)

const VIEW_SIZE := Vector2i(1280, 720)
const CHUNK_SIZE_PX := 256
const CHUNK_COLUMNS := 5
const CHUNK_ROWS := 3
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 180
const REVEAL_TOGGLE_ITERATIONS := 10000

var _root_2d: Node2D = null
var _field: MountainCavitySkylightField = null
var _point_light: PointLight2D = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_cavity_skylight_field_perf_probe: must run windowed")
		quit(1)
		return
	DisplayServer.window_set_size(VIEW_SIZE)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_build_scene()

	var apply_started_usec: int = Time.get_ticks_usec()
	var source: Dictionary = _make_field_source()
	for y: int in range(CHUNK_ROWS):
		for x: int in range(CHUNK_COLUMNS):
			var chunk_coord := Vector2i(x, y)
			var chunk_source: Dictionary = source.duplicate()
			var origin := Vector2(x * CHUNK_SIZE_PX, y * CHUNK_SIZE_PX)
			chunk_source["chunk_origin_world"] = origin
			chunk_source["mask_origin_world"] = origin
			chunk_source["selector_origin_world"] = origin
			_field.apply_chunk_source(chunk_coord, chunk_source)
	var apply_ms: float = float(Time.get_ticks_usec() - apply_started_usec) / 1000.0

	var reveal_started_usec: int = Time.get_ticks_usec()
	for index: int in range(REVEAL_TOGGLE_ITERATIONS):
		_field.set_reveal_blend(0.85 if (index & 1) == 0 else 1.0)
	var reveal_total_ms: float = float(Time.get_ticks_usec() - reveal_started_usec) / 1000.0

	_field.visible = false
	_point_light.enabled = false
	var baseline: Dictionary = await _measure_case()
	_field.set_reveal_blend(0.0)
	var closed_mouth: Dictionary = await _measure_case()
	_field.set_reveal_blend(1.0)
	var field_only: Dictionary = await _measure_case()
	_point_light.enabled = true
	var field_with_point: Dictionary = await _measure_case()

	var debug: Dictionary = _field.get_debug_state()
	var expected_chunks: int = CHUNK_COLUMNS * CHUNK_ROWS
	if int(debug.get("sprite_count", 0)) != expected_chunks \
			or int(debug.get("active_chunk_count", 0)) != expected_chunks:
		push_error("mountain_cavity_skylight_field_perf_probe: field chunk accounting failed")
		quit(1)
		return

	print("mountain_cavity_skylight_field_perf_probe results:")
	print("chunk_apply count=%d total_ms=%.3f avg_ms=%.4f" % [
		expected_chunks,
		apply_ms,
		apply_ms / float(expected_chunks),
	])
	print("reveal_o1 iterations=%d total_ms=%.3f avg_usec=%.3f" % [
		REVEAL_TOGGLE_ITERATIONS,
		reveal_total_ms,
		reveal_total_ms * 1000.0 / float(REVEAL_TOGGLE_ITERATIONS),
	])
	_print_frame_case("baseline", baseline)
	_print_frame_case("closed_mouth", closed_mouth)
	_print_frame_case("field_only", field_only)
	_print_frame_case("field_with_generic_point", field_with_point)
	print("mountain_cavity_skylight_field_perf_probe: PASS (diagnostic timings reported)")
	quit(0)


func _build_scene() -> void:
	_root_2d = Node2D.new()
	root.add_child(_root_2d)
	var ground := Sprite2D.new()
	ground.texture = _make_unit_texture()
	ground.position = Vector2(VIEW_SIZE) * 0.5
	ground.scale = Vector2(VIEW_SIZE)
	ground.modulate = Color(0.34, 0.24, 0.15)
	_root_2d.add_child(ground)

	_point_light = PointLight2D.new()
	_point_light.position = Vector2(VIEW_SIZE) * 0.5
	_point_light.texture = _make_radial_texture(1024)
	_point_light.texture_scale = 1.4
	_point_light.energy = 1.0
	_point_light.color = Color(1.0, 0.75, 0.48)
	_point_light.enabled = false
	_root_2d.add_child(_point_light)

	_field = MountainCavitySkylightField.new()
	_root_2d.add_child(_field)


func _make_field_source() -> Dictionary:
	const MASK_SIDE := 32
	const SELECTOR_SIDE := 4
	var closed := Image.create(MASK_SIDE, MASK_SIDE, false, Image.FORMAT_L8)
	closed.fill(Color.WHITE)
	var live := Image.create(MASK_SIDE, MASK_SIDE, false, Image.FORMAT_L8)
	live.fill(Color.BLACK)
	var exposure := Image.create(MASK_SIDE, MASK_SIDE, false, Image.FORMAT_L8)
	exposure.fill(Color.BLACK)
	var selector := Image.create(SELECTOR_SIDE, SELECTOR_SIDE, false, Image.FORMAT_L8)
	selector.fill(Color.WHITE)
	return {
		"ready": true,
		"live_mask_texture": ImageTexture.create_from_image(live),
		"closed_roof_mask_texture": ImageTexture.create_from_image(closed),
		"sky_exposure_texture": ImageTexture.create_from_image(exposure),
		"reveal_selector_texture": ImageTexture.create_from_image(selector),
		"any_cutout_texture": ImageTexture.create_from_image(selector),
		"chunk_origin_world": Vector2.ZERO,
		"chunk_size_world": Vector2.ONE * CHUNK_SIZE_PX,
		"mask_origin_world": Vector2.ZERO,
		"mask_size_world": Vector2.ONE * CHUNK_SIZE_PX,
		"selector_origin_world": Vector2.ZERO,
		"selector_size_world": Vector2.ONE * CHUNK_SIZE_PX,
		"mask_sample_step_px": float(CHUNK_SIZE_PX) / float(MASK_SIDE),
		"facade_height_px": 72.0,
	}


func _measure_case() -> Dictionary:
	for _index: int in range(WARMUP_FRAMES):
		await process_frame
	var samples: Array[float] = []
	var previous_usec: int = Time.get_ticks_usec()
	for _index: int in range(SAMPLE_FRAMES):
		await RenderingServer.frame_post_draw
		var now_usec: int = Time.get_ticks_usec()
		samples.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
	samples.sort()
	var total_ms: float = 0.0
	for sample_ms: float in samples:
		total_ms += sample_ms
	return {
		"avg_ms": total_ms / float(samples.size()),
		"p95_ms": samples[mini(samples.size() - 1, floori(samples.size() * 0.95))],
		"max_ms": samples[samples.size() - 1],
	}


func _print_frame_case(label: String, result: Dictionary) -> void:
	print("%s avg_ms=%.3f p95_ms=%.3f max_ms=%.3f" % [
		label,
		float(result.get("avg_ms", 0.0)),
		float(result.get("p95_ms", 0.0)),
		float(result.get("max_ms", 0.0)),
	])


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
