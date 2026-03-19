class_name BuildingSystem
extends Node2D

## Фасад системы строительства.
## Делегирует размещение, indoor-расчет и persistence профильным сервисам.

# --- Экспортируемые ---
@export var balance: BuildingBalance = null
@export var wall_container: Node2D = null

# --- Публичные ---
var is_build_mode: bool = false
## Все постройки на сетке: Vector2i -> Node2D.
var walls: Dictionary = {}
## Ячейки внутри замкнутых комнат: Vector2i -> true.
var indoor_cells: Dictionary = {}

# --- Приватные ---
var _player_scrap: int = 0
var _placement_service: BuildingPlacementService = BuildingPlacementService.new()
var _indoor_solver: IndoorSolver = IndoorSolver.new()
var _persistence: BuildingPersistence = BuildingPersistence.new()

# --- Встроенные ---

func _ready() -> void:
	wall_container = get_node("../WallContainer")
	_placement_service.setup(balance, wall_container)
	walls = _placement_service.walls
	indoor_cells = _indoor_solver.indoor_cells
	EventBus.scrap_collected.connect(_on_scrap_collected)
	EventBus.scrap_spent.connect(func(_a: int, remaining: int) -> void: _player_scrap = remaining)
	call_deferred("_connect_build_menu")

func _process(_delta: float) -> void:
	if is_build_mode:
		queue_redraw()

func _draw() -> void:
	for cell_pos: Vector2i in indoor_cells:
		var world_pos: Vector2 = grid_to_world(cell_pos)
		var half_grid: Vector2 = _placement_service.get_half_grid()
		var grid_size: int = _placement_service.get_grid_size()
		var rect := Rect2(world_pos - half_grid, Vector2(grid_size, grid_size))
		draw_rect(rect, Color(0.1, 0.25, 0.12, 0.35))
	if not is_build_mode:
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	var snap_pos: Vector2 = grid_to_world(grid_pos)
	var half_grid: Vector2 = _placement_service.get_half_grid()
	var grid_size: int = _placement_service.get_grid_size()
	var rect := Rect2(snap_pos - half_grid, Vector2(grid_size, grid_size))
	var can_place: bool = _placement_service.can_place_at(grid_pos, _player_scrap)
	var ghost_color: Color
	if can_place:
		var selected: BuildingData = _placement_service.get_selected_building()
		ghost_color = Color(selected.placeholder_color, 0.55) if selected else Color(0.2, 0.9, 0.3, 0.45)
	else:
		ghost_color = Color(0.9, 0.2, 0.2, 0.35)
	draw_rect(rect, ghost_color)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build_mode"):
		_toggle_build_mode()
	elif is_build_mode and event.is_action_pressed("primary_action"):
		_try_place_building()
	elif is_build_mode and event.is_action_pressed("secondary_action"):
		_try_remove_building()

# --- Публичные методы ---

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return _placement_service.world_to_grid(world_pos)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return _placement_service.grid_to_world(grid_pos)

func is_cell_indoor(grid_pos: Vector2i) -> bool:
	return _indoor_solver.indoor_cells.has(grid_pos)

## Задать выбранную постройку (делегирование в placement-сервис).
func set_selected_building(building: BuildingData) -> void:
	_placement_service.set_selected_building(building)

## Сохранить состояние системы строительства.
func save_state() -> Dictionary:
	return _persistence.save_state(_placement_service.walls)

## Восстановить состояние системы строительства.
func load_state(data: Dictionary) -> void:
	_persistence.load_state(data, _create_building_from_persistence, _clear_buildings_for_persistence)
	_recalculate_indoor()

# --- Приватные ---

func _connect_build_menu() -> void:
	var menus: Array[Node] = get_tree().get_nodes_in_group("build_menu")
	if menus.is_empty():
		for node: Node in get_tree().get_nodes_in_group(""):
			if node is BuildMenu:
				(node as BuildMenu).building_selected.connect(_on_menu_selection)
				return
		var ui_layer: Node = get_parent().get_node_or_null("UILayer")
		if ui_layer:
			for child: Node in ui_layer.get_children():
				if child is BuildMenu:
					(child as BuildMenu).building_selected.connect(_on_menu_selection)
					return
	else:
		var menu: BuildMenu = menus[0] as BuildMenu
		menu.building_selected.connect(_on_menu_selection)

func _on_menu_selection(building: BuildingData) -> void:
	set_selected_building(building)

func _toggle_build_mode() -> void:
	is_build_mode = not is_build_mode
	if not is_build_mode:
		queue_redraw()
	EventBus.build_mode_changed.emit(is_build_mode)

func _try_place_building() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = world_to_grid(world_pos)
	if not _placement_service.can_place_at(grid_pos, _player_scrap):
		return
	var cost: int = _placement_service.get_selected_building_cost()
	_player_scrap -= cost
	EventBus.scrap_spent.emit(cost, _player_scrap)
	var placed_pos: Vector2i = _placement_service.place_selected_at(world_pos)
	_bind_building_health(walls.get(placed_pos), placed_pos)
	_recalculate_indoor()
	EventBus.building_placed.emit(placed_pos)

func _try_remove_building() -> void:
	var removed_pos: Vector2i = _placement_service.remove_at(get_global_mouse_position())
	if removed_pos == Vector2i(2147483647, 2147483647):
		return
	_player_scrap += 1
	EventBus.scrap_collected.emit(_player_scrap)
	_recalculate_indoor()
	EventBus.building_removed.emit(removed_pos)

func _on_building_destroyed(grid_pos: Vector2i) -> void:
	if walls.has(grid_pos):
		walls[grid_pos].queue_free()
		walls.erase(grid_pos)
		_recalculate_indoor()
		EventBus.building_removed.emit(grid_pos)

func _recalculate_indoor() -> void:
	indoor_cells = _indoor_solver.recalculate(walls)
	EventBus.rooms_recalculated.emit(indoor_cells)
	queue_redraw()

func _on_scrap_collected(total: int) -> void:
	_player_scrap = total

func _bind_building_health(node: Node2D, grid_pos: Vector2i) -> void:
	if not node:
		return
	var health: HealthComponent = node.get_node_or_null("HealthComponent")
	if health and not health.died.is_connected(_on_building_destroyed.bind(grid_pos)):
		health.died.connect(_on_building_destroyed.bind(grid_pos))

func _create_building_from_persistence(grid_pos: Vector2i, building_id: String) -> Node2D:
	var node: Node2D = _placement_service.create_building_by_id(grid_pos, building_id)
	_bind_building_health(node, grid_pos)
	return node

func _clear_buildings_for_persistence() -> void:
	_placement_service.clear_all_buildings()
	_indoor_solver.indoor_cells.clear()
	indoor_cells = _indoor_solver.indoor_cells
