class_name PlayerExposureComponent
extends Node
## Per-player authority for wetness and cold exposure. V0 is warning-only:
## this component deliberately has no health, movement, oxygen, or death seam.

signal exposure_changed(wetness: float, cold_load: float)

const WeatherRuntimeScript = preload("res://core/autoloads/weather_runtime.gd")

@export var balance: PlayerExposureBalance = null

var _wetness: float = 0.0
var _cold_load: float = 0.0
var _tick_elapsed: float = 0.0
var _owner_body: Node2D = null
var _exposure_resolver: EnvironmentExposureResolver = null
var _life_support_powered: bool = false


static func from_player(player: Node) -> PlayerExposureComponent:
	if player == null:
		return null
	return player.get_node_or_null("ExposureComponent") as PlayerExposureComponent


func _ready() -> void:
	_owner_body = get_parent() as Node2D
	if balance == null or not balance.is_valid_balance() or _owner_body == null:
		push_error("PlayerExposureComponent requires a valid balance and Node2D parent")
		set_process(false)
		return
	if EventBus != null \
			and not EventBus.life_support_power_changed.is_connected(
				_on_life_support_power_changed,
			):
		EventBus.life_support_power_changed.connect(_on_life_support_power_changed)
	call_deferred("_resolve_boot_services")


func _process(delta: float) -> void:
	_tick_elapsed += maxf(delta, 0.0)
	if _tick_elapsed < balance.tick_interval_seconds:
		return
	var step_delta: float = _tick_elapsed
	_tick_elapsed = 0.0
	_advance_runtime(step_delta)


func get_wetness() -> float:
	return _wetness


func get_cold_load() -> float:
	return _cold_load


func get_wetness_visible_threshold() -> float:
	return balance.wetness_visible_threshold if balance != null else 1.0


func get_wetness_warning_threshold() -> float:
	return balance.wetness_warning_threshold if balance != null else 1.0


func get_wetness_critical_threshold() -> float:
	return balance.wetness_critical_threshold if balance != null else 1.0


func get_cold_visible_threshold() -> float:
	return balance.cold_visible_threshold if balance != null else 1.0


func get_cold_warning_threshold() -> float:
	return balance.cold_warning_threshold if balance != null else 1.0


func get_cold_critical_threshold() -> float:
	return balance.cold_critical_threshold if balance != null else 1.0


func is_wetness_visible() -> bool:
	return _wetness >= get_wetness_visible_threshold()


func is_wetness_warning() -> bool:
	return _wetness >= get_wetness_warning_threshold()


func is_cold_visible() -> bool:
	return _cold_load >= get_cold_visible_threshold()


func is_cold_warning() -> bool:
	return _cold_load >= get_cold_warning_threshold()


func save_state() -> Dictionary:
	return {
		"wetness": _wetness,
		"cold_load": _cold_load,
	}


func load_state(data: Dictionary) -> void:
	_set_state(
		_normalized_save_value(data.get("wetness", 0.0)),
		_normalized_save_value(data.get("cold_load", 0.0)),
	)


func _advance_runtime(delta: float) -> void:
	var open_sky: bool = false
	var building_indoor: bool = false
	if _exposure_resolver != null and is_instance_valid(_exposure_resolver):
		open_sky = _exposure_resolver.is_open_sky_at(_owner_body.global_position)
		building_indoor = _exposure_resolver.is_building_indoor_at(
			_owner_body.global_position,
		)
	var precipitation_kind: int = WeatherRuntimeScript.PrecipitationKind.NONE
	var rain_intensity: float = 0.0
	var air_temperature_c: float = balance.cold_safe_temperature_c
	if WeatherRuntime != null:
		precipitation_kind = int(WeatherRuntime.get_precipitation_kind())
		rain_intensity = clampf(WeatherRuntime.get_precipitation_intensity(), 0.0, 1.0)
		air_temperature_c = WeatherRuntime.get_temperature_c()
	var wind_strength: float = 0.0
	if WindRuntime != null:
		wind_strength = clampf(WindRuntime.get_wind_strength(), 0.0, 1.0)
	var next_state: Vector2 = calculate_next_state(
		balance,
		Vector2(_wetness, _cold_load),
		delta,
		precipitation_kind,
		rain_intensity,
		open_sky,
		building_indoor,
		_life_support_powered,
		air_temperature_c,
		wind_strength,
	)
	_set_state(next_state.x, next_state.y)


