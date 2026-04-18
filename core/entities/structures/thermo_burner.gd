class_name ThermoBurner
extends StaticBody2D

## Термосжигатель. Примитивная печь, сжигающая местную биомассу.
## Единственный «земной» генератор — дальше всё будет чужим.
## ШУМНЫЙ: привлекает Очистителей. Нужно топливо.

const DEFAULT_TILE_SIZE_PX: int = 32

# --- Публичные ---
## Текущий уровень топлива (единицы биомассы).
var fuel_current: float = 0.0
## Максимум топлива в загрузке.
var fuel_capacity: float = 100.0
## Позиция на сетке.
var grid_pos: Vector2i = Vector2i.ZERO
## Работает ли сейчас (есть топливо + включён).
var is_running: bool = false

# --- Приватные ---
var _power_source: PowerSourceComponent = null
var _noise: NoiseComponent = null
var _health: HealthComponent = null
var _visual: ColorRect = null
var _fuel_rate: float = 0.5
var _balance: PowerBalance = null

func _ready() -> void:
	add_to_group("buildings")
	collision_layer = 2
	collision_mask = 0

## Настроить термосжигатель.
func setup(p_grid_pos: Vector2i, world_pos: Vector2, balance: PowerBalance) -> void:
	grid_pos = p_grid_pos
	global_position = world_pos
	_balance = balance
	fuel_capacity = balance.burner_fuel_capacity
	_fuel_rate = balance.burner_fuel_rate
	var tile_px: int = DEFAULT_TILE_SIZE_PX
	var size: int = balance.building_tile_size * tile_px
	# Визуал
	_visual = ColorRect.new()
	_visual.size = Vector2(size, size)
	_visual.position = -Vector2(size, size) * 0.5
	_visual.color = balance.burner_color
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
	_health.max_health = 60.0
	add_child(_health)
	_health.died.connect(_on_destroyed)
	# Источник энергии
	_power_source = PowerSourceComponent.new()
	_power_source.name = "PowerSource"
	add_child(_power_source)
	_power_source.set_max_output(balance.burner_output)
	_power_source.set_enabled(false)  # Не работает пока нет топлива
	# Шум (привлекает Очистителей!)
	_noise = NoiseComponent.new()
	_noise.name = "NoiseComponent"
	_noise.noise_radius = balance.burner_noise_radius
	_noise.noise_level = balance.burner_noise_level
	_noise.is_active = false  # Шумит только когда работает
	add_child(_noise)

func _process(delta: float) -> void:
	if not is_running:
		return
	# Расход топлива
	fuel_current -= _fuel_rate * delta
	if fuel_current <= 0.0:
		fuel_current = 0.0
		_stop_running()
	_update_visual()

# --- Публичные методы ---

## Добавить топливо (биомассу). Возвращает сколько принято.
func add_fuel(amount: float) -> float:
	var space: float = fuel_capacity - fuel_current
	var accepted: float = minf(amount, space)
	fuel_current += accepted
	# Автозапуск если было выключено из-за пустого бака
	if fuel_current > 0.0 and not is_running:
		_start_running()
	return accepted

## Получить топливо в процентах.
func get_fuel_percent() -> float:
	if fuel_capacity <= 0.0:
		return 0.0
	return fuel_current / fuel_capacity

## Включить вручную (если есть топливо).
func toggle() -> void:
	if is_running:
		_stop_running()
	elif fuel_current > 0.0:
		_start_running()

func save_state() -> Dictionary:
	return {
		"type": "thermo_burner",
		"grid_x": grid_pos.x, "grid_y": grid_pos.y,
		"fuel": fuel_current, "running": is_running,
	}

func load_state(data: Dictionary) -> void:
	fuel_current = data.get("fuel", 0.0)
	var was_running: bool = data.get("running", false)
	if was_running and fuel_current > 0.0:
		_start_running()
	else:
		_stop_running()
	_update_visual()

# --- Приватные ---

func _start_running() -> void:
	is_running = true
	if _power_source:
		_power_source.set_enabled(true)
	if _noise:
		_noise.set_active(true)
	_update_visual()

func _stop_running() -> void:
	is_running = false
	if _power_source:
		_power_source.set_enabled(false)
	if _noise:
		_noise.set_active(false)
	_update_visual()

func _update_visual() -> void:
	if not _visual or not _balance:
		return
	if is_running:
		# Оранжевый с пульсацией яркости по уровню топлива
		var t: float = get_fuel_percent()
		_visual.color = Color(0.8, 0.3 + 0.2 * t, 0.1)
	else:
		_visual.color = Color(0.4, 0.25, 0.12)

func _on_destroyed() -> void:
	_stop_running()
	EventBus.building_removed.emit(grid_pos)
	queue_free()
