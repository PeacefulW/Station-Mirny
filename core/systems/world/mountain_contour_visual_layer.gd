class_name MountainContourVisualLayer
extends Node2D

const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")
const RUNTIME_SHADER = preload("res://assets/shaders/mountain_contour_runtime.gdshader")

const ATTRIBUTE_STRIDE: int = 6
const SURFACE_IDS: Array[String] = ["top", "face", "rim", "outline"]
const SURFACE_PREFIX_BY_ID: Dictionary = {
	"top": "visual_top",
	"face": "visual_face",
	"rim": "visual_rim",
	"outline": "visual_outline",
}
const SURFACE_ZONE_BY_ID: Dictionary = {
	"top": 0.0,
	"face": 1.0,
	"rim": 2.0,
	"outline": 3.0,
}

var chunk_coord: Vector2i = Vector2i.ZERO

var _style: MountainContourStyle = null
var _mesh_nodes: Dictionary = {}
var _materials_by_surface: Dictionary = {}
var _surface_stats: Dictionary = {}
var _last_result_stats: Dictionary = {}

func _ready() -> void:
	z_index = 20
	_ensure_surface_nodes()

func configure(new_chunk_coord: Vector2i, style: MountainContourStyle) -> void:
	chunk_coord = new_chunk_coord
	_style = style
	_ensure_surface_nodes()
	_rebuild_materials()

func apply_runtime_result(result: Dictionary) -> bool:
	if _style == null:
		push_error("MountainContourVisualLayer: style must be configured before applying runtime result.")
		return false
	if not bool(result.get("ready", false)):
		clear_runtime_result()
		return false
	_ensure_surface_nodes()
	_last_result_stats = {
		"ready": true,
		"solid_sample_count": int(result.get("solid_sample_count", 0)),
		"boundary_edge_count": int(result.get("boundary_edge_count", 0)),
		"seam_touch_mask": int(result.get("seam_touch_mask", 0)),
		"compute_time_usec": int(result.get("compute_time_usec", 0)),
	}
	_surface_stats.clear()
	for surface_id: String in SURFACE_IDS:
		_apply_surface(surface_id, result)
	visible = get_total_vertex_count() > 0
	return true

func clear_runtime_result() -> void:
	for surface_id: String in SURFACE_IDS:
		var node: MeshInstance2D = _mesh_nodes.get(surface_id, null) as MeshInstance2D
		if node != null:
			node.mesh = null
	_surface_stats.clear()
	_last_result_stats = {"ready": false}
	visible = false

func get_total_vertex_count() -> int:
	var total: int = 0
	for surface_id: String in SURFACE_IDS:
		var stats: Dictionary = _surface_stats.get(surface_id, {}) as Dictionary
		total += int(stats.get("vertex_count", 0))
	return total

func get_debug_stats() -> Dictionary:
	var result: Dictionary = {
		"chunk_coord": chunk_coord,
		"material_ready": _materials_ready(),
		"surface_count": SURFACE_IDS.size(),
		"total_vertex_count": get_total_vertex_count(),
		"total_index_count": 0,
		"total_triangle_count": 0,
		"solid_sample_count": int(_last_result_stats.get("solid_sample_count", 0)),
		"boundary_edge_count": int(_last_result_stats.get("boundary_edge_count", 0)),
		"seam_touch_mask": int(_last_result_stats.get("seam_touch_mask", 0)),
		"compute_time_usec": int(_last_result_stats.get("compute_time_usec", 0)),
	}
	for surface_id: String in SURFACE_IDS:
		var stats: Dictionary = _surface_stats.get(surface_id, {}) as Dictionary
		var vertex_count: int = int(stats.get("vertex_count", 0))
		var index_count: int = int(stats.get("index_count", 0))
		var triangle_count: int = int(stats.get("triangle_count", 0))
		result["%s_vertex_count" % [surface_id]] = vertex_count
		result["%s_index_count" % [surface_id]] = index_count
		result["%s_triangle_count" % [surface_id]] = triangle_count
		result["total_index_count"] = int(result["total_index_count"]) + index_count
		result["total_triangle_count"] = int(result["total_triangle_count"]) + triangle_count
	return result

