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
var _player: Player = null
var _placement_service: BuildingPlacementService = BuildingPlacementService.new()
var _indoor_solver: IndoorSolver = IndoorSolver.new()
var _persistence: BuildingPersistence = BuildingPersistence.new()
var _command_executor: CommandExecutor = null

# --- Встроенные ---

func _ready() -> void:
	add_to_group("building_system")
	if not wall_container:
		wall_container = get_node_or_null("../WallContainer") as Node2D
	if not wall_container:
		push_error(Localization.t("SYSTEM_BUILD_WALL_CONTAINER_MISSING"))
		return
	_player = _find_player()
	_placement_service.setup(balance, wall_container)
	walls = _placement_service.walls
	indoor_cells = _indoor_solver.indoor_cells
	_command_executor = _find_command_executor()
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
	var selected: BuildingData = _placement_service.get_selected_building()
	if not selected:
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	var grid_size: int = _placement_service.get_grid_size()
	var origin_world := Vector2(grid_pos.x * grid_size, grid_pos.y * grid_size)
	var full_size := Vector2(selected.size_x * grid_size, selected.size_y * grid_size)
	var can_place: bool = _placement_service.can_place_at(grid_pos, _player_scrap)
	var ghost_color: Color
	if can_place:
		ghost_color = Color(selected.placeholder_color, 0.55)
	else:
		ghost_color = Color(0.9, 0.2, 0.2, 0.35)
	draw_rect(Rect2(origin_world, full_size), ghost_color)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build_mode"):
		_toggle_build_mode()
	elif is_build_mode and event.is_action_pressed("primary_action"):
		_execute_place_command()
	elif is_build_mode and event.is_action_pressed("secondary_action"):
		_execute_remove_command()

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
		return
	var menu: BuildMenu = menus[0] as BuildMenu
	if menu and not menu.building_selected.is_connected(_on_menu_selection):
		menu.building_selected.connect(_on_menu_selection)

func _on_menu_selection(building: BuildingData) -> void:
	set_selected_building(building)

func _toggle_build_mode() -> void:
	is_build_mode = not is_build_mode
	if not is_build_mode:
		queue_redraw()
	EventBus.build_mode_changed.emit(is_build_mode)

func place_selected_building_at(world_pos: Vector2) -> Dictionary:
	var grid_pos: Vector2i = world_to_grid(world_pos)
	var selected_building: BuildingData = _placement_service.get_selected_building()
	if not selected_building:
		return {"success": false, "message_key": "SYSTEM_BUILD_NOT_SELECTED"}
	if not _placement_service.can_place_at(grid_pos, _player_scrap):
		return {"success": false, "message_key": "SYSTEM_BUILD_CANNOT_PLACE"}
	var cost: int = _placement_service.get_selected_building_cost()
	if not _player and not _find_player():
		return {"success": false, "message_key": "SYSTEM_PLAYER_NOT_FOUND"}
	if not _player.spend_scrap(cost):
		return {"success": false, "message_key": "SYSTEM_BUILD_NOT_ENOUGH_SCRAP"}
	_player_scrap = _player.get_scrap_count()
	var placed_pos: Vector2i = _placement_service.place_selected_at(world_pos)
	if placed_pos == Vector2i(2147483647, 2147483647):
		_player.collect_scrap(cost)
		_player_scrap = _player.get_scrap_count()
		return {"success": false, "message_key": "SYSTEM_BUILD_CREATE_FAILED"}
	var building_node: Node2D = walls.get(placed_pos)
	if not building_node:
		_player.collect_scrap(cost)
		_player_scrap = _player.get_scrap_count()
		return {"success": false, "message_key": "SYSTEM_BUILD_CREATE_FAILED"}
	EventBus.scrap_spent.emit(cost, _player_scrap)
	_bind_building_health(walls.get(placed_pos), placed_pos)
	_recalculate_indoor()
	EventBus.building_placed.emit(placed_pos)
	return {
		"success": true,
		"message_key": "SYSTEM_BUILD_PLACED",
		"message_args": {
			"building": selected_building.get_display_name(),
		},
		"grid_pos": placed_pos,
		"building_id": str(selected_building.id),
	}

func remove_building_at(world_pos: Vector2) -> Dictionary:
	var removal_result: Dictionary = _placement_service.remove_at(world_pos)
	if removal_result.is_empty():
		return {"success": false, "message_key": "SYSTEM_BUILD_NOT_FOUND"}
	var removed_pos: Vector2i = removal_result.get("grid_pos", Vector2i.ZERO)
	var building_id: String = str(removal_result.get("building_id", ""))
	var refund_amount: int = 1
	var building_data: BuildingData = _placement_service.get_building_data_by_id(building_id)
	if building_data:
		refund_amount = maxi(building_data.scrap_cost, 0)
	if _player or _find_player():
		_player.collect_scrap(refund_amount)
	_recalculate_indoor()
	EventBus.building_removed.emit(removed_pos)
	return {
		"success": true,
		"message_key": "SYSTEM_BUILD_REMOVED",
		"message_args": {
			"amount": refund_amount,
		},
		"grid_pos": removed_pos,
		"refund_amount": refund_amount,
	}

func _on_building_destroyed(grid_pos: Vector2i) -> void:
	if not walls.has(grid_pos):
		return
	var node: Node2D = walls[grid_pos]
	var origin: Vector2i = node.get_meta("grid_origin", grid_pos) as Vector2i
	var sx: int = int(node.get_meta("size_x", 1))
	var sy: int = int(node.get_meta("size_y", 1))
	for dx: int in range(sx):
		for dy: int in range(sy):
			walls.erase(Vector2i(origin.x + dx, origin.y + dy))
	node.queue_free()
	_recalculate_indoor()
	EventBus.building_removed.emit(origin)

func _recalculate_indoor() -> void:
	indoor_cells = _indoor_solver.recalculate(walls)
	EventBus.rooms_recalculated.emit(indoor_cells)
	queue_redraw()

func _on_scrap_collected(total: int) -> void:
	_player_scrap = total

func _find_player() -> Player:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	_player = players[0] as Player
	return _player

func _find_command_executor() -> CommandExecutor:
	var executors: Array[Node] = get_tree().get_nodes_in_group("command_executor")
	if executors.is_empty():
		return null
	return executors[0] as CommandExecutor

func _execute_place_command() -> void:
	if not _command_executor:
		_command_executor = _find_command_executor()
	if not _command_executor:
		place_selected_building_at(get_global_mouse_position())
		return
	var command := PlaceBuildingCommand.new().setup(self, get_global_mouse_position())
	_command_executor.execute(command)

func _execute_remove_command() -> void:
	if not _command_executor:
		_command_executor = _find_command_executor()
	if not _command_executor:
		remove_building_at(get_global_mouse_position())
		return
	var command := RemoveBuildingCommand.new().setup(self, get_global_mouse_position())
	_command_executor.execute(command)

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
