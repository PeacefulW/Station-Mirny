class_name Player
extends CharacterBody2D

## Игрок (Инженер). Управляет движением, атакой,
## сбором ресурсов. Компоненты (O₂, здоровье, инвентарь) — дочерние ноды.

# --- Константы ---
const SCRAP_ITEM_ID: String = "base:scrap"
const WOOD_ITEM_ID: String = "base:wood"
const HarvestTileCommandScript = preload("res://core/systems/commands/harvest_tile_command.gd")

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
var _command_executor: CommandExecutor = null
var _state_machine: StateMachine = StateMachine.new()
var _camera: PlayerCamera = null

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
	_setup_camera()
	_setup_state_machine()
	call_deferred("_find_chunk_manager")
	call_deferred("_find_command_executor")
	call_deferred("_emit_scrap_state")

func _physics_process(delta: float) -> void:
	_handle_rotation()
	_state_machine.physics_update(delta)
	_apply_terrain_blocking(delta)
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if _camera and _camera.handle_zoom_input(event):
		get_viewport().set_input_as_handled()
		return
	_state_machine.handle_input(event)

# --- Добыча ресурсов ---
func perform_harvest() -> bool:
	if _try_refuel_nearby_burner():
		return true
	if _harvest_timer > 0.0:
		return false
	if not _chunk_manager or not _inventory:
		return false
	# Ищем первый rock-тайл по лучу от игрока к курсору.
	var harvest_pos: Vector2 = _find_harvest_target_position()
	if harvest_pos == Vector2.INF:
		return false
	if not _command_executor:
		_find_command_executor()
	if not _command_executor:
		push_warning("Harvest command executor unavailable")
		return false
	var command := HarvestTileCommandScript.new().setup(_chunk_manager as ChunkManager, harvest_pos)
	var result: Dictionary = _command_executor.execute(command)
	if result.is_empty():
		return false
	if not bool(result.get("success", true)):
		return false
	var item_id: String = result.get("item_id", "")
	var amount: int = result.get("amount", 0)
	if item_id.is_empty() or amount <= 0:
		return false
	_harvest_timer = balance.harvest_cooldown
	collect_item(item_id, amount)
	PlayerPopup.spawn_harvest(self, item_id, amount, balance)
	_flash_harvest()
	return true

func _get_harvest_position() -> Vector2:
	var dir: Vector2 = (get_global_mouse_position() - global_position).normalized()
	return global_position + dir * balance.harvest_range

func _find_harvest_target_position() -> Vector2:
	if not WorldGenerator or not WorldGenerator.balance:
		var fallback_pos: Vector2 = _get_harvest_position()
		if _chunk_manager.has_resource_at_world(fallback_pos):
			return fallback_pos
		return global_position if _chunk_manager.has_resource_at_world(global_position) else Vector2.INF
	var dir: Vector2 = get_global_mouse_position() - global_position
	if dir.length_squared() <= 0.0001:
		return global_position if _chunk_manager.has_resource_at_world(global_position) else Vector2.INF
	dir = dir.normalized()
	var step_size: float = maxf(8.0, float(WorldGenerator.balance.tile_size) * 0.25)
	var max_steps: int = maxi(1, ceili(balance.harvest_range / step_size))
	var visited_tiles: Dictionary = {}
	for step: int in range(1, max_steps + 1):
		var sample_pos: Vector2 = global_position + dir * minf(step * step_size, balance.harvest_range)
		var sample_tile: Vector2i = WorldGenerator.world_to_tile(sample_pos)
		if visited_tiles.has(sample_tile):
			continue
		visited_tiles[sample_tile] = true
		var tile_center: Vector2 = WorldGenerator.tile_to_world(sample_tile)
		if _chunk_manager.has_resource_at_world(tile_center):
			return tile_center
	return global_position if _chunk_manager.has_resource_at_world(global_position) else Vector2.INF

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
	var nodes: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not nodes.is_empty():
		_chunk_manager = nodes[0]

func _find_command_executor() -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("command_executor")
	if not nodes.is_empty():
		_command_executor = nodes[0] as CommandExecutor

func _apply_terrain_blocking(delta: float) -> void:
	if not _chunk_manager or velocity == Vector2.ZERO:
		return
	var adjusted_velocity: Vector2 = velocity
	var next_x: Vector2 = global_position + Vector2(velocity.x * delta, 0.0)
	if not _can_occupy_world(next_x):
		adjusted_velocity.x = 0.0
	var next_y: Vector2 = global_position + Vector2(0.0, velocity.y * delta)
	if not _can_occupy_world(next_y):
		adjusted_velocity.y = 0.0
	velocity = adjusted_velocity

func _can_occupy_world(target_pos: Vector2) -> bool:
	if not _chunk_manager or not _chunk_manager.has_method("is_walkable_at_world"):
		return true
	var half_extent: float = 20.0
	var sample_points: Array[Vector2] = [
		target_pos,
		target_pos + Vector2(-half_extent, -half_extent),
		target_pos + Vector2(half_extent, -half_extent),
		target_pos + Vector2(-half_extent, half_extent),
		target_pos + Vector2(half_extent, half_extent),
	]
	for point: Vector2 in sample_points:
		if not _chunk_manager.is_walkable_at_world(point):
			return false
	return true

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

func _setup_camera() -> void:
	_camera = get_node_or_null("Camera2D") as PlayerCamera
	if _camera:
		_camera.setup(balance)

func reset_camera_smoothing() -> void:
	if _camera:
		_camera.reset_smoothing()

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
	var best_distance: float = balance.burner_refuel_range
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
	var accepted: float = nearest_burner.add_fuel(balance.burner_fuel_per_wood)
	if accepted <= 0.0:
		collect_item(WOOD_ITEM_ID, 1)
		return false
	PlayerPopup.spawn_context(self, Localization.t("UI_BURNER_REFUELED", {"amount": roundi(accepted)}), Color(0.95, 0.75, 0.35))
	return true

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
