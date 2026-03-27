class_name WorldStructureContext
extends RefCounted

var world_pos: Vector2i = Vector2i.ZERO
var canonical_world_pos: Vector2i = Vector2i.ZERO
var ridge_strength: float = 0.0
var mountain_mass: float = 0.0
var river_strength: float = 0.0
var floodplain_strength: float = 0.0

func clamp_fields() -> WorldStructureContext:
	ridge_strength = clampf(ridge_strength, 0.0, 1.0)
	mountain_mass = clampf(mountain_mass, 0.0, 1.0)
	river_strength = clampf(river_strength, 0.0, 1.0)
	floodplain_strength = clampf(floodplain_strength, 0.0, 1.0)
	return self

func is_ridge_core(threshold: float = 0.66) -> bool:
	return ridge_strength >= threshold

func is_river_core(threshold: float = 0.66) -> bool:
	return river_strength >= threshold

func has_floodplain(threshold: float = 0.45) -> bool:
	return floodplain_strength >= threshold
