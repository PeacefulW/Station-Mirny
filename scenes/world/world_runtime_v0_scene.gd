class_name WorldRuntimeV0Scene
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const PerformanceFlightRecorderScript = preload(
	"res://core/runtime/performance_flight_recorder.gd"
)
const LoadingScreenScript = preload("res://scenes/ui/loading_screen.gd")

var _booted_chunk_coords: Dictionary = { }
var _world_initialized: bool = false
var _performance_recorder: PerformanceFlightRecorder = null
var _loading_screen: LoadingScreen = null
var _loading_transition_to_world: bool = false
var _player_paused_for_loading: bool = false
var _player_process_mode_before_loading: int = Node.PROCESS_MODE_INHERIT

@onready var _world_streamer: WorldStreamer = $WorldStreamer as WorldStreamer
@onready var _player: Player = $Player as Player
@onready var _height_shadow_field: WorldHeightShadowField = (
	$WorldHeightShadowField as WorldHeightShadowField
)
@onready var _postprocess_overlay: Node = $PostProcessLayer/PostProcessOverlay
@onready var _hud_manager: HudManager = $HudLayer/HudManager as HudManager


func _ready() -> void:
	_show_initial_loading_screen()
	_world_streamer.bind_height_shadow_field(_height_shadow_field)
	_performance_recorder = PerformanceFlightRecorderScript.new() as PerformanceFlightRecorder
	add_child(_performance_recorder)
	_performance_recorder.setup(_world_streamer, _postprocess_overlay)
	if _hud_manager != null:
		_hud_manager.set_performance_source(_world_streamer)
		_hud_manager.set_performance_recorder(_performance_recorder)
	if TimeManager and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(false)
	if EventBus and not EventBus.world_initialized.is_connected(_on_world_initialized):
		EventBus.world_initialized.connect(_on_world_initialized)
	if EventBus and not EventBus.chunk_loaded.is_connected(_on_chunk_loaded):
		EventBus.chunk_loaded.connect(_on_chunk_loaded)
	if EventBus and not EventBus.chunk_unloaded.is_connected(_on_chunk_unloaded):
		EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	call_deferred("_bootstrap_scene")


func _process(_delta: float) -> void:
	var loading_state: Dictionary = _world_streamer.get_initial_loading_state()
	if bool(loading_state.get("active", false)) \
			and _loading_screen == null \
			and not _loading_transition_to_world:
		_show_initial_loading_screen()
	if _loading_screen == null:
		return
	_loading_screen.set_loading_state(loading_state)
	if bool(loading_state.get("ready", false)) \
			and _loading_screen.is_presented() \
			and not _loading_screen.is_fading():
		_loading_screen.fade_out()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var loading_state: Dictionary = _world_streamer.get_initial_loading_state()
	if bool(loading_state.get("active", false)) \
			and key_event.keycode not in [KEY_F2, KEY_F3, KEY_F4]:
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_F2:
		if _performance_recorder != null:
			_performance_recorder.capture_manual_snapshot()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F3:
		if _hud_manager != null:
			_hud_manager.cycle_performance_mode()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F4:
		if _performance_recorder != null:
			_performance_recorder.toggle_recording()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F5:
		var save_slot: String = (
			SaveManager.current_slot
			if not SaveManager.current_slot.is_empty()
			else WorldRuntimeConstants.DEFAULT_SAVE_SLOT
		)
		SaveManager.save_game(save_slot)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F6:
		_world_streamer.toggle_debug_tile_grid()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F7:
		_world_streamer.toggle_debug_mountain_solid_mask()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_G:
		# DEBUG: print terrain/tile data under the player (F8 is Godot's Stop key).
		var dbg_player: Node2D = PlayerAuthority.get_local_player() as Node2D
		if dbg_player != null:
			print(_world_streamer.describe_tile_under_debug(dbg_player.global_position))
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F9:
		var load_slot: String = (
			SaveManager.current_slot
			if not SaveManager.current_slot.is_empty()
			else WorldRuntimeConstants.DEFAULT_SAVE_SLOT
		)
		if SaveManager.save_exists(load_slot):
			SaveManager.load_game(load_slot)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F10:
		_world_streamer.toggle_debug_mountain_contour()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F11:
		var debug_collisions_visible: bool = _world_streamer.toggle_debug_object_collisions()
		_set_player_debug_collision_visible(debug_collisions_visible)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F12:
		_toggle_postprocess()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_ESCAPE:
		PlayerAuthority.clear_cache()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		get_viewport().set_input_as_handled()


func _bootstrap_scene() -> void:
	PlayerAuthority.clear_cache()
	if _world_initialized:
		return
	var pending_slot: String = SaveManager.consume_pending_load_slot() if SaveManager else ""
	if pending_slot.is_empty():
		_world_streamer.reset_for_new_game()
		if TimeManager and TimeManager.has_method("reset_for_new_game"):
			TimeManager.reset_for_new_game()
		return
	SaveManager.load_game(pending_slot)


func get_initial_loading_state() -> Dictionary:
	return _world_streamer.get_initial_loading_state()


func _show_initial_loading_screen() -> void:
	if _loading_screen != null and is_instance_valid(_loading_screen):
		return
	_pause_player_for_initial_loading()
	_loading_screen = LoadingScreenScript.new() as LoadingScreen
	_loading_screen.name = "InitialLoadingScreen"
	_loading_screen.loading_completed.connect(_on_initial_loading_screen_completed)
	add_child(_loading_screen)


func _pause_player_for_initial_loading() -> void:
	if _player == null or _player_paused_for_loading:
		return
	_player_process_mode_before_loading = _player.process_mode
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player_paused_for_loading = true


func _restore_player_after_initial_loading() -> void:
	if _player == null or not _player_paused_for_loading:
		return
	_player.process_mode = _player_process_mode_before_loading as Node.ProcessMode
	_player_paused_for_loading = false


func _on_initial_loading_screen_completed() -> void:
	_loading_screen = null
	_loading_transition_to_world = true
	_finish_initial_world_presentation()


func _finish_initial_world_presentation() -> void:
	await get_tree().process_frame
	if not _world_streamer.acknowledge_initial_world_presented():
		_loading_transition_to_world = false
		return
	_restore_player_after_initial_loading()
	_loading_transition_to_world = false


func _set_player_debug_collision_visible(enabled: bool) -> void:
	var player: Player = PlayerAuthority.get_local_player()
	if player == null:
		return
	player.set_debug_collision_visible(enabled)


func _toggle_postprocess() -> void:
	if _postprocess_overlay == null or not _postprocess_overlay.has_method("toggle_postprocess"):
		return
	_postprocess_overlay.call("toggle_postprocess")


func _on_world_initialized(_seed_value: int) -> void:
	_world_initialized = true
	_booted_chunk_coords.clear()


func _on_chunk_loaded(chunk_coord: Vector2i) -> void:
	if not _world_initialized:
		return
	_booted_chunk_coords[chunk_coord] = true


func _on_chunk_unloaded(chunk_coord: Vector2i) -> void:
	_booted_chunk_coords.erase(chunk_coord)
