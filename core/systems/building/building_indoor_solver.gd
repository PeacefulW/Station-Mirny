class_name IndoorSolver
extends RefCounted

## Решатель помещений. Определяет indoor-ячейки по словарю построек.

# --- Публичные ---
## Последний рассчитанный набор indoor-ячеек: Vector2i -> true.
var indoor_cells: Dictionary = {}

const _CARDINAL_DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

# --- Публичные методы ---

## Пересчитать indoor-ячейки на основе текущих построек.
func recalculate(walls: Dictionary) -> Dictionary:
	indoor_cells.clear()
	if walls.is_empty():
		return indoor_cells
	var wall_bounds: Rect2i = _compute_wall_bounds(walls)
	var solve_bounds: Rect2i = _grow_rect(wall_bounds, 1)
	indoor_cells = _solve_indoor_in_bounds(walls, solve_bounds)
	return indoor_cells

## Решить локальный патч indoor-состояния внутри заданной proof-области.
func solve_local_patch(walls: Dictionary, current_indoor: Dictionary, proof_bounds: Rect2i) -> Dictionary:
	var previous_local: Dictionary = _collect_cells_in_bounds(current_indoor, proof_bounds)
	var next_local: Dictionary = _solve_indoor_in_bounds(walls, proof_bounds)
	var old_touches_boundary: bool = _has_cells_on_inner_boundary(previous_local, proof_bounds)
	var new_touches_boundary: bool = _has_cells_on_inner_boundary(next_local, proof_bounds)
	return {
		"proof_bounds": proof_bounds,
		"added_cells": _diff_cells(next_local, previous_local),
		"removed_cells": _diff_cells(previous_local, next_local),
		"proof_succeeded": not old_touches_boundary and not new_touches_boundary,
		"old_touches_boundary": old_touches_boundary,
		"new_touches_boundary": new_touches_boundary,
	}

func begin_recalculate_state(walls: Dictionary) -> Dictionary:
	var state: Dictionary = {
		"phase": &"done",
		"bounds": Rect2i(),
		"outdoor": {},
		"queue": [],
		"head": 0,
		"scan_x": 0,
		"scan_y": 0,
		"indoor": {},
	}
	if walls.is_empty():
		return state
	var wall_bounds: Rect2i = _compute_wall_bounds(walls)
	var solve_bounds: Rect2i = _grow_rect(wall_bounds, 1)
	var outdoor: Dictionary = {}
	var queue: Array = []
	_seed_boundary_outdoor(walls, solve_bounds, outdoor, queue)
	state["phase"] = &"flood"
	state["bounds"] = solve_bounds
	state["outdoor"] = outdoor
	state["queue"] = queue
	return state

func advance_recalculate_state(state: Dictionary, walls: Dictionary, flood_budget: int, scan_budget: int) -> bool:
	var phase: StringName = state.get("phase", &"done")
	if phase == &"done":
		return true
	if phase == &"flood":
		var queue: Array = state.get("queue", [])
		var outdoor: Dictionary = state.get("outdoor", {})
		var head: int = int(state.get("head", 0))
		var steps: int = 0
		while head < queue.size() and steps < maxi(flood_budget, 1):
			var current: Vector2i = queue[head]
			head += 1
			steps += 1
			for offset: Vector2i in _CARDINAL_DIRS:
				var neighbor: Vector2i = current + offset
				var bounds: Rect2i = state.get("bounds", Rect2i())
				if not _rect_has_point(bounds, neighbor):
					continue
				if outdoor.has(neighbor) or walls.has(neighbor):
					continue
				outdoor[neighbor] = true
				queue.append(neighbor)
		state["queue"] = queue
		state["outdoor"] = outdoor
		state["head"] = head
		if head < queue.size():
			return false
		var bounds: Rect2i = state.get("bounds", Rect2i())
		state["phase"] = &"scan"
		state["scan_x"] = bounds.position.x
		state["scan_y"] = bounds.position.y
	if state.get("phase", &"done") == &"scan":
		var bounds: Rect2i = state.get("bounds", Rect2i())
		var outdoor: Dictionary = state.get("outdoor", {})
		var indoor: Dictionary = state.get("indoor", {})
		var max_x: int = bounds.position.x + bounds.size.x
		var max_y: int = bounds.position.y + bounds.size.y
		var x: int = int(state.get("scan_x", bounds.position.x))
		var y: int = int(state.get("scan_y", bounds.position.y))
		var steps: int = 0
		while y < max_y and steps < maxi(scan_budget, 1):
			var pos := Vector2i(x, y)
			if not walls.has(pos) and not outdoor.has(pos):
				indoor[pos] = true
			steps += 1
			x += 1
			if x >= max_x:
				x = bounds.position.x
				y += 1
		state["indoor"] = indoor
		state["scan_x"] = x
		state["scan_y"] = y
		if y < max_y:
			return false
		state["phase"] = &"done"
	return true

