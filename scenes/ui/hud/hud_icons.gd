class_name HudIcons
extends RefCounted
## Векторные пиктограммы HUD.
## Рисуются кодом, а не импортируются: набор работает на 14-22 px, где растровые
## иконки мылятся, и должен перекрашиваться по состоянию без второго комплекта
## текстур.

enum Id {
	OXYGEN,
	VITALS,
	WARNING,
	SUN,
	MOON,
	DAWN,
	DUSK,
	CLOUD,
	TEMPERATURE,
	HUMIDITY,
	WETNESS,
	COLD,
	SHELTER,
	MOVE,
	INTERACT,
	PACK,
	HAMMER,
	STRIKE,
	BOLT,
	EXIT,
	PLACE,
	REMOVE,
}


static func draw_glyph(
		canvas: CanvasItem,
		id: Id,
		rect: Rect2,
		color: Color,
		width: float = 1.5,
) -> void:
	match id:
		Id.OXYGEN:
			_draw_oxygen(canvas, rect, color, width)
		Id.VITALS:
			_draw_vitals(canvas, rect, color, width)
		Id.WARNING:
			_draw_warning(canvas, rect, color, width)
		Id.SUN:
			_draw_sun(canvas, rect, color, width)
		Id.MOON:
			_draw_moon(canvas, rect, color, width)
		Id.DAWN:
			_draw_horizon(canvas, rect, color, width, true)
		Id.DUSK:
			_draw_horizon(canvas, rect, color, width, false)
		Id.CLOUD:
			_draw_cloud(canvas, rect, color, width)
		Id.TEMPERATURE:
			_draw_temperature(canvas, rect, color, width)
		Id.HUMIDITY:
			_draw_humidity(canvas, rect, color, width)
		Id.WETNESS:
			_draw_wetness(canvas, rect, color, width)
		Id.COLD:
			_draw_cold(canvas, rect, color, width)
		Id.SHELTER:
			_draw_shelter(canvas, rect, color, width)
		Id.MOVE:
			_draw_move(canvas, rect, color)
		Id.INTERACT:
			_draw_interact(canvas, rect, color, width)
		Id.PACK:
			_draw_pack(canvas, rect, color, width)
		Id.HAMMER:
			_draw_hammer(canvas, rect, color, width)
		Id.STRIKE:
			_draw_strike(canvas, rect, color, width)
		Id.BOLT:
			_draw_bolt(canvas, rect, color)
		Id.EXIT:
			_draw_exit(canvas, rect, color, width)
		Id.PLACE:
			_draw_cell_mark(canvas, rect, color, width, true)
		Id.REMOVE:
			_draw_cell_mark(canvas, rect, color, width, false)


## Стрелка ветра. Направление приходит из WindRuntime, поэтому иконка живая, а не
## подобранная из таблицы символов.
static func draw_wind(
		canvas: CanvasItem,
		rect: Rect2,
		color: Color,
		angle_rad: float,
		width: float = 1.5,
) -> void:
	var center: Vector2 = rect.position + rect.size * 0.5
	var reach: Vector2 = Vector2(rect.size.x * 0.40, 0.0).rotated(angle_rad)
	var tip: Vector2 = center + reach
	var tail: Vector2 = center - reach
	canvas.draw_line(tail, tip, color, width, true)
	var left_wing: Vector2 = tip - reach.rotated(0.55) * 0.52
	var right_wing: Vector2 = tip - reach.rotated(-0.55) * 0.52
	canvas.draw_line(tip, left_wing, color, width, true)
	canvas.draw_line(tip, right_wing, color, width, true)
	# Штрихи поперёк потока читаются как скорость и отделяют ветер от компаса.
	var across: Vector2 = reach.orthogonal().normalized()
	var faded: Color = Color(color, color.a * 0.5)
	for offset: float in [-1.0, 1.0]:
		var base: Vector2 = center + across * rect.size.y * 0.26 * offset
		canvas.draw_line(base - reach * 0.85, base - reach * 0.15, faded, width * 0.8, true)


