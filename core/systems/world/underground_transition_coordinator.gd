class_name UndergroundTransitionCoordinator
extends Node

## Координирует controlled z-transition:
## fade-out -> hidden z switch -> wait for target hot envelope full_ready -> fade-in.

var _chunk_manager: ChunkManager = null
var _z_manager: ZLevelManager = null
var _overlay: ZTransitionOverlay = null
var _player: Node2D = null
var _is_transitioning: bool = false
var _restore_player_physics_process: bool = false
var _restore_player_input_process: bool = false
var _player_locked: bool = false

func setup(
	chunk_manager: ChunkManager,
	z_manager: ZLevelManager,
	overlay: ZTransitionOverlay,
	player: Node2D
) -> void:
	_chunk_manager = chunk_manager
	_z_manager = z_manager
	_overlay = overlay
	_player = player

func request_transition(new_z: int) -> bool:
	if _is_transitioning:
		return false
	if _chunk_manager == null or _z_manager == null:
		return false
	if new_z < ZLevelManager.Z_MIN or new_z > ZLevelManager.Z_MAX:
		return false
	if new_z == _z_manager.get_current_z():
		return false
	_is_transitioning = true
	call_deferred("_run_transition", new_z)
	return true

func is_transitioning() -> bool:
	return _is_transitioning

func _run_transition(new_z: int) -> void:
	_lock_player()
	if _overlay != null:
		_overlay.fade_to_black()
		await _overlay.fade_to_black_finished
	if _chunk_manager != null:
		_chunk_manager.set_transition_hidden(true)
	if _z_manager != null:
		_z_manager.change_level(new_z)
	while is_inside_tree():
		if _chunk_manager == null:
			break
		if _chunk_manager != null and _chunk_manager.is_active_player_hot_envelope_full_ready():
			break
		await get_tree().process_frame
	if _chunk_manager != null:
		_chunk_manager.set_transition_hidden(false)
	if _overlay != null:
		_overlay.fade_from_black()
		await _overlay.fade_from_black_finished
	_unlock_player()
	_is_transitioning = false

func _lock_player() -> void:
	if _player == null or _player_locked:
		return
	_restore_player_physics_process = _player.is_physics_processing()
	_restore_player_input_process = _player.is_processing_input()
	_player.set_physics_process(false)
	_player.set_process_input(false)
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO
	else:
		var velocity_value: Variant = _player.get("velocity")
		if typeof(velocity_value) == TYPE_VECTOR2:
			_player.set("velocity", Vector2.ZERO)
	_player_locked = true

func _unlock_player() -> void:
	if _player == null or not _player_locked:
		return
	_player.set_physics_process(_restore_player_physics_process)
	_player.set_process_input(_restore_player_input_process)
	_player_locked = false
