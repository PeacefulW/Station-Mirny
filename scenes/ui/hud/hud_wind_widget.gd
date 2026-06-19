class_name HudWindWidget
extends HudWidget
## Индикатор ветра: сила в процентах + стрелка направления. Источник —
## WindRuntime (один владелец состояния ветра). Дублирует визуальный
## спидометр летящей пыли точным числом.

const UPDATE_INTERVAL_SECONDS: float = 0.12
const ARROWS: PackedStringArray = ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]

var _label: Label = null
var _elapsed: float = 0.0
var _last_strength_bucket: int = -1
var _last_arrow_index: int = -1


func _setup() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.52, 0.58, 0.62))
	add_child(_label)
	EventBus.language_changed.connect(
		func(_locale: String) -> void:
			_last_strength_bucket = -1
			_update_label()
	)
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
	var strength: float = clampf(WindRuntime.get_wind_strength(), 0.0, 1.0)
	var strength_pct: int = int(round(strength * 100.0))
	var arrow_index: int = posmod(
		int(round(WindRuntime.get_wind_direction_deg() / 45.0)),
		ARROWS.size(),
	)
	# Перерисовываем только при заметной смене, чтобы не дёргать локализацию.
	if strength_pct == _last_strength_bucket and arrow_index == _last_arrow_index:
		return
	_last_strength_bucket = strength_pct
	_last_arrow_index = arrow_index
	_label.text = Localization.t(
		"UI_HUD_WIND",
		{
			"strength": strength_pct,
			"arrow": ARROWS[arrow_index],
		},
	)
