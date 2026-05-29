class_name MountainPlateau2DLayer
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const TOP_TEXTURE_PATH: String = "res://assets/textures/terrain/mountain_plateau_top.png"
const FACE_TEXTURE_PATH: String = "res://assets/textures/terrain/mountain_plateau_face.png"

const TILE_SIZE_PX: float = 64.0
const DIR_N: int = 0
const DIR_E: int = 1
const DIR_S: int = 2
const DIR_W: int = 3

# Scaled from tools/rimworld-autotile-lab desktop_app mountain defaults:
# tile_size=128, south_height=64, rim_width=16, outline_width=6, roughness=10.
const FACADE_HEIGHT_PX: float = 32.0
const RIM_WIDTH_PX: float = 8.0
const OUTLINE_WIDTH_PX: float = 3.0
const ROUGHNESS_PX: float = 5.0
const CORNER_ROUND_PX: float = 16.0
const CROWN_BEVEL_PX: float = 5.0
const EDGE_DEBRIS_STRENGTH: float = 0.8
const CONTOUR_SMOOTH_ITERATIONS: int = 3
const CONTOUR_CHAIKIN_CUT: float = 0.30
const CONTOUR_MIN_POINT_DISTANCE_PX: float = 4.0

const TOP_COLOR: Color = Color(0.82, 0.36, 0.12, 0.92)
const TOP_TEXTURE_MODULATE: Color = Color(1.0, 0.82, 0.68, 0.36)
const TOP_LIGHT_DETAIL_COLOR: Color = Color(1.0, 0.62, 0.25, 0.16)
const TOP_DARK_DETAIL_COLOR: Color = Color(0.31, 0.12, 0.045, 0.18)
const FACE_TOP_COLOR: Color = Color(0.55, 0.23, 0.085, 0.98)
const FACE_MID_COLOR: Color = Color(0.39, 0.15, 0.055, 0.99)
const FACE_BOTTOM_COLOR: Color = Color(0.19, 0.07, 0.03, 1.0)
const FACE_TEXTURE_MODULATE: Color = Color(1.0, 0.76, 0.55, 0.46)
const RIM_COLOR: Color = Color(0.28, 0.10, 0.035, 0.95)
const EDGE_COLOR: Color = Color(0.40, 0.16, 0.055, 0.74)
const OUTLINE_COLOR: Color = Color(0.025, 0.018, 0.012, 0.72)
const DEBUG_EDGE_COLOR: Color = Color(0.62, 0.88, 1.0, 0.72)
const GROUND_COLOR: Color = Color(0.20, 0.34, 0.18, 1.0)
const GROUND_DETAIL_COLOR: Color = Color(0.30, 0.45, 0.25, 0.15)
const GROUND_BACKDROP_PADDING_TILES: int = 18

const TOP_TEXTURE_SOURCE_SCALE: float = 1.0
const FACE_TEXTURE_SOURCE_SCALE: float = 0.65

@export var draw_debug_edges: bool = false

var _mountain_tiles: Dictionary = {}
var _edge_tiles: Dictionary = {}
var _right_connectors: Array[Vector2i] = []
var _down_connectors: Array[Vector2i] = []
var _exposed_edges: Array[Vector3i] = []
var _south_facade_edges: Array[Vector2i] = []
var _top_contours: Array[PackedVector2Array] = []
var _top_fill_contours: Array[PackedVector2Array] = []
var _bounds: Rect2i = Rect2i()
var _top_texture: Texture2D = null
var _face_texture: Texture2D = null
var _debug_snapshot: Dictionary = {
	"ready": false,
}

func rebuild_from_packets(packets: Array[Dictionary], target_chunk: Vector2i) -> void:
	_ensure_textures_loaded()
	_mountain_tiles.clear()
	_edge_tiles.clear()
	_right_connectors.clear()
	_down_connectors.clear()
	_exposed_edges.clear()
	_south_facade_edges.clear()
	_top_contours.clear()
	_top_fill_contours.clear()
	position = -WorldRuntimeConstants.chunk_origin_px(target_chunk)
	for packet: Dictionary in packets:
		_collect_mountain_tiles(packet)
	_build_draw_cache()
	_build_debug_snapshot(packets.size())
	queue_redraw()

