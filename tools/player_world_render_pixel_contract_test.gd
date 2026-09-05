extends Node2D
## Windowed framebuffer parity proof for the migrated Player body.
##
## The legacy Sprite2D and the production RenderWorld shader draw the same
## authored idle frame through the same camera at zoom 1.0 and 0.2. The test
## compares their silhouette, bounds and rendered pixels inside a bounded crop.

const WorldRenderRecord = preload("res://core/systems/world/world_render_record.gd")
const WorldRenderClassRegistry = preload(
	"res://core/systems/world/world_render_class_registry.gd"
)
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const BODY_SHADER: Shader = preload("res://assets/shaders/world_render_body.gdshader")
const FRAME_SIZE := Vector2(208.0, 288.0)
const GPU_STRIDE: int = 16
const PLAYER_IDLE_DESCRIPTOR_ID: float = 4.0
const SAMPLE_HALF_EXTENT: int = 128
const COLOR_EPSILON: float = 0.01
const PIXEL_DIFF_EPSILON: float = 0.025
const REPORT_PATH: String = "user://player_world_render_pixel_contract.txt"
## Distinct from both 0 (verified) and 1 (regression): the proof did not run.
const SKIP_EXIT_CODE: int = 2

var _legacy: Sprite2D = null
var _rendered: MultiMeshInstance2D = null
var _camera: Camera2D = null
var _legacy_image: Image = null
var _stage: int = 0
var _frames: int = 0
var _failed: bool = false
var _skipped: bool = false
var _lines := PackedStringArray()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		# This proof needs a real framebuffer. Reporting it as PASS would make an
		# unrun contract indistinguishable from a verified one.
		_skipped = true
		_say("player_world_render_pixel_contract_test: SKIP headless framebuffer")
		_finish.call_deferred()
		return
	RenderingServer.set_default_clear_color(Color(0.035, 0.045, 0.055, 1.0))
	var source_player: Node = PLAYER_SCENE.instantiate()
	var source_visual: Sprite2D = source_player.get_node("Visual") as Sprite2D
	var body_atlases: Array[Texture2D] = [
		source_player.get("idle_visual_texture") as Texture2D,
		source_player.get("run_forward_visual_texture") as Texture2D,
		source_player.get("run_backward_visual_texture") as Texture2D,
		source_player.get("strafe_left_visual_texture") as Texture2D,
		source_player.get("strafe_right_visual_texture") as Texture2D,
	]
	_legacy = Sprite2D.new()
	_legacy.name = "LegacyPlayerSprite"
	_legacy.texture = body_atlases[0]
	_legacy.centered = source_visual.centered
	_legacy.offset = source_visual.offset
	_legacy.scale = source_visual.scale
	_legacy.region_enabled = true
	_legacy.region_rect = Rect2(Vector2.ZERO, FRAME_SIZE)
	_legacy.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_legacy)
	source_player.free()

	var material := ShaderMaterial.new()
	material.shader = BODY_SHADER
	var registry := WorldRenderClassRegistry.new()
	if not registry.configure():
		_fail("production RenderClassRegistry did not configure")
		_finish.call_deferred()
		return
	material.set_shader_parameter("world_body_base_atlas", registry.get_texture(&"body_base"))
	material.set_shader_parameter("world_foliage_atlas", registry.get_texture(&"foliage"))
	material.set_shader_parameter("world_snow_overlay_atlas", registry.get_texture(&"snow_overlay"))
	material.set_shader_parameter("world_wind_mask_atlas", registry.get_texture(&"wind_mask"))
	material.set_shader_parameter("world_snow_mask_atlas", registry.get_texture(&"snow_mask"))
	material.set_shader_parameter("world_season_mask_atlas", registry.get_texture(&"season_mask"))
	material.set_shader_parameter("actor_body_atlas", registry.get_texture(&"actor_body"))
	material.set_shader_parameter("render_descriptor_lut", registry.get_descriptor_lut())
	material.set_shader_parameter("render_variant_crop_lut", registry.get_variant_crop_lut())
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.visible_instance_count = 1
	var body_transform: Transform2D = WorldRenderRecord.unit_quad_transform_for_sprite(
		_legacy,
		FRAME_SIZE,
	)
	multimesh.buffer = _actor_buffer(body_transform)
	_rendered = MultiMeshInstance2D.new()
	_rendered.name = "RenderWorldPlayerBody"
	_rendered.multimesh = multimesh
	_rendered.material = material
	_rendered.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rendered.visible = false
	add_child(_rendered)

	_camera = Camera2D.new()
	_camera.name = "PixelParityCamera"
	_camera.zoom = Vector2.ONE
	add_child(_camera)
	_camera.make_current()
	_say("framebuffer stage 1: legacy Player at zoom 1.0")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % 8 != 0:
		return
	match _stage:
		0:
			_legacy_image = _capture("legacy_zoom_1_0")
			_show_rendered(true)
			_stage = 1
			_say("framebuffer stage 2: RenderWorld Player at zoom 1.0")
		1:
			_compare("zoom 1.0", _legacy_image, _capture("rendered_zoom_1_0"), 0.035, 1)
			_camera.zoom = Vector2(0.2, 0.2)
			_show_rendered(false)
			_stage = 2
			_say("framebuffer stage 3: legacy Player at zoom 0.2")
		2:
			_legacy_image = _capture("legacy_zoom_0_2")
			_show_rendered(true)
			_stage = 3
			_say("framebuffer stage 4: RenderWorld Player at zoom 0.2")
		3:
			_compare("zoom 0.2", _legacy_image, _capture("rendered_zoom_0_2"), 0.12, 2)
			_finish()


