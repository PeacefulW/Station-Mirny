class_name HudHintsWidget
extends HudWidget

## Контекстные подсказки внизу экрана.
## Меняются при переключении режима строительства.

var _label: Label = null

func _setup() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.4, 0.42, 0.48))
	add_child(_label)

	_show_default_hints()
	EventBus.build_mode_changed.connect(_on_build_mode)
	EventBus.language_changed.connect(func(_l: String) -> void: _show_default_hints())

func _on_build_mode(is_active: bool) -> void:
	if is_active:
		_label.text = Localization.t("UI_HINT_BUILD_MODE")
	else:
		_show_default_hints()

func _show_default_hints() -> void:
	_label.text = Localization.t("UI_HINT_DEFAULT")
