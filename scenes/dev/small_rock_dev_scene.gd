class_name SmallRockDevScene
extends Node2D
## Dev-песочница мелких layered rocks. Сцена использует тот же
## LayeredRockObjectLayer, что runtime-чанки, но расставляет камни локально,
## чтобы быстро крутить размер, плотность, снег и фиксированную тень.

const LayeredRockObjectLayer = preload("res://core/systems/world/layered_rock_object_layer.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")

const GROUND_TEXTURE: Texture2D = preload("res://assets/textures/world/biomes/plains/ground/dry_ground_top_albedo.png")
const GRASS_SPARSE_TEXTURE: Texture2D = preload("res://assets/textures/world/biomes/plains/ground/dry_grass_sparse_albedo.png")
const GRASS_MEDIUM_TEXTURE: Texture2D = preload("res://assets/textures/world/biomes/plains/ground/dry_grass_medium_albedo.png")

const SETTINGS_PATH: String = "res://data/world_objects/placement_groups/plains_small_rocks.tres"
const FIELD_RECT := Rect2(Vector2(-1040.0, -600.0), Vector2(2080.0, 1200.0))
const BASE_SEED: int = 910337
const CAMERA_ZOOM_STEP: float = 1.12
const PARAM_ADJUST_BIG_SCALE: float = 5.0
const COPY_FLASH_SECONDS: float = 2.0

const ROCK_ASSET_DIRS: Array[String] = [
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_01",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_02",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_03",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_04",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_05",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_06",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_07",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_08",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_09",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_10",
]

const DEFAULT_PARAMS: Dictionary = {
	"count": 54.0,
	"cluster_count": 9.0,
	"min_size_px": 28.0,
	"max_size_px": 70.0,
	"spread_x_px": 1600.0,
	"spread_y_px": 860.0,
	"cluster_radius_px": 112.0,
	"cluster_min_count": 3.0,
	"cluster_max_count": 7.0,
	"cluster_min_distance_px": 26.0,
	"edge_bias": 0.76,
	"rocky_patch_bias": 0.48,
	"variant_count": 10.0,
	"variant_offset": 0.0,
	"tint_min": 0.86,
	"tint_max": 1.0,
	"shadow_length_px": 96.0,
	"shadow_opacity": 0.72,
	"snow_amount": 0.0,
}

const TUNABLE_PARAMS: Array[Dictionary] = [
	{ "key": "count", "step": 1.0, "min": 1.0, "max": 140.0, "rebuild": true },
	{ "key": "cluster_count", "step": 1.0, "min": 1.0, "max": 28.0, "rebuild": true },
	{ "key": "min_size_px", "step": 1.0, "min": 8.0, "max": 180.0, "rebuild": true },
	{ "key": "max_size_px", "step": 1.0, "min": 8.0, "max": 220.0, "rebuild": true },
	{ "key": "spread_x_px", "step": 20.0, "min": 280.0, "max": 2200.0, "rebuild": true },
	{ "key": "spread_y_px", "step": 20.0, "min": 220.0, "max": 1400.0, "rebuild": true },
	{ "key": "cluster_radius_px", "step": 4.0, "min": 16.0, "max": 260.0, "rebuild": true },
	{ "key": "cluster_min_count", "step": 1.0, "min": 1.0, "max": 16.0, "rebuild": true },
	{ "key": "cluster_max_count", "step": 1.0, "min": 1.0, "max": 16.0, "rebuild": true },
	{ "key": "cluster_min_distance_px", "step": 2.0, "min": 0.0, "max": 120.0, "rebuild": true },
	{ "key": "edge_bias", "step": 0.03, "min": 0.0, "max": 1.0, "rebuild": true },
	{ "key": "rocky_patch_bias", "step": 0.03, "min": 0.0, "max": 1.0, "rebuild": true },
	{ "key": "variant_count", "step": 1.0, "min": 1.0, "max": 10.0, "rebuild": true },
	{ "key": "variant_offset", "step": 1.0, "min": 0.0, "max": 9.0, "rebuild": true },
	{ "key": "tint_min", "step": 0.01, "min": 0.55, "max": 1.35, "rebuild": true },
	{ "key": "tint_max", "step": 0.01, "min": 0.55, "max": 1.35, "rebuild": true },
	{ "key": "shadow_length_px", "step": 8.0, "min": 0.0, "max": 220.0, "rebuild": false },
	{ "key": "shadow_opacity", "step": 0.03, "min": 0.0, "max": 1.0, "rebuild": false },
	{ "key": "snow_amount", "step": 0.05, "min": 0.0, "max": 1.0, "rebuild": false },
]

