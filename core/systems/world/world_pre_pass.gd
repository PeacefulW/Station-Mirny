class_name WorldPrePass
extends RefCounted

class LakeRecord extends RefCounted:
	var id: int = 0
	var grid_cells: PackedInt32Array = PackedInt32Array()
	var spill_point: Vector2i = Vector2i.ZERO
	var surface_height: float = 0.0
	var max_depth: float = 0.0
	var area_grid_cells: int = 0
	var lake_type: StringName = &"tectonic"
	var inflow_accumulation: float = 0.0

const HEIGHT_CHANNEL: StringName = &"height"
const WorldNoiseUtilsScript = preload("res://core/systems/world/world_noise_utils.gd")
const FLOAT_EPSILON: float = 0.00001
const MAX_LAKE_MASK_ID: int = 255
const LAKE_TYPE_MOUNTAIN: StringName = &"mountain"
const LAKE_TYPE_GLACIAL: StringName = &"glacial"
const LAKE_TYPE_FLOODPLAIN: StringName = &"floodplain"
const LAKE_TYPE_TECTONIC: StringName = &"tectonic"
const GRID_NEIGHBOR_OFFSETS_8: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

var _balance: WorldGenBalance = null
var _planet_sampler: PlanetSampler = null
var _grid_step: int = 32
var _wrap_width_tiles: int = WorldNoiseUtilsScript.DEFAULT_WRAP_WIDTH_TILES
var _prepass_min_y: int = 0
var _prepass_max_y: int = 0
var _grid_width: int = 1
var _grid_height: int = 1
var _grid_span_x: float = 1.0
var _grid_span_y: float = 1.0
var _height_grid: PackedFloat32Array = PackedFloat32Array()
var _filled_height_grid: PackedFloat32Array = PackedFloat32Array()
var _lake_mask: PackedByteArray = PackedByteArray()
var _lake_records: Array[LakeRecord] = []

func configure(balance_resource: WorldGenBalance, planet_sampler: PlanetSampler) -> WorldPrePass:
	_balance = balance_resource
	_planet_sampler = planet_sampler
	_grid_step = _resolve_grid_step()
	_wrap_width_tiles = _resolve_wrap_width_tiles()
	_prepass_min_y = _resolve_prepass_min_y()
	_prepass_max_y = _resolve_prepass_max_y()
	var y_span_tiles: int = _resolve_y_span_tiles()
	_grid_width = maxi(1, int(ceili(float(_wrap_width_tiles) / float(_grid_step))))
	_grid_height = maxi(1, int(ceili(float(y_span_tiles) / float(_grid_step))))
	_grid_span_x = float(_wrap_width_tiles) / float(_grid_width)
	_grid_span_y = float(y_span_tiles) / float(_grid_height)
	_height_grid = PackedFloat32Array()
	_filled_height_grid = PackedFloat32Array()
	_lake_mask = PackedByteArray()
	_lake_records.clear()
	return self

func compute() -> WorldPrePass:
	_height_grid.resize(_grid_width * _grid_height)
	_filled_height_grid.resize(_grid_width * _grid_height)
	_lake_mask.resize(_grid_width * _grid_height)
	_lake_mask.fill(0)
	_lake_records.clear()
	if _planet_sampler == null:
		_height_grid.fill(0.0)
		_filled_height_grid.fill(0.0)
		return self
	for grid_y: int in range(_grid_height):
		var world_y: int = _grid_to_world_y(grid_y)
		for grid_x: int in range(_grid_width):
			var world_pos := Vector2i(_grid_to_world_x(grid_x), world_y)
			_height_grid[_flatten_index(grid_x, grid_y)] = _planet_sampler.sample_height(world_pos)
	_compute_lake_aware_fill()
	return self

func sample(channel: StringName, world_pos: Vector2i) -> float:
	if channel != HEIGHT_CHANNEL or _height_grid.is_empty():
		return 0.0
	return _sample_grid(_height_grid, world_pos)

