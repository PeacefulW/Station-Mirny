class_name ChunkDebugVisualLayer
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const GRID_COLOR: Color = Color(0.82, 0.88, 0.9, 0.55)
const SOLID_MASK_COLOR: Color = Color(1.0, 0.34, 0.12, 0.34)
const CONTOUR_FILL_COLOR: Color = Color(0.0, 0.92, 1.0, 0.22)
const CONTOUR_LINE_COLOR: Color = Color(0.0, 1.0, 1.0, 0.88)
const CONTOUR_VERTEX_COLOR: Color = Color(1.0, 1.0, 1.0, 0.88)
const GRID_WIDTH: float = 1.0
const CONTOUR_LINE_WIDTH: float = 1.5
const VERTEX_RADIUS: float = 2.0

var chunk_coord: Vector2i = Vector2i.ZERO

var _grid_visible: bool = false
var _solid_mask_visible: bool = false
var _contour_visible: bool = false
var _solid_mask: PackedByteArray = PackedByteArray()
var _contour_vertices: PackedVector2Array = PackedVector2Array()
var _contour_indices: PackedInt32Array = PackedInt32Array()

func _ready() -> void:
	z_index = 30

func configure(new_chunk_coord: Vector2i) -> void:
	chunk_coord = new_chunk_coord
	queue_redraw()

func set_debug_visibility(grid_visible: bool, solid_mask_visible: bool, contour_visible: bool) -> void:
	_grid_visible = grid_visible
	_solid_mask_visible = solid_mask_visible
	_contour_visible = contour_visible
	visible = _grid_visible or _solid_mask_visible or _contour_visible
	queue_redraw()

func set_debug_data(
	solid_mask: PackedByteArray,
	contour_vertices: PackedVector2Array,
	contour_indices: PackedInt32Array
) -> void:
	_solid_mask = solid_mask.duplicate()
	if _solid_mask.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_solid_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_contour_vertices = contour_vertices.duplicate()
	_contour_indices = contour_indices.duplicate()
	queue_redraw()

func get_debug_state() -> Dictionary:
	return {
		"chunk_coord": chunk_coord,
		"grid_visible": _grid_visible,
		"solid_mask_visible": _solid_mask_visible,
		"contour_visible": _contour_visible,
		"solid_tile_count": _count_solid_tiles(),
		"contour_vertex_count": _contour_vertices.size(),
		"contour_index_count": _contour_indices.size(),
		"contour_triangle_count": _contour_indices.size() / 3,
	}

func _draw() -> void:
	if _solid_mask_visible:
		_draw_solid_mask()
	if _grid_visible:
		_draw_grid()
	if _contour_visible:
		_draw_contour_mesh()

func _draw_solid_mask() -> void:
	var tile_size: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	for index: int in range(mini(_solid_mask.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		if int(_solid_mask[index]) == 0:
			continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		draw_rect(
			Rect2(Vector2(local_coord) * tile_size, Vector2(tile_size, tile_size)),
			SOLID_MASK_COLOR,
			true
		)

func _draw_grid() -> void:
	var tile_size: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	var chunk_px: float = tile_size * float(WorldRuntimeConstants.CHUNK_SIZE)
	for line_index: int in range(WorldRuntimeConstants.CHUNK_SIZE + 1):
		var offset_px: float = float(line_index) * tile_size
		draw_line(Vector2(offset_px, 0.0), Vector2(offset_px, chunk_px), GRID_COLOR, GRID_WIDTH)
		draw_line(Vector2(0.0, offset_px), Vector2(chunk_px, offset_px), GRID_COLOR, GRID_WIDTH)

func _draw_contour_mesh() -> void:
	for index: int in range(0, _contour_indices.size(), 3):
		if index + 2 >= _contour_indices.size():
			break
		var a_index: int = int(_contour_indices[index])
		var b_index: int = int(_contour_indices[index + 1])
		var c_index: int = int(_contour_indices[index + 2])
		if not _is_vertex_index_valid(a_index) \
				or not _is_vertex_index_valid(b_index) \
				or not _is_vertex_index_valid(c_index):
			continue
		var a: Vector2 = _contour_vertices[a_index]
		var b: Vector2 = _contour_vertices[b_index]
		var c: Vector2 = _contour_vertices[c_index]
		draw_colored_polygon(PackedVector2Array([a, b, c]), CONTOUR_FILL_COLOR)
		draw_line(a, b, CONTOUR_LINE_COLOR, CONTOUR_LINE_WIDTH)
		draw_line(b, c, CONTOUR_LINE_COLOR, CONTOUR_LINE_WIDTH)
		draw_line(c, a, CONTOUR_LINE_COLOR, CONTOUR_LINE_WIDTH)
	if _contour_vertices.size() <= 1024:
		for vertex: Vector2 in _contour_vertices:
			draw_circle(vertex, VERTEX_RADIUS, CONTOUR_VERTEX_COLOR)

func _count_solid_tiles() -> int:
	var count: int = 0
	for value: int in _solid_mask:
		if value != 0:
			count += 1
	return count

func _is_vertex_index_valid(index: int) -> bool:
	return index >= 0 and index < _contour_vertices.size()
