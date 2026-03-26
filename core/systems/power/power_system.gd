class_name PowerSystem
extends Node
## ╨б╨╕╤Б╤В╨╡╨╝╨░ ╤Н╨╗╨╡╨║╤В╤А╨╕╤З╨╡╤Б╤В╨▓╨░. ╨б╤З╨╕╤В╨░╨╡╤В ╨╛╨▒╤Й╨╕╨╣ ╨▒╨░╨╗╨░╨╜╤Б
## ╨│╨╡╨╜╨╡╤А╨░╤Ж╨╕╨╕ ╨╕ ╨┐╨╛╤В╤А╨╡╨▒╨╗╨╡╨╜╨╕╤П. ╨Я╤А╨╕ ╨┤╨╡╤Д╨╕╤Ж╨╕╤В╨╡ тАФ ╨╛╤В╨║╨╗╤О╤З╨░╨╡╤В
## ╨┐╨╛╤В╤А╨╡╨▒╨╕╤В╨╡╨╗╨╡╨╣ ╨┐╨╛ ╨┐╤А╨╕╨╛╤А╨╕╤В╨╡╤В╤Г (LOW ╨┐╨╡╤А╨▓╤Л╨╝, CRITICAL ╨┐╨╛╤Б╨╗╨╡╨┤╨╜╨╕╨╝).
##
## ╨Э╨╡ ╨╖╨╜╨░╨╡╤В ╨╛ ╨║╨╛╨╜╨║╤А╨╡╤В╨╜╤Л╤Е ╨│╨╡╨╜╨╡╤А╨░╤В╨╛╤А╨░╤Е тАФ ╤В╨╛╨╗╤М╨║╨╛ ╨╛ ╨║╨╛╨╝╨┐╨╛╨╜╨╡╨╜╤В╨░╤Е
## PowerSourceComponent ╨╕ PowerConsumerComponent.
## ╨Ю╨▒╤Й╨░╨╡╤В╤Б╤П ╤З╨╡╤А╨╡╨╖ EventBus.
# --- ╨Ъ╨╛╨╜╤Б╤В╨░╨╜╤В╤Л ---
const BALANCE_PATH: String = "res://data/balance/power_balance.tres"
# --- ╨Я╤Г╨▒╨╗╨╕╤З╨╜╤Л╨╡ ---
var balance: PowerBalance = null
## ╨в╨╡╨║╤Г╤Й╨░╤П ╤Б╤Г╨╝╨╝╨░╤А╨╜╨░╤П ╨│╨╡╨╜╨╡╤А╨░╤Ж╨╕╤П (╨Т╤В).
var total_supply: float = 0.0
## ╨в╨╡╨║╤Г╤Й╨╡╨╡ ╤Б╤Г╨╝╨╝╨░╤А╨╜╨╛╨╡ ╨┐╨╛╤В╤А╨╡╨▒╨╗╨╡╨╜╨╕╨╡ (╨Т╤В).
var total_demand: float = 0.0
## ╨Х╤Б╤В╤М ╨╗╨╕ ╨┤╨╡╤Д╨╕╤Ж╨╕╤В ╨┐╤А╤П╨╝╨╛ ╤Б╨╡╨╣╤З╨░╤Б.
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
# --- ╨Я╤Г╨▒╨╗╨╕╤З╨╜╤Л╨╡ ╨╝╨╡╤В╨╛╨┤╤Л ---
## ╨Я╤А╨╕╨╜╤Г╨┤╨╕╤В╨╡╨╗╤М╨╜╤Л╨╣ ╨┐╨╡╤А╨╡╤Б╤З╤С╤В (╨┐╨╛╤Б╨╗╨╡ ╨┐╨╛╤Б╤В╤А╨╛╨╣╨║╨╕/╤Б╨╜╨╛╤Б╨░ ╨│╨╡╨╜╨╡╤А╨░╤В╨╛╤А╨░).
func force_recalculate() -> void:
	_recalculate_balance()
## ╨Я╨╛╨╗╤Г╤З╨╕╤В╤М ╨▒╨░╨╗╨░╨╜╤Б: ╨┐╨╛╨╗╨╛╨╢╨╕╤В╨╡╨╗╤М╨╜╤Л╨╣ = ╨╕╨╖╨╗╨╕╤И╨╡╨║, ╨╛╤В╤А╨╕╤Ж╨░╤В╨╡╨╗╤М╨╜╤Л╨╣ = ╨┤╨╡╤Д╨╕╤Ж╨╕╤В.
func get_balance() -> float:
	return total_supply - total_demand
