class_name PlayerExposureBalance
extends Resource
## Data-authored tuning for player wetness and cold exposure.
## The V0 component only reports warning state; it never applies damage or
## movement penalties.

@export_group("Identity")
@export var id: StringName = &"core:player_exposure"

@export_group("Cadence")
@export_range(0.05, 1.0, 0.05) var tick_interval_seconds: float = 0.25

@export_group("Wetness per second")
@export_range(0.0, 1.0, 0.001) var rain_wetness_rate_per_second: float = 0.026
@export_range(0.0, 1.0, 0.001) var dry_open_rate_per_second: float = 0.002
@export_range(0.0, 1.0, 0.001) var dry_covered_rate_per_second: float = 0.008
@export_range(0.0, 1.0, 0.001) var dry_powered_indoor_rate_per_second: float = 0.024

@export_group("Effective temperature")
@export_range(-60.0, 60.0, 0.5) var controlled_indoor_temperature_c: float = 20.0
@export_range(0.0, 40.0, 0.5) var wind_chill_max_c: float = 8.0
@export_range(0.0, 40.0, 0.5) var wet_chill_max_c: float = 12.0
@export_range(0.0, 1.0, 0.05) var covered_wet_chill_multiplier: float = 0.35
@export_range(-40.0, 30.0, 0.5) var cold_safe_temperature_c: float = 8.0
@export_range(-60.0, 10.0, 0.5) var cold_severe_temperature_c: float = -14.0
@export_range(0.0, 1.0, 0.01) var cold_accumulation_rate_per_second: float = 0.08
@export_range(0.0, 1.0, 0.01) var warm_recovery_rate_per_second: float = 0.14

@export_group("HUD thresholds")
@export_range(0.0, 1.0, 0.01) var wetness_visible_threshold: float = 0.10
@export_range(0.0, 1.0, 0.01) var wetness_warning_threshold: float = 0.45
@export_range(0.0, 1.0, 0.01) var wetness_critical_threshold: float = 0.80
@export_range(0.0, 1.0, 0.01) var cold_visible_threshold: float = 0.12
@export_range(0.0, 1.0, 0.01) var cold_warning_threshold: float = 0.45
@export_range(0.0, 1.0, 0.01) var cold_critical_threshold: float = 0.80


func is_valid_balance() -> bool:
	if str(id).is_empty() or not _in_range(tick_interval_seconds, 0.05, 1.0):
		return false
	var normalized_rates: Array[float] = [
		rain_wetness_rate_per_second,
		dry_open_rate_per_second,
		dry_covered_rate_per_second,
		dry_powered_indoor_rate_per_second,
		cold_accumulation_rate_per_second,
		warm_recovery_rate_per_second,
	]
	for value: float in normalized_rates:
		if not _in_range(value, 0.0, 1.0):
			return false
	if dry_open_rate_per_second > dry_covered_rate_per_second \
			or dry_covered_rate_per_second > dry_powered_indoor_rate_per_second:
		return false
	if not _in_range(controlled_indoor_temperature_c, -60.0, 60.0) \
			or not _in_range(wind_chill_max_c, 0.0, 40.0) \
			or not _in_range(wet_chill_max_c, 0.0, 40.0) \
			or not _in_range(covered_wet_chill_multiplier, 0.0, 1.0) \
			or not _in_range(cold_safe_temperature_c, -40.0, 30.0) \
			or not _in_range(cold_severe_temperature_c, -60.0, 10.0):
		return false
	if cold_safe_temperature_c <= cold_severe_temperature_c:
		return false
	return _valid_thresholds(
		wetness_visible_threshold,
		wetness_warning_threshold,
		wetness_critical_threshold,
	) and _valid_thresholds(
		cold_visible_threshold,
		cold_warning_threshold,
		cold_critical_threshold,
	)


static func _valid_thresholds(visible_at: float, warning_at: float, critical_at: float) -> bool:
	return (
		is_finite(visible_at)
		and is_finite(warning_at)
		and is_finite(critical_at)
		and visible_at >= 0.0
		and visible_at < warning_at
		and warning_at < critical_at
		and critical_at <= 1.0
	)


static func _in_range(value: float, minimum: float, maximum: float) -> bool:
	return is_finite(value) and value >= minimum and value <= maximum
