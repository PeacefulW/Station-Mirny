class_name SpawnOrchestrator
extends Node

## Оркестратор спавна врагов и пикапов.
## Извлечён из GameWorld для изоляции spawn-логики от runtime (Iteration 5, ADR-0001).

var _player: Player = null
var _enemy_container: Node2D = null
var _pickup_container: Node2D = null
var _command_executor: CommandExecutor = null
var _enemy_balance: EnemyBalance = null
var _enemy_factory: EnemyFactory = EnemyFactory.new()
var _pickup_factory: PickupFactory = PickupFactory.new()
var _spawn_timer: float = 0.0
var _enemy_count: int = 0
var _enemy_spawning_enabled: bool = false

func setup(
	player: Player,
	enemy_container: Node2D,
	pickup_container: Node2D,
	command_executor: CommandExecutor,
	enemy_balance: EnemyBalance
) -> void:
	_player = player
	_enemy_container = enemy_container
	_pickup_container = pickup_container
	_command_executor = command_executor
	_enemy_balance = enemy_balance
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.item_dropped.connect(_on_item_dropped)
	# Temporary for development testing: enemy spawning is intentionally disabled. This is not a bug.
	set_enemy_spawning_enabled(false)

func _process(delta: float) -> void:
	_sync_pickups_to_player()
	_update_enemy_spawning(delta)

func spawn_initial_scrap() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if not _player:
		return
	for i: int in range(10):
		var angle: float = randf() * TAU
		var dist: float = randf_range(100.0, 400.0)
		var pos: Vector2 = _player.global_position + Vector2.from_angle(angle) * dist
		_spawn_scrap_pickup(pos)
	WorldPerfProbe.end("_spawn_initial_scrap", started_usec)

