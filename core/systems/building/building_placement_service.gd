class_name BuildingPlacementService
extends RefCounted

## Сервис размещения построек. Инкапсулирует логику создания и удаления нод на сетке.

# --- Публичные ---
var walls: Dictionary = {}

# --- Приватные ---
var _balance: BuildingBalance = null
var _wall_container: Node2D = null
var _grid_size: int = 32
var _half_grid: Vector2 = Vector2(16, 16)
var _selected_building: BuildingData = null
var _building_catalog: Dictionary = {}

# --- Публичные методы ---

## Инициализирует сервис ссылками на баланс и контейнер построек.
func setup(balance: BuildingBalance, wall_container: Node2D) -> void:
	_balance = balance
	_wall_container = wall_container
	if _balance:
		_grid_size = _balance.grid_size
		_half_grid = Vector2(_grid_size * 0.5, _grid_size * 0.5)
	_building_catalog = _build_building_catalog()

## Перевод мировых координат в координаты сетки.
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / _grid_size), floori(world_pos.y / _grid_size))

## Перевод координат сетки в мировые координаты центра клетки.
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * _grid_size + _grid_size * 0.5,
		grid_pos.y * _grid_size + _grid_size * 0.5
	)

## Возвращает размер клетки в пикселях.
func get_grid_size() -> int:
	return _grid_size

## Возвращает половину клетки для отрисовки.
func get_half_grid() -> Vector2:
	return _half_grid

## Возвращает выбранную постройку.
func get_selected_building() -> BuildingData:
	return _selected_building

## Задает выбранную постройку.
func set_selected_building(building: BuildingData) -> void:
	_selected_building = building

## Проверяет, можно ли разместить постройку в клетке.
func can_place_at(grid_pos: Vector2i, player_scrap: int) -> bool:
	if walls.has(grid_pos):
		return false
	if not _selected_building:
		return false
	return player_scrap >= _selected_building.scrap_cost

## Возвращает стоимость выбранной постройки.
func get_selected_building_cost() -> int:
	if not _selected_building:
		return 0
	return _selected_building.scrap_cost

## Размещает выбранную постройку в позиции мыши.
func place_selected_at(mouse_world: Vector2) -> Vector2i:
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	_create_building_at(grid_pos, _selected_building)
	return grid_pos

## Удаляет постройку в позиции мыши.
func remove_at(mouse_world: Vector2) -> Vector2i:
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	if not walls.has(grid_pos):
		return Vector2i(2147483647, 2147483647)
	var node: Node2D = walls[grid_pos]
	node.queue_free()
	walls.erase(grid_pos)
	return grid_pos

## Очистить все постройки из контейнера и словаря.
func clear_all_buildings() -> void:
	for pos: Vector2i in walls:
		var node: Node2D = walls[pos]
		if is_instance_valid(node):
			node.queue_free()
	walls.clear()

## Создать постройку с сохранённым id в указанной клетке.
func create_building_by_id(grid_pos: Vector2i, building_id: String) -> Node2D:
	var bd: BuildingData = _get_building_data_by_id(building_id)
	if bd:
		return _create_building_at(grid_pos, bd)
	return null

# --- Приватные методы ---

## Создать постройку по BuildingData.
func _create_building_at(grid_pos: Vector2i, bd: BuildingData) -> Node2D:
	if not bd:
		return null
	var snap_pos: Vector2 = grid_to_world(grid_pos)
	if not bd.script_path.is_empty():
		return _create_scripted_building(grid_pos, snap_pos, bd)
	return _create_simple_wall(grid_pos, snap_pos, bd)

## Создать обычную стену без скриптовой логики.
func _create_simple_wall(grid_pos: Vector2i, snap_pos: Vector2, bd: BuildingData) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = snap_pos
	wall.collision_layer = 2
	wall.collision_mask = 0

	var visual := ColorRect.new()
	visual.size = Vector2(_grid_size, _grid_size)
	visual.position = -_half_grid
	visual.color = bd.placeholder_color
	wall.add_child(visual)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(_grid_size, _grid_size)
	collision.shape = shape
	wall.add_child(collision)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = bd.health
	wall.add_child(health)
	wall.set_meta("building_id", str(bd.id) if not str(bd.id).is_empty() else "wall")

	if _wall_container:
		_wall_container.add_child(wall)
	walls[grid_pos] = wall
	return wall

## Создать здание с собственным скриптом.
func _create_scripted_building(grid_pos: Vector2i, snap_pos: Vector2, bd: BuildingData) -> Node2D:
	var script_res: GDScript = load(bd.script_path) as GDScript
	if not script_res:
		push_error("BuildingPlacementService: не найден скрипт %s" % bd.script_path)
		return _create_simple_wall(grid_pos, snap_pos, bd)

	var bld_balance: Resource = null
	if not bd.balance_path.is_empty():
		bld_balance = load(bd.balance_path)

	var node := StaticBody2D.new()
	node.set_script(script_res)
	if node.has_method("setup"):
		node.setup(grid_pos, snap_pos, bld_balance)
	else:
		node.global_position = snap_pos
	node.set_meta("building_id", str(bd.id))

	if _wall_container:
		_wall_container.add_child(node)
	walls[grid_pos] = node
	return node

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
