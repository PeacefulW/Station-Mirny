class_name HudHpWidget
extends HudWidget

## Шкала HP. Подписывается на EventBus.player_health_changed.
## Скрывается при полном здоровье: спокойный HUD делает появление шкалы самим
## по себе сигналом тревоги.

const WARNING_RATIO: float = 0.6
const CRITICAL_RATIO: float = 0.3

var _meter: HudSegmentMeter = null
var _icon: HudIcon = null
var _value_label: Label = null


func _setup() -> void:
	visible = false

	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(row)

	_icon = HudIcon.new()
	_icon.configure(HudIcons.Id.VITALS, 15.0, HudPalette.STABLE, 1.4)
	row.add_child(_icon)

	_meter = HudSegmentMeter.new()
	_meter.set_fill(HudPalette.STABLE)
	_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_meter)

	_value_label = _make_hud_label(
		LabelStyle.VALUE,
		12,
		HudPalette.TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	_value_label.custom_minimum_size.x = 38.0
	_value_label.text = "100%"
	row.add_child(_value_label)

	EventBus.player_health_changed.connect(_on_health_changed)


func _on_health_changed(current: float, max_value: float) -> void:
	if _meter == null or max_value <= 0.0:
		return
	var ratio: float = clampf(current / max_value, 0.0, 1.0)
	_meter.set_ratio(ratio)
	_value_label.text = "%d%%" % int(round(ratio * 100.0))
	visible = ratio < 0.99

	var is_critical: bool = ratio < CRITICAL_RATIO
	var state_color: Color = HudPalette.STABLE
	if is_critical:
		state_color = HudPalette.CRITICAL
	elif ratio < WARNING_RATIO:
		state_color = HudPalette.CAUTION
	_meter.set_fill(state_color)
	_meter.set_alarming(is_critical)
	_icon.set_glyph_color(state_color)
	_value_label.add_theme_color_override("font_color", state_color)