func clear_plateau() -> void:
	_mountain_tiles.clear()
	_edge_tiles.clear()
	_right_connectors.clear()
	_down_connectors.clear()
	_exposed_edges.clear()
	_south_facade_edges.clear()
	_top_contours.clear()
	_top_fill_contours.clear()
	_bounds = Rect2i()
	_debug_snapshot = {
		"ready": false,
	}
	queue_redraw()

func get_debug_snapshot() -> Dictionary:
	return _debug_snapshot.duplicate(true)

func _draw() -> void:
	if _mountain_tiles.is_empty():
		return
	_draw_ground_backdrop()
	_draw_contour_facade()
	_draw_contour_rim()
	_draw_top_mass()
	_draw_top_texture_details()
	if draw_debug_edges:
		_draw_debug_edges()

func _ensure_textures_loaded() -> void:
	if _top_texture == null:
		_top_texture = _load_external_texture(TOP_TEXTURE_PATH, "mountain top")
	if _face_texture == null:
		_face_texture = _load_external_texture(FACE_TEXTURE_PATH, "mountain face")

func _load_external_texture(path: String, label: String) -> Texture2D:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		push_error("MountainPlateau2DLayer cannot load %s texture: %s" % [label, path])
	return texture

func _collect_mountain_tiles(packet: Dictionary) -> void:
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if not _is_mountain_terrain(terrain_id):
			continue
		if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
			continue
		if terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
				and index < mountain_flags.size():
			var flags: int = int(mountain_flags[index])
			if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
				continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord
		_mountain_tiles[world_tile] = true

func _build_draw_cache() -> void:
	if _mountain_tiles.is_empty():
		_bounds = Rect2i()
		return
	var min_tile := Vector2i(2147483647, 2147483647)
	var max_tile := Vector2i(-2147483648, -2147483648)
	for tile_variant: Variant in _mountain_tiles.keys():
		var tile: Vector2i = tile_variant as Vector2i
		min_tile.x = mini(min_tile.x, tile.x)
		min_tile.y = mini(min_tile.y, tile.y)
		max_tile.x = maxi(max_tile.x, tile.x)
		max_tile.y = maxi(max_tile.y, tile.y)
		if _mountain_tiles.has(tile + Vector2i(1, 0)):
			_right_connectors.append(tile)
		if _mountain_tiles.has(tile + Vector2i(0, 1)):
			_down_connectors.append(tile)
		_collect_exposed_edge(tile, DIR_N)
		_collect_exposed_edge(tile, DIR_E)
		_collect_exposed_edge(tile, DIR_S)
		_collect_exposed_edge(tile, DIR_W)
	_bounds = Rect2i(min_tile, max_tile - min_tile + Vector2i.ONE)
	_build_top_contours()

func _collect_exposed_edge(tile: Vector2i, direction: int) -> void:
	if _mountain_tiles.has(tile + _direction_offset(direction)):
		return
	_edge_tiles[tile] = true
	_exposed_edges.append(Vector3i(tile.x, tile.y, direction))
	if direction == DIR_S:
		_south_facade_edges.append(tile)

func _build_top_contours() -> void:
	_top_contours.clear()
	_top_fill_contours.clear()
	var next_vertices: Dictionary = {}
	for edge: Vector3i in _exposed_edges:
		var segment: Array[Vector2i] = _edge_vertices(edge)
		var start: Vector2i = segment[0]
		var ends: Array = next_vertices.get(start, []) as Array
		ends.append(segment[1])
		next_vertices[start] = ends

	while not next_vertices.is_empty():
		var start: Vector2i = next_vertices.keys()[0] as Vector2i
		var current: Vector2i = start
		var raw_loop: Array[Vector2i] = []
		var guard: int = 0
		while guard < _exposed_edges.size() + 8:
			guard += 1
			raw_loop.append(current)
			var ends: Array = next_vertices.get(current, []) as Array
			if ends.is_empty():
				break
			var next: Vector2i = ends.pop_back() as Vector2i
			if ends.is_empty():
				next_vertices.erase(current)
			else:
				next_vertices[current] = ends
			current = next
			if current == start:
				break
		if current != start or raw_loop.size() < 3:
			continue
		var contour: PackedVector2Array = _smooth_grid_loop(raw_loop)
		if contour.size() < 3:
			continue
		_top_contours.append(contour)
		if _signed_area(contour) > 0.0:
			_top_fill_contours.append(contour)

