class_name PlayerIdleState
extends EntityState

func enter(_data: Dictionary = {}) -> void:
	var player: Player = owner as Player
	if player:
		player.stop_movement()

func physics_update(_delta: float) -> void:
	var player: Player = owner as Player
	if not player:
		return
	if player.is_dead():
		machine.transition_to(&"dead")
	elif player.has_move_input():
		machine.transition_to(&"move")

func handle_input(event: InputEvent) -> void:
	var player: Player = owner as Player
	if not player or player.is_dead():
		return
	if event.is_action_pressed("attack") and player.can_attack():
		machine.transition_to(&"attack")
	elif event.is_action_pressed("interact") and player.can_harvest():
		machine.transition_to(&"harvest")
