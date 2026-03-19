class_name BuildingPlacementService
extends RefCounted

## Сервис размещения/удаления построек.
## Инкапсулирует операции с walls, трату scrap и создание нод построек.

# --- Приватные ---
var _walls: Dictionary = {}
var _wall_container: Node2D = null
var _grid_size: int = 32
var _half_grid: Vector2 = Vector2(16, 16)
var _get_player_scrap: Callable = Callable()
var _set_player_scrap: Callable = Callable()
var _recalculate_indoor: Callable = Callable()

# --- Публичные методы ---

## Настройка зависимостей сервиса.
func setup(
	walls: Dictionary,
	wall_container: Node2D,
	grid_size: int,
	half_grid: Vector2,
	get_player_scrap: Callable,
	set_player_scrap: Callable,
	recalculate_indoor: Callable
) -> void:
	_walls = walls
	_wall_container = wall_container
	_grid_size = grid_size
	_half_grid = half_grid
	_get_player_scrap = get_player_scrap
	_set_player_scrap = set_player_scrap
	_recalculate_indoor = recalculate_indoor

func _can_place_at(grid_pos: Vector2i, selected_building: BuildingData) -> bool:
	if _walls.has(grid_pos):
		return false
	if not selected_building:
		return false
	return _get_current_scrap() >= selected_building.scrap_cost

func _try_place_building(grid_pos: Vector2i, selected_building: BuildingData) -> void:
	if not _can_place_at(grid_pos, selected_building):
		return
	var new_scrap: int = _get_current_scrap() - selected_building.scrap_cost
	_set_current_scrap(new_scrap)
	EventBus.scrap_spent.emit(selected_building.scrap_cost, new_scrap)
	_create_building_at(grid_pos, selected_building)
	_call_recalculate_indoor()
	EventBus.building_placed.emit(grid_pos)

func _try_remove_building(grid_pos: Vector2i) -> void:
	if not _walls.has(grid_pos):
		return
	var node: Node2D = _walls[grid_pos]
	node.queue_free()
	_walls.erase(grid_pos)
	var new_scrap: int = _get_current_scrap() + 1
	_set_current_scrap(new_scrap)
	EventBus.scrap_collected.emit(new_scrap)
	_call_recalculate_indoor()
	EventBus.building_removed.emit(grid_pos)

## Создать постройку по BuildingData.
func _create_building_at(grid_pos: Vector2i, bd: BuildingData) -> Node2D:
	var snap_pos: Vector2 = _grid_to_world(grid_pos)
	if not bd.script_path.is_empty():
		return _create_scripted_building(grid_pos, snap_pos, bd)
	return _create_simple_wall(grid_pos, snap_pos, bd)

## Создать обычную стену без логики.
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
	health.died.connect(_on_building_destroyed.bind(grid_pos))

	wall.set_meta("building_id", str(bd.id) if not str(bd.id).is_empty() else "wall")
	if _wall_container:
		_wall_container.add_child(wall)
	_walls[grid_pos] = wall
	return wall

## Создать здание с собственным скриптом (батарея, термосжигатель...).
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

	var health: HealthComponent = node.get_node_or_null("HealthComponent")
	if health:
		health.died.connect(_on_building_destroyed.bind(grid_pos))

	node.set_meta("building_id", str(bd.id))
	if _wall_container:
		_wall_container.add_child(node)
	_walls[grid_pos] = node
	return node

func _on_building_destroyed(grid_pos: Vector2i) -> void:
	if _walls.has(grid_pos):
		_walls[grid_pos].queue_free()
		_walls.erase(grid_pos)
		_call_recalculate_indoor()
		EventBus.building_removed.emit(grid_pos)

# --- Приватные методы ---

func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * _grid_size + _grid_size * 0.5,
		grid_pos.y * _grid_size + _grid_size * 0.5
	)

func _call_recalculate_indoor() -> void:
	if _recalculate_indoor.is_valid():
		_recalculate_indoor.call()

func _get_current_scrap() -> int:
	if _get_player_scrap.is_valid():
		return int(_get_player_scrap.call())
	return 0

func _set_current_scrap(value: int) -> void:
	if _set_player_scrap.is_valid():
		_set_player_scrap.call(value)
