class_name PowerSystem
extends Node

## Система электричества. Считает общий баланс
## генерации и потребления. При дефиците — отключает
## потребителей по приоритету (LOW первым, CRITICAL последним).
##
## Не знает о конкретных генераторах — только о компонентах
## PowerSourceComponent и PowerConsumerComponent.
## Общается через EventBus.

# --- Константы ---
const BALANCE_PATH: String = "res://data/balance/power_balance.tres"

# --- Публичные ---
var balance: PowerBalance = null
## Текущая суммарная генерация (Вт).
var total_supply: float = 0.0
## Текущее суммарное потребление (Вт).
var total_demand: float = 0.0
## Есть ли дефицит прямо сейчас.
var is_deficit: bool = false

# --- Приватные ---
var _update_timer: float = 0.0
var _was_deficit: bool = false

func _ready() -> void:
	balance = load(BALANCE_PATH) as PowerBalance
	if not balance:
		push_error("PowerSystem: не удалось загрузить %s" % BALANCE_PATH)

func _process(delta: float) -> void:
	if not balance:
		return
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = balance.update_interval
		_recalculate_balance()

# --- Публичные методы ---

## Принудительный пересчёт (после постройки/сноса генератора).
func force_recalculate() -> void:
	_recalculate_balance()

## Получить баланс: положительный = излишек, отрицательный = дефицит.
func get_balance() -> float:
	return total_supply - total_demand

## Получить процент обеспеченности (0.0–1.0+).
func get_supply_ratio() -> float:
	if total_demand <= 0.0:
		return 1.0
	return total_supply / total_demand

func save_state() -> Dictionary:
	return {
		"supply": total_supply,
		"demand": total_demand,
		"deficit": is_deficit,
	}

# --- Приватные методы ---

func _recalculate_balance() -> void:
	# Собираем все источники
	var sources: Array[Node] = get_tree().get_nodes_in_group("power_sources")
	total_supply = 0.0
	for node: Node in sources:
		var src: PowerSourceComponent = node as PowerSourceComponent
		if src and src.is_enabled:
			total_supply += src.current_output

	# Собираем всех потребителей
	var consumers: Array[Node] = get_tree().get_nodes_in_group("power_consumers")
	total_demand = 0.0
	for node: Node in consumers:
		var con: PowerConsumerComponent = node as PowerConsumerComponent
		if con:
			total_demand += con.demand

	# Определяем состояние
	is_deficit = total_supply < total_demand

	# Управляем питанием потребителей
	if is_deficit:
		_apply_brownout(consumers)
	else:
		_power_all(consumers)

	# Оповещаем
	EventBus.power_changed.emit(total_supply, total_demand)
	if is_deficit and not _was_deficit:
		EventBus.power_deficit.emit(total_demand - total_supply)
	elif not is_deficit and _was_deficit:
		EventBus.power_restored.emit()
	_was_deficit = is_deficit

## Включить все потребители (хватает энергии).
func _power_all(consumers: Array[Node]) -> void:
	for node: Node in consumers:
		var con: PowerConsumerComponent = node as PowerConsumerComponent
		if con:
			con.set_powered(true)

## Отключить потребителей по приоритету до баланса.
func _apply_brownout(consumers: Array[Node]) -> void:
	# Сортируем: LOW (3) первыми, CRITICAL (0) последними
	var sorted: Array[PowerConsumerComponent] = []
	for node: Node in consumers:
		var con: PowerConsumerComponent = node as PowerConsumerComponent
		if con:
			sorted.append(con)
	sorted.sort_custom(func(a: PowerConsumerComponent, b: PowerConsumerComponent) -> bool:
		return a.priority > b.priority  # Высокий приоритет-число = LOW = отключаем первым
	)

	var remaining_power: float = total_supply
	for con: PowerConsumerComponent in sorted:
		if remaining_power >= con.demand:
			con.set_powered(true)
			remaining_power -= con.demand
		else:
			con.set_powered(false)
