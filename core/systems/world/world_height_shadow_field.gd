class_name WorldHeightShadowField
extends Node

const WorldHeightShadowProfile = preload(
	"res://core/systems/world/world_height_shadow_profile.gd"
)
const DEFAULT_PROFILE: WorldHeightShadowProfile = preload(
	"res://data/world_objects/presentation_profiles/world_height_shadow_profile.tres"
)

@export var profile: WorldHeightShadowProfile = DEFAULT_PROFILE
var _source_viewport: Viewport = null
var _mask_viewport: SubViewport = null
var _last_source_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	name = "WorldHeightShadowField"
	_source_viewport = get_viewport()
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "TallCasterMaskViewport"
	_mask_viewport.disable_3d = true
	_mask_viewport.transparent_bg = true
	_mask_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_viewport.canvas_cull_mask = WorldHeightShadowProfile.CASTER_VISIBILITY_LAYER
	add_child(_mask_viewport)
	_sync_viewport(true)


func _process(_delta: float) -> void:
	_sync_viewport(false)


func get_mask_texture() -> Texture2D:
	if _mask_viewport == null or not is_instance_valid(_mask_viewport):
		return null
	return _mask_viewport.get_texture()


func bind_receiver(
		material: ShaderMaterial,
		receiver_class: int,
) -> void:
	if material == null or profile == null:
		return
	material.set_shader_parameter("height_shadow_mask", get_mask_texture())
	material.set_shader_parameter(
		"height_shadow_caster_height",
		profile.height_for(profile.caster_class),
	)
	material.set_shader_parameter(
		"height_shadow_receiver_height",
		profile.height_for(receiver_class),
	)
	material.set_shader_parameter(
		"height_shadow_height_fade",
		profile.height_fade,
	)
	material.set_shader_parameter(
		"height_shadow_strength",
		clampf(profile.strength_for(receiver_class), 0.0, 1.0),
	)
	material.set_shader_parameter(
		"height_shadow_tint",
		Vector3(
			profile.receiver_tint.r,
			profile.receiver_tint.g,
			profile.receiver_tint.b,
		),
	)


func get_debug_state() -> Dictionary:
	return {
		"ready": _mask_viewport != null and is_instance_valid(_mask_viewport),
		"source_size": _last_source_size,
		"mask_size": _mask_viewport.size if _mask_viewport != null else Vector2i.ZERO,
		"resolution_scale": profile.mask_resolution_scale if profile != null else 0.0,
		"caster_class": profile.caster_class if profile != null else -1,
		"caster_visibility_layer": WorldHeightShadowProfile.CASTER_VISIBILITY_LAYER,
	}


func _sync_viewport(force: bool) -> void:
	if _source_viewport == null or not is_instance_valid(_source_viewport):
		_source_viewport = get_viewport()
	if _source_viewport == null or _mask_viewport == null:
		return
	if _mask_viewport.world_2d != _source_viewport.world_2d:
		_mask_viewport.world_2d = _source_viewport.world_2d
	var source_size: Vector2i = Vector2i(_source_viewport.get_visible_rect().size)
	if source_size.x <= 0 or source_size.y <= 0:
		return
	if force or source_size != _last_source_size:
		_last_source_size = source_size
		var resolution_scale: float = (
			clampf(profile.mask_resolution_scale, 0.25, 1.0)
			if profile != null
			else 0.5
		)
		_mask_viewport.size = Vector2i(
			maxi(1, ceili(float(source_size.x) * resolution_scale)),
			maxi(1, ceili(float(source_size.y) * resolution_scale)),
		)
	var scale_to_mask := Vector2(
		float(_mask_viewport.size.x) / float(source_size.x),
		float(_mask_viewport.size.y) / float(source_size.y),
	)
	var screen_scale := Transform2D(
		Vector2(scale_to_mask.x, 0.0),
		Vector2(0.0, scale_to_mask.y),
		Vector2.ZERO,
	)
	_mask_viewport.canvas_transform = screen_scale * _source_viewport.canvas_transform
