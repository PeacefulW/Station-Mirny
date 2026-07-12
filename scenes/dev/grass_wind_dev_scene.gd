extends Node2D
## Dev-песочница травы и ветра. Первый потребитель WindRuntime:
## сцена НЕ владеет ветром и не рассылает wind-параметры в материалы —
## шейдер читает wind_* global uniforms, которые пишет WindRuntime.
## Дев-управление идёт через debug override API WindRuntime.
##
## Тюнинг-режим: сцена читает sampling_params из
## grass_scatter_material_set.tres, зеркалит нативную математику размещения
## (grass_scatter.cpp: acceptance * density_scale, lerp размеров, банки по
## orange-полю) и даёт крутить параметры вживую. P копирует готовый блок
## sampling_params в буфер обмена для вставки в .tres.
## Контракт: docs/02_system_specs/world/wind_and_grass_scatter_presentation.md

const GRASS_WIND_SHADER = preload("res://assets/shaders/grass_scatter_batch.gdshader")
const DENSE_GRASS_GROUND_TEXTURE: Texture2D = preload("res://assets/textures/world/biomes/plains/ground/dry_grass_dense_albedo.png")
const GRASS_TUFT_ATLAS: Texture2D = preload("res://assets/textures/world/biomes/plains/flora/grass_tuft_atlas.png")
const GRASS_TUFT_SHADOW_ATLAS: Texture2D = preload("res://assets/textures/world/biomes/plains/flora/grass_tuft_shadow_atlas.png")
const WorldVisualWindProfile = preload("res://core/systems/world/world_visual_wind_profile.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")

const MATERIAL_SET_PATH: String = "res://data/terrain/material_sets/grass_scatter_material_set.tres"
const PROTOTYPE_SNOW_OVERLAY_ATLAS_PATH: String = "res://artifacts/blender_grass_tufts/grass_tuft_snow_overlay_atlas.png"

const FIELD_RECT := Rect2(Vector2(-980.0, -560.0), Vector2(1960.0, 1120.0))
# Зеркало native: chunk 1024 px / candidate_grid_side 80 (см. grass_scatter.cpp).
const CANDIDATE_CELL_PX: float = 12.8
# Синтетическое биополе: оранжевое пятно справа, чтобы orange_* параметры
# было видно рядом с сухим банком.
const ORANGE_BLOB_CENTER := Vector2(560.0, -60.0)
const ORANGE_BLOB_RADIUS: float = 430.0
const ORANGE_FIELD_PEAK: float = 0.55

const CAMERA_ZOOM_STEP: float = 1.12
const BASE_SEED: int = 612917
const STRENGTH_OVERRIDE_STEP: float = 0.1
const DIRECTION_OVERRIDE_STEP_DEG: float = 8.0
const SEASON_STEP: float = 0.1
const SEASON_AUTO_SPEED: float = 0.16
const PARAM_ADJUST_BIG_SCALE: float = 5.0
const COPY_FLASH_SECONDS: float = 2.0

const TREE_ASSET_DIRS: Array[String] = [
	"res://assets/sprites/flora/layered_trees/tree_01",
	"res://assets/sprites/flora/layered_trees/tree_02",
	"res://assets/sprites/flora/layered_trees/tree_03",
]
# Пара деревьев для масштаба: одно в сухой зоне, одно у края, одно в биополе.
const TREE_INSTANCES: Array[Dictionary] = [
	{ "position": Vector2(-560.0, -220.0) },
	{ "position": Vector2(-140.0, 260.0) },
	{ "position": Vector2(520.0, -40.0) },
]

