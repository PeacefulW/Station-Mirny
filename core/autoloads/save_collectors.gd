class_name SaveCollectors
extends RefCounted

## Набор функций для сбора данных сохранения.
## Не пишет на диск и не меняет состояние мира.

static func collect_meta(save_version: int) -> Dictionary:
	return {
		"save_version": save_version,
		"save_format_version": 4,
		"save_time": Time.get_datetime_string_from_system(),
		"world_seed": 0,
		"game_day": TimeManager.current_day if TimeManager else 1,
	}

static func collect_player(tree: SceneTree) -> Dictionary:
	var authority: Node = tree.root.get_node_or_null("/root/PlayerAuthority")
	var player: Node2D = authority.get_local_player() if authority else null
	if not player:
		# Fallback: static context cannot access autoloads directly.
		var players: Array[Node] = tree.get_nodes_in_group("player")
		if players.is_empty():
			return {}
		player = players[0]
	var data: Dictionary = {
		"position": {
			"x": player.global_position.x,
			"y": player.global_position.y,
		},
	}
	var z_level_managers: Array[Node] = _find_nodes_by_class(tree, "ZLevelManager")
	if not z_level_managers.is_empty():
		var z_level_manager: Node = z_level_managers[0]
		if z_level_manager.has_method("get_current_z"):
			data["z_level"] = int(z_level_manager.get_current_z())
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health:
		data["health"] = {
			"current": health.current_health,
			"max": health.max_health,
		}
	var inventory: Node = player.get_node_or_null("InventoryComponent")
	if inventory and inventory.has_method("save_state"):
		data["inventory"] = inventory.save_state()
	var equipment: Node = player.get_node_or_null("EquipmentComponent")
	if equipment and equipment.has_method("save_state"):
		data["equipment"] = equipment.save_state()
	var oxygen_system: Node = player.get_node_or_null("OxygenSystem")
	if oxygen_system and oxygen_system.has_method("save_state"):
		data["oxygen"] = oxygen_system.save_state()
	return data

static func collect_world(tree: SceneTree) -> Dictionary:
	return {
		"world_rebuild_frozen": true,
		"world_scene_present": tree.current_scene != null,
	}

static func collect_time() -> Dictionary:
	if not TimeManager:
		return {}
	return {
		"current_hour": TimeManager.current_hour,
		"current_day": TimeManager.current_day,
		"current_season": int(TimeManager.current_season),
	}

static func collect_buildings(tree: SceneTree) -> Dictionary:
	var building_systems: Array[Node] = tree.get_nodes_in_group("building_system")
	if building_systems.is_empty():
		building_systems = _find_nodes_by_class(tree, "BuildingSystem")
		if building_systems.is_empty():
			return {}
	var building_system: Node = building_systems[0]
	if building_system.has_method("save_state"):
		return building_system.save_state()

	var walls: Dictionary = building_system.get("walls") if building_system.has_method("get") else {}
	var wall_data: Array[Dictionary] = []
	for pos: Vector2i in walls:
		var wall_node: Node2D = walls[pos]
		var entry: Dictionary = {
			"x": pos.x,
			"y": pos.y,
		}
		var health: HealthComponent = wall_node.get_node_or_null("HealthComponent")
		if health:
			entry["health"] = health.current_health
		wall_data.append(entry)
	return {"walls": wall_data}

static func collect_chunk_data(tree: SceneTree) -> Dictionary:
	return {}

static func _find_nodes_by_class(tree: SceneTree, class_name_str: String) -> Array[Node]:
	var result: Array[Node] = []
	_find_recursive(tree.root, class_name_str, result)
	return result

static func _find_recursive(node: Node, class_name_str: String, result: Array[Node]) -> void:
	if node.get_class() == class_name_str or \
	   (node.get_script() and node.get_script().get_global_name() == class_name_str):
		result.append(node)
	for child: Node in node.get_children():
		_find_recursive(child, class_name_str, result)
