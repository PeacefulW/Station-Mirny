class_name PlayerCamera
extends Camera2D

## Камера игрока с плавным зумом.
## Параметры зума берёт из PlayerBalance.

var _target_zoom: float = 2.5
var _balance: PlayerBalance = null

## Инициализировать камеру с балансом.
func setup(balance: PlayerBalance) -> void:
	_balance = balance
	if _balance:
		_target_zoom = _balance.zoom_default
		zoom = Vector2(_target_zoom, _target_zoom)
	enabled = true
	position_smoothing_enabled = true
	position_smoothing_speed = 10.0

func _process(delta: float) -> void:
	if not _balance:
		return
	var current: float = zoom.x
	if not is_equal_approx(current, _target_zoom):
		var new_zoom: float = lerpf(current, _target_zoom, _balance.zoom_speed * delta)
		if absf(new_zoom - _target_zoom) < 0.01:
			new_zoom = _target_zoom
		zoom = Vector2(new_zoom, new_zoom)

## Обработать ввод зума. Возвращает true если обработан.
func handle_zoom_input(event: InputEvent) -> bool:
	if not _balance:
		return false
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clampf(_target_zoom + _balance.zoom_step, _balance.zoom_min, _balance.zoom_max)
				return true
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clampf(_target_zoom - _balance.zoom_step, _balance.zoom_min, _balance.zoom_max)
				return true
	return false
