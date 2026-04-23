class_name Player
extends CharacterBody2D

## Игрок (Инженер). Управляет движением, атакой,
## сбором ресурсов. Компоненты (O₂, здоровье, инвентарь) — дочерние ноды.

# --- Константы ---
const MountainResolver = preload("res://core/systems/world/mountain_resolver.gd")
const HarvestQuery = preload("res://core/systems/world/harvest_query.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")
const SCRAP_ITEM_ID: String = "base:scrap"
const WOOD_ITEM_ID: String = "base:wood"
const SHOW_MOUNTAIN_DEBUG_OVERLAY: bool = false
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
var _world_streamer: WorldStreamer = null
var _mountain_resolver: MountainResolver = null
var _state_machine: StateMachine = StateMachine.new()
var _camera: PlayerCamera = null
var _mountain_debug_layer: CanvasLayer = null
var _mountain_debug_panel: PanelContainer = null
var _mountain_debug_label: Label = null

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
	EventBus.world_initialized.connect(_on_world_initialized)
	_apply_attack_range()
	_setup_camera()
	_setup_state_machine()
	_ensure_mountain_debug_overlay()
	_mountain_resolver = MountainResolver.new()
	call_deferred("_find_chunk_manager")
	call_deferred("_emit_scrap_state")

func _physics_process(delta: float) -> void:
	_handle_rotation()
	_state_machine.physics_update(delta)
	_apply_terrain_blocking(delta)
	move_and_slide()
	var streamer: WorldStreamer = _get_world_streamer()
	if _mountain_resolver != null and streamer != null:
		_mountain_resolver.update_from_player_position(global_position, streamer)
	_update_mountain_debug_overlay(global_position, streamer)

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
	var chunk_manager: Node = _get_chunk_manager()
	if not chunk_manager or not _inventory:
		return false
	# Ищем первый rock-тайл по лучу от игрока к курсору.
	var harvest_pos: Vector2 = _find_harvest_target_position()
	if harvest_pos == Vector2.INF:
		return false
	if not chunk_manager.has_method("try_harvest_at_world"):
		return false
	var result: Dictionary = chunk_manager.try_harvest_at_world(harvest_pos)
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
	var chunk_manager: Node = _get_chunk_manager()
	if chunk_manager == null \
			or not chunk_manager.has_method("has_resource_at_world") \
			or not chunk_manager.has_method("is_walkable_at_world"):
		return Vector2.INF
	var dir: Vector2 = get_global_mouse_position() - global_position
	var end_world: Vector2 = global_position if dir.length_squared() <= 0.0001 \
		else global_position + dir.normalized() * balance.harvest_range
	return HarvestQuery.find_target_on_ray(
		global_position,
		end_world,
		Callable(chunk_manager, "has_resource_at_world"),
		Callable(chunk_manager, "is_walkable_at_world")
	)

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
	_chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_world_streamer = _chunk_manager as WorldStreamer

func _get_chunk_manager() -> Node:
	if _chunk_manager != null and is_instance_valid(_chunk_manager):
		return _chunk_manager
	_find_chunk_manager()
	if _chunk_manager != null and is_instance_valid(_chunk_manager):
		return _chunk_manager
	return null

func _get_world_streamer() -> WorldStreamer:
	if _world_streamer != null and is_instance_valid(_world_streamer):
		return _world_streamer
	_find_chunk_manager()
	if _world_streamer != null and is_instance_valid(_world_streamer):
		return _world_streamer
	return null

func _on_world_initialized(_seed_value: int) -> void:
	_mountain_resolver = MountainResolver.new()
	_chunk_manager = null
	_world_streamer = null
	call_deferred("_find_chunk_manager")

