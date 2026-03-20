class_name CraftingSystem
extends Node

## Сервис крафта. Поддерживает рецепты с массивами входов/выходов
## и обратную совместимость с форматом 1→1.

func _ready() -> void:
	add_to_group("crafting_system")

# --- Публичные методы ---

## Проверяет, можно ли выполнить рецепт.
func can_craft(recipe: RecipeData, inventory: InventoryComponent) -> bool:
	if not recipe or not inventory:
		return false
	for input: Dictionary in recipe.get_inputs():
		var item_id: String = str(input.get("item_id", ""))
		var amount: int = int(input.get("amount", 0))
		var item: ItemData = ItemRegistry.get_item(item_id)
		if not item or not inventory.has_item(item, amount):
			return false
	return true

## Выполняет крафт и возвращает структурированный результат.
func execute_recipe(recipe: RecipeData, inventory: InventoryComponent) -> Dictionary:
	if not recipe or not inventory:
		return {"success": false, "message_key": "SYSTEM_CRAFT_RECIPE_OR_INVENTORY_MISSING"}

	var recipe_inputs: Array[Dictionary] = recipe.get_inputs()
	var recipe_outputs: Array[Dictionary] = recipe.get_outputs()

	# Проверить все входы
	for input: Dictionary in recipe_inputs:
		var item_id: String = str(input.get("item_id", ""))
		var amount: int = int(input.get("amount", 0))
		var item: ItemData = ItemRegistry.get_item(item_id)
		if not item:
			return {"success": false, "message_key": "SYSTEM_CRAFT_ITEMS_NOT_FOUND"}
		if not inventory.has_item(item, amount):
			return {"success": false, "message_key": "SYSTEM_CRAFT_NOT_ENOUGH_RESOURCES"}

	# Списать входы
	for input: Dictionary in recipe_inputs:
		var item: ItemData = ItemRegistry.get_item(str(input.get("item_id", "")))
		if not inventory.remove_item(item, int(input.get("amount", 0))):
			return {"success": false, "message_key": "SYSTEM_CRAFT_INPUT_REMOVE_FAILED"}

	# Добавить выходы
	var first_output_name: String = ""
	var first_output_amount: int = 0
	for output: Dictionary in recipe_outputs:
		var item_id: String = str(output.get("item_id", ""))
		var amount: int = int(output.get("amount", 0))
		var item: ItemData = ItemRegistry.get_item(item_id)
		if not item:
			continue
		if first_output_name.is_empty():
			first_output_name = item.get_display_name()
			first_output_amount = amount
		var leftover: int = inventory.add_item(item, amount)
		if leftover > 0:
			return {"success": false, "message_key": "SYSTEM_CRAFT_NOT_ENOUGH_SPACE"}

	return {
		"success": true,
		"message_key": "SYSTEM_CRAFT_SUCCESS",
		"message_args": {"item": first_output_name, "amount": first_output_amount},
	}
