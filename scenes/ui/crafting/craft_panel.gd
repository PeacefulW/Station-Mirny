class_name CraftPanel
extends Control

## Крафт-панель с прогресс-баром и подсказками зависимостей.
## Поддерживает ручной крафт (station_type="") и станционный (позже).

var _station_type: StringName = &""
var _inventory: InventoryComponent = null
var _selected_recipe: RecipeData = null
var _is_crafting: bool = false
var _craft_timer: float = 0.0
var _craft_total: float = 0.0

var _recipe_list_container: VBoxContainer = null
var _detail_name: Label = null
var _detail_desc: Label = null
var _ingredients_container: VBoxContainer = null
var _output_container: VBoxContainer = null
var _craft_button: Button = null
var _progress_bar: ProgressBar = null
var _hints_container: VBoxContainer = null
var _feedback_label: Label = null

func _ready() -> void:
	visible = false
	_build_ui()
	EventBus.language_changed.connect(func(_l: String) -> void: _refresh_recipe_list())

## Открыть панель для станции (или ручной крафт).
func open(station_type: StringName = &"", inventory: InventoryComponent = null) -> void:
	_station_type = station_type
	if inventory:
		_inventory = inventory
	visible = true
	_refresh_recipe_list()
	_clear_details()

## Закрыть панель.
func close() -> void:
	visible = false
	_cancel_craft()

func setup_inventory(inventory: InventoryComponent) -> void:
	_inventory = inventory

# --- Построение UI ---

func _build_ui() -> void:
	custom_minimum_size = Vector2(460, 300)
	size_flags_horizontal = SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_vertical = SIZE_EXPAND_FILL

	# Левая часть — список рецептов
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 200
	left.add_theme_constant_override("separation", 4)

	var recipes_title := Label.new()
	recipes_title.text = Localization.t("UI_CRAFT_RECIPES")
	recipes_title.add_theme_font_size_override("font_size", 13)
	recipes_title.add_theme_color_override("font_color", Color(0.7, 0.68, 0.58))
	left.add_child(recipes_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipe_list_container = VBoxContainer.new()
	_recipe_list_container.add_theme_constant_override("separation", 3)
	_recipe_list_container.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_recipe_list_container)
	left.add_child(scroll)
	hbox.add_child(left)

	# Разделитель
	var sep := VSeparator.new()
	hbox.add_child(sep)

	# Правая часть — детали
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 14)
	_detail_name.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	right.add_child(_detail_name)

	_detail_desc = Label.new()
	_detail_desc.add_theme_font_size_override("font_size", 11)
	_detail_desc.add_theme_color_override("font_color", Color(0.55, 0.53, 0.48))
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_detail_desc)

	right.add_child(HSeparator.new())

	var ing_label := Label.new()
	ing_label.text = Localization.t("UI_CRAFT_INGREDIENTS")
	ing_label.add_theme_font_size_override("font_size", 12)
	ing_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	right.add_child(ing_label)

	_ingredients_container = VBoxContainer.new()
	_ingredients_container.add_theme_constant_override("separation", 2)
	right.add_child(_ingredients_container)

	var out_label := Label.new()
	out_label.text = Localization.t("UI_CRAFT_RESULT")
	out_label.add_theme_font_size_override("font_size", 12)
	out_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	right.add_child(out_label)

	_output_container = VBoxContainer.new()
	right.add_child(_output_container)

	right.add_child(HSeparator.new())

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 14)
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0
	_progress_bar.show_percentage = false
	_progress_bar.visible = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.7, 0.4)
	fill.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.12)
	bg.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("background", bg)
	right.add_child(_progress_bar)

	_craft_button = Button.new()
	_craft_button.text = Localization.t("UI_CRAFT_BUTTON")
	_craft_button.custom_minimum_size = Vector2(0, 32)
	_craft_button.disabled = true
	_craft_button.pressed.connect(_on_craft_pressed)
	right.add_child(_craft_button)

	_feedback_label = Label.new()
	_feedback_label.add_theme_font_size_override("font_size", 11)
	_feedback_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5))
	right.add_child(_feedback_label)

	_hints_container = VBoxContainer.new()
	_hints_container.add_theme_constant_override("separation", 2)
	right.add_child(_hints_container)

	hbox.add_child(right)
	add_child(hbox)

