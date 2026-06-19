class_name HudWeatherWidget
extends HudWidget
## Индикатор погоды: текущий режим (Ясно/Облачно/Пасмурно) + облачность в
## процентах. Источник — WeatherRuntime (владелец погоды). Обновляется по
## событию weather_changed и плавно по облачности.

const UPDATE_INTERVAL_SECONDS: float = 0.2

var _label: Label = null
var _elapsed: float = 0.0
var _last_text: String = ""


func _setup() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.52, 0.58, 0.62))
	add_child(_label)
	EventBus.weather_changed.connect(func(_r: StringName, _p: StringName) -> void: _update_label())
	EventBus.language_changed.connect(func(_locale: String) -> void: _update_label())
	_update_label()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL_SECONDS:
		return
	_elapsed = 0.0
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	var name_key: StringName = WeatherRuntime.get_active_display_name_key()
	var weather_name: String = Localization.t(name_key) if not str(name_key).is_empty() else "?"
	var cloud_pct: int = int(round(clampf(WeatherRuntime.get_cloud_cover(), 0.0, 1.0) * 100.0))
	var text: String = Localization.t(
		"UI_HUD_WEATHER",
		{
			"weather": weather_name,
			"cloud": cloud_pct,
		},
	)
	if text == _last_text:
		return
	_last_text = text
	_label.text = text
