class_name PlayerCamera
extends Camera2D

## Камера игрока с плавным зумом.
## Параметры зума берёт из PlayerBalance.

const MIN_SAFE_ZOOM: float = 0.01

var _target_zoom: float = 2.5
var _balance: PlayerBalance = null

## Инициализировать камеру с балансом.
func setup(balance: PlayerBalance) -> void:
	_balance = balance
	if _balance:
		_target_zoom = _clamp_zoom_value(_balance.zoom_default)
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
				_apply_zoom_step(1, mb.factor)
				return true
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_apply_zoom_step(-1, mb.factor)
				return true
	return false

func _apply_zoom_step(direction: int, wheel_factor: float = 1.0) -> void:
	var zoom_delta: float = _resolve_zoom_step_delta(wheel_factor)
	if direction > 0:
		_target_zoom = _clamp_zoom_value(_target_zoom + zoom_delta)
	else:
		_target_zoom = _clamp_zoom_value(_target_zoom - zoom_delta)

func _resolve_zoom_step_delta(wheel_factor: float = 1.0) -> float:
	var safe_wheel_factor: float = maxf(1.0, absf(wheel_factor))
	if _balance == null:
		return 0.1 * safe_wheel_factor
	return maxf(0.01, _balance.zoom_step * safe_wheel_factor)

func _clamp_zoom_value(value: float) -> float:
	return clampf(value, _zoom_min_limit(), _zoom_max_limit())

func _zoom_min_limit() -> float:
	if _balance == null:
		return MIN_SAFE_ZOOM
	return maxf(MIN_SAFE_ZOOM, minf(_balance.zoom_min, _balance.zoom_max))

func _zoom_max_limit() -> float:
	if _balance == null:
		return _zoom_min_limit()
	return maxf(_zoom_min_limit(), _balance.zoom_max)
