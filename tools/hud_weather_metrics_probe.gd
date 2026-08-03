extends SceneTree
## Static contract probe for the compact weather metrics. Standalone SceneTree
## scripts do not register project autoload identifiers for dependent scripts,
## so production compilation is verified separately through an editor parse.

const WIDGET_PATH: String = "res://scenes/ui/hud/hud_weather_widget.gd"
const ICONS_PATH: String = "res://scenes/ui/hud/hud_icons.gd"
const MANAGER_PATH: String = "res://scenes/ui/hud/hud_manager.gd"

var _failed: bool = false


func _init() -> void:
	var widget_source: String = FileAccess.get_file_as_string(WIDGET_PATH)
	var icons_source: String = FileAccess.get_file_as_string(ICONS_PATH)
	var manager_source: String = FileAccess.get_file_as_string(MANAGER_PATH)

	_assert(not widget_source.is_empty(), "Weather widget source must be readable.")
	_assert(not icons_source.is_empty(), "HUD icon source must be readable.")
	_assert(
		widget_source.contains("WeatherRuntime.get_temperature_c()")
		and widget_source.contains("WeatherRuntime.get_humidity()")
		and widget_source.contains("WeatherRuntime.get_cloud_cover()"),
		"Weather metrics must read all live values from WeatherRuntime.",
	)
	_assert(
		widget_source.contains("Localization.t(name_key)")
		and widget_source.contains("_weather_label.text = weather_text"),
		"Orientation line must preserve the localized active weather name.",
	)
	_assert(
		widget_source.contains("\"%s%d°C\"")
		and widget_source.count("\"%d%%\"") == 2,
		"Temperature and humidity must use compact numeric readouts without labels.",
	)
	_assert(
		not widget_source.contains("UI_HUD_WEATHER")
		and not widget_source.contains("PanelContainer")
		and not widget_source.contains("Tween")
		and not widget_source.contains("AnimationPlayer"),
		"Weather metrics must add no raw label, card or attention animation.",
	)

	_assert(
		widget_source.contains("TimeManager.get_season_display_name_key()")
		and widget_source.contains("Localization.t(season_key)")
		and widget_source.contains("TimeManager.get_day_in_season()")
		and widget_source.contains("TimeManager.get_season_length_days()"),
		"Season line must read the localized name and phase day from TimeManager.",
	)
	_assert(
		not widget_source.contains("\"Цветение\"")
		and not widget_source.contains("\"Bloom\"")
		and not widget_source.contains("SEASON_WARM"),
		"Season names must stay authored keys, never literal strings in the widget.",
	)
	_assert(
		widget_source.contains("OS.is_debug_build()")
		and widget_source.contains("get_time_scale()"),
		"Time-scale indicator must exist and be gated to debug builds.",
	)

	var weather_name_index: int = widget_source.find("\"WeatherName\"")
	var season_name_index: int = widget_source.find("\"SeasonName\"")
	var cloud_index: int = widget_source.find("\"CloudMetric\"")
	_assert(
		weather_name_index >= 0
		and weather_name_index < season_name_index
		and season_name_index < cloud_index,
		"Season line must sit between the weather name and the compact metric row.",
	)
	var temperature_index: int = widget_source.find("\"TemperatureMetric\"")
	var humidity_index: int = widget_source.find("\"HumidityMetric\"")
	_assert(
		cloud_index >= 0
		and cloud_index < temperature_index
		and temperature_index < humidity_index,
		"Compact metric order must be cloud, temperature, humidity.",
	)
	_assert(
		widget_source.contains("HBoxContainer.new()")
		and widget_source.contains("UPDATE_INTERVAL_SECONDS")
		and widget_source.contains("EventBus.weather_changed.connect"),
		"Metrics must reuse the compact row and existing refresh path.",
	)

	_assert(
		icons_source.contains("TEMPERATURE,")
		and icons_source.contains("HUMIDITY,")
		and icons_source.contains("_draw_temperature(canvas, rect, color, width)")
		and icons_source.contains("_draw_humidity(canvas, rect, color, width)"),
		"Temperature and humidity must use code-drawn HUD glyphs.",
	)
	var icons_script: Resource = load(ICONS_PATH)
	_assert(icons_script is Script, "HUD icon script must compile as a Script resource.")

	_assert(
		manager_source.contains("_top_right.add_child(HudWeatherWidget.new())")
		and manager_source.contains("_environment_panel.modulate"),
		"Weather widget must remain inside the dimmed environment panel.",
	)

	if _failed:
		quit(1)
		return
	print("hud_weather_metrics_probe: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
