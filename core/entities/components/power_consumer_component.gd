class_name PowerConsumerComponent
extends Node

## Компонент потребителя энергии. Прикрепляется к любой
## постройке, которая нуждается в электричестве (компрессор,
## электропечь, сервер дешифровки, турель, освещение...).
## PowerSystem находит потребителей через группу "power_consumers".

# --- Сигналы ---
## Питание включено/выключено (для визуала и логики владельца).
signal powered_changed(is_powered: bool)

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

func _ready() -> void:
	add_to_group("power_consumers")

## Включить/выключить питание (вызывается PowerSystem).
func set_powered(powered: bool) -> void:
	if powered != is_powered:
		is_powered = powered
		powered_changed.emit(is_powered)

func save_state() -> Dictionary:
	return {"powered": is_powered, "demand": demand, "priority": priority}

func load_state(data: Dictionary) -> void:
	demand = data.get("demand", demand)
	priority = data.get("priority", priority) as Priority
	is_powered = data.get("powered", false)
