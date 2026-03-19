class_name IndoorSolver
extends RefCounted

## Решатель помещений. Определяет indoor-ячейки по словарю построек.

# --- Публичные ---
## Последний рассчитанный набор indoor-ячееек: Vector2i -> true.
var indoor_cells: Dictionary = {}

# --- Публичные методы ---

## Пересчитать indoor-ячейки на основе текущих построек.
func recalculate(walls: Dictionary) -> Dictionary:
	indoor_cells.clear()
	if walls.is_empty():
		return indoor_cells

	var min_pos := Vector2i(999999, 999999)
	var max_pos := Vector2i(-999999, -999999)
	for pos: Vector2i in walls:
		min_pos = Vector2i(mini(min_pos.x, pos.x), mini(min_pos.y, pos.y))
		max_pos = Vector2i(maxi(max_pos.x, pos.x), maxi(max_pos.y, pos.y))
	min_pos -= Vector2i(1, 1)
	max_pos += Vector2i(1, 1)

	var outdoor: Dictionary = {}
	var queue: Array[Vector2i] = [min_pos]
	outdoor[min_pos] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = current + offset
			if neighbor.x < min_pos.x or neighbor.x > max_pos.x:
				continue
			if neighbor.y < min_pos.y or neighbor.y > max_pos.y:
				continue
			if outdoor.has(neighbor) or walls.has(neighbor):
				continue
			outdoor[neighbor] = true
			queue.append(neighbor)

	for x: int in range(min_pos.x, max_pos.x + 1):
		for y: int in range(min_pos.y, max_pos.y + 1):
			var pos := Vector2i(x, y)
			if not walls.has(pos) and not outdoor.has(pos):
				indoor_cells[pos] = true
	return indoor_cells
