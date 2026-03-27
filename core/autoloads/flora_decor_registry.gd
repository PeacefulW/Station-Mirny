class_name FloraDecorRegistrySingleton
extends Node

## Реестр наборов флоры и декора.
## Загружает FloraSetData/DecorSetData и предоставляет доступ по namespaced ID.

const BASE_NAMESPACE: StringName = &"base"
const BASE_FLORA_DIR: String = "res://data/flora"
const BASE_DECOR_DIR: String = "res://data/decor"

var _flora_sets: Dictionary = {}
var _decor_sets: Dictionary = {}

func _ready() -> void:
	_load_sets_from_directory(BASE_FLORA_DIR, BASE_NAMESPACE, true)
	_load_sets_from_directory(BASE_DECOR_DIR, BASE_NAMESPACE, false)

func register_flora_set(flora_set: FloraSetData, biome_namespace: StringName = BASE_NAMESPACE) -> void:
	if flora_set == null or str(flora_set.id).is_empty():
		return
	_flora_sets[_namespaced_id(flora_set.id, biome_namespace)] = flora_set

func register_decor_set(decor_set: DecorSetData, biome_namespace: StringName = BASE_NAMESPACE) -> void:
	if decor_set == null or str(decor_set.id).is_empty():
		return
	_decor_sets[_namespaced_id(decor_set.id, biome_namespace)] = decor_set

func get_flora_set(id: StringName) -> FloraSetData:
	var result: FloraSetData = _flora_sets.get(id, null) as FloraSetData
	if result:
		return result
	return _flora_sets.get(_namespaced_id(id, BASE_NAMESPACE), null) as FloraSetData

func get_decor_set(id: StringName) -> DecorSetData:
	var result: DecorSetData = _decor_sets.get(id, null) as DecorSetData
	if result:
		return result
	return _decor_sets.get(_namespaced_id(id, BASE_NAMESPACE), null) as DecorSetData

func get_flora_sets_for_ids(ids: Array[StringName]) -> Array[FloraSetData]:
	var result: Array[FloraSetData] = []
	for id: StringName in ids:
		var flora_set: FloraSetData = get_flora_set(id)
		if flora_set:
			result.append(flora_set)
	return result

func get_decor_sets_for_ids(ids: Array[StringName]) -> Array[DecorSetData]:
	var result: Array[DecorSetData] = []
	for id: StringName in ids:
		var decor_set: DecorSetData = get_decor_set(id)
		if decor_set:
			result.append(decor_set)
	return result

func load_mod_flora(directory_path: String, biome_namespace: StringName) -> void:
	_load_sets_from_directory(directory_path, biome_namespace, true)

func load_mod_decor(directory_path: String, biome_namespace: StringName) -> void:
	_load_sets_from_directory(directory_path, biome_namespace, false)

func _load_sets_from_directory(dir_path: String, biome_namespace: StringName, is_flora: bool) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if not dir:
		return
	var paths: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and (entry.ends_with(".tres") or entry.ends_with(".res")):
			paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	for path: String in paths:
		var res: Resource = load(path)
		if is_flora and res is FloraSetData:
			register_flora_set(res as FloraSetData, biome_namespace)
		elif not is_flora and res is DecorSetData:
			register_decor_set(res as DecorSetData, biome_namespace)

func _namespaced_id(short_id: StringName, biome_namespace: StringName) -> StringName:
	if str(short_id).contains(":"):
		return short_id
	return StringName("%s:%s" % [str(biome_namespace), str(short_id)])