# --- Рецепты ---

func _refresh_recipe_list() -> void:
	if not _recipe_list_container:
		return
	for child: Node in _recipe_list_container.get_children():
		child.queue_free()

	var recipes: Array[RecipeData] = _get_filtered_recipes()
	if recipes.is_empty():
		var empty := Label.new()
		empty.text = Localization.t("UI_CRAFT_NO_RECIPES")
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
		_recipe_list_container.add_child(empty)
		return

	for recipe: RecipeData in recipes:
		var item := RecipeListItem.new()
		item.setup(recipe, _can_craft(recipe))
		item.recipe_selected.connect(_on_recipe_selected)
		_recipe_list_container.add_child(item)

func _get_filtered_recipes() -> Array[RecipeData]:
	var all: Array[RecipeData] = ItemRegistry.get_all_recipes()
	var result: Array[RecipeData] = []
	for r: RecipeData in all:
		if r.station_type == _station_type:
			result.append(r)
	return result

func _can_craft(recipe: RecipeData) -> bool:
	if not _inventory:
		return false
	for input: Dictionary in recipe.get_inputs():
		var item_id: String = str(input.get("item_id", ""))
		var amount: int = int(input.get("amount", 0))
		if _inventory.get_item_count(item_id) < amount:
			return false
	return true

# --- Детали рецепта ---

func _on_recipe_selected(recipe: RecipeData) -> void:
	_selected_recipe = recipe
	_cancel_craft()
	_show_recipe_details(recipe)

func _show_recipe_details(recipe: RecipeData) -> void:
	_detail_name.text = recipe.get_display_name()
	_detail_desc.text = recipe.get_description()

	_clear_container(_ingredients_container)
	for input: Dictionary in recipe.get_inputs():
		_ingredients_container.add_child(_create_ingredient_row(input))

	_clear_container(_output_container)
	for output: Dictionary in recipe.get_outputs():
		_output_container.add_child(_create_output_row(output))

	_craft_button.disabled = not _can_craft(recipe)
	_craft_button.text = Localization.t("UI_CRAFT_BUTTON")
	_feedback_label.text = ""
	_show_dependency_hints(recipe)

func _clear_details() -> void:
	_detail_name.text = Localization.t("UI_CRAFT_SELECT_RECIPE")
	_detail_desc.text = ""
	_clear_container(_ingredients_container)
	_clear_container(_output_container)
	_clear_container(_hints_container)
	_craft_button.disabled = true
	_feedback_label.text = ""

func _create_ingredient_row(input: Dictionary) -> HBoxContainer:
	var item_id: String = str(input.get("item_id", ""))
	var required: int = int(input.get("amount", 0))
	var have: int = _inventory.get_item_count(item_id) if _inventory else 0
	var item: ItemData = ItemRegistry.get_item(item_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = item.get_display_name() if item else item_id
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "%d/%d" % [have, required]
	count_label.add_theme_font_size_override("font_size", 12)
	if have >= required:
		count_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	else:
		count_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	row.add_child(count_label)
	return row

func _create_output_row(output: Dictionary) -> HBoxContainer:
	var item_id: String = str(output.get("item_id", ""))
	var amount: int = int(output.get("amount", 0))
	var item: ItemData = ItemRegistry.get_item(item_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "%s x%d" % [item.get_display_name() if item else item_id, amount]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.5))
	row.add_child(label)
	return row

# --- Прогресс-бар крафта ---

func _process(delta: float) -> void:
	if not _is_crafting:
		return
	_craft_timer += delta
	var progress: float = _craft_timer / _craft_total if _craft_total > 0 else 1.0
	_progress_bar.value = clampf(progress * 100.0, 0.0, 100.0)
	if _craft_timer >= _craft_total:
		_complete_craft()

