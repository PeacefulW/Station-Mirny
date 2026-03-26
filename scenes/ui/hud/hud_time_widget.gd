class_name HudTimeWidget
extends HudWidget

## Время суток + день + фаза. Подписывается на EventBus.

var _time_label: Label = null
var _day_label: Label = null

func _setup() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE

	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_font_size_override("font_size", 16)
	_time_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_time_label.text = "%02d:00" % 7
	vbox.add_child(_time_label)

	_day_label = Label.new()
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_day_label.add_theme_font_size_override("font_size", 12)
	_day_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	vbox.add_child(_day_label)

	add_child(vbox)

	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.time_of_day_changed.connect(_on_phase_changed)
	EventBus.language_changed.connect(func(_l: String) -> void: _refresh_day_label())

	_refresh_day_label()

func _on_hour_changed(hour: int) -> void:
	if _time_label:
		_time_label.text = "%02d:00" % hour

func _on_day_changed(_day_number: int) -> void:
	_refresh_day_label()

func _on_phase_changed(new_phase: int, _old_phase: int) -> void:
	_refresh_day_label()
	if not _time_label:
		return
	match new_phase:
		0: _time_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.5))
		1: _time_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.75))
		2: _time_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.3))
		3: _time_label.add_theme_color_override("font_color", Color(0.4, 0.45, 0.7))

func _refresh_day_label() -> void:
	if not _day_label:
		return
	var day: int = TimeManager.current_day if TimeManager else 1
	var phase: int = TimeManager.current_time_of_day if TimeManager else 1
	var phase_name: String = _get_phase_name(phase)
	_day_label.text = Localization.t("UI_HUD_DAY_PHASE", {"day": day, "phase": phase_name})

func _get_phase_name(phase: int) -> String:
	match phase:
		0: return Localization.t("UI_TIME_DAWN")
		1: return Localization.t("UI_TIME_DAY")
		2: return Localization.t("UI_TIME_DUSK")
		3: return Localization.t("UI_TIME_NIGHT")
	return Localization.t("UI_TIME_UNKNOWN")
