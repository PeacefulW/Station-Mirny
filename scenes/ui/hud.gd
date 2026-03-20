class_name GameHUD
extends Control

## Интерфейс (HUD). Подписывается на EventBus и показывает
## состояние игрока: O₂, скрап, режим строительства, время.

var _o2_bar: ProgressBar = null
var _o2_label: Label = null
var _status_label: Label = null
var _scrap_label: Label = null
var _build_label: Label = null
var _controls_label: Label = null
var _game_over_label: Label = null
var _time_label: Label = null
var _day_label: Label = null
var _is_indoor: bool = false
var _life_support_powered: bool = false

func _ready() -> void:
	_create_ui()
	_connect_signals()
	_apply_localization()

func _create_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var o2_container := HBoxContainer.new()
	o2_container.position = Vector2(20, 15)
	add_child(o2_container)

	_o2_label = Label.new()
	_o2_label.add_theme_font_size_override("font_size", 18)
	o2_container.add_child(_o2_label)

	_o2_bar = ProgressBar.new()
	_o2_bar.custom_minimum_size = Vector2(200, 24)
	_o2_bar.max_value = 100.0
	_o2_bar.value = 100.0
	_o2_bar.show_percentage = false
	_o2_bar.add_theme_stylebox_override("background", _make_rounded_box(Color(0.15, 0.15, 0.2)))
	_o2_bar.add_theme_stylebox_override("fill", _make_rounded_box(Color(0.3, 0.7, 1.0)))
	o2_container.add_child(_o2_bar)

	_status_label = Label.new()
	_status_label.position = Vector2(20, 48)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	_status_label.add_theme_font_size_override("font_size", 16)
	add_child(_status_label)

	_scrap_label = Label.new()
	_scrap_label.position = Vector2(20, 72)
	_scrap_label.add_theme_font_size_override("font_size", 16)
	add_child(_scrap_label)

	_build_label = Label.new()
	_build_label.position = Vector2(20, 96)
	_build_label.text = ""
	_build_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	_build_label.add_theme_font_size_override("font_size", 16)
	add_child(_build_label)

	_time_label = Label.new()
	_time_label.anchor_left = 1.0
	_time_label.anchor_right = 1.0
	_time_label.position = Vector2(-180, 15)
	_time_label.text = "07:00"
	_time_label.add_theme_font_size_override("font_size", 22)
	_time_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	add_child(_time_label)

	_day_label = Label.new()
	_day_label.anchor_left = 1.0
	_day_label.anchor_right = 1.0
	_day_label.position = Vector2(-180, 42)
	_day_label.add_theme_font_size_override("font_size", 14)
	_day_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	add_child(_day_label)

	_controls_label = Label.new()
	_controls_label.anchor_top = 1.0
	_controls_label.anchor_bottom = 1.0
	_controls_label.anchor_left = 0.0
	_controls_label.position = Vector2(20, -60)
	_controls_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.5))
	_controls_label.add_theme_font_size_override("font_size", 14)
	add_child(_controls_label)

	_game_over_label = Label.new()
	_game_over_label.anchor_left = 0.5
	_game_over_label.anchor_top = 0.4
	_game_over_label.add_theme_font_size_override("font_size", 48)
	_game_over_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1))
	_game_over_label.visible = false
	add_child(_game_over_label)

