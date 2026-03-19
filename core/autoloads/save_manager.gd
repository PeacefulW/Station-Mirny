class_name SaveManagerSingleton
extends Node

## Менеджер сохранений. Autoload-синглтон.
## Координирует сохранение/загрузку всех систем.
##
## Каждая система не знает о файлах — она только умеет
## save_state() и load_state(). SaveManager собирает всё
## и пишет на диск.
##
## Структура на диске:
## user://saves/{slot_name}/
##   ├── meta.json       ← Версия, дата, seed, мод-лист
##   ├── player.json     ← Позиция, статы, инвентарь
##   ├── world.json      ← Seed, параметры генерации
##   ├── time.json       ← День, час, сезон
##   ├── buildings.json   ← Стены, постройки (пока не в чанках)
##   └── chunks/          ← Изменения в чанках (по файлу на чанк)

# --- Константы ---
const SAVES_ROOT: String = "user://saves"
const META_FILE: String = "meta.json"
const PLAYER_FILE: String = "player.json"
const WORLD_FILE: String = "world.json"
const TIME_FILE: String = "time.json"
const BUILDINGS_FILE: String = "buildings.json"
const SAVE_VERSION: int = 1

# --- Публичные ---
## Текущий слот сохранения.
var current_slot: String = ""
## Идёт ли процесс сохранения/загрузки.
var is_busy: bool = false

func _ready() -> void:
	# Создаём корневую папку сохранений
	if not DirAccess.dir_exists_absolute(SAVES_ROOT):
		DirAccess.make_dir_recursive_absolute(SAVES_ROOT)

# --- Публичные методы ---

## Сохранить игру в указанный слот.
## Если slot_name пуст — используется текущий слот.
func save_game(slot_name: String = "") -> bool:
	if is_busy:
		push_warning("SaveManager: уже идёт операция сохранения/загрузки")
		return false
	if slot_name.is_empty():
		slot_name = current_slot
	if slot_name.is_empty():
		slot_name = "save_001"
	is_busy = true
	current_slot = slot_name
	EventBus.save_requested.emit()
	var save_path: String = SAVES_ROOT.path_join(slot_name)
	# Создаём папку слота
	if not DirAccess.dir_exists_absolute(save_path):
		DirAccess.make_dir_recursive_absolute(save_path)
	var success: bool = true
	# 1. Meta
	success = success and _write_json(save_path, META_FILE, _collect_meta())
	# 2. Player
	success = success and _write_json(save_path, PLAYER_FILE, _collect_player())
	# 3. World
	success = success and _write_json(save_path, WORLD_FILE, _collect_world())
	# 4. Time
	success = success and _write_json(save_path, TIME_FILE, _collect_time())
	# 5. Buildings
	success = success and _write_json(save_path, BUILDINGS_FILE, _collect_buildings())
	# 6. Chunks (через ChunkSaveSystem)
	var chunk_data: Dictionary = _collect_chunk_data()
	if not chunk_data.is_empty():
		success = success and ChunkSaveSystem.save_chunks(save_path, chunk_data)
	is_busy = false
	if success:
		EventBus.save_completed.emit()
	return success

## Загрузить игру из слота.
func load_game(slot_name: String) -> bool:
	if is_busy:
		push_warning("SaveManager: уже идёт операция")
		return false
	var save_path: String = SAVES_ROOT.path_join(slot_name)
	if not DirAccess.dir_exists_absolute(save_path):
		push_error("SaveManager: сохранение не найдено: %s" % slot_name)
		return false
	is_busy = true
	current_slot = slot_name
	# 1. World (seed) — должен быть первым!
	var world_data: Dictionary = _read_json(save_path, WORLD_FILE)
	if world_data.is_empty():
		push_error("SaveManager: невалидный world.json")
		is_busy = false
		return false
	_apply_world(world_data)
	# 2. Chunks
	var chunk_data: Dictionary = ChunkSaveSystem.load_chunks(save_path)
	_apply_chunk_data(chunk_data)
	# 3. Time
	var time_data: Dictionary = _read_json(save_path, TIME_FILE)
	if not time_data.is_empty():
		_apply_time(time_data)
	# 4. Buildings
	var buildings_data: Dictionary = _read_json(save_path, BUILDINGS_FILE)
	if not buildings_data.is_empty():
		_apply_buildings(buildings_data)
	# 5. Player — последним (зависит от мира)
	var player_data: Dictionary = _read_json(save_path, PLAYER_FILE)
	if not player_data.is_empty():
		_apply_player(player_data)
	is_busy = false
	EventBus.load_completed.emit()
	return true

