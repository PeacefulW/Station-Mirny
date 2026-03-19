class_name BuildingSystem
extends Node2D

## Система строительства. Управляет размещением построек на сетке,
## определяет герметичные помещения (indoor_cells).
## Теперь работает с BuildMenu — строит то, что выбрано.

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
var _grid_size: int = 32
var _player_scrap: int = 0
var _half_grid: Vector2 = Vector2(16, 16)
## Текущая выбранная постройка из меню (или null).
var _selected_building: BuildingData = null
## Каталог доступных построек: id(String) -> BuildingData.
var _building_catalog: Dictionary = {}
var _placement_service: BuildingPlacementService = BuildingPlacementService.new()

func _ready() -> void:
	wall_container = get_node("../WallContainer")
	if balance:
		_grid_size = balance.grid_size
		_half_grid = Vector2(_grid_size * 0.5, _grid_size * 0.5)
	_placement_service.setup(
		walls,
		wall_container,
		_grid_size,
		_half_grid,
		func() -> int: return _player_scrap,
		func(value: int) -> void: _player_scrap = value,
		func() -> void: _recalculate_indoor()
	)
	_building_catalog = _build_building_catalog()
	EventBus.scrap_collected.connect(_on_scrap_collected)
	EventBus.scrap_spent.connect(
		func(_a: int, remaining: int) -> void: _player_scrap = remaining
	)
	# Подключаемся к BuildMenu если он существует
	call_deferred("_connect_build_menu")

func _process(_delta: float) -> void:
	if is_build_mode:
		queue_redraw()

func _draw() -> void:
	# Подсветка внутренних ячеек (всегда)
	for cell_pos: Vector2i in indoor_cells:
		var world_pos: Vector2 = grid_to_world(cell_pos)
		var rect := Rect2(world_pos - _half_grid, Vector2(_grid_size, _grid_size))
		draw_rect(rect, Color(0.1, 0.25, 0.12, 0.35))
	if not is_build_mode:
		return
	# Призрак размещения
	var mouse_world: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	var snap_pos: Vector2 = grid_to_world(grid_pos)
	var rect := Rect2(snap_pos - _half_grid, Vector2(_grid_size, _grid_size))
	var can_place: bool = _placement_service._can_place_at(grid_pos, _selected_building)
	# Цвет призрака — из выбранной постройки
	var ghost_color: Color
	if can_place:
		if _selected_building:
			ghost_color = Color(_selected_building.placeholder_color, 0.55)
		else:
			ghost_color = Color(0.2, 0.9, 0.3, 0.45)
	else:
		ghost_color = Color(0.9, 0.2, 0.2, 0.35)
	draw_rect(rect, ghost_color)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build_mode"):
		_toggle_build_mode()
	elif is_build_mode and event.is_action_pressed("primary_action"):
		var world_pos: Vector2 = get_global_mouse_position()
		var grid_pos: Vector2i = world_to_grid(world_pos)
		_placement_service._try_place_building(grid_pos, _selected_building)
	elif is_build_mode and event.is_action_pressed("secondary_action"):
		var world_pos: Vector2 = get_global_mouse_position()
		var grid_pos: Vector2i = world_to_grid(world_pos)
		_placement_service._try_remove_building(grid_pos)

# --- Публичные методы ---

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / _grid_size), floori(world_pos.y / _grid_size))

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * _grid_size + _grid_size * 0.5,
		grid_pos.y * _grid_size + _grid_size * 0.5
	)

func is_cell_indoor(grid_pos: Vector2i) -> bool:
	return indoor_cells.has(grid_pos)

## Задать выбранную постройку (вызывается BuildMenu).
func set_selected_building(building: BuildingData) -> void:
	_selected_building = building

## Сохранить состояние системы строительства.
func save_state() -> Dictionary:
	var serialized: Array[Dictionary] = []
	for grid_pos: Vector2i in walls:
		var node: Node2D = walls[grid_pos]
		if not is_instance_valid(node):
			continue
		var entry: Dictionary = {
			"x": grid_pos.x,
			"y": grid_pos.y,
			"building_id": str(node.get_meta("building_id", "wall")),
		}
		var health: HealthComponent = node.get_node_or_null("HealthComponent")
		if health:
			entry["health"] = health.current_health
		if node.has_method("save_state"):
			entry["state"] = node.save_state()
		serialized.append(entry)
	return {"walls": serialized}