func finish_recalculate_state(state: Dictionary) -> Dictionary:
	indoor_cells = (state.get("indoor", {}) as Dictionary).duplicate()
	return indoor_cells

# --- Приватные методы ---

func _compute_wall_bounds(walls: Dictionary) -> Rect2i:
	var min_pos := Vector2i(999999, 999999)
	var max_pos := Vector2i(-999999, -999999)
	for pos: Vector2i in walls:
		min_pos = Vector2i(mini(min_pos.x, pos.x), mini(min_pos.y, pos.y))
		max_pos = Vector2i(maxi(max_pos.x, pos.x), maxi(max_pos.y, pos.y))
	return Rect2i(
		min_pos,
		Vector2i(max_pos.x - min_pos.x + 1, max_pos.y - min_pos.y + 1)
	)

func _solve_indoor_in_bounds(walls: Dictionary, bounds: Rect2i) -> Dictionary:
	var indoor: Dictionary = {}
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return indoor
	var outdoor: Dictionary = {}
	var queue: Array[Vector2i] = []
	_seed_boundary_outdoor(walls, bounds, outdoor, queue)
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in _CARDINAL_DIRS:
			var neighbor: Vector2i = current + offset
			if not _rect_has_point(bounds, neighbor):
				continue
			if outdoor.has(neighbor) or walls.has(neighbor):
				continue
			outdoor[neighbor] = true
			queue.append(neighbor)
	var max_x: int = bounds.position.x + bounds.size.x
	var max_y: int = bounds.position.y + bounds.size.y
	for x: int in range(bounds.position.x, max_x):
		for y: int in range(bounds.position.y, max_y):
			var pos := Vector2i(x, y)
			if not walls.has(pos) and not outdoor.has(pos):
				indoor[pos] = true
	return indoor

func _seed_boundary_outdoor(walls: Dictionary, bounds: Rect2i, outdoor: Dictionary, queue: Array[Vector2i]) -> void:
	var min_x: int = bounds.position.x
	var min_y: int = bounds.position.y
	var max_x: int = bounds.position.x + bounds.size.x - 1
	var max_y: int = bounds.position.y + bounds.size.y - 1
	for x: int in range(min_x, max_x + 1):
		_enqueue_boundary_cell(Vector2i(x, min_y), walls, outdoor, queue)
		if max_y != min_y:
			_enqueue_boundary_cell(Vector2i(x, max_y), walls, outdoor, queue)
	for y: int in range(min_y + 1, max_y):
		_enqueue_boundary_cell(Vector2i(min_x, y), walls, outdoor, queue)
		if max_x != min_x:
			_enqueue_boundary_cell(Vector2i(max_x, y), walls, outdoor, queue)

func _enqueue_boundary_cell(cell: Vector2i, walls: Dictionary, outdoor: Dictionary, queue: Array[Vector2i]) -> void:
	if walls.has(cell) or outdoor.has(cell):
		return
	outdoor[cell] = true
	queue.append(cell)

func _collect_cells_in_bounds(cells: Dictionary, bounds: Rect2i) -> Dictionary:
	var subset: Dictionary = {}
	for cell: Vector2i in cells:
		if _rect_has_point(bounds, cell):
			subset[cell] = true
	return subset

func _has_cells_on_inner_boundary(cells: Dictionary, bounds: Rect2i) -> bool:
	if cells.is_empty():
		return false
	var min_x: int = bounds.position.x + 1
	var min_y: int = bounds.position.y + 1
	var max_x: int = bounds.position.x + bounds.size.x - 2
	var max_y: int = bounds.position.y + bounds.size.y - 2
	for cell: Vector2i in cells:
		if cell.x <= min_x or cell.x >= max_x:
			return true
		if cell.y <= min_y or cell.y >= max_y:
			return true
	return false

func _diff_cells(lhs: Dictionary, rhs: Dictionary) -> Dictionary:
	var diff: Dictionary = {}
	for cell: Vector2i in lhs:
		if not rhs.has(cell):
			diff[cell] = true
	return diff

func _grow_rect(rect: Rect2i, amount: int) -> Rect2i:
	var grow_by: int = maxi(amount, 0)
	var grow_vec := Vector2i(grow_by, grow_by)
	return Rect2i(rect.position - grow_vec, rect.size + grow_vec * 2)

func _rect_has_point(rect: Rect2i, point: Vector2i) -> bool:
	return point.x >= rect.position.x \
		and point.y >= rect.position.y \
		and point.x < rect.position.x + rect.size.x \
		and point.y < rect.position.y + rect.size.y
