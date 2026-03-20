class_name BuildingData
extends Resource

## Определение типа постройки. Каждый тип — отдельный .tres файл.
## Мод создаёт новый .tres → здание появляется в меню строительства.

# --- Перечисления ---
enum Category { STRUCTURE, POWER, LIFE_SUPPORT, PRODUCTION, DEFENSE }

@export_group("Идентификация")
## Уникальный ID.
@export var id: StringName = &""
## Ключ локализации имени.
@export var display_name_key: String = ""
## Отображаемое имя.
@export var display_name: String = ""
## Ключ локализации описания.
@export var description_key: String = ""
## Описание (для тултипа).
@export var description: String = ""
## Категория (для вкладок меню).
@export var category: Category = Category.STRUCTURE

@export_group("Стоимость")
## Сколько скрапа стоит.
@export var scrap_cost: int = 2

@export_group("Характеристики")
## Здоровье постройки.
@export var health: float = 50.0
## Размер в тайлах (1 = 1×1, позже 2 = 2×2).
@export var tile_size: int = 1
## Блокирует ли проход (стена = да, лампа = нет).
@export var is_solid: bool = true

@export_group("Визуал (заглушки)")
## Цвет заглушки.
@export var placeholder_color: Color = Color(0.5, 0.5, 0.5)
## Горячая клавиша (0 = нет). Для быстрого доступа.
@export var hotkey: int = 0

@export_group("Скрипт")
## Путь к скрипту здания (пустой = обычная стена без логики).
## Пример: "res://core/entities/structures/thermo_burner.gd"
@export var script_path: String = ""
## Путь к ресурсу баланса здания (если нужен).
@export var balance_path: String = ""
## Прямая ссылка на script-ресурс. Предпочтительнее runtime load().
@export var logic_script: Script = null
## Прямая ссылка на ресурс баланса. Предпочтительнее runtime load().
@export var logic_balance: Resource = null

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)

func get_description() -> String:
	return Localization.td(description_key, description)
