class_name BuildingData
extends Resource

## Определение типа постройки. Каждый тип — отдельный .tres файл.
## Мод создаёт новый .tres → здание появляется в нужной вкладке автоматически.

# --- Перечисления ---
enum Category {
	STRUCTURE,
	DOORS,
	POWER,
	PRODUCTION,
	LIFE_SUPPORT,
	WATER,
	DEFENSE,
	VERTICAL,
	DECOR,
}

## Ключи локализации для каждой категории.
const CATEGORY_NAME_KEYS: Dictionary = {
	Category.STRUCTURE: "BUILD_CAT_STRUCTURE",
	Category.DOORS: "BUILD_CAT_DOORS",
	Category.POWER: "BUILD_CAT_POWER",
	Category.PRODUCTION: "BUILD_CAT_PRODUCTION",
	Category.LIFE_SUPPORT: "BUILD_CAT_LIFE_SUPPORT",
	Category.WATER: "BUILD_CAT_WATER",
	Category.DEFENSE: "BUILD_CAT_DEFENSE",
	Category.VERTICAL: "BUILD_CAT_VERTICAL",
	Category.DECOR: "BUILD_CAT_DECOR",
}

@export_group("Идентификация")
## Уникальный ID.
@export var id: StringName = &""
## Ключ локализации имени.
@export var display_name_key: String = ""
## Отображаемое имя (fallback).
@export var display_name: String = ""
## Ключ локализации описания.
@export var description_key: String = ""
## Описание (fallback).
@export var description: String = ""
## Иконка здания.
@export var icon: Texture2D = null
## Категория (для вкладок меню).
@export var category: Category = Category.STRUCTURE

@export_group("Размещение")
## Ширина в тайлах.
@export var size_x: int = 1
## Высота в тайлах.
@export var size_y: int = 1
## Можно ли поворачивать (R).
@export var can_rotate: bool = false
## Блокирует ли проход (стена = да, лампа = нет).
@export var is_solid: bool = true

@export_group("Стоимость")
## Расширенная стоимость: [{item_id: "base:scrap", amount: 5}, ...].
@export var cost: Array[Dictionary] = []
## Обратная совместимость: скрап (если cost пуст).
@export var scrap_cost: int = 0

@export_group("Энергия")
## Потребление (Вт).
@export var power_consumption: float = 0.0
## Выработка (Вт).
@export var power_production: float = 0.0

@export_group("Прогрессия")
## Требуемая технология (пусто = доступно сразу).
@export var required_tech: StringName = &""

@export_group("Визуал")
## Цвет заглушки.
@export var placeholder_color: Color = Color(0.5, 0.5, 0.5)
## Здоровье постройки.
@export var health: float = 100.0
## Горячая клавиша (0 = нет).
@export var hotkey: int = 0

@export_group("Логика")
## Прямая ссылка на script-ресурс.
@export var logic_script: Script = null
## Прямая ссылка на ресурс баланса.
@export var logic_balance: Resource = null
## Путь к скрипту здания (fallback).
@export var script_path: String = ""
## Путь к ресурсу баланса (fallback).
@export var balance_path: String = ""

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)

func get_description() -> String:
	return Localization.td(description_key, description)
