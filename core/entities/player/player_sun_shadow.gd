class_name PlayerSunShadow
extends Sprite2D
## Visual-only sun-tied silhouette shadow for the local player.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const PLAYER_SUN_SHADOW_SHADER = preload("res://assets/shaders/player_silhouette_shadow.gdshader")

const PLAYER_FRAME_HEIGHT_PX: float = 256.0
## Фиксированная линия земли под игроком (UV в кадре) — медиана контакта ног idle.
## Каждый кадр шейдер пиннит контакт ног на эту линию: убирает отрыв и «дрожание».
const GROUND_CONTACT_UV: float = 0.773
## 16 кадров на направление; индекс контакта dir-major: idx = direction*16 + frame.
const ATLAS_FRAMES_PER_DIRECTION: int = 16
## Запасной контакт, если у клипа нет запечённого frame_contact_uv (логируем сбой).
const DEFAULT_CONTACT_UV: float = 0.773
const SHADOW_OPACITY_SCALE: float = 0.45
const SHADOW_VISIBILITY_EPSILON: float = 0.006
const DIRECT_SUN_FADE_START_COVER: float = 0.72
const DIRECT_SUN_FADE_END_COVER: float = 0.95
## Длина тени = доля высоты фигуры, «уложенной» на землю вдоль shadow_dir.
## Минимум держим заметным: тело непрозрачно и рисуется ПОВЕРХ тени, поэтому при
## высоком солнце тень обязана вылезать из-под тела (путь Factorio: видна всегда).
const SHADOW_PROJECTION_MIN: float = 0.5
const SHADOW_PROJECTION_MAX: float = 1.4
## Контактное пятно: мягкий тёмный эллипс у ног, из которого «прорастает» силуэт.
## Чистый уложенный силуэт человека отрывается у ног (тонкие ноги → бледная связь);
## пятно прибивает тень к ступням и закрывает разрыв. Размеры — в пикселях кадра.
const POOL_BASE_LENGTH_PX: float = 95.0
const POOL_LENGTH_PER_PROJECTION_PX: float = 80.0
const POOL_WIDTH_PX: float = 80.0
const POOL_FORWARD_BIAS: float = 0.30
const POOL_OPACITY_FACTOR: float = 0.85
const POOL_TEXTURE_SIZE_PX: int = 128
const SHADOW_TINT: Color = Color(0.045, 0.036, 0.026)
const SHADOW_ABSOLUTE_Z_OFFSET: int = 1
const PARAM_EPSILON: float = 0.001

@export var visual_node_path: NodePath = ^"../Visual"

var _visual: Sprite2D = null
var _shadow_material: ShaderMaterial = null
var _world_streamer: Node = null
var _building_system: Node = null
var _last_shadow_dir: Vector2 = Vector2.INF
var _last_projection: float = -1.0
var _last_opacity: float = -1.0
var _last_contact_uv: float = -1.0
var _contact_tables: Dictionary = {}
var _contact_pool: Sprite2D = null


func _ready() -> void:
	centered = true
	region_enabled = true
	rotation = 0.0
	z_as_relative = false
	z_index = WorldRuntimeConstants.Z_GRASS_SHADOW + SHADOW_ABSOLUTE_Z_OFFSET
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = PLAYER_SUN_SHADOW_SHADER
	_shadow_material.set_shader_parameter("sprite_height_px", PLAYER_FRAME_HEIGHT_PX)
	_shadow_material.set_shader_parameter("ground_uv_y", GROUND_CONTACT_UV)
	material = _shadow_material
	_contact_pool = _build_contact_pool()
	add_child(_contact_pool)
	_sync_visual_frame()
	_update_shadow_from_environment()


func _physics_process(_delta: float) -> void:
	_sync_visual_frame()
	_update_shadow_from_environment()


func _sync_visual_frame() -> void:
	if _visual == null or not is_instance_valid(_visual):
		_visual = get_node_or_null(visual_node_path) as Sprite2D
	if _visual == null:
		visible = false
		return
	texture = _visual.texture
	region_enabled = _visual.region_enabled
	region_rect = _visual.region_rect
	scale = _visual.scale
	position = _visual.position
	offset = _visual.offset
	centered = _visual.centered
	flip_h = _visual.flip_h
	flip_v = _visual.flip_v
	rotation = 0.0
	_apply_contact_uv()


func _apply_contact_uv() -> void:
	if _shadow_material == null or texture == null:
		return
	var contact_uv: float = DEFAULT_CONTACT_UV
	var table: PackedFloat32Array = _contact_table_for(texture)
	if not table.is_empty():
		var col: int = int(region_rect.position.x / PLAYER_FRAME_HEIGHT_PX)
		var row: int = int(region_rect.position.y / PLAYER_FRAME_HEIGHT_PX)
		var index: int = row * ATLAS_FRAMES_PER_DIRECTION + col
		if index >= 0 and index < table.size():
			contact_uv = table[index]
	if absf(contact_uv - _last_contact_uv) > PARAM_EPSILON:
		_last_contact_uv = contact_uv
		_shadow_material.set_shader_parameter("contact_uv_y", contact_uv)


