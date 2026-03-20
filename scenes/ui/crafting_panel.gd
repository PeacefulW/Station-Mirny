class_name CraftingPanel
extends VBoxContainer

## Правая панель крафта для окна инвентаря.
## Показывает рецепты и выполняет крафт по клику.

signal craft_succeeded(message: String)
signal craft_failed(message: String)

var _inventory: InventoryComponent = null
var _crafting_system: CraftingSystem = null
var _recipes: Array[RecipeData] = []
var _recipe_scroll: ScrollContainer = null
var _recipe_list: VBoxContainer = null
var _recipe_description: Label = null
var _craft_feedback: Label = null
var _command_executor: CommandExecutor = null

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
	_command_executor = _find_command_executor()
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

	_recipe_scroll = ScrollContainer.new()
	_recipe_scroll.custom_minimum_size = Vector2(360, 200)
	_recipe_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_recipe_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipe_scroll.resized.connect(_sync_recipe_list_width)
	add_child(_recipe_scroll)

	_recipe_list = VBoxContainer.new()
	_recipe_list.add_theme_constant_override("separation", 6)
	_recipe_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_recipe_scroll.add_child(_recipe_list)

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

	_sync_recipe_list_width()

func _load_recipes() -> void:
	_recipes = ItemRegistry.get_all_recipes()
	_recipes.sort_custom(func(a: RecipeData, b: RecipeData) -> bool: return a.display_name < b.display_name)

func _refresh_recipe_list() -> void:
	if not _recipe_list:
		return
	for child: Node in _recipe_list.get_children():
		child.queue_free()

	if _recipes.is_empty():
		var no_recipes := Label.new()
		no_recipes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		no_recipes.text = "Рецепты не найдены. Проверьте папку data/recipes и корректность .tres."
		no_recipes.add_theme_font_size_override("font_size", 12)
		no_recipes.add_theme_color_override("font_color", Color(0.85, 0.55, 0.35))
		_recipe_list.add_child(no_recipes)
		return

	for recipe: RecipeData in _recipes:
		var button := Button.new()
		button.text = _format_recipe_button_text(recipe)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 72
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_recipe_pressed.bind(recipe))
		_recipe_list.add_child(button)

func _sync_recipe_list_width() -> void:
	if not _recipe_scroll or not _recipe_list:
		return
	# ScrollContainer не растягивает контент по ширине автоматически,
	# поэтому фиксируем минимальную ширину списка вручную.
	var content_width: float = maxf(_recipe_scroll.size.x - 12.0, 0.0)
	_recipe_list.custom_minimum_size.x = content_width

func _on_recipe_pressed(recipe: RecipeData) -> void:
	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		var error_message: String = "Ошибка рецепта: предмет не найден в реестре"
		_craft_feedback.text = error_message
		_craft_feedback.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
		craft_failed.emit(error_message)
		return

	_recipe_description.text = "%s\n\nНужно: %s x%d\nРезультат: %s x%d" % [
		recipe.description,
		input_item.display_name,
		recipe.input_amount,
		output_item.display_name,
		recipe.output_amount
	]

	if not _crafting_system or not _inventory:
		var unavailable_message: String = "Система крафта недоступна"
		_craft_feedback.text = unavailable_message
		_craft_feedback.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
		craft_failed.emit(unavailable_message)
		return

	if not _command_executor:
		_command_executor = _find_command_executor()

	var result: Dictionary
	if _command_executor:
		var command := CraftRecipeCommand.new().setup(_crafting_system, _inventory, recipe)
		result = _command_executor.execute(command)
	else:
		result = _crafting_system.execute_recipe(recipe, _inventory)

	if result.get("success", false):
		var ok_message: String = str(result.get("message", "Скрафчено"))
		_craft_feedback.text = ok_message
		_craft_feedback.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
		craft_succeeded.emit(ok_message)
	else:
		var failed_message: String = "Крафт не выполнен: %s" % str(result.get("message", _get_unavailable_reason(recipe)))
		_craft_feedback.text = failed_message
		_craft_feedback.add_theme_color_override("font_color", Color(0.95, 0.55, 0.35))
		craft_failed.emit(failed_message)

	_refresh_recipe_list()

func _format_recipe_button_text(recipe: RecipeData) -> String:
	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		return "%s\n(некорректный рецепт)" % recipe.display_name

	var reason: String = _get_unavailable_reason(recipe)
	var marker: String = "✓" if reason.is_empty() else "✗"
	var status_line: String = "Доступно" if reason.is_empty() else "Недоступно: %s" % reason
	return "%s %s\n%s x%d → %s x%d\n%s" % [
		marker,
		recipe.display_name,
		input_item.display_name,
		recipe.input_amount,
		output_item.display_name,
		recipe.output_amount,
		status_line
	]

func _get_unavailable_reason(recipe: RecipeData) -> String:
	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		return "рецепт повреждён (предметы не найдены)"
	if not _crafting_system:
		return "система крафта не инициализирована"
	if not _inventory:
		return "инвентарь игрока не найден"
	if _crafting_system.can_craft(recipe, _inventory):
		if _can_fit_item(output_item, recipe.output_amount):
			return ""
		return "недостаточно места в инвентаре"
	var required_amount: int = maxi(recipe.input_amount, 0)
	var available_amount: int = _count_item_amount(input_item)
	return "нужно %d %s, есть %d" % [required_amount, input_item.display_name, available_amount]

func _count_item_amount(item_data: ItemData) -> int:
	if not _inventory or not item_data:
		return 0
	var total: int = 0
	for slot: InventorySlot in _inventory.slots:
		if not slot.is_empty() and slot.item and slot.item.id == item_data.id:
			total += slot.amount
	return total

func _can_fit_item(item_data: ItemData, amount: int) -> bool:
	if not _inventory or not item_data:
		return false
	var remaining: int = maxi(amount, 0)
	for slot: InventorySlot in _inventory.slots:
		if slot.is_empty():
			continue
		if slot.item and slot.item.id == item_data.id:
			var free_in_stack: int = maxi(slot.item.max_stack - slot.amount, 0)
			remaining -= free_in_stack
			if remaining <= 0:
				return true
	for slot: InventorySlot in _inventory.slots:
		if slot.is_empty():
			remaining -= item_data.max_stack
			if remaining <= 0:
				return true
	return false

func _find_command_executor() -> CommandExecutor:
	var executors: Array[Node] = get_tree().get_nodes_in_group("command_executor")
	if executors.is_empty():
		return null
	return executors[0] as CommandExecutor
