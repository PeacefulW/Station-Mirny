class_name PowerSystem
extends Node
## Система электричества. Считает общий баланс
## генерации и потребления. При дефиците — отключает
## потребителей по приоритету (LOW первым, CRITICAL последним).
##
## Авторитетный runtime state хранится внутри registry источников
## и потребителей, а не через повторные scene-tree scans.
## Общается через EventBus.

# --- Константы ---
const BALANCE_PATH: String = "res://data/balance/power_balance.tres"
const _HEARTBEAT_INTERVAL: float = 5.0

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
var _registered_sources: Dictionary = {}
var _registered_consumers: Dictionary = {}

func _ready() -> void:
	add_to_group("power_system")
	balance = load(BALANCE_PATH) as PowerBalance
	if not balance:
		push_error(Localization.t("SYSTEM_POWER_BALANCE_LOAD_FAILED", {"path": BALANCE_PATH}))
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
		_mark_power_dirty()

# --- Публичные методы ---

func register_source(source: PowerSourceComponent) -> void:
	if not source or _registered_sources.has(source):
		return
	_registered_sources[source] = true
	if not source.output_changed.is_connected(_on_source_output_changed):
		source.output_changed.connect(_on_source_output_changed)
	_mark_power_dirty()

func unregister_source(source: PowerSourceComponent) -> void:
	if not source or not _registered_sources.has(source):
		return
	if source.output_changed.is_connected(_on_source_output_changed):
		source.output_changed.disconnect(_on_source_output_changed)
	_registered_sources.erase(source)
	_mark_power_dirty()

func register_consumer(consumer: PowerConsumerComponent) -> void:
	if not consumer or _registered_consumers.has(consumer):
		return
	_registered_consumers[consumer] = true
	if not consumer.configuration_changed.is_connected(_on_consumer_configuration_changed):
		consumer.configuration_changed.connect(_on_consumer_configuration_changed)
	_mark_power_dirty()

func unregister_consumer(consumer: PowerConsumerComponent) -> void:
	if not consumer or not _registered_consumers.has(consumer):
		return
	if consumer.configuration_changed.is_connected(_on_consumer_configuration_changed):
		consumer.configuration_changed.disconnect(_on_consumer_configuration_changed)
	_registered_consumers.erase(consumer)
	_mark_power_dirty()

## Принудительный пересчёт (после boot/load). Boot/load only.
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

func has_pending_recompute() -> bool:
	return _is_dirty

func get_registered_source_count() -> int:
	return _registered_sources.size()

func get_registered_consumer_count() -> int:
	return _registered_consumers.size()

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
	var sources: Array[PowerSourceComponent] = _collect_registered_sources()
	var consumers: Array[PowerConsumerComponent] = _collect_registered_consumers()
	total_supply = 0.0
	for source: PowerSourceComponent in sources:
		if source.is_enabled:
			total_supply += source.current_output
	total_demand = 0.0
	for consumer: PowerConsumerComponent in consumers:
		total_demand += consumer.demand
	is_deficit = total_supply < total_demand
	if is_deficit:
		_apply_brownout(consumers)
	else:
		_power_all(consumers)
	EventBus.power_changed.emit(total_supply, total_demand)
	if is_deficit and not _was_deficit:
		EventBus.power_deficit.emit(total_demand - total_supply)
	elif not is_deficit and _was_deficit:
		EventBus.power_restored.emit()
	_was_deficit = is_deficit

func _collect_registered_sources() -> Array[PowerSourceComponent]:
	var sources: Array[PowerSourceComponent] = []
	var stale: Array[PowerSourceComponent] = []
	for source: PowerSourceComponent in _registered_sources.keys():
		if not is_instance_valid(source):
			stale.append(source)
			continue
		sources.append(source)
	for source: PowerSourceComponent in stale:
		_registered_sources.erase(source)
	return sources

func _collect_registered_consumers() -> Array[PowerConsumerComponent]:
	var consumers: Array[PowerConsumerComponent] = []
	var stale: Array[PowerConsumerComponent] = []
	for consumer: PowerConsumerComponent in _registered_consumers.keys():
		if not is_instance_valid(consumer):
			stale.append(consumer)
			continue
		consumers.append(consumer)
	for consumer: PowerConsumerComponent in stale:
		_registered_consumers.erase(consumer)
	return consumers

func _power_all(consumers: Array[PowerConsumerComponent]) -> void:
	for consumer: PowerConsumerComponent in consumers:
		consumer.set_powered(true)

func _apply_brownout(consumers: Array[PowerConsumerComponent]) -> void:
	var sorted: Array[PowerConsumerComponent] = consumers.duplicate()
	sorted.sort_custom(func(a: PowerConsumerComponent, b: PowerConsumerComponent) -> bool:
		return a.priority > b.priority
	)
	var remaining_power: float = total_supply
	for consumer: PowerConsumerComponent in sorted:
		if remaining_power >= consumer.demand:
			consumer.set_powered(true)
			remaining_power -= consumer.demand
		else:
			consumer.set_powered(false)

func _on_source_output_changed(_new_output: float) -> void:
	_mark_power_dirty()

func _on_consumer_configuration_changed() -> void:
	_mark_power_dirty()
