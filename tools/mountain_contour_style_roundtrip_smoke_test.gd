extends SceneTree

const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")
const MountainContourVisualLayer = preload("res://core/systems/world/mountain_contour_visual_layer.gd")

const STYLE_PATH: String = "res://assets/textures/terrain/mountains/mountain/mountain_contour_style.v1.json"
const EPSILON: float = 0.0001

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var data: Dictionary = _load_style_data()
	_mutate_style_data(data)

	var style: MountainContourStyle = MountainContourStyle.load_from_dict(data, STYLE_PATH.get_base_dir())
	_assert(style != null, "Mutated contour style must load from the generator-style package.")
	if style == null:
		quit(1)
		return

	_assert(style.has_method("to_shader_params"), "MountainContourStyle must expose to_shader_params() as the single shader handoff payload.")
	if not style.has_method("to_shader_params"):
		quit(1)
		return

	var shader_params: Dictionary = style.call("to_shader_params") as Dictionary
	_assert_shader_params(shader_params)
	_assert(style.has_method("to_runtime_geometry_params"), "MountainContourStyle must expose to_runtime_geometry_params() for native contour builder handoff.")
	if style.has_method("to_runtime_geometry_params"):
		_assert_geometry_params(style.call("to_runtime_geometry_params") as Dictionary)

	var layer := MountainContourVisualLayer.new()
	root.add_child(layer)
	layer.configure(Vector2i.ZERO, style)

	_assert(layer.has_method("get_style_shader_debug_snapshot"), "MountainContourVisualLayer must expose shader parameter debug snapshot.")
	if layer.has_method("get_style_shader_debug_snapshot"):
		var snapshot: Dictionary = layer.call("get_style_shader_debug_snapshot") as Dictionary
		_assert_layer_snapshot(snapshot)

	root.remove_child(layer)
	layer.free()
	quit(1 if _failed else 0)

func _load_style_data() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(STYLE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	_assert(parsed is Dictionary, "Default contour style JSON must parse as Dictionary.")
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}

func _mutate_style_data(data: Dictionary) -> void:
	data["top_world_scale_px"] = 333.0
	data["face_world_scale_px"] = 155.0
	data["macro_world_scale_px"] = 777.0
	data["texture_scale"] = 1.75
	data["south_height_px"] = 41.0
	data["side_height_px"] = 9.0
	data["corner_round_px"] = 23.0
	data["diagonal_smooth_px"] = 34.0
	data["contour_warp_px"] = 2.0
	data["rim_width_px"] = 21.0
	data["mountain_outline_enabled"] = false
	data["mountain_outline_width_px"] = 9.0
	data["normal_strength"] = 13.0
	data["normal_detail_strength"] = 2.5
	data["edge_debris"] = 0.12
	data["edge_color_strength"] = 0.91
	var colors: Dictionary = (data.get("colors", {}) as Dictionary).duplicate(true)
	colors["top"] = "#102030"
	colors["face"] = "#405060"
	colors["edge"] = "#708090"
	colors["base"] = "#a0b0c0"
	data["colors"] = colors

func _assert_shader_params(params: Dictionary) -> void:
	_assert_float(params, "top_world_scale_px", 333.0)
	_assert_float(params, "face_world_scale_px", 155.0)
	_assert_float(params, "macro_world_scale_px", 777.0)
	_assert_float(params, "texture_scale", 1.75)
	_assert_float(params, "south_height_px", 41.0)
	_assert_float(params, "side_height_px", 9.0)
	_assert_float(params, "rim_width_px", 21.0)
	_assert_bool(params, "mountain_outline_enabled", false)
	_assert_float(params, "mountain_outline_width_px", 9.0)
	_assert_float(params, "normal_strength", 13.0)
	_assert_float(params, "normal_detail_strength", 2.5)
	_assert_float(params, "edge_debris", 0.12)
	_assert_float(params, "edge_color_strength", 0.91)
	_assert_color(params, "top_tint", Color(16.0 / 255.0, 32.0 / 255.0, 48.0 / 255.0, 1.0))
	_assert_color(params, "face_tint", Color(64.0 / 255.0, 80.0 / 255.0, 96.0 / 255.0, 1.0))
	_assert_color(params, "edge_tint", Color(112.0 / 255.0, 128.0 / 255.0, 144.0 / 255.0, 1.0))
	_assert_color(params, "base_tint", Color(160.0 / 255.0, 176.0 / 255.0, 192.0 / 255.0, 1.0))
	for texture_key: String in [
		"top_albedo_tex",
		"face_albedo_tex",
		"base_albedo_tex",
		"top_modulation_tex",
		"face_modulation_tex",
		"top_normal_tex",
		"face_normal_tex",
		"edge_profile_lut",
		"height_profile_lut",
	]:
		_assert(params.get(texture_key, null) is Texture2D, "Shader params must include Texture2D %s." % [texture_key])

