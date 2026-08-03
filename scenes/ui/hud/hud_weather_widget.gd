class_name HudWeatherWidget
extends HudWidget
## Индикатор погоды: локализованное название режима и компактный ряд внешних
## условий. WeatherRuntime остаётся единственным владельцем значений.

const UPDATE_INTERVAL_SECONDS: float = 0.2
const OVERCAST_RATIO: float = 0.35
const METRIC_ICON_SIZE: float = 14.0

var _weather_label: Label = null
var _cloud_label: Label = null
var _temperature_label: Label = null
var _humidity_label: Label = null
var _cloud_icon: HudIcon = null
var _elapsed: float = 0.0
var _last_weather_text: String = ""
var _last_cloud_percent: int = -1
var _last_temperature_c: int = -1000
var _last_humidity_percent: int = -1
var _is_overcast: bool = false


func _setup() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "WeatherLayout"
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(column)

	_weather_label = _make_hud_label(
		LabelStyle.CAPS,
		11,
		HudPalette.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	_weather_label.name = "WeatherName"
	_weather_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_weather_label)

	var metrics: HBoxContainer = HBoxContainer.new()
	metrics.name = "WeatherMetrics"
	metrics.alignment = BoxContainer.ALIGNMENT_END
	metrics.add_theme_constant_override("separation", 10)
	metrics.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(metrics)

	_cloud_icon = _make_metric_icon("CloudIcon", HudIcons.Id.SUN)
	_cloud_label = _make_metric_label("CloudValue")
	metrics.add_child(_make_metric_group("CloudMetric", _cloud_icon, _cloud_label))

	var temperature_icon: HudIcon = _make_metric_icon(
		"TemperatureIcon",
		HudIcons.Id.TEMPERATURE,
	)
	_temperature_label = _make_metric_label("TemperatureValue")
	metrics.add_child(
		_make_metric_group("TemperatureMetric", temperature_icon, _temperature_label),
	)

	var humidity_icon: HudIcon = _make_metric_icon("HumidityIcon", HudIcons.Id.HUMIDITY)
	_humidity_label = _make_metric_label("HumidityValue")
	metrics.add_child(_make_metric_group("HumidityMetric", humidity_icon, _humidity_label))

	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.language_changed.connect(_on_language_changed)
	_update_readout()


func _make_metric_icon(node_name: StringName, glyph: HudIcons.Id) -> HudIcon:
	var icon: HudIcon = HudIcon.new()
	icon.name = node_name
	icon.configure(glyph, METRIC_ICON_SIZE, HudPalette.TEXT_SECONDARY, 1.3)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func _make_metric_label(node_name: StringName) -> Label:
	var label: Label = _make_hud_label(
		LabelStyle.VALUE,
		11,
		HudPalette.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	label.name = node_name
	return label


func _make_metric_group(
		node_name: StringName,
		icon: HudIcon,
		label: Label,
) -> HBoxContainer:
	var group: HBoxContainer = HBoxContainer.new()
	group.name = node_name
	group.add_theme_constant_override("separation", 4)
	group.mouse_filter = MOUSE_FILTER_IGNORE
	group.add_child(icon)
	group.add_child(label)
	return group


func _on_weather_changed(_regime_id: StringName, _previous_regime_id: StringName) -> void:
	_update_readout()


func _on_language_changed(_locale: String) -> void:
	_update_readout()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL_SECONDS:
		return
	_elapsed = 0.0
	_update_readout()


func _update_readout() -> void:
	if (
		_weather_label == null
		or _cloud_label == null
		or _temperature_label == null
		or _humidity_label == null
		or _cloud_icon == null
	):
		return
	var name_key: StringName = WeatherRuntime.get_active_display_name_key()
	var weather_name: String = Localization.t(name_key) if not str(name_key).is_empty() else "?"
	var weather_text: String = weather_name.to_upper()
	var cloud_ratio: float = clampf(WeatherRuntime.get_cloud_cover(), 0.0, 1.0)
	var cloud_percent: int = int(round(cloud_ratio * 100.0))
	var temperature_c: int = int(round(WeatherRuntime.get_temperature_c()))
	var humidity_percent: int = int(
		round(clampf(WeatherRuntime.get_humidity(), 0.0, 1.0) * 100.0),
	)
	var is_overcast: bool = cloud_ratio >= OVERCAST_RATIO
	if is_overcast != _is_overcast:
		_is_overcast = is_overcast
		_cloud_icon.set_glyph(HudIcons.Id.CLOUD if is_overcast else HudIcons.Id.SUN)

	var changed: bool = false
	if weather_text != _last_weather_text:
		_last_weather_text = weather_text
		_weather_label.text = weather_text
		changed = true
	if cloud_percent != _last_cloud_percent:
		_last_cloud_percent = cloud_percent
		_cloud_label.text = "%d%%" % cloud_percent
		changed = true
	if temperature_c != _last_temperature_c:
		_last_temperature_c = temperature_c
		var sign_prefix: String = "+" if temperature_c >= 0 else ""
		_temperature_label.text = "%s%d°C" % [sign_prefix, temperature_c]
		changed = true
	if humidity_percent != _last_humidity_percent:
		_last_humidity_percent = humidity_percent
		_humidity_label.text = "%d%%" % humidity_percent
		changed = true
	if changed:
		update_minimum_size()
