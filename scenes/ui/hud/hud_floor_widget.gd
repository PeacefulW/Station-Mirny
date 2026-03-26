class_name HudFloorWidget
extends HudWidget

## Текущий z-уровень. Подписывается на EventBus.z_level_changed.
## На поверхности (z=0) показывает текст, на других этажах — меняет цвет.

var _label: Label = null

func _setup() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	add_child(_label)

	EventBus.z_level_changed.connect(_on_z_changed)
	_update_label(0)

func _on_z_changed(new_z: int, _old_z: int) -> void:
	_update_label(new_z)

func _update_label(z: int) -> void:
	if not _label:
		return
	match z:
		-1:
			_label.text = Localization.t("UI_HUD_FLOOR_BASEMENT")
			_label.add_theme_color_override("font_color", Color(0.7, 0.55, 0.4))
		0:
			_label.text = Localization.t("UI_HUD_FLOOR_SURFACE")
			_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		1:
			_label.text = Localization.t("UI_HUD_FLOOR_UPPER")
			_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8))
		_:
			_label.text = Localization.t("UI_HUD_FLOOR_GENERIC", {"z": z})
