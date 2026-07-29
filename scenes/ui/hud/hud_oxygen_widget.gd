class_name HudOxygenWidget
extends HudWidget

## Кислород — главный показатель HUD, поэтому он единственный получает крупное
## число и собственную шкалу. Подписывается на EventBus.oxygen_changed.

const WARNING_RATIO: float = 0.5
const CRITICAL_RATIO: float = 0.25

var _meter: HudSegmentMeter = null
var _icon: HudIcon = null
var _title_label: Label = null
var _value_label: Label = null
var _warning_row: HBoxContainer = null
var _warning_icon: HudIcon = null
var _warning_label: Label = null


func _setup() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(column)

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 7)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(head)

	_icon = HudIcon.new()
	_icon.configure(HudIcons.Id.OXYGEN, 15.0, HudPalette.OXYGEN, 1.4)
	head.add_child(_icon)

	_title_label = _make_hud_label(LabelStyle.CAPS, 11, HudPalette.OXYGEN)
	_title_label.text = Localization.t("UI_HUD_O2")
	head.add_child(_title_label)

	_value_label = _make_hud_label(
		LabelStyle.DISPLAY,
		16,
		HudPalette.TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_label.text = "100%"
	head.add_child(_value_label)

	_meter = HudSegmentMeter.new()
	_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_meter)

	_warning_row = HBoxContainer.new()
	_warning_row.add_theme_constant_override("separation", 6)
	_warning_row.mouse_filter = MOUSE_FILTER_IGNORE
	_warning_row.visible = false
	column.add_child(_warning_row)

	_warning_icon = HudIcon.new()
	_warning_icon.configure(HudIcons.Id.WARNING, 12.0, HudPalette.CAUTION, 1.3)
	_warning_row.add_child(_warning_icon)

	_warning_label = _make_hud_label(LabelStyle.CAPS, 10, HudPalette.CAUTION)
	_warning_label.text = Localization.t("UI_HUD_O2_LOW")
	_warning_row.add_child(_warning_label)

	EventBus.oxygen_changed.connect(_on_oxygen_changed)
	EventBus.language_changed.connect(_on_language_changed)


func _on_language_changed(_locale: String) -> void:
	_title_label.text = Localization.t("UI_HUD_O2")
	_warning_label.text = Localization.t("UI_HUD_O2_LOW")


func _on_oxygen_changed(current: float, maximum: float) -> void:
	if _meter == null or maximum <= 0.0:
		return
	var ratio: float = clampf(current / maximum, 0.0, 1.0)
	_meter.set_ratio(ratio)
	_value_label.text = "%d%%" % int(round(ratio * 100.0))

	var is_critical: bool = ratio < CRITICAL_RATIO
	var state_color: Color = HudPalette.OXYGEN
	if is_critical:
		state_color = HudPalette.CRITICAL
	elif ratio < WARNING_RATIO:
		state_color = HudPalette.CAUTION
	_meter.set_fill(state_color)
	_meter.set_alarming(is_critical)
	# Весь блок кислорода красится целиком: разноцветная строка читалась бы как
	# сбой отрисовки, а не как тревога.
	_icon.set_glyph_color(state_color)
	_title_label.add_theme_color_override("font_color", state_color)
	_value_label.add_theme_color_override(
		"font_color",
		HudPalette.TEXT_PRIMARY if ratio >= WARNING_RATIO else state_color,
	)
	_warning_row.visible = ratio < WARNING_RATIO
	_warning_label.add_theme_color_override("font_color", state_color)
	_warning_icon.set_glyph_color(state_color)
