class_name CloudOccluderField
extends WorldViewOverlay
## View-bounded world-space cloud shadow layer. This is the Iteration 3 spatial
## response for docs/02_system_specs/world/cloud_occlusion_lighting.md.
##
## Two rejected renderers are intentionally not used:
## - LightOccluder2D: projects to screen-edge infinity in this top-down camera.
## - subtractive PointLight2D blobs: proven not to darken the normal-mapped
##   plains ground that is mostly carried by CanvasModulate.
##
## The live fallback is one world-space shader pass above world visuals and
## below HUD/CanvasLayer UI. It mixes the visible ground toward a cold dark sky
## color where the drifting cloud field is dense. No screen texture read, no
## saved state, no per-object or per-chunk work.

const CLOUD_SHADOW_SHADER = preload("res://assets/shaders/cloud_occluder_field.gdshader")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const CLOUD_SHADOW_Z_INDEX: int = 395
const NOISE_TEX_SIZE: int = 256

var _current_z: int = 0
var _building_system: Node = null
var _world_streamer: Node = null
var _noise_texture: NoiseTexture2D = null
var _daylight: Node = null


func _ready() -> void:
	super._ready()
	_current_z = _resolve_current_z()
	if EventBus != null and not EventBus.z_level_changed.is_connected(_on_z_level_changed):
		EventBus.z_level_changed.connect(_on_z_level_changed)


func set_active_z_level(new_z: int) -> void:
	_current_z = new_z


func _overlay_shader() -> Shader:
	return CLOUD_SHADOW_SHADER


func _overlay_z() -> int:
	return CLOUD_SHADOW_Z_INDEX


func _on_overlay_ready(overlay_material: ShaderMaterial) -> void:
	# Бесшовная процедурная текстура шума -> поле облаков без сеточных артефактов
	# точности на больших мировых координатах.
	overlay_material.set_shader_parameter("cloud_noise", _build_noise_texture())


func _build_noise_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = NOISE_TEX_SIZE
	tex.height = NOISE_TEX_SIZE
	tex.seamless = true
	tex.seamless_blend_skirt = 0.2
	tex.generate_mipmaps = true
	tex.noise = noise
	_noise_texture = tex
	return tex


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	var cover: float = 0.0
	var occlusion: float = 0.0
	var open_sky: bool = _has_open_sky_context()
	if open_sky and WeatherRuntime != null:
		cover = clampf(WeatherRuntime.get_cloud_cover(), 0.0, 1.0)
		if WeatherRuntime.has_method("get_cloud_occlusion"):
			occlusion = clampf(float(WeatherRuntime.call("get_cloud_occlusion")), 0.0, 1.0)
	# Тень бывает только пока есть прямое солнце: ночью гаснет, на рассвете
	# проявляется. Облачность-состояние при этом сохраняется (глобальный димминг).
	var sun_presence: float = _sun_day_factor() if open_sky else 0.0
	visible = cover > 0.12 and open_sky and sun_presence > 0.02
	overlay_material.set_shader_parameter("cloud_cover", cover)
	overlay_material.set_shader_parameter("cloud_occlusion", occlusion)
	overlay_material.set_shader_parameter("sun_presence", sun_presence)


## Доля прямого солнца сейчас (0 ночью .. 1 днём) — из DaylightSystem.
func _sun_day_factor() -> float:
	if _daylight == null or not is_instance_valid(_daylight):
		_daylight = get_parent().get_node_or_null("Daylight") if get_parent() != null else null
	if _daylight != null and _daylight.has_method("get_sun_day_factor"):
		return clampf(float(_daylight.call("get_sun_day_factor")), 0.0, 1.0)
	return 1.0


func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	set_active_z_level(new_z)


func _is_surface_context() -> bool:
	return _current_z == 0


func _has_open_sky_context() -> bool:
	if not _is_surface_context():
		return false
	if _is_building_indoor():
		return false
	if _is_mountain_interior():
		return false
	return true


func _is_building_indoor() -> bool:
	var building_system: Node = _get_building_system()
	if building_system == null:
		return false
	if not building_system.has_method("world_to_grid") or not building_system.has_method("is_cell_indoor"):
		return false
	var grid_pos_variant: Variant = building_system.call("world_to_grid", _local_player_position())
	if not (grid_pos_variant is Vector2i):
		return false
	return bool(building_system.call("is_cell_indoor", grid_pos_variant))


func _is_mountain_interior() -> bool:
	var streamer: Node = _get_world_streamer()
	if streamer == null:
		return false
	if not streamer.has_method("get_mountain_cover_sample"):
		return false
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(_local_player_position())
	var sample: Dictionary = streamer.call("get_mountain_cover_sample", tile_coord) as Dictionary
	if not bool(sample.get("ready", false)):
		return false
	var mountain_flags: int = int(sample.get("mountain_flags", 0))
	return (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0


func _local_player_position() -> Vector2:
	if PlayerAuthority == null:
		return Vector2.ZERO
	if PlayerAuthority.has_method("get_local_player_position"):
		return PlayerAuthority.get_local_player_position()
	return Vector2.ZERO


func _get_building_system() -> Node:
	if _building_system != null and is_instance_valid(_building_system):
		return _building_system
	var nodes: Array[Node] = get_tree().get_nodes_in_group("building_system")
	if nodes.is_empty():
		return null
	_building_system = nodes[0]
	return _building_system


func _get_world_streamer() -> Node:
	if _world_streamer != null and is_instance_valid(_world_streamer):
		return _world_streamer
	var nodes: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if nodes.is_empty():
		return null
	_world_streamer = nodes[0]
	return _world_streamer


func _resolve_current_z() -> int:
	var z_managers: Array[Node] = get_tree().get_nodes_in_group("z_level_manager")
	if z_managers.is_empty():
		return 0
	var z_manager: Node = z_managers[0]
	if z_manager.has_method("get_current_z"):
		return int(z_manager.get_current_z())
	return 0
