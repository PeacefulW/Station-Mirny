class_name PowerSourceComponent
extends Node

## Компонент источника энергии. Прикрепляется к любой
## постройке, производящей ватты (батареи, термосжигатель,
## ферментатор, сейсмоуловитель...).
## PowerSystem находит все источники через группу "power_sources".

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

func _ready() -> void:
	add_to_group("power_sources")
	_recalculate()

## Задать множитель условий (вызывается владельцем).
func set_condition(multiplier: float) -> void:
	condition_multiplier = clampf(multiplier, 0.0, 1.0)
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

func _recalculate() -> void:
	var new_val: float = max_output * condition_multiplier if is_enabled else 0.0
	if not is_equal_approx(new_val, current_output):
		current_output = new_val
		output_changed.emit(current_output)
