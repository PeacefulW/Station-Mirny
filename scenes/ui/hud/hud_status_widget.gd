class_name HudStatusWidget
extends HudWidget

## Статус: снаружи / в базе / питание. Скрап. Строительство.

var _status_label: Label = null
var _scrap_label: Label = null
var _build_label: Label = null
var _is_indoor: bool = false
var _life_support_powered: bool = false

func _setup() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	vbox.add_child(_status_label)

	_scrap_label = Label.new()
	_scrap_label.add_theme_font_size_override("font_size", 13)
	_scrap_label.text = Localization.t("UI_HUD_SCRAP", {"count": 0})
	vbox.add_child(_scrap_label)

	_build_label = Label.new()
	_build_label.add_theme_font_size_override("font_size", 13)
	_build_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	vbox.add_child(_build_label)

	add_child(vbox)

	_update_status()

	EventBus.player_entered_indoor.connect(func() -> void: _is_indoor = true; _update_status())
	EventBus.player_exited_indoor.connect(func() -> void: _is_indoor = false; _update_status())
	EventBus.life_support_power_changed.connect(func(p: bool) -> void: _life_support_powered = p; _update_status())
	EventBus.scrap_collected.connect(func(total: int) -> void: _scrap_label.text = Localization.t("UI_HUD_SCRAP", {"count": total}))
	EventBus.scrap_spent.connect(func(_a: int, rem: int) -> void: _scrap_label.text = Localization.t("UI_HUD_SCRAP", {"count": rem}))
	EventBus.build_mode_changed.connect(func(a: bool) -> void: _build_label.text = Localization.t("UI_HUD_BUILD_MODE") if a else "")
	EventBus.language_changed.connect(func(_l: String) -> void: _update_status(); _scrap_label.text = Localization.t("UI_HUD_SCRAP", {"count": 0}))

func _update_status() -> void:
	if not _status_label:
		return
	if not _is_indoor:
		_status_label.text = Localization.t("UI_HUD_STATUS_OUTSIDE")
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	elif _life_support_powered:
		_status_label.text = Localization.t("UI_HUD_STATUS_BASE_POWERED")
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	else:
		_status_label.text = Localization.t("UI_HUD_STATUS_BASE_UNPOWERED")
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.25))
