class_name Mountain2DLightProbe
extends Node2D

const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const SUN_ENERGY: float = 1.25
const SUN_ROTATION_DEGREES: float = WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG
const AMBIENT_COLOR: Color = Color(0.34, 0.31, 0.27, 1.0)
const SUN_COLOR: Color = Color(1.0, 0.84, 0.58, 1.0)

var _canvas_modulate: CanvasModulate = null
var _sun_light: DirectionalLight2D = null
var _enabled: bool = false

func _ready() -> void:
	_ensure_nodes()
	set_light_mode_enabled(_enabled)

func set_light_mode_enabled(enabled: bool) -> void:
	_enabled = enabled
	_ensure_nodes()
	_canvas_modulate.visible = _enabled
	_sun_light.enabled = _enabled
	_sun_light.visible = _enabled

func is_light_mode_enabled() -> bool:
	return _enabled

func set_light_position(world_position: Vector2) -> void:
	_ensure_nodes()
	# Directional sun is infinite; this keeps the old probe API without moving a local light.

func get_debug_snapshot() -> Dictionary:
	return {
		"enabled": _enabled,
		"node_ready": _sun_light != null and is_instance_valid(_sun_light),
		"kind": "directional_sun",
		"shadow_enabled": _sun_light.shadow_enabled if _sun_light != null and is_instance_valid(_sun_light) else false,
		"uses_light_texture": false,
		"sun_angle_degrees": rad_to_deg(_sun_light.rotation) if _sun_light != null and is_instance_valid(_sun_light) else SUN_ROTATION_DEGREES,
	}

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
			return
		_sun_light.rotation = (get_global_mouse_position() - global_position).angle()

func _ensure_nodes() -> void:
	if _canvas_modulate == null or not is_instance_valid(_canvas_modulate):
		_canvas_modulate = CanvasModulate.new()
		_canvas_modulate.name = "Mountain2DLightCanvasModulate"
		_canvas_modulate.color = AMBIENT_COLOR
		add_child(_canvas_modulate)
	if _sun_light == null or not is_instance_valid(_sun_light):
		_sun_light = DirectionalLight2D.new()
		_sun_light.name = "Mountain2DSunLight"
		_sun_light.energy = SUN_ENERGY
		_sun_light.color = SUN_COLOR
		_sun_light.rotation = deg_to_rad(SUN_ROTATION_DEGREES)
		_sun_light.shadow_enabled = true
		add_child(_sun_light)
