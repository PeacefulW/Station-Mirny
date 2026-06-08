extends Node2D

const GRASS_WIND_SHADER = preload("res://assets/shaders/dev_grass_wind.gdshader")
const DENSE_GRASS_GROUND_TEXTURE: Texture2D = preload("res://assets/textures/world/biomes/plains/ground/dry_grass_dense_albedo.png")

const ATLAS_COLUMNS: int = 4
const ATLAS_ROWS: int = 4
const ATLAS_FRAME_COUNT: int = ATLAS_COLUMNS * ATLAS_ROWS
const FRAME_SIZE: Vector2i = Vector2i(72, 104)
const FIELD_RECT := Rect2(Vector2(-980.0, -560.0), Vector2(1960.0, 1120.0))
const CAMERA_ZOOM_STEP: float = 1.12
const BASE_SEED: int = 612917

const DENSITY_PRESETS: Array[Dictionary] = [
	{
		"name": "редкая",
		"low": 1800,
		"mid": 900,
		"tall": 320,
	},
	{
		"name": "густая",
		"low": 4200,
		"mid": 2600,
		"tall": 980,
	},
	{
		"name": "очень густая",
		"low": 7200,
		"mid": 4600,
		"tall": 1700,
	},
]

var _rng := RandomNumberGenerator.new()
var _camera: Camera2D = null
var _label: Label = null
var _base_sprite: Sprite2D = null
var _atlas_texture: Texture2D = null
var _grass_layers: Array[MultiMeshInstance2D] = []
var _grass_materials: Array[ShaderMaterial] = []
var _density_index: int = 1
var _wind_time: float = 0.0
var _wind_speed: float = 0.85
var _wind_amplitude_px: float = 2.6
var _wind_angle_deg: float = -13.0
var _grass_height_scale: float = 1.0
var _wind_running: bool = true
var _seed_offset: int = 0

func _ready() -> void:
	_rng.seed = BASE_SEED
	_build_background()
	_atlas_texture = _build_grass_atlas()
	_build_grass_layers()
	_build_camera()
	_build_hud()
	_rebuild_grass()
	_update_hud()

func _process(delta: float) -> void:
	if _wind_running:
		_wind_time += delta
	_apply_wind()
	_update_camera_pan(delta)
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.keycode:
			KEY_1:
				_set_density(0)
			KEY_2:
				_set_density(1)
			KEY_3:
				_set_density(2)
			KEY_Q:
				_wind_speed = maxf(0.10, _wind_speed - 0.12)
			KEY_E:
				_wind_speed = minf(2.80, _wind_speed + 0.12)
			KEY_A:
				_wind_angle_deg -= 8.0
			KEY_D:
				_wind_angle_deg += 8.0
			KEY_Z:
				_grass_height_scale = maxf(0.45, _grass_height_scale - 0.10)
				_rebuild_grass()
			KEY_X:
				_grass_height_scale = minf(1.85, _grass_height_scale + 0.10)
				_rebuild_grass()
			KEY_C:
				_grass_height_scale = 1.0
				_rebuild_grass()
			KEY_SPACE:
				_wind_running = not _wind_running
			KEY_R:
				_seed_offset += 1
				_rebuild_grass()
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_camera.zoom *= CAMERA_ZOOM_STEP
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_camera.zoom /= CAMERA_ZOOM_STEP

func _build_background() -> void:
	_base_sprite = Sprite2D.new()
	_base_sprite.name = "DenseDryGrassUnderlay"
	_base_sprite.texture = DENSE_GRASS_GROUND_TEXTURE
	_base_sprite.region_enabled = true
	_base_sprite.region_rect = Rect2(Vector2.ZERO, FIELD_RECT.size)
	_base_sprite.position = FIELD_RECT.get_center()
	_base_sprite.z_index = -20
	_base_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_base_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(_base_sprite)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.enabled = true
	_camera.zoom = Vector2(0.95, 0.95)
	add_child(_camera)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Hud"
	add_child(canvas)
	_label = Label.new()
	_label.name = "InfoLabel"
	_label.offset_left = 16.0
	_label.offset_top = 16.0
	_label.offset_right = 760.0
	_label.offset_bottom = 220.0
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.84, 0.92, 0.86, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_label)

func _build_grass_layers() -> void:
	for layer_index: int in range(3):
		var layer := MultiMeshInstance2D.new()
		layer.name = ["GrassLowBatch", "GrassMidBatch", "GrassTallBatch"][layer_index]
		layer.texture = _atlas_texture
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		layer.z_index = layer_index
		var material := ShaderMaterial.new()
		material.shader = GRASS_WIND_SHADER
		material.set_shader_parameter("atlas_columns", float(ATLAS_COLUMNS))
		material.set_shader_parameter("atlas_rows", float(ATLAS_ROWS))
		material.set_shader_parameter("atlas_frame_count", float(ATLAS_FRAME_COUNT))
		layer.material = material
		_grass_layers.append(layer)
		_grass_materials.append(material)
		add_child(layer)

