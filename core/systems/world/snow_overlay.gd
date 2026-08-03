class_name SnowOverlay
extends WorldViewOverlay
## One view-bounded snow pass, mirroring RainOverlay. WeatherRuntime owns
## precipitation truth; this layer only reads intensity and the presentation
## cross-fade weight, and suppresses itself outside an open-sky context.
## Контракт: docs/02_system_specs/world/snow_precipitation_runtime.md

const SNOW_SHADER: Shader = preload("res://assets/shaders/snow_overlay.gdshader")
const WeatherRuntimeScript = preload("res://core/autoloads/weather_runtime.gd")
const SNOW_Z_INDEX: int = 405
const MIN_VISIBLE_INTENSITY: float = 0.002
## Shader fall/sway speeds travel an exact periodic cell field over this
## interval, so wrapping client-local animation time cannot produce a jump.
## Snow falls far slower than rain, so its period is correspondingly longer.
const SNOW_TIME_PERIOD_SECONDS: float = 128.0

var _exposure_resolver: EnvironmentExposureResolver = null
var _snow_time_seconds: float = 0.0


func _ready() -> void:
	visible = false
	super._ready()
	call_deferred("_resolve_exposure_resolver")


func _process(delta: float) -> void:
	_snow_time_seconds = fposmod(
		_snow_time_seconds + maxf(delta, 0.0),
		SNOW_TIME_PERIOD_SECONDS,
	)
	super._process(delta)


func _overlay_shader() -> Shader:
	return SNOW_SHADER


func _overlay_z() -> int:
	return SNOW_Z_INDEX


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	var intensity: float = 0.0
	if _has_open_sky_context() and WeatherRuntime != null:
		var precipitation_kind: int = int(WeatherRuntime.get_precipitation_kind())
		# Гейт по "осадки есть", а не по конкретному виду: вес кросс-фейда сам
		# разводит дождь и снег. Гейт по kind == SNOW обнулял бы слой рывком
		# ровно на пересечении порога — то есть возвращал бы тот самый скачок,
		# ради устранения которого полоса и существует.
		if precipitation_kind != WeatherRuntimeScript.PrecipitationKind.NONE:
			intensity = (
				clampf(WeatherRuntime.get_precipitation_intensity(), 0.0, 1.0)
				* clampf(WeatherRuntime.get_snow_presentation_weight(), 0.0, 1.0)
			)
	visible = intensity > MIN_VISIBLE_INTENSITY
	overlay_material.set_shader_parameter("snow_intensity", intensity)
	overlay_material.set_shader_parameter("snow_time_seconds", _snow_time_seconds)


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