func sample_all(world_pos: Vector2i) -> Dictionary:
	return {
		HEIGHT_CHANNEL: sample(HEIGHT_CHANNEL, world_pos),
	}

func get_grid_value(channel: StringName, grid_x: int, grid_y: int) -> float:
	if channel != HEIGHT_CHANNEL or _height_grid.is_empty():
		return 0.0
	if grid_x < 0 or grid_x >= _grid_width or grid_y < 0 or grid_y >= _grid_height:
		return 0.0
	return _height_grid[_flatten_index(grid_x, grid_y)]

func _sample_grid(grid: PackedFloat32Array, world_pos: Vector2i) -> float:
	var wrapped_x: int = _wrap_x(world_pos.x)
	var x0: int = 0
	var x1: int = 0
	var tx: float = 0.0
	if _grid_width > 1:
		var x_coord: float = float(wrapped_x) / _grid_span_x
		var x_floor: int = floori(x_coord)
		x0 = int(posmod(x_floor, _grid_width))
		x1 = int(posmod(x0 + 1, _grid_width))
		tx = x_coord - float(x_floor)

	var y0: int = 0
	var y1: int = 0
	var ty: float = 0.0
	if _grid_height > 1:
		if world_pos.y <= _prepass_min_y:
			y0 = 0
			y1 = 0
		elif world_pos.y >= _prepass_max_y:
			y0 = _grid_height - 1
			y1 = y0
		else:
			var y_coord: float = float(world_pos.y - _prepass_min_y) / _grid_span_y
			var y_floor: int = floori(y_coord)
			y0 = clampi(y_floor, 0, _grid_height - 1)
			if y0 >= _grid_height - 1:
				y1 = y0
			else:
				y1 = y0 + 1
				ty = y_coord - float(y_floor)

	var v00: float = grid[_flatten_index(x0, y0)]
	if x0 == x1 and y0 == y1:
		return v00
	var v10: float = grid[_flatten_index(x1, y0)]
	var v01: float = grid[_flatten_index(x0, y1)]
	var v11: float = grid[_flatten_index(x1, y1)]
	var top: float = lerpf(v00, v10, tx)
	var bottom: float = lerpf(v01, v11, tx)
	return lerpf(top, bottom, ty)

func _flatten_index(grid_x: int, grid_y: int) -> int:
	return grid_y * _grid_width + grid_x

func _index_to_grid(index: int) -> Vector2i:
	if _grid_width <= 0:
		return Vector2i.ZERO
	return Vector2i(int(posmod(index, _grid_width)), int(index / _grid_width))

func _grid_to_world_x(grid_x: int) -> int:
	if _grid_width <= 0:
		return 0
	return _wrap_x(int(floor(float(grid_x) * float(_wrap_width_tiles) / float(_grid_width))))

func _grid_to_world_y(grid_y: int) -> int:
	if _grid_height <= 0:
		return _prepass_min_y
	var y_span_tiles: int = _resolve_y_span_tiles()
	return _prepass_min_y + int(floor(float(grid_y) * float(y_span_tiles) / float(_grid_height)))

func _resolve_grid_step() -> int:
	if _balance == null:
		return 32
	return maxi(1, _balance.prepass_grid_step)

func _resolve_wrap_width_tiles() -> int:
	if _planet_sampler:
		return maxi(1, _planet_sampler.get_wrap_width_tiles())
	return WorldNoiseUtilsScript.resolve_wrap_width_tiles(_balance)

func _resolve_prepass_min_y() -> int:
	var equator_y: int = 0
	if _balance:
		equator_y = _balance.equator_tile_y
	return equator_y - _resolve_latitude_half_span_tiles()

func _resolve_prepass_max_y() -> int:
	var equator_y: int = 0
	if _balance:
		equator_y = _balance.equator_tile_y
	return equator_y + _resolve_latitude_half_span_tiles()

func _resolve_latitude_half_span_tiles() -> int:
	if _balance == null:
		return 4096
	return maxi(256, _balance.latitude_half_span_tiles)

func _resolve_y_span_tiles() -> int:
	return maxi(1, _prepass_max_y - _prepass_min_y)

