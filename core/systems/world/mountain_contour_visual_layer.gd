class_name MountainContourVisualLayer
extends Node2D

const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")
const RUNTIME_SHADER = preload("res://assets/shaders/mountain_contour_runtime.gdshader")

const ATTRIBUTE_STRIDE: int = 8
const ATTR_EDGE_U: int = 0
const ATTR_EDGE_V: int = 1
const ATTR_SIGNED_DISTANCE: int = 2
const ATTR_FACE_DEPTH_NORM: int = 3
const ATTR_FACADE_SIDE: int = 4
const ATTR_ZONE: int = 5
const SURFACE_IDS: Array[String] = ["top", "face", "rim", "outline"]
const SURFACE_PREFIX_BY_ID: Dictionary = {
	"top": "visual_top",
	"face": "visual_face",
	"rim": "visual_rim",
	"outline": "visual_outline",
}
const SURFACE_Z_INDEX_BY_ID: Dictionary = {
	"top": 0,
	"face": 1,
	"rim": 2,
	"outline": 3,
}

var chunk_coord: Vector2i = Vector2i.ZERO

var _style: MountainContourStyle = null
var _mesh_nodes: Dictionary = {}
var _shared_material: ShaderMaterial = null
var _surface_stats: Dictionary = {}
var _last_result_stats: Dictionary = {}

func _ready() -> void:
	z_index = 20
	_ensure_surface_nodes()

func configure(new_chunk_coord: Vector2i, style: MountainContourStyle) -> void:
	chunk_coord = new_chunk_coord
	_style = style
	_ensure_surface_nodes()
	_rebuild_material()

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
		"material_ready": _material_ready(),
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
		var surface_params: Dictionary = {}
		if _shared_material != null:
			for parameter_name: String in MountainContourStyle.SHADER_PARAMETER_NAMES:
				surface_params[parameter_name] = _shared_material.get_shader_parameter(parameter_name)
		if _style != null:
			surface_params["texture_paths"] = _style.texture_paths.duplicate(true)
			surface_params["style_debug"] = _style.debug_snapshot()
		result[surface_id] = surface_params
	return result

func _ensure_surface_nodes() -> void:
	for surface_id: String in SURFACE_IDS:
		var existing: MeshInstance2D = _mesh_nodes.get(surface_id, null) as MeshInstance2D
		if existing != null and is_instance_valid(existing):
			continue
		var node := MeshInstance2D.new()
		node.name = "%s_mesh" % [surface_id]
		node.z_index = int(SURFACE_Z_INDEX_BY_ID.get(surface_id, 0))
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(node)
		_mesh_nodes[surface_id] = node

func _rebuild_material() -> void:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = RUNTIME_SHADER
	_apply_style_to_material(_shared_material)
	for surface_id: String in SURFACE_IDS:
		var node: MeshInstance2D = _mesh_nodes.get(surface_id, null) as MeshInstance2D
		if node != null:
			node.material = _shared_material

func _apply_style_to_material(material: ShaderMaterial) -> void:
	if _style == null:
		return
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
	node.mesh = _build_array_mesh(vertices, indices, attributes)
	if _shared_material != null:
		node.material = _shared_material
	_surface_stats[surface_id] = {
		"vertex_count": vertices.size(),
		"index_count": indices.size(),
		"triangle_count": indices.size() / 3,
	}

func _build_array_mesh(
	vertices: PackedVector2Array,
	indices: PackedInt32Array,
	attributes: PackedFloat32Array
) -> ArrayMesh:
	var vertex_count: int = vertices.size()
	var vertices_3d := PackedVector3Array()
	vertices_3d.resize(vertex_count)
	var uvs := PackedVector2Array()
	uvs.resize(vertex_count)
	var colors := PackedColorArray()
	colors.resize(vertex_count)
	for index: int in vertex_count:
		var vertex: Vector2 = vertices[index]
		vertices_3d[index] = Vector3(vertex.x, vertex.y, 0.0)
		var stride_base: int = index * ATTRIBUTE_STRIDE
		var edge_u: float = 0.0
		var edge_v: float = 0.0
		var signed_distance: float = 0.0
		var face_depth_norm: float = 0.0
		var facade_side: float = 0.0
		var zone: float = 0.0
		if stride_base + ATTRIBUTE_STRIDE <= attributes.size():
			edge_u = attributes[stride_base + ATTR_EDGE_U]
			edge_v = attributes[stride_base + ATTR_EDGE_V]
			signed_distance = attributes[stride_base + ATTR_SIGNED_DISTANCE]
			face_depth_norm = attributes[stride_base + ATTR_FACE_DEPTH_NORM]
			facade_side = attributes[stride_base + ATTR_FACADE_SIDE]
			zone = attributes[stride_base + ATTR_ZONE]
		uvs[index] = Vector2(edge_u, edge_v)
		colors[index] = Color(
			clampf(signed_distance / 256.0 + 0.5, 0.0, 1.0),
			clampf(face_depth_norm, 0.0, 1.0),
			clampf(facade_side / 4.0, 0.0, 1.0),
			clampf(zone / 8.0, 0.0, 1.0)
		)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices_3d
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _material_ready() -> bool:
	if _style == null:
		return false
	if _shared_material == null or _shared_material.shader == null:
		return false
	return _style.top_albedo is Texture2D \
		and _style.face_albedo is Texture2D \
		and _style.base_albedo is Texture2D \
		and _style.top_normal is Texture2D \
		and _style.face_normal is Texture2D