func _draw_ground_backdrop() -> void:
	var padding_px: float = float(GROUND_BACKDROP_PADDING_TILES) * TILE_SIZE_PX
	var origin: Vector2 = _grid_vertex_to_world(_bounds.position) - Vector2(padding_px, padding_px)
	var size: Vector2 = Vector2(_bounds.size) * TILE_SIZE_PX + Vector2(padding_px * 2.0, padding_px * 2.0)
	var rect := Rect2(origin, size)
	draw_rect(rect, GROUND_COLOR, true)
	var min_x: int = _bounds.position.x - GROUND_BACKDROP_PADDING_TILES
	var max_x: int = _bounds.position.x + _bounds.size.x + GROUND_BACKDROP_PADDING_TILES
	var min_y: int = _bounds.position.y - GROUND_BACKDROP_PADDING_TILES
	var max_y: int = _bounds.position.y + _bounds.size.y + GROUND_BACKDROP_PADDING_TILES
	for y: int in range(min_y, max_y, 2):
		for x: int in range(min_x, max_x, 2):
			var tile := Vector2i(x, y)
			if _tile_noise(tile) < 0.78:
				continue
			var dot_origin: Vector2 = _grid_vertex_to_world(tile) + Vector2(
				_tile_noise(tile + Vector2i(17, 3)) * TILE_SIZE_PX,
				_tile_noise(tile + Vector2i(5, 23)) * TILE_SIZE_PX
			)
			draw_rect(
				Rect2(dot_origin, Vector2(5.0, 4.0)),
				GROUND_DETAIL_COLOR,
				true
			)

func _draw_contour_facade() -> void:
	for contour: PackedVector2Array in _top_contours:
		_draw_projected_facade(contour)

func _draw_top_mass() -> void:
	for contour: PackedVector2Array in _top_fill_contours:
		_draw_filled_contour(contour, TOP_COLOR)
		_draw_textured_contour(contour, _top_texture, TOP_TEXTURE_SOURCE_SCALE, TOP_TEXTURE_MODULATE)

func _draw_contour_rim() -> void:
	for contour: PackedVector2Array in _top_contours:
		_draw_closed_polyline(contour, RIM_COLOR, RIM_WIDTH_PX)
		_draw_closed_polyline(_offset_contour_outward(contour, CROWN_BEVEL_PX), EDGE_COLOR, RIM_WIDTH_PX * 0.55)
		_draw_closed_polyline(_translated_contour(contour, Vector2(0.0, FACADE_HEIGHT_PX)), OUTLINE_COLOR, OUTLINE_WIDTH_PX)

func _draw_edge_debris() -> void:
	for tile: Vector2i in _south_facade_edges:
		var origin: Vector2 = _tile_origin(tile)
		var base_y: float = origin.y + TILE_SIZE_PX + FACADE_HEIGHT_PX - 2.0
		for index: int in range(3):
			if _tile_noise(tile + Vector2i(index * 17, 31)) < 1.0 - EDGE_DEBRIS_STRENGTH:
				continue
			var x: float = origin.x + 8.0 + float(index) * 19.0 + (_tile_noise(tile + Vector2i(index, 7)) - 0.5) * 8.0
			var height: float = 8.0 + _tile_noise(tile + Vector2i(index * 5, 13)) * 11.0
			var width: float = 8.0 + _tile_noise(tile + Vector2i(index * 9, 19)) * 8.0
			draw_rect(
				Rect2(Vector2(x, base_y - height), Vector2(width, height)),
				EDGE_COLOR,
				true
			)
			draw_line(
				Vector2(x, base_y - height),
				Vector2(x + width, base_y),
				FACE_BOTTOM_COLOR,
				2.0
			)

