class_name WeatherPresentationCurves
extends RefCounted
## Pure response curves for weather presentation. WeatherRuntime owns cloud_cover;
## visual layers interpret it through these curves without becoming weather owners.


static func broken_cloud_strength(cloud_cover: float) -> float:
	var cover: float = clampf(cloud_cover, 0.0, 1.0)
	return _smoothstep(0.15, 0.40, cover) * (1.0 - _smoothstep(0.62, 0.88, cover))


static func deck_strength(cloud_cover: float) -> float:
	return _smoothstep(0.30, 0.95, clampf(cloud_cover, 0.0, 1.0))


static func flatten_strength(cloud_cover: float) -> float:
	return _smoothstep(0.62, 1.0, clampf(cloud_cover, 0.0, 1.0))


static func sun_ray_strength(cloud_cover: float) -> float:
	var cover: float = clampf(cloud_cover, 0.0, 1.0)
	return broken_cloud_strength(cover) * (1.0 - _smoothstep(0.56, 0.70, cover))


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
