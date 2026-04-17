class_name ResourceNodeData
extends Resource

## Определение типа ресурсной ноды (рудная жила, дерево, камень...).
## Мод создаёт новый .tres файл — появляется новый ресурс в мире.

@export_group("Идентификация")
## Уникальный ID.
@export var id: StringName = &""
## Ключ локализации имени.
@export var display_name_key: String = ""
## Отображаемое имя.
@export var display_name: String = ""

@export_group("Добыча")
## ID предмета, который выпадает при добыче.
@export var drop_item_id: StringName = &""
## Количество за одну добычу.
@export var drop_amount_min: int = 1
@export var drop_amount_max: int = 3
## Сколько раз можно добыть до истощения (0 = бесконечно).
@export var harvest_count: int = 5
## Время одной добычи (секунды).
@export var harvest_time: float = 1.5
## Восстанавливается ли со временем.
@export var regenerates: bool = false
## Время полного восстановления (секунды).
@export var regen_time: float = 300.0

@export_group("Визуал (заглушки)")
## Цвет заглушки (пока нет спрайтов).
@export var placeholder_color: Color = Color(0.5, 0.5, 0.5)
## Размер заглушки в пикселях.
@export var placeholder_size: Vector2 = Vector2(24, 24)

@export_group("Коллизия")
## Блокирует ли проход.
@export var is_solid: bool = true
## Радиус коллизии.
@export var collision_radius: float = 12.0

@export_group("Связь с генерацией")
## Какому внутреннему типу залежи соответствует.
@export var deposit_type: int = 0

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)
