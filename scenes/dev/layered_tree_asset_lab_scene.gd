class_name LayeredTreeAssetLabScene
extends Node2D

const DEFAULT_TREE_DIR: String = "res://assets/sprites/flora/layered_trees/tree_01"
const FROZEN_FOLIAGE_SHADER: Shader = preload("res://scenes/dev/layered_tree_asset_lab_frozen_foliage.gdshader")
const TRUNK_SEASON_SHADER: Shader = preload("res://assets/shaders/layered_tree_trunk_season.gdshader")
const LAB_SNOW_SHADER: Shader = preload("res://scenes/dev/layered_tree_asset_lab_snow.gdshader")
const MAX_WIND_STRENGTH_PX: float = 18.0
const SHADOW_DIRECTION_NORTH_EAST: Vector2 = Vector2(0.887216, -0.461354)
const SHADOW_DIRECTION_SOUTH_EAST: Vector2 = Vector2(0.707107, 0.707107)
const SHADOW_OPACITY: float = 0.82

@export var tree_dir: String = DEFAULT_TREE_DIR
@export var shadow_texture_override: String = ""

var _meta: Dictionary = {}
var _root_position: Vector2 = Vector2(512.0, 620.0)
var _tree_scale: float = 0.86
var _wind_strength_px: float = 3.0
var _plant_depth_px: float = 0.0
var _season_amount: float = 0.0
var _shadow_hour: float = 14.5
var _shadow_length_scale: float = 1.0
var _shadow_width_scale: float = 1.0
var _shadow_backward_stretch_scale: float = 1.0
var _shadow_root: Node2D = null
var _shadow_polygons: Array[Polygon2D] = []
var _shadow_texture: Texture2D = null
var _shadow_frame_size: Vector2 = Vector2(768.0, 768.0)
var _shadow_anchor_px: Vector2 = Vector2(384.0, 650.0)
var _shadow_direction: Vector2 = SHADOW_DIRECTION_NORTH_EAST
var _shadow_direction_name: String = "north_east"
var _shadow_contact_lock_source_px: float = 0.0
var _trunk_material: ShaderMaterial = null
var _foliage_material: ShaderMaterial = null
var _snow_material: ShaderMaterial = null
var _snow_sprite: Sprite2D = null
var _hud_label: Label = null


func _ready() -> void:
	name = "LayeredTreeAssetLabScene"
	_meta = _load_json_dictionary("%s/meta.json" % tree_dir)
	_resolve_shadow_direction()
	_build_tree()
	_build_camera()
	_build_hud()
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()
	var effective_wind_strength_px: float = _wind_strength_px * (1.0 - _season_amount)
	if _foliage_material != null:
		_foliage_material.set_shader_parameter("wind_strength_px", effective_wind_strength_px)
		_foliage_material.set_shader_parameter("season_amount", _season_amount)
	if _trunk_material != null:
		_trunk_material.set_shader_parameter("wind_strength_px", effective_wind_strength_px)
		_trunk_material.set_shader_parameter("season_amount", _season_amount)
	if _snow_sprite != null:
		_snow_sprite.visible = _season_amount > 0.01
	if _snow_material != null:
		_snow_material.set_shader_parameter("season_amount", _season_amount)
	_apply_shadow_hour()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_SPACE:
			_season_amount = 1.0 if _season_amount < 0.5 else 0.0
			get_viewport().set_input_as_handled()
		KEY_Z:
			_season_amount = maxf(_season_amount - 0.05, 0.0)
			get_viewport().set_input_as_handled()
		KEY_X:
			_season_amount = minf(_season_amount + 0.05, 1.0)
			get_viewport().set_input_as_handled()
		KEY_EQUAL, KEY_PLUS:
			_wind_strength_px = minf(_wind_strength_px + 0.6, MAX_WIND_STRENGTH_PX)
			get_viewport().set_input_as_handled()
		KEY_MINUS:
			_wind_strength_px = maxf(_wind_strength_px - 0.6, 0.0)
			get_viewport().set_input_as_handled()
		KEY_Q:
			_shadow_hour = maxf(_shadow_hour - 0.25, 13.0)
			get_viewport().set_input_as_handled()
		KEY_E:
			_shadow_hour = minf(_shadow_hour + 0.25, 16.0)
			get_viewport().set_input_as_handled()
		KEY_1:
			_shadow_hour = 13.0
			get_viewport().set_input_as_handled()
		KEY_2:
			_shadow_hour = 14.5
			get_viewport().set_input_as_handled()
		KEY_3:
			_shadow_hour = 16.0
			get_viewport().set_input_as_handled()
		KEY_4:
			_season_amount = 0.35
			get_viewport().set_input_as_handled()
		KEY_5:
			_season_amount = 0.70
			get_viewport().set_input_as_handled()
		KEY_6:
			_season_amount = 1.0
			get_viewport().set_input_as_handled()
		KEY_R:
			_season_amount = 0.0
			get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1024.0, 768.0)), Color(0.18, 0.165, 0.135, 1.0))
	for y: int in range(0, 768, 32):
		var tint: float = 0.02 if (y / 32) % 2 == 0 else 0.0
		draw_rect(Rect2(Vector2(0.0, float(y)), Vector2(1024.0, 16.0)), Color(0.15 + tint, 0.14 + tint, 0.115 + tint, 1.0))
	draw_line(Vector2(0.0, _root_position.y), Vector2(1024.0, _root_position.y), Color(0.7, 0.48, 0.22, 0.45), 1.0)


