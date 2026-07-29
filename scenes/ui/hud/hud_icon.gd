class_name HudIcon
extends Control
## Пиктограмма HUD как Control: встаёт в контейнер рядом с текстом и
## перекрашивается по состоянию показателя.

const SHADOW_OFFSET: Vector2 = Vector2(1.0, 1.0)

var _id: HudIcons.Id = HudIcons.Id.OXYGEN
var _color: Color = HudPalette.TEXT_SECONDARY
var _stroke: float = 1.5
var _wind_angle_rad: float = 0.0
var _is_wind_arrow: bool = false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func configure(id: HudIcons.Id, box: float, color: Color, stroke: float = 1.5) -> void:
	_id = id
	_color = color
	_stroke = stroke
	custom_minimum_size = Vector2(box, box)
	queue_redraw()


func set_glyph(id: HudIcons.Id) -> void:
	if _id == id and not _is_wind_arrow:
		return
	_id = id
	_is_wind_arrow = false
	queue_redraw()


func set_glyph_color(color: Color) -> void:
	if _color.is_equal_approx(color):
		return
	_color = color
	queue_redraw()


## Стрелка ветра вместо статичной пиктограммы: направление живое.
func use_wind_arrow(angle_rad: float) -> void:
	if _is_wind_arrow and is_equal_approx(_wind_angle_rad, angle_rad):
		return
	_is_wind_arrow = true
	_wind_angle_rad = angle_rad
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var shadow: Color = Color(0.0, 0.0, 0.0, _color.a * 0.7)
	_draw_pass(Rect2(rect.position + SHADOW_OFFSET, rect.size), shadow)
	_draw_pass(rect, _color)


func _draw_pass(rect: Rect2, color: Color) -> void:
	if _is_wind_arrow:
		HudIcons.draw_wind(self, rect, color, _wind_angle_rad, _stroke)
		return
	HudIcons.draw_glyph(self, _id, rect, color, _stroke)
