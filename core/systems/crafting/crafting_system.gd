class_name CraftingSystem
extends Node

## Сервис ручного крафта.
## Выполняет рецепт формата 1 вход -> 1 выход для указанного инвентаря.

func _ready() -> void:
	add_to_group("crafting_system")

# --- Публичные методы ---

## Проверяет, можно ли выполнить рецепт с текущим состоянием инвентаря.
func can_craft(recipe: RecipeData, inventory: InventoryComponent) -> bool:
	if not recipe or not inventory:
		return false

	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	if not input_item:
		return false

	return inventory.has_item(input_item, recipe.input_amount)

## Пытается скрафтить рецепт. Возвращает true при успехе.
func craft(recipe: RecipeData, inventory: InventoryComponent) -> bool:
	return execute_recipe(recipe, inventory).get("success", false)

## Выполняет крафт и возвращает структурированный результат.
func execute_recipe(recipe: RecipeData, inventory: InventoryComponent) -> Dictionary:
	if not recipe or not inventory:
		return {
			"success": false,
			"message_key": "SYSTEM_CRAFT_RECIPE_OR_INVENTORY_MISSING",
		}

	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		return {
			"success": false,
			"message_key": "SYSTEM_CRAFT_ITEMS_NOT_FOUND",
		}

	if not inventory.has_item(input_item, recipe.input_amount):
		return {
			"success": false,
			"message_key": "SYSTEM_CRAFT_NOT_ENOUGH_RESOURCES",
		}

	if not inventory.remove_item(input_item, recipe.input_amount):
		return {
			"success": false,
			"message_key": "SYSTEM_CRAFT_INPUT_REMOVE_FAILED",
		}

	var leftover: int = inventory.add_item(output_item, recipe.output_amount)
	if leftover <= 0:
		return {
			"success": true,
			"message_key": "SYSTEM_CRAFT_SUCCESS",
			"message_args": {
				"item": output_item.get_display_name(),
				"amount": recipe.output_amount,
			},
			"output_item_id": output_item.id,
			"output_amount": recipe.output_amount,
		}

	# Защита от потери предметов: откатываем по возможности вход,
	# а частично добавленный выход удаляем.
	var crafted_amount: int = recipe.output_amount - leftover
	if crafted_amount > 0:
		inventory.remove_item(output_item, crafted_amount)
	inventory.add_item(input_item, recipe.input_amount)
	return {
		"success": false,
		"message_key": "SYSTEM_CRAFT_NOT_ENOUGH_SPACE",
	}