var _rng := RandomNumberGenerator.new()
var _params: Dictionary = DEFAULT_PARAMS.duplicate()
var _param_index: int = 0
var _seed_offset: int = 0
var _copy_flash_left: float = 0.0
var _instance_count: int = 0
var _camera: Camera2D = null
var _rock_layer: LayeredRockObjectLayer = null
var _info_label: Label = null
var _params_label: Label = null


func _ready() -> void:
	name = "SmallRockDevScene"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_background()
	_build_rock_layer()
	_build_camera()
	_build_hud()
	_rebuild_rocks()
	_apply_live_params()
	_update_hud()


func _process(delta: float) -> void:
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
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_adjust_selected_param(1.0, key_event.shift_pressed)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_adjust_selected_param(-1.0, key_event.shift_pressed)
			KEY_BACKSPACE:
				_reset_selected_param()
			KEY_R:
				_seed_offset += 1
				_rebuild_rocks()
			KEY_1:
				_set_shadow_preset(0.0, 0.35)
			KEY_2:
				_set_shadow_preset(78.0, 0.72)
			KEY_3:
				_set_shadow_preset(190.0, 0.95)
			KEY_Q:
				_params["snow_amount"] = maxf(0.0, float(_params["snow_amount"]) - 0.05)
				_apply_live_params()
			KEY_E:
				_params["snow_amount"] = minf(1.0, float(_params["snow_amount"]) + 0.05)
				_apply_live_params()
			KEY_C:
				_copy_tres_hint_to_clipboard()
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_camera.zoom *= CAMERA_ZOOM_STEP
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_camera.zoom /= CAMERA_ZOOM_STEP


func get_debug_snapshot() -> Dictionary:
	var layer_state: Dictionary = _rock_layer.get_debug_state() if _rock_layer != null else {}
	return {
		"instance_count": _instance_count,
		"seed_offset": _seed_offset,
		"params": _params.duplicate(),
		"rock_layer": layer_state,
		"settings_path": SETTINGS_PATH,
	}


func set_debug_param(key: String, value: float) -> void:
	if not _params.has(key):
		return
	_params[key] = value
	_sanitize_params()
	_rebuild_rocks()
	_apply_live_params()


func _build_background() -> void:
	_add_repeating_sprite("GroundBase", GROUND_TEXTURE, FIELD_RECT, -40, Color(0.86, 0.82, 0.72, 1.0))
	_add_repeating_sprite("SparseGrassWash", GRASS_SPARSE_TEXTURE, FIELD_RECT, -38, Color(1.0, 1.0, 1.0, 0.56))
	_add_repeating_sprite(
		"MediumGrassPatch",
		GRASS_MEDIUM_TEXTURE,
		Rect2(Vector2(-620.0, -380.0), Vector2(1240.0, 760.0)),
		-37,
		Color(1.0, 1.0, 1.0, 0.34),
	)


func _add_repeating_sprite(
		sprite_name: String,
		texture: Texture2D,
		rect: Rect2,
		z: int,
		modulate_color: Color,
) -> void:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, rect.size)
	sprite.position = rect.get_center()
	sprite.z_index = z
	sprite.modulate = modulate_color
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(sprite)


