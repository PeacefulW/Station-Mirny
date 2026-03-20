class_name RecipeListItem
extends PanelContainer

## Строка рецепта в списке. Иконка выхода + название. Зелёный/серый.

signal recipe_selected(recipe: RecipeData)

var _recipe: RecipeData = null

## Настроить строку рецепта.
func setup(recipe: RecipeData, can_craft: bool) -> void:
	_recipe = recipe
	custom_minimum_size = Vector2(180, 34)
	mouse_filter = MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.09)
	style.border_color = Color(0.20, 0.19, 0.17)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = MOUSE_FILTER_IGNORE

	# Иконка выхода
	var recipe_outputs: Array[Dictionary] = recipe.get_outputs()
	if not recipe_outputs.is_empty():
		var output_id: String = str(recipe_outputs[0].get("item_id", ""))
		var item: ItemData = ItemRegistry.get_item(output_id)
		if item and item.icon:
			var tex := TextureRect.new()
			tex.texture = item.icon
			tex.custom_minimum_size = Vector2(24, 24)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.mouse_filter = MOUSE_FILTER_IGNORE
			row.add_child(tex)

	# Название
	var label := Label.new()
	label.text = recipe.get_display_name()
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	if can_craft:
		label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.75))
	else:
		label.add_theme_color_override("font_color", Color(0.45, 0.44, 0.42))
	row.add_child(label)

	add_child(row)
	gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			recipe_selected.emit(_recipe)
