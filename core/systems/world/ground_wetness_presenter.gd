class_name GroundWetnessPresenter
extends Node
## O(1) bridge from authoritative rain to the existing shared plains material.
## The integrated scalar is transient presentation state and is never saved.

const WeatherRuntimeScript = preload("res://core/autoloads/weather_runtime.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactoryScript = preload("res://core/systems/world/world_tile_set_factory.gd")

@export var profile: GroundWetnessProfile = null

var _ground_wetness: float = 0.0
var _elapsed: float = 0.0
var _active_z: int = 0
var _ground_material: ShaderMaterial = null
var _last_precipitation_kind: int = WeatherRuntimeScript.PrecipitationKind.NONE
var _last_precipitation_intensity: float = 0.0


func _ready() -> void:
	if profile == null or not profile.is_valid_profile():
		push_error("GroundWetnessPresenter requires a valid boot-prepared profile")
		set_process(false)
		return
	if EventBus != null and not EventBus.z_level_changed.is_connected(_on_z_level_changed):
		EventBus.z_level_changed.connect(_on_z_level_changed)
	call_deferred("_resolve_active_z")


func _exit_tree() -> void:
	if _ground_material != null and is_instance_valid(_ground_material):
		_ground_material.set_shader_parameter("wet_ground_amount", 0.0)
		_ground_material.set_shader_parameter("wet_ground_rain_intensity", 0.0)


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _elapsed < profile.update_interval_seconds:
		return
	var step_delta: float = _elapsed
	_elapsed = 0.0
	var precipitation_kind: int = WeatherRuntimeScript.PrecipitationKind.NONE
	var precipitation_intensity: float = 0.0
	if WeatherRuntime != null:
		precipitation_kind = int(WeatherRuntime.get_precipitation_kind())
		precipitation_intensity = clampf(
			WeatherRuntime.get_precipitation_intensity(),
			0.0,
			1.0,
		)
	_last_precipitation_kind = precipitation_kind
	_last_precipitation_intensity = precipitation_intensity
	_ground_wetness = calculate_next_amount(
		profile,
		_ground_wetness,
		step_delta,
		precipitation_kind,
		precipitation_intensity,
	)
	_publish_to_shared_material(precipitation_kind, precipitation_intensity)


func get_ground_wetness() -> float:
	return _ground_wetness


static func calculate_next_amount(
		tuning: GroundWetnessProfile,
		current_amount: float,
		delta: float,
		precipitation_kind: int,
		precipitation_intensity: float,
) -> float:
	var amount: float = clampf(current_amount, 0.0, 1.0)
	if tuning == null or delta <= 0.0:
		return amount
	if precipitation_kind == WeatherRuntimeScript.PrecipitationKind.RAIN \
			and precipitation_intensity > 0.0:
		amount += (
			clampf(precipitation_intensity, 0.0, 1.0)
			* tuning.accumulation_rate_per_second
			* delta
		)
	else:
		amount -= tuning.drying_rate_per_second * delta
	return clampf(amount, 0.0, 1.0)


func _publish_to_shared_material(
		precipitation_kind: int,
		precipitation_intensity: float,
) -> void:
	var material: ShaderMaterial = (
		WorldTileSetFactoryScript.get_built_material_for_terrain(
			WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
		)
	)
	if material == null:
		return
	if material != _ground_material:
		_ground_material = material
		_apply_profile_uniforms(_ground_material)
	var surface_active: bool = _active_z == 0
	var visible_amount: float = _ground_wetness if surface_active else 0.0
	var visible_rain: float = 0.0
	if surface_active \
			and precipitation_kind == WeatherRuntimeScript.PrecipitationKind.RAIN:
		visible_rain = clampf(precipitation_intensity, 0.0, 1.0)
	_ground_material.set_shader_parameter("wet_ground_amount", visible_amount)
	_ground_material.set_shader_parameter("wet_ground_rain_intensity", visible_rain)


func _apply_profile_uniforms(material: ShaderMaterial) -> void:
	material.set_shader_parameter("wet_ground_basin_contrast", profile.basin_contrast)
	material.set_shader_parameter("wet_ground_grass_floor", profile.grass_wetness_floor)
	material.set_shader_parameter("wet_ground_puddle_threshold", profile.puddle_threshold)
	material.set_shader_parameter("wet_ground_darkening", profile.wet_darkening)
	material.set_shader_parameter("wet_ground_desaturation", profile.wet_desaturation)
	material.set_shader_parameter("wet_ground_puddle_tint", profile.puddle_tint)
	material.set_shader_parameter("wet_ground_puddle_opacity", profile.puddle_opacity)
	material.set_shader_parameter("wet_ground_impact_cell_px", profile.impact_cell_size_px)
	material.set_shader_parameter("wet_ground_impact_ring_width_px", profile.impact_ring_width)
	material.set_shader_parameter(
		"wet_ground_impact_lifetime_seconds",
		profile.impact_lifetime_seconds,
	)
	material.set_shader_parameter("wet_ground_impact_density", profile.impact_density)


func _resolve_active_z() -> void:
	var z_manager: Node = get_tree().get_first_node_in_group("z_level_manager")
	if z_manager != null and z_manager.has_method("get_current_z"):
		_active_z = int(z_manager.call("get_current_z"))
	_publish_to_shared_material(
		_last_precipitation_kind,
		_last_precipitation_intensity,
	)


func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	_active_z = new_z
	_publish_to_shared_material(
		_last_precipitation_kind,
		_last_precipitation_intensity,
	)