## ╨Я╨╛╨╗╤Г╤З╨╕╤В╤М ╨┐╤А╨╛╤Ж╨╡╨╜╤В ╨╛╨▒╨╡╤Б╨┐╨╡╤З╨╡╨╜╨╜╨╛╤Б╤В╨╕ (0.0тАУ1.0+).
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
	# ╨б╨╛╨▒╨╕╤А╨░╨╡╨╝ ╨▓╤Б╨╡ ╨╕╤Б╤В╨╛╤З╨╜╨╕╨║╨╕
	var sources: Array[Node] = get_tree().get_nodes_in_group("power_sources")
	total_supply = 0.0
	for node: Node in sources:
		var src: PowerSourceComponent = node as PowerSourceComponent
		if src and src.is_enabled:
			total_supply += src.current_output
	# ╨б╨╛╨▒╨╕╤А╨░╨╡╨╝ ╨▓╤Б╨╡╤Е ╨┐╨╛╤В╤А╨╡╨▒╨╕╤В╨╡╨╗╨╡╨╣
	var consumers: Array[Node] = get_tree().get_nodes_in_group("power_consumers")
	total_demand = 0.0
	for node: Node in consumers:
		var con: PowerConsumerComponent = node as PowerConsumerComponent
		if con:
			total_demand += con.demand
	# ╨Ю╨┐╤А╨╡╨┤╨╡╨╗╤П╨╡╨╝ ╤Б╨╛╤Б╤В╨╛╤П╨╜╨╕╨╡
	is_deficit = total_supply < total_demand
	# ╨г╨┐╤А╨░╨▓╨╗╤П╨╡╨╝ ╨┐╨╕╤В╨░╨╜╨╕╨╡╨╝ ╨┐╨╛╤В╤А╨╡╨▒╨╕╤В╨╡╨╗╨╡╨╣
	if is_deficit:
		_apply_brownout(consumers)
	else:
		_power_all(consumers)
	# ╨Ю╨┐╨╛╨▓╨╡╤Й╨░╨╡╨╝
	EventBus.power_changed.emit(total_supply, total_demand)
	if is_deficit and not _was_deficit:
		EventBus.power_deficit.emit(total_demand - total_supply)
	elif not is_deficit and _was_deficit:
		EventBus.power_restored.emit()
	_was_deficit = is_deficit
## ╨Т╨║╨╗╤О╤З╨╕╤В╤М ╨▓╤Б╨╡ ╨┐╨╛╤В╤А╨╡╨▒╨╕╤В╨╡╨╗╨╕ (╤Е╨▓╨░╤В╨░╨╡╤В ╤Н╨╜╨╡╤А╨│╨╕╨╕).
func _power_all(consumers: Array[Node]) -> void:
	for node: Node in consumers:
		var con: PowerConsumerComponent = node as PowerConsumerComponent
		if con:
			con.set_powered(true)
## ╨Ю╤В╨║╨╗╤О╤З╨╕╤В╤М ╨┐╨╛╤В╤А╨╡╨▒╨╕╤В╨╡╨╗╨╡╨╣ ╨┐╨╛ ╨┐╤А╨╕╨╛╤А╨╕╤В╨╡╤В╤Г ╨┤╨╛ ╨▒╨░╨╗╨░╨╜╤Б╨░.
func _apply_brownout(consumers: Array[Node]) -> void:
	# ╨б╨╛╤А╤В╨╕╤А╤Г╨╡╨╝: LOW (3) ╨┐╨╡╤А╨▓╤Л╨╝╨╕, CRITICAL (0) ╨┐╨╛╤Б╨╗╨╡╨┤╨╜╨╕╨╝╨╕
	var sorted: Array[PowerConsumerComponent] = []
	for node: Node in consumers:
		var con: PowerConsumerComponent = node as PowerConsumerComponent
		if con:
			sorted.append(con)
	sorted.sort_custom(func(a: PowerConsumerComponent, b: PowerConsumerComponent) -> bool:
		return a.priority > b.priority  # ╨Т╤Л╤Б╨╛╨║╨╕╨╣ ╨┐╤А╨╕╨╛╤А╨╕╤В╨╡╤В-╤З╨╕╤Б╨╗╨╛ = LOW = ╨╛╤В╨║╨╗╤О╤З╨░╨╡╨╝ ╨┐╨╡╤А╨▓╤Л╨╝
	)
	var remaining_power: float = total_supply
	for con: PowerConsumerComponent in sorted:
		if remaining_power >= con.demand:
			con.set_powered(true)
			remaining_power -= con.demand
		else:
			con.set_powered(false)