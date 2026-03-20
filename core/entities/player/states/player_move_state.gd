class_name PlayerMoveState
extends EntityState

func physics_update(_delta: float) -> void:
	var player: Player = owner as Player
	if not player:
		return
	if player.is_dead():
		machine.transition_to(&"dead")
		return
	player.update_movement_velocity()
	if not player.has_move_input():
		machine.transition_to(&"idle")

func handle_input(event: InputEvent) -> void:
	var player: Player = owner as Player
	if not player or player.is_dead():
		return
	if event.is_action_pressed("attack") and player.can_attack():
		machine.transition_to(&"attack")
	elif event.is_action_pressed("interact") and player.can_harvest():
		machine.transition_to(&"harvest")
