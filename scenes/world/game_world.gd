class_name GameWorld
extends Node2D

const WorldFeatureDebugOverlayScript = preload("res://core/systems/world/world_feature_debug_overlay.gd")
const WORLD_SEED_OVERRIDE_ARG_PREFIX: String = "codex_world_seed="
const BOOT_PROOF_QUIT_ARG: String = "codex_quit_on_boot_complete"

## Главная сцена мира. Инициализирует системы, запускает boot-последовательность,
## управляет runtime-связкой между системами (indoor status ↔ oxygen).
## Debug-оверлей и spawn-логика вынесены в GameWorldDebug и SpawnOrchestrator.

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
var _resolved_ui_layer: CanvasLayer = null
var _command_executor: CommandExecutor = null
var _crafting_system: CraftingSystem = null
var _life_support: BaseLifeSupport = null
var _game_stats: GameStats = null
var _death_screen: DeathScreen = null
var _z_manager: ZLevelManager = null
var _z_overlay: ZTransitionOverlay = null
var _bg_rect: ColorRect = null
var _mountain_roof_system: MountainRoofSystem = null
var _mountain_shadow_system: MountainShadowSystem = null
var _feature_debug_overlay: WorldFeatureDebugOverlay = null
var _loading_screen: LoadingScreen = null
var _boot_complete: bool = false
var _boot_first_playable_done: bool = false
var _boot_player_handoff_done: bool = false
var _boot_shadows_scheduled: bool = false
var _boot_shadows_built: bool = false
var _boot_shadows_scheduled_usec: int = 0
var _spawn_orchestrator: SpawnOrchestrator = null
var _pending_load_slot: String = ""

func _ready() -> void:
	var startup_usec: int = WorldPerfProbe.begin()
	if not WorldPerfProbe.has_milestone("Startup.start_pressed"):
		WorldPerfProbe.mark_milestone("Startup.start_pressed")
	_pause_time_for_boot()
	_player = PlayerAuthority.get_local_player()
	_start_boot_sequence()
	WorldPerfProbe.end("GameWorld._ready", startup_usec)
	call_deferred("_finish_scene_setup_after_loading_screen")

func _finish_scene_setup_after_loading_screen() -> void:
	await _await_loading_screen_presented()
	if not WorldPerfProbe.has_milestone("Startup.loading_screen_visible"):
		WorldPerfProbe.mark_milestone("Startup.loading_screen_visible")
	WorldPerfProbe.record_between(
		"Startup.start_to_loading_screen_visible_ms",
		"Startup.start_pressed",
		"Startup.loading_screen_visible"
	)
	var setup_usec: int = WorldPerfProbe.begin()
	_building_system = get_node_or_null("BuildingSystem")
	var enemy_container: Node2D = get_node_or_null("EnemyContainer")
	var pickup_container: Node2D = get_node_or_null("PickupContainer")
	_resolved_ui_layer = _resolve_ui_layer()
	_pending_load_slot = _consume_pending_load_slot()
	EventBus.game_over.connect(_on_game_over)
	await _init_world_generator()
	_setup_chunk_manager()
	_setup_mountain_roof_system()
	_setup_command_executor()
	_setup_life_support()
	_setup_z_levels()
	_setup_mountain_shadows()
	_setup_feature_debug_overlay()

	# Spawn orchestrator
	_spawn_orchestrator = SpawnOrchestrator.new()
	_spawn_orchestrator.name = "SpawnOrchestrator"
	add_child(_spawn_orchestrator)
	_spawn_orchestrator.setup(_player, enemy_container, pickup_container, _command_executor, enemy_balance)
	_bootstrap_session_state()
	_canonicalize_player_world_position()

	# Debug overlay
	var debug := GameWorldDebug.new()
	debug.name = "GameWorldDebug"
	add_child(debug)
	debug.setup(_chunk_manager, _resolved_ui_layer, self)

	# UI composition
	var build_menu := BuildMenuPanel.new()
	build_menu.name = "BuildMenu"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(build_menu)

	_crafting_system = CraftingSystem.new()
	_crafting_system.name = "CraftingSystem"
	add_child(_crafting_system)

	if _player:
		var equipment := EquipmentComponent.new()
		equipment.name = "EquipmentComponent"
		_player.add_child(equipment)

	var inv_panel := InventoryPanel.new()
	inv_panel.name = "InventoryPanel"
	if _resolved_ui_layer:
		_resolved_ui_layer.add_child(inv_panel)

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
	WorldPerfProbe.end("GameWorld._setup_after_loading_screen", setup_usec)
	await _run_boot_sequence()

func _physics_process(_delta: float) -> void:
	if not _boot_first_playable_done:
		return
	_canonicalize_player_world_position()
	if not _boot_complete:
		_tick_boot_finalization()

func is_boot_complete() -> bool:
	return _boot_complete

# --- Инициализация ---

