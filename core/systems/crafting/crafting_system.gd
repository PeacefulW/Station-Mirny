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
	if not recipe or not inventory:
		return false

	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		return false

	if not inventory.has_item(input_item, recipe.input_amount):
		return false

	if not inventory.remove_item(input_item, recipe.input_amount):
		return false

	var leftover: int = inventory.add_item(output_item, recipe.output_amount)
	if leftover <= 0:
		return true

	# Защита от потери предметов: откатываем по возможности вход,
	# а частично добавленный выход удаляем.
	var crafted_amount: int = recipe.output_amount - leftover
	if crafted_amount > 0:
		inventory.remove_item(output_item, crafted_amount)
	inventory.add_item(input_item, recipe.input_amount)
	return false
