class_name RecipeData
extends Resource

## Базовый ресурс рецепта крафта (минимальный формат 1 вход -> 1 выход).
## Все рецепты задаются через .tres для Data-Driven расширения.

@export var id: String = "base:recipe_unknown"
@export var display_name_key: String = ""
@export var display_name: String = "Неизвестный рецепт"
@export var description_key: String = ""
@export_multiline var description: String = ""
@export var input_item_id: String = ""
@export var input_amount: int = 1
@export var output_item_id: String = ""
@export var output_amount: int = 1

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)

func get_description() -> String:
	return Localization.td(description_key, description)