# Живые ручки. step — шаг +/- (Shift ×5); material-only параметры не требуют
# пересборки инстансов.
const TUNABLE_PARAMS: Array[Dictionary] = [
	{ "key": "density_scale", "step": 0.05, "min": 0.0, "max": 6.0 },
	{ "key": "height_scale", "step": 0.02, "min": 0.1, "max": 2.0 },
	{ "key": "tuft_min_width_px", "step": 1.0, "min": 4.0, "max": 160.0 },
	{ "key": "tuft_max_width_px", "step": 1.0, "min": 4.0, "max": 220.0 },
	{ "key": "tuft_min_height_px", "step": 1.0, "min": 4.0, "max": 160.0 },
	{ "key": "tuft_max_height_px", "step": 1.0, "min": 4.0, "max": 220.0 },
	{ "key": "alpha_min", "step": 0.02, "min": 0.0, "max": 1.0 },
	{ "key": "alpha_max", "step": 0.02, "min": 0.0, "max": 1.0 },
	{ "key": "base_tint_min", "step": 0.02, "min": 0.0, "max": 1.35 },
	{ "key": "base_tint_max", "step": 0.02, "min": 0.0, "max": 1.35 },
	{ "key": "directional_shadow_alpha", "step": 0.02, "min": 0.0, "max": 1.0, "material": true },
	{ "key": "orange_density_boost", "step": 0.05, "min": 0.0, "max": 2.0 },
	{ "key": "orange_tint_boost", "step": 0.02, "min": 0.0, "max": 1.0 },
	{ "key": "orange_bank_low", "step": 0.02, "min": 0.0, "max": 1.0 },
	{ "key": "orange_bank_high", "step": 0.02, "min": 0.0, "max": 1.0 },
	{ "key": "wind_sway_fraction", "step": 0.005, "min": 0.0, "max": 0.4, "material": true },
	{ "key": "storm_lean_fraction", "step": 0.02, "min": 0.0, "max": 1.0, "material": true },
	{ "key": "intra_tuft_flutter", "step": 0.005, "min": 0.0, "max": 0.3, "material": true },
]

var _rng := RandomNumberGenerator.new()
var _camera: Camera2D = null
var _info_label: Label = null
var _params_label: Label = null
var _base_sprite: Sprite2D = null
var _snow_overlay_texture: Texture2D = null
var _grass_layer: MultiMeshInstance2D = null
var _shadow_layer: MultiMeshInstance2D = null
var _snow_layer: MultiMeshInstance2D = null
var _grass_material: ShaderMaterial = null
var _shadow_material: ShaderMaterial = null
var _snow_material: ShaderMaterial = null
var _tree_layer: LayeredTreeObjectLayer = null
var _params: Dictionary = {}
var _file_params: Dictionary = {}
var _param_index: int = 0
var _instance_count: int = 0
var _seed_offset: int = 0
var _season_amount: float = 0.0
var _season_auto: bool = false
var _copy_flash_left: float = 0.0


func _ready() -> void:
	# Сцена живёт в паузе (ввод/HUD), чтобы проверять контракт
	# «пауза игры останавливает ветер»: WindRuntime паузится с деревом.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = BASE_SEED
	_load_sampling_params()
	_build_background()
	_snow_overlay_texture = _load_png_texture(PROTOTYPE_SNOW_OVERLAY_ATLAS_PATH)
	_build_grass_layers()
	_build_trees()
	_build_camera()
	_build_hud()
	_apply_material_params()
	_set_season_amount(_season_amount, false)
	_rebuild_grass()
	_update_hud()


