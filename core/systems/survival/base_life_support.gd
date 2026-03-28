class_name BaseLifeSupport
extends Node

## Базовый потребитель энергии станции.
## Пока сеть питает жизнеобеспечение, кислород внутри базы восстанавливается.

@export var demand: float = 40.0

var _consumer: PowerConsumerComponent = null

func _ready() -> void:
	name = "BaseLifeSupport"
	add_to_group("life_support")
	_consumer = PowerConsumerComponent.new()
	_consumer.name = "PowerConsumer"
	add_child(_consumer)
	set_power_demand(demand)
	_consumer.set_priority(PowerConsumerComponent.Priority.CRITICAL)
	_consumer.powered_changed.connect(_on_powered_changed)
	_emit_state()

func is_powered() -> bool:
	return _consumer != null and _consumer.is_powered

func set_power_demand(new_demand: float) -> void:
	demand = maxf(new_demand, 0.0)
	if _consumer:
		_consumer.set_demand(demand)

func get_power_demand() -> float:
	return demand

func _on_powered_changed(powered: bool) -> void:
	EventBus.life_support_power_changed.emit(powered)

func _emit_state() -> void:
	EventBus.life_support_power_changed.emit(is_powered())
