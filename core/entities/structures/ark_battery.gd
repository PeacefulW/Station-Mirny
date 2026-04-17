class_name ArkBattery
extends StaticBody2D

## Аварийная батарея Ковчега. Найдена в обломках корабля.
## Конечный ресурс: заряд тратится, когда кончится — навсегда.
## Бесшумная, стабильная, надёжная. «Наша технология».

const DEFAULT_TILE_SIZE_PX: int = 12

# --- Публичные ---
## Оставшийся заряд (Вт⋅ч).
var charge_remaining: float = 2000.0
## Максимальная ёмкость (Вт⋅ч).
var charge_max: float = 2000.0
## Позиция на сетке.
var grid_pos: Vector2i = Vector2i.ZERO

# --- Приватные ---
var _power_source: PowerSourceComponent = null
var _health: HealthComponent = null
var _visual: ColorRect = null
var _depleted: bool = false

func _ready() -> void:
	add_to_group("buildings")
	collision_layer = 2
	collision_mask = 0

## Настроить батарею. Вызывается при размещении.
func setup(p_grid_pos: Vector2i, world_pos: Vector2, balance: PowerBalance) -> void:
	grid_pos = p_grid_pos
	global_position = world_pos
	charge_max = balance.ark_battery_capacity
	charge_remaining = charge_max
	# Визуал
	var tile_px: int = DEFAULT_TILE_SIZE_PX
	var size: int = balance.building_tile_size * tile_px
	_visual = ColorRect.new()
	_visual.size = Vector2(size, size)
	_visual.position = -Vector2(size, size) * 0.5
	_visual.color = balance.ark_battery_color
	add_child(_visual)
	# Коллизия
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(size, size)
	col.shape = shape
	add_child(col)
	# Здоровье
	_health = HealthComponent.new()
	_health.name = "HealthComponent"
	_health.max_health = 80.0
	add_child(_health)
	_health.died.connect(_on_destroyed)
	# Источник энергии
	_power_source = PowerSourceComponent.new()
	_power_source.name = "PowerSource"
	add_child(_power_source)
	_power_source.set_max_output(balance.ark_battery_output)

func _process(delta: float) -> void:
	if _depleted or not _power_source or not _power_source.is_enabled:
		return
	# Расход заряда: мощность (Вт) × время (ч)
	var drain: float = _power_source.current_output * (delta / 3600.0)
	charge_remaining -= drain
	if charge_remaining <= 0.0:
		charge_remaining = 0.0
		_depleted = true
		_power_source.force_shutdown()
		_update_visual()

## Получить заряд в процентах.
func get_charge_percent() -> float:
	if charge_max <= 0.0:
		return 0.0
	return charge_remaining / charge_max

func save_state() -> Dictionary:
	return {
		"type": "ark_battery",
		"grid_x": grid_pos.x, "grid_y": grid_pos.y,
		"charge": charge_remaining, "depleted": _depleted,
	}

func load_state(data: Dictionary) -> void:
	charge_remaining = data.get("charge", charge_max)
	_depleted = data.get("depleted", false)
	if _depleted and _power_source:
		_power_source.force_shutdown()
	_update_visual()

func _update_visual() -> void:
	if not _visual:
		return
	if _depleted:
		_visual.color = Color(0.25, 0.25, 0.25)
	else:
		var t: float = get_charge_percent()
		_visual.color = Color(0.25 + 0.05 * t, 0.35 + 0.15 * t, 0.5 + 0.3 * t)

func _on_destroyed() -> void:
	if _power_source:
		_power_source.force_shutdown()
	EventBus.building_removed.emit(grid_pos)
	queue_free()
