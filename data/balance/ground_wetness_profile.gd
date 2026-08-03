class_name GroundWetnessProfile
extends Resource
## Authored tuning for the transient shared-material wet-ground response.
## It is presentation-only and never becomes terrain or save state.

@export_group("Identity and cadence")
@export var id: StringName = &"core:ground_wetness"
@export_range(0.05, 1.0, 0.05) var update_interval_seconds: float = 0.10
@export_range(0.0, 1.0, 0.001) var accumulation_rate_per_second: float = 0.075
@export_range(0.0, 1.0, 0.001) var drying_rate_per_second: float = 0.005

@export_group("Wet mask")
@export_range(0.1, 4.0, 0.05) var basin_contrast: float = 1.50
@export_range(0.0, 1.0, 0.05) var grass_wetness_floor: float = 0.32
@export_range(0.0, 1.0, 0.01) var puddle_threshold: float = 0.56
@export_range(0.0, 1.0, 0.01) var wet_darkening: float = 0.32
@export_range(0.0, 1.0, 0.01) var wet_desaturation: float = 0.22
@export var puddle_tint: Color = Color(0.12, 0.19, 0.21, 1.0)
@export_range(0.0, 1.0, 0.01) var puddle_opacity: float = 0.48

@export_group("Drop impacts")
@export_range(24.0, 160.0, 1.0) var impact_cell_size_px: float = 72.0
@export_range(0.25, 4.0, 0.05) var impact_ring_width: float = 1.45
@export_range(0.2, 2.0, 0.05) var impact_lifetime_seconds: float = 0.78
@export_range(0.0, 1.0, 0.01) var impact_density: float = 0.52


func is_valid_profile() -> bool:
	if str(id).is_empty():
		return false
	if not _in_range(update_interval_seconds, 0.05, 1.0) \
			or not _in_range(accumulation_rate_per_second, 0.0, 1.0) \
			or not _in_range(drying_rate_per_second, 0.0, 1.0) \
			or not _in_range(basin_contrast, 0.1, 4.0) \
			or not _in_range(impact_cell_size_px, 24.0, 160.0) \
			or not _in_range(impact_ring_width, 0.25, 4.0) \
			or not _in_range(impact_lifetime_seconds, 0.2, 2.0):
		return false
	var normalized_values: Array[float] = [
		grass_wetness_floor,
		puddle_threshold,
		wet_darkening,
		wet_desaturation,
		puddle_opacity,
		impact_density,
	]
	for value: float in normalized_values:
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return false
	return (
		is_finite(puddle_tint.r)
		and is_finite(puddle_tint.g)
		and is_finite(puddle_tint.b)
		and is_finite(puddle_tint.a)
	)


static func _in_range(value: float, minimum: float, maximum: float) -> bool:
	return is_finite(value) and value >= minimum and value <= maximum
