class_name WaterPresentationProfile
extends Resource

@export_group("Identity")
@export var id: StringName = &""

@export_group("Floodplain Bands")
@export_range(0, 255, 1) var far_strength_min: int = 96
@export_range(0, 255, 1) var near_strength_min: int = 192
@export_range(0, 255, 1) var max_strength: int = 255

@export_group("Floodplain Overlay")
@export var far_color: Color = Color(0.23, 0.38, 0.22, 0.10)
@export var near_color: Color = Color(0.20, 0.43, 0.30, 0.24)
@export var peak_color: Color = Color(0.18, 0.46, 0.34, 0.32)

func is_valid_profile() -> bool:
	return not str(id).is_empty() \
			and far_strength_min >= 0 \
			and far_strength_min < near_strength_min \
			and near_strength_min <= max_strength \
			and max_strength <= 255 \
			and _is_alpha_valid(far_color) \
			and _is_alpha_valid(near_color) \
			and _is_alpha_valid(peak_color)

func get_floodplain_overlay_color(
	strength: int,
	has_far_flag: bool,
	has_near_flag: bool
) -> Color:
	var clamped_strength: int = clampi(strength, 0, max_strength)
	if has_near_flag and clamped_strength >= near_strength_min:
		return near_color.lerp(peak_color, _band_t(clamped_strength, near_strength_min, max_strength))
	if has_far_flag and clamped_strength >= far_strength_min and clamped_strength < near_strength_min:
		return far_color.lerp(near_color, _band_t(clamped_strength, far_strength_min, near_strength_min - 1))
	return Color.TRANSPARENT

func _band_t(value: int, min_value: int, max_value: int) -> float:
	if max_value <= min_value:
		return 1.0
	return clampf((float(value) - float(min_value)) / (float(max_value) - float(min_value)), 0.0, 1.0)

func _is_alpha_valid(color: Color) -> bool:
	return color.a >= 0.0 and color.a <= 1.0
