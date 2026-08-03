class_name EnvironmentExposureResolver
extends Node
## Shared, stateless open-sky read for rain presentation and player exposure.
## It derives context from existing world/building authorities and owns no
## survival state of its own.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _active_z: int = 0
var _building_system: Node = null
var _world_streamer: Node = null
var _services_resolved: bool = false


func _enter_tree() -> void:
	add_to_group("environment_exposure_resolver")


func _ready() -> void:
	if EventBus != null and not EventBus.z_level_changed.is_connected(_on_z_level_changed):
		EventBus.z_level_changed.connect(_on_z_level_changed)
	if EventBus != null \
			and not EventBus.rooms_recalculated.is_connected(_on_rooms_recalculated):
		EventBus.rooms_recalculated.connect(_on_rooms_recalculated)
	# Stable services add their groups in _ready(). Defer the one scene-tree
	# lookup until every sibling has completed that boot phase.
	call_deferred("_resolve_services_once")


func set_active_z_level(new_z: int) -> void:
	_active_z = new_z


func get_active_z_level() -> int:
	return _active_z


func is_open_sky_at(world_position: Vector2) -> bool:
	return is_open_sky_at_z(world_position, _active_z)


func is_open_sky_at_z(world_position: Vector2, z_level: int) -> bool:
	if z_level != 0 or not _services_resolved:
		return false
	if is_building_indoor_at(world_position):
		return false
	# Unknown mountain cover is fail-closed: gameplay and rain presentation
	# wait for the authoritative sample instead of leaking rain through a roof.
	if _world_streamer == null \
			or not _world_streamer.has_method("get_mountain_cover_sample"):
		return false
	var tile_coord: Vector2i = WorldRuntimeConstants.world_to_tile(world_position)
	var sample: Dictionary = _world_streamer.call(
		"get_mountain_cover_sample",
		tile_coord,
	) as Dictionary
	if not bool(sample.get("ready", false)):
		return false
	var mountain_flags: int = int(sample.get("mountain_flags", 0))
	return (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) == 0


func is_building_indoor_at(world_position: Vector2) -> bool:
	if not _services_resolved or _building_system == null:
		return false
	if not _building_system.has_method("world_to_grid") \
			or not _building_system.has_method("is_cell_indoor"):
		return false
	var grid_position: Variant = _building_system.call("world_to_grid", world_position)
	if not (grid_position is Vector2i):
		return false
	return bool(_building_system.call("is_cell_indoor", grid_position))


func _resolve_services_once() -> void:
	if _services_resolved:
		return
	_services_resolved = true
	_building_system = get_tree().get_first_node_in_group("building_system")
	_world_streamer = get_tree().get_first_node_in_group("chunk_manager")
	var z_manager: Node = get_tree().get_first_node_in_group("z_level_manager")
	if z_manager != null and z_manager.has_method("get_current_z"):
		_active_z = int(z_manager.call("get_current_z"))


func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	set_active_z_level(new_z)


func _on_rooms_recalculated(_indoor_cells: Dictionary) -> void:
	# BuildingSystem may be added after the world shell during future base
	# integration. Refresh only on its authoritative room publication, never
	# from the per-frame exposure query.
	if _building_system == null or not is_instance_valid(_building_system):
		_building_system = get_tree().get_first_node_in_group("building_system")
