class_name BuildingFactory
extends RefCounted

## Фабрика создания построек по BuildingData.

func create_building(
	grid_pos: Vector2i,
	world_pos: Vector2,
	building_data: BuildingData,
	grid_size: int
) -> Node2D:
	if not building_data:
		return null
	if building_data.logic_script:
		return _create_scripted_building(grid_pos, world_pos, building_data)
	return _create_simple_building(grid_pos, world_pos, building_data, grid_size)

func _create_simple_building(
	grid_pos: Vector2i,
	world_pos: Vector2,
	building_data: BuildingData,
	grid_size: int
) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = world_pos
	wall.collision_layer = 2
	wall.collision_mask = 0

	var full_w: float = building_data.size_x * grid_size
	var full_h: float = building_data.size_y * grid_size
	var visual := ColorRect.new()
	visual.size = Vector2(full_w, full_h)
	visual.position = -Vector2(full_w, full_h) * 0.5
	visual.color = building_data.placeholder_color
	wall.add_child(visual)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(full_w, full_h)
	collision.shape = shape
	wall.add_child(collision)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = building_data.health
	wall.add_child(health)
	wall.set_meta("building_id", str(building_data.id))
	wall.set_meta("grid_pos", grid_pos)
	return wall

func _create_scripted_building(
	grid_pos: Vector2i,
	world_pos: Vector2,
	building_data: BuildingData
) -> Node2D:
	var script_res: Script = building_data.logic_script
	if not script_res and not building_data.script_path.is_empty():
		script_res = load(building_data.script_path) as Script
	if not script_res:
		push_error(Localization.t("SYSTEM_BUILD_FACTORY_SCRIPT_MISSING", {"building": building_data.get_display_name()}))
		return null

	var building_balance: Resource = building_data.logic_balance
	if not building_balance and not building_data.balance_path.is_empty():
		building_balance = load(building_data.balance_path)

	var node := StaticBody2D.new()
	node.set_script(script_res)
	if node.has_method("setup"):
		node.setup(grid_pos, world_pos, building_balance)
	else:
		node.global_position = world_pos
	node.set_meta("building_id", str(building_data.id))
	node.set_meta("grid_pos", grid_pos)
	return node