func _on_craft_pressed() -> void:
	if not _selected_recipe or _is_crafting or not _can_craft(_selected_recipe):
		return
	_is_crafting = true
	_craft_timer = 0.0
	_craft_total = _selected_recipe.craft_time
	_craft_button.disabled = true
	_craft_button.text = Localization.t("UI_CRAFT_IN_PROGRESS")
	_progress_bar.visible = true
	_progress_bar.value = 0
	_feedback_label.text = ""

func _complete_craft() -> void:
	_is_crafting = false
	_progress_bar.visible = false
	_progress_bar.value = 0

	if _selected_recipe and _inventory:
		var crafting_system: CraftingSystem = _find_crafting_system()
		if crafting_system:
			var result: Dictionary = crafting_system.execute_recipe(_selected_recipe, _inventory)
			if result.get("success", false):
				_feedback_label.text = Localization.t("UI_CRAFT_SUCCESS")
				_feedback_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
			else:
				var msg_key: String = str(result.get("message_key", ""))
				_feedback_label.text = Localization.t(msg_key) if not msg_key.is_empty() else ""
				_feedback_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))

	_craft_button.text = Localization.t("UI_CRAFT_BUTTON")
	_craft_button.disabled = not _can_craft(_selected_recipe) if _selected_recipe else true
	_refresh_recipe_list()
	if _selected_recipe:
		_show_recipe_details(_selected_recipe)

func _cancel_craft() -> void:
	_is_crafting = false
	_craft_timer = 0.0
	if _progress_bar:
		_progress_bar.visible = false
		_progress_bar.value = 0

# --- Подсказки зависимостей ---

func _show_dependency_hints(recipe: RecipeData) -> void:
	_clear_container(_hints_container)
	if _can_craft(recipe):
		return

	for input: Dictionary in recipe.get_inputs():
		var item_id: String = str(input.get("item_id", ""))
		var required: int = int(input.get("amount", 0))
		var have: int = _inventory.get_item_count(item_id) if _inventory else 0
		if have >= required:
			continue
		var missing: int = required - have
		var item: ItemData = ItemRegistry.get_item(item_id)
		var item_name: String = item.get_display_name() if item else item_id

		var sub_recipe: RecipeData = _find_recipe_for_item(item_id)
		var hint := Label.new()
		hint.add_theme_font_size_override("font_size", 10)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if sub_recipe:
			var station_name: String = _get_station_name(sub_recipe.station_type)
			hint.text = Localization.t("UI_CRAFT_HINT_DEPENDENCY", {
				"item": item_name, "amount": missing, "station": station_name,
			})
			hint.add_theme_color_override("font_color", Color(0.7, 0.6, 0.3))
		else:
			hint.text = Localization.t("UI_CRAFT_HINT_GATHER", {
				"item": item_name, "amount": missing,
			})
			hint.add_theme_color_override("font_color", Color(0.6, 0.5, 0.4))
		_hints_container.add_child(hint)

func _find_recipe_for_item(item_id: String) -> RecipeData:
	var all: Array[RecipeData] = ItemRegistry.get_all_recipes()
	for r: RecipeData in all:
		for output: Dictionary in r.get_outputs():
			if str(output.get("item_id", "")) == item_id:
				return r
	return null

func _get_station_name(station_type: StringName) -> String:
	if station_type == &"":
		return Localization.t("UI_CRAFT_STATION_HAND")
	return str(station_type)

# --- Утилиты ---

func _clear_container(container: VBoxContainer) -> void:
	if not container:
		return
	for child: Node in container.get_children():
		child.queue_free()

func _find_crafting_system() -> CraftingSystem:
	var systems: Array[Node] = get_tree().get_nodes_in_group("crafting_system")
	if systems.is_empty():
		return null
	return systems[0] as CraftingSystem