func _contact_table_for(clip_texture: Texture2D) -> PackedFloat32Array:
	var path: String = clip_texture.resource_path
	if path.is_empty():
		return PackedFloat32Array()
	if _contact_tables.has(path):
		var cached: PackedFloat32Array = _contact_tables[path]
		return cached
	var table: PackedFloat32Array = _load_contact_table(path)
	_contact_tables[path] = table
	return table


func _load_contact_table(texture_path: String) -> PackedFloat32Array:
	var json_path: String = texture_path.get_basename() + ".json"
	var json_text: String = FileAccess.get_file_as_string(json_path)
	if json_text.is_empty():
		push_error("PlayerSunShadow: missing clip metadata %s" % json_path)
		return PackedFloat32Array()
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("frame_contact_uv"):
		push_error("PlayerSunShadow: %s lacks baked frame_contact_uv" % json_path)
		return PackedFloat32Array()
	var raw: Variant = (parsed as Dictionary)["frame_contact_uv"]
	if not (raw is Array):
		push_error("PlayerSunShadow: frame_contact_uv in %s is not an array" % json_path)
		return PackedFloat32Array()
	var values: Array = raw as Array
	var table: PackedFloat32Array = PackedFloat32Array()
	table.resize(values.size())
	for i: int in values.size():
		table[i] = float(values[i])
	return table


func _update_shadow_from_environment() -> void:
	if _shadow_material == null or texture == null:
		visible = false
		_set_contact_pool_visible(false)
		return
	var current_hour: float = _current_hour()
	var sun_progress: float = _sun_progress()
	var low_sun: float = WorldVisualLightingProfile.low_sun_for_progress(sun_progress)
	var light_angle: float = _light_angle()
	var shadow_angle: float = light_angle + PI
	var shadow_dir := Vector2(cos(shadow_angle), sin(shadow_angle)).normalized()
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
		_set_contact_pool_visible(false)
		_apply_opacity_if_needed(0.0)
		return
	visible = true
	var projection: float = lerpf(SHADOW_PROJECTION_MIN, SHADOW_PROJECTION_MAX, low_sun)
	_apply_shadow_params_if_needed(shadow_dir, projection, shadow_opacity)
	_update_contact_pool(shadow_dir, projection, shadow_opacity)


func _build_contact_pool() -> Sprite2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	var pool_texture := GradientTexture2D.new()
	pool_texture.gradient = gradient
	pool_texture.width = POOL_TEXTURE_SIZE_PX
	pool_texture.height = POOL_TEXTURE_SIZE_PX
	pool_texture.fill = GradientTexture2D.FILL_RADIAL
	pool_texture.fill_from = Vector2(0.5, 0.5)
	pool_texture.fill_to = Vector2(1.0, 0.5)
	var pool := Sprite2D.new()
	pool.texture = pool_texture
	pool.centered = true
	pool.show_behind_parent = true
	pool.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pool.visible = false
	return pool


func _update_contact_pool(shadow_dir: Vector2, projection: float, shadow_opacity: float) -> void:
	if _contact_pool == null:
		return
	_contact_pool.visible = true
	var feet_local := Vector2(0.0, (GROUND_CONTACT_UV - 0.5) * PLAYER_FRAME_HEIGHT_PX)
	var pool_length: float = POOL_BASE_LENGTH_PX + projection * POOL_LENGTH_PER_PROJECTION_PX
	_contact_pool.rotation = shadow_dir.angle()
	_contact_pool.position = feet_local + shadow_dir * (pool_length * POOL_FORWARD_BIAS)
	_contact_pool.scale = Vector2(
		pool_length / float(POOL_TEXTURE_SIZE_PX),
		POOL_WIDTH_PX / float(POOL_TEXTURE_SIZE_PX),
	)
	var pool_alpha: float = clampf(shadow_opacity * POOL_OPACITY_FACTOR, 0.0, 1.0)
	_contact_pool.self_modulate = Color(SHADOW_TINT.r, SHADOW_TINT.g, SHADOW_TINT.b, pool_alpha)


func _set_contact_pool_visible(pool_visible: bool) -> void:
	if _contact_pool != null:
		_contact_pool.visible = pool_visible


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


func _light_angle() -> float:
	var time_manager: Node = _get_time_manager()
	if time_manager != null and time_manager.has_method("get_sun_angle"):
		return float(time_manager.call("get_sun_angle"))
	return deg_to_rad(WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG)


func _direct_sun_factor() -> float:
	var cloud_cover: float = 0.0
	var weather_runtime: Node = _get_weather_runtime()
	if weather_runtime != null and weather_runtime.has_method("get_cloud_cover"):
		cloud_cover = clampf(float(weather_runtime.call("get_cloud_cover")), 0.0, 1.0)
	return 1.0 - WorldVisualLightingProfile.smoothstep_float(
		DIRECT_SUN_FADE_START_COVER,
		DIRECT_SUN_FADE_END_COVER,
		cloud_cover,
	)


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
		shadow_dir: Vector2,
		projection: float,
		shadow_opacity: float,
) -> void:
	if shadow_dir.distance_to(_last_shadow_dir) > PARAM_EPSILON:
		_last_shadow_dir = shadow_dir
		_shadow_material.set_shader_parameter("shadow_dir", shadow_dir)
	if absf(projection - _last_projection) > PARAM_EPSILON:
		_last_projection = projection
		_shadow_material.set_shader_parameter("shadow_projection", projection)
	_apply_opacity_if_needed(shadow_opacity)
