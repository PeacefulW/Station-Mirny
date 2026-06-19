class_name OvercastFlattenOverlay
extends WorldViewOverlay
## Surface-only screen-space pass for overcast flatness. It reads the rendered
## surface and desaturates/compresses contrast by flatten(cover).

const WeatherPresentationCurves = preload("res://core/systems/world/weather_presentation_curves.gd")
const FLATTEN_SHADER = preload("res://assets/shaders/overcast_flatten_overlay.gdshader")
const FLATTEN_Z_INDEX: int = 398

var _current_z: int = 0


func _ready() -> void:
	super._ready()
	_current_z = _resolve_current_z()
	if EventBus != null and not EventBus.z_level_changed.is_connected(_on_z_level_changed):
		EventBus.z_level_changed.connect(_on_z_level_changed)


func set_active_z_level(new_z: int) -> void:
	_current_z = new_z


func _overlay_shader() -> Shader:
	return FLATTEN_SHADER


func _overlay_z() -> int:
	return FLATTEN_Z_INDEX


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	var strength: float = 0.0
	if _is_surface_context() and WeatherRuntime != null:
		strength = WeatherPresentationCurves.flatten_strength(WeatherRuntime.get_cloud_cover())
	overlay_material.set_shader_parameter("flatten_strength", strength)


func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	set_active_z_level(new_z)


func _is_surface_context() -> bool:
	return _current_z == 0


func _resolve_current_z() -> int:
	var z_managers: Array[Node] = get_tree().get_nodes_in_group("z_level_manager")
	if z_managers.is_empty():
		return 0
	var z_manager: Node = z_managers[0]
	if z_manager.has_method("get_current_z"):
		return int(z_manager.get_current_z())
	return 0
