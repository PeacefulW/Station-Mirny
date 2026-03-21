class_name OxygenSystem
extends Node

## Система кислорода. Прикрепляется к игроку.
## Снаружи базы O₂ расходуется, внутри — восполняется.
## Не знает о других системах — общается через EventBus.

# --- Сигналы ---
signal speed_modifier_changed(modifier: float)

# --- Экспортируемые ---
@export var balance: SurvivalBalance = null

# --- Приватные ---
var _current_oxygen: float = 0.0
var _is_indoor: bool = false
var _is_depleting: bool = false
var _is_base_powered: bool = false

func _ready() -> void:
	if not balance:
		push_error(Localization.t("SYSTEM_OXYGEN_BALANCE_MISSING"))
		return
	_current_oxygen = balance.max_oxygen
	EventBus.rooms_recalculated.connect(_on_rooms_recalculated)
	EventBus.life_support_power_changed.connect(_on_life_support_power_changed)
	_emit_oxygen_state()

func _process(delta: float) -> void:
	if not balance:
		return
	# TODO: вернуть когда закончим тесты генерации
	#_update_oxygen(delta)
	#_apply_effects()

## Получить текущий O₂ в процентах (0.0 — 1.0).
func get_oxygen_percent() -> float:
	if not balance or balance.max_oxygen <= 0.0:
		return 0.0
	return _current_oxygen / balance.max_oxygen

## Установить статус "внутри/снаружи" напрямую.
func set_indoor(indoor: bool) -> void:
	if _is_indoor == indoor:
		return
	_is_indoor = indoor
	if indoor:
		EventBus.player_entered_indoor.emit()
	else:
		EventBus.player_exited_indoor.emit()

func set_base_powered(powered: bool) -> void:
	_is_base_powered = powered

## Сохранить состояние кислорода.
func save_state() -> Dictionary:
	return {
		"current_oxygen": _current_oxygen,
		"is_indoor": _is_indoor,
		"is_base_powered": _is_base_powered,
	}

## Восстановить состояние кислорода.
func load_state(data: Dictionary) -> void:
	if not balance:
		return
	_current_oxygen = clampf(
		float(data.get("current_oxygen", balance.max_oxygen)),
		0.0,
		balance.max_oxygen
	)
	_is_indoor = bool(data.get("is_indoor", false))
	_is_base_powered = bool(data.get("is_base_powered", false))
	_is_depleting = false
	_emit_oxygen_state()
	_apply_effects()

# --- Приватные методы ---

func _update_oxygen(delta: float) -> void:
	var old_oxygen: float = _current_oxygen
	if _is_indoor:
		if _is_base_powered:
			_current_oxygen = minf(
				_current_oxygen + balance.oxygen_refill_rate * delta,
				balance.max_oxygen
			)
		else:
			_current_oxygen = maxf(
				_current_oxygen - balance.oxygen_unpowered_indoor_drain_rate * delta,
				0.0
			)
	else:
		_current_oxygen = maxf(
			_current_oxygen - balance.oxygen_drain_rate * delta,
			0.0
		)
	if not is_equal_approx(old_oxygen, _current_oxygen):
		_emit_oxygen_state()

func _apply_effects() -> void:
	var percent: float = get_oxygen_percent()
	# Предупреждение о низком O₂
	if percent <= balance.low_oxygen_threshold and not _is_depleting:
		_is_depleting = true
		EventBus.oxygen_depleting.emit(percent)
	elif percent > balance.low_oxygen_threshold:
		_is_depleting = false
	# Модификатор скорости
	var modifier: float = 1.0
	if percent <= balance.low_oxygen_threshold and percent > balance.blackout_threshold:
		var t: float = percent / balance.low_oxygen_threshold
		modifier = lerpf(balance.speed_penalty_at_low_oxygen, 1.0, t)
	elif percent <= balance.blackout_threshold:
		modifier = balance.speed_penalty_at_low_oxygen * 0.5
	speed_modifier_changed.emit(modifier)

func _emit_oxygen_state() -> void:
	if balance:
		EventBus.oxygen_changed.emit(_current_oxygen, balance.max_oxygen)

func _on_rooms_recalculated(_indoor_cells: Dictionary) -> void:
	# Пересчёт статуса будет вызван из game_world
	pass

func _on_life_support_power_changed(is_powered: bool) -> void:
	_is_base_powered = is_powered
