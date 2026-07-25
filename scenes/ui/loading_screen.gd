class_name LoadingScreen
extends CanvasLayer
## Full-viewport honest world-loading surface. It renders only authoritative
## WorldStreamer progress and never decides readiness itself.

signal loading_completed
signal screen_presented

var _bg: ColorRect = null
var _title: Label = null
var _progress_bar: ProgressBar = null
var _label: Label = null
var _detail_label: Label = null
var _fade_tween: Tween = null
var _presented: bool = false
var _fading: bool = false


func _ready() -> void:
	layer = 100
	_build_ui()
	call_deferred("_announce_presented")


func is_presented() -> bool:
	return _presented


func is_fading() -> bool:
	return _fading


func set_loading_state(state: Dictionary) -> void:
	if _progress_bar == null or _label == null or _detail_label == null:
		return
	var progress_ratio: float = clampf(
		float(state.get("progress_ratio", 0.0)),
		0.0,
		1.0,
	)
	var stage: String = String(state.get("current_stage", "resolving_spawn"))
	var target_count: int = int(state.get("target_chunk_count", 0))
	var current_count: int = _stage_current_count(stage, state)
	_progress_bar.value = progress_ratio * 100.0
	_label.text = Localization.t(_stage_label_key(stage))
	_detail_label.text = Localization.t(
		"UI_LOADING_INITIAL_BUBBLE_PROGRESS",
		{
			"current": current_count,
			"total": target_count,
			"percent": roundi(progress_ratio * 100.0),
		},
	)


func fade_out() -> void:
	if _fading:
		return
	_fading = true
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_bg, "modulate:a", 0.0, 0.35)
	_fade_tween.tween_callback(_finish_fade)


func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.025, 0.032, 0.045, 1.0)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -240.0
	vbox.offset_right = 240.0
	vbox.offset_top = -92.0
	vbox.offset_bottom = 92.0
	vbox.add_theme_constant_override("separation", 14)
	_bg.add_child(vbox)

	_title = Label.new()
	_title.text = Localization.t("UI_LOADING_INITIAL_BUBBLE_TITLE")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(0.91, 0.82, 0.58))
	vbox.add_child(_title)

	_label = Label.new()
	_label.text = Localization.t("UI_LOADING_PREPARING")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 17)
	vbox.add_child(_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.custom_minimum_size = Vector2(480.0, 20.0)
	_progress_bar.show_percentage = false
	vbox.add_child(_progress_bar)

	_detail_label = Label.new()
	_detail_label.text = Localization.t(
		"UI_LOADING_INITIAL_BUBBLE_PROGRESS",
		{ "current": 0, "total": 0, "percent": 0 },
	)
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override("font_size", 13)
	_detail_label.add_theme_color_override("font_color", Color(0.66, 0.70, 0.76))
	vbox.add_child(_detail_label)


func _announce_presented() -> void:
	await get_tree().process_frame
	if _presented or not is_inside_tree():
		return
	_presented = true
	screen_presented.emit()


func _finish_fade() -> void:
	loading_completed.emit()
	queue_free()


func _stage_label_key(stage: String) -> String:
	match stage:
		"resolving_spawn":
			return "UI_LOADING_RESOLVING_SPAWN"
		"generating":
			return "UI_LOADING_GENERATING_INITIAL_BUBBLE"
		"gameplay":
			return "UI_LOADING_PREPARING_GAMEPLAY"
		"presentation":
			return "UI_LOADING_PREPARING_PRESENTATION"
		"reserve":
			return "UI_LOADING_PREPARING_RESERVE"
		"ready":
			return "UI_LOADING_READY"
		_:
			return "UI_LOADING_PREPARING"


func _stage_current_count(stage: String, state: Dictionary) -> int:
	match stage:
		"generating":
			return int(state.get("generated_chunk_count", 0))
		"gameplay":
			return int(state.get("gameplay_ready_chunk_count", 0))
		"presentation":
			return int(state.get("presentation_ready_chunk_count", 0))
		"reserve", "ready":
			return int(state.get("reserve_ready_chunk_count", 0))
		_:
			return 0
