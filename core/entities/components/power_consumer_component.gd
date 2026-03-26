class_name PowerConsumerComponent
extends Node

## Компонент потребителя энергии. Прикрепляется к любой
## постройке, которая нуждается в электричестве (компрессор,
## электропечь, сервер дешифровки, турель, освещение...).
## PowerSystem получает его через explicit register/unregister.
## Группа "power_consumers" сохраняется для UI/debug совместимости.

# --- Сигналы ---
## Питание включено/выключено (для визуала и логики владельца).
signal powered_changed(is_powered: bool)
## Изменилась конфигурация потребителя, влияющая на power balance.
signal configuration_changed()

# --- Перечисления ---
## Приоритет отключения при дефиците.
## Чем ниже число — тем позже отключат (критичнее).
enum Priority {
	CRITICAL = 0,    ## Шлюз, жизнеобеспечение — отключается последним
	HIGH = 1,        ## Компрессор, обогрев
	MEDIUM = 2,      ## Электропечь, верстак, серверная
	LOW = 3,         ## Освещение, декор — отключается первым
}

# --- Экспортируемые ---
## Потребление в ваттах.
@export var demand: float = 50.0
## Приоритет при дефиците.
@export var priority: Priority = Priority.MEDIUM

# --- Публичные ---
## Получает ли постройка электричество прямо сейчас.
var is_powered: bool = false

# --- Приватные ---
var _power_system: PowerSystem = null

func _ready() -> void:
	add_to_group("power_consumers")
	call_deferred("_register_with_power_system")

func _exit_tree() -> void:
	_unregister_from_power_system()

## Включить/выключить питание (вызывается PowerSystem).
func set_powered(powered: bool) -> void:
	if powered != is_powered:
		is_powered = powered
		powered_changed.emit(is_powered)

func set_demand(new_demand: float) -> void:
	if is_equal_approx(new_demand, demand):
		return
	demand = new_demand
	configuration_changed.emit()

func set_priority(new_priority: Priority) -> void:
	if new_priority == priority:
		return
	priority = new_priority
	configuration_changed.emit()

func save_state() -> Dictionary:
	return {"powered": is_powered, "demand": demand, "priority": priority}

func load_state(data: Dictionary) -> void:
	var config_changed: bool = false
	var new_demand: float = data.get("demand", demand)
	if not is_equal_approx(new_demand, demand):
		demand = new_demand
		config_changed = true
	var new_priority: Priority = data.get("priority", priority) as Priority
	if new_priority != priority:
		priority = new_priority
		config_changed = true
	is_powered = data.get("powered", false)
	if config_changed:
		configuration_changed.emit()

func _register_with_power_system() -> void:
	if _power_system and is_instance_valid(_power_system):
		return
	var systems: Array[Node] = get_tree().get_nodes_in_group("power_system")
	if systems.is_empty():
		return
	_power_system = systems[0] as PowerSystem
	if _power_system:
		_power_system.register_consumer(self)

func _unregister_from_power_system() -> void:
	if _power_system and is_instance_valid(_power_system):
		_power_system.unregister_consumer(self)
	_power_system = null