func get_debug_snapshot() -> Dictionary:
	return {
		"ready": not _meta.is_empty(),
		"tree_dir": tree_dir,
		"shadow_texture_override": shadow_texture_override,
		"asset": str(_meta.get("asset", "")),
		"anchor": _meta.get("anchor", []),
		"has_shadow": get_node_or_null("Shadow") != null,
		"has_trunk": get_node_or_null("Trunk") != null,
		"has_trunk_season_material": _trunk_material != null,
		"has_foliage": get_node_or_null("Foliage") != null,
		"has_snow": get_node_or_null("SnowOverlay") != null,
		"wind_strength_px": _wind_strength_px,
		"effective_wind_strength_px": _wind_strength_px * (1.0 - _season_amount),
		"max_wind_strength_px": MAX_WIND_STRENGTH_PX,
		"plant_depth_px": _plant_depth_px,
		"snow_enabled": _season_amount > 0.01,
		"season_amount": _season_amount,
		"shadow_hour": _shadow_hour,
		"shadow_direction_screen": _shadow_direction_name,
		"shadow_direction_vector_screen": [_shadow_direction.x, _shadow_direction.y],
		"shadow_contact_lock_source_px": _shadow_contact_lock_source_px,
		"shadow_probe_local_points": _get_shadow_probe_local_points(),
		"shadow_rotation_degrees": 0.0,
		"shadow_length_scale": _shadow_length_scale,
		"shadow_width_scale": _shadow_width_scale,
		"shadow_backward_stretch_scale": _shadow_backward_stretch_scale,
	}


func set_debug_shadow_hour(hour: float) -> void:
	_shadow_hour = clampf(hour, 13.0, 16.0)
	_apply_shadow_hour()


func set_debug_winter_state(season_amount: float) -> void:
	_season_amount = clampf(season_amount, 0.0, 1.0)


func set_debug_wind_strength_px(strength_px: float) -> void:
	_wind_strength_px = clampf(strength_px, 0.0, MAX_WIND_STRENGTH_PX)


func _get_shadow_probe_local_points() -> Dictionary:
	var points: Dictionary = {}
	for distance: float in [0.0, 16.0, 32.0, 48.0, 96.0, 303.0]:
		var source_point: Vector2 = _shadow_anchor_px + _shadow_direction * distance
		var stretch_forward: bool = distance > _shadow_contact_lock_source_px
		var local_point: Vector2 = _shadow_texture_point_to_local(source_point, stretch_forward)
		points[str(int(distance))] = [local_point.x, local_point.y]
	return points


