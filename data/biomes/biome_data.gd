class_name BiomeData
extends Resource

## Определение биома. Описывает визуальные и геймплейные
## характеристики одной климатической зоны.
## Мод добавляет новый биом — создаёт новый .tres файл.

@export_group("Идентификация")
## Уникальный ID биома.
@export var id: StringName = &""
## Ключ локализации имени.
@export var display_name_key: String = ""
## Отображаемое имя.
@export var display_name: String = ""

@export_group("Тайлы")
## ID тайла земли в тайлсете (основная поверхность).
@export var ground_tile_id: int = 0
## ID тайла камня.
@export var rock_tile_id: int = 1
## ID тайла воды.
@export var water_tile_id: int = 2
## ID тайла песка (переходная зона у воды).
@export var sand_tile_id: int = 3
## ID тайла травы (декоративная поверхность).
@export var grass_tile_id: int = 4

@export_group("Цвета (для заглушек без тайлсета)")
## Цвет земли.
@export var ground_color: Color = Color(0.22, 0.18, 0.12)
## Цвет камня.
@export var rock_color: Color = Color(0.35, 0.33, 0.30)
## Цвет воды.
@export var water_color: Color = Color(0.10, 0.15, 0.28)
## Цвет песка.
@export var sand_color: Color = Color(0.45, 0.38, 0.25)
## Цвет травы.
@export var grass_color: Color = Color(0.35, 0.28, 0.10)

@export_group("Окружающая среда")
## Базовая температура биома (°C).
@export var base_temperature: float = -5.0
## Множитель плотности спор (1.0 = стандарт).
@export var spore_density_multiplier: float = 1.0
## Множитель частоты появления врагов.
@export var enemy_frequency_multiplier: float = 1.0
## Множитель плотности ресурсов.
@export var resource_density_multiplier: float = 1.0

@export_group("Растительность")
## Доступные типы деревьев (ID из реестра ресурсов).
@export var tree_types: Array[StringName] = [&"dead_tree"]
## Вероятность декоративной травы (0.0 – 1.0).
@export var grass_coverage: float = 0.6

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)