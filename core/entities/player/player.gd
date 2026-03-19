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
		push_error("Player: Компонент InventoryComponent не найден!")

func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_rotation()
	_update_attack_cooldown(delta)
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_try_attack()
		
	# --- НАЧАЛО ТЕСТА ИНВЕНТАРЯ ---
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			print("Тест: Подбираем 15 железа...")
			collect_item("base:iron_ore", 15)
			_debug_print_inventory()
		elif event.keycode == KEY_2:
			print("Тест: Подбираем 55 камня (проверка стаков)...")
			# Если макс. стак камня 50, он должен занять один слот полностью,
			# а остаток (5) положить в следующий слот!
			collect_item("base:stone", 55) 
			_debug_print_inventory()
	# --- КОНЕЦ ТЕСТА ИНВЕНТАРЯ ---

## Временная функция для проверки инвентаря в консоли
func _debug_print_inventory() -> void:
	print("=== ИНВЕНТАРЬ ИГРОКА ===")
	if not _inventory:
		print("Ошибка: Компонент InventoryComponent не найден!")
		return
		
	var has_items: bool = false
	for i: int in range(_inventory.capacity):
		var slot: InventorySlot = _inventory.slots[i]
		if not slot.is_empty():
			print("Слот [%d]: %s — %d шт." % [i, slot.item.display_name, slot.amount])
			has_items = true
			
	if not has_items:
		print("Инвентарь абсолютно пуст.")
	print("========================")

## Собрать предмет в инвентарь (заменяет старую функцию collect_scrap).
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
		# TODO: Позже здесь можно реализовать выброс невлезших предметов на землю (дроп)
		print("Инвентарь полон! Не влезло: ", leftover)

## Временная функция-переходник для совместимости со старыми механиками.
## Конвертирует подобранный "скрап" в железную руду и обновляет старые системы.
func collect_scrap(amount: int) -> void:
	if not _inventory:
		return
		
	# 1. Подбираем скрап как железную руду
	collect_item("base:iron_ore", amount)
	
	# 2. Считаем, сколько всего железа теперь в инвентаре
	var total_iron: int = 0
	for slot: InventorySlot in _inventory.slots:
		if not slot.is_empty() and slot.item.id == "base:iron_ore":
			total_iron += slot.amount
			
	# 3. Эмитим старый сигнал, чтобы HUD не крашился и стены можно было строить
	EventBus.scrap_collected.emit(total_iron)

## Получить ссылку на систему кислорода.
func get_oxygen_system() -> OxygenSystem:
	return _oxygen_system

## Получить ссылку на инвентарь игрока.
func get_inventory() -> InventoryComponent:
	return _inventory

# --- Приватные методы ---

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
	
	# Визуальная индикация атаки (мигание) — ОБНОВЛЕНО ДЛЯ SPRITE2D
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual:
		# Окрашиваем спрайт в красный оттенок при ударе
		visual.modulate = Color(1.0, 0.3, 0.3)
		# Возвращаем нормальный цвет (белый = без искажений) через 0.1 сек
		get_tree().create_timer(0.1).timeout.connect(
			func() -> void: visual.modulate = Color(1.0, 1.0, 1.0)
		)
		
	# Поиск врагов в зоне атаки
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
