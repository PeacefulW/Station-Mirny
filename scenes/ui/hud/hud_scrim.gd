class_name HudScrim
extends PanelContainer
## Стеклянная плита кластера HUD.
## Полупрозрачная, со скруглением, тонкой кромкой и мягкой тенью: мир должен
## просвечивать сквозь интерфейс, а не закрываться чёрным пятном.

const CORNER_RADIUS: int = 7
const SHEEN_BANDS: int = 20
const SHEEN_HEIGHT_RATIO: float = 0.46


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


## Внутренние отступы кластера. Сама плита подгоняется под содержимое.
func configure(padding: Vector4) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = HudPalette.GLASS_INK
	style.set_corner_radius_all(CORNER_RADIUS)
	style.set_border_width_all(1)
	style.border_color = HudPalette.GLASS_EDGE
	# Тень отделяет стекло от мира и заменяет плотную заливку фона.
	style.shadow_color = HudPalette.GLASS_SHADOW
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 3.0)
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	add_theme_stylebox_override("panel", style)
	queue_redraw()


## Блик по верхней части плиты и опорная линия снизу: без них полупрозрачный
## прямоугольник читается как дырка в экране, а не как стекло.
func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var inset: float = float(CORNER_RADIUS)
	var band_height: float = maxf(size.y * SHEEN_HEIGHT_RATIO / float(SHEEN_BANDS), 1.0)
	for index: int in range(SHEEN_BANDS):
		var t: float = float(index) / float(SHEEN_BANDS)
		var alpha: float = HudPalette.GLASS_SHEEN.a * (1.0 - smoothstep(0.0, 1.0, t))
		if alpha <= 0.002:
			continue
		draw_rect(
			Rect2(
				Vector2(inset, 1.0 + float(index) * band_height),
				Vector2(size.x - inset * 2.0, band_height),
			),
			Color(HudPalette.GLASS_SHEEN, alpha),
			true,
		)
	draw_line(
		Vector2(inset, size.y - 1.5),
		Vector2(size.x - inset, size.y - 1.5),
		HudPalette.GLASS_RAIL,
		1.0,
	)