func _wrap_x(world_x: int) -> int:
	return WorldNoiseUtilsScript.wrap_x(world_x, _wrap_width_tiles)

func _compute_lake_aware_fill() -> void:
	if _height_grid.is_empty():
		return
	_filled_height_grid = _height_grid.duplicate()
	var visited := PackedByteArray()
	visited.resize(_height_grid.size())
	visited.fill(0)
	var heap: Array[Dictionary] = []
	_seed_priority_flood_boundaries(visited, heap)
	while not heap.is_empty():
		var current: Dictionary = _heap_pop(heap)
		var current_index: int = int(current.get("index", -1))
		var current_level: float = float(current.get("priority", 0.0))
		if current_index < 0:
			continue
		var current_grid: Vector2i = _index_to_grid(current_index)
		for offset: Vector2i in GRID_NEIGHBOR_OFFSETS_8:
			var neighbor_y: int = current_grid.y + offset.y
			if neighbor_y < 0 or neighbor_y >= _grid_height:
				continue
			var neighbor_x: int = int(posmod(current_grid.x + offset.x, _grid_width))
			var neighbor_index: int = _flatten_index(neighbor_x, neighbor_y)
			if visited[neighbor_index] != 0:
				continue
			visited[neighbor_index] = 1
			var raw_height: float = _height_grid[neighbor_index]
			var filled_height: float = maxf(raw_height, current_level)
			_filled_height_grid[neighbor_index] = filled_height
			_heap_push(heap, neighbor_index, filled_height)
	_extract_lake_records()

func _seed_priority_flood_boundaries(visited: PackedByteArray, heap: Array[Dictionary]) -> void:
	for grid_x: int in range(_grid_width):
		_seed_priority_flood_boundary_cell(grid_x, 0, visited, heap)
		if _grid_height > 1:
			_seed_priority_flood_boundary_cell(grid_x, _grid_height - 1, visited, heap)

func _seed_priority_flood_boundary_cell(
	grid_x: int,
	grid_y: int,
	visited: PackedByteArray,
	heap: Array[Dictionary]
) -> void:
	var cell_index: int = _flatten_index(grid_x, grid_y)
	if visited[cell_index] != 0:
		return
	visited[cell_index] = 1
	_heap_push(heap, cell_index, _height_grid[cell_index])

func _extract_lake_records() -> void:
	_lake_mask.fill(0)
	_lake_records.clear()
	if _height_grid.is_empty():
		return
	var component_id_by_cell: Array[int] = []
	component_id_by_cell.resize(_height_grid.size())
	component_id_by_cell.fill(-1)
	var next_component_id: int = 0
	for cell_index: int in range(_height_grid.size()):
		if component_id_by_cell[cell_index] != -1:
			continue
		if _filled_height_grid[cell_index] <= _height_grid[cell_index] + FLOAT_EPSILON:
			continue
		var component_cells: Array[int] = _collect_basin_component(cell_index, next_component_id, component_id_by_cell)
		if component_cells.is_empty():
			continue
		component_cells.sort()
		var lake_record: LakeRecord = _build_lake_record(component_cells, next_component_id, component_id_by_cell)
		next_component_id += 1
		if lake_record == null:
			continue
		if lake_record.area_grid_cells < _resolve_lake_min_area():
			continue
		if lake_record.max_depth < _resolve_lake_min_depth():
			continue
		if _lake_records.size() >= MAX_LAKE_MASK_ID:
			push_error("WorldPrePass lake mask overflow: more than %d lakes detected" % MAX_LAKE_MASK_ID)
			break
		lake_record.id = _lake_records.size() + 1
		_lake_records.append(lake_record)
		for basin_index: int in component_cells:
			_lake_mask[basin_index] = lake_record.id

