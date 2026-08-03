class_name RainOverlay
extends WorldViewOverlay
## One view-bounded rain pass. WeatherRuntime owns rain truth; this layer only
## reads kind/intensity and suppresses presentation outside an open-sky context.

const RAIN_SHADER: Shader = preload("res://assets/shaders/rain_overlay.gdshader")
const WeatherRuntimeScript = preload("res://core/autoloads/weather_runtime.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const RAIN_Z_INDEX: int = 405
const MIN_VISIBLE_INTENSITY: float = 0.002
## Shader fall speeds travel an exact periodic cell field over this interval,
## so wrapping client-local animation time cannot produce a visual jump.
const RAIN_TIME_PERIOD_SECONDS: float = 16.0

var _current_z: int = 0
var _building_system: Node = null
var _world_streamer: Node = null
var _rain_time_seconds: float = 0.0


func _ready() -> void:
	visible = false
	super._ready()
	_current_z = _resolve_current_z()
	if EventBus != null and not EventBus.z_level_changed.is_connected(_on_z_level_changed):
		EventBus.z_level_changed.connect(_on_z_level_changed)


func _process(delta: float) -> void:
	_rain_time_seconds = fposmod(
		_rain_time_seconds + maxf(delta, 0.0),
		RAIN_TIME_PERIOD_SECONDS,
	)
	super._process(delta)


func set_active_z_level(new_z: int) -> void:
	_current_z = new_z


func _overlay_shader() -> Shader:
	return RAIN_SHADER


func _overlay_z() -> int:
	return RAIN_Z_INDEX


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	var intensity: float = 0.0
	if _has_open_sky_context() and WeatherRuntime != null:
		var precipitation_kind: int = int(WeatherRuntime.get_precipitation_kind())
		if precipitation_kind == WeatherRuntimeScript.PrecipitationKind.RAIN:
			intensity = clampf(WeatherRuntime.get_precipitation_intensity(), 0.0, 1.0)
	visible = intensity > MIN_VISIBLE_INTENSITY
	overlay_material.set_shader_parameter("rain_intensity", intensity)
	overlay_material.set_shader_parameter("rain_time_seconds", _rain_time_seconds)


func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	set_active_z_level(new_z)


func _has_open_sky_context() -> bool:
	if _current_z != 0:
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
	if not building_system.has_method("world_to_grid") \
			or not building_system.has_method("is_cell_indoor"):
		return false
	var grid_pos_variant: Variant = building_system.call(
		"world_to_grid",
		_local_player_position(),
	)
	if not (grid_pos_variant is Vector2i):
		return false
	return bool(building_system.call("is_cell_indoor", grid_pos_variant))


func _is_mountain_interior() -> bool:
	var streamer: Node = _get_world_streamer()
	if streamer == null or not streamer.has_method("get_mountain_cover_sample"):
		return false
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(_local_player_position())
	var sample: Dictionary = streamer.call("get_mountain_cover_sample", tile_coord) as Dictionary
	if not bool(sample.get("ready", false)):
		return false
	var mountain_flags: int = int(sample.get("mountain_flags", 0))
	return (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0


func _local_player_position() -> Vector2:
	if PlayerAuthority != null and PlayerAuthority.has_method("get_local_player_position"):
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
