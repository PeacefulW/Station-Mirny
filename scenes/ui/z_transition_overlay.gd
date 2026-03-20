class_name ZTransitionOverlay
extends CanvasLayer

## Плавный фейд при переходе между z-уровнями.
## Затемнение → callback → осветление.

@export var balance: ZLevelBalance = null

var _rect: ColorRect = null
var _is_transitioning: bool = false

func _ready() -> void:
	if not balance:
		balance = load("res://data/balance/z_level_balance.tres") as ZLevelBalance
	layer = 100
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

## Выполнить фейд: затемнение → callback → осветление.
func do_transition(callback: Callable) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	var fade_in: float = balance.fade_in_duration if balance else 0.15
	var fade_hold: float = balance.fade_hold_duration if balance else 0.05
	var fade_out: float = balance.fade_out_duration if balance else 0.15
	var tween: Tween = create_tween()
	tween.tween_property(_rect, "color:a", 1.0, fade_in)
	tween.tween_callback(callback)
	tween.tween_interval(fade_hold)
	tween.tween_property(_rect, "color:a", 0.0, fade_out)
	tween.tween_callback(func() -> void: _is_transitioning = false)

## Сейчас идёт переход?
func is_transitioning() -> bool:
	return _is_transitioning
