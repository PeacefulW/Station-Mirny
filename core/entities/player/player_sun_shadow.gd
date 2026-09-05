class_name PlayerSunShadow
extends Sprite2D
## Visual-only baked sun shadow for the local player.
##
## The body and shadow use separate atlases. The body owns the active clip,
## direction and frame; this component mirrors only those integer indices into
## the matching 76x48 baked-shadow atlas. The baked cast already points toward
## screen south-east, so time of day may stretch/soften/fade it but never rotate
## it or rebuild a silhouette at runtime.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldRenderRecord = preload("res://core/systems/world/world_render_record.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const PLAYER_SUN_SHADOW_SHADER = preload("res://assets/shaders/player_silhouette_shadow.gdshader")

const ATLAS_DIRECTIONS: int = 16
const ATLAS_FRAMES_PER_DIRECTION: int = 16
const ALBEDO_FRAME_SIZE_PX: Vector2 = Vector2(208.0, 288.0)
const SHADOW_FRAME_SIZE_PX: Vector2 = Vector2(76.0, 48.0)
## The shadow pass is baked at one quarter of the albedo's linear resolution.
## Its Sprite2D therefore needs four times the albedo node scale to preserve the
## same projected world size.
const SHADOW_DOWNSAMPLE_FACTOR: float = 4.0
## Both passes align by the projection of the same 3D world origin. This is not
## the old V0 `foot_contact_uv` silhouette hinge.
const ALBEDO_WORLD_ORIGIN_UV: Vector2 = Vector2(0.5, 0.806)
const SHADOW_WORLD_ORIGIN_PX: Vector2 = Vector2(26.0, 14.0)
const SHADOW_ANCHOR_EPSILON_PX: float = 0.01

## Baked layered-object shadows use this same noon-to-low-sun stretch range.
const SHADOW_LENGTH_SCALE_MIN: float = 1.0
const SHADOW_LENGTH_SCALE_MAX: float = 1.85
## Transverse taps follow the tree-shadow material: the cast grows softer, but
## its fixed authored direction and grounded origin do not change.
const SHADOW_SOFTNESS_MIN_TEXELS: float = 0.75
const SHADOW_SOFTNESS_MAX_TEXELS: float = 7.0
const SHADOW_OPACITY_SCALE: float = 0.60
const SHADOW_VISIBILITY_EPSILON: float = 0.006
const PARAM_EPSILON: float = 0.001
const SHADOW_METADATA_PATHS: Dictionary = {
	&"idle": "res://assets/sprites/player/player_idle_shadow_16dir_16frames.json",
	&"run_forward": "res://assets/sprites/player/player_run_forward_shadow_16dir_16frames.json",
	&"run_backward": "res://assets/sprites/player/player_run_backward_shadow_16dir_16frames.json",
	&"strafe_left": "res://assets/sprites/player/player_strafe_left_shadow_16dir_16frames.json",
	&"strafe_right": "res://assets/sprites/player/player_strafe_right_shadow_16dir_16frames.json",
}

@export var visual_node_path: NodePath = ^"../Visual"

@export_group("Albedo clip atlas references")
@export var idle_albedo_texture: Texture2D = null
@export var run_forward_albedo_texture: Texture2D = null
@export var run_backward_albedo_texture: Texture2D = null
@export var strafe_left_albedo_texture: Texture2D = null
@export var strafe_right_albedo_texture: Texture2D = null

@export_group("Baked shadow clip atlas references")
@export var idle_shadow_texture: Texture2D = null
@export var run_forward_shadow_texture: Texture2D = null
@export var run_backward_shadow_texture: Texture2D = null
@export var strafe_left_shadow_texture: Texture2D = null
@export var strafe_right_shadow_texture: Texture2D = null

var _visual: Sprite2D = null
var _shadow_material: ShaderMaterial = null
var _world_streamer: Node = null
var _building_system: Node = null
## Keyed by the albedo Texture2D instance id. Five fixed entries keep clip
## selection O(1) without `load()` or filename parsing on the gameplay path.
var _clip_bindings: Dictionary = {}
## Metadata is parsed exactly once per shadow atlas during `_ready()`.
var _metadata_cache: Dictionary = {}
var _reported_missing_binding_ids: Dictionary = {}
var _last_shadow_texture: Texture2D = null
var _last_frame_index: int = -1
var _last_direction_index: int = -1
var _last_anchor_px: Vector2 = Vector2.INF
var _last_length_scale: float = -1.0
var _last_softness_texels: float = -1.0
var _last_opacity: float = -1.0
var _has_valid_frame: bool = false
var _external_rendering_enabled: bool = false


