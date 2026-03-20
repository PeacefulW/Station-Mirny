class_name Player
extends CharacterBody2D

## Игрок (Инженер). Управляет движением, атакой,
## сбором ресурсов. Компоненты (O₂, здоровье, инвентарь) — дочерние ноды.

# --- Константы ---
const SCRAP_ITEM_ID: String = "base:scrap"
const WOOD_ITEM_ID: String = "base:wood"
const BURNER_REFUEL_RANGE: float = 56.0
const BURNER_FUEL_PER_WOOD: float = 20.0

@export var balance: PlayerBalance = null

var _speed_modifier: float = 1.0
var _attack_timer: float = 0.0
var _harvest_timer: float = 0.0
var _is_dead: bool = false
var _oxygen_system: OxygenSystem = null
var _health_component: HealthComponent = null
var _attack_area: Area2D = null
var _inventory: InventoryComponent = null
var _chunk_manager: Node = null
var _state_machine: StateMachine = StateMachine.new()

func _ready() -> void:
	if not balance:
		push_error(Localization.t("SYSTEM_PLAYER_BALANCE_MISSING"))
		return
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
		push_error(Localization.t("SYSTEM_PLAYER_INVENTORY_COMPONENT_MISSING"))
	else:
		EventBus.inventory_updated.connect(_on_inventory_updated)
	_apply_attack_range()
	_setup_state_machine()
	call_deferred("_find_chunk_manager")
	call_deferred("_emit_scrap_state")

func _physics_process(delta: float) -> void:
	_handle_rotation()
	_state_machine.physics_update(delta)
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	_state_machine.handle_input(event)

# --- Добыча ресурсов ---

func perform_harvest() -> bool:
	if _try_refuel_nearby_burner():
		return true
	if _harvest_timer > 0.0:
		return false
	if not _chunk_manager or not _inventory:
		return false
	# Проверяем тайл перед игроком (в направлении курсора)
	var harvest_pos: Vector2 = _get_harvest_position()
	if not _chunk_manager.has_resource_at_world(harvest_pos):
		# Пробуем прямо под игроком
		harvest_pos = global_position
		if not _chunk_manager.has_resource_at_world(harvest_pos):
			return false
	_harvest_timer = balance.harvest_cooldown
	var result: Dictionary = _chunk_manager.try_harvest_at_world(harvest_pos)
	if result.is_empty():
		return false
	var item_id: String = result.get("item_id", "")
	var amount: int = result.get("amount", 0)
	if item_id.is_empty() or amount <= 0:
		return false
	collect_item(item_id, amount)
	# Визуальная обратная связь
	_spawn_harvest_popup(item_id, amount)
	_flash_harvest()
	return true

func _get_harvest_position() -> Vector2:
	var dir: Vector2 = (get_global_mouse_position() - global_position).normalized()
	return global_position + dir * balance.harvest_range

func tick_harvest_cooldown(delta: float) -> void:
	if _harvest_timer > 0.0:
		_harvest_timer -= delta

func _flash_harvest() -> void:
	var visual: Node2D = get_node_or_null("Visual") as Node2D
	if visual:
		visual.modulate = Color(0.5, 1.0, 0.5)
		get_tree().create_timer(balance.harvest_flash_duration).timeout.connect(
			func() -> void:
				if is_instance_valid(visual):
					visual.modulate = Color(1.0, 1.0, 1.0)
		)

## Всплывающий текст "+3 Железная руда"
func _spawn_harvest_popup(item_id: String, amount: int) -> void:
	var item_data: ItemData = ItemRegistry.get_item(item_id)
	var display_name: String = item_data.get_display_name() if item_data else item_id
	var popup := Label.new()
	popup.text = Localization.t("UI_PICKUP_POPUP", {
		"amount": amount,
		"item": display_name,
	})
	popup.add_theme_font_size_override("font_size", 14)
	popup.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	popup.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	popup.add_theme_constant_override("shadow_offset_x", 1)
	popup.add_theme_constant_override("shadow_offset_y", 1)
	popup.position = Vector2(-40, -50)
	popup.z_index = 100
	add_child(popup)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		popup,
		"position:y",
		popup.position.y - balance.harvest_popup_rise_distance,
		balance.harvest_popup_duration
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, balance.harvest_popup_duration).set_delay(
		balance.harvest_popup_fade_delay
	)
	tween.chain().tween_callback(popup.queue_free)

# --- Сбор предметов ---

func collect_item(item_id: String, amount: int) -> int:
	if not _inventory:
		return 0
	var item_data: ItemData = ItemRegistry.get_item(item_id)
	if not item_data:
		return 0
	var leftover: int = _inventory.add_item(item_data, amount)
	var collected_amount: int = amount - leftover
	if collected_amount > 0:
		EventBus.item_collected.emit(item_id, collected_amount)
	if leftover > 0:
		push_warning(Localization.t("SYSTEM_INVENTORY_OVERFLOW", {"amount": leftover}))
	return collected_amount

func collect_scrap(amount: int) -> int:
	if not _inventory:
		return 0
	return collect_item(SCRAP_ITEM_ID, amount)

func get_oxygen_system() -> OxygenSystem:
	return _oxygen_system

func get_inventory() -> InventoryComponent:
	return _inventory

func get_scrap_count() -> int:
	return _count_item_amount(SCRAP_ITEM_ID)

func spend_scrap(amount: int) -> bool:
	if not _inventory or amount <= 0:
		return false
	var scrap_item: ItemData = ItemRegistry.get_item(SCRAP_ITEM_ID)
	if not scrap_item:
		return false
	return _inventory.remove_item(scrap_item, amount)

