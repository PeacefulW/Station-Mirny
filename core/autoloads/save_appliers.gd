class_name SaveAppliers
extends RefCounted

## Набор функций для применения данных сохранения в рантайм.
## Не работает с файловой системой напрямую.

static func apply_world(data: Dictionary) -> bool:
	if not WorldGenerator:
		return false
	if not data.has("seed") or not data.has("spawn_tile"):
		return false

	var spawn_tile: Dictionary = data.get("spawn_tile", {})
	WorldGenerator.spawn_tile = Vector2i(
		int(spawn_tile.get("x", 0)),
		int(spawn_tile.get("y", 0))
	)

	if WorldGenerator.balance:
		var generation: Dictionary = data.get("generation", {})
		var balance: WorldGenBalance = WorldGenerator.balance
		balance.water_threshold = generation.get("water_threshold", balance.water_threshold)
		balance.rock_threshold = generation.get("rock_threshold", balance.rock_threshold)
		balance.warp_strength = generation.get("warp_strength", balance.warp_strength)
		balance.ridge_weight = generation.get("ridge_weight", balance.ridge_weight)

	WorldGenerator.initialize_world(int(data.get("seed", 0)))
	return true

static func apply_chunk_data(tree: SceneTree, data: Dictionary) -> void:
	var managers: Array[Node] = _find_nodes_by_class(tree, "ChunkManager")
	if managers.is_empty():
		return
	var chunk_manager: Node = managers[0]
	if chunk_manager.has_method("set_saved_data"):
		chunk_manager.set_saved_data(data)

static func apply_time(data: Dictionary) -> void:
	if not TimeManager:
		return
	TimeManager.current_hour = data.get("current_hour", 7.0)
	TimeManager.current_day = int(data.get("current_day", 1))
	TimeManager.current_season = int(data.get("current_season", 0))

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
			var wall_node: Node2D = building_system.walls.get(pos)
			if wall_node:
				var health: HealthComponent = wall_node.get_node_or_null("HealthComponent")
				if health:
					health.current_health = wall_entry["health"]
	if building_system.has_method("_recalculate_indoor"):
		building_system._recalculate_indoor()

static func apply_player(tree: SceneTree, data: Dictionary) -> void:
	var players: Array[Node] = tree.get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node2D = players[0]

	var position_data: Dictionary = data.get("position", {})
	player.global_position = Vector2(
		float(position_data.get("x", 0.0)),
		float(position_data.get("y", 0.0))
	)

	var resources: Dictionary = data.get("resources", {})
	if resources.has("scrap_count"):
		player.set("scrap_count", int(resources["scrap_count"]))

	var health_data: Dictionary = data.get("health", {})
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health and not health_data.is_empty():
		health.current_health = float(health_data.get("current", health.current_health))
		health.max_health = float(health_data.get("max", health.max_health))

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