func _build_rock_layer() -> void:
	_rock_layer = LayeredRockObjectLayer.new()
	_rock_layer.name = "LayeredSmallRocks"
	_rock_layer.set_world_origin_y(0.0)
	_rock_layer.set_asset_dirs(ROCK_ASSET_DIRS)
	add_child(_rock_layer)
	_rock_layer.update_ladder_z(0)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.enabled = true
	_camera.zoom = Vector2(0.72, 0.72)
	add_child(_camera)
	_camera.make_current()


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Hud"
	add_child(canvas)
	_info_label = _make_hud_label("InfoLabel", 16.0, 770.0)
	canvas.add_child(_info_label)
	_params_label = _make_hud_label("ParamsLabel", 0.0, 460.0)
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
	label.offset_bottom = 660.0
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.86, 0.92, 0.86, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.80))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _adjust_selected_param(direction: float, big_step: bool) -> void:
	var spec: Dictionary = TUNABLE_PARAMS[_param_index]
	var key: String = str(spec["key"])
	var step: float = float(spec["step"]) * direction
	if big_step:
		step *= PARAM_ADJUST_BIG_SCALE
	var value: float = float(_params.get(key, 0.0)) + step
	_params[key] = snappedf(clampf(value, float(spec["min"]), float(spec["max"])), 0.001)
	_sanitize_params()
	if bool(spec.get("rebuild", false)):
		_rebuild_rocks()
	_apply_live_params()


func _reset_selected_param() -> void:
	var spec: Dictionary = TUNABLE_PARAMS[_param_index]
	var key: String = str(spec["key"])
	_params[key] = DEFAULT_PARAMS.get(key, _params.get(key, 0.0))
	_sanitize_params()
	if bool(spec.get("rebuild", false)):
		_rebuild_rocks()
	_apply_live_params()


func _sanitize_params() -> void:
	_params["min_size_px"] = minf(float(_params["min_size_px"]), float(_params["max_size_px"]))
	_params["max_size_px"] = maxf(float(_params["max_size_px"]), float(_params["min_size_px"]))
	_params["tint_min"] = minf(float(_params["tint_min"]), float(_params["tint_max"]))
	_params["tint_max"] = maxf(float(_params["tint_max"]), float(_params["tint_min"]))
	_params["variant_count"] = clampf(roundf(float(_params["variant_count"])), 1.0, float(ROCK_ASSET_DIRS.size()))
	_params["variant_offset"] = clampf(roundf(float(_params["variant_offset"])), 0.0, float(ROCK_ASSET_DIRS.size() - 1))
	_params["count"] = clampf(roundf(float(_params["count"])), 1.0, 140.0)
	_params["cluster_count"] = clampf(roundf(float(_params["cluster_count"])), 1.0, 28.0)
	_params["cluster_min_count"] = clampf(roundf(float(_params["cluster_min_count"])), 1.0, 16.0)
	_params["cluster_max_count"] = clampf(
		roundf(maxf(float(_params["cluster_max_count"]), float(_params["cluster_min_count"]))),
		1.0,
		16.0,
	)


func _set_shadow_preset(length_px: float, opacity: float) -> void:
	_params["shadow_length_px"] = length_px
	_params["shadow_opacity"] = opacity
	_apply_live_params()


