class_name HealthComponent
extends Node

## Компонент здоровья. Прикрепляется к любой сущности,
## которая может получать урон и умирать.

signal health_changed(new_health: float, max_health: float)
signal died()

@export var max_health: float = 100.0

var current_health: float = 0.0

func _ready() -> void:
	restore_state(max_health, max_health)

## Нанести урон. Возвращает true если сущность погибла.
func take_damage(amount: float) -> bool:
	restore_state(current_health - amount, max_health)
	if current_health <= 0.0:
		died.emit()
		return true
	return false

## Восстановить здоровье.
func heal(amount: float) -> void:
	restore_state(current_health + amount, max_health)

## Получить здоровье в процентах (0.0 — 1.0).
func get_health_percent() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health

func restore_state(new_current_health: float, new_max_health: float) -> void:
	max_health = maxf(new_max_health, 0.0)
	current_health = clampf(new_current_health, 0.0, max_health)
	health_changed.emit(current_health, max_health)
