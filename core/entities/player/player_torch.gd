class_name PlayerTorch
extends PointLight2D

# Player-carried torch light (visual, docs/02_system_specs/world/world_dynamic_lighting_2d.md).
# Generates its own soft radial texture so the scene needs no sub-resource.
# Constant-on for now; fuel / power gating is a later ADR-0005 gameplay concern.
# Mountain blocking is handled by MountainTorchShadowField, a world-space shader
# overlay that reads the native mountain mask. The PointLight2D itself stays a
# simple warm pool; it does not use engine shadow maps. This is visual only — no
# gameplay visibility authority here.

const ENERGY: float = 0.9
const RANGE_SCALE: float = 1.1
const LIGHT_HEIGHT: float = 140.0
const LIGHT_COLOR: Color = Color(1.0, 0.78, 0.5)
const TEXTURE_SIZE: int = 1024
## Dev-toggle: keycode for on/off. Off by default so the true (torch-less) day/night
## reads first; press to test the torch. A real fuel/power item is a later concern.
const TOGGLE_KEYCODE: int = KEY_F

static var _cached_radial_texture: Texture2D = null


func _ready() -> void:
	texture = _make_radial(TEXTURE_SIZE)
	color = LIGHT_COLOR
	energy = ENERGY
	texture_scale = RANGE_SCALE
	height = LIGHT_HEIGHT
	shadow_enabled = false
	enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == TOGGLE_KEYCODE:
			enabled = not enabled


func _make_radial(size_px: int) -> Texture2D:
	if _cached_radial_texture != null and _cached_radial_texture.get_width() == size_px:
		return _cached_radial_texture
	var image := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size_px - 1), float(size_px - 1)) * 0.5
	var radius: float = maxf(float(size_px) * 0.5, 1.0)
	for y: int in range(size_px):
		for x: int in range(size_px):
			var uv := Vector2(float(x), float(y))
			var r: float = clampf(uv.distance_to(center) / radius, 0.0, 1.0)
			var falloff: float = 1.0 - r
			var alpha: float = falloff * falloff * (3.0 - 2.0 * falloff)
			var dither_gate: float = smoothstep(0.02, 0.16, alpha) * (1.0 - smoothstep(0.86, 0.99, alpha))
			alpha = clampf(alpha + _radial_dither(x, y) * dither_gate, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_cached_radial_texture = ImageTexture.create_from_image(image)
	return _cached_radial_texture


static func _radial_dither(x: int, y: int) -> float:
	var n: int = (x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return (float(n & 255) / 255.0 - 0.5) / 255.0
