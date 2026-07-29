class_name HudPalette
extends RefCounted
## Палитра и типографика HUD в одном месте.
## Виджеты не объявляют собственные оттенки: иначе набор показателей со временем
## расходится по стилю и HUD перестаёт читаться как один прибор.

# Стекло: тёплый почти-чёрный под цвет породы, а не синий "сай-фай" пластик.
# Полупрозрачность обязательна — мир должен просвечивать сквозь HUD.
const GLASS_INK: Color = Color(0.062, 0.054, 0.047, 0.47)
const GLASS_EDGE: Color = Color(0.90, 0.78, 0.58, 0.21)
const GLASS_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.32)
const GLASS_SHEEN: Color = Color(0.98, 0.93, 0.84, 0.075)
const GLASS_RAIL: Color = Color(0.86, 0.70, 0.48, 0.12)
const SEPARATOR: Color = Color(0.80, 0.66, 0.47, 0.30)

const TEXT_PRIMARY: Color = Color(0.94, 0.91, 0.84)
const TEXT_SECONDARY: Color = Color(0.71, 0.66, 0.58)
const TEXT_QUIET: Color = Color(0.49, 0.46, 0.41)
const TEXT_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.78)

const OXYGEN: Color = Color(0.42, 0.76, 0.82)
const STABLE: Color = Color(0.53, 0.73, 0.47)
const CAUTION: Color = Color(0.91, 0.64, 0.25)
const CRITICAL: Color = Color(0.89, 0.31, 0.23)
const EMBER: Color = Color(0.85, 0.47, 0.22)

const METER_TRACK: Color = Color(0.10, 0.09, 0.08, 0.88)
const METER_TRACK_EDGE: Color = Color(0.72, 0.62, 0.48, 0.20)

const PHASE_DAWN: Color = Color(0.94, 0.73, 0.46)
const PHASE_DAY: Color = Color(0.95, 0.89, 0.74)
const PHASE_DUSK: Color = Color(0.89, 0.53, 0.29)
const PHASE_NIGHT: Color = Color(0.57, 0.64, 0.81)

static var _display_font: FontVariation = null
static var _value_font: FontVariation = null
static var _label_font: FontVariation = null


## Крупные числа: время, проценты. Полужирный без трекинга.
static func display_font() -> FontVariation:
	if _display_font == null:
		_display_font = _make_font(0.55, 0)
	return _display_font


## Средние значения внутри строк показателей.
static func value_font() -> FontVariation:
	if _value_font == null:
		_value_font = _make_font(0.30, 0)
	return _value_font


## Подписи капслоком: разрядка делает мелкий текст читаемым поверх мира.
static func label_font() -> FontVariation:
	if _label_font == null:
		_label_font = _make_font(0.0, 1)
	return _label_font


## Цвет фазы суток. Используется и часами, и иконкой неба.
static func phase_color(phase: int) -> Color:
	match phase:
		0:
			return PHASE_DAWN
		2:
			return PHASE_DUSK
		3:
			return PHASE_NIGHT
		_:
			return PHASE_DAY


static func _make_font(embolden: float, tracking: int) -> FontVariation:
	var font: FontVariation = FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = embolden
	font.spacing_glyph = tracking
	return font
