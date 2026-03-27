class_name ChunkSaveSystem
extends RefCounted

## Читает/пишет изменения чанков на диск.
## Один JSON-файл на каждый изменённый чанк.
## Неизменённые чанки не занимают места на диске.
##
## Формат: saves/{slot}/chunks/chunk_{z}_{x}_{y}.json
## Содержимое: Dictionary { координаты_тайла -> изменение }

# --- Константы ---
const CHUNKS_DIR: String = "chunks"

# --- Публичные методы ---

## Сохранить все изменённые чанки на диск.
## [param save_path] — папка сохранения (напр. "user://saves/save_001").
## [param chunk_data] — z-aware Dictionary[Vector3i -> Dictionary] от ChunkManager.
static func save_chunks(save_path: String, chunk_data: Dictionary) -> bool:
	var chunks_path: String = save_path.path_join(CHUNKS_DIR)
	# Создаём папку если нет
	if not DirAccess.dir_exists_absolute(chunks_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(chunks_path)
		if err != OK:
			push_error(Localization.t("SYSTEM_CHUNK_SAVE_DIR_CREATE_FAILED", {"path": chunks_path}))
			return false
	var saved_count: int = 0
	var expected_files: Dictionary = {}
	for key: Variant in chunk_data:
		var identity: Dictionary = _normalize_chunk_identity(key)
		if not identity.get("valid", false):
			continue
		var coord: Vector2i = _canonicalize_chunk_coord(identity["coord"] as Vector2i)
		var z_level: int = int(identity.get("z", 0))
		var modifications: Dictionary = chunk_data[key]
		var file_path: String = _chunk_file_path(chunks_path, coord, z_level)
		if modifications.is_empty():
			# Если изменений нет — удаляем файл (чанк стал чистым)
			_delete_chunk_file(chunks_path, coord, z_level)
			continue
		expected_files[file_path.get_file()] = true
		var serialized: Dictionary = _serialize_chunk(coord, z_level, modifications)
		var json_string: String = JSON.stringify(serialized, "\t")
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if not file:
			push_error(Localization.t("SYSTEM_CHUNK_SAVE_WRITE_FAILED", {"path": file_path}))
			continue
		file.store_string(json_string)
		file.close()
		saved_count += 1
	_delete_stale_chunk_files(chunks_path, expected_files)
	return true

## Загрузить все сохранённые чанки с диска.
## Возвращает z-aware Dictionary[Vector3i -> Dictionary].
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
				var chunk_key: Vector3i = chunk_result["key"] as Vector3i
				result[chunk_key] = chunk_result["modifications"]
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
static func _chunk_file_path(chunks_dir: String, coord: Vector2i, z_level: int) -> String:
	var canonical_coord: Vector2i = _canonicalize_chunk_coord(coord)
	return chunks_dir.path_join("chunk_%d_%d_%d.json" % [z_level, canonical_coord.x, canonical_coord.y])

static func _legacy_chunk_file_path(chunks_dir: String, coord: Vector2i) -> String:
	return chunks_dir.path_join("chunk_%d_%d.json" % [coord.x, coord.y])

## Удалить файл чанка если существует.
static func _delete_chunk_file(chunks_dir: String, coord: Vector2i, z_level: int) -> void:
	var path: String = _chunk_file_path(chunks_dir, coord, z_level)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if z_level == 0:
		var legacy_path: String = _legacy_chunk_file_path(chunks_dir, coord)
		if FileAccess.file_exists(legacy_path):
			DirAccess.remove_absolute(legacy_path)

static func _delete_stale_chunk_files(chunks_dir: String, expected_files: Dictionary) -> void:
	var dir := DirAccess.open(chunks_dir)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name.begins_with("chunk_") and not expected_files.has(file_name):
			dir.remove(file_name)
		file_name = dir.get_next()

## Сериализовать данные чанка в словарь для JSON.
## Ключи Vector2i превращаются в строки "(x,y)".
static func _serialize_chunk(coord: Vector2i, z_level: int, modifications: Dictionary) -> Dictionary:
	var canonical_coord: Vector2i = _canonicalize_chunk_coord(coord)
	var mods: Dictionary = {}
	for tile_pos: Vector2i in modifications:
		var key: String = "(%d,%d)" % [tile_pos.x, tile_pos.y]
		mods[key] = modifications[tile_pos]
	return {
		"coord_x": canonical_coord.x,
		"coord_y": canonical_coord.y,
		"coord_z": z_level,
		"version": 3,
		"modifications": mods,
	}

## Загрузить один файл чанка.
## Возвращает {"coord": Vector2i, "z": int, "key": Vector3i, "modifications": Dictionary} или пустой.
static func _load_single_chunk(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning(Localization.t("SYSTEM_CHUNK_SAVE_READ_FAILED", {"path": file_path}))
		return {}
	var json_string: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	var parse_err: Error = json.parse(json_string)
	if parse_err != OK:
		push_warning(Localization.t("SYSTEM_CHUNK_SAVE_PARSE_FAILED", {
			"path": file_path,
			"error": json.get_error_message(),
		}))
		return {}
	var data: Dictionary = json.data
	if not data.has("coord_x") or not data.has("modifications"):
		push_warning(Localization.t("SYSTEM_CHUNK_SAVE_INVALID_FORMAT", {"path": file_path}))
		return {}
	var coord := _canonicalize_chunk_coord(Vector2i(int(data["coord_x"]), int(data["coord_y"])))
	var z_level: int = int(data.get("coord_z", 0))
	# Восстанавливаем ключи из строк "(x,y)" обратно в Vector2i
	var modifications: Dictionary = {}
	for key: String in data["modifications"]:
		var tile_pos: Vector2i = _parse_vector2i_key(key)
		modifications[tile_pos] = data["modifications"][key]
	return {
		"coord": coord,
		"z": z_level,
		"key": Vector3i(coord.x, coord.y, z_level),
		"modifications": modifications,
	}

## Распарсить строку "(x,y)" в Vector2i.
static func _parse_vector2i_key(key: String) -> Vector2i:
	var cleaned: String = key.replace("(", "").replace(")", "")
	var parts: PackedStringArray = cleaned.split(",")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(parts[0].strip_edges().to_int(), parts[1].strip_edges().to_int())

static func _normalize_chunk_identity(key: Variant) -> Dictionary:
	if key is Vector3i:
		var coord3: Vector3i = key as Vector3i
		return {
			"valid": true,
			"coord": _canonicalize_chunk_coord(Vector2i(coord3.x, coord3.y)),
			"z": coord3.z,
		}
	if key is Vector2i:
		return {
			"valid": true,
			"coord": _canonicalize_chunk_coord(key as Vector2i),
			"z": 0,
		}
	return {"valid": false}

static func _canonicalize_chunk_coord(coord: Vector2i) -> Vector2i:
	if WorldGenerator and WorldGenerator.has_method("canonicalize_chunk_coord"):
		return WorldGenerator.canonicalize_chunk_coord(coord)
	return coord