func _build_tree() -> void:
	var frame_width: float = float(_meta.get("frame_width", 768))
	var frame_height: float = float(_meta.get("frame_height", 768))
	var anchor_array: Array = _meta.get("anchor", [frame_width * 0.5, frame_height * 0.84]) as Array
	var anchor := Vector2(float(anchor_array[0]), float(anchor_array[1]))
	var center := Vector2(frame_width, frame_height) * 0.5
	_plant_depth_px = float(_meta.get("plant_depth_px", 0.0))
	var sprite_position: Vector2 = _root_position - (anchor - center) * _tree_scale
	var planted_sprite_position: Vector2 = sprite_position + Vector2(0.0, _plant_depth_px * _tree_scale)

	_build_shadow(frame_width, frame_height, anchor)

	var trunk := _make_sprite("Trunk", "%s/trunk.png" % tree_dir, planted_sprite_position, _tree_scale)
	trunk.z_index = 2
	_trunk_material = ShaderMaterial.new()
	_trunk_material.shader = TRUNK_SEASON_SHADER
	_trunk_material.set_shader_parameter("snow_mask_texture", _load_png_texture("%s/snow_mask.png" % tree_dir))
	_trunk_material.set_shader_parameter("wind_mask_texture", _load_png_texture("%s/wind_mask.png" % tree_dir))
	_trunk_material.set_shader_parameter("wind_strength_px", _wind_strength_px)
	_trunk_material.set_shader_parameter("season_amount", _season_amount)
	trunk.material = _trunk_material
	add_child(trunk)

	var foliage := _make_sprite("Foliage", "%s/foliage.png" % tree_dir, planted_sprite_position, _tree_scale)
	foliage.z_index = 3
	_foliage_material = ShaderMaterial.new()
	_foliage_material.shader = FROZEN_FOLIAGE_SHADER
	_foliage_material.set_shader_parameter("wind_mask_texture", _load_png_texture("%s/wind_mask.png" % tree_dir))
	_foliage_material.set_shader_parameter("season_mask_texture", _load_png_texture("%s/season_mask.png" % tree_dir))
	_foliage_material.set_shader_parameter("wind_strength_px", _wind_strength_px)
	_foliage_material.set_shader_parameter("season_amount", _season_amount)
	foliage.material = _foliage_material
	add_child(foliage)

	_snow_sprite = _make_sprite("SnowOverlay", "%s/snow_overlay.png" % tree_dir, planted_sprite_position, _tree_scale)
	_snow_sprite.z_index = 4
	_snow_sprite.visible = _season_amount > 0.01
	_snow_material = ShaderMaterial.new()
	_snow_material.shader = LAB_SNOW_SHADER
	_snow_material.set_shader_parameter("snow_mask_texture", _load_png_texture("%s/snow_mask.png" % tree_dir))
	_snow_material.set_shader_parameter("season_mask_texture", _load_png_texture("%s/season_mask.png" % tree_dir))
	_snow_material.set_shader_parameter("season_amount", _season_amount)
	_snow_sprite.material = _snow_material
	add_child(_snow_sprite)


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = Vector2(512.0, 384.0)
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	_hud_label = Label.new()
	_hud_label.name = "HudLabel"
	_hud_label.position = Vector2(14.0, 12.0)
	_hud_label.add_theme_font_size_override("font_size", 16)
	_hud_label.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82, 1.0))
	layer.add_child(_hud_label)
	_update_hud()


func _update_hud() -> void:
	if _hud_label == null:
		return
	_hud_label.text = "Layered tree lab | Space winter | Z/X season %.2f | 4/5/6 frost 0.35/0.70/1.00 | R thaw | +/- wind %.1f/%0.0f px | Q/E fixed %s shadow %.1f h" % [
		_season_amount,
		_wind_strength_px,
		MAX_WIND_STRENGTH_PX,
		_shadow_direction_name.to_upper(),
		_shadow_hour,
	]


func _apply_shadow_hour() -> void:
	if _shadow_root == null:
		return
	var t: float = clampf((_shadow_hour - 13.0) / 3.0, 0.0, 1.0)
	var day_edge: float = absf(t - 0.5) * 2.0
	_shadow_length_scale = lerpf(1.0, 1.85, day_edge)
	_shadow_width_scale = 1.0
	_shadow_backward_stretch_scale = 1.0
	for polygon: Polygon2D in _shadow_polygons:
		polygon.modulate = Color(1.0, 1.0, 1.0, SHADOW_OPACITY)
	_rebuild_shadow_polygons()


func _build_shadow(frame_width: float, frame_height: float, anchor: Vector2) -> void:
	var shadow_path: String = shadow_texture_override
	if shadow_path.is_empty():
		shadow_path = "%s/shadow.png" % tree_dir
	_shadow_texture = _load_png_texture(shadow_path)
	_shadow_frame_size = Vector2(frame_width, frame_height)
	_shadow_anchor_px = anchor
	_shadow_polygons.clear()

	_shadow_root = Node2D.new()
	_shadow_root.name = "Shadow"
	_shadow_root.position = _root_position
	_shadow_root.z_index = 0
	add_child(_shadow_root)

	for polygon_name: String in ["ShadowBack", "ShadowForward"]:
		var polygon := Polygon2D.new()
		polygon.name = polygon_name
		polygon.texture = _shadow_texture
		polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		polygon.modulate = Color(1.0, 1.0, 1.0, SHADOW_OPACITY)
		_shadow_root.add_child(polygon)
		_shadow_polygons.append(polygon)
	_apply_shadow_hour()


