class_name WorldVisualWindProfile
extends RefCounted
## Авторский профиль поведения ветра (environment runtime, ADR-0007 layer 3).
## Чистые функции от накопленного wind_time; без аллокаций на кадр.
## Контракт: docs/02_system_specs/world/wind_and_grass_scatter_presentation.md

const BASE_STRENGTH: float = 0.46
const GUST_STRENGTH_SPAN: Vector2 = Vector2(0.15, 0.95)
const GUST_DRIFT_PERIOD_S: float = 9.0
const DIRECTION_BASE_DEG: float = -13.0
const DIRECTION_DRIFT_DEG: float = 14.0
const DIRECTION_DRIFT_PERIOD_S: float = 53.0
const GUST_FIELD_SCALE_PX: float = 420.0
const GUST_FIELD_ANISOTROPY: float = 2.6
const GUST_SCROLL_SPEED_PX_PER_S: float = 150.0
## Сила ветра меняет ТЕМП анимации и скорость фронтов, не размах травы:
## темп хода wind_time и множитель скорости скролла по силе 0..1.
const WIND_ANIM_RATE_SPAN: Vector2 = Vector2(0.6, 3.4)
const GUST_SCROLL_SPEED_STRENGTH_SPAN: Vector2 = Vector2(0.45, 2.4)


## Два несоизмеримых синуса дают апериодичный дрейф [-1..1]:
## сила ветра «дышит» без видимого повтора цикла.
static func strength_drift_for_time(wind_time: float) -> float:
	return sin(wind_time * TAU / GUST_DRIFT_PERIOD_S) * 0.62 \
			+ sin(wind_time * TAU / (GUST_DRIFT_PERIOD_S * 0.371) + 1.7) * 0.38


static func strength_for_time(wind_time: float) -> float:
	var half_span: float = (GUST_STRENGTH_SPAN.y - GUST_STRENGTH_SPAN.x) * 0.5
	return clampf(
		BASE_STRENGTH + strength_drift_for_time(wind_time) * half_span,
		GUST_STRENGTH_SPAN.x,
		GUST_STRENGTH_SPAN.y,
	)


static func direction_deg_for_time(wind_time: float) -> float:
	var drift: float = sin(wind_time * TAU / DIRECTION_DRIFT_PERIOD_S) * 0.71 \
			+ sin(wind_time * TAU / (DIRECTION_DRIFT_PERIOD_S * 0.413) + 0.9) * 0.29
	return DIRECTION_BASE_DEG + DIRECTION_DRIFT_DEG * drift


static func direction_for_time(wind_time: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(direction_deg_for_time(wind_time)))


static func anim_rate_for_strength(strength: float) -> float:
	return lerpf(WIND_ANIM_RATE_SPAN.x, WIND_ANIM_RATE_SPAN.y, clampf(strength, 0.0, 1.0))


static func scroll_speed_px_per_s_for_strength(strength: float) -> float:
	return GUST_SCROLL_SPEED_PX_PER_S * lerpf(
		GUST_SCROLL_SPEED_STRENGTH_SPAN.x,
		GUST_SCROLL_SPEED_STRENGTH_SPAN.y,
		clampf(strength, 0.0, 1.0),
	)
