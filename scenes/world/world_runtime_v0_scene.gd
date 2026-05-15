class_name WorldRuntimeV0Scene
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _booted_chunk_coords: Dictionary = {}
var _world_initialized: bool = false

@onready var _world_streamer: WorldStreamer = $WorldStreamer as WorldStreamer

func _ready() -> void:
	if TimeManager and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(false)
	if EventBus and not EventBus.world_initialized.is_connected(_on_world_initialized):
		EventBus.world_initialized.connect(_on_world_initialized)
	if EventBus and not EventBus.chunk_loaded.is_connected(_on_chunk_loaded):
		EventBus.chunk_loaded.connect(_on_chunk_loaded)
	if EventBus and not EventBus.chunk_unloaded.is_connected(_on_chunk_unloaded):
		EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	call_deferred("_bootstrap_scene")

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F5:
		var save_slot: String = SaveManager.current_slot if not SaveManager.current_slot.is_empty() else WorldRuntimeConstants.DEFAULT_SAVE_SLOT
		SaveManager.save_game(save_slot)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F6:
		_world_streamer.toggle_debug_tile_grid()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F7:
		_world_streamer.toggle_debug_mountain_solid_mask()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F9:
		var load_slot: String = SaveManager.current_slot if not SaveManager.current_slot.is_empty() else WorldRuntimeConstants.DEFAULT_SAVE_SLOT
		if SaveManager.save_exists(load_slot):
			SaveManager.load_game(load_slot)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F10:
		_world_streamer.toggle_debug_mountain_contour()
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

func _on_world_initialized(_seed_value: int) -> void:
	_world_initialized = true
	_booted_chunk_coords.clear()

func _on_chunk_loaded(chunk_coord: Vector2i) -> void:
	if not _world_initialized:
		return
	_booted_chunk_coords[chunk_coord] = true

func _on_chunk_unloaded(chunk_coord: Vector2i) -> void:
	_booted_chunk_coords.erase(chunk_coord)
