class_name ChunkSaveSystem
extends RefCounted

## Читает/пишет изменения чанков на диск.
## Один JSON-файл на каждый изменённый чанк.
## Неизменённые чанки не занимают места на диске.
##
## Формат: saves/{slot}/chunks/chunk_{x}_{y}.json
## Содержимое: Dictionary { координаты_тайла -> изменение }

# --- Константы ---
const CHUNKS_DIR: String = "chunks"

# --- Публичные методы ---

## Сохранить все изменённые чанки на диск.
## [param save_path] — папка сохранения (напр. "user://saves/save_001").
## [param chunk_data] — Dictionary[Vector2i -> Dictionary] от ChunkManager.
static func save_chunks(save_path: String, chunk_data: Dictionary) -> bool:
	var chunks_path: String = save_path.path_join(CHUNKS_DIR)
	# Создаём папку если нет
	if not DirAccess.dir_exists_absolute(chunks_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(chunks_path)
		if err != OK:
			push_error("ChunkSaveSystem: не удалось создать %s" % chunks_path)
			return false
	var saved_count: int = 0
	for coord: Vector2i in chunk_data:
		var modifications: Dictionary = chunk_data[coord]
		if modifications.is_empty():
			# Если изменений нет — удаляем файл (чанк стал чистым)
			_delete_chunk_file(chunks_path, coord)
			continue
		var file_path: String = _chunk_file_path(chunks_path, coord)
		var serialized: Dictionary = _serialize_chunk(coord, modifications)
		var json_string: String = JSON.stringify(serialized, "\t")
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if not file:
			push_error("ChunkSaveSystem: не удалось записать %s" % file_path)
			continue
		file.store_string(json_string)
		file.close()
		saved_count += 1
	return true

## Загрузить все сохранённые чанки с диска.
## Возвращает Dictionary[Vector2i -> Dictionary].
static func load_chunks(save_path: String) -> Dictionary:
	var chunks_path: String = save_path.path_join(CHUNKS_DIR)
	var result: Dictionary = {}
	if not DirAccess.dir_exists_absolute(chunks_path):
		return result
	var dir := DirAccess.open(chunks_path)
	if not dir:
		return result
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name.begins_with("chunk_"):
			var file_path: String = chunks_path.path_join(file_name)
			var chunk_result: Dictionary = _load_single_chunk(file_path)
			if not chunk_result.is_empty():
				var coord: Vector2i = chunk_result["coord"]
				result[coord] = chunk_result["modifications"]
		file_name = dir.get_next()
	return result

## Удалить все файлы чанков (при удалении сохранения).
static func delete_all_chunks(save_path: String) -> void:
	var chunks_path: String = save_path.path_join(CHUNKS_DIR)
	if not DirAccess.dir_exists_absolute(chunks_path):
		return
	var dir := DirAccess.open(chunks_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			dir.remove(file_name)
		file_name = dir.get_next()

# --- Приватные методы ---

## Путь к файлу конкретного чанка.
static func _chunk_file_path(chunks_dir: String, coord: Vector2i) -> String:
	return chunks_dir.path_join("chunk_%d_%d.json" % [coord.x, coord.y])

## Удалить файл чанка если существует.
static func _delete_chunk_file(chunks_dir: String, coord: Vector2i) -> void:
	var path: String = _chunk_file_path(chunks_dir, coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## Сериализовать данные чанка в словарь для JSON.
## Ключи Vector2i превращаются в строки "(x,y)".
static func _serialize_chunk(coord: Vector2i, modifications: Dictionary) -> Dictionary:
	var mods: Dictionary = {}
	for tile_pos: Vector2i in modifications:
		var key: String = "(%d,%d)" % [tile_pos.x, tile_pos.y]
		mods[key] = modifications[tile_pos]
	return {
		"coord_x": coord.x,
		"coord_y": coord.y,
		"version": 1,
		"modifications": mods,
	}

## Загрузить один файл чанка.
## Возвращает {"coord": Vector2i, "modifications": Dictionary} или пустой.
static func _load_single_chunk(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("ChunkSaveSystem: не удалось прочитать %s" % file_path)
		return {}
	var json_string: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	var parse_err: Error = json.parse(json_string)
	if parse_err != OK:
		push_warning("ChunkSaveSystem: ошибка парсинга %s: %s" % [file_path, json.get_error_message()])
		return {}
	var data: Dictionary = json.data
	if not data.has("coord_x") or not data.has("modifications"):
		push_warning("ChunkSaveSystem: невалидный формат %s" % file_path)
		return {}
	var coord := Vector2i(int(data["coord_x"]), int(data["coord_y"]))
	# Восстанавливаем ключи из строк "(x,y)" обратно в Vector2i
	var modifications: Dictionary = {}
	for key: String in data["modifications"]:
		var tile_pos: Vector2i = _parse_vector2i_key(key)
		modifications[tile_pos] = data["modifications"][key]
	return {"coord": coord, "modifications": modifications}

## Распарсить строку "(x,y)" в Vector2i.
static func _parse_vector2i_key(key: String) -> Vector2i:
	var cleaned: String = key.replace("(", "").replace(")", "")
	var parts: PackedStringArray = cleaned.split(",")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(parts[0].strip_edges().to_int(), parts[1].strip_edges().to_int())