func _assert_geometry_params(params: Dictionary) -> void:
	_assert_float(params, "south_height_px", 41.0)
	_assert_float(params, "side_height_px", 9.0)
	_assert_float(params, "corner_round_px", 23.0)
	_assert_float(params, "diagonal_smooth_px", 34.0)
	_assert_float(params, "contour_warp_px", 2.0)
	_assert_float(params, "rim_width_px", 21.0)
	_assert_bool(params, "mountain_outline_enabled", false)
	_assert_float(params, "mountain_outline_width_px", 9.0)

func _assert_layer_snapshot(snapshot: Dictionary) -> void:
	for surface_id: String in ["top", "face", "rim", "outline"]:
		_assert(snapshot.has(surface_id), "Layer snapshot must include %s material." % [surface_id])
		var material_params: Dictionary = snapshot.get(surface_id, {}) as Dictionary
		_assert_float(material_params, "top_world_scale_px", 333.0)
		_assert_float(material_params, "face_world_scale_px", 155.0)
		_assert_float(material_params, "rim_width_px", 21.0)
		_assert_bool(material_params, "mountain_outline_enabled", false)
		_assert_float(material_params, "mountain_outline_width_px", 9.0)
		_assert_float(material_params, "edge_color_strength", 0.91)
		_assert_color(material_params, "top_tint", Color(16.0 / 255.0, 32.0 / 255.0, 48.0 / 255.0, 1.0))
	_assert_float(snapshot.get("top", {}) as Dictionary, "surface_zone", 0.0)
	_assert_float(snapshot.get("face", {}) as Dictionary, "surface_zone", 1.0)
	_assert_float(snapshot.get("rim", {}) as Dictionary, "surface_zone", 2.0)
	_assert_float(snapshot.get("outline", {}) as Dictionary, "surface_zone", 3.0)

func _assert_float(params: Dictionary, key: String, expected: float) -> void:
	_assert(params.has(key), "Missing float shader param %s." % [key])
	if not params.has(key):
		return
	_assert(absf(float(params[key]) - expected) <= EPSILON, "Shader param %s expected %.4f got %.4f." % [key, expected, float(params[key])])

func _assert_bool(params: Dictionary, key: String, expected: bool) -> void:
	_assert(params.has(key), "Missing bool shader param %s." % [key])
	if not params.has(key):
		return
	_assert(bool(params[key]) == expected, "Shader param %s expected %s got %s." % [key, str(expected), str(params[key])])

func _assert_color(params: Dictionary, key: String, expected: Color) -> void:
	_assert(params.has(key), "Missing color shader param %s." % [key])
	if not params.has(key):
		return
	var actual: Color = params[key] as Color
	_assert(absf(actual.r - expected.r) <= EPSILON, "Shader param %s.r mismatch." % [key])
	_assert(absf(actual.g - expected.g) <= EPSILON, "Shader param %s.g mismatch." % [key])
	_assert(absf(actual.b - expected.b) <= EPSILON, "Shader param %s.b mismatch." % [key])
	_assert(absf(actual.a - expected.a) <= EPSILON, "Shader param %s.a mismatch." % [key])

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
