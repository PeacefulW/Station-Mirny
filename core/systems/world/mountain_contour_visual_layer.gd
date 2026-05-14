class_name MountainContourVisualLayer
extends Node2D

const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")
const RUNTIME_SHADER = preload("res://assets/shaders/mountain_contour_runtime.gdshader")

const ATTRIBUTE_STRIDE: int = 8
const ATTR_EDGE_U: int = 0
const ATTR_EDGE_V: int = 1
const ATTR_SIGNED_DISTANCE: int = 2
const ATTR_FACE_DEPTH_PX: int = 3
const ATTR_FACADE_SIDE: int = 4
const ATTR_ZONE: int = 5
const ATTR_NOISE_U: int = 6
const ATTR_NOISE_V: int = 7
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

func get_style_shader_debug_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for surface_id: String in SURFACE_IDS:
		var material: ShaderMaterial = _materials_by_surface.get(surface_id, null) as ShaderMaterial
		var surface_params: Dictionary = {}
		if material != null:
			surface_params["surface_zone"] = material.get_shader_parameter("surface_zone")
			for parameter_name: String in MountainContourStyle.SHADER_PARAMETER_NAMES:
				surface_params[parameter_name] = material.get_shader_parameter(parameter_name)
		if _style != null:
			surface_params["texture_paths"] = _style.texture_paths.duplicate(true)
			surface_params["style_debug"] = _style.debug_snapshot()
		result[surface_id] = surface_params
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
	var shader_params: Dictionary = _style.to_shader_params()
	for parameter_name: String in shader_params.keys():
		material.set_shader_parameter(parameter_name, shader_params[parameter_name])

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
	arrays[Mesh.ARRAY_TEX_UV] = _build_edge_uvs(attributes, vertices.size())
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

func _build_edge_uvs(attributes: PackedFloat32Array, vertex_count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(vertex_count)
	for index: int in vertex_count:
		result[index] = Vector2(
			_read_attribute(attributes, index, ATTR_EDGE_U, 0.0),
			_read_attribute(attributes, index, ATTR_EDGE_V, 0.0)
		)
	return result

func _build_vertex_colors(attributes: PackedFloat32Array, vertex_count: int, surface_zone: float) -> PackedColorArray:
	var result := PackedColorArray()
	result.resize(vertex_count)
	for index: int in vertex_count:
		var signed_distance: float = clampf((_read_attribute(attributes, index, ATTR_SIGNED_DISTANCE, 0.0) + 128.0) / 256.0, 0.0, 1.0)
		var face_depth_px: float = clampf(_read_attribute(attributes, index, ATTR_FACE_DEPTH_PX, 0.0) / 128.0, 0.0, 1.0)
		var facade_side: float = clampf(_read_attribute(attributes, index, ATTR_FACADE_SIDE, 0.0) / 4.0, 0.0, 1.0)
		var zone: float = clampf(_read_attribute(attributes, index, ATTR_ZONE, surface_zone) / 8.0, 0.0, 1.0)
		result[index] = Color(signed_distance, face_depth_px, facade_side, zone)
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