func _rebuild_grass() -> void:
	var preset: Dictionary = DENSITY_PRESETS[_density_index]
	_rng.seed = BASE_SEED + _seed_offset * 1009
	_apply_layer_instances(
		0,
		int(preset["low"]),
		_scaled_grass_size(Vector2(38.0, 48.0)),
		_scaled_grass_size(Vector2(66.0, 78.0)),
		Color(0.95, 0.96, 0.82, 0.86),
		0.72
	)
	_apply_layer_instances(
		1,
		int(preset["mid"]),
		_scaled_grass_size(Vector2(48.0, 68.0)),
		_scaled_grass_size(Vector2(82.0, 104.0)),
		Color(1.08, 1.10, 0.92, 0.94),
		1.00
	)
	_apply_layer_instances(
		2,
		int(preset["tall"]),
		_scaled_grass_size(Vector2(58.0, 92.0)),
		_scaled_grass_size(Vector2(100.0, 144.0)),
		Color(1.18, 1.22, 1.00, 0.98),
		1.18
	)

func _scaled_grass_size(size: Vector2) -> Vector2:
	return Vector2(size.x, size.y * _grass_height_scale)

func _apply_layer_instances(
	layer_index: int,
	instance_count: int,
	min_size: Vector2,
	max_size: Vector2,
	tint_base: Color,
	wind_scale: float
) -> void:
	var multimesh := MultiMesh.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.instance_count = instance_count
	multimesh.visible_instance_count = instance_count
	for i: int in range(instance_count):
		var position := _random_grass_position()
		var size := Vector2(
			_rng.randf_range(min_size.x, max_size.x),
			_rng.randf_range(min_size.y, max_size.y)
		)
		var rotation := deg_to_rad(_rng.randf_range(-8.0, 8.0))
		var transform := Transform2D(rotation, position)
		transform.x *= size.x
		transform.y *= size.y
		multimesh.set_instance_transform_2d(i, transform)
		var frame_index: int = _rng.randi_range(0, ATLAS_FRAME_COUNT - 1)
		var tint: float = clampf(_rng.randf_range(0.80, 1.16) * tint_base.g, 0.50, 1.35)
		var phase: float = _rng.randf()
		var alpha: float = clampf(_rng.randf_range(tint_base.a - 0.10, tint_base.a + 0.06), 0.0, 1.0)
		multimesh.set_instance_color(i, Color(
			float(frame_index) / 255.0,
			tint,
			phase,
			alpha
		))
	_grass_layers[layer_index].multimesh = multimesh
	_grass_materials[layer_index].set_shader_parameter("wind_strength_px", _wind_amplitude_px * wind_scale)

func _random_grass_position() -> Vector2:
	var x := _rng.randf_range(FIELD_RECT.position.x, FIELD_RECT.end.x)
	var y := _rng.randf_range(FIELD_RECT.position.y, FIELD_RECT.end.y)
	var wave := sin((x + y * 0.38) / 190.0) * 0.5 + sin((x * 0.21 - y) / 310.0) * 0.5
	if wave < -0.62 and _rng.randf() < 0.62:
		x += _rng.randf_range(-28.0, 28.0)
		y += _rng.randf_range(-28.0, 28.0)
	return Vector2(x, y)

func _apply_wind() -> void:
	var direction := Vector2(cos(deg_to_rad(_wind_angle_deg)), sin(deg_to_rad(_wind_angle_deg))).normalized()
	for layer_index: int in range(_grass_materials.size()):
		var material: ShaderMaterial = _grass_materials[layer_index]
		material.set_shader_parameter("wind_time", _wind_time)
		material.set_shader_parameter("wind_speed", _wind_speed)
		material.set_shader_parameter("wind_direction", direction)
		material.set_shader_parameter(
			"wind_strength_px",
			_wind_amplitude_px * [0.72, 1.0, 1.18][layer_index]
		)

