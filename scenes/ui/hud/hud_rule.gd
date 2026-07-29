class_name HudRule
extends Control
## Разделитель внутри кластера HUD: линия, гаснущая к дальнему от края экрана
## концу. Ровная рамка вернула бы ощущение окна приложения.

enum Fade { TO_RIGHT, TO_LEFT }

const _SEGMENTS: int = 28

var _fade: Fade = Fade.TO_RIGHT
var _color: Color = HudPalette.SEPARATOR


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 1.0)


func configure(fade: Fade, color: Color = HudPalette.SEPARATOR) -> void:
	_fade = fade
	_color = color
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0:
		return
	var step: float = size.x / float(_SEGMENTS)
	var y: float = size.y * 0.5
	for index: int in range(_SEGMENTS):
		var center: float = (float(index) + 0.5) / float(_SEGMENTS)
		var distance: float = center if _fade == Fade.TO_RIGHT else 1.0 - center
		var alpha: float = _color.a * (1.0 - smoothstep(0.30, 1.0, distance))
		if alpha <= 0.004:
			continue
		draw_line(
			Vector2(float(index) * step, y),
			Vector2(float(index + 1) * step, y),
			Color(_color, alpha),
			1.0,
		)
