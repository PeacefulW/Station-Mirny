class_name PlayerTorch
extends PointLight2D

# Player-carried torch light (visual, Iteration 1 of
# docs/02_system_specs/world/world_dynamic_lighting_2d.md). Generates its own soft
# radial texture so the scene needs no sub-resource. Constant-on for now; fuel /
# power gating is a later ADR-0005 gameplay concern, and cast shadows (occluders)
# are Iteration 2. This is visual only — no gameplay visibility authority here.

const ENERGY: float = 0.9
const RANGE_SCALE: float = 2.2
const LIGHT_COLOR: Color = Color(1.0, 0.78, 0.5)
const TEXTURE_SIZE: int = 512
## Dev-toggle: keycode for on/off. Off by default so the true (torch-less) day/night
## reads first; press to test the torch. A real fuel/power item is a later concern.
const TOGGLE_KEYCODE: int = KEY_F


func _ready() -> void:
	texture = _make_radial(TEXTURE_SIZE)
	color = LIGHT_COLOR
	energy = ENERGY
	texture_scale = RANGE_SCALE
	shadow_enabled = false
	enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == TOGGLE_KEYCODE:
			enabled = not enabled


func _make_radial(size_px: int) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size_px
	tex.height = size_px
	return tex
