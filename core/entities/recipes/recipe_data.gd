class_name RecipeData
extends Resource

## Ресурс рецепта крафта. Поддерживает массивы входов/выходов
## и обратную совместимость с форматом 1→1.

@export var id: String = "base:recipe_unknown"
@export var display_name_key: String = ""
@export var display_name: String = ""
@export var description_key: String = ""
@export_multiline var description: String = ""

@export_group("Ингредиенты (расширенный формат)")
## Массив входов: [{item_id: "base:iron_ore", amount: 2}, ...].
@export var inputs: Array[Dictionary] = []
## Массив выходов: [{item_id: "base:iron_ingot", amount: 1}, ...].
@export var outputs: Array[Dictionary] = []

@export_group("Ингредиенты (1→1, обратная совместимость)")
## Единственный вход (используется если inputs пуст).
@export var input_item_id: String = ""
@export var input_amount: int = 1
## Единственный выход (используется если outputs пуст).
@export var output_item_id: String = ""
@export var output_amount: int = 1

@export_group("Крафт")
## Тип станции ("" = руками).
@export var station_type: StringName = &""
## Время крафта (секунды).
@export var craft_time: float = 1.0

@export_group("Прогрессия")
## Требуемая технология ("" = доступно сразу).
@export var required_tech: StringName = &""

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)

func get_description() -> String:
	return Localization.td(description_key, description)

## Получить входы (с обратной совместимостью).
func get_inputs() -> Array[Dictionary]:
	if not inputs.is_empty():
		return inputs
	if not input_item_id.is_empty():
		return [{"item_id": input_item_id, "amount": input_amount}]
	return []

## Получить выходы (с обратной совместимостью).
func get_outputs() -> Array[Dictionary]:
	if not outputs.is_empty():
		return outputs
	if not output_item_id.is_empty():
		return [{"item_id": output_item_id, "amount": output_amount}]
	return []
