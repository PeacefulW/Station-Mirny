class_name MountainContourStyle
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const SCHEMA_VERSION: int = 1
const REQUIRED_TEXTURE_FIELDS: Array[String] = [
	"top_albedo",
	"face_albedo",
	"base_albedo",
	"top_modulation",
	"face_modulation",
	"top_normal",
	"face_normal",
	"edge_profile_lut",
	"height_profile_lut",
]
const REQUIRED_SCALAR_FIELDS: Array[String] = [
	"schema_version",
	"asset_name",
	"preset",
	"logical_tile_size_px",
	"style_tile_size_px",
	"south_height_px",
	"north_height_px",
	"side_height_px",
	"corner_round_px",
	"diagonal_smooth_px",
	"contour_warp_px",
	"roughness",
	"corner_variation",
	"rim_width_px",
	"edge_debris",
	"edge_color_strength",
	"mountain_outline_enabled",
	"mountain_outline_width_px",
	"normal_strength",
	"normal_detail_strength",
	"top_world_scale_px",
	"face_world_scale_px",
	"macro_world_scale_px",
	"texture_scale",
	"colors",
	"texture_paths",
	"reference_preview_path",
	"reference_normal_path",
]
const REQUIRED_COLOR_FIELDS: Array[String] = ["top", "face", "edge", "base"]
const RUNTIME_GEOMETRY_PARAMETER_NAMES: Array[String] = [
	"south_height_px",
	"north_height_px",
	"side_height_px",
	"corner_round_px",
	"diagonal_smooth_px",
	"contour_warp_px",
	"roughness",
	"corner_variation",
	"rim_width_px",
	"mountain_outline_enabled",
	"mountain_outline_width_px",
]
const SHADER_PARAMETER_NAMES: Array[String] = [
	"top_albedo_tex",
	"face_albedo_tex",
	"base_albedo_tex",
	"top_modulation_tex",
	"face_modulation_tex",
	"top_normal_tex",
	"face_normal_tex",
	"edge_profile_lut",
	"height_profile_lut",
	"top_world_scale_px",
	"face_world_scale_px",
	"macro_world_scale_px",
	"texture_scale",
	"south_height_px",
	"side_height_px",
	"rim_width_px",
	"mountain_outline_enabled",
	"mountain_outline_width_px",
	"normal_strength",
	"normal_detail_strength",
	"edge_debris",
	"edge_color_strength",
	"top_tint",
	"face_tint",
	"edge_tint",
	"base_tint",
]

var asset_name: StringName
var preset: StringName
var logical_tile_size_px: int
var style_tile_size_px: int
var south_height_px: float
var north_height_px: float
var side_height_px: float
var corner_round_px: float
var diagonal_smooth_px: float
var contour_warp_px: float
var roughness: float
var corner_variation: float
var rim_width_px: float
var edge_debris: float
var edge_color_strength: float
var mountain_outline_enabled: bool
var mountain_outline_width_px: float
var normal_strength: float
var normal_detail_strength: float
var top_world_scale_px: float
var face_world_scale_px: float
var macro_world_scale_px: float
var texture_scale: float
var colors: Dictionary = {}
var texture_paths: Dictionary = {}
var reference_preview_path: String = ""
var reference_normal_path: String = ""
var source_path: String = ""
var source_signature: Dictionary = {}

var top_albedo: Texture2D
var face_albedo: Texture2D
var base_albedo: Texture2D
var top_modulation: Texture2D
var face_modulation: Texture2D
var top_normal: Texture2D
var face_normal: Texture2D
var edge_profile_lut: Texture2D
var height_profile_lut: Texture2D

