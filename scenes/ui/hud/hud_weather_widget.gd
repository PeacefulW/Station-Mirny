class_name HudWeatherWidget
extends HudWidget
## Индикатор погоды: текущий режим + облачность в процентах. Источник —
## WeatherRuntime (владелец погоды). Обновляется по событию weather_changed и
## плавно по облачности.

const UPDATE_INTERVAL_SECONDS: float = 0.2
const OVERCAST_RATIO: float = 0.35

var _label: Label = null
var _icon: HudIcon = null
var _elapsed: float = 0.0
var _last_text: String = ""
var _is_overcast: bool = false


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
	_icon.configure(HudIcons.Id.SUN, 14.0, HudPalette.TEXT_SECONDARY, 1.3)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)

	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.language_changed.connect(_on_language_changed)
	_update_label()


func _on_weather_changed(_regime_id: StringName, _previous_regime_id: StringName) -> void:
	_update_label()


func _on_language_changed(_locale: String) -> void:
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
	var cloud_ratio: float = clampf(WeatherRuntime.get_cloud_cover(), 0.0, 1.0)
	var is_overcast: bool = cloud_ratio >= OVERCAST_RATIO
	if is_overcast != _is_overcast:
		_is_overcast = is_overcast
		_icon.set_glyph(HudIcons.Id.CLOUD if is_overcast else HudIcons.Id.SUN)
	# Название режима погоды — общий контентный ключ в обычном регистре.
	# Капс делаем здесь, чтобы строка встала в один ряд с остальным HUD и при
	# этом не менять текст для других поверхностей.
	var text: String = Localization.t(
		"UI_HUD_WEATHER",
		{
			"weather": weather_name,
			"cloud": int(round(cloud_ratio * 100.0)),
		},
	).to_upper()
	if text == _last_text:
		return
	_last_text = text
	_label.text = text
