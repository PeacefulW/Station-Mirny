class_name ItemTooltip
extends PanelContainer

## Тултип предмета. Показывает название, описание, характеристики.

var _name_label: Label = null
var _desc_label: Label = null
var _stats_label: Label = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	custom_minimum_size = Vector2(180, 0)
	z_index = 200

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.95)
	style.border_color = Color(0.3, 0.32, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	vbox.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 11)
	_desc_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size.x = 170
	vbox.add_child(_desc_label)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	vbox.add_child(_stats_label)

	add_child(vbox)

## Показать тултип для предмета.
func show_item(item: ItemData, screen_pos: Vector2) -> void:
	if not item:
		hide_tooltip()
		return
	_name_label.text = item.get_display_name()
	_desc_label.text = item.get_description()

	var stats: String = ""
	if item.weight > 0:
		stats += Localization.t("UI_TOOLTIP_WEIGHT", {"weight": "%.1f" % item.weight})
	if item.max_stack > 1:
		stats += "\n" + Localization.t("UI_TOOLTIP_STACK", {"max": item.max_stack})
	if item.equipment_slot >= 0:
		var slot_key: String = EquipmentSlotType.SLOT_NAME_KEYS.get(item.equipment_slot, "")
		if not slot_key.is_empty():
			stats += "\n" + Localization.t("UI_TOOLTIP_EQUIP_SLOT", {"slot": Localization.t(slot_key)})
	_stats_label.text = stats
	_stats_label.visible = not stats.is_empty()

	global_position = _clamp_to_screen(screen_pos + Vector2(16, 8))
	visible = true

## Скрыть тултип.
func hide_tooltip() -> void:
	visible = false

## Показать тултип для слота экипировки (пустого).
func show_equip_slot(slot_name: String, screen_pos: Vector2) -> void:
	_name_label.text = slot_name
	_desc_label.text = Localization.t("UI_TOOLTIP_EMPTY_SLOT")
	_stats_label.text = ""
	_stats_label.visible = false
	global_position = _clamp_to_screen(screen_pos + Vector2(16, 8))
	visible = true

func _clamp_to_screen(pos: Vector2) -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	var s: Vector2 = size
	pos.x = clampf(pos.x, 0, vp.x - s.x - 8)
	pos.y = clampf(pos.y, 0, vp.y - s.y - 8)
	return pos
