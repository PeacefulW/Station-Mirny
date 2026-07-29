class_name HudActionSlot
extends VBoxContainer
## Ячейка панели действий: пиктограмма, клавиша и подпись.
## Клавиша тоже приходит ключом локализации: ЛКМ/ПРОБЕЛ переводятся, а будущая
## переназначаемая раскладка не должна требовать правки виджета.

const ICON_BOX: float = 18.0

var _icon: HudIcon = null
var _key_label: Label = null
var _caption_label: Label = null
var _key_key: String = ""
var _caption_key: String = ""


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 5)

	var head: HBoxContainer = HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 7)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(head)

	_icon = HudIcon.new()
	_icon.configure(HudIcons.Id.INTERACT, ICON_BOX, HudPalette.TEXT_PRIMARY, 1.5)
	head.add_child(_icon)

	_key_label = Label.new()
	_key_label.mouse_filter = MOUSE_FILTER_IGNORE
	_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key_label.add_theme_font_override("font", HudPalette.label_font())
	_key_label.add_theme_font_size_override("font_size", 9)
	_key_label.add_theme_color_override("font_color", HudPalette.TEXT_PRIMARY)
	_key_label.add_theme_stylebox_override("normal", _make_key_cap_style())
	head.add_child(_key_label)

	_caption_label = Label.new()
	_caption_label.mouse_filter = MOUSE_FILTER_IGNORE
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.add_theme_font_override("font", HudPalette.label_font())
	_caption_label.add_theme_font_size_override("font_size", 9)
	_caption_label.add_theme_color_override("font_color", HudPalette.TEXT_SECONDARY)
	_caption_label.add_theme_color_override("font_shadow_color", HudPalette.TEXT_SHADOW)
	_caption_label.add_theme_constant_override("shadow_offset_x", 1)
	_caption_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_caption_label)


func configure(id: HudIcons.Id, key_key: String, caption_key: String) -> void:
	_key_key = key_key
	_caption_key = caption_key
	_icon.set_glyph(id)
	refresh_text()


func refresh_text() -> void:
	_key_label.text = Localization.t(_key_key)
	_caption_label.text = Localization.t(_caption_key)


func _make_key_cap_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.86, 0.79, 0.66, 0.09)
	style.border_color = Color(0.82, 0.67, 0.47, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 3.0
	return style
