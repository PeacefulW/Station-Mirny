class_name BuildingPersistence
extends RefCounted

## Сериализация и десериализация построек для сохранений.
## Не знает деталей инстанцирования: использует callback-и.

# --- Публичные методы ---

## Сохранить состояние построек в формате save-файла.
func save_state(walls: Dictionary) -> Dictionary:
	return serialize_walls(walls)

## Загрузить состояние построек через callback-и.
func load_state(data: Dictionary, create_building_cb: Callable, clear_cb: Callable) -> void:
	deserialize_walls(data, create_building_cb, clear_cb)

## Сериализует словарь построек в словарь с массивом "walls".
## Многотайловые здания записываются один раз (по grid_origin).
func serialize_walls(walls: Dictionary) -> Dictionary:
	var serialized: Array[Dictionary] = []
	var saved_ids: Dictionary = {}
	for grid_pos: Vector2i in walls:
		var node: Node2D = walls[grid_pos]
		if not is_instance_valid(node):
			continue
		var nid: int = node.get_instance_id()
		if saved_ids.has(nid):
			continue
		saved_ids[nid] = true
		var origin: Vector2i = node.get_meta("grid_origin", grid_pos) as Vector2i
		var entry: Dictionary = {
			"x": origin.x,
			"y": origin.y,
			"building_id": str(node.get_meta("building_id", "wall")),
		}
		var health: HealthComponent = node.get_node_or_null("HealthComponent")
		if health:
			entry["health"] = health.current_health
		if node.has_method("save_state"):
			entry["state"] = node.save_state()
		serialized.append(entry)
	return {"walls": serialized}

## Десериализует словарь "walls" и восстанавливает постройки через callback.
## Если building_id неизвестен, выполняет fallback на "wall".
func deserialize_walls(data: Dictionary, create_building_cb: Callable, clear_cb: Callable) -> void:
	_clear_all_buildings(clear_cb)
	var wall_data: Array = data.get("walls", [])
	for raw_entry: Variant in wall_data:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var grid_pos := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var building_id: String = str(entry.get("building_id", "wall"))
		var node: Node2D = create_building_cb.call(grid_pos, building_id)
		if not node and building_id != "wall":
			node = create_building_cb.call(grid_pos, "wall")
		if not node:
			continue
		var health: HealthComponent = node.get_node_or_null("HealthComponent")
		if health and entry.has("health"):
			health.current_health = float(entry["health"])
		if entry.has("state") and node.has_method("load_state"):
			node.load_state(entry["state"])

# --- Приватные методы ---

func _clear_all_buildings(clear_cb: Callable) -> void:
	if clear_cb.is_valid():
		clear_cb.call()