func _draw_top_texture_details() -> void:
	for tile_variant: Variant in _mountain_tiles.keys():
		var tile: Vector2i = tile_variant as Vector2i
		var noise: float = _tile_noise(tile)
		var origin: Vector2 = _tile_origin(tile)
		if noise > 0.72:
			var dot_pos := origin + Vector2(
				10.0 + _tile_noise(tile + Vector2i(11, 3)) * 42.0,
				10.0 + _tile_noise(tile + Vector2i(5, 17)) * 42.0
			)
			var dot_size: float = 3.0 + _tile_noise(tile + Vector2i(9, 1)) * 5.0
			draw_rect(Rect2(dot_pos, Vector2(dot_size, dot_size * 0.72)), TOP_LIGHT_DETAIL_COLOR, true)
		elif noise < 0.10:
			var start := origin + Vector2(
				12.0 + _tile_noise(tile + Vector2i(2, 23)) * 36.0,
				12.0 + _tile_noise(tile + Vector2i(29, 5)) * 36.0
			)
			draw_line(start, start + Vector2(12.0, 4.0), TOP_DARK_DETAIL_COLOR, 2.0)

func _draw_face_strata(face_rect: Rect2, tile: Vector2i) -> void:
	for index: int in range(3):
		var y: float = face_rect.position.y + 9.0 + float(index) * 7.0 \
			+ (_tile_noise(tile + Vector2i(index * 13, 5)) - 0.5) * 2.0
		draw_line(
			Vector2(face_rect.position.x + 4.0, y),
			Vector2(face_rect.position.x + face_rect.size.x - 5.0, y + _tile_noise(tile + Vector2i(index, 41)) * 2.0),
			Color(0.12, 0.045, 0.018, 0.30),
			2.0
		)
	if _tile_noise(tile + Vector2i(23, 71)) > 0.42:
		var x: float = face_rect.position.x + 12.0 + _tile_noise(tile + Vector2i(17, 3)) * 40.0
		draw_line(
			Vector2(x, face_rect.position.y + 4.0),
			Vector2(x + (_tile_noise(tile + Vector2i(7, 29)) - 0.5) * 8.0, face_rect.position.y + 27.0),
			Color(0.10, 0.035, 0.014, 0.36),
			2.0
		)

func _draw_texture_region(texture: Texture2D, rect: Rect2, source_scale: float, modulate: Color) -> void:
	if texture == null:
		return
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 1.0 or texture_size.y <= 1.0:
		return
	var region_size: Vector2 = Vector2(
		clampf(rect.size.x * source_scale, 1.0, texture_size.x),
		clampf(rect.size.y * source_scale, 1.0, texture_size.y)
	)
	var max_origin := Vector2(
		maxf(texture_size.x - region_size.x, 1.0),
		maxf(texture_size.y - region_size.y, 1.0)
	)
	var region_position := Vector2(
		fmod(absf(rect.position.x * source_scale), max_origin.x),
		fmod(absf(rect.position.y * source_scale), max_origin.y)
	)
	draw_texture_rect_region(texture, rect, Rect2(region_position, region_size), modulate)

func _draw_filled_contour(contour: PackedVector2Array, color: Color) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(contour)
	for index: int in range(0, indices.size(), 3):
		var triangle := PackedVector2Array([
			contour[int(indices[index])],
			contour[int(indices[index + 1])],
			contour[int(indices[index + 2])],
		])
		if _triangle_area_abs(triangle) < 0.5:
			continue
		draw_primitive(
			triangle,
			PackedColorArray([color, color, color]),
			PackedVector2Array()
		)

