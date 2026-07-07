class_name LayeredTreeAssetLabScene
extends Node2D

const TREE_DIR: String = "res://assets/sprites/flora/layered_trees/tree_01"
const FOLIAGE_WIND_SHADER: Shader = preload("res://assets/shaders/layered_tree_foliage_wind.gdshader")

var _meta: Dictionary = {}
var _root_position: Vector2 = Vector2(512.0, 620.0)
var _tree_scale: float = 0.86
var _wind_strength_px: float = 2.4
var _snow_enabled: bool = false
var _shadow_hour: float = 14.5
var _shadow_anchor_delta_px: Vector2 = Vector2.ZERO
var _shadow_sprite: Sprite2D = null
var _foliage_material: ShaderMaterial = null
var _snow_sprite: Sprite2D = null
var _hud_label: Label = null


func _ready() -> void:
	name = "LayeredTreeAssetLabScene"
	_meta = _load_json_dictionary("%s/meta.json" % TREE_DIR)
	_build_tree()
	_build_camera()
	_build_hud()
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()
	if _foliage_material != null:
		_foliage_material.set_shader_parameter("wind_strength_px", _wind_strength_px)
	if _snow_sprite != null:
		_snow_sprite.visible = _snow_enabled
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
			_snow_enabled = not _snow_enabled
			get_viewport().set_input_as_handled()
		KEY_EQUAL, KEY_PLUS:
			_wind_strength_px = minf(_wind_strength_px + 0.4, 8.0)
			get_viewport().set_input_as_handled()
		KEY_MINUS:
			_wind_strength_px = maxf(_wind_strength_px - 0.4, 0.0)
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1024.0, 768.0)), Color(0.18, 0.165, 0.135, 1.0))
	for y: int in range(0, 768, 32):
		var tint: float = 0.02 if (y / 32) % 2 == 0 else 0.0
		draw_rect(Rect2(Vector2(0.0, float(y)), Vector2(1024.0, 16.0)), Color(0.15 + tint, 0.14 + tint, 0.115 + tint, 1.0))
	draw_line(Vector2(0.0, _root_position.y), Vector2(1024.0, _root_position.y), Color(0.7, 0.48, 0.22, 0.45), 1.0)


func get_debug_snapshot() -> Dictionary:
	return {
		"ready": not _meta.is_empty(),
		"asset": str(_meta.get("asset", "")),
		"anchor": _meta.get("anchor", []),
		"has_shadow": get_node_or_null("Shadow") != null,
		"has_trunk": get_node_or_null("Trunk") != null,
		"has_foliage": get_node_or_null("Foliage") != null,
		"has_snow": get_node_or_null("SnowOverlay") != null,
		"wind_strength_px": _wind_strength_px,
		"snow_enabled": _snow_enabled,
		"shadow_hour": _shadow_hour,
	}


func _build_tree() -> void:
	var frame_width: float = float(_meta.get("frame_width", 768))
	var frame_height: float = float(_meta.get("frame_height", 768))
	var anchor_array: Array = _meta.get("anchor", [frame_width * 0.5, frame_height * 0.84]) as Array
	var anchor := Vector2(float(anchor_array[0]), float(anchor_array[1]))
	var center := Vector2(frame_width, frame_height) * 0.5
	var sprite_position: Vector2 = _root_position - (anchor - center) * _tree_scale
	_shadow_anchor_delta_px = anchor - center

	var shadow := _make_sprite("Shadow", "%s/shadow.png" % TREE_DIR, sprite_position, _tree_scale)
	shadow.z_index = 0
	shadow.modulate = Color(1.0, 1.0, 1.0, 0.95)
	_shadow_sprite = shadow
	add_child(shadow)
	_apply_shadow_hour()

	var trunk := _make_sprite("Trunk", "%s/trunk.png" % TREE_DIR, sprite_position, _tree_scale)
	trunk.z_index = 2
	add_child(trunk)

	var foliage := _make_sprite("Foliage", "%s/foliage.png" % TREE_DIR, sprite_position, _tree_scale)
	foliage.z_index = 3
	_foliage_material = ShaderMaterial.new()
	_foliage_material.shader = FOLIAGE_WIND_SHADER
	_foliage_material.set_shader_parameter("wind_mask_texture", _load_png_texture("%s/wind_mask.png" % TREE_DIR))
	_foliage_material.set_shader_parameter("wind_strength_px", _wind_strength_px)
	foliage.material = _foliage_material
	add_child(foliage)

	_snow_sprite = _make_sprite("SnowOverlay", "%s/snow_overlay.png" % TREE_DIR, sprite_position, _tree_scale)
	_snow_sprite.z_index = 4
	_snow_sprite.visible = _snow_enabled
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
	_hud_label.text = "Layered tree asset lab | Space snow: %s | +/- wind %.1f px | Q/E shadow %.1f h | 1/2/3" % [
		"ON" if _snow_enabled else "OFF",
		_wind_strength_px,
		_shadow_hour,
	]


func _apply_shadow_hour() -> void:
	if _shadow_sprite == null:
		return
	var t: float = clampf((_shadow_hour - 13.0) / 3.0, 0.0, 1.0)
	var angle: float = deg_to_rad(lerpf(0.0, 72.0, t))
	var scale_vec := Vector2(
		_tree_scale * lerpf(0.97, 1.08, t),
		_tree_scale * lerpf(0.96, 1.18, t)
	)
	var scaled_anchor_delta := Vector2(
		_shadow_anchor_delta_px.x * scale_vec.x,
		_shadow_anchor_delta_px.y * scale_vec.y
	)
	_shadow_sprite.rotation = angle
	_shadow_sprite.scale = scale_vec
	_shadow_sprite.position = _root_position - scaled_anchor_delta.rotated(angle)


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
	if FileAccess.file_exists(path + ".import"):
		var imported: Texture2D = load(path) as Texture2D
		if imported != null:
			return imported
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