func _ensure_surface_nodes() -> void:
	for surface_index: int in SURFACE_IDS.size():
		var surface_id: String = SURFACE_IDS[surface_index]
		var existing: MeshInstance2D = _mesh_nodes.get(surface_id, null) as MeshInstance2D
		if existing != null and is_instance_valid(existing):
			continue
		var node := MeshInstance2D.new()
		node.name = "%s_mesh" % [surface_id]
		node.z_index = surface_index
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(node)
		_mesh_nodes[surface_id] = node

func _rebuild_materials() -> void:
	_materials_by_surface.clear()
	for surface_id: String in SURFACE_IDS:
		var material := ShaderMaterial.new()
		material.shader = RUNTIME_SHADER
		_apply_style_to_material(material, float(SURFACE_ZONE_BY_ID.get(surface_id, 0.0)))
		_materials_by_surface[surface_id] = material
		var node: MeshInstance2D = _mesh_nodes.get(surface_id, null) as MeshInstance2D
		if node != null:
			node.material = material

func _apply_style_to_material(material: ShaderMaterial, surface_zone: float) -> void:
	if _style == null:
		return
	material.set_shader_parameter("surface_zone", surface_zone)
	material.set_shader_parameter("top_albedo_tex", _style.top_albedo)
	material.set_shader_parameter("face_albedo_tex", _style.face_albedo)
	material.set_shader_parameter("base_albedo_tex", _style.base_albedo)
	material.set_shader_parameter("top_modulation_tex", _style.top_modulation)
	material.set_shader_parameter("face_modulation_tex", _style.face_modulation)
	material.set_shader_parameter("top_normal_tex", _style.top_normal)
	material.set_shader_parameter("face_normal_tex", _style.face_normal)
	material.set_shader_parameter("edge_profile_lut", _style.edge_profile_lut)
	material.set_shader_parameter("height_profile_lut", _style.height_profile_lut)
	material.set_shader_parameter("top_world_scale_px", _style.top_world_scale_px)
	material.set_shader_parameter("face_world_scale_px", _style.face_world_scale_px)
	material.set_shader_parameter("macro_world_scale_px", _style.macro_world_scale_px)
	material.set_shader_parameter("texture_scale", _style.texture_scale)
	material.set_shader_parameter("south_height_px", _style.south_height_px)
	material.set_shader_parameter("side_height_px", _style.side_height_px)
	material.set_shader_parameter("rim_width_px", _style.rim_width_px)
	material.set_shader_parameter("mountain_outline_enabled", _style.mountain_outline_enabled)
	material.set_shader_parameter("mountain_outline_width_px", _style.mountain_outline_width_px)
	material.set_shader_parameter("normal_strength", _style.normal_strength)
	material.set_shader_parameter("normal_detail_strength", _style.normal_detail_strength)
	material.set_shader_parameter("edge_debris", _style.edge_debris)
	material.set_shader_parameter("edge_color_strength", _style.edge_color_strength)
	material.set_shader_parameter("top_tint", _style_color("top", Color(0.44, 0.35, 0.25, 1.0)))
	material.set_shader_parameter("face_tint", _style_color("face", Color(0.24, 0.18, 0.14, 1.0)))
	material.set_shader_parameter("edge_tint", _style_color("edge", Color(0.29, 0.22, 0.17, 1.0)))
	material.set_shader_parameter("base_tint", _style_color("base", Color(0.72, 0.55, 0.35, 1.0)))

func _apply_surface(surface_id: String, result: Dictionary) -> void:
	var prefix: String = str(SURFACE_PREFIX_BY_ID.get(surface_id, ""))
	var vertices: PackedVector2Array = result.get("%s_vertices" % [prefix], PackedVector2Array()) as PackedVector2Array
	var indices: PackedInt32Array = result.get("%s_indices" % [prefix], PackedInt32Array()) as PackedInt32Array
	var attributes: PackedFloat32Array = result.get("%s_attributes" % [prefix], PackedFloat32Array()) as PackedFloat32Array
	var node: MeshInstance2D = _mesh_nodes.get(surface_id, null) as MeshInstance2D
	if node == null:
		return
	if vertices.is_empty() or indices.is_empty():
		node.mesh = null
		_surface_stats[surface_id] = {
			"vertex_count": 0,
			"index_count": 0,
			"triangle_count": 0,
		}
		return
	node.mesh = _build_array_mesh(vertices, indices, attributes, float(SURFACE_ZONE_BY_ID.get(surface_id, 0.0)))
	if _materials_by_surface.has(surface_id):
		node.material = _materials_by_surface[surface_id] as ShaderMaterial
	_surface_stats[surface_id] = {
		"vertex_count": vertices.size(),
		"index_count": indices.size(),
		"triangle_count": indices.size() / 3,
	}

