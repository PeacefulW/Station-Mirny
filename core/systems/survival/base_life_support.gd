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
	_consumer.demand = demand
	_consumer.priority = PowerConsumerComponent.Priority.CRITICAL
	add_child(_consumer)
	_consumer.powered_changed.connect(_on_powered_changed)
	_emit_state()

func is_powered() -> bool:
	return _consumer != null and _consumer.is_powered

func _on_powered_changed(powered: bool) -> void:
	EventBus.life_support_power_changed.emit(powered)

func _emit_state() -> void:
	EventBus.life_support_power_changed.emit(is_powered())