func _init_world_generator() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if not WorldGenerator:
		push_error(Localization.t("SYSTEM_WORLD_GENERATOR_MISSING"))
		return
	if _player:
		WorldGenerator.spawn_tile = WorldGenerator.world_to_tile(_player.global_position)
	if WorldGenerator._is_initialized:
		WorldPerfProbe.end("_init_world_generator", started_usec)
		return
	world_seed = _resolve_requested_world_seed()
	if world_seed == 0 and WorldGenerator.has_method("is_initialize_world_pending") and WorldGenerator.is_initialize_world_pending():
		world_seed = WorldGenerator.world_seed
	var requested_seed: int = world_seed
	if requested_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		requested_seed = rng.randi()
		world_seed = requested_seed
	var begin_ok: bool = false
	if WorldGenerator.has_method("begin_initialize_world_async") and WorldGenerator.has_method("complete_pending_initialize_world"):
		if not WorldGenerator.is_initialize_world_pending():
			begin_ok = WorldGenerator.begin_initialize_world_async(requested_seed)
		else:
			begin_ok = true
		while WorldGenerator.is_initialize_world_pending() and not WorldGenerator.complete_pending_initialize_world():
			await get_tree().process_frame
	if not WorldGenerator._is_initialized:
		if requested_seed == 0:
			WorldGenerator.initialize_random()
		else:
			WorldGenerator.initialize_world(requested_seed)
	elif not begin_ok:
		push_warning("[GameWorld] async world initialization unavailable; used sync fallback")
	WorldPerfProbe.end("_init_world_generator", started_usec)

func _resolve_requested_world_seed() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(WORLD_SEED_OVERRIDE_ARG_PREFIX):
			continue
		var raw_value: String = arg.trim_prefix(WORLD_SEED_OVERRIDE_ARG_PREFIX)
		if raw_value.is_empty():
			continue
		return raw_value.to_int()
	return world_seed

func _should_quit_on_boot_complete() -> bool:
	return BOOT_PROOF_QUIT_ARG in OS.get_cmdline_user_args()

func _setup_chunk_manager() -> void:
	_chunk_manager = ChunkManager.new()
	_chunk_manager.name = "ChunkManager"
	add_child(_chunk_manager)
	move_child(_chunk_manager, 0)

func _setup_command_executor() -> void:
	_command_executor = CommandExecutor.new()
	_command_executor.name = "CommandExecutor"
	add_child(_command_executor)

func _setup_mountain_roof_system() -> void:
	_mountain_roof_system = MountainRoofSystem.new()
	_mountain_roof_system.name = "MountainRoofSystem"
	add_child(_mountain_roof_system)

func _setup_life_support() -> void:
	_life_support = BaseLifeSupport.new()
	_life_support.name = "BaseLifeSupport"
	add_child(_life_support)

func _setup_mountain_shadows() -> void:
	_mountain_shadow_system = MountainShadowSystem.new()
	_mountain_shadow_system.name = "MountainShadowSystem"
	add_child(_mountain_shadow_system)

func _setup_feature_debug_overlay() -> void:
	if not WorldGenerator:
		return
	_feature_debug_overlay = WorldFeatureDebugOverlayScript.new()
	_feature_debug_overlay.name = "WorldFeatureDebugOverlay"
	add_child(_feature_debug_overlay)
	_feature_debug_overlay.setup(
		Callable(WorldGenerator, "_get_cached_feature_and_poi_payload"),
		Callable(WorldGenerator, "tile_to_world")
	)

# --- Game Over ---

func _on_game_over() -> void:
	if _death_screen and _game_stats:
		_death_screen.show_death(_game_stats.get_summary())

# --- Boot ---

func _start_boot_sequence() -> void:
	_loading_screen = LoadingScreen.new()
	_loading_screen.name = "LoadingScreen"
	add_child(_loading_screen)
	if _player:
		_player.set_physics_process(false)
		_player.set_process_input(false)

func _await_loading_screen_presented() -> void:
	if not _loading_screen:
		return
	if _loading_screen.is_presented():
		return
	await _loading_screen.screen_presented

func _run_boot_sequence() -> void:
	if not _loading_screen:
		_finish_boot_sequence()
		return
	_loading_screen.set_progress(5.0, Localization.t("UI_LOADING_INITIALIZING_WORLD"))
	await get_tree().process_frame
	if _chunk_manager:
		await _chunk_manager.boot_load_initial_chunks(
			func(pct: float, text: String) -> void:
				if _loading_screen:
					_loading_screen.set_progress(pct, text)
		)
	## first_playable reached — near chunk visuals are converged enough to start boot finalization.
	## Player handoff still waits for the fully-ready boot milestone so the loading screen
	## does not drop while shadows or startup visuals are still building on screen.
	if _chunk_manager and _chunk_manager.is_boot_first_playable():
		_on_boot_first_playable()
	else:
		_finish_boot_sequence()

# --- Z-уровни ---

