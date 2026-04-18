class_name SaveAppliers
extends RefCounted

## Набор функций для применения данных сохранения в рантайм.
## Не работает с файловой системой напрямую.

static func apply_world(tree: SceneTree, data: Dictionary) -> bool:
	var chunk_managers: Array[Node] = tree.get_nodes_in_group("chunk_manager")
	if not chunk_managers.is_empty():
		var chunk_manager: Node = chunk_managers[0]
		if chunk_manager.has_method("load_world_state"):
			chunk_manager.load_world_state(data)
	return true

static func apply_chunk_data(tree: SceneTree, data: Dictionary) -> void:
	var chunk_managers: Array[Node] = tree.get_nodes_in_group("chunk_manager")
	if chunk_managers.is_empty():
		return
	var chunk_manager: Node = chunk_managers[0]
	if chunk_manager.has_method("load_chunk_diffs"):
		chunk_manager.load_chunk_diffs(data.get("chunks", []))

static func apply_time(data: Dictionary) -> void:
	if not TimeManager:
		return
	TimeManager.restore_persisted_state(
		float(data.get("current_hour", 7.0)),
		int(data.get("current_day", 1)),
		int(data.get("current_season", 0))
	)

static func apply_buildings(tree: SceneTree, data: Dictionary) -> void:
	var building_systems: Array[Node] = _find_nodes_by_class(tree, "BuildingSystem")
	if building_systems.is_empty():
		return
	var building_system: Node = building_systems[0]
	if building_system.has_method("load_state"):
		building_system.load_state(data)
		return

	if "walls" not in data:
		return
	for wall_entry: Dictionary in data["walls"]:
		var pos := Vector2i(int(wall_entry.get("x", 0)), int(wall_entry.get("y", 0)))
		if building_system.has_method("_create_wall_at"):
			building_system._create_wall_at(pos)
		if wall_entry.has("health"):
			var wall_node: Node2D = building_system.get_building_node_at(pos) if building_system.has_method("get_building_node_at") else null
			if wall_node:
				var health: HealthComponent = wall_node.get_node_or_null("HealthComponent")
				if health:
					health.restore_state(float(wall_entry["health"]), health.max_health)
	# Legacy fallback: room rebuild handled by load_state() in primary path above.

static func apply_player(tree: SceneTree, data: Dictionary) -> void:
	var authority: Node = tree.root.get_node_or_null("/root/PlayerAuthority")
	var player: Node2D = authority.get_local_player() if authority else null
	if not player:
		# Fallback: static context cannot access autoloads directly.
		var players: Array[Node] = tree.get_nodes_in_group("player")
		if players.is_empty():
			return
		player = players[0]

	if data.has("z_level"):
		var z_level_managers: Array[Node] = _find_nodes_by_class(tree, "ZLevelManager")
		if not z_level_managers.is_empty():
			var z_level_manager: Node = z_level_managers[0]
			if z_level_manager.has_method("change_level"):
				z_level_manager.change_level(int(data.get("z_level", 0)))

	var position_data: Dictionary = data.get("position", {})
	var player_position := Vector2(
		float(position_data.get("x", 0.0)),
		float(position_data.get("y", 0.0))
	)
	player.global_position = player_position

	var inventory: Node = player.get_node_or_null("InventoryComponent")
	if inventory and inventory.has_method("load_state") and data.has("inventory"):
		inventory.load_state(data["inventory"])

	var equipment: Node = player.get_node_or_null("EquipmentComponent")
	if equipment and equipment.has_method("load_state") and data.has("equipment"):
		equipment.load_state(data["equipment"])

	var health_data: Dictionary = data.get("health", {})
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health and not health_data.is_empty():
		health.restore_state(
			float(health_data.get("current", health.current_health)),
			float(health_data.get("max", health.max_health))
		)

	var oxygen_system: Node = player.get_node_or_null("OxygenSystem")
	if oxygen_system and oxygen_system.has_method("load_state") and data.has("oxygen"):
		oxygen_system.load_state(data["oxygen"])

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
