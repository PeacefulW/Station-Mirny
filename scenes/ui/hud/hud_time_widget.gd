class_name HudTimeWidget
extends HudWidget

## Время суток: крупные часы, иконка неба и строка дня.
## Фаза несёт цвет и пиктограмму, потому что ночь и закат должны читаться
## периферийным зрением, без чтения текста.

var _sky_icon: HudIcon = null
var _time_label: Label = null
var _day_label: Label = null
var _phase: int = 1


func _setup() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(column)

	var head: HBoxContainer = HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_END
	head.add_theme_constant_override("separation", 9)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(head)

	_sky_icon = HudIcon.new()
	_sky_icon.configure(HudIcons.Id.SUN, 19.0, HudPalette.PHASE_DAY, 1.4)
	_sky_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_sky_icon)

	_time_label = _make_hud_label(
		LabelStyle.DISPLAY,
		25,
		HudPalette.TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	_time_label.text = "%02d:00" % 7
	head.add_child(_time_label)

	_day_label = _make_hud_label(
		LabelStyle.CAPS,
		10,
		HudPalette.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_day_label)

	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.time_of_day_changed.connect(_on_phase_changed)
	EventBus.language_changed.connect(_on_language_changed)
	_on_hour_changed(TimeManager.get_hour() if TimeManager else 7)
	var current_phase: int = TimeManager.current_time_of_day if TimeManager else 1
	_on_phase_changed(current_phase, current_phase)


func _on_hour_changed(hour: int) -> void:
	if _time_label != null:
		_time_label.text = "%02d:00" % hour


func _on_day_changed(_day_number: int) -> void:
	_refresh_day_label()


func _on_language_changed(_locale: String) -> void:
	_refresh_day_label()


func _on_phase_changed(new_phase: int, _old_phase: int) -> void:
	_phase = new_phase
	_refresh_day_label()
	if _time_label == null:
		return
	var color: Color = HudPalette.phase_color(new_phase)
	_time_label.add_theme_color_override("font_color", color)
	_sky_icon.set_glyph_color(color)
	_sky_icon.set_glyph(_phase_glyph(new_phase))


func _phase_glyph(phase: int) -> HudIcons.Id:
	match phase:
		0:
			return HudIcons.Id.DAWN
		2:
			return HudIcons.Id.DUSK
		3:
			return HudIcons.Id.MOON
		_:
			return HudIcons.Id.SUN


func _refresh_day_label() -> void:
	if _day_label == null:
		return
	var day: int = TimeManager.current_day if TimeManager else 1
	_day_label.text = Localization.t(
		"UI_HUD_DAY_PHASE",
		{
			"day": day,
			"phase": Localization.t(_phase_name_key(_phase)),
		},
	)


func _phase_name_key(phase: int) -> String:
	match phase:
		0:
			return "UI_TIME_DAWN"
		1:
			return "UI_TIME_DAY"
		2:
			return "UI_TIME_DUSK"
		3:
			return "UI_TIME_NIGHT"
		_:
			return "UI_TIME_UNKNOWN"