func _actor_buffer(body_transform: Transform2D) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(GPU_STRIDE)
	buffer[0] = body_transform.x.x
	buffer[1] = body_transform.x.y
	buffer[3] = body_transform.origin.x
	buffer[4] = body_transform.y.x
	buffer[5] = body_transform.y.y
	buffer[7] = body_transform.origin.y
	buffer[8] = 1.0
	buffer[9] = 1.0
	buffer[10] = 1.0
	buffer[11] = 1.0
	buffer[12] = PLAYER_IDLE_DESCRIPTOR_ID
	buffer[13] = 0.0
	buffer[14] = 0.0
	buffer[15] = 1.0
	return buffer


func _show_rendered(enabled: bool) -> void:
	_legacy.visible = not enabled
	_rendered.visible = enabled


func _capture(label: String) -> Image:
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		_fail("%s framebuffer readback returned no image" % label)
		return null
	image.save_png("user://player_world_render_%s.png" % label)
	return image


func _compare(
		label: String,
		legacy_image: Image,
		rendered_image: Image,
		max_diff_ratio: float,
		max_bounds_delta: int,
) -> void:
	if legacy_image == null or rendered_image == null:
		_fail("%s has a missing framebuffer" % label)
		return
	var width: int = mini(legacy_image.get_width(), rendered_image.get_width())
	var height: int = mini(legacy_image.get_height(), rendered_image.get_height())
	var center := Vector2i(width / 2, height / 2)
	var sample := Rect2i(
		maxi(0, center.x - SAMPLE_HALF_EXTENT),
		maxi(0, center.y - SAMPLE_HALF_EXTENT),
		mini(width, center.x + SAMPLE_HALF_EXTENT) - maxi(0, center.x - SAMPLE_HALF_EXTENT),
		mini(height, center.y + SAMPLE_HALF_EXTENT) - maxi(0, center.y - SAMPLE_HALF_EXTENT),
	)
	var background: Color = legacy_image.get_pixel(0, 0)
	var legacy_count: int = 0
	var rendered_count: int = 0
	var union_count: int = 0
	var different_count: int = 0
	var legacy_bounds := Rect2i()
	var rendered_bounds := Rect2i()
	for y: int in range(sample.position.y, sample.end.y):
		for x: int in range(sample.position.x, sample.end.x):
			var legacy_color: Color = legacy_image.get_pixel(x, y)
			var rendered_color: Color = rendered_image.get_pixel(x, y)
			var legacy_authored: bool = _color_distance(legacy_color, background) > COLOR_EPSILON
			var rendered_authored: bool = _color_distance(rendered_color, background) > COLOR_EPSILON
			if legacy_authored:
				legacy_count += 1
				legacy_bounds = _include_pixel(legacy_bounds, Vector2i(x, y))
			if rendered_authored:
				rendered_count += 1
				rendered_bounds = _include_pixel(rendered_bounds, Vector2i(x, y))
			if legacy_authored or rendered_authored:
				union_count += 1
				if _color_distance(legacy_color, rendered_color) > PIXEL_DIFF_EPSILON:
					different_count += 1
	var diff_ratio: float = float(different_count) / maxf(float(union_count), 1.0)
	var count_delta_ratio: float = absf(float(legacy_count - rendered_count)) \
			/ maxf(float(legacy_count), 1.0)
	var bounds_delta: int = _bounds_delta(legacy_bounds, rendered_bounds)
	_say(
		"%s: legacy=%d rendered=%d diff=%.4f count_delta=%.4f bounds_delta=%d"
		% [label, legacy_count, rendered_count, diff_ratio, count_delta_ratio, bounds_delta],
	)
	if legacy_count <= 0 or rendered_count <= 0:
		_fail("%s did not draw authored Player pixels" % label)
	if diff_ratio > max_diff_ratio:
		_fail("%s pixel difference %.4f exceeds %.4f" % [label, diff_ratio, max_diff_ratio])
	if count_delta_ratio > max_diff_ratio:
		_fail("%s authored-pixel count delta %.4f exceeds %.4f" % [label, count_delta_ratio, max_diff_ratio])
	if bounds_delta > max_bounds_delta:
		_fail("%s silhouette bounds delta %d exceeds %d" % [label, bounds_delta, max_bounds_delta])


func _include_pixel(bounds: Rect2i, pixel: Vector2i) -> Rect2i:
	if bounds.size == Vector2i.ZERO:
		return Rect2i(pixel, Vector2i.ONE)
	return bounds.merge(Rect2i(pixel, Vector2i.ONE))


func _bounds_delta(a: Rect2i, b: Rect2i) -> int:
	if a.size == Vector2i.ZERO or b.size == Vector2i.ZERO:
		return 1 << 20
	return maxi(
		maxi(absi(a.position.x - b.position.x), absi(a.position.y - b.position.y)),
		maxi(absi(a.end.x - b.end.x), absi(a.end.y - b.end.y)),
	)


func _color_distance(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


func _fail(message: String) -> void:
	_failed = true
	_say("FAIL: %s" % message)


func _finish() -> void:
	set_process(false)
	var verdict: String = "PASS: Player authored pixels preserved by RenderWorld."
	var exit_code: int = 0
	if _failed:
		verdict = "FAIL: Player RenderWorld pixel parity regression."
		exit_code = 1
	elif _skipped:
		verdict = "SKIP: Player RenderWorld pixel parity not verified (no framebuffer)."
		exit_code = SKIP_EXIT_CODE
	_say(verdict)
	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report != null:
		report.store_string("\n".join(_lines) + "\n")
		report.close()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _say(line: String) -> void:
	print(line)
	_lines.append(line)
