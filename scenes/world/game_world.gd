class_name GameWorld
extends Node2D

## Главная сцена мира. Инициализирует WorldGenerator (если не было),
## управляет ChunkManager, спавном врагов и пикапов.

# --- Экспортируемые ---
@export var enemy_balance: EnemyBalance = null
## Seed мира. Используется только если мир не инициализирован
## (при запуске напрямую, минуя экран создания). 0 = случайный.
@export var world_seed: int = 0

# --- Приватные ---
var _player: Player = null
var _building_system: BuildingSystem = null
var _chunk_manager: ChunkManager = null
var _enemy_container: Node2D = null
var _pickup_container: Node2D = null
var _crafting_system: CraftingSystem = null
var _spawn_timer: float = 0.0
var _enemy_count: int = 0

func _ready() -> void:
	_player = _find_node_in_group("player") as Player
	_building_system = get_node_or_null("BuildingSystem")
	_enemy_container = get_node_or_null("EnemyContainer")
	_pickup_container = get_node_or_null("PickupContainer")
	EventBus.enemy_killed.connect(_on_enemy_killed)
	_init_world_generator()
	_setup_chunk_manager()
	_spawn_initial_scrap()
	
	# Создаём меню строительства в UILayer
	var build_menu := BuildMenu.new()
	build_menu.name = "BuildMenu"
	get_node("UILayer").add_child(build_menu)

	# Создаём CraftingSystem
	_crafting_system = CraftingSystem.new()
	_crafting_system.name = "CraftingSystem"
	add_child(_crafting_system)

	# Создаём UI инвентаря
	var inv_ui := InventoryUI.new()
	inv_ui.name = "InventoryUI"
	get_node("UILayer").add_child(inv_ui)

	# Создаём PowerSystem
	var power_sys := PowerSystem.new()
	power_sys.name = "PowerSystem"
	add_child(power_sys)
	
	# UI энергосистемы
	var power_ui := PowerUI.new()
	power_ui.name = "PowerUI"
	get_node("UILayer").add_child(power_ui)

func _process(delta: float) -> void:
	_update_player_indoor_status()
	_update_enemy_spawning(delta)

# --- Инициализация ---

func _init_world_generator() -> void:
	if not WorldGenerator:
		push_error("GameWorld: WorldGenerator Autoload не найден!")
		return
	if _player:
		WorldGenerator.spawn_tile = WorldGenerator.world_to_tile(_player.global_position)
	# Если уже инициализирован (из экрана создания мира) — не трогаем
	if WorldGenerator._is_initialized:
		return
	# Иначе инициализируем (запуск напрямую для тестирования)
	if world_seed == 0:
		WorldGenerator.initialize_random()
	else:
		WorldGenerator.initialize_world(world_seed)

func _setup_chunk_manager() -> void:
	_chunk_manager = ChunkManager.new()
	_chunk_manager.name = "ChunkManager"
	add_child(_chunk_manager)
	move_child(_chunk_manager, 0)

# --- Обновления ---

func _update_player_indoor_status() -> void:
	if not _player or not _building_system:
		return
	var o2: OxygenSystem = _player.get_oxygen_system()
	if not o2:
		return
	var grid_pos: Vector2i = _building_system.world_to_grid(_player.global_position)
	o2.set_indoor(_building_system.is_cell_indoor(grid_pos))

func _update_enemy_spawning(delta: float) -> void:
	if not enemy_balance or not _player or not _enemy_container:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = enemy_balance.spawn_interval
		if _enemy_count < enemy_balance.max_enemies:
			_spawn_enemy()

func _spawn_enemy() -> void:
	if not enemy_balance:
		return
	var angle: float = randf() * TAU
	var dist: float = randf_range(
		enemy_balance.spawn_distance_min,
		enemy_balance.spawn_distance_max
	)
	var spawn_pos: Vector2 = _player.global_position + Vector2.from_angle(angle) * dist
	if WorldGenerator and WorldGenerator._is_initialized:
		if not WorldGenerator.is_walkable_at(spawn_pos):
			return
	var enemy := CharacterBody2D.new()
	enemy.collision_layer = 4
	enemy.collision_mask = 1 | 2
	enemy.global_position = spawn_pos
	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.texture = preload("res://assets/sprites/fauna/enemy_cleaner_32.png")
	enemy.add_child(visual)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 24)
	collision.shape = shape
	enemy.add_child(collision)
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = enemy_balance.max_health
	enemy.add_child(health)
	var script: GDScript = load("res://core/entities/fauna/basic_enemy.gd")
	enemy.set_script(script)
	enemy.balance = enemy_balance
	enemy.add_to_group("enemies")
	_enemy_container.add_child(enemy)
	_enemy_count += 1
	EventBus.enemy_spawned.emit(enemy)

func _on_enemy_killed(death_position: Vector2) -> void:
	_enemy_count = maxi(_enemy_count - 1, 0)
	if enemy_balance:
		var drop: int = randi_range(enemy_balance.scrap_drop_min, enemy_balance.scrap_drop_max)
		for i: int in range(drop):
			var offset := Vector2(randf_range(-20, 20), randf_range(-20, 20))
			_spawn_scrap_pickup(death_position + offset)

func _spawn_initial_scrap() -> void:
	if not _player:
		return
	for i: int in range(10):
		var angle: float = randf() * TAU
		var dist: float = randf_range(50.0, 200.0)
		var pos: Vector2 = _player.global_position + Vector2.from_angle(angle) * dist
		_spawn_scrap_pickup(pos)

func _spawn_scrap_pickup(pos: Vector2) -> void:
	if not _pickup_container:
		return
	var pickup := Area2D.new()
	pickup.global_position = pos
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	pickup.monitoring = true
	pickup.monitorable = false
	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.texture = preload("res://assets/sprites/pickups/pickup_scrap_16.png")
	pickup.add_child(visual)
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	collision.shape = shape
	pickup.add_child(collision)
	pickup.body_entered.connect(_on_pickup_collected.bind(pickup))
	_pickup_container.add_child(pickup)

func _on_pickup_collected(body: Node2D, pickup: Area2D) -> void:
	if body is Player:
		body.collect_scrap(1)
		pickup.queue_free()

func _find_node_in_group(group_name: String) -> Node:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
	if nodes.is_empty():
		return null
	return nodes[0]