## Получить список доступных сохранений.
## Возвращает массив словарей с мета-информацией.
func get_save_list() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var dir := DirAccess.open(SAVES_ROOT)
	if not dir:
		return saves
	dir.list_dir_begin()
	var folder_name: String = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var meta: Dictionary = _read_json(
				SAVES_ROOT.path_join(folder_name), META_FILE
			)
			if not meta.is_empty():
				meta["slot_name"] = folder_name
				saves.append(meta)
		folder_name = dir.get_next()
	# Сортируем по дате (новые первыми)
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("save_time", "") > b.get("save_time", "")
	)
	return saves

## Удалить сохранение.
func delete_save(slot_name: String) -> bool:
	var save_path: String = SAVES_ROOT.path_join(slot_name)
	if not DirAccess.dir_exists_absolute(save_path):
		return false
	ChunkSaveSystem.delete_all_chunks(save_path)
	# Удаляем JSON-файлы
	var dir := DirAccess.open(save_path)
	if dir:
		dir.list_dir_begin()
		var f: String = dir.get_next()
		while f != "":
			if f.ends_with(".json"):
				dir.remove(f)
			f = dir.get_next()
	# Удаляем пустую папку chunks и саму папку слота
	DirAccess.remove_absolute(save_path.path_join("chunks"))
	DirAccess.remove_absolute(save_path)
	return true

## Существует ли сохранение?
func save_exists(slot_name: String) -> bool:
	var meta_path: String = SAVES_ROOT.path_join(slot_name).path_join(META_FILE)
	return FileAccess.file_exists(meta_path)

# --- Сбор данных ---

func _collect_meta() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"save_time": Time.get_datetime_string_from_system(),
		"seed": WorldGenerator.world_seed if WorldGenerator else 0,
		"game_day": TimeManager.current_day if TimeManager else 1,
	}

func _collect_player() -> Dictionary:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return {}
	var player: Node2D = players[0]
	var data: Dictionary = {
		"position_x": player.global_position.x,
		"position_y": player.global_position.y,
	}
	# Скрап
	if player.has_method("collect_scrap"):
		data["scrap_count"] = player.get("scrap_count")
	# Здоровье
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health:
		data["health"] = health.current_health
		data["max_health"] = health.max_health
	# Кислород
	var o2: Node = player.get_node_or_null("OxygenSystem")
	if o2 and o2.has_method("save_state"):
		data["oxygen"] = o2.save_state()
	return data

func _collect_world() -> Dictionary:
	if not WorldGenerator:
		return {}
	var data: Dictionary = {
		"seed": WorldGenerator.world_seed,
		"spawn_tile_x": WorldGenerator.spawn_tile.x,
		"spawn_tile_y": WorldGenerator.spawn_tile.y,
	}
	# Сохраняем параметры генерации (могли быть изменены слайдерами)
	if WorldGenerator.balance:
		var b: WorldGenBalance = WorldGenerator.balance
		data["water_threshold"] = b.water_threshold
		data["rock_threshold"] = b.rock_threshold
		data["warp_strength"] = b.warp_strength
		data["ridge_weight"] = b.ridge_weight
	return data

func _collect_time() -> Dictionary:
	if not TimeManager:
		return {}
	return {
		"current_hour": TimeManager.current_hour,
		"current_day": TimeManager.current_day,
		"current_season": TimeManager.current_season,
	}

func _collect_buildings() -> Dictionary:
	var building_systems: Array[Node] = get_tree().get_nodes_in_group("building_system")
	if building_systems.is_empty():
		# Попробуем найти по классу
		var nodes: Array[Node] = _find_nodes_by_class("BuildingSystem")
		if nodes.is_empty():
			return {}
		building_systems = nodes
	var bs: Node = building_systems[0]
	if not bs.has_method("save_state"):
		# Сериализуем стены вручную
		var walls: Dictionary = bs.get("walls") if bs.has_method("get") else {}
		var wall_data: Array[Dictionary] = []
		for pos: Vector2i in walls:
			var wall_node: Node2D = walls[pos]
			var entry: Dictionary = {
				"x": pos.x, "y": pos.y,
			}
			var health: HealthComponent = wall_node.get_node_or_null("HealthComponent")
			if health:
				entry["health"] = health.current_health
			wall_data.append(entry)
		return {"walls": wall_data}
	return bs.save_state()

