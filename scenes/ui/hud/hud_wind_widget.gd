class_name HudWindWidget
extends HudWidget
## Индикатор ветра: сила в процентах + живая стрелка направления. Источник —
## WindRuntime (один владелец состояния ветра). Дублирует визуальный спидометр
## летящей пыли точным числом.

const UPDATE_INTERVAL_SECONDS: float = 0.12

var _label: Label = null
var _icon: HudIcon = null
var _elapsed: float = 0.0
var _last_strength_bucket: int = -1


func _setup() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(row)

	_label = _make_hud_label(
		LabelStyle.CAPS,
		11,
		HudPalette.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	row.add_child(_label)

	_icon = HudIcon.new()
	_icon.configure(HudIcons.Id.MOVE, 14.0, HudPalette.TEXT_SECONDARY, 1.3)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)

	EventBus.language_changed.connect(_on_language_changed)
	_update_readout()


func _on_language_changed(_locale: String) -> void:
	_last_strength_bucket = -1
	_update_readout()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL_SECONDS:
		return
	_elapsed = 0.0
	_update_readout()


func _update_readout() -> void:
	if _label == null:
		return
	_icon.use_wind_arrow(deg_to_rad(WindRuntime.get_wind_direction_deg()))
	var strength_pct: int = int(round(clampf(WindRuntime.get_wind_strength(), 0.0, 1.0) * 100.0))
	# Перерисовываем текст только при заметной смене, чтобы не дёргать локализацию.
	if strength_pct == _last_strength_bucket:
		return
	_last_strength_bucket = strength_pct
	_label.text = Localization.t("UI_HUD_WIND", {"strength": strength_pct})
