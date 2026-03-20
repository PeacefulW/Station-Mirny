class_name GameWorld
extends Node2D

## Главная сцена мира. Инициализирует WorldGenerator (если не было),
## управляет ChunkManager, спавном врагов и пикапов.

# --- Экспортируемые ---
@export var enemy_balance: EnemyBalance = null
## Seed мира. Используется только если мир не инициализирован
## (при запуске напрямую, минуя экран создания). 0 = случайный.
@export var world_seed: int = 0
@export var ui_layer: CanvasLayer = null

# --- Приватные ---
var _player: Player = null
var _building_system: BuildingSystem = null
var _chunk_manager: ChunkManager = null
var _enemy_container: Node2D = null
var _pickup_container: Node2D = null
var _crafting_system: CraftingSystem = null
var _spawn_timer: float = 0.0
var _enemy_count: int = 0
var _resolved_ui_layer: CanvasLayer = null
var _command_executor: CommandExecutor = null
var _enemy_factory: EnemyFactory = EnemyFactory.new()
var _pickup_factory: PickupFactory = PickupFactory.new()
var _life_support: BaseLifeSupport = null

func _ready() -> void:
	_player = _find_node_in_group("player") as Player
	_building_system = get_node_or_null("BuildingSystem")
	_enemy_container = get_node_or_null("EnemyContainer")
	_pickup_container = get_node_or_null("PickupContainer")
	_resolved_ui_layer = _resolve_ui_layer()
	EventBus.enemy_killed.connect(_on_enemy_killed)
	_init_world_generator()
	_setup_chunk_manager()
	_setup_command_executor()
	_setup_life_support()
	_spawn_initial_scrap()
	
	# Создаём меню строительства в UILayer
	var build_menu := BuildMenu.new()
	build_menu.name = "BuildMenu"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(build_menu)

	# Создаём CraftingSystem
	_crafting_system = CraftingSystem.new()
	_crafting_system.name = "CraftingSystem"
	add_child(_crafting_system)

	# Создаём UI инвентаря
	var inv_ui := InventoryUI.new()
	inv_ui.name = "InventoryUI"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(inv_ui)
	
	# UI энергосистемы
	var power_ui := PowerUI.new()
	power_ui.name = "PowerUI"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(power_ui)

	var pause_menu := PauseMenu.new()
	pause_menu.name = "PauseMenu"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(pause_menu)

func _process(delta: float) -> void:
	_update_player_indoor_status()
	_update_enemy_spawning(delta)

# --- Инициализация ---

func _init_world_generator() -> void:
	if not WorldGenerator:
		push_error(Localization.t("SYSTEM_WORLD_GENERATOR_MISSING"))
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

func _setup_command_executor() -> void:
	_command_executor = CommandExecutor.new()
	_command_executor.name = "CommandExecutor"
	add_child(_command_executor)

func _setup_life_support() -> void:
	_life_support = BaseLifeSupport.new()
	_life_support.name = "BaseLifeSupport"
	add_child(_life_support)

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
	var enemy := _enemy_factory.create_basic_enemy(spawn_pos, enemy_balance)
	if not enemy:
		return
	_enemy_container.add_child(enemy)
	_enemy_count += 1
	EventBus.enemy_spawned.emit(enemy)

func _on_enemy_killed(death_position: Vector2) -> void:
	_enemy_count = maxi(_enemy_count - 1, 0)
	if enemy_balance:
		var drop: int = randi_range(enemy_balance.scrap_drop_min, enemy_balance.scrap_drop_max)
		for i: int in range(drop):
			var offset := Vector2(randf_range(-8, 8), randf_range(-8, 8))
			_spawn_scrap_pickup(death_position + offset)

func _spawn_initial_scrap() -> void:
	if not _player:
		return
	for i: int in range(10):
		var angle: float = randf() * TAU
		var dist: float = randf_range(19.0, 75.0)
		var pos: Vector2 = _player.global_position + Vector2.from_angle(angle) * dist
		_spawn_scrap_pickup(pos)

func _spawn_scrap_pickup(pos: Vector2) -> void:
	if not _pickup_container:
		return
	var pickup := _pickup_factory.create_item_pickup(Player.SCRAP_ITEM_ID, 1, pos)
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

func _find_node_in_group(group_name: String) -> Node:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
	if nodes.is_empty():
		return null
	return nodes[0]

func _resolve_ui_layer() -> CanvasLayer:
	if ui_layer:
		return ui_layer
	var fallback: CanvasLayer = get_node_or_null("UILayer") as CanvasLayer
	if not fallback:
		push_error(Localization.t("SYSTEM_UI_LAYER_MISSING"))
	return fallback