func _collect_chunk_data() -> Dictionary:
	# Ищем ChunkManager в дереве сцен
	var managers: Array[Node] = _find_nodes_by_class("ChunkManager")
	if managers.is_empty():
		return {}
	var cm: Node = managers[0]
	if cm.has_method("get_save_data"):
		return cm.get_save_data()
	return {}

# --- Применение данных ---

func _apply_world(data: Dictionary) -> void:
	if not WorldGenerator:
		return
	var seed_val: int = int(data.get("seed", 0))
	WorldGenerator.spawn_tile = Vector2i(
		int(data.get("spawn_tile_x", 0)),
		int(data.get("spawn_tile_y", 0))
	)
	# Восстанавливаем параметры генерации
	if WorldGenerator.balance:
		var b: WorldGenBalance = WorldGenerator.balance
		b.water_threshold = data.get("water_threshold", b.water_threshold)
		b.rock_threshold = data.get("rock_threshold", b.rock_threshold)
		b.warp_strength = data.get("warp_strength", b.warp_strength)
		b.ridge_weight = data.get("ridge_weight", b.ridge_weight)
	WorldGenerator.initialize_world(seed_val)

func _apply_chunk_data(data: Dictionary) -> void:
	var managers: Array[Node] = _find_nodes_by_class("ChunkManager")
	if managers.is_empty():
		return
	var cm: Node = managers[0]
	if cm.has_method("set_saved_data"):
		cm.set_saved_data(data)

func _apply_time(data: Dictionary) -> void:
	if not TimeManager:
		return
	TimeManager.current_hour = data.get("current_hour", 7.0)
	TimeManager.current_day = int(data.get("current_day", 1))
	TimeManager.current_season = int(data.get("current_season", 0))

func _apply_player(data: Dictionary) -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node2D = players[0]
	player.global_position = Vector2(
		data.get("position_x", 0.0),
		data.get("position_y", 0.0)
	)
	if "scrap_count" in data:
		player.set("scrap_count", int(data["scrap_count"]))
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health and "health" in data:
		health.current_health = data["health"]
		health.max_health = data.get("max_health", health.max_health)
	var o2: Node = player.get_node_or_null("OxygenSystem")
	if o2 and o2.has_method("load_state") and "oxygen" in data:
		o2.load_state(data["oxygen"])

func _apply_buildings(data: Dictionary) -> void:
	var building_systems: Array[Node] = _find_nodes_by_class("BuildingSystem")
	if building_systems.is_empty():
		return
	var bs: Node = building_systems[0]
	if bs.has_method("load_state"):
		bs.load_state(data)
		return
	# Ручное восстановление стен
	if "walls" in data:
		for wall_entry: Dictionary in data["walls"]:
			var pos := Vector2i(int(wall_entry["x"]), int(wall_entry["y"]))
			if bs.has_method("_create_wall_at"):
				bs._create_wall_at(pos)
			if "health" in wall_entry:
				var wall_node: Node2D = bs.walls.get(pos)
				if wall_node:
					var h: HealthComponent = wall_node.get_node_or_null("HealthComponent")
					if h:
						h.current_health = wall_entry["health"]
		if bs.has_method("_recalculate_indoor"):
			bs._recalculate_indoor()

# --- Утилиты ---

func _write_json(save_path: String, file_name: String, data: Dictionary) -> bool:
	if data.is_empty():
		return true
	var path: String = save_path.path_join(file_name)
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: не удалось записать %s" % path)
		return false
	file.store_string(json_string)
	file.close()
	return true

func _read_json(save_path: String, file_name: String) -> Dictionary:
	var path: String = save_path.path_join(file_name)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json_string: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_warning("SaveManager: ошибка парсинга %s" % path)
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func _find_nodes_by_class(class_name_str: String) -> Array[Node]:
	var result: Array[Node] = []
	_find_recursive(get_tree().root, class_name_str, result)
	return result

func _find_recursive(node: Node, class_name_str: String, result: Array[Node]) -> void:
	if node.get_class() == class_name_str or \
	   (node.get_script() and node.get_script().get_global_name() == class_name_str):
		result.append(node)
	for child: Node in node.get_children():
		_find_recursive(child, class_name_str, result)
