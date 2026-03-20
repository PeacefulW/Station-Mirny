class_name BuildingCard
extends PanelContainer

## Карточка здания в меню строительства.
## Иконка (или цветная заглушка) + короткое название.

signal card_clicked(building: BuildingData)
signal card_hovered(building: BuildingData)
signal card_unhovered()

var _building: BuildingData = null
var _is_selected: bool = false

## Настроить карточку с данными здания.
func setup(building: BuildingData) -> void:
	_building = building
	custom_minimum_size = Vector2(64, 76)
	mouse_filter = MOUSE_FILTER_STOP
	_apply_style(false)
	_build_visual()

	mouse_entered.connect(func() -> void: card_hovered.emit(_building))
	mouse_exited.connect(func() -> void: card_unhovered.emit())
	gui_input.connect(_on_gui_input)

## Выделить / снять выделение.
func set_selected(selected: bool) -> void:
	_is_selected = selected
	_apply_style(selected)

func _build_visual() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = MOUSE_FILTER_IGNORE

	# Иконка или цветная заглушка
	if _building.icon:
		var icon := TextureRect.new()
		icon.texture = _building.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(40, 40)
		icon.mouse_filter = MOUSE_FILTER_IGNORE
		vbox.add_child(icon)
	else:
		var color_box := ColorRect.new()
		color_box.custom_minimum_size = Vector2(40, 40)
		color_box.color = _building.placeholder_color
		color_box.mouse_filter = MOUSE_FILTER_IGNORE
		vbox.add_child(color_box)

	# Название
	var name_label := Label.new()
	name_label.text = _building.get_display_name()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
	name_label.clip_text = true
	name_label.custom_minimum_size.x = 58
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	add_child(vbox)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			card_clicked.emit(_building)

func _apply_style(selected: bool) -> void:
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = Color(0.18, 0.20, 0.16)
		style.border_color = Color(0.7, 0.6, 0.3)
	else:
		style.bg_color = Color(0.10, 0.11, 0.09)
		style.border_color = Color(0.22, 0.21, 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