func save_pickups() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _pickup_container:
		return result
	for child: Node in _pickup_container.get_children():
		var pickup: Area2D = child as Area2D
		if not pickup:
			continue
		var item_id: String = str(pickup.get_meta("item_id", ""))
		var amount: int = int(pickup.get_meta("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		var logical_position: Vector2 = _get_pickup_logical_position(pickup)
		result.append({
			"item_id": item_id,
			"amount": amount,
			"position": {
				"x": logical_position.x,
				"y": logical_position.y,
			},
		})
	return result

func save_enemy_runtime() -> Dictionary:
	var entries: Array[Dictionary] = []
	if _enemy_container:
		for child: Node in _enemy_container.get_children():
			var enemy: BasicEnemy = child as BasicEnemy
			if not enemy or enemy.is_dead():
				continue
			var logical_position: Vector2 = enemy.global_position
			if WorldGenerator and WorldGenerator._is_initialized:
				logical_position = WorldGenerator.canonicalize_world_position(logical_position)
			var entry: Dictionary = {
				"position": {
					"x": logical_position.x,
					"y": logical_position.y,
				},
			}
			var health: HealthComponent = enemy.get_node_or_null("HealthComponent")
			if health:
				entry["health"] = {
					"current": health.current_health,
					"max": health.max_health,
				}
			entries.append(entry)
	return {
		"spawn_timer": _spawn_timer,
		"spawning_enabled": _enemy_spawning_enabled,
		"enemies": entries,
	}

func load_enemy_runtime(data: Dictionary) -> void:
	clear_enemies()
	_spawn_timer = float(data.get("spawn_timer", 0.0))
	# Temporary for development testing: enemy spawning and enemy restore are intentionally disabled. This is not a bug.
	_enemy_spawning_enabled = false
	_enemy_count = 0

func set_enemy_spawning_enabled(enabled: bool) -> void:
	_enemy_spawning_enabled = enabled

func load_pickups(entries: Array) -> void:
	clear_pickups()
	for entry_variant: Variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var item_id: String = str(entry.get("item_id", ""))
		var amount: int = int(entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		var position_data: Dictionary = entry.get("position", {})
		var pickup := _pickup_factory.create_item_pickup(
			item_id,
			amount,
			Vector2(
				float(position_data.get("x", 0.0)),
				float(position_data.get("y", 0.0))
			)
		)
		_prepare_pickup_for_world_wrap(pickup)
		pickup.body_entered.connect(_on_pickup_collected.bind(pickup))
		_pickup_container.add_child(pickup)

func clear_pickups() -> void:
	if not _pickup_container:
		return
	for child: Node in _pickup_container.get_children():
		child.queue_free()

func clear_enemies() -> void:
	if not _enemy_container:
		_enemy_count = 0
		return
	for child: Node in _enemy_container.get_children():
		child.queue_free()
	_enemy_count = 0

func _update_enemy_spawning(delta: float) -> void:
	if not _enemy_spawning_enabled:
		return
	if not _enemy_balance or not _player or not _enemy_container:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = _enemy_balance.spawn_interval
		if _enemy_count < _enemy_balance.max_enemies:
			_spawn_enemy()

func _spawn_enemy() -> void:
	if not _enemy_balance:
		return
	var angle: float = randf() * TAU
	var dist: float = randf_range(
		_enemy_balance.spawn_distance_min,
		_enemy_balance.spawn_distance_max
	)
	var spawn_pos: Vector2 = _player.global_position + Vector2.from_angle(angle) * dist
	if WorldGenerator and WorldGenerator._is_initialized:
		if not WorldGenerator.is_walkable_at(spawn_pos):
			return
	var enemy := _enemy_factory.create_basic_enemy(spawn_pos, _enemy_balance)
	if not enemy:
		return
	_enemy_container.add_child(enemy)
	_enemy_count += 1
	EventBus.enemy_spawned.emit(enemy)

func _on_enemy_killed(death_position: Vector2) -> void:
	_enemy_count = maxi(_enemy_count - 1, 0)
	if _enemy_balance:
		var drop: int = randi_range(_enemy_balance.scrap_drop_min, _enemy_balance.scrap_drop_max)
		for i: int in range(drop):
			var offset := Vector2(randf_range(-40, 40), randf_range(-40, 40))
			_spawn_scrap_pickup(death_position + offset)

func _on_item_dropped(item_id: String, amount: int, world_pos: Vector2) -> void:
	if not _pickup_container:
		return
	var drop_pos: Vector2 = world_pos
	var drop_distance: float = 24.0
	var pickup_delay: float = 0.5
	if _player and _player.balance:
		drop_distance = _player.balance.item_drop_distance
		pickup_delay = _player.balance.item_drop_pickup_delay
	if drop_pos == Vector2.ZERO and _player:
		var angle: float = randf() * TAU
		drop_pos = _player.global_position + Vector2.from_angle(angle) * drop_distance
	var pickup := _pickup_factory.create_item_pickup(item_id, amount, drop_pos)
	var col: CollisionShape2D = pickup.get_child(1) as CollisionShape2D
	if col:
		col.set_deferred("disabled", true)
	_prepare_pickup_for_world_wrap(pickup)
	pickup.body_entered.connect(_on_pickup_collected.bind(pickup))
	_pickup_container.add_child(pickup)
	if col:
		get_tree().create_timer(pickup_delay).timeout.connect(func() -> void:
			if is_instance_valid(col):
				col.disabled = false
		)

func _spawn_scrap_pickup(pos: Vector2) -> void:
	if not _pickup_container:
		return
	var pickup := _pickup_factory.create_item_pickup(Player.SCRAP_ITEM_ID, 1, pos)
	_prepare_pickup_for_world_wrap(pickup)
	pickup.body_entered.connect(_on_pickup_collected.bind(pickup))
	_pickup_container.add_child(pickup)

func _on_pickup_collected(body: Node2D, pickup: Area2D) -> void:
	if body is Player:
		var item_id: String = str(pickup.get_meta("item_id", Player.SCRAP_ITEM_ID))
		var amount: int = int(pickup.get_meta("amount", 1))
		if _command_executor:
			var command := PickupItemCommand.new().setup(body as Player, item_id, amount, pickup)
			_command_executor.execute(command)
			return
		body.collect_item(item_id, amount)
		pickup.queue_free()

func sync_pickups_to_player() -> void:
	_sync_pickups_to_player()

func _sync_pickups_to_player() -> void:
	if not _pickup_container:
		return
	for child: Node in _pickup_container.get_children():
		var pickup: Area2D = child as Area2D
		if not pickup:
			continue
		_sync_pickup_display_position(pickup)

func _prepare_pickup_for_world_wrap(pickup: Area2D) -> void:
	if not pickup:
		return
	pickup.set_meta("logical_position", _canonicalize_pickup_position(pickup.global_position))
	_sync_pickup_display_position(pickup)

func _sync_pickup_display_position(pickup: Area2D) -> void:
	if not pickup:
		return
	var logical_position: Vector2 = _get_pickup_logical_position(pickup)
	if _player and WorldGenerator and WorldGenerator._is_initialized:
		pickup.global_position = WorldGenerator.get_display_world_position(logical_position, _player.global_position)
	else:
		pickup.global_position = logical_position

func _get_pickup_logical_position(pickup: Area2D) -> Vector2:
	var stored: Variant = pickup.get_meta("logical_position", pickup.global_position)
	if stored is Vector2:
		return _canonicalize_pickup_position(stored as Vector2)
	return _canonicalize_pickup_position(pickup.global_position)

func _canonicalize_pickup_position(world_pos: Vector2) -> Vector2:
	if WorldGenerator and WorldGenerator._is_initialized:
		return WorldGenerator.canonicalize_world_position(world_pos)
	return world_pos