func spend_item(item_id: String, amount: int) -> bool:
	if not _inventory or amount <= 0:
		return false
	var item_data: ItemData = ItemRegistry.get_item(item_id)
	if not item_data:
		return false
	return _inventory.remove_item(item_data, amount)

# --- Приватные ---

func _find_chunk_manager() -> void:
	var parent: Node = get_parent()
	if parent:
		_chunk_manager = parent.get_node_or_null("ChunkManager")
	if not _chunk_manager:
		# Поиск по дереву
		var nodes: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
		if not nodes.is_empty():
			_chunk_manager = nodes[0]

func update_movement_velocity() -> void:
	var direction: Vector2 = get_move_input()
	velocity = direction * balance.move_speed * _speed_modifier

func get_move_input() -> Vector2:
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction.y -= 1.0
	if Input.is_action_pressed("move_down"):
		direction.y += 1.0
	if Input.is_action_pressed("move_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("move_right"):
		direction.x += 1.0
	return direction.normalized() if direction.length() > 0.0 else Vector2.ZERO

func _handle_rotation() -> void:
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual:
		visual.look_at(get_global_mouse_position())
		visual.rotation_degrees -= 90.0

func perform_attack() -> bool:
	if _attack_timer > 0.0 or not _attack_area:
		return false
	_attack_timer = balance.attack_cooldown
	var visual: Node2D = get_node_or_null("Visual") as Node2D
	if visual:
		visual.modulate = Color(1.0, 0.3, 0.3)
		get_tree().create_timer(balance.attack_flash_duration).timeout.connect(
			func() -> void:
				if is_instance_valid(visual):
					visual.modulate = Color(1.0, 1.0, 1.0)
		)
	var bodies: Array[Node2D] = _attack_area.get_overlapping_bodies()
	for body: Node2D in bodies:
		if body.is_in_group("enemies"):
			var health: HealthComponent = body.get_node_or_null("HealthComponent")
			if health:
				health.take_damage(balance.attack_damage)
	return true

func tick_attack_cooldown(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta

func _on_speed_modifier_changed(modifier: float) -> void:
	_speed_modifier = modifier

func _on_died() -> void:
	_is_dead = true
	_state_machine.transition_to(&"dead")

func _on_inventory_updated(inventory_node: Node) -> void:
	if inventory_node != _inventory:
		return
	_emit_scrap_state()

func _apply_attack_range() -> void:
	if not _attack_area:
		return
	var attack_shape_node: CollisionShape2D = _attack_area.get_node_or_null("AttackShape")
	if not attack_shape_node:
		return
	var attack_shape: CircleShape2D = attack_shape_node.shape as CircleShape2D
	if attack_shape:
		attack_shape.radius = balance.attack_range

func _count_item_amount(item_id: String) -> int:
	if not _inventory:
		return 0
	var total: int = 0
	for slot: InventorySlot in _inventory.slots:
		if not slot.is_empty() and slot.item and slot.item.id == item_id:
			total += slot.amount
	return total

func _emit_scrap_state() -> void:
	EventBus.scrap_collected.emit(get_scrap_count())

func _try_refuel_nearby_burner() -> bool:
	var burners: Array[Node] = get_tree().get_nodes_in_group("buildings")
	var nearest_burner: ThermoBurner = null
	var best_distance: float = BURNER_REFUEL_RANGE
	for node: Node in burners:
		var burner: ThermoBurner = node as ThermoBurner
		if not burner:
			continue
		var dist: float = global_position.distance_to(burner.global_position)
		if dist <= best_distance:
			best_distance = dist
			nearest_burner = burner
	if not nearest_burner:
		return false
	if not spend_item(WOOD_ITEM_ID, 1):
		return false
	var accepted: float = nearest_burner.add_fuel(BURNER_FUEL_PER_WOOD)
	if accepted <= 0.0:
		collect_item(WOOD_ITEM_ID, 1)
		return false
	_spawn_context_popup(Localization.t("UI_BURNER_REFUELED", {"amount": roundi(accepted)}), Color(0.95, 0.75, 0.35))
	return true

func _spawn_context_popup(text: String, color: Color) -> void:
	var popup := Label.new()
	popup.text = text
	popup.add_theme_font_size_override("font_size", 13)
	popup.add_theme_color_override("font_color", color)
	popup.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	popup.add_theme_constant_override("shadow_offset_x", 1)
	popup.add_theme_constant_override("shadow_offset_y", 1)
	popup.position = Vector2(-48, -68)
	popup.z_index = 100
	add_child(popup)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 28.0, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tween.chain().tween_callback(popup.queue_free)

func stop_movement() -> void:
	velocity = Vector2.ZERO

func has_move_input() -> bool:
	return get_move_input() != Vector2.ZERO

func can_attack() -> bool:
	return not _is_dead and _attack_timer <= 0.0 and _attack_area != null

func can_harvest() -> bool:
	return not _is_dead and _harvest_timer <= 0.0 and _chunk_manager != null and _inventory != null

func is_attack_busy() -> bool:
	return _attack_timer > 0.0

func is_harvest_busy() -> bool:
	return _harvest_timer > 0.0

func is_dead() -> bool:
	return _is_dead

func handle_death() -> void:
	stop_movement()
	EventBus.player_died.emit()
	EventBus.game_over.emit()

func _setup_state_machine() -> void:
	_state_machine.setup(self)
	_state_machine.add_state(&"idle", PlayerIdleState.new())
	_state_machine.add_state(&"move", PlayerMoveState.new())
	_state_machine.add_state(&"harvest", PlayerHarvestState.new())
	_state_machine.add_state(&"attack", PlayerAttackState.new())
	_state_machine.add_state(&"dead", PlayerDeadState.new())
	_state_machine.transition_to(&"idle")


