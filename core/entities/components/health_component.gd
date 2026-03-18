class_name HealthComponent
extends Node

## Компонент здоровья. Прикрепляется к любой сущности,
## которая может получать урон и умирать.

signal health_changed(new_health: float, max_health: float)
signal died()

@export var max_health: float = 100.0

var current_health: float = 0.0

func _ready() -> void:
	current_health = max_health

## Нанести урон. Возвращает true если сущность погибла.
func take_damage(amount: float) -> bool:
	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		died.emit()
		return true
	return false

## Восстановить здоровье.
func heal(amount: float) -> void:
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

## Получить здоровье в процентах (0.0 — 1.0).
func get_health_percent() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health
