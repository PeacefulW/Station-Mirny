class_name HudHpWidget
extends HudWidget

## Шкала HP. Подписывается на EventBus.player_health_changed.
## Скрывается когда HP = 100%.

var _bar: ProgressBar = null
var _label: Label = null

func _setup() -> void:
	custom_minimum_size = Vector2(180, 0)
	visible = false

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.text = Localization.t("UI_HUD_HP")
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
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
	fill.bg_color = Color(0.3, 0.8, 0.3)
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	row.add_child(_bar)

	add_child(row)
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.language_changed.connect(func(_l: String) -> void: _label.text = Localization.t("UI_HUD_HP"))

func _on_health_changed(current: float, max_value: float) -> void:
	if not _bar or max_value <= 0.0:
		return
	var percent: float = current / max_value
	_bar.value = percent * 100.0

	# Скрыть при полном HP
	visible = percent < 0.99

	var fill: StyleBoxFlat = _bar.get_theme_stylebox("fill") as StyleBoxFlat
	if not fill:
		return
	if percent > 0.6:
		fill.bg_color = Color(0.3, 0.8, 0.3)
	elif percent > 0.3:
		fill.bg_color = Color(0.9, 0.7, 0.2)
	else:
		fill.bg_color = Color(0.9, 0.2, 0.2)
