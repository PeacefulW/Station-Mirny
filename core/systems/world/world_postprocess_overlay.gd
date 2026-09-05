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
var _last_render_target_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = POSTPROCESS_SHADER
	material = _shader_material
	_apply_shader_parameters()
	set_postprocess_enabled(effect_enabled)
	sync_render_target_rect()


func _process(_delta: float) -> void:
	sync_render_target_rect()


## The post-process remains on the native viewport after the bounded world
## texture is composited and before the HUD layer. Synchronize the authored
## 1280x720 full rect with the current logical output on resize.
func sync_render_target_rect() -> void:
	var target_viewport: Viewport = get_viewport()
	if target_viewport == null:
		return
	# Controls live in the viewport's logical canvas. With stretch enabled the
	# backing texture can be larger than this rectangle; using the physical RID
	# size here would shift the vignette centre and recreate a visible boundary.
	var target_rect: Rect2 = target_viewport.get_visible_rect()
	var target_size := Vector2i(
		roundi(target_rect.size.x),
		roundi(target_rect.size.y),
	)
	if target_size.x <= 0 or target_size.y <= 0 or target_size == _last_render_target_size:
		return
	_last_render_target_size = target_size
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = float(target_size.x)
	offset_bottom = float(target_size.y)


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
