class_name HudOxygenWidget
extends HudWidget

## Шкала кислорода. Подписывается на EventBus.oxygen_changed.

var _bar: ProgressBar = null
var _label: Label = null

func _setup() -> void:
	custom_minimum_size = Vector2(180, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.text = Localization.t("UI_HUD_O2")
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	row.add_child(_label)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(120, 14)
	_bar.max_value = 100.0
	_bar.value = 100.0
	_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.15)
	bg.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.6, 1.0)
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	row.add_child(_bar)

	add_child(row)
	EventBus.oxygen_changed.connect(_on_oxygen_changed)
	EventBus.language_changed.connect(func(_l: String) -> void: _label.text = Localization.t("UI_HUD_O2"))

func _on_oxygen_changed(current: float, maximum: float) -> void:
	if not _bar or maximum <= 0.0:
		return
	_bar.value = (current / maximum) * 100.0
	var fill: StyleBoxFlat = _bar.get_theme_stylebox("fill") as StyleBoxFlat
	if not fill:
		return
	var percent: float = current / maximum
	if percent > 0.5:
		fill.bg_color = Color(0.2, 0.6, 1.0)
	elif percent > 0.25:
		fill.bg_color = Color(0.9, 0.7, 0.2)
	else:
		fill.bg_color = Color(0.9, 0.2, 0.2)
