class_name PowerSourceComponent
extends Node

## Компонент источника энергии. Прикрепляется к любой
## постройке, производящей ватты (батареи, термосжигатель,
## ферментатор, сейсмоуловитель...).
## PowerSystem получает его через explicit register/unregister.
## Группа "power_sources" сохраняется для UI/debug совместимости.

# --- Сигналы ---
signal output_changed(new_output: float)

# --- Экспортируемые ---
## Максимальная выходная мощность (Вт).
@export var max_output: float = 100.0

# --- Публичные ---
## Текущая реальная выработка.
var current_output: float = 0.0
## Включён ли источник.
var is_enabled: bool = true
## Множитель от внешних условий (0.0–1.0).
## Погода, сейсмоактивность, топливо и т.д.
var condition_multiplier: float = 1.0

# --- Приватные ---
var _power_system: PowerSystem = null

func _ready() -> void:
	add_to_group("power_sources")
	_recalculate()
	call_deferred("_register_with_power_system")

func _exit_tree() -> void:
	_unregister_from_power_system()

## Задать множитель условий (вызывается владельцем).
func set_condition(multiplier: float) -> void:
	condition_multiplier = clampf(multiplier, 0.0, 1.0)
	_recalculate()

func set_max_output(output: float) -> void:
	max_output = maxf(output, 0.0)
	_recalculate()

## Включить/выключить.
func set_enabled(enabled: bool) -> void:
	is_enabled = enabled
	_recalculate()

## Аварийное отключение (топливо кончилось, батарея села).
func force_shutdown() -> void:
	is_enabled = false
	current_output = 0.0
	output_changed.emit(0.0)

func save_state() -> Dictionary:
	return {"enabled": is_enabled, "output": current_output, "condition": condition_multiplier}

func load_state(data: Dictionary) -> void:
	is_enabled = data.get("enabled", true)
	condition_multiplier = data.get("condition", 1.0)
	_recalculate()

func refresh_from_config() -> void:
	_recalculate()

func _register_with_power_system() -> void:
	if _power_system and is_instance_valid(_power_system):
		return
	var systems: Array[Node] = get_tree().get_nodes_in_group("power_system")
	if systems.is_empty():
		return
	_power_system = systems[0] as PowerSystem
	if _power_system:
		_power_system.register_source(self)

func _unregister_from_power_system() -> void:
	if _power_system and is_instance_valid(_power_system):
		_power_system.unregister_source(self)
	_power_system = null

func _recalculate() -> void:
	var new_val: float = max_output * condition_multiplier if is_enabled else 0.0
	if not is_equal_approx(new_val, current_output):
		current_output = new_val
		output_changed.emit(current_output)