func _rebuild_shadow_polygons() -> void:
	if _shadow_polygons.size() != 2:
		return
	var rect_points: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(_shadow_frame_size.x, 0.0),
		_shadow_frame_size,
		Vector2(0.0, _shadow_frame_size.y),
	]
	var back_points: Array[Vector2] = _clip_shadow_polygon(rect_points, false)
	var forward_points: Array[Vector2] = _clip_shadow_polygon(rect_points, true)
	_set_shadow_polygon(_shadow_polygons[0], back_points, false)
	_set_shadow_polygon(_shadow_polygons[1], forward_points, true)


func _set_shadow_polygon(polygon: Polygon2D, texture_points: Array[Vector2], stretch_forward: bool) -> void:
	var local_points: Array[Vector2] = []
	for point: Vector2 in texture_points:
		local_points.append(_shadow_texture_point_to_local(point, stretch_forward))
	polygon.polygon = PackedVector2Array(local_points)
	polygon.uv = PackedVector2Array(texture_points)


func _shadow_texture_point_to_local(point: Vector2, stretch_forward: bool) -> Vector2:
	var delta: Vector2 = point - _shadow_anchor_px
	if stretch_forward:
		var forward_distance: float = maxf(
			delta.dot(_shadow_direction) - _shadow_contact_lock_source_px,
			0.0
		)
		delta += _shadow_direction * forward_distance * (_shadow_length_scale - 1.0)
	return delta * _tree_scale


func _clip_shadow_polygon(points: Array[Vector2], keep_forward: bool) -> Array[Vector2]:
	if points.is_empty():
		return []
	var clipped: Array[Vector2] = []
	for index: int in range(points.size()):
		var current: Vector2 = points[index]
		var previous: Vector2 = points[(index + points.size() - 1) % points.size()]
		var current_inside: bool = _shadow_point_inside(current, keep_forward)
		var previous_inside: bool = _shadow_point_inside(previous, keep_forward)
		if current_inside:
			if not previous_inside:
				clipped.append(_shadow_line_intersection(previous, current))
			clipped.append(current)
		elif previous_inside:
			clipped.append(_shadow_line_intersection(previous, current))
	return clipped


func _shadow_point_inside(point: Vector2, keep_forward: bool) -> bool:
	var distance: float = _shadow_signed_distance(point)
	return distance >= -0.01 if keep_forward else distance <= 0.01


func _shadow_line_intersection(a: Vector2, b: Vector2) -> Vector2:
	var da: float = _shadow_signed_distance(a)
	var db: float = _shadow_signed_distance(b)
	var denominator: float = da - db
	if absf(denominator) < 0.0001:
		return a
	return a.lerp(b, clampf(da / denominator, 0.0, 1.0))


func _shadow_signed_distance(point: Vector2) -> float:
	return (point - _shadow_anchor_px).dot(_shadow_direction) - _shadow_contact_lock_source_px


func _resolve_shadow_direction() -> void:
	_shadow_direction = SHADOW_DIRECTION_NORTH_EAST
	_shadow_direction_name = "north_east"
	var bake_profile: Dictionary = _meta.get("bake_profile", {}) as Dictionary
	var fixed_direction: String = str(bake_profile.get("fixed_shadow_direction", ""))
	if fixed_direction == "screen_south_east":
		_shadow_direction = SHADOW_DIRECTION_SOUTH_EAST
		_shadow_direction_name = "south_east"
	var direction_value: Variant = bake_profile.get("fixed_shadow_direction_vector_screen", [])
	if direction_value is Array and (direction_value as Array).size() >= 2:
		var direction_array: Array = direction_value as Array
		var authored_direction := Vector2(float(direction_array[0]), float(direction_array[1]))
		if authored_direction.length_squared() > 0.0001:
			_shadow_direction = authored_direction.normalized()
			if fixed_direction.begins_with("screen_"):
				_shadow_direction_name = fixed_direction.trim_prefix("screen_")
	_shadow_contact_lock_source_px = maxf(
		float(bake_profile.get("shadow_contact_lock_source_px", 0.0)),
		0.0
	)


func _make_sprite(sprite_name: String, path: String, position: Vector2, scale_factor: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = _load_png_texture(path)
	sprite.centered = true
	sprite.position = position
	sprite.scale = Vector2.ONE * scale_factor
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sprite


func _load_png_texture(path: String) -> Texture2D:
	var image := Image.new()
	var err: int = image.load(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("LayeredTreeAssetLabScene: cannot load %s (err %d)" % [path, err])
		return null
	return ImageTexture.create_from_image(image)


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("LayeredTreeAssetLabScene: missing JSON %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("LayeredTreeAssetLabScene: invalid JSON %s" % path)
	return {}
