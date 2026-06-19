class_name WorldVisualWindProfile
extends RefCounted
## Форма порывов ветра для шейдеров (environment runtime, ADR-0007 layer 3).
## Силу и направление ветра задаёт WeatherRuntime; этот профиль отвечает
## только за ШЕЙП порывов: масштаб/анизотропию gust-поля и как сила ветра
## ускоряет темп анимации и бег фронтов. Чистые функции, без аллокаций.
## Контракт: docs/02_system_specs/world/wind_and_grass_scatter_presentation.md

const GUST_FIELD_SCALE_PX: float = 420.0
const GUST_FIELD_ANISOTROPY: float = 2.6
const GUST_SCROLL_SPEED_PX_PER_S: float = 150.0
## Сила ветра меняет ТЕМП анимации и скорость фронтов, не размах травы:
## темп хода wind_time и множитель скорости скролла по силе 0..1.
const WIND_ANIM_RATE_SPAN: Vector2 = Vector2(0.6, 3.4)
const GUST_SCROLL_SPEED_STRENGTH_SPAN: Vector2 = Vector2(0.45, 2.4)


static func anim_rate_for_strength(strength: float) -> float:
	return lerpf(WIND_ANIM_RATE_SPAN.x, WIND_ANIM_RATE_SPAN.y, clampf(strength, 0.0, 1.0))


static func scroll_speed_px_per_s_for_strength(strength: float) -> float:
	return GUST_SCROLL_SPEED_PX_PER_S * lerpf(
		GUST_SCROLL_SPEED_STRENGTH_SPAN.x,
		GUST_SCROLL_SPEED_STRENGTH_SPAN.y,
		clampf(strength, 0.0, 1.0),
	)
