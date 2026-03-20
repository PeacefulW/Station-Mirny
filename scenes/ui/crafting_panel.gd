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
var _recipe_title: Label = null

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(360, 320)
	size_flags_horizontal = SIZE_EXPAND_FILL
	_build_ui()
	_load_recipes()
	_refresh_recipe_list()
	EventBus.language_changed.connect(_on_language_changed)

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
	_recipe_title = Label.new()
	_recipe_title.add_theme_font_size_override("font_size", 14)
	add_child(_recipe_title)

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
	_recipe_description.add_theme_font_size_override("font_size", 12)
	_recipe_description.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	add_child(_recipe_description)

	_craft_feedback = Label.new()
	_craft_feedback.text = ""
	_craft_feedback.add_theme_font_size_override("font_size", 12)
	_craft_feedback.add_theme_color_override("font_color", Color(0.65, 0.72, 0.9))
	add_child(_craft_feedback)

	_apply_localization()
	_sync_recipe_list_width()

func _load_recipes() -> void:
	_recipes = ItemRegistry.get_all_recipes()
	_recipes.sort_custom(func(a: RecipeData, b: RecipeData) -> bool: return a.get_display_name() < b.get_display_name())

func _refresh_recipe_list() -> void:
	if not _recipe_list:
		return
	for child: Node in _recipe_list.get_children():
		child.queue_free()

	if _recipes.is_empty():
		var no_recipes := Label.new()
		no_recipes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		no_recipes.text = Localization.t("UI_CRAFT_NO_RECIPES")
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
	var content_width: float = maxf(_recipe_scroll.size.x - 12.0, 0.0)
	_recipe_list.custom_minimum_size.x = content_width

func _on_recipe_pressed(recipe: RecipeData) -> void:
	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		var error_message: String = Localization.t("UI_CRAFT_RECIPE_INVALID")
		_craft_feedback.text = error_message
		_craft_feedback.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
		craft_failed.emit(error_message)
		return

	_recipe_description.text = Localization.t("UI_CRAFT_RECIPE_DETAILS", {
		"description": recipe.get_description(),
		"input": input_item.get_display_name(),
		"input_amount": recipe.input_amount,
		"output": output_item.get_display_name(),
		"output_amount": recipe.output_amount,
	})

	if not _crafting_system or not _inventory:
		var unavailable_message: String = Localization.t("UI_CRAFT_SYSTEM_UNAVAILABLE")
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
		var ok_message: String = _format_result_message(result, "SYSTEM_CRAFT_SUCCESS")
		_craft_feedback.text = ok_message
		_craft_feedback.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
		craft_succeeded.emit(ok_message)
	else:
		var failure_reason: String = _format_result_message(result, "")
		if failure_reason.is_empty():
			failure_reason = _get_unavailable_reason(recipe)
		var failed_message: String = Localization.t("UI_CRAFT_FAILED", {"reason": failure_reason})
		_craft_feedback.text = failed_message
		_craft_feedback.add_theme_color_override("font_color", Color(0.95, 0.55, 0.35))
		craft_failed.emit(failed_message)

	_refresh_recipe_list()

func _format_recipe_button_text(recipe: RecipeData) -> String:
	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		return "%s\n(%s)" % [recipe.get_display_name(), Localization.t("UI_CRAFT_RECIPE_BROKEN")]

	var reason: String = _get_unavailable_reason(recipe)
	var marker: String = "✓" if reason.is_empty() else "✗"
	var status_line: String = Localization.t("UI_CRAFT_STATUS_AVAILABLE") if reason.is_empty() else Localization.t("UI_CRAFT_STATUS_UNAVAILABLE", {"reason": reason})
	return "%s %s\n%s x%d -> %s x%d\n%s" % [
		marker,
		recipe.get_display_name(),
		input_item.get_display_name(),
		recipe.input_amount,
		output_item.get_display_name(),
		recipe.output_amount,
		status_line
	]

func _get_unavailable_reason(recipe: RecipeData) -> String:
	var input_item: ItemData = ItemRegistry.get_item(recipe.input_item_id)
	var output_item: ItemData = ItemRegistry.get_item(recipe.output_item_id)
	if not input_item or not output_item:
		return Localization.t("UI_CRAFT_REASON_RECIPE_BROKEN")
	if not _crafting_system:
		return Localization.t("UI_CRAFT_REASON_SYSTEM_NOT_READY")
	if not _inventory:
		return Localization.t("UI_CRAFT_REASON_INVENTORY_NOT_FOUND")
	if _crafting_system.can_craft(recipe, _inventory):
		if _can_fit_item(output_item, recipe.output_amount):
			return ""
		return Localization.t("UI_CRAFT_REASON_NOT_ENOUGH_SPACE")
	var required_amount: int = maxi(recipe.input_amount, 0)
	var available_amount: int = _count_item_amount(input_item)
	return Localization.t("UI_CRAFT_REASON_MISSING_ITEMS", {
		"required": required_amount,
		"item": input_item.get_display_name(),
		"available": available_amount,
	})

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

func _format_result_message(result: Dictionary, fallback_key: String) -> String:
	var message_key: String = str(result.get("message_key", fallback_key))
	var message_args: Dictionary = result.get("message_args", {})
	if not message_key.is_empty():
		return Localization.t(message_key, message_args)
	return str(result.get("message", ""))

func _apply_localization() -> void:
	if _recipe_title:
		_recipe_title.text = Localization.t("UI_CRAFT_TITLE")
	if _recipe_description:
		_recipe_description.text = Localization.t("UI_CRAFT_SELECT_RECIPE")

func _on_language_changed(_locale_code: String) -> void:
	_apply_localization()
	_refresh_recipe_list()