static func calculate_next_state(
		tuning: PlayerExposureBalance,
		current_state: Vector2,
		delta: float,
		precipitation_kind: int,
		precipitation_intensity: float,
		open_sky: bool,
		building_indoor: bool,
		life_support_powered: bool,
		air_temperature_c: float,
		wind_strength: float,
) -> Vector2:
	var wetness: float = clampf(current_state.x, 0.0, 1.0)
	var cold_load: float = clampf(current_state.y, 0.0, 1.0)
	if tuning == null or delta <= 0.0:
		return Vector2(wetness, cold_load)
	var powered_indoor: bool = building_indoor and life_support_powered
	var covered: bool = not open_sky
	if open_sky \
			and precipitation_kind == WeatherRuntimeScript.PrecipitationKind.RAIN \
			and precipitation_intensity > 0.0:
		wetness += (
			clampf(precipitation_intensity, 0.0, 1.0)
			* tuning.rain_wetness_rate_per_second
			* delta
		)
	elif powered_indoor:
		wetness -= tuning.dry_powered_indoor_rate_per_second * delta
	elif covered:
		wetness -= tuning.dry_covered_rate_per_second * delta
	else:
		wetness -= tuning.dry_open_rate_per_second * delta
	wetness = clampf(wetness, 0.0, 1.0)

	var base_temperature_c: float = (
		tuning.controlled_indoor_temperature_c
		if powered_indoor
		else air_temperature_c
	)
	var wind_chill_c: float = (
		clampf(wind_strength, 0.0, 1.0) * tuning.wind_chill_max_c
		if open_sky
		else 0.0
	)
	var wet_chill_c: float = wetness * tuning.wet_chill_max_c
	if covered:
		wet_chill_c *= tuning.covered_wet_chill_multiplier
	var effective_temperature_c: float = base_temperature_c - wind_chill_c - wet_chill_c
	var cold_target: float = clampf(
		inverse_lerp(
			tuning.cold_safe_temperature_c,
			tuning.cold_severe_temperature_c,
			effective_temperature_c,
		),
		0.0,
		1.0,
	)
	var cold_rate: float = (
		tuning.cold_accumulation_rate_per_second
		if cold_target > cold_load
		else tuning.warm_recovery_rate_per_second
	)
	cold_load = move_toward(cold_load, cold_target, cold_rate * delta)
	return Vector2(wetness, clampf(cold_load, 0.0, 1.0))


func _set_state(next_wetness: float, next_cold_load: float) -> void:
	var clamped_wetness: float = clampf(next_wetness, 0.0, 1.0)
	var clamped_cold_load: float = clampf(next_cold_load, 0.0, 1.0)
	if is_equal_approx(clamped_wetness, _wetness) \
			and is_equal_approx(clamped_cold_load, _cold_load):
		return
	_wetness = clamped_wetness
	_cold_load = clamped_cold_load
	exposure_changed.emit(_wetness, _cold_load)


func _resolve_boot_services() -> void:
	_exposure_resolver = get_tree().get_first_node_in_group(
		"environment_exposure_resolver",
	) as EnvironmentExposureResolver
	var life_support: Node = get_tree().get_first_node_in_group("life_support")
	if life_support != null and life_support.has_method("is_powered"):
		_life_support_powered = bool(life_support.call("is_powered"))


func _on_life_support_power_changed(is_powered: bool) -> void:
	_life_support_powered = is_powered


static func _normalized_save_value(value: Variant) -> float:
	if not (value is float or value is int):
		return 0.0
	var numeric_value: float = float(value)
	if not is_finite(numeric_value):
		return 0.0
	return clampf(numeric_value, 0.0, 1.0)
