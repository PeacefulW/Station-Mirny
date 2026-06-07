extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

const TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_top_albedo.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/mountain/rock_face_albedo.png"
const MASK_WIDTH: int = 768
const MASK_HEIGHT: int = 640
const MASK_STEP_PX: float = 1.0
const MOUNTAIN_CENTER: Vector2 = Vector2(390.0, 320.0)
const CAMERA_ZOOM_STEP: float = 1.12

var _chunk_view: ChunkView = null
var _camera: Camera2D = null
var _label: Label = null
var _preview_hour: float = WorldVisualLightingProfile.DEFAULT_PREVIEW_HOUR
var _auto_sun: bool = true
var _shadow_opacity_scale: float = 1.0

func _ready() -> void:
	WorldTileSetFactory.bootstrap()
	_build_background()
	_build_mountain()
	_build_camera()
	_build_hud()
	_apply_sun()
	queue_redraw()

func _process(delta: float) -> void:
	if _auto_sun:
		_preview_hour = fposmod(_preview_hour + delta * 1.2, WorldVisualLightingProfile.HOURS_PER_DAY)
	_apply_sun()
	_update_label()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.keycode:
			KEY_SPACE:
				_auto_sun = not _auto_sun
			KEY_Q:
				_auto_sun = false
				_preview_hour = fposmod(_preview_hour - 0.5, WorldVisualLightingProfile.HOURS_PER_DAY)
			KEY_E:
				_auto_sun = false
				_preview_hour = fposmod(_preview_hour + 0.5, WorldVisualLightingProfile.HOURS_PER_DAY)
			KEY_Z:
				_shadow_opacity_scale = maxf(0.0, _shadow_opacity_scale - 0.10)
			KEY_X:
				_shadow_opacity_scale = minf(1.60, _shadow_opacity_scale + 0.10)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_camera.zoom *= CAMERA_ZOOM_STEP
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_camera.zoom /= CAMERA_ZOOM_STEP

func _draw() -> void:
	var sun_angle_deg: float = WorldVisualLightingProfile.light_angle_deg_for_hour(_preview_hour)
	var light_dir := Vector2(cos(deg_to_rad(sun_angle_deg)), sin(deg_to_rad(sun_angle_deg))).normalized()
	var start := MOUNTAIN_CENTER - light_dir * 210.0
	var finish := MOUNTAIN_CENTER - light_dir * 82.0
	draw_line(start, finish, Color(1.0, 0.78, 0.28, 0.92), 4.0, true)
	draw_circle(start, 14.0, Color(1.0, 0.70, 0.20, 0.95))

func _build_background() -> void:
	var ground := Polygon2D.new()
	ground.name = "GroundBackdrop"
	ground.polygon = PackedVector2Array([
		Vector2(-260.0, -180.0),
		Vector2(1180.0, -180.0),
		Vector2(1180.0, 900.0),
		Vector2(-260.0, 900.0),
	])
	ground.color = Color(0.20, 0.32, 0.19, 1.0)
	ground.z_index = -30
	add_child(ground)
	for i: int in range(80):
		var dot := ColorRect.new()
		dot.color = Color(0.28, 0.42, 0.25, 0.18)
		dot.size = Vector2(7.0 + float(i % 5), 7.0 + float((i * 3) % 5))
		dot.position = Vector2(
			-160.0 + fposmod(float(i * 173), 1280.0),
			-80.0 + fposmod(float(i * 97), 880.0)
		)
		dot.z_index = -29
		add_child(dot)

func _build_mountain() -> void:
	var top_texture := load(TOP_TEXTURE_PATH) as Texture2D
	var face_texture := load(FACE_TEXTURE_PATH) as Texture2D
	assert(top_texture != null, "Missing mountain top texture: %s" % TOP_TEXTURE_PATH)
	assert(face_texture != null, "Missing mountain face texture: %s" % FACE_TEXTURE_PATH)

	_chunk_view = ChunkView.new()
	_chunk_view.name = "RuntimeChunkViewSmallMountain"
	_chunk_view.configure(Vector2i.ZERO)
	_chunk_view.set_mountain_tile_visuals_enabled(false)
	add_child(_chunk_view)

	var mask_data: Dictionary = _build_small_mountain_mask()
	var result: Dictionary = {
		"success": true,
		"ready": true,
		"native": true,
		"top_mask": mask_data.get("top_mask", PackedByteArray()),
		"top_mask_width": MASK_WIDTH,
		"top_mask_height": MASK_HEIGHT,
		"top_mask_origin_world": Vector2.ZERO,
		"top_mask_step_px": MASK_STEP_PX,
		"top_texture_scale": 0.70,
		"hit_mask": mask_data.get("hit_mask", PackedByteArray()),
		"hit_mask_width": MASK_WIDTH,
		"hit_mask_height": MASK_HEIGHT,
		"hit_mask_origin_world": Vector2.ZERO,
		"hit_mask_step_px": MASK_STEP_PX,
		"hit_mask_solid_pixel_count": int(mask_data.get("solid_pixels", 0)),
		"render_origin_world": Vector2.ZERO,
		"render_size_world": Vector2(MASK_WIDTH, MASK_HEIGHT),
		"mountain_tile_count": 18,
		"top_pixel_count": int(mask_data.get("solid_pixels", 0)),
		"face_pixel_count": 0,
		"rim_pixel_count": 0,
		"image_width": MASK_WIDTH,
		"image_height": MASK_HEIGHT,
		"runtime_emit_top_mask": true,
		"runtime_edge_overlay_only": true,
		"runtime_visual_clip_to_target_rect": true,
	}
	_chunk_view.apply_mountain_render_page(result, top_texture, face_texture)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.enabled = true
	_camera.position = MOUNTAIN_CENTER + Vector2(0.0, 40.0)
	_camera.zoom = Vector2(1.15, 1.15)
	add_child(_camera)
	_camera.make_current()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	_label = Label.new()
	_label.offset_left = 16.0
	_label.offset_top = 16.0
	_label.offset_right = 720.0
	_label.offset_bottom = 150.0
	_label.add_theme_color_override("font_color", Color(0.84, 0.90, 0.94, 1.0))
	_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(_label)
	_update_label()