static func _point(rect: Rect2, x: float, y: float) -> Vector2:
	return rect.position + Vector2(rect.size.x * x, rect.size.y * y)


static func _polyline(
		canvas: CanvasItem,
		rect: Rect2,
		coords: PackedVector2Array,
		color: Color,
		width: float,
) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for coord: Vector2 in coords:
		points.append(_point(rect, coord.x, coord.y))
	canvas.draw_polyline(points, color, width, true)


static func _draw_oxygen(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var unit: float = minf(rect.size.x, rect.size.y)
	canvas.draw_arc(_point(rect, 0.38, 0.38), unit * 0.27, 0.0, TAU, 20, color, width, true)
	canvas.draw_arc(_point(rect, 0.66, 0.66), unit * 0.22, 0.0, TAU, 18, color, width, true)


static func _draw_vitals(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.04, 0.55),
				Vector2(0.26, 0.55),
				Vector2(0.37, 0.22),
				Vector2(0.50, 0.82),
				Vector2(0.62, 0.44),
				Vector2(0.72, 0.55),
				Vector2(0.96, 0.55),
			],
		),
		color,
		width,
	)


static func _draw_warning(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.50, 0.08),
				Vector2(0.96, 0.90),
				Vector2(0.04, 0.90),
				Vector2(0.50, 0.08),
			],
		),
		color,
		width,
	)
	canvas.draw_line(_point(rect, 0.5, 0.38), _point(rect, 0.5, 0.62), color, width, true)
	canvas.draw_circle(_point(rect, 0.5, 0.76), maxf(width * 0.7, 1.0), color)


static func _draw_sun(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var center: Vector2 = rect.position + rect.size * 0.5
	var unit: float = minf(rect.size.x, rect.size.y)
	canvas.draw_arc(center, unit * 0.24, 0.0, TAU, 22, color, width, true)
	for index: int in range(8):
		var direction: Vector2 = Vector2.RIGHT.rotated(TAU * float(index) / 8.0)
		canvas.draw_line(
			center + direction * unit * 0.34,
			center + direction * unit * 0.48,
			color,
			width,
			true,
		)


static func _draw_moon(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var unit: float = minf(rect.size.x, rect.size.y)
	var radius: float = unit * 0.34
	var outer: Vector2 = rect.position + rect.size * 0.5 - Vector2(unit * 0.08, 0.0)
	var inner: Vector2 = outer + Vector2(unit * 0.24, -unit * 0.04)
	# Углы пересечения двух окружностей одинакового радиуса: серп замыкается сам.
	var span: Vector2 = inner - outer
	var half: float = acos(clampf(span.length() * 0.5 / radius, -1.0, 1.0))
	var axis: float = span.angle()
	canvas.draw_arc(outer, radius, axis + half, axis + TAU - half, 24, color, width, true)
	canvas.draw_arc(inner, radius, axis + PI + half, axis + TAU + PI - half, 20, color, width, true)


static func _draw_horizon(
		canvas: CanvasItem,
		rect: Rect2,
		color: Color,
		width: float,
		is_rising: bool,
) -> void:
	var unit: float = minf(rect.size.x, rect.size.y)
	var base: Vector2 = _point(rect, 0.5, 0.70)
	canvas.draw_arc(base, unit * 0.25, PI, TAU, 18, color, width, true)
	canvas.draw_line(_point(rect, 0.06, 0.70), _point(rect, 0.94, 0.70), color, width, true)
	var tip_y: float = 0.14 if is_rising else 0.40
	var wing_y: float = 0.30 if is_rising else 0.24
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.34, wing_y),
				Vector2(0.50, tip_y),
				Vector2(0.66, wing_y),
			],
		),
		color,
		width,
	)


