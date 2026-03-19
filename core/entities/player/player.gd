class_name Player
extends CharacterBody2D

## Игрок (Инженер). Управляет движением, атакой,
## сбором ресурсов. Компоненты (O₂, здоровье, инвентарь) — дочерние ноды.

# --- Константы ---
const BASE_SPEED: float = 150.0
const ATTACK_DAMAGE: float = 15.0
const ATTACK_COOLDOWN: float = 0.4
const PICKUP_RADIUS: float = 40.0

# --- Приватные ---
var _speed_modifier: float = 1.0
var _attack_timer: float = 0.0
var _oxygen_system: OxygenSystem = null
var _health_component: HealthComponent = null
var _attack_area: Area2D = null
var _inventory: InventoryComponent = null

func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 2 | 4
	_oxygen_system = get_node_or_null("OxygenSystem")
	_health_component = get_node_or_null("HealthComponent")
	_attack_area = get_node_or_null("AttackArea")
	_inventory = get_node_or_null("InventoryComponent")
	if _oxygen_system:
		_oxygen_system.speed_modifier_changed.connect(_on_speed_modifier_changed)
	if _health_component:
		_health_component.died.connect(_on_died)
	if not _inventory:
		push_error("Player: InventoryComponent не найден!")

func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_rotation()
	_update_attack_cooldown(delta)
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_try_attack()

## Собрать предмет в инвентарь.
func collect_item(item_id: String, amount: int) -> void:
	if not _inventory:
		return
	var item_data: ItemData = ItemRegistry.get_item(item_id)
	if not item_data:
		return
	var leftover: int = _inventory.add_item(item_data, amount)
	var collected_amount: int = amount - leftover
	if collected_amount > 0:
		EventBus.item_collected.emit(item_id, collected_amount)
	if leftover > 0:
		print("Инвентарь полон! Не влезло: ", leftover)

## Совместимость со старой системой скрапа.
func collect_scrap(amount: int) -> void:
	if not _inventory:
		return
	collect_item("base:iron_ore", amount)
	var total_iron: int = 0
	for slot: InventorySlot in _inventory.slots:
		if not slot.is_empty() and slot.item.id == "base:iron_ore":
			total_iron += slot.amount
	EventBus.scrap_collected.emit(total_iron)

func get_oxygen_system() -> OxygenSystem:
	return _oxygen_system

func get_inventory() -> InventoryComponent:
	return _inventory

# --- Приватные ---

func _handle_movement() -> void:
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction.y -= 1.0
	if Input.is_action_pressed("move_down"):
		direction.y += 1.0
	if Input.is_action_pressed("move_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("move_right"):
		direction.x += 1.0
	if direction.length() > 0.0:
		direction = direction.normalized()
	velocity = direction * BASE_SPEED * _speed_modifier

func _handle_rotation() -> void:
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual:
		visual.look_at(get_global_mouse_position())
		visual.rotation_degrees -= 90.0

func _try_attack() -> void:
	if _attack_timer > 0.0 or not _attack_area:
		return
	_attack_timer = ATTACK_COOLDOWN
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual:
		visual.modulate = Color(1.0, 0.3, 0.3)
		get_tree().create_timer(0.1).timeout.connect(
			func() -> void: visual.modulate = Color(1.0, 1.0, 1.0)
		)
	var bodies: Array[Node2D] = _attack_area.get_overlapping_bodies()
	for body: Node2D in bodies:
		if body.is_in_group("enemies"):
			var health: HealthComponent = body.get_node_or_null("HealthComponent")
			if health:
				health.take_damage(ATTACK_DAMAGE)

func _update_attack_cooldown(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta

func _on_speed_modifier_changed(modifier: float) -> void:
	_speed_modifier = modifier

func _on_died() -> void:
	EventBus.player_died.emit()
	EventBus.game_over.emit()
