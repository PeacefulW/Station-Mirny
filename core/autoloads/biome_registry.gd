class_name BiomeRegistrySingleton
extends Node

## Глобальный реестр биомов.
## Загружает BiomeData ресурсы и предоставляет доступ по namespaced ID.
## Позволяет модам регистрировать биомы из своих директорий.

const BASE_NAMESPACE: StringName = &"base"
const BASE_BIOMES_DIR: String = "res://data/biomes"
const DEFAULT_BIOME_ID: StringName = &"base:plains"

var _biomes_by_id: Dictionary = {}
var _biomes_ordered: Array[BiomeData] = []
var _palette_index_by_id: Dictionary = {}

func _ready() -> void:
	_load_biomes_from_directory(BASE_BIOMES_DIR, BASE_NAMESPACE)

## Регистрирует биом вручную (для модов или runtime добавления).
func register_biome(biome: BiomeData, biome_namespace: StringName = BASE_NAMESPACE) -> void:
	if biome == null or str(biome.id).is_empty():
		return
	var namespaced_id: StringName = _make_namespaced_id(biome.id, biome_namespace)
	var runtime_biome: BiomeData = _duplicate_runtime_biome(biome, namespaced_id)
	var existing_index: int = int(_palette_index_by_id.get(namespaced_id, -1))
	_biomes_by_id[namespaced_id] = runtime_biome
	if existing_index >= 0 and existing_index < _biomes_ordered.size():
		_biomes_ordered[existing_index] = runtime_biome
		return
	_palette_index_by_id[namespaced_id] = _biomes_ordered.size()
	_biomes_ordered.append(runtime_biome)

## Возвращает BiomeData по namespaced ID (например "base:plains").
func get_biome(id: StringName) -> BiomeData:
	return _biomes_by_id.get(id, null) as BiomeData

## Возвращает BiomeData по short ID, пробуя base biome_namespace.
func get_biome_by_short_id(short_id: StringName) -> BiomeData:
	var namespaced: StringName = _make_namespaced_id(short_id, BASE_NAMESPACE)
	var result: BiomeData = _biomes_by_id.get(namespaced, null) as BiomeData
	if result:
		return result
	return _biomes_by_id.get(short_id, null) as BiomeData

## Возвращает все зарегистрированные биомы в порядке загрузки.
func get_all_biomes() -> Array[BiomeData]:
	return _biomes_ordered.duplicate()

## Возвращает palette index по namespaced или short ID.
func get_palette_index(biome_id: StringName) -> int:
	if biome_id == &"":
		return get_default_palette_index()
	var idx: Variant = _palette_index_by_id.get(biome_id, null)
	if idx != null:
		return int(idx)
	var namespaced: StringName = _make_namespaced_id(biome_id, BASE_NAMESPACE)
	idx = _palette_index_by_id.get(namespaced, null)
	if idx != null:
		return int(idx)
	return get_default_palette_index()

## Возвращает palette-отсортированный список биомов.
func get_palette_order() -> Array[BiomeData]:
	return _biomes_ordered.duplicate()

## Возвращает default/fallback биом.
func get_default_biome() -> BiomeData:
	var fallback: BiomeData = get_biome(DEFAULT_BIOME_ID)
	if fallback:
		return fallback
	fallback = get_biome_by_short_id(&"plains")
	if fallback:
		return fallback
	if not _biomes_ordered.is_empty():
		return _biomes_ordered[0]
	return null

func get_default_palette_index() -> int:
	var default_biome: BiomeData = get_default_biome()
	if default_biome == null or str(default_biome.id).is_empty():
		return 0
	return int(_palette_index_by_id.get(default_biome.id, 0))

## Проверяет наличие биома по ID.
func has_biome(id: StringName) -> bool:
	return _biomes_by_id.has(id) or _biomes_by_id.has(_make_namespaced_id(id, BASE_NAMESPACE))

## Загружает биомы из указанной директории с заданным biome_namespace.
func load_mod_biomes(directory_path: String, biome_namespace: StringName) -> void:
	_load_biomes_from_directory(directory_path, biome_namespace)

func _load_biomes_from_directory(dir_path: String, biome_namespace: StringName) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if not dir:
		push_error(Localization.t("SYSTEM_WORLD_BALANCE_LOAD_FAILED", {"path": dir_path}))
		return
	var resource_paths: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and (entry.ends_with(".tres") or entry.ends_with(".res")):
			resource_paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	resource_paths.sort()
	for path: String in resource_paths:
		var biome: BiomeData = load(path) as BiomeData
		if biome and not str(biome.id).is_empty():
			register_biome(biome, biome_namespace)

func _make_namespaced_id(short_id: StringName, biome_namespace: StringName) -> StringName:
	var id_str: String = str(short_id)
	if id_str.contains(":"):
		return short_id
	return StringName("%s:%s" % [str(biome_namespace), id_str])

func _duplicate_runtime_biome(biome: BiomeData, namespaced_id: StringName) -> BiomeData:
	var runtime_biome: BiomeData = biome.duplicate(true) as BiomeData
	if runtime_biome == null:
		runtime_biome = biome
	runtime_biome.id = namespaced_id
	return runtime_biome
