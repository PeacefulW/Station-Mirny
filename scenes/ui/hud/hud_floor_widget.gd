class_name HudFloorWidget
extends HudWidget

## Текущий z-уровень. Подписывается на EventBus.z_level_changed.
## На поверхности (z=0) показывает текст, на других этажах — меняет цвет.

var _label: Label = null
var _current_z: int = 0

func _setup() -> void:
	_label = _make_hud_label(
		LabelStyle.CAPS,
		10,
		HudPalette.TEXT_QUIET,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	add_child(_label)

	EventBus.z_level_changed.connect(_on_z_changed)
	EventBus.language_changed.connect(func(_locale: String) -> void: _update_label(_current_z))
	_update_label(0)

func _on_z_changed(new_z: int, _old_z: int) -> void:
	_current_z = new_z
	_update_label(new_z)

func _update_label(z: int) -> void:
	if not _label:
		return
	# Плоский Control не пересчитывает минимум за наследником: без этого строка
	# переменной длины выезжает за плиту.
	update_minimum_size()
	match z:
		-1:
			_label.text = Localization.t("UI_HUD_FLOOR_BASEMENT")
			_label.add_theme_color_override("font_color", HudPalette.CAUTION)
		0:
			_label.text = Localization.t("UI_HUD_FLOOR_SURFACE")
			_label.add_theme_color_override("font_color", HudPalette.TEXT_QUIET)
		1:
			_label.text = Localization.t("UI_HUD_FLOOR_UPPER")
			_label.add_theme_color_override("font_color", HudPalette.PHASE_NIGHT)
		_:
			_label.text = Localization.t("UI_HUD_FLOOR_GENERIC", {"z": z})