static func load_from_file(style_path: String) -> MountainContourStyle:
	if not FileAccess.file_exists(style_path):
		push_error("MountainContourStyle: style JSON is missing: %s" % [style_path])
		return null
	var text: String = FileAccess.get_file_as_string(style_path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		push_error("MountainContourStyle: style JSON is not a dictionary: %s" % [style_path])
		return null
	var style: MountainContourStyle = load_from_dict(parsed as Dictionary, style_path.get_base_dir())
	if style != null:
		style.source_path = style_path
		style._rebuild_source_signature(style_path)
	return style

static func load_from_dict(data: Dictionary, base_dir: String) -> MountainContourStyle:
	for field_name: String in REQUIRED_SCALAR_FIELDS:
		if not data.has(field_name):
			push_error("MountainContourStyle: missing required field '%s'." % [field_name])
			return null
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		push_error("MountainContourStyle: unsupported schema_version %s." % [str(data.get("schema_version", null))])
		return null

	if data.get("colors", null) is not Dictionary:
		push_error("MountainContourStyle: colors must be a dictionary.")
		return null
	if data.get("texture_paths", null) is not Dictionary:
		push_error("MountainContourStyle: texture_paths must be a dictionary.")
		return null
	var texture_path_values: Dictionary = data.get("texture_paths", {}) as Dictionary
	for texture_field: String in REQUIRED_TEXTURE_FIELDS:
		if not texture_path_values.has(texture_field) or str(texture_path_values.get(texture_field, "")).is_empty():
			push_error("MountainContourStyle: missing required texture path '%s'." % [texture_field])
			return null

	var style := new()
	style.asset_name = StringName(str(data.get("asset_name", "")))
	style.preset = StringName(str(data.get("preset", "")))
	style.logical_tile_size_px = int(data.get("logical_tile_size_px", 0))
	style.style_tile_size_px = int(data.get("style_tile_size_px", 0))
	style.south_height_px = float(data.get("south_height_px", 0.0))
	style.north_height_px = float(data.get("north_height_px", 0.0))
	style.side_height_px = float(data.get("side_height_px", 0.0))
	style.corner_round_px = float(data.get("corner_round_px", 0.0))
	style.diagonal_smooth_px = float(data.get("diagonal_smooth_px", 0.0))
	style.contour_warp_px = float(data.get("contour_warp_px", 0.0))
	style.roughness = float(data.get("roughness", 0.0))
	style.corner_variation = float(data.get("corner_variation", 0.0))
	style.rim_width_px = float(data.get("rim_width_px", 0.0))
	style.edge_debris = float(data.get("edge_debris", 0.0))
	style.edge_color_strength = float(data.get("edge_color_strength", 0.0))
	style.mountain_outline_enabled = bool(data.get("mountain_outline_enabled", false))
	style.mountain_outline_width_px = float(data.get("mountain_outline_width_px", 0.0))
	style.normal_strength = float(data.get("normal_strength", 0.0))
	style.normal_detail_strength = float(data.get("normal_detail_strength", 0.0))
	style.top_world_scale_px = float(data.get("top_world_scale_px", 0.0))
	style.face_world_scale_px = float(data.get("face_world_scale_px", 0.0))
	style.macro_world_scale_px = float(data.get("macro_world_scale_px", 0.0))
	style.texture_scale = float(data.get("texture_scale", 0.0))
	style.colors = (data.get("colors", {}) as Dictionary).duplicate(true)
	style.reference_preview_path = _resolve_style_path(base_dir, str(data.get("reference_preview_path", "")))
	style.reference_normal_path = _resolve_style_path(base_dir, str(data.get("reference_normal_path", "")))
	style.texture_paths = {}

	if not style._validate_scalar_ranges() or not style._validate_colors():
		return null
	if not style._load_textures(texture_path_values, base_dir):
		return null
	style._rebuild_source_signature("")
	return style

func debug_snapshot() -> Dictionary:
	return {
		"asset_name": String(asset_name),
		"preset": String(preset),
		"logical_tile_size_px": logical_tile_size_px,
		"style_tile_size_px": style_tile_size_px,
		"south_height_px": south_height_px,
		"north_height_px": north_height_px,
		"side_height_px": side_height_px,
		"corner_round_px": corner_round_px,
		"diagonal_smooth_px": diagonal_smooth_px,
		"contour_warp_px": contour_warp_px,
		"roughness": roughness,
		"corner_variation": corner_variation,
		"rim_width_px": rim_width_px,
		"edge_debris": edge_debris,
		"edge_color_strength": edge_color_strength,
		"mountain_outline_enabled": mountain_outline_enabled,
		"mountain_outline_width_px": mountain_outline_width_px,
		"normal_strength": normal_strength,
		"normal_detail_strength": normal_detail_strength,
		"top_world_scale_px": top_world_scale_px,
		"face_world_scale_px": face_world_scale_px,
		"macro_world_scale_px": macro_world_scale_px,
		"texture_scale": texture_scale,
		"colors": colors.duplicate(true),
		"texture_count": texture_paths.size(),
		"texture_paths": texture_paths.duplicate(true),
		"reference_preview_path": reference_preview_path,
		"reference_normal_path": reference_normal_path,
		"source_path": source_path,
		"source_signature": get_source_signature(),
	}

func to_shader_params() -> Dictionary:
	return {
		"top_albedo_tex": top_albedo,
		"face_albedo_tex": face_albedo,
		"base_albedo_tex": base_albedo,
		"top_modulation_tex": top_modulation,
		"face_modulation_tex": face_modulation,
		"top_normal_tex": top_normal,
		"face_normal_tex": face_normal,
		"edge_profile_lut": edge_profile_lut,
		"height_profile_lut": height_profile_lut,
		"top_world_scale_px": top_world_scale_px,
		"face_world_scale_px": face_world_scale_px,
		"macro_world_scale_px": macro_world_scale_px,
		"texture_scale": texture_scale,
		"south_height_px": south_height_px,
		"side_height_px": side_height_px,
		"rim_width_px": rim_width_px,
		"mountain_outline_enabled": mountain_outline_enabled,
		"mountain_outline_width_px": mountain_outline_width_px,
		"normal_strength": normal_strength,
		"normal_detail_strength": normal_detail_strength,
		"edge_debris": edge_debris,
		"edge_color_strength": edge_color_strength,
		"top_tint": color_value("top"),
		"face_tint": color_value("face"),
		"edge_tint": color_value("edge"),
		"base_tint": color_value("base"),
	}

func to_runtime_geometry_params() -> Dictionary:
	return {
		"south_height_px": south_height_px,
		"north_height_px": north_height_px,
		"side_height_px": side_height_px,
		"corner_round_px": corner_round_px,
		"diagonal_smooth_px": diagonal_smooth_px,
		"contour_warp_px": contour_warp_px,
		"roughness": roughness,
		"corner_variation": corner_variation,
		"rim_width_px": rim_width_px,
		"mountain_outline_enabled": mountain_outline_enabled,
		"mountain_outline_width_px": mountain_outline_width_px,
	}

func color_value(color_id: String) -> Color:
	return _parse_hex_color(str(colors.get(color_id, "#ffffff")), Color(1.0, 1.0, 1.0, 1.0))

func get_source_signature() -> Dictionary:
	return source_signature.duplicate(true)

func _validate_scalar_ranges() -> bool:
	if String(asset_name).is_empty():
		push_error("MountainContourStyle: asset_name must not be empty.")
		return false
	if logical_tile_size_px != WorldRuntimeConstants.TILE_SIZE_PX:
		push_error("MountainContourStyle: logical_tile_size_px must be %d, got %d." % [WorldRuntimeConstants.TILE_SIZE_PX, logical_tile_size_px])
		return false
	if style_tile_size_px < 1 or style_tile_size_px > 4096:
		push_error("MountainContourStyle: style_tile_size_px is outside safe range.")
		return false
	for field_name: String in ["south_height_px", "north_height_px", "side_height_px"]:
		if not _float_in_range(get(field_name), 0.0, 512.0):
			push_error("MountainContourStyle: %s is outside safe range." % [field_name])
			return false
	for field_name: String in ["corner_round_px", "diagonal_smooth_px", "contour_warp_px", "rim_width_px", "mountain_outline_width_px"]:
		if not _float_in_range(get(field_name), 0.0, 256.0):
			push_error("MountainContourStyle: %s is outside safe range." % [field_name])
			return false
	if not _float_in_range(roughness, 0.0, 100.0):
		push_error("MountainContourStyle: roughness is outside safe range.")
		return false
	if not _float_in_range(corner_variation, 0.0, 1.0):
		push_error("MountainContourStyle: corner_variation is outside safe range.")
		return false
	if not _float_in_range(edge_debris, 0.0, 1.0):
		push_error("MountainContourStyle: edge_debris is outside safe range.")
		return false
	if not _float_in_range(edge_color_strength, 0.0, 1.0):
		push_error("MountainContourStyle: edge_color_strength is outside safe range.")
		return false
	if not _float_in_range(normal_strength, 0.0, 16.0) or not _float_in_range(normal_detail_strength, 0.0, 16.0):
		push_error("MountainContourStyle: normal strength is outside safe range.")
		return false
	if not _float_in_range(top_world_scale_px, 1.0, 4096.0):
		push_error("MountainContourStyle: top_world_scale_px is outside safe range.")
		return false
	if not _float_in_range(face_world_scale_px, 1.0, 4096.0):
		push_error("MountainContourStyle: face_world_scale_px is outside safe range.")
		return false
	if not _float_in_range(macro_world_scale_px, 1.0, 8192.0):
		push_error("MountainContourStyle: macro_world_scale_px is outside safe range.")
		return false
	if not _float_in_range(texture_scale, 0.01, 16.0):
		push_error("MountainContourStyle: texture_scale is outside safe range.")
		return false
	return true

func _validate_colors() -> bool:
	for color_field: String in REQUIRED_COLOR_FIELDS:
		if not colors.has(color_field):
			push_error("MountainContourStyle: missing required color '%s'." % [color_field])
			return false
		if not _is_valid_hex_color(str(colors.get(color_field, ""))):
			push_error("MountainContourStyle: color '%s' must be a #RRGGBB or #RRGGBBAA value." % [color_field])
			return false
	return true

func _load_textures(source_paths: Dictionary, base_dir: String) -> bool:
	for texture_field: String in REQUIRED_TEXTURE_FIELDS:
		var resolved_path: String = _resolve_style_path(base_dir, str(source_paths.get(texture_field, "")))
		var texture: Texture2D = _load_texture2d(resolved_path)
		if texture == null:
			push_error("MountainContourStyle: texture '%s' failed to load as Texture2D: %s" % [texture_field, resolved_path])
			return false
		texture_paths[texture_field] = resolved_path
		set(texture_field, texture)
	return true

static func _resolve_style_path(base_dir: String, source_path: String) -> String:
	if source_path.begins_with("res://") or source_path.begins_with("user://"):
		return source_path
	return base_dir.path_join(source_path)

static func _load_texture2d(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var uncached_texture: Texture2D = _load_texture2d_uncached(path)
	if uncached_texture != null:
		return uncached_texture
	if ResourceLoader.exists(path):
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is Texture2D:
			return resource as Texture2D
	return null

static func _load_texture2d_uncached(path: String) -> Texture2D:
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _rebuild_source_signature(style_file_path: String) -> void:
	var texture_signatures: Dictionary = {}
	for texture_field: String in REQUIRED_TEXTURE_FIELDS:
		texture_signatures[texture_field] = _file_signature(str(texture_paths.get(texture_field, "")))
	source_signature = {
		"style_path": style_file_path,
		"style": _file_signature(style_file_path) if not style_file_path.is_empty() else {},
		"textures": texture_signatures,
		"reference_preview": _file_signature(reference_preview_path),
		"reference_normal": _file_signature(reference_normal_path),
	}

static func _float_in_range(value: float, min_value: float, max_value: float) -> bool:
	return value >= min_value and value <= max_value

static func _file_signature(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {
			"path": path,
			"exists": false,
			"modified_time": 0,
			"size_bytes": 0,
		}
	var size_bytes: int = 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		size_bytes = int(file.get_length())
		file.close()
	return {
		"path": path,
		"exists": true,
		"modified_time": int(FileAccess.get_modified_time(path)),
		"size_bytes": size_bytes,
	}

static func _is_valid_hex_color(raw_value: String) -> bool:
	var text: String = raw_value.strip_edges()
	if text.begins_with("#"):
		text = text.substr(1)
	if text.length() != 6 and text.length() != 8:
		return false
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		var is_digit: bool = code >= 48 and code <= 57
		var is_upper: bool = code >= 65 and code <= 70
		var is_lower: bool = code >= 97 and code <= 102
		if not is_digit and not is_upper and not is_lower:
			return false
	return true

static func _parse_hex_color(raw_value: String, fallback: Color) -> Color:
	var text: String = raw_value.strip_edges()
	if text.begins_with("#"):
		text = text.substr(1)
	if not _is_valid_hex_color(text):
		return fallback
	var red: float = float(text.substr(0, 2).hex_to_int()) / 255.0
	var green: float = float(text.substr(2, 2).hex_to_int()) / 255.0
	var blue: float = float(text.substr(4, 2).hex_to_int()) / 255.0
	var alpha: float = 1.0
	if text.length() == 8:
		alpha = float(text.substr(6, 2).hex_to_int()) / 255.0
	return Color(red, green, blue, alpha)
