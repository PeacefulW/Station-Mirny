class_name WorldPostProcessOverlay
extends ColorRect
## Client-local presentation response (ADR-0007 layer 4): one bounded
## screen-space pass below HUD. It does not own gameplay light or visibility.

signal postprocess_enabled_changed(enabled: bool)

const POSTPROCESS_SHADER: Shader = preload("res://assets/shaders/world_postprocess_overlay.gdshader")

@export var effect_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var grade_strength: float = 0.14
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.16
@export_range(0.0, 1.0, 0.01) var edge_shadow_strength: float = 0.10
@export_range(0.0, 1.0, 0.005) var warm_bloom_strength: float = 0.055

var _shader_material: ShaderMaterial = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = POSTPROCESS_SHADER
	material = _shader_material
	_apply_shader_parameters()
	set_postprocess_enabled(effect_enabled)


func set_postprocess_enabled(enabled: bool) -> void:
	var changed: bool = effect_enabled != enabled
	effect_enabled = enabled
	visible = enabled
	if _shader_material != null:
		_shader_material.set_shader_parameter("effect_enabled", enabled)
	if changed:
		postprocess_enabled_changed.emit(enabled)


func toggle_postprocess() -> bool:
	set_postprocess_enabled(not effect_enabled)
	return effect_enabled


func get_postprocess_enabled() -> bool:
	return effect_enabled


func _apply_shader_parameters() -> void:
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("effect_enabled", effect_enabled)
	_shader_material.set_shader_parameter("grade_strength", grade_strength)
	_shader_material.set_shader_parameter("vignette_strength", vignette_strength)
	_shader_material.set_shader_parameter("edge_shadow_strength", edge_shadow_strength)
	_shader_material.set_shader_parameter("warm_bloom_strength", warm_bloom_strength)
