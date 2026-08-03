class_name RainOverlay
extends WorldViewOverlay
## One view-bounded rain pass. WeatherRuntime owns rain truth; this layer only
## reads kind/intensity and suppresses presentation outside an open-sky context.

const RAIN_SHADER: Shader = preload("res://assets/shaders/rain_overlay.gdshader")
const WeatherRuntimeScript = preload("res://core/autoloads/weather_runtime.gd")
const RAIN_Z_INDEX: int = 405
const MIN_VISIBLE_INTENSITY: float = 0.002
## Shader fall speeds travel an exact periodic cell field over this interval,
## so wrapping client-local animation time cannot produce a visual jump.
const RAIN_TIME_PERIOD_SECONDS: float = 16.0

var _exposure_resolver: EnvironmentExposureResolver = null
var _rain_time_seconds: float = 0.0


func _ready() -> void:
	visible = false
	super._ready()
	call_deferred("_resolve_exposure_resolver")


func _process(delta: float) -> void:
	_rain_time_seconds = fposmod(
		_rain_time_seconds + maxf(delta, 0.0),
		RAIN_TIME_PERIOD_SECONDS,
	)
	super._process(delta)


func _overlay_shader() -> Shader:
	return RAIN_SHADER


func _overlay_z() -> int:
	return RAIN_Z_INDEX


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	var intensity: float = 0.0
	if _has_open_sky_context() and WeatherRuntime != null:
		var precipitation_kind: int = int(WeatherRuntime.get_precipitation_kind())
		if precipitation_kind == WeatherRuntimeScript.PrecipitationKind.RAIN:
			intensity = clampf(WeatherRuntime.get_precipitation_intensity(), 0.0, 1.0)
	visible = intensity > MIN_VISIBLE_INTENSITY
	overlay_material.set_shader_parameter("rain_intensity", intensity)
	overlay_material.set_shader_parameter("rain_time_seconds", _rain_time_seconds)


func _has_open_sky_context() -> bool:
	return (
		_exposure_resolver != null
		and is_instance_valid(_exposure_resolver)
		and _exposure_resolver.is_open_sky_at(_local_player_position())
	)


func _local_player_position() -> Vector2:
	if PlayerAuthority != null and PlayerAuthority.has_method("get_local_player_position"):
		return PlayerAuthority.get_local_player_position()
	return Vector2.ZERO


func _resolve_exposure_resolver() -> void:
	_exposure_resolver = get_tree().get_first_node_in_group(
		"environment_exposure_resolver",
	) as EnvironmentExposureResolver