func _update_camera_pan(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.y += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if move != Vector2.ZERO:
		_camera.position += move.normalized() * 520.0 * delta / maxf(_camera.zoom.x, 0.1)

func _set_density(index: int) -> void:
	_density_index = clampi(index, 0, DENSITY_PRESETS.size() - 1)
	_rebuild_grass()

func _update_hud() -> void:
	if _label == null:
		return
	var preset: Dictionary = DENSITY_PRESETS[_density_index]
	var total_count: int = 0
	for layer: MultiMeshInstance2D in _grass_layers:
		if layer.multimesh != null:
			total_count += layer.multimesh.instance_count
	_label.text = "\n".join([
		"Grass wind dev scene",
		"visual-only | MultiMeshInstance2D | runtime world не подключён",
		"Плотность: %s (%d пучков)" % [str(preset["name"]), total_count],
		"Высота травы: %.2fx" % _grass_height_scale,
		"Ветер: скорость %.2fx, амплитуда %.1f px, угол %.0f°, %s" % [_wind_speed, _wind_amplitude_px, _wind_angle_deg, "идёт" if _wind_running else "пауза"],
		"1/2/3 — плотность | Z/X — высота | C — сброс высоты | Q/E — скорость ветра | A/D — угол и панорама | Space — пауза | R — seed | колесо — zoom | WASD — камера",
	])

func _build_grass_atlas() -> Texture2D:
	var atlas_size := Vector2i(FRAME_SIZE.x * ATLAS_COLUMNS, FRAME_SIZE.y * ATLAS_ROWS)
	var image := Image.create(atlas_size.x, atlas_size.y, true, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var atlas_rng := RandomNumberGenerator.new()
	atlas_rng.seed = BASE_SEED + 451
	for frame_index: int in range(ATLAS_FRAME_COUNT):
		var frame_origin := Vector2i(
			(frame_index % ATLAS_COLUMNS) * FRAME_SIZE.x,
			(frame_index / ATLAS_COLUMNS) * FRAME_SIZE.y
		)
		_paint_grass_frame(image, frame_origin, atlas_rng, frame_index)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _paint_grass_frame(image: Image, origin: Vector2i, atlas_rng: RandomNumberGenerator, frame_index: int) -> void:
	var blade_count: int = atlas_rng.randi_range(11, 22)
	for i: int in range(blade_count):
		var root := Vector2(
			float(origin.x) + FRAME_SIZE.x * atlas_rng.randf_range(0.18, 0.82),
			float(origin.y) + FRAME_SIZE.y * atlas_rng.randf_range(0.80, 0.98)
		)
		var lean := atlas_rng.randf_range(-22.0, 22.0) + sin(float(frame_index) * 1.7 + float(i)) * 6.0
		var tip := Vector2(
			root.x + lean,
			float(origin.y) + FRAME_SIZE.y * atlas_rng.randf_range(0.04, 0.46)
		)
		var mid := root.lerp(tip, atlas_rng.randf_range(0.42, 0.64)) + Vector2(atlas_rng.randf_range(-8.0, 8.0), atlas_rng.randf_range(-4.0, 4.0))
		var width := atlas_rng.randf_range(2.0, 4.8)
		var hue := atlas_rng.randf_range(-0.020, 0.018)
		var color := Color.from_hsv(0.075 + hue, atlas_rng.randf_range(0.76, 0.96), atlas_rng.randf_range(0.72, 1.00), atlas_rng.randf_range(0.72, 0.96))
		if i % 5 == 0:
			color = Color.from_hsv(0.060 + hue, 0.90, 0.52, 0.72)
		_paint_blade_segment(image, root, mid, width, color)
		_paint_blade_segment(image, mid, tip, width * 0.62, color.lightened(0.08))

func _paint_blade_segment(image: Image, start: Vector2, finish: Vector2, width: float, color: Color) -> void:
	var min_x: int = clampi(floori(minf(start.x, finish.x) - width - 2.0), 0, image.get_width() - 1)
	var max_x: int = clampi(ceili(maxf(start.x, finish.x) + width + 2.0), 0, image.get_width() - 1)
	var min_y: int = clampi(floori(minf(start.y, finish.y) - width - 2.0), 0, image.get_height() - 1)
	var max_y: int = clampi(ceili(maxf(start.y, finish.y) + width + 2.0), 0, image.get_height() - 1)
	var segment := finish - start
	var segment_len_sq := maxf(segment.length_squared(), 0.0001)
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var t := clampf((p - start).dot(segment) / segment_len_sq, 0.0, 1.0)
			var closest := start + segment * t
			var radius := width * (1.0 - t) * (0.34 + 0.66 * sin(t * PI))
			var dist := p.distance_to(closest)
			var alpha := 1.0 - smoothstep(maxf(0.15, radius - 0.80), radius + 0.95, dist)
			if alpha <= 0.001:
				continue
			_blend_pixel(image, x, y, Color(color.r, color.g, color.b, color.a * alpha))

func _blend_pixel(image: Image, x: int, y: int, src: Color) -> void:
	var dst := image.get_pixel(x, y)
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a <= 0.0001:
		return
	var out_rgb := (Vector3(src.r, src.g, src.b) * src.a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / out_a
	image.set_pixel(x, y, Color(out_rgb.x, out_rgb.y, out_rgb.z, out_a))
