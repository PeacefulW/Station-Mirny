class_name ZTransitionOverlay
extends CanvasLayer

## Плавный фейд при переходе между z-уровнями.
## Затемнение → callback → осветление.

var _rect: ColorRect = null
var _is_transitioning: bool = false

func _ready() -> void:
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
	var tween: Tween = create_tween()
	tween.tween_property(_rect, "color:a", 1.0, 0.15)
	tween.tween_callback(callback)
	tween.tween_interval(0.05)
	tween.tween_property(_rect, "color:a", 0.0, 0.15)
	tween.tween_callback(func() -> void: _is_transitioning = false)

## Сейчас идёт переход?
func is_transitioning() -> bool:
	return _is_transitioning