func _ready() -> void:
	# Player updates its Visual at the default priority. Run immediately after it
	# so the baked cast never trails the body by one physics frame.
	process_physics_priority = 1
	centered = true
	region_enabled = true
	region_filter_clip_enabled = true
	rotation = 0.0
	flip_h = false
	flip_v = false
	z_as_relative = false
	z_index = WorldRuntimeConstants.Z_ACTOR_SHADOW
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = PLAYER_SUN_SHADOW_SHADER
	_shadow_material.set_shader_parameter(
		"shadow_direction",
		WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION,
	)
	_shadow_material.set_shader_parameter("shadow_frame_size_px", SHADOW_FRAME_SIZE_PX)
	material = _shadow_material
	_build_clip_bindings()
	_sync_visual_frame()
	_update_shadow_from_environment()


func _physics_process(_delta: float) -> void:
	_sync_visual_frame()
	_update_shadow_from_environment()
	if _external_rendering_enabled:
		visible = false


func set_external_rendering_enabled(enabled: bool) -> void:
	_external_rendering_enabled = enabled
	if enabled:
		visible = false


func get_world_render_shadow_state() -> Dictionary:
	var safe_anchor: Vector2 = _last_anchor_px
	if not safe_anchor.is_finite():
		safe_anchor = SHADOW_WORLD_ORIGIN_PX
	return {
		"shadow_visible": _has_valid_frame \
				and _last_opacity > SHADOW_VISIBILITY_EPSILON,
		"shadow_transform": WorldRenderRecord.unit_quad_transform_for_sprite(
			self,
			SHADOW_FRAME_SIZE_PX,
		),
		"shadow_anchor": safe_anchor / SHADOW_FRAME_SIZE_PX,
		"shadow_softness": maxf(_last_softness_texels, 0.0),
		"shadow_opacity": maxf(_last_opacity, 0.0),
		"shadow_length_scale": maxf(_last_length_scale, 1.0),
	}


func _build_clip_bindings() -> void:
	_clip_bindings.clear()
	_metadata_cache.clear()
	_register_clip(&"idle", idle_albedo_texture, idle_shadow_texture)
	_register_clip(&"run_forward", run_forward_albedo_texture, run_forward_shadow_texture)
	_register_clip(&"run_backward", run_backward_albedo_texture, run_backward_shadow_texture)
	_register_clip(&"strafe_left", strafe_left_albedo_texture, strafe_left_shadow_texture)
	_register_clip(&"strafe_right", strafe_right_albedo_texture, strafe_right_shadow_texture)


func _register_clip(clip_id: StringName, albedo_texture: Texture2D, shadow_texture: Texture2D) -> void:
	if albedo_texture == null or shadow_texture == null:
		push_error("PlayerSunShadow: clip %s is missing an explicit albedo/shadow atlas reference" % clip_id)
		return
	var metadata: Dictionary = _metadata_for_shadow(clip_id, shadow_texture)
	var anchor_px: Vector2 = _validated_shadow_anchor(clip_id, metadata)
	var albedo_anchor_uv: Vector2 = _validated_albedo_anchor(clip_id, metadata)
	_clip_bindings[albedo_texture.get_instance_id()] = {
		"clip_id": clip_id,
		"shadow_texture": shadow_texture,
		"anchor_px": anchor_px,
		"albedo_anchor_uv": albedo_anchor_uv,
	}


func _metadata_for_shadow(clip_id: StringName, shadow_texture: Texture2D) -> Dictionary:
	var metadata_path: String = str(SHADOW_METADATA_PATHS.get(clip_id, ""))
	if metadata_path.is_empty():
		var texture_path: String = shadow_texture.resource_path
		if texture_path.is_empty():
			push_error("PlayerSunShadow: baked shadow clip has no metadata binding")
			return {}
		metadata_path = texture_path.get_basename() + ".json"
	if _metadata_cache.has(metadata_path):
		return _metadata_cache[metadata_path] as Dictionary
	var result: Dictionary = {}
	var json_text: String = FileAccess.get_file_as_string(metadata_path)
	if json_text.is_empty():
		push_error("PlayerSunShadow: missing baked shadow metadata %s" % metadata_path)
	else:
		var parsed: Variant = JSON.parse_string(json_text)
		if parsed is Dictionary:
			result = parsed as Dictionary
		else:
			push_error("PlayerSunShadow: invalid baked shadow metadata %s" % metadata_path)
	_metadata_cache[metadata_path] = result
	return result