func _setup_z_levels() -> void:
	_z_manager = ZLevelManager.new()
	_z_manager.name = "ZLevelManager"
	add_child(_z_manager)
	_z_manager.z_level_changed.connect(_on_z_level_changed)
	_z_overlay = ZTransitionOverlay.new()
	_z_overlay.name = "ZTransitionOverlay"
	add_child(_z_overlay)
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
	var daylight_system: Node = get_node_or_null("DaylightSystem")
	if daylight_system and daylight_system.has_method("set_active_z_level"):
		daylight_system.set_active_z_level(new_z)
	if _mountain_shadow_system and _mountain_shadow_system.has_method("set_active_z_level"):
		_mountain_shadow_system.set_active_z_level(new_z)
	_update_background_for_z(new_z)

func _update_background_for_z(z: int) -> void:
	if not _bg_rect:
		return
	match z:
		-1: _bg_rect.color = Color(0.10, 0.08, 0.06)
		0: _bg_rect.color = Color(0.05, 0.10, 0.05)
		1: _bg_rect.color = Color(0.02, 0.02, 0.04)

func request_z_transition(new_z: int) -> bool:
	if not _z_manager:
		return false
	if _z_overlay:
		_z_overlay.do_transition(func() -> void: _z_manager.change_level(new_z))
	else:
		_z_manager.change_level(new_z)
	return true

# --- Утилиты ---

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

func _consume_pending_load_slot() -> String:
	if not SaveManager:
		return ""
	return SaveManager.consume_pending_load_slot()

func _bootstrap_session_state() -> void:
	if _pending_load_slot.is_empty():
		if TimeManager and TimeManager.has_method("reset_for_new_game"):
			TimeManager.reset_for_new_game()
		_pause_time_for_boot()
		if _spawn_orchestrator:
			_spawn_orchestrator.spawn_initial_scrap()
		return
	if SaveManager and not SaveManager.load_game(_pending_load_slot):
		_pending_load_slot = ""
		if TimeManager and TimeManager.has_method("reset_for_new_game"):
			TimeManager.reset_for_new_game()
		_pause_time_for_boot()
		if _spawn_orchestrator:
			_spawn_orchestrator.spawn_initial_scrap()
		return
	_pause_time_for_boot()

func _pause_time_for_boot() -> void:
	if TimeManager and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)

func _on_boot_first_playable() -> void:
	if _boot_first_playable_done:
		return
	WorldPerfProbe.mark_milestone("Startup.startup_bubble_ready")
	WorldPerfProbe.record_between(
		"Startup.loading_screen_visible_to_startup_bubble_ready_ms",
		"Startup.loading_screen_visible",
		"Startup.startup_bubble_ready"
	)
	_canonicalize_player_world_position()
	_boot_first_playable_done = true

func _handoff_boot_to_player() -> void:
	if _boot_player_handoff_done:
		return
	_canonicalize_player_world_position()
	if _player:
		_player.set_physics_process(true)
		_player.set_process_input(true)
	if TimeManager and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(false)
	_boot_player_handoff_done = true
	if _loading_screen:
		_loading_screen.fade_out()

func _tick_boot_finalization() -> void:
	if _mountain_shadow_system:
		if not _boot_shadows_scheduled and _mountain_shadow_system.has_method("schedule_boot_shadows"):
			## Lightweight: seeds sun angle, shows container, ensures dirty queues.
			## Actual shadow build happens incrementally via FrameBudgetDispatcher (1ms budget).
			_boot_shadows_scheduled = true
			_boot_shadows_scheduled_usec = Time.get_ticks_usec()
			_mountain_shadow_system.schedule_boot_shadows()
		if not _boot_shadows_built and _mountain_shadow_system.has_method("is_boot_shadow_work_drained") and _mountain_shadow_system.is_boot_shadow_work_drained():
			_boot_shadows_built = true
			if _boot_shadows_scheduled_usec > 0:
				var shadow_stale_age_ms: float = float(Time.get_ticks_usec() - _boot_shadows_scheduled_usec) / 1000.0
				WorldPerfProbe.record("Shadow.stale_age_ms", shadow_stale_age_ms)
	if _chunk_manager and _chunk_manager.is_boot_complete() and _boot_shadows_built:
		if not _boot_complete:
			_boot_complete = true
			WorldPerfProbe.mark_milestone("Startup.boot_complete")
			WorldPerfProbe.record_between(
				"Startup.startup_bubble_ready_to_boot_complete_ms",
				"Startup.startup_bubble_ready",
				"Startup.boot_complete"
			)
			_handoff_boot_to_player()
			if _should_quit_on_boot_complete():
				print("[CodexValidation] boot proof complete; quitting")
				get_tree().quit()

func _finish_boot_sequence() -> void:
	_on_boot_first_playable()
	_handoff_boot_to_player()

func _canonicalize_player_world_position() -> void:
	if not _player or not WorldGenerator or not WorldGenerator._is_initialized:
		return
	var canonical_pos: Vector2 = WorldGenerator.canonicalize_world_position(_player.global_position)
	if canonical_pos.is_equal_approx(_player.global_position):
		return
	_player.global_position = canonical_pos
	_player.reset_camera_smoothing()
	if _chunk_manager:
		_chunk_manager.sync_display_to_player()
	if _spawn_orchestrator:
		_spawn_orchestrator.sync_pickups_to_player()
