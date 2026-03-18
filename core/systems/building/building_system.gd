class_name BuildingSystem
extends Node2D

## Система строительства. Управляет размещением стен на сетке
## и определяет, какие ячейки находятся "внутри" (замкнуты стенами).
## Рисует призрак размещения и подсветку внутренних ячеек.

# --- Экспортируемые ---
@export var balance: BuildingBalance = null
@export var wall_container: Node2D = null

# --- Публичные ---
var is_build_mode: bool = false
## Ячейки, занятые стенами. Vector2i -> Node2D (нода стены).
var walls: Dictionary = {}
## Ячейки внутри замкнутых комнат. Vector2i -> true.
var indoor_cells: Dictionary = {}

# --- Приватные ---
var _grid_size: int = 32
var _player_scrap: int = 0
var _half_grid: Vector2 = Vector2(16, 16)

func _ready() -> void:
	if balance:
		_grid_size = balance.grid_size
		_half_grid = Vector2(_grid_size * 0.5, _grid_size * 0.5)
	EventBus.scrap_collected.connect(_on_scrap_collected)
	EventBus.scrap_spent.connect(
		func(_a: int, remaining: int) -> void: _player_scrap = remaining
	)

func _process(_delta: float) -> void:
	if is_build_mode:
		queue_redraw()

func _draw() -> void:
	# Подсветка внутренних ячеек (всегда)
	for cell_pos: Vector2i in indoor_cells:
		var world_pos: Vector2 = grid_to_world(cell_pos)
		var rect := Rect2(world_pos - _half_grid, Vector2(_grid_size, _grid_size))
		draw_rect(rect, Color(0.1, 0.25, 0.12, 0.35))
	# Призрак стены (только в режиме строительства)
	if not is_build_mode:
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	var snap_pos: Vector2 = grid_to_world(grid_pos)
	var rect := Rect2(snap_pos - _half_grid, Vector2(_grid_size, _grid_size))
	var can_place: bool = _can_place_at(grid_pos)
	var ghost_color := Color(0.2, 0.9, 0.3, 0.45) if can_place else Color(0.9, 0.2, 0.2, 0.35)
	draw_rect(rect, ghost_color)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build_mode"):
		_toggle_build_mode()
	elif is_build_mode and event.is_action_pressed("primary_action"):
		_try_place_wall()
	elif is_build_mode and event.is_action_pressed("secondary_action"):
		_try_remove_wall()

## Преобразовать мировые координаты в координаты сетки.
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / _grid_size),
		floori(world_pos.y / _grid_size)
	)

## Преобразовать координаты сетки в центр ячейки.
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * _grid_size + _grid_size * 0.5,
		grid_pos.y * _grid_size + _grid_size * 0.5
	)

## Проверить, является ли ячейка внутренней.
func is_cell_indoor(grid_pos: Vector2i) -> bool:
	return indoor_cells.has(grid_pos)

# --- Приватные методы ---

func _can_place_at(grid_pos: Vector2i) -> bool:
	if not balance:
		return false
	return not walls.has(grid_pos) and _player_scrap >= balance.wall_scrap_cost

func _toggle_build_mode() -> void:
	is_build_mode = not is_build_mode
	if not is_build_mode:
		queue_redraw()
	EventBus.build_mode_changed.emit(is_build_mode)

func _try_place_wall() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = world_to_grid(world_pos)
	if not _can_place_at(grid_pos):
		return
	_player_scrap -= balance.wall_scrap_cost
	EventBus.scrap_spent.emit(balance.wall_scrap_cost, _player_scrap)
	_create_wall_at(grid_pos)
	_recalculate_indoor()
	EventBus.building_placed.emit(grid_pos)

func _try_remove_wall() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = world_to_grid(world_pos)
	if not walls.has(grid_pos):
		return
	var wall_node: Node2D = walls[grid_pos]
	wall_node.queue_free()
	walls.erase(grid_pos)
	_player_scrap += 1
	EventBus.scrap_collected.emit(_player_scrap)
	_recalculate_indoor()
	EventBus.building_removed.emit(grid_pos)

func _create_wall_at(grid_pos: Vector2i) -> void:
	var wall := StaticBody2D.new()
	wall.position = grid_to_world(grid_pos)
	wall.collision_layer = 2
	wall.collision_mask = 0
	var visual := ColorRect.new()
	visual.size = Vector2(_grid_size, _grid_size)
	visual.position = -_half_grid
	visual.color = Color(0.45, 0.48, 0.52)
	wall.add_child(visual)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(_grid_size, _grid_size)
	collision.shape = shape
	wall.add_child(collision)
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	if balance:
		health.max_health = balance.wall_health
	wall.add_child(health)
	health.died.connect(_on_wall_destroyed.bind(grid_pos))
	if wall_container:
		wall_container.add_child(wall)
	walls[grid_pos] = wall

func _on_wall_destroyed(grid_pos: Vector2i) -> void:
	if walls.has(grid_pos):
		walls[grid_pos].queue_free()
		walls.erase(grid_pos)
		_recalculate_indoor()
		EventBus.building_removed.emit(grid_pos)

func _recalculate_indoor() -> void:
	indoor_cells.clear()
	if walls.is_empty():
		EventBus.rooms_recalculated.emit(indoor_cells)
		queue_redraw()
		return
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
	EventBus.rooms_recalculated.emit(indoor_cells)
	queue_redraw()

func _on_scrap_collected(total: int) -> void:
	_player_scrap = total
