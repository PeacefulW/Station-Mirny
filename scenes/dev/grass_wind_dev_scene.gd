extends Node2D
## Dev-песочница травы и ветра. Первый потребитель WindRuntime:
## сцена НЕ владеет ветром и не рассылает wind-параметры в материалы —
## шейдер читает wind_* global uniforms, которые пишет WindRuntime.
## Дев-управление идёт через debug override API WindRuntime.
## Контракт: docs/02_system_specs/world/wind_and_grass_scatter_presentation.md

const GRASS_WIND_SHADER = preload("res://assets/shaders/grass_scatter_batch.gdshader")
const DENSE_GRASS_GROUND_TEXTURE: Texture2D = preload("res://assets/textures/world/biomes/plains/ground/dry_grass_dense_albedo.png")
const GRASS_TUFT_ATLAS: Texture2D = preload("res://assets/textures/world/biomes/plains/flora/grass_tuft_atlas.png")
const WorldVisualWindProfile = preload("res://core/systems/world/world_visual_wind_profile.gd")

const ATLAS_COLUMNS: int = 4
# 4 ряда сухой палитры + 4 ряда биополя (см. GrassAtlasPainter); песочница
# намеренно мешает оба банка для наглядного тюнинга атласа.
const ATLAS_ROWS: int = 8
const ATLAS_FRAME_COUNT: int = ATLAS_COLUMNS * ATLAS_ROWS
const FIELD_RECT := Rect2(Vector2(-980.0, -560.0), Vector2(1960.0, 1120.0))
const CAMERA_ZOOM_STEP: float = 1.12
const BASE_SEED: int = 612917
const BASE_WIND_SWAY_FRACTION: float = 0.085
const BASE_STORM_LEAN_FRACTION: float = 0.35
const WIND_LAYER_SWAY_SCALE: Array[float] = [0.72, 1.0, 1.18]
const STRENGTH_OVERRIDE_STEP: float = 0.1
const DIRECTION_OVERRIDE_STEP_DEG: float = 8.0
const DEFAULT_GRASS_HEIGHT_SCALE: float = 0.7

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
var _grass_height_scale: float = DEFAULT_GRASS_HEIGHT_SCALE
var _seed_offset: int = 0


func _ready() -> void:
	# Сцена живёт в паузе (ввод/HUD), чтобы проверять контракт
	# «пауза игры останавливает ветер»: WindRuntime паузится с деревом.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = BASE_SEED
	_build_background()
	# Атлас — экспортированный PNG-ассет (1:1 с рантаймом); runtime-bake
	# запрещён спекой. Перегенерация: tools/grass_atlas_export.gd.
	_atlas_texture = GRASS_TUFT_ATLAS
	_build_grass_layers()
	_build_camera()
	_build_hud()
	_rebuild_grass()
	_update_hud()


func _process(delta: float) -> void:
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
			KEY_UP:
				WindRuntime.set_debug_strength_override(
					WindRuntime.get_wind_strength() + STRENGTH_OVERRIDE_STEP,
				)
			KEY_DOWN:
				WindRuntime.set_debug_strength_override(
					WindRuntime.get_wind_strength() - STRENGTH_OVERRIDE_STEP,
				)
			KEY_LEFT:
				WindRuntime.set_debug_direction_override_deg(
					WindRuntime.get_wind_direction_deg() - DIRECTION_OVERRIDE_STEP_DEG,
				)
			KEY_RIGHT:
				WindRuntime.set_debug_direction_override_deg(
					WindRuntime.get_wind_direction_deg() + DIRECTION_OVERRIDE_STEP_DEG,
				)
			KEY_O:
				WindRuntime.clear_debug_wind_override()
			KEY_Z:
				_grass_height_scale = maxf(0.45, _grass_height_scale - 0.10)
				_rebuild_grass()
			KEY_X:
				_grass_height_scale = minf(1.85, _grass_height_scale + 0.10)
				_rebuild_grass()
			KEY_C:
				_grass_height_scale = DEFAULT_GRASS_HEIGHT_SCALE
				_rebuild_grass()
			KEY_SPACE:
				get_tree().paused = not get_tree().paused
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
		# Ветровой отклик слоя задаётся один раз: per-frame рассылок нет,
		# динамика приходит только через wind_* global uniforms.
		material.set_shader_parameter(
			"wind_sway_fraction",
			BASE_WIND_SWAY_FRACTION * WIND_LAYER_SWAY_SCALE[layer_index],
		)
		material.set_shader_parameter(
			"storm_lean_fraction",
			BASE_STORM_LEAN_FRACTION * WIND_LAYER_SWAY_SCALE[layer_index],
		)
		material.set_shader_parameter(
			"gust_field_scale_px",
			WorldVisualWindProfile.GUST_FIELD_SCALE_PX,
		)
		material.set_shader_parameter(
			"gust_field_anisotropy",
			WorldVisualWindProfile.GUST_FIELD_ANISOTROPY,
		)
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
	)
	_apply_layer_instances(
		1,
		int(preset["mid"]),
		_scaled_grass_size(Vector2(48.0, 68.0)),
		_scaled_grass_size(Vector2(82.0, 104.0)),
		Color(1.08, 1.10, 0.92, 0.94),
	)
	_apply_layer_instances(
		2,
		int(preset["tall"]),
		_scaled_grass_size(Vector2(58.0, 92.0)),
		_scaled_grass_size(Vector2(100.0, 144.0)),
		Color(1.18, 1.22, 1.00, 0.98),
	)


func _scaled_grass_size(size: Vector2) -> Vector2:
	return Vector2(size.x, size.y * _grass_height_scale)


func _apply_layer_instances(
		layer_index: int,
		instance_count: int,
		min_size: Vector2,
		max_size: Vector2,
		tint_base: Color,
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
			_rng.randf_range(min_size.y, max_size.y),
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
		multimesh.set_instance_color(
			i,
			Color(
				float(frame_index) / 255.0,
				tint,
				phase,
				alpha,
			),
		)
	_grass_layers[layer_index].multimesh = multimesh


func _random_grass_position() -> Vector2:
	var x := _rng.randf_range(FIELD_RECT.position.x, FIELD_RECT.end.x)
	var y := _rng.randf_range(FIELD_RECT.position.y, FIELD_RECT.end.y)
	var wave := sin((x + y * 0.38) / 190.0) * 0.5 + sin((x * 0.21 - y) / 310.0) * 0.5
	if wave < -0.62 and _rng.randf() < 0.62:
		x += _rng.randf_range(-28.0, 28.0)
		y += _rng.randf_range(-28.0, 28.0)
	return Vector2(x, y)


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
	var override_state: String = "override" if WindRuntime.has_debug_wind_override() else "профиль"
	_label.text = "\n".join(
		[
			"Grass wind dev scene — потребитель WindRuntime (wind_* global uniforms)",
			"Плотность: %s (%d пучков) | Высота травы: %.2fx" % [str(preset["name"]), total_count, _grass_height_scale],
			"Ветер [%s]: сила %.2f, угол %.0f°, время %.1fс, %s" % [
				override_state,
				WindRuntime.get_wind_strength(),
				WindRuntime.get_wind_direction_deg(),
				WindRuntime.get_wind_time(),
				"пауза" if get_tree().paused else "идёт",
			],
			"1/2/3 — плотность | Z/X/C — высота | стрелки ↑↓ — сила | ←→ — угол | O — сброс override",
			"Space — пауза дерева | R — seed | колесо — zoom | WASD — камера",
		],
	)
