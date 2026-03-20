class_name CraftRecipeCommand
extends GameCommand

var _crafting_system: CraftingSystem = null
var _inventory: InventoryComponent = null
var _recipe: RecipeData = null

func setup(crafting_system: CraftingSystem, inventory: InventoryComponent, recipe: RecipeData) -> CraftRecipeCommand:
	_crafting_system = crafting_system
	_inventory = inventory
	_recipe = recipe
	return self

func execute() -> Dictionary:
	if not _crafting_system or not _inventory or not _recipe:
		return {
			"success": false,
			"message_key": "SYSTEM_CRAFT_UNAVAILABLE",
		}
	return _crafting_system.execute_recipe(_recipe, _inventory)