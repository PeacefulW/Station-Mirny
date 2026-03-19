class_name SaveIO
extends RefCounted

## Файловый I/O для системы сохранений.
## Не содержит геймплейной логики.

static func ensure_directory(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	return DirAccess.make_dir_recursive_absolute(path) == OK

static func write_json(path: String, data: Dictionary) -> bool:
	if data.is_empty():
		return true
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(json_string)
	file.close()
	return true

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json_string: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

static func list_save_slots(saves_root: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(saves_root)
	if not dir:
		return result
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			result.append(name)
		name = dir.get_next()
	return result

static func delete_save_slot(slot_path: String) -> bool:
	if not DirAccess.dir_exists_absolute(slot_path):
		return false
	var dir := DirAccess.open(slot_path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				dir.remove(file_name)
			file_name = dir.get_next()
	DirAccess.remove_absolute(slot_path.path_join("chunks"))
	DirAccess.remove_absolute(slot_path)
	return true