func _collect_basin_component(
	start_index: int,
	component_id: int,
	component_id_by_cell: Array[int]
) -> Array[int]:
	var surface_height: float = _filled_height_grid[start_index]
	var queue: Array[int] = [start_index]
	var queue_index: int = 0
	var component_cells: Array[int] = []
	component_id_by_cell[start_index] = component_id
	while queue_index < queue.size():
		var current_index: int = queue[queue_index]
		queue_index += 1
		component_cells.append(current_index)
		var current_grid: Vector2i = _index_to_grid(current_index)
		for offset: Vector2i in GRID_NEIGHBOR_OFFSETS_8:
			var neighbor_y: int = current_grid.y + offset.y
			if neighbor_y < 0 or neighbor_y >= _grid_height:
				continue
			var neighbor_x: int = int(posmod(current_grid.x + offset.x, _grid_width))
			var neighbor_index: int = _flatten_index(neighbor_x, neighbor_y)
			if component_id_by_cell[neighbor_index] != -1:
				continue
			if _filled_height_grid[neighbor_index] <= _height_grid[neighbor_index] + FLOAT_EPSILON:
				continue
			if absf(_filled_height_grid[neighbor_index] - surface_height) > FLOAT_EPSILON:
				continue
			component_id_by_cell[neighbor_index] = component_id
			queue.append(neighbor_index)
	return component_cells

func _build_lake_record(
	component_cells: Array[int],
	component_id: int,
	component_id_by_cell: Array[int]
) -> LakeRecord:
	if component_cells.is_empty():
		return null
	var record := LakeRecord.new()
	record.grid_cells = PackedInt32Array(component_cells)
	record.area_grid_cells = component_cells.size()
	record.surface_height = _filled_height_grid[component_cells[0]]
	record.max_depth = _measure_component_max_depth(component_cells)
	var spill_index: int = _find_component_spill_index(component_cells, component_id, component_id_by_cell)
	if spill_index >= 0:
		record.spill_point = _index_to_grid(spill_index)
	else:
		record.spill_point = _index_to_grid(component_cells[0])
	record.lake_type = _classify_lake_type(component_cells, record.max_depth)
	record.inflow_accumulation = 0.0
	return record

func _measure_component_max_depth(component_cells: Array[int]) -> float:
	var max_depth: float = 0.0
	for cell_index: int in component_cells:
		max_depth = maxf(max_depth, _filled_height_grid[cell_index] - _height_grid[cell_index])
	return max_depth

func _find_component_spill_index(
	component_cells: Array[int],
	component_id: int,
	component_id_by_cell: Array[int]
) -> int:
	var best_index: int = -1
	var best_filled_height: float = INF
	var best_raw_height: float = INF
	for cell_index: int in component_cells:
		var cell_grid: Vector2i = _index_to_grid(cell_index)
		for offset: Vector2i in GRID_NEIGHBOR_OFFSETS_8:
			var neighbor_y: int = cell_grid.y + offset.y
			if neighbor_y < 0 or neighbor_y >= _grid_height:
				continue
			var neighbor_x: int = int(posmod(cell_grid.x + offset.x, _grid_width))
			var neighbor_index: int = _flatten_index(neighbor_x, neighbor_y)
			if component_id_by_cell[neighbor_index] == component_id:
				continue
			var neighbor_filled_height: float = _filled_height_grid[neighbor_index]
			var neighbor_raw_height: float = _height_grid[neighbor_index]
			if neighbor_filled_height < best_filled_height - FLOAT_EPSILON:
				best_index = neighbor_index
				best_filled_height = neighbor_filled_height
				best_raw_height = neighbor_raw_height
				continue
			if absf(neighbor_filled_height - best_filled_height) <= FLOAT_EPSILON:
				if neighbor_raw_height < best_raw_height - FLOAT_EPSILON:
					best_index = neighbor_index
					best_raw_height = neighbor_raw_height
					continue
				if absf(neighbor_raw_height - best_raw_height) <= FLOAT_EPSILON and _is_index_lexicographically_less(neighbor_index, best_index):
					best_index = neighbor_index
	return best_index