func _validated_shadow_anchor(clip_id: StringName, metadata: Dictionary) -> Vector2:
	_validate_metadata_grid(clip_id, metadata)
	var raw_anchor: Variant = metadata.get("shadow_anchor_px", metadata.get("anchor_px", []))
	var anchor_px: Vector2 = SHADOW_WORLD_ORIGIN_PX
	if raw_anchor is Array and (raw_anchor as Array).size() >= 2:
		var values: Array = raw_anchor as Array
		anchor_px = Vector2(float(values[0]), float(values[1]))
	elif raw_anchor is Vector2:
		anchor_px = raw_anchor as Vector2
	else:
		push_error("PlayerSunShadow: clip %s metadata has no shadow_anchor_px" % clip_id)
	if anchor_px.distance_to(SHADOW_WORLD_ORIGIN_PX) > SHADOW_ANCHOR_EPSILON_PX:
		push_error(
			"PlayerSunShadow: clip %s shadow anchor %s does not match authored %s"
			% [clip_id, anchor_px, SHADOW_WORLD_ORIGIN_PX]
		)
		# Keep presentation grounded even in a bad development bake; the contract
		# test still fails on the metadata mismatch.
		return SHADOW_WORLD_ORIGIN_PX
	return anchor_px


func _validated_albedo_anchor(clip_id: StringName, metadata: Dictionary) -> Vector2:
	var raw_anchor: Variant = metadata.get("albedo_anchor_uv", [])
	var anchor_uv: Vector2 = ALBEDO_WORLD_ORIGIN_UV
	if raw_anchor is Array and (raw_anchor as Array).size() >= 2:
		var values: Array = raw_anchor as Array
		anchor_uv = Vector2(float(values[0]), float(values[1]))
	elif raw_anchor is Vector2:
		anchor_uv = raw_anchor as Vector2
	else:
		push_error("PlayerSunShadow: clip %s metadata has no albedo_anchor_uv" % clip_id)
	if anchor_uv.distance_to(ALBEDO_WORLD_ORIGIN_UV) > PARAM_EPSILON:
		push_error(
			"PlayerSunShadow: clip %s albedo anchor %s does not match authored %s"
			% [clip_id, anchor_uv, ALBEDO_WORLD_ORIGIN_UV]
		)
		return ALBEDO_WORLD_ORIGIN_UV
	return anchor_uv


func _validate_metadata_grid(clip_id: StringName, metadata: Dictionary) -> void:
	if metadata.is_empty():
		return
	var directions: int = int(metadata.get("directions", 0))
	var frames: int = int(metadata.get("frames_per_direction", 0))
	var frame_width: int = int(metadata.get("frame_width_px", metadata.get("shadow_frame_width_px", 0)))
	var frame_height: int = int(metadata.get("frame_height_px", metadata.get("shadow_frame_height_px", 0)))
	if directions != ATLAS_DIRECTIONS or frames != ATLAS_FRAMES_PER_DIRECTION:
		push_error(
			"PlayerSunShadow: clip %s shadow grid is %sx%s, expected %sx%s"
			% [clip_id, frames, directions, ATLAS_FRAMES_PER_DIRECTION, ATLAS_DIRECTIONS]
		)
	if frame_width != int(SHADOW_FRAME_SIZE_PX.x) or frame_height != int(SHADOW_FRAME_SIZE_PX.y):
		push_error(
			"PlayerSunShadow: clip %s shadow tile is %sx%s, expected %sx%s"
			% [clip_id, frame_width, frame_height, int(SHADOW_FRAME_SIZE_PX.x), int(SHADOW_FRAME_SIZE_PX.y)]
		)
	if str(metadata.get("direction_zero", "")) != "screen_north" \
			or str(metadata.get("direction_order", "")) != "clockwise":
		push_error("PlayerSunShadow: clip %s shadow direction contract must be screen_north + clockwise" % clip_id)


