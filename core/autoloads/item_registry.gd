class_name ItemRegistrySingleton
extends Node

## Глобальный реестр игровых data-ресурсов.
## Загружает предметы, рецепты и world-resource данные из .tres
## и предоставляет доступ по ID.
## Позволяет модам регистрировать свои данные.

# --- Приватные переменные ---
const RECIPE_DATA_SCRIPT_PATH: String = "res://core/entities/recipes/recipe_data.gd"

var _items: Dictionary = {}
var _recipes: Dictionary = {}
var _resource_nodes: Dictionary = {}
var _resource_nodes_by_deposit: Dictionary = {}
var _are_recipes_loaded: bool = false

func _ready() -> void:
	# На Фазе 0 мы загружаем базовые ресурсы вручную.
	# Позже ModLoader будет парсить папки автоматически.
	_load_base_items()
	_load_resource_nodes()
	_ensure_recipes_loaded()

# --- Публичные методы ---

## Возвращает данные предмета по его строковому ID (например "base:iron_ore").
func get_item(id: String) -> ItemData:
	if _items.has(id):
		return _items[id]
	push_warning("ItemRegistry: Предмет с ID '%s' не найден." % id)
	return null

## Возвращает данные рецепта по строковому ID.
func get_recipe(id: String) -> RecipeData:
	_ensure_recipes_loaded()
	if _recipes.has(id):
		return _recipes[id]
	push_warning("ItemRegistry: Рецепт с ID '%s' не найден." % id)
	return null

## Возвращает все зарегистрированные рецепты.
func get_all_recipes() -> Array[RecipeData]:
	_ensure_recipes_loaded()
	var result: Array[RecipeData] = []
	for recipe: RecipeData in _recipes.values():
		result.append(recipe)
	return result

## Возвращает описание ресурсной ноды по её ID.
func get_resource_node(id: StringName) -> ResourceNodeData:
	if _resource_nodes.has(id):
		return _resource_nodes[id]
	push_warning("ItemRegistry: Ресурсная нода с ID '%s' не найдена." % id)
	return null

## Возвращает описание ресурсной ноды по deposit_type генератора мира.
func get_resource_node_by_deposit(deposit_type: int) -> ResourceNodeData:
	if _resource_nodes_by_deposit.has(deposit_type):
		return _resource_nodes_by_deposit[deposit_type]
	push_warning("ItemRegistry: Ресурсная нода для deposit_type '%d' не найдена." % deposit_type)
	return null

## Возвращает все зарегистрированные world-resource типы.
func get_all_resource_nodes() -> Array[ResourceNodeData]:
	var result: Array[ResourceNodeData] = []
	for resource_node: ResourceNodeData in _resource_nodes.values():
		result.append(resource_node)
	return result

## Регистрирует новый предмет в базе (используется ядром и модами).
func register_item(item: ItemData) -> void:
	if not item or item.id.is_empty():
		push_error("ItemRegistry: Попытка зарегистрировать некорректный предмет.")
		return
	_items[item.id] = item

## Регистрирует новый рецепт в базе (используется ядром и модами).
func register_recipe(recipe: RecipeData) -> void:
	if not recipe or recipe.id.is_empty():
		push_error("ItemRegistry: Попытка зарегистрировать некорректный рецепт.")
		return
	_recipes[recipe.id] = recipe

## Регистрирует описание ресурсной ноды мира.
func register_resource_node(resource_node: ResourceNodeData) -> void:
	if not resource_node or resource_node.id.is_empty():
		push_error("ItemRegistry: Попытка зарегистрировать некорректную ресурсную ноду.")
		return
	_resource_nodes[resource_node.id] = resource_node
	_resource_nodes_by_deposit[resource_node.deposit_type] = resource_node

# --- Приватные методы ---

func _load_base_items() -> void:
	var items_path: String = "res://data/items/"
	var dir := DirAccess.open(items_path)
	if not dir:
		push_warning("ItemRegistry: Не удалось открыть папку %s" % items_path)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource: Resource = load(items_path + file_name)
			if resource is ItemData:
				register_item(resource as ItemData)
		file_name = dir.get_next()

func _load_resource_nodes() -> void:
	var resources_path: String = "res://data/resources/"
	var dir := DirAccess.open(resources_path)
	if not dir:
		push_warning("ItemRegistry: Не удалось открыть папку %s" % resources_path)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource: Resource = load(resources_path + file_name)
			if resource is ResourceNodeData:
				register_resource_node(resource as ResourceNodeData)
		file_name = dir.get_next()

func _ensure_recipes_loaded() -> void:
	if _are_recipes_loaded:
		return
	_load_recipes_in_directory("res://data/recipes/")
	_are_recipes_loaded = true

func _load_recipes_in_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if dir.current_is_dir():
			if entry_name != "." and entry_name != "..":
				_load_recipes_in_directory(path.path_join(entry_name))
		elif entry_name.ends_with(".tres"):
			var recipe_path: String = path.path_join(entry_name)
			var resource: Resource = load(recipe_path)
			if _is_recipe_resource(resource):
				register_recipe(resource as RecipeData)
		entry_name = dir.get_next()

func _is_recipe_resource(resource: Resource) -> bool:
	if resource is RecipeData:
		return true
	if not resource:
		return false
	var script: Script = resource.get_script() as Script
	if not script:
		return false
	return script.resource_path == RECIPE_DATA_SCRIPT_PATH