func _rebuild_rocks() -> void:
	if _rock_layer == null:
		return
	_sanitize_params()
	_rng.seed = BASE_SEED + _seed_offset * 1009
	var max_count: int = int(_params["count"])
	var cluster_count: int = int(_params["cluster_count"])
	var spread := Vector2(float(_params["spread_x_px"]), float(_params["spread_y_px"]))
	var min_size: float = float(_params["min_size_px"])
	var max_size: float = float(_params["max_size_px"])
	var cluster_radius: float = float(_params["cluster_radius_px"])
	var cluster_min_count: int = int(_params["cluster_min_count"])
	var cluster_max_count: int = int(_params["cluster_max_count"])
	var cluster_min_distance: float = float(_params["cluster_min_distance_px"])
	var edge_bias: float = float(_params["edge_bias"])
	var rocky_patch_bias: float = float(_params["rocky_patch_bias"])
	var tint_min: float = float(_params["tint_min"])
	var tint_max: float = float(_params["tint_max"])
	var variant_count: int = int(_params["variant_count"])
	var variant_offset: int = int(_params["variant_offset"])
	var instances: Array[Dictionary] = []
	var placed_positions: Array[Vector2] = []
	for cluster_index: int in range(cluster_count):
		if instances.size() >= max_count:
			break
		var center: Vector2 = _cluster_center(cluster_index, spread, edge_bias, rocky_patch_bias)
		var cluster_member_count: int = _rng.randi_range(cluster_min_count, cluster_max_count)
		var rotation: float = _rng.randf() * TAU
		var radius_x: float = cluster_radius * lerpf(0.78, 1.28, _rng.randf())
		var radius_y: float = cluster_radius * lerpf(0.42, 0.82, _rng.randf())
		for member_index: int in range(cluster_member_count):
			if instances.size() >= max_count:
				break
			var position: Vector2 = center
			var accepted: bool = false
			var distance_t: float = 0.0
			for attempt: int in range(6):
				distance_t = sqrt(_rng.randf())
				var angle: float = _rng.randf() * TAU
				var local_offset := Vector2(cos(angle) * distance_t * radius_x, sin(angle) * distance_t * radius_y).rotated(rotation)
				position = center + local_offset
				if absf(position.x) > spread.x * 0.5 or absf(position.y) > spread.y * 0.5:
					continue
				if not _is_far_enough(position, placed_positions, cluster_min_distance):
					continue
				accepted = true
				break
			if not accepted:
				continue
			placed_positions.append(position)
			var variant_index: int = posmod(variant_offset + instances.size(), variant_count)
			var asset_dir: String = ROCK_ASSET_DIRS[variant_index]
			var size_px: float = lerpf(min_size, max_size, pow(_rng.randf(), 1.35))
			size_px *= lerpf(1.10, 0.76, distance_t)
			size_px = clampf(size_px, min_size, max_size)
			var tint_value: float = lerpf(tint_min, tint_max, _rng.randf())
			instances.append(
				{
					"position": position,
					"asset_dir": asset_dir,
					"size_px": size_px,
					"tint": Color(tint_value, tint_value, tint_value, 1.0),
				},
			)
	_instance_count = instances.size()
	_rock_layer.set_instances(instances)
	_rock_layer.update_ladder_z(0)


func _cluster_center(cluster_index: int, spread: Vector2, edge_bias: float, rocky_patch_bias: float) -> Vector2:
	var x: float = lerpf(-spread.x * 0.5, spread.x * 0.5, _rng.randf())
	var normalized_x: float = x / maxf(spread.x, 1.0)
	var edge_y: float = sin(normalized_x * TAU * 1.7 + float(_seed_offset) * 0.61) * spread.y * 0.18
	edge_y += sin(normalized_x * TAU * 3.1 + float(cluster_index) * 0.37) * spread.y * 0.08
	var roll: float = _rng.randf()
	if roll < edge_bias:
		return Vector2(x, edge_y + (_rng.randf() - 0.5) * spread.y * 0.22)
	if roll < edge_bias + rocky_patch_bias * 0.5:
		return Vector2(
			x * 0.92 + (_rng.randf() - 0.5) * spread.x * 0.14,
			edge_y + (_rng.randf() - 0.5) * spread.y * 0.54,
		)
	return Vector2(
		lerpf(-spread.x * 0.5, spread.x * 0.5, _rng.randf()),
		lerpf(-spread.y * 0.5, spread.y * 0.5, _rng.randf()),
	)


