class_name SaveManagerSingleton
extends Node

## Менеджер сохранений. Autoload-синглтон.
## Отвечает только за orchestration сценариев save/load.

# --- Константы ---
const SAVES_ROOT: String = "user://saves"
const META_FILE: String = "meta.json"
const PLAYER_FILE: String = "player.json"
const WORLD_FILE: String = "world.json"
const TIME_FILE: String = "time.json"
const BUILDINGS_FILE: String = "buildings.json"
const SAVE_VERSION: int = 2

# --- Публичные ---
## Текущий слот сохранения.
var current_slot: String = ""
## Идёт ли процесс сохранения/загрузки.
var is_busy: bool = false
## Слот, который нужно загрузить после смены сцены (из главного меню).
var pending_load_slot: String = ""

func _ready() -> void:
	if not SaveIO.ensure_directory(SAVES_ROOT):
		push_error(Localization.t("SYSTEM_SAVE_ROOT_CREATE_FAILED", {"path": SAVES_ROOT}))

# --- Публичные методы ---

## Сохранить игру в указанный слот.
## Если slot_name пуст — используется текущий слот.
func save_game(slot_name: String = "") -> bool:
	if is_busy:
		push_warning(Localization.t("SYSTEM_SAVE_BUSY"))
		return false

	var resolved_slot: String = _resolve_slot_name(slot_name)
	is_busy = true
	current_slot = resolved_slot
	EventBus.save_requested.emit()

	var save_path: String = SAVES_ROOT.path_join(resolved_slot)
	if not SaveIO.ensure_directory(save_path):
		is_busy = false
		push_error(Localization.t("SYSTEM_SAVE_SLOT_CREATE_FAILED", {"slot": resolved_slot}))
		return false

	var success: bool = true
	success = success and SaveIO.write_json(
		save_path.path_join(META_FILE),
		SaveCollectors.collect_meta(SAVE_VERSION)
	)
	success = success and SaveIO.write_json(
		save_path.path_join(PLAYER_FILE),
		SaveCollectors.collect_player(get_tree())
	)
	success = success and SaveIO.write_json(
		save_path.path_join(WORLD_FILE),
		SaveCollectors.collect_world()
	)
	success = success and SaveIO.write_json(
		save_path.path_join(TIME_FILE),
		SaveCollectors.collect_time()
	)
	success = success and SaveIO.write_json(
		save_path.path_join(BUILDINGS_FILE),
		SaveCollectors.collect_buildings(get_tree())
	)

	var chunk_data: Dictionary = SaveCollectors.collect_chunk_data(get_tree())
	if not chunk_data.is_empty():
		success = success and ChunkSaveSystem.save_chunks(save_path, chunk_data)

	is_busy = false
	if success:
		EventBus.save_completed.emit()
	return success

## Загрузить игру из слота.
func load_game(slot_name: String) -> bool:
	if is_busy:
		push_warning(Localization.t("SYSTEM_SAVE_BUSY"))
		return false

	var save_path: String = SAVES_ROOT.path_join(slot_name)
	if not DirAccess.dir_exists_absolute(save_path):
		push_error(Localization.t("SYSTEM_SAVE_NOT_FOUND", {"slot": slot_name}))
		return false

	is_busy = true
	current_slot = slot_name

	var world_data: Dictionary = SaveIO.read_json(save_path.path_join(WORLD_FILE))
	if world_data.is_empty() or not SaveAppliers.apply_world(world_data):
		push_error(Localization.t("SYSTEM_SAVE_WORLD_INVALID", {"file": WORLD_FILE}))
		is_busy = false
		return false

	SaveAppliers.apply_chunk_data(get_tree(), ChunkSaveSystem.load_chunks(save_path))

	var time_data: Dictionary = SaveIO.read_json(save_path.path_join(TIME_FILE))
	if not time_data.is_empty():
		SaveAppliers.apply_time(time_data)

	var buildings_data: Dictionary = SaveIO.read_json(save_path.path_join(BUILDINGS_FILE))
	if not buildings_data.is_empty():
		SaveAppliers.apply_buildings(get_tree(), buildings_data)

	var player_data: Dictionary = SaveIO.read_json(save_path.path_join(PLAYER_FILE))
	if not player_data.is_empty():
		SaveAppliers.apply_player(get_tree(), player_data)

	is_busy = false
	EventBus.load_completed.emit()
	return true

## Получить список доступных сохранений.
## Возвращает массив словарей с мета-информацией.
func get_save_list() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var slot_names: Array[String] = SaveIO.list_save_slots(SAVES_ROOT)
	for slot_name: String in slot_names:
		var meta: Dictionary = SaveIO.read_json(SAVES_ROOT.path_join(slot_name).path_join(META_FILE))
		if not meta.is_empty():
			meta["slot_name"] = slot_name
			saves.append(meta)
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
	return SaveIO.delete_save_slot(save_path)

## Существует ли сохранение?
func save_exists(slot_name: String) -> bool:
	return FileAccess.file_exists(SAVES_ROOT.path_join(slot_name).path_join(META_FILE))

# --- Приватные ---

func _resolve_slot_name(slot_name: String) -> String:
	if not slot_name.is_empty():
		return slot_name
	if not current_slot.is_empty():
		return current_slot
	return "save_001"
