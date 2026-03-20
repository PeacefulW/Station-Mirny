class_name PlayerDeadState
extends EntityState

func enter(_data: Dictionary = {}) -> void:
	var player: Player = owner as Player
	if player:
		player.handle_death()

func physics_update(_delta: float) -> void:
	var player: Player = owner as Player
	if player:
		player.stop_movement()
