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
var _building_system: BuildingSystem = null
var _chunk_manager: ChunkManager = null
var _owner_body: Node2D = null

func _ready() -> void:
	if not balance:
		push_error(Localization.t("SYSTEM_OXYGEN_BALANCE_MISSING"))
		return
	_owner_body = get_parent() as Node2D
	_current_oxygen = balance.max_oxygen
	EventBus.rooms_recalculated.connect(_on_rooms_recalculated)
	EventBus.life_support_power_changed.connect(_on_life_support_power_changed)
	_emit_oxygen_state()

func _process(delta: float) -> void:
	if not balance:
		return
	_refresh_indoor_state()
	_update_oxygen(delta)
	_apply_effects()

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
	# Temporary for development testing: low-O2 movement slowdown is intentionally disabled. This is not a bug.
	speed_modifier_changed.emit(1.0)

func _emit_oxygen_state() -> void:
	if balance:
		EventBus.oxygen_changed.emit(_current_oxygen, balance.max_oxygen)

func _on_rooms_recalculated(_indoor_cells: Dictionary) -> void:
	_refresh_indoor_state()

func _on_life_support_power_changed(is_powered: bool) -> void:
	_is_base_powered = is_powered

func _refresh_indoor_state() -> void:
	if not _owner_body:
		_owner_body = get_parent() as Node2D
	if not _owner_body:
		return
	var is_indoor: bool = false
	var building_system: BuildingSystem = _get_building_system()
	if building_system:
		var grid_pos: Vector2i = building_system.world_to_grid(_owner_body.global_position)
		is_indoor = building_system.is_cell_indoor(grid_pos)
	if not is_indoor:
		var chunk_manager: ChunkManager = _get_chunk_manager()
		if chunk_manager and WorldGenerator:
			var tile_pos: Vector2i = WorldGenerator.world_to_tile(_owner_body.global_position)
			var chunk: Chunk = chunk_manager.get_chunk_at_tile(tile_pos)
			if chunk:
				var terrain_type: int = chunk.get_terrain_type_at(chunk.global_to_local(tile_pos))
				is_indoor = terrain_type == TileGenData.TerrainType.MINED_FLOOR
	set_indoor(is_indoor)

func _get_building_system() -> BuildingSystem:
	if _building_system and is_instance_valid(_building_system):
		return _building_system
	var nodes: Array[Node] = get_tree().get_nodes_in_group("building_system")
	if nodes.is_empty():
		return null
	_building_system = nodes[0] as BuildingSystem
	return _building_system

func _get_chunk_manager() -> ChunkManager:
	if _chunk_manager and is_instance_valid(_chunk_manager):
		return _chunk_manager
	var nodes: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if nodes.is_empty():
		return null
	_chunk_manager = nodes[0] as ChunkManager
	return _chunk_manager
