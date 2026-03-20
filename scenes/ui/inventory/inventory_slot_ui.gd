class_name InventorySlotUI
extends PanelContainer

## Одна ячейка инвентаря. Показывает иконку + количество.
## Поддерживает drag-drop и hover.

signal slot_clicked(slot_index: int, button: int)
signal slot_dropped(from_index: int, to_index: int)
signal slot_hovered(slot_index: int)
signal slot_unhovered()

const SLOT_SIZE: float = 44.0

var slot_index: int = -1
var _icon: TextureRect = null
var _count_label: Label = null
var _color_bg: ColorRect = null
var _item: ItemData = null
var _amount: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	mouse_filter = MOUSE_FILTER_STOP
	_apply_style(Color(0.13, 0.14, 0.12), Color(0.25, 0.24, 0.20))

	_color_bg = ColorRect.new()
	_color_bg.set_anchors_preset(PRESET_CENTER)
	_color_bg.grow_horizontal = GROW_DIRECTION_BOTH
	_color_bg.grow_vertical = GROW_DIRECTION_BOTH
	_color_bg.custom_minimum_size = Vector2(28, 28)
	_color_bg.visible = false
	_color_bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_color_bg)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(SLOT_SIZE - 4, SLOT_SIZE - 4)
	_icon.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_icon)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.set_anchors_preset(PRESET_FULL_RECT)
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
	_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	_count_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_count_label)

	mouse_entered.connect(func() -> void: slot_hovered.emit(slot_index))
	mouse_exited.connect(func() -> void: slot_unhovered.emit())
	gui_input.connect(_on_gui_input)

## Обновить содержимое ячейки.
func set_slot_data(item: ItemData, amount: int) -> void:
	_item = item
	_amount = amount
	if not _item or amount <= 0:
		_icon.texture = null
		_color_bg.visible = false
		_count_label.text = ""
		_apply_style(Color(0.13, 0.14, 0.12), Color(0.25, 0.24, 0.20))
	else:
		if _item.icon:
			_icon.texture = _item.icon
			_color_bg.visible = false
		else:
			_icon.texture = null
			_color_bg.visible = true
			_color_bg.color = Color(0.5, 0.5, 0.5)
		_count_label.text = str(amount) if amount > 1 else ""
		_apply_style(Color(0.16, 0.17, 0.14), Color(0.32, 0.30, 0.24))

func get_item() -> ItemData:
	return _item

func get_amount() -> int:
	return _amount

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		slot_clicked.emit(slot_index, mb.button_index)

func _get_drag_data(_position: Vector2) -> Variant:
	if not _item:
		return null
	var preview := TextureRect.new()
	if _item.icon:
		preview.texture = _item.icon
	preview.custom_minimum_size = Vector2(32, 32)
	preview.modulate.a = 0.7
	set_drag_preview(preview)
	return {"source": "inventory", "slot_index": slot_index, "item": _item, "amount": _amount}

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	return data.has("source") and data.get("source") == "inventory"

func _drop_data(_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	var from_index: int = int(data.get("slot_index", -1))
	if from_index >= 0 and from_index != slot_index:
		slot_dropped.emit(from_index, slot_index)

func _apply_style(bg: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", style)
