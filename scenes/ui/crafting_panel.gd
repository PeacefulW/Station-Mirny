class_name CraftingPanel
extends VBoxContainer

## Правая панель крафта для окна инвентаря.
## Показывает рецепты и выполняет крафт по клику.

var _inventory: InventoryComponent = null
var _crafting_system: CraftingSystem = null
var _recipes: Array[RecipeData] = []
var _recipe_list: VBoxContainer = null
var _recipe_description: Label = null
var _craft_feedback: Label = null

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(360, 320)
	size_flags_horizontal = SIZE_EXPAND_FILL
	_build_ui()
	_load_recipes()
	_refresh_recipe_list()

## Настраивает ссылки на нужные системы и перечитывает рецепты.
func setup(inventory: InventoryComponent, crafting_system: CraftingSystem) -> void:
	_inventory = inventory
	_crafting_system = crafting_system
	_load_recipes()
	_refresh_recipe_list()

## Обновляет доступность рецептов и подписи после изменения инвентаря.
func refresh() -> void:
	_refresh_recipe_list()

func _build_ui() -> void:
	var recipe_title := Label.new()
	recipe_title.text = "Крафт"
	recipe_title.add_theme_font_size_override("font_size", 14)
	add_child(recipe_title)

	var recipe_scroll := ScrollContainer.new()
	recipe_scroll.custom_minimum_size = Vector2(360, 200)
	recipe_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(recipe_scroll)

	_recipe_list = VBoxContainer.new()
	_recipe_list.add_theme_constant_override("separation", 6)
	recipe_scroll.add_child(_recipe_list)

	_recipe_description = Label.new()
	_recipe_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recipe_description.text = "Выберите рецепт справа."
	_recipe_description.add_theme_font_size_override("font_size", 12)
	_recipe_description.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	add_child(_recipe_description)

	_craft_feedback = Label.new()
	_craft_feedback.text = ""
	_craft_feedback.add_theme_font_size_override("font_size", 12)
	_craft_feedback.add_theme_color_override("font_color", Color(0.65, 0.72, 0.9))
	add_child(_craft_feedback)

func _load_recipes() -> void:
	_recipes = ItemRegistry.get_all_recipes()
	_recipes.sort_custom(func(a: RecipeData, b: RecipeData) -> bool: return a.display_name < b.display_name)

func _refresh_recipe_list() -> void:
	if not _recipe_list:
		return
	for child: Node in _recipe_list.get_children():
		child.queue_free()

	for recipe: RecipeData in _recipes:
		var button := Button.new()
		button.text = _format_recipe_button_text(recipe)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_recipe_pressed.bind(recipe))
		_recipe_list.add_child(button)

func _on_recipe_pressed(recipe: RecipeData) -> void:
	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		_craft_feedback.text = "Ошибка рецепта: предмет не найден в реестре"
		_craft_feedback.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
		return

	_recipe_description.text = "%s\n\nНужно: %s x%d\nРезультат: %s x%d" % [
		recipe.description,
		input_item.display_name,
		recipe.input_amount,
		output_item.display_name,
		recipe.output_amount
	]

	if not _crafting_system or not _inventory:
		_craft_feedback.text = "Система крафта недоступна"
		_craft_feedback.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
		return

	if _crafting_system.craft(recipe, _inventory):
		_craft_feedback.text = "Скрафчено: %s x%d" % [output_item.display_name, recipe.output_amount]
		_craft_feedback.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
	else:
		_craft_feedback.text = "Недостаточно ресурсов или нет места в инвентаре"
		_craft_feedback.add_theme_color_override("font_color", Color(0.95, 0.55, 0.35))

	_refresh_recipe_list()

func _format_recipe_button_text(recipe: RecipeData) -> String:
	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		return "%s\n(некорректный рецепт)" % recipe.display_name

	var can_make: bool = false
	if _crafting_system and _inventory:
		can_make = _crafting_system.can_craft(recipe, _inventory)

	var marker: String = "✓" if can_make else "✗"
	return "%s %s\n%s x%d → %s x%d" % [
		marker,
		recipe.display_name,
		input_item.display_name,
		recipe.input_amount,
		output_item.display_name,
		recipe.output_amount
	]
