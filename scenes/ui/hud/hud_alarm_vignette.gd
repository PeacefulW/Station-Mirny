class_name HudAlarmVignette
extends Control
## Кромка экрана, оживающая только в критическом состоянии.
## Единственный канал "срочно" в постоянном HUD: панели остаются спокойными, а
## тревога приходит из мира вокруг игрока, а не из очередной надписи.

const _RAMP_SIZE: int = 64
const PULSE_SPEED: float = 2.6

var _ramp: ImageTexture = null
var _tint: Color = HudPalette.CRITICAL
var _is_active: bool = false
var _pulse_phase: float = 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visible = false
	set_process(false)


func set_alarm(is_active: bool, tint: Color = HudPalette.CRITICAL) -> void:
	_tint = tint
	if _is_active == is_active:
		queue_redraw()
		return
	_is_active = is_active
	_pulse_phase = 0.0
	visible = is_active
	set_process(is_active)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_phase = fmod(_pulse_phase + delta * PULSE_SPEED, TAU)
	queue_redraw()


func _draw() -> void:
	if not _is_active:
		return
	if _ramp == null:
		_ramp = _build_ramp()
	var strength: float = 0.11 + 0.13 * (0.5 + 0.5 * sin(_pulse_phase))
	draw_texture_rect(_ramp, Rect2(Vector2.ZERO, size), false, Color(_tint, strength))


func _build_ramp() -> ImageTexture:
	var image: Image = Image.create(_RAMP_SIZE, _RAMP_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(_RAMP_SIZE):
		var v: float = (float(y) + 0.5) / float(_RAMP_SIZE)
		for x: int in range(_RAMP_SIZE):
			var u: float = (float(x) + 0.5) / float(_RAMP_SIZE)
			var distance: float = maxf(absf(u - 0.5), absf(v - 0.5)) * 2.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, smoothstep(0.58, 1.0, distance)))
	return ImageTexture.create_from_image(image)