static func _draw_cloud(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var unit: float = minf(rect.size.x, rect.size.y)
	var base_y: float = 0.70
	canvas.draw_arc(_point(rect, 0.36, base_y), unit * 0.20, PI, TAU, 16, color, width, true)
	canvas.draw_arc(_point(rect, 0.60, base_y), unit * 0.28, PI, TAU, 18, color, width, true)
	canvas.draw_line(
		_point(rect, 0.16, base_y),
		_point(rect, 0.88, base_y),
		color,
		width,
		true,
	)


static func _draw_temperature(
		canvas: CanvasItem,
		rect: Rect2,
		color: Color,
		width: float,
) -> void:
	var unit: float = minf(rect.size.x, rect.size.y)
	var bulb_center: Vector2 = _point(rect, 0.38, 0.76)
	canvas.draw_line(
		_point(rect, 0.38, 0.14),
		_point(rect, 0.38, 0.68),
		color,
		width * 1.35,
		true,
	)
	canvas.draw_arc(bulb_center, unit * 0.18, 0.0, TAU, 18, color, width, true)
	canvas.draw_circle(bulb_center, maxf(width * 0.85, 1.0), color)
	canvas.draw_line(_point(rect, 0.60, 0.28), _point(rect, 0.82, 0.28), color, width, true)
	canvas.draw_line(_point(rect, 0.60, 0.46), _point(rect, 0.75, 0.46), color, width, true)


static func _draw_humidity(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.50, 0.08),
				Vector2(0.34, 0.31),
				Vector2(0.18, 0.53),
				Vector2(0.18, 0.68),
				Vector2(0.29, 0.85),
				Vector2(0.50, 0.92),
				Vector2(0.71, 0.85),
				Vector2(0.82, 0.68),
				Vector2(0.82, 0.53),
				Vector2(0.66, 0.31),
				Vector2(0.50, 0.08),
			],
		),
		color,
		width,
	)


static func _draw_wetness(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	# Suit wetness uses a filled lower waterline, keeping it distinct from the
	# ambient-humidity outline shown in the weather cluster.
	_draw_humidity(canvas, rect, color, width)
	canvas.draw_line(_point(rect, 0.29, 0.66), _point(rect, 0.71, 0.66), color, width, true)
	canvas.draw_line(
		_point(rect, 0.35, 0.76),
		_point(rect, 0.65, 0.76),
		Color(color, color.a * 0.72),
		width,
		true,
	)


static func _draw_cold(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var center: Vector2 = rect.position + rect.size * 0.5
	var unit: float = minf(rect.size.x, rect.size.y)
	for index: int in range(3):
		var axis: Vector2 = Vector2.RIGHT.rotated(float(index) * PI / 3.0)
		var tip_a: Vector2 = center + axis * unit * 0.43
		var tip_b: Vector2 = center - axis * unit * 0.43
		canvas.draw_line(tip_a, tip_b, color, width, true)
		var branch: Vector2 = axis.orthogonal() * unit * 0.10
		canvas.draw_line(
			tip_a - axis * unit * 0.13,
			tip_a - axis * unit * 0.22 + branch,
			color,
			width,
			true,
		)
		canvas.draw_line(
			tip_a - axis * unit * 0.13,
			tip_a - axis * unit * 0.22 - branch,
			color,
			width,
			true,
		)
		canvas.draw_line(
			tip_b + axis * unit * 0.13,
			tip_b + axis * unit * 0.22 + branch,
			color,
			width,
			true,
		)
		canvas.draw_line(
			tip_b + axis * unit * 0.13,
			tip_b + axis * unit * 0.22 - branch,
			color,
			width,
			true,
		)


static func _draw_shelter(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.08, 0.50),
				Vector2(0.50, 0.16),
				Vector2(0.92, 0.50),
			],
		),
		color,
		width,
	)
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.20, 0.50),
				Vector2(0.20, 0.86),
				Vector2(0.80, 0.86),
				Vector2(0.80, 0.50),
			],
		),
		color,
		width,
	)


static func _draw_move(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var center: Vector2 = rect.position + rect.size * 0.5
	var unit: float = minf(rect.size.x, rect.size.y)
	for index: int in range(4):
		var direction: Vector2 = Vector2.RIGHT.rotated(TAU * float(index) / 4.0)
		var side: Vector2 = direction.orthogonal()
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[
					center + direction * unit * 0.46,
					center + direction * unit * 0.20 + side * unit * 0.16,
					center + direction * unit * 0.20 - side * unit * 0.16,
				],
			),
			color,
		)