func _classify_lake_type(component_cells: Array[int], max_depth: float) -> StringName:
	if _planet_sampler == null:
		if component_cells.size() >= 50 and max_depth > 0.15:
			return LAKE_TYPE_TECTONIC
		return LAKE_TYPE_FLOODPLAIN
	var total_temperature: float = 0.0
	var total_height: float = 0.0
	var total_ruggedness: float = 0.0
	for cell_index: int in component_cells:
		var cell_grid: Vector2i = _index_to_grid(cell_index)
		var world_pos := Vector2i(_grid_to_world_x(cell_grid.x), _grid_to_world_y(cell_grid.y))
		var channels: WorldChannels = _planet_sampler.sample_world_channels(world_pos)
		total_temperature += channels.temperature
		total_height += channels.height
		total_ruggedness += channels.ruggedness
	var sample_count: float = float(maxi(1, component_cells.size()))
	var average_temperature: float = total_temperature / sample_count
	if average_temperature <= _resolve_frozen_lake_temperature():
		return LAKE_TYPE_GLACIAL
	if component_cells.size() >= 50 and max_depth > 0.15:
		return LAKE_TYPE_TECTONIC
	var average_height: float = total_height / sample_count
	var average_ruggedness: float = total_ruggedness / sample_count
	if average_height >= 0.58 or average_ruggedness >= 0.45:
		return LAKE_TYPE_MOUNTAIN
	return LAKE_TYPE_FLOODPLAIN

func _resolve_lake_min_area() -> int:
	if _balance == null:
		return 8
	return maxi(3, _balance.prepass_lake_min_area)

func _resolve_lake_min_depth() -> float:
	if _balance == null:
		return 0.04
	return maxf(0.01, _balance.prepass_lake_min_depth)

func _resolve_frozen_lake_temperature() -> float:
	if _balance == null:
		return 0.15
	return clampf(_balance.prepass_frozen_lake_temperature, 0.0, 0.5)

func _heap_push(heap: Array[Dictionary], cell_index: int, priority: float) -> void:
	heap.append({
		"index": cell_index,
		"priority": priority,
	})
	var child_index: int = heap.size() - 1
	while child_index > 0:
		var parent_index: int = int((child_index - 1) / 2)
		if not _is_heap_entry_less(heap[child_index], heap[parent_index]):
			break
		var temp: Dictionary = heap[parent_index]
		heap[parent_index] = heap[child_index]
		heap[child_index] = temp
		child_index = parent_index

func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	if heap.is_empty():
		return {}
	var result: Dictionary = heap[0]
	var last_index: int = heap.size() - 1
	if last_index == 0:
		heap.pop_back()
		return result
	heap[0] = heap[last_index]
	heap.pop_back()
	var parent_index: int = 0
	while true:
		var left_index: int = parent_index * 2 + 1
		if left_index >= heap.size():
			break
		var smallest_index: int = left_index
		var right_index: int = left_index + 1
		if right_index < heap.size() and _is_heap_entry_less(heap[right_index], heap[left_index]):
			smallest_index = right_index
		if not _is_heap_entry_less(heap[smallest_index], heap[parent_index]):
			break
		var temp: Dictionary = heap[parent_index]
		heap[parent_index] = heap[smallest_index]
		heap[smallest_index] = temp
		parent_index = smallest_index
	return result

func _is_heap_entry_less(left_entry: Dictionary, right_entry: Dictionary) -> bool:
	var left_priority: float = float(left_entry.get("priority", 0.0))
	var right_priority: float = float(right_entry.get("priority", 0.0))
	if left_priority < right_priority - FLOAT_EPSILON:
		return true
	if left_priority > right_priority + FLOAT_EPSILON:
		return false
	return int(left_entry.get("index", 0)) < int(right_entry.get("index", 0))

func _is_index_lexicographically_less(left_index: int, right_index: int) -> bool:
	if right_index < 0:
		return true
	var left_grid: Vector2i = _index_to_grid(left_index)
	var right_grid: Vector2i = _index_to_grid(right_index)
	if left_grid.y != right_grid.y:
		return left_grid.y < right_grid.y
	return left_grid.x < right_grid.x