func _build_small_mountain_mask() -> Dictionary:
	var top_mask := PackedByteArray()
	var hit_mask := PackedByteArray()
	top_mask.resize(MASK_WIDTH * MASK_HEIGHT)
	hit_mask.resize(MASK_WIDTH * MASK_HEIGHT)
	var solid_pixels: int = 0
	for y: int in range(MASK_HEIGHT):
		for x: int in range(MASK_WIDTH):
			var p := Vector2(float(x), float(y))
			var sdf: float = _mountain_sdf(p)
			sdf += (_fbm(p / 82.0) - 0.5) * 20.0
			sdf += (_fbm(p / 31.0 + Vector2(19.0, -7.0)) - 0.5) * 7.0
			var value: int = int(round(255.0 * (1.0 - smoothstep(-14.0, 14.0, sdf))))
			var index: int = y * MASK_WIDTH + x
			top_mask[index] = clampi(value, 0, 255)
			if value >= 112:
				hit_mask[index] = 1
				solid_pixels += 1
	return {
		"top_mask": top_mask,
		"hit_mask": hit_mask,
		"solid_pixels": solid_pixels,
	}

func _mountain_sdf(p: Vector2) -> float:
	var d: float = 999999.0
	d = minf(d, _ellipse_sdf(p, Vector2(300.0, 300.0), Vector2(135.0, 96.0)))
	d = minf(d, _ellipse_sdf(p, Vector2(425.0, 278.0), Vector2(178.0, 124.0)))
	d = minf(d, _ellipse_sdf(p, Vector2(520.0, 350.0), Vector2(124.0, 94.0)))
	d = minf(d, _ellipse_sdf(p, Vector2(342.0, 418.0), Vector2(132.0, 82.0)))
	d = minf(d, _ellipse_sdf(p, Vector2(455.0, 418.0), Vector2(112.0, 74.0)))
	d = minf(d, _ellipse_sdf(p, Vector2(575.0, 250.0), Vector2(66.0, 58.0)))
	d = maxf(d, -_ellipse_sdf(p, Vector2(280.0, 365.0), Vector2(62.0, 54.0)))
	return d

func _ellipse_sdf(p: Vector2, center: Vector2, radius: Vector2) -> float:
	var q := Vector2((p.x - center.x) / radius.x, (p.y - center.y) / radius.y)
	return (q.length() - 1.0) * minf(radius.x, radius.y)

func _fbm(p: Vector2) -> float:
	var value: float = 0.0
	var amp: float = 0.55
	var total: float = 0.0
	for i: int in range(4):
		value += _value_noise(p) * amp
		total += amp
		p = p * 2.03 + Vector2(17.0 + float(i) * 3.0, -11.0)
		amp *= 0.48
	return value / maxf(total, 0.0001)

func _value_noise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	var u := Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var a: float = _hash(i)
	var b: float = _hash(i + Vector2(1.0, 0.0))
	var c: float = _hash(i + Vector2(0.0, 1.0))
	var d: float = _hash(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)

func _hash(p: Vector2) -> float:
	return fposmod(sin(p.x * 127.1 + p.y * 311.7) * 43758.5453123, 1.0)

func _apply_sun() -> void:
	if _chunk_view == null:
		return
	var sun_progress: float = WorldVisualLightingProfile.sun_progress_for_hour(_preview_hour)
	var low_sun: float = WorldVisualLightingProfile.low_sun_for_progress(sun_progress)
	var sun_angle_deg: float = WorldVisualLightingProfile.light_angle_deg_for_hour(_preview_hour)
	_chunk_view.apply_sun_lighting(
		sun_angle_deg,
		WorldVisualLightingProfile.shadow_length_px_for_low_sun(low_sun),
		WorldVisualLightingProfile.shadow_opacity_for_low_sun_and_hour(low_sun, _preview_hour) * _shadow_opacity_scale,
		WorldVisualLightingProfile.shadow_softness_px_for_low_sun(low_sun)
	)

func _update_label() -> void:
	if _label == null:
		return
	var sun_angle_deg: float = WorldVisualLightingProfile.light_angle_deg_for_hour(_preview_hour)
	var sun_progress: float = WorldVisualLightingProfile.sun_progress_for_hour(_preview_hour)
	var low_sun: float = WorldVisualLightingProfile.low_sun_for_progress(sun_progress)
	var runtime_opacity: float = WorldVisualLightingProfile.shadow_opacity_for_low_sun_and_hour(low_sun, _preview_hour)
	_label.text = "Тест маленькой 2D-горы\nЧас: %.1f  солнце: %.1f deg  авто=%s\nТень runtime=%.2f  множитель=%.1f\nSpace авто | Q/E час | Z/X сила тени | колесо зум" % [
		_preview_hour,
		sun_angle_deg,
		str(_auto_sun),
		runtime_opacity,
		_shadow_opacity_scale,
	]