func _is_far_enough(position: Vector2, existing_positions: Array[Vector2], min_distance: float) -> bool:
	var min_distance_sq: float = min_distance * min_distance
	for existing: Vector2 in existing_positions:
		if position.distance_squared_to(existing) < min_distance_sq:
			return false
	return true


func _apply_live_params() -> void:
	if _rock_layer == null:
		return
	_rock_layer.set_sun_lighting(
		WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG,
		float(_params["shadow_length_px"]),
		float(_params["shadow_opacity"]),
		WorldVisualLightingProfile.DEFAULT_SHADOW_SOFTNESS_PX,
	)
	_rock_layer.set_season_amount(float(_params["snow_amount"]))


func _update_camera_pan(delta: float) -> void:
	if _camera == null:
		return
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
		_camera.position += move.normalized() * 620.0 * delta / maxf(_camera.zoom.x, 0.1)


func _selected_param_key() -> String:
	return str(TUNABLE_PARAMS[_param_index]["key"])


func _copy_tres_hint_to_clipboard() -> void:
	var lines: Array[String] = [
		"# Paste into %s" % SETTINGS_PATH,
		"max_per_chunk = %d" % int(_params["count"]),
		"scatter_grid_side = %d" % int(_params["cluster_count"]),
		"min_distance_px = %.1f" % maxf(float(_params["cluster_radius_px"]) * 1.6, 1.0),
		"visual_size_min_px = %.1f" % float(_params["min_size_px"]),
		"visual_size_max_px = %.1f" % float(_params["max_size_px"]),
		"asset_variant_count = %d" % int(_params["variant_count"]),
		"cluster_radius_px = %.1f" % float(_params["cluster_radius_px"]),
		"cluster_min_count = %d" % int(_params["cluster_min_count"]),
		"cluster_max_count = %d" % int(_params["cluster_max_count"]),
		"cluster_min_distance_px = %.1f" % float(_params["cluster_min_distance_px"]),
		"edge_bias = %.2f" % float(_params["edge_bias"]),
		"rocky_patch_bias = %.2f" % float(_params["rocky_patch_bias"]),
	]
	DisplayServer.clipboard_set("\n".join(lines))
	_copy_flash_left = COPY_FLASH_SECONDS


func _update_hud() -> void:
	if _info_label == null:
		return
	var layer_state: Dictionary = _rock_layer.get_debug_state() if _rock_layer != null else {}
	_info_label.text = "\n".join(
		[
			"Small rock dev scene — реальный LayeredRockObjectLayer",
			"Настройки генерации в игре: %s" % SETTINGS_PATH,
			"Камней: %d | Layer shadows: %d | Asset dirs: %d | Seed offset: %d" % [
				_instance_count,
				int(layer_state.get("shadow_instance_count", 0)),
				ROCK_ASSET_DIRS.size(),
				_seed_offset,
			],
			"Tab — параметр | +/- — крутить (Shift x5) | Backspace — default",
			"R — новый seed | 1/2/3 — полдень/обычно/закат | Q/E — снег | C — copy .tres hint",
			"WASD — камера | колесо — zoom",
		],
	)
	if _params_label != null:
		_params_label.text = _params_hud_text()


func _params_hud_text() -> String:
	var lines: Array[String] = ["live params:"]
	for i: int in range(TUNABLE_PARAMS.size()):
		var key: String = str(TUNABLE_PARAMS[i]["key"])
		var marker: String = "> " if i == _param_index else "  "
		lines.append("%s%s = %s" % [marker, key, _format_number(float(_params.get(key, 0.0)))])
	if _copy_flash_left > 0.0:
		lines.append("")
		lines.append("Copied .tres hint to clipboard")
	return "\n".join(lines)


func _format_number(value: float) -> String:
	if absf(value - roundf(value)) < 0.0005:
		return str(int(roundf(value)))
	return String.num(value, 3)