func _sync_visual_frame() -> void:
	_has_valid_frame = false
	if _visual == null or not is_instance_valid(_visual):
		_visual = get_node_or_null(visual_node_path) as Sprite2D
	if _visual == null or _visual.texture == null:
		visible = false
		return
	var visual_texture_id: int = _visual.texture.get_instance_id()
	var binding_variant: Variant = _clip_bindings.get(visual_texture_id)
	if not (binding_variant is Dictionary):
		if not _reported_missing_binding_ids.has(visual_texture_id):
			_reported_missing_binding_ids[visual_texture_id] = true
			push_error(
				"PlayerSunShadow: no baked shadow binding for %s"
				% _visual.texture.resource_path
			)
		visible = false
		return
	var binding: Dictionary = binding_variant as Dictionary
	var shadow_texture: Texture2D = binding.get("shadow_texture") as Texture2D
	if shadow_texture == null:
		visible = false
		return

	var frame_index: int = clampi(
		roundi(_visual.region_rect.position.x / ALBEDO_FRAME_SIZE_PX.x),
		0,
		ATLAS_FRAMES_PER_DIRECTION - 1,
	)
	var direction_index: int = clampi(
		roundi(_visual.region_rect.position.y / ALBEDO_FRAME_SIZE_PX.y),
		0,
		ATLAS_DIRECTIONS - 1,
	)
	var anchor_px: Vector2 = binding.get("anchor_px", SHADOW_WORLD_ORIGIN_PX) as Vector2
	var albedo_anchor_uv: Vector2 = binding.get(
		"albedo_anchor_uv",
		ALBEDO_WORLD_ORIGIN_UV,
	) as Vector2
	if shadow_texture != _last_shadow_texture \
			or frame_index != _last_frame_index \
			or direction_index != _last_direction_index:
		_last_shadow_texture = shadow_texture
		_last_frame_index = frame_index
		_last_direction_index = direction_index
		texture = shadow_texture
		region_rect = Rect2(
			frame_index * SHADOW_FRAME_SIZE_PX.x,
			direction_index * SHADOW_FRAME_SIZE_PX.y,
			SHADOW_FRAME_SIZE_PX.x,
			SHADOW_FRAME_SIZE_PX.y,
		)
	if anchor_px.distance_to(_last_anchor_px) > PARAM_EPSILON:
		_last_anchor_px = anchor_px
		# With centered=true this makes the baked world-origin pixel land at the
		# Sprite2D node origin, which is also the shader's stretch pivot.
		offset = SHADOW_FRAME_SIZE_PX * 0.5 - anchor_px
		_shadow_material.set_shader_parameter("shadow_anchor_px", anchor_px)

	# Project the same 3D world origin used by the albedo bake into the player's
	# local 2D space. Do not use the old lowest-alpha foot-contact compensation.
	var albedo_origin_local_px := Vector2(
		(albedo_anchor_uv.x - 0.5) * ALBEDO_FRAME_SIZE_PX.x + _visual.offset.x,
		(albedo_anchor_uv.y - 0.5) * ALBEDO_FRAME_SIZE_PX.y + _visual.offset.y,
	)
	var target_position: Vector2 = _visual.transform * albedo_origin_local_px
	if position.distance_to(target_position) > PARAM_EPSILON:
		position = target_position
	var target_scale: Vector2 = _visual.scale * SHADOW_DOWNSAMPLE_FACTOR
	if scale.distance_to(target_scale) > PARAM_EPSILON:
		scale = target_scale
	_has_valid_frame = true


