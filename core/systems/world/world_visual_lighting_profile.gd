class_name WorldVisualLightingProfile
extends RefCounted

const HOURS_PER_DAY: float = 24.0
const DEFAULT_PREVIEW_HOUR: float = 10.0
const DEFAULT_LIGHT_ANGLE_DEG: float = 225.0
const DEFAULT_SHADOW_LENGTH_PX: float = 78.0
const DEFAULT_SHADOW_OPACITY: float = 0.0
const DEFAULT_SHADOW_SOFTNESS_PX: float = 24.0

const SHADOW_MIN_LENGTH_PX: float = 78.0
const SHADOW_MAX_LENGTH_PX: float = 360.0
const SHADOW_MIN_OPACITY: float = 0.512
const SHADOW_MAX_OPACITY: float = 1.0
const SHADOW_MIN_SOFTNESS_PX: float = 24.0
const SHADOW_MAX_SOFTNESS_PX: float = 78.0
const SHADOW_DUSK_FADE_START_HOUR: float = 17.0
const SHADOW_DUSK_FADE_END_HOUR: float = 21.0
const SHADOW_DAWN_FADE_START_HOUR: float = 4.0
const SHADOW_DAWN_FADE_END_HOUR: float = 7.0
const TERRAIN_EDGE_SHADOW_OPACITY_SCALE: float = 0.30

const LIGHT_ANGLE_EPSILON_DEG: float = 0.05
const SHADOW_LENGTH_EPSILON_PX: float = 0.05
const SHADOW_OPACITY_EPSILON: float = 0.002
const SHADOW_SOFTNESS_EPSILON_PX: float = 0.05

static func sun_progress_for_hour(hour: float) -> float:
	return fposmod(hour / HOURS_PER_DAY + 0.5, 1.0)

static func light_angle_deg_for_sun_progress(_sun_progress: float) -> float:
	# Art direction keeps the sun north-west and the cast-shadow axis
	# south-east; time of day changes energy, colour and length, not azimuth.
	return DEFAULT_LIGHT_ANGLE_DEG

static func light_angle_deg_for_hour(hour: float) -> float:
	return light_angle_deg_for_sun_progress(sun_progress_for_hour(hour))

static func shadow_direction_for_light_angle_deg(light_angle_deg: float) -> Vector2:
	var shadow_angle_rad: float = deg_to_rad(light_angle_deg + 180.0)
	return Vector2(cos(shadow_angle_rad), sin(shadow_angle_rad)).normalized()

static func low_sun_for_progress(sun_progress: float) -> float:
	var elevation: float = maxf(cos(sun_progress * TAU), 0.0)
	return pow(1.0 - clampf(elevation, 0.0, 1.0), 0.72)

static func shadow_visibility_for_hour(hour: float) -> float:
	var wrapped_hour: float = fposmod(hour, HOURS_PER_DAY)
	if wrapped_hour >= SHADOW_DUSK_FADE_START_HOUR and wrapped_hour < SHADOW_DUSK_FADE_END_HOUR:
		return 1.0 - smoothstep_float(SHADOW_DUSK_FADE_START_HOUR, SHADOW_DUSK_FADE_END_HOUR, wrapped_hour)
	if wrapped_hour >= SHADOW_DAWN_FADE_START_HOUR and wrapped_hour < SHADOW_DAWN_FADE_END_HOUR:
		return smoothstep_float(SHADOW_DAWN_FADE_START_HOUR, SHADOW_DAWN_FADE_END_HOUR, wrapped_hour)
	if wrapped_hour >= SHADOW_DAWN_FADE_END_HOUR and wrapped_hour < SHADOW_DUSK_FADE_START_HOUR:
		return 1.0
	return 0.0

static func shadow_length_px_for_low_sun(low_sun: float) -> float:
	return lerpf(SHADOW_MIN_LENGTH_PX, SHADOW_MAX_LENGTH_PX, clampf(low_sun, 0.0, 1.0))

static func shadow_opacity_for_low_sun_and_hour(low_sun: float, hour: float) -> float:
	return lerpf(SHADOW_MIN_OPACITY, SHADOW_MAX_OPACITY, clampf(low_sun, 0.0, 1.0)) \
		* shadow_visibility_for_hour(hour)

static func shadow_softness_px_for_low_sun(low_sun: float) -> float:
	return lerpf(SHADOW_MIN_SOFTNESS_PX, SHADOW_MAX_SOFTNESS_PX, clampf(low_sun, 0.0, 1.0))

static func smoothstep_float(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
