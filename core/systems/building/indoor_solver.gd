class_name IndoorSolver
extends RefCounted

## Чистый расчёт внутренних ячеек для системы строительства.
## Не содержит побочных эффектов и не взаимодействует с узлами.

# --- Константы ---
const _BOUND_PADDING: Vector2i = Vector2i(1, 1)
const _NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

# --- Публичные методы ---

## Рассчитать все внутренние ячейки (помещения), окружённые стенами.
## [param walls] Словарь стен вида Vector2i -> Node2D.
## [return] Словарь indoor-ячеек вида Vector2i -> true.
func solve_indoor_cells(walls: Dictionary) -> Dictionary:
	var indoor_cells: Dictionary = {}
	if walls.is_empty():
		return indoor_cells
	var min_pos: Vector2i = _get_min_wall_pos(walls) - _BOUND_PADDING
	var max_pos: Vector2i = _get_max_wall_pos(walls) + _BOUND_PADDING
	var outdoor: Dictionary = _flood_fill_outdoor(walls, min_pos, max_pos)
	for x: int in range(min_pos.x, max_pos.x + 1):
		for y: int in range(min_pos.y, max_pos.y + 1):
			var pos := Vector2i(x, y)
			if not walls.has(pos) and not outdoor.has(pos):
				indoor_cells[pos] = true
	return indoor_cells

# --- Приватные методы ---

func _get_min_wall_pos(walls: Dictionary) -> Vector2i:
	var min_pos := Vector2i(999999, 999999)
	for pos: Vector2i in walls:
		min_pos = Vector2i(mini(min_pos.x, pos.x), mini(min_pos.y, pos.y))
	return min_pos

func _get_max_wall_pos(walls: Dictionary) -> Vector2i:
	var max_pos := Vector2i(-999999, -999999)
	for pos: Vector2i in walls:
		max_pos = Vector2i(maxi(max_pos.x, pos.x), maxi(max_pos.y, pos.y))
	return max_pos

func _flood_fill_outdoor(walls: Dictionary, min_pos: Vector2i, max_pos: Vector2i) -> Dictionary:
	var outdoor: Dictionary = {}
	var queue: Array[Vector2i] = [min_pos]
	outdoor[min_pos] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for offset: Vector2i in _NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = current + offset
			if _is_out_of_bounds(neighbor, min_pos, max_pos):
				continue
			if outdoor.has(neighbor) or walls.has(neighbor):
				continue
			outdoor[neighbor] = true
			queue.append(neighbor)
	return outdoor

func _is_out_of_bounds(cell: Vector2i, min_pos: Vector2i, max_pos: Vector2i) -> bool:
	if cell.x < min_pos.x or cell.x > max_pos.x:
		return true
	if cell.y < min_pos.y or cell.y > max_pos.y:
		return true
	return false
