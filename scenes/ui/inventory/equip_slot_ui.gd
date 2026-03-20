class_name EquipSlotUI
extends PanelContainer

## Слот экипировки. Показывает тип слота + экипированный предмет.
## Принимает drag из инвентаря, отдаёт обратно по клику.

signal equip_clicked(slot_type: int)
signal equip_hovered(slot_type: int)
signal equip_unhovered()

const SLOT_SIZE: float = 44.0

var slot_type: int = -1
var _icon: TextureRect = null
var _type_label: Label = null
var _item: ItemData = null

func _init() -> void:
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	mouse_filter = MOUSE_FILTER_STOP

## Настроить слот с типом.
func setup_slot(p_slot_type: int) -> void:
	slot_type = p_slot_type
	_build_ui()

func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.14)
	style.border_color = Color(0.28, 0.30, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", style)

	_type_label = Label.new()
	_type_label.text = EquipmentSlotType.SLOT_ICONS.get(slot_type, "?")
	_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_type_label.set_anchors_preset(PRESET_FULL_RECT)
	_type_label.add_theme_font_size_override("font_size", 16)
	_type_label.add_theme_color_override("font_color", Color(0.3, 0.32, 0.38))
	_type_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_type_label)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(SLOT_SIZE - 4, SLOT_SIZE - 4)
	_icon.mouse_filter = MOUSE_FILTER_IGNORE
	_icon.visible = false
	add_child(_icon)

	mouse_entered.connect(func() -> void: equip_hovered.emit(slot_type))
	mouse_exited.connect(func() -> void: equip_unhovered.emit())
	gui_input.connect(_on_gui_input)

## Обновить содержимое слота.
func set_equipped_item(item: ItemData) -> void:
	_item = item
	if _item and _item.icon:
		_icon.texture = _item.icon
		_icon.visible = true
		_type_label.visible = false
	else:
		_icon.visible = false
		_type_label.visible = true

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		equip_clicked.emit(slot_type)

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("item"):
		return false
	var item: ItemData = data["item"]
	return item.equipment_slot == slot_type

func _drop_data(_position: Vector2, _data: Variant) -> void:
	equip_clicked.emit(slot_type)

## Получить название слота для тултипа.
func get_slot_name() -> String:
	var key: String = EquipmentSlotType.SLOT_NAME_KEYS.get(slot_type, "")
	return Localization.t(key) if not key.is_empty() else "?"