func _update_shadow_from_environment() -> void:
	if not _has_valid_frame or _shadow_material == null or texture == null:
		visible = false
		return
	var current_hour: float = _current_hour()
	var sun_progress: float = _sun_progress()
	var low_sun: float = WorldVisualLightingProfile.low_sun_for_progress(sun_progress)
	var direct_sun_factor: float = _direct_sun_factor()
	var surface_factor: float = _surface_context_factor()
	var profile_opacity: float = WorldVisualLightingProfile.shadow_opacity_for_low_sun_and_hour(
		low_sun,
		current_hour,
	)
	var shadow_opacity: float = clampf(
		profile_opacity * direct_sun_factor * surface_factor * SHADOW_OPACITY_SCALE,
		0.0,
		1.0,
	)
	if shadow_opacity <= SHADOW_VISIBILITY_EPSILON:
		visible = false
		_apply_opacity_if_needed(0.0)
		return
	visible = true
	var length_scale: float = lerpf(SHADOW_LENGTH_SCALE_MIN, SHADOW_LENGTH_SCALE_MAX, low_sun)
	var softness_texels: float = lerpf(
		SHADOW_SOFTNESS_MIN_TEXELS,
		SHADOW_SOFTNESS_MAX_TEXELS,
		low_sun,
	)
	_apply_shadow_params_if_needed(length_scale, softness_texels, shadow_opacity)


func _current_hour() -> float:
	var time_manager: Node = _get_time_manager()
	if time_manager != null:
		var current_hour: Variant = time_manager.get("current_hour")
		if current_hour != null:
			return float(current_hour)
	return WorldVisualLightingProfile.DEFAULT_PREVIEW_HOUR


func _sun_progress() -> float:
	var time_manager: Node = _get_time_manager()
	if time_manager != null and time_manager.has_method("get_sun_progress"):
		return float(time_manager.call("get_sun_progress"))
	return WorldVisualLightingProfile.sun_progress_for_hour(_current_hour())


func _direct_sun_factor() -> float:
	var weather_runtime: Node = _get_weather_runtime()
	if weather_runtime == null or not weather_runtime.has_method("get_cloud_occlusion"):
		return 1.0
	var cloud_occlusion: float = clampf(float(weather_runtime.call("get_cloud_occlusion")), 0.0, 1.0)
	return 1.0 - cloud_occlusion


func _surface_context_factor() -> float:
	if _is_building_indoor() or _is_mountain_interior():
		return 0.0
	return 1.0


func _is_building_indoor() -> bool:
	var building_system: Node = _get_building_system()
	if building_system == null:
		return false
	if not building_system.has_method("world_to_grid") or not building_system.has_method("is_cell_indoor"):
		return false
	var grid_pos_variant: Variant = building_system.call("world_to_grid", global_position)
	if not (grid_pos_variant is Vector2i):
		return false
	return bool(building_system.call("is_cell_indoor", grid_pos_variant))


func _is_mountain_interior() -> bool:
	var streamer: Node = _get_world_streamer()
	if streamer == null:
		return false
	if not streamer.has_method("get_mountain_cover_sample"):
		return false
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(global_position)
	var sample: Dictionary = streamer.call("get_mountain_cover_sample", tile_coord) as Dictionary
	if not bool(sample.get("ready", false)):
		return false
	var mountain_flags: int = int(sample.get("mountain_flags", 0))
	return (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0


func _get_world_streamer() -> Node:
	if _world_streamer != null and is_instance_valid(_world_streamer):
		return _world_streamer
	var nodes: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if nodes.is_empty():
		return null
	_world_streamer = nodes[0]
	return _world_streamer


func _get_building_system() -> Node:
	if _building_system != null and is_instance_valid(_building_system):
		return _building_system
	var nodes: Array[Node] = get_tree().get_nodes_in_group("building_system")
	if nodes.is_empty():
		return null
	_building_system = nodes[0]
	return _building_system


func _get_time_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/TimeManager")


func _get_weather_runtime() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/WeatherRuntime")


func _apply_opacity_if_needed(shadow_opacity: float) -> void:
	if absf(shadow_opacity - _last_opacity) <= PARAM_EPSILON:
		return
	_last_opacity = shadow_opacity
	_shadow_material.set_shader_parameter("shadow_opacity", shadow_opacity)


func _apply_shadow_params_if_needed(
		length_scale: float,
		softness_texels: float,
		shadow_opacity: float,
) -> void:
	if absf(length_scale - _last_length_scale) > PARAM_EPSILON:
		_last_length_scale = length_scale
		_shadow_material.set_shader_parameter("shadow_length_scale", length_scale)
	if absf(softness_texels - _last_softness_texels) > PARAM_EPSILON:
		_last_softness_texels = softness_texels
		_shadow_material.set_shader_parameter("shadow_softness_texels", softness_texels)
	_apply_opacity_if_needed(shadow_opacity)
