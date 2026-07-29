class_name HudSegmentMeter
extends Control
## Сегментная шкала жизненного показателя.
## Сегменты вместо гладкой полосы: запас читается как отсчитываемый ресурс и
## заметен боковым зрением, когда игрок смотрит на мир, а не на HUD.

const SEGMENT_COUNT: int = 16
const SEGMENT_GAP: float = 2.0
const PULSE_SPEED: float = 3.6

var _ratio: float = 1.0
var _fill: Color = HudPalette.OXYGEN
var _is_alarming: bool = false
var _pulse_phase: float = 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 11.0)
	set_process(false)


func set_ratio(ratio: float) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(_ratio, clamped):
		return
	_ratio = clamped
	queue_redraw()


func set_fill(color: Color) -> void:
	if _fill.is_equal_approx(color):
		return
	_fill = color
	queue_redraw()


## Тревога стоит кадрового времени, поэтому пульс включается только в критике.
func set_alarming(is_alarming: bool) -> void:
	if _is_alarming == is_alarming:
		return
	_is_alarming = is_alarming
	_pulse_phase = 0.0
	set_process(is_alarming)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_phase = fmod(_pulse_phase + delta * PULSE_SPEED, TAU)
	queue_redraw()


func _draw() -> void:
	var track: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(track, HudPalette.METER_TRACK, true)
	draw_rect(track, HudPalette.METER_TRACK_EDGE, false, 1.0)

	var inner: Rect2 = track.grow(-2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var segment_width: float = (
		(inner.size.x - SEGMENT_GAP * float(SEGMENT_COUNT - 1)) / float(SEGMENT_COUNT)
	)
	if segment_width <= 0.0:
		return
	var pulse: float = 1.0
	if _is_alarming:
		pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(_pulse_phase))
	var filled_edge: float = _ratio * float(SEGMENT_COUNT)
	for index: int in range(SEGMENT_COUNT):
		var amount: float = clampf(filled_edge - float(index), 0.0, 1.0)
		var rect: Rect2 = Rect2(
			Vector2(inner.position.x + float(index) * (segment_width + SEGMENT_GAP), inner.position.y),
			Vector2(segment_width, inner.size.y),
		)
		if amount <= 0.0:
			draw_rect(rect, Color(_fill, 0.10), true)
			continue
		var is_head: bool = filled_edge - float(index) < 1.0
		var color: Color = _fill.lightened(0.25) if is_head else _fill
		draw_rect(rect, Color(color, amount * pulse), true)
