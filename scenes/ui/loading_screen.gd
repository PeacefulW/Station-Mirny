class_name LoadingScreen
extends CanvasLayer

## Экран загрузки мира. Показывает прогресс-бар и текст этапа.
## Перекрывает всё до завершения boot sequence.

signal loading_completed
signal screen_presented

var _bg: ColorRect = null
var _progress_bar: ProgressBar = null
var _label: Label = null
var _fade_tween: Tween = null
var _presented: bool = false

func _ready() -> void:
	layer = 100
	_build_ui()
	call_deferred("_announce_presented")

func is_presented() -> bool:
	return _presented

func set_progress(value: float, text: String) -> void:
	if _progress_bar:
		_progress_bar.value = value
	if _label:
		_label.text = text

func fade_out() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_bg, "modulate:a", 0.0, 0.5)
	_fade_tween.tween_callback(queue_free)
	_fade_tween.tween_callback(func() -> void: loading_completed.emit())

func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.05, 0.08, 1.0)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -200.0
	vbox.offset_right = 200.0
	vbox.offset_top = -40.0
	vbox.offset_bottom = 40.0
	vbox.add_theme_constant_override("separation", 12)
	_bg.add_child(vbox)

	_label = Label.new()
	_label.text = Localization.t("UI_LOADING_PREPARING")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.custom_minimum_size = Vector2(400.0, 24.0)
	_progress_bar.show_percentage = false
	vbox.add_child(_progress_bar)

func _announce_presented() -> void:
	await get_tree().process_frame
	if _presented or not is_inside_tree():
		return
	_presented = true
	screen_presented.emit()