func _connect_signals() -> void:
	EventBus.oxygen_changed.connect(_on_oxygen_changed)
	EventBus.player_entered_indoor.connect(_on_entered_indoor)
	EventBus.player_exited_indoor.connect(_on_exited_indoor)
	EventBus.scrap_collected.connect(_on_scrap_changed)
	EventBus.scrap_spent.connect(_on_scrap_spent)
	EventBus.build_mode_changed.connect(_on_build_mode_changed)
	EventBus.life_support_power_changed.connect(_on_life_support_power_changed)
	EventBus.game_over.connect(_on_game_over)
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.time_of_day_changed.connect(_on_time_of_day_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.language_changed.connect(_on_language_changed)

func _on_oxygen_changed(current: float, maximum: float) -> void:
	if not _o2_bar:
		return
	_o2_bar.max_value = maximum
	_o2_bar.value = current
	var percent: float = current / maximum if maximum > 0.0 else 0.0
	var fill: StyleBoxFlat = _o2_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		if percent > 0.5:
			fill.bg_color = Color(0.3, 0.7, 1.0)
		elif percent > 0.25:
			fill.bg_color = Color(1.0, 0.8, 0.2)
		else:
			fill.bg_color = Color(1.0, 0.2, 0.1)

func _make_rounded_box(bg_color: Color, radius: int = 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

func _on_entered_indoor() -> void:
	_is_indoor = true
	_update_status_label()

func _on_exited_indoor() -> void:
	_is_indoor = false
	_update_status_label()

func _on_scrap_changed(total: int) -> void:
	_scrap_label.text = Localization.t("UI_HUD_SCRAP", {"count": total})

func _on_scrap_spent(_amount: int, remaining: int) -> void:
	_scrap_label.text = Localization.t("UI_HUD_SCRAP", {"count": remaining})

func _on_build_mode_changed(is_active: bool) -> void:
	_build_label.text = Localization.t("UI_HUD_BUILD_MODE") if is_active else ""

func _on_game_over() -> void:
	_game_over_label.visible = true

func _on_hour_changed(hour: int) -> void:
	if not _time_label:
		return
	_time_label.text = "%02d:00" % hour

func _on_time_of_day_changed(new_phase: int, _old_phase: int) -> void:
	_update_day_label(new_phase)

func _on_day_changed(day_number: int) -> void:
	if not _day_label:
		return
	var phase_name: String = _get_phase_name(TimeManager.current_time_of_day)
	_day_label.text = Localization.t("UI_HUD_DAY_PHASE", {"day": day_number, "phase": phase_name})

func _update_day_label(phase: int) -> void:
	if not _day_label:
		return
	var phase_name: String = _get_phase_name(phase)
	var day: int = TimeManager.current_day if TimeManager else 1
	_day_label.text = Localization.t("UI_HUD_DAY_PHASE", {"day": day, "phase": phase_name})
	match phase:
		TimeManagerSingleton.TimeOfDay.DAWN:
			_day_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
		TimeManagerSingleton.TimeOfDay.DAY:
			_day_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		TimeManagerSingleton.TimeOfDay.DUSK:
			_day_label.add_theme_color_override("font_color", Color(0.85, 0.5, 0.3))
		TimeManagerSingleton.TimeOfDay.NIGHT:
			_day_label.add_theme_color_override("font_color", Color(0.4, 0.45, 0.7))

func _get_phase_name(phase: int) -> String:
	match phase:
		TimeManagerSingleton.TimeOfDay.DAWN:
			return Localization.t("UI_TIME_DAWN")
		TimeManagerSingleton.TimeOfDay.DAY:
			return Localization.t("UI_TIME_DAY")
		TimeManagerSingleton.TimeOfDay.DUSK:
			return Localization.t("UI_TIME_DUSK")
		TimeManagerSingleton.TimeOfDay.NIGHT:
			return Localization.t("UI_TIME_NIGHT")
	return Localization.t("UI_TIME_UNKNOWN")

func _on_life_support_power_changed(is_powered: bool) -> void:
	_life_support_powered = is_powered
	_update_status_label()

func _update_status_label() -> void:
	if not _status_label:
		return
	if not _is_indoor:
		_status_label.text = Localization.t("UI_HUD_STATUS_OUTSIDE")
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		return
	if _life_support_powered:
		_status_label.text = Localization.t("UI_HUD_STATUS_BASE_POWERED")
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	else:
		_status_label.text = Localization.t("UI_HUD_STATUS_BASE_UNPOWERED")
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.25))

func _apply_localization() -> void:
	if _o2_label:
		_o2_label.text = Localization.t("UI_HUD_OXYGEN")
	if _scrap_label:
		_scrap_label.text = Localization.t("UI_HUD_SCRAP", {"count": 0})
	if _controls_label:
		_controls_label.text = Localization.t("UI_HUD_CONTROLS")
	if _game_over_label:
		_game_over_label.text = Localization.t("UI_GAME_OVER")
	if _build_label and not _build_label.text.is_empty():
		_build_label.text = Localization.t("UI_HUD_BUILD_MODE")
	_update_status_label()
	_update_day_label(TimeManager.current_time_of_day if TimeManager else 0)

func _on_language_changed(_locale_code: String) -> void:
	_apply_localization()