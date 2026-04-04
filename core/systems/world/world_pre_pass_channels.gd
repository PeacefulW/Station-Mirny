class_name WorldPrePassChannels
extends RefCounted

var world_pos: Vector2i = Vector2i.ZERO
var canonical_world_pos: Vector2i = Vector2i.ZERO
var drainage: float = 0.0
var slope: float = 0.0
var rain_shadow: float = 0.0
var continentalness: float = 0.0

func clamp_fields() -> WorldPrePassChannels:
	drainage = clampf(drainage, 0.0, 1.0)
	slope = clampf(slope, 0.0, 1.0)
	rain_shadow = clampf(rain_shadow, 0.0, 1.0)
	continentalness = clampf(continentalness, 0.0, 1.0)
	return self