func _process(delta: float) -> void:
	if _season_auto:
		_set_season_amount(wrapf(_season_amount + delta * SEASON_AUTO_SPEED, 0.0, 1.0), true)
	if _copy_flash_left > 0.0:
		_copy_flash_left = maxf(0.0, _copy_flash_left - delta)
	_update_camera_pan(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.keycode:
			KEY_TAB:
				var direction: int = -1 if key_event.shift_pressed else 1
				_param_index = wrapi(_param_index + direction, 0, TUNABLE_PARAMS.size())
			KEY_EQUAL, KEY_KP_ADD:
				_adjust_selected_param(1.0, key_event.shift_pressed)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_adjust_selected_param(-1.0, key_event.shift_pressed)
			KEY_BACKSPACE:
				_reset_selected_param()
			KEY_P:
				_copy_params_to_clipboard()
			KEY_L:
				_load_sampling_params()
				_apply_material_params()
				_rebuild_grass()
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
			KEY_Q:
				_season_auto = false
				_set_season_amount(_season_amount - SEASON_STEP, false)
			KEY_E:
				_season_auto = false
				_set_season_amount(_season_amount + SEASON_STEP, false)
			KEY_F:
				_season_auto = not _season_auto
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


func _load_sampling_params() -> void:
	# CACHE_MODE_IGNORE: пользователь может править .tres, пока сцена открыта;
	# L перечитывает файл с диска, а не из кэша ресурсов.
	var material_set: Resource = ResourceLoader.load(
		MATERIAL_SET_PATH, "", ResourceLoader.CACHE_MODE_IGNORE,
	)
	assert(material_set != null, "grass_scatter_material_set.tres missing")
	var sampling: Dictionary = material_set.get("sampling_params") as Dictionary
	assert(not sampling.is_empty(), "sampling_params missing in grass material set")
	_file_params = sampling.duplicate()
	_params = sampling.duplicate()


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


func _build_grass_layers() -> void:
	# Порядок как в рантайме: направленная тень под травой, трава, снег сверху.
	_shadow_layer = _make_batch_layer("GrassShadowBatch", GRASS_TUFT_SHADOW_ATLAS, -6, true, false)
	_shadow_material = _shadow_layer.material as ShaderMaterial
	_configure_directional_shadow_material()
	add_child(_shadow_layer)
	_grass_layer = _make_batch_layer("GrassBatch", GRASS_TUFT_ATLAS, 0, false, true)
	_grass_material = _grass_layer.material as ShaderMaterial
	add_child(_grass_layer)
	if _snow_overlay_texture != null:
		_snow_layer = _make_batch_layer("GrassSnowBatch", _snow_overlay_texture, 6, true, true)
		_snow_material = _snow_layer.material as ShaderMaterial
		add_child(_snow_layer)


func _make_batch_layer(
		layer_name: String,
		texture: Texture2D,
		z_index_value: int,
		overlay_exact: bool,
		wind_enabled: bool,
) -> MultiMeshInstance2D:
	var layer := MultiMeshInstance2D.new()
	layer.name = layer_name
	layer.texture = texture
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.z_index = z_index_value
	var material := ShaderMaterial.new()
	material.shader = GRASS_WIND_SHADER
	material.set_shader_parameter("atlas_columns", float(_params.get("atlas_columns", 4.0)))
	material.set_shader_parameter("atlas_rows", float(_params.get("atlas_rows", 8.0)))
	material.set_shader_parameter("atlas_frame_count", float(_params.get("atlas_frame_count", 32.0)))
	material.set_shader_parameter(
		"gust_field_scale_px",
		WorldVisualWindProfile.GUST_FIELD_SCALE_PX,
	)
	material.set_shader_parameter(
		"gust_field_anisotropy",
		WorldVisualWindProfile.GUST_FIELD_ANISOTROPY,
	)
	material.set_shader_parameter("overlay_exact", 1.0 if overlay_exact else 0.0)
	material.set_shader_parameter("overlay_alpha", 1.0)
	if not wind_enabled:
		# Как в рантайме: направленная тень не качается ветром.
		material.set_shader_parameter("wind_sway_fraction", 0.0)
		material.set_shader_parameter("storm_lean_fraction", 0.0)
		material.set_shader_parameter("intra_tuft_flutter", 0.0)
	layer.material = material
	layer.set_meta("wind_enabled", wind_enabled)
	return layer


func _build_trees() -> void:
	_tree_layer = LayeredTreeObjectLayer.new()
	_tree_layer.name = "LayeredTrees"
	# Над травой и снегом; внутренний shadow_root слоя добавит свой z для
	# полигонов теней (в игре кроны и тени деревьев тоже рисуются над пучками).
	_tree_layer.z_index = 20
	add_child(_tree_layer)
	_tree_layer.set_asset_dirs(TREE_ASSET_DIRS)
	_tree_layer.set_sun_lighting(
		WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG,
		WorldVisualLightingProfile.DEFAULT_SHADOW_LENGTH_PX,
		0.75,
		WorldVisualLightingProfile.shadow_softness_px_for_low_sun(0.0),
	)
	var instances: Array[Dictionary] = []
	for index: int in range(TREE_INSTANCES.size()):
		var instance: Dictionary = TREE_INSTANCES[index].duplicate()
		instance["asset_dir"] = TREE_ASSET_DIRS[index % TREE_ASSET_DIRS.size()]
		instances.append(instance)
	_tree_layer.set_instances(instances)
	_tree_layer.set_season_amount(_season_amount)


func _configure_directional_shadow_material() -> void:
	if _shadow_material == null:
		return
	_shadow_material.set_shader_parameter("overlay_shadow_rotation_enabled", 1.0)
	_shadow_material.set_shader_parameter(
		"overlay_shadow_baked_direction",
		_params.get("directional_shadow_baked_direction", Vector2(0.887216, -0.461354)),
	)
	_shadow_material.set_shader_parameter(
		"overlay_shadow_runtime_direction",
		WorldVisualLightingProfile.shadow_direction_for_light_angle_deg(
			WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG,
		),
	)
	_shadow_material.set_shader_parameter(
		"overlay_shadow_anchor_uv",
		_params.get("directional_shadow_anchor_uv", Vector2(0.42, 0.75)),
	)


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
	_info_label = _make_hud_label("InfoLabel", 16.0, 720.0)
	canvas.add_child(_info_label)
	_params_label = _make_hud_label("ParamsLabel", 0.0, 470.0)
	_params_label.anchor_left = 1.0
	_params_label.anchor_right = 1.0
	_params_label.offset_left = -486.0
	_params_label.offset_right = -16.0
	canvas.add_child(_params_label)


func _make_hud_label(label_name: String, left_px: float, width_px: float) -> Label:
	var label := Label.new()
	label.name = label_name
	label.offset_left = left_px
	label.offset_top = 16.0
	label.offset_right = left_px + width_px
	label.offset_bottom = 620.0
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.84, 0.92, 0.86, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _selected_param_key() -> String:
	return str(TUNABLE_PARAMS[_param_index]["key"])


func _adjust_selected_param(direction: float, big_step: bool) -> void:
	var spec: Dictionary = TUNABLE_PARAMS[_param_index]
	var key: String = str(spec["key"])
	var step: float = float(spec["step"]) * direction
	if big_step:
		step *= PARAM_ADJUST_BIG_SCALE
	var value: float = float(_params.get(key, 0.0)) + step
	_params[key] = snappedf(clampf(value, float(spec["min"]), float(spec["max"])), 0.001)
	_apply_material_params()
	if not bool(spec.get("material", false)):
		_rebuild_grass()


func _reset_selected_param() -> void:
	var spec: Dictionary = TUNABLE_PARAMS[_param_index]
	var key: String = str(spec["key"])
	_params[key] = _file_params.get(key, _params.get(key, 0.0))
	_apply_material_params()
	if not bool(spec.get("material", false)):
		_rebuild_grass()


func _apply_material_params() -> void:
	for layer: MultiMeshInstance2D in [_grass_layer, _snow_layer]:
		if layer == null:
			continue
		var material := layer.material as ShaderMaterial
		material.set_shader_parameter("wind_sway_fraction", float(_params.get("wind_sway_fraction", 0.085)))
		material.set_shader_parameter("storm_lean_fraction", float(_params.get("storm_lean_fraction", 0.35)))
		material.set_shader_parameter("intra_tuft_flutter", float(_params.get("intra_tuft_flutter", 0.05)))
		material.set_shader_parameter("local_dir_min_deg", float(_params.get("local_dir_min_deg", 5.0)))
		material.set_shader_parameter("local_dir_max_deg", float(_params.get("local_dir_max_deg", 26.0)))
		material.set_shader_parameter("local_dir_field_scale_px", float(_params.get("local_dir_field_scale_px", 1400.0)))
		material.set_shader_parameter("local_dir_gust_gain", float(_params.get("local_dir_gust_gain", 0.9)))
	if _shadow_material != null:
		_configure_directional_shadow_material()
		_shadow_material.set_shader_parameter(
			"overlay_alpha",
			float(_params.get("directional_shadow_alpha", 0.88)),
		)


## Зеркало нативного размещения (grass_scatter.cpp): сетка кандидатов,
## acceptance по полю × density_scale, размеры/тинт/банк из sampling_params.
## Поля здесь синтетические (волны + оранжевое пятно), но формулы — 1:1.
func _rebuild_grass() -> void:
	_rng.seed = BASE_SEED + _seed_offset * 1009
	var density_scale: float = float(_params.get("density_scale", 1.0))
	var height_scale: float = float(_params.get("height_scale", 1.0))
	var min_width: float = float(_params.get("tuft_min_width_px", 32.0))
	var max_width: float = float(_params.get("tuft_max_width_px", 54.0))
	var min_height: float = float(_params.get("tuft_min_height_px", 24.0))
	var max_height: float = float(_params.get("tuft_max_height_px", 40.0))
	var alpha_min: float = float(_params.get("alpha_min", 0.78))
	var alpha_max: float = float(_params.get("alpha_max", 0.95))
	var tint_min: float = float(_params.get("base_tint_min", 0.8))
	var tint_max: float = float(_params.get("base_tint_max", 1.16))
	var orange_density_boost: float = float(_params.get("orange_density_boost", 0.65))
	var orange_tint_boost: float = float(_params.get("orange_tint_boost", 0.18))
	var orange_bank_low: float = float(_params.get("orange_bank_low", 0.12))
	var orange_bank_high: float = float(_params.get("orange_bank_high", 0.45))
	var dry_frame_count: int = int(_params.get("dry_frame_count", 16.0))
	var orange_frame_base: int = int(_params.get("orange_frame_base", 16.0))
	var orange_frame_count: int = int(_params.get("orange_frame_count", 16.0))

	var columns: int = maxi(1, int(FIELD_RECT.size.x / CANDIDATE_CELL_PX))
	var rows: int = maxi(1, int(FIELD_RECT.size.y / CANDIDATE_CELL_PX))
	var transforms: Array[Transform2D] = []
	var colors: Array[Color] = []
	for row: int in range(rows):
		for column: int in range(columns):
			var position := Vector2(
				FIELD_RECT.position.x + (float(column) + 0.5 + (_rng.randf() - 0.5) * 0.92) * CANDIDATE_CELL_PX,
				FIELD_RECT.position.y + (float(row) + 0.5 + (_rng.randf() - 0.5) * 0.92) * CANDIDATE_CELL_PX,
			)
			var grass_d: float = _grass_density_field(position)
			var orange: float = _orange_field(position)
			var acceptance: float = smoothstep(0.30, 0.62, grass_d) * 0.34 \
				+ smoothstep(0.62, 0.86, grass_d) * 0.30
			acceptance += orange * orange_density_boost
			acceptance = clampf(acceptance * density_scale, 0.0, 1.0)
			if _rng.randf() >= acceptance:
				continue
			var width: float = lerpf(min_width, max_width, _rng.randf())
			var height: float = lerpf(min_height, max_height, _rng.randf()) \
				* height_scale * (1.0 + orange * 0.15)
			var rotation: float = (_rng.randf() - 0.5) * 2.0 * deg_to_rad(14.0)
			var biofield_pick: float = smoothstep(orange_bank_low, orange_bank_high, orange)
			var use_biofield: bool = _rng.randf() < biofield_pick
			var tint: float = lerpf(tint_min, tint_max, _rng.randf())
			var frame_index: int = 0
			if use_biofield:
				frame_index = orange_frame_base + int(_rng.randf() * float(orange_frame_count))
			else:
				frame_index = int(_rng.randf() * float(dry_frame_count))
				tint *= 1.0 + orange * orange_tint_boost
			tint = clampf(tint, 0.0, 1.35)
			var alpha: float = lerpf(alpha_min, alpha_max, _rng.randf())
			var transform := Transform2D(rotation, position)
			transform.x *= width
			transform.y *= height
			transforms.append(transform)
			colors.append(Color(
				float(frame_index) / 255.0,
				tint,
				_rng.randf(),
				alpha,
			))

	var multimesh := MultiMesh.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = transforms.size()
	for i: int in range(transforms.size()):
		multimesh.set_instance_transform_2d(i, transforms[i])
		multimesh.set_instance_color(i, colors[i])
	_instance_count = transforms.size()
	_grass_layer.multimesh = multimesh
	if _shadow_layer != null:
		_shadow_layer.multimesh = multimesh
	if _snow_layer != null:
		_snow_layer.multimesh = multimesh


func _grass_density_field(position: Vector2) -> float:
	# Апериодичная волновая пятнистость: лысины и плотные куртины, как ladder
	# в игре. Не нативное поле, но покрывает тот же диапазон 0..1.
	var wave: float = 0.55 \
		+ 0.30 * sin((position.x + position.y * 0.38) / 190.0) \
		+ 0.24 * sin((position.x * 0.21 - position.y) / 310.0)
	return clampf(wave, 0.0, 1.0)


func _orange_field(position: Vector2) -> float:
	var distance_to_core: float = position.distance_to(ORANGE_BLOB_CENTER)
	return ORANGE_FIELD_PEAK * (1.0 - smoothstep(ORANGE_BLOB_RADIUS * 0.35, ORANGE_BLOB_RADIUS, distance_to_core))


func _load_png_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	var err: Error = image.load(path)
	if err != OK:
		push_warning("grass_wind_dev_scene: failed to load %s (err %d)" % [path, err])
		return null
	return ImageTexture.create_from_image(image)


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


func _set_season_amount(value: float, _from_auto: bool) -> void:
	_season_amount = clampf(value, 0.0, 1.0)
	if _snow_material != null:
		_snow_material.set_shader_parameter("overlay_alpha", _season_amount)
	if _snow_layer != null:
		_snow_layer.visible = _season_amount > 0.01
	if _tree_layer != null:
		_tree_layer.set_season_amount(_season_amount)


func _copy_params_to_clipboard() -> void:
	var keys: Array = _params.keys()
	keys.sort()
	var lines: Array[String] = ["sampling_params = {"]
	for i: int in range(keys.size()):
		var key: String = str(keys[i])
		var comma: String = "," if i < keys.size() - 1 else ""
		lines.append("\"%s\": %s%s" % [key, _format_tres_number(float(_params[key])), comma])
	lines.append("}")
	DisplayServer.clipboard_set("\n".join(lines))
	_copy_flash_left = COPY_FLASH_SECONDS


func _format_tres_number(value: float) -> String:
	var text: String = String.num(value, 4)
	if not text.contains("."):
		text += ".0"
	return text


func _params_hud_text() -> String:
	var lines: Array[String] = [
		"sampling_params (%s)" % MATERIAL_SET_PATH.get_file(),
		"TAB — выбор | +/− — правка (Shift ×5) | Backspace — сброс",
		"P — скопировать блок в буфер | L — перечитать .tres",
		"",
	]
	for i: int in range(TUNABLE_PARAMS.size()):
		var key: String = str(TUNABLE_PARAMS[i]["key"])
		var value: float = float(_params.get(key, 0.0))
		var file_value: float = float(_file_params.get(key, value))
		var marker: String = "► " if i == _param_index else "   "
		var changed: String = ""
		if absf(value - file_value) > 0.0005:
			changed = "   (файл: %s)" % _format_tres_number(file_value)
		lines.append("%s\"%s\": %s,%s" % [marker, key, _format_tres_number(value), changed])
	if _copy_flash_left > 0.0:
		lines.append("")
		lines.append("Скопировано в буфер обмена — вставляй в .tres")
	return "\n".join(lines)


func _update_hud() -> void:
	if _info_label == null:
		return
	var override_state: String = "override" if WindRuntime.has_debug_wind_override() else "профиль"
	var season_state: String = "auto" if _season_auto else "manual"
	_info_label.text = "\n".join(
		[
			"Grass wind dev scene — потребитель WindRuntime (wind_* global uniforms)",
			"Пучков: %d | Сетка кандидатов %.1f px (зеркало native) | Сезон: %.2f (%s)" % [
				_instance_count,
				CANDIDATE_CELL_PX,
				_season_amount,
				season_state,
			],
			"Ветер [%s]: сила %.2f, угол %.0f°, время %.1fс, %s" % [
				override_state,
				WindRuntime.get_wind_strength(),
				WindRuntime.get_wind_direction_deg(),
				WindRuntime.get_wind_time(),
				"пауза" if get_tree().paused else "идёт",
			],
			"Справа — живые sampling_params; оранжевое пятно справа поля — биополе",
			"Q/E — сезон | F — авто-сезон | ↑↓ — сила ветра | ←→ — угол | O — сброс override",
			"Space — пауза дерева | R — seed | колесо — zoom | WASD — камера",
		],
	)
	if _params_label != null:
		_params_label.text = _params_hud_text()
