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
var _building_factory: BuildingFactory = BuildingFactory.new()

# --- Публичные методы ---

## Инициализирует сервис ссылками на баланс и контейнер построек.
func setup(balance: BuildingBalance, wall_container: Node2D) -> void:
	_balance = balance
	_wall_container = wall_container
	if _balance:
		_grid_size = _balance.grid_size
		_half_grid = Vector2(_grid_size * 0.5, _grid_size * 0.5)

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

## Проверяет, можно ли разместить постройку в клетке (все тайлы свободны).
func can_place_at(grid_pos: Vector2i, player_scrap: int) -> bool:
	if not _selected_building:
		return false
	if player_scrap < _selected_building.scrap_cost:
		return false
	for dx: int in range(_selected_building.size_x):
		for dy: int in range(_selected_building.size_y):
			if walls.has(Vector2i(grid_pos.x + dx, grid_pos.y + dy)):
				return false
	return true

## Возвращает стоимость выбранной постройки.
func get_selected_building_cost() -> int:
	if not _selected_building:
		return 0
	return _selected_building.scrap_cost

## Размещает выбранную постройку в позиции мыши.
func place_selected_at(mouse_world: Vector2) -> Vector2i:
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	var node: Node2D = _create_building_at(grid_pos, _selected_building)
	if not node:
		return Vector2i(2147483647, 2147483647)
	return grid_pos

## Удаляет постройку в позиции мыши (освобождает все занятые тайлы).
func remove_at(mouse_world: Vector2) -> Dictionary:
	var grid_pos: Vector2i = world_to_grid(mouse_world)
	if not walls.has(grid_pos):
		return {}
	var node: Node2D = walls[grid_pos]
	var building_id: String = str(node.get_meta("building_id", ""))
	var origin: Vector2i = node.get_meta("grid_origin", grid_pos) as Vector2i
	var sx: int = int(node.get_meta("size_x", 1))
	var sy: int = int(node.get_meta("size_y", 1))
	for dx: int in range(sx):
		for dy: int in range(sy):
			walls.erase(Vector2i(origin.x + dx, origin.y + dy))
	node.queue_free()
	return {
		"grid_pos": origin,
		"building_id": building_id,
	}

func get_building_data_by_id(building_id: String) -> BuildingData:
	return _get_building_data_by_id(building_id)

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

## Создать постройку по BuildingData. Занимает все тайлы size_x × size_y.
func _create_building_at(grid_pos: Vector2i, bd: BuildingData) -> Node2D:
	if not bd:
		return null
	var world_pos: Vector2 = _get_building_world_pos(grid_pos, bd)
	var node: Node2D = _building_factory.create_building(grid_pos, world_pos, bd, _grid_size)
	if not node:
		push_error(Localization.t("SYSTEM_BUILD_PLACEMENT_CREATE_FAILED", {"building": bd.get_display_name()}))
		return null
	node.set_meta("grid_origin", grid_pos)
	node.set_meta("size_x", bd.size_x)
	node.set_meta("size_y", bd.size_y)
	if _wall_container:
		_wall_container.add_child(node)
	for dx: int in range(bd.size_x):
		for dy: int in range(bd.size_y):
			walls[Vector2i(grid_pos.x + dx, grid_pos.y + dy)] = node
	return node

## Позиция мира для центра многотайлового здания.
func _get_building_world_pos(grid_pos: Vector2i, bd: BuildingData) -> Vector2:
	var cx: float = grid_pos.x * _grid_size + (bd.size_x * _grid_size) * 0.5
	var cy: float = grid_pos.y * _grid_size + (bd.size_y * _grid_size) * 0.5
	return Vector2(cx, cy)

func _get_building_data_by_id(building_id: String) -> BuildingData:
	var registry_building: BuildingData = ItemRegistry.get_building(StringName(building_id))
	if registry_building:
		return registry_building
	return BuildingCatalog.get_default_building(building_id)