static func _draw_interact(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var center: Vector2 = rect.position + rect.size * 0.5
	var unit: float = minf(rect.size.x, rect.size.y)
	canvas.draw_circle(center, unit * 0.10, color)
	canvas.draw_arc(center, unit * 0.26, 0.0, TAU, 20, color, width, true)
	var faded: Color = Color(color, color.a * 0.6)
	canvas.draw_arc(center, unit * 0.42, -0.9, 0.9, 12, faded, width, true)
	canvas.draw_arc(center, unit * 0.42, PI - 0.9, PI + 0.9, 12, faded, width, true)


static func _draw_pack(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var unit: float = minf(rect.size.x, rect.size.y)
	canvas.draw_arc(_point(rect, 0.5, 0.36), unit * 0.17, PI, TAU, 14, color, width, true)
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.18, 0.36),
				Vector2(0.82, 0.36),
				Vector2(0.82, 0.88),
				Vector2(0.18, 0.88),
				Vector2(0.18, 0.36),
			],
		),
		color,
		width,
	)
	canvas.draw_line(_point(rect, 0.18, 0.66), _point(rect, 0.82, 0.66), color, width, true)


static func _draw_hammer(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	canvas.draw_line(
		_point(rect, 0.24, 0.90),
		_point(rect, 0.62, 0.40),
		color,
		width * 1.5,
		true,
	)
	canvas.draw_line(
		_point(rect, 0.46, 0.20),
		_point(rect, 0.90, 0.44),
		color,
		width * 2.6,
		true,
	)


static func _draw_strike(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	var offsets: PackedFloat32Array = PackedFloat32Array([-0.20, 0.02, 0.24])
	var lengths: PackedFloat32Array = PackedFloat32Array([0.72, 0.86, 0.66])
	for index: int in range(offsets.size()):
		var shift: float = offsets[index]
		var length: float = lengths[index]
		var fade: float = 1.0 if index == 1 else 0.62
		canvas.draw_line(
			_point(rect, 0.10 + shift, 0.50 - length * 0.42),
			_point(rect, 0.10 + shift + length * 0.62, 0.50 + length * 0.42),
			Color(color, color.a * fade),
			width,
			true,
		)


static func _draw_bolt(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var coords: PackedVector2Array = PackedVector2Array(
		[
			Vector2(0.58, 0.06),
			Vector2(0.22, 0.56),
			Vector2(0.46, 0.56),
			Vector2(0.38, 0.94),
			Vector2(0.78, 0.42),
			Vector2(0.52, 0.42),
		],
	)
	var points: PackedVector2Array = PackedVector2Array()
	for coord: Vector2 in coords:
		points.append(_point(rect, coord.x, coord.y))
	canvas.draw_colored_polygon(points, color)


static func _draw_exit(canvas: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.62, 0.14),
				Vector2(0.14, 0.14),
				Vector2(0.14, 0.86),
				Vector2(0.62, 0.86),
			],
		),
		color,
		width,
	)
	canvas.draw_line(_point(rect, 0.44, 0.50), _point(rect, 0.90, 0.50), color, width, true)
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.72, 0.32),
				Vector2(0.90, 0.50),
				Vector2(0.72, 0.68),
			],
		),
		color,
		width,
	)


static func _draw_cell_mark(
		canvas: CanvasItem,
		rect: Rect2,
		color: Color,
		width: float,
		is_plus: bool,
) -> void:
	_polyline(
		canvas,
		rect,
		PackedVector2Array(
			[
				Vector2(0.10, 0.16),
				Vector2(0.90, 0.16),
				Vector2(0.90, 0.84),
				Vector2(0.10, 0.84),
				Vector2(0.10, 0.16),
			],
		),
		color,
		width,
	)
	canvas.draw_line(_point(rect, 0.30, 0.50), _point(rect, 0.70, 0.50), color, width, true)
	if is_plus:
		canvas.draw_line(_point(rect, 0.50, 0.30), _point(rect, 0.50, 0.70), color, width, true)