func _apply_terrain_blocking(delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	if _get_chunk_manager() == null:
		return
	var intended_pos: Vector2 = global_position + velocity * delta
	if _can_occupy_world(intended_pos):
		return
	var adjusted_velocity: Vector2 = Vector2.ZERO
	var horizontal_first: bool = absf(velocity.x) >= absf(velocity.y)
	if horizontal_first:
		var next_x: Vector2 = global_position + Vector2(velocity.x * delta, 0.0)
		if _can_occupy_world(next_x):
			adjusted_velocity.x = velocity.x
		var resolved_x_pos: Vector2 = global_position + Vector2(adjusted_velocity.x * delta, 0.0)
		var next_y_after_x: Vector2 = resolved_x_pos + Vector2(0.0, velocity.y * delta)
		if _can_occupy_world(next_y_after_x):
			adjusted_velocity.y = velocity.y
	else:
		var next_y: Vector2 = global_position + Vector2(0.0, velocity.y * delta)
		if _can_occupy_world(next_y):
			adjusted_velocity.y = velocity.y
		var resolved_y_pos: Vector2 = global_position + Vector2(0.0, adjusted_velocity.y * delta)
		var next_x_after_y: Vector2 = resolved_y_pos + Vector2(velocity.x * delta, 0.0)
		if _can_occupy_world(next_x_after_y):
			adjusted_velocity.x = velocity.x
	velocity = adjusted_velocity

func _can_occupy_world(target_pos: Vector2) -> bool:
	var chunk_manager: Node = _get_chunk_manager()
	if not chunk_manager or not chunk_manager.has_method("is_walkable_at_world"):
		return true
	var sample_points: Array[Vector2] = _build_occupancy_sample_points(target_pos)
	for point: Vector2 in sample_points:
		if not chunk_manager.is_walkable_at_world(point):
			return false
	return true

func _build_occupancy_sample_points(target_pos: Vector2) -> Array[Vector2]:
	var half_extents: Vector2 = _resolve_blocking_half_extents()
	var edge_x: float = maxf(4.0, half_extents.x - 2.0)
	var edge_y: float = maxf(4.0, half_extents.y - 2.0)
	# Sample the full footprint so diagonal motion cannot cut through impassable tiles.
	return [
		target_pos,
		target_pos + Vector2(-edge_x, 0.0),
		target_pos + Vector2(edge_x, 0.0),
		target_pos + Vector2(0.0, -edge_y),
		target_pos + Vector2(0.0, edge_y),
		target_pos + Vector2(-edge_x, -edge_y),
		target_pos + Vector2(edge_x, -edge_y),
		target_pos + Vector2(-edge_x, edge_y),
		target_pos + Vector2(edge_x, edge_y),
	]

func _resolve_blocking_half_extents() -> Vector2:
	var collision_shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape_node == null or collision_shape_node.shape == null:
		return Vector2(20.0, 20.0)
	var shape: Shape2D = collision_shape_node.shape
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size * 0.5
	if shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius
		return Vector2(radius, radius)
	if shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = shape as CapsuleShape2D
		return Vector2(capsule.radius, capsule.radius + capsule.height * 0.5)
	return Vector2(20.0, 20.0)

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

func _ensure_mountain_debug_overlay() -> void:
	# Keep the overlay wiring available, but hide it until we need it again.
	if not SHOW_MOUNTAIN_DEBUG_OVERLAY:
		if _mountain_debug_layer != null and is_instance_valid(_mountain_debug_layer):
			_mountain_debug_layer.visible = false
		return
	if _mountain_debug_label != null and is_instance_valid(_mountain_debug_label):
		return
	_mountain_debug_layer = CanvasLayer.new()
	_mountain_debug_layer.name = "MountainDebugOverlay"
	add_child(_mountain_debug_layer)

	_mountain_debug_panel = PanelContainer.new()
	_mountain_debug_panel.name = "MountainDebugPanel"
	_mountain_debug_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_mountain_debug_panel.offset_left = 12.0
	_mountain_debug_panel.offset_top = 12.0
	_mountain_debug_panel.custom_minimum_size = Vector2(620.0, 192.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.08, 0.86)
	panel_style.border_color = Color(0.42, 0.74, 1.0, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 8.0
	_mountain_debug_panel.add_theme_stylebox_override("panel", panel_style)
	_mountain_debug_layer.add_child(_mountain_debug_panel)

	_mountain_debug_label = Label.new()
	_mountain_debug_label.name = "MountainDebugLabel"
	_mountain_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mountain_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_mountain_debug_label.custom_minimum_size = Vector2(600.0, 176.0)
	_mountain_debug_label.add_theme_font_size_override("font_size", 15)
	_mountain_debug_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	_mountain_debug_panel.add_child(_mountain_debug_label)

func _update_mountain_debug_overlay(
	world_pos: Vector2,
	streamer: WorldStreamer
) -> void:
	if not SHOW_MOUNTAIN_DEBUG_OVERLAY:
		if _mountain_debug_layer != null and is_instance_valid(_mountain_debug_layer):
			_mountain_debug_layer.visible = false
		return
	if _mountain_debug_label == null or not is_instance_valid(_mountain_debug_label):
		return
	if _mountain_resolver == null:
		_mountain_debug_label.text = "Mountain debug: resolver missing"
		return
	var resolver_debug: Dictionary = _mountain_resolver.get_debug_snapshot()
	if not bool(resolver_debug.get("ready", false)):
		_mountain_debug_label.text = "Mountain debug: resolver not ready | reason=%s | last=%d" % [
			String(resolver_debug.get("reason", "unknown")),
			int(resolver_debug.get("last_mountain_id", 0)),
		]
		return
	var tile_coord: Vector2i = resolver_debug.get("tile_coord", WorldRuntimeConstants.world_to_tile(world_pos)) as Vector2i
	var sample_mountain_id: int = int(resolver_debug.get("sample_mountain_id", 0))
	var sample_mountain_flags: int = int(resolver_debug.get("sample_mountain_flags", 0))
	var sample_is_interior: bool = (sample_mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0
	var sample_component_id: int = int(resolver_debug.get("sample_component_id", 0))
	var sample_is_opening: bool = bool(resolver_debug.get("sample_is_opening", false))
	var resolved_mountain_id: int = int(resolver_debug.get("resolved_mountain_id", 0))
	var resolved_component_id: int = int(resolver_debug.get("resolved_component_id", 0))
	var last_before: int = int(resolver_debug.get("last_mountain_id_before_update", 0))
	var last_component_before: int = int(resolver_debug.get("last_component_id_before_update", 0))
	var last_after: int = int(resolver_debug.get("last_mountain_id_after_update", last_before))
	var last_component_after: int = int(resolver_debug.get("last_component_id_after_update", last_component_before))
	var cover_debug: Dictionary = {}
	if streamer != null:
		cover_debug = streamer.get_mountain_cover_debug_snapshot(tile_coord)
	var render_debug: Dictionary = {}
	if streamer != null:
		render_debug = streamer.get_mountain_cover_render_debug_snapshot(tile_coord)
	var terrain_debug: Dictionary = _get_mountain_debug_tile_state(tile_coord, streamer)
	var terrain_id: int = int(terrain_debug.get("terrain_id", -1))
	var terrain_name: String = _terrain_debug_name(terrain_id)
	var terrain_ready: bool = bool(terrain_debug.get("ready", false))
	var world_version: int = streamer.get_world_version() if streamer != null else -1
	var state_text: String = String(cover_debug.get("inside_outside_state", "OUTSIDE"))
	var active_mountain_id: int = int(cover_debug.get("active_mountain_id", 0))
	var active_component_id: int = int(cover_debug.get("active_component_id", 0))
	var cover_mountain_id: int = int(cover_debug.get("mountain_id", sample_mountain_id))
	var cover_component_id: int = int(cover_debug.get("component_id", sample_component_id))
	var cover_is_opening: bool = bool(cover_debug.get("is_opening", sample_is_opening))
	var roof_layer_metric: int = int(cover_debug.get("roof_layers_per_chunk_max", 0))
	var probe_tile: Vector2i = render_debug.get("probe_tile", tile_coord) as Vector2i
	var probe_mountain_id: int = int(render_debug.get("probe_mountain_id", 0))
	var probe_expected_open: int = int(render_debug.get("expected_open_bit", -1))
	var probe_mask_value: float = float(render_debug.get("mask_value", -1.0))
	var probe_pending_mountain_id: int = int(render_debug.get("pending_mountain_id", 0))
	var probe_pending_flags: int = int(render_debug.get("pending_flags", 0))
	var probe_has_roof_layer: bool = bool(render_debug.get("has_roof_layer", false))
	var probe_layer_has_cover_material: bool = bool(render_debug.get("layer_has_cover_material", false))
	var probe_roof_cell_source_id: int = int(render_debug.get("roof_cell_source_id", -1))
	var probe_roof_cell_atlas: Vector2i = render_debug.get("roof_cell_atlas_coords", Vector2i(-1, -1)) as Vector2i
	var probe_roof_tile_material_present: bool = bool(render_debug.get("roof_tile_material_present", false))
	var probe_chunk_view_ready: bool = bool(render_debug.get("chunk_view_ready", false))
	_mountain_debug_label.text = "\n".join([
		"Mountain debug: %s | tile=(%d,%d) | world_version=%d" % [state_text, tile_coord.x, tile_coord.y, world_version],
		"terrain_id=%d (%s) | packet_ready=%s" % [terrain_id, terrain_name, str(terrain_ready)],
		"sample_mountain_id=%d | sample_flags=%d | sample_interior=%s | sample_component_id=%d | sample_opening=%s" % [
			sample_mountain_id,
			sample_mountain_flags,
			str(sample_is_interior),
			sample_component_id,
			str(sample_is_opening),
		],
		"resolved_mountain_id=%d | resolved_component_id=%d | last_before=(%d,%d) | last_after=(%d,%d)" % [
			resolved_mountain_id,
			resolved_component_id,
			last_before,
			last_component_before,
			last_after,
			last_component_after,
		],
		"cover_mountain_id=%d | cover_component_id=%d | cover_opening=%s | active=(%d,%d) | roof_layers_per_chunk_max=%d" % [
			cover_mountain_id,
			cover_component_id,
			str(cover_is_opening),
			active_mountain_id,
			active_component_id,
			roof_layer_metric,
		],
		"render_probe_tile=(%d,%d) | probe_mountain_id=%d | expected_open=%d | mask=%.2f | chunk_view_ready=%s" % [
			probe_tile.x,
			probe_tile.y,
			probe_mountain_id,
			probe_expected_open,
			probe_mask_value,
			str(probe_chunk_view_ready),
		],
		"roof_layer=%s | cover_material=%s | roof_cell_source=%d | roof_cell_atlas=(%d,%d) | tile_material=%s | pending=(%d,%d)" % [
			str(probe_has_roof_layer),
			str(probe_layer_has_cover_material),
			probe_roof_cell_source_id,
			probe_roof_cell_atlas.x,
			probe_roof_cell_atlas.y,
			str(probe_roof_tile_material_present),
			probe_pending_mountain_id,
			probe_pending_flags,
		],
	])

func _get_mountain_debug_tile_state(tile_coord: Vector2i, streamer: WorldStreamer) -> Dictionary:
	if streamer == null:
		return {"ready": false}
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var packet: Dictionary = streamer.get_chunk_packet(chunk_coord)
	if packet.is_empty():
		return {"ready": false}
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	if index < 0 or index >= terrain_ids.size():
		return {"ready": false}
	return {
		"ready": true,
		"terrain_id": int(terrain_ids[index]),
	}

func _terrain_debug_name(terrain_id: int) -> String:
	match terrain_id:
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
			return "PLAINS_GROUND"
		WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
			return "LEGACY_BLOCKED"
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
			return "PLAINS_DUG"
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL:
			return "MOUNTAIN_WALL"
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			return "MOUNTAIN_FOOT"
		_:
			return "UNKNOWN"

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
	return not _is_dead and _harvest_timer <= 0.0 and _get_chunk_manager() != null and _inventory != null
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
