class_name BuildingCatalog
extends RefCounted

const POWER_BALANCE: PowerBalance = preload("res://data/balance/power_balance.tres")
const ARK_BATTERY_SCRIPT: Script = preload("res://core/entities/structures/ark_battery.gd")
const THERMO_BURNER_SCRIPT: Script = preload("res://core/entities/structures/thermo_burner.gd")

static func get_default_buildings() -> Array[BuildingData]:
	return [
		_make_wall_default_data(),
		_make_battery_default_data(),
		_make_burner_default_data(),
	]

static func get_default_building(building_id: String) -> BuildingData:
	for building_data: BuildingData in get_default_buildings():
		if str(building_data.id) == building_id:
			return building_data
	return null

static func _make_wall_default_data() -> BuildingData:
	var wall := BuildingData.new()
	wall.id = &"wall"
	wall.display_name = "Стена"
	wall.description = "Базовая стена. Герметизирует помещение."
	wall.category = BuildingData.Category.STRUCTURE
	wall.scrap_cost = 2
	wall.health = 50.0
	wall.placeholder_color = Color(0.45, 0.48, 0.52)
	wall.hotkey = 1
	return wall

static func _make_battery_default_data() -> BuildingData:
	var battery := BuildingData.new()
	battery.id = &"ark_battery"
	battery.display_name = "Батарея Ковчега"
	battery.description = "Конечный запас энергии. Когда сядет — навсегда."
	battery.category = BuildingData.Category.POWER
	battery.scrap_cost = POWER_BALANCE.ark_battery_cost
	battery.health = 80.0
	battery.placeholder_color = Color(0.3, 0.5, 0.8)
	battery.hotkey = 2
	battery.logic_script = ARK_BATTERY_SCRIPT
	battery.logic_balance = POWER_BALANCE
	battery.script_path = "res://core/entities/structures/ark_battery.gd"
	battery.balance_path = "res://data/balance/power_balance.tres"
	return battery

static func _make_burner_default_data() -> BuildingData:
	var burner := BuildingData.new()
	burner.id = &"thermo_burner"
	burner.display_name = "Термосжигатель"
	burner.description = "Жжёт древесину -> энергия для базы. Шумит и привлекает Очистителей."
	burner.category = BuildingData.Category.POWER
	burner.scrap_cost = POWER_BALANCE.burner_cost
	burner.health = 60.0
	burner.placeholder_color = Color(0.8, 0.4, 0.15)
	burner.hotkey = 3
	burner.logic_script = THERMO_BURNER_SCRIPT
	burner.logic_balance = POWER_BALANCE
	burner.script_path = "res://core/entities/structures/thermo_burner.gd"
	burner.balance_path = "res://data/balance/power_balance.tres"
	return burner