## Восстановить состояние системы строительства.
func load_state(data: Dictionary) -> void:
	_clear_all_buildings()
	var wall_data: Array = data.get("walls", [])
	for raw_entry: Variant in wall_data:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var grid_pos := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var building_id: String = str(entry.get("building_id", "wall"))
		var bd: BuildingData = _get_building_data_by_id(building_id)
		var node: Node2D = null
		if bd:
			node = _placement_service._create_building_at(grid_pos, bd)
		else:
			node = _placement_service._create_simple_wall(
				grid_pos,
				grid_to_world(grid_pos),
				_make_wall_default_data()
			)
		if not node:
			continue
		var health: HealthComponent = node.get_node_or_null("HealthComponent")
		if health and entry.has("health"):
			health.current_health = float(entry["health"])
		if entry.has("state") and node.has_method("load_state"):
			node.load_state(entry["state"])
	_recalculate_indoor()

# --- Приватные ---

func _connect_build_menu() -> void:
	var menus: Array[Node] = get_tree().get_nodes_in_group("build_menu")
	if menus.is_empty():
		# Ищем по типу в UI Layer
		for node: Node in get_tree().get_nodes_in_group(""):
			if node is BuildMenu:
				(node as BuildMenu).building_selected.connect(_on_menu_selection)
				return
		# Ищем вверх по дереву
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
	_selected_building = building

func _toggle_build_mode() -> void:
	is_build_mode = not is_build_mode
	if not is_build_mode:
		queue_redraw()
	EventBus.build_mode_changed.emit(is_build_mode)

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

func _clear_all_buildings() -> void:
	for pos: Vector2i in walls:
		var node: Node2D = walls[pos]
		if is_instance_valid(node):
			node.queue_free()
	walls.clear()
	indoor_cells.clear()

func _build_building_catalog() -> Dictionary:
	var catalog: Dictionary = {}
	var dir_path: String = "res://data/buildings/"
	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var res: Resource = load(dir_path + file_name)
				if res is BuildingData:
					var bd: BuildingData = res as BuildingData
					catalog[str(bd.id)] = bd
			file_name = dir.get_next()
	_register_default_buildings(catalog)
	return catalog

func _register_default_buildings(catalog: Dictionary) -> void:
	var wall := _make_wall_default_data()
	catalog[str(wall.id)] = wall
	var battery := BuildingData.new()
	battery.id = &"ark_battery"
	battery.display_name = "Батарея Ковчега"
	battery.category = BuildingData.Category.POWER
	battery.scrap_cost = 0
	battery.health = 80.0
	battery.placeholder_color = Color(0.3, 0.5, 0.8)
	battery.script_path = "res://core/entities/structures/ark_battery.gd"
	battery.balance_path = "res://data/balance/power_balance.tres"
	if not catalog.has(str(battery.id)):
		catalog[str(battery.id)] = battery
	var burner := BuildingData.new()
	burner.id = &"thermo_burner"
	burner.display_name = "Термосжигатель"
	burner.category = BuildingData.Category.POWER
	burner.scrap_cost = 8
	burner.health = 60.0
	burner.placeholder_color = Color(0.8, 0.4, 0.15)
	burner.script_path = "res://core/entities/structures/thermo_burner.gd"
	burner.balance_path = "res://data/balance/power_balance.tres"
	if not catalog.has(str(burner.id)):
		catalog[str(burner.id)] = burner

func _make_wall_default_data() -> BuildingData:
	var wall := BuildingData.new()
	wall.id = &"wall"
	wall.display_name = "Стена"
	wall.category = BuildingData.Category.STRUCTURE
	wall.scrap_cost = 2
	wall.health = 50.0
	wall.placeholder_color = Color(0.45, 0.48, 0.52)
	return wall

func _get_building_data_by_id(building_id: String) -> BuildingData:
	if _building_catalog.has(building_id):
		return _building_catalog[building_id] as BuildingData
	return null
