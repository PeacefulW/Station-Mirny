class_name PlaceBuildingCommand
extends GameCommand

var _building_system: BuildingSystem = null
var _world_pos: Vector2 = Vector2.ZERO

func setup(building_system: BuildingSystem, world_pos: Vector2) -> PlaceBuildingCommand:
	_building_system = building_system
	_world_pos = world_pos
	return self

func execute() -> Dictionary:
	if not _building_system:
		return {
			"success": false,
			"message_key": "SYSTEM_BUILDING_SYSTEM_UNAVAILABLE",
		}
	return _building_system.place_selected_building_at(_world_pos)