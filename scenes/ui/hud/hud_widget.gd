class_name HudWidget
extends Control

## Базовый класс для всех виджетов HUD.
## Наследники переопределяют _setup() и подписываются на EventBus.
## Оттенки и шрифты берутся только из HudPalette: иначе набор показателей со
## временем расходится по стилю и перестаёт читаться как один прибор.

enum LabelStyle { DISPLAY, VALUE, CAPS }


## Показать виджет.
func show_widget() -> void:
	visible = true


## Скрыть виджет.
func hide_widget() -> void:
	visible = false


## Переопределить в наследнике: построить UI.
func _setup() -> void:
	pass


func _make_hud_label(
		style: LabelStyle,
		font_size: int,
		color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = alignment
	_style_label(label, style, font_size, color)
	return label


func _style_label(label: Label, style: LabelStyle, font_size: int, color: Color) -> void:
	label.add_theme_font_override("font", _style_font(style))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", HudPalette.TEXT_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = MOUSE_FILTER_IGNORE


func _style_font(style: LabelStyle) -> FontVariation:
	match style:
		LabelStyle.DISPLAY:
			return HudPalette.display_font()
		LabelStyle.VALUE:
			return HudPalette.value_font()
		_:
			return HudPalette.label_font()


func _get_minimum_size() -> Vector2:
	var minimum: Vector2 = Vector2.ZERO
	for child: Node in get_children():
		var control: Control = child as Control
		if control == null:
			continue
		var child_minimum: Vector2 = control.get_combined_minimum_size()
		minimum.x = maxf(minimum.x, child_minimum.x)
		minimum.y = maxf(minimum.y, child_minimum.y)
	return minimum


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_setup()
	update_minimum_size()
