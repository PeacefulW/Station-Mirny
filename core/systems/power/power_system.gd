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
var _was_deficit: bool = false
var _is_dirty: bool = true
var _power_job_id: StringName = &""
var _heartbeat_timer: float = 0.0
const _HEARTBEAT_INTERVAL: float = 5.0

func _ready() -> void:
	balance = load(BALANCE_PATH) as PowerBalance
	if not balance:
		push_error(Localization.t("SYSTEM_POWER_BALANCE_LOAD_FAILED", {"path": BALANCE_PATH}))
	EventBus.building_placed.connect(func(_pos: Vector2i) -> void: _mark_power_dirty())
	EventBus.building_removed.connect(func(_pos: Vector2i) -> void: _mark_power_dirty())
	_power_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_TOPOLOGY,
		1.0,
		_power_recompute_tick,
		&"power.balance_recompute",
		RuntimeWorkTypes.CadenceKind.NEAR_PLAYER,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"Power balance recompute"
	)

func _exit_tree() -> void:
	if _power_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_power_job_id)

func _process(delta: float) -> void:
	if not balance:
		return
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = _HEARTBEAT_INTERVAL
		_is_dirty = true

# --- Публичные методы ---

## Принудительный пересчёт (после постройки/сноса генератора). Boot/load only.
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

func _mark_power_dirty() -> void:
	_is_dirty = true

func _power_recompute_tick() -> bool:
	if not _is_dirty:
		return false
	_is_dirty = false
	_recalculate_balance()
	return false

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
