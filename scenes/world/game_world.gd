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
var _game_stats: GameStats = null
var _death_screen: DeathScreen = null
var _z_manager: ZLevelManager = null
var _z_overlay: ZTransitionOverlay = null
var _bg_rect: ColorRect = null
var _stairs_container: Node2D = null
var _mountain_roof: MountainRoofSystem = null

func _ready() -> void:
	_player = _find_node_in_group("player") as Player
	_building_system = get_node_or_null("BuildingSystem")
	_enemy_container = get_node_or_null("EnemyContainer")
	_pickup_container = get_node_or_null("PickupContainer")
	_resolved_ui_layer = _resolve_ui_layer()
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.item_dropped.connect(_on_item_dropped)
	EventBus.game_over.connect(_on_game_over)
	_init_world_generator()
	_setup_chunk_manager()
	_setup_command_executor()
	_setup_life_support()
	_setup_z_levels()
	_spawn_initial_scrap()
	_spawn_test_stairs()
	
	# Создаём меню строительства в UILayer
	var build_menu := BuildMenuPanel.new()
	build_menu.name = "BuildMenu"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(build_menu)

	# Создаём CraftingSystem
	_crafting_system = CraftingSystem.new()
	_crafting_system.name = "CraftingSystem"
	add_child(_crafting_system)

	# EquipmentComponent для игрока
	if _player:
		var equipment := EquipmentComponent.new()
		equipment.name = "EquipmentComponent"
		_player.add_child(equipment)

	# Создаём UI инвентаря
	var inv_panel := InventoryPanel.new()
	inv_panel.name = "InventoryPanel"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(inv_panel)
	
	# UI энергосистемы
	var power_ui := PowerUI.new()
	power_ui.name = "PowerUI"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(power_ui)

	var pause_menu := PauseMenu.new()
	pause_menu.name = "PauseMenu"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(pause_menu)

	_game_stats = GameStats.new()
	_game_stats.name = "GameStats"
	add_child(_game_stats)

	_death_screen = DeathScreen.new()
	_death_screen.name = "DeathScreen"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(_death_screen)

	_mountain_roof = MountainRoofSystem.new()
	_mountain_roof.name = "MountainRoofSystem"
	add_child(_mountain_roof)

	call_deferred("_check_pending_load")

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

func _on_item_dropped(item_id: String, amount: int, world_pos: Vector2) -> void:
	if not _pickup_container:
		return
	# Рассчитать позицию: если Vector2.ZERO — рядом с игроком
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
	# Отключить коллизию на время чтобы не подобрать сразу
	var col: CollisionShape2D = pickup.get_child(1) as CollisionShape2D
	if col:
		col.set_deferred("disabled", true)
	pickup.body_entered.connect(_on_pickup_collected.bind(pickup))
	_pickup_container.add_child(pickup)
	if col:
		get_tree().create_timer(pickup_delay).timeout.connect(func() -> void:
			if is_instance_valid(col):
				col.disabled = false
		)

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

func _on_game_over() -> void:
	if _death_screen and _game_stats:
		_death_screen.show_death(_game_stats.get_summary())

func _check_pending_load() -> void:
	if SaveManager and not SaveManager.pending_load_slot.is_empty():
		var slot: String = SaveManager.pending_load_slot
		SaveManager.pending_load_slot = ""
		SaveManager.load_game(slot)

# --- Z-уровни ---

func _setup_z_levels() -> void:
	_z_manager = ZLevelManager.new()
	_z_manager.name = "ZLevelManager"
	add_child(_z_manager)
	_z_manager.z_level_changed.connect(_on_z_level_changed)
	_z_overlay = ZTransitionOverlay.new()
	_z_overlay.name = "ZTransitionOverlay"
	add_child(_z_overlay)
	_stairs_container = Node2D.new()
	_stairs_container.name = "StairsContainer"
	add_child(_stairs_container)
	_setup_background()

func _setup_background() -> void:
	_bg_rect = ColorRect.new()
	_bg_rect.name = "BackgroundRect"
	_bg_rect.z_index = -100
	_bg_rect.size = Vector2(10000, 10000)
	_bg_rect.position = Vector2(-5000, -5000)
	_bg_rect.color = Color(0.05, 0.10, 0.05)
	add_child(_bg_rect)
	move_child(_bg_rect, 0)

func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	if _chunk_manager and _chunk_manager.has_method("set_active_z_level"):
		_chunk_manager.set_active_z_level(new_z)
	_update_background_for_z(new_z)

func _update_background_for_z(z: int) -> void:
	if not _bg_rect:
		return
	match z:
		-1: _bg_rect.color = Color(0.10, 0.08, 0.06)
		0: _bg_rect.color = Color(0.05, 0.10, 0.05)
		1: _bg_rect.color = Color(0.02, 0.02, 0.04)

func _spawn_test_stairs() -> void:
	if not _player or not _stairs_container:
		return
	var stair_pos: Vector2 = _player.global_position + Vector2(36, 0)
	# Люк вниз на поверхности (z=0 → z=-1)
	var stairs_down := ZStairs.new()
	stairs_down.target_z = -1
	stairs_down.source_z = 0
	stairs_down.global_position = stair_pos
	stairs_down.name = "TestStairsDown"
	_stairs_container.add_child(stairs_down)
	# Парная лестница наверх в подвале (z=-1 → z=0)
	var stairs_up := ZStairs.new()
	stairs_up.target_z = 0
	stairs_up.source_z = -1
	stairs_up.stairs_type = &"stairs_up"
	stairs_up.global_position = stair_pos
	stairs_up.name = "TestStairsUp"
	_stairs_container.add_child(stairs_up)

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