func _draw_textured_contour(
	contour: PackedVector2Array,
	texture: Texture2D,
	source_scale: float,
	modulate: Color
) -> void:
	if texture == null:
		return
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 1.0 or texture_size.y <= 1.0:
		return
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(contour)
	for index: int in range(0, indices.size(), 3):
		var part := PackedVector2Array([
			contour[int(indices[index])],
			contour[int(indices[index + 1])],
			contour[int(indices[index + 2])],
		])
		if _triangle_area_abs(part) < 0.5:
			continue
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		for point: Vector2 in part:
			colors.append(modulate)
			uvs.append(Vector2(
				fmod(absf(point.x * source_scale), texture_size.x),
				fmod(absf(point.y * source_scale), texture_size.y)
			))
		draw_primitive(part, colors, uvs, texture)

func _draw_projected_facade(contour: PackedVector2Array) -> void:
	# Mirrors the lab's front-only SDF path: face pixels come from a vertical
	# projection of top coverage, not from per-edge outward expansion.
	_draw_translated_filled_contour(contour, Vector2(0.0, FACADE_HEIGHT_PX), FACE_BOTTOM_COLOR)
	_draw_translated_textured_contour(
		contour,
		Vector2(0.0, FACADE_HEIGHT_PX),
		_face_texture,
		FACE_TEXTURE_SOURCE_SCALE,
		FACE_TEXTURE_MODULATE
	)
	_draw_translated_filled_contour(contour, Vector2(0.0, FACADE_HEIGHT_PX * 0.58), FACE_MID_COLOR)
	_draw_translated_filled_contour(contour, Vector2(0.0, FACADE_HEIGHT_PX * 0.26), FACE_TOP_COLOR)

func _draw_textured_triangle(
	triangle: PackedVector2Array,
	texture: Texture2D,
	texture_size: Vector2,
	source_scale: float,
	modulate: Color
) -> void:
	if _triangle_area_abs(triangle) < 0.5:
		return
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for point: Vector2 in triangle:
		colors.append(modulate)
		uvs.append(Vector2(
			fmod(absf(point.x * source_scale), texture_size.x),
			fmod(absf(point.y * source_scale), texture_size.y)
		))
	draw_primitive(triangle, colors, uvs, texture)

func _draw_translated_filled_contour(
	contour: PackedVector2Array,
	offset: Vector2,
	color: Color
) -> void:
	_draw_filled_contour(_translated_contour(contour, offset), color)

func _draw_translated_textured_contour(
	contour: PackedVector2Array,
	offset: Vector2,
	texture: Texture2D,
	source_scale: float,
	modulate: Color
) -> void:
	_draw_textured_contour(_translated_contour(contour, offset), texture, source_scale, modulate)

func _triangle_area_abs(triangle: PackedVector2Array) -> float:
	if triangle.size() != 3:
		return 0.0
	return absf(
		(triangle[1].x - triangle[0].x) * (triangle[2].y - triangle[0].y)
		- (triangle[1].y - triangle[0].y) * (triangle[2].x - triangle[0].x)
	) * 0.5