func _build_array_mesh(
	vertices: PackedVector2Array,
	indices: PackedInt32Array,
	attributes: PackedFloat32Array,
	surface_zone: float
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _to_vector3_vertices(vertices)
	arrays[Mesh.ARRAY_TEX_UV] = _build_uvs(vertices)
	arrays[Mesh.ARRAY_TEX_UV2] = _build_noise_uvs(attributes, vertices.size())
	arrays[Mesh.ARRAY_COLOR] = _build_vertex_colors(attributes, vertices.size(), surface_zone)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _to_vector3_vertices(vertices: PackedVector2Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for index: int in vertices.size():
		var vertex: Vector2 = vertices[index]
		result[index] = Vector3(vertex.x, vertex.y, 0.0)
	return result

func _build_uvs(vertices: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(vertices.size())
	var scale: float = maxf(1.0, float(_style.logical_tile_size_px if _style != null else 64))
	for index: int in vertices.size():
		result[index] = vertices[index] / scale
	return result

func _build_noise_uvs(attributes: PackedFloat32Array, vertex_count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(vertex_count)
	for index: int in vertex_count:
		result[index] = Vector2(
			_read_attribute(attributes, index, 3, 0.0),
			_read_attribute(attributes, index, 4, 0.0)
		)
	return result

func _build_vertex_colors(attributes: PackedFloat32Array, vertex_count: int, surface_zone: float) -> PackedColorArray:
	var result := PackedColorArray()
	result.resize(vertex_count)
	for index: int in vertex_count:
		var edge_distance: float = clampf(_read_attribute(attributes, index, 0, 0.0) / 128.0, 0.0, 1.0)
		var face_depth: float = clampf(_read_attribute(attributes, index, 1, 0.0) / 128.0, 0.0, 1.0)
		var edge_kind: float = clampf(_read_attribute(attributes, index, 2, 0.0) / 8.0, 0.0, 1.0)
		var material_zone: float = clampf(_read_attribute(attributes, index, 5, surface_zone) / 8.0, 0.0, 1.0)
		result[index] = Color(edge_distance, face_depth, edge_kind, material_zone)
	return result

func _read_attribute(attributes: PackedFloat32Array, vertex_index: int, offset: int, default_value: float) -> float:
	var attribute_index: int = vertex_index * ATTRIBUTE_STRIDE + offset
	if attribute_index < 0 or attribute_index >= attributes.size():
		return default_value
	return float(attributes[attribute_index])

func _materials_ready() -> bool:
	if _style == null:
		return false
	if _materials_by_surface.size() != SURFACE_IDS.size():
		return false
	for surface_id: String in SURFACE_IDS:
		var material: ShaderMaterial = _materials_by_surface.get(surface_id, null) as ShaderMaterial
		if material == null or material.shader == null:
			return false
	return _style.top_albedo is Texture2D \
		and _style.face_albedo is Texture2D \
		and _style.base_albedo is Texture2D \
		and _style.top_normal is Texture2D \
		and _style.face_normal is Texture2D

func _style_color(color_id: String, fallback: Color) -> Color:
	if _style == null:
		return fallback
	var raw_value: String = str(_style.colors.get(color_id, ""))
	return _parse_hex_color(raw_value, fallback)

static func _parse_hex_color(raw_value: String, fallback: Color) -> Color:
	var text: String = raw_value.strip_edges()
	if text.begins_with("#"):
		text = text.substr(1)
	if text.length() != 6 and text.length() != 8:
		return fallback
	var red: float = float(text.substr(0, 2).hex_to_int()) / 255.0
	var green: float = float(text.substr(2, 2).hex_to_int()) / 255.0
	var blue: float = float(text.substr(4, 2).hex_to_int()) / 255.0
	var alpha: float = 1.0
	if text.length() == 8:
		alpha = float(text.substr(6, 2).hex_to_int()) / 255.0
	return Color(red, green, blue, alpha)
