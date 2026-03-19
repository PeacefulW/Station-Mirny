class_name ItemRegistrySingleton
extends Node

## Глобальный реестр всех предметов в игре.
## Загружает .tres файлы и предоставляет к ним доступ по ID.
## Позволяет модам регистрировать свои предметы.

# --- Приватные переменные ---
var _items: Dictionary = {}

func _ready() -> void:
	# На Фазе 0 мы загружаем базовые ресурсы вручную.
	# Позже ModLoader будет парсить папки автоматически.
	_load_base_items()

# --- Публичные методы ---

## Возвращает данные предмета по его строковому ID (например "base:iron_ore").
func get_item(id: String) -> ItemData:
	if _items.has(id):
		return _items[id]
	push_warning("ItemRegistry: Предмет с ID '%s' не найден." % id)
	return null

## Регистрирует новый предмет в базе (используется ядром и модами).
func register_item(item: ItemData) -> void:
	if not item or item.id.is_empty():
		push_error("ItemRegistry: Попытка зарегистрировать некорректный предмет.")
		return
	_items[item.id] = item

# --- Приватные методы ---

func _load_base_items() -> void:
	# Папка, где мы будем хранить .tres файлы наших предметов
	var items_path: String = "res://data/items/"
	var dir := DirAccess.open(items_path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var resource: Resource = load(items_path + file_name)
				if resource is ItemData:
					register_item(resource as ItemData)
			file_name = dir.get_next()
	else:
		push_warning("ItemRegistry: Не удалось открыть папку %s" % items_path)