func _draw_closed_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func _offset_contour_outward(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.size() < 3:
		return result
	var orientation_sign: float = 1.0 if _signed_area(points) >= 0.0 else -1.0
	for index: int in range(points.size()):
		var current: Vector2 = points[index]
		var normal: Vector2 = _contour_vertex_outward_normal(points, index, orientation_sign)
		if normal == Vector2.ZERO:
			result.append(current)
			continue
		result.append(current + normal.normalized() * distance)
	return result

func _translated_contour(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(point + offset)
	return result

func _contour_vertex_outward_normal(
	points: PackedVector2Array,
	index: int,
	orientation_sign: float
) -> Vector2:
	var previous: Vector2 = points[(index - 1 + points.size()) % points.size()]
	var current: Vector2 = points[index]
	var next: Vector2 = points[(index + 1) % points.size()]
	var previous_normal: Vector2 = _edge_outward_normal(previous, current, orientation_sign)
	var next_normal: Vector2 = _edge_outward_normal(current, next, orientation_sign)
	var normal: Vector2 = previous_normal + next_normal
	if normal.length_squared() <= 0.0001:
		normal = next_normal if next_normal.length_squared() > 0.0001 else previous_normal
	if normal.length_squared() <= 0.0001:
		return Vector2.ZERO
	return normal

func _edge_outward_normal(from: Vector2, to: Vector2, orientation_sign: float) -> Vector2:
	var tangent: Vector2 = to - from
	if tangent.length_squared() <= 0.0001:
		return Vector2.ZERO
	tangent = tangent.normalized()
	return Vector2(tangent.y, -tangent.x) * orientation_sign

func _draw_debug_edges() -> void:
	for contour: PackedVector2Array in _top_contours:
		_draw_closed_polyline(contour, DEBUG_EDGE_COLOR, 2.0)

func _edge_vertices(edge: Vector3i) -> Array[Vector2i]:
	var x: int = edge.x
	var y: int = edge.y
	match edge.z:
		DIR_N:
			return [Vector2i(x, y), Vector2i(x + 1, y)]
		DIR_E:
			return [Vector2i(x + 1, y), Vector2i(x + 1, y + 1)]
		DIR_S:
			return [Vector2i(x + 1, y + 1), Vector2i(x, y + 1)]
		DIR_W:
			return [Vector2i(x, y + 1), Vector2i(x, y)]
	return [Vector2i(x, y), Vector2i(x, y)]

func _smooth_grid_loop(raw_loop: Array[Vector2i]) -> PackedVector2Array:
	var points: PackedVector2Array = _grid_loop_without_collinear_vertices(raw_loop)
	for _iteration: int in range(CONTOUR_SMOOTH_ITERATIONS):
		points = _chaikin_smooth_closed(points)
	return _remove_close_contour_points(points, CONTOUR_MIN_POINT_DISTANCE_PX)

func _grid_loop_without_collinear_vertices(raw_loop: Array[Vector2i]) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count: int = raw_loop.size()
	for index: int in range(count):
		var previous_grid: Vector2i = raw_loop[(index - 1 + count) % count]
		var current_grid: Vector2i = raw_loop[index]
		var next_grid: Vector2i = raw_loop[(index + 1) % count]
		var incoming := Vector2i(current_grid.x - previous_grid.x, current_grid.y - previous_grid.y)
		var outgoing := Vector2i(next_grid.x - current_grid.x, next_grid.y - current_grid.y)
		if incoming == outgoing:
			continue
		result.append(_grid_vertex_to_world(current_grid))
	return result

func _chaikin_smooth_closed(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var result := PackedVector2Array()
	for index: int in range(points.size()):
		var current: Vector2 = points[index]
		var next: Vector2 = points[(index + 1) % points.size()]
		result.append(current.lerp(next, CONTOUR_CHAIKIN_CUT))
		result.append(current.lerp(next, 1.0 - CONTOUR_CHAIKIN_CUT))
	return result

func _remove_close_contour_points(points: PackedVector2Array, min_distance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var result := PackedVector2Array()
	var min_distance_squared: float = min_distance * min_distance
	for point: Vector2 in points:
		if result.is_empty() or result[result.size() - 1].distance_squared_to(point) >= min_distance_squared:
			result.append(point)
	if result.size() > 2 and result[0].distance_squared_to(result[result.size() - 1]) < min_distance_squared:
		result.remove_at(result.size() - 1)
	return result

func _rounded_grid_loop(raw_loop: Array[Vector2i]) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count: int = raw_loop.size()
	for index: int in range(count):
		var previous: Vector2 = _grid_vertex_to_world(raw_loop[(index - 1 + count) % count])
		var current: Vector2 = _grid_vertex_to_world(raw_loop[index])
		var next: Vector2 = _grid_vertex_to_world(raw_loop[(index + 1) % count])
		var from_previous: Vector2 = previous - current
		var to_next: Vector2 = next - current
		if from_previous.length_squared() <= 0.01 or to_next.length_squared() <= 0.01:
			continue
		if absf(from_previous.normalized().dot(to_next.normalized())) > 0.999:
			result.append(current)
			continue
		var previous_radius: float = minf(CORNER_ROUND_PX, from_previous.length() * 0.48)
		var next_radius: float = minf(CORNER_ROUND_PX, to_next.length() * 0.48)
		var start: Vector2 = current + from_previous.normalized() * previous_radius
		var end: Vector2 = current + to_next.normalized() * next_radius
		for step: int in range(5):
			var t: float = float(step) / 4.0
			var inv_t: float = 1.0 - t
			result.append(start * inv_t * inv_t + current * 2.0 * inv_t * t + end * t * t)
	return result

func _grid_vertex_to_world(vertex: Vector2i) -> Vector2:
	return WorldRuntimeConstants.tile_to_world_center(vertex) - Vector2(TILE_SIZE_PX * 0.5, TILE_SIZE_PX * 0.5)

func _signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for index: int in range(points.size()):
		var current: Vector2 = points[index]
		var next: Vector2 = points[(index + 1) % points.size()]
		area += current.x * next.y - current.y * next.x
	return area * 0.5

func _build_debug_snapshot(packet_count: int) -> void:
	_debug_snapshot = {
		"ready": not _mountain_tiles.is_empty(),
		"packet_count": packet_count,
		"mountain_tile_count": _mountain_tiles.size(),
		"edge_tile_count": _edge_tiles.size(),
		"right_connector_count": _right_connectors.size(),
		"down_connector_count": _down_connectors.size(),
		"exposed_edge_count": _exposed_edges.size(),
		"facade_edge_count": _south_facade_edges.size(),
		"rim_edge_count": _exposed_edges.size(),
		"contour_count": _top_contours.size(),
		"fill_contour_count": _top_fill_contours.size(),
		"facade_height_px": FACADE_HEIGHT_PX,
		"rim_width_px": RIM_WIDTH_PX,
		"corner_round_px": CORNER_ROUND_PX,
		"top_texture_loaded": _top_texture != null,
		"face_texture_loaded": _face_texture != null,
		"bounds_position": _bounds.position,
		"bounds_size": _bounds.size,
	}

func _edge_segment(edge: Vector3i) -> PackedVector2Array:
	var tile := Vector2i(edge.x, edge.y)
	var origin: Vector2 = _tile_origin(tile)
	match edge.z:
		DIR_N:
			return PackedVector2Array([origin, origin + Vector2(TILE_SIZE_PX, 0.0)])
		DIR_E:
			return PackedVector2Array([
				origin + Vector2(TILE_SIZE_PX, 0.0),
				origin + Vector2(TILE_SIZE_PX, TILE_SIZE_PX),
			])
		DIR_S:
			return PackedVector2Array([
				origin + Vector2(0.0, TILE_SIZE_PX),
				origin + Vector2(TILE_SIZE_PX, TILE_SIZE_PX),
			])
		DIR_W:
			return PackedVector2Array([origin, origin + Vector2(0.0, TILE_SIZE_PX)])
	return PackedVector2Array([origin, origin])

func _direction_offset(direction: int) -> Vector2i:
	match direction:
		DIR_N:
			return Vector2i(0, -1)
		DIR_E:
			return Vector2i(1, 0)
		DIR_S:
			return Vector2i(0, 1)
		DIR_W:
			return Vector2i(-1, 0)
	return Vector2i.ZERO

func _tile_noise(tile: Vector2i) -> float:
	var value: int = tile.x * 92837111 + tile.y * 689287499 + 283923481
	value = posmod(value * 1103515245 + 12345, 100000)
	return float(value) / 99999.0

func _tile_origin(tile: Vector2i) -> Vector2:
	return WorldRuntimeConstants.tile_to_world_center(tile) - Vector2(TILE_SIZE_PX * 0.5, TILE_SIZE_PX * 0.5)

func _tile_rect(tile: Vector2i) -> Rect2:
	return Rect2(_tile_origin(tile), Vector2(TILE_SIZE_PX, TILE_SIZE_PX))

func _is_mountain_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED
