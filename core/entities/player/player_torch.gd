class_name PlayerTorch
extends PointLight2D

# Player-carried torch light (visual, docs/02_system_specs/world/world_dynamic_lighting_2d.md).
# Generates its own soft radial texture so the scene needs no sub-resource.
# Constant-on for now; fuel / power gating is a later ADR-0005 gameplay concern.
# Iteration 2 (cast shadows): the torch casts engine PointLight2D shadows from
# LightOccluder2D nodes built by ChunkView from the mountain solid contour. Those
# occluders block the torch on ground/open terrain. The mountain mask shader itself
# gates point-light contribution to facade pixels only, because applying the engine
# shadow texture directly to the large mountain sprite produced visible line/square
# bands. This is visual only — no gameplay visibility authority here.

const ENERGY: float = 0.9
const RANGE_SCALE: float = 2.2
const LIGHT_HEIGHT: float = 140.0
const LIGHT_COLOR: Color = Color(1.0, 0.78, 0.5)
const TEXTURE_SIZE: int = 512
## Dev-toggle: keycode for on/off. Off by default so the true (torch-less) day/night
## reads first; press to test the torch. A real fuel/power item is a later concern.
const TOGGLE_KEYCODE: int = KEY_F
## Occluder cull layer for torch shadows. Mountain LightOccluder2D nodes use the
## same layer so ONLY the torch (not the sun, whose shadow cull is a separate
## reserved layer) casts shadows from mountain geometry.
const MOUNTAIN_OCCLUDER_LIGHT_LAYER: int = 1


func _ready() -> void:
	texture = _make_radial(TEXTURE_SIZE)
	color = LIGHT_COLOR
	energy = ENERGY
	texture_scale = RANGE_SCALE
	height = LIGHT_HEIGHT
	# Engine radial shadows: the mountain occluders block the pool so light does
	# not pass through walls or bend around corners (incl. runtime-dug geometry).
	shadow_enabled = true
	shadow_filter = Light2D.SHADOW_FILTER_PCF13
	# PCF softens the ground/open-terrain shadow edge. Mountain pixels do not rely
	# on this shadow texture; their point-light acceptance is shader-gated.
	shadow_filter_smooth = 9.0
	shadow_item_cull_mask = MOUNTAIN_OCCLUDER_LIGHT_LAYER
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
