class_name ZTransitionOverlay
extends CanvasLayer

## Плавный фейд при переходе между z-уровнями.
## Затемнение → callback → осветление.

signal fade_to_black_finished
signal fade_from_black_finished

@export var balance: ZLevelBalance = null

enum TransitionPhase {
	IDLE,
	FADING_TO_BLACK,
	BLACK,
	FADING_FROM_BLACK,
}

var _rect: ColorRect = null
var _phase: int = TransitionPhase.IDLE

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
	if is_transitioning():
		return
	_run_callback_transition(callback)

func fade_to_black() -> void:
	match _phase:
		TransitionPhase.BLACK:
			call_deferred("_emit_fade_to_black_finished")
			return
		TransitionPhase.IDLE:
			pass
		_:
			return
	_phase = TransitionPhase.FADING_TO_BLACK
	var fade_in: float = balance.fade_in_duration if balance else 0.15
	var tween: Tween = create_tween()
	tween.tween_property(_rect, "color:a", 1.0, fade_in)
	tween.tween_callback(_complete_fade_to_black)

func fade_from_black() -> void:
	match _phase:
		TransitionPhase.IDLE:
			call_deferred("_emit_fade_from_black_finished")
			return
		TransitionPhase.BLACK:
			pass
		_:
			return
	_phase = TransitionPhase.FADING_FROM_BLACK
	var fade_hold: float = balance.fade_hold_duration if balance else 0.05
	var fade_out: float = balance.fade_out_duration if balance else 0.15
	var tween: Tween = create_tween()
	tween.tween_interval(fade_hold)
	tween.tween_property(_rect, "color:a", 0.0, fade_out)
	tween.tween_callback(_complete_fade_from_black)

## Сейчас идёт переход?
func is_transitioning() -> bool:
	return _phase != TransitionPhase.IDLE

func _run_callback_transition(callback: Callable) -> void:
	fade_to_black()
	await fade_to_black_finished
	callback.call()
	fade_from_black()

func _complete_fade_to_black() -> void:
	_phase = TransitionPhase.BLACK
	fade_to_black_finished.emit()

func _complete_fade_from_black() -> void:
	_phase = TransitionPhase.IDLE
	fade_from_black_finished.emit()

func _emit_fade_to_black_finished() -> void:
	fade_to_black_finished.emit()

func _emit_fade_from_black_finished() -> void:
	fade_from_black_finished.emit()
